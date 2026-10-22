-- The Farmers' Hideout shop. Survival's hideout trader (HideoutTrader.lua)
-- keeps its vacuum: crates dropped in its dropzone and sucked in with its
-- button land in the trader's container. But its menu and unlock progression
-- are replaced by this simple shop (HIDEOUT_TRADES in layouts.lua): the
-- Fabricator's menu at its normal size, crate counters in the header (two rows
-- of four), trades in the grid, the selected trade on the right.
--
-- These functions are put on Survival's HideoutTrader class by
-- ApplySurvivalPatches (survival_patches.lua), so they run as that script.
-- Delivered crates are also reported to the game for the Roadside Picnic
-- quest (Story.lua).

-- Copied onto HideoutTrader (it may not exist yet when this loads)
HideoutShop = {}

local ShopSlotFile = dofile( "$SURVIVAL_DATA/Gui/JsonGuis/ItemSlot.gui" )
local ShopGuiFile = dofile( "$CONTENT_DATA/Gui/JsonGuis/Fabricator.gui" )
local ShopGui -- built once (BuildShopGui)

local HAVE_COLOUR = "#A3CD46"
local MISSING_COLOUR = "#F42B2B"
local MUTED_COLOUR = "#909292"
local COUNTER_WIDTH = 58 -- a crate counter: number + icon
local COUNTER_ROW = 24 -- (three rows: the crates, then the caged farmers)
local COUNTERS_PER_ROW = 4

local function RenameShopCallbacks( widget, names )
	for key, value in pairs( widget ) do
		if type( value ) == "string" and key:sub( 1, 2 ) == "on" then
			widget[key] = names[value] or "cl_shopNothing"
		end
	end
	for _, child in ipairs( widget.Childs or {} ) do
		RenameShopCallbacks( child, names )
	end
end

local function SetItemIcon( widget, uuid )
	local resource, group, name = sm.gui.getItemIconFromUuid( uuid )
	widget.ImageTexture = nil
	widget.Type = "ImageBox"
	widget.Skin = "ImageBox"
	widget.ImageResource = resource
	widget.ImageGroup = group
	widget.ImageName = name
end

