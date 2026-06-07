# Project layers and file map

HoloJustice has six practical layers: distribution metadata, VMF bootstrap, VMF metadata/UI, orchestration, balance/runtime modules, and compiled resources.

## 1. Distribution and Workshop layer

| Path | Purpose | Runtime role |
|---|---|---|
| `itemV2.cfg` | Steam Workshop upload metadata: title, description, preview, visibility, published ID, sanction status, and tags. | Read by the Workshop upload tooling, not normal gameplay Lua. |
| `item_preview.jpg` | Workshop preview image. | Distribution only. |
| `README.md` | Short repository overview. | None. |
| `.gitattributes`, `.gitignore` | Git behavior. | None. |
| `.idea/` | IDE project state. | None; do not treat it as game configuration. |

`itemV2.cfg` calls this upload **HoloXussy**, the beta version, while the VMF mod ID is **HoloJustice** and the script folder is **TourneyBalance**. These are three different identifiers with different consumers.

## 2. Launcher/bootstrap layer

### `HoloJustice.mod`

This is the entry manifest executed by the Vermintide launcher/mod loader.

It does two things:

1. Its `run` function asserts that VMF's global `new_mod` function already exists, producing a useful load-order error if VMF is below HoloJustice.
2. It calls `new_mod("HoloJustice", ...)`, mapping the registered mod to:
   - `scripts/mods/TourneyBalance/TourneyBalance.lua`
   - `scripts/mods/TourneyBalance/TourneyBalance_data.lua`
   - `scripts/mods/TourneyBalance/TourneyBalance_localization.lua`

The manifest also declares the compiled `resource_packages/TourneyBalance/TourneyBalance` package.

**Invariant:** `get_mod("HoloJustice")` is correct for active HoloJustice scripts even though their filesystem path contains `TourneyBalance`.

## 3. VMF metadata, settings, and localization layer

### `scripts/mods/TourneyBalance/TourneyBalance_data.lua`

Returns VMF metadata and options. The mod is deliberately `is_togglable = false`; disabling a balance mod midway through a process would not safely undo table mutations or hooks.

Declared settings:

- Tournament-check UI: `tourney_mode`, `tourney_display_mods`, `font_size`, `position_x`, and `position_y`.
- QoL: `disable_bots`, pause keybind, and restart keybind.
- `performance_logging`.

Not every setting currently has active implementation. The tournament checker and performance logger modules are present but not loaded by the active orchestrator.

### `scripts/mods/TourneyBalance/TourneyBalance_localization.lua`

Returns VMF localization strings for settings and commands. It is separate from the runtime `mod:add_text` mechanism used to replace gameplay talent descriptions.

There are therefore two localization paths:

1. **VMF metadata localization:** returned from `TourneyBalance_localization.lua`, consumed by VMF for option labels and descriptions.
2. **Runtime gameplay localization overlay:** populated via `mod:add_text` and intercepted by the `Localize` hook in `TourneyBalance.lua`.

## 4. Orchestration and finalization layer

### `scripts/mods/TourneyBalance/TourneyBalance.lua`

This is the active main script. It:

- obtains the VMF object with `get_mod("HoloJustice")`;
- creates the runtime localization overlay and hooks global `Localize`;
- defines early helper state such as `NewDamageProfileTemplates` and `mod:add_buff`;
- blocks interaction with the Skull of Fury pickup;
- executes active modules in a deliberate order using `mod:dofile`;
- registers new damage profiles in `NetworkLookup.damage_profiles`;
- merges and normalizes damage profiles;
- generates `_no_damage` variants;
- rebuilds/validates weapon lookup metadata similarly to base-game startup logic;
- merges talent buffs into `BuffTemplates` again in `on_enabled`.

See [Initialization and integration](initialization-and-integration.md) for the detailed sequence.

## 5. Balance and runtime behavior layer

### Active modules

Loaded, in order, from `TourneyBalance.lua`:

| Order | Module | Main responsibility |
|---:|---|---|
| 1 | `changes/thp_stagger_changes.lua` | Reworks stagger damage and temporary-health talents; defines several shared helpers. |
| 2 | `changes/talent_changes.lua` | Talent buffs, talent definitions, proc/buff functions, and many career-specific talent mechanics. Re-defines/extends helper methods used later. |
| 3 | `changes/weapon_changes.lua` | Weapon action chains, attack timing, ammo, damage profiles, and weapon-specific mechanics. |
| 4 | `changes/career_changes.lua` | Passives, career abilities, auras, career hooks, and non-talent career behavior. |
| 5 | `changes/SpicyEnemies.lua` | Enemy/mutator buff templates and required base-game mutator package loads. |
| 6 | `logging_and_qol/basic_qol.lua` | Pause/restart commands and keybind targets, bot disabling, and a disabled-bot crash guard. |
| 7 | `changes/rats.lua` | Registers `/silly_proj`, which toggles a process-wide replacement for the shared thrown-projectile trajectory template. |

### Present but inactive modules

These files are **not** loaded by `TourneyBalance.lua`:

- `logging_and_qol/mod_checker.lua`
- `logging_and_qol/performance_logging.lua`

They should be treated as dormant/experimental code, not current behavior. Both call `get_mod("TourneyBalance")`, which does not match the active VMF ID `HoloJustice`; loading them unchanged is likely to fail or attach behavior to the wrong/nonexistent mod object. They also define lifecycle callbacks that could overwrite callbacks defined elsewhere if loaded carelessly.

### Generated artifact

`changes/career_changes.lua.processed` is a generated/processed counterpart to `career_changes.lua`. It is not loaded by the orchestrator. Make source changes in `.lua` unless the build pipeline explicitly requires regenerating processed files.

## 6. Resource and build layer

| Path | Purpose |
|---|---|
| `resource_packages/TourneyBalance/TourneyBalance.package` | Compiled package declared by `HoloJustice.mod`. It is binary and not a substitute for the Lua source. |
| `core/physx_metadata/*.physx_metadata` | Physics metadata included in the bundle/tooling environment. Not balance logic. |
| `lua_preprocessor_defines.config` | Defines valid Lua preprocessor feature tags. No active tags are currently defined. |

`SpicyEnemies.lua` additionally loads several **base-game** mutator/DLC packages through `Managers.package:load`. Those packages are not stored in this repository; the game supplies them.

## Dependency direction

```text
Workshop metadata (distribution only)

HoloJustice.mod
  -> VMF new_mod
      -> TourneyBalance_data.lua
      -> TourneyBalance_localization.lua
      -> TourneyBalance.lua
          -> active changes/*.lua and basic_qol.lua
          -> base-game globals, managers, classes, and packages
```

Most modules are not isolated Lua libraries. They assume VMF and the base game have already created many globals. Running them with a stock standalone Lua interpreter will not work.
