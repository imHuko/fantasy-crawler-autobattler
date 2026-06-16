extends Node

# -------------------------------------------------------
# Rarity Weights by Difficulty (1-10)
# -------------------------------------------------------
const RARITY_WEIGHTS = {
	1:  { "COMMON": 80, "RARE": 16, "EPIC": 3,  "LEGENDARY": 1  },
	2:  { "COMMON": 72, "RARE": 22, "EPIC": 5,  "LEGENDARY": 1  },
	3:  { "COMMON": 62, "RARE": 27, "EPIC": 8,  "LEGENDARY": 3  },
	4:  { "COMMON": 50, "RARE": 30, "EPIC": 14, "LEGENDARY": 6  },
	5:  { "COMMON": 40, "RARE": 32, "EPIC": 20, "LEGENDARY": 8  },
	6:  { "COMMON": 30, "RARE": 32, "EPIC": 26, "LEGENDARY": 12 },
	7:  { "COMMON": 20, "RARE": 30, "EPIC": 32, "LEGENDARY": 18 },
	8:  { "COMMON": 12, "RARE": 26, "EPIC": 36, "LEGENDARY": 26 },
	9:  { "COMMON": 6,  "RARE": 20, "EPIC": 38, "LEGENDARY": 36 },
	10: { "COMMON": 2,  "RARE": 12, "EPIC": 36, "LEGENDARY": 50 },
}

# Stat count per rarity
const STAT_ROLLS = {
	"COMMON":    { "count": 1, "min": 3,  "max": 8  },
	"RARE":      { "count": 2, "min": 6,  "max": 15 },
	"EPIC":      { "count": 3, "min": 10, "max": 24 },
	"LEGENDARY": { "count": 4, "min": 16, "max": 38 },
}

# Quality tier stat multipliers (applied on top of normal max)
const QUALITY_MULTIPLIERS = {
	"AWAKENED":     { "min_mult": 1.0,  "max_mult": 1.5  },
	"ASCENDANT":    { "min_mult": 1.5,  "max_mult": 2.2  },
	"TRANSCENDENT": { "min_mult": 2.2,  "max_mult": 3.0  },
}

const SLOT_STATS = {
	"WEAPON":    ["attack", "attack_speed", "crit_chance", "crit_damage"],
	"ARMOR":     ["hp", "armor", "hp", "attack_speed"],
	"RING":      ["attack", "crit_chance", "crit_damage", "hp"],
	"ACCESSORY": ["hp", "armor", "attack", "crit_chance"],
}

const FLOAT_STATS = ["crit_chance", "attack_speed"]
const FLOAT_RANGES = {
	"crit_chance": {
		"COMMON":    {"min": 0.02, "max": 0.05},
		"RARE":      {"min": 0.04, "max": 0.09},
		"EPIC":      {"min": 0.07, "max": 0.14},
		"LEGENDARY": {"min": 0.12, "max": 0.22},
	},
	"attack_speed": {
		"COMMON":    {"min": 0.03, "max": 0.07},
		"RARE":      {"min": 0.06, "max": 0.12},
		"EPIC":      {"min": 0.10, "max": 0.18},
		"LEGENDARY": {"min": 0.15, "max": 0.28},
	},
}
const CRIT_DMG_RANGES = {
	"COMMON":    {"min": 8,  "max": 18},
	"RARE":      {"min": 15, "max": 28},
	"EPIC":      {"min": 22, "max": 40},
	"LEGENDARY": {"min": 35, "max": 60},
}