local function BuildShopGui()
	if ShopGui then return ShopGui end
	local gui = {}
	gui.json = DeepCopy( ShopGuiFile )
	RenameShopCallbacks( gui.json, { cl_onTradeClick = "cl_shopTrade", cl_onClose = "cl_shopClose" } )
	gui.Main = FindWidget( gui.json, "MainPanel" )
	gui.Side = FindWidget( gui.json, "TradePanel" )
	gui.MainTitle = FindWidget( gui.Main, "Title" )
	gui.Header = FindWidget( gui.Main, "Image" )
	gui.Grid = FindWidget( gui.Main, "ItemContentPanel" )
	gui.Background = FindWidget( gui.Main, "ScrollBg" )
	FindWidget( gui.Main, "TabsHolder" ).Visible = false
	gui.Preview = FindWidget( gui.Side, "Preview" )
	gui.Title = FindWidget( gui.Side, "Title" )
	gui.Description = FindWidget( gui.Side, "DescriptionBox" )
	gui.Button = FindWidget( gui.Side, "TradeButton" )
	-- (the cost goes in the description: it can be several kinds of crate)
	local trading = FindWidget( gui.Side, "Trading" )
	for i, widget in ipairs( gui.Side.Childs ) do
		if widget == trading then
			for _, w in ipairs( { trading, gui.Side.Childs[i + 1] } ) do
				if w then w.Visible = false; w.height = 0; w.y = 0 end
			end
			break
		end
	end
	local holder = FindWidget( gui.Side, "TradeHolder" )
	holder.Visible = false
	holder.height = 0
	gui.Description.height = 220 -- (the Trade button comes right under it)

	-- Crate counters: the currency box split into one icon + number per crate
	gui.Currency = FindWidget( gui.Main, "Currency" )
	local template = DeepCopy( gui.Currency.Childs )
	gui.Currency.Childs = {}
	if gui.Currency.LayoutRule ~= nil then gui.Currency.LayoutRule = "Absolute" end
	if gui.Currency.Caption ~= nil then gui.Currency.Caption = "" end
	gui.Currency.x = 196
	gui.Currency.y = 86
	gui.Currency.width = COUNTERS_PER_ROW * COUNTER_WIDTH
	gui.Currency.height = math.ceil( #HIDEOUT_CRATES / COUNTERS_PER_ROW ) * COUNTER_ROW
	gui.Counters = {}
	for i, crate in ipairs( HIDEOUT_CRATES ) do
		local counter = {}
		local column, row = ( i - 1 ) % COUNTERS_PER_ROW, math.floor( ( i - 1 ) / COUNTERS_PER_ROW )
		for _, widget in ipairs( DeepCopy( template ) ) do
			if widget.Name == "AvailableAmountValue" then
				counter.value = widget
				widget.Name = "CrateCount" .. i
				widget.x = column * COUNTER_WIDTH
				widget.width = COUNTER_WIDTH - 28
			elseif widget.Name == "Icon" then
				counter.icon = widget
				widget.Name = "CrateIcon" .. i
				widget.x = column * COUNTER_WIDTH + COUNTER_WIDTH - 28
			end
			widget.y = row * COUNTER_ROW
			table.insert( gui.Currency.Childs, widget )
		end
		SetItemIcon( counter.icon, sm.uuid.new( crate.uuid ) )
		gui.Counters[i] = counter
	end

	gui.Slot = DeepCopy( ShopSlotFile )
	removeFromArray( gui.Slot.Childs, function( widget ) return widget.Type == "EffectBox" or widget.Name == "KeyItem" end )
	gui.SlotRoot = FindWidget( gui.Slot, "Item" )
	gui.SlotImage = FindWidget( gui.Slot, "Image" )
	gui.SlotQuantity = FindWidget( gui.Slot, "Quantity" )
	ShopGui = gui
	return gui
end

-- "Carrot crate", "Caged Farmer"
local function CrateTitle( uuid )
	for _, crate in ipairs( HIDEOUT_CRATES ) do
		if crate.uuid == uuid then return crate.farmer and crate.title or ( crate.title .. " crate" ) end
	end
	return sm.shape.getShapeTitle( sm.uuid.new( uuid ) )
end

local function IsFarmer( uuid )
	for _, crate in ipairs( HIDEOUT_CRATES ) do
		if crate.uuid == uuid then return crate.farmer == true end
	end
	return false
end


-- Client ------------------------------------------------------------------------

function HideoutShop.client_onInteract( self, character, state )
	if state then
		self:cl_shopOpen()
	end
end

function HideoutShop.cl_shopNothing( self ) end

function HideoutShop.cl_shopOpen( self )
	BuildShopGui()
	self.cl.shop = self.cl.shop or { selected = 1 }
	if not self.cl.shopGui or not sm.exists( self.cl.shopGui ) then
		self.cl.shopGui = sm.jsonGui.createGui( { handleKeySetup = "Hideout", name = "Hideout" } )
	end
	self:cl_shopRender()
end

function HideoutShop.cl_shopClose( self )
	if self.cl.shopGui and sm.exists( self.cl.shopGui ) then
		self.cl.shopGui:close()
	end
	self.cl.shopGui = nil
end

function HideoutShop.cl_shopCount( self, uuid )
	local container = self.interactable:getContainer( 0 )
	return container and sm.container.totalQuantity( container, sm.uuid.new( uuid ) ) or 0
end

function HideoutShop.cl_shopCanAfford( self, trade )
	for uuid, amount in pairs( trade.cost ) do
		if self:cl_shopCount( uuid ) < amount then return false end
	end
	return true
end

function HideoutShop.cl_shopSelect( self, widgetName, data )
	self.cl.shop.selected = data and data.index or 1
	self:cl_shopRender()
end

function HideoutShop.cl_shopTrade( self )
	local index = self.cl.shop and self.cl.shop.selected
	if index and HIDEOUT_TRADES[index] and self:cl_shopCanAfford( HIDEOUT_TRADES[index] ) then
		sm.effect.playEffect( "audio:event:/ui/trading/trade" )
		self.network:sendToServer( "sv_n_shopTrade", { index = index } )
	end
end

function HideoutShop.cl_n_shopTraded( self )
	self:cl_shopRender()
end

function HideoutShop.cl_shopRender( self )
	if not self.cl.shopGui or not sm.exists( self.cl.shopGui ) then return end
	local gui = ShopGui
	gui.MainTitle.Caption = "FARMERS' TRADES"
	SetItemIcon( gui.Header, sm.uuid.new( HIDEOUT_CRATES[1].uuid ) )
	for i, crate in ipairs( HIDEOUT_CRATES ) do
		local count = self:cl_shopCount( crate.uuid )
		gui.Counters[i].value.Caption = ( count > 0 and "#FFFFFF" or "#595959" ) .. tostring( count )
	end

	-- The trades
	gui.Grid.Childs = {}
	for index, trade in ipairs( HIDEOUT_TRADES ) do
		local resource, group, name = sm.gui.getItemIconFromUuid( sm.uuid.new( trade.item ) )
		gui.SlotImage.ImageResource = resource
		gui.SlotImage.ImageGroup = group
		gui.SlotImage.ImageName = name
		gui.SlotImage.Alpha = self:cl_shopCanAfford( trade ) and 1 or 0.45
		gui.SlotImage.InheritsAlpha = false
		if gui.SlotQuantity then
			gui.SlotQuantity.Caption = "x" .. trade.quantity
			gui.SlotQuantity.Visible = true
		end
		gui.SlotRoot.onClick = "cl_shopSelect"
		gui.SlotRoot.onClickData = { index = index }
		gui.Slot.StateSelected = index == self.cl.shop.selected
		local slot = DeepCopy( gui.Slot )
		slot.Name = "Trade" .. index
		table.insert( gui.Grid.Childs, slot )
	end

	-- The selected trade
	local trade = HIDEOUT_TRADES[self.cl.shop.selected] or HIDEOUT_TRADES[1]
	local uuid = sm.uuid.new( trade.item )
	gui.Preview.ItemPreview = trade.item
	gui.Title.Caption = trade.quantity .. "x " .. sm.shape.getShapeTitle( uuid )
	local lines = { "#FFFFFFCosts" }
	local farmers = false
	for crateUuid, amount in pairs( trade.cost ) do
		local have = self:cl_shopCount( crateUuid )
		farmers = farmers or IsFarmer( crateUuid )
		lines[#lines + 1] = ( have >= amount and HAVE_COLOUR or MISSING_COLOUR ) .. amount .. "x " .. CrateTitle( crateUuid )
			.. MUTED_COLOUR .. "  (you've delivered " .. have .. ")"
	end
	lines[#lines + 1] = ""
	if farmers then
		lines[#lines + 1] = MUTED_COLOUR .. "Rescue caged farmers out in the zone, drop them in the hideout's dropzone and press its button to bring them in."
	else
		lines[#lines + 1] = MUTED_COLOUR .. "Bring crates from the packing stations, drop them in the hideout's dropzone and press its button to deliver them."
	end
	lines[#lines + 1] = ""
	lines[#lines + 1] = "#FFFFFF" .. sm.shape.getShapeDescription( uuid )
	gui.Description.Caption = table.concat( lines, "\n" )
	gui.Button.Caption = "Trade"
	gui.Button.Enabled = self:cl_shopCanAfford( trade )
	self.cl.shopGui:render( gui.json )
end

-- (called every frame on top of Survival's): the counters follow deliveries
function HideoutShop_ClientOnUpdate( self, dt )
	if self.cl and self.cl.shopGui and sm.exists( self.cl.shopGui ) then
		self.cl.shopTimer = ( self.cl.shopTimer or 0 ) + dt
		if self.cl.shopTimer > 1.0 then
			self.cl.shopTimer = 0
			self:cl_shopRender()
		end
	end
end


-- Server ------------------------------------------------------------------------

function HideoutShop.sv_n_shopTrade( self, params, player )
	local trade = HIDEOUT_TRADES[params and params.index or 0]
	local container = self.interactable:getContainer( 0 )
	local inventory = player:getInventory()
	if not trade or not container or not inventory then return end
	for uuid, amount in pairs( trade.cost ) do
		if sm.container.totalQuantity( container, sm.uuid.new( uuid ) ) < amount then return end
	end
	sm.container.beginTransaction()
	for uuid, amount in pairs( trade.cost ) do
		sm.container.spend( container, sm.uuid.new( uuid ), amount, true )
	end
	sm.container.collect( inventory, sm.uuid.new( trade.item ), trade.quantity, true )
	if sm.container.endTransaction() then
		if self.sv_saveInventory then self:sv_saveInventory( container ) end
		self.network:sendToClient( player, "cl_n_shopTraded" )
	else
		self.network:sendToClient( player, "cl_n_shopMessage", "Not enough room in your inventory" )
	end
end

function HideoutShop.cl_n_shopMessage( self, text )
	sm.gui.displayAlertText( text, 3 )
end
