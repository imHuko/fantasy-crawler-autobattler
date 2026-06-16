extends Node

# -------------------------------------------------------
# Rarity Weights by Difficulty (1-10)
# Higher difficulty = better loot chances
# -------------------------------------------------------

const RARITY_WEIGHTS = {
	1:  { "COMMON": 80, "UNCOMMON": 17, "RARE": 3,  "LEGENDARY": 0  },
	2:  { "COMMON": 72, "UNCOMMON": 22, "RARE": 5,  "LEGENDARY": 1  },
	3:  { "COMMON": 65, "UNCOMMON": 25, "RARE": 8,  "LEGENDARY": 2  },
	4:  { "COMMON": 55, "UNCOMMON": 28, "RARE": 13, "LEGENDARY": 4  },
	5:  { "COMMON": 45, "UNCOMMON": 30, "RARE": 18, "LEGENDARY": 7  },
	6:  { "COMMON": 35, "UNCOMMON": 30, "RARE": 25, "LEGENDARY": 10 },
	7:  { "COMMON": 25, "UNCOMMON": 30, "RARE": 30, "LEGENDARY": 15 },
	8:  { "COMMON": 15, "UNCOMMON": 28, "RARE": 35, "LEGENDARY": 22 },
	9:  { "COMMON": 8,  "UNCOMMON": 22, "RARE": 38, "LEGENDARY": 32 },
	10: { "COMMON": 3,  "UNCOMMON": 15, "RARE": 37, "LEGENDARY": 45 },
}

# -------------------------------------------------------
# Stat Ranges per Rarity
# Each rarity rolls more stats and higher values
# -------------------------------------------------------

const STAT_ROLLS = {
	"COMMON":    { "count": 1, "min": 3,  "max": 8  },
	"UNCOMMON":  { "count": 2, "min": 6,  "max": 14 },
	"RARE":      { "count": 3, "min": 10, "max": 22 },
	"LEGENDARY": { "count": 4, "min": 16, "max": 35 },
}

# Which stats each slot can roll
const SLOT_STATS = {
	"WEAPON":    ["attack", "crit_chance", "speed"],
	"ARMOR":     ["defense", "hp", "speed"],
	"RING":      ["attack", "defense", "hp", "crit_chance"],
	"ACCESSORY": ["hp", "speed", "defense", "attack"],
}

# Special stats that use float ranges instead of int
const FLOAT_STATS = ["crit_chance"]
const FLOAT_STAT_RANGES = {
	"COMMON":    { "min": 0.02, "max": 0.06 },
	"UNCOMMON":  { "min": 0.05, "max": 0.10 },
	"RARE":      { "min": 0.08, "max": 0.16 },
	"LEGENDARY": { "min": 0.13, "max": 0.25 },
}

# -------------------------------------------------------
# Set Definitions
# Each set has themed gear names per slot
# -------------------------------------------------------

const SETS = {
	"Dragon Scale": {
		"WEAPON":    "Dragon Fang Blade",
		"ARMOR":     "Dragon Scale Chestplate",
		"RING":      "Dragon Eye Ring",
		"ACCESSORY": "Dragon Tooth Pendant",
	},
	"Iron Oath": {
		"WEAPON":    "Iron Oath Sword",
		"ARMOR":     "Iron Oath Plate",
		"RING":      "Iron Oath Band",
		"ACCESSORY": "Iron Oath Buckle",
	},
	"Emberborn": {
		"WEAPON":    "Ember Wand",
		"ARMOR":     "Emberborn Robe",
		"RING":      "Ember Signet",
		"ACCESSORY": "Smoldering Charm",
	},
	"Shadow Veil": {
		"WEAPON":    "Shadow Dagger",
		"ARMOR":     "Shadow Veil Cloak",
		"RING":      "Void Ring",
		"ACCESSORY": "Darkstone Pendant",
	},
	"Storm Aegis": {
		"WEAPON":    "Stormcaller Staff",
		"ARMOR":     "Storm Aegis Plate",
		"RING":      "Tempest Band",
		"ACCESSORY": "Lightning Charm",
	},
}

