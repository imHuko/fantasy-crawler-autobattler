class_name TroopData
extends Resource

enum TroopType { KNIGHT, ARCHER, MAGE, HEALER, ROGUE }

@export var troop_name: String = ""
@export var troop_type: TroopType = TroopType.KNIGHT
@export var troop_id: String = ""   # unique identifier, independent of display name
@export var is_hero: bool = false   # true only for PlayerInventory.hero, set at creation

func _init() -> void:
	if troop_id == "":
		troop_id = str(Time.get_ticks_usec()) + "_" + str(randi())
@export var base_stats: Dictionary = {}
# e.g. { "hp": 100, "attack": 10, "defense": 5, "speed": 3 }

# Gear slots: keyed by slot name, value is a GearItem or null
var equipped_gear: Dictionary = {
	"WEAPON": null,
	"ARMOR": null,
	"RING": null,
	"ACCESSORY": null,
}

func get_type_name() -> String:
	return TroopType.keys()[troop_type]

# Returns base stats merged with all equipped gear stats
func get_effective_stats() -> Dictionary:
	var effective = base_stats.duplicate()
	for slot_key in equipped_gear:
		var gear: GearItem = equipped_gear[slot_key]
		if gear != null:
			for stat in gear.stats:
				if effective.has(stat):
					effective[stat] += gear.stats[stat]
				else:
					effective[stat] = gear.stats[stat]

	# Talent-granted flat bonuses, applied to all troops (and the hero, via
	# the same TroopData class) after gear so they stack on top cleanly.
	if PlayerInventory.unlocked_talents.get("combat_hardened_ranks", false):
		effective["hp"] = effective.get("hp", 0) + 15
	if PlayerInventory.unlocked_talents.get("combat_sharpened_blades", false):
		effective["attack"] = effective.get("attack", 0) + 5
	if is_hero and PlayerInventory.unlocked_talents.get("combat_heros_resolve", false):
		effective["hp"] = effective.get("hp", 0) + 30
		effective["attack"] = effective.get("attack", 0) + 8

	return effective

# Returns a list of set names currently equipped (for set bonus checking)
func get_equipped_set_names() -> Array:
	var sets = []
	for slot_key in equipped_gear:
		var gear: GearItem = equipped_gear[slot_key]
		if gear != null and gear.set_name != "":
			sets.append(gear.set_name)
	return sets

func equip(gear: GearItem) -> void:
	var slot_key = gear.get_slot_name()
	equipped_gear[slot_key] = gear

func unequip(slot_key: String) -> GearItem:
	var gear = equipped_gear[slot_key]
	equipped_gear[slot_key] = null
	return gear

func print_info() -> void:
	print("=== Troop: ", troop_name, " (", get_type_name(), ") ===")
	print("Base Stats:      ", base_stats)
	print("Effective Stats: ", get_effective_stats())
	print("Equipped Sets:   ", get_equipped_set_names())
	for slot_key in equipped_gear:
		var gear = equipped_gear[slot_key]
		print("  ", slot_key, ": ", gear.item_name if gear else "empty")
	print("==========================================")
