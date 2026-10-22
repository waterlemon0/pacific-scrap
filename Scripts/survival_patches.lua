-- Small runtime additions to survival scripts, so energy anchors work like
-- survival's carried resources:
--   * ARC Device and Fabricator: carry an energy anchor to one and click to
--     insert it, like the battery holder at the mining hub.
--   * Render settings: survival only uses a world's default render settings in
--     indoor worlds (warehouses, dungeons). The zone is outdoor, so its fog and
--     the storm lighting are layered on top of the time-of-day settings here.
--     Worlds add files with AddWorldRenderSettings.
--   * Weather: survival's WeatherManager creates its rain/sky effects once, in
--     whatever world was the "weatherworld" then. When that changes (garage <->
--     zone) they're rebuilt in the new world.
-- Survival keeps its insert targets and refinery recipes in locals, so the
-- functions that use them are swapped for copies that also know the anchor.
-- ApplySurvivalPatches() is called again regularly in case a survival script
-- gets loaded (and redefines its class) after us.

dofile( "$SURVIVAL_DATA/Scripts/game/survival_collections.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/interactables/Refinery.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/tools/CarryTool.lua" )
dofile( "$GAME_DATA/Scripts/game/managers/WeatherManager.lua" )
dofile( "$CONTENT_DATA/Scripts/layouts.lua" )
dofile( "$CONTENT_DATA/Scripts/hideout_shop.lua" ) -- (the hideout shop, put on HideoutTrader below)
dofile( "$CONTENT_DATA/Scripts/upgrade_tree.lua" ) -- (LOCKED_DEFAULT_RECIPES)

local ANCHOR_UUID = sm.uuid.new( "c243bb55-92f9-4f77-bb2a-b7c87b5a2be9" )
local ARC_DEVICE_UUID = sm.uuid.new( "a6258a75-ea2b-47f7-acec-a3ace313bbd9" )
local FABRICATOR_UUID = sm.uuid.new( "7ee97af5-72b9-4335-a3bd-e80d49dab105" )
local COMPONENT_KIT_UUID = sm.uuid.new( "5530e6a0-4748-4926-b134-50ca9ecb9dcf" )

-- Survival's refinery recipes plus the anchor
local function Recipe( input, output, quantity )
	return { itemId = tostring( output ), itemUuid = output, quantity = quantity, craftTime = 7, ingredientList = { { quantity = 1, itemId = input } } }
end
local PacificRefineryRecipes = {
	[tostring( ITEMS.obj_harvest_wood )] = Recipe( ITEMS.obj_harvest_wood, ITEMS.blk_scrapwood, 20 ),
	[tostring( ITEMS.obj_harvest_wood2 )] = Recipe( ITEMS.obj_harvest_wood2, ITEMS.blk_scrapwood, 40 ),
	[tostring( ITEMS.obj_harvest_metal )] = Recipe( ITEMS.obj_harvest_metal, ITEMS.blk_scrapmetal, 20 ),
	[tostring( ITEMS.obj_harvest_metal2 )] = Recipe( ITEMS.obj_harvest_metal2, ITEMS.blk_metal1, 20 ),
	[tostring( ITEMS.obj_harvest_stone )] = Recipe( ITEMS.obj_harvest_stone, ITEMS.blk_scrapstone, 20 ),
}

-- Copied from Survival/Scripts/game/interactables/Refinery.lua, using the table above
local function RefinerySvCanFitCraftedItem( self, itemUuid )
	local recipe = PacificRefineryRecipes[tostring( itemUuid )]
	if recipe then
		-- Dry run to see if we can fit all crafted items
		sm.container.beginTransaction()
		local remainingQuantity = recipe.quantity
		remainingQuantity = remainingQuantity - sm.container.collect( self:getOutputContainer(), recipe.itemUuid, recipe.quantity, false )
		while remainingQuantity > 0 do
			local containerShape = sm.pipeGraph.getContainerShapeToCollectTo( self.shape, { recipe.itemUuid }, { 1 } )
			if containerShape == nil then
				break
			end
			local outputContainer = containerShape:getInteractable():getContainer( 0 ) --TODO: Ask the pipe graph for which container to use
			local collected = sm.container.collect( outputContainer, recipe.itemUuid, remainingQuantity, false )
			if collected == 0 then
				break -- Should not be possible
			end
			remainingQuantity = remainingQuantity - collected
		end
		sm.container.abortTransaction()
		return remainingQuantity == 0
	end
	return false
end

