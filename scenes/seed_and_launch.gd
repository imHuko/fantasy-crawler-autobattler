extends Node

func _ready() -> void:
	_seed_test_data()
	await get_tree().process_frame
	get_tree().change_scene_to_file("res://scenes/management_screen.tscn")

func _seed_test_data() -> void:
	PlayerInventory.gear_inventory.clear()
	PlayerInventory.troop_roster.clear()
	PlayerInventory.current_stage = 1

	var knight = TroopData.new()
	knight.troop_name = "Sir Aldric"
	knight.troop_type = TroopData.TroopType.KNIGHT
	knight.base_stats = { "hp": 200, "attack": 15, "defense": 20, "speed": 2 }
	PlayerInventory.troop_roster.append(knight)

	var mage = TroopData.new()
	mage.troop_name = "Lyra"
	mage.troop_type = TroopData.TroopType.MAGE
	mage.base_stats = { "hp": 80, "attack": 30, "defense": 5, "speed": 4 }
	PlayerInventory.troop_roster.append(mage)

	var healer = TroopData.new()
	healer.troop_name = "Brother Edwyn"
	healer.troop_type = TroopData.TroopType.HEALER
	healer.base_stats = { "hp": 120, "attack": 8, "defense": 10, "speed": 3 }
	PlayerInventory.troop_roster.append(healer)

	for i in range(6):
		var biomes = ["crypt", "forest_ruins", "dragon_lair"]
		var biome = biomes[randi() % biomes.size()]
		PlayerInventory.gear_inventory.append(GearGenerator.generate(biome, randi_range(2, 6)))

	print("[Seed] Ready — ", PlayerInventory.troop_roster.size(), " troops, ", PlayerInventory.gear_inventory.size(), " gear items.")
