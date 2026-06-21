class_name TroopData
extends Resource

enum TroopType { KNIGHT, ARCHER, MAGE, HEALER, ROGUE }

@export var troop_name: String = ""
@export var troop_type: TroopType = TroopType.KNIGHT
@export var troop_id: String = ""   # unique identifier, independent of display name
@export var is_hero: bool = false   # true for the player's one Hero character — usable on the map, in defense battles, and in the action dungeon

func _init() -> void:
	if troop_id == "":
		troop_id = str(Time.get_ticks_usec()) + "_" + str(randi())
@export var base_stats: Dictionary = {}
# e.g. { "hp": 100, "attack": 10, "defense": 5, "speed": 3 }

# Persists HP across battles rather than always starting full. -1 means
# "not yet set" (brand new troop) — treated as full HP the first time
# it's actually read via get_current_hp().
@export var current_hp: int = -1

# Bonus max HP earned by surviving defense battles (Veterans' Grit talent).
# Stacks up to 3 times (+5 each = +15 max), tracked separately so it
# persists correctly across saves and isn't reset when gear changes.
@export var veteran_hp_bonus: int = 0

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
			var gear_stats = gear.get_effective_stats()   # includes upgrade level bonus
			for stat in gear_stats:
				if effective.has(stat):
					effective[stat] += gear_stats[stat]
				else:
					effective[stat] = gear_stats[stat]

	# Talent-granted flat bonuses, applied to all troops (and the hero, via
	# the same TroopData class) after gear so they stack on top cleanly.
	if PlayerInventory.unlocked_talents.get("combat_hardened_ranks", false):
		effective["hp"] = effective.get("hp", 0) + 15
	if PlayerInventory.unlocked_talents.get("combat_sharpened_blades", false):
		effective["attack"] = effective.get("attack", 0) + 5
	if is_hero and PlayerInventory.unlocked_talents.get("combat_heros_resolve", false):
		effective["hp"] = effective.get("hp", 0) + 30
		effective["attack"] = effective.get("attack", 0) + 8
	if veteran_hp_bonus > 0 and PlayerInventory.unlocked_talents.get("combat_veterans_grit", false):
		effective["hp"] = effective.get("hp", 0) + veteran_hp_bonus

	return effective

# Current max HP given equipped gear and talents right now. Changes
# whenever gear changes — current_hp is an absolute value, not a % of
# this, so swapping gear doesn't change how wounded a troop reads as.
func get_max_hp() -> int:
	return get_effective_stats().get("hp", 100)

# Returns current HP, clamped to whatever max HP actually is right now
# (handles gear being unequipped after healing, etc). Brand new troops
# (current_hp == -1) read as full HP without needing special-casing
# everywhere else that calls this.
func get_current_hp() -> int:
	var max_hp = get_max_hp()
	if current_hp < 0:
		return max_hp
	return min(current_hp, max_hp)

func get_missing_hp() -> int:
	return get_max_hp() - get_current_hp()

# Heals up to `amount` HP, clamped to max. Returns how much HP was
# actually restored, since that's what determines the real food cost.
func heal(amount: int) -> int:
	var before = get_current_hp()
	current_hp = min(before + amount, get_max_hp())
	return current_hp - before

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
