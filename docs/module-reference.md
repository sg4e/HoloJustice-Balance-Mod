# Module reference

This reference describes every project-owned runtime/configuration file and highlights maintenance risks.

## Root files

### `HoloJustice.mod`

- **Loaded by:** game mod launcher.
- **Role:** VMF bootstrap and package declaration.
- **Key contract:** VMF must load first; VMF mod ID is `HoloJustice`.
- **Change when:** renaming/moving main scripts or adding a compiled package.
- **Risk:** a bad path prevents the mod from loading at all.

### `itemV2.cfg`

- **Loaded by:** Workshop upload tooling.
- **Role:** beta Workshop listing metadata.
- **Change when:** updating Workshop description, visibility, tags, preview, or published item metadata.
- **Risk:** distribution-only changes can affect the published listing; they do not change gameplay.

### `lua_preprocessor_defines.config`

- **Loaded by:** Lua resource compiler/preprocessor.
- **Role:** allow-list for conditional compilation tags.
- **Current state:** no active valid tags.

### `resource_packages/TourneyBalance/TourneyBalance.package`

- **Loaded by:** manifest/package system.
- **Role:** compiled package artifact.
- **Risk:** binary artifact; source review cannot explain its contents. Regenerate only with the appropriate mod tools.

### `core/physx_metadata/*`

Physics metadata artifacts for supported PhysX versions/architectures. They are not balance logic.

## VMF top-level files

### `TourneyBalance.lua`

- **Loaded by:** VMF as `mod_script`.
- **Role:** active orchestrator and post-processing layer.
- **Owns:** runtime localization overlay, active `dofile` list, damage-profile registration/finalization, weapon normalization, `on_enabled` talent-buff merge.
- **High-risk areas:** module load order, network lookup insertion, broad loops over every damage profile and weapon.
- **Note:** a large commented-out `BuffExtension` replacement has no runtime effect.

### `TourneyBalance_data.lua`

- **Loaded by:** VMF as `mod_data`.
- **Role:** mod name, non-togglable status, and options widgets.
- **Risk:** settings can be visible without behavior if their implementing module is inactive.
- **Known inactive-facing settings:** tournament checker and performance logging currently point toward dormant modules.

### `TourneyBalance_localization.lua`

- **Loaded by:** VMF as `mod_localization`.
- **Role:** settings and command localization.
- **Different from:** runtime gameplay text registered with `mod:add_text`.

## Active change modules

### `changes/thp_stagger_changes.lua`

- **Loaded:** first.
- **Role:** temporary-health and stagger changes plus shared helper definitions.
- **Integrates via:** core combat hooks/replacements, talent/buff template mutation, proc registration.
- **Defines:** `mod:add_talent_buff_template`, `mod:add_buff_template`, `mod:add_proc_function`, and `mod:modify_talent` (some are later redefined).
- **Risk:** system-wide combat math and hot-path performance.

### `changes/talent_changes.lua`

- **Loaded:** second.
- **Role:** selectable talent behavior across heroes/careers.
- **Integrates via:** talent/buff table mutation, custom proc/buff functions, hooks, networked buff addition, runtime localization.
- **Defines/redefines:** the primary helper set used by later active modules.
- **Risk:** very broad scope; helper changes can affect many later sections. Some hooks fully replace base-game methods.

### `changes/weapon_changes.lua`

- **Loaded:** third.
- **Role:** melee/ranged weapon and damage-profile balance.
- **Integrates via:** direct `Weapons`/`DamageProfileTemplates` mutation, `NewDamageProfileTemplates`, action-chain edits, and hooks for weapon mechanics.
- **Risk:** the largest module; shared profile edits and action chains have non-obvious consumers. Contains two global `add_chain_actions` definitions, so the later definition wins.

### `changes/career_changes.lua`

- **Loaded:** fourth.
- **Role:** passives, career abilities, auras, and non-talent career mechanics.
- **Integrates via:** helper-based buff edits, direct data edits, runtime localization, wrapper hooks, and origin replacements.
- **Risk:** ability-class origin hooks are tightly coupled to base-game code.

### `changes/SpicyEnemies.lua`

- **Loaded:** fifth.
- **Role:** reusable enemy/mutator buffs for Dutch Spice-style behavior.
- **Integrates via:** global base-game package loads, buff/proc functions, and network-registered buff templates.
- **Risk:** global package memory/dependency cost, AI/server authority, and network synchronization.
- **Style note:** filename capitalization matters on case-sensitive systems.

### `logging_and_qol/basic_qol.lua`

- **Loaded:** sixth.
- **Role:** pause and restart keybind/commands, optional bot disabling, disabled-bot crash prevention.
- **Integrates via:** VMF commands, mod methods referenced by data widgets, and wrapper hooks.
- **Risk:** restart/pause depend on current game mode/state; bot hooks affect spawning flow.

### `changes/rats.lua`

- **Loaded:** seventh/last.
- **Role:** registers `/silly_proj`, a novelty command that toggles a chaotic thrown-projectile trajectory.
- **Integrates via:** direct replacement/restoration of `ProjectileTemplates.trajectory_templates.throw_trajectory`; uses separate unit and husk update functions.
- **Risk:** changes a shared process-wide trajectory template, uses randomness, and intentionally gives unit/husk paths different behavior. Test multiplayer synchronization and ensure the original template is restored when toggled off.

## Inactive or generated files

### `logging_and_qol/mod_checker.lua`

- **Current state:** not loaded.
- **Intended role:** compare active Workshop mods against required/allowed/prohibited lists, share status over networking, and display warnings.
- **Before enabling:** change/verify `get_mod("TourneyBalance")`, compose lifecycle callbacks rather than overwriting others, review hard-coded Workshop IDs, and test networking/UI paths.

### `logging_and_qol/performance_logging.lua`

- **Current state:** not loaded.
- **Intended role:** collect and print mission performance data.
- **Before enabling:** change/verify `get_mod("TourneyBalance")`, compose `mod.update`/game-state callbacks, verify globals and all hook signatures, and assess hot-path overhead.

### `changes/career_changes.lua.processed`

- **Current state:** not loaded by the active script.
- **Role:** generated/processed artifact.
- **Rule:** edit `career_changes.lua`; regenerate only through the relevant build step.

## Cross-module helper ownership

The codebase evolved as a patch set rather than a formal library. Several helpers are defined in more than one file. Their effective ownership is load-order based.

For new work:

- call helpers only after the file defining the desired version has loaded;
- avoid adding a third incompatible implementation;
- consider moving shared helpers into a dedicated early-loaded module in a future refactor;
- preserve deterministic registration behavior;
- search all definitions before changing helper semantics.

## Active versus merely present

A file's presence does not make it active. The authoritative active graph is:

1. paths named in `HoloJustice.mod`;
2. files reached by `mod:dofile` from the active main script;
3. base-game files/packages reached by `require` or `Managers.package:load`.

When debugging “my change does nothing,” first prove that the file is on this graph.
