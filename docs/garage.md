# The garage

Code: `GarageWorld` in `Scripts/DriveWorld.lua`, `GarageLayout` in
`Scripts/layouts.lua`, garage parts in their own scripts.

## The world

`GarageWorld` extends Survival's `Overworld`, so respawning, quests and
anything in Survival that looks for "the overworld" keeps working. The game
script saves it as `saved.overworld` for that reason.

Layout (`GarageLayout`), a 6×6 cell world (`GARAGE_CELL_MIN/MAX`):

- `Terrain/Tiles/garage.tile`: our editable copy of Survival's mechanic
  station (2×2 cells at 0,0). **The props are placed in this tile**: Friendly
  Dumpster, Fabricator, Route Planner, battery socket, battery. Edit it in the
  game's tile editor.
- `Terrain/Tiles/junction.tile` at `GARAGE_JUNCTION`: the junction you depart from.
- `Terrain/Tiles/garage_exit_128.tile` (2x2, north of the player spawn behind the station, cells 0..1, 2..3; `GARAGE_EXIT.tile`; arrivals face south): where you arrive back, at `GARAGE_EXIT.spot` in its clearing. New saves only.
  Behind (north of) the mechanic station, its road opening facing south
  towards it.
- Deep forest everywhere else.

Edits to these tiles show up in existing saves, except the layout itself:
which tile goes where is decided when the save is created.

## Power (Getting Started)

The garage socket is Survival's power core socket. `GarageWorld.sv_findSocket`
finds it; every second `server_onFixedUpdate` checks whether it's active. The
first time it is, `sv_e_garagePowered` → `saved.garagePowered = true`,
`g_garagePowered = true`.

Things that need power read `g_garagePowered`:

- junction pad (`sv_e_garageJunction` refuses: "The garage has no power")
- Fabricator and Route Planner (set `interactable.active` to it; the client
  shows "No power")
- Fuel Pump

