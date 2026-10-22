# Pacific Scrap: how it works

Pacific Scrap is a Scrap Mechanic **custom game** that recreates Pacific Drive on
top of Survival. You live in a garage, drive into a junction, explore a randomly
generated zone, collect energy anchors, power an ARC Device on your car, open a
gateway and drive through it before the storm catches you.

These pages explain how each part is built, so you can find your way around the
code. They describe **how it works and where**, not every line.

| Page | What it covers |
|---|---|
| [junctions.md](junctions.md) | The junction map: how junctions are created, placed, locked and unlocked; the Route Planner |
| [zones.md](zones.md) | How a zone world is generated (tiles, roads, anchors, liquids, landmarks) and retired |
| [storm-and-gateway.md](storm-and-gateway.md) | The collapse timer, storm wall, conditions, ARC Device, gateway and the trip home |
| [story.md](story.md) | The main quest chain, side quests, how quest steps reach the HUD |
| [ui.md](ui.md) | The Fabricator and map menus: full-width layout, the drag-and-zoom canvas, the Logbook key opening the map |
| [garage.md](garage.md) | Garage world: power, launch pad, dumpster, fuel pump, Fabricator, towing |
| [gotchas.md](gotchas.md) | Engine limits we ran into and the workarounds (read before changing world/portal code) |
| [tuning.md](tuning.md) | Where every number you might want to change lives |

## Editors (open in a browser)

Double-click the file to open it in Edge or Chrome (they can save straight into
the mod folder). After saving, clear `Cache/` before launching.

