dofile( "$SURVIVAL_DATA/Scripts/util.lua" )
dofile( "$CONTENT_DATA/Scripts/upgrade_tree.lua" )
dofile( "$CONTENT_DATA/Scripts/layouts.lua" )
dofile( "$CONTENT_DATA/Scripts/wide_gui.lua" )

-- Fabricator: a bot in the garage with a Pacific Drive style upgrade tree.
-- Pay with energy anchors (stable, unstable, corrupted) to unlock schematics,
-- which then show up in the Craftbot. Anchors can't go in the inventory, so the
-- Fabricator keeps a bank: carry an anchor to it and click to deposit
-- (survival_patches.lua hooks the carry tool for that).
-- The menu is survival's mining hub trader menu (Gui/JsonGuis/Fabricator.gui)
-- with category tabs; the upgrades themselves are in upgrade_tree.lua. Each tab
-- is drawn as a tree: upgrades left to right by what they require, joined by
-- lines, on a canvas inside the menu's scroll panel.
Fabricator = class()
Fabricator.maxParentCount = 0
Fabricator.maxChildCount = 0


local SufficientColor = "#A3CD46"
local InsufficientColor = "#F42B2B"
local MutedColor = "#909292"

-- Schematic slot for the grid, cleaned up the same way the trader does it
local Slot = DeepCopy( dofile( "$SURVIVAL_DATA/Gui/JsonGuis/ItemSlotSchematic.gui" ) )
local SlotRoot = FindWidget( Slot, "Item" )
local SlotImage = FindWidget( Slot, "Image" )
removeFromArray( Slot.Childs, function( widget ) return widget.Type == "EffectBox" end )
-- (the wheel zooms the tree, and a drag can start on a node)
Slot.onMouseWheel = "cl_treeWheel"
for _, child in ipairs( Slot.Childs ) do
	child.onMouseWheel = "cl_treeWheel"
end
SlotRoot.onPressed = "cl_treeDragStart"
SlotRoot.onDrag = "cl_treeDragMove"
SlotRoot.onReleased = "cl_treeDragEnd"

local Gui = {}
Gui.json = DeepCopy( dofile( "$CONTENT_DATA/Gui/JsonGuis/Fabricator.gui" ) )
Gui.MainPanel = FindWidget( Gui.json, "MainPanel" )
Gui.TradePanel = FindWidget( Gui.json, "TradePanel" )
Gui.Header = FindWidget( Gui.MainPanel, "Image" )
Gui.Grid = FindWidget( Gui.MainPanel, "ItemContentPanel" )
Gui.Preview = FindWidget( Gui.TradePanel, "Preview" )
Gui.Title = FindWidget( Gui.TradePanel, "Title" )
Gui.Description = FindWidget( Gui.TradePanel, "DescriptionBox" )

Gui.UnlockIcon = FindWidget( Gui.TradePanel, "TradeIcon" )
Gui.UnlockCount = FindWidget( Gui.TradePanel, "TradeCount" )
Gui.UnlockButton = FindWidget( Gui.TradePanel, "TradeButton" )
-- The tab buttons in Fabricator.gui, left to right, get UPGRADE_TABS' names and
-- captions (so the tabs follow upgrade_tree.lua, whatever the .gui calls them)
local function TabButtons( widget, found )
	for _, child in ipairs( widget.Childs or {} ) do
		if child.onClick == "cl_selectTab" then
			table.insert( found, child )
		end
		TabButtons( child, found )
	end
	return found
end
local tabButtons = TabButtons( Gui.MainPanel, {} )
table.sort( tabButtons, function( a, b ) return a.x < b.x end )
Gui.Tabs = {}
for i, tab in ipairs( UPGRADE_TABS ) do
	local button = tabButtons[i]
	if button then
		button.Name = tab.name
		FindWidget( button, "TabText" ).Caption = tab.caption
		Gui.Tabs[tab.name] = button
	end
end

-- Splits a "value + icon" widget into one per anchor kind, side by side.
-- Returns { [kind] = { value = widget, icon = widget } }.
local function SplitCurrency( holder, valueName, iconName, x, width, blockWidth )
	local template = DeepCopy( holder.Childs )
	holder.Childs = {}
	holder.x = x
	holder.width = width
	-- (only set what the widget already has: plain widgets have no Caption)
	if holder.LayoutRule ~= nil then
		holder.LayoutRule = "Absolute"
	end
	if holder.Caption ~= nil then
		holder.Caption = ""
	end
	local blocks = {}
	for i, anchor in ipairs( ENERGY_ANCHORS ) do
		local value, icon
		for _, widget in ipairs( DeepCopy( template ) ) do
			if widget.Name == valueName then
				value = widget
				widget.Name = valueName .. "_" .. anchor.name
				widget.x = ( i - 1 ) * blockWidth
				widget.width = blockWidth - 28
			elseif widget.Name == iconName then
				icon = widget
				widget.Name = iconName .. "_" .. anchor.name
				widget.x = ( i - 1 ) * blockWidth + blockWidth - 26
			end
			table.insert( holder.Childs, widget )
		end
		blocks[anchor.name] = { value = value, icon = icon }
	end
	return blocks
