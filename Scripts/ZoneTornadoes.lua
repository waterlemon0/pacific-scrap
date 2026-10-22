-- Survival's tornadoes, roaming the zone. Survival's TornadoManager only serves
-- one world (it latches onto the garage) and spawns from desert tile nodes, so the
-- zone runs its own: the same effects, size, speed and lift/push forces (copied
-- from Survival/Scripts/game/managers/TornadoManager.lua), spawned at random.
--
-- The server decides where tornadoes are and syncs { position, direction, tick }
-- now and then; every client moves them along between syncs and, like survival,
-- applies the forces itself through an area trigger.

local TORNADO_RADIUS = 6.0
local TORNADO_HEIGHT = 7.0
local TORNADO_SPEED = 5 -- m/s
local TORNADO_DIMENSIONS = sm.vec3.new( TORNADO_RADIUS, TORNADO_RADIUS, TORNADO_HEIGHT )
local TORNADO_HEIGHT_OFFSET = sm.vec3.new( 0, 0, TORNADO_HEIGHT )
local RAYCAST_OFFSET = sm.vec3.new( 0, 0, 128 )
local RAYCAST_FILTER = sm.physics.filter.terrainSurface
local TURN_INTERVAL_TICKS = 40 * 6 -- picks a new heading this often
local SYNC_INTERVAL_TICKS = 40 * 5

local PLAYER_VERTICAL_IMPULSE = sm.vec3.new( 0, 0, 40 )
local PLAYER_HORIZONTAL_FORCE = 25
local CREATION_VERTICAL_FORCE = sm.vec3.new( 0, 0, 1700 )
local CREATION_HORIZONTAL_FORCE = 500
local CREATION_MAX_IMPULSE_PER_BODY = 4000
local CREATION_MAX_MASS = 10000
local DISTANCE_FROM_CENTER_MODIFIER = 5.0

local function HasAny( t )
	for _ in pairs( t ) do return true end
	return false
end

local function Flat( v )
	return sm.vec3.new( v.x, v.y, 0 )
end

local function RandomHeading()
	local angle = math.random() * 2 * math.pi
	return sm.vec3.new( math.cos( angle ), math.sin( angle ), 0 )
end

local function InsideZone( position, margin )
	local lo, hi = ZONE_CELL_MIN * 64 + margin, ( ZONE_CELL_MAX + 1 ) * 64 - margin
	return position.x > lo and position.x < hi and position.y > lo and position.y < hi
end

-- Where a tornado that was at `position` heading `direction` at `tick` is now
local function PositionAt( data, tick )
	return data.position + data.direction * ( TORNADO_SPEED * ( tick - data.tick ) / 40 )
end


-- Server ------------------------------------------------------------------------

function ZoneTornadoes_SvInit( self )
	self.sv.tornadoes = {}
	self.sv.tornadoCounter = 0
	self.sv.nextTornadoRoll = sm.game.getCurrentTick() + ZONE_TORNADO_ROLL_SECONDS * 40
end

