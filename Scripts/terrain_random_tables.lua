-- Survival's random swaps for prefabs and blueprints placed in tiles (copied from
-- Survival/Scripts/terrain/terrain_overworld.lua). Ruins use these, e.g. their haypiles.

blueprintTable = {}

blueprintTable["Kit_RoadsideMarket_Antenna"] =						{	"$SURVIVAL_DATA/LocalBlueprints/Kit_RoadsideMarket_Antenna_01.blueprint",
																		"$SURVIVAL_DATA/LocalBlueprints/Kit_RoadsideMarket_Antenna_02.blueprint" }

blueprintTable["Kit_RoadsideMarket_LightLantern"] =					{	"$SURVIVAL_DATA/LocalBlueprints/Kit_RoadsideMarket_LightLantern_01.blueprint",
																		"$SURVIVAL_DATA/LocalBlueprints/Kit_RoadsideMarket_LightLantern_02.blueprint",
																		"$SURVIVAL_DATA/LocalBlueprints/Kit_RoadsideMarket_LightLantern_03.blueprint",
																		"$SURVIVAL_DATA/LocalBlueprints/Kit_RoadsideMarket_LightLantern_04.blueprint",
																		"$SURVIVAL_DATA/LocalBlueprints/Kit_RoadsideMarket_LightLantern_05.blueprint",
																		"$SURVIVAL_DATA/LocalBlueprints/Kit_RoadsideMarket_LightLantern_06.blueprint" }

blueprintTable["RoadsideMarket_Clutter_BoxWood"] =					{{	"$SURVIVAL_DATA/LocalBlueprints/RoadsideMarket_Clutter_BoxWood_01.blueprint", 10 },
																		"$SURVIVAL_DATA/LocalBlueprints/RoadsideMarket_Clutter_BoxWood_02.blueprint",
																		"$SURVIVAL_DATA/LocalBlueprints/RoadsideMarket_Clutter_BoxWood_03.blueprint",
																		"$SURVIVAL_DATA/LocalBlueprints/RoadsideMarket_Clutter_BoxWood_04.blueprint" }

blueprintTable["RoadsideMarket_Clutter_FruitCrateDisplay"] =		{	"$SURVIVAL_DATA/LocalBlueprints/RoadsideMarket_Clutter_FruitCrateDisplay_01.blueprint",
																		"$SURVIVAL_DATA/LocalBlueprints/RoadsideMarket_Clutter_FruitCrateDisplay_02.blueprint",
																		"$SURVIVAL_DATA/LocalBlueprints/RoadsideMarket_Clutter_FruitCrateDisplay_03.blueprint",
																		"$SURVIVAL_DATA/LocalBlueprints/RoadsideMarket_Clutter_FruitCrateDisplay_04.blueprint",
																		"$SURVIVAL_DATA/LocalBlueprints/RoadsideMarket_Clutter_FruitCrateDisplay_05.blueprint" }

blueprintTable["RoadsideMarket_Clutter_PottedPlant"] =				{	"$SURVIVAL_DATA/LocalBlueprints/RoadsideMarket_Clutter_PottedPlant_01.blueprint",
																		"$SURVIVAL_DATA/LocalBlueprints/RoadsideMarket_Clutter_PottedPlant_02.blueprint",
																		"$SURVIVAL_DATA/LocalBlueprints/RoadsideMarket_Clutter_PottedPlant_03.blueprint" }

blueprintTable["RoadsideMarket_Clutter_SeedBag"] =					{	"$SURVIVAL_DATA/LocalBlueprints/RoadsideMarket_Clutter_SeedBag_01.blueprint",
																		"$SURVIVAL_DATA/LocalBlueprints/RoadsideMarket_Clutter_SeedBag_02.blueprint" }

blueprintTable["WarehouseExterior_Barrack"] =						{	"$SURVIVAL_DATA/LocalBlueprints/WarehouseExterior_Barrack_01.blueprint",
																		"$SURVIVAL_DATA/LocalBlueprints/WarehouseExterior_Barrack_02.blueprint",
																		"$SURVIVAL_DATA/LocalBlueprints/WarehouseExterior_Barrack_03.blueprint" }

blueprintTable["WarehouseExterior_Clutter_JunkCrate"] =				{	"$SURVIVAL_DATA/LocalBlueprints/WarehouseExterior_Clutter_JunkCrate_01.blueprint",
																		"$SURVIVAL_DATA/LocalBlueprints/WarehouseExterior_Clutter_JunkCrate_02.blueprint",
																		"$SURVIVAL_DATA/LocalBlueprints/WarehouseExterior_Clutter_JunkCrate_03.blueprint" }

