# Junctions and the map

Code: `Scripts/JunctionMap.lua` (server half at the top, the map window at the
bottom), helpers in `Scripts/layouts.lua` and `Scripts/Story.lua`.

## The big idea

The map is a **tree**. The garage is the root (node `id = 1`, depth 0). Every
junction leads on to 1–2 junctions one step deeper (the garage always to 2).
"Depth" is how many junctions away from the garage it is, and it drives
almost everything: biome, gateway cost, storm speed, anchor quality, which zone
tier it belongs to.

```
            depth 3   [G5]   [F4]   [E6]
                        \    /        |
            depth 2     [G2]        [E3]   (VP) ← landmark side branch
                           \        /  /
            depth 1        [G1]   [E1]
                              \   /
            depth 0         GARAGE
```

All of it is saved in `self.sv.saved.map`:

```lua
map = {
  nodes = { [id] = node, ... },
  nextId = 17,        -- next id to hand out
  current = 4,        -- where you are (1 = garage)
  destination = 9,    -- planned with the Route Planner, or nil
  charges = 3,        -- scanner charges left this trip home
}
```

A **node** (one junction):

| Field | Meaning |
|---|---|
| `id`, `parent`, `children` | Tree links |
| `depth` | Steps from the garage |
| `code`, `mapName` | Label on the map ("E3", "BACK ROADS") |
| `biome` | forest / autumn / field / burnt / desert |
| `mx`, `my`, `site` | Position on the map picture, and which premade site it took |
| `visited`, `scanned` | Been there / its details are known |
| `cleared` | **Escaped through a gateway here once** → its exits are unlocked |
| `noExit` | "No stable exits": the ARC Device can't open a gateway here, you must drive on |
| `deadEnd` | No gateway *and* no way on (only appears as a 2nd child, so you're never stuck) |
| `collapsed` | Already collapsed: storm everywhere, no gateway, drive through; supply pods. Re-picked every return home, the furthest junctions ([zones.md](zones.md)) |
| `landmark` | `"veg"`, `"fruit"`, `"hideout"`, or nil |
| `conditions` | List like `{ "fog", "rapid" }` (see `conditions.lua`) |
| `stability`, `storm`, `anomalies`, `atmosphere`, `buildings` | Route Analysis meters (0–100 / 0–4) |
| `water`, `oil`, `chemicals` | Liquid levels 0–4 |
| `anchors` | Exact anchor kinds the zone will spawn, e.g. `{ "stable", "unstable" }` |

## How the map grows

`Game.sv_jmGrow( node, levels )` gives a junction its children if it has fewer
than `MAP_CHILDREN[1]`:

1. Roll a biome (sometimes the next depth's, `MAP_BIOME_SPREAD`), a map name, a code.
2. Roll dead end / no exit (`DEAD_END_CHANCE`, `NO_EXIT_CHANCE`).
3. `RollJunction` rolls everything re-rollable: conditions, stability, meters,
   liquids, anchors.
4. `PlaceJunction` finds it a spot on the map (below).
5. If no free site was found, the child is dropped, except the first one,
   which always exists so a junction always has a way on.

It also adds **landmarks**: each landmark in `LANDMARKS` (layouts.lua) appears
once on the map, as an *extra* child of a junction one shallower than the
landmark's depth. Landmarks don't count toward the 1–2 normal children.

`Game.sv_jmGrowOpen()` is called whenever something changes. It grows one
level ahead of every junction you can reach with open exits, plus where you
are (so you can see what's behind locked exits), and repeats until nothing new
appears (because "no exit" junctions are pass-through, they open further
growth).

## Where junctions sit on the map (premade sites)

Like Pacific Drive, the map has a **fixed set of places**. `Gui/make_map.py`
generates them once into `Scripts/map_sites.lua`: about 45 sites, each with
`{ x, y, d = depth, code }`. The picture `Gui/RouteMap.png` is drawn by the
same script so the tier rings line up.

- Map units: garage at (0, 0), the zone's core 2300 units "north" at (0, −2300).
  Each depth is `MAP_DEPTH_STEP = 220` closer to the core.
- Region letters: Outer G/E/F, Mid D/C/B, Deep A. Numbered outward from home.

`PlaceJunction( map, node )` picks, among free sites of the right depth within
`MAP_SITE_REACH` of the parent and not within `MAP_KEEP_APART` of another
junction, the nearest one whose road doesn't cross an existing road. The node
takes that site's `code`. If none fits it falls back to a spot towards the core
(only the first child is kept in that case).

To change the map layout: edit `SITE_SPACING` etc. in `make_map.py`, run it
(`python Gui/make_map.py`), and it rewrites both files. Existing junctions keep
their positions.

### Hand-made maps (`Tools/map_editor.html`)

Instead of the random map, you can draw one: open `Tools/map_editor.html` in a
browser (Edge/Chrome save straight into the mod), place junctions on the
picture, connect them into a tree from the garage and pick what each one is.
Save it as **`Maps/map_layout.json`** (`MAP_LAYOUT_FILE`).

- Only a **new save** uses it: `sv_jmMap` sets `map.layout` when it makes the
  map, and the garage gets `layoutId = 1`. Older saves stay random.
- `sv_jmGrow` asks `LayoutChildren`: if the layout has junctions after this
  one, those are made (`LayoutJunction`, remembering `node.layoutId`) instead
  of random ones. Trimmed junctions come back the same, at the same spot.
- Per junction, anything not picked by hand is rolled as usual: `kind`
  (`random`/`normal`/`noExit`/`collapsed`/`deadEnd`), `biome`, `landmark`,
  `buildings`, `name`, `code`, `conditions` (fixed ones are kept in
  `node.fixedConditions` and `RollJunction` uses them every time).
  `handBiome`/`handBuildings` stop the older-save fix-ups changing them.
- A junction's **number** (`node.depth`, "JCT 3") is how many junctions along
  the road from the garage it is, the shortest way (`layout.hops`, worked out
  when the layout loads). Difficulty goes by it (gateway cost, stability,
  anchors, conditions, storm speed) and so do the story's goals (escape at JCT
  3, 6, 9: `story.deepest`).
- Its **zone** is the ring area it sits in on the picture (`MapDepthAt`):
  `node.zoneDepth` = its number kept inside that zone's range (`ZoneDepthFor`),
  read with `NodeZoneDepth`. The zone's look, biome, liquids, robots,
  missiles, storm damage, music and supply pods go by it (`saved.zoneDepth`,
  the zone world's `data.zone`), and so does unlocking: `WithinTiers` and
  `JunctionExitsOpen` keep junctions in zones the story hasn't opened out of
  reach (`Reachable`, `sv_jmDestination`).
- **Roads can merge**: a layout junction's `also` lists more junctions with a
  road into it. On the map it's one junction with `node.parents` (`parent` is
  the first); growth links the second road to the junction already there.
  Everything that used to walk back along `parent` goes along the roads
  instead: `RouteTo` (the way from one junction to another), `IsAhead`,
  `Reachable` (some open way from the garage), `Ancestors` (trimming), and
  `map.trail` remembers the way you actually came this trip (drawn on the map).
  Still one way only: no loops, you never drive back.
- Past a layout junction with no roads on (and not a dead end), the map goes on
  as a random one. Landmarks the layout doesn't place are added as usual.
- Editing the file moves existing junctions of a hand-made save to their new
  spots; layout ids must never be reused (the editor keeps counting up).

## Locked and unlocked exits (the Pacific Drive rule)

A junction's exits are **locked until you escape it through a gateway once**.
So each successful trip pushes the frontier one junction further.

```lua
function JunctionExitsOpen( node )
  if node.id == 1 then return true end                       -- garage: always open
  if not LeadsOnWithinTiers( node ) then return false end   -- no road on into an opened zone
  return node.cleared or ( node.noExit and not node.deadEnd ) -- escaped, or pass-through
end
```

- `node.cleared` is set in `Game.sv_jmReturnHome( escaped = true )`, called by
  `sv_endRun` after a gateway return.
- `g_storyMaxDepth` comes from the main quest (see [story.md](story.md)): the
  last depth of the last unlocked tier. So at the edge of the Outer Zone you
  can't drive on until the story unlocks the Mid Zone, unless a hand-made
  map has a road from there to a junction still inside the open zones
  (`LeadsOnWithinTiers`; the Farmers' Hideout sits at the Outer Zone's edge).
- A landmark the story shows you (the Farmers' Hideout, once the farmers have
  called: `g_storyRevealedLandmarks`, Story.lua): the junction right before
  it counts as escaped, so its exits are open (`OpenRevealedLandmarkRoutes`,
  run by `sv_jmGrowOpen`). The ones before that you open as usual.
- `JunctionNoExit( node )` = no-exit **only while its exits are open**. At a
  tier edge the exits are locked, so a "no exit" junction gets a gateway after
  all; otherwise you'd be stuck with no gateway and no road out.
- `Reachable( map, id )` = every junction on the path from the garage has open exits.

What locked exits mean in the zone: the zone generator only makes **one** exit
road (the one you arrive by) and driving into a junction says "Exits locked".
See `Game.sv_e_zoneJunction`.

## Pruning and trips home

- `sv_jmArrive( id )`, when you arrive: marks visited/scanned, sets `current`,
  triggers the story's landmark quest, prunes, grows.
- `sv_jmPrune()` keeps only: the garage, the route to where you are, anything
  reachable, and the children of where you are. Everything else is forgotten
  (it will regrow, re-rolled).
- `sv_jmReturnHome( escaped )`, back at the garage: `current = 1`, charges
  refill, every junction **re-rolls its conditions** and becomes unscanned
  (landmarks stay known). After a failed run, one of the garage's first
  junctions is made Perpetual Stability (and scanned).
- A map with more than `MAP_MAX_JUNCTIONS` (an old save, `/revealmap` spam) is
  cut back to the route in `sv_jmMap()`.

`sv_jmMap()` is also where old saves are migrated (missing fields filled in,
unplaced junctions placed, landmarks moved if their depth changed).

## Choosing where to go

When you drive into a junction (the garage pad or a zone exit) and
`JUNCTION_MAP_ON_ENTRY` is true:

1. `Game.sv_e_garageJunction` / `sv_e_zoneJunction` call `sv_jmBeginChoice`:
   the car is held still (`sv_e_stopBodiesNear` every 4 ticks) and the map opens
   in **travel** mode.
2. Clicking Travel sends `sv_n_jmTravel( id )`. If you picked something further
   than the next junction it becomes `map.destination`.
3. It calls the junction handler again with `chosen = true`, which actually
   departs. `sv_jmDestination()` returns the **next hop**: the child of
   `current` on the path to `destination`, or the first child.
4. Closing the map without picking (`sv_n_jmCancel`) gives you 5 s to drive off.

## Route Planner (garage only)

`RoutePlanner.lua` is a garage console; interacting sends
`sv_e_openRoutePlanner` → the same map window in **planner** mode:

- **Set destination** (`sv_n_jmSetDestination`, the main button): any reachable
  junction ahead, scanned or not, gateway or not.
- **Scan** (`sv_n_jmScan`, the second button on an unscanned junction): costs a
  charge (`SCANNER_CHARGES` per trip home, more with the antenna), reveals a
  junction's details and the route to it.
- **Re-stabilize** (`sv_n_jmReroll`): costs a charge, re-rolls conditions, removes
  Rapid Collapse, +20 stability, corrupted anchors become unstable.

Stability → seconds before collapse: `StabilityToSeconds = (16.2 × stability + 150) × STABILITY_TIME_SCALE`
(Pacific Drive's formula, shortened).

## The map window (client)

The full explanation (layout, drag and zoom, tabs, Logbook key) is in
[ui.md](ui.md). In short:

`Game.cl_n_junctionMap( data )` receives the node list (`sv_jmSend`, which hides
details of unscanned junctions) and builds the window from the Fabricator's
menu (`Gui/JsonGuis/Fabricator.gui`) via `BuildMapGui`. Modes: `planner`,
`travel`, `view` (`/junctionmap` or the Logbook key).

- The map is drawn in `cl_jmBuild`: background picture, curved dotted roads
  (bending around other junctions by `MAP_ROAD_CLEARANCE`), junction icons.
- Camera: `jmCam` (map point in the middle) and `jmZoom`; mouse wheel zooms
  toward the cursor using a grid of invisible `MapCell_x_y` buttons; drag pans;
  clicking a junction glides to it (`MAP_GLIDE`).
- In view mode there are MAP / QUESTS / BEACONS tabs with track buttons (the
  logbook's lists).
- The Route Analysis meters are drawn in the header (`cl_jmMeters`).

The picture path uses `$CONTENT_3c9f5e62-...` (the mod's localId) because menus
can't expand `$CONTENT_DATA`.

## Cheats

| Command | What |
|---|---|
| `/junctionmap` | Open the map to look |
| `/junction` | In a zone: unlock this junction's exits and open the travel map as if you drove into a junction |
| `/revealmap` | Scan everything and unlock every junction's exits, one more level each time (still stops at the story's tier edge; use `/skipquest`) |

## Revealed landmarks

A landmark the story reveals (the Farmers' Hideout, once the farmers have
called) goes on the map straight away even if the junctions before it haven't
been explored (`EnsureRevealedLandmarks`, run with `sv_jmGrowOpen`): off a
junction one shallower on a random map, or at its spot on a hand-made one along
with the junctions on the way. Those are shown locked until you can get there,
and pruning keeps them (`RevealedLandmarkRoutes`). Any junction you can get to,
gateway or not, can be the destination.
