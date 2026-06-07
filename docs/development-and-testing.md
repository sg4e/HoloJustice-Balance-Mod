# Development, testing, and release

Balance-mod development requires both static review and in-game testing. Standalone Lua execution cannot model Vermintide's globals, VMF hooks, managers, network lookups, or game resources.

## Recommended change workflow

1. **Create a focused change.** Keep one weapon/talent/system change together and near similar code.
2. **Find the source template.** Confirm names and fields in current base-game scripts.
3. **Search consumers.** Determine whether the edited template is shared.
4. **Select the least invasive mechanism.** Prefer field edit → dedicated clone → wrapper hook → origin replacement.
5. **Keep startup deterministic.** Register every new peer-visible template unconditionally and in the same order.
6. **Update UI text.** Mechanics and descriptions should agree.
7. **Review authority.** Decide what runs on host, local client, or every peer.
8. **Run static checks.** Search for bad IDs, unregistered names, syntax mistakes, and accidental generated-file edits.
9. **Run in-game tests.** Include multiplayer for any gameplay change.
10. **Document compatibility concerns.** Especially shared profiles and `hook_origin` replacements.

## Static inspection commands

```bash
# List the active module graph.
rg -n 'mod:dofile' scripts/mods/TourneyBalance/TourneyBalance.lua

# Find all definitions/usages before editing a helper.
rg -n 'add_talent_buff_template|modify_talent_buff_template' scripts/mods/TourneyBalance

# Find direct consumers of a profile/template.
rg -n 'profile_or_template_name' scripts/mods/TourneyBalance

# Review hooks, especially full replacements.
rg -n 'mod:hook_origin|mod:hook_safe|mod:hook\(' scripts/mods/TourneyBalance

# Catch the stale original mod ID in code proposed for activation.
rg -n 'get_mod\("TourneyBalance"\)' scripts/mods/TourneyBalance

# Review changed files and whitespace.
git diff --check
git diff --stat
git diff
```

If a Lua parser/linter compatible with Vermintide's Lua dialect is available, use it, but do not assume a generic modern-Lua linter understands the game's extensions/preprocessing.

## Startup smoke test

Launch with VMF above HoloJustice and inspect the console/log.

Confirm:

- no `new_mod` load-order assertion;
- no missing script/package error;
- no nil global/table field failure during top-level module execution;
- no duplicate/missing `NetworkLookup` entry error;
- no damage-profile or weapon action assertion;
- the `BETA HoloJustice` echo appears;
- settings page opens and keybinds can be assigned.

Top-level errors are especially severe: they can prevent all later modules and finalization from running.

## Keep/menu test

Before combat, verify:

- weapon inventory/equipment screens open;
- talent screens open and descriptions match changes;
- affected careers can be selected/spawned;
- commands/keybinds fail gracefully in invalid states;
- no continuous console spam or frame-time regression.

## Combat test matrix

For a weapon/damage-profile change, test:

| Dimension | Cases |
|---|---|
| Hit order | first target, later targets, default target |
| Armor | infantry, armor, super armor, berserker, monster, special cases |
| Hit quality | body, headshot, crit, crit headshot, backstab if relevant |
| Attack | every edited action and chain transition |
| State | normal, buffed, debuffed, high/low overcharge if relevant |
| Feedback | damage, stagger, cleave, reach, animation, sound/VFX |

For a talent/career change, test selecting/deselecting, death/respawn, cooldown, joining in progress, swapping careers, stacking limits, buff expiration, and UI descriptions.

For enemy changes, test spawn, stagger, death, specials/monsters, hordes, server performance, and interactions with the intended difficulty/mutator.

## Multiplayer test matrix

At minimum:

1. Host and client both use the same build.
2. Client joins in progress.
3. Host triggers the changed effect.
4. Client triggers the changed effect.
5. Buffs/damage/cooldowns agree on both peers.
6. Death, respawn, reconnect, and level transition do not leave state behind.
7. No RPC lookup/disconnect errors appear.

Also deliberately test a version mismatch in a controlled environment if distributing a change that adds network templates. The correct outcome may be requiring matching versions; the important goal is understanding the failure mode.

## Testing hooks safely

For each hook:

- verify its target and method still exist;
- compare argument order against current base-game source;
- preserve return values where callers expect them;
- ensure wrapper hooks call `func` exactly once unless intentional;
- check authority and game-state assumptions;
- avoid logging in per-frame/per-hit hot paths;
- for `hook_origin`, compare the replacement against the latest original after every game update.

## Debugging common failures

### Mod fails before showing its startup echo

Likely causes: wrong VMF order, syntax/runtime error in an active module, renamed base-game global/template, missing package, or assertion in finalization. Read the first relevant error, not only the cascade afterward.

### A new damage profile is nil at runtime

Confirm it was assigned to `NewDamageProfileTemplates` before main-script finalization, its name is spelled identically on the action, and startup completed without error.

### A new buff cannot synchronize

Confirm it exists in `BuffTemplates`, has a two-way `NetworkLookup.buff_templates` entry on every peer, is registered in deterministic order, and the request is made for a networked unit with correct host/client authority.

### A value changes more weapons than expected

The edited damage/buff/action subtable is shared or aliased. Search all references and create a cloned dedicated template.

### A setting appears but has no effect

The widget is only metadata. Confirm an active module reads the setting or defines the referenced keybind function. In this repository, mod-checker and performance-logging code is currently dormant.

### A file edit has no effect

Confirm the file is loaded by `HoloJustice.mod` or an active `mod:dofile`. `career_changes.lua.processed`, `mod_checker.lua`, and `performance_logging.lua` are not on the current active graph.

## Style and maintenance guidance

- Use unique `hj_`-prefixed names for new templates/functions/localization IDs where practical.
- Keep changes in the appropriate module and near the relevant hero/weapon section.
- Comment intent and original value, not merely what an assignment does.
- Avoid adding globals; use `local` unless the startup finalizer intentionally consumes a global such as `NewDamageProfileTemplates`.
- Do not silently redefine shared helpers.
- Do not add `hook_origin` without a rationale.
- Keep localization synchronized with mechanics.
- Treat case-sensitive paths consistently (`SpicyEnemies.lua` is capitalized).

## Packaging and release

Source edits and the compiled `.package` are separate concerns. Pure Lua changes may be picked up by a development mod workflow, while Workshop/bundle releases may require the Vermintide mod tools to rebuild/package content.

Before release:

- review `git diff` and generated/binary changes;
- verify whether the package needs regeneration;
- update Workshop metadata only intentionally;
- test a clean installation/load order;
- test matching multiplayer clients;
- note incompatibilities with other balance mods;
- provide a concise player-facing changelog.

## Review checklist

- [ ] The edited file is active.
- [ ] Correct VMF ID (`HoloJustice`) is used.
- [ ] Base-game names/field shapes were verified.
- [ ] Shared-template blast radius was checked.
- [ ] New network templates are unique and deterministically registered.
- [ ] Host/client authority is correct.
- [ ] Descriptions/localization match mechanics.
- [ ] Wrapper/origin hook behavior was reviewed.
- [ ] Startup, keep, combat, and multiplayer tests passed.
- [ ] `git diff --check` is clean.
