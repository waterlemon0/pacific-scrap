-- The farmer at the Farmers' Hideout you talk to (Characters/Database/
-- CharacterSets/example.characterset). Survival's builder farmers (the ones
-- by the builder quest pads) already greet you, follow you with their eyes and
-- act out a conversation, so this is one of them, minus the builder quest:
-- talking to him tells the game (Game.sv_e_hideoutFarmerTalk, Story.lua),
-- which picks what he says. ZoneWorld.sv_keepHideoutFarmer puts him there, and
-- tells him when to hold out the key to the Mid Zone (like Hubert holds out his
-- keys: the item glowing in his right hand; Use takes it).

dofile( "$SURVIVAL_DATA/Scripts/game/characters/GenericBuilderQuestCharacter.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/units/GenericBuilderQuestUnit.lua" )

HIDEOUT_FARMER_UUID = "e7342b5f-ed16-4adc-9f04-69b90aceff2b"

-- Character ----------------------------------------------------------------------

HideoutFarmerCharacter = class( GenericBuilderQuestCharacter )

-- (no builder quest: nothing to look up)
function HideoutFarmerCharacter.server_onCreate( self )
	self.sv = {}
end

function HideoutFarmerCharacter.server_onFixedUpdate( self )
end

-- The key he holds out (survival's keycard, Story.lua MID_ZONE_KEY) and where
-- (survival's quest characters hold items there, BaseQuestActorCharacter)
local KEY_UUID = sm.uuid.new( "e49b210a-0d46-4f06-bcd8-08862379d156" )
local HELD_ITEM_OFFSET = sm.vec3.new( 0.2, 0, -0.5 )

-- The world says whether he's holding out the key
function HideoutFarmerCharacter.sv_e_setGive( self, params )
	self.network:setClientData( { give = params.give == true } )
end

function HideoutFarmerCharacter.client_onClientDataUpdate( self, data )
	self.cl.give = data and data.give == true
	self:cl_updateGive()
end

function HideoutFarmerCharacter.client_onGraphicsLoaded( self )
	GenericBuilderQuestCharacter.client_onGraphicsLoaded( self )
	self:cl_updateGive()
end

function HideoutFarmerCharacter.client_onDestroy( self )
	GenericBuilderQuestCharacter.client_onDestroy( self )
	if self.cl.giveEffect and sm.exists( self.cl.giveEffect ) then
		self.cl.giveEffect:destroy()
	end
end

-- Holding out the key: survival's quest-item glow with the key in his hand,
-- and his reward gesture
function HideoutFarmerCharacter.cl_updateGive( self )
	local holding = self.cl.giveEffect and sm.exists( self.cl.giveEffect )
	if self.cl.give and self.cl.graphicsLoaded and not holding then
		self.cl.giveEffect = sm.effect.createEffect( "Questeffects - Quest_lootitem", self.character, "jnt_right_hand" )
		self.cl.giveEffect:setOffsetPosition( HELD_ITEM_OFFSET )
		self.cl.giveEffect:setOffsetRotation( sm.quat.fromEuler( sm.vec3.new( 0, 180, 0 ) ) )
		self.cl.giveEffect:setParameter( "uuid", KEY_UUID )
		local bounds = sm.item.getShapeSize( KEY_UUID )
		local scale = bounds and sm.construction.constants.subdivideRatio / ( ( bounds.x + bounds.y + bounds.z ) / 3.0 ) or 1.0
		self.cl.giveEffect:setScale( sm.vec3.new( scale, scale, scale ) )
		self.cl.giveEffect:start()
		self:cl_setCurrentAnimation( "reward" )
	elseif not self.cl.give and holding then
		self.cl.giveEffect:destroy()
		self.cl.giveEffect = nil
	end
end

function HideoutFarmerCharacter.client_canInteract( self )
	if DialogManager.Cl_IsRunning() then
		return false
	end
	sm.gui.setInteractionText( "", sm.gui.getKeyBinding( "Use", true ), self.cl.give and "#{INTERACTION_PICK_UP}" or "#{INTERACTION_TALK}" )
	return true
end

-- Pressed Use on him (GenericBuilderQuestCharacter.client_onInteract sends this)
function HideoutFarmerCharacter.sv_n_talk( self, _, player )
	sm.event.sendToGame( "sv_e_hideoutFarmerTalk", { unit = self.character:getUnit(), player = player } )
end

-- Unit (stands still, faces the nearest player) -----------------------------------

HideoutFarmerUnit = class( GenericBuilderQuestUnit )

local TARGET_DISTANCE = 12
local UNTARGET_DISTANCE = 16

function HideoutFarmerUnit.server_onCreate( self )
	-- (the world finds him by this: ZoneWorld.sv_keepHideoutFarmer)
	g_hideoutFarmers = g_hideoutFarmers or {}
	g_hideoutFarmers[self.unit.id] = self.unit
	self.idleState = self.unit:createState( "idle" )
	self.idleState.debugName = "idleState"
	self.currentState = self.idleState
	self.currentState:start()
	self.target = nil
	self.switchTargetCooldown = 0
end

function HideoutFarmerUnit.server_onDestroy( self )
	if g_hideoutFarmers then g_hideoutFarmers[self.unit.id] = nil end
end

function HideoutFarmerUnit.server_onFixedUpdate( self, dt )
	self.switchTargetCooldown = math.max( self.switchTargetCooldown - 1, 0 )
	if not self.currentState then
		return
	end
	self.currentState:onFixedUpdate( dt )
	local closest = GetClosestPlayer( self.unit.character.worldPosition, nil, self.unit.character:getWorld() )
	if closest and closest.character and sm.exists( closest.character ) then
		local distance = sm.vec3.getDistance( closest.character.worldPosition, self.unit.character.worldPosition )
		if distance <= TARGET_DISTANCE then
			if self.target ~= closest and self.switchTargetCooldown == 0 then
				self.target = closest
				self:sv_updateCharacterTarget()
				self.switchTargetCooldown = 80
			end
		elseif distance >= UNTARGET_DISTANCE and self.target ~= nil then
			self.target = nil
			self:sv_updateCharacterTarget()
		end
	end
	if self.target and sm.exists( self.target ) and self.target.character then
		local facing = ( self.target.character.worldPosition - self.unit.character.worldPosition ):safeNormalize( self.currentState:getFacingDirection() )
		self.unit:setFacingDirection( facing )
	end
end
