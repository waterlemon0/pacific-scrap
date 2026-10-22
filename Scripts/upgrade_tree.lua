-- Fabricator upgrade tree, loaded from Fabricator/upgrade_tree.json (edit it
-- with Tools/fabricator_editor.html). Each upgrade unlocks the crafting recipe
-- (schematic) of an item the Craftbot can make, costs energy anchors, and can
-- require other upgrades first.
--
-- The file: { tabs = { { name, caption }, ... }, upgrades = { upgrade, ... } }
--   tab      which tab it shows under (a tab's name)
--   item     the item whose schematic gets unlocked (also the icon)
--   name     the item's name, so the file is readable (not used by the game)
--   cost     energy anchors by kind, e.g. { stable = 2, unstable = 1, corrupted = 1 }
--            (ENERGY_ANCHORS in layouts.lua)
--   requires items of the upgrades that must ALL be unlocked first (optional)
--   extras   more schematics unlocked along with it (optional)
-- The order of the upgrades is the order of the tree's top-level branches.
--
-- Tier 2-5 engines, seats, suspension etc. aren't crafted in survival; you
-- upgrade a placed part with component kits instead.
UPGRADE_TREE_FILE = "$CONTENT_DATA/Fabricator/upgrade_tree.json"

UPGRADE_TABS = {}
UPGRADES = {}
do
	-- (an empty or broken file, say a save that went wrong, mustn't stop the game loading)
	local data = nil
	if sm.json.fileExists( UPGRADE_TREE_FILE ) then
		local ok, opened = pcall( sm.json.open, UPGRADE_TREE_FILE )
		if ok then data = opened else sm.log.warning( "[PacificScrap] Couldn't read " .. UPGRADE_TREE_FILE .. ": " .. tostring( opened ) ) end
	end
	if type( data ) == "table" then
		for _, tab in ipairs( data.tabs or {} ) do
			if type( tab.name ) == "string" then
				UPGRADE_TABS[#UPGRADE_TABS + 1] = { name = tab.name, caption = tab.caption or tab.name:upper() }
			end
		end
		for _, upgrade in ipairs( data.upgrades or {} ) do
			if type( upgrade.item ) == "string" and type( upgrade.tab ) == "string" then
				upgrade.cost = type( upgrade.cost ) == "table" and upgrade.cost or {}
				UPGRADES[#UPGRADES + 1] = upgrade
			end
		end
	end
	if #UPGRADE_TABS == 0 then
		sm.log.warning( "[PacificScrap] " .. UPGRADE_TREE_FILE .. " is missing or has no tabs: the Fabricator is empty" )
		UPGRADE_TABS[1] = { name = "Tools", caption = "TOOLS" }
	end
end

-- Recipes Survival unlocks from the start (RecipeManager's DefaultUnlockedItems)
local SURVIVAL_DEFAULT_RECIPES = {
	"b63c6440-dfc2-4da7-acdb-3c385080b2e4", -- obj_craftbot_craftbot1
	"5cb15c93-4fa9-48da-9974-2e95ca6c9e1c", -- obj_craftbot_refinery
	"a930a42f-63ed-4fb0-933e-56ce8a889cc5", -- obj_craftbot_resourcecontainer
	"2af00456-b22e-4743-b338-a91934aba7c5", -- obj_craftbot_cookbot
	"767a3121-2c31-473c-a5ab-27e188fdd55a", -- obj_craftbot_dressbot
	"b46c3271-6288-4b74-a6b1-9ea946cf072b", -- obj_interactive_prospector
	"b593a935-802a-4715-b27f-739a091a8977", -- obj_interactive_mineralcrusher
	"80680f7d-5f8a-4bf7-962b-ebd07481cd0a", -- obj_interactive_gravelcollector
	"0a0cc4ee-bdd7-41b1-b5cb-f34a0e6de46e", -- obj_interactive_sawtable1
	"c96ab903-f238-4bae-a614-28a758716d00", -- obj_scrap_gasengine
	"bd597ac9-6640-43ba-9bd8-ed584a794f13", -- obj_scrap_driverseat
	"847daf20-02bf-4170-8699-9ab106acd29a", -- obj_scrap_seat
	"59f6951a-a450-42bf-ad03-54567cb70245", -- obj_scrap_smallwheel
	"4a1b886b-913e-4aad-b5b6-6e41b0db23a6", -- jnt_bearing
	"8c7efc37-cd7c-4262-976e-39585f8527bf", -- tool_connect
	"f0cba95b-2dc4-4492-8fd9-36546a4cb5aa", -- blk_cardboard
	"7cf717d7-d167-4f2d-a6e7-6b2c70aa3986", -- obj_interactive_switch
	"05900757-a49f-4907-b498-96bfd2b15176", -- obj_craftbot_portablecraftbot
	"fdb8b8be-96e7-4de0-85c7-d2f42e4f33ce", -- tool_weld
	"c60b9627-fc2b-4319-97c5-05921cb976c6", -- tool_paint
	"798c2c81-1f8e-481b-8c32-b71b5dc5511a", -- obj_tool_bucket_empty
	"dfefc9d7-db03-4d25-ad85-eae1d824d8c0", -- obj_interactive_radio
	"1e8d93a4-506b-470d-9ada-9c0a321e2db5", -- obj_interactive_button
	"818f4e15-ff51-4fed-b874-723a25d62e1c", -- obj_interactive_horn
	"598d865c-324c-4129-9c57-21a6abd2cb2e", -- obj_interactive_controller_01
	"1bfccc0a-828f-475c-882c-87d5a96054c9", -- obj_interactive_gasengine_01
	"f3cfef9d-faef-4be8-9283-476eb99614d7", -- jnt_suspensionoffroad_01
	"67da25c9-3825-41f6-9724-4546a11cb2a5", -- jnt_suspensionsport_01
	"fcfae5e2-1df9-47d8-bb9a-30bec9b5b1f5", -- obj_container_smallchest
	"4c474cff-3f6a-4306-93d1-c4c74578afd2", -- obj_container_smallchest_pipe
	"69e362c3-32aa-4cd1-adc0-dcfc47b92c0d", -- obj_vehicle_smallwheel
	"db66f0b1-0c50-4b74-bdc7-771374204b1f", -- obj_vehicle_bigwheel
	"77c2687c-2e13-4df8-996a-96fb26d75ee0", -- obj_interactive_driverseat_01
	"3b972f2f-30c7-4a5e-a100-5e257e62295d", -- obj_interactive_seat_01
	"a5985971-1f95-4373-a5d9-4ce0a3e74851", -- obj_interactive_beacon
	"97f449b6-c948-448b-b8b3-4448e3f6b956", -- obj_pneumatic_pump
	"9b8f2abd-265c-4750-b8b9-fe6cb564633c", -- obj_pneumatic_pipe_03
	"5939f460-ab6c-48f2-9d07-a66845ce8cf2", -- obj_pneumatic_pipe_bend
	"bab9d1d1-6131-4329-a6f2-7b2ddf1f25e1", -- obj_pneumatic_pipe_t
	"ed27f5e2-cac5-4a32-a5d9-49f116acc6af", -- obj_light_headlight
	"7527cf2e-1705-4214-9d07-3dc374957e25", -- obj_container_tinychest
	"d4d68946-aa03-4b8f-b1af-96b81ad4e305", -- obj_consumable_gas
	"869d4736-289a-4952-96cd-8a40117a2d28", -- obj_consumable_water
	"f74c2891-79a9-45e0-982e-4896651c2e25", -- obj_consumable_chemical
	"1147e59d-6940-42b4-840b-07f05054f5e0", -- obj_resource_crudeoil
	"36335664-6e61-4d44-9876-54f9660a8565", -- obj_consumable_glue
	"267e0c93-62e3-45ad-9470-a14035cb9ca4", -- obj_resource_ember
	"9a3e478c-2224-44fa-887c-239965bd05ad", -- obj_consumable_soilbag
	"8e61a423-5aa6-4dd3-ac57-ecac313f82f5", -- obj_consumable_tea
	"c7322cd1-3158-41d9-b15a-eff2f2f8d9f7", -- obj_consumable_inkammo
	"4908ecfb-ec05-42c5-a02a-7675ccc3eb19", -- obj_interactive_textsign_small
	"a96232ef-2778-4c23-8a11-7cbc5b1de8b0", -- obj_interactive_textsign_large
	"46d85e5b-353c-4f06-8fd8-b9ddd3443245", -- obj_interactive_textsign_extralarge
	"df953d9c-234f-4ac2-af5e-f0490b223e71", -- blk_wood1
	"8aedf6c2-94e1-4506-89d4-a0227c552f1e", -- blk_metal1
	"3d0b7a6e-5b40-474c-bbaf-efaa54890e6a", -- blk_crossnet
	"927d80d8-84ee-44f0-9d8b-cb7a688e0b6c", -- obj_small_long_pipe
	"0dba257b-b907-4919-baaf-2fefe19f4e24", -- obj_small_2way_pipe
	"8024db09-9147-4fe3-a747-00bc30ab724b", -- obj_small_2wayb_pipe
	"e1273b8a-945b-4080-81eb-cbf79961cccb", -- obj_small_3way_pipe
	"203fdf06-b311-49fd-933d-a1c6b671a017", -- obj_small_3wayb_pipe
	"387095d6-5aba-45e3-abd0-098710c268f8", -- obj_small_4way_pipe
	"5a106512-9284-40de-be68-2c186e903097", -- obj_small_4wayb_pipe
	"c6ebae46-8e69-4ddd-a3c0-895d887027bd", -- obj_small_5way_pipe
	"9c6d8dba-1783-4c42-8a02-6af1c5d63ec6", -- obj_small_6way_pipe
	"54d8ef21-357d-48a3-a66d-40446f6bb686", -- obj_consumable_carrotburger
	"54d84731-d9ec-435d-bc9d-d48e0763b1bf", -- obj_consumable_pizzaburger
	"e243f642-6934-42bb-8cdd-f8ff1704d411", -- obj_consumable_longsandwich
	"1897ee42-0291-43e4-9645-8c5a5d310398", -- blk_wood2
	"1016cafc-9f6b-40c9-8713-9019d399783f", -- blk_metal2
	"a6c6ce30-dd47-4587-b475-085d55c6a3b4", -- blk_concrete1
	"ff234e42-5da4-43cc-8893-940547c97882", -- blk_concrete2
	"c56700d9-bbe5-4b17-95ed-cef05bd8be1b", -- blk_sand
	"5f41af56-df4c-4837-9b3c-10781335757f", -- blk_glass
	"a5a857de-14be-11ed-861d-0242ac120002", -- wdg_scrapwood
	"cb529af8-14b9-11ed-861d-0242ac120002", -- wdg_wood1
	"5dae0b3a-14bf-11ed-861d-0242ac120002", -- wdg_wood2
	"5dae0e46-14bf-11ed-861d-0242ac120002", -- wdg_scrapmetal
	"a358c216-14b9-11ed-861d-0242ac120002", -- wdg_metal1
	"5dae0f2c-14bf-11ed-861d-0242ac120002", -- wdg_metal2
	"e83cd904-14b8-11ed-861d-0242ac120002", -- wdg_concrete1
	"5dae15c6-14bf-11ed-861d-0242ac120002", -- wdg_concrete2
	"3f2e92d0-14c7-11ed-861d-0242ac120002", -- wdg_sand
	"5dae16a2-14bf-11ed-861d-0242ac120002", -- wdg_scrapstone
	"3bb5dc9e-14bd-11ed-861d-0242ac120002", -- wdg_glass
	"9acecf66-14c1-11ed-861d-0242ac120002", -- wdg_crossnet
	"5d5144be-14be-11ed-861d-0242ac120002", -- wdg_cardboard
	"2a583574-6419-496a-b260-3236cc1cca5d", -- wdg_ice
	"4f5f7175-28d0-417c-8b3b-be0b2c0b46f7", -- wdg_dekotora
	"7a0e9041-9dd5-4cb1-b804-69ee16c45efe", -- obj_industrial_windshieldlarge
	"50007ac9-e97d-4b32-9fd6-de919c8a34a4", -- obj_industrial_windshield
}

-- Those that are in the tree come from the Fabricator instead: locked until
-- unlocked there (survival_patches.lua makes Survival's RecipeManager treat
-- them so). The rest (consumables, food, the scrap wedges...) stay free.
LOCKED_DEFAULT_RECIPES = {}
do
	local inTree = {}
	for _, upgrade in ipairs( UPGRADES ) do
		inTree[upgrade.item] = true
		for _, extra in ipairs( upgrade.extras or {} ) do inTree[extra] = true end
	end
	for _, id in ipairs( SURVIVAL_DEFAULT_RECIPES ) do
		if inTree[id] then LOCKED_DEFAULT_RECIPES[id] = true end
	end
end

-- The upgrades an upgrade requires, always as a list
function UpgradeRequirements( upgrade )
	if upgrade.requires == nil then
		return {}
	elseif type( upgrade.requires ) == "table" then
		return upgrade.requires
	end
	return { upgrade.requires }
end
