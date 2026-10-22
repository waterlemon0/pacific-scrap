# Pacific Scrap

Scrap Mechanic **custom game** (Lua) recreating Pacific Drive on top of Survival.
The owner is learning how it works and plays it to test; there is no test suite.

**Read `docs/` first.** `docs/README.md` has the run loop and a file map;
`docs/gotchas.md` lists engine limits that broke saves before. Update the docs
only for important changes: a new system, a change to how one works, or a new
engine gotcha. Skip small tweaks (numbers, text, models, loot).

## Rules

- World creation data must stay well under 64KB (pack tile lists with `tilepack.lua`), or saves corrupt and freeze the PC on load.
- Never `world:destroy()` or wipe a zone; retire it (`Game.sv_retireZone`).
- Portals: delay `transferAToB()` a few ticks after creating or moving openings; one portal per creation; collect whole creations with `getCreationBodies()`.
- Don't `sendToWorld` before the world's script reports ready.
- No `setmetatable`; `dofile` only at top level; GUI paths use `$CONTENT_3c9f5e62-8d1a-4b7e-9a35-6f2d0c4e8b71`.
- Old saves must keep loading: add migrations (`sv_storyState`, `sv_jmMap`, `LANDMARK_LAYOUT`) instead of breaking saved data.
- After **any** change (scripts too), delete everything inside `Cache/` (`Bundle`, `Data`, `Raw`, `Textures`, `Impostor`, `Mesh`) before launch, by full path. The game caches scripts in `Cache/Raw` and textures in `Cache/Textures` and doesn't notice when the files change, so edits silently don't apply.
- **Only the mod's own `Cache/`** (`...\Mods\PacificScrap\Cache`). Never touch the game's `Cache` folder (`D:\steam\steamapps\common\Scrap Mechanic\Cache`): the game ships some content (character customization) only as pre-built files there, and deleting them leaves the player invisible until Steam's "Verify integrity of game files" restores them.
- Match the code style: tabs, `sv_`/`cl_`/`_e_`/`_n_` naming, explanatory comments in plain English.
- When the owner asks for an opinion, give it and wait; don't implement.

## Paths

- Game install (Survival data, logs): `D:\steam\steamapps\common\Scrap Mechanic`
- Logs: `D:\steam\steamapps\common\Scrap Mechanic\Logs\game-*.log`, lines tagged `[PacificScrap]`
- Map sites and picture: `python Gui/make_map.py`
- Editors (open in a browser, owner uses them): `Tools/map_editor.html` → `Maps/map_layout.json`,
  `Tools/fabricator_editor.html` → `Fabricator/upgrade_tree.json` (the Fabricator tree lives
  there now, not in `upgrade_tree.lua`; catalog: `python Tools/make_fabricator_catalog.py`)
