dofile( "$SURVIVAL_DATA/Scripts/game/managers/QuestManager.lua" )

-- Side quest shown while in the zone. The zone world tracks the anchors and
-- publishes how many are left in g_zoneAnchorsLeft; the markers pointing at
-- them are drawn by the zone world too (DriveWorld.lua).
ZoneAnchorsQuest = class()
ZoneAnchorsQuest.isSaveObject = true

function ZoneAnchorsQuest.server_onCreate( self )
	self.sv = { left = nil }
end

function ZoneAnchorsQuest.server_onFixedUpdate( self )
	local left = g_zoneAnchorsLeft or 0
	if left ~= self.sv.left then
		self.sv.left = left
		self.network:setClientData( { left = left } )
	end
end

function ZoneAnchorsQuest.client_onCreate( self )
	QuestManager.Cl_OnQuestCreated( "quest_zone_anchors" )
	self.cl = {}
	self.scriptableObject.clientPublicData = {}
	self.scriptableObject.clientPublicData.progressString = ""
end

-- Abandoned quests don't leave the on-screen tracker by themselves
function ZoneAnchorsQuest.client_onDestroy( self )
	QuestManager.Cl_UntrackQuest( "quest_zone_anchors" )
end

function ZoneAnchorsQuest.client_onClientDataUpdate( self, data )
	local text
	if data.left > 0 then
		text = "Collect the energy anchors (" .. data.left .. " left)"
	else
		text = "All energy anchors collected"
	end
	self.scriptableObject.clientPublicData.progressString = text
	QuestManager.Cl_UpdateQuestTracker()
end
