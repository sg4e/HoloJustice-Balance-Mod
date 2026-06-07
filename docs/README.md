# HoloJustice Balance Mod documentation

This directory documents the project from its Workshop metadata down to the runtime tables and hooks that implement the balance patch. It is written for maintainers who know Lua but may not yet know Vermintide 2 or the Vermintide Mod Framework (VMF).

> **Important:** HoloJustice is an unsanctioned, version-sensitive balance mod. It edits game-owned Lua tables and replaces some game functions. Fatshark updates can rename or reshape those objects. Every player in a multiplayer lobby should use the same balance-mod version.

## Start here

1. [Project layers and file map](project-layers.md) — what every repository area is for and whether it is active at runtime.
2. [Initialization and integration](initialization-and-integration.md) — the complete launcher → VMF → base-game initialization path.
3. [Runtime data model](runtime-data-model.md) — weapons, damage profiles, talents, buffs, careers, enemies, hooks, and networking.
4. [Balance change cookbook](balance-cookbook.md) — plentiful patterns for changing existing and new game elements.
5. [Module reference](module-reference.md) — responsibilities and hazards of every Lua module.
6. [Development, testing, and release](development-and-testing.md) — safe workflow, debugging, compatibility, packaging, and review checklist.

## Mental model

HoloJustice is mostly a **startup-time patch set**:

```text
Vermintide 2 launcher
  -> loads VMF first
  -> executes HoloJustice.mod
  -> VMF new_mod("HoloJustice", ...)
  -> VMF loads data, localization, and TourneyBalance.lua
  -> TourneyBalance.lua executes active change modules in order
  -> modules mutate base-game global tables and register VMF hooks/functions
  -> final normalization and network lookup setup runs
  -> gameplay uses the patched tables and hooks
```

The source directory is still named `TourneyBalance` because this project was derived from Tourney Balance, while the registered VMF identity is `HoloJustice`. That distinction matters whenever calling `get_mod`, defining paths, or troubleshooting a load failure.

## Terminology

- **Base game:** Fatshark's Vermintide 2 Lua runtime, global template tables, extension classes, managers, and resource packages.
- **VMF:** Vermintide Mod Framework. It creates the mod object and supplies APIs such as `get_mod`, `mod:dofile`, `mod:hook`, `mod:hook_origin`, `mod:command`, settings, localization, and lifecycle callbacks.
- **Template:** A shared Lua table that describes a weapon, damage profile, buff, talent, career, breed, or similar object.
- **Lookup:** A name ↔ numeric-ID table used by network RPCs. New synchronized templates generally need registration in the corresponding `NetworkLookup`.
- **Hook:** A VMF-installed wrapper or replacement around a base-game function.
- **Host/server authoritative:** Logic that must be decided by the host and synchronized to clients rather than independently executed by every peer.

## Scope and source-of-truth caveat

These docs describe the repository as it exists now. They do not reproduce the base-game source, which is not included here. To discover a base-game template name or current table shape, inspect the game's Lua source with the usual Vermintide modding tools and compare it against nearby working changes in this repository. Never assume a name found in an old guide still exists in the installed game version.
