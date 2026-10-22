dofile( "$SURVIVAL_DATA/Scripts/game/survival_projectiles.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_loot.lua" )
dofile( "$CONTENT_DATA/Scripts/layouts.lua" )

-- Supply pod: a crate of rarer loot (the Friendly Dumpster's chest model). While a zone collapses they come down out
-- of the sky (ZoneWorld.sv_e_dropPod, timed by Game.sv_updateStorm), trailing
-- smoke like the missiles, and they lie about collapsed zones. Once it's down
-- a smoke column marks it; press E to open it: a chest window, like Survival's
-- chests, with the loot inside.
-- What's inside: POD_LOOT in layouts.lua, by the zone's tier (a collapsed zone's
-- pods roll the next tier's).
SupplyPod = class()
SupplyPod.maxParentCount = 0
SupplyPod.maxChildCount = 0

local LANDED_SPEED = 1.5 -- m/s: slower than this after falling = it's down
local MAX_FALL_SPEED = 35 -- m/s

-- Server ------------------------------------------------------------------------

function SupplyPod.server_onCreate( self )
	self.sv = { saved = self.storage:load() or { opened = false, landed = false } }
	self.sv.createTick = sm.game.getCurrentTick()
	-- Down on the ground (the upright copy put down where it landed, or one
	-- placed in a collapsed zone): its chest, filled once
	if self.shape.body:isStatic() and not self.sv.saved.filled then
		self:sv_fill()
	end
	self:sv_sync()
end

function SupplyPod.sv_sync( self )
	self.network:setClientData( { opened = self.sv.saved.opened, landed = self.sv.saved.landed } )
end

function SupplyPod.server_onFixedUpdate( self )
	if self.sv.saved.landed or sm.game.getCurrentTick() - self.sv.createTick < 20 then
		return
	end
	local body = self.shape.body
	if body:isStatic() then
		-- (the upright one put down when it landed, or one placed on the ground)
		self.sv.saved.landed = true
		self.storage:save( self.sv.saved )
		self:sv_sync()
	else
		-- Falling: no faster than MAX_FALL_SPEED (fast bodies can pass right
		-- through the ground), and down as soon as the ground is just below
		local velocity = body.velocity
		if velocity.z < -MAX_FALL_SPEED then
			sm.physics.applyImpulse( body, sm.vec3.new( 0, 0, -MAX_FALL_SPEED - velocity.z ) * body.mass, true )
		end
		local position = self.shape.worldPosition
		local reach = math.abs( velocity.z ) / 40 * 2 + 2.5
		local hit, result = sm.physics.raycast( position, position - sm.vec3.new( 0, 0, reach ), body )
		if hit or velocity:length() < LANDED_SPEED then
			-- Down: the impact, then it stands up straight on the ground (a static
			-- copy, so it doesn't topple and its loot comes out upwards)
			sm.effect.playEffect( "Scannerbot - Missleexplosion", position )
			if not hit then
				hit, result = sm.physics.raycast( position + sm.vec3.new( 0, 0, 3 ), position - sm.vec3.new( 0, 0, 10 ), body )
			end
			local ground = hit and result.pointWorld or ( position - sm.vec3.new( 0, 0, 1 ) )
			local world = body:getWorld()
			self.shape:destroyShape()
			sm.event.sendToWorld( world, "sv_e_placePod", { x = ground.x, y = ground.y, z = ground.z } )
		end
	end
end

-- Which loot table: the zone's tier, one up in a collapsed zone
local function LootTable( world )
	local data = world and world.publicData or {}
	local _, tier = ZoneTierOf( data.depth or 1 )
	if data.collapsed then tier = tier + 1 end
	local name = ZONE_TIERS[math.min( tier, #ZONE_TIERS )].name
	return POD_LOOT[name] or POD_LOOT.outer
end

local function Roll( entries )
	local loot = {}
	for _, entry in ipairs( entries ) do
		if math.random() < ( entry.chance or 1 ) then
			local quantity = math.random( entry.min or 1, entry.max or entry.min or 1 )
			if quantity > 0 then
				loot[#loot + 1] = { uuid = sm.uuid.new( entry.uuid ), quantity = quantity }
			end
		end
	end
	return loot
end

local SLOTS = 20

function SupplyPod.sv_fill( self )
	local container = self.interactable:getContainer( 0 ) or self.interactable:addContainer( 0, SLOTS )
	for _, item in ipairs( Roll( LootTable( self.shape.body:getWorld() ) ) ) do
		sm.container.beginTransaction()
		sm.container.collect( container, item.uuid, item.quantity, false )
		sm.container.endTransaction()
	end
	self.sv.saved.filled = true
	self.storage:save( self.sv.saved )
end

-- Opened: the smoke column goes out
function SupplyPod.sv_n_open( self, _, player )
	if self.sv.saved.opened then
		return
	end
	self.sv.saved.opened = true
	self.storage:save( self.sv.saved )
	self:sv_sync()
	sm.effect.playEffect( "LootCrate - DestroyGlow", self.shape.worldPosition + sm.vec3.new( 0, 0, 1.5 ) )
end


-- Client ------------------------------------------------------------------------

function SupplyPod.client_onCreate( self )
	self.cl = { opened = false, landed = false }
	self.cl.trail = sm.effect.createEffect( "Scannerbot - Misslesmoketrail", self.interactable )
	self.cl.smoke = sm.effect.createEffect( "Controlconsole - Destroyed Smokeloop", self.interactable )
end

function SupplyPod.client_onDestroy( self )
	for _, effect in ipairs( { self.cl.trail, self.cl.smoke } ) do
		if effect and sm.exists( effect ) then effect:destroy() end
	end
end

local function Play( effect, on )
	if effect and sm.exists( effect ) then
		if on and not effect:isPlaying() then effect:start()
		elseif not on and effect:isPlaying() then effect:stop() end
	end
end

function SupplyPod.client_onClientDataUpdate( self, data )
	self.cl.opened, self.cl.landed = data.opened, data.landed
	-- Falling: the missile's trail; down: a smoke column until it's opened
	Play( self.cl.trail, not data.landed )
	Play( self.cl.smoke, data.landed and not data.opened )
end

function SupplyPod.client_canInteract( self )
	if not self.cl.landed then
		return false
	end
	sm.gui.setInteractionText( "", sm.gui.getKeyBinding( "Use", true ), "Open the supply pod" )
	return true
end

-- A chest window, like Survival's chests
function SupplyPod.client_onInteract( self, character, state )
	if state then
		self.network:sendToServer( "sv_n_open" )
		local container = self.interactable:getContainer( 0 )
		if container then
			local gui = sm.gui.createContainerGui( true )
			gui:setText( "UpperName", "Supply Pod" )
			gui:setContainer( "UpperGrid", container )
			gui:setText( "LowerName", "#{INVENTORY_TITLE}" )
			gui:setContainer( "LowerGrid", sm.localPlayer.getInventory() )
			gui:open()
		end
	end
end