blueprintTable["WarehouseExterior_Clutter_JunkSpill"] =				{	"$SURVIVAL_DATA/LocalBlueprints/WarehouseExterior_Clutter_JunkSpill_01.blueprint",
																		"$SURVIVAL_DATA/LocalBlueprints/WarehouseExterior_Clutter_JunkSpill_02.blueprint",
																		"$SURVIVAL_DATA/LocalBlueprints/WarehouseExterior_Clutter_JunkSpill_03.blueprint" }

blueprintTable["WarehouseExterior_Clutter_Pallet_Junk"] =			{	"$SURVIVAL_DATA/LocalBlueprints/WarehouseExterior_Clutter_Pallet_Junk_01.blueprint",
																		"$SURVIVAL_DATA/LocalBlueprints/WarehouseExterior_Clutter_Pallet_Junk_02.blueprint",
																		"$SURVIVAL_DATA/LocalBlueprints/WarehouseExterior_Clutter_Pallet_Junk_03.blueprint" }

blueprintTable["WarehouseExterior_Roof_Tower_Water"] =				{	"$SURVIVAL_DATA/LocalBlueprints/WarehouseExterior_Roof_Tower_Water_01.blueprint",
																		"$SURVIVAL_DATA/LocalBlueprints/WarehouseExterior_Roof_Tower_Water_02.blueprint" }

blueprintTable["GameplayBlueprints/loot_structureparts_concrete"] =	{	"$SURVIVAL_DATA/LocalBlueprints/GameplayBlueprints/loot_structureparts_concrete_01.blueprint",
																		"$SURVIVAL_DATA/LocalBlueprints/GameplayBlueprints/loot_structureparts_concrete_02.blueprint",
																		"$SURVIVAL_DATA/LocalBlueprints/GameplayBlueprints/loot_structureparts_concrete_03.blueprint",
																		"$SURVIVAL_DATA/LocalBlueprints/GameplayBlueprints/loot_structureparts_concrete_04.blueprint",
																		"$SURVIVAL_DATA/LocalBlueprints/GameplayBlueprints/loot_structureparts_concrete_05.blueprint",
																		"$SURVIVAL_DATA/LocalBlueprints/GameplayBlueprints/loot_structureparts_concrete_06.blueprint",
																		"$SURVIVAL_DATA/LocalBlueprints/GameplayBlueprints/loot_structureparts_concrete_07.blueprint"}

----------------------------------------------------------------------------------------------------

prefabTable = {}

prefabTable["RoadsideMarket_ShackLarge"] =							{	"$SURVIVAL_DATA/LocalPrefabs/RoadsideMarket_ShackLarge_01.prefab",
																		"$SURVIVAL_DATA/LocalPrefabs/RoadsideMarket_ShackLarge_02.prefab",
																		"$SURVIVAL_DATA/LocalPrefabs/RoadsideMarket_ShackLarge_03.prefab",
																		"$SURVIVAL_DATA/LocalPrefabs/RoadsideMarket_ShackLarge_04.prefab" }

prefabTable["RoadsideMarket_ShackMedium"] =							{	"$SURVIVAL_DATA/LocalPrefabs/RoadsideMarket_ShackMedium_01.prefab",
																		"$SURVIVAL_DATA/LocalPrefabs/RoadsideMarket_ShackMedium_02.prefab",
																		"$SURVIVAL_DATA/LocalPrefabs/RoadsideMarket_ShackMedium_03.prefab",
																		"$SURVIVAL_DATA/LocalPrefabs/RoadsideMarket_ShackMedium_04.prefab" }

prefabTable["RoadsideMarket_ShackSmall"] =							{	"$SURVIVAL_DATA/LocalPrefabs/RoadsideMarket_ShackSmall_01.prefab",
																		"$SURVIVAL_DATA/LocalPrefabs/RoadsideMarket_ShackSmall_02.prefab",
																		"$SURVIVAL_DATA/LocalPrefabs/RoadsideMarket_ShackSmall_03.prefab",
																		"$SURVIVAL_DATA/LocalPrefabs/RoadsideMarket_ShackSmall_04.prefab" }