const SETS = {
	"Dragon Scale": {
		"WEAPON": "Dragon Fang Blade", "ARMOR": "Dragon Scale Chestplate",
		"RING": "Dragon Eye Ring",     "ACCESSORY": "Dragon Tooth Pendant",
	},
	"Iron Oath": {
		"WEAPON": "Iron Oath Sword", "ARMOR": "Iron Oath Plate",
		"RING": "Iron Oath Band",    "ACCESSORY": "Iron Oath Buckle",
	},
	"Emberborn": {
		"WEAPON": "Ember Wand",    "ARMOR": "Emberborn Robe",
		"RING": "Ember Signet",    "ACCESSORY": "Smoldering Charm",
	},
	"Shadow Veil": {
		"WEAPON": "Shadow Dagger",    "ARMOR": "Shadow Veil Cloak",
		"RING": "Void Ring",          "ACCESSORY": "Darkstone Pendant",
	},
	"Storm Aegis": {
		"WEAPON": "Stormcaller Staff", "ARMOR": "Storm Aegis Plate",
		"RING": "Tempest Band",        "ACCESSORY": "Lightning Charm",
	},
}

const BIOME_SET_WEIGHTS = {
	"crypt":        {"Dragon Scale": 10, "Iron Oath": 20, "Emberborn": 15, "Shadow Veil": 40, "Storm Aegis": 15},
	"forest_ruins": {"Dragon Scale": 25, "Iron Oath": 30, "Emberborn": 20, "Shadow Veil": 15, "Storm Aegis": 10},
	"dragon_lair":  {"Dragon Scale": 50, "Iron Oath": 10, "Emberborn": 25, "Shadow Veil": 5,  "Storm Aegis": 10},
}

const GENERIC_NAMES = {
	"WEAPON":    ["Soldier's Blade", "Worn Shortsword", "Cracked Staff", "Bent Dagger", "Old Mace"],
	"ARMOR":     ["Battered Chestplate", "Torn Robe", "Dented Cuirass", "Rough Hide Armor", "Frayed Tunic"],
	"RING":      ["Plain Band", "Scratched Ring", "Simple Loop", "Crude Circle", "Worn Ring"],
	"ACCESSORY": ["Frayed Charm", "Old Pendant", "Rough Talisman", "Simple Brooch", "Worn Amulet"],
}
const RARITY_PREFIXES = {
	"COMMON": "", "RARE": "Fine ", "EPIC": "Superior ", "LEGENDARY": "Ancient "
}

# -------------------------------------------------------
# Main Generation
# -------------------------------------------------------
func generate(biome: String, difficulty: int) -> GearItem:
	difficulty = clamp(difficulty, 1, 10)
	var gear = GearItem.new()

	var rarity_name = _roll_rarity(difficulty)
	gear.rarity = GearItem.Rarity[rarity_name]

	var slot_name = _roll_slot()
	gear.slot = GearItem.Slot[slot_name]

	# Roll quality tier (checks talent unlocks)
	var quality_name = _roll_quality(rarity_name)
	gear.quality = GearItem.Quality[quality_name]

	# Name
	if randf() < _get_set_threshold(rarity_name):
		gear.set_name = _roll_set(biome)
		gear.item_name = SETS[gear.set_name][slot_name]
	else:
		gear.set_name = ""
		var base = GENERIC_NAMES[slot_name][randi() % GENERIC_NAMES[slot_name].size()]
		gear.item_name = RARITY_PREFIXES[rarity_name] + base

	# Roll stats with quality multiplier
	var stat_result = _roll_stats(slot_name, rarity_name, quality_name)
	gear.stats = stat_result["stats"]
	gear.stat_ranges = stat_result["ranges"]

	return gear

# -------------------------------------------------------
# Quality Rolling — gated by talents
# -------------------------------------------------------
func _roll_quality(rarity_name: String) -> String:
	var t = PlayerInventory.talents

	# Transcendent check
	if t["transcendent_unlock"] and t["transcendent_chance"] > 0:
		if rarity_name == "LEGENDARY" and randf() < t["transcendent_chance"]:
			return "TRANSCENDENT"

	# Ascendant check
	if t["ascendant_unlock"]:
		var chance = 0.0
		if rarity_name == "LEGENDARY":   chance = t["ascendant_chance_legendary"]
		elif rarity_name == "EPIC":       chance = t["ascendant_chance_epic"]
		if chance > 0 and randf() < chance:
			return "ASCENDANT"

	# Awakened check
	if t["awakened_unlock"]:
		var chance = 0.0
		if rarity_name == "LEGENDARY":   chance = t["awakened_chance_legendary"]
		elif rarity_name == "EPIC":       chance = t["awakened_chance_epic"]
		if chance > 0 and randf() < chance:
			return "AWAKENED"

	return "NORMAL"

