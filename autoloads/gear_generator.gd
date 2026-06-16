extends Node

# -------------------------------------------------------
# Rarity Weights by Difficulty (1-10)
# -------------------------------------------------------
const RARITY_WEIGHTS = {
	1:  { "COMMON": 915, "RARE": 70,  "EPIC": 10, "LEGENDARY": 5   },
	2:  { "COMMON": 880, "RARE": 100, "EPIC": 18, "LEGENDARY": 2   },
	3:  { "COMMON": 82,  "RARE": 14,  "EPIC": 3,  "LEGENDARY": 1   },
	4:  { "COMMON": 72,  "RARE": 20,  "EPIC": 6,  "LEGENDARY": 2   },
	5:  { "COMMON": 60,  "RARE": 25,  "EPIC": 11, "LEGENDARY": 4   },
	6:  { "COMMON": 46,  "RARE": 28,  "EPIC": 18, "LEGENDARY": 8   },
	7:  { "COMMON": 32,  "RARE": 28,  "EPIC": 26, "LEGENDARY": 14  },
	8:  { "COMMON": 18,  "RARE": 26,  "EPIC": 34, "LEGENDARY": 22  },
	9:  { "COMMON": 8,   "RARE": 20,  "EPIC": 38, "LEGENDARY": 34  },
	10: { "COMMON": 2,   "RARE": 12,  "EPIC": 36, "LEGENDARY": 50  },
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

# Item level (1-10, same scale as dungeon stage/difficulty) scales the
# stat range itself rather than just picking a position within a fixed
# range. This curve is deliberately gentle: a well-rolled Legendary at
# item level 1 should still be clearly strong and worth using for a
# while, not gated down toward Common-tier numbers. Rarity is what
# should carry most of the early power difference; item level is a
# slower-building, longer-term ceiling on top of that.
const ITEM_LEVEL_MULT = {
	1:  0.80, 2:  0.85, 3:  0.90, 4:  0.95, 5:  1.00,
	6:  1.10, 7:  1.25, 8:  1.45, 9:  1.70, 10: 2.00,
}

func _get_item_level_mult(item_level: int) -> float:
	return ITEM_LEVEL_MULT.get(clamp(item_level, 1, 10), 1.0)

# Diminishing returns when the same stat gets picked more than once on a
# single item (e.g. a Legendary rolling HP four times instead of four
# different stats). Each repeat contributes less than the last, so
# stacking is powerful but not simply linear — a 4x stack lands around
# 2.4x a single roll's value, not a full 4x.
const STACK_DIMINISH = [1.0, 0.65, 0.45, 0.30, 0.20, 0.15]

func _get_stack_mult(occurrence_index: int) -> float:
	return STACK_DIMINISH[min(occurrence_index, STACK_DIMINISH.size() - 1)]

const SLOT_STATS = {
	"WEAPON":    ["attack", "attack_speed", "crit_chance", "crit_damage", "spell_power", "lifesteal", "thorns", "move_speed"],
	"ARMOR":     ["hp", "armor", "attack_speed", "spell_power", "lifesteal", "thorns", "move_speed"],
	"RING":      ["attack", "crit_chance", "crit_damage", "hp", "spell_power", "lifesteal", "thorns", "move_speed"],
	"ACCESSORY": ["hp", "armor", "attack", "crit_chance", "spell_power", "lifesteal", "thorns", "move_speed"],
}

const FLOAT_STATS = ["crit_chance", "attack_speed", "spell_power", "lifesteal", "move_speed"]
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
	# % bonus to Mage damage / Healer heal amount. Dead weight on Knight/
	# Archer/Rogue — they have no spell-power-affected ability at all.
	"spell_power": {
		"COMMON":    {"min": 0.05, "max": 0.12},
		"RARE":      {"min": 0.10, "max": 0.22},
		"EPIC":      {"min": 0.18, "max": 0.35},
		"LEGENDARY": {"min": 0.30, "max": 0.50},
	},
	# % of damage dealt returned as self-heal. Inert on Healer, who doesn't
	# deal direct damage through the same path.
	"lifesteal": {
		"COMMON":    {"min": 0.03, "max": 0.06},
		"RARE":      {"min": 0.05, "max": 0.09},
		"EPIC":      {"min": 0.08, "max": 0.12},
		"LEGENDARY": {"min": 0.10, "max": 0.15},
	},
	# % bonus to closing speed. Meaningful for melee (Knight/Rogue) that
	# need to close distance; negligible for ranged/stationary units.
	"move_speed": {
		"COMMON":    {"min": 0.05, "max": 0.12},
		"RARE":      {"min": 0.10, "max": 0.20},
		"EPIC":      {"min": 0.18, "max": 0.32},
		"LEGENDARY": {"min": 0.28, "max": 0.45},
	},
}
const CRIT_DMG_RANGES = {
	"COMMON":    {"min": 8,  "max": 18},
	"RARE":      {"min": 15, "max": 28},
	"EPIC":      {"min": 22, "max": 40},
	"LEGENDARY": {"min": 35, "max": 60},
}
# Flat damage reflected on melee hits taken. Reliable on Knight/Rogue
# (melee, get hit often); situational on Archer/Mage/Healer (only
# triggers when an enemy reaches them directly).
const THORNS_RANGES = {
	"COMMON":    {"min": 2,  "max": 5},
	"RARE":      {"min": 4,  "max": 9},
	"EPIC":      {"min": 7,  "max": 15},
	"LEGENDARY": {"min": 12, "max": 24},
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
	gear.item_level = difficulty

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

	# Roll stats with quality and item level multipliers
	var stat_result = _roll_stats(slot_name, rarity_name, quality_name, difficulty)
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
func _roll_stats(slot_name: String, rarity_name: String, quality_name: String, item_level: int = 5) -> Dictionary:
	var roll_info = STAT_ROLLS[rarity_name]
	var pool = SLOT_STATS[slot_name]

	var q_mult = QUALITY_MULTIPLIERS.get(quality_name, {"min_mult": 1.0, "max_mult": 1.0})
	var lvl_mult = _get_item_level_mult(item_level)
	var base_count = roll_info["count"]

	# Sharper Eye talent: Common/Rare gear has a chance to roll one extra stat
	if rarity_name in ["COMMON", "RARE"] and PlayerInventory.unlocked_talents.get("gear_sharper_eye", false):
		if randf() < 0.25:
			base_count += 1

	# Each of the `count` slots independently picks ANY stat from the pool,
	# including ones already picked — no dedup. Most rolls naturally land
	# on a spread of different stats just from random chance, but the same
	# stat CAN come up multiple times, which is what lets something like a
	# Legendary roll quadruple HP instead of four different stats.
	var occurrence_counts = {}   # stat -> how many times picked so far
	var stats = {}
	var ranges = {}

	for i in range(base_count):
		var stat = pool[randi() % pool.size()]
		var occurrence = occurrence_counts.get(stat, 0)
		occurrence_counts[stat] = occurrence + 1
		var stack_mult = _get_stack_mult(occurrence)

		var rolled = _roll_single_stat(stat, rarity_name, quality_name, q_mult, lvl_mult, stack_mult)

		if stats.has(stat):
			# Merge into the existing value/range rather than overwriting
			stats[stat] += rolled["value"]
			ranges[stat]["rolled"] = stats[stat]
			ranges[stat]["max"] += rolled["range_max"]
			ranges[stat]["stacked"] = occurrence_counts[stat]
		else:
			stats[stat] = rolled["value"]
			ranges[stat] = {
				"rolled": rolled["value"],
				"min": rolled["range_min"],
				"max": rolled["range_max"],
				"is_quality": quality_name != "NORMAL",
				"stacked": 1,
			}

	return {"stats": stats, "ranges": ranges}

# Rolls a single instance of one stat, scaled by quality, item level, and
# the stacking diminishing-returns multiplier for repeat picks of the
# same stat on one item.
func _roll_single_stat(stat: String, rarity_name: String, quality_name: String,
		q_mult: Dictionary, lvl_mult: float, stack_mult: float) -> Dictionary:
	var range_min
	var range_max
	var rolled_val

	if stat == "crit_damage":
		var r = CRIT_DMG_RANGES[rarity_name]
		range_min = int(r["min"] * lvl_mult * stack_mult)
		range_max = int(r["max"] * q_mult["max_mult"] * lvl_mult * stack_mult)
		var q_min = int(r["max"] * q_mult["min_mult"] * lvl_mult * stack_mult) if quality_name != "NORMAL" else range_min
		rolled_val = randi_range(min(q_min, range_max), range_max)
	elif stat == "thorns":
		var r = THORNS_RANGES[rarity_name]
		range_min = int(r["min"] * lvl_mult * stack_mult)
		range_max = int(r["max"] * q_mult["max_mult"] * lvl_mult * stack_mult)
		var q_min = int(r["max"] * q_mult["min_mult"] * lvl_mult * stack_mult) if quality_name != "NORMAL" else range_min
		rolled_val = randi_range(min(q_min, range_max), range_max)
	elif stat in FLOAT_STATS:
		var r = FLOAT_RANGES[stat][rarity_name]
		range_min = snappedf(r["min"] * lvl_mult * stack_mult, 0.01)
		range_max = snappedf(r["max"] * q_mult["max_mult"] * lvl_mult * stack_mult, 0.01)
		var q_min = snappedf(r["max"] * q_mult["min_mult"] * lvl_mult * stack_mult, 0.01) if quality_name != "NORMAL" else range_min
		rolled_val = snappedf(randf_range(min(q_min, range_max), range_max), 0.01)
	else:
		var roll_info = STAT_ROLLS[rarity_name]
		range_min = int(roll_info["min"] * lvl_mult * stack_mult)
		range_max = int(roll_info["max"] * q_mult["max_mult"] * lvl_mult * stack_mult)
		var q_min = int(roll_info["max"] * q_mult["min_mult"] * lvl_mult * stack_mult) if quality_name != "NORMAL" else range_min
		rolled_val = randi_range(min(q_min, range_max), range_max)

	return {"value": rolled_val, "range_min": range_min, "range_max": range_max}

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
