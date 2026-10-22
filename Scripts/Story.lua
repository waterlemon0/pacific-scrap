-- Main quest: the story chain that unlocks the zone tiers (ZONE_TIERS in
-- layouts.lua).
--
--   1. Getting Started: search the Friendly Dumpster (the battery and the ARC
--      Device are in it) and put the battery in the socket to power the garage
--      (the Fabricator, Route Planner and junction pad need it).
--   2. Into the Zone: the tutorial. Depart, find anchors, power the ARC Device,
--      open a gateway and escape through it.
--   3. The Outer Zone: escape through a gateway at the Outer Zone's last
--      junction.
--   4. Raise the Antenna: build the antenna on the builder pad by the station
--      (survival_patches.lua, BuilderGuides/antenna_lv1_guide.json): the Route
--      Planner gets 3 scans every trip instead of 1. Its parts' schematics
--      are handed out when it starts.
--   5. Distress Call: with the antenna up, the farmers call you on the phone
--      asking for help (Dialogs.lua); the quest only shows once the call is
--      over, and so does the Farmers' Hideout on the map (a landmark junction
--      in the Outer Zone, see LANDMARKS in layouts.lua): reach it and talk to
--      the farmer there (HideoutFarmer.lua), who offers a key to the Mid Zone
--      for food. Once he's done talking, Roadside Picnic starts.
--   6. Roadside Picnic: deliver crates (from the packing stations) to the
--      hideout, then talk to the farmer: he thanks you and holds out the key
--      to the Mid Zone (like Hubert's keys); taking it finishes the quest and
--      unlocks the Mid Zone.
--   7. The Mid Zone: escape at the Mid Zone's edge. Unlocks the Deep Zone.
--   8. Boost the Signal: the old antenna comes down (an explosion) and you
--      build the bigger one on the same pad (antenna_lv2_guide.json): 5 scans
--      every trip. Its parts' schematics are handed out when it starts.
--   9. The Deep Zone: escape at JCT 9 or further. The end
--      (for now): the Deep Zone then goes on for ever.
--
-- Junctions past the last unlocked tier stay locked (JunctionExitsOpen checks
-- g_storyMaxDepth). The game works out each quest's tracker steps here and
-- publishes them in g_storyTracker; the quest objects (StoryQuests.lua) only
-- show them.
--
-- Loaded by Game.lua; everything here is Game methods.

STORY_QUESTS = {
	{ name = "quest_story_getting_started", title = "Getting Started", power = true },
	{ name = "quest_story_first_gateway", title = "Into the Zone" },
	{ name = "quest_story_outer", title = "The Outer Zone", tier = 1 },
	{ name = "quest_story_antenna", title = "Raise the Antenna", antenna = 1 },
	{ name = "quest_story_hideout", title = "Distress Call", landmark = "hideout", call = "DistressCall", talk = "HideoutTalk" },
	{ name = "quest_story_farmers", title = "Roadside Picnic", crates = 3, unlocks = true },
	{ name = "quest_story_mid", title = "The Mid Zone", tier = 2, unlocks = true },
	{ name = "quest_story_antenna2", title = "Boost the Signal", antenna = 2 },
	{ name = "quest_story_deep", title = "The Deep Zone", tier = 3 },
}

-- How many tiers are open at a chapter: the first, plus one per unlocking
-- quest done (unlocks = true)
local function UnlockedTiers( chapter )
	local tiers = 1
	for i = 1, chapter - 1 do
		if STORY_QUESTS[i] and STORY_QUESTS[i].unlocks then tiers = tiers + 1 end
	end
	return math.min( tiers, #ZONE_TIERS )
end

-- 2: Getting Started added in front. 3: Craftbot Online and Gearing Up added
-- after First Gateway. 4: Signs of Life added after The Outer Zone. 5: Feed
-- the Farmers added after Signs of Life (it unlocks the Mid Zone now).
-- 6: Gearing Up (the Fabricator tutorial) moved before Craftbot Online.
-- 7: Raise the Antenna added after Craftbot Online. 8: Distress Call moved
-- before The Outer Zone (the farmers call once the antenna is up). 9: The
-- Outer Zone moved back before Raise the Antenna. 10: Gearing Up and Craftbot
-- Online taken out. 11: Boost the Signal (the level 2 antenna) added after The
-- Mid Zone.
local STORY_VERSION = 11

-- Quests taken out of the chain: dropped from saves that still have them
local RETIRED_QUESTS = { "quest_story_arming", "quest_story_craftbot" }

-- Seconds home in the garage before a quest's phone call rings
CALL_DELAY_SECONDS = 5

local ARC_DEVICE_ITEM = sm.uuid.new( "a6258a75-ea2b-47f7-acec-a3ace313bbd9" )

-- The deepest junction you can drive on from (its exits lead out of the open
-- tiers otherwise). The last tier goes on for ever.
local function MaxDepthFor( chapter )
	local tiers = UnlockedTiers( chapter )
	if tiers >= #ZONE_TIERS then
		return math.huge
	end
	return ZONE_TIERS[tiers].last
end

-- The garage antenna standing now (the Route Planner's extra scans, see
-- ScannerCharges): 0 none, 1, or 2. The first comes down when Boost the Signal
-- starts (antennaBroken) until the second is up.
function AntennaLevel( story )
	if story.antenna2Built then return 2 end
	if story.antennaBuilt and not story.antennaBroken then return 1 end
	return 0
end

function Game.sv_storyState( self )
	local story = self.sv.saved.story
	if not story then
		-- Saves from before the story: skip the tutorial if you've escaped before,
		-- and count your deepest escape so far
		local deepest = 0
		local map = self.sv.saved.map
		for _, node in pairs( map and map.nodes or {} ) do
			if node.cleared then deepest = math.max( deepest, node.depth ) end
		end
		story = { chapter = deepest > 0 and 3 or 1, deepest = deepest, version = STORY_VERSION }
		self.sv.saved.story = story
		if deepest > 0 then self.sv.saved.garagePowered = true end
		self:sv_storyAdvance( true )
	end
	-- Saves from before Getting Started: their garage counts as powered, and
	-- every chapter moves one along
	if ( story.version or 1 ) < 2 then
		story.chapter = story.chapter + 1
		story.version = 2
		self.sv.saved.garagePowered = true
	end
	-- Saves from before Craftbot Online / Gearing Up: past First Gateway already,
	-- they skip them
	if story.version < 3 then
		if story.chapter >= 3 then story.chapter = story.chapter + 2 end
		story.version = 3
	end
	-- Saves from before Signs of Life: on The Mid Zone quest they're sent to
	-- find the hideout first; further along, they're past it
	if story.version < 4 then
		if story.chapter >= 7 then story.chapter = story.chapter + 1 end
		story.version = 4
	end
	-- Saves from before Roadside Picnic: past Signs of Life, they skip it
	if story.version < 5 then
		if story.chapter >= 7 then story.chapter = story.chapter + 1 end
		story.version = 5
	end
	-- Saves from before Gearing Up came first: on Gearing Up (then chapter 4,
	-- Craftbot Online done) it's chapter 3 now; on Craftbot Online (chapter 3)
	-- they do Gearing Up first, and the Craftbot is checked after
	if story.version < 6 then
		if story.chapter == 4 then story.chapter = 3 end
		story.version = 6
	end
	-- Saves from before Raise the Antenna: on The Outer Zone (chapter 5) they
	-- build the antenna first; further along, they're past it
	if story.version < 7 then
		if story.chapter > 5 then story.chapter = story.chapter + 1 end
		story.version = 7
	end
	-- Saves from before Distress Call came first: on The Outer Zone (chapter 6)
	-- they get the call and Distress Call first (The Outer Zone completes after,
	-- if they've done it); on Distress Call (chapter 7) it's chapter 6 now
	if story.version < 8 then
		if story.chapter == 7 then story.chapter = 6 end
		story.version = 8
	end
	-- Saves from before The Outer Zone came back first (then: 5 antenna,
	-- 6 Distress Call, 7 The Outer Zone): on any of them it's The Outer Zone
	-- now, and what's already done completes after it. Past Distress Call, its
	-- call and talk count as done (they came later than some saves did it).
	if story.version < 9 then
		if story.chapter >= 7 then
			story.calls = story.calls or {}
			story.callsDone = story.callsDone or {}
			story.talks = story.talks or {}
			story.calls.DistressCall, story.callsDone.DistressCall, story.talks.HideoutTalk = true, true, true
		end
		if story.chapter >= 5 and story.chapter <= 7 then story.chapter = 5 end
		story.version = 9
		self.sv.saved.story = story
		self:sv_storyAdvance( true )
	end
	-- Saves from before Gearing Up and Craftbot Online went (then chapters 3 and
	-- 4): on either, it's The Outer Zone now; further along, two chapters back
	if story.version < 10 then
		if story.chapter == 3 or story.chapter == 4 then
			story.chapter = 3
		elseif story.chapter > 4 then
			story.chapter = story.chapter - 2
		end
		story.version = 10
		self.sv.saved.story = story
		self:sv_storyAdvance( true )
	end
	-- Saves from before Boost the Signal: past The Mid Zone, it's next (The
	-- Deep Zone after it completes straight away if you've already escaped it)
	if story.version < 11 then
		if story.chapter > 8 then story.chapter = 8 end
		story.version = 11
		self.sv.saved.story = story
		self:sv_storyAdvance( true )
	end
	return story
end

-- Called once the save is loaded
function Game.sv_storyInit( self )
	self.sv.storyActivated = {}
	local story = self:sv_storyState()
	g_storyMaxDepth = MaxDepthFor( story.chapter )
	g_antennaLevel = AntennaLevel( story )
	g_hideoutKeyReady = story.talks ~= nil and story.talks.HideoutKey == true and not story.midKeyTaken
	self:sv_storyLandmarksHidden( story )
end

-- Has a quest's phone call been and gone? (Its quest only shows after)
local function CallDone( story, quest )
	return not quest.call or ( story.callsDone ~= nil and story.callsDone[quest.call] == true )
end

-- Landmarks the story keeps off the map until their quest's call is over
-- (g_hiddenLandmarks, JunctionMap.lua): the Farmers' Hideout until the farmers
-- have called (Distress Call)
-- Once shown (g_storyRevealedLandmarks), the way there is open: the
-- junctions on the road to it count as escaped (JunctionMap.lua)
function Game.sv_storyLandmarksHidden( self, story )
	local hidden, revealed = {}, {}
	for i, quest in ipairs( STORY_QUESTS ) do
		if quest.landmark and quest.call then
			if story.chapter < i or ( story.chapter == i and not CallDone( story, quest ) ) then
				hidden[quest.landmark] = true
			else
				revealed[quest.landmark] = true
			end
		end
	end
	g_hiddenLandmarks = hidden
	g_storyRevealedLandmarks = revealed
end

-- Escaped through a gateway at this depth
function Game.sv_storyOnEscape( self, depth )
	local story = self:sv_storyState()
	story.deepest = math.max( story.deepest or 0, depth or 0 )
	story.escaped = true
	self:sv_storyAdvance( false )
	self:sv_saveGame()
end

-- Complete every quest whose goal is met. quiet: no notifications (old saves)
function Game.sv_storyAdvance( self, quiet )
	local story = self.sv.saved.story
	while STORY_QUESTS[story.chapter] do
		local quest = STORY_QUESTS[story.chapter]
		local done
		if story.skipped and story.skipped[quest.name] then
			done = true -- (/skipquest)
		elseif quest.tier then
			done = ( story.deepest or 0 ) >= ZONE_TIERS[quest.tier].last
		elseif quest.power then
			done = self.sv.saved.garagePowered == true
		elseif quest.crates then
			-- (the crates, then the farmer hands over the key: taking it is the end)
			done = story.midKeyTaken == true
		elseif quest.landmark then
			done = CallDone( story, quest ) and story.landmarks ~= nil and story.landmarks[quest.landmark] == true
				and ( not quest.talk or ( story.talks ~= nil and story.talks[quest.talk] == true ) )
		elseif quest.antenna then
			done = ( quest.antenna == 2 and story.antenna2Built or story.antennaBuilt ) == true
		else
			done = story.escaped == true or ( story.deepest or 0 ) > 0
		end
		if not done then
			break
		end
		story.chapter = story.chapter + 1
		if not quiet then
			NotificationManager.Sv_QuestCompleted( quest.title, "main" )
			-- (QuestManager's own completion would also try to grant an achievement)
			QuestManager.Sv_TryAbandonQuest( quest.name )
			local unlocked = ZONE_TIERS[UnlockedTiers( story.chapter )]
			if quest.unlocks and unlocked then
				self.network:sendToClients( "cl_n_alert", { text = unlocked.title .. " unlocked\nThe junctions beyond " .. ZONE_TIERS[UnlockedTiers( story.chapter ) - 1].title .. " are open", seconds = 6 } )
			end
			sm.log.info( "[PacificScrap] Story: completed", quest.name, "- chapter", story.chapter )
		end
	end
	g_storyMaxDepth = MaxDepthFor( story.chapter )
	self:sv_storyLandmarksHidden( story )
end

-- Every tick: keep the current chapter's quest active and its steps up to date
function Game.sv_storyUpdate( self )
	if not self.sv.questRegistered then
		return
	end
	local story = self:sv_storyState()
	local quest = STORY_QUESTS[story.chapter]
	-- (once a session) A junction's number is counted along the road from the
	-- garage now (JunctionMap.lua): escapes already made count by that
	if not self.sv.storyActivated.recounted then
		self.sv.storyActivated.recounted = true
		local deepest = 0
		local map = self:sv_jmMap()
		for _, node in pairs( map.nodes ) do
			if node.cleared and node.depth > 0 then deepest = math.max( deepest, node.depth ) end
		end
		if deepest > ( story.deepest or 0 ) then
			sm.log.info( "[PacificScrap] Story: deepest escape recounted as JCT", deepest )
			self:sv_storyOnEscape( deepest )
			quest = STORY_QUESTS[story.chapter]
		end
	end
	-- Retired quests go (once a session)
	if not self.sv.storyActivated.retired then
		self.sv.storyActivated.retired = true
		for _, name in ipairs( RETIRED_QUESTS ) do QuestManager.Sv_TryAbandonQuest( name ) end
	end
	-- Earlier chapters' quests are done (e.g. a save that skipped the tutorial)
	for i = 1, story.chapter - 1 do
		local old = STORY_QUESTS[i]
		if old and not self.sv.storyActivated["done_" .. old.name] then
			self.sv.storyActivated["done_" .. old.name] = true
			QuestManager.Sv_TryAbandonQuest( old.name )
		end
	end
	-- (a quest with a phone call only shows once the call is over)
	if quest and not self.sv.storyActivated[quest.name] and CallDone( story, quest ) then
		self.sv.storyActivated[quest.name] = true
		if not QuestManager.Sv_IsQuestActive( quest.name ) then
			QuestManager.Sv_ActivateQuest( quest.name )
		end
	end
	-- An antenna quest hands out the schematics of every part in its antenna
	-- (once): RecipeManager shows each as unlocked
	if quest and quest.antenna and self.sv.storyActivated[quest.name] and ANTENNA_GUIDES and ANTENNA_GUIDES[quest.name] then
		story.antennaRecipes = story.antennaRecipes or {}
		if not story.antennaRecipes[quest.antenna] then
			story.antennaRecipes[quest.antenna] = true
			local seen = { [ANTENNA_PAD_UUID] = true, ["5627aa08-8bc4-4cf3-a6b6-101ae59e6fc6"] = true } -- (not the pad)
			local guide = sm.json.open( ANTENNA_GUIDES[quest.name] )
			for _, body in ipairs( guide and guide.bodies or {} ) do
				for _, child in ipairs( body.childs or {} ) do
					if child.shapeId and not seen[child.shapeId] then
						seen[child.shapeId] = true
						RecipeManager.Sv_UnlockRecipe( child.shapeId )
					end
				end
			end
			self:sv_saveGame()
		end
	end
	-- A phone call that starts the quest (quest.call, Dialogs.lua): it rings
	-- once you've been home in the garage for a few seconds
	if quest and quest.call and not ( story.calls and story.calls[quest.call] ) and sm.game.getCurrentTick() % 40 == 23 then
		if self.sv.run.state == "idle" and g_garagePowered then
			self.sv.callWait = ( self.sv.callWait or 0 ) + 1
			if self.sv.callWait >= CALL_DELAY_SECONDS then
				story.calls = story.calls or {}
				story.calls[quest.call] = true
				self.sv.callTick = sm.game.getCurrentTick()
				self:sv_playCall( DIALOG_DISTRESS_CALL, quest.call )
				self:sv_saveGame()
			end
		else
			self.sv.callWait = 0
		end
	end
	-- The call is over (no longer in survival's dialog queue): the quest shows,
	-- and its landmark goes on the map
	if quest and quest.call and story.calls and story.calls[quest.call] and not CallDone( story, quest )
		and sm.game.getCurrentTick() % 20 == 11 and sm.game.getCurrentTick() - ( self.sv.callTick or 0 ) > 80
		and not DialogManager.Sv_IsDialogQueued( DIALOG_DISTRESS_CALL, quest.call ) then
		story.callsDone = story.callsDone or {}
		story.callsDone[quest.call] = true
		sm.log.info( "[PacificScrap] Call over:", quest.call )
		self:sv_storyLandmarksHidden( story )
		self:sv_saveGame()
		-- (the map grows the landmark in; sv_jmMap makes the map first on a new save)
		self:sv_jmMap()
	end
	-- A talk with someone is over (Game.sv_e_hideoutFarmerTalk started it): done
	if self.sv.talking and sm.game.getCurrentTick() % 20 == 13 and sm.game.getCurrentTick() - self.sv.talking.tick > 80
		and not DialogManager.Sv_IsDialogQueued( self.sv.talking.dialog, self.sv.talking.entry ) then
		local entry = self.sv.talking.entry
		self.sv.talking = nil
		if story.talks and story.talks[entry] == false then
			story.talks[entry] = true
			sm.log.info( "[PacificScrap] Talk over:", entry )
			if entry == "HideoutKey" then g_hideoutKeyReady = true end
			self:sv_storyAdvance( false )
			self:sv_saveGame()
		end
	end
	self:sv_checklistUpdate()
	if sm.game.getCurrentTick() % 10 == 0 then
		g_storyTracker = quest and { name = quest.name, steps = self:sv_storySteps( story, quest ) } or nil
	end
end

-- The tracker lines, laid out like survival's quests: a line of context (desc:
-- no checkbox, names in yellow), then the steps to tick off. Counters go in
-- front like survival's ("2/3 Crates delivered").
-- { name, text, complete } for a step, { name, text, desc = true } for context
local function Desc( name, text ) return { name = name, text = text, desc = true } end
local function Step( name, text, complete ) return { name = name, text = text, complete = complete == true } end
local function Name( text ) return "#FFFFC0" .. text .. "#FFFFFF" end
local function Count( count, total ) return "#FFFFC0" .. count .. "/" .. total .. "#FFFFFF " end

function Game.sv_storySteps( self, story, quest )
	local run = self.sv.run
	local inZone = run.state == "inZone" or run.state == "returning"
	if quest.crates then
		local delivered = math.min( story.cratesDelivered or 0, quest.crates )
		if delivered < quest.crates then
			return {
				Desc( "desc", "The farmers are starving. Feed them and they'll give you their key to the " .. Name( ZONE_TIERS[2].title ) .. "." ),
				Step( "crates", Count( delivered, quest.crates ) .. "Crates delivered to the hideout's dropzone", false ),
			}
		end
		local talked = story.talks ~= nil and story.talks.HideoutKey == true
		return {
			Desc( "desc", "That's plenty of food. The farmer has something for you." ),
			Step( "talk", "Talk to the farmer", talked ),
			Step( "key", "Take the " .. Name( ZONE_TIERS[2].title .. " Key" ), story.midKeyTaken == true ),
		}
	end
	if quest.landmark then
		local landmark = LandmarkByName( quest.landmark )
		local reached = story.landmarks ~= nil and story.landmarks[quest.landmark] == true
		local steps = {
			Desc( "desc", quest.call and ( "The farmers called for help. Their hideout is on the " .. Name( "Route Planner" ) .. " now." )
				or ( "The " .. Name( landmark.title ) .. " is marked on the Route Planner." ) ),
			Step( "reach", "Reach the " .. Name( landmark.title ), reached ),
		}
		if quest.talk then
			steps[#steps + 1] = Step( "talk", "Talk to the farmer", false )
		end
		return steps
	end
	if quest.antenna == 2 then
		return {
			Desc( "desc", "The old antenna came down. A bigger " .. Name( "Antenna" ) .. " gives the Route Planner five scans every trip." ),
			Step( "build", "Build the new antenna on the pad beside the " .. Name( "Mechanic Station" ), story.antenna2Built == true ),
		}
	end
	if quest.antenna then
		return {
			Desc( "desc", "An " .. Name( "Antenna" ) .. " gives the Route Planner three scans every trip instead of one." ),
			Step( "build", "Build the antenna on the pad beside the " .. Name( "Mechanic Station" ), story.antennaBuilt == true ),
		}
	end
	if quest.power then
		local hasBattery = false
		for _, player in ipairs( sm.player.getAllPlayers() ) do
			local inventory = player:getInventory()
			if inventory and sm.container.totalQuantity( inventory, POWER_CORE_UUID ) > 0 then hasBattery = true end
		end
		local powered = self.sv.saved.garagePowered == true
		return {
			Desc( "desc", "The garage has no power. Get it running again." ),
			Step( "dumpster", "Search the " .. Name( "Friendly Dumpster" ), story.dumpsterOpened == true or hasBattery or powered ),
			Step( "socket", "Put the " .. Name( "Battery" ) .. " in the battery socket", powered ),
		}
	end
	if not quest.tier then
		-- The tutorial, in three parts (live: a failed run starts the zone part over)
		local cost = g_gatewayCost or JUNCTION_COST_BASE
		local total = g_zoneAnchorsTotal or 0
		local collected = inZone and math.max( total - ( g_zoneAnchorsLeft or total ), 0 ) or 0
		local loaded = 0
		for _, entry in pairs( g_arcAnchorCounts or {} ) do
			if sm.game.getCurrentTick() - entry.tick < 80 then loaded = math.max( loaded, entry.count ) end
		end
		local gateway = inZone and run.gateway ~= nil
		local powered = gateway or ( inZone and loaded >= cost )
		-- The ARC Device (in the garage): found once someone has it, or it's on a vehicle
		if not story.arcFound then
			for _, player in ipairs( sm.player.getAllPlayers() ) do
				local inventory = player:getInventory()
				if inventory and sm.container.totalQuantity( inventory, ARC_DEVICE_ITEM ) > 0 then story.arcFound = true end
			end
			for _, device in pairs( g_arcDevices or {} ) do
				if device.onVehicle then story.arcFound = true end
			end
		end
		-- Getting ready in the garage: the Expedition Checklist has the steps
		if not inZone then
			return {
				Desc( "desc", "Get ready for your first trip into the " .. Name( "Zone" ) .. ". Follow the " .. Name( "Expedition Checklist" ) .. "." ),
			}
		end
		-- Powering the ARC Device
		if not powered then
			return {
				Desc( "desc", "Gateways home are powered by " .. Name( "Energy Anchors" ) .. ". Follow their beacons to find them." ),
				Step( "anchors", Count( math.min( collected, cost ), cost ) .. "Energy Anchors found", collected >= cost ),
				Step( "load", "Put them in the ARC Device on your car", false ),
			}
		end
		-- Getting out
		return {
			Desc( "desc", "Open a gateway and get out before the zone collapses!" ),
			Step( "switch", "Switch on the " .. Name( "ARC Device" ) .. " (wire a switch to it)", gateway ),
			Step( "gateway", "Drive into the yellow " .. Name( "Gateway" ), false ),
		}
	end
	local tier = ZONE_TIERS[quest.tier]
	local next = ZONE_TIERS[quest.tier + 1]
	-- (done once you've escaped at JCT tier.last or further: story.deepest; on a
	-- hand-made map a zone can have junctions past that number)
	local why = ( quest.unlocks and next and ( "Get far enough in to open the " .. Name( next.title ) .. "." ) )
		or ( next and "Get far enough in." )
		or "The heart of the zone lies further in."
	return {
		Desc( "desc", "Push through the " .. Name( tier.title ) .. ". " .. why ),
		Step( "goal", "Escape through a gateway at " .. Name( "JCT " .. tier.last ) .. " or further", false ),
	}
end

-- Survival's power core: the garage's battery (a quest marker shows where it
-- is, and then the socket: GarageWorld.sv_powerMarker)
POWER_CORE_UUID = sm.uuid.new( "c654a023-ca53-4109-9f18-d297c18e9a02" )

-- A Craftbot crafted at the mechanic station's workbench (StoryCraftbotQuest
-- hears it from survival's crafter)
function Game.sv_hasCraftbot( self )
	return self.sv.saved.story.craftbotMade == true
end

function Game.sv_e_craftbotMade( self )
	local story = self:sv_storyState()
	if not story.craftbotMade then
		story.craftbotMade = true
		self:sv_storyAdvance( false )
		self:sv_saveGame()
	end
end

-- Cheat (/skipquest [count]): the current main quest counts as done (and the
-- next ones, for a count). Getting Started also powers the garage.
function Game.sv_storySkip( self, player, count )
	local story = self:sv_storyState()
	for _ = 1, math.max( count or 1, 1 ) do
		local quest = STORY_QUESTS[story.chapter]
		if not quest then
			self:sv_message( player, "The main quest is finished: nothing left to skip." )
			break
		end
		story.skipped = story.skipped or {}
		story.skipped[quest.name] = true
		if quest.power and not self.sv.saved.garagePowered then
			self.sv.saved.garagePowered = true
			g_garagePowered = true
			-- (the battery goes into the socket for real: lights and all)
			sm.event.sendToWorld( self.sv.saved.overworld, "sv_e_forcePower", { player = player } )
		end
		self:sv_storyAdvance( false )
		sm.log.info( "[PacificScrap] Cheat: skipped", quest.name )
	end
	self:sv_saveGame()
end

-- A crate went into the hideout's vacuum (hideout_shop.lua; Roadside Picnic)
function Game.sv_e_crateDelivered( self )
	local story = self:sv_storyState()
	story.cratesDelivered = ( story.cratesDelivered or 0 ) + 1
	self:sv_storyAdvance( false )
	self:sv_saveGame()
end

-- The Friendly Dumpster was looked through (Getting Started, Into the Zone)
function Game.sv_e_dumpsterOpened( self )
	local story = self:sv_storyState()
	if not story.dumpsterOpened then
		story.dumpsterOpened = true
		self:sv_storyAdvance( false )
		self:sv_saveGame()
	end
end

-- Arrived at a landmark junction (Distress Call)
function Game.sv_storyOnLandmark( self, name )
	local story = self:sv_storyState()
	story.landmarks = story.landmarks or {}
	if not story.landmarks[name] then
		story.landmarks[name] = true
		self:sv_storyAdvance( false )
		self:sv_saveGame()
	end
end

-- An antenna on the garage's builder pad is finished (survival_patches.lua):
-- its quest is done, and the Route Planner gets its extra scans now.
-- params.level: 1 (Raise the Antenna) or 2 (Boost the Signal)
function Game.sv_e_antennaBuilt( self, params )
	local story = self:sv_storyState()
	local level = params and params.level or 1
	if level == 2 then
		if story.antenna2Built then return end
		story.antenna2Built = true
		story.antennaBroken = nil
	else
		if story.antennaBuilt then return end
		story.antennaBuilt = true
	end
	g_antennaLevel = AntennaLevel( story )
	local map = self.sv.saved.map
	if map then map.charges = math.max( map.charges or 0, ScannerCharges() ) end
	self.network:sendToClients( "cl_n_alert", { text = "Antenna raised\nThe Route Planner gets " .. ScannerCharges() .. " scans every trip", seconds = 6 } )
	sm.log.info( "[PacificScrap] Antenna built, level", level )
	self:sv_storyAdvance( false )
	self:sv_saveGame()
end

-- Boost the Signal started and the old antenna came down (survival_patches.lua):
-- only the Route Planner's own scan until the new one is up
function Game.sv_e_antennaTornDown( self )
	local story = self:sv_storyState()
	story.antennaBroken = true
	g_antennaLevel = AntennaLevel( story )
	sm.log.info( "[PacificScrap] Old antenna torn down" )
	self:sv_saveGame()
end

-- Talked to the farmer at the hideout (HideoutFarmer.lua): on Distress Call he
-- makes his offer (and Roadside Picnic follows when he's done), on Roadside
-- Picnic he reminds you, after that he thanks you
function Game.sv_e_hideoutFarmerTalk( self, params )
	if self.sv.talking then return end -- (already talking)
	local story = self:sv_storyState()
	local quest = STORY_QUESTS[story.chapter]
	local entry
	if quest and quest.talk and CallDone( story, quest ) and story.landmarks and story.landmarks[quest.landmark] then
		entry = quest.talk
		story.talks = story.talks or {}
		if story.talks[entry] ~= true then story.talks[entry] = false end -- (started, not done)
	elseif quest and quest.crates and story.talks and story.talks.HideoutKey == true then
		-- He's holding out the key: taking it finishes Roadside Picnic
		self:sv_takeMidKey( params and params.player )
		return
	elseif quest and quest.crates and ( story.cratesDelivered or 0 ) >= quest.crates then
		entry = "HideoutKey" -- (thanks; then he holds out the key)
		story.talks = story.talks or {}
		story.talks.HideoutKey = false -- (started, not done)
	elseif quest and quest.crates then
		entry = "HideoutReminder"
	elseif story.talks and story.talks.HideoutTalk then
		entry = "HideoutThanks"
	else
		entry = "HideoutReminder"
	end
	self.sv.talking = { dialog = DIALOG_HIDEOUT, entry = entry, tick = sm.game.getCurrentTick() }
	DialogManager.Sv_PlayDialog( DIALOG_HIDEOUT, entry, nil, DialogType.Person, "Farmer", DialogPriority.MainQuest,
		params and params.unit and sm.exists( params.unit ) and params.unit or nil )
end

-- The farmer's key to the Mid Zone: survival's keycard (Hubert's warehouse
-- key), held out once he's thanked you for the crates (g_hideoutKeyReady:
-- ZoneWorld.sv_keepHideoutFarmer has him hold it, HideoutFarmer.lua)
MID_ZONE_KEY = sm.uuid.new( "e49b210a-0d46-4f06-bcd8-08862379d156" )

function Game.sv_takeMidKey( self, player )
	local story = self:sv_storyState()
	if story.midKeyTaken then return end
	story.midKeyTaken = true
	g_hideoutKeyReady = false
	if player and sm.exists( player ) and player:getInventory() then
		sm.container.beginTransaction()
		sm.container.collect( player:getInventory(), MID_ZONE_KEY, 1 )
		sm.container.endTransaction()
	end
	sm.log.info( "[PacificScrap] Mid Zone key taken" )
	self:sv_storyAdvance( false )
	self:sv_saveGame()
end

-- Anchors were banked into the Fabricator (Gearing Up's first step)
function Game.sv_e_anchorsBanked( self )
	local story = self:sv_storyState()
	if not story.anchorsBanked then
		story.anchorsBanked = true
		self:sv_saveGame()
	end
end

-- Something was unlocked at the Fabricator (Gearing Up's second step)
function Game.sv_e_fabricatorUnlocked( self )
	local story = self:sv_storyState()
	if not story.fabricatorUsed then
		story.fabricatorUsed = true
		self:sv_saveGame()
	end
end

-- Expedition Checklist (side quest): in the garage, once it has power, a fresh
-- one every time you're home. It's done when you set off into the zone.
local CHECKLIST_QUEST = "quest_expedition_checklist"

function Game.sv_checklistSteps( self )
	-- Any ARC Device in the garage will do (others lying about don't matter)
	local onVehicle, connected = false, false
	for _, device in pairs( g_arcDevices or {} ) do
		if sm.game.getCurrentTick() - device.tick < 120 and device.world == self.sv.saved.overworld and device.onVehicle then
			onVehicle = true
			connected = connected or device.connected
		end
	end
	local map = self.sv.saved.map
	return {
		Desc( "desc", "Get your car ready before heading into the " .. Name( "Zone" ) .. "." ),
		Step( "arc", "Fit the " .. Name( "ARC Device" ) .. " to your car", onVehicle ),
		Step( "button", "Wire it to a button or switch", connected ),
		Step( "destination", "Set a destination in the " .. Name( "Route Planner" ), map ~= nil and map.destination ~= nil ),
		Step( "zone", "Drive into the junction", false ),
	}
end

function Game.sv_checklistUpdate( self )
	local wanted = self.sv.run.state == "idle" and self.sv.saved.garagePowered == true
	if self.sv.checklistOn == nil then
		self.sv.checklistOn = QuestManager.Sv_IsQuestActive( CHECKLIST_QUEST ) == true
	end
	if wanted ~= self.sv.checklistOn then
		self.sv.checklistOn = wanted
		if wanted then
			QuestManager.Sv_ActivateQuest( CHECKLIST_QUEST )
		else
			-- Set off: that was the last step
			if self.sv.run.state ~= "idle" then
				NotificationManager.Sv_QuestCompleted( "Expedition Checklist", "side" )
			end
			QuestManager.Sv_AbandonQuest( CHECKLIST_QUEST )
		end
	end
	if sm.game.getCurrentTick() % 10 == 5 then
		g_questTrackers = g_questTrackers or {}
		g_questTrackers[CHECKLIST_QUEST] = wanted and { steps = self:sv_checklistSteps() } or nil
	end
end

-- First departure into the zone (the tutorial's first step)
function Game.sv_storyOnDepart( self )
	local story = self:sv_storyState()
	if not story.departed then
		story.departed = true
		self:sv_saveGame()
	end
end
