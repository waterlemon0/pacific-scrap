-- Fuel Pump (garage): take gas canisters for the car. FUEL_PUMP_TAKE a time, up
-- to FUEL_PUMP_PER_TRIP per stay at home (it refills after every trip into the
-- zone, like the Friendly Dumpster: g_garageTrips is counted by the game). Only
-- once the garage has power (the Getting Started quest).
dofile( "$CONTENT_DATA/Scripts/layouts.lua" ) -- (FUEL_PUMP_HOME, PlaceFuelPumpAtHome)

FuelPump = class()
FuelPump.maxParentCount = 0
FuelPump.maxChildCount = 0

local GAS_CANISTER = sm.uuid.new( "d4d68946-aa03-4b8f-b1af-96b81ad4e305" )
local FUEL_PUMP_TAKE = 5
local FUEL_PUMP_PER_TRIP = 10

-- Its spot in the garage: FUEL_PUMP_HOME (layouts.lua). It was placed in the
-- garage tile with physics on, so it could be knocked about: one with physics,
-- off its spot or not standing up is swapped for a static copy on its spot
-- (sv_checkPlace). A second one turning up (an old knocked-away one loading
-- in) goes, if one's on the spot already.
local HOME_TOLERANCE = 0.75 -- metres off its spot that still count as in place

-- Server ------------------------------------------------------------------------

function FuelPump.server_onCreate( self )
	-- (a copy put back on its spot takes over the old one's count)
	local carried = g_fuelPumpCarry
	g_fuelPumpCarry = nil
	self.sv = { saved = self.storage:load() or carried or { trip = -1, given = 0 } }
	self.sv.saved.home = nil -- (an earlier version remembered its own)
	self.storage:save( self.sv.saved )
	g_fuelPumps = g_fuelPumps or {}
	g_fuelPumps[self.shape.id] = self.shape
	self:sv_sync()
end

function FuelPump.server_onDestroy( self )
	if g_fuelPumps then g_fuelPumps[self.shape.id] = nil end
end

-- In the garage: static, standing, on its spot? If not, a static copy goes on
-- its spot and this one goes. (/fuelpump: put back right away, g_fuelPumpHome)
function FuelPump.sv_checkPlace( self )
	local body = self.shape.body
	local world = body:getWorld()
	if not ( world.publicData and world.publicData.type == "GarageWorld" ) then return end
	local forced = g_fuelPumpHome
	g_fuelPumpHome = nil
	local home = FuelPumpHome()
	-- (height counts too: an earlier version put one on the garage roof)
	local function awayFrom( p ) return ( p - home ):length() end
	local pos = self.shape.worldPosition
	local upright = self.shape.at.z > 0.95 -- (its Y axis points up when it stands)
	local away = awayFrom( pos )
	-- (several on the spot, from an earlier version placing more while the
	-- garage was unloaded: the oldest stays)
	if away < HOME_TOLERANCE then
		for id, shape in pairs( g_fuelPumps or {} ) do
			if id < self.shape.id and sm.exists( shape ) and awayFrom( shape.worldPosition ) < HOME_TOLERANCE then
				self.shape:destroyShape()
				sm.log.info( "[PacificScrap] Extra Fuel Pump removed (one is on its spot already)" )
				return
			end
		end
	end
	if not forced and body:isStatic() and upright and away < HOME_TOLERANCE then return end
	-- (another pump already on the spot: this one's an extra)
	for id, shape in pairs( g_fuelPumps or {} ) do
		if id ~= self.shape.id and sm.exists( shape ) and awayFrom( shape.worldPosition ) < HOME_TOLERANCE then
			self.shape:destroyShape()
			sm.log.info( "[PacificScrap] Extra Fuel Pump removed (one is on its spot already)" )
			return
		end
	end
	g_fuelPumpCarry = self.sv.saved
	PlaceFuelPumpAtHome()
	self.shape:destroyShape()
	sm.log.info( "[PacificScrap] Fuel Pump put back on its spot (it was", math.floor( away * 10 ) / 10, "m away,",
		body:isStatic() and "static" or "loose", upright and "standing)" or "knocked over)" )
end

function FuelPump.sv_left( self )
	local trip = g_garageTrips or 0
	if self.sv.saved.trip ~= trip then
		return FUEL_PUMP_PER_TRIP
	end
	return math.max( FUEL_PUMP_PER_TRIP - self.sv.saved.given, 0 )
end

function FuelPump.sv_sync( self )
	local data = { left = self:sv_left(), powered = g_garagePowered == true }
	if not self.sv.sent or self.sv.sent.left ~= data.left or self.sv.sent.powered ~= data.powered then
		self.sv.sent = data
		self.network:setClientData( data )
	end
end

function FuelPump.server_onFixedUpdate( self )
	if sm.game.getCurrentTick() % 40 == 17 then
		self:sv_sync()
	end
	-- (soon after it's made or loaded, then now and then)
	self.sv.placeChecks = ( self.sv.placeChecks or 0 ) + 1
	if self.sv.placeChecks == 20 or self.sv.placeChecks % 200 == 0 or g_fuelPumpHome then
		self:sv_checkPlace()
	end
end

function FuelPump.sv_n_take( self, _, player )
	local left = self:sv_left()
	if not g_garagePowered or left <= 0 then
		return
	end
	local amount = math.min( FUEL_PUMP_TAKE, left )
	sm.container.beginTransaction()
	sm.container.collect( player:getInventory(), GAS_CANISTER, amount, true )
	if sm.container.endTransaction() then
		local trip = g_garageTrips or 0
		if self.sv.saved.trip ~= trip then
			self.sv.saved = { trip = trip, given = 0 }
		end
		self.sv.saved.given = self.sv.saved.given + amount
		self.storage:save( self.sv.saved )
		self:sv_sync()
		sm.effect.playEffect( "Part - Upgrade", self.shape.worldPosition )
	end
end

-- Client ------------------------------------------------------------------------

function FuelPump.client_onCreate( self )
	self.cl = { left = FUEL_PUMP_PER_TRIP, powered = false }
end

function FuelPump.client_onClientDataUpdate( self, data )
	self.cl.left, self.cl.powered = data.left, data.powered
end

function FuelPump.client_canInteract( self )
	if not self.cl.powered then
		sm.gui.setInteractionText( "No power", "Put the battery in the garage's socket" )
		return false
	end
	if self.cl.left <= 0 then
		sm.gui.setInteractionText( "Empty", "It refills after your next trip" )
		return false
	end
	sm.gui.setInteractionText( "", sm.gui.getKeyBinding( "Use", true ), "Take fuel (" .. self.cl.left .. " left)" )
	return true
end

function FuelPump.client_onInteract( self, character, state )
	if state then
		self.network:sendToServer( "sv_n_take" )
	end
end
