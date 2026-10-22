dofile( "$CONTENT_DATA/Scripts/layouts.lua" )

-- ARC Device: a part you mount on your car.
--   Power it up: carry an energy anchor to it and click it to insert, like the
--   battery holder at the mining hub (E works too). Anchors sit in its slots.
--   Activate it: wire a button or switch to it. With enough anchors (the gateway
--   cost of the junction you're in, see GatewayCost in layouts.lua)
--   inside, turning that on charges it up for ARC_CHARGE_SECONDS, then it blasts
--   and opens a gateway out in the zone. The anchors stay in it (as in Pacific
--   Drive): back at the garage every anchor that came home is banked into the
--   Fabricator (GarageWorld.sv_bankAnchors).
--   (The click-to-insert hook is in survival_patches.lua.)
ArcDevice = class()
ArcDevice.maxParentCount = 1
ArcDevice.maxChildCount = 0
ArcDevice.connectionInput = sm.interactable.connectionType.logic
ArcDevice.connectionOutput = sm.interactable.connectionType.none

local ANCHOR_UUID = sm.uuid.new( "c243bb55-92f9-4f77-bb2a-b7c87b5a2be9" )
local CHARGED_ORB_EFFECT = "PacificScrap - GatewaySphere"
local CHARGE_EFFECT = "PacificScrap - ArcCharge"
local BLAST_EFFECT = "PacificScrap - ArcBlast"
local ORB_OFFSET = sm.vec3.new( 0, 0.6, 0 )
local SPHERE_MESH_RADIUS = 6.16

local SLOTS = ZONE_ANCHORS_MAX -- room for the most a gateway can cost

-- What a gateway costs where the game currently is (set by Game.lua)
local function GatewayCostNow()
	return g_gatewayCost or ARC_ANCHORS_TO_OPEN
end

function ArcDevice.server_onCreate( self )
	self.sv = {}
	-- (a carry item: picked up, its storage comes along as carry data and its
	-- anchors in the carry's extra slots, which the game puts back on drop)
	self.sv.saved = self.storage:load() or self.interactable:getCarryData() or {}
	self.interactable:setCarryData( self.sv.saved )
	self.sv.parentActive = false

	local container = self.interactable:getContainer( 0 )
	local keep = 0
	if container and container:getSize() < SLOTS then
		-- Older device with fewer slots: rebuild it, keeping its anchors
		for _, uuid in ipairs( ENERGY_ANCHOR_UUIDS ) do
			keep = keep + sm.container.totalQuantity( container, uuid )
		end
		self.interactable:removeContainer( 0 )
		container = nil
	end
	if not container then
		container = self.interactable:addContainer( 0, SLOTS, 1 )
	end
	keep = keep + ( self.sv.saved.anchors or 0 )
	container:setFilters( ENERGY_ANCHOR_UUIDS )
	-- (the very first devices counted anchors in storage instead)
	if keep > 0 then
		sm.container.beginTransaction()
		sm.container.collect( container, ANCHOR_UUID, math.min( keep, SLOTS ), true )
		sm.container.endTransaction()
		self.sv.saved.anchors = 0
		self.storage:save( self.sv.saved )
	end
	self:sv_sendCount()
end

function ArcDevice.sv_container( self )
	return self.interactable:getContainer( 0 )
end

function ArcDevice.sv_count( self )
	local container = self:sv_container()
	if not container then return 0 end
	local count = 0
	for _, uuid in ipairs( ENERGY_ANCHOR_UUIDS ) do
		count = count + sm.container.totalQuantity( container, uuid )
	end
	return count
end

function ArcDevice.sv_sendCount( self )
	self.sv.sentCost = GatewayCostNow()
	self.network:setClientData( { anchors = self:sv_count(), cost = self.sv.sentCost } )
end

-- Moves one anchor from a player's carry slot into the device
function ArcDevice.sv_insertFrom( self, fromContainer )
	local container = self:sv_container()
	if not container or not fromContainer then
		return
	end
	sm.container.beginTransaction()
	local uuid
	for _, kind in ipairs( ENERGY_ANCHOR_UUIDS ) do
		if sm.container.totalQuantity( fromContainer, kind ) > 0 then uuid = kind break end
	end
	if not uuid then
		sm.container.abortTransaction()
		return
	end
	sm.container.spend( fromContainer, uuid, 1, true )
	sm.container.collect( container, uuid, 1, true )
	if sm.container.endTransaction() then
		sm.effect.playEffect( "PowerSocket - Activate", self.shape.worldPosition, nil, self.shape.worldRotation )
		self:sv_sendCount()
	end
end

-- Carry tool click (see survival_patches.lua)
function ArcDevice.sv_e_receiveItem( self, params )
	if EnergyAnchorOf( params.itemA ) then
		self:sv_insertFrom( params.containerA )
	end
end

-- E while carrying an anchor
function ArcDevice.sv_n_insert( self, _, player )
	self:sv_insertFrom( player:getCarry() )
end

-- Always carried (never into the inventory), so its anchors aren't lost
function ArcDevice.client_canCarry( self )
	return true
end

function ArcDevice.server_onFixedUpdate( self )
	-- The tutorial quest checks the anchors put in (Story.lua)
	if sm.game.getCurrentTick() % 20 == 0 then
		g_arcAnchorCounts = g_arcAnchorCounts or {}
		g_arcAnchorCounts[self.interactable.id] = { count = self:sv_count(), tick = sm.game.getCurrentTick() }
	end
	-- The Expedition Checklist (Story.lua): on a vehicle, and wired to a switch?
	if sm.game.getCurrentTick() % 40 == 5 then
		g_arcDevices = g_arcDevices or {}
		g_arcDevices[self.interactable.id] = {
			tick = sm.game.getCurrentTick(), world = self.shape.body:getWorld(), position = self.shape.worldPosition,
			onVehicle = self:sv_onVehicle(), connected = self.interactable:getSingleParent() ~= nil,
		}
	end

	-- The cost changes with the junction
	if sm.game.getCurrentTick() % 40 == 0 and GatewayCostNow() ~= self.sv.sentCost then
		self:sv_sendCount()
	end

	-- Charging up: release it when the time is up
	if self.sv.chargeTick and sm.game.getCurrentTick() >= self.sv.chargeTick then
		self.sv.chargeTick = nil
		self.network:sendToClients( "cl_n_blast" )
		sm.event.sendToGame( "sv_e_arcOpenGateway", { device = self.interactable, position = self.shape.worldPosition, world = self.shape.body:getWorld() } )
	end

	-- Activate when the connected button or switch turns on
	local parent = self.interactable:getSingleParent()
	local active = parent ~= nil and parent:isActive()
	if active and not self.sv.parentActive then
		self:sv_activate()
	end
	self.sv.parentActive = active
end

-- On a vehicle: built onto a creation that can move (not one fixed to the
-- ground), and not just the device lying about on its own
function ArcDevice.sv_onVehicle( self )
	local body = self.shape.body
	return body:isDynamic() and #body:getCreationShapes() > 1
end

function ArcDevice.sv_activate( self )
	local count = self:sv_count()
	if self.sv.chargeTick then
		return -- already charging
	end
	local cost = GatewayCostNow()
	if count >= cost then
		-- The game checks we're in the zone with no gateway yet, and calls back to start charging
		sm.event.sendToGame( "sv_e_arcRequestCharge", { device = self.interactable, position = self.shape.worldPosition, world = self.shape.body:getWorld() } )
	else
		self.network:sendToClients( "cl_n_message", { text = "The ARC Device needs " .. cost .. " energy anchors here (" .. count .. "/" .. cost .. ")", position = self.shape.worldPosition } )
		sm.log.info( "[PacificScrap] ARC Device: not enough anchors", count, "/", cost )
	end
end

-- The game says why a gateway can't open (e.g. no stable exits here)
function ArcDevice.sv_e_message( self, text )
	self.network:sendToClients( "cl_n_message", { text = text, position = self.shape.worldPosition } )
end

function ArcDevice.sv_e_arcStartCharge( self )
	if not self.sv.chargeTick then
		self.sv.chargeTick = sm.game.getCurrentTick() + math.floor( ARC_CHARGE_SECONDS * 40 )
		self.sv.chargeCost = GatewayCostNow()
		self.network:sendToClients( "cl_n_charge" )
	end
end

-- Called by the game once the gateway has opened
-- (the anchors aren't used up: they go to the Fabricator once home)
function ArcDevice.sv_e_gatewayOpened( self )
	self:sv_sendCount()
end

-- Its anchors were banked at the garage (GarageWorld.sv_bankAnchors)
function ArcDevice.sv_e_refreshCount( self )
	self:sv_sendCount()
end


-- Client --------------------------------------------------------------------------

function ArcDevice.client_onCreate( self )
	self.cl = { anchors = 0, cost = ARC_ANCHORS_TO_OPEN }
end

function ArcDevice.client_onDestroy( self )
	self:cl_stopCharge()
	if self.cl.orb and sm.exists( self.cl.orb ) then
		self.cl.orb:destroy()
	end
end

function ArcDevice.client_onClientDataUpdate( self, data )
	self.cl.anchors = data.anchors
	self.cl.cost = data.cost or ARC_ANCHORS_TO_OPEN
	local charged = self.cl.anchors >= self.cl.cost
	-- A small glowing orb on top while charged
	if charged and not self.cl.orb then
		self.cl.orb = sm.effect.createEffect( CHARGED_ORB_EFFECT, self.interactable )
		self.cl.orb:setOffsetPosition( ORB_OFFSET )
		self.cl.orb:setScale( sm.vec3.one() * ( 0.3 / SPHERE_MESH_RADIUS ) )
		self.cl.orb:start()
	elseif not charged and self.cl.orb then
		self.cl.orb:destroy()
		self.cl.orb = nil
	end
end

local function LocalCarryingAnchor()
	local carry = sm.localPlayer.getCarry()
	for _, uuid in ipairs( ENERGY_ANCHOR_UUIDS ) do
		if sm.container.totalQuantity( carry, uuid ) > 0 then return true end
	end
	return false
end

function ArcDevice.client_canInteract( self, character )
	local status = "Anchors: " .. self.cl.anchors .. "/" .. self.cl.cost
	if LocalCarryingAnchor() then
		sm.gui.setInteractionText( "", sm.gui.getKeyBinding( "Use", true ), "Insert energy anchor" )
	elseif self.cl.anchors >= self.cl.cost then
		sm.gui.setInteractionText( "Charged - connect a button or switch to open a gateway" )
	else
		sm.gui.setInteractionText( "ARC Device" )
	end
	sm.gui.setInteractionText( status )
	return LocalCarryingAnchor()
end

function ArcDevice.client_onInteract( self, character, state )
	if state and LocalCarryingAnchor() then
		self.network:sendToServer( "sv_n_insert" )
	end
end

-- Charging: sparks and a rumble, and an orb of light swelling up on the device
function ArcDevice.cl_n_charge( self )
	self:cl_stopCharge()
	self.cl.chargeEffect = sm.effect.createEffect( CHARGE_EFFECT, self.interactable )
	self.cl.chargeEffect:start()
	self.cl.chargeOrb = sm.effect.createEffect( CHARGED_ORB_EFFECT, self.interactable )
	self.cl.chargeOrb:setOffsetPosition( ORB_OFFSET )
	self.cl.chargeOrb:setScale( sm.vec3.one() * ( 0.3 / SPHERE_MESH_RADIUS ) )
	self.cl.chargeOrb:start()
	self.cl.chargeTime = 0
end

function ArcDevice.cl_n_blast( self )
	self:cl_stopCharge()
	sm.effect.playHostedEffect( BLAST_EFFECT, self.interactable )
end

function ArcDevice.cl_stopCharge( self )
	if self.cl.chargeEffect and sm.exists( self.cl.chargeEffect ) then
		self.cl.chargeEffect:stopImmediate()
		self.cl.chargeEffect:destroy()
	end
	self.cl.chargeEffect = nil
	if self.cl.chargeOrb and sm.exists( self.cl.chargeOrb ) then
		self.cl.chargeOrb:destroy()
	end
	self.cl.chargeOrb = nil
	self.cl.chargeTime = nil
end

function ArcDevice.client_onUpdate( self, dt )
	if self.cl.chargeOrb and sm.exists( self.cl.chargeOrb ) then
		-- Grows from 0.3m to 2.5m radius, flickering faster near the end
		self.cl.chargeTime = self.cl.chargeTime + dt
		local t = math.min( self.cl.chargeTime / ARC_CHARGE_SECONDS, 1.0 )
		local flicker = 1.0 + math.sin( self.cl.chargeTime * ( 10 + t * 40 ) ) * 0.12 * t
		local radius = ( 0.3 + t * t * 2.2 ) * flicker
		self.cl.chargeOrb:setScale( sm.vec3.one() * ( radius / SPHERE_MESH_RADIUS ) )
	end
end

function ArcDevice.cl_n_message( self, params )
	local character = sm.localPlayer.getPlayer().character
	if character and sm.exists( character ) and ( character.worldPosition - params.position ):length() < 30 then
		sm.gui.displayAlertText( params.text, 3 )
	end
end
