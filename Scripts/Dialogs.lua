-- Phone calls, like survival's (the mysterious caller): survival's dialog
-- manager plays them, with the caller portrait and text bubbles typing out.
--
-- The lines are in Gui/Language/<language>/Dialog/PacificDialogs.json, in
-- survival's dialog format (lines with a duration each). Survival's dialog
-- manager only reads its own dialog files, so every client puts ours into its
-- table (cl_dialogsEnsure, every tick: a language change empties it).
--
-- Survival only plays a voice for lines with a recorded clip, and ours have
-- none, so each text bubble plays the entry's "audio" effect instead (the
-- builder farmers' mumble), from cl_dialogsUpdate.
--
-- Loaded by Game.lua; everything here is Game methods.

PACIFIC_DIALOGS = "$CONTENT_DATA/Gui/Language/#{LANGUAGE}/Dialog/PacificDialogs.json"
DIALOG_DISTRESS_CALL = "a7b2c18a-6aeb-4437-821d-da31407e816f"
DIALOG_HIDEOUT = "4929056a-4cdf-49a4-85e8-cd5406677f11" -- (the farmer at the hideout, in person)

-- Our dialogs as survival's dialog manager keeps them: [uuid] = { speaker,
-- title, hideInLogbook, entries = { [name] = { lines = { { startTime, endTime,
-- text } }, audio } } }. Read once per language.
local s_dialogs, s_dialogsLanguage
local function LoadPacificDialogs( language )
	if s_dialogs and s_dialogsLanguage == language then
		return s_dialogs
	end
	local path = PACIFIC_DIALOGS:gsub( "#{LANGUAGE}", language )
	if not sm.json.fileExists( path ) then
		path = PACIFIC_DIALOGS:gsub( "#{LANGUAGE}", "English" )
	end
	local dialogs = {}
	if sm.json.fileExists( path ) then
		for _, dialog in ipairs( sm.json.open( path ).list or {} ) do
			local entries = {}
			for _, entry in ipairs( dialog.entries or {} ) do
				local lines, at = {}, 0
				for i, line in ipairs( entry.lines or {} ) do
					lines[i] = { startTime = at, endTime = at + ( line.duration or 4 ), text = line.text }
					at = at + ( line.duration or 4 )
				end
				entries[entry.name] = { lines = lines, audio = entry.audio }
			end
			dialogs[tostring( dialog.uuid )] = { speaker = dialog.speaker, title = dialog.title, hideInLogbook = dialog.hideInLogbook, entries = entries }
		end
	end
	s_dialogs, s_dialogsLanguage = dialogs, language
	return dialogs
end

-- Client, every tick: our dialogs are in survival's dialog manager's table
function Game.cl_dialogsEnsure( self )
	local manager = g_dialogManagerSelf
	local set = manager and manager.cl and manager.cl.dialogSet
	if not set then
		return
	end
	local dialogs = LoadPacificDialogs( sm.gui.getCurrentLanguage() )
	for uuid, dialog in pairs( dialogs ) do
		if set[uuid] ~= dialog then
			set[uuid] = dialog
		end
	end
end

-- Client, every tick: a new text bubble of one of our calls plays its sound
function Game.cl_dialogsUpdate( self )
	local manager = g_dialogManagerSelf
	local playing = manager and manager.cl and manager.cl.playingDialog
	local dialog = playing and s_dialogs and s_dialogs[tostring( playing.uuid )]
	if not dialog or not playing.openDone then
		self.cl.dialogBubble = nil
		return
	end
	local bubble = tostring( playing.id ) .. ":" .. tostring( playing.segment )
	if self.cl.dialogBubble == bubble then
		return
	end
	self.cl.dialogBubble = bubble
	local entry = dialog.entries[playing.entryName]
	if entry and entry.audio then
		-- The game script has no world, so it can't play a sound where you are
		-- (and the mumble is a 3D sound: unpositioned it's silent). The world
		-- you're in plays it at your character (DriveWorld.lua, PlayDialogBubble).
		g_pacificDialogBubble = { key = bubble, audio = entry.audio }
	end
end

-- Server: one of our calls rings (DIALOG_* uuid, its entry's name)
function Game.sv_playCall( self, uuid, entryName )
	if DialogManager and DialogManager.Sv_PlayDialog then
		local dialog = LoadPacificDialogs( "English" )[uuid]
		DialogManager.Sv_PlayDialog( uuid, entryName, nil, DialogType.Call, dialog and dialog.speaker, DialogPriority.MainQuest, nil )
		sm.log.info( "[PacificScrap] Call:", entryName )
	end
end
