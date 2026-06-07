# Initialization and integration with VMF and the base game

This document traces exactly how HoloJustice becomes part of Vermintide 2 and explains the three principal integration mechanisms: table mutation, VMF hooks, and network/template registration.

## Prerequisites and load order

HoloJustice depends on the Vermintide Mod Framework. In the launcher, VMF must be enabled and ordered **above** HoloJustice.

The first executable code is `HoloJustice.mod`:

```lua
fassert(rawget(_G, "new_mod"), "`HoloJustice` mod must be lower than Vermintide Mod Framework in your launcher's load order.")
new_mod("HoloJustice", { ... })
```

VMF creates a mod object named `HoloJustice`, arranges for the configured script/data/localization files to be loaded, and supplies the APIs used throughout the project.

## Complete initialization sequence

### Phase 1: launcher manifest

1. The launcher reads `HoloJustice.mod`.
2. The manifest verifies VMF has installed global `new_mod`.
3. `new_mod("HoloJustice", ...)` registers the mod and its three main VMF paths.
4. The declared compiled resource package becomes available through the mod loader.

A failure before step 2 means the load order is wrong. A failure after step 3 usually points to a bad script path, syntax/runtime error, or a base-game compatibility break.

### Phase 2: VMF metadata and localization

VMF consumes:

- `TourneyBalance_data.lua` for the options UI, keybind function names, and non-togglable status;
- `TourneyBalance_localization.lua` for settings/command strings;
- `TourneyBalance.lua` for behavior.

The precise internal order is managed by VMF, but behavior code can rely on `get_mod("HoloJustice")` returning its VMF object.

### Phase 3: main-script bootstrap

At top-level, `TourneyBalance.lua` immediately executes. This is not deferred until a mission begins.

It first installs a runtime localization overlay:

```lua
mod:add_text("some_text_id", "Replacement English text")
```

stores text in a private table, while a VMF `mod:hook("Localize", ...)` returns an override when one exists and delegates to the original `Localize` otherwise. This lets balance modules keep talent descriptions consistent with changed mechanics without editing base-game localization files.

The main script also initializes `NewDamageProfileTemplates`, provides an early buff-registration helper, and adds a wrapper hook that blocks one pickup.

### Phase 4: ordered module execution

`mod:dofile(path)` executes each active module in the same shared game/VMF environment. Order matters because the modules both mutate base-game state and define methods on the shared `mod` object.

```text
thp_stagger_changes
  -> talent_changes
  -> weapon_changes
  -> career_changes
  -> SpicyEnemies
  -> basic_qol
  -> rats
```

Examples of order dependence:

- Talent and career files call helpers such as `mod:modify_talent_buff_template`, `mod:add_buff_function`, and `mod:add_proc_function` defined earlier.
- Weapon modules populate `NewDamageProfileTemplates`; the main script only registers and merges those profiles **after** all modules return.
- Later direct mutations win if two modules write the same field.
- Helper names are redefined in more than one module. At any point, the most recently executed definition is the one later modules see.

Do not casually alphabetize the `dofile` list.

### Phase 5: finalization

Once all active modules finish, the remainder of `TourneyBalance.lua` performs startup normalization:

1. Every entry in `NewDamageProfileTemplates` is added to the two-way `NetworkLookup.damage_profiles` table.
2. New profiles are recursively merged into `DamageProfileTemplates`.
3. String references in damage-profile fields are resolved through `PowerLevelTemplates`, and required fields are asserted.
4. A zero-attack-power `_no_damage` clone is generated for every damage profile that lacks one.
5. Every `Weapons` entry receives/rebuilds names, crosshair defaults, attack metadata, action lookup data, action validation, and related derived fields.
6. On VMF's `mod.on_enabled`, talent buff templates are recursively merged into global `BuffTemplates`.

This finalization is why a new damage profile should normally be added to `NewDamageProfileTemplates`, not only assigned straight into `DamageProfileTemplates`.

## How HoloJustice changes the base game

### 1. Direct mutation of base-game global tables

Most simple balance changes assign into tables already built by the game:

```lua
Weapons.some_template.dodge_count = 4
DamageProfileTemplates.some_profile.default_target.power_distribution.attack = 0.45
```

These changes are global for the process and generally affect every action that references the changed template. Shared profile edits can therefore unintentionally affect multiple weapons.