local function RefineryServerOnFixedUpdate( self, dt )
	if self.sv.isProducing then
		local inputItemUuids = sm.container.itemUuid( self:getInputContainer() )
		local harvestUuid = inputItemUuids[1]
		local recipe = PacificRefineryRecipes[tostring( inputItemUuids[1] )]
		if recipe then
			self.sv.productionProgress = self.sv.productionProgress + dt/self.sv.productionTime
			if self.sv.productionProgress >= 1.0 then
				-- Done producing
				if sm.container.beginTransaction() then
					sm.container.spend( self:getInputContainer(), harvestUuid, 1, true )
					local internalContainer = self:getOutputContainer()
					local remainingQuantity = recipe.quantity
					local effectTargetShapes = {}
					while remainingQuantity > 0 do
						-- Prioritise filling attached pipe containers before the internal output container
						local pipeContainerShape = sm.pipeGraph.getContainerShapeToCollectTo( self.shape, { recipe.itemUuid }, { 1 } )
						local outputContainer = pipeContainerShape and pipeContainerShape:getInteractable():getContainer( 0 ) or internalContainer --TODO: Ask the pipe graph for which container to use
						local collected = sm.container.collect( outputContainer, recipe.itemUuid, remainingQuantity, false )
						if collected == 0 then
							break
						end

						remainingQuantity = remainingQuantity - collected
						if pipeContainerShape then
							effectTargetShapes[#effectTargetShapes+1] = pipeContainerShape
						end
					end
					if remainingQuantity == 0 then
						if sm.container.endTransaction() then
							self.sv.productionProgress = 0.0
							self.sv.isProducing = false
							if #effectTargetShapes > 0 then
								self.network:sendToClients( "cl_n_finishProduction", { effectTargets = effectTargetShapes, item = recipe.itemUuid } )
							else
								self.network:sendToClients( "cl_n_finishProduction" )
							end
						end
					else
						sm.container.abortTransaction()
					end
				end
			end
		else
			self.sv.isProducing = false
			self.sv.productionProgress = 0.0
			local params = { isProducing = false }
			self.network:sendToClients( "cl_n_setIsProducing", params )
		end
	else
		self.sv.productionProgress = 0
	end

	--------------------

	self.sv.updateProgress = self.sv.updateProgress + dt/self.sv.updateTime
	if self.sv.updateProgress >= 1.0 then
		self.sv.updateProgress = 0.0

		local inputItemUuids = sm.container.itemUuid( self:getInputContainer() )
		local hasInputItem = PacificRefineryRecipes[tostring( inputItemUuids[1] )] ~= nil

		if not sm.uuid.isNil( inputItemUuids[1] ) and not hasInputItem then
			sm.log.error( "Refinery got an invalid input item: "..tostring( inputItemUuids[1] ) )
			sm.container.beginTransaction()
			sm.container.setItem( self:getInputContainer(), 0, sm.uuid.getNil(), 0 )
			sm.container.endTransaction()
			hasInputItem = false
		end
		-------------------
		local foundContainers = {}
		local adjacentShapeIds = {}
		for _, object in ipairs( self.sv.areaTrigger:getContents() ) do
			if type( object ) == "AreaTrigger" then
				local trigger = object
				if sm.exists( trigger ) then
					local userData = trigger:getUserData()
					if userData and userData.resourceCollector and not userData.isGravelCollector then
						local shape = userData.resourceCollector
						--Search shape containers
						if shape:getInteractable() then
							local otherContainer = shape:getInteractable():getContainer( 0 )
							if otherContainer then
								foundContainers[#foundContainers+1] = otherContainer
								adjacentShapeIds[#adjacentShapeIds+1] = shape:getId()
							end
						end
					end
				end
			end
		end

		table.sort( adjacentShapeIds )
		if not ArrayCompareShallow( adjacentShapeIds, self.sv.sourceShapeSignature or {} ) then
			self.sv.sourceShapeSignature = adjacentShapeIds
			sm.pipeGraph.removeAutomatedTasks( self.shape )
		end
		
		if not hasInputItem then
			for _,otherContainer in ipairs( foundContainers ) do
				local otherItemUuids = sm.container.itemUuid( otherContainer )
				for _, itemUuid in ipairs( otherItemUuids ) do
					local recipe = PacificRefineryRecipes[tostring( itemUuid )]
					if recipe then
						--if self:sv_canFitCraftedItem( itemUuid ) then --NOTE: Not guaranteed to still fit when done
							if sm.container.beginTransaction() then
								sm.container.collect( self.shape:getInteractable():getContainer( 1 ), itemUuid, 1, true )
								sm.container.spend( otherContainer, itemUuid, 1, true )
								for _, currentRecipe in pairs( PacificRefineryRecipes ) do
									local recipeCopy = shallowcopy( currentRecipe )
									recipeCopy.externalContainers = foundContainers
									recipeCopy.selfOutputContainer = self:getOutputContainer()
									sm.pipeGraph.setAutomatedTask( self.shape, recipeCopy )
								end
								sm.container.endTransaction()
							end
							break
						--end
					end
				end
			end
		end

		if hasInputItem then
			-- Can produce so start production
			if not self.sv.isProducing then
				self.sv.isProducing = true
				self.sv.productionProgress = 0.0
				local params = { isProducing = true }
				self.network:sendToClients( "cl_n_setIsProducing", params )
			end
		end

		if not hasInputItem then
			-- Abort any ongoing production because production can't continue
			if self.sv.isProducing then
				self.sv.isProducing = false
				self.sv.productionProgress = 0.0
				local params = { isProducing = false }
				self.network:sendToClients( "cl_n_setIsProducing", params )
			end
		end
		--TODO: Handle outputFull. Sen jammed signal to client
	end
end

local function RefinerySvReceiveItem( self, params )
	local recipe = PacificRefineryRecipes[tostring( params.itemA )]
	if recipe then --and self:sv_canFitCraftedItem( params.itemA )
		local container = self.interactable:getContainer( 1 )
		if container then
			sm.container.beginTransaction()
			sm.container.spend( params.containerA, params.itemA, params.quantityA, true )
			sm.container.collect( container, params.itemA, params.quantityA, true )
			sm.container.endTransaction()
		end
	end
end

-- Carry tool: clicking the ARC Device or the Fabricator while carrying an
-- energy anchor (any kind) inserts it
local function PatchedTryInsert( self, character, primaryState, playerCarry, carryUuid, playerCarryColor )
	if EnergyAnchorOf( carryUuid ) then
		local success, result = sm.localPlayer.getRaycast( 7.5 )
		if success and result.type == "body" then
			local shape = result:getShape()
			local target = shape and sm.exists( shape ) and shape.interactable and ( shape.uuid == ARC_DEVICE_UUID or shape.uuid == FABRICATOR_UUID )
			if target then
				local container = shape.interactable:getContainer( 0 )
				if shape.uuid == FABRICATOR_UUID or ( container and sm.container.canCollect( container, carryUuid, 1 ) ) then
					sm.gui.setInteractionText( "", sm.gui.getKeyBinding( "Create", true ), "#{INTERACTION_INSERT}" )
					if primaryState == sm.tool.interactState.start then
						local params = { containerA = playerCarry, itemA = carryUuid, quantityA = 1, targetShape = shape, fromPosition = character.worldPosition, fromRotation = sm.quat.identity(), color = playerCarryColor }
						self.network:sendToServer( "sv_n_sendItem", params )
					end
					return true
				end
			end
		end
	end
	return g_pacificOriginalTryInsert( self, character, primaryState, playerCarry, carryUuid, playerCarryColor )
end

-- Render settings layered over an outdoor world: g_pacificWorldRender[worldId]
-- is a list of { path, order, startTick }, applied lowest order first, each
-- fading in over RENDER_FADE_TICKS. A file may have a "pacific_night" block
-- ({ volumetric_intensity, vertical_opacity }) with multipliers used at night,
-- and a "pacific_colors" block ({ day = {r,g,b}, night = {r,g,b}, sky = { start,
-- end, falloff, top, middle, bottom } }): the fog takes the colour for the time
-- of day, and the horizon light paints the far distance and the sky with it so
-- the skybox disappears into the fog too.
local RENDER_FADE_TICKS = 40 * 3
g_pacificWorldRender = g_pacificWorldRender or {}
local loadedRenderSettings = {}

function AddWorldRenderSettings( world, path, order )
	local list = g_pacificWorldRender[world.id] or {}
	for _, entry in ipairs( list ) do
		if entry.path == path then return end
	end
	list[#list + 1] = { path = path, order = order or 0, startTick = sm.game.getCurrentTick() }
	table.sort( list, function( a, b ) return a.order < b.order end )
	g_pacificWorldRender[world.id] = list
end

-- (a pooled zone world used again starts without the last trip's)
function RemoveWorldRenderSettings( world, path )
	local list = g_pacificWorldRender[world.id]
	for i = #( list or {} ), 1, -1 do
		if list[i].path == path then table.remove( list, i ) end
	end
end

-- 1 in full daylight, 0 at night, following survival's time of day timeline
local function Daylight()
	local tod = sm.game.getTimeOfDay()
	local function ramp( a, b, x ) return math.max( math.min( ( x - a ) / ( b - a ), 1.0 ), 0.0 ) end
	if tod < 0.5 then
		return ramp( 0.2, 0.35, tod )
	end
	return 1.0 - ramp( 0.7, 0.85, tod )
end

local function PatchedMixRenderSettings( self, fromSettings, toSettings, t )
	local mix = g_pacificOriginalMixRenderSettings( self, fromSettings, toSettings, t )
	local character = sm.localPlayer.getPlayer().character
	local world = character and sm.exists( character ) and character:getWorld()
	local list = world and g_pacificWorldRender[world.id]
	if not list then
		return mix
	end
	local tick = sm.game.getCurrentTick()
	for _, entry in ipairs( list ) do
		local s = loadedRenderSettings[entry.path]
		if s == nil then
			s = self:cl_preprocessSettings( sm.json.open( entry.path ).settings )
			loadedRenderSettings[entry.path] = s
		end
		local w = math.max( math.min( ( tick - entry.startTick ) / RENDER_FADE_TICKS, 1.0 ), 0.0 )
		if w > 0 then
			if s.GI and s.GI.override then mix.GI = self:cl_mixGI( mix.GI, s.GI, w ) end
			if s.camera_light and s.camera_light.override then mix.camera_light = self:cl_mixCameraLight( mix.camera_light, s.camera_light, w ) end
			if s.reflection_color and s.reflection_color.override then mix.reflection_color = self:cl_mixReflection( mix.reflection_color, s.reflection_color, w ) end
			if s.LUT and s.LUT.override then mix.LUTargs = { mix.LUTargs[2], s.LUT.LUT, w } end
			if s.horizon_light and s.horizon_light.enable then mix.horizon_light = self:cl_mixHorizonLight( mix.horizon_light, s.horizon_light, w ) end
			local night = s.pacific_night
			local daylight = night and Daylight() or 1.0
			local fog, volumetric = s.fog, s.volumetric_fog
			if night and fog and fog.vertical_fog and night.vertical_opacity then
				fog = shallowcopy( fog )
				fog.vertical_fog = shallowcopy( fog.vertical_fog )
				fog.vertical_fog.opacity = fog.vertical_fog.opacity * sm.util.lerp( night.vertical_opacity, 1.0, daylight )
			end
			local colors = s.pacific_colors
			if colors and fog then
				local d = Daylight()
				local function tod( alpha )
					local r = sm.util.lerp( colors.night[1], colors.day[1], d )
					local g = sm.util.lerp( colors.night[2], colors.day[2], d )
					local b = sm.util.lerp( colors.night[3], colors.day[3], d )
					return sm.color.new( r, g, b, alpha or 1.0 )
				end
				fog = shallowcopy( fog )
				fog.vertical_fog = shallowcopy( fog.vertical_fog )
				fog.start_color, fog.end_color = tod( 0.6 ), tod( 1.0 )
				fog.vertical_fog.start_color, fog.vertical_fog.end_color = tod( 1.0 ), tod( 0.0 )
				fog.selective_override = shallowcopy( fog.selective_override or {} )
				fog.selective_override.start_color, fog.selective_override.end_color = true, true
				fog.vertical_fog.selective_override = shallowcopy( fog.vertical_fog.selective_override or {} )
				fog.vertical_fog.selective_override.start_color, fog.vertical_fog.selective_override.end_color = true, true
				local sky = colors.sky
				if sky then
					mix.horizon_light = self:cl_mixHorizonLight( mix.horizon_light, {
						top_color = tod( sky.top ), middle_color = tod( sky.middle ), bottom_color = tod( sky.bottom ),
						direction = sm.vec3.new( 0, 0, -1 ), start = sky.start, ["end"] = sky["end"], falloff = sky.falloff,
					}, w )
				end
			end
			if fog and fog.override then mix.fog = self:cl_mixFog( mix.fog, fog, w ) end
			if night and volumetric and night.volumetric_intensity then
				volumetric = shallowcopy( volumetric )
				volumetric.intensity = volumetric.intensity * sm.util.lerp( night.volumetric_intensity, 1.0, daylight )
			end
			if volumetric and volumetric.override then mix.volumetric_fog = self:cl_mixVolumetricFog( mix.volumetric_fog, volumetric, w ) end
		end
	end
	return mix
end

local function PatchedWeatherUpdate( self, dt )
	local world = WorldManager and WorldManager.Cl_GetWorld( "weatherworld" )
	if self.cl and world ~= self.cl.pacificWeatherWorld then
		for _, key in ipairs( { "skyEffects", "normalEffects", "todSkyEffects", "todNormalEffects" } ) do
			for _, entry in pairs( self.cl[key] or {} ) do
				if entry.effect and sm.exists( entry.effect ) then
					entry.effect:stopImmediate()
					entry.effect:destroy()
				end
			end
		end
		self.cl.skyEffects, self.cl.normalEffects, self.cl.todSkyEffects, self.cl.todNormalEffects = nil, nil, nil, nil
		if self.rainEffect and sm.exists( self.rainEffect ) then
			self.rainEffect:stop()
			self.rainEffect:destroy()
		end
		self.rainEffect = nil
		self.cl.pacificWeatherWorld = world
	end
	return g_pacificOriginalWeatherUpdate( self, dt )
end

-- The Logbook key equips survival's logbook tool. With MAP_ON_LOGBOOK_KEY the
-- player takes the logbook out as usual (same models and animations) but the
-- junction map opens instead of the logbook's window; putting it away closes
-- the map, and closing the map puts it away. A tool can't use the game's
-- network, so it only asks (g_pacificMapRequest); Game.client_onUpdate opens
-- or closes the map. Closing the map sets g_pacificMapClosedByUser.
local LOGBOOK_RENDERABLES = { "$SURVIVAL_DATA/Character/Char_Tools/Char_logbook/char_logbook.rend" }
local LOGBOOK_TP = { "$SURVIVAL_DATA/Character/Char_Male/Animations/char_male_tp_logbook.rend", "$SURVIVAL_DATA/Character/Char_Tools/Char_logbook/char_logbook_tp_animlist.rend" }
local LOGBOOK_FP = { "$SURVIVAL_DATA/Character/Char_Male/Animations/char_male_fp_logbook.rend", "$SURVIVAL_DATA/Character/Char_Tools/Char_logbook/char_logbook_fp_animlist.rend" }

local function PatchedLogBookEquip( self, animate )
	if not MAP_ON_LOGBOOK_KEY then
		return g_pacificOriginalLogBookEquip( self, animate )
	end
	self.cl.pacificMap = true
	g_pacificMapClosedByUser = false
	local tp, fp = {}, {}
	concat( tp, LOGBOOK_TP ) concat( tp, LOGBOOK_RENDERABLES )
	concat( fp, LOGBOOK_FP ) concat( fp, LOGBOOK_RENDERABLES )
	self.tool:setTpRenderables( tp )
	if self.tool:isLocal() then
		self.tool:setFpRenderables( fp )
		g_pacificMapRequest = "open"
	end
	self:cl_loadAnimations()
	setTpAnimation( self.tpAnimations, "pickup", 0.0001 )
	if self.tool:isLocal() then
		swapFpAnimation( self.fpAnimations, "unequip", "equip", 0.2 )
	end
end

local function PatchedLogBookUnequip( self, animate )
	if self.cl and self.cl.pacificMap then
		self.cl.pacificMap = nil
		if self.tool:isLocal() then
			g_pacificMapRequest = "close"
		end
		if sm.exists( self.tool ) and self.tpAnimations then
			setTpAnimation( self.tpAnimations, "useExit" )
			if self.tool:isLocal() and self.fpAnimations and self.fpAnimations.currentAnimation ~= "unequip" and self.fpAnimations.currentAnimation ~= "useExit" then
				swapFpAnimation( self.fpAnimations, "equip", "useExit", 0.2 )
			end
		end
		return
	end
	if not self.fpAnimations then return end
	return g_pacificOriginalLogBookUnequip( self, animate )
end

local function PatchedLogBookEquippedUpdate( self, primaryState, secondaryState )
	if self.cl and self.cl.pacificMap and self.tool:isLocal() then
		-- The map was closed (Esc, the close button): put the logbook away
		if g_pacificMapClosedByUser then
			g_pacificMapClosedByUser = false
			sm.tool.forceTool( nil )
		end
		return true, true
	end
	return g_pacificOriginalLogBookEquippedUpdate( self, primaryState, secondaryState )
end

-- Survival's hideout traders only trade once its "Feed the Farmers" quest is
-- done; in Pacific Scrap they trade as soon as you reach the hideout
local function PatchedTraderActive( self )
	return true
end

-- Respawning (no bed): at the garage exit, facing the station, instead of
-- Survival's nearest spawner. g_pacificRespawn is set by Game.lua once the exit
-- is known.
local function PatchedGetSpawner( self, character )
	local respawn = g_pacificRespawn
	if respawn then
		return respawn.position, respawn.rotation
	end
	return g_pacificOriginalGetSpawner( self, character )
end

-- Beds don't set where you respawn in Pacific Scrap (you always come back at
-- the garage exit): lying down is just lying down, and no saved bed counts
local function PatchedGetPlayerBed( self, player )
	return nil
end
local function PatchedActivateBed( self, character )
end
local function PatchedBedInteract( self, character, state )
	if state == true then
		self:cl_seat()
	end
end

-- Recipes Survival unlocks from the start but Pacific Scrap locks
-- (LOCKED_DEFAULT_RECIPES in upgrade_tree.lua): locked until unlocked at the
-- Fabricator. (Survival's default-unlocked list is a local, so its checks are
-- swapped instead.)
local function PatchedSvIsUnlocked( self, itemId )
	if LOCKED_DEFAULT_RECIPES[itemId] and sm.game.getRecipesEnabled() then
		return self.sv.saved.unlockedRecipes[itemId] == true
	end
	return g_pacificOriginalSvIsUnlocked( self, itemId )
end

local function PatchedClIsUnlocked( self, itemId )
	if LOCKED_DEFAULT_RECIPES[itemId] and sm.game.getRecipesEnabled() then
		return self.cl.unlockedRecipes[itemId] == true
	end
	return g_pacificOriginalClIsUnlocked( self, itemId )
end

-- ...and the Craftbot's recipe grid, which asks for the whole unlocked list
-- (Survival adds its default-unlocked items to it): ours taken back out until
-- unlocked
local function PatchedClGetUnlockedRecipes( self )
	local result = g_pacificOriginalClGetUnlockedRecipes( self )
	if sm.game.getRecipesEnabled() then
		for itemId in pairs( LOCKED_DEFAULT_RECIPES ) do
			if not self.cl.unlockedRecipes[itemId] then
				result[itemId] = nil
			end
		end
	end
	return result
end

-- The hideout shop's counters follow deliveries while it's open
local function PatchedTraderUpdate( self, dt )
	if g_pacificOriginalTraderUpdate then g_pacificOriginalTraderUpdate( self, dt ) end
	HideoutShop_ClientOnUpdate( self, dt )
end

-- Every crate the hideout vacuums in counts for the Roadside Picnic quest
-- (a caged farmer doesn't: the vacuum takes those too)
local CAGED_FARMER_UUID = sm.uuid.new( "8d601982-4608-4d5e-bb9e-e4041486f7c7" )
local function PatchedVacuum( self )
	local container = self.interactable and self.interactable:getContainer( 0 )
	local farmersBefore = container and sm.container.totalQuantity( container, CAGED_FARMER_UUID ) or 0
	local vacuumed = g_pacificOriginalVacuum( self )
	local farmersAfter = container and sm.container.totalQuantity( container, CAGED_FARMER_UUID ) or 0
	if vacuumed and farmersAfter <= farmersBefore then
		sm.event.sendToGame( "sv_e_crateDelivered" )
	end
	return vacuumed
end

-- Survival's scrap engine lets the wheels spin free when nobody is driving (or
-- it's out of gas), so a parked car rolls away. The other gas engines hold the
-- wheels still then; the scrap engine does the same here.
local SCRAP_ENGINE_UUID = "c96ab903-f238-4bae-a614-28a758716d00"
local function PatchedControlEngine( self, direction, active, timeStep, gearIdx )
	g_pacificOriginalControlEngine( self, direction, active, timeStep, gearIdx )
	if not active and self.shape and sm.exists( self.shape ) and tostring( self.shape.uuid ) == SCRAP_ENGINE_UUID then
		-- (as the other engines: still, with twice the gear's power)
		self.motorVelocity = 0
		self.motorImpulse = 2 * self.gears[gearIdx].power
	end
end

-- Seedbots in a zone carry the seeds of its tier (SEEDBOT_SEEDS in
-- layouts.lua) instead of what Survival's progress would pick. Survival picks
-- them before the unit is made, so a new seedbot's pick is replaced as it
-- starts (one that's been saved keeps its seeds).
local function SeedForZone( world )
	local data = world and world.publicData
	if not data or data.type ~= "ZoneWorld" then return nil end
	local weights = SEEDBOT_SEEDS and SEEDBOT_SEEDS[ZoneTierOf( data.depth or 1 ).name]
	if not weights then return nil end
	local total = 0
	for _, weight in pairs( weights ) do total = total + weight end
	local r = math.random() * total
	for seed, weight in pairs( weights ) do
		r = r - weight
		if r <= 0 then return seed end
	end
	return nil
end

local function PatchedSeedbotCreate( self )
	if self.storage:load() == nil then
		local character = self.unit and self.unit.character
		local seed = character and sm.exists( character ) and SeedForZone( character:getWorld() )
		if seed then
			self.params = self.params or {}
			self.params.seedType = seed
		end
	end
	return g_pacificOriginalSeedbotCreate( self )
end

-- The lift's carried creation (picked up with the lift, not placed yet): the
-- lift tool only remembers it on the player's side, so it tells the server
-- (g_liftCarry[player id] = a body of it). Going through a gateway or junction,
-- the game brings it along (Game.sv_prepareCarried / sv_sendCarried), so it's still in hand.
-- (both the game's Lift and Survival's SurvivalLift, a copy of it made when
-- it loads: each keeps its own original, g_pacificLiftOriginals[name])
g_pacificLiftOriginals = g_pacificLiftOriginals or {}
local function LiftOriginal( self, name )
	local originals = g_pacificLiftOriginals[self.pacificLiftClass or "Lift"] or g_pacificLiftOriginals.Lift or {}
	return originals[name]
end

-- (coming through, the lift lets go of it while it's on its way: for a while
-- after changing world, the creation it held is picked back up once it's here)
local LIFT_REPICK_TICKS = 40 * 8

local function PatchedLiftEquippedUpdate( self, primaryState, secondaryState )
	local tick = sm.game.getCurrentTick()
	local changedRecently = self.pacificWorldChangeTick and tick - self.pacificWorldChangeTick < LIFT_REPICK_TICKS
	local held = self.pacificCarryKeep
	if changedRecently and held and ( not self.selectedBodies or #self.selectedBodies == 0 ) then
		local character = sm.localPlayer.getPlayer().character
		if sm.exists( held ) and held:isDynamic() and character and held:getWorld() == character:getWorld() then
			self.selectedBodies = held:getCreationBodies()
			self.selectedBodiesInitTick = tick
			sm.log.info( "[PacificScrap] Lift: picked the carried creation back up after coming through" )
		end
	end
	local a, b = LiftOriginal( self, "equippedUpdate" )( self, primaryState, secondaryState )
	local first = self.selectedBodies and self.selectedBodies[1]
	local carried = first and sm.exists( first ) and first or nil
	-- (what it holds, kept through a world change; let go of for good when the
	-- player places or drops it, away from one)
	if carried then
		self.pacificCarryKeep = carried
	elseif self.pacificCarryKeep and not changedRecently then
		self.pacificCarryKeep = nil
	end
	local key = carried and carried.id or 0
	if key ~= self.pacificSentCarry then
		self.pacificSentCarry = key
		self.network:sendToServer( "sv_n_pacificCarry", carried )
	end
	return a, b
end

local function PatchedLiftUnequip( self )
	LiftOriginal( self, "unequip" )( self )
	-- (taking another tool drops what the lift carried)
	if self.pacificSentCarry and self.pacificSentCarry ~= 0 then
		self.pacificSentCarry = 0
		self.network:sendToServer( "sv_n_pacificCarry", nil )
	end
end

local function PatchedLiftChangedWorld( self, world )
	LiftOriginal( self, "changedWorld" )( self, world )
	self.pacificWorldChangeTick = sm.game.getCurrentTick()
end

local function LiftSvCarry( self, body, player )
	g_liftCarry = g_liftCarry or {}
	g_liftCarry[player.id] = body
end

-- The builder quest pad in the garage (survival's watchtower platform, placed
-- in Terrain/Tiles/garage.tile) builds the garage antenna instead of Hubert's
-- watchtower: the guide of whichever antenna quest is active (BuilderGuides/,
-- made by make_antenna.py). When it's done the pad becomes that antenna,
-- locked, and tells the game. When Boost the Signal starts, the old antenna
-- comes down (an explosion) and a bare pad takes its place for the new one.
-- Any other builder pad works as survival's.
ANTENNA_PAD_UUID = "c3065683-98ff-4ef6-9862-ed0443ec71c2"
ANTENNA_QUEST = "quest_story_antenna"
ANTENNA2_QUEST = "quest_story_antenna2"
-- Each antenna quest's guide, and the level its antenna counts as
ANTENNA_GUIDES = {
	[ANTENNA_QUEST] = "$CONTENT_DATA/BuilderGuides/antenna_lv1_guide.json",
	[ANTENNA2_QUEST] = "$CONTENT_DATA/BuilderGuides/antenna_lv2_guide.json",
}
-- (a guide's colours mark its build stages; the finished antenna has its own)
local ANTENNA_COMPLETES = {
	[ANTENNA_QUEST] = "$CONTENT_DATA/BuilderGuides/antenna_lv1_complete.json",
	[ANTENNA2_QUEST] = "$CONTENT_DATA/BuilderGuides/antenna_lv2_complete.json",
}
local ANTENNA_LEVELS = { [ANTENNA_QUEST] = 1, [ANTENNA2_QUEST] = 2 }
local ANTENNA_PAD_ONLY = "$CONTENT_DATA/BuilderGuides/antenna_pad.json"
local ANTENNA_TEARDOWN_EFFECT = "PropaneTank - ExplosionBig"

local function IsAntennaPad( self )
	return self.shape and sm.exists( self.shape ) and tostring( self.shape.uuid ) == ANTENNA_PAD_UUID
end

-- The antenna quest that's active (the newer one first), and its guide
local function ActiveAntennaQuest( server )
	for _, name in ipairs( { ANTENNA2_QUEST, ANTENNA_QUEST } ) do
		local active
		if server then active = QuestManager.Sv_IsQuestActive( name ) else active = QuestManager.Cl_IsQuestActive( name ) end
		if active then return name, ANTENNA_GUIDES[name] end
	end
	return nil, nil
end

-- What's standing on the pad: 0 = nothing finished, else the antenna's level
-- (antennas finished before there were levels count as 1)
local function PadAntennaLevel( self )
	if not self.sv.saved.complete then return 0 end
	return ( self.params and self.params.antennaLevel ) or 1
end

-- Puts a blueprint where the pad is (as survival's sv_replace does) and takes
-- the old creation away; level: the finished antenna's level, or nil for a
-- bare pad to build on
local function ReplacePad( self, blueprint, level )
	local world = self.shape.body:getWorld()
	local rotation = self.shape:getWorldRotation()
	local position = self.shape:getWorldPosition() - rotation * ( self.shape:getBoundingBox() / 2 )
	local creation = sm.creation.importFromFile( world, blueprint, position, rotation )
	for _, body in ipairs( creation ) do
		for _, shape in ipairs( body:getShapes() ) do
			if tostring( shape.uuid ) == ANTENNA_PAD_UUID then
				shape:getInteractable():setParams( { complete = level ~= nil, antennaLevel = level } )
			end
		end
		if level then
			body:setErasable( false )
			body:setBuildable( false )
			body:setDestructable( false )
		end
	end
	self.shape:getBody():destroyCreation()
end

local function PatchedPadServerUpdate( self )
	if not IsAntennaPad( self ) then
		return g_pacificOriginalPadServerUpdate( self )
	end
	local questName = ActiveAntennaQuest( true )
	if not questName then
		return
	end
	-- An older antenna on the pad and a newer one to build: it comes down
	local standing = PadAntennaLevel( self )
	if standing > 0 then
		if standing < ANTENNA_LEVELS[questName] and not self.sv.tornDown then
			self.sv.tornDown = true
			sm.effect.playEffect( ANTENNA_TEARDOWN_EFFECT, self.shape.worldPosition + sm.vec3.new( 0, 0, 4 ) )
			sm.event.sendToGame( "sv_e_antennaTornDown" )
			ReplacePad( self, ANTENNA_PAD_ONLY, nil )
		end
		return
	end
	local bodies = sm.body.getCreationBodies( self.shape:getBody() )
	if #bodies ~= self.sv.lastBodyCount or self.shape:getBody():getId() ~= self.sv.lastBodyId or self.sv.guideQuest ~= questName then
		self:sv_checkBuilderGuide()
		self.sv.lastBodyCount = #bodies
	else
		for _, body in ipairs( bodies ) do
			if body:hasChanged( self.sv.rebuildTick ) then
				self:sv_checkBuilderGuide()
				self.sv.lastBodyCount = #bodies
				break
			end
		end
	end
end

local function PatchedPadCheckGuide( self )
	if not IsAntennaPad( self ) then
		return g_pacificOriginalPadCheckGuide( self )
	end
	local questName, guide = ActiveAntennaQuest( true )
	if not questName then
		return
	end
	-- (a new body, or the other antenna's guide: started again)
	if ( self.shape:getBody():getId() ~= self.sv.lastBodyId or self.sv.guideQuest ~= questName ) and self.sv.builderGuide then
		self.sv.builderGuide:destroy()
		self.sv.builderGuide = nil
	end
	self.sv.lastBodyId = self.shape:getBody():getId()
	self.sv.guideQuest = questName
	if self.sv.builderGuide == nil then
		self.sv.builderGuide = sm.builderGuide.createBuilderGuide( guide, self.shape, false, false, false )
	end
	self.sv.builderGuide:update()
	self.sv.rebuildTick = sm.game.getCurrentTick()
	if self.sv.builderGuide:isComplete() then
		local level = ANTENNA_LEVELS[questName]
		sm.effect.playEffect( self.data.platformBuildCompleteEffect or "BuilderguideQuest - Buildcomplete", self.shape.worldPosition, nil, self.shape.worldRotation )
		sm.event.sendToGame( "sv_e_antennaBuilt", { level = level } )
		ReplacePad( self, ANTENNA_COMPLETES[questName], level ) -- (the finished antenna, locked in place)
	else
		self.network:setClientData( { active = true } ) -- (start the ghost on clients)
	end
end

local function PatchedPadClientUpdate( self )
	if not IsAntennaPad( self ) then
		return g_pacificOriginalPadClientUpdate( self )
	end
	g_antennaPadShape = self.shape -- (for the info panel beside it)
	local questName = ActiveAntennaQuest( false )
	if questName and self.cl.active then
		if not self.cl.backgroundEffect:isPlaying() then
			sm.effect.playHostedEffect( self.data.platformActiveEffect or "BuilderguideQuest - Active", self.interactable )
			self.cl.backgroundEffect:start()
		end
		local bodies = sm.body.getCreationBodies( self.shape:getBody() )
		if #bodies ~= self.cl.lastBodyCount or self.shape:getBody():getId() ~= self.cl.lastBodyId or self.cl.guideQuest ~= questName then
			self:cl_rebuildVisualization()
			self.cl.lastBodyCount = #bodies
		else
			for _, body in ipairs( bodies ) do
				if body:hasChanged( self.cl.rebuildTick ) then
					self:cl_rebuildVisualization()
					self.cl.lastBodyCount = #bodies
					break
				end
			end
		end
	else
		if self.cl.backgroundEffect:isPlaying() then
			self.cl.backgroundEffect:stop()
		end
		if self.cl.builderGuideVis then
			self.cl.builderGuideVis:destroy()
			self.cl.builderGuideVis = nil
		end
	end
end

local function PatchedPadVisualization( self )
	if not IsAntennaPad( self ) then
		return g_pacificOriginalPadVisualization( self )
	end
	local questName, guide = ActiveAntennaQuest( false )
	if not questName then
		return
	end
	if ( self.shape:getBody():getId() ~= self.cl.lastBodyId or self.cl.guideQuest ~= questName ) and self.cl.builderGuideVis then
		self.cl.builderGuideVis:destroy()
		self.cl.builderGuideVis = nil
	end
	if self.cl.builderGuideVis then
		self.cl.builderGuideVis:updateBuilderGuide()
	else
		self.cl.lastBodyId = self.shape:getBody():getId()
		self.cl.guideQuest = questName
		self.cl.builderGuideVis = sm.visualization.createBuilderGuide( guide, self.shape, false,
			self.data.stageCompleteEffect or "Builderguide - Stagecomplete",
			self.data.platformStageCompleteEffect or "BuilderguideQuest - StageComplete" )
	end
	self.cl.rebuildTick = sm.game.getCurrentTick()
end

-- The info panel beside the pad (in garage.tile) lists the parts the guide
-- still needs. Survival's only works for Hubert's watchtower quest, so the
-- panel near the antenna pad shows the active antenna guide instead.
-- (the pad notes itself here on clients: PatchedPadClientUpdate)
local ANTENNA_PANEL_RANGE = 40 -- metres from the pad
local function IsAntennaPanel( self )
	local pad = g_antennaPadShape
	return pad and sm.exists( pad ) and self.harvestable and sm.exists( self.harvestable )
		and ( self.harvestable.worldPosition - pad.worldPosition ):length() < ANTENNA_PANEL_RANGE
end

local function PatchedPanelCanInteract( self )
	if not IsAntennaPanel( self ) then
		return g_pacificOriginalPanelCanInteract( self )
	end
	if not ActiveAntennaQuest( false ) then
		return false
	end
	sm.gui.setInteractionText( "", sm.gui.getKeyBinding( "Use", true ), "#{INTERACTION_USE}" )
	return true
end

local function PatchedPanelInteract( self, character, state )
	if not IsAntennaPanel( self ) then
		return g_pacificOriginalPanelInteract( self, character, state )
	end
	local questName, guide = ActiveAntennaQuest( false )
	if state and questName then
		-- (cl_showGui reads these: the guide, and the pad's body for what's built already)
		self.cl.blueprintPath = guide
		self.cl.platformBodyId = g_antennaPadShape.body.id
		self:cl_showGui()
	end
end

-- Survival's hideout trader adds the "Hideout" logbook entry (with a
-- waypoint) when you come near; Pacific Scrap doesn't use the logbook for it
local function PatchedAddLog( uuid, skipNotification )
	if LOGS and LOGS.log_hideout and uuid == LOGS.log_hideout then
		return
	end
	return g_pacificOriginalAddLog( uuid, skipNotification )
end

function ApplySurvivalPatches()
	g_disableRaids = true -- survival's crop raids are off in Pacific Scrap
	if Refinery and Refinery.sv_e_receiveItem ~= RefinerySvReceiveItem then
		Refinery.sv_canFitCraftedItem = RefinerySvCanFitCraftedItem
		Refinery.server_onFixedUpdate = RefineryServerOnFixedUpdate
		Refinery.sv_e_receiveItem = RefinerySvReceiveItem
	end
	if RenderSettingsManager and RenderSettingsManager.cl_mixRenderSettings ~= PatchedMixRenderSettings then
		if RenderSettingsManager.cl_mixRenderSettings ~= g_pacificPatchedMixRenderSettings then
			g_pacificOriginalMixRenderSettings = RenderSettingsManager.cl_mixRenderSettings
		end
		RenderSettingsManager.cl_mixRenderSettings = PatchedMixRenderSettings
		g_pacificPatchedMixRenderSettings = PatchedMixRenderSettings
	end
	if WeatherManager and WeatherManager.client_onUpdate ~= PatchedWeatherUpdate then
		if WeatherManager.client_onUpdate ~= g_pacificPatchedWeatherUpdate then
			g_pacificOriginalWeatherUpdate = WeatherManager.client_onUpdate
		end
		WeatherManager.client_onUpdate = PatchedWeatherUpdate
		g_pacificPatchedWeatherUpdate = PatchedWeatherUpdate
	end
	if LogEntryManager and LogEntryManager.Sv_AddLog ~= PatchedAddLog then
		if LogEntryManager.Sv_AddLog ~= g_pacificPatchedAddLog then
			g_pacificOriginalAddLog = LogEntryManager.Sv_AddLog
		end
		LogEntryManager.Sv_AddLog = PatchedAddLog
		g_pacificPatchedAddLog = PatchedAddLog
	end
	if HideoutTrader and HideoutTrader.cl_isTraderActive ~= PatchedTraderActive then
		HideoutTrader.cl_isTraderActive = PatchedTraderActive
	end
	-- The hideout's shop (hideout_shop.lua) in place of its menu and unlocks
	if HideoutTrader and HideoutShop and HideoutTrader.cl_shopOpen ~= HideoutShop.cl_shopOpen then
		for name, fn in pairs( HideoutShop ) do
			HideoutTrader[name] = fn
		end
		if HideoutTrader.client_onUpdate ~= g_pacificPatchedTraderUpdate then
			g_pacificOriginalTraderUpdate = HideoutTrader.client_onUpdate
		end
		HideoutTrader.client_onUpdate = PatchedTraderUpdate
		g_pacificPatchedTraderUpdate = PatchedTraderUpdate
		if HideoutTrader.sv_vacuumObject ~= g_pacificPatchedVacuum then
			g_pacificOriginalVacuum = HideoutTrader.sv_vacuumObject
		end
		HideoutTrader.sv_vacuumObject = PatchedVacuum
		g_pacificPatchedVacuum = PatchedVacuum
	end
	if LogBook and LogBook.client_onEquip ~= PatchedLogBookEquip then
		if LogBook.client_onEquip ~= g_pacificPatchedLogBookEquip then
			g_pacificOriginalLogBookEquip = LogBook.client_onEquip
			g_pacificOriginalLogBookUnequip = LogBook.client_onUnequip
			g_pacificOriginalLogBookEquippedUpdate = LogBook.client_onEquippedUpdate
		end
		LogBook.client_onEquip = PatchedLogBookEquip
		LogBook.client_onUnequip = PatchedLogBookUnequip
		LogBook.client_onEquippedUpdate = PatchedLogBookEquippedUpdate
		g_pacificPatchedLogBookEquip = PatchedLogBookEquip
	end
	if RecipeManager and RecipeManager.sv_isUnlocked ~= PatchedSvIsUnlocked then
		if RecipeManager.sv_isUnlocked ~= g_pacificPatchedSvIsUnlocked then
			g_pacificOriginalSvIsUnlocked = RecipeManager.sv_isUnlocked
			g_pacificOriginalClIsUnlocked = RecipeManager.cl_isUnlocked
			g_pacificOriginalClGetUnlockedRecipes = RecipeManager.cl_getUnlockedRecipes
		end
		RecipeManager.sv_isUnlocked = PatchedSvIsUnlocked
		RecipeManager.cl_isUnlocked = PatchedClIsUnlocked
		RecipeManager.cl_getUnlockedRecipes = PatchedClGetUnlockedRecipes
		g_pacificPatchedSvIsUnlocked = PatchedSvIsUnlocked
	end
	-- (the recipe manager objects may hold their own copies of the functions:
	-- patched on them too, server's and client's)
	if g_recipeManager and g_recipeManager.sv_isUnlocked ~= PatchedSvIsUnlocked then
		g_recipeManager.sv_isUnlocked = PatchedSvIsUnlocked
	end
	if g_recipeManagerClient and g_recipeManagerClient.cl_getUnlockedRecipes ~= PatchedClGetUnlockedRecipes then
		g_recipeManagerClient.cl_isUnlocked = PatchedClIsUnlocked
		g_recipeManagerClient.cl_getUnlockedRecipes = PatchedClGetUnlockedRecipes
	end
	-- ...and the static functions the Craftbot and others call
	if RecipeManager and RecipeManager.Cl_GetUnlockedRecipes ~= g_pacificPatchedClGetUnlocked then
		local originalGet = RecipeManager.Cl_GetUnlockedRecipes
		local originalCl = RecipeManager.Cl_IsUnlocked
		local originalSv = RecipeManager.Sv_IsUnlocked
		g_pacificPatchedClGetUnlocked = function()
			local result = originalGet()
			local unlocked = g_recipeManagerClient and g_recipeManagerClient.cl and g_recipeManagerClient.cl.unlockedRecipes or {}
			if sm.game.getRecipesEnabled() then
				for itemId in pairs( LOCKED_DEFAULT_RECIPES ) do
					if not unlocked[itemId] then result[itemId] = nil end
				end
			end
			return result
		end
		RecipeManager.Cl_GetUnlockedRecipes = g_pacificPatchedClGetUnlocked
		RecipeManager.Cl_IsUnlocked = function( itemId )
			if LOCKED_DEFAULT_RECIPES[itemId] and sm.game.getRecipesEnabled() then
				local unlocked = g_recipeManagerClient and g_recipeManagerClient.cl and g_recipeManagerClient.cl.unlockedRecipes or {}
				return unlocked[itemId] == true
			end
			return originalCl( itemId )
		end
		RecipeManager.Sv_IsUnlocked = function( itemId )
			if LOCKED_DEFAULT_RECIPES[itemId] and sm.game.getRecipesEnabled() then
				local unlocked = g_recipeManager and g_recipeManager.sv and g_recipeManager.sv.saved.unlockedRecipes or {}
				return unlocked[itemId] == true
			end
			return originalSv( itemId )
		end
	end
	if RespawnManager and RespawnManager.sv_getSpawner ~= PatchedGetSpawner then
		if RespawnManager.sv_getSpawner ~= g_pacificPatchedGetSpawner then
			g_pacificOriginalGetSpawner = RespawnManager.sv_getSpawner
		end
		RespawnManager.sv_getSpawner = PatchedGetSpawner
		g_pacificPatchedGetSpawner = PatchedGetSpawner
	end
	if GasEngine and GasEngine.controlEngine ~= PatchedControlEngine then
		if GasEngine.controlEngine ~= g_pacificPatchedControlEngine then
			g_pacificOriginalControlEngine = GasEngine.controlEngine
		end
		GasEngine.controlEngine = PatchedControlEngine
		g_pacificPatchedControlEngine = PatchedControlEngine
	end
	for name, class in pairs( { Lift = Lift, SurvivalLift = SurvivalLift } ) do
		if class and class.client_onEquippedUpdate ~= PatchedLiftEquippedUpdate then
			if class.client_onEquippedUpdate ~= g_pacificPatchedLiftEquippedUpdate then
				g_pacificLiftOriginals[name] = { equippedUpdate = class.client_onEquippedUpdate, unequip = class.client_onUnequip,
					changedWorld = class.client_onLocalPlayerChangedWorld }
			end
			class.client_onEquippedUpdate = PatchedLiftEquippedUpdate
			class.client_onUnequip = PatchedLiftUnequip
			class.client_onLocalPlayerChangedWorld = PatchedLiftChangedWorld
			class.sv_n_pacificCarry = LiftSvCarry
			class.pacificLiftClass = name
			g_pacificPatchedLiftEquippedUpdate = PatchedLiftEquippedUpdate
		end
	end
	if SeedbotUnit and SeedbotUnit.server_onCreate ~= PatchedSeedbotCreate then
		if SeedbotUnit.server_onCreate ~= g_pacificPatchedSeedbotCreate then
			g_pacificOriginalSeedbotCreate = SeedbotUnit.server_onCreate
		end
		SeedbotUnit.server_onCreate = PatchedSeedbotCreate
		g_pacificPatchedSeedbotCreate = PatchedSeedbotCreate
	end
	if RespawnManager and RespawnManager.sv_getPlayerBed ~= PatchedGetPlayerBed then
		RespawnManager.sv_getPlayerBed = PatchedGetPlayerBed
	end
	if Bed and Bed.sv_activateBed ~= PatchedActivateBed then
		Bed.sv_activateBed = PatchedActivateBed
		Bed.client_onInteract = PatchedBedInteract
	end
	if CarryTool and CarryTool.cl_tryInsert ~= PatchedTryInsert then
		-- Keep the original unless what's there is our own earlier patch
		if CarryTool.cl_tryInsert ~= g_pacificPatchedTryInsert then
			g_pacificOriginalTryInsert = CarryTool.cl_tryInsert
		end
		CarryTool.cl_tryInsert = PatchedTryInsert
		g_pacificPatchedTryInsert = PatchedTryInsert
	end
	-- The garage's builder pad builds the antenna (see PatchedPadServerUpdate)
	if BuilderGuidePlatform and BuilderGuidePlatform.server_onFixedUpdate ~= PatchedPadServerUpdate then
		-- (keep each original unless what's there is our own earlier patch)
		if BuilderGuidePlatform.server_onFixedUpdate ~= g_pacificPatchedPadServerUpdate then
			g_pacificOriginalPadServerUpdate = BuilderGuidePlatform.server_onFixedUpdate
		end
		if BuilderGuidePlatform.sv_checkBuilderGuide ~= g_pacificPatchedPadCheckGuide then
			g_pacificOriginalPadCheckGuide = BuilderGuidePlatform.sv_checkBuilderGuide
		end
		if BuilderGuidePlatform.client_onFixedUpdate ~= g_pacificPatchedPadClientUpdate then
			g_pacificOriginalPadClientUpdate = BuilderGuidePlatform.client_onFixedUpdate
		end
		if BuilderGuidePlatform.cl_rebuildVisualization ~= g_pacificPatchedPadVisualization then
			g_pacificOriginalPadVisualization = BuilderGuidePlatform.cl_rebuildVisualization
		end
		BuilderGuidePlatform.server_onFixedUpdate = PatchedPadServerUpdate
		BuilderGuidePlatform.sv_checkBuilderGuide = PatchedPadCheckGuide
		BuilderGuidePlatform.client_onFixedUpdate = PatchedPadClientUpdate
		BuilderGuidePlatform.cl_rebuildVisualization = PatchedPadVisualization
		g_pacificPatchedPadServerUpdate = PatchedPadServerUpdate
		g_pacificPatchedPadCheckGuide = PatchedPadCheckGuide
		g_pacificPatchedPadClientUpdate = PatchedPadClientUpdate
		g_pacificPatchedPadVisualization = PatchedPadVisualization
	end
	-- ...and the info panel beside it lists the antenna's parts
	if BuilderGuideInfoPanel and BuilderGuideInfoPanel.client_canInteract ~= PatchedPanelCanInteract then
		if BuilderGuideInfoPanel.client_canInteract ~= g_pacificPatchedPanelCanInteract then
			g_pacificOriginalPanelCanInteract = BuilderGuideInfoPanel.client_canInteract
			g_pacificOriginalPanelInteract = BuilderGuideInfoPanel.client_onInteract
		end
		BuilderGuideInfoPanel.client_canInteract = PatchedPanelCanInteract
		BuilderGuideInfoPanel.client_onInteract = PatchedPanelInteract
		g_pacificPatchedPanelCanInteract = PatchedPanelCanInteract
	end
end

ApplySurvivalPatches()
