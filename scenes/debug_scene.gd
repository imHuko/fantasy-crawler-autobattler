extends Node

func _ready() -> void:
	print("\n========== DEBUG SCENE START ==========\n")
	_test_gear_items()
	_test_troop_data()
not	_test_inventory()
	print("\n========== DEBUG SCENE END ==========\n")

func _test_gear_items() -> void:
	print(">> Testing GearItem creation...\n")

	var sword = GearItem.new()
	sword.item_name = "Iron Sword"
	sword.rarity = GearItem.Rarity.COMMON
	sword.slot = GearItem.Slot.WEAPON
	sword.stats = { "attack": 8, "crit_chance": 0.05 }
	sword.set_name = "Iron Oath"
	sword.print_info()

	var chestplate = GearItem.new()
	chestplate.item_name = "Dragon Scale Chestplate"
	chestplate.rarity = GearItem.Rarity.RARE
	chestplate.slot = GearItem.Slot.ARMOR
	chestplate.stats = { "defense": 15, "hp": 40 }
	chestplate.set_name = "Dragon Scale"
	chestplate.print_info()

	var ring = GearItem.new()
	ring.item_name = "Legendary Ring of Might"
	ring.rarity = GearItem.Rarity.LEGENDARY
	ring.slot = GearItem.Slot.RING
	ring.stats = { "attack": 20, "speed": 5, "hp": 25 }
	ring.set_name = ""
	ring.print_info()

func _test_troop_data() -> void:
	print(">> Testing TroopData creation and gear equipping...\n")

	var knight = TroopData.new()
	knight.troop_name = "Sir Aldric"
	knight.troop_type = TroopData.TroopType.KNIGHT
	knight.base_stats = { "hp": 200, "attack": 15, "defense": 20, "speed": 2 }

	print("Knight before gear:")
	knight.print_info()

	# Equip a weapon and armor
	var sword = GearItem.new()
	sword.item_name = "Iron Sword"
	sword.rarity = GearItem.Rarity.UNCOMMON
	sword.slot = GearItem.Slot.WEAPON
	sword.stats = { "attack": 12, "crit_chance": 0.08 }
	sword.set_name = "Iron Oath"

	var armor = GearItem.new()
	armor.item_name = "Iron Oath Plate"
	armor.rarity = GearItem.Rarity.UNCOMMON
	armor.slot = GearItem.Slot.ARMOR
	armor.stats = { "defense": 10, "hp": 30 }
	armor.set_name = "Iron Oath"

	knight.equip(sword)
	knight.equip(armor)

	print("Knight after equipping Iron Oath sword + armor:")
	knight.print_info()

func _test_inventory() -> void:
	print(">> Testing PlayerInventory autoload...\n")

	# Create and add a troop
	var mage = TroopData.new()
	mage.troop_name = "Lyra the Arcane"
	mage.troop_type = TroopData.TroopType.MAGE
	mage.base_stats = { "hp": 80, "attack": 30, "defense": 5, "speed": 4 }
	PlayerInventory.add_troop(mage)

	var healer = TroopData.new()
	healer.troop_name = "Brother Edwyn"
	healer.troop_type = TroopData.TroopType.HEALER
	healer.base_stats = { "hp": 100, "attack": 5, "defense": 8, "speed": 3 }
	PlayerInventory.add_troop(healer)

	# Add some gear to inventory
	var wand = GearItem.new()
	wand.item_name = "Ember Wand"
	wand.rarity = GearItem.Rarity.RARE
	wand.slot = GearItem.Slot.WEAPON
	wand.stats = { "attack": 25, "speed": 2 }
	wand.set_name = "Emberborn"
	PlayerInventory.add_gear(wand)

	var robe = GearItem.new()
	robe.item_name = "Emberborn Robe"
	robe.rarity = GearItem.Rarity.RARE
	robe.slot = GearItem.Slot.ARMOR
	robe.stats = { "defense": 6, "hp": 20 }
	robe.set_name = "Emberborn"
	PlayerInventory.add_gear(robe)

	# Equip gear to the mage directly
	mage.equip(wand)
	mage.equip(robe)

	PlayerInventory.print_inventory()