Common game-owned tables used here include:

- `Weapons`
- `DamageProfileTemplates`
- `PowerLevelTemplates`
- `TalentBuffTemplates`, `BuffTemplates`
- `Talents`, `TalentTrees`, `TalentIDLookup`, `CareerSettings`
- `ProcFunctions`, `BuffFunctionTemplates.functions`
- `NetworkLookup`
- breed/enemy tables reached by hooks

### 2. Creating and registering templates

New buffs and damage profiles need names that every peer can convert to matching numeric network IDs.

The repository's helpers generally register a new buff like this:

```lua
BuffTemplates[buff_name] = template
local index = #NetworkLookup.buff_templates + 1
NetworkLookup.buff_templates[index] = buff_name
NetworkLookup.buff_templates[buff_name] = index
```

New damage profiles are accumulated in `NewDamageProfileTemplates`; the main script later performs equivalent registration and merges them into `DamageProfileTemplates`.

**Multiplayer invariant:** peers must load the same templates in the same order. A host/client mismatch can produce wrong IDs, failed RPCs, disconnects, or divergent gameplay.

### 3. VMF hooks

The project uses three VMF hook styles:

- `mod:hook(target, method, wrapper)` or `mod:hook(function, wrapper)`: wraps the original. The wrapper receives `func` and should call it unless intentionally suppressing/replacing behavior.
- `mod:hook_origin(target, method, replacement)`: replaces the original implementation. It is powerful and highly version-sensitive.
- `mod:hook_safe(target, method, observer)`: runs observation/side-effect logic safely around the original; used mainly by dormant logging modules.

Wrapper example pattern:

```lua
mod:hook(SomeClass, "method", function(func, self, ...)
    -- before
    local result = func(self, ...)
    -- after
    return result
end)
```

Replacement example pattern:

```lua
mod:hook_origin(SomeClass, "method", function(self, ...)
    -- Entire replacement. Must preserve required base-game behavior yourself.
end)
```

Prefer table mutation or wrapper hooks over `hook_origin`. A copied replacement silently goes stale when Fatshark changes the original function.

### 4. Base-game managers, systems, and extensions

More complex changes call live game services:

- `Managers.state.network` and `network_transmit` for RPCs;
- `Managers.state.entity:system("buff_system")` for synchronized buffs;
- `Managers.player` and `Managers.state.side` for ownership and teams;
- `ScriptUnit.extension(unit, "buff_system")` and other extensions for per-unit state;
- `Managers.package:load` for base-game resource packages.

These objects may be absent in menus or during transitions. Runtime code should guard state-dependent manager access unless the hooked function guarantees the relevant state exists.

### 5. VMF settings, commands, and callbacks

`TourneyBalance_data.lua` maps keybinds to methods on the mod object, such as `do_pause` and `restart_level`. `basic_qol.lua` defines those methods and also registers `/pause` and `/restart` commands with `mod:command`.

VMF lifecycle/event callback names are properties on the mod object, for example:

```lua
mod.on_enabled = function(self) ... end
mod.update = function(dt) ... end
mod.on_game_state_changed = function(status, state_name) ... end
```

Only one function can occupy a property at once. If multiple modules assign `mod.update`, the last assignment wins unless the project explicitly composes them.

## Host/client responsibilities

A balance change is not multiplayer-safe merely because all peers load the file.

- Pure template values should be identical on every peer.
- Spawning, granting buffs, drops, damage, and authoritative state changes generally belong on the server/host.
- Visual/UI-only logic may belong only on the local client.
- Synchronized buff additions must use registered template IDs and the appropriate buff system/RPC.
- Avoid generating lookup entries conditionally based on local settings; that changes network ID order.

The helper `mod:add_buff(owner_unit, buff_name)` in `talent_changes.lua` demonstrates the split: the server adds the synchronized buff directly, while a client asks the server through an RPC.

## Compatibility implications

Because HoloJustice mutates shared global tables:

- load order against other balance mods determines which assignment wins;
- two mods can compose on different fields but conflict on the same field or hook;
- replacing a shared damage profile affects all consumers, including other mods;
- registering different templates in different orders breaks network lookup agreement;
- a base-game patch can break field paths or `hook_origin` signatures.

For a change intended only for one attack, clone/create a dedicated damage profile and point that attack to it rather than changing a broadly shared profile.