function ZoneTornadoes_SvSync( self, player )
	local tick = sm.game.getCurrentTick()
	local list = {}
	for id, data in pairs( self.sv.tornadoes ) do
		list[#list + 1] = { id = id, position = PositionAt( data, tick ), direction = data.direction, tick = tick }
	end
	if player then
		self.network:sendToClient( player, "cl_n_setTornadoes", list )
	else
		self.network:sendToClients( "cl_n_setTornadoes", list )
	end
end

function ZoneTornadoes_SvUpdate( self, active )
	local tick = sm.game.getCurrentTick()
	local changed = false

	-- Move on: turn now and then, steer back from the map edge, die of old age
	for id, data in pairs( self.sv.tornadoes ) do
		if tick >= data.endTick then
			self.sv.tornadoes[id] = nil
			changed = true
		elseif tick >= data.turnTick then
			local position = PositionAt( data, tick )
			local heading = data.direction:rotate( math.rad( math.random( -50, 50 ) ), sm.vec3.new( 0, 0, 1 ) )
			if not InsideZone( position + heading * 64, 96 ) then
				heading = ( Flat( sm.vec3.new( ( ZONE_CELL_MIN + ZONE_CELL_MAX + 1 ) * 32, ( ZONE_CELL_MIN + ZONE_CELL_MAX + 1 ) * 32, 0 ) ) - Flat( position ) ):safeNormalize( RandomHeading() )
			end
			data.position, data.direction, data.tick = position, heading, tick
			data.turnTick = tick + TURN_INTERVAL_TICKS
			changed = true
		end
	end

	-- Now and then, maybe a new one near a random player
	if active and tick >= self.sv.nextTornadoRoll then
		self.sv.nextTornadoRoll = tick + ZONE_TORNADO_ROLL_SECONDS * 40
		local count = 0
		for _ in pairs( self.sv.tornadoes ) do count = count + 1 end
		local players = {}
		for _, player in ipairs( sm.player.getAllPlayers() ) do
			local character = player.character
			if character and sm.exists( character ) and character:getWorld() == self.world then
				players[#players + 1] = character.worldPosition
			end
		end
		-- (this trip's: a pooled world's change every trip, ZoneWorld.sv_trip)
		local trip = ( self.sv.saved and self.sv.saved.trip ) or self.data or {}
		local depth = trip.depth or 1
		local chance = math.min( ZONE_TORNADO_CHANCE * ( 1 + ( ZONE_TORNADO_DEPTH_BONUS or 0 ) * ( depth - 1 ) ), 0.9 )
		-- Route planner anomaly density
		local anomalies = trip.anomalies
		if anomalies then
			chance = math.min( ZONE_TORNADO_CHANCE * ( 1 + 0.5 * anomalies ), 0.95 )
		end
		local maxCount, perRoll, spawnDistance, lifetime = ZONE_TORNADO_MAX, 1, ZONE_TORNADO_SPAWN_DISTANCE, ZONE_TORNADO_LIFETIME
		local squall = HasCondition( trip.conditions, "tornadoes" )
		if squall then
			-- Hurricane Squall
			chance = CONDITION_TORNADO_CHANCE
			maxCount = CONDITION_TORNADO_MAX
			perRoll = CONDITION_TORNADO_PER_ROLL
			spawnDistance = CONDITION_TORNADO_SPAWN_DISTANCE
			lifetime = CONDITION_TORNADO_LIFETIME
			self.sv.nextTornadoRoll = tick + CONDITION_TORNADO_ROLL_SECONDS * 40
		end
		for _ = 1, perRoll do
			if count < maxCount and #players > 0 and math.random() < chance then
				count = count + 1
				local near = players[math.random( #players )]
				for _ = 1, 8 do
					local distance = spawnDistance[1] + math.random() * ( spawnDistance[2] - spawnDistance[1] )
					local position = Flat( near ) + RandomHeading() * distance
					if InsideZone( position, 96 ) then
						-- Roughly towards the player, so you get to see it
						local heading = ( Flat( near ) - position ):safeNormalize( RandomHeading() ):rotate( math.rad( math.random( -60, 60 ) ), sm.vec3.new( 0, 0, 1 ) )
						self.sv.tornadoCounter = self.sv.tornadoCounter + 1
						self.sv.tornadoes[self.sv.tornadoCounter] = {
							position = position, direction = heading, tick = tick,
							turnTick = tick + TURN_INTERVAL_TICKS, endTick = tick + lifetime * 40
						}
						changed = true
						sm.log.info( "[PacificScrap] Tornado at", position )
						break
					end
				end
			end
		end
	end

	if changed or ( HasAny( self.sv.tornadoes ) and tick % SYNC_INTERVAL_TICKS == 0 ) then
		ZoneTornadoes_SvSync( self )
	end
end

function ZoneTornadoes_SvClear( self )
	if self.sv.tornadoes and HasAny( self.sv.tornadoes ) then
		self.sv.tornadoes = {}
		ZoneTornadoes_SvSync( self )
	end
end


-- Client ------------------------------------------------------------------------

local function DestroyTornado( data )
	for _, effect in ipairs( data.effects ) do
		if sm.exists( effect ) then
			effect:stopImmediate()
			effect:destroy()
		end
	end
	if data.trigger and sm.exists( data.trigger ) then
		sm.areaTrigger.destroy( data.trigger )
	end
end

function ZoneTornadoes_ClInit( self )
	self.cl = self.cl or {}
	self.cl.tornadoes = {}
	self.cl.tornadoTriggers = {}
end

function ZoneTornadoes_ClDestroy( self )
	for _, data in pairs( self.cl.tornadoes or {} ) do
		DestroyTornado( data )
	end
	self.cl.tornadoes = {}
end

function ZoneTornadoes_ClSet( self, list )
	local seen = {}
	for _, entry in ipairs( list or {} ) do
		seen[entry.id] = true
		local data = self.cl.tornadoes[entry.id]
		if not data then
			data = { effects = {
				sm.effect.createEffect( "Environment - Tornado" ),
				sm.effect.createEffect( "Environment - Tornado_grass" ),
			} }
			data.trigger = sm.areaTrigger.createBox( TORNADO_DIMENSIONS, Flat( entry.position ) + TORNADO_HEIGHT_OFFSET, sm.quat.identity(), sm.areaTrigger.filter.dynamicBody + sm.areaTrigger.filter.character, nil, self.world )
			data.trigger:bindOnStay( "cl_trigger_onTornado" )
			self.cl.tornadoTriggers[data.trigger.id] = entry.id
			self.cl.tornadoes[entry.id] = data
		end
		data.position, data.direction, data.tick = entry.position, entry.direction, entry.tick
	end
	for id, data in pairs( self.cl.tornadoes ) do
		if not seen[id] then
			DestroyTornado( data )
			self.cl.tornadoes[id] = nil
		end
	end
end

function ZoneTornadoes_ClUpdate( self, here )
	local tick = sm.game.getServerTick()
	for _, data in pairs( self.cl.tornadoes ) do
		local position = PositionAt( data, tick )
		local hit, result = sm.physics.raycast( position + RAYCAST_OFFSET, position - RAYCAST_OFFSET, nil, RAYCAST_FILTER )
		if hit then
			position = result.pointWorld
		end
		for _, effect in ipairs( data.effects ) do
			if sm.exists( effect ) then
				effect:setPosition( position )
				if here and not effect:isPlaying() then
					effect:start()
				elseif not here and effect:isPlaying() then
					effect:stop()
				end
			end
		end
		if data.trigger and sm.exists( data.trigger ) then
			data.trigger:setWorldPosition( position + TORNADO_HEIGHT_OFFSET )
		end
	end
end

-- Survival's tornado forces: lift, plus a swirl around the middle
local function TornadoImpulse( object, trigger )
	local isBody = type( object ) == "Body"
	local targetPos = Flat( isBody and object:getCenterOfMassPosition() or object:getWorldPosition() )
	local direction = ( targetPos - Flat( trigger:getWorldPosition() ) ):safeNormalize( sm.vec3.new( 1, 0, 0 ) )
	local cross = sm.vec3.cross( direction, sm.vec3.new( 0, 0, 1 ) ):rotateZ( math.rad( -40 ) )
	cross = cross - direction * DISTANCE_FROM_CENTER_MODIFIER

	if type( object ) == "Character" then
		return PLAYER_VERTICAL_IMPULSE + cross * PLAYER_HORIZONTAL_FORCE
	end
	local bodies = object:getCreationBodies()
	local totalMass = 1
	for _, body in ipairs( bodies ) do totalMass = totalMass + body:getMass() end
	if totalMass > CREATION_MAX_MASS then
		return nil
	end
	local impulses = {}
	for _, body in ipairs( bodies ) do
		local share = math.max( body:getMass(), 1 ) / totalMass
		local impulse = ( CREATION_VERTICAL_FORCE + cross * CREATION_HORIZONTAL_FORCE ) * share
		if impulse:length() > CREATION_MAX_IMPULSE_PER_BODY then
			impulse = impulse:normalize() * CREATION_MAX_IMPULSE_PER_BODY
		end
		impulses[body.id] = impulse
	end
	return impulses
end

function ZoneTornadoes_ClTriggerStay( self, trigger, results )
	if not sm.exists( trigger ) then
		return
	end
	local doneCreations = {}
	for _, object in ipairs( results ) do
		if sm.exists( object ) then
			if type( object ) == "Character" then
				-- Only push your own character; other players push theirs
				if object == sm.localPlayer.getPlayer().character then
					local impulse = TornadoImpulse( object, trigger )
					if object:isTumbling() then
						object:applyTumblingImpulse( impulse )
					else
						sm.physics.applyImpulse( object, impulse, true )
					end
				end
			elseif type( object ) == "Body" and sm.isHost then
				-- Creations once (the host's game owns the physics)
				local creationId = object:getCreationId()
				if not doneCreations[creationId] then
					doneCreations[creationId] = true
					local impulses = TornadoImpulse( object, trigger )
					if impulses then
						for _, body in ipairs( object:getCreationBodies() ) do
							if impulses[body.id] then
								sm.physics.applyImpulse( body, impulses[body.id], true )
							end
						end
					end
				end
			end
		end
	end
end
