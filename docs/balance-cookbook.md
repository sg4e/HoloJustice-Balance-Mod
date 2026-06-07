# Balance change cookbook

These examples illustrate repository conventions. Template names and field shapes are version-sensitive; confirm them against the installed game's scripts and a nearby working HoloJustice change before committing.

## General workflow for any balance change

1. Identify the game object and exact template name.
2. Search this repository for the name and for similar changes.
3. Decide whether the desired scope is global/shared or isolated.
4. Choose data mutation before hooks whenever possible.
5. If adding a synchronized template, register it deterministically.
6. Update descriptions/localization.
7. Test startup, keep, mission, host/client, and the intended combat case.

Useful searches:

```bash
rg -n 'one_handed_swords_template_1' scripts/mods/TourneyBalance
rg -n 'DamageProfileTemplates\.' scripts/mods/TourneyBalance/changes/weapon_changes.lua
rg -n 'mod:modify_talent\(' scripts/mods/TourneyBalance/changes
rg -n 'mod:hook(_origin|_safe)?\(' scripts/mods/TourneyBalance
```

## Change an existing weapon-level property

For a narrow scalar already on a weapon template, mutate it directly in `weapon_changes.lua` near that weapon's section:

```lua
-- Example only: give a weapon one additional effective dodge.
Weapons.example_weapon_template.dodge_count = 4
```

Good candidates include dodge count/distance and existing ammo fields. Verify whether the field lives on the weapon template, an ammo template, or an action.

## Change attack timing, reach, chaining, or hit mass

Actions live under `Weapons.<weapon>.actions.<action>.<sub_action>`:

```lua
local heavy = Weapons.example_weapon_template.actions.action_one.heavy_attack
heavy.anim_time_scale = 1.1
heavy.range_mod = 1.2
heavy.hit_mass_count = LINESMAN_HIT_MASS_COUNT
```

Potential consequences:

- `anim_time_scale` changes animation speed, while `total_time` and chain windows govern input/transition timing; changing only one can feel or look wrong.
- `range_mod` affects reach but does not change the visible weapon.
- `hit_mass_count` changes which hit-mass behavior is used, not raw damage.
- Bad `allowed_chain_actions` can create dead inputs, animation skips, or unintended attack loops.

When changing a chain, copy the shape of a working neighboring action and ensure every referenced action exists.

## Change a shared damage profile

Use this only when every action referencing the profile should change:

```lua
local profile = DamageProfileTemplates.example_shared_profile
profile.default_target.power_distribution.attack = 0.30
profile.default_target.power_distribution.impact = 0.20
profile.cleave_distribution.attack = 0.25
profile.cleave_distribution.impact = 0.40
```

Before doing so, search for the profile name. If unrelated weapons use it, create a dedicated profile instead.

## Give one attack a dedicated cloned damage profile

This is the safer pattern for an isolated weapon buff:

```lua
local profile_name = "hj_example_weapon_heavy"
local profile = table.clone(DamageProfileTemplates.existing_heavy_profile)

profile.default_target.power_distribution.attack = 0.35
profile.targets[1].power_distribution.attack = 0.50
profile.cleave_distribution.attack = 0.30

NewDamageProfileTemplates[profile_name] = profile
Weapons.example_weapon_template.actions.action_one.heavy_attack.damage_profile = profile_name
```

Why `NewDamageProfileTemplates`?

- The main script registers its name in `NetworkLookup.damage_profiles`.
- The main script merges it into `DamageProfileTemplates` after all change modules load.
- The normalizer validates/resolves profile fields and creates a `_no_damage` counterpart.

Add new profiles before finalization—normally inside `weapon_changes.lua` or another module already loaded by the main script.

## Change armor interaction or headshot scaling

```lua
local first_target = DamageProfileTemplates.example_profile.targets[1]
first_target.armor_modifier.attack = { 1, 0.5, 2, 1, 0.75, 0.25 }
first_target.boost_curve_type = "ninja_curve"
first_target.boost_curve_coefficient_headshot = 1.5
```

