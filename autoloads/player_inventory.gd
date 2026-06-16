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

# Map state
var current_battle_zone: int = -1
var current_attack_force: float = 1.0
var conquering_zone: bool = false

# Dungeon run tier — chosen on the dungeon picker screen each time, not
# the same as the map's Easy/Normal/Hard/Nightmare difficulty above.
var dungeon_tier: String = "Standard"   # "Quick", "Standard", "Deep Delve"

# Resources — banked for spending (recruiting, rerolling, talents, etc).
# Food and Gold are interchangeable for spending purposes — costs are
# checked and paid against their combined total.
var resources: Dictionary = {
	"food": 0,
	"gold": 0,
}

func get_total_resources() -> int:
	return resources.get("food", 0) + resources.get("gold", 0)

# Checks if a cost dict (e.g. {"food": 15, "gold": 15}) can be paid using
# the combined Food+Gold total, regardless of which pool the numbers
# nominally came from.
func can_afford(cost: Dictionary) -> bool:
	var total_cost = cost.get("food", 0) + cost.get("gold", 0)
	return get_total_resources() >= total_cost

# Deducts a cost from the combined pool, draining Food first then Gold.
# Returns false (and deducts nothing) if the combined total can't cover it.
func spend_resources(cost: Dictionary) -> bool:
	var total_cost = cost.get("food", 0) + cost.get("gold", 0)
	if get_total_resources() < total_cost:
		return false

	var remaining = total_cost
	var from_food = min(remaining, resources.get("food", 0))
	resources["food"] -= from_food
	remaining -= from_food
	resources["gold"] -= remaining
	return true

# Per-zone building slot limit. Talents can raise this later.
var max_buildings_per_zone: int = 2

# Persistent world map state. Generated once by world_map.gd on first visit,
# then read/written directly so zone ownership, buildings, and stationed
# troops survive scene changes and saves.
var map_zones: Array = []
var map_connections: Array = []
var map_elapsed_seconds: float = 0.0
var map_generated: bool = false

# Battle result reporting (read by world_map on _ready)
var last_battle_result: String = ""      # "won", "lost", "retreat", ""
var last_battle_zone: int = -1
var last_battle_was_conquest: bool = false

# Tutorial state
var tutorial_complete: bool = false
var play_tutorial: bool = true   # set from new game screen checkbox
var map_tutorial_seen: Dictionary = {
	"intro": false, "conquer": false, "build": false,
	"move_troops": false, "end_turn": false,
}

# Dungeon hero — a dedicated character separate from the troop roster,
# with its own gear slots used only in dungeon runs.
var hero: TroopData = null

func ensure_hero_exists() -> void:
	if hero == null:
		hero = TroopData.new()
		hero.is_hero = true
		hero.troop_name = "Hero"
		hero.troop_type = TroopData.TroopType.KNIGHT
		hero.base_stats = { "hp": 120, "attack": 16, "defense": 8, "speed": 4 }

# Snapshot of troop names eligible for the current/next battle.
# Set by world_map right before launching defense_scene so the battle
# only offers troops actually stationed at (or staged near) that zone.
var current_battle_zone_troop_names: Array = []
var current_battle_forge_level: int = 0
var current_battle_shrine_level: int = 0

func set_battle_roster_from_zone_troops(troop_names: Array) -> void:
	current_battle_zone_troop_names = troop_names.duplicate()

func set_battle_zone_buffs(forge_level: int, shrine_level: int) -> void:
	current_battle_forge_level = forge_level
	current_battle_shrine_level = shrine_level

func get_zone_troop_names(zone_id: int) -> Array:
	# zone_id is unused here since world_map already resolved the
	# correct troop list before the scene change; this just returns
	# the snapshot. Kept as a function (not a raw var read) so the
	# lookup logic can be made zone-aware later without touching callers.
	return current_battle_zone_troop_names

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

# Tracks which talent node IDs have been purchased (see talent_tree.gd for definitions)
var unlocked_talents: Dictionary = {}

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