end

Gui.Available = SplitCurrency( FindWidget( Gui.MainPanel, "Currency" ), "AvailableAmountValue", "Icon", 210, 210, 70 )
-- (the cost row uses the whole box, no "Cost" label, so all three kinds fit:
-- the box is 173 wide. Its labels' font only has capital letters.)
Gui.Cost = SplitCurrency( FindWidget( Gui.TradePanel, "Cost" ), "CostValue", "Currency", 4, 165, 55 )

-- Tree layout (pixels)
local TREE_PAD = 12
local TREE_COLUMN = 108   -- grid cell, left to right (square cells: diagonals at 45 degrees)
local TREE_ROW = 108      -- grid cell, top to bottom
local NODE_SIZE = 74
local LINE_WIDTH = 3
-- The tree view: drag to move it, the wheel zooms (towards the mouse), like the
-- Route Planner's map; the tree itself stays a tidy grid
local TREE_ZOOM_MIN = 0.35
local TREE_ZOOM_MAX = 1.6
local TREE_ZOOM_STEP = 1.15
local TREE_CELLS_X = 24 -- the wheel finds the mouse to within one of these cells
local TREE_CELLS_Y = 12
local TREE_GLIDE = 8.0 -- how fast the view glides to a clicked item

-- Frame colours behind a node
local FrameColours = {
	unlocked = "0.64 0.80 0.27 1",   -- green: owned
	available = "1 0.83 0.29 1",     -- yellow: can buy now
	expensive = "0.96 0.45 0.17 1",  -- orange: next up, not enough anchors banked
	locked = "0.45 0.45 0.45 1",     -- grey: needs the one before it
	selected = "1 1 1 1",
}

local function Rect( name, x, y, width, height, colour, alpha )
	return {
		Name = name, Type = "Widget", Skin = "WhiteSkin", Colour = colour, Alpha = alpha or 1,
		InheritsAlpha = false, NeedKey = false, NeedMouse = false, Childs = {},
		x = math.floor( x ), y = math.floor( y ), width = math.max( math.floor( width ), 1 ), height = math.max( math.floor( height ), 1 ),
	}
end

-- Scales a widget and everything in it (for shrinking the tree to fit)
function ScaleWidget( widget, scale )
	if scale == 1 then return end
	for _, key in ipairs( { "x", "y", "width", "height" } ) do
		if type( widget[key] ) == "number" then
			widget[key] = math.floor( widget[key] * scale + 0.5 )
		end
	end
	for _, child in ipairs( widget.Childs or {} ) do
		ScaleWidget( child, scale )
	end
end

local function SetIcon( widget, uuid )
	local resource, group, name = sm.gui.getItemIconFromUuid( uuid )
	widget.ImageTexture = nil -- a texture would win over the item icon
	widget.Type = "ImageBox"
	widget.Skin = "ImageBox"
	widget.ImageResource = resource
	widget.ImageGroup = group
	widget.ImageName = name
end


-- Server ------------------------------------------------------------------------

function Fabricator.server_onCreate( self )
	self.sv = {}
	self.sv.saved = self.storage:load() or {}
	self.sv.saved.bank = self.sv.saved.bank or {}
	for _, anchor in ipairs( ENERGY_ANCHORS ) do
		self.sv.saved.bank[anchor.name] = self.sv.saved.bank[anchor.name] or 0
	end
	self.network:setClientData( { bank = self.sv.saved.bank } )
end

function Fabricator.sv_save( self )
	self.storage:save( self.sv.saved )
	self.network:setClientData( { bank = self.sv.saved.bank } )
end

-- Carry tool click with an anchor (see survival_patches.lua): bank it
-- Anchors that came home from the zone (GarageWorld.sv_bankAnchors):
-- { [kind name] = count }
function Fabricator.sv_e_depositAnchors( self, counts )
	for name, count in pairs( counts or {} ) do
		self.sv.saved.bank[name] = ( self.sv.saved.bank[name] or 0 ) + count
	end
	self:sv_save()
	sm.effect.playEffect( "PowerSocket - Activate", self.shape.worldPosition, nil, self.shape.worldRotation )
end

function Fabricator.sv_e_receiveItem( self, params )
	local anchor = EnergyAnchorOf( params.itemA )
	if not anchor then
		return
	end
	sm.container.beginTransaction()
	sm.container.spend( params.containerA, params.itemA, 1, true )
	if sm.container.endTransaction() then
		self.sv.saved.bank[anchor.name] = self.sv.saved.bank[anchor.name] + 1
		self:sv_save()
		sm.effect.playEffect( "PowerSocket - Activate", self.shape.worldPosition, nil, self.shape.worldRotation )
	end
end

function Fabricator.sv_n_unlock( self, params, player )
	local upgrade = UPGRADES[params.index]
	if not upgrade or RecipeManager.Sv_IsUnlocked( upgrade.item ) then
		return
	end
	for _, item in ipairs( UpgradeRequirements( upgrade ) ) do
		if not RecipeManager.Sv_IsUnlocked( item ) then
			return
		end
	end

	local bank = self.sv.saved.bank
	for kind, amount in pairs( upgrade.cost ) do
		if ( bank[kind] or 0 ) < amount then
			self.network:sendToClient( player, "cl_n_message", "Not enough energy anchors banked" )
			return
		end
	end
	for kind, amount in pairs( upgrade.cost ) do
		bank[kind] = bank[kind] - amount
	end
	self:sv_save()

	RecipeManager.Sv_UnlockRecipe( upgrade.item )
	for _, extra in ipairs( upgrade.extras or {} ) do
		RecipeManager.Sv_UnlockRecipe( extra )
	end
	self.network:sendToClients( "cl_n_unlocked", { item = upgrade.item } )
	sm.event.sendToGame( "sv_e_fabricatorUnlocked" ) -- (the Gearing Up quest, Story.lua)
end


-- Client ------------------------------------------------------------------------

function Fabricator.client_onCreate( self )
	self.cl = { activeTab = UPGRADE_TABS[1].name, justUnlocked = {}, bank = {} }
	-- Animations (the mini craftbot's: survival's mechanic station workbench,
	-- whose model this is; Crafter.lua drives them the same way)
	self.cl.anim = { name = nil, time = 0, duration = 1, craftTime = 0 }
	self.cl.upDown, self.cl.leftRight = 0.5, 0.5
	for _, name in ipairs( { "aimbend_updown", "aimbend_leftright" } ) do
		if self.interactable:hasAnim( name ) then self.interactable:setAnimEnabled( name, true ) end
	end
end

-- How long it "crafts" after an unlock (seconds of its craft loop)
local FABRICATOR_CRAFT_SECONDS = 2.5
-- Looking at you when you come near (survival's workbench settings)
local FABRICATOR_LOOK = { range = 3.5, headUp = -0.2, headForward = -1.5, lerp = 1.0 / 15.0 }

-- The workbench's animations: offline without power, turning on, idling (now
-- and then an idle special), and a craft (start, loop, finish) after each
-- unlock; while idle it looks at the nearest player
function Fabricator.cl_updateAnimation( self, dt )
	local anim = self.cl.anim
	anim.time = anim.time + dt
	local done = anim.time > anim.duration
	if done then anim.time = math.fmod( anim.time, anim.duration ) end
	anim.craftTime = math.max( anim.craftTime - dt, 0 )
	local name = anim.name
	if not self.interactable.active then
		name = "offline"
	elseif name == nil or name == "offline" then
		name = "turnon"
	elseif anim.craftTime > 0 and ( name == "idle" or name == "idlespecial01" or name == "idlespecial02" ) then
		name = "craft_start"
	elseif done then
		if name == "craft_start" then
			name = "craft_loop"
		elseif name == "craft_loop" then
			if anim.craftTime <= 0 then name = "craft_finish" end
		elseif name == "idle" then
			local roll = math.random( 1, 5 )
			name = ( roll == 1 and "idlespecial01" ) or ( roll == 2 and "idlespecial02" ) or "idle"
		else
			name = "idle" -- (after turning on, an idle special or a craft)
		end
	end
	if name ~= anim.name then
		if anim.name and self.interactable:hasAnim( anim.name ) then
			self.interactable:setAnimEnabled( anim.name, false )
			self.interactable:setAnimProgress( anim.name, 0 )
		end
		anim.name, anim.time = name, 0
		if self.interactable:hasAnim( name ) then
			anim.duration = math.max( self.interactable:getAnimDuration( name ), 0.01 )
			self.interactable:setAnimEnabled( name, true )
		end
	end
	if self.interactable:hasAnim( anim.name ) then
		self.interactable:setAnimProgress( anim.name, math.min( anim.time / anim.duration, 1 ) )
	end
	-- Looking at the nearest player while idle (as survival's workbench does)
	local upDown, leftRight = 0.5, 0.5
	if anim.name == "idle" then
		local player = GetClosestPlayer( self.shape.worldPosition, FABRICATOR_LOOK.range, self.shape.body:getWorld() )
		if player and player.character then
			local up, right, forward = self.shape:getAt(), -self.shape:getRight(), self.shape:getUp()
			local target = player.character.worldPosition
			if forward:dot( ( target - self.shape.worldPosition ):safeNormalize( forward ) ) > 0 then
				local from = self.shape.worldPosition + up * FABRICATOR_LOOK.headUp + forward * FABRICATOR_LOOK.headForward
				local look = ( target - from ):safeNormalize( forward )
				upDown = sm.util.clamp( 1.0 - ( ( look:dot( up ) + 1 ) / 2 ), 0, 1 )
				leftRight = sm.util.clamp( ( look:dot( right ) + 1 ) / 2, 0, 1 )
			end
		end
	end
	self.cl.upDown = magicInterpolation( self.cl.upDown, upDown, dt, FABRICATOR_LOOK.lerp )
	self.cl.leftRight = magicInterpolation( self.cl.leftRight, leftRight, dt, FABRICATOR_LOOK.lerp )
	if self.interactable:hasAnim( "aimbend_updown" ) then self.interactable:setAnimProgress( "aimbend_updown", self.cl.upDown ) end
	if self.interactable:hasAnim( "aimbend_leftright" ) then self.interactable:setAnimProgress( "aimbend_leftright", self.cl.leftRight ) end
end

function Fabricator.client_onClientDataUpdate( self, data )
	self.cl.bank = data.bank or {}
	self.cl.dirty = true
end

function Fabricator.cl_canAfford( self, upgrade )
	for kind, amount in pairs( upgrade.cost ) do
		if ( self.cl.bank[kind] or 0 ) < amount then return false end
	end
	return true
end

function Fabricator.client_onDestroy( self )
	self:cl_onClose()
end

-- No power in the garage yet (the Getting Started quest): it doesn't work.
-- The server shows the power state as the interactable being on.
function Fabricator.server_onFixedUpdate( self )
	if sm.game.getCurrentTick() % 40 == 11 and self.interactable.active ~= ( g_garagePowered == true ) then
		self.interactable.active = g_garagePowered == true
	end
end

function Fabricator.client_canInteract( self )
	if not self.interactable.active then
		sm.gui.setInteractionText( "No power", "Put the battery in the garage's socket" )
		return false
	end
	sm.gui.setInteractionText( "", sm.gui.getKeyBinding( "Use", true ), "Upgrades" )
	return true
end

function Fabricator.client_onInteract( self, character, state )
	if not state then
		return
	end
	-- Currency icons (the trader's "wonk" coin becomes the anchors)
	for _, anchor in ipairs( ENERGY_ANCHORS ) do
		local uuid = sm.uuid.new( anchor.uuid )
		SetIcon( Gui.Available[anchor.name].icon, uuid )
		SetIcon( Gui.Cost[anchor.name].icon, uuid )
	end
	SetIcon( Gui.Header, sm.uuid.new( ENERGY_ANCHORS[1].uuid ) )
	-- Across the whole screen (the tree gets the room), like the Route Planner
	WidenHideoutGui( Gui.json, Gui.MainPanel, { FindWidget( Gui.MainPanel, "ScrollBg" ), Gui.Grid }, { FindWidget( Gui.MainPanel, "Currency" ) } )

	if self.cl.gui == nil then
		self.cl.gui = sm.jsonGui.createGui( { handleKeySetup = "Hideout", name = "Hideout" } )
	else
		self.cl.gui:setHidden( false )
	end
	self.cl.treeCam = nil
	self:cl_selectTab( self.cl.activeTab )
end

function Fabricator.cl_isUnlocked( self, item )
	return self.cl.justUnlocked[item] or RecipeManager.Cl_IsUnlocked( item )
end

function Fabricator.cl_requirementsMet( self, upgrade )
	for _, item in ipairs( UpgradeRequirements( upgrade ) ) do
		if not self:cl_isUnlocked( item ) then
			return false
		end
	end
	return true
end


function Fabricator.cl_selectTab( self, widgetName )
	for name, tab in pairs( Gui.Tabs ) do
		local selected = name == widgetName
		tab.StateSelected = selected
		FindWidget( tab, "TabText" ).TextColour = selected and "0 0 0 1" or "1 1 1 0.5"
	end
	if Gui.Tabs[widgetName] then
		if self.cl.activeTab ~= widgetName then
			self.cl.treeCam, self.cl.treeTarget = nil, nil -- (a new tab starts with the whole tree in view)
		end
		self.cl.activeTab = widgetName
		self.cl.selected = nil
		self.cl.dirty = true
	end
end

function Fabricator.cl_selectUpgrade( self, widgetName, data )
	if self.cl.treeDragMoved then
		self.cl.treeDragMoved = false
		return -- that was a drag, not a click
	end
	self.cl.selected = data
	self.cl.dirty = true
	-- Glide the view over to it
	local point = data and self.cl.treePoints and self.cl.treePoints[data.index]
	if point then
		self.cl.treeTarget = { x = point.x, y = point.y }
	end
end

-- Tree view: wheel zoom (about the mouse: the grid cell, or the node, the wheel
-- turned over) and dragging
function Fabricator.cl_treeWheel( self, widgetName, scrollValue )
	local view, cam = self.cl.treeView, self.cl.treeCam
	if not view or not cam then return end
	local old = self.cl.treeZoom or 1.0
	local zoom = ( scrollValue or 0 ) > 0 and old * TREE_ZOOM_STEP or old / TREE_ZOOM_STEP
	zoom = math.max( math.min( zoom, TREE_ZOOM_MAX ), TREE_ZOOM_MIN )
	local sx, sy
	local cx, cy = tostring( widgetName or "" ):match( "^TreeCell_(%d+)_(%d+)$" )
	if cx then
		sx, sy = ( tonumber( cx ) + 0.5 ) * view.cellW, ( tonumber( cy ) + 0.5 ) * view.cellH
	else
		local index = tonumber( tostring( widgetName or "" ):match( "^Node(%d+)$" ) or "" )
		local point = index and self.cl.treePoints and self.cl.treePoints[index]
		if point then
			sx, sy = view.w * 0.5 + ( point.x - cam.x ) * old, view.h * 0.5 + ( point.y - cam.y ) * old
		end
	end
	if sx then
		local mx = cam.x + ( sx - view.w * 0.5 ) / old
		local my = cam.y + ( sy - view.h * 0.5 ) / old
		self.cl.treeCam = { x = mx - ( sx - view.w * 0.5 ) / zoom, y = my - ( sy - view.h * 0.5 ) / zoom }
	end
	self.cl.treeZoom = zoom
	self.cl.dirty = true
end

function Fabricator.cl_treeDragStart( self, widgetName, x, y )
	self.cl.treeTarget = nil -- (dragging takes over from a glide)
	self.cl.treeDrag = { x = x, y = y, cam = self.cl.treeCam }
	self.cl.treeDragMoved = false
end

function Fabricator.cl_treeDragMove( self, widgetName, x, y )
	local drag = self.cl.treeDrag
	if not drag or not drag.cam or not self.cl.treeZoom then return end
	if math.abs( x - drag.x ) + math.abs( y - drag.y ) > 4 then
		self.cl.treeDragMoved = true -- (so letting go isn't a click)
	end
	self.cl.treeCam = { x = drag.cam.x - ( x - drag.x ) / self.cl.treeZoom, y = drag.cam.y - ( y - drag.y ) / self.cl.treeZoom }
	self.cl.dirty = true
end

function Fabricator.cl_treeDragEnd( self )
	self.cl.treeDrag = nil
end

function Fabricator.cl_onTradeClick( self )
	if not self.cl.selected then
		return
	end
	if self.cl.gui and sm.exists( self.cl.gui ) then
		local effectBox = self.cl.gui:getWidget( "TradeButtonEffectBox" )
		if effectBox then
			effectBox:startEffect( "tradebutton" )
		end
	end
	sm.effect.playEffect( "audio:event:/ui/trading/trade" )
	self.network:sendToServer( "sv_n_unlock", { index = self.cl.selected.index } )
end

function Fabricator.cl_n_unlocked( self, params )
	self.cl.justUnlocked[params.item] = true
	self.cl.dirty = true
	self.cl.anim.craftTime = FABRICATOR_CRAFT_SECONDS -- (it crafts the schematic)
end

function Fabricator.cl_n_message( self, text )
	sm.gui.displayAlertText( text, 3 )
end

function Fabricator.cl_onClose( self )
	if self.cl.gui and sm.exists( self.cl.gui ) then
		self.cl.gui:close()
	end
	self.cl.gui = nil
end

function Fabricator.cl_updateGui( self )
	for _, anchor in ipairs( ENERGY_ANCHORS ) do
		Gui.Available[anchor.name].value.Caption = anchor.colour .. tostring( self.cl.bank[anchor.name] or 0 )
	end

	self:cl_buildTree()

	-- Side panel: the selected upgrade
	local upgrade = self.cl.selected and UPGRADES[self.cl.selected.index]
	if not upgrade then
		Gui.TradePanel.Visible = false
		return
	end
	Gui.TradePanel.Visible = true
	local uuid = sm.uuid.new( upgrade.item )
	Gui.Title.Caption = sm.shape.getShapeTitle( uuid )
	Gui.Preview.ItemPreview = tostring( uuid )
	SetIcon( Gui.UnlockIcon, uuid )
	Gui.UnlockCount.Caption = ""

	local unlocked = self:cl_isUnlocked( upgrade.item )
	local prerequisiteMet = self:cl_requirementsMet( upgrade )
	local status
	for _, anchor in ipairs( ENERGY_ANCHORS ) do
		local amount = upgrade.cost[anchor.name] or 0
		local colour = ( unlocked or amount == 0 ) and MutedColor
			or ( ( self.cl.bank[anchor.name] or 0 ) >= amount and SufficientColor or InsufficientColor )
		Gui.Cost[anchor.name].value.Caption = colour .. tostring( amount )
	end
	if unlocked then
		status = SufficientColor .. "Unlocked. Craft it at a Craftbot."
	elseif not prerequisiteMet then
		local missing = {}
		for _, item in ipairs( UpgradeRequirements( upgrade ) ) do
			if not self:cl_isUnlocked( item ) then
				missing[#missing + 1] = sm.shape.getShapeTitle( sm.uuid.new( item ) )
			end
		end
		status = InsufficientColor .. "Requires: " .. table.concat( missing, ", " )
	else
		status = MutedColor .. "Unlocks this schematic for the Craftbot."
	end
	Gui.Description.Caption = status .. "\n\n#FFFFFF" .. sm.shape.getShapeDescription( uuid )
	Gui.UnlockButton.Enabled = not unlocked and prerequisiteMet and self:cl_canAfford( upgrade )
end

-- The active tab as a tree on a canvas, laid out on a grid like Pacific Drive's
-- fabrication station: what an upgrade leads to sits in the cells around it,
-- carrying on outward (the way it came first, then turning), joined by straight
-- lines, diagonals too. Separate trees are packed in rows, a cell apart.
function Fabricator.cl_buildTree( self )
	local tab = self.cl.activeTab
	local inTab, list = {}, {}
	for index, upgrade in ipairs( UPGRADES ) do
		if upgrade.tab == tab then
			inTab[upgrade.item] = index
			list[#list + 1] = index
		end
	end
	local parents, children = {}, {}
	for _, index in ipairs( list ) do
		parents[index] = {}
		for _, item in ipairs( UpgradeRequirements( UPGRADES[index] ) ) do
			local parent = inTab[item]
			if parent then
				table.insert( parents[index], parent )
				children[parent] = children[parent] or {}
				table.insert( children[parent], index )
			end
		end
	end

	-- Grid cells: each tree laid out on its own from its root, breadth first (an
	-- upgrade goes in the free cell next to the one it came from, keeping the
	-- same heading if it can), then the trees packed in rows like tiles
	local cellOf = {}
	-- (the 8 neighbours, starting with the heading and turning away from it bit by bit)
	local AROUND = { { 1, 0 }, { 1, 1 }, { 0, 1 }, { -1, 1 }, { -1, 0 }, { -1, -1 }, { 0, -1 }, { 1, -1 } }
	local function key( x, y ) return x .. "," .. y end
	local function freeNear( taken, x, y, hx, hy )
		local start = 1
		for i, d in ipairs( AROUND ) do
			if d[1] == hx and d[2] == hy then start = i end
		end
		for turn = 0, 4 do
			for _, side in ipairs( turn == 0 and { 0 } or { -turn, turn } ) do
				local d = AROUND[( start - 1 + side ) % 8 + 1]
				if not taken[key( x + d[1], y + d[2] )] then return x + d[1], y + d[2], d[1], d[2] end
			end
		end
		-- (all 8 taken: the nearest free cell further out)
		for r = 2, 12 do
			for dx = r, -r, -1 do
				for dy = -r, r do
					if math.max( math.abs( dx ), math.abs( dy ) ) == r and not taken[key( x + dx, y + dy )] then
						return x + dx, y + dy, ( dx > 0 and 1 ) or ( dx < 0 and -1 ) or 0, ( dy > 0 and 1 ) or ( dy < 0 and -1 ) or 0
					end
				end
			end
		end
		return x + 13, y, 1, 0
	end
	local trees = {} -- { members = { [index] = { x, y } }, minX, minY, w, h }
	local placed = {}
	local function layOut( rootIndex )
		local tree = { members = {} }
		local taken, heading = {}, {}
		local function put( index, x, y )
			tree.members[index] = { x = x, y = y }
			taken[key( x, y )] = true
			placed[index] = true
		end
		put( rootIndex, 0, 0 )
		heading[rootIndex] = { 1, 0 }
		local queue, at = { rootIndex }, 1
		while queue[at] do
			local index = queue[at]
			at = at + 1
			for _, kid in ipairs( children[index] or {} ) do
				if not placed[kid] then
					local c, h = tree.members[index], heading[index]
					local x, y, hx, hy = freeNear( taken, c.x, c.y, h[1], h[2] )
					put( kid, x, y )
					heading[kid] = { hx, hy }
					queue[#queue + 1] = kid
				end
			end
		end
		local minX, minY, maxX, maxY = math.huge, math.huge, -math.huge, -math.huge
		for _, c in pairs( tree.members ) do
			minX, maxX = math.min( minX, c.x ), math.max( maxX, c.x )
			minY, maxY = math.min( minY, c.y ), math.max( maxY, c.y )
		end
		tree.minX, tree.minY, tree.w, tree.h = minX, minY, maxX - minX + 1, maxY - minY + 1
		trees[#trees + 1] = tree
	end
	for _, index in ipairs( list ) do
		if #parents[index] == 0 and not placed[index] then layOut( index ) end
	end
	-- (anything left, only reachable through a loop: a tree of its own)
	for _, index in ipairs( list ) do
		if not placed[index] then layOut( index ) end
	end
	-- Packing: rows of trees, a cell apart, about twice as wide as tall
	local area, widest = 0, 0
	for _, tree in ipairs( trees ) do
		area = area + ( tree.w + 1 ) * ( tree.h + 1 )
		widest = math.max( widest, tree.w )
	end
	local rowWidth = math.max( widest, math.ceil( math.sqrt( area * 2 ) ) )
	local penX, penY, shelf = 0, 0, 0
	for _, tree in ipairs( trees ) do
		if penX > 0 and penX + tree.w > rowWidth then
			penX, penY, shelf = 0, penY + shelf + 1, 0
		end
		for index, c in pairs( tree.members ) do
			cellOf[index] = { x = penX + c.x - tree.minX, y = penY + c.y - tree.minY }
		end
		penX = penX + tree.w + 1
		shelf = math.max( shelf, tree.h )
	end
	-- As columns and rows from the top left
	local minX, minY, maxX, maxY = math.huge, math.huge, -math.huge, -math.huge
	for _, c in pairs( cellOf ) do
		minX, maxX = math.min( minX, c.x ), math.max( maxX, c.x )
		minY, maxY = math.min( minY, c.y ), math.max( maxY, c.y )
	end
	local depth, row = {}, {}
	for index, c in pairs( cellOf ) do
		depth[index] = c.x - minX
		row[index] = c.y - minY
	end
	local maxDepth = #list > 0 and maxX - minX or 0
	local rows = #list > 0 and maxY - minY + 1 or 0

	-- The view: the tree (unscaled grid units) around a camera, times the zoom
	local viewW, viewH = Gui.Grid.width - 12, Gui.Grid.height - 12
	local treeW = maxDepth * TREE_COLUMN + NODE_SIZE
	local treeH = math.max( rows - 1, 0 ) * TREE_ROW + NODE_SIZE
	if not self.cl.treeCam then
		-- A new tab (or just opened): the whole tree in view if it fits, up to full size
		self.cl.treeZoom = math.max( math.min( ( viewW - 2 * TREE_PAD ) / treeW, ( viewH - 2 * TREE_PAD ) / treeH, 1.0 ), TREE_ZOOM_MIN )
		self.cl.treeCam = { x = treeW * 0.5, y = treeH * 0.5 }
	end
	-- (the middle of the view stays on the tree)
	self.cl.treeCam.x = math.max( math.min( self.cl.treeCam.x, treeW ), 0 )
	self.cl.treeCam.y = math.max( math.min( self.cl.treeCam.y, treeH ), 0 )
	local scale = self.cl.treeZoom
	local cam = self.cl.treeCam
	self.cl.treeView = { w = viewW, h = viewH, cellW = viewW / TREE_CELLS_X, cellH = viewH / TREE_CELLS_Y }
	local nodeSize = math.floor( NODE_SIZE * scale )
	local nodes = {}
	self.cl.treePoints = {}
	for _, index in ipairs( list ) do
		local gx, gy = depth[index] * TREE_COLUMN, row[index] * TREE_ROW
		nodes[index] = { x = viewW * 0.5 + ( gx - cam.x ) * scale, y = viewH * 0.5 + ( gy - cam.y ) * scale }
		self.cl.treePoints[index] = { x = gx + NODE_SIZE * 0.5, y = gy + NODE_SIZE * 0.5 }
	end

	local canvas = {
		Name = "TreeCanvas", Type = "Widget", Skin = "PanelEmpty", LayoutRule = "Absolute",
		NeedKey = false, NeedMouse = true, Childs = {}, x = 0, y = 0, width = viewW, height = viewH,
		onMouseWheel = "cl_treeWheel",
	}
	-- Behind everything: invisible buttons in a grid over the view, catching
	-- drags and the wheel (which cell got the wheel says where the mouse is)
	local cellW, cellH = self.cl.treeView.cellW, self.cl.treeView.cellH
	for cy = 0, TREE_CELLS_Y - 1 do
		for cx = 0, TREE_CELLS_X - 1 do
			local x, y = math.floor( cx * cellW ), math.floor( cy * cellH )
			canvas.Childs[#canvas.Childs + 1] = {
				Name = "TreeCell_" .. cx .. "_" .. cy, Type = "Button", Skin = "PanelEmpty", NeedKey = false, NeedMouse = true, Childs = {},
				x = x, y = y, width = math.floor( ( cx + 1 ) * cellW ) - x, height = math.floor( ( cy + 1 ) * cellH ) - y,
				onPressed = "cl_treeDragStart", onDrag = "cl_treeDragMove", onReleased = "cl_treeDragEnd", onMouseWheel = "cl_treeWheel",
			}
		end
	end

	-- What state each upgrade is in
	local states = {}
	for _, index in ipairs( list ) do
		local upgrade = UPGRADES[index]
		if self:cl_isUnlocked( upgrade.item ) then
			states[index] = "unlocked"
		elseif not self:cl_requirementsMet( upgrade ) then
			states[index] = "locked"
		else
			states[index] = self:cl_canAfford( upgrade ) and "available" or "expensive"
		end
	end

	-- Lines first, so they sit behind the nodes: straight from one item to the
	-- next, edge to edge. Level or upright ones are one bar; any other (a
	-- diagonal) is a row of dots, as widgets can't be turned. A line is lit once
	-- its requirement is owned.
	local t = math.max( math.floor( LINE_WIDTH * scale + 0.5 ), 2 )
	local half = nodeSize * 0.5
	local gap = half + math.max( math.floor( 3 * scale + 0.5 ), 2 ) + 2 -- (clear of the frames)
	for _, index in ipairs( list ) do
		local node = nodes[index]
		for n, parentIndex in ipairs( parents[index] ) do
			local parent = nodes[parentIndex]
			local lit = states[parentIndex] == "unlocked"
			local colour = lit and FrameColours.unlocked or FrameColours.locked
			local alpha = lit and 1 or 0.6
			local ax, ay = parent.x + half, parent.y + half
			local bx, by = node.x + half, node.y + half
			local name = "Line" .. index .. "_" .. n
			if math.abs( ay - by ) < 1 then
				local x1, x2 = math.min( ax, bx ) + gap, math.max( ax, bx ) - gap
				if x2 > x1 then table.insert( canvas.Childs, Rect( name, x1, ay - t * 0.5, x2 - x1, t, colour, alpha ) ) end
			elseif math.abs( ax - bx ) < 1 then
				local y1, y2 = math.min( ay, by ) + gap, math.max( ay, by ) - gap
				if y2 > y1 then table.insert( canvas.Childs, Rect( name, ax - t * 0.5, y1, t, y2 - y1, colour, alpha ) ) end
			else
				-- (from where the line leaves one frame to where it meets the other)
				local dx, dy = bx - ax, by - ay
				local length = math.sqrt( dx * dx + dy * dy )
				local reach = gap / math.max( math.abs( dx ), math.abs( dy ) ) * length -- (a square frame's edge along this line)
				local step = t * 2.2
				local dots = math.floor( ( length - 2 * reach ) / step )
				for d = 0, dots do
					local along = ( reach + d * step ) / length
					table.insert( canvas.Childs, Rect( name .. "_" .. d, ax + dx * along - t * 0.5, ay + dy * along - t * 0.5, t, t, colour, alpha ) )
				end
			end
		end
	end

	-- Nodes: a coloured frame with the item slot on top
	for _, index in ipairs( list ) do
		local node = nodes[index]
		local upgrade = UPGRADES[index]
		local selected = self.cl.selected ~= nil and self.cl.selected.index == index
		local state = states[index]
		local border = math.max( math.floor( 3 * scale + 0.5 ), 2 )
		table.insert( canvas.Childs, Rect( "Frame" .. index, node.x - border, node.y - border, nodeSize + border * 2, nodeSize + border * 2,
			selected and FrameColours.selected or FrameColours[state], state == "locked" and 0.5 or 1 ) )

		local resource, group, name = sm.gui.getItemIconFromUuid( sm.uuid.new( upgrade.item ) )
		SlotImage.ImageResource = resource
		SlotImage.ImageGroup = group
		SlotImage.ImageName = name
		SlotImage.Alpha = state == "locked" and 0.35 or 1
		SlotImage.InheritsAlpha = false
		SlotRoot.onClick = "cl_selectUpgrade"
		SlotRoot.onClickData = { index = index }
		Slot.StateSelected = selected
		local slot = DeepCopy( Slot )
		-- (the little schematic icon only while it's still to unlock)
		local keyIcon = FindWidget( slot, "KeyItem" )
		if keyIcon then keyIcon.Visible = state ~= "unlocked" end
		ScaleWidget( slot, scale )
		slot.Name = "Node" .. index
		slot.x = math.floor( node.x )
		slot.y = math.floor( node.y )
		table.insert( canvas.Childs, slot )
	end

	table.insert( canvas.Childs, {
		Name = "TreeHint", Type = "TextBox", Skin = "TextBox", FontName = "SM_TextTiny", TextAlign = "Left",
		NeedKey = false, NeedMouse = false, Childs = {}, Caption = "#707272Drag to move, scroll to zoom",
		x = 8, y = viewH - 20, width = 260, height = 16,
	} )

	Gui.Grid.LayoutRule = "Vertical"
	Gui.Grid.GridItemSize = nil
	Gui.Grid.Childs = { canvas }
end

function Fabricator.client_onUpdate( self, dt )
	self:cl_updateAnimation( dt )
	if not self.cl.gui or not sm.exists( self.cl.gui ) or self.cl.gui:isHidden() then
		return
	end
	-- Gliding to a clicked item
	local target, cam = self.cl.treeTarget, self.cl.treeCam
	if target and cam then
		local t = 1 - math.exp( -dt * TREE_GLIDE )
		cam.x, cam.y = cam.x + ( target.x - cam.x ) * t, cam.y + ( target.y - cam.y ) * t
		if math.abs( target.x - cam.x ) + math.abs( target.y - cam.y ) < 1 then
			cam.x, cam.y = target.x, target.y
			self.cl.treeTarget = nil
		end
		self.cl.dirty = true
	end
	-- Redraw when something changed, and now and then to catch inventory changes
	self.cl.redrawTimer = ( self.cl.redrawTimer or 0 ) + dt
	if self.cl.dirty or self.cl.redrawTimer > 0.5 then
		self.cl.dirty = false
		self.cl.redrawTimer = 0
		self:cl_updateGui()
		self.cl.gui:render( Gui.json )
	end
end
