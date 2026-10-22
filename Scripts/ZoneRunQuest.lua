dofile( "$SURVIVAL_DATA/Scripts/game/managers/QuestManager.lua" )

-- Quest tracker entry for the run loop. The game script owns the actual state
-- and publishes it in g_zoneRunStage; this object just mirrors it to the HUD.
ZoneRunQuest = class()
ZoneRunQuest.isSaveObject = true

local StageText = {
	garage = "Drive into junction to depart to the zone",
	zone = "Power the ARC Device with energy anchors to open a gateway home, or take a junction deeper",
	gateway = "Drive into the yellow gateway to exit the zone",
	storm = "The zone is collapsing! Open a gateway or take a junction",
	stormGateway = "The zone is collapsing! Reach the yellow gateway before the storm does",
}

function ZoneRunQuest.server_onCreate( self )
	self.sv = { stage = nil }
end

function ZoneRunQuest.server_onFixedUpdate( self )
	local stage = g_zoneRunStage or "garage"
	if stage ~= self.sv.stage then
		self.sv.stage = stage
		self.network:setClientData( { stage = stage } )
	end
end

function ZoneRunQuest.client_onCreate( self )
	QuestManager.Cl_OnQuestCreated( "quest_zone_run" )
	self.cl = {}
	self.scriptableObject.clientPublicData = {}
	self.scriptableObject.clientPublicData.progressString = ""
end

function ZoneRunQuest.client_onClientDataUpdate( self, data )
	self.scriptableObject.clientPublicData.progressString = StageText[data.stage] or ""
	QuestManager.Cl_UpdateQuestTracker()
end