prefabTable["gameplay_prefabs/loot_randomparts_shelf_4x4"] =		{	"$SURVIVAL_DATA/LocalPrefabs/gameplay_prefabs/loot_randomparts_shelf_4x4_01.prefab",
																		"$SURVIVAL_DATA/LocalPrefabs/gameplay_prefabs/loot_randomparts_shelf_4x4_02.prefab",
																		"$SURVIVAL_DATA/LocalPrefabs/gameplay_prefabs/loot_randomparts_shelf_4x4_03.prefab",
																		"$SURVIVAL_DATA/LocalPrefabs/gameplay_prefabs/loot_randomparts_shelf_4x4_04.prefab",
																		"$SURVIVAL_DATA/LocalPrefabs/gameplay_prefabs/loot_randomparts_shelf_4x4_05.prefab",
																		"$SURVIVAL_DATA/LocalPrefabs/gameplay_prefabs/loot_randomparts_shelf_4x4_06.prefab",
																		"$SURVIVAL_DATA/LocalPrefabs/gameplay_prefabs/loot_randomparts_shelf_4x4_07.prefab",
																		"$SURVIVAL_DATA/LocalPrefabs/gameplay_prefabs/loot_randomparts_shelf_4x4_08.prefab",
																		"$SURVIVAL_DATA/LocalPrefabs/gameplay_prefabs/loot_randomparts_shelf_4x4_09.prefab",
																		"$SURVIVAL_DATA/LocalPrefabs/gameplay_prefabs/loot_randomparts_shelf_4x4_10.prefab",
																		"$SURVIVAL_DATA/LocalPrefabs/gameplay_prefabs/loot_randomparts_shelf_4x4_11.prefab",
																		"$SURVIVAL_DATA/LocalPrefabs/gameplay_prefabs/loot_randomparts_shelf_4x4_12.prefab",
																		"$SURVIVAL_DATA/LocalPrefabs/gameplay_prefabs/loot_randomparts_shelf_4x4_13.prefab",
																		"$SURVIVAL_DATA/LocalPrefabs/gameplay_prefabs/loot_randomparts_shelf_4x4_14.prefab",
																		"$SURVIVAL_DATA/LocalPrefabs/gameplay_prefabs/loot_randomparts_shelf_4x4_15.prefab",
																		"$SURVIVAL_DATA/LocalPrefabs/gameplay_prefabs/loot_randomparts_shelf_4x4_16.prefab",
																		"$SURVIVAL_DATA/LocalPrefabs/gameplay_prefabs/loot_randomparts_shelf_4x4_17.prefab",
																		"$SURVIVAL_DATA/LocalPrefabs/gameplay_prefabs/loot_randomparts_shelf_4x4_18.prefab" }

prefabTable["gameplay_prefabs/loot_randomparts_shelf_4x8"] =		{	"$SURVIVAL_DATA/LocalPrefabs/gameplay_prefabs/loot_randomparts_shelf_4x8_01.prefab",
																		"$SURVIVAL_DATA/LocalPrefabs/gameplay_prefabs/loot_randomparts_shelf_4x8_02.prefab",
																		"$SURVIVAL_DATA/LocalPrefabs/gameplay_prefabs/loot_randomparts_shelf_4x8_03.prefab",
																		"$SURVIVAL_DATA/LocalPrefabs/gameplay_prefabs/loot_randomparts_shelf_4x8_04.prefab",
																		"$SURVIVAL_DATA/LocalPrefabs/gameplay_prefabs/loot_randomparts_shelf_4x8_05.prefab",
																		"$SURVIVAL_DATA/LocalPrefabs/gameplay_prefabs/loot_randomparts_shelf_4x8_06.prefab",
																		"$SURVIVAL_DATA/LocalPrefabs/gameplay_prefabs/loot_randomparts_shelf_4x8_07.prefab",
																		"$SURVIVAL_DATA/LocalPrefabs/gameplay_prefabs/loot_randomparts_shelf_4x8_08.prefab",
																		"$SURVIVAL_DATA/LocalPrefabs/gameplay_prefabs/loot_randomparts_shelf_4x8_09.prefab",
																		"$SURVIVAL_DATA/LocalPrefabs/gameplay_prefabs/loot_randomparts_shelf_4x8_09.prefab",
																		"$SURVIVAL_DATA/LocalPrefabs/gameplay_prefabs/loot_randomparts_shelf_4x8_10.prefab",
																		"$SURVIVAL_DATA/LocalPrefabs/gameplay_prefabs/loot_randomparts_shelf_4x8_11.prefab",
																		"$SURVIVAL_DATA/LocalPrefabs/gameplay_prefabs/loot_randomparts_shelf_4x8_12.prefab",
																		"$SURVIVAL_DATA/LocalPrefabs/gameplay_prefabs/loot_randomparts_shelf_4x8_13.prefab",
																		"$SURVIVAL_DATA/LocalPrefabs/gameplay_prefabs/loot_randomparts_shelf_4x8_14.prefab",
																		"$SURVIVAL_DATA/LocalPrefabs/gameplay_prefabs/loot_randomparts_shelf_4x8_15.prefab",
																		"$SURVIVAL_DATA/LocalPrefabs/gameplay_prefabs/loot_randomparts_shelf_4x8_16.prefab",
																		"$SURVIVAL_DATA/LocalPrefabs/gameplay_prefabs/loot_randomparts_shelf_4x8_17.prefab",
																		"$SURVIVAL_DATA/LocalPrefabs/gameplay_prefabs/loot_randomparts_shelf_4x8_18.prefab",
																		"$SURVIVAL_DATA/LocalPrefabs/gameplay_prefabs/loot_randomparts_shelf_4x8_19.prefab",
																		"$SURVIVAL_DATA/LocalPrefabs/gameplay_prefabs/loot_randomparts_shelf_4x8_20.prefab",
																		"$SURVIVAL_DATA/LocalPrefabs/gameplay_prefabs/loot_randomparts_shelf_4x8_21.prefab",
																		"$SURVIVAL_DATA/LocalPrefabs/gameplay_prefabs/loot_randomparts_shelf_4x8_22.prefab" }