The battery to use comes from the Friendly Dumpster: while the garage has no
power and nobody has a battery on them, opening it puts one in its chest
(`sv_giveEssentials`; the battery placed in the tile doesn't count). Until
then a quest marker points at the dumpster, then at the socket once someone
has a battery on them (`sv_powerMarker` → `cl_n_powerMarker`).

## Launch pad

The pad is a spot (`saved.pad.ground`) with a glowing disc, a thin tall
trigger (`PAD_TRIGGER_HALF_SIZE`) and a 12×12×8 m portal footprint
(`PAD_PORTAL_HALF_SIZE` in Game.lua). It's put on the junction tile's pad
spot automatically (`sv_e_junctionPadFound`, measured with `FloorAt`, which
finds the floor even under a roof). `/setpad` moves it.

Driving onto it: `trigger_onPad` → `Game.sv_e_garageJunction` → junction map
(travel mode) → `sv_depart`. Everything inside the pad portal box goes.

`JUNCTION_PAD_SPOT` (layouts.lua) is where in the junction tile the pad goes,
in tile editor metres; `JunctionPadPosition` rotates it with the tile.
`GARAGE_EXIT.spot` is the same for the exit.

### Junction gate

`junction.tile` has a kinematic door (`kin_door_mediumelevator`, placed closed,
`eventListen` = `JUNCTION_GATE_EVENT`, "opengate01", `saved` on). Kinematics
register with Survival's `KinematicManager` by tile cell, so the world scripts
find the gate in the junction's cell (`JunctionGates`) and check where it is:
open = moved off where it was placed. In the garage
(`GarageWorld.sv_updateJunctionGate`) it opens while a route is set or you're
setting off (`g_garageGateWanted`, set by the game) and shuts otherwise; each
`sv_e_activate` plays it to its other end, so it's only sent when the gate is
standing still at the wrong end. It only animates (with
`PacificScrap - GateAlarm` from the gate when opening) if a player is within
`GATE_WATCH_RANGE`; otherwise it's set straight to open or shut
(`sv_e_resetTrack`), so it's never saved half-way when the garage unloads
behind you (a reload replays a saved half-finished move). In a zone (`ZoneWorld.sv_openJunctionGates`)
every junction's gate is set straight to open (`sv_e_resetTrack` to the back).

## Garage parts

All are in `Objects/Database/ShapeSets/example.shapeset`, with restrictions so
they can't be lifted, erased or destroyed.

| Part | Script | What |
|---|---|---|
| Friendly Dumpster | `FriendlyDumpster.lua` | A chest window (its own container, like Survival's chests). First open: starter kit (`DUMPSTER_STARTER`). After every trip: restock (`DUMPSTER_RESTOCK`). When no car came home, after a failed run that towed none or an escape on foot (`g_carKitPending`, set by `sv_carKitPending` from `sv_e_recoverFound` and `sv_e_onGatewayReached`): a scrap car kit (`DUMPSTER_CAR_KIT`). On every open (`sv_giveEssentials`): an ARC Device if nobody has one, and the battery while the garage has no power, in the chest (on top only if it's full). Model: Survival's ruin chest. Lid open while empty. |
| Fuel Pump | `FuelPump.lua` | E = 5 gas canisters, 20 per stay at home, refills each trip. Needs power. Model: our own old-style gas pump (`obj_pacificscrap_fuelpump`, 4×8×3; its Blender source isn't shipped with the mod). |
| Fabricator | `Fabricator.lua`, `upgrade_tree.lua` | Upgrade tree. Deposit anchors (carry + click), spend them to unlock Craftbot recipes. Its model is the mini craftbot (the mechanic station workbench, `char_workbench`), animated like it (`cl_updateAnimation`: offline, turn on, idle and idle specials, a craft after each unlock, looking at you). |
| Route Planner | `RoutePlanner.lua` | Opens the junction map in planner mode (see [junctions.md](junctions.md)) |
| ARC Device | `ArcDevice.lua` | Mounts on your car (see [storm-and-gateway.md](storm-and-gateway.md)) |

"Refills each trip" works through `g_garageTrips` (`saved.trips`, +1 in every
`sv_endRun`): a part remembers which trip it was last emptied on.

Garage parts placed in the tile must be set to static in the tile editor. The game script can't create parts, so
cheats like `/dumpster` ask the garage world (`sv_e_placePart`).

### The Fabricator's upgrade tree

Edit it with the **[Fabricator Tree Editor](../Tools/fabricator_editor.html)**
(open it in a browser, then Open… `Fabricator/upgrade_tree.json`). It shows the
tree laid out like the game, with icons straight from the game folder, and
checks for mistakes (a requirement that isn't in the tree, loops, items with no
recipe).

The tree is `Fabricator/upgrade_tree.json`, loaded by `upgrade_tree.lua` into
`UPGRADE_TABS` and `UPGRADES`. Each upgrade has a `tab`, an `item` (whose
Craftbot recipe it unlocks, also its icon), a `cost` in anchor kinds, optional
`requires` (a list of items) and `extras` (more recipes); `name` is only there
to make the file readable. Unlocking uses Survival's `RecipeManager` (ids as
**strings**).

Anything Survival unlocks from the start (`SURVIVAL_DEFAULT_RECIPES`) that's
**in the tree** is locked until unlocked here: `LOCKED_DEFAULT_RECIPES`, worked
out when the tree loads, and `survival_patches.lua` swaps
`RecipeManager.sv_isUnlocked` / `cl_isUnlocked` / `cl_getUnlockedRecipes` (the
Craftbot grid uses that one). Take an item out of the tree and it's free again. The window is
the Hideout trader menu, stretched full width by `wide_gui.lua`, with a
zoomable, draggable tree.

### The abandoned car

The garage tile has Survival's `random_abandoned_vehicle` prefab. Its car
comes from our copies of the blueprints (`Blueprints/`, made by
`python Blueprints/make_cars.py`): still scrap wheels and scrap engine, the
engine's tank full (10 canisters). `UpgradeCar` in terrain.lua swaps the path
(garage world only). Every car spot has a car: in the garage the prefab's
empty variant (`random_abandoned_vehicle_01`, about half the time in
Survival) is left out (`garagePrefabTable`, `PrepareCell`; new saves). The real small wheel and gas engine are the first
Vehicle unlocks at the Fabricator.

The scrap parts are made less bad:
- **Scrap engine:** Survival's lets the wheels spin free when nobody drives
  or it's out of gas, so a parked car rolled away. `PatchedControlEngine` in
  survival_patches.lua holds them like the other engines.
- **Scrap wheel:** its bumpy custom collider made cars crawl. It's redefined
  in our shapeset (same uuid) with the small wheel's round one; it keeps its
  low durability.

## Arriving home

The gateway return lands at the exit tile (`sv_returnGround` = exit floor +
1.5 m). Other creations within `RETURN_GATHER_RADIUS` of the gateway (a
friend's car, loose parts) are towed home too, each through its own portal,
beside where the car comes out (`run.extras`, `sv_towToGarage`). Setting off
from the garage, players within `PAD_GATHER_RADIUS` of the launch pad but not
on it come along to the landing spot (`sv_bringNearPad`). A player who leaves a
run early while others go on (died and respawned, `/home`) gets their car and
things towed home straight away (`sv_towForLostPlayers` →
`sv_e_findRecoverables { player }`; nothing within 20 m of a player still in
the zone), beside the exit spot. A creation a player carries with the lift (the lift
tool reports it: `g_liftCarry`, survival_patches.lua) comes through
gateways, junctions and the launch pad with them, through its own portal set
up when the crossing starts and sent in the same moment as the player
(`sv_prepareCarried` / `sv_landCarried` / `sv_sendCarried`): a moment later
its area has unloaded and it's gone. Towed cars (failed run) land there too, spaced sideways. See
[storm-and-gateway.md](storm-and-gateway.md).

## Anchors come home as energy

Energy anchors can't stay anchors in the garage. Every 2 seconds
`GarageWorld.sv_bankAnchors` takes every anchor there: loose ones, ones on a
car, in an ARC Device, or carried by a player. It banks them into the
Fabricator (`Fabricator.sv_e_depositAnchors`) and shows what was banked. So a
trip always starts with an empty ARC Device (no stockpiling for the next trip),
and every anchor brought home becomes upgrade currency.

## Respawning

A player who dies without a bed respawns a few metres up the garage exit road,
facing the station (`Game.sv_setRespawn` sets `g_pacificRespawn`;
`survival_patches.lua` swaps Survival's `RespawnManager.sv_getSpawner`).

## New games

A new save starts at night (`INTRO_TIME_OF_DAY`) in a thunderstorm that lasts
until your first trip (`saved.introWeather`). New players get only Survival's
sledgehammer and lift; everything else comes from the dumpster.

## Cheats

With the developer switch on (`CHEAT_COMMANDS` in `layouts.lua`, on by
default; set it to false to hide them). `/where` always works.

| Command | What |
|---|---|
| `/dumpster` | Place a full Friendly Dumpster |
| `/fuelpump` | Put the garage's Fuel Pump back on its spot (`FUEL_PUMP_HOME` in layouts.lua), or a new one there if there's none |
| `/routeplanner` | Place a Route Planner |
| `/arcdevice` | Get an ARC Device |
| `/setpad` | Move the launch pad to where you stand |
| `/depart` | Depart without driving onto the pad (must be on it) |
| `/home` | Teleport home (the run ends if nobody is left in the zone; the car is towed) |
| `/where` | Print your position |

### Fabricator tabs and beds

The Fabricator's tabs are the game's own inventory categories: BLOCKS (wedges
come along as extras), PARTS, INTERACTIVE, CONSUMABLE, TOOLS. An item's
category comes from its shapeset: a block, a tool, a part marked `consumable`,
a part with an interactable (`scripted`, a seat, logic, light, chest, pipe,
spring, piston...), or else a plain part. Requirements can cross tabs (no line
is drawn; the panel says "Requires"). `Fabricator.lua` gives the .gui's tab buttons (left to right) the tree's
tab names and captions, so the .gui's own button names don't matter; it has 5
buttons, so only the first 5 tabs show. Most of Survival's default Craftbot
recipes are in the tree; consumables, food, scrap wedges and Craftbot upgrades
aren't, so they stay free. Beds don't set your respawn
(survival_patches.lua: `RespawnManager.sv_getPlayerBed` gives none, beds only
seat you): you always come back at the garage exit.
