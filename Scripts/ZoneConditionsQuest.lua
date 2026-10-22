dofile( "$SURVIVAL_DATA/Scripts/game/managers/QuestManager.lua" )

-- Side quest entry shown while in the zone, listing the junction's conditions.
-- The game publishes the text in g_zoneConditionsText (see conditions.lua).
ZoneConditionsQuest = class()
ZoneConditionsQuest.isSaveObject = true

function ZoneConditionsQuest.server_onCreate( self )
	self.sv = { text = nil }
end

function ZoneConditionsQuest.server_onFixedUpdate( self )
	local text = g_zoneConditionsText or ""
	if text ~= self.sv.text then
		self.sv.text = text
		self.network:setClientData( { text = text } )
	end
end

function ZoneConditionsQuest.client_onCreate( self )
	QuestManager.Cl_OnQuestCreated( "quest_zone_conditions" )
	self.cl = {}
	self.scriptableObject.clientPublicData = {}
	self.scriptableObject.clientPublicData.progressString = ""
end

-- Abandoned quests don't leave the on-screen tracker by themselves
function ZoneConditionsQuest.client_onDestroy( self )
	QuestManager.Cl_UntrackQuest( "quest_zone_conditions" )
end

function ZoneConditionsQuest.client_onClientDataUpdate( self, data )
	self.scriptableObject.clientPublicData.progressString = data.text or ""
	QuestManager.Cl_UpdateQuestTracker()
end
