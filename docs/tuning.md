# Tuning

Where the numbers live. Most are near the top of `Scripts/layouts.lua`.
Values below are the current ones.

## Difficulty: storm and timer (`layouts.lua`)

| Setting | Value | Effect |
|---|---|---|
| `STORM_STABLE_TIME` | 300 s | Calm time before collapse (when the junction has no stability value) |
| `STORM_WARNING_TIME` | 60 s | Alarm this long before collapse |
| `STORM_TIME_VARIATION` | 0.2 | ±20% per zone |
| `STORM_DEPTH_TIME_STEP` / `STORM_DEPTH_MIN_FACTOR` | 0.12 / 0.4 | Calm time −12% per junction, down to 40% |
| `STORM_SPEED` | 5 m/s | Wall speed after the timer runs out |
| `STORM_GATEWAY_SPEED` | 8 m/s | Wall speed once the gateway opens |
| `STORM_DEPTH_SPEED_STEP` | 0.15 | +15% wall speed per storm level |
| `STORM_GATEWAY_START_MARGIN` | 80 m | Head start beyond the farthest player when the gateway opens |
| `STORM_GATEWAY_START_MARGIN_BY_DEPTH` | 300 / 220 / 150 m | The same at JCT 1 / 2 / 3 (more room early on) |
| `STORM_GATEWAY_TIME_BY_DEPTH` | 180 / 150 / 120 / 100 s | Seconds the gateway's wall takes to close in at JCT 1 / 2 / 3 / 4+ (its speed = distance ÷ time, then the storm level and Rapid Collapse speed it up); replaces `STORM_GATEWAY_SPEED` for the gateway |
| `STORM_GATEWAY_SPEED_MIN` | 2 m/s | The gateway wall never moves slower than this |
| `STORM_DAMAGE_PER_SECOND` | 4 | Damage outside the wall |
| `STORM_MISSILES`, `STORM_MISSILE_INTERVAL`, `STORM_MISSILES_PER_VOLLEY` | on, 6 s, 2 | Seeker missiles outside the wall |
| `STABILITY_TIME_SCALE` (JunctionMap.lua) | 0.4 | Scales the Route Planner's stability → seconds |
| `CONDITION_UNSTABLE_TIME_FACTOR` (conditions.lua) | 0.5 | Elevated Instability |
| `CONDITION_RAPID_SPEED_FACTOR` (conditions.lua) | 1.6 | Rapid Collapse |

## Tiers, enemies, pods (`layouts.lua`)