| Editor | Edits | Saves to |
|---|---|---|
| **[Junction Map Editor](../Tools/map_editor.html)** | A hand-made junction map: where each junction is, how they connect, what kind each one is ([junctions.md](junctions.md#hand-made-maps-toolsmap_editorhtml)) | `Maps/map_layout.json` (new saves) |
| **[Fabricator Tree Editor](../Tools/fabricator_editor.html)** | The Fabricator's tabs and upgrades: which recipes, their anchor costs, what needs what ([garage.md](garage.md#the-fabricators-upgrade-tree)) | `Fabricator/upgrade_tree.json` |

---

## The run loop

```
 GARAGE (GarageWorld)
   │  drive onto the launch pad on the garage junction
   │  → junction map opens, pick where to go
   ▼
 ZONE (ZoneWorld, a new world, or one from the zone pool)
   │  collect energy anchors, put them in the ARC Device, switch it on
   │  → a gateway opens far away, and the storm starts closing in on it
   │
   ├── drive into the gateway ──────────────► back to the GARAGE (exits of
   │                                           this junction unlock)
   ├── drive into a junction at the end of ─► a new ZONE, one junction deeper
   │   an exit road (if exits are unlocked)
   └── die / /home ─────────────────────────► respawn at the garage, car towed home
```

Every arrow is a **portal** (`sm.portal`), the same thing Survival's elevators
use. A portal has two openings (A and B), each a box in some world; calling
`transferAToB()` moves everything inside box A to box B, cars and players
included. See [gotchas.md](gotchas.md) for the rules portals need.

The state of a trip lives in `self.sv.run` in `Game.lua`:

| `run.state` | Meaning |
|---|---|
| `idle` | In the garage, no trip |
| `departing` | Portal set up, waiting ~3 s (`DEPART_DELAY_TICKS`) for the landing spot, then transfers |
| `inZone` | Exploring; storm timer running |
| `returning` | Drove into the gateway; portal is being built, transfers 12 ticks later |

---

## Where the code is

All scripts are in `Scripts/`. The game script is loaded from `Game.lua`; most
other files add to the same `Game` class or are loaded by the world scripts.

| File | What it is |
|---|---|
| `Game.lua` | **The game script** (class `Game`, extends Survival's `SurvivalGame`). Run state machine, departures, returns, storm timer and damage, gateway placement, towing, chat commands. Creates the worlds. |
| `JunctionMap.lua` | Junction map data (server) and the map/Route Planner window (client). Adds `Game` methods. |
| `zone_pool.lua` | The zone pool: which zone world a junction gets, kept and used again so the save stops growing ([zones.md](zones.md#the-zone-pool)). |
| `Story.lua` | Main quest chain and the Expedition Checklist. Adds `Game` methods. |
| `HideoutFarmer.lua` | The farmer you talk to at the hideout (character in `Characters/Database/CharacterSets/example.characterset`) |
| `Dialogs.lua` | Phone calls through Survival's dialog manager (lines in `Gui/Language/English/Dialog/PacificDialogs.json`). Adds `Game` methods. |
| `DriveWorld.lua` | The two **world scripts**: `GarageWorld` (extends Survival's `Overworld`) and `ZoneWorld` (extends `BaseWorld`). Triggers, anchors, storm wall visuals, gateway beam, markers. |
| `layouts.lua` | **Settings** (most tuning numbers) and the tile layout generators for the garage and zones. |
| `conditions.lua` | Junction conditions (Perpetual Stability, Acid Rain, ...) and how they're rolled. |
| `terrain.lua` | Terrain script both worlds use: builds the world from a tile list, adds gentle hills. |
| `tilepack.lua` | Packs tile lists small enough for world creation data (64KB limit). |
| `map_sites.lua` | Generated: every place on the map a junction can be. Made by `Gui/make_map.py`. |
| `survival_patches.lua` | Runtime tweaks to Survival scripts (carry-to-insert anchors, logbook key opens the map, render settings, weather, no raids). |
| `ArcDevice.lua` | The ARC Device part. |
| `Fabricator.lua` + `upgrade_tree.lua` | Upgrade tree bot: spend anchors to unlock Craftbot recipes. `upgrade_tree.lua` loads the tree from `Fabricator/upgrade_tree.json`. |
| `RoutePlanner.lua` | Garage console that opens the map in planner mode. |
| `FriendlyDumpster.lua` | Garage loot box, refills after each trip. |
| `FuelPump.lua` | Garage gas canister dispenser. |
| `ZoneTornadoes.lua` | Survival's tornadoes, running in the zone. |
| `Bunny.lua` | A bunny: chases a driven car, circles it, latches on (unit and character). |
| `ZoneBunnies.lua` | Puts bunny groups in zone cells; draws the latched ones on cars. |
| `StoryQuests.lua`, `Zone*Quest.lua` | Quest objects: they only mirror text the game script publishes onto the HUD tracker. |
| `Player.lua` | Survival player plus loading blueprints onto the lift. |
| `wide_gui.lua` | Stretches the Hideout-style menu across the screen (Fabricator, map). |

Other folders that matter:

| Path | What |
|---|---|
| `Objects/Database/ShapeSets/example.shapeset` | Our parts (ARC Device, anchors, Fabricator, dumpster, fuel pump, ...) |
| `ScriptableObjects/ScriptableObjectSets/example.sobset` | Our quests (uuids must match `QUESTS` in `Game.lua`) |
| `Terrain/Tiles/*.tile` | Our editable tile copies: `garage`, `junction`, `garage_exit_128` (`garage_exit`: the old one), `packingstation_veg/fruit`, `hideout` |
| `Gui/make_map.py` | Makes `Gui/RouteMap.png` and `Scripts/map_sites.lua` |
| `BuilderGuides/make_antenna.py` | Writes the antenna guides (the ghost builds for Raise the Antenna and Boost the Signal) from `Blueprints/antenna_*.blueprint` |
| `Tools/map_editor.html` | Junction map editor (see [Editors](#editors-open-in-a-browser)) |
| `Maps/map_layout.json` | Optional hand-made junction map; new saves use it |
| `Tools/fabricator_editor.html` | Fabricator tree editor (see [Editors](#editors-open-in-a-browser)); its item list is `Tools/fabricator_catalog.js`, made by `python Tools/make_fabricator_catalog.py` from the game's files |
| `Fabricator/upgrade_tree.json` | The Fabricator's tabs and upgrades |
| `CraftingRecipes/craftbot_core.json` | Our copy of the Craftbot's core recipes, loaded instead of Survival's (`Game.loadCraftingRecipes`): Ember = 10 scrap wood + 2 gas canisters |
| `Objects/Mesh`, `Objects/Renderable` | Our resized copies of Survival models (anchors: half-size molten orbs; anchor pedestal: the barracks column base at 2x). `python Tools/fbx_scale.py in.fbx out.fbx 0.5` makes a scaled copy of a binary FBX. Our own models (Fuel Pump, ARC Device) use **Survival's textures**: their `.rend` points at the game's files, nothing is copied |
| `Tools/blender/` | Blender scripts for our own models: `sm_import` loads vanilla `.dae`/`.fbx` models with their `.rend` textures and paint; `sm_kit` puts vanilla texture areas ("trims") on new geometry; `sm_export` writes the `.fbx` (1 unit = 1 block, Y up) and a `.rend`. The `.blend` files (`Tools/Models/`, not shipped with the mod: too big) held the vanilla references and the loose pieces cut from them (`sm_kit.pieces`); the Fuel Pump and ARC Device are our own shapes (collections `GasPump` / `ArcDevice`) textured from vanilla sheets, with vanilla pieces swapped in where one fits (stand, screens, connectors, bolts, anchor port, dish). They were rebuilt with the text blocks `fp_hybrid.py` / `arc_hybrid.py` and exported with `kb_export.py` |
| `Gui/Language/English/inventoryDescriptions.json` | Item names and descriptions |
| `Tools/make_icon_mod.py` | Item icons: the Mod Tool's icon generator runs out of graphics memory on the whole mod (blank textures, ~20 min), so it makes a small local parts mod, `Mods/PacificScrap_Icons`, to create the icons in, then `collect` copies `Gui/IconMap.png/.xml` back. Never uploaded. |
| `Render/zone.rendersettings` | Zone fog look |

## How the pieces talk

Scrap Mechanic scripts are separate objects that can't call each other
directly. They send events:

- `sm.event.sendToGame( "sv_e_something", params )`: a world or part tells the game script.
- `sm.event.sendToWorld( world, "sv_e_something", params )`: the game tells a world.
- `self.network:sendToClients / sendToClient / sendToServer`: server ↔ client inside one script.
- Globals (`g_garagePowered`, `g_garageTrips`, `g_storyMaxDepth`, `g_arcDevices`, ...):
  all server scripts share one Lua state, so the game publishes values in
  globals that parts and worlds read. Client scripts share a different state.

Naming convention: `sv_` runs on the server, `cl_` on the client, `_e_` is an
event from another script, `_n_` is a network call from the other side.

## Logs

The game writes a new log every launch to
`D:\steam\steamapps\common\Scrap Mechanic\Logs\game-<date>-<time>.log`. Our
lines start with `[PacificScrap]`; Lua errors show the script and line.
