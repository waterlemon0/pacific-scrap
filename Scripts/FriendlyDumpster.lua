dofile( "$SURVIVAL_DATA/Scripts/game/survival_projectiles.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_loot.lua" )
dofile( "$CONTENT_DATA/Scripts/layouts.lua" )

-- Friendly Dumpster (Pacific Drive): a dumpster by the garage that refills after
-- every trip into the zone. Open it (a chest window, like Survival's chests) and
-- the supplies are inside, so you can never get stuck:
--   * the first time: a starter kit (portable Craftbot, basic materials, fuel,
--     food)
--   * after every trip: scrap, fuel and the odd extra
--   * after a failed run that didn't tow a car home: a car starter kit
--   * an ARC Device whenever nobody has one, and the garage's battery while
--     the garage has no power and nobody has one (Getting Started), both in
--     the chest (on top only if it's full), whenever it's opened
-- What it gives is set in DUMPSTER_STARTER / DUMPSTER_RESTOCK / DUMPSTER_CAR_KIT
-- (layouts.lua).
FriendlyDumpster = class()
FriendlyDumpster.maxParentCount = 0
FriendlyDumpster.maxChildCount = 0

local ARC_DEVICE_UUID = sm.uuid.new( "a6258a75-ea2b-47f7-acec-a3ace313bbd9" )
local BATTERY_UUID = sm.uuid.new( "c654a023-ca53-4109-9f18-d297c18e9a02" ) -- (survival's power core)
local SLOTS = 30


-- Server ------------------------------------------------------------------------

function FriendlyDumpster.server_onCreate( self )
	self.sv = {}
	self.sv.saved = self.storage:load() or { starterGiven = false, emptiedTrip = -1 }
	if not self.interactable:getContainer( 0 ) then
		self.interactable:addContainer( 0, SLOTS )
	end
	self:sv_sync()
end

-- Full when there's been a trip since it was last emptied (g_garageTrips is
-- counted by the game)
function FriendlyDumpster.sv_isFull( self )
	return not self.sv.saved.starterGiven or ( g_garageTrips or 0 ) > self.sv.saved.emptiedTrip or g_carKitPending == true
end

function FriendlyDumpster.sv_sync( self )
	local full = self:sv_isFull()
	if full ~= self.sv.sentFull then
		self.sv.sentFull = full
		self.network:setClientData( { full = full } )
	end
end

function FriendlyDumpster.server_onFixedUpdate( self )
	if sm.game.getCurrentTick() % 40 == 0 then
		self:sv_sync()
	end
end

-- Is there one of these anywhere we can see: any player's inventory or carry,
-- the dumpster's own chest, or on any creation in this (the garage) world?
-- (with skipWorld, nothing in the world counts)
local function ItemExists( uuid, world, container, skipWorld )
	if container and sm.container.totalQuantity( container, uuid ) > 0 then
		return true
	end
	for _, player in ipairs( sm.player.getAllPlayers() ) do
		if sm.container.totalQuantity( player:getInventory(), uuid ) > 0
			or sm.container.totalQuantity( player:getCarry(), uuid ) > 0 then
			return true
		end
		-- (the hotbar is its own container only with the unlimited inventory)
		local hotbar = not sm.game.getLimitedInventory() and player:getHotbar()
		if hotbar and sm.container.totalQuantity( hotbar, uuid ) > 0 then
			return true
		end
	end
	if skipWorld then
		return false
	end
	for _, body in ipairs( sm.body.getAllBodies( world ) ) do
		if sm.exists( body ) then
			for _, shape in ipairs( body:getShapes() ) do
				if shape.uuid == uuid then
					return true
				end
			end
		end
	end
	return false
end

-- The ARC Device and (while the garage has no power) the battery, if nobody
-- has one: into the chest, or on top if it's full. Checked on every open, so a
-- lost one always comes back.
function FriendlyDumpster.sv_giveEssentials( self, container )
	local world = self.shape.body:getWorld()
	local give = {}
	if not ItemExists( ARC_DEVICE_UUID, world, container ) then
		give[#give + 1] = { uuid = ARC_DEVICE_UUID, quantity = 1 }
	end
	-- (the battery placed in the garage tile doesn't count: the Getting Started
	-- quest sends you here for one)
	if not g_garagePowered and not ItemExists( BATTERY_UUID, world, container, true ) then
		give[#give + 1] = { uuid = BATTERY_UUID, quantity = 1 }
	end
	for _, item in ipairs( give ) do
		sm.container.beginTransaction()
		local collected = sm.container.collect( container, item.uuid, item.quantity, false )
		sm.container.endTransaction()
		if collected == 0 then
			SpawnLoot( self.shape, { item }, self.shape.worldPosition + sm.vec3.new( 0, 0, 3 ) )
		end
	end
end

-- Rolls a loot table: { { uuid, min, max, chance } }
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

function FriendlyDumpster.sv_n_open( self, _, player )
	sm.event.sendToGame( "sv_e_dumpsterOpened" ) -- (Getting Started and Into the Zone, Story.lua)
	local container = self.interactable:getContainer( 0 )
	self:sv_giveEssentials( container )
	if not self:sv_isFull() then
		return -- (whatever's still inside is in the window)
	end

	local starter = not self.sv.saved.starterGiven
	local loot = Roll( starter and DUMPSTER_STARTER or DUMPSTER_RESTOCK )
	-- No car came home from the last failed run: the parts for a new one
	if g_carKitPending then
		for _, item in ipairs( Roll( DUMPSTER_CAR_KIT ) ) do loot[#loot + 1] = item end
		sm.event.sendToGame( "sv_e_carKitGiven" )
	end

	-- Into the dumpster's chest (what doesn't fit stays out)
	for _, item in ipairs( loot ) do
		sm.container.beginTransaction()
		sm.container.collect( container, item.uuid, item.quantity, false )
		sm.container.endTransaction()
	end

	self.sv.saved.starterGiven = true
	self.sv.saved.emptiedTrip = g_garageTrips or 0
	self.storage:save( self.sv.saved )
	self:sv_sync()
	sm.effect.playEffect( "LootCrate - DestroyGlow", self.shape.worldPosition + sm.vec3.new( 0, 0, 1.5 ) )
end


-- Client ------------------------------------------------------------------------

function FriendlyDumpster.client_onCreate( self )
	self.cl = { full = true }
end

function FriendlyDumpster.client_onClientDataUpdate( self, data )
	self.cl.full = data.full
end

function FriendlyDumpster.client_canInteract( self )
	if self.cl.full then
		sm.gui.setInteractionText( "", sm.gui.getKeyBinding( "Use", true ), "Rummage through the Friendly Dumpster" )
	else
		sm.gui.setInteractionText( "", sm.gui.getKeyBinding( "Use", true ), "Open the Friendly Dumpster (refills after your next trip)" )
	end
	return true
end

-- A chest window, like Survival's chests (the server fills it as it opens)
function FriendlyDumpster.client_onInteract( self, character, state )
	if state then
		self.network:sendToServer( "sv_n_open" )
		local container = self.interactable:getContainer( 0 )
		if container then
			local gui = sm.gui.createContainerGui( true )
			gui:setText( "UpperName", "Friendly Dumpster" )
			gui:setContainer( "UpperGrid", container )
			gui:setText( "LowerName", "#{INVENTORY_TITLE}" )
			gui:setContainer( "LowerGrid", sm.localPlayer.getInventory() )
			gui:open()
		end
	end
end