| Setting | Effect |
|---|---|
| `ZONE_TIERS[*].missiles` | `miss` range (m), `volley`, `interval` (s) |
| `ZONE_TIERS[*].enemies` | `chance` per cell, `count`, `units` (uuid, weight) |
| `ZONE_TIERS[*].liquid`, `biomeShare`, `hills`, `wetland` | the tier's liquid, forest share, hills, Mid Zone flooding |
| `ZONE_DEPTH_BIOMES` | biome per depth (a biome, or `{ biome = chance }`, e.g. autumn in the deeper Outer Zone) |
| `ZONE_MIN_BUILDINGS` | lowest building level (ruins, shacks) per depth: more to loot early |
| `START_LOOT_DEPTH` | junctions up to here use Survival's starting-area loot |
| `ZONE_ENEMY_SAFE_DISTANCE` | robots never spawn this close to you |
| `ZONE_ARRIVAL_CLEAR_RADIUS`, `ZONE_ARRIVAL_CLEAR_SECONDS` | robots near you are cleared for this long after you arrive |
| `POD_FIRST_DELAY`, `POD_INTERVAL`, `POD_DISTANCE`, `POD_DROP_HEIGHT` | supply pods during a collapse |
| `POD_LOOT` | pod loot by tier |
| `COLLAPSED_PER_RETURN`, `COLLAPSED_FURTHEST`, `COLLAPSED_OUTER_CHANCE`, `COLLAPSED_DAMAGE`, `COLLAPSED_POD_CHANCE`, `COLLAPSED_MISSILE_GRACE` | collapsed junctions |
| `ZONE_EDGE`, `GARAGE_EDGE` | rim and mountains at the map edge |
| `HIDEOUT_TRADES` | the hideout shop |
| `ZONE_POOL` | the zone pool on or off ([zones.md](zones.md#the-zone-pool)); `false` = a new world every trip |
| `ZONE_POOL_SIZES` | worlds kept per zone depth (1, 2, 3, ...; deeper ones use the last) |
| `ZONE_POOL_ANCHOR_SPOTS` | anchor spots a pooled world keeps (each trip uses some) |

## Gateways and anchors (`layouts.lua`)

| Setting | Value | Effect |
|---|---|---|
| `JUNCTION_COST_BASE` / `JUNCTION_COST_STEP` | 2 / 1 | Anchors a gateway costs: 2 at depth 1, +1 per junction |
| `ZONE_ANCHORS_MIN` / `MAX` | 2 / 7 | Anchors per zone (never fewer than the cost) |
| `SEEDBOT_SEEDS` | table | Seeds the seedbots carry by zone tier (Outer veg, Mid fruit, Deep broccoli and pineapple) |
| `ANCHOR_KIND_WEIGHTS` | table | Stable/unstable/corrupted chances by zone tier (Outer stable, Mid unstable, Deep corrupted) |
| `ARC_CHARGE_SECONDS` | 5 | ARC Device charge-up |
| `GATEWAY_MIN_DISTANCE` / `MAX` | 650 / 1100 m | How far away gateways open (`GATEWAY_DISTANCE_BY_DEPTH`: closer in JCT 1–2) |

## Zone generation (`layouts.lua`)

| Setting | Effect |
|---|---|
| `ZONE_CELL_MIN/MAX` (−16/15) | Zone size in 64 m cells. Keep under ~56×56 (64KB limit) |
| `ZONE_ROAD_EXITS_MIN/MAX` (2/4) | Exit roads, each ending in a junction |
| `ZONE_DEPTH_BIOMES` | Biome per depth |
| `ZONE_BIOMES[*].share` | How much of the zone is biome vs meadow |
| `ZONE_TIERS` | Outer/Mid/Deep depth ranges and music |
| `ZONE_HILLS` | Hill height/size (nil = flat) |
| `ZONE_RUIN_ROLLS` / `ZONE_RUIN_CHANCE` | Ruins |
| `ZONE_SHACK_CHANCE`, `ZONE_LIQUID_TILE_COUNTS` | Shacks and liquids per level |
| `ZONE_TORNADO_*` | Tornadoes |
| `LANDMARKS` | Landmark junctions (depth, tile, size) |
| `ZONE_CONDITIONS`, `ZONE_CONDITION_COUNTS` (conditions.lua) | Which conditions, how likely, how many |

## Map (`JunctionMap.lua` top, `Gui/make_map.py`)

| Setting | Effect |
|---|---|
| `MAP_CHILDREN` | Junctions leading on from each (1–2) |
| `NO_EXIT_CHANCE` / `DEAD_END_CHANCE` | Special junctions |
| `MAP_BIOME_SPREAD` | Chance of the next depth's biome |
| `SCANNER_CHARGES` | Scans/re-rolls per trip home |
| `MAP_SITE_REACH`, `MAP_KEEP_APART` | Placement on the map |
| `MAP_NAMES` | Map names and their building levels |
| `SITE_SPACING` etc. in `make_map.py` | Number of sites (run the script after changing) |

## Garage and loot

| Setting | Where | Effect |
|---|---|---|
| `DUMPSTER_STARTER` / `DUMPSTER_RESTOCK` | layouts.lua | Dumpster loot: `{ uuid, min, max, chance }` |
| `FUEL_PUMP_TAKE` / `FUEL_PUMP_PER_TRIP` | FuelPump.lua | 5 per press, 20 per trip home |
| Fabricator unlocks and costs | `Fabricator/upgrade_tree.json` | Edit with [Tools/fabricator_editor.html](../Tools/fabricator_editor.html) |
| `TRAVEL_HOURS_MIN/MAX` | layouts.lua | Hours skipped per trip |
| `INTRO_TIME_OF_DAY` | Game.lua | New game's start time |

## Switches (`layouts.lua`)

| Setting | Effect |
|---|---|
| `DEV_MODE` | Survival dev mode (dev hotbar, spawn) |
| `CHEAT_COMMANDS` | Developer switch (on): our cheat/debug commands (/depart, /gateway, /skipquest ...) and Survival's (/god, /unlimited, ...) without dev mode. `/where` always works |
| `LIFT_BLUEPRINTS` | Hold the lift + E to load a blueprint, free. Off by default; `/liftblueprints` toggles it per save |
| `JUNCTION_MAP_ON_ENTRY` | Driving into a junction opens the map |
| `MAP_ON_LOGBOOK_KEY` | Logbook key opens the map |
| `ZONE_FOG` / `ZONE_RENDER_SETTINGS` | Zone fog |
| `ZONE_MUSIC` / `ZONE_STORM_MUSIC` | Music |