# Biomes influence which sets are more likely to drop
const BIOME_SET_WEIGHTS = {
	"crypt": {
		"Dragon Scale": 10, "Iron Oath": 20, "Emberborn": 15,
		"Shadow Veil": 40, "Storm Aegis": 15
	},
	"forest_ruins": {
		"Dragon Scale": 25, "Iron Oath": 30, "Emberborn": 20,
		"Shadow Veil": 15, "Storm Aegis": 10
	},
	"dragon_lair": {
		"Dragon Scale": 50, "Iron Oath": 10, "Emberborn": 25,
		"Shadow Veil": 5,  "Storm Aegis": 10
	},
}

# Generic names for non-set gear
const GENERIC_NAMES = {
	"WEAPON":    ["Soldier's Blade", "Worn Shortsword", "Cracked Staff", "Bent Dagger", "Old Mace"],
	"ARMOR":     ["Battered Chestplate", "Torn Robe", "Dented Cuirass", "Rough Hide Armor", "Frayed Tunic"],
	"RING":      ["Plain Band", "Scratched Ring", "Simple Loop", "Crude Circle", "Worn Ring"],
	"ACCESSORY": ["Frayed Charm", "Old Pendant", "Rough Talisman", "Simple Brooch", "Worn Amulet"],
}

# -------------------------------------------------------
# Main Generation Function
# -------------------------------------------------------

func generate(biome: String, difficulty: int) -> GearItem:
	difficulty = clamp(difficulty, 1, 10)

	var gear = GearItem.new()

	# Roll rarity
	var rarity_name = _roll_rarity(difficulty)
	gear.rarity = GearItem.Rarity[rarity_name]

	# Roll slot
	var slot_name = _roll_slot()
	gear.slot = GearItem.Slot[slot_name]

	# Roll set (chance based on biome, higher rarity = more likely to be a set piece)
	var set_roll = randf()
	var set_threshold = _get_set_threshold(rarity_name)
	if set_roll < set_threshold:
		gear.set_name = _roll_set(biome)
		gear.item_name = SETS[gear.set_name][slot_name]
	else:
		gear.set_name = ""
		gear.item_name = _roll_generic_name(slot_name, rarity_name)

	# Roll stats
	gear.stats = _roll_stats(slot_name, rarity_name)

	return gear

# -------------------------------------------------------
# Private Helpers
# -------------------------------------------------------

func _roll_rarity(difficulty: int) -> String:
	var weights = RARITY_WEIGHTS[difficulty]
	var total = 0
	for w in weights.values():
		total += w
	var roll = randi() % total
	var cumulative = 0
	for rarity in weights:
		cumulative += weights[rarity]
		if roll < cumulative:
			return rarity
	return "COMMON"

func _roll_slot() -> String:
	var slots = GearItem.Slot.keys()
	return slots[randi() % slots.size()]

func _get_set_threshold(rarity_name: String) -> float:
	match rarity_name:
		"COMMON":    return 0.10  # 10% chance
		"UNCOMMON":  return 0.25  # 25% chance
		"RARE":      return 0.55  # 55% chance
		"LEGENDARY": return 0.90  # 90% chance
	return 0.10

func _roll_set(biome: String) -> String:
	var weights = BIOME_SET_WEIGHTS.get(biome, BIOME_SET_WEIGHTS["forest_ruins"])
	var total = 0
	for w in weights.values():
		total += w
	var roll = randi() % total
	var cumulative = 0
	for set_name in weights:
		cumulative += weights[set_name]
		if roll < cumulative:
			return set_name
	return "Iron Oath"

func _roll_generic_name(slot_name: String, rarity_name: String) -> String:
	var base = GENERIC_NAMES[slot_name][randi() % GENERIC_NAMES[slot_name].size()]
	match rarity_name:
		"UNCOMMON":  return "Fine " + base
		"RARE":      return "Superior " + base
		"LEGENDARY": return "Ancient " + base
	return base

func _roll_stats(slot_name: String, rarity_name: String) -> Dictionary:
	var result = {}
	var roll_info = STAT_ROLLS[rarity_name]
	var available_stats = SLOT_STATS[slot_name].duplicate()
	available_stats.shuffle()

	var count = min(roll_info["count"], available_stats.size())
	for i in range(count):
		var stat = available_stats[i]
		if stat in FLOAT_STATS:
			var range_info = FLOAT_STAT_RANGES[rarity_name]
			var value = randf_range(range_info["min"], range_info["max"])
			result[stat] = snappedf(value, 0.01)
		else:
			result[stat] = randi_range(roll_info["min"], roll_info["max"])

	return result