prefabTable["gameplay_prefabs/loot_structureparts_wood"] =			{	"$SURVIVAL_DATA/LocalPrefabs/gameplay_prefabs/loot_structureparts_wood_01.prefab",
																		"$SURVIVAL_DATA/LocalPrefabs/gameplay_prefabs/loot_structureparts_wood_02.prefab",
																		"$SURVIVAL_DATA/LocalPrefabs/gameplay_prefabs/loot_structureparts_wood_03.prefab",
																		"$SURVIVAL_DATA/LocalPrefabs/gameplay_prefabs/loot_structureparts_wood_04.prefab",
																		"$SURVIVAL_DATA/LocalPrefabs/gameplay_prefabs/loot_structureparts_wood_05.prefab",
																		"$SURVIVAL_DATA/LocalPrefabs/gameplay_prefabs/loot_structureparts_wood_06.prefab",
																		"$SURVIVAL_DATA/LocalPrefabs/gameplay_prefabs/loot_structureparts_wood_07.prefab",
																		"$SURVIVAL_DATA/LocalPrefabs/gameplay_prefabs/loot_structureparts_wood_08.prefab",
																		"$SURVIVAL_DATA/LocalPrefabs/gameplay_prefabs/loot_structureparts_wood_09.prefab",
																		"$SURVIVAL_DATA/LocalPrefabs/gameplay_prefabs/loot_structureparts_wood_10.prefab" }

prefabTable["gameplay_prefabs/random_abandoned_vehicle"] =			{{	"$SURVIVAL_DATA/LocalPrefabs/gameplay_prefabs/random_abandoned_vehicle_01.prefab", 60 },
																	 {	"$SURVIVAL_DATA/LocalPrefabs/gameplay_prefabs/random_abandoned_vehicle_02.prefab", 1 },
																	 {	"$SURVIVAL_DATA/LocalPrefabs/gameplay_prefabs/random_abandoned_vehicle_03.prefab", 10 },
																	 {	"$SURVIVAL_DATA/LocalPrefabs/gameplay_prefabs/random_abandoned_vehicle_04.prefab", 5 },
																	 {	"$SURVIVAL_DATA/LocalPrefabs/gameplay_prefabs/random_abandoned_vehicle_05.prefab", 10 },
																	 {	"$SURVIVAL_DATA/LocalPrefabs/gameplay_prefabs/random_abandoned_vehicle_06.prefab", 5 },
																	 {	"$SURVIVAL_DATA/LocalPrefabs/gameplay_prefabs/random_abandoned_vehicle_07.prefab", 10 },
																	 {	"$SURVIVAL_DATA/LocalPrefabs/gameplay_prefabs/random_abandoned_vehicle_08.prefab", 5 },
																	 {	"$SURVIVAL_DATA/LocalPrefabs/gameplay_prefabs/random_abandoned_vehicle_09.prefab", 10 },
																	 {	"$SURVIVAL_DATA/LocalPrefabs/gameplay_prefabs/random_abandoned_vehicle_10.prefab", 5 },
																	 {	"$SURVIVAL_DATA/LocalPrefabs/gameplay_prefabs/random_abandoned_vehicle_11.prefab", 10 },
																	 {	"$SURVIVAL_DATA/LocalPrefabs/gameplay_prefabs/random_abandoned_vehicle_12.prefab", 5 }}


prefabTable["GameplayPrefabs/Ruin/surprisespawner_haypile"] =		{{	"$SURVIVAL_DATA/LocalPrefabs/GameplayPrefabs/Ruin/surprisespawner_haypile_01.prefab", 10 },
																	{	"$SURVIVAL_DATA/LocalPrefabs/GameplayPrefabs/Ruin/surprisespawner_haypile_02.prefab", 20 },
																	{	"$SURVIVAL_DATA/LocalPrefabs/GameplayPrefabs/Ruin/surprisespawner_haypile_03.prefab", 1 },
																	{	"$SURVIVAL_DATA/LocalPrefabs/GameplayPrefabs/Ruin/surprisespawner_haypile_04.prefab", 10 }}

----------------------------------------------------------------------------------------------------
