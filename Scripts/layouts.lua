dofile( "$CONTENT_DATA/Scripts/conditions.lua" )

-- Settings, world sizes and tile layouts for the garage and the zone.
-- Tiles are survival's own, picked and rotated per 64m cell the same way the
-- survival map generator does it (see Survival/Scripts/terrain/overworld).

-- Survival dev mode: dev chat commands (/god, /unlimited, /spawn, /starterkit ...)
-- and a dev starter hotbar. Set to false for normal survival.
DEV_MODE = false
-- Developer switch: the cheat and debug chat commands, Pacific Scrap's
-- (/depart, /gateway, /home, /skipquest, /revealmap, /dumpster ...) and
-- survival's (/god, /unlimited, /spudgun, /components ...), without the rest
-- of dev mode (dev starter items, dev spawn point). On: anyone can use them.
-- (/where always works: handy for bug reports.)
CHEAT_COMMANDS = true

-- Hold the lift and press E to load a blueprint onto it (free, like creative).
-- Off by default; /liftblueprints turns it on or off for a save (cheats).
LIFT_BLUEPRINTS = false

-- Zone collapse (Pacific Drive style storm). After STORM_STABLE_TIME seconds in
-- the zone, or as soon as the gateway is opened, a storm wall closes in on the
-- gateway. Outside it you take damage and seeker missiles come for you.
STORM_STABLE_TIME = 5 * 60         -- seconds before the zone collapses on its own
STORM_WARNING_TIME = 60            -- seconds of warning before that (the alarm)
STORM_TIME_VARIATION = 0.2         -- both of those vary by up to +-20% each zone
-- Deeper junctions are less stable: the calm period shrinks by this much per
-- junction (down to STORM_DEPTH_MIN_FACTOR of it) and the wall moves faster
STORM_DEPTH_TIME_STEP = 0.12
STORM_DEPTH_MIN_FACTOR = 0.4
STORM_DEPTH_SPEED_STEP = 0.15
STORM_SPEED = 5.0                  -- m/s the wall moves after the timer runs out
STORM_GATEWAY_SPEED = 8.0          -- (not used for the gateway any more: STORM_GATEWAY_TIME_BY_DEPTH below)
STORM_GATEWAY_START_MARGIN = 80    -- metres of safe ground beyond the farthest player when the gateway opens
-- (more in the first junctions, so the wall doesn't appear right next to you:
-- by junction number, past the list STORM_GATEWAY_START_MARGIN)
STORM_GATEWAY_START_MARGIN_BY_DEPTH = { [1] = 300, [2] = 220, [3] = 150 }
-- Once the gateway opens, the wall takes about this many seconds to close in
-- on it, however far away it opened: its speed is the distance over the time
-- (then sped up by the junction's storm level and Rapid Collapse, as
-- STORM_GATEWAY_SPEED would be). By junction number; deeper ones use the last.
STORM_GATEWAY_TIME_BY_DEPTH = { [1] = 180, [2] = 150, [3] = 120, [4] = 100 }
STORM_GATEWAY_SPEED_MIN = 2.0 -- m/s: never slower (a gateway opened right beside you)
STORM_MIN_RADIUS = 0               -- the wall closes in all the way (then it's gone: the storm is everywhere)
STORM_DAMAGE_PER_SECOND = 4
STORM_MISSILES = true              -- seeker missiles at players caught in the storm
STORM_MISSILE_INTERVAL = 6         -- seconds between volleys per player
STORM_MISSILES_PER_VOLLEY = 2
STORM_DARK_SKY = true              -- warehouse-countdown lighting (red horizon, dark fog) once the zone collapses
-- Supply pods (SupplyPod.lua): while the zone collapses, pods with rarer loot
-- come down like the missiles, somewhere near a player. Open one with E.
POD_FIRST_DELAY = 15               -- seconds after the collapse starts until the first
POD_INTERVAL = 45                  -- seconds between pods after that
POD_DISTANCE = { 60, 160 }         -- metres from the player it lands
POD_DROP_HEIGHT = 220              -- metres up it starts falling from
-- Collapsed junctions (Pacific Drive style): already collapsed when you get
-- there, the storm everywhere (it hurts less: COLLAPSED_DAMAGE a second), no
-- gateway, but its exits are open (drive through). Pods lie about, the loot
-- of a collapsed zone (a bit better than a falling pod's). Which ones are
-- collapsed changes every time you come home: some of the furthest junctions.
COLLAPSED_PER_RETURN = { 1, 2 }    -- how many collapse each return home (min, max), past the Outer Zone
COLLAPSED_FURTHEST = 2             -- out of the furthest this many rings of junctions on the map (never junction 1)
COLLAPSED_OUTER_CHANCE = 0.15      -- the Outer Zone: mostly none, now and then (this chance a return home) one
COLLAPSED_DAMAGE = 1
COLLAPSED_MISSILE_GRACE = 30       -- seconds after you arrive in a collapsed zone before missiles come
COLLAPSED_POD_CHANCE = 0.035       -- per 64m cell, as it first loads
-- Pod loot by zone tier: { uuid, min, max, chance } (like the dumpster's);
-- a collapsed zone's pods roll the next tier's table
POD_LOOT = {
	outer = {
		{ uuid = "d4d68946-aa03-4b8f-b1af-96b81ad4e305", min = 4, max = 8 },                -- gas canisters
		{ uuid = "5530e6a0-4748-4926-b134-50ca9ecb9dcf", min = 1, max = 2 },                -- component kits
		{ uuid = "910a7f2c-52b0-46eb-8873-ad13255539af", min = 1, max = 2, chance = 0.6 },  -- batteries
		{ uuid = "f152e4df-bc40-44fb-8d20-3b3ff70cdfe3", min = 1, chance = 0.4 },           -- circuit board
		{ uuid = "36335664-6e61-4d44-9876-54f9660a8565", min = 1, max = 3, chance = 0.5 },  -- glue
	},
	mid = {
		{ uuid = "d4d68946-aa03-4b8f-b1af-96b81ad4e305", min = 6, max = 12 },               -- gas canisters
		{ uuid = "5530e6a0-4748-4926-b134-50ca9ecb9dcf", min = 2, max = 4 },                -- component kits
		{ uuid = "910a7f2c-52b0-46eb-8873-ad13255539af", min = 2, max = 3 },                -- batteries
		{ uuid = "f152e4df-bc40-44fb-8d20-3b3ff70cdfe3", min = 1, max = 2 },                -- circuit boards
		{ uuid = "1bfccc0a-828f-475c-882c-87d5a96054c9", min = 1, chance = 0.25 },          -- gas engine
		{ uuid = "69e362c3-32aa-4cd1-adc0-dcfc47b92c0d", min = 2, max = 4, chance = 0.3 },  -- small wheels
	},
	deep = {
		{ uuid = "d4d68946-aa03-4b8f-b1af-96b81ad4e305", min = 10, max = 20 },              -- gas canisters
		{ uuid = "5530e6a0-4748-4926-b134-50ca9ecb9dcf", min = 3, max = 6 },                -- component kits
		{ uuid = "910a7f2c-52b0-46eb-8873-ad13255539af", min = 2, max = 5 },                -- batteries
		{ uuid = "f152e4df-bc40-44fb-8d20-3b3ff70cdfe3", min = 2, max = 4 },                -- circuit boards
		{ uuid = "1bfccc0a-828f-475c-882c-87d5a96054c9", min = 1, chance = 0.4 },           -- gas engine
		{ uuid = "db66f0b1-0c50-4b74-bdc7-771374204b1f", min = 2, max = 4, chance = 0.4 },  -- big wheels
	},
}
ZONE_MUSIC = 5                    -- survival music in the zone: 5 = warehouse floors, 6 = warehouse top floor, nil = none
ZONE_STORM_MUSIC = 6               -- music while the zone is collapsing
-- Zone look: "$CONTENT_DATA/Render/zone.rendersettings" (thick grey mist that follows the
-- time of day) or "$CONTENT_DATA/Render/zone_greenfog.rendersettings" (growlab-style green fog)
ZONE_RENDER_SETTINGS = "$CONTENT_DATA/Render/zone.rendersettings"
ZONE_FOG = false            -- true = use ZONE_RENDER_SETTINGS (the zone fog) in the zone

-- Wetland shores: how gently the ground slopes down into the flooded patches
-- (higher = gentler; 0.12 was the old, steep one). New zones only: a zone's
-- ground is fixed when it's made.
WETLAND_SLOPE_SOFTNESS = 0.3

-- Zone pool: zone worlds are kept and used again, so the save stops growing
-- (each world is about 2 MB once driven through, and worlds can never be
-- deleted: docs/zones.md, The zone pool). Zones are
-- pooled by their zone depth (NodeZoneDepth: 1-3 Outer, 4-6 Mid, 7-9 Deep);
-- until a pool is full every trip there makes a new world, then the one used
-- longest ago comes back. A world keeps its roads, buildings and liquids;
-- anchors, conditions, robots, mines and the collapse are new every trip.
-- false = a brand new world every trip, as before (pooled worlds stay in the
-- save but aren't used).
ZONE_POOL = true
ZONE_POOL_SIZES = { 10, 8, 6, 5, 4, 3, 3, 2, 2 } -- worlds per zone depth 1, 2, 3...; deeper ones use the last
ZONE_POOL_ANCHOR_SPOTS = 14 -- spots a pooled world keeps for anchor pedestals (each trip uses some of them)

-- Hours that pass on each trip to or from the zone
TRAVEL_HOURS_MIN = 1
TRAVEL_HOURS_MAX = 3

-- Energy anchors an ARC Device needs to open a gateway. Like Pacific Drive, the
-- deeper the junction the more it costs: the first junction out of the garage
-- costs JUNCTION_COST_BASE, each junction further adds JUNCTION_COST_STEP, up to
-- ZONE_ANCHORS_MAX (a zone always has at least as many anchors as it costs).
JUNCTION_COST_BASE = 2
JUNCTION_COST_STEP = 1
ARC_ANCHORS_TO_OPEN = JUNCTION_COST_BASE -- fallback before the game has told the device
-- Energy anchors come in three kinds (like Pacific Drive). They all power the
-- ARC Device the same; the Fabricator takes all three as currency. Their
-- colours (yellow, pink, green: the orb models) are used for the Fabricator's
-- counts, the banking popups, the Route Planner and the beacons' tint.
ENERGY_ANCHORS = {
	{ name = "stable", title = "Stable", uuid = "c243bb55-92f9-4f77-bb2a-b7c87b5a2be9", colour = "#F5B830" },
	{ name = "unstable", title = "Unstable", uuid = "e7a1c3d2-5b6f-4a8e-9c1d-2f3b4a5c6d7e", colour = "#F27AA8" },
	{ name = "corrupted", title = "Corrupted", uuid = "9b8c7d6e-1f2a-4b3c-8d4e-5f6a7b8c9d0e", colour = "#4ED98C" },
}
ENERGY_ANCHOR_BY_NAME = {}
ENERGY_ANCHOR_UUIDS = {}
for _, anchor in ipairs( ENERGY_ANCHORS ) do
	ENERGY_ANCHOR_BY_NAME[anchor.name] = anchor
	ENERGY_ANCHOR_UUIDS[#ENERGY_ANCHOR_UUIDS + 1] = sm.uuid.new( anchor.uuid )
end

-- The anchor kind for an item uuid, or nil if it isn't an energy anchor
function EnergyAnchorOf( uuid )
	local text = tostring( uuid )
	for _, anchor in ipairs( ENERGY_ANCHORS ) do
		if anchor.uuid == text then return anchor end
	end
	return nil
end

-- Seedbots (the little totebots that carry seeds and drop them when hit): the
-- seeds they carry by zone tier, like Survival's seed progression (tomato and
-- potato first, pineapple last), with a few of the zone before's, and potatoes
-- everywhere (the spud gun's ammo). Survival's
-- seedbots elsewhere (the garage) are left alone. { seed type = weight }
SEEDBOT_SEEDS = {
	outer = { tomato = 1, potato = 1, carrot = 1, redbeet = 1 },
	mid = { banana = 1, blueberry = 1, orange = 1, potato = 1, carrot = 0.25, redbeet = 0.25, tomato = 0.25 },
	deep = { broccoli = 1, pineapple = 1, potato = 1, banana = 0.2, blueberry = 0.2, orange = 0.2 },
}

-- Chance of each kind per zone tier, as in Pacific Drive: the Outer Zone has
-- stable anchors, the Mid Zone unstable, the Deep Zone corrupted (with a few of
-- the zone before's)
ANCHOR_KIND_WEIGHTS = {
	outer = { stable = 1 },
	mid = { stable = 0.2, unstable = 0.8 },
	deep = { unstable = 0.2, corrupted = 0.8 },
}

-- zoneDepth: the junction's zone (NodeZoneDepth), whose tier picks the weights
function RollAnchorKind( zoneDepth )
	local weights = ANCHOR_KIND_WEIGHTS[ZoneTierOf( zoneDepth or 1 ).name] or ANCHOR_KIND_WEIGHTS.outer
	local total = 0
	for _, anchor in ipairs( ENERGY_ANCHORS ) do total = total + ( weights[anchor.name] or 0 ) end
	local r = math.random() * total
	for _, anchor in ipairs( ENERGY_ANCHORS ) do
		r = r - ( weights[anchor.name] or 0 )
		if r <= 0 then return anchor.name end
	end
	return "stable"
end
-- Seconds the ARC Device charges up (sparks, rumble) before the gateway opens
ARC_CHARGE_SECONDS = 5

-- Where gateways open (metres from the nearest player); "/gateway here" uses GATEWAY_NEAR_DISTANCE
GATEWAY_MIN_DISTANCE = 650
GATEWAY_MAX_DISTANCE = 1100
GATEWAY_NEAR_DISTANCE = 50
-- (closer in the first junctions, while you're learning: { min, max } by
-- junction depth; deeper ones use GATEWAY_MIN/MAX_DISTANCE)
GATEWAY_DISTANCE_BY_DEPTH = {
	[1] = { 350, 600 },
	[2] = { 500, 850 },
}

-- Gateway distance range (metres) for a junction depth
function GatewayDistance( depth )
	local range = GATEWAY_DISTANCE_BY_DEPTH[depth or 1]
	if range then return range[1], range[2] end
	return GATEWAY_MIN_DISTANCE, GATEWAY_MAX_DISTANCE
end

-- Garage: mechanic station in the middle (cells 0..1), forest around it
GARAGE_CELL_MIN = -2
GARAGE_CELL_MAX = 3

-- (The Friendly Dumpster, Fabricator and Route Planner are part of the garage
-- tile, Terrain/Tiles/garage.tile)

-- The Fuel Pump's spot: where it stands in the garage tile (its centre,
-- measured in game; upright, turned -90 degrees). A pump off it is put back
-- (FuelPump.lua), and a garage with no pump gets one there (GarageWorld).
-- Move it in the tile? Change this too.
FUEL_PUMP_UUID = "e3473813-1984-4a22-9ef7-b1b9f735ccbf"
FUEL_PUMP_HOME = { x = 35.139, y = 87.148, z = 1.406, yaw = -90 }
function FuelPumpHome()
	local center = sm.vec3.new( FUEL_PUMP_HOME.x, FUEL_PUMP_HOME.y, FUEL_PUMP_HOME.z )
	local rotation = sm.quat.angleAxis( math.rad( FUEL_PUMP_HOME.yaw ), sm.vec3.new( 0, 0, 1 ) ) * sm.quat.angleAxis( math.rad( 90 ), sm.vec3.new( 1, 0, 0 ) ) -- (modelled Y-up)
	return center, rotation
end

-- A static Fuel Pump on its spot (createPart wants its corner)
function PlaceFuelPumpAtHome()
	local uuid = sm.uuid.new( FUEL_PUMP_UUID )
	local center, rotation = FuelPumpHome()
	local size = sm.item.getShapeSize( uuid ) * 0.25
	return sm.shape.createPart( uuid, center - rotation * ( size * 0.5 ), rotation, false, true )
end

-- Friendly Dumpster loot: { uuid, min, max, chance }. The starter kit comes the
-- first time it's opened; the restock after every trip. An ARC Device is added
-- whenever nobody has one, and the battery while the garage has no power.
DUMPSTER_STARTER = {
	{ uuid = "05900757-a49f-4907-b498-96bfd2b15176", min = 1 },             -- portable Craftbot
	{ uuid = "8c7efc37-cd7c-4262-976e-39585f8527bf", min = 1 },             -- Connect Tool (to wire the ARC Device)
	{ uuid = "7cf717d7-d167-4f2d-a6e7-6b2c70aa3986", min = 1 },             -- switch (to turn the ARC Device on)
	{ uuid = "d4d68946-aa03-4b8f-b1af-96b81ad4e305", min = 6 },             -- gas canisters
	{ uuid = "59f6951a-a450-42bf-ad03-54567cb70245", min = 3 },             -- scrap wheels
	{ uuid = "c96ab903-f238-4bae-a614-28a758716d00", min = 1 },             -- scrap engine
	{ uuid = "1fc74a28-addb-451a-878d-c3c605d63811", min = 60 },            -- scrap wood
	{ uuid = "1f7ac0bb-ad45-4246-9817-59bdf7f7ab39", min = 60 },            -- scrap metal
	{ uuid = "36335664-6e61-4d44-9876-54f9660a8565", min = 2 },             -- glue
	{ uuid = "cb7305b2-d8b5-4302-aff3-6cdd9212ca64", min = 5 },             -- sunshakes
}
-- When no car came home (a failed run that towed none, or an escape on foot):
-- the parts for a new one
DUMPSTER_CAR_KIT = {
	{ uuid = "77c2687c-2e13-4df8-996a-96fb26d75ee0", min = 1 },             -- driver's seat
	{ uuid = "c96ab903-f238-4bae-a614-28a758716d00", min = 1 },             -- scrap engine
	{ uuid = "59f6951a-a450-42bf-ad03-54567cb70245", min = 3 },             -- scrap wheels
	{ uuid = "4a1b886b-913e-4aad-b5b6-6e41b0db23a6", min = 3 },             -- bearings
	{ uuid = "1f7ac0bb-ad45-4246-9817-59bdf7f7ab39", min = 40 },            -- scrap metal
	{ uuid = "1fc74a28-addb-451a-878d-c3c605d63811", min = 40 },            -- scrap wood
	{ uuid = "d4d68946-aa03-4b8f-b1af-96b81ad4e305", min = 8 },             -- gas canisters
}
DUMPSTER_RESTOCK = {
	{ uuid = "d4d68946-aa03-4b8f-b1af-96b81ad4e305", min = 2, max = 4 },    -- gas canisters
	{ uuid = "1fc74a28-addb-451a-878d-c3c605d63811", min = 15, max = 30 },  -- scrap wood
	{ uuid = "1f7ac0bb-ad45-4246-9817-59bdf7f7ab39", min = 15, max = 30 },  -- scrap metal
	{ uuid = "36335664-6e61-4d44-9876-54f9660a8565", min = 1, max = 2, chance = 0.4 },  -- glue
	{ uuid = "5530e6a0-4748-4926-b134-50ca9ecb9dcf", min = 1, max = 2, chance = 0.3 },  -- component kits
	{ uuid = "f152e4df-bc40-44fb-8d20-3b3ff70cdfe3", min = 1, chance = 0.2 },           -- circuit board
	{ uuid = "910a7f2c-52b0-46eb-8873-ad13255539af", min = 1, max = 2, chance = 0.25 }, -- batteries
	{ uuid = "8e61a423-5aa6-4dd3-ac57-ecac313f82f5", min = 2, max = 3 },    -- flower tea
}

-- Where new players (and /home) spawn, in garage world metres. z is only a
-- fallback: the ground height is measured when the cell loads.
GARAGE_SPAWN = { x = 43.5, y = 85.0, z = 8.0 }

-- Zone: 32x32 cells (2km x 2km) of meadow and forest with a road network,
-- regenerated every run. Keep it under ~56x56: the save stores the zone's tile
-- list in a slot that holds 64KB at most (see tilepack.lua)
ZONE_CELL_MIN = -16
ZONE_CELL_MAX = 15
ZONE_ROAD_EXITS_MIN = 2     -- roads leading off the loop to the edge of the map, each ending in a junction
ZONE_ROAD_EXITS_MAX = 4
ZONE_FOREST_SHARE = 0.4     -- default share of the zone covered by its biome (the rest is meadow); the map edge is always biome
-- Zone biome by junction depth (1 = first junction out of the garage); deeper
-- than the list uses the last one. Biomes: forest, autumn, field, burnt, desert
-- (Outer and Mid: forest and meadow, the Mid Zone with more meadow, autumn
-- forest creeping into the deeper Outer junctions; Deep: burnt forest)
-- An entry is a biome, or { biome = chance, ... } picked per junction.
ZONE_DEPTH_BIOMES = { "forest", { forest = 0.85, autumn = 0.15 }, { forest = 0.55, autumn = 0.45 }, "forest", "forest", "forest", "burnt" }
-- Zone tiers (Pacific Drive's Outer / Mid / Deep Zone) by junction depth. The
-- main quest (Story.lua) unlocks them one at a time: escape through a gateway
-- at a tier's last junction to open the next. The last tier goes on for ever.
ZONE_TIERS = {
	-- music: survival's music parameter (5/6 = Warehouse floors / top floor,
	-- 8 = underground; 9 = Growlab is near silent outside a fight).
	-- stormMusic: while the zone collapses. stormCombat: also switch the
	-- music's combat stage on while it collapses.
	-- missiles: the storm's seeker missiles. miss = how far from you they aim
	-- (metres, random in the range; the blast reaches 2 m, so 3+ always misses),
	-- volley = missiles at a time, interval = seconds between volleys.
	-- enemies: robots placed around the zone as its cells first load. chance =
	-- how likely a cell gets any, count = { min, max } then, units = { uuid,
	-- weight } (survival_units.lua names in the comments).
	-- liquid: the one liquid the tier's junctions roll (water, chemicals, oil)
	-- biomeShare: how much of the zone is the biome (the rest meadow; the
	-- biome's own share if not set)
	-- hills: { amplitude, scale } of the rolling hills (metres)
	{ name = "outer", title = "Outer Zone", first = 1, last = 3, music = 5, stormMusic = 6,
		liquid = "water", hills = { amplitude = 9.0, scale = 150.0 },
		-- biomeShares: forest share by junction (meadow mostly at first); after
		-- that the biome's own (forest: 40%)
		biomeShares = { [1] = 0.2, [2] = 0.3 },
		-- now and then a zone is partly flooded with shallow water (see the Mid
		-- Zone's wetland; chance = how often)
		wetland = { chance = 0.15, liquid = "water", share = { [0] = 0.4, 0.44, 0.48, 0.52, 0.56 }, cover = 0.65, depth = 1.2 },
		stormDamage = 1, -- (a second, outside the storm wall; STORM_DAMAGE_PER_SECOND if not set)
		missiles = { miss = { 5, 9 }, volley = 1, interval = 8 } },
	{ name = "mid", title = "Mid Zone", first = 4, last = 6, music = 8, stormMusic = 6,
		liquid = "chemicals", biomeShare = 0.28, hills = { amplitude = 20.0, scale = 140.0 },
		stormDamage = 3,
		-- wetland: most of the open ground flooded with shallow chemicals, in big
		-- connected stretches, over the roads too (terrain.lua WetDip). liquid =
		-- water, chemicals or oil; chance = how often a zone has it (always if
		-- not set); share = how much of the zone's cells, by the junction's level
		-- of that liquid 0-4; cover = how much of a flooded cell the liquid shows
		-- on; depth = metres the ground dips under it (the liquid is that, less
		-- 0.2 m). (Older zones have pools instead: scattered round ones.)
		wetland = { liquid = "chemicals", share = { [0] = 0.62, 0.65, 0.68, 0.71, 0.74 }, cover = 0.7, depth = 1.6 },
		missiles = { miss = { 4, 8 }, volley = 2, interval = 6 },
		-- paint: the ground (and the grass on it) tinted like Survival's chemical
		-- lakes, which paint theirs pink (Survival's own tiles paint it white).
		-- Two shades mixed in patches this many metres across (terrain.lua).
		-- (paint = { strong = { r, g, b }, soft = { r, g, b }, scale = metres } tints
		-- the ground paint, but it only shows on a few textures; the pink ground
		-- comes from worldClass below)
		-- foliage: like the chemical tiles' plants. clutter: every grass type
		-- becomes one of these (the game's clutter numbers: 41 / 43 seaweed,
		-- 103 violet weed), in patches; leaves / bark: colours for bushes and
		-- trees (from the chemical tiles' own)
		foliage = { clutter = { 41, 43, 41, 103 }, leaves = { "A42B58FF", "CB5B7AFF", "7A1823FF", "7F0F23FF" }, bark = "DE92DDFF" },
		-- worldClass: the zone world class, for its ground textures (the grass
		-- ones don't take paint): ZoneWorldMid's are pink (Terrain/make_ground.py)
		worldClass = "ZoneWorldMid",
		-- the green and yellow tapebots
		enemies = { chance = 0.3, count = { 1, 2 }, units = {
			{ "c68914f8-d769-4638-9071-f7dbd1d97351", 2 }, -- tapebot_green_1
			{ "f3ded3f4-ddf9-441d-83f1-28b8cf2c7581", 2 }, -- tapebot_green_2
			{ "54a06cf0-c035-41a5-b19e-158496d35586", 2 }, -- tapebot_green_3
			{ "97efd943-d176-479a-a6f4-46373327ddcd", 2 }, -- tapebot_yellow
		} } },
	{ name = "deep", title = "Deep Zone", first = 7, last = 9, music = 8, stormMusic = 6,
		-- all burnt forest, with very steep hills. (mix: the second biome instead
		-- of meadow, whole cells; burnt both ways makes it all burnt forest, with
		-- an open road tile where it has none for a road's shape)
		liquid = "oil", biomeShare = 0.6, mix = "burnt", hills = { amplitude = 55.0, scale = 170.0 },
		-- now and then a zone is partly flooded with oil (see the Mid Zone's wetland)
		wetland = { chance = 0.15, liquid = "oil", share = { [0] = 0.36, 0.4, 0.44, 0.48, 0.52 }, cover = 0.65, depth = 1.6 },
		stormDamage = 5,
		missiles = { miss = { 0, 1.5 }, volley = 3, interval = 5 },
		-- blue tapebots, miner bots and the explosive red tapebots
		enemies = { chance = 0.35, count = { 1, 2 }, units = {
			{ "04761b4a-a83e-4736-b565-120bc776edb2", 2 }, -- tapebot (blue)
			{ "9dbbd2fb-7726-4e8f-8eb4-0dab228a561d", 2 }, -- tapebot_taped_1 (blue)
			{ "fcb2e8ce-ca94-45e4-a54b-b5acc156170b", 2 }, -- tapebot_taped_2 (blue)
			{ "68d3b2f3-ed4b-4967-9d22-8ee6f555df63", 2 }, -- tapebot_taped_3 (blue)
			{ "92da8324-3cfe-4529-ac1c-c71facda50a3", 1 }, -- minerbot
			{ "c3d31c47-0c9b-4b07-9bd4-8f022dc4333e", 1 }, -- tapebot_red (explosive)
		} } },
}
ZONE_ENEMY_SAFE_DISTANCE = 110 -- robots never appear this close to a player
-- Arriving in a zone: the cells where you land load before you're there, so
-- nothing of ours spawns in them, and for a while after you arrive any robot
-- this close (survival's own ones in ruins too) is cleared away
ZONE_ARRIVAL_CLEAR_RADIUS = 100 -- metres
ZONE_ARRIVAL_CLEAR_SECONDS = 15

-- The tier (and its index) a junction depth is in. g_testTier (the /testtier
-- cheat, Game.lua) makes every zone count as that tier.
function ZoneTierOf( depth )
	if g_testTier then
		for i, tier in ipairs( ZONE_TIERS ) do
			if tier.name == g_testTier then return tier, i end
		end
	end
	for i, tier in ipairs( ZONE_TIERS ) do
		if ( depth or 1 ) <= tier.last then return tier, i end
	end
	return ZONE_TIERS[#ZONE_TIERS], #ZONE_TIERS
end
-- Tornadoes get more likely the deeper you go: chance x (1 + this x (depth - 1))
ZONE_TORNADO_DEPTH_BONUS = 0.3
ZONE_ANCHORS_MIN = 2        -- energy anchor pedestals per zone, random in this range
ZONE_ANCHORS_MAX = 7        -- (but never fewer than the junction's gateway cost)
ZONE_RUIN_ROLLS = 4         -- chances for a ruin per zone...
ZONE_RUIN_CHANCE = 0.4      -- ...each this likely, so 0 to 4 ruins
-- Gentle rolling hills in the zone: up to amplitude metres up or down, with hills
-- about scale metres across (survival's overworld is much more extreme). nil = flat.
ZONE_HILLS = { amplitude = 11.0, scale = 150.0 }
-- The map's edge (terrain.lua EdgeHeight): mountains beyond it instead of flat
-- grass, and inside it the ground climbs into a rim (not around junctions).
-- rim / width: how high (m) over how wide a band; mountains: their height (m)
ZONE_EDGE = { rim = 26, width = 120, mountains = 110 }
-- A ring of deep forest this many cells wide around the playable area, on the
-- mountains beyond the edge (the world's own border is outside it)
WORLD_RING = 2
GARAGE_EDGE = { mountains = 90 } -- (the garage: mountains only; new saves; bounds added in Game.lua)

-- Junctions: an editable tile (Terrain/Tiles/junction.tile, a copy of survival's
-- forest road dead end; keep its road opening on the east side). One sits at the
-- end of each zone exit road, driving into it takes you one junction deeper. The
-- same tile is next to the garage, and its launch pad is where you depart from.
JUNCTION_TILE = "$CONTENT_DATA/Terrain/Tiles/junction.tile"
-- The junction tile's gate (a kinematic door placed closed, eventListen set to
-- this): in the garage it opens once a route is set (DriveWorld.lua,
-- GarageWorld.sv_updateJunctionGate); in a zone it's always open
JUNCTION_GATE_EVENT = "opengate01"
-- true: driving into a junction (the garage pad or a zone exit) fades out and
-- opens the junction map; you travel once you pick where to go. false: you go
-- straight to the destination set with /junctionmap (or the first one).
JUNCTION_MAP_ON_ENTRY = true
-- true: the Logbook key opens (and closes) the junction map instead of the logbook
MAP_ON_LOGBOOK_KEY = true
GARAGE_JUNCTION = { x = 2, y = 0, rotation = 2 } -- cell and rotation (2 = road opening faces west, to the garage)
-- Where in the junction tile you drive in (its elevator): metres in the tile as
-- it is in the tile editor (road opening east). Pads and triggers go here.
JUNCTION_PAD_SPOT = { x = 38.0, y = 32.25 }
-- Where you arrive back from a gateway: another editable tile (Terrain/Tiles/
-- garage_exit.tile, a copy of survival's open-ground road dead end, opening on
-- the east side) at the other end of the garage road
GARAGE_EXIT_TILE = "$CONTENT_DATA/Terrain/Tiles/garage_exit_128.tile"
-- spot: where you arrive, metres in the tile as in the tile editor (the middle
-- of its spawn platform)
-- Terrain/Tiles/garage_exit_128.tile: a 2x2 forest tile, the garage's size,
-- north of the player spawn, behind the garage station (cells 0..1, 2..3), with
-- a clearing in the middle where you arrive. tile: where the tile goes (its
-- corner cell). x, y: the cell the arrival spot is in; spot: metres in that
-- cell (picked in game with /where: about 44, 158); rotation 3 = arrivals face south,
-- to the garage (a 2x2 tile isn't turned, so the spot isn't either).
-- Only new saves get a moved exit (the garage world is made once).
-- (The old 1-cell exit, garage_exit.tile, sat at -1, 0 with spot 30, 32.25.)
GARAGE_EXIT = { x = 0, y = 2, rotation = 3, spot = { x = 44, y = 30 }, tile = { x = 0, y = 2, size = 2 } }

-- Tornadoes (survival's) roaming the zone: every ZONE_TORNADO_ROLL_SECONDS there's
-- a ZONE_TORNADO_CHANCE one spawns somewhere near a player, up to ZONE_TORNADO_MAX at once
ZONE_TORNADOES = true
ZONE_TORNADO_ROLL_SECONDS = 45
ZONE_TORNADO_CHANCE = 0.25
ZONE_TORNADO_MAX = 2
ZONE_TORNADO_LIFETIME = 100   -- seconds
ZONE_TORNADO_SPAWN_DISTANCE = { 120, 220 }


-- Tiles -------------------------------------------------------------------------

local TILES = "$SURVIVAL_DATA/Terrain/Tiles/"

local function Variants( pattern, count )
	local paths = {}
	for i = 1, count do
		paths[#paths + 1] = TILES .. string.format( pattern, i )
	end
	return paths
end

local function Pick( list )
	return list[math.random( #list )]
end

-- The garage: an editable tile (Terrain/Tiles/garage.tile, a copy of survival's
-- mechanic station, 2x2 cells). Only new saves pick up a different tile here;
-- edits to this tile itself show in existing saves too.
MECHANIC_STATION_TILE = "$CONTENT_DATA/Terrain/Tiles/garage.tile"

-- Forest edge tiles, keyed by which cell corners are forest, in survival's
-- order: south-east, south-west, north-west, north-east. All four = deep
-- forest; none = meadow (MEADOW_TILES).
FOREST_TILES = {
	{ se = 0, sw = 0, nw = 0, ne = 1, paths = Variants( "forest/Forest(0001)_%02d.tile", 5 ) },
	{ se = 0, sw = 0, nw = 1, ne = 1, paths = Variants( "forest/Forest(0011)_%02d.tile", 5 ) },
	{ se = 0, sw = 1, nw = 0, ne = 1, paths = Variants( "forest/Forest(0101)_%02d.tile", 1 ) },
	{ se = 0, sw = 1, nw = 1, ne = 1, paths = Variants( "forest/Forest(0111)_%02d.tile", 1 ) },
	{ se = 1, sw = 1, nw = 1, ne = 1, paths = Variants( "forest/Forest(1111)_%02d.tile", 3 ) },
}
DEEP_FOREST_TILES = FOREST_TILES[#FOREST_TILES].paths
MEADOW_TILES = Variants( "meadow/Meadow_64(1111)_%02d.tile", 29 )
-- Survival's 64m ruins for open meadow (biome ones are in ZONE_BIOMES)
MEADOW_RUIN_TILES = Variants( "poi/Ruin_Meadow_64_%02d.tile", 11 )

-- Farmer shacks: survival's road kiosk tiles. Like in survival they replace a
-- straight piece of road (the tile has the road running through it, the shack
-- beside it). The junction's building level (0-4, the Route Planner's
-- BUILDINGS) is how many tries, each ZONE_SHACK_CHANCE likely.
ZONE_SHACK_CHANCE = 0.6
SHACK_TILES = Variants( "poi/Kiosk_64_%02d.tile", 3 )

-- Landmarks: survival's big places as junctions of their own (their tiles are
-- editable copies in Terrain/Tiles: packingstation_veg, packingstation_fruit,
-- hideout; keep their sizes, and the packing stations' road along the bottom row). Each is an
-- optional side branch off a junction one shallower than its depth, always
-- shown on the map; perpetual stability and no stable exits (you drive on).
-- Its world is made on the first visit and kept (and reused) for good.
-- tile: the point of interest, size cells across, in the middle of the zone
-- with a ring road round it.
LANDMARKS = {
	-- road: a road tile (survival's packing stations): the zone's road runs
	-- west to east through its bottom row, as it does through survival's
	{ name = "veg", title = "Vegetable Packing Station", code = "VP", depth = 2, size = 2, road = true, beaconIcon = 18,
		tile = "$CONTENT_DATA/Terrain/Tiles/packingstation_veg.tile",
		text = "Shoot tomatoes, carrots, beets and broccoli into it to pack crates. The farmers trade for crates." },
	{ name = "fruit", title = "Fruit Packing Station", code = "FP", depth = 2, size = 2, road = true, beaconIcon = 18,
		tile = "$CONTENT_DATA/Terrain/Tiles/packingstation_fruit.tile",
		text = "Shoot bananas, blueberries, oranges and pineapples into it to pack crates. The farmers trade for crates." },
	{ name = "hideout", title = "Farmers' Hideout", code = "FH", depth = 2, size = 8, beaconIcon = 5,
		tile = "$CONTENT_DATA/Terrain/Tiles/hideout.tile",
		text = "Where the farmers hold out. Trade crates and produce with them for seeds, parts and gear." },
}

-- The Farmers' Hideout: crates go in through its vacuum (Survival's dropzone and
-- button), and its traders swap them for these (Scripts/hideout_shop.lua; no
-- unlock progression). The header counts every kind of crate, and the caged
-- farmers rescued from the zone (Survival's farmer cages; the vacuum takes
-- those too).
--   item, quantity: what you get; cost: { [crate uuid] = how many }
HIDEOUT_CRATES = {
	{ uuid = "9cd8288c-5a19-479f-af47-9eb55230ade2", title = "Carrot" },
	{ uuid = "1dcd74ca-39ba-4b00-a36a-3381b25055f4", title = "Tomato" },
	{ uuid = "99477093-e819-4199-b62a-fda6143aae89", title = "Broccoli" },
	{ uuid = "628fd350-577d-413f-82a8-7f08a83de3d8", title = "Beetroot" },
	{ uuid = "0bc74539-df8a-47c7-aad8-d55d809a01e4", title = "Banana" },
	{ uuid = "e77d9577-589a-446b-96c1-f6d0d7495489", title = "Blueberry" },
	{ uuid = "c10a77d5-3357-4cb4-8113-a2cbe69c7ff2", title = "Orange" },
	{ uuid = "bc69cb3b-7e0c-4c36-805d-f8d89fcfced3", title = "Pineapple" },
	{ uuid = "8d601982-4608-4d5e-bb9e-e4041486f7c7", title = "Caged Farmer", farmer = true },
}
local CARROT, TOMATO, BROCCOLI, BEET = HIDEOUT_CRATES[1].uuid, HIDEOUT_CRATES[2].uuid, HIDEOUT_CRATES[3].uuid, HIDEOUT_CRATES[4].uuid
local BANANA, BLUEBERRY, ORANGE, PINEAPPLE = HIDEOUT_CRATES[5].uuid, HIDEOUT_CRATES[6].uuid, HIDEOUT_CRATES[7].uuid, HIDEOUT_CRATES[8].uuid
local FARMER = HIDEOUT_CRATES[9].uuid
HIDEOUT_TRADES = {
	{ item = "d4d68946-aa03-4b8f-b1af-96b81ad4e305", quantity = 15, cost = { [CARROT] = 1 } },               -- gas canisters
	{ item = "d4d68946-aa03-4b8f-b1af-96b81ad4e305", quantity = 15, cost = { [TOMATO] = 1 } },               -- gas canisters
	{ item = "d4d68946-aa03-4b8f-b1af-96b81ad4e305", quantity = 50, cost = { [CARROT] = 1, [TOMATO] = 1, [BROCCOLI] = 1 } }, -- gas canisters, bulk
	{ item = "d4d68946-aa03-4b8f-b1af-96b81ad4e305", quantity = 30, cost = { [FARMER] = 1 } },               -- gas canisters, for a rescued farmer
	{ item = "5530e6a0-4748-4926-b134-50ca9ecb9dcf", quantity = 3, cost = { [BROCCOLI] = 1 } },              -- component kits
	{ item = "910a7f2c-52b0-46eb-8873-ad13255539af", quantity = 3, cost = { [BEET] = 1 } },                  -- batteries
	{ item = "bfcfac34-db0f-42d6-bd0c-74a7a5c95e82", quantity = 60, cost = { [BEET] = 1 } },                 -- potatoes (spud gun ammo)
	{ item = "f152e4df-bc40-44fb-8d20-3b3ff70cdfe3", quantity = 2, cost = { [BANANA] = 1 } },                -- circuit boards
	{ item = "36335664-6e61-4d44-9876-54f9660a8565", quantity = 5, cost = { [BLUEBERRY] = 1 } },             -- glue
	{ item = "54d84731-d9ec-435d-bc9d-d48e0763b1bf", quantity = 3, cost = { [ORANGE] = 1 } },                -- pizza burgers
	{ item = "cb7305b2-d8b5-4302-aff3-6cdd9212ca64", quantity = 2, cost = { [PINEAPPLE] = 1 } },             -- sunshakes
}

-- Bump when landmark worlds should be made again (a layout change): 2 = the
-- packing stations on the road, 3 = the fruit station moved to depth 2,
-- 4 = the mod's own (editable) copies of the tiles
LANDMARK_LAYOUT = 4

function LandmarkByName( name )
	for _, landmark in ipairs( LANDMARKS ) do
		if landmark.name == name then return landmark end
	end
end
-- Water, oil and chemicals: each junction rolls a level (0-4, shown on the
-- Route Planner) and gets this many of that for it. Water stays rare: each is
-- a pond made of survival's lake edge tiles (four cells around one corner).
-- Chemicals alternate between the road chemical plant (on a straight road,
-- like the shacks) and a 128m chemical lake.
OIL_TILES = Variants( "poi/OilPool_Desert_64_%02d.tile", 2 )
CHEMICAL_ROAD_TILES = { TILES .. "poi/ChemicalPlant_Road_64_01.tile" }
CHEMICAL_LAKE_TILES = Variants( "poi/ChemicalLake_128_%02d.tile", 3 )
ZONE_LIQUID_TILE_COUNTS = {
	water = { [0] = 0, 1, 1, 2, 2 },
	oil = { [0] = 0, 1, 2, 3, 4 },
	chemicals = { [0] = 0, 1, 2, 3, 4 },
}

-- Road tiles, keyed by road openings (south, west, north, east; north = +y,
-- east = +x) and forest corners (south-east, south-west, north-west, north-east),
-- straight from the tile names, e.g. Road(0101)_Forest(0011). Forest roads and
-- their forest-edge versions are survival's biome roads; open-ground roads are
-- its roads_and_cliffs set.
local function Road( openings, corners, pattern, count )
	return {
		s = tonumber( openings:sub( 1, 1 ) ), w = tonumber( openings:sub( 2, 2 ) ), n = tonumber( openings:sub( 3, 3 ) ), e = tonumber( openings:sub( 4, 4 ) ),
		se = tonumber( corners:sub( 1, 1 ) ), sw = tonumber( corners:sub( 2, 2 ) ), nw = tonumber( corners:sub( 3, 3 ) ), ne = tonumber( corners:sub( 4, 4 ) ),
		paths = Variants( pattern, count )
	}
end
-- Open ground roads: every shape exists, so a road can always fall back to these
OPEN_ROAD_TILES = {
	Road( "0001", "0000", "roads_and_cliffs/Road(0001)_Cliff(0000)_%02d.tile", 1 ),
	Road( "0011", "0000", "roads_and_cliffs/Road(0011)_Cliff(0000)_%02d.tile", 14 ),
	Road( "0101", "0000", "roads_and_cliffs/Road(0101)_Cliff(0000)_%02d.tile", 16 ),
	Road( "0111", "0000", "roads_and_cliffs/Road(0111)_Cliff(0000)_%02d.tile", 1 ),
	Road( "1111", "0000", "roads_and_cliffs/Road(1111)_Cliff(0000)_%02d.tile", 2 ),
}
FOREST_ROAD_TILES = {
	Road( "0001", "1111", "roads_biomes/Road(0001)_Forest(1111)_%02d.tile", 1 ),
	Road( "0011", "1111", "roads_biomes/Road(0011)_Forest(1111)_%02d.tile", 1 ),
	Road( "0101", "1111", "roads_biomes/Road(0101)_Forest(1111)_%02d.tile", 1 ),
	Road( "0111", "1111", "roads_biomes/Road(0111)_Forest(1111)_%02d.tile", 1 ),
	Road( "1111", "1111", "roads_biomes/Road(1111)_Forest(1111)_%02d.tile", 1 ),
	-- Forest edges
	Road( "0011", "0001", "roads_biomes/Road(0011)_Forest(0001)_%02d.tile", 1 ),
	Road( "0011", "0110", "roads_biomes/Road(0011)_Forest(0110)_%02d.tile", 1 ),
	Road( "0011", "1100", "roads_biomes/Road(0011)_Forest(1100)_%02d.tile", 1 ),
	Road( "0011", "1110", "roads_biomes/Road(0011)_Forest(1110)_%02d.tile", 1 ),
	Road( "0101", "0001", "roads_biomes/Road(0101)_Forest(0001)_%02d.tile", 1 ),
	Road( "0101", "0010", "roads_biomes/Road(0101)_Forest(0010)_%02d.tile", 1 ),
	Road( "0101", "0011", "roads_biomes/Road(0101)_Forest(0011)_%02d.tile", 1 ),
	Road( "0101", "0111", "roads_biomes/Road(0101)_Forest(0111)_%02d.tile", 1 ),
	Road( "0101", "1001", "roads_biomes/Road(0101)_Forest(1001)_%02d.tile", 1 ),
	Road( "0101", "1011", "roads_biomes/Road(0101)_Forest(1011)_%02d.tile", 1 ),
}

-- Edge tiles for a biome, keyed by corners like FOREST_TILES
local function EdgeTiles( folder, name, counts )
	local list = {}
	for _, key in ipairs( { "0001", "0011", "0101", "0111", "1111" } ) do
		list[#list + 1] = {
			se = tonumber( key:sub( 1, 1 ) ), sw = tonumber( key:sub( 2, 2 ) ), nw = tonumber( key:sub( 3, 3 ) ), ne = tonumber( key:sub( 4, 4 ) ),
			paths = Variants( folder .. "/" .. name .. "(" .. key .. ")_%02d.tile", counts[key] )
		}
	end
	return list
end

-- Lake edge tiles (only the one-corner ones are used, for small ponds)
LAKE_TILES = EdgeTiles( "lake", "Lake", { ["0001"] = 11, ["0011"] = 14, ["0101"] = 1, ["0111"] = 6, ["1111"] = 13 } )

-- Zone biomes. The biome covers patches (and the map edge); the rest is meadow.
-- tiles: edge tiles keyed by corners (the last entry is the solid biome)
-- roads: road tiles for biome cells (only forest has every shape; elsewhere
--        roads run through open ground and the biome grows around them)
-- ruins: 64m points of interest placed in solid biome cells
ZONE_BIOMES = {
	forest = {
		title = "Forest", share = 0.4, tiles = FOREST_TILES, roads = FOREST_ROAD_TILES, roadsInBiome = true,
		ruins = Variants( "poi/Ruin_Forest_64_%02d.tile", 3 ),
	},
	autumn = {
		title = "Autumn Forest", share = 0.45,
		tiles = EdgeTiles( "autumn_forest", "AutumnForest", { ["0001"] = 5, ["0011"] = 5, ["0101"] = 1, ["0111"] = 1, ["1111"] = 2 } ),
		roads = {
			Road( "0011", "1111", "roads_biomes/Road(0011)_AutumnForest(1111)_%02d.tile", 1 ),
			Road( "0101", "1111", "roads_biomes/Road(0101)_AutumnForest(1111)_%02d.tile", 1 ),
			Road( "0101", "1001", "roads_biomes/Road(0101)_AutumnForest(1001)_%02d.tile", 1 ),
		},
		ruins = Variants( "poi/Ruin_AutumnForest_64_%02d.tile", 3 ),
	},
	field = {
		title = "Fields", share = 0.6,
		tiles = EdgeTiles( "field", "Field", { ["0001"] = 1, ["0011"] = 1, ["0101"] = 1, ["0111"] = 1, ["1111"] = 7 } ),
		roads = {
			Road( "0011", "1111", "roads_biomes/Road(0011)_Field(1111)_%02d.tile", 1 ),
			Road( "0101", "1111", "roads_biomes/Road(0101)_Field(1111)_%02d.tile", 1 ),
			Road( "0101", "1001", "roads_biomes/Road(0101)_Field(1001)_%02d.tile", 1 ),
		},
		ruins = { TILES .. "poi/Ruin_Field_64_01.tile", TILES .. "poi/Ruin_Field_64_02.tile", TILES .. "poi/Ruin_Field_64_03.tile",
			TILES .. "poi/Random_Field_64_01.tile", TILES .. "poi/Random_Field_64_02.tile", TILES .. "poi/Random_Field_64_03.tile" },
	},
	burnt = {
		title = "Burnt Forest", share = 0.5,
		tiles = EdgeTiles( "burnt_forest", "BurntForest", { ["0001"] = 3, ["0011"] = 3, ["0101"] = 1, ["0111"] = 3, ["1111"] = 2 } ),
		roads = {
			Road( "0011", "1111", "roads_biomes/Road(0011)_BurntForest(1111)_%02d.tile", 1 ),
			Road( "0101", "1111", "roads_biomes/Road(0101)_BurntForest(1111)_%02d.tile", 1 ),
			Road( "0101", "1001", "roads_biomes/Road(0101)_BurntForest(1001)_%02d.tile", 1 ),
		},
		ruins = Variants( "poi/Ruin_BurntForest_64_%02d.tile", 3 ),
	},
	desert = {
		title = "Desert", share = 0.75,
		tiles = EdgeTiles( "desert", "Desert", { ["0001"] = 3, ["0011"] = 4, ["0101"] = 1, ["0111"] = 2, ["1111"] = 6 } ),
		roads = {
			Road( "0011", "1111", "roads_biomes/Road(0011)_Desert(1111)_%02d.tile", 2 ),
			Road( "0101", "1111", "roads_biomes/Road(0101)_Desert(1111)_%02d.tile", 3 ),
			Road( "0101", "0001", "roads_biomes/Road(0101)_Desert(0001)_%02d.tile", 1 ),
			Road( "0101", "0010", "roads_biomes/Road(0101)_Desert(0010)_%02d.tile", 1 ),
			Road( "0101", "1001", "roads_biomes/Road(0101)_Desert(1001)_%02d.tile", 2 ),
		},
		ruins = { TILES .. "poi/Random_Desert_64_01.tile", TILES .. "poi/Random_Desert_64_02.tile", TILES .. "poi/Kiosk_Desert_64_01.tile",
			TILES .. "poi/OilPool_Desert_64_01.tile", TILES .. "poi/OilPool_Desert_64_02.tile" },
	},
}

local function DepthBiomes( depth )
	local list = ZONE_DEPTH_BIOMES
	return list[math.min( math.max( depth or 1, 1 ), #list )] or "forest"
end

-- A biome for a junction at this depth (picked by chance where there's a choice)
function ZoneBiomeForDepth( depth )
	local entry = DepthBiomes( depth )
	if type( entry ) == "table" then
		local total = 0
		for _, chance in pairs( entry ) do total = total + chance end
		local r = math.random() * total
		for name, chance in pairs( entry ) do
			r = r - chance
			if r <= 0 then return ZONE_BIOMES[name] and name or "forest" end
		end
		return "forest"
	end
	return ZONE_BIOMES[entry] and entry or "forest"
end

-- Can a junction at this depth have this biome?
function ZoneBiomeAllowed( depth, name )
	local entry = DepthBiomes( depth )
	if type( entry ) == "table" then
		return entry[name] ~= nil
	end
	return entry == name
end

-- Rotating a tile by 1 turns it 90 degrees counter-clockwise (east opening ->
-- north, north-east corner -> north-west), as survival's generator does
local function RotateCorners( c )
	return { se = c.sw, sw = c.nw, nw = c.ne, ne = c.se }
end

local function RotateRoad( t )
	local r = RotateCorners( t )
	r.s, r.w, r.n, r.e = t.w, t.n, t.e, t.s
	return r
end

local CORNER_KEYS = { "se", "sw", "nw", "ne" }
local ROAD_KEYS = { "s", "w", "n", "e", "se", "sw", "nw", "ne" }

-- Finds a tile in the set, and the rotation, whose keys match the wanted ones
local function FindRotatedTile( set, wanted, keys, rotate )
	for _, tile in ipairs( set ) do
		local r = tile
		for rotation = 0, 3 do
			local match = true
			for _, k in ipairs( keys ) do
				if r[k] ~= wanted[k] then
					match = false
					break
				end
			end
			if match then
				return Pick( tile.paths ), rotation
			end
			r = rotate( r )
		end
	end
end


-- Gateway cost (energy anchors) at a junction depth: 1 = first junction out of the garage
function GatewayCost( depth )
	return math.min( JUNCTION_COST_BASE + ( math.max( depth or 1, 1 ) - 1 ) * JUNCTION_COST_STEP, ZONE_ANCHORS_MAX )
end

-- Middle of a junction (or exit) cell
function JunctionCenter( junction )
	return sm.vec3.new( ( junction.x + 0.5 ) * 64, ( junction.y + 0.5 ) * 64, 0 )
end

-- The launch pad / trigger spot: on the road, in front of the rock at the end.
-- The tile's opening is east at rotation 0; each rotation turns it 90 degrees
-- counter-clockwise.
local OPENING_DIRECTIONS = { [0] = { 1, 0 }, { 0, 1 }, { -1, 0 }, { 0, -1 } }
-- Which way a junction's road leads out of it (unit vector)
function JunctionOpening( junction )
	local d = OPENING_DIRECTIONS[( junction.rotation or 0 ) % 4]
	return sm.vec3.new( d[1], d[2], 0 )
end

-- Portal opening rotation that faces a horizontal direction. A portal keeps the
-- car's heading relative to its openings, so driving in along A's facing comes
-- out driving along B's.
function FacingRotation( dir )
	if not dir or ( dir.x == 0 and dir.y == 0 ) then
		return sm.quat.identity()
	end
	return sm.quat.angleAxis( math.atan2( dir.y, dir.x ), sm.vec3.new( 0, 0, 1 ) )
end

-- A spot in a placed junction (or exit) tile: its own spot, or the junction
-- tile's, turned with the tile (rotation 1 = 90 degrees counter-clockwise).
-- A big tile (junction.tile, e.g. the 2x2 garage exit) isn't turned: there
-- rotation is only which way you face.
function JunctionPadPosition( junction )
	local spot = junction.spot or JUNCTION_PAD_SPOT
	local dx, dy = spot.x - 32, spot.y - 32
	for _ = 1, junction.tile and 0 or ( junction.rotation or 0 ) % 4 do
		dx, dy = -dy, dx
	end
	return JunctionCenter( junction ) + sm.vec3.new( dx, dy, 0 )
end


-- Garage ------------------------------------------------------------------------

-- Deep forest in a WORLD_RING cells wide ring round the playable cells
-- (lo..hi on both axes): the mountains beyond the edge get trees
function ForestRing( tiles, lo, hi, paths )
	for y = lo - WORLD_RING, hi + WORLD_RING do
		for x = lo - WORLD_RING, hi + WORLD_RING do
			if x < lo or x > hi or y < lo or y > hi then
				tiles[#tiles + 1] = { path = Pick( paths ), x = x, y = y, size = 1, rotation = math.random( 0, 3 ) }
			end
		end
	end
end

-- The playable area in metres, for the terrain's edge (terrain.lua EdgeHeight)
function EdgeBounds( lo, hi )
	return { x0 = lo * 64, x1 = ( hi + 1 ) * 64, y0 = lo * 64, y1 = ( hi + 1 ) * 64 }
end

function GarageLayout()
	local tiles = {}
	tiles[#tiles + 1] = { path = MECHANIC_STATION_TILE, x = 0, y = 0, size = 2 }
	tiles[#tiles + 1] = { path = JUNCTION_TILE, x = GARAGE_JUNCTION.x, y = GARAGE_JUNCTION.y, size = 1, rotation = GARAGE_JUNCTION.rotation }
	-- (the exit: a 2x2 tile, or an older 1-cell one)
	local exitTile = GARAGE_EXIT.tile or { x = GARAGE_EXIT.x, y = GARAGE_EXIT.y, size = 1 }
	tiles[#tiles + 1] = { path = GARAGE_EXIT_TILE, x = exitTile.x, y = exitTile.y, size = exitTile.size, rotation = exitTile.size == 1 and GARAGE_EXIT.rotation or 0 }
	local function inExit( x, y )
		return x >= exitTile.x and x < exitTile.x + exitTile.size and y >= exitTile.y and y < exitTile.y + exitTile.size
	end
	for y = GARAGE_CELL_MIN, GARAGE_CELL_MAX do
		for x = GARAGE_CELL_MIN, GARAGE_CELL_MAX do
			local isJunction = ( x == GARAGE_JUNCTION.x and y == GARAGE_JUNCTION.y ) or inExit( x, y )
			if not ( ( x == 0 or x == 1 ) and ( y == 0 or y == 1 ) ) and not isJunction then
				tiles[#tiles + 1] = { path = Pick( DEEP_FOREST_TILES ), x = x, y = y, size = 1, rotation = math.random( 0, 3 ) }
			end
		end
	end
	ForestRing( tiles, GARAGE_CELL_MIN, GARAGE_CELL_MAX, DEEP_FOREST_TILES )
	return tiles
end


-- Zone --------------------------------------------------------------------------

local function Degree( o )
	return o.s + o.w + o.n + o.e
end

-- Road network on the cell grid: roads[y][x] = { s, w, n, e }
local function NewRoadGrid()
	local grid = { roads = {} }
	function grid.get( x, y )
		return grid.roads[y] and grid.roads[y][x]
	end
	function grid.cell( x, y )
		grid.roads[y] = grid.roads[y] or {}
		grid.roads[y][x] = grid.roads[y][x] or { s = 0, w = 0, n = 0, e = 0 }
		return grid.roads[y][x]
	end
	function grid.connect( x1, y1, x2, y2 )
		if x2 > x1 then grid.cell( x1, y1 ).e = 1; grid.cell( x2, y2 ).w = 1
		elseif x2 < x1 then grid.cell( x1, y1 ).w = 1; grid.cell( x2, y2 ).e = 1
		elseif y2 > y1 then grid.cell( x1, y1 ).n = 1; grid.cell( x2, y2 ).s = 1
		elseif y2 < y1 then grid.cell( x1, y1 ).s = 1; grid.cell( x2, y2 ).n = 1 end
	end
	function grid.remove( x, y )
		local o = grid.get( x, y )
		if not o then return end
		if o.e == 1 then grid.cell( x + 1, y ).w = 0 end
		if o.w == 1 then grid.cell( x - 1, y ).e = 0 end
		if o.n == 1 then grid.cell( x, y + 1 ).s = 0 end
		if o.s == 1 then grid.cell( x, y - 1 ).n = 0 end
		grid.roads[y][x] = nil
	end
	function grid.each( fn )
		for y, row in pairs( grid.roads ) do
			for x, o in pairs( row ) do
				fn( x, y, o )
			end
		end
	end
	return grid
end

-- The loop: random points around the middle joined by L-shaped stretches, then
-- any dead-end stubs trimmed off so only the closed loop is left
local function BuildLoop( grid )
	local lo, hi = ZONE_CELL_MIN + 2, ZONE_CELL_MAX - 2
	local cx = math.random() - 0.5
	local cy = math.random() - 0.5
	local count = math.random( 9, 11 )
	local points = {}
	for i = 1, count do
		local angle = ( i - 1 + ( math.random() - 0.5 ) * 0.6 ) / count * 2 * math.pi
		local half = ( ZONE_CELL_MAX - ZONE_CELL_MIN + 1 ) / 2
		local radius = half * ( 0.38 + math.random() * 0.3 ) -- loop size scales with the map
		local px = sm.util.clamp( math.floor( cx + math.cos( angle ) * radius + 0.5 ), lo, hi )
		local py = sm.util.clamp( math.floor( cy + math.sin( angle ) * radius + 0.5 ), lo, hi )
		local last = points[#points]
		if not last or last.x ~= px or last.y ~= py then
			points[#points + 1] = { x = px, y = py }
		end
	end

	local lastDx, lastDy = 0, 0
	local function walk( x, y, tx, ty )
		while x ~= tx or y ~= ty do
			local dx = tx > x and 1 or ( tx < x and -1 or 0 )
			local dy = ty > y and 1 or ( ty < y and -1 or 0 )
			if dx ~= 0 then dy = 0 end
			grid.connect( x, y, x + dx, y + dy )
			x, y = x + dx, y + dy
			lastDx, lastDy = dx, dy
		end
		return x, y
	end
	for i = 1, #points do
		local a, b = points[i], points[i % #points + 1]
		-- L-shape: horizontal or vertical first, never doubling straight back
		local horizontalFirst = math.random() < 0.5
		if horizontalFirst and lastDx ~= 0 and ( b.x - a.x ) * lastDx < 0 then horizontalFirst = false end
		if not horizontalFirst and lastDy ~= 0 and ( b.y - a.y ) * lastDy < 0 then horizontalFirst = true end
		local x, y = a.x, a.y
		if horizontalFirst then
			x, y = walk( x, y, b.x, y )
		else
			x, y = walk( x, y, x, b.y )
		end
		walk( x, y, b.x, b.y )
	end

	-- Trim dead ends until only loops remain
	local trimmed = true
	while trimmed do
		trimmed = false
		local stubs = {}
		grid.each( function( x, y, o ) if Degree( o ) <= 1 then stubs[#stubs + 1] = { x = x, y = y } end end )
		for _, s in ipairs( stubs ) do
			grid.remove( s.x, s.y )
			trimmed = true
		end
	end
end

-- An exit road wandering outwards from the loop to the map edge. Returns its cells.
local function BuildExit( grid, side )
	local dx = side == "e" and 1 or ( side == "w" and -1 or 0 )
	local dy = side == "n" and 1 or ( side == "s" and -1 or 0 )

	-- Start from the loop cell furthest towards that side
	local best, bestScore = nil, -math.huge
	grid.each( function( x, y, o )
		if grid.blocked and grid.blocked[x .. "," .. y] then return end
		local score = x * dx + y * dy + math.random() * 0.5
		if score > bestScore then best, bestScore = { x = x, y = y }, score end
	end )
	if not best then return {} end

	local x, y = best.x, best.y
	local path = {}
	local lo, hi = ZONE_CELL_MIN + 2, ZONE_CELL_MAX - 2
	local function atEdge( px, py )
		return ( dx ~= 0 and ( px == ZONE_CELL_MIN or px == ZONE_CELL_MAX ) ) or ( dy ~= 0 and ( py == ZONE_CELL_MIN or py == ZONE_CELL_MAX ) )
	end
	local function remaining( px, py )
		if dx > 0 then return ZONE_CELL_MAX - px elseif dx < 0 then return px - ZONE_CELL_MIN
		elseif dy > 0 then return ZONE_CELL_MAX - py else return py - ZONE_CELL_MIN end
	end
	local step = 0
	while not atEdge( x, y ) do
		step = step + 1
		-- Now and then sidestep a cell or two, away from the start and the edge
		if step > 1 and remaining( x, y ) > 3 and math.random() < 0.3 then
			local sx, sy = dy ~= 0 and 1 or 0, dx ~= 0 and 1 or 0
			if math.random() < 0.5 then sx, sy = -sx, -sy end
			for _ = 1, math.random( 1, 2 ) do
				local nx, ny = x + sx, y + sy
				if nx < lo or nx > hi or ny < lo or ny > hi or grid.get( nx, ny ) then break end
				grid.connect( x, y, nx, ny )
				x, y = nx, ny
				path[#path + 1] = { x = x, y = y }
			end
		end
		local nx, ny = x + dx, y + dy
		if grid.get( nx, ny ) then break end -- don't run into another road
		grid.connect( x, y, nx, ny )
		x, y = nx, ny
		path[#path + 1] = { x = x, y = y }
	end
	return path
end

local function IsStraight( o )
	return ( o.n == 1 and o.s == 1 and o.e == 0 and o.w == 0 ) or ( o.e == 1 and o.w == 1 and o.n == 0 and o.s == 0 )
end

-- Rotation of the junction tile (opening east) for a dead end's single opening
local function JunctionRotation( o )
	if o.e == 1 then return 0 elseif o.n == 1 then return 1 elseif o.w == 1 then return 2 end
	return 3
end

-- Pacific Drive style roads: an irregular loop with a few exit roads running
-- off to the edge of the map, each ending in a junction. Returns the grid,
-- spawn cells (a straight cell near the outer end of each exit, with the index
-- of that exit's junction) and the junctions.
-- block: a landmark's cells ({ x, y, size, road }): the loop is a ring road
-- round it, or for a road tile one whose south side runs through its bottom row
local function GenerateRoads( exitCount, block )
	local grid = NewRoadGrid()
	if block then
		-- Its own cells: no exit roads start there, no anchors go there
		grid.blocked = {}
		for y = block.y, block.y + block.size - 1 do
			for x = block.x, block.x + block.size - 1 do grid.blocked[x .. "," .. y] = true end
		end
		local x0, y0, x1, y1 = block.x - 1, block.road and block.y or block.y - 1, block.x + block.size, block.y + block.size
		for x = x0, x1 - 1 do grid.connect( x, y0, x + 1, y0 ); grid.connect( x, y1, x + 1, y1 ) end
		for y = y0, y1 - 1 do grid.connect( x0, y, x0, y + 1 ); grid.connect( x1, y, x1, y + 1 ) end
	else
		BuildLoop( grid )
	end
	local hasLoop = false
	grid.each( function() hasLoop = true end )
	if not hasLoop then
		-- Degenerate random loop: fall back to a rectangle
		for x = -3, 2 do grid.connect( x, -3, x + 1, -3 ); grid.connect( x, 3, x + 1, 3 ) end
		for y = -3, 2 do grid.connect( -3, y, -3, y + 1 ); grid.connect( 3, y, 3, y + 1 ) end
	end

	local sides = { "n", "e", "s", "w" }
	for i = #sides, 2, -1 do
		local j = math.random( i )
		sides[i], sides[j] = sides[j], sides[i]
	end
	local spawnCells, junctions = {}, {}
	for i = 1, exitCount or math.random( ZONE_ROAD_EXITS_MIN, ZONE_ROAD_EXITS_MAX ) do
		local path = BuildExit( grid, sides[i] )
		local last = path[#path]
		local lastOpenings = last and grid.get( last.x, last.y )
		if lastOpenings and lastOpenings.s + lastOpenings.w + lastOpenings.n + lastOpenings.e == 1 then
			junctions[#junctions + 1] = { x = last.x, y = last.y, rotation = JunctionRotation( lastOpenings ) }
			for j = #path - 1, 1, -1 do
				if IsStraight( grid.get( path[j].x, path[j].y ) ) then
					local nextCell = path[j + 1]
					spawnCells[#spawnCells + 1] = { x = path[j].x, y = path[j].y, junction = #junctions,
						dir = { x = path[j].x - nextCell.x, y = path[j].y - nextCell.y } }
					break
				end
			end
		end
	end
	return grid, spawnCells, junctions
end

-- The road tile (and rotation) for a cell's openings and biome corners, or nil
local function RoadTileFor( openings, corners, biome )
	local wanted = { s = openings.s, w = openings.w, n = openings.n, e = openings.e, se = corners.se, sw = corners.sw, nw = corners.nw, ne = corners.ne }
	local path, rotation = FindRotatedTile( OPEN_ROAD_TILES, wanted, ROAD_KEYS, RotateRoad )
	if not path and biome then
		path, rotation = FindRotatedTile( biome.roads, wanted, ROAD_KEYS, RotateRoad )
	end
	return path, rotation
end

local function IsBorderCorner( x, y )
	return x <= ZONE_CELL_MIN + 1 or x >= ZONE_CELL_MAX or y <= ZONE_CELL_MIN + 1 or y >= ZONE_CELL_MAX
end

-- Which grid corners are forest (1) or meadow (0): mostly meadow with forest
-- patches, and solid forest around the edge of the map. Road cells must be
-- wholly forest or wholly meadow (there are no road tiles for forest edges).
local function GenerateCorners( grid, biome, skip, shareOverride )
	local share = shareOverride or biome.share or ZONE_FOREST_SHARE
	local corners = {}
	local interior, forested = 0, 0
	for y = ZONE_CELL_MIN, ZONE_CELL_MAX + 1 do
		corners[y] = {}
		for x = ZONE_CELL_MIN, ZONE_CELL_MAX + 1 do
			corners[y][x] = 0
			if not IsBorderCorner( x, y ) then interior = interior + 1 end
		end
	end

	-- Forest patches until the forest share is reached
	local attempts = 0
	while forested < interior * share and attempts < 300 do
		attempts = attempts + 1
		local px = ZONE_CELL_MIN + 2 + math.random() * ( ZONE_CELL_MAX - ZONE_CELL_MIN - 3 )
		local py = ZONE_CELL_MIN + 2 + math.random() * ( ZONE_CELL_MAX - ZONE_CELL_MIN - 3 )
		local radius = 1.5 + math.random() * 1.5
		for y = ZONE_CELL_MIN, ZONE_CELL_MAX + 1 do
			for x = ZONE_CELL_MIN, ZONE_CELL_MAX + 1 do
				if corners[y][x] == 0 and not IsBorderCorner( x, y ) and ( x - px ) ^ 2 + ( y - py ) ^ 2 < radius * radius then
					corners[y][x] = 1
					forested = forested + 1
				end
			end
		end
	end
	for y = ZONE_CELL_MIN, ZONE_CELL_MAX + 1 do
		for x = ZONE_CELL_MIN, ZONE_CELL_MAX + 1 do
			if IsBorderCorner( x, y ) then corners[y][x] = 1 end
		end
	end

	-- Every road cell needs a road tile for its forest corners. Where none exists,
	-- clear the cell to meadow (or, touching the forest border, fill it with
	-- forest). Any cells still left over after that become forest; cells only
	-- ever switch towards forest in that last pass, so it always finishes.
	local function cellCorners( x, y )
		return { se = corners[y][x + 1], sw = corners[y][x], nw = corners[y + 1][x], ne = corners[y + 1][x + 1] }
	end
	local function setCell( x, y, v )
		corners[y][x], corners[y][x + 1], corners[y + 1][x], corners[y + 1][x + 1] = v, v, v, v
	end
	local function touchesBorder( x, y )
		return IsBorderCorner( x, y ) or IsBorderCorner( x + 1, y ) or IsBorderCorner( x, y + 1 ) or IsBorderCorner( x + 1, y + 1 )
	end
	local function misfits()
		local list = {}
		grid.each( function( x, y, o )
			if not skip[x .. "," .. y] and not RoadTileFor( o, cellCorners( x, y ), biome ) then list[#list + 1] = { x = x, y = y } end
		end )
		return list
	end
	for _ = 1, 10 do
		local list = misfits()
		if #list == 0 then break end
		for _, c in ipairs( list ) do
			setCell( c.x, c.y, ( biome.roadsInBiome and touchesBorder( c.x, c.y ) ) and 1 or 0 )
		end
	end
	-- Whatever's left: forest has every road shape, so fill it in; other biomes
	-- clear to open ground, which also has every shape. Each pass only moves
	-- cells one way, so this always finishes.
	local fill = biome.roadsInBiome and 1 or 0
	local list = misfits()
	while #list > 0 do
		for _, c in ipairs( list ) do
			setCell( c.x, c.y, fill )
		end
		list = misfits()
	end
	return corners
end

-- Spots for anchor pedestals: next to a road, inside the forest border, spread out
local function PickAnchorCells( grid, count )
	local candidates = {}
	for y = ZONE_CELL_MIN + 2, ZONE_CELL_MAX - 2 do
		for x = ZONE_CELL_MIN + 2, ZONE_CELL_MAX - 2 do
			if not grid.get( x, y ) and not ( grid.blocked and grid.blocked[x .. "," .. y] ) and ( grid.get( x + 1, y ) or grid.get( x - 1, y ) or grid.get( x, y + 1 ) or grid.get( x, y - 1 ) ) then
				candidates[#candidates + 1] = { x = x, y = y }
			end
		end
	end
	local picked = {}
	for _ = 1, 200 do
		if #picked >= count or #candidates == 0 then break end
		local c = table.remove( candidates, math.random( #candidates ) )
		local farEnough = true
		for _, p in ipairs( picked ) do
			if math.abs( p.x - c.x ) + math.abs( p.y - c.y ) < 4 then farEnough = false break end
		end
		if farEnough then picked[#picked + 1] = c end
	end
	return picked
end

-- Ruins: a few rolls, each placing one beside the roads in a cell that is all
-- meadow or all forest, away from the map edge, anchors and other ruins
local function PickRuinCells( grid, corners, anchorCells, junctionAt, rolls )
	local taken = {}
	for _, c in ipairs( anchorCells ) do taken[c.x .. "," .. c.y] = true end
	local candidates = {}
	for y = ZONE_CELL_MIN + 2, ZONE_CELL_MAX - 2 do
		for x = ZONE_CELL_MIN + 2, ZONE_CELL_MAX - 2 do
			local sum = corners[y][x] + corners[y][x + 1] + corners[y + 1][x] + corners[y + 1][x + 1]
			local besideRoad = grid.get( x + 1, y ) or grid.get( x - 1, y ) or grid.get( x, y + 1 ) or grid.get( x, y - 1 )
			if not grid.get( x, y ) and besideRoad and ( sum == 0 or sum == 4 ) and not taken[x .. "," .. y] and not junctionAt[x .. "," .. y] then
				candidates[#candidates + 1] = { x = x, y = y, forest = sum == 4 }
			end
		end
	end
	local ruins = {}
	for _ = 1, rolls or ZONE_RUIN_ROLLS do
		if math.random() < ZONE_RUIN_CHANCE then
			for _ = 1, 20 do
				if #candidates == 0 then break end
				local c = table.remove( candidates, math.random( #candidates ) )
				local farEnough = true
				for _, r in ipairs( ruins ) do
					if math.abs( r.x - c.x ) + math.abs( r.y - c.y ) < 4 then farEnough = false break end
				end
				if farEnough then
					ruins[c.x .. "," .. c.y] = c
					ruins[#ruins + 1] = c
					break
				end
			end
		end
	end
	return ruins
end

-- Free cells for extra tiles (shacks, lakes, ...): not a road, junction or
-- something already placed, away from the map edge, all meadow (or, with
-- allowForest, all forest), beside a road if besideRoad. Picks up to count,
-- spread apart, and marks them taken.
local function PickFeatureCells( grid, corners, taken, junctionAt, count, besideRoad, allowForest )
	local candidates = {}
	for y = ZONE_CELL_MIN + 1, ZONE_CELL_MAX - 1 do
		for x = ZONE_CELL_MIN + 1, ZONE_CELL_MAX - 1 do
			local sum = corners[y][x] + corners[y][x + 1] + corners[y + 1][x] + corners[y + 1][x + 1]
			local nearRoad = grid.get( x + 1, y ) or grid.get( x - 1, y ) or grid.get( x, y + 1 ) or grid.get( x, y - 1 )
			if not grid.get( x, y ) and not taken[x .. "," .. y] and not junctionAt[x .. "," .. y]
				and ( sum == 0 or ( allowForest and sum == 4 ) ) and ( nearRoad or not besideRoad ) then
				candidates[#candidates + 1] = { x = x, y = y, forest = sum == 4 }
			end
		end
	end
	local picked = {}
	while #picked < count and #candidates > 0 do
		local c = table.remove( candidates, math.random( #candidates ) )
		local farEnough = true
		for _, p in ipairs( picked ) do
			if math.abs( p.x - c.x ) + math.abs( p.y - c.y ) < 3 then farEnough = false break end
		end
		if farEnough and not taken[c.x .. "," .. c.y] then
			taken[c.x .. "," .. c.y] = true
			picked[#picked + 1] = c
		end
	end
	return picked
end

-- Road points of interest (shacks, chemical plants): straight road cells in
-- open meadow, not a junction, landing spot or anchor, spread apart. Returns
-- { x, y, rotation } with the rotation that lines the tile's road up (0/2 for
-- a west-east road, 1/3 for south-north, as survival does).
local function PickRoadPoiCells( grid, corners, taken, junctionAt, avoid, count )
	local candidates = {}
	for y = ZONE_CELL_MIN + 1, ZONE_CELL_MAX - 1 do
		for x = ZONE_CELL_MIN + 1, ZONE_CELL_MAX - 1 do
			local o = grid.get( x, y )
			local sum = corners[y][x] + corners[y][x + 1] + corners[y + 1][x] + corners[y + 1][x + 1]
			local key = x .. "," .. y
			if o and IsStraight( o ) and sum == 0 and not taken[key] and not junctionAt[key] and not avoid[key] then
				candidates[#candidates + 1] = { x = x, y = y, rotation = ( o.e == 1 and 0 or 1 ) + math.random( 0, 1 ) * 2 }
			end
		end
	end
	local picked = {}
	while #picked < count and #candidates > 0 do
		local c = table.remove( candidates, math.random( #candidates ) )
		local farEnough = true
		for _, p in ipairs( picked ) do
			if math.abs( p.x - c.x ) + math.abs( p.y - c.y ) < 3 then farEnough = false break end
		end
		if farEnough then
			taken[c.x .. "," .. c.y] = true
			picked[#picked + 1] = c
		end
	end
	return picked
end

-- Ponds: corner points whose four cells are free and all meadow. Picks up to
-- count, spread apart, marks the cells taken and returns the points.
local function PickPondPoints( grid, corners, taken, junctionAt, count )
	local candidates = {}
	for py = ZONE_CELL_MIN + 2, ZONE_CELL_MAX - 1 do
		for px = ZONE_CELL_MIN + 2, ZONE_CELL_MAX - 1 do
			local ok = true
			for y = py - 1, py + 1 do
				for x = px - 1, px + 1 do
					if corners[y][x] ~= 0 then ok = false end
				end
			end
			for y = py - 1, py do
				for x = px - 1, px do
					if grid.get( x, y ) or taken[x .. "," .. y] or junctionAt[x .. "," .. y] then ok = false end
				end
			end
			if ok then candidates[#candidates + 1] = { x = px, y = py } end
		end
	end
	local picked = {}
	while #picked < count and #candidates > 0 do
		local p = table.remove( candidates, math.random( #candidates ) )
		local free = true
		for y = p.y - 1, p.y do
			for x = p.x - 1, p.x do
				if taken[x .. "," .. y] then free = false end
			end
		end
		if free then
			for y = p.y - 1, p.y do
				for x = p.x - 1, p.x do taken[x .. "," .. y] = true end
			end
			picked[#picked + 1] = p
		end
	end
	return picked
end

-- Returns the tile list, the cells to land the car on, the anchor cells, the
-- junctions and the liquid cells (water, oil, chemicals: no gateways there).
-- exitCount: how many exit roads (each ending in a junction); default random.
-- features: { shacks = 0-4, water = 0-4, oil = 0-4, chemicals = 0-4 } levels.
-- landmark: one of LANDMARKS, put in the middle (with a ring road round it).
function ZoneLayout( anchorCount, biomeName, ruinRolls, exitCount, features, landmark )
	local biome = ZONE_BIOMES[biomeName or "forest"] or ZONE_BIOMES.forest
	local deepTiles = biome.tiles[#biome.tiles].paths
	local block = landmark and { x = -math.floor( landmark.size / 2 ), y = -math.floor( landmark.size / 2 ), size = landmark.size, road = landmark.road }
	local grid, spawnCells, junctions = GenerateRoads( exitCount, block )
	local junctionAt = {}
	for _, j in ipairs( junctions ) do junctionAt[j.x .. "," .. j.y] = j end
	local corners = GenerateCorners( grid, biome, junctionAt, features and features.biomeShare )
	if block then
		-- Open ground round the landmark (its edges are meadow)
		for y = block.y - 1, block.y + block.size + 1 do
			for x = block.x - 1, block.x + block.size + 1 do
				if corners[y] and corners[y][x] then corners[y][x] = 0 end
			end
		end
	end
	local anchorCells = PickAnchorCells( grid, anchorCount or ZONE_ANCHORS_MAX )
	local ruins = PickRuinCells( grid, corners, anchorCells, junctionAt, ruinRolls )

	-- Shacks beside the roads, then the liquids
	features = features or {}
	local taken = {}
	for _, c in ipairs( anchorCells ) do taken[c.x .. "," .. c.y] = true end
	for _, r in ipairs( ruins ) do taken[r.x .. "," .. r.y] = true end
	if block then
		for y = block.y, block.y + block.size - 1 do
			for x = block.x, block.x + block.size - 1 do taken[x .. "," .. y] = true end
		end
	end
	local extras = {}
	local shackCount = 0
	for _ = 1, features.shacks or 0 do
		if math.random() < ZONE_SHACK_CHANCE then shackCount = shackCount + 1 end
	end
	-- (not on the landing spots either)
	local avoid = {}
	for _, c in ipairs( spawnCells ) do avoid[c.x .. "," .. c.y] = true end
	local flats = {} -- (kept level under the hills, see terrain.lua)
	-- Buildings and junctions sit on level ground: a flat spot over each cell
	local function levelCell( c )
		flats[#flats + 1] = { x = ( c.x + 0.5 ) * 64, y = ( c.y + 0.5 ) * 64, r = 46 }
	end
	for _, c in ipairs( PickRoadPoiCells( grid, corners, taken, junctionAt, avoid, shackCount ) ) do
		extras[c.x .. "," .. c.y] = { path = Pick( SHACK_TILES ), rotation = c.rotation }
		levelCell( c )
	end
	for _, r in ipairs( ruins ) do levelCell( r ) end
	for _, j in ipairs( junctions ) do levelCell( j ) end
	local liquids = {}
	local function level( name )
		return ZONE_LIQUID_TILE_COUNTS[name][math.max( math.min( features[name] or 0, 4 ), 0 )] or 0
	end
	-- Chemicals: plants on the road (half, rounded up), lakes for the rest
	local chemicals = level( "chemicals" )
	for _, c in ipairs( PickRoadPoiCells( grid, corners, taken, junctionAt, avoid, math.ceil( chemicals / 2 ) ) ) do
		extras[c.x .. "," .. c.y] = { path = Pick( CHEMICAL_ROAD_TILES ), rotation = c.rotation }
		liquids[#liquids + 1] = { x = c.x, y = c.y }
		flats[#flats + 1] = { x = ( c.x + 0.5 ) * 64, y = ( c.y + 0.5 ) * 64, r = 46 }
	end
	local bigTiles, covered = {}, {}
	if block then
		bigTiles[#bigTiles + 1] = { path = landmark.tile, x = block.x, y = block.y, size = block.size, rotation = 0 }
		flats[#flats + 1] = { x = ( block.x + block.size / 2 ) * 64, y = ( block.y + block.size / 2 ) * 64, r = block.size * 32 * 1.45 }
		for y = block.y, block.y + block.size - 1 do
			for x = block.x, block.x + block.size - 1 do covered[x .. "," .. y] = true end
		end
	end
	for _, p in ipairs( PickPondPoints( grid, corners, taken, junctionAt, math.floor( chemicals / 2 ) ) ) do
		bigTiles[#bigTiles + 1] = { path = Pick( CHEMICAL_LAKE_TILES ), x = p.x - 1, y = p.y - 1, size = 2, rotation = 0 }
		flats[#flats + 1] = { x = p.x * 64, y = p.y * 64, r = 92 }
		for y = p.y - 1, p.y do
			for x = p.x - 1, p.x do
				covered[x .. "," .. y] = true
				liquids[#liquids + 1] = { x = x, y = y }
			end
		end
	end
	-- Ponds: the four cells around the point each get the lake edge tile with
	-- the lake in the corner at the point
	for _, p in ipairs( PickPondPoints( grid, corners, taken, junctionAt, level( "water" ) ) ) do
		flats[#flats + 1] = { x = p.x * 64, y = p.y * 64, r = 92 }
		for y = p.y - 1, p.y do
			for x = p.x - 1, p.x do
				local wanted = {
					sw = ( x == p.x and y == p.y ) and 1 or 0, se = ( x + 1 == p.x and y == p.y ) and 1 or 0,
					nw = ( x == p.x and y + 1 == p.y ) and 1 or 0, ne = ( x + 1 == p.x and y + 1 == p.y ) and 1 or 0,
				}
				local path, rotation = FindRotatedTile( LAKE_TILES, wanted, CORNER_KEYS, RotateCorners )
				if path then
					extras[x .. "," .. y] = { path = path, rotation = rotation }
					liquids[#liquids + 1] = { x = x, y = y }
				end
			end
		end
	end
	for _, c in ipairs( PickFeatureCells( grid, corners, taken, junctionAt, level( "oil" ), false, false ) ) do
		extras[c.x .. "," .. c.y] = { path = Pick( OIL_TILES ), rotation = math.random( 0, 3 ) }
		liquids[#liquids + 1] = { x = c.x, y = c.y }
		flats[#flats + 1] = { x = ( c.x + 0.5 ) * 64, y = ( c.y + 0.5 ) * 64, r = 46 }
	end
	local tiles = {}
	for _, tile in ipairs( bigTiles ) do tiles[#tiles + 1] = tile end
	-- Two biomes and no meadow (features.mix, the Deep Zone): the corners say
	-- which, cell by cell (mostly biome corners = the biome, else the mix one).
	-- There are no tiles blending one biome into another, so it's whole cells.
	local mix = features.mix and ZONE_BIOMES[features.mix]
	local SOLID = { se = 1, sw = 1, nw = 1, ne = 1 }
	local OPEN = { se = 0, sw = 0, nw = 0, ne = 0 }
	for y = ZONE_CELL_MIN, ZONE_CELL_MAX do
		for x = ZONE_CELL_MIN, ZONE_CELL_MAX do
			local c = { se = corners[y][x + 1], sw = corners[y][x], nw = corners[y + 1][x], ne = corners[y + 1][x + 1] }
			local forestCorners = c.se + c.sw + c.nw + c.ne
			local openings = grid.get( x, y )
			local path, rotation
			local ruin = ruins[x .. "," .. y]
			local junction = junctionAt[x .. "," .. y]
			local cellBiome = mix and ( forestCorners >= 2 and biome or mix )
			if covered[x .. "," .. y] then
				-- (part of a 128m tile)
			elseif junction then
				path, rotation = JUNCTION_TILE, junction.rotation
			elseif extras[x .. "," .. y] then
				path, rotation = extras[x .. "," .. y].path, extras[x .. "," .. y].rotation
			elseif mix and ruin then
				path, rotation = Pick( cellBiome.ruins ), math.random( 0, 3 )
			elseif mix and openings then
				-- (the biome's own road for the shape, else an open-ground one)
				local wanted = { s = openings.s, w = openings.w, n = openings.n, e = openings.e, se = 1, sw = 1, nw = 1, ne = 1 }
				path, rotation = FindRotatedTile( cellBiome.roads, wanted, ROAD_KEYS, RotateRoad )
				if not path then
					path, rotation = RoadTileFor( openings, OPEN, nil )
				end
			elseif mix then
				path, rotation = Pick( cellBiome.tiles[#cellBiome.tiles].paths ), math.random( 0, 3 )
			elseif ruin then
				path, rotation = Pick( ruin.forest and biome.ruins or MEADOW_RUIN_TILES ), math.random( 0, 3 )
			elseif openings then
				path, rotation = RoadTileFor( openings, c, biome )
			elseif forestCorners == 0 then
				path, rotation = Pick( MEADOW_TILES ), math.random( 0, 3 )
			elseif forestCorners == 4 then
				path, rotation = Pick( deepTiles ), math.random( 0, 3 )
			else
				path, rotation = FindRotatedTile( biome.tiles, c, CORNER_KEYS, RotateCorners )
			end
			if path then
				tiles[#tiles + 1] = { path = path, x = x, y = y, size = 1, rotation = rotation or 0 }
			end
		end
	end
	-- Shallow chemical pools over the ground (the Mid Zone; terrain.lua dips the
	-- ground in each and puts the liquid in): { x, y, r } in metres
	local pools = {}
	local spec = features.pools
	if spec then
		local count = spec.count[math.max( math.min( features.chemicals or 0, 4 ), 0 )] or 0
		for _, c in ipairs( PickFeatureCells( grid, corners, taken, junctionAt, count, false, true ) ) do
			local r = spec.radius[1] + math.random() * ( spec.radius[2] - spec.radius[1] )
			local margin = math.min( r, 30 )
			local px = c.x * 64 + margin + math.random() * ( 64 - 2 * margin )
			local py = c.y * 64 + margin + math.random() * ( 64 - 2 * margin )
			pools[#pools + 1] = { x = math.floor( px ), y = math.floor( py ), r = math.floor( r ), depth = spec.depth }
			-- (level all round it, out past the corners of its square liquid surface)
			flats[#flats + 1] = { x = math.floor( px ), y = math.floor( py ), r = math.floor( r * 1.45 ) + 3 }
		end
	end
	-- Wetland (features.wetland: the Mid Zone always, now and then the others): flooded cells in big connected
	-- stretches (a smoothed random field, one value per 4 cells), never on the
	-- junctions, buildings, landing spots, anchors or other liquids. Sent as a
	-- bitmap (one character a cell) to stay small in the world data.
	local wet
	local wetland = features.wetland
	if wetland and math.random() < ( wetland.chance or 1 ) then
		local liquid = wetland.liquid or "chemicals"
		local share = wetland.share[math.max( math.min( features[liquid] or 0, 4 ), 0 )] or 0.5
		local field = {}
		local function at( i, j )
			local key = i .. "," .. j
			field[key] = field[key] or math.random()
			return field[key]
		end
		-- (buildings and junctions get a ring of dry ground round them too: the
		-- wetland's raised, dipped ground would cut a square round their tile)
		local function nearBuilding( x, y )
			for dy = -1, 1 do
				for dx = -1, 1 do
					local key = ( x + dx ) .. "," .. ( y + dy )
					if junctionAt[key] or ruins[key] or extras[key] or covered[key] then return true end
				end
			end
			return false
		end
		local bits = {}
		for y = ZONE_CELL_MIN, ZONE_CELL_MAX do
			for x = ZONE_CELL_MIN, ZONE_CELL_MAX do
				local fx, fy = x / 4, y / 4
				local ix, iy = math.floor( fx ), math.floor( fy )
				local tx, ty = fx - ix, fy - iy
				tx, ty = tx * tx * ( 3 - 2 * tx ), ty * ty * ( 3 - 2 * ty )
				local v = ( at( ix, iy ) * ( 1 - tx ) + at( ix + 1, iy ) * tx ) * ( 1 - ty )
					+ ( at( ix, iy + 1 ) * ( 1 - tx ) + at( ix + 1, iy + 1 ) * tx ) * ty
				local key = x .. "," .. y
				local dry = taken[key] or avoid[key] or nearBuilding( x, y )
				bits[#bits + 1] = ( not dry and v < share ) and "1" or "0"
			end
		end
		local size = ZONE_CELL_MAX - ZONE_CELL_MIN + 1
		wet = { x0 = ZONE_CELL_MIN, y0 = ZONE_CELL_MIN, w = size, h = size, bits = table.concat( bits ), depth = wetland.depth, cover = wetland.cover, liquid = liquid,
			soft = WETLAND_SLOPE_SOFTNESS }
	end
	-- The forest ring on the mountains outside (WORLD_RING)
	ForestRing( tiles, ZONE_CELL_MIN, ZONE_CELL_MAX, deepTiles )
	return tiles, spawnCells, anchorCells, junctions, liquids, flats, pools, wet
end

-- The rolling hills at a junction depth: the tier's (ZONE_TIERS hills), a bit
-- higher (20%) at every junction further in
function HillsFor( depth )
	local tier = ZoneTierOf( depth )
	local hills = tier.hills or ZONE_HILLS
	local step = math.max( ( depth or 1 ) - tier.first, 0 )
	return { amplitude = hills.amplitude * ( 1 + 0.2 * step ), scale = hills.scale }
end

-- The first junctions are built up more (ruins and farmer shacks) so the early
-- game has more to loot: the lowest building level (0-4) at these depths
ZONE_MIN_BUILDINGS = { [1] = 3, [2] = 2 }

function MinBuildingsFor( depth )
	return ZONE_MIN_BUILDINGS[depth or 0] or 0
end

-- Loot: junctions up to this depth use Survival's starting-area loot pools
-- (ruin chests and crates as near the crash site); deeper ones its normal pools.
-- The terrain tags their cells STARTAREA, which is how Survival tells them apart.
START_LOOT_DEPTH = 2


-- Storm helpers -----------------------------------------------------------------

-- Storm wall radius at a given game tick. storm = { center, r0, speed, startTick, minRadius }
function StormRadius( storm, tick )
	local elapsed = math.max( tick - storm.startTick, 0 ) / 40
	return math.max( storm.minRadius, storm.r0 - storm.speed * elapsed )
end

function DistanceXY( a, b )
	local dx, dy = a.x - b.x, a.y - b.y
	return math.sqrt( dx * dx + dy * dy )
end
