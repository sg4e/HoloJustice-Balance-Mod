# Runtime data model

Vermintide 2 balance behavior is largely data-driven. HoloJustice patches the game's already-created Lua tables, then uses hooks where data alone is insufficient.

## Weapon templates and actions

`Weapons[template_name]` describes a weapon. Relevant fields commonly include:

- weapon-level values such as `dodge_count`, `dodge_distance`, ammo data, and `buff_type`;
- `actions[action_name][sub_action_name]`, usually under `action_one`/`action_two`;
- attack timing such as `total_time`, `anim_time_scale`, and `allowed_chain_actions`;
- reach/targeting such as `range_mod` and `hit_mass_count`;
- `damage_profile`, or left/right profiles for dual-wield actions;
- `attack_meta_data`, used by bots and other systems.

An action does not normally contain all damage numbers. It points to a named damage profile. Changing an action's profile changes which damage rules it uses; changing the profile changes every action that references it.

The main script reprocesses weapon/action lookup metadata after balance modules run. New or malformed actions can fail assertions during this phase.

## Damage profiles

`DamageProfileTemplates[name]` controls damage, stagger, cleave, armor interaction, critical behavior, and hit-target behavior.

Typical shape:

```lua
{
    targets = {
        [1] = {
            power_distribution = { attack = ..., impact = ... },
            armor_modifier = { attack = {...}, impact = {...} },
            boost_curve_type = ...,
            boost_curve_coefficient_headshot = ...,
        },
    },
    default_target = {
        power_distribution = { attack = ..., impact = ... },
        armor_modifier = { attack = {...}, impact = {...} },
    },
    cleave_distribution = { attack = ..., impact = ... },
    critical_strike = ...,
}
```

`targets[1]`, `targets[2]`, etc. represent successive enemies hit; `default_target` applies after explicit target entries. `power_distribution.attack` controls damage power while `impact` controls stagger power. Armor modifier arrays map to the game's armor categories; copy a working neighboring profile and verify category ordering before changing them.

### Existing versus new profiles

- Edit `DamageProfileTemplates.foo` only when intentionally changing every consumer of `foo`.
- Add a profile to `NewDamageProfileTemplates` when a change needs its own behavior. The main script registers and merges it later.
- Use `table.clone(existing)` before modifying a clone. Plain assignment aliases the same table.

The main script creates `name .. "_no_damage"` clones automatically with attack power set to zero.

## Buff templates

A buff template is commonly wrapped as:

```lua
BuffTemplates.example = {
    buffs = {
        {
            name = "example",
            stat_buff = "power_level",
            multiplier = 0.1,
        },
    },
}
```

Buff entries can be passive stat modifiers or active behaviors. Common fields include:

- `stat_buff`, `multiplier`, `bonus`, `duration`, `max_stacks`;
- `event` and `buff_func` for event-driven procs;
- `apply_buff_func`, `remove_buff_func`, `update_func`;
- `proc_chance`, `buff_to_add`, and custom fields read by custom functions;
- synchronization/server-only flags.

New buff function names are registered in `BuffFunctionTemplates.functions`; new proc function names are registered in `ProcFunctions`. A string in a buff template must match one of those registered names or a base-game function.

### Repository helper APIs

The active modules add methods to the shared mod object:

- `mod:add_talent_buff_template(hero_name, buff_name, buff_data, extra_data)`
- `mod:modify_talent_buff_template(hero_name, buff_name, buff_data, extra_data)`
- `mod:add_buff_template(buff_name, buff_data)`
- `mod:add_proc_function(name, func)`
- `mod:add_buff_function(name, func)`
- `mod:add_buff(owner_unit, buff_name)`
- `mod:add_talent(career_name, tier, index, new_talent_name, new_talent_data)`

Definitions are duplicated across modules and are not a stable public library. Before extending them, inspect the currently active definition and load order.

## Talents and talent trees

A career's displayed talent slot resolves through several tables:

```text
CareerSettings[career_name]
  -> profile_name + talent_tree_index
  -> TalentTrees[hero][tree_index][tier][index]
  -> talent name
  -> TalentIDLookup[talent_name].talent_id
  -> Talents[hero][talent_id]
```

`mod:modify_talent(career_name, tier, index, fields)` follows that chain and merges fields into the existing talent. Typical talent fields point at buff names and localization IDs.

