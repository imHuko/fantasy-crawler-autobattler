extends Node

# All gear the player has collected across runs
var gear_inventory: Array[GearItem] = []

# All troops the player has unlocked
var troop_roster: Array[TroopData] = []

# How many troop slots are currently unlocked (increases with progression)
var unlocked_troop_slots: int = 3

# Current stage/progression value
var current_stage: int = 1

# Game setup
var player_name: String = "Commander"
var map_seed: int = 0
var difficulty: String = "Normal"
var difficulty_settings: Dictionary = {
	"attack_frequency": 0.6,
	"warning_turns": 3,
	"force_size": 1.0,
	"enemy_expansion": 0.7,
}

# -------------------------------------------------------
# Talent hooks for gear quality system
# Updated by talent tree purchases
# -------------------------------------------------------
var talents = {
	"awakened_unlock":             false,
	"awakened_chance_epic":        0.0,
	"awakened_chance_legendary":   0.0,
	"ascendant_unlock":            false,
	"ascendant_chance_epic":       0.0,
	"ascendant_chance_legendary":  0.0,
	"transcendent_unlock":         false,
	"transcendent_chance":         0.0,
}

# -------------------------------------------------------
# Gear Management
# -------------------------------------------------------

func add_gear(gear: GearItem) -> void:
	gear_inventory.append(gear)
	print("[Inventory] Added gear: ", gear.item_name, " (", gear.get_rarity_name(), ")")

func remove_gear(gear: GearItem) -> void:
	gear_inventory.erase(gear)

func get_gear_by_slot(slot: GearItem.Slot) -> Array:
	return gear_inventory.filter(func(g): return g.slot == slot)

# -------------------------------------------------------
# Troop Management
# -------------------------------------------------------

func add_troop(troop: TroopData) -> void:
	if troop_roster.size() < unlocked_troop_slots:
		troop_roster.append(troop)
		print("[Inventory] Added troop: ", troop.troop_name)
	else:
		print("[Inventory] Cannot add troop — all slots filled.")

func unlock_troop_slot() -> void:
	unlocked_troop_slots += 1
	print("[Inventory] Troop slot unlocked! Total slots: ", unlocked_troop_slots)

# -------------------------------------------------------
# Set Bonus Helpers
# -------------------------------------------------------

# Returns a dictionary of { set_name: count } across ALL equipped gear on ALL troops
func get_global_set_counts() -> Dictionary:
	var counts = {}
	for troop in troop_roster:
		for set_name in troop.get_equipped_set_names():
			counts[set_name] = counts.get(set_name, 0) + 1
	return counts

# -------------------------------------------------------
# Debug
# -------------------------------------------------------

func print_inventory() -> void:
	print("\n====== PLAYER INVENTORY ======")
	print("Stage: ", current_stage)
	print("Troop Slots: ", troop_roster.size(), " / ", unlocked_troop_slots)
	print("\n-- Gear (", gear_inventory.size(), " items) --")
	for gear in gear_inventory:
		print("  [", gear.get_slot_name(), "] ", gear.item_name, " | ", gear.get_rarity_name(), " | Set: ", gear.set_name if gear.set_name != "" else "None")
	print("\n-- Troops --")
	for troop in troop_roster:
		troop.print_info()
	print("==============================\n")
