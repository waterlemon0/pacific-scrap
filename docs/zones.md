# Zones

Code: `CreateZone` in `Scripts/Game.lua`, the generator `ZoneLayout` in
`Scripts/layouts.lua`, the world script `ZoneWorld` in `Scripts/DriveWorld.lua`,
the terrain script `Scripts/terrain.lua`.

## One trip, one zone world

Every time you head to a junction, `Game.sv_resetZone` calls `CreateZone`,
which either builds a **new world** with `sm.world.createWorld( DriveWorld.lua,
"ZoneWorld", data, seed )` or, with the zone pool on, uses one made before (see
[The zone pool](#the-zone-pool)). The old zone is **retired**, not deleted (see
[gotchas.md](gotchas.md) for why).

The zone is 32×32 cells of 64 m = about 2 km square (`ZONE_CELL_MIN/MAX`).

### What CreateZone decides

Mostly copied from the junction node (see [junctions.md](junctions.md)), so the
zone matches what the Route Planner showed:

- conditions (until the first escape, `stable` is forced on: no collapse timer)
- anchor count and kinds (`node.anchors`)
- biome
- ruins (from `node.buildings`; the first junctions have at least `ZONE_MIN_BUILDINGS`)
- loot: junctions up to `START_LOOT_DEPTH` (2) get `startLoot`, so the terrain
  tags their cells `STARTAREA` (`GetTagsForCell`) and Survival fills their ruin
  chests and crates from its starting-area pools; deeper ones get the normal pools
- shacks, water, oil, chemicals levels
- locked? → only 1 exit road
- landmark? → reuse its saved world if it has one

It stores the zone's settings in `self.sv.saved` (`zone`, `depth`, `biome`,
`zoneConditions`, `zoneStability`, `zoneStorm`, `zoneNoExit`, `zoneLocked`,
`zoneSpawnCells`, `zoneLiquidCells`).

## The layout generator (`ZoneLayout`)

Everything is built from **Survival's own 64 m tiles**, picked and rotated per
cell the way Survival's map generator does it. The result is a list of
`{ path, x, y, size, rotation }`.

Steps:

1. **Roads** (`GenerateRoads`)
   - `BuildLoop`: 9–11 random points in a ring round the middle, joined by
     L-shaped stretches, dead-end stubs trimmed so a closed loop remains.
   - `BuildExit` × 2–4 (`ZONE_ROAD_EXITS_MIN/MAX`, or 1 if exits are locked):
     a road wandering from the loop to the map edge in a random direction,
     sometimes sidestepping. Its last cell becomes a **junction**
     (`Terrain/Tiles/junction.tile`, rotated so its opening meets the road).
   - A straight cell near each exit's outer end is a **spawn cell**: you land
     there, facing inward, as if you'd just come from that junction. That
     junction is your "entry junction" and does nothing when driven into.
2. **Biome corners** (`GenerateCorners`): each grid corner is biome (1) or
   meadow (0), patches of biome plus the map border. A cell's four corners pick
   the edge tile (e.g. `Forest(0011)`).
3. **Anchor cells** (`PickAnchorCells`): next to a road, spread out.
4. **Ruins**: a few rolls, each placing a 64 m ruin in a cell beside the roads.
5. **Shacks** (farmer kiosks) and **road chemical plants**: these are road
   tiles, so they *replace* a straight road cell (`PickRoadPoiCells`).
6. **Liquids**: ponds (four lake-edge tiles around one corner), 128 m chemical
   lakes, oil pools. Their cells go in `liquids` so gateways avoid them, and in
   `flats` so the hills stay level under them.
7. Every remaining cell: junction / extra / ruin / road tile / meadow / deep
   biome / biome edge.

Road tiles are chosen by `RoadTileFor`: openings (s, w, n, e) plus corners,
matched with rotation by `FindRotatedTile`. Open-ground roads have every shape,
so they're the fallback.

### Landmarks

