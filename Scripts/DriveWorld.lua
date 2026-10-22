dofile( "$SURVIVAL_DATA/Scripts/game/worlds/Overworld.lua" )
dofile( "$CONTENT_DATA/Scripts/layouts.lua" )
dofile( "$CONTENT_DATA/Scripts/survival_patches.lua" )
dofile( "$CONTENT_DATA/Scripts/ZoneTornadoes.lua" )

-- Visuals are glowing laser-hologram spheres (Effects/Renderable/*.rend, built on
-- the plasma drill's sphere mesh). Scaled unevenly they make orbs, beams, discs
-- and the storm dome, and a sphere looks right whatever way the mesh is oriented.
local GATEWAY_SPHERE_EFFECT = "PacificScrap - GatewaySphere"

-- The gates in a junction tile's cell (kinematics listening for
-- JUNCTION_GATE_EVENT; only there while the cell is loaded)
local function JunctionGates( world, x, y )
	if not ( KinematicManager and TileStorageManager and g_kinematicManager ) then return {} end
	local key = TileStorageManager.Sv_GetTileStorageKeyFromCell( world, x, y )
	local gates = key and KinematicManager.Sv_GetRegistered( key, JUNCTION_GATE_EVENT ) or {}
	local found = {}
	for _, gate in ipairs( gates ) do
		if sm.exists( gate ) then found[#found + 1] = gate end
	end
	return found
end

-- A gate is open once it has moved off where it was placed (placed closed)
local function GateOpen( gate )
	return ( gate.worldPosition - gate.initialPosition ):length() > 0.5
end

local function GateMoving( gate )
	return gate.publicData ~= nil and gate.publicData.moving == true
end

local GATE_ALARM_EFFECT = "PacificScrap - GateAlarm" -- warehouse alarm, from the gate as it opens
local GATE_WATCH_RANGE = 80 -- metres: nobody this close, the gate is just put open or shut (no animation)
-- The storm wall and the gateway beam are rings of flat glowing panels (one
-- stretched sphere glitched depending on where the camera looked)
local STORM_PANEL_EFFECT = "PacificScrap - StormPanel"
local GATEWAY_PANEL_EFFECT = "PacificScrap - GatewayPanel"
local STORM_HOLOGRAM_EFFECT = "PacificScrap - StormHologram"
local STORM_PANELS = 48
local STORM_WALL_RISE_SECONDS = 4 -- the wall rises out of the ground (and sinks back) this fast
local STORM_WALL_GONE_RADIUS = 2 -- metres: a wall closed in this far disappears
local STORM_PANEL_ROWS = 6
local GATEWAY_PANEL_ROWS = 10
-- Plain orange glow over the whole wall, with bands of the warehouse hologram.
-- The wall is split into equal rows, listed top to bottom: 1 = hologram band, 0 = just orange
local STORM_STRIPE_PATTERN = { 1, 0, 0, 0, 1, 0, 0, 0, 0 }
-- The game stops drawing things a little over a kilometre from the camera, so a
-- very tall wall gets cut off along a curve. Keep it modest.
local STORM_WALL_BOTTOM = -50.0
local STORM_WALL_HEIGHT = 350.0
local GATEWAY_PANELS = 12
local SPHERE_MESH_RADIUS = 6.16 -- radius of the sphere mesh at scale 1

-- Gateway look and size (metres). Tweak freely.
local GATEWAY_TRIGGER_HALF_SIZE = sm.vec3.new( 12.0, 12.0, 300.0 ) -- tall so ground height doesn't matter
local GATEWAY_BEAM_RADIUS = 18.0
local GATEWAY_BEAM_HEIGHT = 600.0 -- above the ground
local GATEWAY_MARKER_NAME = "pacificscrap_gateway"
local JUNCTION_TRIGGER_HALF_SIZE = sm.vec3.new( 3.5, 3.5, 300.0 ) -- thin and tall: inside the elevator, whatever the height
local GATEWAY_SHAKE_EFFECT = "PacificScrap - GatewayShake"
local ANCHOR_MARKER_PREFIX = "pacificscrap_anchor_"
local JUNCTION_MARKER_PREFIX = "pacificscrap_junction_"
-- Beacon icon for junctions: 0 down, 1 up, 2 !, 3 ?, 4 car, 5 house, 8 tree,
-- 12 wrench, 19 cog, 21 heart, 22 drop, 23 X (the beacon's icon picker order)
local JUNCTION_BEACON_ICON = 4
local ANCHOR_BEACON_ICON = 16 -- the round orb
local MARKER_GREY = "DDDDDDFF"
local GATEWAY_BEACON_ICON = 1 -- the up arrow: the way out
local GATEWAY_YELLOW = "FFD44AFF"
local ANCHOR_GRAB_EFFECT = "PacificScrap - AnchorGrab"

-- Launch pad marker (matches the departure portal footprint in Game.lua)
local PAD_RADIUS = 6.0

-- Metres before the wall the red screen starts (it fades in over ~2s)
local STORM_SCREEN_LEAD = 0.0
local STORM_LIGHTING = "$GAME_DATA/Render/RenderSettings/World/world_warehouse_countdown.rendersettings"
-- Same red screen the seeker bot uses when it spots you
local STORM_RENDER_SETTINGS = "$GAME_DATA/Render/RenderSettings/Gameplay/gameplay_scannerbot.rendersettings"
local STORM_ALARM_EFFECT = "PacificScrap - Alarm" -- warehouse alarm sound, three times

local LANDING_ATTEMPTS = 24
-- Energy anchor parts (Objects/Database/ShapeSets/example.shapeset)
local ANCHOR_UUID = sm.uuid.new( "c243bb55-92f9-4f77-bb2a-b7c87b5a2be9" ) -- stable (all kinds are the same size)

local function CarryingAnchor( player )
	local carry = player:getCarry()
	for _, uuid in ipairs( ENERGY_ANCHOR_UUIDS ) do
		if sm.container.totalQuantity( carry, uuid ) > 0 then return true end
	end
	return false
end
local PEDESTAL_UUID = sm.uuid.new( "a6be2c12-f280-4d2b-b270-8e407813c28d" )
-- (static bodies too: floors built from parts in an edited tile)
local GROUND_MASK = sm.physics.filter.terrainSurface + sm.physics.filter.terrainAsset + sm.physics.filter.staticBody
local LANDING_MASK = GROUND_MASK + sm.physics.filter.harvestable


-- Shared helpers ------------------------------------------------------------

-- A ring of upright panels. The panel mesh is a PANEL_MESH_SIZE square in its
-- local XZ plane, facing +Y (the game reads its units as metres and doesn't
-- turn it Z-up). One panel per side: the materials draw both faces.
local PANEL_MESH_SIZE = 100.0
local PANEL_BASE_ROTATION = sm.quat.angleAxis( math.pi * 0.5, sm.vec3.new( 0, 0, 1 ) ) -- x->along, y->facing, z->up
local function CreateRing( effectName, panels, rows )
	local effects = { columns = panels, rows = rows or 1 }
	for i = 1, panels * ( rows or 1 ) do
		effects[i] = sm.effect.createEffect( effectName )
	end
	return effects
end

-- Same panel turned 90 degrees in its own plane (texture runs the other way)
local PANEL_SIDEWAYS_ROTATION = sm.quat.new( -0.5, -0.5, -0.5, 0.5 ) -- x->up, y->facing, z->along

-- The game doesn't draw anything much past a kilometre from the camera, which
-- cut big holes in the far side of the storm wall. Shrinking an object towards
-- the camera moves every point along its own line of sight, so it looks exactly
-- the same, just nearer. So every frame, each panel reaching further than this
-- is pulled in (and shrunk) until its far edge is this close.
local PANEL_DRAW_LIMIT = 750.0

local function UpdateRing( effects, center, radius, bottom, height, sideways )
	local camera = sm.camera.getPosition()
	local panels = effects.columns
	local rows = effects.rows
	local step = 2 * math.pi / panels
	local width = 2 * radius * math.sin( step / 2 ) + 0.05 -- just touching, so no overlap seams
	local inset = radius * math.cos( step / 2 )
	local rowHeight = height / rows
	local halfDiagonal = 0.5 * math.sqrt( width * width + rowHeight * rowHeight )
	local scale = sm.vec3.new( width / PANEL_MESH_SIZE, 1, rowHeight / PANEL_MESH_SIZE )
	local baseRotation = PANEL_BASE_ROTATION
	if sideways then
		scale = sm.vec3.new( rowHeight / PANEL_MESH_SIZE, 1, width / PANEL_MESH_SIZE )
		baseRotation = PANEL_SIDEWAYS_ROTATION
	end
	local up = sm.vec3.new( 0, 0, 1 )
	for i = 1, panels do
		local angle = ( i - 0.5 ) * step
		local rotation = sm.quat.angleAxis( angle, up ) * baseRotation
		for row = 1, rows do
			local effect = effects[( row - 1 ) * panels + i]
			if sm.exists( effect ) then
				local position = sm.vec3.new( center.x + math.cos( angle ) * inset, center.y + math.sin( angle ) * inset, bottom + rowHeight * ( row - 0.5 ) )
				local k = math.min( 1.0, PANEL_DRAW_LIMIT / ( ( position - camera ):length() + halfDiagonal ) )
				effect:setPosition( camera + ( position - camera ) * k )
				effect:setRotation( rotation )
				effect:setScale( scale * k )
			end
		end
	end
end

-- Survival's weather (rain, clouds) plays in the world registered as
-- "weatherworld" (the garage, as survival's overworld). Each world claims it
-- while the local player is in it, so the weather follows you into the zone.
local function ClaimWeatherWorld( world )
	if not g_worldManager or not g_worldManager.cl_worlds then
		return
	end
	local character = sm.localPlayer.getPlayer().character
	if character and sm.exists( character ) and character:getWorld() == world and WorldManager.Cl_GetWorld( "weatherworld" ) ~= world then
		WorldManager.Cl_RegisterWorld( "weatherworld", world )
	end
end

local function GroundBelow( from, distance, mask )
	local hit, result = sm.physics.raycast( from, from - sm.vec3.new( 0, 0, distance ), nil, mask )
	if hit then
		return result.pointWorld, result.type
	end
end

-- The floor at a spot, even under a roof (the junction's elevator): the
-- terrain there, then whatever is just above it (a platform, a floor)
local FLOOR_PROBE_HEIGHT = 3.0
local function FloorAt( position )
	local terrain = GroundBelow( sm.vec3.new( position.x, position.y, 512 ), 1024, sm.physics.filter.terrainSurface )
	if not terrain then
		return nil
	end
	return GroundBelow( terrain + sm.vec3.new( 0, 0, FLOOR_PROBE_HEIGHT ), FLOOR_PROBE_HEIGHT + 2, GROUND_MASK ) or terrain
end

-- Cancels the velocity of every dynamic body near a point (so the car doesn't
-- keep its speed through a portal)
local function StopBodiesNear( world, position, radius )
	for _, body in ipairs( sm.body.getAllBodies( world ) ) do
		if sm.exists( body ) and body:isDynamic() and ( body.worldPosition - position ):length() < radius then
			sm.physics.applyImpulse( body, body.velocity * -body.mass, true )
		end
	end
end

-- An ellipsoid with the given radii (metres) centered at position
local function CreateSphereEffect( name, position, radii )
	local effect = sm.effect.createEffect( name )
	effect:setPosition( position )
	effect:setScale( radii * ( 1.0 / SPHERE_MESH_RADIUS ) )
	return effect
end

local function DestroyEffects( effects )
	for _, effect in ipairs( effects or {} ) do
		if sm.exists( effect ) then
			effect:destroy()
		end
	end
end

-- Only show marker effects while the local player is in that world
local function UpdateEffectVisibility( world, effects )
	local character = sm.localPlayer.getPlayer().character
	local here = character ~= nil and sm.exists( character ) and character:getWorld() == world
	for _, effect in ipairs( effects or {} ) do
		if sm.exists( effect ) then
			if here and not effect:isPlaying() then
				effect:start()
			elseif not here and effect:isPlaying() then
				effect:stop()
			end
		end
	end
end


-- Garage --------------------------------------------------------------------

-- Inherits the survival Overworld so respawning, quests and anything that
-- looks up the "overworld" world keep working.
GarageWorld = class( Overworld )
GarageWorld.terrainScript = "$CONTENT_DATA/Scripts/terrain.lua"
-- (plus the forest ring on the mountains round it, WORLD_RING)
GarageWorld.cellMinX = GARAGE_CELL_MIN - WORLD_RING
GarageWorld.cellMaxX = GARAGE_CELL_MAX + WORLD_RING
GarageWorld.cellMinY = GARAGE_CELL_MIN - WORLD_RING
GarageWorld.cellMaxY = GARAGE_CELL_MAX + WORLD_RING
GarageWorld.horizonWater = false
GarageWorld.hLod = false
GarageWorld.worldBorder = true
-- No voxel (diggable) terrain: the worlds are built purely from tiles
GarageWorld.enableVoxelTerrain = false

function GarageWorld.server_onCreate( self )
	Overworld.server_onCreate( self )
	-- Overworld replaces the terrain script data; put our tile layout back
	self.world:setTerrainScriptData( { tiles = self.data and self.data.tiles, edge = self.data and self.data.edge, filterVoxelTrianglesFromNavMesh = true } )
	self.world.publicData.type = "GarageWorld"
	self.sv.pad = nil
	-- On load this starts after the game script, so ask for the launch pad
	sm.event.sendToGame( "sv_e_garageReady" )
end

-- The garage junction's launch pad is found once its cell loads
function GarageWorld.sv_checkJunctionPad( self, x, y )
	local junction = GARAGE_JUNCTION
	if junction and x == junction.x and y == junction.y then
		local ground = FloorAt( JunctionPadPosition( junction ) )
		if ground then
			sm.event.sendToGame( "sv_e_junctionPadFound", { ground = ground } )
		end
	end
	-- (garages from older saves don't have the exit tile)
	local exit = GARAGE_EXIT
	if exit and self.data and self.data.hasExit and x == exit.x and y == exit.y then
		local ground = FloorAt( JunctionPadPosition( exit ) )
		if ground then
			sm.event.sendToGame( "sv_e_exitFound", { ground = ground } )
		end
	end
end

local function SpawnCell()
	return math.floor( GARAGE_SPAWN.x / 64 ), math.floor( GARAGE_SPAWN.y / 64 )
end

-- Measures the real ground height at the spawn point and points the survival
-- spawn constants (used by new players and respawns) at it
function GarageWorld.sv_updateSpawnPoint( self, x, y )
	local cx, cy = SpawnCell()
	if x ~= cx or y ~= cy then
		return
	end
	local ground = GroundBelow( sm.vec3.new( GARAGE_SPAWN.x, GARAGE_SPAWN.y, 512 ), 1024, sm.physics.filter.terrainSurface )
	local z = ground and ( ground.z + 1.0 ) or GARAGE_SPAWN.z
	START_AREA_SPAWN_POINT = sm.vec3.new( GARAGE_SPAWN.x, GARAGE_SPAWN.y, z )
	SURVIVAL_DEV_SPAWN_POINT = START_AREA_SPAWN_POINT
end

-- The Friendly Dumpster, Fabricator and Route Planner are part of the garage
-- tile now; the cheats (/dumpster, /routeplanner) can still put one down
local PROP_STANDING = sm.quat.angleAxis( math.rad( 90 ), sm.vec3.new( 1, 0, 0 ) ) -- props are modelled Y-up

-- A static part standing on the ground (the terrain itself, not trees or rocks)
local function PlacePropOnGround( uuid, x, y, degrees )
	local ground = GroundBelow( sm.vec3.new( x, y, 512 ), 1024, sm.physics.filter.terrainSurface ) or sm.vec3.new( x, y, 0 )
	local rotation = sm.quat.angleAxis( math.rad( degrees or 0 ), sm.vec3.new( 0, 0, 1 ) ) * PROP_STANDING
	local size = sm.item.getShapeSize( uuid ) * 0.25
	local center = ground + sm.vec3.new( 0, 0, size.y * 0.5 + 0.02 )
	sm.shape.createPart( uuid, center - rotation * ( size * 0.5 ), rotation, false, true )
	sm.log.info( "[PacificScrap] Placed", tostring( uuid ), "at", ground )
	return ground
end

-- The garage's battery socket (survival's power core socket, in the garage
-- tile): once a battery is in it, the garage has power (the Getting Started
-- quest, Story.lua). Survival's own socket script does the inserting, the
-- effect and the lights wired to it; this only watches whether it's on.
local POWER_SOCKET_UUID = sm.uuid.new( "c0159b96-edf3-46cd-9fbe-96ee1126304b" )

function GarageWorld.sv_findSocket( self )
	if self.sv.socket and sm.exists( self.sv.socket ) then return end
	for _, body in ipairs( sm.body.getAllBodies( self.world ) ) do
		for _, shape in ipairs( sm.exists( body ) and body:getShapes() or {} ) do
			if shape.uuid == POWER_SOCKET_UUID and shape.interactable then
				self.sv.socket = shape.interactable
				return
			end
		end
	end
end

-- While the garage has no power: where the quest marker goes. The Friendly
-- Dumpster (the battery is in it), until someone has a battery on them: then
-- the socket.
local POWER_CORE_SHAPE_UUID = sm.uuid.new( "c654a023-ca53-4109-9f18-d297c18e9a02" )
local DUMPSTER_UUID = sm.uuid.new( "d0f1e2a3-b4c5-4d6e-8f70-81a2b3c4d5e6" )
function GarageWorld.sv_powerMarker( self )
	if g_garagePowered then
		return nil
	end
	local carried = false
	for _, player in ipairs( sm.player.getAllPlayers() ) do
		if sm.container.totalQuantity( player:getInventory(), POWER_CORE_SHAPE_UUID ) > 0
			or sm.container.totalQuantity( player:getCarry(), POWER_CORE_SHAPE_UUID ) > 0 then
			carried = true
		end
	end
	if not carried then
		if not ( self.sv.dumpster and sm.exists( self.sv.dumpster ) ) then
			self.sv.dumpster = nil
			for _, body in ipairs( sm.body.getAllBodies( self.world ) ) do
				for _, shape in ipairs( sm.exists( body ) and body:getShapes() or {} ) do
					if shape.uuid == DUMPSTER_UUID then self.sv.dumpster = shape end
				end
			end
		end
		if self.sv.dumpster then
			return { position = self.sv.dumpster.worldPosition, what = "dumpster" }
		end
	end
	if self.sv.socket and sm.exists( self.sv.socket ) then
		return { position = self.sv.socket.shape.worldPosition, what = "socket" }
	end
end

function GarageWorld.server_onFixedUpdate( self, dt )
	Overworld.server_onFixedUpdate( self, dt )
	local tick = sm.game.getCurrentTick()
	if tick % 40 == 7 then
		self:sv_findSocket()
		local socket = self.sv.socket
		local powered = socket ~= nil and sm.exists( socket ) and socket.active == true
		if powered and not self.sv.reportedPower then
			self.sv.reportedPower = true
			sm.event.sendToGame( "sv_e_garagePowered" )
		end
		-- The quest marker, when it moves
		local marker = self:sv_powerMarker()
		local key = marker and string.format( "%s %d %d %d", marker.what, marker.position.x, marker.position.y, marker.position.z ) or ""
		if key ~= self.sv.powerMarkerKey then
			self.sv.powerMarkerKey = key
			self.sv.powerMarker = marker
			self.network:sendToClients( "cl_n_powerMarker", marker or {} )
		end
	end
	if tick % 80 == 47 then
		self:sv_bankAnchors()
	end
	if tick % 200 == 123 then
		self:sv_ensureFuelPump()
	end
	if tick % 20 == 11 then
		self:sv_updateJunctionGate()
	end
	-- (rescue portals go once they've done their job)
	for i = #( self.sv.rescuePortals or {} ), 1, -1 do
		local entry = self.sv.rescuePortals[i]
		if entry.transfer and tick >= entry.transfer then
			entry.transfer = nil
			if sm.exists( entry.portal ) then entry.portal:transferAToB() end
		end
		if tick >= entry.tick then
			if sm.exists( entry.portal ) then sm.portal.destroy( entry.portal ) end
			table.remove( self.sv.rescuePortals, i )
		end
	end
end

-- The garage always has a Fuel Pump: if its spot's cell has been loaded a
-- while and no pump has turned up (knocked far away, or lost), one is put on
-- its spot (FUEL_PUMP_HOME; FuelPump.lua keeps it there). A lost one that
-- loads in later removes itself.
function GarageWorld.sv_ensureFuelPump( self )
	local loaded = self.sv.pumpCellLoadedTick
	if not loaded or sm.game.getCurrentTick() - loaded < 40 * 10 then return end
	for _, shape in pairs( g_fuelPumps or {} ) do
		if sm.exists( shape ) and shape.body:getWorld() == self.world then return end
	end
	PlaceFuelPumpAtHome()
	self.sv.pumpCellLoadedTick = sm.game.getCurrentTick() -- (give it time to start before looking again)
	sm.log.info( "[PacificScrap] No Fuel Pump in the garage: put one on its spot" )
end

-- /fuelpump with no pump in the garage (the game script can't make parts)
function GarageWorld.sv_e_placeFuelPump( self )
	PlaceFuelPumpAtHome()
end

function GarageWorld.sv_notePumpCell( self, x, y )
	if x == math.floor( FUEL_PUMP_HOME.x / 64 ) and y == math.floor( FUEL_PUMP_HOME.y / 64 ) then
		self.sv.pumpCellLoadedTick = self.sv.pumpCellLoadedTick or sm.game.getCurrentTick()
	end
end

-- The gate on the garage's junction: open while a route is set (and while
-- you're setting off), shut otherwise. The game says which (g_garageGateWanted);
-- each activation plays the gate to its other end, so it's only sent when the
-- gate is standing still at the wrong end. It only moves (with its alarm) when
-- someone's near enough to see; otherwise it's just put there, so it's never
-- left half-way when the garage unloads behind you.
function GarageWorld.sv_updateJunctionGate( self )
	local wanted = g_garageGateWanted == true
	-- (only while its cell is loaded: asking about an unloaded cell logs errors)
	if not self.sv.gateCellLoaded then return end
	for _, gate in ipairs( JunctionGates( self.world, GARAGE_JUNCTION.x, GARAGE_JUNCTION.y ) ) do
		if not GateMoving( gate ) and GateOpen( gate ) ~= wanted then
			local watched = false
			for _, player in ipairs( sm.player.getAllPlayers() ) do
				local character = player.character
				if character and sm.exists( character ) and character:getWorld() == self.world
					and ( character.worldPosition - gate.worldPosition ):length() < GATE_WATCH_RANGE then
					watched = true
				end
			end
			if watched then
				sm.event.sendToHarvestable( gate, "sv_e_activate" )
				if wanted then
					sm.effect.playEffect( GATE_ALARM_EFFECT, gate.worldPosition + sm.vec3.new( 0, 0, 2 ) )
				end
			else
				sm.event.sendToHarvestable( gate, "sv_e_resetTrack", { toBack = wanted } )
			end
		end
	end
end

function GarageWorld.cl_n_powerMarker( self, marker )
	if not g_worldMarkerManager then return end
	if marker and marker.position then
		WorldMarkerManager.Cl_CreateOrUpdateMarker( "pacificscrap_power", {
			effect = "QuestMarker",
			farEffect = "QuestMarker_Far",
			position = marker.position + sm.vec3.new( 0, 0, 1.2 ),
			world = self.world,
			textureIndex = 0,
			color = sm.color.new( "798B0FF1" ),
			compassImage = "icon_compass_main_quest.png",
			activate = true,
		} )
	else
		WorldMarkerManager.Cl_DestroyMarker( "pacificscrap_power" )
	end
end

-- /skipquest on Getting Started: the battery goes into the socket as if you'd
-- put it there (Survival's socket script does the lights and effect), and the
-- one lying about goes
function GarageWorld.sv_e_forcePower( self, params )
	self:sv_findSocket()
	local socket = self.sv.socket
	local player = params.player
	if not socket or not sm.exists( socket ) or socket.active or not player or not sm.exists( player ) then
		return
	end
	for _, body in ipairs( sm.body.getAllBodies( self.world ) ) do
		for _, shape in ipairs( sm.exists( body ) and body:getShapes() or {} ) do
			if shape.uuid == POWER_CORE_SHAPE_UUID then shape:destroyShape() end
		end
	end
	sm.container.beginTransaction()
	sm.container.collect( player:getInventory(), POWER_CORE_SHAPE_UUID, 1, true )
	if sm.container.endTransaction() then
		sm.event.sendToInteractable( socket, "sv_e_unlock", { player = player, keyId = POWER_CORE_SHAPE_UUID } )
	end
end

-- Anchors can't stay anchors at home: every couple of seconds, any in the
-- garage (lying about, on a car, in an ARC Device, carried) is taken and
-- banked into the Fabricator as its energy. So a trip always starts with an
-- empty ARC Device, and every anchor brought home counts.
local FABRICATOR_UUID = sm.uuid.new( "7ee97af5-72b9-4335-a3bd-e80d49dab105" )
local ARC_DEVICE_UUID = sm.uuid.new( "a6258a75-ea2b-47f7-acec-a3ace313bbd9" )
function GarageWorld.sv_bankAnchors( self )
	local fabricator
	local found = {} -- { kind = n }
	local total = 0
	local popups = {} -- where each came from: { pos, kind, n }
	local function add( uuid, n, pos )
		local anchor = EnergyAnchorOf( uuid )
		if anchor and n > 0 then
			found[anchor.name] = ( found[anchor.name] or 0 ) + n
			total = total + n
			popups[#popups + 1] = { pos = pos, kind = anchor.name, n = n }
		end
	end
	local loose, arcs = {}, {}
	for _, body in ipairs( sm.body.getAllBodies( self.world ) ) do
		for _, shape in ipairs( sm.exists( body ) and body:getShapes() or {} ) do
			if shape.uuid == FABRICATOR_UUID and shape.interactable then
				fabricator = shape.interactable
			elseif shape.uuid == ARC_DEVICE_UUID and shape.interactable then
				arcs[#arcs + 1] = shape.interactable
			elseif EnergyAnchorOf( shape.uuid ) then
				loose[#loose + 1] = shape
			end
		end
	end
	if not fabricator then
		return -- (nowhere to bank them)
	end
	local function empty( container, pos )
		for _, uuid in ipairs( ENERGY_ANCHOR_UUIDS ) do
			local n = sm.container.totalQuantity( container, uuid )
			if n > 0 then
				sm.container.beginTransaction()
				sm.container.spend( container, uuid, n, true )
				if sm.container.endTransaction() then add( uuid, n, pos ) end
			end
		end
	end
	for _, shape in ipairs( loose ) do
		add( shape.uuid, 1, shape.worldPosition )
		shape:destroyShape()
	end
	for _, arc in ipairs( arcs ) do
		local container = arc:getContainer( 0 )
		if container then
			local before = total
			empty( container, arc.shape.worldPosition )
			if total > before then sm.event.sendToInteractable( arc, "sv_e_refreshCount" ) end
		end
	end
	for _, player in ipairs( sm.player.getAllPlayers() ) do
		local character = player.character
		if character and sm.exists( character ) and character:getWorld() == self.world then
			empty( player:getCarry(), character.worldPosition + sm.vec3.new( 0, 0, 1.2 ) )
		end
	end
	if total > 0 then
		sm.event.sendToInteractable( fabricator, "sv_e_depositAnchors", found )
		local parts = {}
		for _, anchor in ipairs( ENERGY_ANCHORS ) do
			if found[anchor.name] then parts[#parts + 1] = anchor.colour .. "+" .. found[anchor.name] .. " " .. anchor.title:lower() end
		end
		self.network:sendToClients( "cl_n_anchorsBanked", { text = "Energy banked at the Fabricator\n" .. table.concat( parts, "#FFFFFF, " ), popups = popups } )
		sm.log.info( "[PacificScrap] Anchors banked:", total )
		sm.event.sendToGame( "sv_e_anchorsBanked" ) -- (the Gearing Up quest, Story.lua)
	end
end

-- The mining vault's deposit popup and sound where each anchor was: "+N" in
-- the anchor's colour rising from it (Survival's "Miningvault - AmmountText"
-- in the vault's number font, and "Miningvault - placement01")
local POPUP_STACK = 0.45 -- metres between popups from the same spot
function GarageWorld.cl_n_anchorsBanked( self, data )
	sm.gui.displayAlertText( data.text, 5 )
	local character = sm.localPlayer.getPlayer().character
	if not character or not sm.exists( character ) or character:getWorld() ~= self.world then
		return -- (the popups are for whoever's in the garage)
	end
	local camera = sm.camera.getPosition()
	local stacked = {}
	for _, popup in ipairs( data.popups or {} ) do
		local key = string.format( "%d,%d,%d", popup.pos.x, popup.pos.y, popup.pos.z )
		local level = stacked[key] or 0
		stacked[key] = level + 1
		local pos = popup.pos + sm.vec3.new( 0, 0, 0.6 + level * POPUP_STACK )
		-- (the text faces the camera: turned about the vertical)
		local toCamera = camera - pos
		local rotation = sm.quat.angleAxis( math.atan2( -toCamera.x, toCamera.y ), sm.vec3.new( 0, 0, 1 ) )
		local anchor = ENERGY_ANCHOR_BY_NAME[popup.kind]
		local colour = anchor and sm.color.new( anchor.colour:sub( 2 ) .. "ff" ) or sm.color.new( "ffffffff" )
		sm.effect.playEffect( "Miningvault - AmmountText", pos, nil, rotation, nil, { TextContent = "+" .. popup.n, Color = colour } )
		if level == 0 then
			sm.effect.playEffect( "Miningvault - placement01", popup.pos )
		end
	end
end

-- /dumpster (the game script can't create parts itself)
function GarageWorld.sv_e_placePart( self, params )
	PlacePropOnGround( params.uuid, params.x, params.y, params.rotation )
end

function GarageWorld.server_onCellCreated( self, x, y )
	Overworld.server_onCellCreated( self, x, y )
	if x == GARAGE_JUNCTION.x and y == GARAGE_JUNCTION.y then self.sv.gateCellLoaded = true end
	self:sv_findSocket()
	self:sv_updateSpawnPoint( x, y )
	self:sv_checkJunctionPad( x, y )
	self:sv_notePumpCell( x, y )
end

function GarageWorld.server_onCellLoaded( self, x, y )
	Overworld.server_onCellLoaded( self, x, y )
	if x == GARAGE_JUNCTION.x and y == GARAGE_JUNCTION.y then self.sv.gateCellLoaded = true end
	self:sv_findSocket()
	self:sv_updateSpawnPoint( x, y )
	self:sv_checkJunctionPad( x, y )
	self:sv_notePumpCell( x, y )
end

function GarageWorld.server_onCellUnloaded( self, x, y )
	Overworld.server_onCellUnloaded( self, x, y )
	if x == GARAGE_JUNCTION.x and y == GARAGE_JUNCTION.y then self.sv.gateCellLoaded = nil end
	-- (the pump's cell gone: its pump is unloaded, not lost)
	if x == math.floor( FUEL_PUMP_HOME.x / 64 ) and y == math.floor( FUEL_PUMP_HOME.y / 64 ) then
		self.sv.pumpCellLoadedTick = nil
	end
end

function GarageWorld.sv_spawnNewCharacter( self, params )
	params.fallbackPosition = START_AREA_SPAWN_POINT
	Overworld.sv_spawnNewCharacter( self, params )
end

-- Finds the ground under a player (or at params.position) for placing the launch pad
function GarageWorld.sv_e_measurePad( self, params )
	local character = params.player.character
	if not character or not sm.exists( character ) or character:getWorld() ~= self.world then
		sm.event.sendToGame( "sv_e_onPadMeasured", { player = params.player, failed = true } )
		return
	end
	local ground
	if params.position then
		ground = FloorAt( params.position )
	end
	if not ground then
		local position = character.worldPosition
		ground = GroundBelow( position + sm.vec3.new( 0, 0, 0.5 ), 30, GROUND_MASK ) or ( position - sm.vec3.new( 0, 0, 1.5 ) )
		params.position = nil
	end
	params.ground = ground
	sm.event.sendToGame( "sv_e_onPadMeasured", params )
end

-- Driving (or walking) onto the pad departs
local PAD_TRIGGER_HALF_SIZE = sm.vec3.new( 3.5, 3.5, 20.0 ) -- thin and tall (a roof over the pad doesn't matter)

function GarageWorld.sv_e_setPad( self, params )
	self.sv.pad = { ground = params.ground }
	self.network:sendToClients( "cl_n_setPad", self.sv.pad )
	if self.sv.padTrigger then
		sm.areaTrigger.destroy( self.sv.padTrigger )
	end
	self.sv.padTrigger = sm.areaTrigger.createBox( PAD_TRIGGER_HALF_SIZE, params.ground + sm.vec3.new( 0, 0, 4.0 ), sm.quat.identity(), sm.areaTrigger.filter.character )
	self.sv.padTrigger:bindOnEnter( "trigger_onPad" )
	self.sv.padTrigger:bindOnStay( "trigger_onPad" )
end

function GarageWorld.trigger_onPad( self, trigger, results )
	-- (fires every tick while someone is on it)
	local tick = sm.game.getCurrentTick()
	if self.sv.padFiredTick and tick - self.sv.padFiredTick < 20 then
		return
	end
	self.sv.padFiredTick = tick
	for _, object in ipairs( results ) do
		if sm.exists( object ) and type( object ) == "Character" and object:isPlayer() then
			sm.event.sendToGame( "sv_e_garageJunction", { player = object:getPlayer() } )
			return
		end
	end
end

-- Back through the gateway: a teleport sound for everyone at the garage
function GarageWorld.sv_e_playTeleport( self, params )
	self.network:sendToClients( "cl_n_playTeleport", params )
end

function GarageWorld.cl_n_playTeleport( self, params )
	local character = sm.localPlayer.getPlayer().character
	if character and sm.exists( character ) and character:getWorld() == self.world then
		sm.effect.playEffect( "PacificScrap - Teleport", character.worldPosition )
	end
end

-- Failsafe after a gateway return: anything near the exit that ended up below
-- its floor (a car, a player) is lifted back above it through a small portal
local RESCUE_RADIUS = 20
local RESCUE_DEPTH = 1.5 -- only what's this far below the floor (really stuck, not just lower ground)
function GarageWorld.sv_e_rescueBelowFloor( self, params )
	local floor = params.floor
	local function lift( center, halfSize, bottom )
		local portal = sm.portal.createPortal( halfSize )
		portal:setOpeningA( center, sm.quat.identity(), self.world )
		portal:setOpeningB( center + sm.vec3.new( 0, 0, floor - bottom + 0.6 ), sm.quat.identity(), self.world )
		-- (it carries a moment later: a new portal needs that)
		self.sv.rescuePortals = self.sv.rescuePortals or {}
		self.sv.rescuePortals[#self.sv.rescuePortals + 1] = { portal = portal, transfer = sm.game.getCurrentTick() + 3, tick = sm.game.getCurrentTick() + 40 }
	end
	local function near( p )
		return DistanceXY( p, params.position ) < RESCUE_RADIUS
	end
	-- Whole creations, one portal each (moving the same things through several
	-- portals at once duplicates them)
	local done = {}
	for _, body in ipairs( sm.body.getAllBodies( self.world ) ) do
		if sm.exists( body ) and body:isDynamic() and not done[body.id] and near( body.worldPosition ) then
			local low, high
			for _, b in ipairs( body:getCreationBodies() ) do
				done[b.id] = true
				local ok, a, c = pcall( function() return b:getWorldAabb() end )
				if ok and a then
					low = low and sm.vec3.new( math.min( low.x, a.x ), math.min( low.y, a.y ), math.min( low.z, a.z ) ) or a
					high = high and sm.vec3.new( math.max( high.x, c.x ), math.max( high.y, c.y ), math.max( high.z, c.z ) ) or c
				end
			end
			if low and low.z < floor - RESCUE_DEPTH then
				lift( ( low + high ) * 0.5, ( high - low ) * 0.5 + sm.vec3.new( 0.5, 0.5, 0.5 ), low.z )
				sm.log.warning( "[PacificScrap] Lifted a creation out of the floor at the garage exit" )
			end
		end
	end
	for _, player in ipairs( sm.player.getAllPlayers() ) do
		local character = player.character
		if character and sm.exists( character ) and character:getWorld() == self.world and near( character.worldPosition )
			and not character:isSeated() and character.worldPosition.z < floor - RESCUE_DEPTH then
			lift( character.worldPosition, sm.vec3.new( 1.0, 1.0, 1.5 ), character.worldPosition.z - 1.0 )
			sm.log.warning( "[PacificScrap] Lifted", player.name, "out of the floor at the garage exit" )
		end
	end
end

-- Back through the gateway at speed: everything that came through moves on
-- along the garage road at that speed (its velocity set, flat)
function GarageWorld.sv_e_launchBodies( self, params )
	local target = params.dir * params.speed
	for _, body in ipairs( sm.body.getAllBodies( self.world ) ) do
		if sm.exists( body ) and body:isDynamic() and ( body.worldPosition - params.position ):length() < params.radius then
			local v = body.velocity
			local change = sm.vec3.new( target.x - v.x, target.y - v.y, -v.z )
			sm.physics.applyImpulse( body, change * body.mass, true )
		end
	end
end

function GarageWorld.sv_e_stopBodiesNear( self, params )
	StopBodiesNear( self.world, params.position, params.radius )
end

function GarageWorld.sv_n_requestPad( self, _, player )
	self.network:sendToClient( player, "cl_n_setPad", self.sv.pad or {} )
	self.network:sendToClient( player, "cl_n_powerMarker", self.sv.powerMarker or {} )
end

function GarageWorld.client_onCreate( self )
	Overworld.client_onCreate( self )
	self.padEffects = {}
	self.network:sendToServer( "sv_n_requestPad" )
end

function GarageWorld.client_onDestroy( self )
	Overworld.client_onDestroy( self )
	DestroyEffects( self.padEffects )
end

function GarageWorld.cl_n_setPad( self, data )
	DestroyEffects( self.padEffects )
	self.padEffects = {}
	if data and data.ground then
		-- A flat glowing disc
		local disc = CreateSphereEffect( GATEWAY_SPHERE_EFFECT, data.ground + sm.vec3.new( 0, 0, 0.1 ), sm.vec3.new( PAD_RADIUS, PAD_RADIUS, 0.15 ) )
		self.padEffects = { disc }
	end
end

-- A phone call's new text bubble (Dialogs.lua sets g_pacificDialogBubble):
-- the world the local player is in plays its voice at their character
local function PlayDialogBubble( self )
	local bubble = g_pacificDialogBubble
	if not bubble or bubble.key == g_pacificDialogBubblePlayed then
		return
	end
	local character = sm.localPlayer.getPlayer().character
	if character and sm.exists( character ) and character:getWorld() == self.world then
		g_pacificDialogBubblePlayed = bubble.key
		sm.effect.playEffect( bubble.audio, character.worldPosition + sm.vec3.new( 0, 0, 0.8 ) )
	end
end

function GarageWorld.client_onFixedUpdate( self )
	Overworld.client_onFixedUpdate( self )
	ClaimWeatherWorld( self.world )
	UpdateEffectVisibility( self.world, self.padEffects )
	PlayDialogBubble( self )
end


-- Zone ----------------------------------------------------------------------

ZoneWorld = class( BaseWorld )
ZoneWorld.terrainScript = "$CONTENT_DATA/Scripts/terrain.lua"
ZoneWorld.groundMaterialSet = Overworld.groundMaterialSet
ZoneWorld.voxelMaterialSet = Overworld.voxelMaterialSet
ZoneWorld.enableSurface = true
ZoneWorld.enableAssets = true
ZoneWorld.enableClutter = true
ZoneWorld.enableNodes = true
ZoneWorld.enableCreations = true
ZoneWorld.enableHarvestables = true
ZoneWorld.enableKinematics = true
ZoneWorld.enableVoxelTerrain = false -- see GarageWorld.enableVoxelTerrain
ZoneWorld.renderMode = "outdoor"
ZoneWorld.worldBorder = true
-- (plus the forest ring on the mountains round it, WORLD_RING)
ZoneWorld.cellMinX = ZONE_CELL_MIN - WORLD_RING
ZoneWorld.cellMaxX = ZONE_CELL_MAX + WORLD_RING
ZoneWorld.cellMinY = ZONE_CELL_MIN - WORLD_RING
ZoneWorld.cellMaxY = ZONE_CELL_MAX + WORLD_RING

function ZoneWorld.server_onCreate( self )
	BaseWorld.server_onCreate( self )
	sm.event.sendToGame( "sv_e_zoneReady", { world = self.world } ) -- (a run loaded from a save resumes now)
	-- A landmark world: survival's packing station manager links up a packing
	-- station's parts when their cell is first made (as the survival overworld does)
	if self.data and self.data.landmark then
		self.packingStationManager = PackingStationManager()
		self.packingStationManager:sv_onCreate( self )
	end
	self.world.publicData.type = "ZoneWorld"
	self.sv.ambienceManager = sm.scriptableObject.createScriptableObject( sm.uuid.new( "635b5d17-fa35-4591-82ec-358da595bac0" ), nil, self.world )
	self.sv.gateway = nil
	self.sv.loadedCells = {}
	ZoneTornadoes_SvInit( self )
	self:sv_checkLandmark() -- (a landmark is marked from the start, not only once you're near)

	-- Anchors: one entry per planned pedestal. Until its cell first loads, the
	-- marker sits at the middle of the cell. (A pooled world gets them every
	-- trip instead, from its anchor spots: sv_startTrip.)
	self.sv.saved = self.storage:load()
	if not self.sv.saved then
		self.sv.saved = { anchors = {}, anchorSpots = self.data and self.data.anchorSpots }
		for _, cell in ipairs( ( self.data and self.data.anchors ) or {} ) do
			self.sv.saved.anchors[#self.sv.saved.anchors + 1] = {
				x = cell.x, y = cell.y, kind = cell.kind,
				pos = sm.vec3.new( ( cell.x + 0.5 ) * 64, ( cell.y + 0.5 ) * 64, 20 )
			}
		end
		self.storage:save( self.sv.saved )
	end

	-- Junctions at the ends of the exit roads lead one junction deeper
	self.sv.junctionGround = {}
	self.sv.junctionTriggers = {}
	self:sv_createJunctionTriggers()
	self:sv_setTripPublicData()
	self:sv_checkTrip()
	self:sv_updateAnchors()
end

-- What this trip is like: the world's own data, or for a pooled world (the
-- zone pool, zone_pool.lua) what the game sent for this trip: { depth, zone,
-- conditions, anomalies, collapsed, locked }
function ZoneWorld.sv_trip( self )
	return ( self.sv.saved and self.sv.saved.trip ) or self.data or {}
end

-- (supply pods pick their loot by these: SupplyPod.lua)
-- (the zone it's in, for its tier: robots, music, pods; see NodeZoneDepth)
function ZoneWorld.sv_setTripPublicData( self )
	local trip = self:sv_trip()
	self.world.publicData.depth = trip.zone or trip.depth or 1
	self.world.publicData.collapsed = trip.collapsed == true
end

function ZoneWorld.sv_createJunctionTriggers( self )
	for index, junction in ipairs( ( self.data and self.data.junctions ) or {} ) do
		local trigger = sm.areaTrigger.createBox( JUNCTION_TRIGGER_HALF_SIZE, JunctionPadPosition( junction ), sm.quat.identity(), sm.areaTrigger.filter.character, { junction = index } )
		trigger:bindOnEnter( "trigger_onJunction" )
		trigger:bindOnStay( "trigger_onJunction" )
		self.sv.junctionTriggers[#self.sv.junctionTriggers + 1] = trigger
	end
end


-- A pooled zone world used again ------------------------------------------------
-- (the zone pool, zone_pool.lua) The game puts what's new for the trip in
-- g_zoneTrip { id, world, depth, zone, conditions, anomalies, collapsed,
-- locked, anchors = { kinds } }. The world it's for picks it up whenever it
-- notices (its script starting, a cell loading, every few ticks): it wakes up
-- if it was retired, and starts afresh. A cell's leftovers from earlier trips
-- are cleared and its anchors, robots and mines put down the first time it
-- loads this trip (sv_tripCell), as a new world does as its cells are made.
-- Worlds made without the pool never get a trip, so none of this runs there.

function ZoneWorld.sv_checkTrip( self )
	local trip = g_zoneTrip
	if trip and trip.world and trip.world.id == self.world.id and trip.id ~= self.sv.saved.tripId then
		self:sv_startTrip( trip )
	end
end

function ZoneWorld.sv_startTrip( self, trip )
	local saved = self.sv.saved
	-- (the last trip's anchors still out there go, pedestals too; ones in
	-- cells that aren't loaded go when their cell next loads)
	for _, anchor in ipairs( saved.anchors or {} ) do
		if anchor.shape and sm.exists( anchor.shape ) then anchor.shape:destroyShape() end
		if anchor.pedestal and sm.exists( anchor.pedestal ) then anchor.pedestal:destroyShape() end
	end
	saved.tripId = trip.id
	saved.trip = { depth = trip.depth, zone = trip.zone, conditions = trip.conditions, anomalies = trip.anomalies,
		collapsed = trip.collapsed, locked = trip.locked }
	-- This trip's anchors, on some of the world's anchor spots
	local spots = {}
	for _, spot in ipairs( saved.anchorSpots or {} ) do spots[#spots + 1] = spot end
	saved.anchors = {}
	for _, kind in ipairs( trip.anchors or {} ) do
		if #spots == 0 then break end
		local spot = table.remove( spots, math.random( #spots ) )
		saved.anchors[#saved.anchors + 1] = { x = spot.x, y = spot.y, kind = kind,
			pos = sm.vec3.new( ( spot.x + 0.5 ) * 64, ( spot.y + 0.5 ) * 64, 20 ) }
	end
	saved.tripCells = {}
	saved.spots = nil -- (where players were, for towing: this trip's only)
	saved.entryJunction = nil
	-- Retired after an earlier trip: awake again
	if saved.retired then
		saved.retired = nil
		if #self.sv.junctionTriggers == 0 then
			self:sv_createJunctionTriggers()
		end
	end
	ZoneTornadoes_SvClear( self )
	self:sv_e_clearGateway()
	self.sv.storm = nil
	self.sv.collapseTick = nil
	self.sv.arrivals = {}
	self.sv.recover = nil
	self:sv_setTripPublicData()
	self.storage:save( saved )
	-- Cells loaded already: their turn now (nobody's here yet, so no robots)
	for key in pairs( self.sv.loadedCells ) do
		local x, y = key:match( "^(-?%d+),(-?%d+)$" )
		if x then self:sv_tripCell( tonumber( x ), tonumber( y ) ) end
	end
	self.network:sendToClients( "cl_n_newTrip" )
	self:sv_updateAnchors()
	self:sv_sendJunctionMarkers()
	sm.log.info( "[PacificScrap] Zone world", self.world.id, "starts trip", trip.id, "with", #saved.anchors, "anchors" )
end

-- What earlier trips left in a cell: anchors and their pedestals, supply
-- pods, our robots and mines (only things standing on their own: nothing
-- built into a creation)
local LEFTOVER_SHAPES = {}
local LEFTOVER_UNITS = {}
local leftoverListsMade = false
local function LeftoverLists()
	if leftoverListsMade then return end
	leftoverListsMade = true
	LEFTOVER_SHAPES["a6be2c12-f280-4d2b-b270-8e407813c28d"] = true -- anchor pedestal
	LEFTOVER_SHAPES["7de73157-8f20-4fe6-9514-299fc166aaf7"] = true -- supply pod
	for _, anchor in ipairs( ENERGY_ANCHORS ) do LEFTOVER_SHAPES[anchor.uuid] = true end
	LEFTOVER_UNITS["9360d346-3ff2-4925-a068-660cf5dd5267"] = true -- red totebot (Minefield)
	for _, tier in ipairs( ZONE_TIERS ) do
		for _, unit in ipairs( tier.enemies and tier.enemies.units or {} ) do LEFTOVER_UNITS[unit[1]] = true end
	end
end

function ZoneWorld.sv_clearLeftovers( self, x, y )
	LeftoverLists()
	local function inCell( p )
		return p.x >= x * 64 and p.x < ( x + 1 ) * 64 and p.y >= y * 64 and p.y < ( y + 1 ) * 64
	end
	local cleared = 0
	for _, body in ipairs( sm.body.getAllBodies( self.world ) ) do
		if sm.exists( body ) and inCell( body.worldPosition ) then
			local shapes = body:getShapes()
			if #shapes == 1 and #body:getCreationBodies() == 1 and LEFTOVER_SHAPES[tostring( shapes[1].uuid )] then
				shapes[1]:destroyShape()
				cleared = cleared + 1
			end
		end
	end
	for _, unit in ipairs( sm.unit.getAllUnits( self.world ) ) do
		local character = sm.exists( unit ) and unit:getCharacter()
		if character and sm.exists( character ) and character:getWorld() == self.world and inCell( character.worldPosition )
			and LEFTOVER_UNITS[tostring( character:getCharacterType() )] then
			sm.unit.forceDestroy( unit )
			cleared = cleared + 1
		end
	end
	if cleared > 0 then
		sm.log.info( "[PacificScrap] Cleared", cleared, "leftovers of an earlier trip in cell", x, y )
	end
end

-- A cell's first load this trip (or, without the pool, its first load ever):
-- its anchors, robots, mines and pods
function ZoneWorld.sv_tripCell( self, x, y )
	local saved = self.sv.saved
	saved.tripCells = saved.tripCells or {}
	local key = x .. "," .. y
	if saved.tripCells[key] then return end
	saved.tripCells[key] = true
	if saved.tripId then
		self:sv_clearLeftovers( x, y )
	end
	for _, anchor in ipairs( saved.anchors ) do
		if anchor.x == x and anchor.y == y and not anchor.shape and not anchor.collected then
			self:sv_spawnAnchor( x, y, anchor )
		end
	end
	self.storage:save( saved )
	-- (nothing spawns in the forest ring outside the playable area)
	if x < ZONE_CELL_MIN or x > ZONE_CELL_MAX or y < ZONE_CELL_MIN or y > ZONE_CELL_MAX then
		return
	end
	-- (not where you're about to land: those cells load before you arrive)
	if self:sv_anyPlayerHere() then
		self:sv_spawnMines( x, y )
		self:sv_spawnEnemies( x, y )
	end
	-- A collapsed zone: supply pods lie about
	if self:sv_trip().collapsed and not saved.retired and math.random() < COLLAPSED_POD_CHANCE then
		local px, py = ( x + 0.2 + math.random() * 0.6 ) * 64, ( y + 0.2 + math.random() * 0.6 ) * 64
		local ground, kind = GroundBelow( sm.vec3.new( px, py, 512 ), 1024, LANDING_MASK )
		if ground and kind == "terrainSurface" then
			self:sv_createPod( ground, false )
		end
	end
end

-- The junction you arrived by doesn't lead anywhere
function ZoneWorld.sv_e_setEntryJunction( self, params )
	self.sv.saved.entryJunction = params.index
	self.storage:save( self.sv.saved )
	self:sv_sendJunctionMarkers()
end

-- Markers on the junctions that lead on (none while the exits are locked: a
-- pooled world has every road, a new one only the way you came)
function ZoneWorld.sv_sendJunctionMarkers( self, player )
	local positions = {}
	local junctions = not self:sv_trip().locked and self.data and self.data.junctions or {}
	for index, junction in ipairs( junctions ) do
		if index ~= self.sv.saved.entryJunction then
			local position = JunctionPadPosition( junction )
			local ground = self.sv.junctionGround and self.sv.junctionGround[index]
			positions[#positions + 1] = { position = ground or position, onGround = ground ~= nil }
		end
	end
	if player then
		self.network:sendToClient( player, "cl_n_setJunctionMarkers", positions )
	else
		self.network:sendToClients( "cl_n_setJunctionMarkers", positions )
	end
end

function ZoneWorld.trigger_onJunction( self, trigger, results )
	local userData = trigger:getUserData()
	local index = userData and userData.junction
	if not index or self.sv.saved.retired then
		return
	end
	-- (fires every tick while you stand in it; the game ignores repeats)
	local tick = sm.game.getCurrentTick()
	if self.sv.junctionFiredTick and tick - self.sv.junctionFiredTick < 40 then
		return
	end
	for _, object in ipairs( results ) do
		if sm.exists( object ) and type( object ) == "Character" and object:isPlayer() then
			self.sv.junctionFiredTick = tick
			if index == self.sv.saved.entryJunction then
				sm.event.sendToGame( "sv_e_zoneJunctionLog", { index = index, ignored = "(the way you came)" } )
			else
				sm.event.sendToGame( "sv_e_zoneJunctionLog", { index = index } )
				sm.event.sendToGame( "sv_e_zoneJunction", { player = object:getPlayer(), index = index, junction = self.data.junctions[index] } )
			end
			return
		end
	end
end

local function CellKeyOf( x, y )
	return x .. "," .. y
end

function ZoneWorld.server_onCellLoaded( self, x, y )
	BaseWorld.server_onCellLoaded( self, x, y )
	self.sv.loadedCells[CellKeyOf( x, y )] = true
	self:sv_measureJunction( x, y )
	self:sv_checkLandmark( x, y )
	-- (a pooled world: a cell's first load this trip)
	self:sv_checkTrip()
	if self.sv.saved.tripId then
		self:sv_tripCell( x, y )
	end
end

-- A junction's cell loaded: measure the ground for its launch pad
function ZoneWorld.sv_measureJunction( self, x, y )
	for index, junction in ipairs( ( self.data and self.data.junctions ) or {} ) do
		if junction.x == x and junction.y == y and not self.sv.junctionGround[index] then
			local position = JunctionPadPosition( junction )
			self.sv.junctionGround[index] = FloorAt( position )
			if self.sv.junctionGround[index] then
				self:sv_sendJunctionMarkers()
			end
		end
	end
end

function ZoneWorld.server_onCellUnloaded( self, x, y )
	BaseWorld.server_onCellUnloaded( self, x, y )
	self.sv.loadedCells[CellKeyOf( x, y )] = nil
end

function ZoneWorld.server_onFixedUpdate( self )
	BaseWorld.server_onFixedUpdate( self )
	-- (a pooled world: a new trip here wakes it up)
	if sm.game.getCurrentTick() % 10 == 5 then
		self:sv_checkTrip()
	end
	-- A zone you've left stays loaded (worlds can't be unloaded): it does nothing
	if self.sv.saved.retired then
		return
	end
	ZoneTornadoes_SvUpdate( self, ZONE_TORNADOES and g_currentZone == self.world )
	if sm.game.getCurrentTick() % 10 == 0 then
		self:sv_updateAnchors()
	end
	if sm.game.getCurrentTick() % 40 == 9 then
		self:sv_trackSpots()
	end
	if sm.game.getCurrentTick() % 20 == 3 then
		self:sv_clearArrival()
	end
	if sm.game.getCurrentTick() % 80 == 41 then
		self:sv_keepHideoutFarmer()
	end
	if sm.game.getCurrentTick() % 40 == 29 then
		self:sv_openJunctionGates()
	end
	self:sv_stepRecover()
end

-- The Farmers' Hideout has a farmer to talk to (HideoutFarmer.lua), standing
-- where it was picked in game with /where (x 6.2, y 28.7 in the hideout's
-- zone). He's put there whenever someone's here and he isn't, and the
-- hideout's marker points at him.
-- Finding him: every farmer adds himself to g_hideoutFarmers when his unit
-- starts (on a reload too); listing the world's units didn't find him.
local HIDEOUT_FARMER = sm.uuid.new( "e7342b5f-ed16-4adc-9f04-69b90aceff2b" )
local HIDEOUT_FARMER_SPOT = { x = 6.2, y = 28.7 }

-- Every farmer in this world (the registry, then the world's units by
-- character type as text, in case)
local function HideoutFarmersIn( world )
	local found, seen = {}, {}
	local function add( unit )
		local character = unit and sm.exists( unit ) and unit:getCharacter()
		if character and sm.exists( character ) and character:getWorld() == world and not seen[unit.id] then
			seen[unit.id] = true
			found[#found + 1] = unit
		end
	end
	for _, unit in pairs( g_hideoutFarmers or {} ) do add( unit ) end
	for _, unit in ipairs( sm.unit.getAllUnits( world ) ) do
		local character = sm.exists( unit ) and unit:getCharacter()
		if character and sm.exists( character ) and tostring( character:getCharacterType() ) == tostring( HIDEOUT_FARMER ) then
			add( unit )
		end
	end
	return found
end

function ZoneWorld.sv_keepHideoutFarmer( self )
	if not ( self.data and self.data.landmark == "hideout" ) or not self:sv_anyPlayerHere() then
		return
	end
	-- Just placed one: give him a moment to show up before looking again
	if self.sv.farmerPlacedTick and sm.game.getCurrentTick() - self.sv.farmerPlacedTick < 40 * 10 then
		return
	end
	-- Is he here? One only, at his spot: extras, and ones left elsewhere by
	-- older versions of this, go
	local home = sm.vec3.new( HIDEOUT_FARMER_SPOT.x, HIDEOUT_FARMER_SPOT.y, 0 )
	local farmer
	for _, unit in ipairs( HideoutFarmersIn( self.world ) ) do
		local at = unit:getCharacter().worldPosition
		local away = sm.vec3.new( at.x - home.x, at.y - home.y, 0 ):length()
		if farmer or away > 6 then
			unit:destroy()
		else
			farmer = unit
		end
	end
	if farmer then
		local character = farmer:getCharacter()
		-- (holding out the key to the Mid Zone, once he's thanked you: Story.lua)
		local give = g_hideoutKeyReady == true
		if self.sv.farmerGive ~= give or self.sv.farmerGiveTo ~= character then
			self.sv.farmerGive, self.sv.farmerGiveTo = give, character
			sm.event.sendToCharacter( character, "sv_e_setGive", { give = give } )
		end
		-- (the hideout's marker points at him)
		local at = character.worldPosition
		if not self.sv.landmarkGround or ( self.sv.landmarkGround - at ):length() > 2 then
			self.sv.landmarkGround = at
			self.sv.landmarkMeasured = true
			self.network:sendToClients( "cl_n_setLandmark", { position = at, landmark = self.data.landmark } )
		end
		return
	end
	-- (placed once already, kept in the world's save: if he can't be found,
	-- better none extra than a crowd of them)
	if self.sv.saved.farmerPlaced == HIDEOUT_FARMER_SPOT.x .. "," .. HIDEOUT_FARMER_SPOT.y then
		if not self.sv.farmerMissingLogged then
			self.sv.farmerMissingLogged = true
			sm.log.warning( "[PacificScrap] The hideout farmer was placed but can't be found; not placing another" )
		end
		return
	end
	local floor = FloorAt( home )
	if not floor then
		return -- (his cell isn't loaded yet)
	end
	sm.unit.createUnit( HIDEOUT_FARMER, floor + sm.vec3.new( 0, 0, 0.1 ), math.pi * 0.5 )
	self.sv.farmerPlacedTick = sm.game.getCurrentTick()
	self.sv.saved.farmerPlaced = HIDEOUT_FARMER_SPOT.x .. "," .. HIDEOUT_FARMER_SPOT.y
	self.storage:save( self.sv.saved )
	sm.log.info( "[PacificScrap] Hideout farmer placed at", floor )
end

-- Is anyone in this zone yet? (The cells where you land load before you arrive)
-- In a zone the junction gates are always open: set straight to their open
-- end (no animation) as their cells load
function ZoneWorld.sv_openJunctionGates( self )
	for _, junction in ipairs( ( self.data and self.data.junctions ) or {} ) do
		-- (only loaded cells: asking about an unloaded one logs errors)
		local gates = self.sv.loadedCells[CellKeyOf( junction.x, junction.y )] and JunctionGates( self.world, junction.x, junction.y ) or {}
		for _, gate in ipairs( gates ) do
			if not GateMoving( gate ) and not GateOpen( gate ) then
				sm.event.sendToHarvestable( gate, "sv_e_resetTrack", { toBack = true } )
			end
		end
	end
end

function ZoneWorld.sv_anyPlayerHere( self )
	for _, player in ipairs( sm.player.getAllPlayers() ) do
		local character = player.character
		if character and sm.exists( character ) and character:getWorld() == self.world then
			return true
		end
	end
	return false
end

-- Just arrived: for ZONE_ARRIVAL_CLEAR_SECONDS, robots near you are cleared
-- away, so you're never attacked the moment you land (survival's own robots in
-- ruin tiles spawn with the cells, wherever you are)
function ZoneWorld.sv_clearArrival( self )
	self.sv.arrivals = self.sv.arrivals or {}
	local now = sm.game.getCurrentTick()
	local near = {}
	for _, player in ipairs( sm.player.getAllPlayers() ) do
		local character = player.character
		local key = tostring( player.id )
		if character and sm.exists( character ) and character:getWorld() == self.world then
			self.sv.arrivals[key] = self.sv.arrivals[key] or now
			if now - self.sv.arrivals[key] < ZONE_ARRIVAL_CLEAR_SECONDS * 40 then
				near[#near + 1] = character.worldPosition
			end
		else
			self.sv.arrivals[key] = nil -- (left: the next arrival counts again)
		end
	end
	if #near == 0 then
		return
	end
	local cleared = 0
	for _, unit in ipairs( sm.unit.getAllUnits( self.world ) ) do
		local character = sm.exists( unit ) and unit:getCharacter()
		if character and sm.exists( character ) and character:getWorld() == self.world
			and isAnyOf( character:getCharacterType(), g_robots or {} ) then
			for _, pos in ipairs( near ) do
				if ( character.worldPosition - pos ):length() < ZONE_ARRIVAL_CLEAR_RADIUS then
					sm.unit.forceDestroy( unit )
					cleared = cleared + 1
					break
				end
			end
		end
	end
	if cleared > 0 then
		sm.log.info( "[PacificScrap] Arrival: cleared", cleared, "robots near the players" )
	end
end

-- Where each player last was, and the vehicle they last sat in (so a car can
-- be towed home if the run ends badly: Game.sv_recoverVehicles)
function ZoneWorld.sv_trackSpots( self )
	local spots = self.sv.saved.spots or {}
	local changed = false
	for _, player in ipairs( sm.player.getAllPlayers() ) do
		local character = player.character
		if character and sm.exists( character ) and character:getWorld() == self.world then
			local key = tostring( player.id )
			local spot = spots[key] or {}
			local here = character.worldPosition
			if not spot.player or ( spot.player - here ):length() > 5 then
				spot.player = here
				changed = true
			end
			local ok, seat = pcall( function() return character:getLockingInteractable() end )
			if ok and seat and sm.exists( seat ) and seat.shape.body:isDynamic() then
				local car = seat.shape.body.worldPosition
				if not spot.vehicle or ( spot.vehicle - car ):length() > 5 then
					spot.vehicle = car
					changed = true
				end
			end
			spots[key] = spot
		end
	end
	-- Cars with an ARC Device on them, wherever their driver is (towed home
	-- after a failed run even if nobody was near: a friend's seat isn't always
	-- known to the server). Keyed "arc<id>", so they're nobody's own spots.
	for id, device in pairs( g_arcDevices or {} ) do
		if device.onVehicle and device.position and device.world == self.world and sm.game.getCurrentTick() - device.tick < 80 then
			local key = "arc" .. id
			local spot = spots[key] or {}
			if not spot.vehicle or ( spot.vehicle - device.position ):length() > 5 then
				spot.vehicle = device.position
				spots[key] = spot
				changed = true
			end
		end
	end
	if changed then
		self.sv.saved.spots = spots
		self.storage:save( self.sv.saved )
	end
end

-- Loads the cells round those spots, waits for them to settle, then tells the
-- game every creation there (cars, the bag a player's things dropped in)
-- params.player (a player's id as text): only that player's spots, while the
-- run goes on without them (they died or went home: Game.sv_towForLostPlayers),
-- and nothing near a player still here (it's theirs, or they're using it)
local RECOVER_RADIUS = 30
local RECOVER_KEEP_NEAR = 20 -- (metres from a player still in the zone)
function ZoneWorld.sv_e_findRecoverables( self, params )
	local only = params and params.player
	local spots = {}
	for key, spot in pairs( self.sv.saved.spots or {} ) do
		if not only or key == only then
			if spot.vehicle then spots[#spots + 1] = spot.vehicle end
			if spot.player then spots[#spots + 1] = spot.player end
		end
	end
	local handles, loaded = {}, {}
	for _, p in ipairs( spots ) do
		local cx, cy = math.floor( p.x / 64 ), math.floor( p.y / 64 )
		for y = cy - 1, cy + 1 do
			for x = cx - 1, cx + 1 do
				if not loaded[x .. "," .. y] then
					loaded[x .. "," .. y] = true
					handles[#handles + 1] = self.world:loadCellWithHandle( x, y )
				end
			end
		end
	end
	self.sv.recover = { spots = spots, handles = handles, findTick = sm.game.getCurrentTick() + 80, releaseTick = sm.game.getCurrentTick() + 40 * 12, partial = only ~= nil, player = only }
end

function ZoneWorld.sv_stepRecover( self )
	local recover = self.sv.recover
	if not recover then return end
	local tick = sm.game.getCurrentTick()
	if recover.findTick and tick >= recover.findTick then
		recover.findTick = nil
		local items, done = {}, {}
		-- (towing one player's things mid-run: where the others still here are)
		local others = {}
		if recover.partial then
			for _, player in ipairs( sm.player.getAllPlayers() ) do
				local character = player.character
				if character and sm.exists( character ) and character:getWorld() == self.world then others[#others + 1] = character.worldPosition end
			end
		end
		-- (a car held up on a lift isn't dynamic: the lift is taken away so it
		-- drops, and the search runs again a moment later)
		local lifted = false
		for _, body in ipairs( sm.body.getAllBodies( self.world ) ) do
			if sm.exists( body ) and body:isOnLift() and not recover.liftsDropped then
				for _, p in ipairs( recover.spots ) do
					if ( body.worldPosition - p ):length() < RECOVER_RADIUS then lifted = true break end
				end
			end
		end
		if lifted then
			recover.liftsDropped = true
			recover.findTick = tick + 40
			recover.releaseTick = math.max( recover.releaseTick, tick + 40 * 12 )
			sm.event.sendToGame( "sv_e_dropLifts", { player = recover.player } )
			return
		end
		for _, body in ipairs( sm.body.getAllBodies( self.world ) ) do
			if sm.exists( body ) and body:isDynamic() and not done[body.id] then
				local near = false
				for _, p in ipairs( recover.spots ) do
					if ( body.worldPosition - p ):length() < RECOVER_RADIUS then near = true break end
				end
				for _, p in ipairs( others ) do
					if ( body.worldPosition - p ):length() < RECOVER_KEEP_NEAR then near = false break end
				end
				if near then
					local low, high
					local shapes = 0
					for _, b in ipairs( body:getCreationBodies() ) do
						done[b.id] = true
						shapes = shapes + #b:getShapes()
						local ok, a, c = pcall( function() return b:getWorldAabb() end )
						if ok and a then
							low = low and sm.vec3.new( math.min( low.x, a.x ), math.min( low.y, a.y ), math.min( low.z, a.z ) ) or a
							high = high and sm.vec3.new( math.max( high.x, c.x ), math.max( high.y, c.y ), math.max( high.z, c.z ) ) or c
						end
					end
					if low then
						items[#items + 1] = { center = ( low + high ) * 0.5, half = ( high - low ) * 0.5 + sm.vec3.new( 1, 1, 1 ), bottom = low.z, shapes = shapes }
					end
				end
			end
		end
		sm.event.sendToGame( "sv_e_recoverFound", { items = items, partial = recover.partial } )
	end
	if tick >= recover.releaseTick then
		for _, handle in ipairs( recover.handles ) do
			pcall( function() handle:release() end )
		end
		self.sv.recover = nil
	end
end


-- Retiring the zone -----------------------------------------------------------------
-- Scrap Mechanic can't unload a world, and deleting one leaves its contents in
-- the save (which then hangs on load). So a zone left for good is retired: it
-- stops everything it does, here and on every client, and as nothing loads it
-- again it's gone from memory after the next reload of the save.

function ZoneWorld.sv_e_retire( self )
	-- (a pooled world can be the next trip's zone straight away: the garage
	-- retires the last zone just before picking the next)
	if g_currentZone and g_currentZone.id == self.world.id then
		return
	end
	if not self.sv.saved.retired then
		self.sv.saved.retired = true
		self.storage:save( self.sv.saved )
	end
	ZoneTornadoes_SvClear( self )
	self:sv_e_clearGateway()
	for _, trigger in ipairs( self.sv.junctionTriggers or {} ) do
		if sm.exists( trigger ) then sm.areaTrigger.destroy( trigger ) end
	end
	self.sv.junctionTriggers = {}
	self.network:sendToClients( "cl_n_retire" )
end

-- An anchor counts as collected once its part is gone and either someone
-- nearby is carrying an anchor or its cell is loaded (picked up and taken away). If its
-- cell is merely unloaded, it's just out of reach for now.
function ZoneWorld.sv_updateAnchors( self )
	local changed = false
	local markers = {}
	-- Where the players carrying an anchor are
	local carriers = {}
	for _, player in ipairs( sm.player.getAllPlayers() ) do
		local character = player.character
		if character and sm.exists( character ) and character:getWorld() == self.world
			and CarryingAnchor( player ) then
			carriers[#carriers + 1] = character.worldPosition
		end
	end
	local function pickedUpNearby( pos )
		for _, c in ipairs( carriers ) do
			if ( c - pos ):length() < 30 then return true end
		end
		return false
	end
	for _, anchor in ipairs( self.sv.saved.anchors ) do
		if anchor.shape and not anchor.collected then
			if sm.exists( anchor.shape ) then
				anchor.pos = anchor.shape.worldPosition
			elseif pickedUpNearby( anchor.pos ) and not anchor.grabbed then
				-- Taken off its pedestal: a burst of energy, once
				anchor.grabbed = true
				anchor.collected = true
				changed = true
				sm.effect.playEffect( ANCHOR_GRAB_EFFECT, anchor.pos )
			elseif pickedUpNearby( anchor.pos ) or self.sv.loadedCells[CellKeyOf( math.floor( anchor.pos.x / 64 ), math.floor( anchor.pos.y / 64 ) )] then
				anchor.collected = true
				changed = true
			end
		end
		if not anchor.collected then
			markers[#markers + 1] = { pos = anchor.pos, kind = self:sv_anchorKind( anchor ) }
		end
	end
	-- Only the current zone counts (retired zones keep their own anchor list)
	if g_currentZone == self.world then
		g_zoneAnchorsLeft = #markers
		g_zoneAnchorsTotal = #self.sv.saved.anchors
	end
	if changed then
		self.storage:save( self.sv.saved )
	end
	-- Resend when an anchor is collected or moves (e.g. its pedestal spawns)
	local signature = {}
	for _, m in ipairs( markers ) do
		signature[#signature + 1] = string.format( "%d,%d,%d", math.floor( m.pos.x ), math.floor( m.pos.y ), math.floor( m.pos.z ) )
	end
	signature = table.concat( signature, ";" )
	if signature ~= self.sv.sentAnchorMarkers then
		self.sv.sentAnchorMarkers = signature
		self.network:sendToClients( "cl_n_setAnchorMarkers", markers )
	end
end

function ZoneWorld.server_onDestroy( self )
	-- When the whole zone world is deleted the ambience object is already gone
	if self.sv.ambienceManager and sm.exists( self.sv.ambienceManager ) then
		self.sv.ambienceManager:destroy()
	end
	self.sv.ambienceManager = nil
	BaseWorld.server_onDestroy( self )
end

-- Energy anchors: a pedestal with an anchor on top in each anchor cell, spawned
-- the first time the cell loads
local STANDING = sm.quat.angleAxis( math.rad( 90 ), sm.vec3.new( 1, 0, 0 ) ) -- both parts are modelled Y-up

-- createPart takes the part's corner, not its center
local function CreatePartAt( uuid, center, rotation, dynamic )
	local corner = center - rotation * ( sm.item.getShapeSize( uuid ) * 0.125 )
	return sm.shape.createPart( uuid, corner, rotation, dynamic, true )
end

function ZoneWorld.server_onCellCreated( self, x, y )
	BaseWorld.server_onCellCreated( self, x, y )
	self:sv_checkLandmark( x, y )
	if self.packingStationManager then
		self.packingStationManager:sv_onCellLoaded( x, y )
	end
	-- A cell's first load only fires this, not server_onCellLoaded
	self.sv.loadedCells[x .. "," .. y] = true
	self:sv_measureJunction( x, y )
	self:sv_checkTrip()
	self:sv_tripCell( x, y )
end

-- Supply pods (SupplyPod.lua) --------------------------------------------------

local SUPPLY_POD_UUID = sm.uuid.new( "7de73157-8f20-4fe6-9514-299fc166aaf7" )

-- falling: dropped from high up with a push downwards, like a missile; else
-- it's put down standing on the ground (static)
function ZoneWorld.sv_createPod( self, position, falling )
	local rotation = sm.quat.angleAxis( math.rad( math.random( 0, 359 ) ), sm.vec3.new( 0, 0, 1 ) ) * sm.quat.angleAxis( math.rad( 90 ), sm.vec3.new( 1, 0, 0 ) ) -- (modelled Y-up)
	if not falling then
		-- (createPart wants its centre: half its height above the ground)
		position = position + sm.vec3.new( 0, 0, sm.item.getShapeSize( SUPPLY_POD_UUID ).y * 0.125 + 0.02 )
	end
	local shape = CreatePartAt( SUPPLY_POD_UUID, position, rotation, falling )
	if shape and falling then
		sm.physics.applyImpulse( shape, sm.vec3.new( 0, 0, -20 ) * shape.body.mass, true )
	end
	return shape
end

-- A falling pod landed (SupplyPod.lua): it's put down upright where it hit
function ZoneWorld.sv_e_placePod( self, params )
	self:sv_createPod( sm.vec3.new( params.x, params.y, params.z ), false )
end

-- The game drops a pod somewhere around a player while the zone collapses
function ZoneWorld.sv_e_dropPod( self, params )
	if self.sv.saved.retired then return end
	self:sv_createPod( sm.vec3.new( params.x, params.y, ( params.z or 0 ) + POD_DROP_HEIGHT ), true )
	sm.log.info( "[PacificScrap] Supply pod coming down at", params.x, params.y )
end

-- The zone tier's robots (ZONE_TIERS enemies in layouts.lua), placed as each
-- cell first loads, never right next to a player; none in landmarks
function ZoneWorld.sv_spawnEnemies( self, x, y )
	local trip = self:sv_trip()
	local enemies = ZoneTierOf( trip.zone or trip.depth ).enemies
	if self.sv.saved.retired or not enemies or ( self.data and self.data.landmark ) or math.random() > enemies.chance then
		return
	end
	local total = 0
	for _, unit in ipairs( enemies.units ) do total = total + unit[2] end
	for _ = 1, math.random( enemies.count[1], enemies.count[2] ) do
		local px, py = ( x + 0.15 + math.random() * 0.7 ) * 64, ( y + 0.15 + math.random() * 0.7 ) * 64
		local ground, kind = GroundBelow( sm.vec3.new( px, py, 512 ), 1024, LANDING_MASK )
		local tooClose = false
		for _, player in ipairs( sm.player.getAllPlayers() ) do
			local character = player.character
			if character and sm.exists( character ) and character:getWorld() == self.world and ground
				and ( character.worldPosition - ground ):length() < ZONE_ENEMY_SAFE_DISTANCE then
				tooClose = true
			end
		end
		if ground and kind == "terrainSurface" and not tooClose then
			local r = math.random() * total
			for _, unit in ipairs( enemies.units ) do
				r = r - unit[2]
				if r <= 0 then
					sm.unit.createUnit( sm.uuid.new( unit[1] ), ground + sm.vec3.new( 0, 0, 0.5 ), math.random() * 2 * math.pi )
					break
				end
			end
		end
	end
end

-- Minefield: red totebots (they explode) scattered over each cell as it first
-- loads, but never right next to a player
local RED_TOTEBOT = sm.uuid.new( "9360d346-3ff2-4925-a068-660cf5dd5267" )
function ZoneWorld.sv_spawnMines( self, x, y )
	if self.sv.saved.retired or not HasCondition( self:sv_trip().conditions, "minefield" ) or math.random() > CONDITION_MINE_CHANCE then
		return
	end
	local count = math.random( CONDITION_MINES_PER_CELL[1], CONDITION_MINES_PER_CELL[2] )
	for _ = 1, count do
		local px, py = ( x + 0.1 + math.random() * 0.8 ) * 64, ( y + 0.1 + math.random() * 0.8 ) * 64
		local ground, kind = GroundBelow( sm.vec3.new( px, py, 512 ), 1024, LANDING_MASK )
		local tooClose = false
		for _, player in ipairs( sm.player.getAllPlayers() ) do
			local character = player.character
			if character and sm.exists( character ) and character:getWorld() == self.world and ground
				and ( character.worldPosition - ground ):length() < CONDITION_MINE_SAFE_DISTANCE then
				tooClose = true
			end
		end
		if ground and kind == "terrainSurface" and not tooClose then
			sm.unit.createUnit( RED_TOTEBOT, ground + sm.vec3.new( 0, 0, 0.5 ), math.random() * 2 * math.pi )
		end
	end
end

-- An anchor entry's kind: stable / unstable / corrupted (older worlds'
-- entries have none: it's in the world's data)
function ZoneWorld.sv_anchorKind( self, anchor )
	local kindName = anchor.kind
	for _, cell in ipairs( not kindName and self.data and self.data.anchors or {} ) do
		if cell.x == anchor.x and cell.y == anchor.y then kindName = cell.kind end
	end
	return kindName or "stable"
end

-- anchor: its entry in saved.anchors
function ZoneWorld.sv_spawnAnchor( self, x, y, anchor )
	local anchorKind = ENERGY_ANCHOR_BY_NAME[self:sv_anchorKind( anchor )] or ENERGY_ANCHOR_BY_NAME.stable
	local anchorUuid = sm.uuid.new( anchorKind.uuid )
	for _ = 1, 16 do
		local px = ( x + 0.2 + math.random() * 0.6 ) * 64
		local py = ( y + 0.2 + math.random() * 0.6 ) * 64
		local ground, kind = GroundBelow( sm.vec3.new( px, py, 512 ), 1024, LANDING_MASK )
		if ground and kind == "terrainSurface" then
			local pedestalHeight = sm.item.getShapeSize( PEDESTAL_UUID ).y * 0.25
			local anchorHeight = sm.item.getShapeSize( ANCHOR_UUID ).y * 0.25
			anchor.pedestal = CreatePartAt( PEDESTAL_UUID, ground + sm.vec3.new( 0, 0, pedestalHeight * 0.5 ), STANDING, false )
			local anchorShape = CreatePartAt( anchorUuid, ground + sm.vec3.new( 0, 0, pedestalHeight + anchorHeight * 0.5 + 0.05 ), STANDING, true )
			anchor.shape = anchorShape
			anchor.pos = anchorShape.worldPosition
			self.storage:save( self.sv.saved )
			self:sv_updateAnchors()
			sm.log.info( "[PacificScrap] Anchor pedestal (" .. anchorKind.name .. ") at", ground )
			return
		end
	end
	sm.log.warning( "[PacificScrap] No room for an anchor pedestal in cell", x, y )
end

function ZoneWorld.sv_e_stopBodiesNear( self, params )
	StopBodiesNear( self.world, params.position, params.radius )
end

-- Finds open ground (not a tree or rock) inside a loaded cell
function ZoneWorld.sv_e_findLanding( self, params )
	local found
	if params.onRoad then
		-- Straight road tiles run through the middle of the cell
		local center = sm.vec3.new( ( params.cellX + 0.5 ) * 64, ( params.cellY + 0.5 ) * 64, 512 )
		found = GroundBelow( center, 1024, GROUND_MASK )
	end
	for _ = 1, found and 0 or LANDING_ATTEMPTS do
		local x = ( params.cellX + 0.15 + math.random() * 0.7 ) * 64
		local y = ( params.cellY + 0.15 + math.random() * 0.7 ) * 64
		local position, kind = GroundBelow( sm.vec3.new( x, y, 512 ), 1024, LANDING_MASK )
		if position and kind == "terrainSurface" then
			found = position
			break
		end
	end

	if not found then
		local x = ( params.cellX + 0.5 ) * 64
		local y = ( params.cellY + 0.5 ) * 64
		found = GroundBelow( sm.vec3.new( x, y, 512 ), 1024, LANDING_MASK ) or sm.vec3.new( x, y, 30 )
	end

	sm.event.sendToGame( "sv_e_onLandingFound", { position = found } )
end

function ZoneWorld.sv_e_spawnGateway( self, params )
	self:sv_e_clearGateway()

	-- The game loads the gateway's cell before sending this, so the ground is there
	local ground = GroundBelow( sm.vec3.new( params.x, params.y, 512 ), 1024, sm.physics.filter.terrainSurface )
		or sm.vec3.new( params.x, params.y, 10 )
	self.sv.gateway = { x = params.x, y = params.y, z = ground.z }
	self.sv.gatewayFiredTick = nil

	self.sv.gatewayTrigger = sm.areaTrigger.createBox( GATEWAY_TRIGGER_HALF_SIZE, sm.vec3.new( params.x, params.y, 0 ), sm.quat.identity(), sm.areaTrigger.filter.character )
	self.sv.gatewayTrigger:bindOnEnter( "trigger_onGateway" )
	self.sv.gatewayTrigger:bindOnStay( "trigger_onGateway" )

	self.network:sendToClients( "cl_n_setGateway", { x = params.x, y = params.y, z = ground.z, fresh = true } )
	sm.event.sendToGame( "sv_e_onGatewaySpawned", { ground = ground } )
end

function ZoneWorld.sv_e_clearGateway( self )
	if self.sv.gatewayTrigger then
		sm.areaTrigger.destroy( self.sv.gatewayTrigger )
		self.sv.gatewayTrigger = nil
	end
	self.sv.gateway = nil
	self.network:sendToClients( "cl_n_setGateway", {} )
end

-- A player in the gateway: told to the game every half second while someone's
-- in it (the game ignores repeats once the return has started), so a moment
-- when the game wasn't ready can't leave the gateway dead
function ZoneWorld.trigger_onGateway( self, trigger, results )
	local tick = sm.game.getCurrentTick()
	if self.sv.gatewayFiredTick and tick - self.sv.gatewayFiredTick < 20 then
		return
	end
	for _, object in ipairs( results ) do
		if sm.exists( object ) and type( object ) == "Character" and object:isPlayer() then
			self.sv.gatewayFiredTick = tick
			-- The gateway grabs the car: stop it so it stays inside the return portal
			StopBodiesNear( self.world, object.worldPosition, 15 )
			sm.event.sendToGame( "sv_e_onGatewayReached", { position = object.worldPosition } )
			return
		end
	end
end

function ZoneWorld.sv_n_requestGateway( self, _, player )
	if self.sv.saved.retired then
		self.network:sendToClient( player, "cl_n_retire" )
		return
	end
	self.network:sendToClient( player, "cl_n_setGateway", self.sv.gateway or {} )
	self.network:sendToClient( player, "cl_n_setStorm", self.sv.storm or {} )
	self.network:sendToClient( player, "cl_n_setCollapseTick", { tick = self.sv.collapseTick } )
	local markers = {}
	for _, anchor in ipairs( self.sv.saved.anchors ) do
		if not anchor.collected then markers[#markers + 1] = { pos = anchor.pos, kind = self:sv_anchorKind( anchor ) } end
	end
	self.network:sendToClient( player, "cl_n_setAnchorMarkers", markers )
	ZoneTornadoes_SvSync( self, player )
	self:sv_sendJunctionMarkers( player )
	local trip = self:sv_trip()
	self.network:sendToClient( player, "cl_n_setConditions", trip.conditions or {} )
	self.network:sendToClient( player, "cl_n_setDepth", { depth = trip.zone or trip.depth or 1 } )
	if self.sv.landmarkGround then
		self.network:sendToClient( player, "cl_n_setLandmark", { position = self.sv.landmarkGround, landmark = self.data.landmark } )
	end
end

-- A landmark world: a beacon marker on the landmark (like the junctions and
-- anchors), only while you're here
local LANDMARK_MARKER = "pacificscrap_landmark"
function ZoneWorld.sv_checkLandmark( self, x, y )
	local landmark = self.data and self.data.landmark and LandmarkByName( self.data.landmark )
	if not landmark or self.sv.landmarkMeasured then return end
	-- (the landmark sits round the middle of the map). Marked from the start
	-- (x, y nil: the zone's creation), so it shows from anywhere; the height is
	-- measured once its cell has loaded
	if x == 0 and y == 0 then
		local ground = GroundBelow( sm.vec3.new( 1, 1, 512 ), 1024, GROUND_MASK )
		if ground then
			self.sv.landmarkGround = ground
			self.sv.landmarkMeasured = true
		end
	end
	self.sv.landmarkGround = self.sv.landmarkGround or sm.vec3.new( 1, 1, 15 )
	self.network:sendToClients( "cl_n_setLandmark", { position = self.sv.landmarkGround, landmark = landmark.name } )
end

function ZoneWorld.cl_n_setLandmark( self, data )
	self.cl.landmark = data and data.position and data or nil
	self:cl_refreshLandmarkMarker()
end

function ZoneWorld.cl_refreshLandmarkMarker( self )
	if not g_worldMarkerManager then return end
	local here = self:cl_localPlayerHere() and not self.cl.retired
	self.cl.landmarkShown = here
	local landmark = here and self.cl.landmark and LandmarkByName( self.cl.landmark.landmark )
	if landmark then
		local colour = sm.color.new( MARKER_GREY )
		WorldMarkerManager.Cl_CreateOrUpdateMarker( LANDMARK_MARKER, {
			effect = "Beacon",
			position = self.cl.landmark.position + sm.vec3.new( 0, 0, 10.0 ),
			world = self.world,
			textureIndex = landmark.beaconIcon or 5,
			iconColor = colour,
			compassItemIcon = { resource = "BeaconCompassIconMap", group = "BeaconCompassIconMap", name = tostring( landmark.beaconIcon or 5 ) },
			compassColor = colour,
			activate = true,
		} )
	else
		WorldMarkerManager.Cl_DestroyMarker( LANDMARK_MARKER )
	end
end

function ZoneWorld.cl_n_setDepth( self, data )
	self.cl.depth = data.depth
end

-- The tier music's fight stage while the zone collapses (Growlab: survival's
-- ambience manager drives it from its combat timer; others: we set it)
function ZoneWorld.cl_updateStormMusic( self )
	local tier = self.cl.depth and ZoneTierOf( self.cl.depth )
	local want = self:cl_localPlayerHere() and self.storm ~= nil and tier ~= nil and tier.stormCombat == true
	if want and tier.stormMusic == 9 then
		if g_ambienceManager then g_ambienceManager:triggerCombatMusic() end
	elseif ( want or false ) ~= ( self.cl.combatOn or false ) then
		sm.audio.setGlobalParameter( "combat", want and 1 or 0 )
	end
	self.cl.combatOn = want and tier.stormMusic ~= 9
end

-- A faint hum when you're right at the gateway
local GATEWAY_HUM_RANGE = GATEWAY_BEAM_RADIUS + 8.0
function ZoneWorld.cl_updateGatewayHum( self )
	local character = sm.localPlayer.getPlayer().character
	local near = false
	if self.gatewayGround and character and sm.exists( character ) and character:getWorld() == self.world then
		local d = character.worldPosition - self.gatewayGround
		near = math.sqrt( d.x * d.x + d.y * d.y ) < ( self.cl.humming and GATEWAY_HUM_RANGE + 6.0 or GATEWAY_HUM_RANGE )
	end
	if near and not self.cl.humming then
		self.cl.humEffect = self.cl.humEffect or sm.effect.createEffect( "PacificScrap - GatewayHum" )
		self.cl.humEffect:setPosition( self.gatewayGround + sm.vec3.new( 0, 0, 2 ) )
		self.cl.humEffect:start()
		self.cl.humming = true
	elseif not near and self.cl.humming then
		if self.cl.humEffect and sm.exists( self.cl.humEffect ) then self.cl.humEffect:stop() end
		self.cl.humming = false
	end
end

function ZoneWorld.cl_n_setJunctionMarkers( self, junctions )
	if self.cl.retired then return end
	self.junctionMarkerPositions = {}
	DestroyEffects( self.junctionPadEffects )
	self.junctionPadEffects = {}
	for _, junction in ipairs( junctions or {} ) do
		self.junctionMarkerPositions[#self.junctionMarkerPositions + 1] = junction.position
		if junction.onGround then
			-- The same yellow launch pad disc as in the garage
			self.junctionPadEffects[#self.junctionPadEffects + 1] = CreateSphereEffect( GATEWAY_SPHERE_EFFECT, junction.position + sm.vec3.new( 0, 0, 0.1 ), sm.vec3.new( PAD_RADIUS, PAD_RADIUS, 0.15 ) )
		end
	end
	self:cl_refreshJunctionMarkers()
end

-- White markers on the junctions, only while you're in this zone
function ZoneWorld.cl_refreshJunctionMarkers( self )
	if not g_worldMarkerManager then
		return
	end
	for i = 1, self.junctionMarkerCount or 0 do
		WorldMarkerManager.Cl_DestroyMarker( JUNCTION_MARKER_PREFIX .. i )
	end
	self.junctionMarkerCount = 0
	self.junctionMarkersShown = self:cl_localPlayerHere()
	if not self.junctionMarkersShown then
		return
	end
	for i, position in ipairs( self.junctionMarkerPositions or {} ) do
		-- Beacon-style marker with the car icon (beacon icon 4), so junctions
		-- stand out from the anchors and the yellow gateway
		local colour = sm.color.new( MARKER_GREY )
		WorldMarkerManager.Cl_CreateOrUpdateMarker( JUNCTION_MARKER_PREFIX .. i, {
			effect = "Beacon",
			position = position + sm.vec3.new( 0, 0, 6.0 ),
			world = self.world,
			textureIndex = JUNCTION_BEACON_ICON,
			iconColor = colour,
			compassItemIcon = { resource = "BeaconCompassIconMap", group = "BeaconCompassIconMap", name = tostring( JUNCTION_BEACON_ICON ) },
			compassColor = colour,
			activate = true,
		} )
		self.junctionMarkerCount = i
	end
end

function ZoneWorld.cl_n_setConditions( self, conditions )
	-- Dense Fog: the zone fog, even if ZONE_FOG is off
	if HasCondition( conditions, "fog" ) and ZONE_RENDER_SETTINGS and AddWorldRenderSettings then
		AddWorldRenderSettings( self.world, ZONE_RENDER_SETTINGS, 2 )
	end
end

function ZoneWorld.cl_n_setTornadoes( self, list )
	if self.cl.retired then return end
	ZoneTornadoes_ClSet( self, list )
end

function ZoneWorld.cl_trigger_onTornado( self, trigger, results )
	ZoneTornadoes_ClTriggerStay( self, trigger, results )
end

-- When the zone starts collapsing on its own (for the HUD countdown)
-- Collapse warning: the alarm for players in the zone
function ZoneWorld.sv_e_alarm( self )
	self.network:sendToClients( "cl_n_alarm" )
end

function ZoneWorld.cl_n_alarm( self )
	if self:cl_localPlayerHere() then
		sm.effect.playEffect( STORM_ALARM_EFFECT, sm.localPlayer.getPlayer().character.worldPosition )
	end
end

function ZoneWorld.sv_e_setCollapseTick( self, params )
	self.sv.collapseTick = params.tick
	self.network:sendToClients( "cl_n_setCollapseTick", params )
end

function ZoneWorld.cl_n_setCollapseTick( self, params )
	self.collapseTick = params.tick
end

-- storm = { center, r0, speed, startTick, minRadius, alarm } or nil to clear
function ZoneWorld.sv_e_setStorm( self, storm )
	if storm and not storm.center then
		storm = nil
	end
	self.sv.storm = storm
	self.network:sendToClients( "cl_n_setStorm", storm or {} )
	if storm then
		storm.alarm = nil -- only sound the alarm when it starts, not for late joiners
	end
end

function ZoneWorld.client_onCreate( self )
	BaseWorld.client_onCreate( self )
	self.world.clientPublicData.type = "ZoneWorld"
	self.world.clientPublicData.isLiftPlacable = true
	-- Survival's music system reads this every frame: the zone tier's music
	-- (see ZONE_TIERS), its storm music while the zone collapses
	self.world.clientPublicData.musicUpdateProcedure = function()
		local tier = self.cl.depth and ZoneTierOf( self.cl.depth )
		if self.storm then
			return ( tier and tier.stormMusic ) or ZONE_STORM_MUSIC or 6
		end
		return ( tier and tier.music ) or ZONE_MUSIC or 3
	end
	self.world.clientPublicData.ambience = "OutdoorAmbience"
	-- Zone fog (survival ignores defaultRenderSetting in outdoor worlds, see survival_patches.lua)
	-- (order 2: stays on top of the storm lighting, so the fog never goes away)
	if ZONE_FOG and ZONE_RENDER_SETTINGS and AddWorldRenderSettings then
		AddWorldRenderSettings( self.world, ZONE_RENDER_SETTINGS, 2 )
	end
	self.world.clientPublicData.ambienceUpdateProcedure = function( ambienceEffect )
		if ambienceEffect and sm.exists( ambienceEffect ) then
			ambienceEffect:setParameter( "amb_day_night", 1.0 - getDayCycleFraction() )
		end
	end

	self.gatewayEffects = {}
	self.stormEffects = {}
	ZoneTornadoes_ClInit( self )
	self.network:sendToServer( "sv_n_requestGateway" )
end

function ZoneWorld.client_onDestroy( self )
	ZoneTornadoes_ClDestroy( self )
	DestroyEffects( self.gatewayEffects )
	DestroyEffects( self.stormEffects )
	self:cl_setStormScreen( false )
	self:cl_setGatewayMarker( nil )
	self.anchorMarkerPositions = {}
	self:cl_refreshAnchorMarkers()
	self.junctionMarkerPositions = {}
	self:cl_refreshJunctionMarkers()
	DestroyEffects( self.junctionPadEffects )
	if self.countdownTimer then
		self.countdownTimer:destroy()
		self.countdownTimer = nil
	end
end

-- Warehouse-destruction style countdown while the zone is collapsing (until the
-- wall has fully closed in)
function ZoneWorld.cl_updateCountdownHud( self )
	if not NotificationManager or not HudManager then
		return
	end
	if not self.countdownTimer then
		self.countdownTimer = NotificationManager.Cl_CreateEventTimer( HudManager.Priority.WarehouseCountdown, "explosion" )
		if not self.countdownTimer then
			return
		end
	end

	local tick = sm.game.getServerTick()
	local timeLeft
	if self:cl_localPlayerHere() and self.storm then
		local fullTick = self.storm.startTick + ( self.storm.r0 - self.storm.minRadius ) / self.storm.speed * 40
		timeLeft = math.max( fullTick - tick, 0 ) / 40
	end

	if timeLeft then
		self.countdownTimer:update( true, timeLeft )
	else
		self.countdownTimer:update( false )
	end
end

function ZoneWorld.cl_n_setStorm( self, data )
	if self.cl.retired then return end
	if not data or not data.center then
		-- The wall sinks back into the ground, then goes
		if self.storm then
			self.wallStorm = self.storm
			self.wallTarget = 0
		else
			DestroyEffects( self.stormEffects )
			self.stormEffects = {}
		end
		self.storm = nil
		self:cl_setStormScreen( false )
		return
	end
	DestroyEffects( self.stormEffects )
	self.stormEffects = {}

	self.storm = data
	-- ...and rises out of the ground
	self.wallStorm = data
	self.wallRise = 0
	self.wallTarget = 1
	self.stormOrange = CreateRing( STORM_PANEL_EFFECT, STORM_PANELS, STORM_PANEL_ROWS )
	for _, effect in ipairs( self.stormOrange ) do self.stormEffects[#self.stormEffects + 1] = effect end
	-- One hologram ring per band
	self.stormBands = {}
	for row, stripe in ipairs( STORM_STRIPE_PATTERN ) do
		if stripe == 1 then
			local ring = CreateRing( STORM_HOLOGRAM_EFFECT, STORM_PANELS )
			ring.row = row
			self.stormBands[#self.stormBands + 1] = ring
			for _, effect in ipairs( ring ) do self.stormEffects[#self.stormEffects + 1] = effect end
		end
	end
	self:cl_updateStormWall()

	-- Red horizon and dark fog, as in a warehouse about to blow, fading in over
	-- the zone fog. Each run has a new zone world, so this never needs undoing.
	if STORM_DARK_SKY and AddWorldRenderSettings then
		AddWorldRenderSettings( self.world, STORM_LIGHTING, 1 )
	end

	if data.alarm and self:cl_localPlayerHere() then
		sm.effect.playEffect( STORM_ALARM_EFFECT, sm.localPlayer.getPlayer().character.worldPosition )
	end
end

function ZoneWorld.cl_localPlayerHere( self )
	local character = sm.localPlayer.getPlayer().character
	return character ~= nil and sm.exists( character ) and character:getWorld() == self.world
end

-- A tall glowing wall at the storm radius
function ZoneWorld.cl_updateStormWall( self, dt )
	local storm = self.wallStorm
	if not storm then
		return
	end
	-- Rising / sinking (smoothed 0..1)
	local step = ( dt or 0 ) / STORM_WALL_RISE_SECONDS
	if ( self.wallRise or 1 ) < ( self.wallTarget or 1 ) then
		self.wallRise = math.min( self.wallRise + step, 1 )
	elseif ( self.wallRise or 1 ) > ( self.wallTarget or 1 ) then
		self.wallRise = math.max( self.wallRise - step, 0 )
		if self.wallRise <= 0 then
			DestroyEffects( self.stormEffects )
			self.stormEffects = {}
			self.wallStorm = nil
			return
		end
	end
	local t = self.wallRise or 1
	local height = STORM_WALL_HEIGHT * t * t * ( 3 - 2 * t )

	local radius = StormRadius( storm, sm.game.getServerTick() )
	-- Closed in all the way: the wall is gone, the storm is everywhere
	if radius < STORM_WALL_GONE_RADIUS then
		DestroyEffects( self.stormEffects )
		self.stormEffects = {}
		self.wallStorm = nil
		return
	end
	UpdateRing( self.stormOrange, storm.center, radius, STORM_WALL_BOTTOM, math.max( height, 0.1 ) )
	-- Hologram bands just inside the orange layer so the two don't flicker against each other
	local rowHeight = height / #STORM_STRIPE_PATTERN
	local top = STORM_WALL_BOTTOM + height
	for _, ring in ipairs( self.stormBands or {} ) do
		UpdateRing( ring, storm.center, radius - 0.5, top - rowHeight * ring.row, math.max( rowHeight, 0.1 ) )
	end
end

-- Red screen while the local player is outside the storm wall. Uses the same
-- area-trigger render settings path as the seeker bot: a trigger covering the
-- whole zone is created while outside and removed when back inside.
function ZoneWorld.cl_setStormScreen( self, enable )
	if enable and not self.stormScreenTrigger and RenderSettingsManager then
		local halfSize = sm.vec3.new( ( ZONE_CELL_MAX - ZONE_CELL_MIN + 1 ) * 32 + 64, ( ZONE_CELL_MAX - ZONE_CELL_MIN + 1 ) * 32 + 64, 500 )
		local center = sm.vec3.new( ( ZONE_CELL_MAX + ZONE_CELL_MIN + 1 ) * 32, ( ZONE_CELL_MAX + ZONE_CELL_MIN + 1 ) * 32, 0 )
		self.stormScreenTrigger = sm.areaTrigger.createBox( halfSize, center, sm.quat.identity(), sm.areaTrigger.filter.character )
		RenderSettingsManager.Cl_AddAreaTriggerRenderSettings( self.stormScreenTrigger, { settings = { settings = { renderSettings = STORM_RENDER_SETTINGS } } } )
	elseif not enable and self.stormScreenTrigger then
		if RenderSettingsManager then
			RenderSettingsManager.Cl_RemoveAreaTriggerRenderSettings( self.stormScreenTrigger )
		end
		if sm.exists( self.stormScreenTrigger ) then
			sm.areaTrigger.destroy( self.stormScreenTrigger )
		end
		self.stormScreenTrigger = nil
	end
end

function ZoneWorld.client_onUpdate( self, dt )
	BaseWorld.client_onUpdate( self, dt )
	if self.cl.retired then
		return
	end
	self:cl_updateStormWall( dt )
	self:cl_updateGatewayBeam()

	local outside = false
	if self.storm and self:cl_localPlayerHere() then
		local radius = StormRadius( self.storm, sm.game.getServerTick() )
		outside = DistanceXY( sm.localPlayer.getPlayer().character.worldPosition, self.storm.center ) > radius - STORM_SCREEN_LEAD
	end
	self:cl_setStormScreen( outside )
end

function ZoneWorld.cl_n_setGateway( self, data )
	if self.cl.retired then return end
	DestroyEffects( self.gatewayEffects )
	self.gatewayEffects = {}
	if data and data.x then
		local ground = sm.vec3.new( data.x, data.y, data.z or 0 )
		-- A thin beam of light up into the sky
		self.gatewayEffects = CreateRing( GATEWAY_PANEL_EFFECT, GATEWAY_PANELS, GATEWAY_PANEL_ROWS )
		self.gatewayGround = ground
		self:cl_updateGatewayBeam()
		self:cl_setGatewayMarker( ground + sm.vec3.new( 0, 0, 12.0 ) )
		if data.fresh and self:cl_localPlayerHere() then
			-- The ground rumbles as the gateway tears open
			sm.effect.playEffect( GATEWAY_SHAKE_EFFECT, sm.localPlayer.getPlayer().character.worldPosition )
		end
	else
		self.gatewayGround = nil
		self:cl_setGatewayMarker( nil )
	end
end

function ZoneWorld.cl_updateGatewayBeam( self )
	if self.gatewayGround then
		UpdateRing( self.gatewayEffects, self.gatewayGround, GATEWAY_BEAM_RADIUS, self.gatewayGround.z - 20.0, GATEWAY_BEAM_HEIGHT + 20.0 )
	end
end

-- Yellow beacon marker + compass icon on the gateway
function ZoneWorld.cl_setGatewayMarker( self, position )
	if not g_worldMarkerManager then
		return
	end
	if position then
		local colour = sm.color.new( GATEWAY_YELLOW )
		WorldMarkerManager.Cl_CreateOrUpdateMarker( GATEWAY_MARKER_NAME, {
			effect = "Beacon",
			position = position,
			world = self.world,
			textureIndex = GATEWAY_BEACON_ICON,
			iconColor = colour,
			compassItemIcon = { resource = "BeaconCompassIconMap", group = "BeaconCompassIconMap", name = tostring( GATEWAY_BEACON_ICON ) },
			compassColor = colour,
			activate = true,
		} )
		self.gatewayMarker = true
	elseif self.gatewayMarker then
		WorldMarkerManager.Cl_DestroyMarker( GATEWAY_MARKER_NAME )
		self.gatewayMarker = nil
	end
end

-- Beacon markers on every anchor still out there, only while you're in the zone.
-- markers: { pos, kind }
function ZoneWorld.cl_n_setAnchorMarkers( self, markers )
	if self.cl.retired then return end
	self.anchorMarkerPositions = markers or {}
	self:cl_refreshAnchorMarkers()
end

-- The grey of the markers, tinted a little towards an anchor kind's colour
-- (ENERGY_ANCHORS colour), so you can tell them apart without it shouting
local ANCHOR_MARKER_TINT = 0.35
local function AnchorMarkerColour( kind )
	local anchor = ENERGY_ANCHOR_BY_NAME[kind or "stable"]
	local hex = anchor and anchor.colour and anchor.colour:gsub( "#", "" )
	if not hex or #hex ~= 6 then return sm.color.new( MARKER_GREY ) end
	local grey = tonumber( MARKER_GREY:sub( 1, 2 ), 16 )
	local parts = {}
	for i = 1, 3 do
		local c = tonumber( hex:sub( i * 2 - 1, i * 2 ), 16 )
		parts[i] = string.format( "%02X", math.floor( grey + ( c - grey ) * ANCHOR_MARKER_TINT + 0.5 ) )
	end
	return sm.color.new( table.concat( parts ) .. "FF" )
end

function ZoneWorld.cl_refreshAnchorMarkers( self )
	if not g_worldMarkerManager then
		return
	end
	for i = 1, self.anchorMarkerCount or 0 do
		WorldMarkerManager.Cl_DestroyMarker( ANCHOR_MARKER_PREFIX .. i )
	end
	self.anchorMarkerCount = 0
	self.anchorMarkersShown = self:cl_localPlayerHere()
	if not self.anchorMarkersShown then
		return
	end
	for i, marker in ipairs( self.anchorMarkerPositions or {} ) do
		local colour = AnchorMarkerColour( marker.kind )
		WorldMarkerManager.Cl_CreateOrUpdateMarker( ANCHOR_MARKER_PREFIX .. i, {
			effect = "Beacon",
			position = marker.pos + sm.vec3.new( 0, 0, 1.0 ),
			world = self.world,
			textureIndex = ANCHOR_BEACON_ICON,
			iconColor = colour,
			compassItemIcon = { resource = "BeaconCompassIconMap", group = "BeaconCompassIconMap", name = tostring( ANCHOR_BEACON_ICON ) },
			compassColor = colour,
			activate = true,
		} )
		self.anchorMarkerCount = i
	end
end

-- A pooled world's new trip: awake again if it was retired, last trip's storm
-- lighting and fog gone, then everything asked for afresh
function ZoneWorld.cl_n_newTrip( self )
	if not self.cl.retired then
		self:cl_n_retire()
	end
	self.cl.retired = false
	if RemoveWorldRenderSettings then
		RemoveWorldRenderSettings( self.world, STORM_LIGHTING )
		if not ZONE_FOG then
			RemoveWorldRenderSettings( self.world, ZONE_RENDER_SETTINGS )
		end
	end
	self.network:sendToServer( "sv_n_requestGateway" )
end

function ZoneWorld.cl_n_retire( self )
	self.cl.retired = true
	DestroyEffects( self.stormEffects )
	DestroyEffects( self.gatewayEffects )
	DestroyEffects( self.junctionPadEffects )
	self.stormEffects, self.gatewayEffects, self.junctionPadEffects = {}, {}, {}
	self.storm, self.wallStorm, self.gatewayGround = nil, nil, nil
	self.junctionMarkerPositions, self.anchorMarkerPositions = {}, {}
	self:cl_refreshJunctionMarkers()
	self:cl_refreshAnchorMarkers()
	self:cl_setGatewayMarker( nil )
	ZoneTornadoes_ClDestroy( self )
	ZoneTornadoes_ClInit( self )
	if self.cl.humEffect and sm.exists( self.cl.humEffect ) then
		self.cl.humEffect:stopImmediate()
		self.cl.humEffect:destroy()
	end
	self.cl.humEffect, self.cl.humming = nil, false
	if self.cl.combatOn then
		sm.audio.setGlobalParameter( "combat", 0 )
		self.cl.combatOn = false
	end
end

function ZoneWorld.client_onFixedUpdate( self )
	BaseWorld.client_onFixedUpdate( self )
	if self.cl.retired then
		return
	end
	PlayDialogBubble( self )
	ClaimWeatherWorld( self.world )
	if ( self.anchorMarkersShown or false ) ~= self:cl_localPlayerHere() then
		self:cl_refreshAnchorMarkers()
	end
	if ( self.junctionMarkersShown or false ) ~= self:cl_localPlayerHere() then
		self:cl_refreshJunctionMarkers()
	end
	if self.cl.landmark and ( self.cl.landmarkShown or false ) ~= self:cl_localPlayerHere() then
		self:cl_refreshLandmarkMarker()
	end
	UpdateEffectVisibility( self.world, self.gatewayEffects )
	UpdateEffectVisibility( self.world, self.stormEffects )
	UpdateEffectVisibility( self.world, self.junctionPadEffects )
	self:cl_updateCountdownHud()
	ZoneTornadoes_ClUpdate( self, self:cl_localPlayerHere() )
	self:cl_updateStormMusic()
	self:cl_updateGatewayHum()
end


-- Zone world classes per tier look ----------------------------------------------
-- A world's ground textures are fixed per class, so a tier with its own ground
-- (ZONE_TIERS worldClass in layouts.lua) has its own class. (Down here, after
-- all of ZoneWorld's functions, so the copy has them all.)
ZoneWorldMid = class( ZoneWorld )
ZoneWorldMid.groundMaterialSet = "$CONTENT_DATA/Terrain/Materials/zone_mid.json" -- pink grass ground (Terrain/make_ground.py)