Talent behavior often spans three changes:

1. modify/add the buff template;
2. modify the talent to reference the buff or new description;
3. add replacement text using `mod:add_text`.

If only the mechanics change, the UI becomes misleading. If only the text changes, gameplay is unchanged.

## Careers, passives, and activated abilities

`career_changes.lua` modifies career buff templates and hooks career ability classes. Data edits are appropriate for aura ranges, passive multipliers, and existing ability settings. Hooks are needed when activation flow, targeting, refund logic, or state transitions change.

Career classes and method signatures are base-game implementation details. `mod:hook_origin` replacements must be reviewed after every relevant game update.

## Temporary health and stagger

`thp_stagger_changes.lua` is both a balance module and a systems-level replacement. It contains custom stagger/damage-calculation logic plus temporary-health talent definitions and helper functions.

This is a high-blast-radius area:

- damage calculation runs frequently;
- armor, stagger state, perks, friendly fire, boosts, and difficulty interact;
- a small arithmetic mistake affects many weapons/careers;
- replacing a core calculation can conflict with other combat overhauls.

Changes here require broader testing than a single weapon-number edit.

## Enemies, breeds, and mutator buffs

Enemy behavior can be altered in two broad ways shown here:

1. Register/apply AI buff templates (`SpicyEnemies.lua`) for health, hit mass, stagger resistance, damage, immunity, auras, and mutator-like effects.
2. Directly mutate `Breeds` fields for static properties, as the THP/stagger and career modules do for bloodlust-health categories and monster boost curves.

For simple enemy health/damage changes, prefer the narrowest existing breed/difficulty table or AI buff that achieves the goal. For networked dynamic effects, apply buffs server-side and synchronize them.

`SpicyEnemies.lua` loads several Fatshark resource packages globally before using their resources. Referencing a unit/effect from an unloaded package can crash or render nothing.

## Projectile templates and process-wide toggles

`rats.lua` registers `/silly_proj`, which replaces `ProjectileTemplates.trajectory_templates.throw_trajectory` with a custom table and restores the captured original when toggled off. This demonstrates a process-wide shared-template toggle rather than a rat/enemy change. Because projectile trajectory has separate `unit` and `husk` update paths, multiplayer behavior must be tested carefully. Randomness or different calculations between those paths can make remote visuals diverge from authoritative movement.

## Hooks and behavioral code

Use the least invasive mechanism:

1. Existing template field change.
2. New dedicated template plus reference change.
3. VMF wrapper hook that calls the original.
4. Safe observer hook for logging/side effects.
5. Full `hook_origin` replacement only when unavoidable.

Hooks run in hot paths in several modules. Avoid allocations, logging every frame/hit, or repeated global searches in frequently called functions.

## Localization

### VMF option localization

Entries returned from `TourneyBalance_localization.lua` describe settings and command UI. Add all user-facing settings IDs there.

### Gameplay localization overrides

`mod:add_text(id, string_or_language_table)` populates the main script's private overlay. The global `Localize` hook checks it first.

```lua
mod:add_text("example_desc", "Increases power by 10%.")

mod:add_text("example_multilingual", {
    en = "English text",
    de = "Deutscher Text",
})
```

English is the fallback. Be careful with `%`: Vermintide localization/formatting often requires `%%` to display a literal percent sign.

## Network lookups and deterministic startup

`NetworkLookup` tables map names to numeric IDs and numeric IDs back to names. The project writes both directions. Names must be unique, and insertion must happen deterministically on every peer.

Do not:

- register templates only when a local setting is enabled;
- iterate an unordered set to register peer-visible templates if order can differ;
- reuse a base-game/mod template name unintentionally;
- add the same name twice without guarding it.

Prefer a unique prefix for new names, such as `hj_`, to reduce collisions.

## Shared-state hazards

Lua tables are references. This aliases, rather than clones:

```lua
NewDamageProfileTemplates.hj_new = DamageProfileTemplates.old
```

A later edit to `hj_new` also edits `old`. Use:

```lua
NewDamageProfileTemplates.hj_new = table.clone(DamageProfileTemplates.old)
```

Likewise, direct edits of a shared base-game profile can have a larger effect than the nearby weapon section suggests. Search all references before deciding whether to edit or clone.
