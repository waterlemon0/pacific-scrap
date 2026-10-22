dofile( "$SURVIVAL_DATA/Scripts/game/managers/QuestManager.lua" )

-- Quest tracker entries worked out by the game (one class per quest, see
-- Story.lua): the main quest's steps in g_storyTracker, other quests' in
-- g_questTrackers[name]. These mirror them to the HUD's quest tracker, with
-- checkmarks on the finished steps (and no checkbox on lines of context).
StoryQuest = class()
StoryQuest.isSaveObject = true

function StoryQuest.server_onCreate( self )
	self.sv = { key = nil }
end

function StoryQuest.server_onFixedUpdate( self )
	local tracker = g_questTrackers and g_questTrackers[self.questName]
	if not tracker then
		tracker = g_storyTracker
		if not tracker or tracker.name ~= self.questName then
			return
		end
	end
	local parts = {}
	for _, step in ipairs( tracker.steps ) do
		parts[#parts + 1] = step.text .. ( step.desc and "=" or ( step.complete and "+" or "-" ) )
	end
	local key = table.concat( parts, "|" )
	if key ~= self.sv.key then
		self.sv.key = key
		self.network:setClientData( { steps = tracker.steps } )
	end
end

function StoryQuest.client_onCreate( self )
	QuestManager.Cl_OnQuestCreated( self.questName )
	self.cl = {}
	self.scriptableObject.clientPublicData = {}
	self.scriptableObject.clientPublicData.trackerData = { { name = "wait", text = "" } }
end

-- Abandoned quests don't leave the on-screen tracker by themselves
function StoryQuest.client_onDestroy( self )
	QuestManager.Cl_UntrackQuest( self.questName )
end

function StoryQuest.client_onClientDataUpdate( self, data )
	local steps = {}
	for _, step in ipairs( data.steps or {} ) do
		-- (a line of context has no checkbox: complete left out, like survival's *_desc lines)
		local line = { name = step.name, text = step.text }
		if not step.desc then line.complete = step.complete == true end
		steps[#steps + 1] = line
	end
	self.scriptableObject.clientPublicData.trackerData = steps
	QuestManager.Cl_UpdateQuestTracker()
end

-- (each class sets everything itself: script classes don't inherit fields)
local function StoryQuestClass( questName )
	local quest = class()
	quest.isSaveObject = true
	quest.questName = questName
	quest.server_onCreate = StoryQuest.server_onCreate
	quest.server_onFixedUpdate = StoryQuest.server_onFixedUpdate
	quest.client_onCreate = StoryQuest.client_onCreate
	quest.client_onDestroy = StoryQuest.client_onDestroy
	quest.client_onClientDataUpdate = StoryQuest.client_onClientDataUpdate
	return quest
end

StoryGettingStartedQuest = StoryQuestClass( "quest_story_getting_started" )
ExpeditionChecklistQuest = StoryQuestClass( "quest_expedition_checklist" )
StoryFirstGatewayQuest = StoryQuestClass( "quest_story_first_gateway" )
StoryCraftbotQuest = StoryQuestClass( "quest_story_craftbot" )

-- Craftbot Online listens for survival's crafters handing out a crafted part
-- (the mechanic station's workbench building a Craftbot) and tells the game
local CraftbotUuids = {
	["b63c6440-dfc2-4da7-acdb-3c385080b2e4"] = true, ["b7571f6f-9d53-44ba-99d2-3b4f05e6fd0f"] = true,
	["1c83675f-7c77-4cbb-875b-79d4bd46100d"] = true, ["c69a7855-d915-4784-af81-d0a8849e458f"] = true,
	["4fcb4cb8-7623-11ea-bc55-0242ac130003"] = true,
}
function StoryCraftbotQuest.server_onCreate( self )
	StoryQuest.server_onCreate( self )
	QuestManager.Sv_SubscribeEvent( QuestEvent.DispenserSpawnShape, self.scriptableObject, "sv_e_onQuestEvent" )
end

function StoryCraftbotQuest.server_onDestroy( self )
	QuestManager.Sv_UnsubscribeAllEvents( self.scriptableObject )
end

function StoryCraftbotQuest.sv_e_onQuestEvent( self, data )
	if data and data.event == QuestEvent.DispenserSpawnShape and data.params and CraftbotUuids[tostring( data.params.shapeUuid )] then
		sm.event.sendToGame( "sv_e_craftbotMade" )
	end
end
StoryArmingQuest = StoryQuestClass( "quest_story_arming" )
StoryAntennaQuest = StoryQuestClass( "quest_story_antenna" )
StoryOuterZoneQuest = StoryQuestClass( "quest_story_outer" )
StoryHideoutQuest = StoryQuestClass( "quest_story_hideout" )
StoryFarmersQuest = StoryQuestClass( "quest_story_farmers" )
StoryMidZoneQuest = StoryQuestClass( "quest_story_mid" )
StoryAntenna2Quest = StoryQuestClass( "quest_story_antenna2" )
StoryDeepZoneQuest = StoryQuestClass( "quest_story_deep" )
