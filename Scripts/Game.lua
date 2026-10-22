dofile( "$SURVIVAL_DATA/Scripts/game/SurvivalGame.lua" )
dofile( "$CONTENT_DATA/Scripts/layouts.lua" )
dofile( "$CONTENT_DATA/Scripts/tilepack.lua" )
dofile( "$CONTENT_DATA/Scripts/survival_patches.lua" )

-- Pacific Drive style loop on top of survival:
--   garage junction (launch pad) --drive in / /depart--> zone
--   zone --drive into a junction at the end of an exit road--> a deeper zone
--   zone --open a gateway with the ARC Device, drive in--> garage
-- Travel uses sm.portal, the same thing the survival elevators use, so the
-- car (and anyone on it) comes along. The launch pad stays put; each run
-- gets a fresh portal from it to a random landing spot.
Game = class( SurvivalGame )

local WORLD_SCRIPT = "$CONTENT_DATA/Scripts/DriveWorld.lua"
local PAD_PORTAL_HALF_SIZE = sm.vec3.new( 6.0, 6.0, 4.0 )     -- 12m x 12m x 8m launch pad
local PAD_PORTAL_LIFT = 3.5                                   -- box center above the pad floor
local GATEWAY_PORTAL_HALF_SIZE = sm.vec3.new( 12.0, 12.0, 5.0 ) -- bigger than the gateway trigger so the whole car fits
local GATEWAY_PORTAL_LIFT = 4.0
local DEPART_DELAY_TICKS = 40 * 3
local RETURN_DELAY_TICKS = 12 -- (a portal needs a moment after its openings move, before it carries anything)
local FADE_DURATION = 0.5
local FADE_TIMEOUT = 15.0
local GATEWAY_EDGE_MARGIN = 40
local MISSILE_UUID = sm.uuid.new( "7daebf10-a0ce-11ed-a8fc-0242ac120002" ) -- the seeker bot's missile
local ARC_DEVICE_UUID = sm.uuid.new( "a6258a75-ea2b-47f7-acec-a3ace313bbd9" ) -- Objects/Database/ShapeSets/example.shapeset
local FABRICATOR_UUID = sm.uuid.new( "7ee97af5-72b9-4335-a3bd-e80d49dab105" ) -- upgrade tree bot
local REFINEBOT_UUID = sm.uuid.new( "5cb15c93-4fa9-48da-9974-2e95ca6c9e1c" ) -- survival refinebot
local MISSILE_GRACE_TICKS = 40 * 2 -- first volley comes this long after you leave the safe area
local JUNCTION_PORTAL_HALF_SIZE = sm.vec3.new( 14.0, 14.0, 6.0 ) -- grabs the car around the player at a zone junction
local HOLD_RADIUS = 18 -- while departing, the car is held still within this of the pad
local JUNCTION_COOLDOWN_TICKS = 40 * 15 -- after arriving somewhere, junctions ignore you for a bit
local OLD_ZONE_RETIRE_DELAY = 40 * 10 -- after arriving somewhere new, the zone left behind is retired
local INTRO_TIME_OF_DAY = 0.92 -- a new game starts at night (survival's time of day: 0.5 is noon)

-- Our quests (must match ScriptableObjects/ScriptableObjectSets/example.sobset)
local QUESTS = {
	quest_zone_run = { uuid = "91ad5ff8-e14f-475d-987b-54a5c68fec29", data = { title = "Into the Zone", mainQuest = true } },
	quest_zone_anchors = { uuid = "83cf70ec-adf4-48a3-89d4-30ad17562ec3", data = { title = "Energy Anchors", mainQuest = false } },
	quest_zone_conditions = { uuid = "4f2b8c6e-1d3a-4e7f-9b25-c8a6d0e3f417", data = { title = "Junction Conditions", mainQuest = false } },
	quest_expedition_checklist = { uuid = "6db1ccac-1e6e-45f0-ad8e-b437e4ae372c", data = { title = "Expedition Checklist", mainQuest = false } },
	quest_story_craftbot = { uuid = "fa2d0997-83a5-4e3a-aa7e-b4a6a5324036", data = { title = "Craftbot Online", mainQuest = true } },
	quest_story_arming = { uuid = "edf6d831-43ee-408e-b9c7-99b5af7532a1", data = { title = "Gearing Up", mainQuest = true } },
	quest_story_antenna = { uuid = "5cf8f169-6ede-4b2f-8dc8-dfb1d5090b24", data = { title = "Raise the Antenna", mainQuest = true } },
	quest_story_hideout = { uuid = "5ae26f1a-9b92-486d-bf25-b12fb8fe2706", data = { title = "Distress Call", mainQuest = true } },
	quest_story_farmers = { uuid = "f73539b7-fd8c-4d85-973c-62eb25b4e218", data = { title = "Roadside Picnic", mainQuest = true } },
	quest_story_getting_started = { uuid = "3b8e5f12-7a4c-4d91-a6e2-0c9f1b7d5e38", data = { title = "Getting Started", mainQuest = true } },
	quest_story_first_gateway = { uuid = "bbadb839-dff7-4c03-a46f-0555a9c03160", data = { title = "Into the Zone", mainQuest = true } },
	quest_story_outer = { uuid = "0130e643-099a-4680-b3af-fc182ee2f59b", data = { title = "The Outer Zone", mainQuest = true } },
	quest_story_mid = { uuid = "eb743495-d974-453c-ae8b-4d8c3ea17a19", data = { title = "The Mid Zone", mainQuest = true } },
	quest_story_antenna2 = { uuid = "3f9d6b2e-8c41-4a7e-b5d0-2e6a1c9f7b34", data = { title = "Boost the Signal", mainQuest = true } },
	quest_story_deep = { uuid = "9c31665f-e0d5-4d78-a4c3-a2d9db7f8440", data = { title = "The Deep Zone", mainQuest = true } },
}
local RUN_QUEST = "quest_zone_run" -- retired for now (kept free for the story); still registered for old saves
local ANCHOR_QUEST = "quest_zone_anchors" -- retired (beacons show the anchors); still registered for old saves
local CONDITIONS_QUEST = "quest_zone_conditions" -- likewise

local function CellOf( position )
	return math.floor( position.x / 64 ), math.floor( position.y / 64 )
end

local function ZoneCenter()
	local c = ( ZONE_CELL_MIN + ZONE_CELL_MAX + 1 ) * 32
	return sm.vec3.new( c, c, 0 )
end

-- Distance from a point to the farthest corner of the zone (a wall starting
-- there covers the whole zone)
local function FarthestZoneCorner( center )
	local lo, hi = ZONE_CELL_MIN * 64, ( ZONE_CELL_MAX + 1 ) * 64
	local farthest = 0
	for _, corner in ipairs( { sm.vec3.new( lo, lo, 0 ), sm.vec3.new( lo, hi, 0 ), sm.vec3.new( hi, lo, 0 ), sm.vec3.new( hi, hi, 0 ) } ) do
		farthest = math.max( farthest, DistanceXY( center, corner ) )
	end
	return farthest
end

-- The zone's edge for the terrain (ZONE_EDGE): its junctions are kept clear of the rim
function ZoneEdge( junctions )
	local clear = {}
	for _, junction in ipairs( junctions or {} ) do
		local spot = JunctionPadPosition( junction )
		clear[#clear + 1] = { x = math.floor( spot.x ), y = math.floor( spot.y ) }
	end
	return { rim = ZONE_EDGE.rim, width = ZONE_EDGE.width, mountains = ZONE_EDGE.mountains, clear = clear,
		bounds = EdgeBounds( ZONE_CELL_MIN, ZONE_CELL_MAX ) }
end

-- Sets up the zone world for a trip to a junction depth into saved (zone,
-- depth, spawn cells). node: the junction map's junction, whose biome and
-- conditions it uses. A new world, or (ZONE_POOL, zone_pool.lua) a pooled one
-- used again; a landmark's is made once and kept. leaving: the zone being
-- left through a junction (never the pooled one used next).
function CreateZone( saved, depth, node, leaving )
	local cost = GatewayCost( depth )
	local conditions = node and node.conditions or RollConditions( depth )
	-- Until the first escape, the zone never collapses on its own (First Gateway)
	if not ( saved.story and saved.story.escaped ) and not HasCondition( conditions, "stable" ) then
		local calm = { "stable" }
		for _, name in ipairs( conditions ) do
			if name ~= "unstable" then calm[#calm + 1] = name end
		end
		table.sort( calm )
		conditions = calm
	end
	local anchorCount = math.random( math.max( ZONE_ANCHORS_MIN, cost ), ZONE_ANCHORS_MAX )
	if node and node.anchors then
		anchorCount = #node.anchors -- exactly what the route planner showed
	elseif HasCondition( conditions, "anchorSurge" ) then
		anchorCount = anchorCount + CONDITION_ANCHOR_SURGE
	elseif HasCondition( conditions, "anchorDrought" ) then
		anchorCount = cost
	end
	local anchorKinds = {}
	for i = 1, anchorCount do
		anchorKinds[i] = ( node and node.anchors and node.anchors[i] ) or RollAnchorKind( node and NodeZoneDepth( node ) or depth )
	end
	-- A landmark (layouts.lua): its world is made once and kept
	local landmark = node and node.landmark and LandmarkByName( node.landmark )
	local known = landmark and saved.landmarks and saved.landmarks[landmark.name]
	-- (one made with an older layout is made again, once)
	if known and ( known.layout or 1 ) < LANDMARK_LAYOUT then
		known = nil
	end
	-- The zone pool: a world made before, used again (the junction has taken
	-- on its biome, buildings and liquids). Never the zone being left.
	local pooling = ZONE_POOL and node ~= nil and not landmark
	local record = pooling and ZonePoolTake( saved, node, leaving ) or nil
	-- (depth: the junction's number, for difficulty; zoneDepth: its zone, see
	-- NodeZoneDepth in JunctionMap.lua)
	local zoneDepth = node and NodeZoneDepth( node ) or depth
	local biome = node and ZONE_BIOMES[node.biome] and node.biome or ZoneBiomeForDepth( zoneDepth )
	-- Building density (route planner) = how many ruins
	local ruinRolls = node and node.buildings and ( node.buildings + 1 ) or nil
	-- Exits locked (not escaped yet, or a dead end): only the road you arrive by
	-- (a pooled world has all its roads: driving into a junction says they're locked)
	local locked = node ~= nil and not JunctionExitsOpen( node )
	-- Farmer shacks follow the building level; water, oil and chemicals the junction's levels
	local liquid = ZoneTierOf( zoneDepth ).liquid
	local features = {
		shacks = node and node.buildings or math.random( 0, 2 ),
		water = node and node.water or ( liquid == "water" and math.random() < 0.3 and 1 or 0 ),
		oil = node and node.oil or ( liquid == "oil" and math.random( 1, 2 ) or 0 ),
		chemicals = node and node.chemicals or ( liquid == "chemicals" and math.random( 1, 2 ) or 0 ),
	}
	local made = false
	if known and known.world then
		if not sm.exists( known.world ) then
			sm.world.loadWorld( known.world )
		end
		saved.zone = known.world
		saved.zoneSpawnCells = known.spawnCells
		saved.zoneLiquidCells = known.liquids or {}
	elseif record then
		if not sm.exists( record.world ) then
			sm.world.loadWorld( record.world )
		end
		saved.zone = record.world
		saved.zoneSpawnCells = record.spawnCells
		saved.zoneLiquidCells = record.liquids or {}
	else
		made = true
		if landmark then
			ruinRolls, features = 0, {}
		end
		local tier = ZoneTierOf( zoneDepth )
		if not landmark then
			features.biomeShare = ( tier.biomeShares and tier.biomeShares[zoneDepth] ) or tier.biomeShare
			features.pools = tier.pools
			features.mix = tier.mix
			-- (flooded or not was rolled with the junction, so the map shows it:
			-- node.wetland; without a junction, or one rolled before that, the
			-- tier's chance)
			local rolled = node and node.wetland
			local flooded = tier.wetland and ( rolled == true or ( rolled == nil and math.random() < ( tier.wetland.chance or 1 ) ) )
			if flooded then
				features.wetland = shallowcopy( tier.wetland )
				features.wetland.chance = 1
			end
		end
		-- (a pooled world keeps more spots for anchors than any one trip needs,
		-- and all its roads)
		local tiles, spawnCells, anchorCells, junctions, liquids, flats, pools, wet = ZoneLayout( pooling and ZONE_POOL_ANCHOR_SPOTS or anchorCount, biome, ruinRolls,
			landmark and 3 or ( ( locked and not pooling ) and 1 or nil ), features, landmark )
		if not pooling then
			for i, cell in ipairs( anchorCells ) do
				cell.kind = anchorKinds[i]
			end
		end
		-- (the tier's world class: its ground textures, ZONE_TIERS worldClass)
		local worldClass = not landmark and ZoneTierOf( zoneDepth ).worldClass or "ZoneWorld"
		saved.zone = sm.world.createWorld( WORLD_SCRIPT, worldClass, {
			tiles = PackTiles( tiles ), junctions = junctions, depth = depth, biome = biome, conditions = conditions,
			anchors = not pooling and anchorCells or nil, anchorSpots = pooling and anchorCells or nil,
			anomalies = node and node.anomalies, deadEnd = node and node.deadEnd, elevation = HillsFor( zoneDepth ), flats = flats, pools = pools, zone = zoneDepth,
			landmark = landmark and landmark.name, edge = ZoneEdge( junctions ), collapsed = node and node.collapsed,
			paint = not landmark and ZoneTierOf( zoneDepth ).paint or nil,
			foliage = not landmark and ZoneTierOf( zoneDepth ).foliage or nil,
			startLoot = depth <= START_LOOT_DEPTH or nil,
			wet = wet
		}, math.random( 1073741823 ) )
		saved.zoneSpawnCells = spawnCells
		saved.zoneLiquidCells = liquids -- (gateways stay off these)
		if landmark then
			saved.landmarks = saved.landmarks or {}
			saved.landmarks[landmark.name] = { world = saved.zone, spawnCells = spawnCells, liquids = liquids, layout = LANDMARK_LAYOUT }
		end
		if pooling then
			record = { world = saved.zone, biome = biome, buildings = node.buildings, water = features.water, oil = features.oil,
				chemicals = features.chemicals, wetland = wet ~= nil, spawnCells = spawnCells, liquids = liquids }
			ZonePoolAdd( saved, node, record )
		end
	end
	-- A pooled world gets what's new this trip (ZoneWorld.sv_startTrip): it
	-- reads g_zoneTrip, so it works whenever its script starts
	if pooling then
		saved.zoneTripId = ( saved.zoneTripId or 0 ) + 1
		record.used = saved.zoneTripId
		saved.zoneTrip = { id = saved.zoneTripId, world = saved.zone, depth = depth, zone = zoneDepth, conditions = conditions,
			anomalies = node.anomalies, collapsed = node.collapsed == true, locked = locked, anchors = anchorKinds }
		g_zoneTrip = saved.zoneTrip
	end
	saved.depth = depth
	saved.zoneDepth = zoneDepth
	saved.biome = biome
	saved.zoneConditions = conditions
	-- Route planner values for this junction (nil without the map)
	saved.zoneStability = node and node.stability
	saved.zoneStorm = node and node.storm
	saved.zoneNoExit = node ~= nil and JunctionNoExit( node )
	saved.zoneDeadEnd = node and node.deadEnd
	saved.zoneCollapsed = node ~= nil and node.collapsed == true
	saved.zoneLocked = locked
	g_gatewayCost = cost
	SetConditionsText( saved )
	sm.log.info( "[PacificScrap]", made and "New zone world" or "Zone world used again", saved.zone.id, "junction", depth, biome, "anchors", anchorCount,
		"gateway cost", cost, "conditions", table.concat( conditions, ", " ) )
end

-- Header + conditions for the "Junction Conditions" tracker entry
function SetConditionsText( saved )
	local biome = ZONE_BIOMES[saved.biome or "forest"] or ZONE_BIOMES.forest
	local text = ConditionsTrackerText( saved.zoneConditions )
	if saved.zoneLocked and not saved.zoneNoExit then
		text = "Exits locked" .. ( text == "Nothing unusual" and "" or "\n" .. text )
	end
	if saved.zoneNoExit then
		text = "No Stable Exits" .. ( text == "Nothing unusual" and "" or "\n" .. text )
	end
	g_zoneConditionsText = "JCT " .. ( saved.depth or 1 ) .. ": " .. biome.title .. "\n" .. text
end

local function UseGarageSpawn()
	-- Survival spawns and respawns at these; the garage world refines z once the cell loads
	if not START_AREA_SPAWN_POINT or START_AREA_SPAWN_POINT.x ~= GARAGE_SPAWN.x or START_AREA_SPAWN_POINT.y ~= GARAGE_SPAWN.y then
		START_AREA_SPAWN_POINT = sm.vec3.new( GARAGE_SPAWN.x, GARAGE_SPAWN.y, GARAGE_SPAWN.z )
	end
	SURVIVAL_DEV_SPAWN_POINT = START_AREA_SPAWN_POINT
end

function Game.server_onCreate( self )
	g_survivalDev = DEV_MODE
	g_disableRaids = true -- no farm raids (survival's crop raids)
	UseGarageSpawn()

	-- Pre-create our worlds so SurvivalGame loads them instead of generating the
	-- survival map. 'overworld' is the garage: survival code uses that name.
	local saved = self.storage:load()
	if saved == nil then
		saved = {}
		saved.data = self.data or {}
		saved.overworld = sm.world.createWorld( WORLD_SCRIPT, "GarageWorld", { tiles = PackTiles( GarageLayout() ), hasExit = true, edge = { mountains = GARAGE_EDGE.mountains, bounds = EdgeBounds( GARAGE_CELL_MIN, GARAGE_CELL_MAX ) } }, math.random( 1073741823 ) )
		CreateZone( saved, 1 )
		-- A new game starts at night, in a thunderstorm (until the first trip)
		saved.introWeather = true
		saved.introNight = true
		self.storage:save( saved )
	end

	SurvivalGame.server_onCreate( self )
	if self.sv.saved.introNight then
		self.sv.saved.introNight = nil
		self.sv.time.timeOfDay = math.floor( self.sv.time.timeOfDay ) + INTRO_TIME_OF_DAY
		self.sv.syncTimer.count = self.sv.syncTimer.ticks -- sync clients now
	end

	self.sv.jobs = {}
	self.sv.run = { state = "idle" }
	g_zoneRunStage = "garage"
	self:sv_storyInit()
	g_garagePowered = self.sv.saved.garagePowered == true
	-- A run saved in a zone with no stable exits whose exits are locked (the
	-- edge of the open tiers): it gets a gateway, so nobody is stuck there
	if self.sv.saved.zoneNoExit and self.sv.saved.map then
		local here = self.sv.saved.map.nodes[self.sv.saved.map.current]
		if here and not JunctionNoExit( here ) then
			self.sv.saved.zoneNoExit = false
			SetConditionsText( self.sv.saved )
		end
	end

	-- Resume a run that was in progress when the game was saved
	local savedRun = self.sv.saved.run
	if savedRun then
		self.sv.run = { state = "inZone", gateway = savedRun.gateway, collapseTick = savedRun.collapseTick, storm = savedRun.storm,
			warned = savedRun.warned, arrivedTick = sm.game.getCurrentTick() }
		self:sv_loadZone()
		-- The gateway, storm, countdown and weather go to the zone once its script
		-- is up (sooner, the messages get lost): Game.sv_e_zoneReady
		self.sv.resumePending = sm.game.getCurrentTick()
		self:sv_refreshStage()
	end

	if self.sv.saved.pad then
		sm.event.sendToWorld( self.sv.saved.overworld, "sv_e_setPad", self.sv.saved.pad )
	end

	g_currentZone = self.sv.saved.zone
	g_zoneTrip = self.sv.saved.zoneTrip -- (what's new this trip, for a pooled zone world: zone_pool.lua)
	g_gatewayCost = GatewayCost( self.sv.saved.depth )
	g_garageTrips = self.sv.saved.trips or 0
	g_testTier = self.sv.saved.testTier -- (/testtier)
	g_carKitPending = self.sv.saved.carKitPending == true
	-- Lift blueprints (Player.lua): LIFT_BLUEPRINTS, unless /liftblueprints changed it for this save
	if self.sv.saved.liftBlueprints ~= nil then
		g_liftBlueprints = self.sv.saved.liftBlueprints
	else
		g_liftBlueprints = LIFT_BLUEPRINTS
	end
	self:sv_setRespawn()
	SetConditionsText( self.sv.saved )
	self.sv.junctionCooldownTick = 0
	self.sv.saved.wipeQueue = nil -- (zones aren't wiped any more)
end

function Game.server_onFixedUpdate( self, timeStep )
	UseGarageSpawn()
	SurvivalGame.server_onFixedUpdate( self, timeStep )
	if sm.game.getCurrentTick() % 40 == 0 then
		ApplySurvivalPatches()
	end
	self:sv_registerQuest()
	-- The new game's thunderstorm (once survival's weather is up; it ends on the first trip)
	if self.sv.saved.introWeather and not self.sv.introWeatherOn and WeatherManager and WeatherManager.Sv_StartCondition
		and sm.game.getCurrentTick() % 40 == 3 then
		self.sv.introWeatherOn = true
		WeatherManager.Sv_StartCondition( "ThunderRain" )
		self.sv.forcedWeather = true
	end
	-- (the zone never said it was ready: resume anyway)
	if self.sv.resumePending and sm.game.getCurrentTick() - self.sv.resumePending > 40 * 10 and sm.exists( self.sv.saved.zone ) then
		self:sv_resumeRun()
	end
	-- (an older save may have the hideout's logbook entry already: taken out)
	if not self.sv.hideoutLogChecked and LogEntryManager and LOGS and LOGS.log_hideout then
		self.sv.hideoutLogChecked = true
		pcall( function()
			if LogEntryManager.Sv_HasLog( LOGS.log_hideout ) then LogEntryManager.Sv_RemoveLog( LOGS.log_hideout ) end
		end )
	end
	-- The garage junction's gate: open once a route is set, and while setting off
	-- (GarageWorld.sv_updateJunctionGate)
	if sm.game.getCurrentTick() % 10 == 0 then
		local run, map = self.sv.run, self.sv.saved.map
		g_garageGateWanted = run ~= nil and ( run.state == "departing"
			or ( run.state == "idle" and map ~= nil and map.destination ~= nil ) )
	end
	self:sv_storyUpdate()
	self:sv_updateStorm()

	local run = self.sv.run
	-- Choosing on the junction map: keep the car parked
	local choice = self.sv.jmChoice
	if choice and sm.game.getCurrentTick() % 4 == 0 then
		sm.event.sendToWorld( choice.hold.world, "sv_e_stopBodiesNear", { position = choice.hold.position, radius = HOLD_RADIUS } )
	end
	-- Departing: keep the car parked on the pad/junction until it's carried off
	if run.state == "departing" and run.hold and sm.game.getCurrentTick() % 4 == 0 then
		sm.event.sendToWorld( run.hold.world, "sv_e_stopBodiesNear", { position = run.hold.position, radius = HOLD_RADIUS } )
	end
	if run.timer then
		run.timer = run.timer - 1
		if run.timer <= 0 then
			run.timer = nil
			if run.state == "departing" then
				self:sv_finishDeparture()
			elseif run.state == "returning" then
				self:sv_finishReturn()
			end
		end
	end

	-- Delayed jobs
	local remaining = {}
	for _, job in ipairs( self.sv.jobs ) do
		job.ticks = job.ticks - 1
		if job.ticks <= 0 then
			job.fn()
		else
			remaining[#remaining + 1] = job
		end
	end
	self.sv.jobs = remaining
end

function Game.sv_after( self, ticks, fn )
	self.sv.jobs[#self.sv.jobs + 1] = { ticks = ticks, fn = fn }
end

function Game.sv_saveGame( self )
	self.storage:save( self.sv.saved )
end

function Game.sv_loadZone( self )
	if not sm.exists( self.sv.saved.zone ) then
		sm.world.loadWorld( self.sv.saved.zone )
	end
end

-- No crash-site intro or tutorial quest here
function Game.client_onLoadingScreenLifted( self )
	EffectManager.Cl_OnLoadingScreenLifted()
	TutorialManager.Cl_OnLoadingScreenLifted()
end

function Game.sv_n_loadingScreenLifted( self, _, player )
end


-- Quest -----------------------------------------------------------------------

-- QuestManager only reads the survival quest list, so add ours to it once it exists
function Game.sv_registerQuest( self )
	local questManager = g_questManagerServer
	if self.sv.questRegistered or not questManager or not questManager.sv or not questManager.sv.quests then
		return
	end
	for name, quest in pairs( QUESTS ) do
		questManager.sv.quests[name] = sm.uuid.new( quest.uuid )
		questManager.sv.questData[name] = quest.data
	end
	self.sv.questRegistered = true

	-- The run quest isn't used any more: take it off saves that still have it
	QuestManager.Sv_TryAbandonQuest( RUN_QUEST )
	self:sv_refreshStage()
end

function Game.client_onFixedUpdate( self, dt )
	SurvivalGame.client_onFixedUpdate( self, dt )
	if sm.game.getCurrentTick() % 40 == 20 then
		ApplySurvivalPatches()
	end
	-- Phone calls (Dialogs.lua): our lines in survival's dialog manager, a sound per bubble
	self:cl_dialogsEnsure()
	self:cl_dialogsUpdate()
	local questManager = g_questManagerClient
	if questManager and questManager.cl and questManager.cl.questData then
		for name, quest in pairs( QUESTS ) do
			questManager.cl.questData[name] = questManager.cl.questData[name] or quest.data
		end
	end
end


-- Helpers ---------------------------------------------------------------------

function Game.sv_message( self, player, text )
	self.network:sendToClient( player, "client_showMessage", text )
end

-- Status messages: log only (the HUD, quest tracker and sounds tell the player)
function Game.sv_broadcast( self, text )
	sm.log.info( "[PacificScrap]", text )
end

local function IsInsideBox( position, center, halfSize )
	local d = position - center
	return math.abs( d.x ) <= halfSize.x and math.abs( d.y ) <= halfSize.y and math.abs( d.z ) <= halfSize.z
end

function Game.sv_playersInBox( self, world, center, halfSize )
	local players = {}
	for _, player in ipairs( sm.player.getAllPlayers() ) do
		local character = player.character
		if character and sm.exists( character ) and character:getWorld() == world and IsInsideBox( character.worldPosition, center, halfSize ) then
			players[#players + 1] = player
		end
	end
	return players
end

-- True when every player has a character and none of them are in the zone.
-- Players without a character (dead, loading in) keep the run alive.
function Game.sv_runAbandoned( self )
	local players = sm.player.getAllPlayers()
	if #players == 0 then
		return false
	end
	for _, player in ipairs( players ) do
		local character = player.character
		if not character or not sm.exists( character ) or character:getWorld() == self.sv.saved.zone then
			return false
		end
	end
	return true
end

function Game.sv_anyPlayerIn( self, world )
	for _, player in ipairs( sm.player.getAllPlayers() ) do
		local character = player.character
		if character and sm.exists( character ) and character:getWorld() == world then
			return true
		end
	end
	return false
end

function Game.sv_fade( self, players, start, timeout )
	for _, player in ipairs( players ) do
		if start then
			sm.event.sendToPlayer( player, "sv_startFadeToBlack", { duration = FADE_DURATION, timeout = timeout or FADE_TIMEOUT } )
		else
			sm.event.sendToPlayer( player, "sv_endFadeToBlack", { duration = FADE_DURATION } )
		end
	end
end

function Game.sv_releaseLater( self, ticks, handle, portal )
	self:sv_after( ticks, function()
		-- pcall: the handle's world may have been destroyed by a zone reset meanwhile
		if handle then
			pcall( function() handle:release() end )
		end
		if portal and sm.exists( portal ) then
			sm.portal.destroy( portal )
		end
	end )
end

function Game.server_onPlayerJoined( self, player, newPlayer )
	SurvivalGame.server_onPlayerJoined( self, player, newPlayer )
	-- New players start with survival's sledgehammer and lift only; everything
	-- else comes from the Friendly Dumpster by the garage exit
end

function Game.sv_sendHome( self, player )
	local x, y = CellOf( START_AREA_SPAWN_POINT )
	self.sv.saved.overworld:loadCell( x, y, player, "sv_createNewPlayer" )
end

-- Every junction gets its zone world: a new one, or with the zone pool one made
-- before (zone_pool.lua). The old one is retired: it stays in the save (about
-- 2 MB, mostly its trees) and isn't loaded again unless the pool picks it.
-- Emptying it wouldn't shrink the save (removed trees stay
-- as "removed" records) and is slow. Do NOT world:destroy() it: that leaves its
-- contents in the save file, and loading a save with those leftovers hangs.
-- keepOld: the zone is being left through a junction; the caller retires it
-- once everyone has been carried out. Returns the old zone.
function Game.sv_resetZone( self, depth, keepOld, node )
	local old = self.sv.saved.zone
	if old and not keepOld then
		for _, player in ipairs( sm.player.getAllPlayers() ) do
			local character = player.character
			if character and sm.exists( character ) and character:getWorld() == old then
				self:sv_sendHome( player )
			end
		end
		self:sv_retireZone( old )
	end
	g_zoneAnchorsLeft = nil -- set again by the new zone
	CreateZone( self.sv.saved, depth or 1, node, keepOld and old or nil )
	g_currentZone = self.sv.saved.zone
	self:sv_saveGame()
	return old
end

-- A zone left for good: retired (it stops doing anything and never loads
-- again; see ZoneWorld.sv_e_retire)
function Game.sv_retireZone( self, world )
	-- (landmark worlds are kept for the next visit)
	for _, landmark in pairs( self.sv.saved.landmarks or {} ) do
		if landmark.world == world then return end
	end
	if world and sm.exists( world ) then
		sm.event.sendToWorld( world, "sv_e_retire" )
	end
end

-- The garage exit's cell loaded: that's where gateway returns land
-- The battery is in the garage's socket (GarageWorld.sv_findSocket)
function Game.sv_e_garagePowered( self )
	if not self.sv.saved.garagePowered then
		self.sv.saved.garagePowered = true
		g_garagePowered = true
		self:sv_storyAdvance( false )
		self:sv_saveGame()
		sm.log.info( "[PacificScrap] Garage powered" )
	end
end

function Game.sv_e_exitFound( self, params )
	self.sv.saved.exitGround = params.ground
	self:sv_saveGame()
	self:sv_setRespawn()
end

-- Players who die (and have no bed) come back at the garage exit, facing the
-- station (survival_patches.lua PatchedGetSpawner)
function Game.sv_setRespawn( self )
	local ground = self.sv.saved.exitGround
	if ground then
		local facing = JunctionOpening( GARAGE_EXIT )
		-- (a little back up the exit road: towed cars land on the exit spot)
		g_pacificRespawn = { position = ground - facing * 8 + sm.vec3.new( 0, 0, 0.2 ), rotation = sm.vec3.getRotation( sm.vec3.new( 0, 0, 1 ), facing ) }
	end
end

-- The run ended without the gateway (everyone died, /home): like in Pacific
-- Drive the car is towed home, to the garage exit, with what's in it, and so
-- is the bag your things dropped in. The zone finds them where its players last
-- were (ZoneWorld.sv_e_findRecoverables) and Game.sv_e_recoverFound moves them.
function Game.sv_recoverVehicles( self )
	local zone = self.sv.saved.zone
	if not zone or not sm.exists( zone ) then return end
	local exit = self:sv_returnGround()
	local gx, gy = CellOf( exit )
	local handle = self.sv.saved.overworld:loadCellWithHandle( gx, gy )
	self:sv_releaseLater( 40 * 15, handle, nil )
	sm.event.sendToWorld( zone, "sv_e_findRecoverables" )
end

-- Multiplayer: a player who was in the zone and is back at the garage while
-- the run goes on (died and respawned, /home) gets their car and things
-- towed home now, as if their run had ended (once per trip; nothing the others
-- still in the zone are near: ZoneWorld.sv_e_findRecoverables)
function Game.sv_towForLostPlayers( self )
	local run = self.sv.run
	local zone, garage = self.sv.saved.zone, self.sv.saved.overworld
	run.wasInZone = run.wasInZone or {}
	run.towedFor = run.towedFor or {}
	-- (nobody left in the zone: the run's over, and its own towing takes everything)
	if not self:sv_anyPlayerIn( zone ) then return end
	for _, player in ipairs( sm.player.getAllPlayers() ) do
		local key = tostring( player.id )
		local character = player.character
		if character and sm.exists( character ) then
			local world = character:getWorld()
			if world == zone then
				run.wasInZone[key] = true
			elseif world == garage and run.wasInZone[key] and not run.towedFor[key] then
				run.towedFor[key] = true
				local gx, gy = CellOf( self:sv_returnGround() )
				self:sv_releaseLater( 40 * 15, garage:loadCellWithHandle( gx, gy ), nil )
				sm.event.sendToWorld( zone, "sv_e_findRecoverables", { player = key } )
				sm.log.info( "[PacificScrap]", player.name, "left the run early: towing their things home" )
			end
		end
	end
end

local RECOVER_SPACING = 9 -- metres between towed things at the garage exit
local CAR_MIN_SHAPES = 6 -- a towed creation this big counts as a car

-- Creations ({ center, half, bottom, shapes }) moved from the zone to the
-- garage exit, each through its own portal, side by side. firstSlot: 1 = the
-- exit spot itself, 2 on = beside it (a gateway return's car takes the spot).
function Game.sv_towToGarage( self, zone, items, firstSlot )
	local floor = self:sv_exitFloor()
	local exitDir = JunctionOpening( GARAGE_EXIT )
	local side = sm.vec3.new( -exitDir.y, exitDir.x, 0 )
	for n, item in ipairs( items or {} ) do
		local i = n + ( firstSlot or 1 ) - 1
		local offset = side * ( ( i - 1 ) * RECOVER_SPACING * ( i % 2 == 0 and 1 or -1 ) * 0.5 )
		local out = floor + offset + sm.vec3.new( 0, 0, item.center.z - item.bottom + 0.6 )
		local portal = sm.portal.createPortal( item.half )
		portal:setOpeningA( item.center, sm.quat.identity(), zone )
		portal:setOpeningB( out, sm.quat.identity(), self.sv.saved.overworld )
		self:sv_after( 3, function() if sm.exists( portal ) then portal:transferAToB() end end )
		self:sv_releaseLater( 60, nil, portal )
	end
end

-- A creation as something to tow: the box round all its bodies (marked in seen)
local function TowItem( body, seen )
	local low, high
	local shapes = 0
	for _, b in ipairs( body:getCreationBodies() ) do
		seen[b.id] = true
		shapes = shapes + #b:getShapes()
		local ok, a, c = pcall( function() return b:getWorldAabb() end )
		if ok and a then
			low = low and sm.vec3.new( math.min( low.x, a.x ), math.min( low.y, a.y ), math.min( low.z, a.z ) ) or a
			high = high and sm.vec3.new( math.max( high.x, c.x ), math.max( high.y, c.y ), math.max( high.z, c.z ) ) or c
		end
	end
	if not low then return nil end
	return { center = ( low + high ) * 0.5, half = ( high - low ) * 0.5 + sm.vec3.new( 1, 1, 1 ), bottom = low.z, shapes = shapes }
end

function Game.sv_e_recoverFound( self, params )
	local zone = self.sv.saved.zone
	-- One player's things while the run goes on (sv_towForLostPlayers): beside
	-- the exit spot, out of the way of the others' return
	if params.partial then
		local run = self.sv.run
		run.towSlot = ( run.towSlot or 2 )
		self:sv_towToGarage( zone, params.items, run.towSlot )
		run.towSlot = run.towSlot + #( params.items or {} )
		if #( params.items or {} ) > 0 then
			sm.log.info( "[PacificScrap] Towed home a lost player's", #params.items, "creations" )
		end
		return
	end
	self:sv_towToGarage( zone, params.items, 1 )
	if #( params.items or {} ) > 0 then
		sm.log.info( "[PacificScrap] Towed home:", #params.items, "creations" )
	end
	-- No car among them (a car: a creation of CAR_MIN_SHAPES parts or more): the
	-- Friendly Dumpster gives a car starter kit (DUMPSTER_CAR_KIT)
	local car = false
	for _, item in ipairs( params.items or {} ) do
		if ( item.shapes or 0 ) >= CAR_MIN_SHAPES then car = true end
	end
	if not car then
		self:sv_carKitPending()
	end
end

-- No car came home (a failed run, or an escape on foot): the Friendly Dumpster
-- has a car starter kit (DUMPSTER_CAR_KIT)
function Game.sv_carKitPending( self )
	self.sv.saved.carKitPending = true
	g_carKitPending = true
	self:sv_saveGame()
	sm.log.info( "[PacificScrap] No car came home: the dumpster has a car kit" )
end

-- Towing found a car on a lift (ZoneWorld.sv_stepRecover): the lift goes so
-- the car drops and can be towed. params.player: only that player's (mid-run,
-- sv_towForLostPlayers); else everyone's (a failed run: lifts can't be asked
-- where they are, so one placed in the garage is taken away too: whatever's
-- on it just drops where it is)
function Game.sv_e_dropLifts( self, params )
	for _, player in ipairs( sm.player.getAllPlayers() ) do
		if not params.player or tostring( player.id ) == params.player then
			local ok = pcall( sm.player.removeLift, player )
			sm.log.info( "[PacificScrap] Towing: took", player.name, "'s lift away so the car on it drops", ok and "" or "(failed)" )
		end
	end
end

-- The Friendly Dumpster handed out the car kit
function Game.sv_e_carKitGiven( self )
	self.sv.saved.carKitPending = nil
	g_carKitPending = false
	self:sv_saveGame()
end

-- Back from a gateway: a player still in the zone (outside the gateway when it
-- went, e.g. out of the car) is brought home too, onto the garage exit
-- (to: where to, in toWorld, the garage by default)
function Game.sv_rescueLeftBehind( self, zone, arrival, toWorld )
	toWorld = toWorld or self.sv.saved.overworld
	for _, player in ipairs( sm.player.getAllPlayers() ) do
		local character = player.character
		if character and sm.exists( character ) and zone and sm.exists( zone ) and character:getWorld() == zone then
			local portal = sm.portal.createPortal( sm.vec3.new( 2.0, 2.0, 2.5 ) )
			portal:setOpeningA( character.worldPosition, sm.quat.identity(), zone )
			portal:setOpeningB( arrival + sm.vec3.new( 0, 0, 1.0 ), sm.quat.identity(), toWorld )
			-- (a moment later: a new portal needs that before it carries anything)
			self:sv_after( 3, function() if sm.exists( portal ) then portal:transferAToB() end end )
			self:sv_releaseLater( 40, nil, portal )
			sm.log.warning( "[PacificScrap] Brought", player.name, "along: the portal missed them" )
		end
	end
end

-- What players carry on their lift (g_liftCarry, survival_patches.lua) comes
-- through with them, each creation through its own portal, landing beside
-- them. It has to go in the same moment they do: once they've left, its area
-- unloads and it's gone. And a portal needs a few ticks before it carries
-- anything, so: sv_prepareCarried when the trip starts (opening A on it),
-- sv_landCarried once the landing spot is known (opening B), sv_sendCarried
-- just before the main portal goes.
function Game.sv_prepareCarried( self, travellers, fromWorld )
	local list = {}
	for _, player in ipairs( travellers or {} ) do
		local body = g_liftCarry and g_liftCarry[player.id]
		if body and sm.exists( body ) and body:getWorld() == fromWorld then
			local item = TowItem( body, {} )
			if item then
				local portal = sm.portal.createPortal( item.half )
				portal:setOpeningA( item.center, sm.quat.identity(), fromWorld )
				list[#list + 1] = { portal = portal, body = body, item = item, player = player, from = fromWorld }
			end
		end
	end
	return list
end

function Game.sv_landCarried( self, list, landing, toWorld )
	for i, entry in ipairs( list or {} ) do
		if sm.exists( entry.portal ) and not entry.to then
			local out = landing + sm.vec3.new( 6 * i, 0, entry.item.center.z - entry.item.bottom + 1.0 )
			entry.portal:setOpeningB( out, sm.quat.identity(), toWorld )
			entry.to, entry.out = toWorld, out
		end
	end
end

function Game.sv_sendCarried( self, list )
	for _, entry in ipairs( list or {} ) do
		local portal, body = entry.portal, entry.body
		if sm.exists( portal ) and entry.to then
			if sm.exists( body ) and body:getWorld() == entry.from then
				portal:transferAToB()
				sm.log.info( "[PacificScrap] Brought", entry.player.name, "'s lifted creation along, to", entry.out )
			else
				sm.log.info( "[PacificScrap] Lifted creation not moved: it", sm.exists( body ) and "had moved world already" or "no longer exists" )
			end
		end
		self:sv_releaseLater( 60, nil, portal )
	end
end

-- Players in the garage within PAD_GATHER_RADIUS of the launch pad who weren't
-- on it go to the landing spot too (a little apart, beside it)
local PAD_GATHER_RADIUS = 25
function Game.sv_bringNearPad( self, travellers, landing, toWorld )
	if not landing then return end
	local taken = {}
	for _, player in ipairs( travellers ) do taken[player.id] = true end
	local garage, pad, count = self.sv.saved.overworld, self:sv_padCenter(), 0
	for _, player in ipairs( sm.player.getAllPlayers() ) do
		local character = player.character
		if not taken[player.id] and character and sm.exists( character ) and character:getWorld() == garage
			and DistanceXY( character.worldPosition, pad ) < PAD_GATHER_RADIUS then
			count = count + 1
			local portal = sm.portal.createPortal( sm.vec3.new( 2.0, 2.0, 2.5 ) )
			portal:setOpeningA( character.worldPosition, sm.quat.identity(), garage )
			portal:setOpeningB( landing + sm.vec3.new( 3 * count, 0, 2.0 ), sm.quat.identity(), toWorld )
			self:sv_after( 3, function() if sm.exists( portal ) then portal:transferAToB() end end )
			self:sv_releaseLater( 40, nil, portal )
			sm.log.info( "[PacificScrap] Brought", player.name, "along from beside the launch pad" )
		end
	end
end

-- Where you come back to from a gateway (the exit tile, or the pad before it's
-- known), a little above the floor so nobody lands inside it
local RETURN_LIFT = 1.5
local RETURN_MAX_SPEED = 30 -- (m/s) faster than this through a gateway is slowed to it
local RETURN_GATHER_RADIUS = 30 -- players this close to the gateway when it's reached go home (with what they sit in)
-- The garage exit's floor itself
function Game.sv_exitFloor( self )
	return self:sv_returnGround() - sm.vec3.new( 0, 0, RETURN_LIFT )
end

function Game.sv_returnGround( self )
	return ( self.sv.saved.exitGround or self.sv.saved.pad.ground ) + sm.vec3.new( 0, 0, RETURN_LIFT )
end

function Game.sv_padCenter( self )
	return self.sv.saved.pad.ground + sm.vec3.new( 0, 0, PAD_PORTAL_LIFT )
end

-- Quest tracker text follows the run state (see ZoneRunQuest.lua)
function Game.sv_refreshStage( self )
	local run = self.sv.run
	if run.state ~= "inZone" and run.state ~= "returning" then
		g_zoneRunStage = "garage"
	elseif run.storm then
		g_zoneRunStage = run.gateway and "stormGateway" or "storm"
	else
		g_zoneRunStage = run.gateway and "gateway" or "zone"
	end

	-- The conditions side quest only exists while a run is in the zone
	-- (activation is asynchronous, so act on changes of the wanted state only)
	if self.sv.questRegistered then
		local wanted = run.state == "inZone" or run.state == "returning"
		-- The old anchors quest: take it off saves that still have it
		if not self.sv.anchorQuestCleared then
			self.sv.anchorQuestCleared = true
			QuestManager.Sv_TryAbandonQuest( ANCHOR_QUEST )
		end
		if self.sv.conditionsQuestOn == nil then
			self.sv.conditionsQuestOn = QuestManager.Sv_IsQuestActive( CONDITIONS_QUEST )
		end
		if wanted ~= self.sv.conditionsQuestOn then
			self.sv.conditionsQuestOn = wanted
			if wanted then
				QuestManager.Sv_ActivateQuest( CONDITIONS_QUEST )
			else
				QuestManager.Sv_AbandonQuest( CONDITIONS_QUEST )
			end
		end
	end
end

-- Pacific Drive skips time when you travel; do the same on each trip
function Game.sv_advanceTime( self )
	local hours = TRAVEL_HOURS_MIN + math.random() * ( TRAVEL_HOURS_MAX - TRAVEL_HOURS_MIN )
	self.sv.time.timeOfDay = self.sv.time.timeOfDay + hours / 24
	self.sv.syncTimer.count = self.sv.syncTimer.ticks -- sync clients now
end

function Game.sv_saveRun( self )
	local run = self.sv.run
	self.sv.saved.run = { gateway = run.gateway, collapseTick = run.collapseTick, storm = run.storm, warned = run.warned }
	self:sv_saveGame()
end

-- A zone world's script is up (ZoneWorld.server_onCreate). A run loaded from a
-- save gets its gateway, storm, countdown and weather back now.
function Game.sv_e_zoneReady( self, params )
	if params.world == self.sv.saved.zone and self.sv.resumePending then
		self:sv_resumeRun()
	end
end

function Game.sv_resumeRun( self )
	self.sv.resumePending = nil
	local run = self.sv.run
	if run.state ~= "inZone" then return end
	if run.gateway then
		self:sv_loadGatewayCell()
	end
	sm.event.sendToWorld( self.sv.saved.zone, "sv_e_setStorm", run.storm or {} )
	if run.collapseTick then
		sm.event.sendToWorld( self.sv.saved.zone, "sv_e_setCollapseTick", { tick = run.collapseTick } )
	end
	self:sv_setZoneWeather( self.sv.saved.zoneConditions )
	sm.log.info( "[PacificScrap] Run resumed: gateway", run.gateway ~= nil, "storm", run.storm ~= nil )
end

-- abandoned = the run ended without going through the gateway (death, /home),
-- so the handles and portal the return would have cleaned up are released here
function Game.sv_endRun( self, abandoned )
	local run = self.sv.run
	if abandoned then
		self:sv_recoverVehicles()
	end
	sm.event.sendToWorld( self.sv.saved.zone, "sv_e_clearGateway" )
	sm.event.sendToWorld( self.sv.saved.zone, "sv_e_setStorm", {} )
	if run.gatewayHandle then
		run.gatewayHandle:release()
	end
	if abandoned then
		if run.garageHandle then
			run.garageHandle:release()
		end
		if run.returnPortal and sm.exists( run.returnPortal ) then
			sm.portal.destroy( run.returnPortal )
		end
	end
	self.sv.run = { state = "idle" }
	self.sv.saved.run = nil
	-- Every finished trip refills the Friendly Dumpster
	self.sv.saved.trips = ( self.sv.saved.trips or 0 ) + 1
	g_garageTrips = self.sv.saved.trips
	self:sv_saveGame()
	self:sv_refreshStage()
	self:sv_setZoneWeather( nil ) -- back to survival's own forecast
	if not abandoned then
		-- Escaped through a gateway: the main quest counts it
		local map = self:sv_jmMap()
		local escapedFrom = map.nodes[map.current]
		self:sv_storyOnEscape( escapedFrom and escapedFrom.depth or self.sv.saved.depth or 1 )
	end
	self:sv_jmReturnHome( not abandoned )
end


-- Launch pad ------------------------------------------------------------------

-- position: put the pad there instead of under the player
function Game.sv_requestPad( self, player, thenDepart, position )
	if self.sv.run.state ~= "idle" then
		self:sv_message( player, "Can't move the launch pad during a run." )
		return
	end
	sm.event.sendToWorld( self.sv.saved.overworld, "sv_e_measurePad", { player = player, thenDepart = thenDepart, position = position } )
end

function Game.sv_e_garageReady( self )
	if self.sv.saved.pad then
		sm.event.sendToWorld( self.sv.saved.overworld, "sv_e_setPad", self.sv.saved.pad )
	end
end

-- The garage junction's cell loaded: put the launch pad on it if there's none
-- yet (or move it if it was put on the junction automatically before)
function Game.sv_e_junctionPadFound( self, params )
	local pad = self.sv.saved.pad
	local onOldSpot = pad and DistanceXY( pad.ground, JunctionCenter( GARAGE_JUNCTION ) ) < 1
	if pad and not pad.auto and not onOldSpot then
		return
	end
	if pad and ( pad.ground - params.ground ):length() < 0.25 then
		return -- (a raised or lowered floor moves it too)
	end
	self.sv.saved.pad = { ground = params.ground, auto = true }
	self:sv_saveGame()
	sm.event.sendToWorld( self.sv.saved.overworld, "sv_e_setPad", self.sv.saved.pad )
	sm.log.info( "[PacificScrap] Launch pad on the garage junction at", params.ground )
end

function Game.sv_e_zoneJunctionLog( self, params )
	sm.log.info( "[PacificScrap] Junction", params.index, "entered", params.ignored or "" )
end

function Game.sv_e_onPadMeasured( self, params )
	if params.failed then
		self:sv_message( params.player, "The launch pad can only be placed in the garage." )
		return
	end

	self.sv.saved.pad = { ground = params.ground }
	self:sv_saveGame()

	sm.event.sendToWorld( self.sv.saved.overworld, "sv_e_setPad", self.sv.saved.pad )
	self:sv_message( params.player, params.position and "Launch pad set on the junction." or "Launch pad placed here (the yellow square). Use /setpad to move it." )
	sm.log.info( "[PacificScrap] Launch pad at", params.ground )

	if params.thenDepart then
		self:sv_depart( params.player )
	end
end


-- Departure: garage -> zone ---------------------------------------------------

function Game.sv_depart( self, player )
	local run = self.sv.run

	-- Everyone left the zone some other way: drop the stale run
	if run.state == "inZone" and not self:sv_anyPlayerIn( self.sv.saved.zone ) then
		self:sv_endRun( true )
		run = self.sv.run
	end

	if run.state ~= "idle" then
		self:sv_message( player, "A run is already in progress." )
		return
	end
	local character = player.character
	if not character or not sm.exists( character ) or character:getWorld() ~= self.sv.saved.overworld then
		self:sv_message( player, "You can only depart from the garage." )
		return
	end
	if not self.sv.saved.pad then
		-- First departure: the pad goes on the garage junction
		self:sv_requestPad( player, true, JunctionPadPosition( GARAGE_JUNCTION ) )
		return
	end
	if not IsInsideBox( character.worldPosition, self:sv_padCenter(), PAD_PORTAL_HALF_SIZE ) then
		self:sv_message( player, "Get on the launch pad (the yellow square) first, or use /setpad to move it here." )
		return
	end

	local garage = self.sv.saved.overworld
	self.sv.run = { state = "departing" }
	run = self.sv.run

	-- Every run gets a brand new zone, starting at the first junction
	local destination = self:sv_jmDestination()
	self:sv_resetZone( destination.depth, false, destination )
	run.mapNode = destination.id

	-- A fresh portal per run (an opening can't be moved once set). It gets the
	-- departure delay to pick up what's on the pad.
	run.portal = sm.portal.createPortal( PAD_PORTAL_HALF_SIZE )
	run.portal:setOpeningA( self:sv_padCenter(), FacingRotation( JunctionOpening( GARAGE_JUNCTION ) * -1 ), garage )
	run.hold = { world = garage, position = self:sv_padCenter() }

	-- Keep the garage exit's cell loaded for the whole run so the return has somewhere to land
	local gx, gy = CellOf( self:sv_returnGround() )
	run.garageHandle = garage:loadCellWithHandle( gx, gy, "sv_onGarageCellLoaded" )

	self:sv_pickLanding()
	run.travellers = self:sv_playersInBox( garage, self:sv_padCenter(), PAD_PORTAL_HALF_SIZE )
	run.carried = self:sv_prepareCarried( run.travellers, garage )
	self:sv_fade( run.travellers, true )
	self:sv_broadcast( "Departing for junction " .. destination.id .. " (" .. tostring( self.sv.saved.biome ) .. ")" )
	run.timer = DEPART_DELAY_TICKS
end

-- Land near the outer end of an exit road, as if arriving from the last
-- junction. That junction is the way you came, so it doesn't lead anywhere.
function Game.sv_pickLanding( self )
	local run = self.sv.run
	local spawnCells = self.sv.saved.zoneSpawnCells or {}
	local cx, cy, onRoad
	run.entryJunction = nil
	run.arrivalDir = nil
	if #spawnCells > 0 then
		local spawnCell = spawnCells[math.random( #spawnCells )]
		cx, cy, onRoad = spawnCell.x, spawnCell.y, true
		run.entryJunction = spawnCell.junction
		run.arrivalDir = spawnCell.dir
	else
		cx = math.random( ZONE_CELL_MIN + 1, ZONE_CELL_MAX - 1 )
		cy = math.random( ZONE_CELL_MIN + 1, ZONE_CELL_MAX - 1 )
	end
	run.zoneHandle = self.sv.saved.zone:loadCellWithHandle( cx, cy, "sv_onLandingCellLoaded", { cellX = cx, cellY = cy, onRoad = onRoad } )
end

-- The garage launch pad (on the junction by default): drive onto it to depart
function Game.sv_e_garageJunction( self, params )
	if self.sv.run.state ~= "idle" or sm.game.getCurrentTick() < self.sv.junctionCooldownTick or not self.sv.saved.pad then
		return
	end
	local character = params.player.character
	if not character or not sm.exists( character ) or not IsInsideBox( character.worldPosition, self:sv_padCenter(), PAD_PORTAL_HALF_SIZE ) then
		return -- just touching the edge: wait until they're on it (the trigger keeps firing)
	end
	if not g_garagePowered then
		self.sv.junctionCooldownTick = sm.game.getCurrentTick() + 40 * 5
		self.network:sendToClient( params.player, "cl_n_alert", { text = "The garage has no power\nThe battery is in the Friendly Dumpster: put it in the socket", seconds = 5 } )
		return
	end
	if JUNCTION_MAP_ON_ENTRY and not params.chosen then
		self:sv_jmBeginChoice( { kind = "garage", player = params.player }, self.sv.saved.overworld, self:sv_padCenter() )
		return
	end
	self:sv_depart( params.player )
end

-- Cheat (/junction): as if you'd driven into a junction right where you are.
-- This junction's exits are unlocked (as if escaped) so you can go on.
function Game.sv_cheatJunction( self, player )
	if self.sv.run.state ~= "inZone" then
		self:sv_message( player, "/junction works in a zone. In the garage, drive onto the junction pad (or use /depart)." )
		return
	end
	local map = self:sv_jmMap()
	local node = map.nodes[map.current]
	if node and not JunctionExitsOpen( node ) then
		node.cleared = true
		self:sv_jmGrowOpen()
		self:sv_saveGame()
		sm.log.info( "[PacificScrap] Cheat: junction", node.id, "exits unlocked" )
	end
	self.sv.junctionCooldownTick = 0
	self:sv_e_zoneJunction( { player = player } )
end

-- A junction at the end of a zone exit road: carries the car (and everyone on
-- it) into a new zone one junction deeper
function Game.sv_e_zoneJunction( self, params )
	local run = self.sv.run
	local player = params.player
	if run.state ~= "inZone" or sm.game.getCurrentTick() < self.sv.junctionCooldownTick then
		return
	end
	local character = player.character
	if not character or not sm.exists( character ) or character:getWorld() ~= self.sv.saved.zone then
		return
	end
	if not JunctionExitsOpen( self:sv_jmMap().nodes[self:sv_jmMap().current] ) then
		local here = self:sv_jmMap().nodes[self:sv_jmMap().current]
		sm.log.info( "[PacificScrap] Junction refused: exits locked (junction", here and here.id, "depth", here and here.depth,
			"cleared", here and here.cleared, "noExit", here and here.noExit, "deadEnd", here and here.deadEnd, "max depth", g_storyMaxDepth, ")" )
		self.sv.junctionCooldownTick = sm.game.getCurrentTick() + 40 * 5
		self.network:sendToClient( player, "cl_n_alert", { text = "Exits locked\nEscape this junction through a gateway to unlock the routes beyond", seconds = 5 } )
		return
	end
	if JUNCTION_MAP_ON_ENTRY and not params.chosen then
		self:sv_jmBeginChoice( { kind = "zone", player = player, params = params }, self.sv.saved.zone, character.worldPosition + sm.vec3.new( 0, 0, 1.5 ) )
		return
	end

	-- This zone's gateway and storm are left behind
	sm.event.sendToWorld( self.sv.saved.zone, "sv_e_clearGateway" )
	sm.event.sendToWorld( self.sv.saved.zone, "sv_e_setStorm", {} )
	if run.gatewayHandle then
		run.gatewayHandle:release()
		run.gatewayHandle = nil
	end
	if run.returnPortal and sm.exists( run.returnPortal ) then
		sm.portal.destroy( run.returnPortal )
	end
	run.returnPortal = nil
	run.gateway = nil
	run.storm = nil
	run.nextPodTick = nil
	run.collapseTick = nil
	run.warned = nil
	run.warnTick = nil

	local center = character.worldPosition + sm.vec3.new( 0, 0, 1.5 )
	local destination = self:sv_jmDestination()
	if not destination then
		sm.log.info( "[PacificScrap] Dead end: no junction to head to" )
		return
	end
	local depth = destination.depth
	run.mapNode = destination.id
	run.state = "departing"
	run.oldZone = self:sv_resetZone( depth, true, destination )
	run.portal = sm.portal.createPortal( JUNCTION_PORTAL_HALF_SIZE )
	run.portal:setOpeningA( center, FacingRotation( params.junction and JunctionOpening( params.junction ) * -1 ), run.oldZone )
	run.hold = { world = run.oldZone, position = center }
	sm.event.sendToWorld( run.oldZone, "sv_e_stopBodiesNear", { position = center, radius = HOLD_RADIUS } )
	run.landing = nil
	self:sv_pickLanding()
	run.travellers = self:sv_playersInBox( run.oldZone, center, JUNCTION_PORTAL_HALF_SIZE )
	run.carried = self:sv_prepareCarried( run.travellers, run.oldZone )
	self:sv_fade( run.travellers, true )
	self:sv_broadcast( "Heading to junction " .. destination.id .. " at depth " .. depth .. " (" .. tostring( self.sv.saved.biome ) .. ")" )
	run.timer = DEPART_DELAY_TICKS
	self:sv_refreshStage()
end

function Game.sv_onGarageCellLoaded( self, world, x, y, params )
	self.sv.run.garageReady = true
end

function Game.sv_onLandingCellLoaded( self, world, x, y, params )
	sm.event.sendToWorld( self.sv.saved.zone, "sv_e_findLanding", params )
end

function Game.sv_e_onLandingFound( self, params )
	local run = self.sv.run
	if run.state ~= "departing" then
		return
	end
	local landingCenter = params.position + sm.vec3.new( 0, 0, PAD_PORTAL_LIFT + 0.5 )
	run.portal:setOpeningB( landingCenter, FacingRotation( run.arrivalDir ), self.sv.saved.zone )
	run.landing = params.position
	self:sv_landCarried( run.carried, run.landing, self.sv.saved.zone )
end

function Game.sv_finishDeparture( self )
	local run = self.sv.run
	if not run.landing then
		-- Zone not ready yet, wait another second
		run.timer = 40
		return
	end

	local portal = run.portal
	local contents = portal:getContentsA()
	sm.log.info( "[PacificScrap] Departing, pad contents:", #contents )
	if #contents == 0 and run.oldZone then
		-- Nothing got picked up at a zone junction (shouldn't happen): send everyone home
		for _, player in ipairs( run.travellers or {} ) do self:sv_sendHome( player ) end
		self:sv_fade( run.travellers, false )
		self:sv_releaseLater( 1, run.zoneHandle, portal )
		self:sv_retireZone( run.oldZone )
		if run.garageHandle then run.garageHandle:release() end
		self.sv.run = { state = "idle" }
		self:sv_refreshStage()
		return
	end
	if #contents == 0 then
		self:sv_fade( run.travellers, false )
		self:sv_releaseLater( 1, run.zoneHandle, portal )
		if run.garageHandle then
			run.garageHandle:release()
		end
		self.sv.run = { state = "idle" }
		self:sv_broadcast( "Nothing on the launch pad got picked up. Try again, or move the pad with /setpad." )
		return
	end

	self:sv_sendCarried( run.carried )
	run.carried = nil
	portal:transferAToB()
	run.hold = nil
	self:sv_advanceTime()
	-- Setting off from the garage: anyone near the launch pad but not on it
	-- (multiplayer: standing beside the car) comes along too
	if not run.oldZone then
		self:sv_bringNearPad( run.travellers or {}, run.landing, self.sv.saved.zone )
	end
	-- Anyone left in the old zone (multiplayer: not at the junction) comes along
	-- too, as it's about to be retired
	if run.oldZone then
		local old, landing, newZone = run.oldZone, run.landing, self.sv.saved.zone
		self:sv_after( 40, function() self:sv_rescueLeftBehind( old, landing, newZone ) end )
	end

	local travellers = run.travellers
	self:sv_after( 30, function() self:sv_fade( travellers, false ) end )
	self:sv_releaseLater( 80, run.zoneHandle, portal )
	run.zoneHandle = nil
	run.portal = nil
	run.state = "inZone"
	run.arrivedTick = sm.game.getCurrentTick()
	local conditions = self.sv.saved.zoneConditions
	if self.sv.saved.zoneCollapsed then
		run.collapseTick = nil -- (collapsed already: the storm starts below)
	elseif HasCondition( conditions, "stable" ) then
		run.collapseTick = nil -- Perpetual Stability: only a gateway starts the collapse
	else
		local depth = self.sv.saved.depth or 1
		local depthFactor = math.max( 1 - STORM_DEPTH_TIME_STEP * ( depth - 1 ), STORM_DEPTH_MIN_FACTOR )
		local variation = 1 + ( math.random() * 2 - 1 ) * STORM_TIME_VARIATION
		-- The route planner's stability, if the junction has one
		local baseTime = self.sv.saved.zoneStability and StabilityToSeconds( self.sv.saved.zoneStability ) or STORM_STABLE_TIME * depthFactor
		local stableTime = baseTime * variation * ( HasCondition( conditions, "unstable" ) and CONDITION_UNSTABLE_TIME_FACTOR or 1 )
		run.collapseTick = sm.game.getCurrentTick() + math.floor( stableTime * 40 )
		local warning = STORM_WARNING_TIME * ( 1 + ( math.random() * 2 - 1 ) * STORM_TIME_VARIATION )
		run.warnTick = run.collapseTick - math.floor( math.min( warning, stableTime * 0.5 ) * 40 )
	end
	sm.event.sendToWorld( self.sv.saved.zone, "sv_e_setCollapseTick", { tick = run.collapseTick } )
	self.sv.saved.introWeather = nil -- (the new game's thunderstorm is over)
	self:sv_setZoneWeather( conditions )
	self:sv_storyOnDepart()
	local arriving = run.mapNode and self:sv_jmNode( run.mapNode )
	local locked = arriving ~= nil and not JunctionExitsOpen( arriving )
	for _, player in ipairs( travellers or {} ) do
		self.network:sendToClient( player, "cl_n_arrival", { depth = self.sv.saved.depth, zone = self.sv.saved.zoneDepth, biome = self.sv.saved.biome, conditions = conditions, noExit = self.sv.saved.zoneNoExit, locked = locked, collapsed = self.sv.saved.zoneCollapsed } )
	end
	sm.event.sendToWorld( self.sv.saved.zone, "sv_e_setEntryJunction", { index = run.entryJunction } )
	if run.mapNode then
		self:sv_jmArrive( run.mapNode )
		run.mapNode = nil
	end
	self.sv.junctionCooldownTick = sm.game.getCurrentTick() + JUNCTION_COOLDOWN_TICKS
	if run.oldZone then
		local old = run.oldZone
		run.oldZone = nil
		self:sv_after( OLD_ZONE_RETIRE_DELAY, function() self:sv_retireZone( old ) end )
	end
	-- A collapsed junction: the storm is everywhere from the start (shrunk to
	-- its middle already), and it hurts less (COLLAPSED_DAMAGE)
	if self.sv.saved.zoneCollapsed then
		self:sv_startStorm( ZoneCenter(), STORM_MIN_RADIUS, 1 ) -- (speed 1: the wall's visuals divide by it)
	end
	self:sv_saveRun()
	self:sv_refreshStage()
end


-- Zone collapse -----------------------------------------------------------------

-- Survival's weather: Rainfall / Electrical Storm force rain; otherwise the
-- weather is survival's own random forecast (which can rain too). Forced rain
-- is only undone when the next place doesn't force it.
function Game.sv_setZoneWeather( self, conditions )
	if not WeatherManager or not WeatherManager.Sv_StartCondition then
		return
	end
	local weather = conditions and ( ( HasCondition( conditions, "thunderstorm" ) and "ThunderRain" )
		or ( ( HasCondition( conditions, "rain" ) or HasCondition( conditions, "acidRain" ) ) and "Rain" ) )
	if weather then
		WeatherManager.Sv_StartCondition( weather )
		self.sv.forcedWeather = true
	elseif self.sv.forcedWeather and W_weatherManagerServer then
		W_weatherManagerServer:sv_startRandomForecast()
		self.sv.forcedWeather = false
	end
end

-- Storm wall speed: faster deeper in, and with Rapid Collapse
function Game.sv_stormSpeed( self, base )
	local depth = self.sv.saved.depth or 1
	local level = self.sv.saved.zoneStorm or ( depth - 1 )
	local speed = base * ( 1 + STORM_DEPTH_SPEED_STEP * level )
	if HasCondition( self.sv.saved.zoneConditions, "rapid" ) then
		speed = speed * CONDITION_RAPID_SPEED_FACTOR
	end
	return speed
end

function Game.sv_startStorm( self, center, r0, speed )
	local run = self.sv.run
	run.storm = {
		center = sm.vec3.new( center.x, center.y, 0 ),
		r0 = r0,
		speed = speed,
		startTick = sm.game.getCurrentTick(),
		minRadius = STORM_MIN_RADIUS
	}
	run.missileTicks = {}
	run.nextPodTick = sm.game.getCurrentTick() + POD_FIRST_DELAY * 40
	sm.event.sendToWorld( self.sv.saved.zone, "sv_e_setStorm", {
		center = run.storm.center, r0 = r0, speed = speed, startTick = run.storm.startTick, minRadius = STORM_MIN_RADIUS, alarm = true
	} )
	self:sv_saveRun()
	self:sv_refreshStage()
	sm.log.info( "[PacificScrap] Storm started at", run.storm.center, "radius", r0, "speed", speed )
end

function Game.sv_updateStorm( self )
	local run = self.sv.run
	if run.state ~= "inZone" then
		return
	end
	local tick = sm.game.getCurrentTick()

	-- Everyone died (and respawned at the garage) or went /home: the run is over
	if tick % 40 == 0 and tick > ( run.arrivedTick or 0 ) + 40 * 5 and self:sv_runAbandoned() then
		self:sv_endRun( true )
		self:sv_broadcast( "Nobody is left in the zone. The run is over." )
		return
	end
	-- (multiplayer: one of them died or went home while the others go on)
	if tick % 40 == 20 then
		self:sv_towForLostPlayers()
	end

	-- Stability timer
	if not run.storm and run.collapseTick then
		if not run.warned and tick >= ( run.warnTick or run.collapseTick - STORM_WARNING_TIME * 40 ) then
			run.warned = true
			-- No text, just the alarm for everyone in the zone
			sm.event.sendToWorld( self.sv.saved.zone, "sv_e_alarm" )
		end
		if tick >= run.collapseTick then
			local center = run.gateway and sm.vec3.new( run.gateway.x, run.gateway.y, 0 ) or ZoneCenter()
			self:sv_startStorm( center, FarthestZoneCorner( center ), self:sv_stormSpeed( STORM_SPEED ) )
			self:sv_broadcast( "The zone is collapsing! Get out before the storm reaches you." )
		end
	end

	if run.storm and tick % 40 == 0 then
		self:sv_stormDamage( tick )
	end
	-- Supply pods come down while the zone collapses
	if run.storm then
		run.nextPodTick = run.nextPodTick or ( tick + POD_FIRST_DELAY * 40 )
		if tick >= run.nextPodTick then
			run.nextPodTick = tick + POD_INTERVAL * 40
			self:sv_dropPod()
		end
	end

	-- Perpetual Daylight / Nightfall: hold the clock
	local heldTime = HasCondition( self.sv.saved.zoneConditions, "daylight" ) and CONDITION_DAYLIGHT_TIME
		or ( HasCondition( self.sv.saved.zoneConditions, "nightfall" ) and CONDITION_NIGHT_TIME )
	if heldTime and self.sv.time then
		local wanted = math.floor( self.sv.time.timeOfDay ) + heldTime
		local jumped = math.abs( self.sv.time.timeOfDay - wanted ) > 0.01
		self.sv.time.timeOfDay = wanted
		if jumped or tick % 200 == 0 then
			self.sv.syncTimer.count = self.sv.syncTimer.ticks -- tell the clients
		end
	end

	-- Acid Rain: hurts on foot (seated in the car is safe)
	if tick % 40 == 20 and HasCondition( self.sv.saved.zoneConditions, "acidRain" ) then
		for _, player in ipairs( sm.player.getAllPlayers() ) do
			local character = player.character
			if character and sm.exists( character ) and character:getWorld() == self.sv.saved.zone and not character:isSeated() then
				sm.event.sendToPlayer( player, "sv_e_receiveDamage", { damage = CONDITION_ACID_DAMAGE, source = "scannerbot" } )
			end
		end
	end
end

-- Once a second: hurt players outside the wall and send seeker missiles at them
function Game.sv_stormDamage( self, tick )
	local run = self.sv.run
	local radius = StormRadius( run.storm, tick )
	run.missileTicks = run.missileTicks or {}
	for _, player in ipairs( sm.player.getAllPlayers() ) do
		local character = player.character
		if character and sm.exists( character ) and character:getWorld() == self.sv.saved.zone then
			if DistanceXY( character.worldPosition, run.storm.center ) > radius then
				-- "scannerbot" damage doesn't throw you out of your seat
				local damage = self.sv.saved.zoneCollapsed and COLLAPSED_DAMAGE
					or ZoneTierOf( self.sv.saved.zoneDepth or self.sv.saved.depth ).stormDamage or STORM_DAMAGE_PER_SECOND
				sm.event.sendToPlayer( player, "sv_e_receiveDamage", { damage = damage, source = "scannerbot" } )
				-- (a collapsed zone gives you COLLAPSED_MISSILE_GRACE first, to get going)
				local grace = self.sv.saved.zoneCollapsed and tick < ( run.arrivedTick or 0 ) + COLLAPSED_MISSILE_GRACE * 40
				if STORM_MISSILES and not grace then
					local nextVolley = run.missileTicks[player.id]
					if nextVolley == nil then
						run.missileTicks[player.id] = tick + MISSILE_GRACE_TICKS
					elseif tick >= nextVolley then
						local missiles = ZoneTierOf( self.sv.saved.zoneDepth or self.sv.saved.depth ).missiles or {}
						run.missileTicks[player.id] = tick + ( missiles.interval or STORM_MISSILE_INTERVAL ) * 40
						self:sv_fireMissiles( character, run.storm.center )
					end
				end
			else
				run.missileTicks[player.id] = nil
			end
		end
	end
end

-- A supply pod somewhere around a random player in the zone (SupplyPod.lua)
function Game.sv_dropPod( self )
	local candidates = {}
	for _, player in ipairs( sm.player.getAllPlayers() ) do
		local character = player.character
		if character and sm.exists( character ) and character:getWorld() == self.sv.saved.zone then
			candidates[#candidates + 1] = character.worldPosition
		end
	end
	if #candidates == 0 then return end
	local at = candidates[math.random( #candidates )]
	local angle = math.random() * 2 * math.pi
	local distance = POD_DISTANCE[1] + math.random() * ( POD_DISTANCE[2] - POD_DISTANCE[1] )
	local lo, hi = ZONE_CELL_MIN * 64 + 30, ( ZONE_CELL_MAX + 1 ) * 64 - 30
	local x = sm.util.clamp( at.x + math.cos( angle ) * distance, lo, hi )
	local y = sm.util.clamp( at.y + math.sin( angle ) * distance, lo, hi )
	sm.event.sendToWorld( self.sv.saved.zone, "sv_e_dropPod", { x = x, y = y, z = at.z } )
end

-- Seeker missiles launched from out in the storm, no seeker bot needed
function Game.sv_fireMissiles( self, character, center )
	local target = character.worldPosition
	local outward = sm.vec3.new( target.x - center.x, target.y - center.y, 0 )
	if outward:length() < 0.01 then
		outward = sm.vec3.new( 1, 0, 0 )
	end
	outward = outward:normalize()
	-- How dangerous they are depends on the zone tier (ZONE_TIERS missiles):
	-- the Outer Zone's just make noise around you, the Deep Zone's hit
	local missiles = ZoneTierOf( self.sv.saved.zoneDepth or self.sv.saved.depth ).missiles or {}
	local miss = missiles.miss or { 1, 3 }
	for _ = 1, missiles.volley or STORM_MISSILES_PER_VOLLEY do
		local direction = outward:rotateZ( math.rad( math.random( -40, 40 ) ) )
		local from = target + direction * 70 + sm.vec3.new( 0, 0, 45 + math.random() * 15 )
		local params = {
			worldPosition = from,
			worldDirection = ( target - from ):normalize(),
			targetOffset = miss[1] + math.random() * ( miss[2] - miss[1] ),
			targetCharacter = character,
			curveChance = 0.5
		}
		sm.scriptableObject.createScriptableObject( MISSILE_UUID, params, character:getWorld() )
	end
end


-- Gateway ---------------------------------------------------------------------

-- Opens the gateway, opened by a player (/gateway) or from a position (an ARC
-- Device: origin = { position, world }). near = true puts it just ahead of the
-- player (for testing); otherwise it lands somewhere out in the zone, well away
-- from every player. Returns true when a gateway was opened.
function Game.sv_spawnGateway( self, player, near, origin )
	local run = self.sv.run
	local function tell( text )
		if player then self:sv_message( player, text ) else self:sv_broadcast( text ) end
	end
	local character = player and player.character
	local position, world
	if origin then
		position, world = origin.position, origin.world
	elseif character and sm.exists( character ) then
		position, world = character.worldPosition, character:getWorld()
	end
	local reason = self:sv_whyNoGateway( position, world )
	if reason then
		tell( reason )
		return false
	end

	local tick = sm.game.getCurrentTick()
	local minPos = ZONE_CELL_MIN * 64 + GATEWAY_EDGE_MARGIN
	local maxPos = ( ZONE_CELL_MAX + 1 ) * 64 - GATEWAY_EDGE_MARGIN
	local zonePlayers = {}
	for _, other in ipairs( sm.player.getAllPlayers() ) do
		local otherCharacter = other.character
		if otherCharacter and sm.exists( otherCharacter ) and otherCharacter:getWorld() == self.sv.saved.zone then
			zonePlayers[#zonePlayers + 1] = otherCharacter.worldPosition
		end
	end

	-- Clamp to the map, and inside the wall if the zone is already collapsing
	local function place( target )
		-- (closed in all the way, there's no inside left: placed as normal)
		if run.storm and StormRadius( run.storm, tick ) > 2 then
			local maxDistance = StormRadius( run.storm, tick ) * 0.6
			local offset = sm.vec3.new( target.x - run.storm.center.x, target.y - run.storm.center.y, 0 )
			if offset:length() > maxDistance then
				target = run.storm.center + offset:normalize() * maxDistance
			end
		end
		return sm.vec3.new( sm.util.clamp( target.x, minPos, maxPos ), sm.util.clamp( target.y, minPos, maxPos ), 0 )
	end

	local target
	if near and character then
		local direction = sm.vec3.new( character.direction.x, character.direction.y, 0 )
		if direction:length() < 0.01 then
			direction = sm.vec3.new( 0, 1, 0 )
		end
		target = place( position + direction:normalize() * GATEWAY_NEAR_DISTANCE )
	else
		-- Try random spots and keep the one furthest from the nearest player,
		-- stopping early once one is far enough from everyone
		-- Not in (or right next to) water, oil or chemicals
		local liquid = {}
		for _, c in ipairs( self.sv.saved.zoneLiquidCells or {} ) do liquid[c.x .. "," .. c.y] = true end
		local function wet( p )
			for _, d in ipairs( { { 0, 0 }, { 24, 0 }, { -24, 0 }, { 0, 24 }, { 0, -24 } } ) do
				if liquid[math.floor( ( p.x + d[1] ) / 64 ) .. "," .. math.floor( ( p.y + d[2] ) / 64 )] then return true end
			end
			return false
		end
		local minDistance, maxDistance = GatewayDistance( self.sv.saved.depth )
		local bestScore = -1
		for _ = 1, 60 do
			local angle = math.random() * 2 * math.pi
			local distance = minDistance + math.random() * ( maxDistance - minDistance )
			local candidate = place( position + sm.vec3.new( math.cos( angle ), math.sin( angle ), 0 ) * distance )
			local score = math.huge
			for _, p in ipairs( zonePlayers ) do
				score = math.min( score, DistanceXY( candidate, p ) )
			end
			if wet( candidate ) then
				score = -0.5 -- only if nothing dry turns up
			end
			if score > bestScore then
				bestScore, target = score, candidate
			end
			if score >= minDistance then
				break
			end
		end
	end
	run.gateway = { x = target.x, y = target.y }
	run.gatewayCenter = nil -- (set when it's in place: sv_e_onGatewaySpawned)
	self:sv_loadGatewayCell()

	-- Opening the gateway makes the zone collapse onto it, fast. The wall starts
	-- far enough out that everyone is inside it. If the zone was already
	-- collapsing, the wall re-centres on the gateway and speeds up.
	local center = sm.vec3.new( run.gateway.x, run.gateway.y, 0 )
	local farthest = 0
	for _, p in ipairs( zonePlayers ) do
		farthest = math.max( farthest, DistanceXY( p, center ) )
	end
	local margin = STORM_GATEWAY_START_MARGIN_BY_DEPTH[self.sv.saved.depth or 1] or STORM_GATEWAY_START_MARGIN
	local r0 = farthest + margin
	if run.storm then
		r0 = math.max( StormRadius( run.storm, tick ), farthest + 20 )
	end
	-- (speed from the distance: the wall takes STORM_GATEWAY_TIME_BY_DEPTH to
	-- close in, then the junction's speed-ups on top)
	local times = STORM_GATEWAY_TIME_BY_DEPTH
	local seconds = times[math.min( self.sv.saved.depth or 1, #times )]
	local base = math.max( r0 / seconds, STORM_GATEWAY_SPEED_MIN )
	self:sv_startStorm( center, r0, self:sv_stormSpeed( base ) )
	self:sv_broadcast( "The gateway is open and the zone is collapsing! Follow the yellow beam." )
	return true
end

-- Sent by a charged ARC Device when its button or switch turns on
-- nil if a gateway can open here, otherwise why not
function Game.sv_whyNoGateway( self, position, world )
	if self.sv.run.state ~= "inZone" or not position or world ~= self.sv.saved.zone then
		return "A gateway can only be opened in the zone."
	end
	if self.sv.run.gateway then
		return "The gateway is already open. Look for the yellow beam."
	end
	-- No stable exits: worked out now, the same way the junctions decide if they
	-- lead on (JunctionNoExit), so a zone always has one way out: where the exits
	-- are locked a gateway can open
	local map = self:sv_jmMap()
	local here = map.nodes[map.current]
	local noExit
	if here then
		noExit = JunctionNoExit( here )
	else
		noExit = self.sv.saved.zoneNoExit
	end
	if noExit then
		return "No stable exits here: the ARC Device can't open a gateway in this junction. Drive on through a junction."
	end
end

-- An ARC Device was switched on: let it charge up if a gateway can open
function Game.sv_e_arcRequestCharge( self, params )
	local reason = self:sv_whyNoGateway( params.position, params.world )
	if reason then
		local map = self:sv_jmMap()
		sm.log.info( "[PacificScrap] ARC Device refused:", reason, "(junction", map.current, ")" )
		-- Shown next to the device
		if params.device and sm.exists( params.device ) then
			sm.event.sendToInteractable( params.device, "sv_e_message", reason )
		end
	elseif params.device and sm.exists( params.device ) then
		sm.event.sendToInteractable( params.device, "sv_e_arcStartCharge" )
	end
end

-- ...and it finished charging
function Game.sv_e_arcOpenGateway( self, params )
	if self:sv_spawnGateway( nil, false, { position = params.position, world = params.world } ) and params.device and sm.exists( params.device ) then
		sm.event.sendToInteractable( params.device, "sv_e_gatewayOpened" )
	end
end

-- The gateway can be far from everyone, so load its cell (and keep it loaded for
-- the run) before the zone measures the ground there
function Game.sv_loadGatewayCell( self )
	local run = self.sv.run
	if run.gatewayHandle then
		run.gatewayHandle:release()
	end
	local x, y = CellOf( sm.vec3.new( run.gateway.x, run.gateway.y, 0 ) )
	run.gatewayHandle = self.sv.saved.zone:loadCellWithHandle( x, y, "sv_onGatewayCellLoaded" )
end

function Game.sv_onGatewayCellLoaded( self, world, x, y, params )
	if self.sv.run.gateway then
		sm.event.sendToWorld( self.sv.saved.zone, "sv_e_spawnGateway", self.sv.run.gateway )
	end
end

-- The zone found the ground at the gateway: put the return portal there now, so
-- it is already tracking the car as it drives in
function Game.sv_e_onGatewaySpawned( self, params )
	local run = self.sv.run
	if run.state ~= "inZone" or not self.sv.saved.pad then
		return
	end
	if run.returnPortal and sm.exists( run.returnPortal ) then
		sm.portal.destroy( run.returnPortal )
	end
	run.returnPortal = sm.portal.createPortal( GATEWAY_PORTAL_HALF_SIZE )
	run.returnPortal:setOpeningA( params.ground + sm.vec3.new( 0, 0, GATEWAY_PORTAL_LIFT ), sm.quat.identity(), self.sv.saved.zone )
	run.returnPortal:setOpeningB( self:sv_returnGround() + sm.vec3.new( 0, 0, GATEWAY_PORTAL_LIFT + 0.3 ), sm.quat.identity(), self.sv.saved.overworld )
	run.gatewayCenter = params.ground + sm.vec3.new( 0, 0, GATEWAY_PORTAL_LIFT )
	self:sv_refreshStage()
end


-- Return: gateway -> garage ---------------------------------------------------

function Game.sv_e_onGatewayReached( self, params )
	local run = self.sv.run
	if run.state ~= "inZone" or not run.gateway then
		return
	end
	-- (the gateway's placeholder portal may not be there yet: the player marks the spot)
	if not run.gatewayCenter and params and params.position then
		run.gatewayCenter = params.position
	end
	if not run.gatewayCenter then
		return
	end
	run.state = "returning"

	if not run.garageHandle then
		-- Run was resumed from a save
		local gx, gy = CellOf( self:sv_returnGround() )
		run.garageHandle = self.sv.saved.overworld:loadCellWithHandle( gx, gy, "sv_onGarageCellLoaded" )
	end

	-- What goes home: everyone near the gateway, and the whole creation each of
	-- them sits in (a car is several bodies: all of them, or it comes apart)
	local zone = self.sv.saved.zone
	local travellers, bodies, seen = {}, {}, {}
	local car = false -- (a creation of CAR_MIN_SHAPES parts or more)
	local function addCreation( body )
		local shapes = 0
		for _, b in ipairs( body:getCreationBodies() ) do
			if not seen[b.id] then
				seen[b.id] = true
				bodies[#bodies + 1] = b
				shapes = shapes + #b:getShapes()
			end
		end
		if shapes >= CAR_MIN_SHAPES then car = true end
	end
	for _, player in ipairs( sm.player.getAllPlayers() ) do
		local character = player.character
		if character and sm.exists( character ) and character:getWorld() == zone
			and DistanceXY( character.worldPosition, run.gatewayCenter ) < RETURN_GATHER_RADIUS then
			travellers[#travellers + 1] = player
			local ok, seat = pcall( function() return character:getLockingInteractable() end )
			if ok and seat and sm.exists( seat ) and seat.shape.body:isDynamic() then
				addCreation( seat.shape.body )
			end
		end
	end
	if run.returnPortal and sm.exists( run.returnPortal ) then
		for _, object in ipairs( run.returnPortal:getContentsA() ) do
			if type( object ) == "Body" and sm.exists( object ) and object:isDynamic() then
				addCreation( object )
			end
		end
	end
	-- Other creations near the gateway (multiplayer: a friend's car nobody sits
	-- in, a second car, loose parts) come home too: towed after the return, each
	-- through its own portal beside where your car comes out (so the return
	-- portal stays the size of your car and never picks up robots)
	run.extras = {}
	for _, body in ipairs( sm.body.getAllBodies( zone ) ) do
		if sm.exists( body ) and body:isDynamic() and not seen[body.id]
			and DistanceXY( body.worldPosition, run.gatewayCenter ) < RETURN_GATHER_RADIUS then
			local item = TowItem( body, seen )
			if item then
				run.extras[#run.extras + 1] = item
				if item.shapes >= CAR_MIN_SHAPES then car = true end
			end
		end
	end
	-- (a car carried on a traveller's lift comes too: sv_prepareCarried)
	for _, player in ipairs( travellers ) do
		local carried = g_liftCarry and g_liftCarry[player.id]
		if carried and sm.exists( carried ) then
			local shapes = 0
			for _, b in ipairs( carried:getCreationBodies() ) do shapes = shapes + #b:getShapes() end
			if shapes >= CAR_MIN_SHAPES then car = true end
		end
	end
	run.travellers = travellers
	run.carried = self:sv_prepareCarried( travellers, zone )
	self:sv_landCarried( run.carried, self:sv_returnGround() - JunctionOpening( GARAGE_EXIT ) * 10, self.sv.saved.overworld )
	self:sv_fade( run.travellers, true )
	-- Escaped but left the car behind: a car kit in the dumpster, as after a
	-- failed run
	if not car then
		self:sv_carKitPending()
	end

	-- Its size, how it's moving, and the box round it (stretched ahead, as it
	-- moves on while the portal gets ready)
	local low, high
	local function grow( a, b )
		low = low and sm.vec3.new( math.min( low.x, a.x ), math.min( low.y, a.y ), math.min( low.z, a.z ) ) or a
		high = high and sm.vec3.new( math.max( high.x, b.x ), math.max( high.y, b.y ), math.max( high.z, b.z ) ) or b
	end
	local momentum, mass = sm.vec3.new( 0, 0, 0 ), 0
	for _, body in ipairs( bodies ) do
		local ok, a, b = pcall( function() return body:getWorldAabb() end )
		if ok and a then grow( a, b ) else grow( body.worldPosition, body.worldPosition ) end
		momentum = momentum + body.velocity * body.mass
		mass = mass + body.mass
	end
	for _, player in ipairs( travellers ) do
		local p = player.character.worldPosition
		grow( p - sm.vec3.new( 0.5, 0.5, 1.0 ), p + sm.vec3.new( 0.5, 0.5, 1.0 ) )
	end
	if not low then
		low, high = run.gatewayCenter - GATEWAY_PORTAL_HALF_SIZE, run.gatewayCenter + GATEWAY_PORTAL_HALF_SIZE
	end
	local velocity = mass > 0 and momentum * ( 1 / mass ) or sm.vec3.new( 0, 0, 0 )
	local flat = sm.vec3.new( velocity.x, velocity.y, 0 )
	local speed = flat:length()
	local lead = flat * ( RETURN_DELAY_TICKS / 40 )
	local center = ( low + high ) * 0.5 + lead * 0.5
	local reach = math.max( high.x - low.x, high.y - low.y ) * 0.5 + lead:length() * 0.5 + 2.0
	local halfSize = sm.vec3.new( reach, reach, ( high.z - low.z ) * 0.5 + 2.0 )

	-- Turned so the way it moves comes out down the garage road; out of the
	-- exit with its bottom just above the floor; it keeps its speed (sv_finishReturn)
	local exitDir = JunctionOpening( GARAGE_EXIT )
	local turning = speed > 1.0
	local floor = self:sv_returnGround() - sm.vec3.new( 0, 0, RETURN_LIFT )
	local out = floor + sm.vec3.new( 0, 0, center.z - low.z + 0.6 )
	run.returnSpeed = math.min( speed, RETURN_MAX_SPEED )
	if run.returnPortal and sm.exists( run.returnPortal ) then
		sm.portal.destroy( run.returnPortal )
	end
	run.returnPortal = sm.portal.createPortal( halfSize )
	run.returnPortal:setOpeningA( center, turning and FacingRotation( flat ) or sm.quat.identity(), zone )
	run.returnPortal:setOpeningB( out, turning and FacingRotation( exitDir ) or sm.quat.identity(), self.sv.saved.overworld )
	sm.log.info( "[PacificScrap] Gateway reached:", #bodies, "bodies,", #travellers, "players, speed", math.floor( speed ) )
	run.timer = RETURN_DELAY_TICKS
end

function Game.sv_finishReturn( self )
	local run = self.sv.run
	if not run.garageReady then
		run.timer = 40
		return
	end

	sm.log.info( "[PacificScrap] Returning, gateway contents:", #run.returnPortal:getContentsA() )
	local exitDir = JunctionOpening( GARAGE_EXIT )
	local speed = run.returnSpeed or 0
	-- (what they carry on their lift, in the same moment)
	self:sv_sendCarried( run.carried )
	run.carried = nil
	run.returnPortal:transferAToB()
	-- (the other creations by the gateway, beside it, once the car's out)
	local extras, fromZone = run.extras, self.sv.saved.zone
	if extras and #extras > 0 then
		self:sv_after( 20, function() self:sv_towToGarage( fromZone, extras, 2 ) end )
		sm.log.info( "[PacificScrap] Towing", #extras, "more creations home from the gateway" )
	end
	self:sv_advanceTime()

	local garage = self.sv.saved.overworld
	local arrival = self:sv_returnGround()
	sm.log.info( "[PacificScrap] Gateway return lands at", arrival, "(exit spot", JunctionPadPosition( GARAGE_EXIT ), ")" )
	self:sv_after( 2, function()
		if speed > 1.0 then
			sm.event.sendToWorld( garage, "sv_e_launchBodies", { position = arrival, radius = 15, dir = exitDir, speed = speed } )
		else
			sm.event.sendToWorld( garage, "sv_e_stopBodiesNear", { position = arrival, radius = 15 } )
		end
		sm.event.sendToWorld( garage, "sv_e_playTeleport", { position = arrival } )
	end )
	local travellers = run.travellers
	self:sv_after( 30, function() self:sv_fade( travellers, false ) end )
	-- Failsafes: anyone the gateway missed comes home anyway, and anything that
	-- arrived under the floor is lifted back onto it
	local zone = self.sv.saved.zone
	self:sv_after( 40, function() self:sv_rescueLeftBehind( zone, arrival ) end )
	-- (soon, before anyone's driven off the platform onto lower ground)
	self:sv_after( 16, function()
		sm.event.sendToWorld( garage, "sv_e_rescueBelowFloor", { position = arrival, floor = arrival.z - RETURN_LIFT } )
	end )
	self:sv_releaseLater( 120, run.garageHandle, run.returnPortal )

	self:sv_endRun()
	self.sv.junctionCooldownTick = sm.game.getCurrentTick() + JUNCTION_COOLDOWN_TICKS
	self:sv_broadcast( "Back at the garage." )
end


-- Chat commands ---------------------------------------------------------------

-- Survival only adds its cheat commands in dev mode (it binds them once the dev
-- flag arrives from the server); pretend for a moment
-- Survival's crafting recipes, with our own copy of the Craftbot's core set
-- (CraftingRecipes/craftbot_core.json): Ember is made from scrap wood and gas
-- canisters instead of needing Ember to start with. (Crafters show the
-- recipe straight from the file, so it's a copy rather than a change to the
-- loaded table; the GUI-safe $CONTENT_ path, see gotchas.md.)
PACIFIC_CORE_RECIPES = "$CONTENT_3c9f5e62-8d1a-4b7e-9a35-6f2d0c4e8b71/CraftingRecipes/craftbot_core.json"

function Game.loadCraftingRecipes( self )
	local recipeSets = sm.json.open( "$SURVIVAL_DATA/CraftingRecipes/craftbot/craftbot.json" )
	recipeSets.craftbot_core = PACIFIC_CORE_RECIPES
	recipeSets.workbench = "$SURVIVAL_DATA/CraftingRecipes/workbench.json"
	recipeSets.portablecrafter = "$SURVIVAL_DATA/CraftingRecipes/portablecrafter.json"
	recipeSets.dispenser = "$SURVIVAL_DATA/CraftingRecipes/dispenser.json"
	recipeSets.cookbot = "$SURVIVAL_DATA/CraftingRecipes/cookbot.json"
	recipeSets.dressbot = "$SURVIVAL_DATA/CraftingRecipes/dressbot.json"
	recipeSets.mininghubDispenser = "$SURVIVAL_DATA/CraftingRecipes/mininghubDispenser.json"
	recipeSets.sawtable = "$SURVIVAL_DATA/CraftingRecipes/sawtable.json"
	LoadCraftingRecipes( recipeSets )
end

function Game.bindChatCommands( self )
	local dev = g_survivalDev
	g_survivalDev = DEV_MODE or CHEAT_COMMANDS
	SurvivalGame.bindChatCommands( self )
	g_survivalDev = dev
end

function Game.client_onCreate( self )
	SurvivalGame.client_onCreate( self )
	self.network:sendToServer( "sv_n_requestLiftBlueprints" ) -- (on or off for this save: Player.lua)
	sm.game.bindChatCommand( "/where", {}, "cl_onChatCommand", "Prints your position" )
	-- The rest only with the developer switch on (CHEAT_COMMANDS in layouts.lua)
	if not ( CHEAT_COMMANDS or DEV_MODE ) then
		return
	end
	sm.game.bindChatCommand( "/depart", {}, "cl_onChatCommand", "Travel to the zone. Everything on the launch pad comes along." )
	sm.game.bindChatCommand( "/setpad", {}, "cl_onChatCommand", "Move the launch pad to where you are standing" )
	sm.game.bindChatCommand( "/gateway", { { "string", "here", true } }, "cl_onChatCommand", "Open the exit gateway somewhere in the zone ('/gateway here' puts it just ahead of you). The zone starts collapsing!" )
	sm.game.bindChatCommand( "/home", {}, "cl_onChatCommand", "Emergency teleport back to the garage (your car stays behind)" )
	sm.game.bindChatCommand( "/arcdevice", {}, "cl_onChatCommand", "Cheat: gives you an ARC Device" )
	sm.game.bindChatCommand( "/junctionmap", {}, "cl_onChatCommand", "Debug: opens the junction map (view only)" )
	sm.game.bindChatCommand( "/routeplanner", {}, "cl_onChatCommand", "Cheat: puts a Route Planner in front of you" )
	sm.game.bindChatCommand( "/revealmap", {}, "cl_onChatCommand", "Cheat: scans every junction on the map and unlocks its exits, one level more each time" )
	sm.game.bindChatCommand( "/skipquest", { { "int", "count", true } }, "cl_onChatCommand", "Cheat: completes the current main quest (or that many in a row)" )
	sm.game.bindChatCommand( "/junction", {}, "cl_onChatCommand", "Cheat: in a zone, opens the junction map as if you drove into a junction (unlocks this junction's exits); sit in your car first" )
	sm.game.bindChatCommand( "/dumpster", {}, "cl_onChatCommand", "Cheat: puts a Friendly Dumpster in front of you, ready to open" )
	sm.game.bindChatCommand( "/fuelpump", {}, "cl_onChatCommand", "Cheat: puts the garage's Fuel Pump back on its spot (or a new one there if there's none)" )
	sm.game.bindChatCommand( "/supplypod", {}, "cl_onChatCommand", "Cheat: in a zone, drops a supply pod somewhere near you" )
	sm.game.bindChatCommand( "/testtier", { { "string", "tier", true } }, "cl_onChatCommand", "Debug: new zones count as this tier (outer, mid, deep: its look, robots, missiles, pods); no name = normal" )
	sm.game.bindChatCommand( "/liftblueprints", {}, "cl_onChatCommand", "Cheat: turns loading blueprints onto the lift (hold the lift, press E) on or off for this save" )
end

-- Lift blueprints on or off: the server's g_liftBlueprints, copied to every
-- client's (they're separate Lua states) as g_liftBlueprintsClient
function Game.sv_n_requestLiftBlueprints( self, _, player )
	self.network:sendToClient( player, "cl_n_setLiftBlueprints", { on = g_liftBlueprints == true } )
end

function Game.cl_n_setLiftBlueprints( self, data )
	g_liftBlueprintsClient = data.on == true
end

function Game.cl_n_alert( self, data )
	sm.gui.displayAlertText( data.text, data.seconds or 4 )
end

-- "JCT 3: Fields" and the junction's conditions when you arrive somewhere
function Game.cl_n_arrival( self, data )
	local biome = ZONE_BIOMES[data.biome or "forest"] or ZONE_BIOMES.forest
	local lines = { "JCT " .. ( data.depth or 1 ) .. ": " .. biome.title .. " (" .. ZoneTierOf( data.zone or data.depth ).title .. ")" }
	if data.collapsed then
		lines[#lines + 1] = "COLLAPSED: the storm is everywhere. Drive through to a junction; supply pods lie about"
	elseif data.noExit then
		lines[#lines + 1] = "No Stable Exits: no gateway here, find a junction"
	elseif data.locked then
		lines[#lines + 1] = "Exits locked: open a gateway here to unlock the routes beyond"
	end
	for _, name in ipairs( data.conditions or {} ) do
		local condition = ZONE_CONDITIONS[name]
		if condition then lines[#lines + 1] = condition.title .. ": " .. condition.text end
	end
	sm.gui.displayAlertText( table.concat( lines, "\n" ), 7 )
end

function Game.cl_onChatCommand( self, params )
	if params[1] == "/junctionmap" then
		self:cl_jmOpen()
	elseif params[1] == "/where" then
		local character = sm.localPlayer.getPlayer().character
		if character then
			local p = character.worldPosition
			sm.gui.chatMessage( string.format( "x=%.1f y=%.1f z=%.1f", p.x, p.y, p.z ) )
			sm.log.info( string.format( "[PacificScrap] /where x=%.2f y=%.2f z=%.2f", p.x, p.y, p.z ) )
		end
	else
		SurvivalGame.cl_onChatCommand( self, params )
	end
end

function Game.sv_onChatCommand( self, params, player )
	if params[1] == "/depart" then
		self:sv_depart( player )
	elseif params[1] == "/setpad" then
		self:sv_requestPad( player, false )
	elseif params[1] == "/gateway" then
		self:sv_spawnGateway( player, params[2] == "here" )
	elseif params[1] == "/home" then
		self:sv_sendHome( player )
	elseif params[1] == "/junction" then
		self:sv_cheatJunction( player )
	elseif params[1] == "/revealmap" then
		self:sv_jmReveal( player )
	elseif params[1] == "/skipquest" then
		self:sv_storySkip( player, params[2] )
	elseif params[1] == "/routeplanner" then
		local character = player.character
		if not character or not sm.exists( character ) or character:getWorld() ~= self.sv.saved.overworld then
			self:sv_message( player, "The Route Planner can only be placed in the garage." )
		else
			local forward = sm.vec3.new( character.direction.x, character.direction.y, 0 ):safeNormalize( sm.vec3.new( 1, 0, 0 ) )
			local spot = character.worldPosition + forward * 3
			sm.event.sendToWorld( self.sv.saved.overworld, "sv_e_placePart", {
				uuid = sm.uuid.new( "c1d2e3f4-a5b6-4c7d-8e9f-a0b1c2d3e4f5" ), x = spot.x, y = spot.y, rotation = math.deg( math.atan2( forward.y, forward.x ) ) + 90
			} )
		end
	elseif params[1] == "/dumpster" then
		local character = player.character
		if not character or not sm.exists( character ) or character:getWorld() ~= self.sv.saved.overworld then
			self:sv_message( player, "The dumpster can only be placed in the garage." )
		else
			local forward = sm.vec3.new( character.direction.x, character.direction.y, 0 ):safeNormalize( sm.vec3.new( 1, 0, 0 ) )
			local spot = character.worldPosition + forward * 3
			local degrees = math.deg( math.atan2( forward.y, forward.x ) ) + 90
			sm.event.sendToWorld( self.sv.saved.overworld, "sv_e_placePart", {
				uuid = sm.uuid.new( "d0f1e2a3-b4c5-4d6e-8f70-81a2b3c4d5e6" ), x = spot.x, y = spot.y, rotation = degrees
			} )
			self.sv.saved.trips = ( self.sv.saved.trips or 0 ) + 1 -- so it's full
			g_garageTrips = self.sv.saved.trips
			self:sv_saveGame()
		end
	elseif params[1] == "/fuelpump" then
		local character = player.character
		if not character or not sm.exists( character ) or character:getWorld() ~= self.sv.saved.overworld then
			self:sv_message( player, "The Fuel Pump can only be placed in the garage." )
		else
			local forward = sm.vec3.new( character.direction.x, character.direction.y, 0 ):safeNormalize( sm.vec3.new( 1, 0, 0 ) )
			local spot = character.worldPosition + forward * 3
			local degrees = math.deg( math.atan2( forward.y, forward.x ) ) + 90
			-- The garage's pump is put back on its spot (FuelPump.lua); no pump yet, a new one
			local existing = false
			for _, shape in pairs( g_fuelPumps or {} ) do
				if sm.exists( shape ) then existing = true end
			end
			if existing then
				g_fuelPumpHome = true
				self:sv_message( player, "Fuel Pump put back on its spot." )
			else
				sm.event.sendToWorld( self.sv.saved.overworld, "sv_e_placeFuelPump" )
				self:sv_message( player, "Fuel Pump put on its spot." )
			end
		end
	elseif params[1] == "/testtier" then
		local tier
		for _, t in ipairs( ZONE_TIERS ) do
			if t.name == params[2] then tier = t.name end
		end
		self.sv.saved.testTier = tier
		g_testTier = tier
		self:sv_saveGame()
		self:sv_message( player, tier and ( "New zones count as the " .. tier .. " tier (from your next trip)." ) or "Zones use their own tier again." )
	elseif params[1] == "/supplypod" then
		if self.sv.run.state == "inZone" then
			self:sv_dropPod()
		else
			self:sv_message( player, "Supply pods only come down in the zone." )
		end
	elseif params[1] == "/liftblueprints" then
		g_liftBlueprints = not g_liftBlueprints
		self.sv.saved.liftBlueprints = g_liftBlueprints
		self:sv_saveGame()
		self.network:sendToClients( "cl_n_setLiftBlueprints", { on = g_liftBlueprints } )
		self:sv_message( player, g_liftBlueprints and "Lift blueprints on: hold the lift and press E to load a blueprint onto it."
			or "Lift blueprints off." )
	elseif params[1] == "/arcdevice" then
		sm.container.beginTransaction()
		sm.container.collect( player:getInventory(), ARC_DEVICE_UUID, 1 )
		if sm.container.endTransaction() then
		else
			self:sv_message( player, "No room in your inventory." )
		end
	else
		SurvivalGame.sv_onChatCommand( self, params, player )
	end
end

-- The junction map (its own file, adds Game methods)
dofile( "$CONTENT_DATA/Scripts/JunctionMap.lua" )
dofile( "$CONTENT_DATA/Scripts/zone_pool.lua" )
dofile( "$CONTENT_DATA/Scripts/Story.lua" )
dofile( "$CONTENT_DATA/Scripts/Dialogs.lua" )

function Game.client_onUpdate( self, dt )
	SurvivalGame.client_onUpdate( self, dt )
	-- The logbook (its key) taken out / put away: open / close the map
	-- (survival_patches.lua)
	local request = g_pacificMapRequest
	g_pacificMapRequest = nil
	local open = self.cl.jmGui ~= nil and sm.exists( self.cl.jmGui ) and self.cl.jmGui:isActive()
	if request == "open" and not open then
		self:cl_jmOpen()
	elseif request == "close" and open and self.cl.jm and self.cl.jm.mode == "view" then
		self:cl_jmOnClose()
		g_pacificMapClosedByUser = false -- (the logbook is already going away)
	end
	self:cl_jmUpdate( dt )
end