# -------------------------------------------------------
# Stat Rolling
# -------------------------------------------------------
func _roll_stats(slot_name: String, rarity_name: String, quality_name: String) -> Dictionary:
	var roll_info = STAT_ROLLS[rarity_name]
	var available = SLOT_STATS[slot_name].duplicate()
	available.shuffle()
	var unique_stats = []
	for s in available:
		if s not in unique_stats:
			unique_stats.append(s)

	var q_mult = QUALITY_MULTIPLIERS.get(quality_name, {"min_mult": 1.0, "max_mult": 1.0})
	var stats = {}
	var ranges = {}
	var base_count = roll_info["count"]

	# Sharper Eye talent: Common/Rare gear has a chance to roll one extra stat
	if rarity_name in ["COMMON", "RARE"] and PlayerInventory.unlocked_talents.get("gear_sharper_eye", false):
		if randf() < 0.25:
			base_count += 1

	var count = min(base_count, unique_stats.size())

	for i in range(count):
		var stat = unique_stats[i]
		var rolled_val
		var range_min
		var range_max

		if stat == "crit_damage":
			var r = CRIT_DMG_RANGES[rarity_name]
			range_min = r["min"]
			range_max = int(r["max"] * q_mult["max_mult"])
			var q_min = int(r["max"] * q_mult["min_mult"]) if quality_name != "NORMAL" else r["min"]
			rolled_val = randi_range(q_min, range_max)
		elif stat in FLOAT_STATS:
			var r = FLOAT_RANGES[stat][rarity_name]
			range_min = r["min"]
			range_max = snappedf(r["max"] * q_mult["max_mult"], 0.01)
			var q_min = snappedf(r["max"] * q_mult["min_mult"], 0.01) if quality_name != "NORMAL" else r["min"]
			rolled_val = snappedf(randf_range(q_min, range_max), 0.01)
		else:
			range_min = roll_info["min"]
			range_max = int(roll_info["max"] * q_mult["max_mult"])
			var q_min = int(roll_info["max"] * q_mult["min_mult"]) if quality_name != "NORMAL" else roll_info["min"]
			rolled_val = randi_range(q_min, range_max)

		stats[stat] = rolled_val
		ranges[stat] = {
			"rolled": rolled_val,
			"min": range_min,
			"max": range_max,
			"is_quality": quality_name != "NORMAL"
		}

	return {"stats": stats, "ranges": ranges}

# -------------------------------------------------------
# Helpers
# -------------------------------------------------------
func _roll_rarity(difficulty: int) -> String:
	var weights = RARITY_WEIGHTS[difficulty]
	var total = 0
	for w in weights.values(): total += w
	var roll = randi() % total
	var cumulative = 0
	for rarity in weights:
		cumulative += weights[rarity]
		if roll < cumulative:
			return rarity
	return "COMMON"

func _roll_slot() -> String:
	return GearItem.Slot.keys()[randi() % GearItem.Slot.keys().size()]

func _get_set_threshold(rarity_name: String) -> float:
	var base_threshold = 0.08
	match rarity_name:
		"COMMON":    base_threshold = 0.08
		"RARE":      base_threshold = 0.20
		"EPIC":      base_threshold = 0.50
		"LEGENDARY": base_threshold = 0.85

	if PlayerInventory.unlocked_talents.get("gear_set_seeker", false):
		base_threshold = min(1.0, base_threshold * 1.5)

	return base_threshold

func _roll_set(biome: String) -> String:
	var weights = BIOME_SET_WEIGHTS.get(biome, BIOME_SET_WEIGHTS["forest_ruins"])
	var total = 0
	for w in weights.values(): total += w
	var roll = randi() % total
	var cumulative = 0
	for sname in weights:
		cumulative += weights[sname]
		if roll < cumulative:
			return sname
	return "Iron Oath"
