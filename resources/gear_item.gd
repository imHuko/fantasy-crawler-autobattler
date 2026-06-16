class_name GearItem
extends Resource

enum Rarity  { COMMON, RARE, EPIC, LEGENDARY }
enum Slot    { WEAPON, ARMOR, RING, ACCESSORY }
enum Quality { NORMAL, AWAKENED, ASCENDANT, TRANSCENDENT }

@export var item_name: String = ""
@export var rarity:  Rarity  = Rarity.COMMON
@export var slot:    Slot    = Slot.WEAPON
@export var quality: Quality = Quality.NORMAL
@export var stats: Dictionary = {}
@export var stat_ranges: Dictionary = {}
# stat_ranges stores the rolled ceiling for each stat so we can show the bar
# format: { "attack": {"rolled": 22, "min": 16, "max": 38, "is_quality": false} }
@export var set_name: String = ""

func get_rarity_name() -> String:
	return Rarity.keys()[rarity]

func get_slot_name() -> String:
	return Slot.keys()[slot]

func get_quality_name() -> String:
	match quality:
		Quality.AWAKENED:      return "Awakened"
		Quality.ASCENDANT:     return "Ascendant"
		Quality.TRANSCENDENT:  return "Transcendent"
	return ""

func get_quality_suffix() -> String:
	match quality:
		Quality.AWAKENED:      return " ✦"
		Quality.ASCENDANT:     return " ✦✦"
		Quality.TRANSCENDENT:  return " ✦✦✦"
	return ""

func get_rarity_color() -> Color:
	match rarity:
		Rarity.COMMON:    return Color(0.75, 0.75, 0.75)
		Rarity.RARE:      return Color(0.25, 0.50, 1.00)
		Rarity.EPIC:      return Color(0.65, 0.25, 0.90)
		Rarity.LEGENDARY: return Color(1.00, 0.65, 0.10)
	return Color.WHITE

func get_display_color() -> Color:
	var base = get_rarity_color()
	match quality:
		Quality.AWAKENED:
			return base.lightened(0.25)
		Quality.ASCENDANT:
			return base.lightened(0.45)
		Quality.TRANSCENDENT:
			return Color(1.0, 1.0, 1.0)  # Pure white/gold
	return base

func get_suggested_units() -> Array:
	var suggestions = []
	var total = 0
	var tank_score = 0
	var dps_score = 0
	var mage_score = 0
	var heal_score = 0

	for stat in stats:
		match stat:
			"hp":           tank_score  += 2; heal_score += 1
			"armor":        tank_score  += 3
			"attack":       dps_score   += 2; mage_score += 1
			"attack_speed": dps_score   += 2; mage_score += 2
			"crit_chance":  dps_score   += 2; mage_score += 1
			"crit_damage":  dps_score   += 2; mage_score += 2

	var scores = {"KNIGHT": tank_score, "ARCHER": dps_score,
				  "MAGE": mage_score, "HEALER": heal_score}
	var max_score = 0
	for s in scores.values():
		if s > max_score: max_score = s
	if max_score == 0: return []

	for unit in scores:
		if scores[unit] >= max_score * 0.7:
			suggestions.append(unit)
	return suggestions

func print_info() -> void:
	print("--- Gear Item ---")
	print("Name:    ", item_name, get_quality_suffix())
	print("Rarity:  ", get_rarity_name())
	print("Quality: ", get_quality_name() if quality != Quality.NORMAL else "Normal")
	print("Slot:    ", get_slot_name())
	print("Set:     ", set_name if set_name != "" else "None")
	print("Stats:   ", stats)
	print("-----------------")