Armor arrays are positional and easy to misunderstand. Copy a known-good profile for the same attack family, then test against infantry, armored, super-armored, berserker, monster, and relevant special targets. Also test crits and headshots.

## Modify an existing talent buff and description

```lua
mod:modify_talent_buff_template("empire_soldier", "example_existing_buff", {
    multiplier = 0.15,
    duration = 10,
})

mod:add_text("example_existing_talent_desc", "Grants 15%% power for 10 seconds.")
```

Then verify the talent's existing description ID. `mod:add_text` only changes the ID you provide; it does not automatically discover which talent uses it.

If the talent definition itself must change:

```lua
mod:modify_talent("career_internal_name", 4, 2, {
    description = "example_existing_talent_desc",
    buffs = { "example_existing_buff" },
})
```

Tier/index are internal talent-tree coordinates, not necessarily what a UI guide calls the talent.

## Add a new passive talent buff

```lua
mod:add_talent_buff_template("empire_soldier", "hj_example_power_buff", {
    stat_buff = "power_level",
    multiplier = 0.10,
})

mod:modify_talent("career_internal_name", 4, 2, {
    description = "hj_example_power_desc",
    buffs = { "hj_example_power_buff" },
})

mod:add_text("hj_example_power_desc", "Increases power by 10%%.")
```

The helper adds the buff to both `TalentBuffTemplates[hero]` and `BuffTemplates` and registers its network lookup. Use globally unique names.

## Add event-driven talent behavior

First register a proc function, then reference it by name from a buff:

```lua
mod:add_proc_function("hj_example_on_kill", function(owner_unit, buff, params)
    if not Managers.player.is_server then
        return
    end

    -- Validate params and perform one authoritative effect here.
end)

mod:add_talent_buff_template("empire_soldier", "hj_example_on_kill_buff", {
    event = "on_kill",
    buff_func = "hj_example_on_kill",
})
```

Use an existing proc with the same event to learn the shape of `params`. Events do not all provide the same fields. Keep authoritative effects server-only and avoid expensive work on frequent events such as damage dealt.

## Add a custom buff function

```lua
mod:add_buff_function("hj_example_apply", function(unit, buff, params)
    -- Called only when a template references this exact name.
end)

mod:add_buff_template("hj_example_active_buff", {
    apply_buff_func = "hj_example_apply",
    duration = 5,
})
```

Depending on the desired lifecycle, use `apply_buff_func`, `remove_buff_func`, `update_func`, or another supported callback field. Copy a base-game/repository template with the same lifecycle rather than guessing callback arguments.

## Add a synchronized buff to a player

The active talent module exposes `mod:add_buff(owner_unit, buff_name)`, which handles the host/client request path:

```lua
mod:add_buff(owner_unit, "hj_example_active_buff")
```

Requirements:

- the buff must already be registered in `NetworkLookup.buff_templates` on every peer;
- the unit must have a network game-object ID;
- the effect should be designed for synchronized addition;
- peers must run matching mod versions.

For richer parameters or removal behavior, use the buff system patterns in existing functions.

## Change a career passive or aura

Many career values are implemented as talent-style buffs even when they are not selectable talents:

```lua
mod:modify_talent_buff_template("empire_soldier", "example_passive", {
    range = 20,
})

mod:modify_talent_buff_template("empire_soldier", "example_passive_aura", {
    multiplier = -0.10,
})
```

Update the passive description with `mod:add_text`. Test self and ally behavior, distance boundaries, host/client, death/respawn, and joining in progress.

## Change an activated career ability

First look for a data field in the relevant ability settings or buff template. If behavior requires a hook, wrap the smallest stable method:

```lua
mod:hook(SomeCareerAbilityClass, "_run_ability", function(func, self, ...)
    -- Optional precondition/change.
    local result = func(self, ...)
    -- Optional post-effect.
    return result
end)
```

Only use `mod:hook_origin` when the original must be fully replaced. When doing so:

