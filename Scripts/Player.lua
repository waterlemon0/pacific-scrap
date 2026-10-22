dofile( "$SURVIVAL_DATA/Scripts/game/SurvivalPlayer.lua" )
dofile( "$CONTENT_DATA/Scripts/layouts.lua" )

-- Survival player (health, food, water, inventory). BasePlayer provides the
-- fade-to-black helpers (sv_startFadeToBlack / sv_endFadeToBlack) the run uses.
Player = class( SurvivalPlayer )

local SURVIVAL_LIFT = sm.uuid.new( "8f190ce2-3a59-423e-8483-a7aa67bd5bc0" )
local MAX_LIFT_DISTANCE = 128.0


-- Lift blueprints ---------------------------------------------------------------
-- The survival lift has no blueprint browser. With lift blueprints on
-- (LIFT_BLUEPRINTS, or /liftblueprints for a save: g_liftBlueprints, the
-- client's copy g_liftBlueprintsClient, Game.lua), holding the lift and
-- pressing E opens the game's Scrap Garage picker, and the chosen creation is
-- loaded onto your placed lift (free of charge).

function Player.client_onInteract( self, character, state )
	SurvivalPlayer.client_onInteract( self, character, state )
	if not g_liftBlueprintsClient or not state or self.player ~= sm.localPlayer.getPlayer() then
		return
	end
	if sm.gui.hasActiveGui() or sm.localPlayer.getActiveItem() ~= SURVIVAL_LIFT then
		return
	end
	if character and sm.exists( character ) and character:getLockingInteractable() then
		return
	end

	local lift = sm.localPlayer.getOwnedLift()
	if not lift then
		sm.gui.chatMessage( "Place your lift first, then hold it and press E to load a blueprint onto it." )
		return
	end
	if lift:hasBodies() then
		sm.gui.chatMessage( "Clear your lift first." )
		return
	end

	pcall( sm.gui.setGarageImportGuiStorage, { sm.localPlayer.getInventory() } )
	sm.gui.openGarageImportGui()
	sm.gui.setGarageButtonCallback( "cl_onBlueprintPicked" )
	sm.gui.setGarageErrorCallback( "cl_onBlueprintError" )
end

function Player.cl_onBlueprintError( self, message )
	sm.gui.chatMessage( "Couldn't load blueprint: " .. tostring( message ) )
end

function Player.cl_onBlueprintPicked( self, path, name )
	local lift = sm.localPlayer.getOwnedLift()
	if not lift or lift:hasBodies() then
		sm.gui.chatMessage( "Your lift has to be placed and empty." )
		return
	end

	-- Lift positions are in quarter-block grid units
	local p = lift.worldPosition
	local request = {
		name = tostring( name or "creation" ),
		liftPosition = sm.vec3.new( math.floor( p.x * 4 + 0.5 ), math.floor( p.y * 4 + 0.5 ), math.floor( p.z * 4 + 0.5 ) ),
		liftLevel = math.max( 0, math.floor( lift.level or 0 ) )
	}
	if sm.isHost then
		-- The host shares the blueprint folder with the server
		request.path = path
	else
		local ok, blueprint = pcall( sm.json.open, path )
		local encoded, json = false, nil
		if ok and type( blueprint ) == "table" then
			encoded, json = pcall( sm.json.writeJsonString, blueprint, false )
		end
		if not encoded then
			sm.gui.chatMessage( "Couldn't read that blueprint." )
			return
		end
		request.blueprintJson = json
	end
	self.network:sendToServer( "sv_n_loadBlueprintOnLift", request )
end

function Player.sv_n_loadBlueprintOnLift( self, request, sender )
	if not g_liftBlueprints or sender ~= self.player then
		return
	end
	local character = self.player.character
	if not character or not sm.exists( character ) then
		return
	end

	local liftWorldPosition = request.liftPosition * 0.25
	if ( liftWorldPosition - character.worldPosition ):length() > MAX_LIFT_DISTANCE then
		self.network:sendToClient( self.player, "cl_n_blueprintResult", "Your lift is too far away." )
		return
	end

	local blueprint
	if request.path and self.player.id == 1 then
		local ok, opened = pcall( sm.json.open, request.path )
		blueprint = ok and opened or nil
	elseif request.blueprintJson then
		local ok, parsed = pcall( sm.json.parseJsonString, request.blueprintJson )
		blueprint = ok and parsed or nil
	end
	if type( blueprint ) ~= "table" or type( blueprint.bodies ) ~= "table" or #blueprint.bodies == 0 then
		self.network:sendToClient( self.player, "cl_n_blueprintResult", "That blueprint couldn't be read." )
		return
	end

	-- Lifts only take dynamic, fully editable bodies; creative blueprints often
	-- leave these out, which would import the creation as static
	for _, body in ipairs( blueprint.bodies ) do
		body.type = 0
		body.buildable, body.connectable, body.convertableToDynamic = true, true, true
		body.destructable, body.erasable, body.liftable = true, true, true
		body.paintable, body.usable, body.restricted = true, true, false
	end

	local message = "That creation couldn't be placed on the lift."
	local encoded, json = pcall( sm.json.writeJsonString, blueprint, false )
	if encoded then
		local imported, bodies = pcall( sm.creation.importFromString, character:getWorld(), json, liftWorldPosition, sm.quat.identity(), false, false )
		if imported and type( bodies ) == "table" and #bodies > 0 then
			local placed = pcall( sm.player.placeLift, self.player, bodies, request.liftPosition, request.liftLevel, 0 )
			if placed then
				message = "Loaded " .. request.name .. " onto your lift."
			elseif sm.exists( bodies[1] ) then
				bodies[1]:destroyCreation()
			end
		end
	end
	self.network:sendToClient( self.player, "cl_n_blueprintResult", message )
end

function Player.cl_n_blueprintResult( self, message )
	sm.gui.chatMessage( message )
end
