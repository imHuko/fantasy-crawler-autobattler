extends Node

func _ready() -> void:
	print("\n========== GEAR GENERATOR TEST ==========\n")
	_test_rarity_distribution()
	_test_biome_drops()
	_test_difficulty_scaling()
	print("\n========== TEST END ==========\n")

func _test_rarity_distribution() -> void:
	print(">> Rarity distribution at difficulty 5 (100 rolls):")
	var counts = { "COMMON": 0, "RARE": 0, "EPIC": 0, "LEGENDARY": 0 }
	for i in range(100):
		var gear = GearGenerator.generate("forest_ruins", 5)
		counts[gear.get_rarity_name()] += 1
	print("  ", counts)
	print("")

func _test_biome_drops() -> void:
	print(">> Sample drops from each biome at difficulty 6:\n")

	for biome in ["crypt", "forest_ruins", "dragon_lair"]:
		print("  -- ", biome.to_upper(), " --")
		for i in range(3):
			var gear = GearGenerator.generate(biome, 6)
			print("  [", gear.get_rarity_name(), "] ", gear.item_name,
				  " | ", gear.get_slot_name(),
				  " | Set: ", gear.set_name if gear.set_name != "" else "None",
				  " | Stats: ", gear.stats)
		print("")

func _test_difficulty_scaling() -> void:
	print(">> Difficulty scaling — one item at each level:\n")
	for diff in [1, 3, 5, 7, 10]:
		var gear = GearGenerator.generate("dragon_lair", diff)
		print("  Diff ", diff, ": [", gear.get_rarity_name(), "] ",
			  gear.item_name, " | Stats: ", gear.stats)
	print("")