- copy all essential original behavior;
- preserve arguments and return values;
- preserve network/authority rules;
- document why wrapping was insufficient;
- re-diff against base-game source after updates.

## Change temporary-health or stagger behavior

For a simple THP talent value, modify its buff/template near the appropriate section of `thp_stagger_changes.lua`. For global stagger damage math, understand the entire custom calculation before editing.

Checklist for stagger/THP changes:

- every stagger state and target armor type;
- headshots, crits, backstabs, power boosts, and friendly fire;
- ranged versus melee;
- elites, specials, monsters, and hordes;
- all THP talent variants;
- host/client health agreement.

Avoid placing weapon-specific exceptions in the global calculation when a dedicated profile can express them.

## Change an enemy stat with an AI buff

Pattern based on `SpicyEnemies.lua`:

```lua
mod:add_buff_template("hj_example_ai_health", {
    name = "hj_example_ai_health",
    apply_buff_func = "apply_max_health_buff_for_ai",
    remove_buff_func = "remove_max_health_buff_for_ai",
    multiplier = 0.25,
})
```

The actual fields required depend on the base-game apply/remove function. Applying the buff is a separate step and should generally be host-authoritative. Use a dedicated AI buff when an effect is dynamic, temporary, aura-based, or shared with another mutator system.

## Change a static enemy breed property

For a field that already exists after base-game tables load, direct mutation is simplest:

```lua
Breeds.example_enemy.bloodlust_health = NewBreedTweaks.bloodlust_health.skaven_elite
Breeds.example_monster.boost_curve_multiplier_override = 2
```

Search for all systems that read the field, and test every difficulty/mutator that may override it. For a breed that rebuilds fields in its initializer, a wrapper can instead apply changes afterward:

```lua
mod:hook(Breeds.example_breed, "initialize_func", function(func, breed, ...)
    func(breed, ...)
    breed.some_field = some_value
end)
```

Always call the original first unless there is a strong reason not to; it may populate fields your patch relies on. This pattern is useful when the game rebuilds or overwrites breed fields during initialization.

## Load a resource used by a new effect

If a buff/effect references a unit, VFX, or other resource in a base-game package that is not normally loaded, load it before use:

```lua
Managers.package:load("resource_packages/path/to/base_game_package", "global")
```

Global package loads consume memory and can create dependencies on DLC/base-game content. Reuse already-loaded resources when possible, verify package availability, and avoid loading packages without a concrete need.

## Add a VMF setting and keybind

1. Add a widget in `TourneyBalance_data.lua`.
2. Add title/tooltip localization in `TourneyBalance_localization.lua`.
3. If it is a function-call keybind, define the named method on `mod` in an active module.
4. Read normal settings with `mod:get("setting_id")` where needed.

Example widget:

```lua
{
    setting_id = "hj_example_toggle",
    type = "checkbox",
    default_value = false,
    title = "hj_example_toggle_title",
    tooltip = "hj_example_toggle_description",
}
```

Do not conditionally register network templates based on a local checkbox. Register them unconditionally, then conditionally activate behavior.

## Add a command

```lua
mod:command("hj_example", "Does an example action", function(...)
    -- Validate game state and authority before acting.
end)
```

Commands may be used in menus or invalid game states. Guard access to `Managers.state`, units, and game mode as necessary.

## Avoid these common mistakes

- Calling `get_mod("TourneyBalance")` in active code; the registered ID is `HoloJustice`.
- Loading a new file only by creating it; it must be reached by `mod:dofile` or another active path.
- Editing `career_changes.lua.processed` instead of the source `.lua`.
- Aliasing a table when intending to clone it.
- Editing a shared profile for one weapon.
- Adding a buff/profile without a network lookup.
- Registering lookups conditionally or nondeterministically.
- Forgetting description/localization changes.
- Using `hook_origin` for a one-field balance change.
- Running authoritative effects on every peer.
- Assuming a setting works because it appears in the options UI.