`LANDMARKS` in layouts.lua: Vegetable/Fruit Packing Station (depth 2) and the
Farmers' Hideout (depth 4). A landmark zone puts the landmark's tile (our
editable copy in `Terrain/Tiles/`) in the middle with a **ring road** around it
(for the packing stations, the road runs through the tile's bottom row, as in
Survival). Landmarks are always Perpetual Stability with no gateway.

A landmark's world is **made once and kept**: `saved.landmarks[name] =
{ world, spawnCells, liquids, layout }`. Bump `LANDMARK_LAYOUT` to force them to
be rebuilt (e.g. after editing their tiles in a way old saves should get).

`ZoneWorld` runs Survival's `PackingStationManager` in landmark worlds so the
packing stations work.

### The Farmers' Hideout shop

The hideout landmark is Survival's hideout tile. Its trader (Survival's
`HideoutTrader.lua`) keeps its **vacuum**: crates dropped in the dropzone and
sucked in with the button go into the trader's container. Its menu and unlock
progression are replaced by `Scripts/hideout_shop.lua` (functions copied onto
`HideoutTrader` by `ApplySurvivalPatches`):

- the same full-width menu as the Fabricator ([ui.md](ui.md)), counters for
  all 8 kinds of crate and for caged farmers (Survival's farmer cages, which the
  vacuum takes too; `HIDEOUT_CRATES`, `farmer = true`) in the header, trades in
  the grid (`HIDEOUT_TRADES` in layouts.lua: item, quantity, cost in crates or
  farmers; a farmer buys 30 gas canisters);
- `sv_n_shopTrade` spends the crates from the trader's container and gives the item;
- every vacuumed crate sends `sv_e_crateDelivered` to the game (the Roadside
  Picnic quest); a caged farmer doesn't count.

### Tier differences in the zone

Per tier settings live in `ZONE_TIERS` (layouts.lua):

- **ground**: the Mid Zone's world class `ZoneWorldMid` (end of DriveWorld.lua,
  picked by `worldClass`) has its own ground material set with pink copies of
  the grass, weeds and hay textures (`python Terrain/make_ground.py`, then
  clear the cache). Ground paint (`paint`, `GetColorAt`) only shows on some
  textures (hay), not the grass ones, so paint alone can't make it pink.
- **foliage**: the Mid Zone's grass types are swapped for the chemical tiles'
  pink plants (`GetClutterIdxAt`; clutter numbers are Data's `clutter.json`
  list followed by Survival's: 41/43 seaweed, 103 violet weed), and bushes'
  `leaves`/`bark` colours and trees' colours are set from the chemical tiles'
  pinks (`GetAssetsForCell` / `GetHarvestablesForCell`).
- **biome, liquid, hills**: Outer and Mid are forest + meadow (Mid with less
  forest, `biomeShare`). Deep is all burnt forest with very steep hills: it
  uses the `mix` path (whole-cell biomes, no meadow) with burnt both ways, which
  falls back to an open-ground road tile for any road shape the biome has no
  tile for. Each tier
  rolls one liquid (`liquid`: Outer water, Mid chemicals, Deep oil;
  `RollLiquids` in JunctionMap.lua). Hills get higher per tier (`hills`) and
  12% per junction further in (`HillsFor`).
- **wetland**: most of a Mid Zone is flooded with chemicals, and now and then
  (`chance`, rolled with the junction as `node.wetland` so the Route Planner shows that liquid at MAX) an Outer Zone with water or a Deep Zone with oil (`wetland`: `liquid`,
  `share` of the cells by chemicals level, `cover`, `depth`). `ZoneLayout` picks
  flooded cells in big connected stretches (a smoothed random field, never on
  landing spots or anchors, and a cell clear all round junctions, buildings
  and other liquids, whose tiles would otherwise cut a square into it) and sends them
  as a bitmap (`wet`, one character a cell: small in the world data). In
  terrain.lua a flooded cell is level ground like a flat spot, and touching ones
  share one height (`LevelGroups`), so the liquid sits level; the ground dips
  up to `depth` (1.6 m, the Outer Zone 1.2 m: the liquid a little shallower) in blobby patches, sloping in as gently as `WETLAND_SLOPE_SOFTNESS` (`wet.soft`, new zones only; older ones keep the steep 0.12) (`WetDip`, fading out near dry cells so the
  liquid never shows at an edge); each flooded cell gets a chemical surface
  asset and a `CHEMICALS` node over the whole cell, just under the level ground
  (`PoolsInCell`, `WetSurface`), so the liquid shows where the ground dips, over
  roads too. `WetBerm` (in `GetHeightAt`) keeps the ground at least just over
  the liquid everywhere in a flooded cell and 1.5 m past its edges, before the
  dips: a tile's own low spots would otherwise show the liquid as a floating
  sheet, with the box's side sticking out over lower ground next to it. Past
  the edge it slopes back down over a wandering 6-18 m (`WET_BERM_SLOPE`), and
  the shore comes from the cells' wet/dry blended between their centres and
  looked up a little off the spot (`WetDip`: diagonals, round corners, a
  wandering edge), so neither shows the square cells. Older Mid Zones have `pools` instead (scattered round ones,
  `PoolDip`).
- **enemies**: robots placed as cells first load (`ZoneWorld.sv_spawnEnemies`):
  Mid = green / yellow / red tapebots, Deep = blue tapebots and miner bots.
- **seeds**: Survival's seedbots (the totebots carrying seeds) carry the
  tier's seeds (`SEEDBOT_SEEDS`: Outer tomato, potato, carrot, beetroot; Mid
  banana, blueberry, orange; Deep broccoli, pineapple; potato in every tier;
  each with a few of the tier before's). `PatchedSeedbotCreate` (survival_patches.lua) replaces
  Survival's pick as a new seedbot starts in a zone world.
- **arrival safety**: the cells where you land load *before* you're moved into
  the zone, so a player-distance check sees nobody there. So our robots and mines
  only spawn in cells created while someone is in the zone (`sv_anyPlayerHere`),
  and for `ZONE_ARRIVAL_CLEAR_SECONDS` after each arrival `sv_clearArrival`
  removes any robot (`g_robots`, Survival's ruin ones too) within
  `ZONE_ARRIVAL_CLEAR_RADIUS` of a player.
- **missiles**: see [storm-and-gateway.md](storm-and-gateway.md).

`/testtier <outer|mid|deep>` makes new zones count as that tier (`g_testTier`
in `ZoneTierOf`).

### Collapsed junctions

`node.collapsed` changes every time you come home (`sv_jmRollCollapses`, called
from `sv_jmReturnHome`): the old ones clear and `COLLAPSED_PER_RETURN` others
collapse, picked from the furthest `COLLAPSED_FURTHEST` rings on the map past
the Outer Zone (depth 2+, never a landmark or dead end). The Outer Zone mostly
has none: only with `COLLAPSED_OUTER_CHANCE` (15%) a return home does one of
its furthest junctions collapse, never more than one. A junction set to Collapsed in the map editor
always is (`handCollapsed`). A collapsed junction has no stable exits (pass
through; `JunctionExitsOpen` / `JunctionNoExit` count it as no-exit without
changing `noExit`), and when you arrive the storm has
already closed in all the way, so you're in it everywhere, taking
`COLLAPSED_DAMAGE`; missiles only start after `COLLAPSED_MISSILE_GRACE`
seconds. Supply pods lie about (`COLLAPSED_POD_CHANCE` per cell, their loot one
tier better). On the map a collapsed junction is shown even unscanned: red, a
wide red ring, DANGER / ZONE COLLAPSED under it, red roads into it, and a
DANGER banner in its info.

### Terrain and hills

**Edge**: `EdgeHeight` in terrain.lua raises a rim over the last `width`
metres inside the map (except around junctions, passed as `edge.clear`) and
mountains beyond it, where the ground is rock (`ZONE_EDGE`; the garage gets
mountains only, `GARAGE_EDGE`). The flat-spot blending includes it. Both
worlds are `WORLD_RING` cells bigger than the playable area, filled with deep
forest (`ForestRing`), so the mountains have trees; `edge.bounds` is the
playable area. Nothing spawns in the ring.

`terrain.lua` turns the packed tile list into the world (it's the terrain
script for both worlds). It adds gentle rolling hills (`ZONE_HILLS =
{ amplitude, scale }`) and flattens circles listed in `flats` (liquids, the
landmark, and every ruin, farmer shack and junction cell) so water doesn't
float and buildings sit level. Flat spots that touch share one height
(`FlatHeights`: the average of their centres), so side-by-side ruins are level
with each other rather than sloping between. Voxel (diggable) terrain is off.

Tile lists are packed by `tilepack.lua` because world creation data over 64KB
corrupts the save (see [gotchas.md](gotchas.md)).

## The ZoneWorld script

`ZoneWorld` (DriveWorld.lua) runs inside each zone:

- `server_onCreate`: tells the game it's ready (`sv_e_zoneReady`, used when
  resuming a saved run), sets up anchors from `data.anchors`, creates a tall
  thin **area trigger** at each junction's pad spot.
- `server_onCellCreated`: the first time a cell loads it spawns that cell's
  **anchor pedestal** (`sv_spawnAnchor`: a static pedestal plus a dynamic anchor
  on top, on open terrain), Minefield totebots, measures junction floors.
- `sv_updateAnchors` (every 10 ticks): an anchor is collected when its part is
  gone and someone nearby carries an anchor (or its cell is loaded). Publishes
  `g_zoneAnchorsLeft/Total` and sends beacon markers.
- `trigger_onJunction` → `Game.sv_e_zoneJunction` (ignored for the entry junction).
- `sv_trackSpots`: remembers each player's last position and car, for towing.
- Gateway trigger, storm wall, countdown HUD, music, gateway hum: see
  [storm-and-gateway.md](storm-and-gateway.md).

### Landing

`Game.sv_pickLanding` picks a spawn cell and loads it with a handle;
`ZoneWorld.sv_e_findLanding` raycasts for ground on the road (or open terrain);
`Game.sv_e_onLandingFound` sets the departure portal's opening B there, facing
inward. `sv_finishDeparture` transfers once it's set (retrying every second).

## The zone pool

`ZONE_POOL` (layouts.lua, `Scripts/zone_pool.lua`).

### Why

Before the pool, every junction you drove to got a brand new world. Each one
stayed in the save for good, so the save grew with every hop and never
shrank. Measured on real saves, a zone world you've driven through costs
**about 2 MB** (a save with 11 zone worlds was 22 MB), almost all of it the
trees and rocks the game records for every cell that has loaded. A long
playthrough would reach hundreds of MB, and big saves load slowly.

**Why not just delete old worlds?** We tried everything Scrap Mechanic offers
(details in [gotchas.md](gotchas.md#worlds-and-saves)):

- `world:destroy()` doesn't remove the world's contents from the save file.
  The leftovers stay behind, and loading a save with them **hangs**.
- Emptying a world first (removing its trees, parts and units) doesn't shrink
  the save either: every removed tree is kept as a "removed" record, so the
  data stays about the same size. It's also slow.
- A world can't be unloaded while the game runs; it only leaves memory when
  the save is reloaded and nothing loads it again.

So a world, once made, is in the save for good. The only way to stop the save
growing is to **stop making new worlds**: keep a fixed number and use them
again. That's the pool.

### How it's sized

Zone worlds are pooled by zone depth (`ZonePoolKey`: `NodeZoneDepth`, plus
whether it has the starting-area loot, which is built into the world), up to
`ZONE_POOL_SIZES` each: **10, 8, 6, 5, 4, 3, 3, 2, 2** for zone depths 1 to 9
(deeper ones use the last). Until a pool is full a trip there makes a new
world, which joins it; then the world used longest ago comes back.

- **The pools fill by trips, not by junctions.** Every trip starts at a
  junction one out of the garage, so the first pool gets a new world every
  trip until it's full, however few junctions the map has there. The deeper
  pools fill more slowly because you go there less.
- **The first pools are the biggest** because that's where you spend most
  trips, so repeats would show most there. Deep junctions are rarely visited,
  so a couple of worlds each is enough.
- **The cost**: at most 43 worlds, so **about 85 MB** once every pool is full
  (a playthrough takes a long time to get there). Bigger pools were weighed:
  20 for the first depth (63 worlds) would be about 125 MB, and 50 (93 worlds)
  about 185 MB, for little gain.
- **Repeats don't feel the same**: you arrive by a different exit road, and
  the anchors, conditions, robots and collapse are new every trip (below). With
  10 first-depth worlds a layout comes back about every 10 trips.

`saved.zonePool[key]` holds the records: `{ id, world, biome, buildings, water,
oil, chemicals, spawnCells, liquids, used }`.

### Turning it off

`ZONE_POOL = false` in layouts.lua: every trip makes a new world again, exactly
as before. All the pool code checks it, and worlds made without the pool
never get a trip (below), so nothing new runs. Pooled worlds already in the
save are left alone; switch it back on and they're used again. Saves made
before the pool keep their old zones (they can't be removed); the pool fills
from the next trip.

### What a world keeps, and what the junction takes on

A world's ground, tiles and road layout are fixed when it's made (the
terrain comes from its creation data). **What a world keeps**: its ground, roads (a pooled world always has all its
exit roads; locked exits refuse you at the junction and get no markers),
buildings, liquids and biome. So a junction takes those on: when it's rolled
(`RollJunction` clears `node.poolPicked`), `Game.sv_zonePoolAssign` (run at
the end of `sv_jmGrowOpen` and after a re-stabilize) picks its world: a new
one while the pool has room (counting junctions already planning one), else
the least recently used one no other junction has, copied onto the node
(`ZonePoolAdopt`), so the Route Planner shows what you'll find.
`ZonePoolTake` (in `CreateZone`) uses it, never the zone being left.

### What's new every trip

`CreateZone` puts it in `saved.zoneTrip` /
`g_zoneTrip` (`{ id, world, depth, zone, conditions, anomalies, collapsed,
locked, anchors }`). The world picks it up whenever it notices
(`ZoneWorld.sv_checkTrip`: its script starting, a cell loading, every 10
ticks) and `sv_startTrip` starts afresh: wakes up if retired (triggers back,
clients told with `cl_n_newTrip`, which also drops the last trip's storm
lighting and fog), picks this trip's anchors from the world's
`anchorSpots` (`ZONE_POOL_ANCHOR_SPOTS` of them, chosen when it was made),
clears towing spots, gateway and tornadoes. `sv_trip()` is what the world
reads for depth, conditions and collapse (a world made without the pool:
its own data).

### Per cell

Our spawns used to run only on a cell's *first ever* load
(`server_onCellCreated`), which never happens again in a reused world.
`sv_tripCell` runs on a cell's first load each trip
(`saved.tripCells`): it clears what earlier trips left there
(`sv_clearLeftovers`: lone anchors, pedestals, supply pods, our robots and
mines; nothing built into a creation) and puts down this trip's anchors,
robots, mines and pods. Survival refills its own ruin loot as cells load.
Anything else players left (an abandoned car) is still there next time.

### Things that bit us while testing

- On a garage departure the last zone was skipped as "the zone being left",
  so with a pool of 1 a second world was made. Only a zone left through a
  junction (`keepOld`, players still inside) is avoided now.
- The garage retires the last zone just before picking the next, which can be
  the same pooled world: `sv_e_retire` ignores the current zone
  (`g_currentZone`).
- To test reuse quickly, set every pool size to 1 for a while.

## Retiring a zone

Scrap Mechanic can't unload or safely delete a world. So `Game.sv_retireZone`
sends `sv_e_retire`: the zone saves `retired = true`, destroys its triggers,
gateway and tornadoes, and clients destroy its effects. `server_onFixedUpdate`
does nothing in a retired zone. Nothing ever loads it again, so after the next
save reload it's out of memory. It stays in the save file (about 2 MB for one
you've driven through, mostly trees), which is why the zone pool exists.

Landmark worlds are never retired. A pooled world is retired like any other
and woken up again when its next trip starts.

When leaving through a junction, the old zone is kept until everyone has been
carried out (`keepOld`), then retired `OLD_ZONE_RETIRE_DELAY` later;
`sv_rescueLeftBehind` brings along anyone who missed the portal.
