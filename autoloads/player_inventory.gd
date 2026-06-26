extends Node

func _ready() -> void:
	_apply_saved_settings()

func _apply_saved_settings() -> void:
	var config = ConfigFile.new()
	if config.load("user://settings.cfg") != OK:
		# First launch — go fullscreen so the game fills whatever screen
		# this device has. Player can change to windowed in Settings.
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		return

	var width = config.get_value("display", "width", -1)
	var height = config.get_value("display", "height", -1)
	var fullscreen = config.get_value("display", "fullscreen", false)
	var borderless = config.get_value("display", "borderless", false)

	if fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	elif borderless:
		var screen = DisplayServer.screen_get_size()
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
		DisplayServer.window_set_size(screen)
		DisplayServer.window_set_position(Vector2i.ZERO)
	elif width > 0 and height > 0:
		DisplayServer.window_set_size(Vector2i(width, height))
		var screen_size = DisplayServer.screen_get_size()
		DisplayServer.window_set_position((screen_size - Vector2i(width, height)) / 2)

	confirm_before_disposing_gear = config.get_value("gameplay", "confirm_before_disposing_gear", true)
	mobile_mode = config.get_value("controls", "mobile_mode", false)

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
var invasions_enabled: bool = true   # player's own preference, only respected when difficulty_settings.invasions_toggleable is true

# Map state
var current_battle_zone: int = -1
var settings_return_scene: String = ""
var confirm_before_disposing_gear: bool = true
var mobile_mode: bool = false   # shows on-screen D-pad in dungeon scenes; loaded from settings.cfg
var current_attack_force: float = 1.0
var conquering_zone: bool = false

# Dungeon run tier — chosen on the dungeon picker screen each time, not
# the same as the map's Easy/Normal/Hard/Nightmare difficulty above.
var dungeon_tier: String = "Standard"   # "Quick", "Standard", "Deep Delve"
var dungeon_duration_seconds: float = 600.0   # how long the next survival run should last, set by the duration picker
var commander_class: String = "ARCHER"   # class profile the Commander uses in dungeon runs
var commander_gear: Dictionary = {
	"WEAPON": null,
	"RING": null,
}

# Resources — banked for spending. Costs require the resource named in
# their cost dictionary; Food cannot substitute for Gold.
var resources: Dictionary = {
	"food": 0,
	"gold": 0,
}

# Salvage materials, one per gear rarity — produced by salvaging gear of
# that rarity, spent on upgrading gear of that same rarity. Deliberately
# NOT interchangeable with each other or with Food/Gold resources, so upgrading a
# Legendary always requires having actually salvaged Legendary gear.
var salvage: Dictionary = {
	"COMMON": 0,
	"RARE": 0,
	"EPIC": 0,
	"LEGENDARY": 0,
}

# Checks if a cost dict can be paid from the matching resource pools.
func can_afford(cost: Dictionary) -> bool:
	for key in cost:
		if resources.get(key, 0) < cost[key]:
			return false
	return true

# Deducts a cost from its matching resource pools.
# Returns false (and deducts nothing) if any required pool can't cover it.
func spend_resources(cost: Dictionary) -> bool:
	if not can_afford(cost):
		return false

	for key in cost:
		resources[key] = resources.get(key, 0) - cost[key]
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
var play_tutorial: bool = true   # set from new game screen checkbox; only matters before the walkthrough starts

# The full forced walkthrough, in order. Each entry is a step ID; the
# actual text/target/screen for each ID lives in TutorialSteps
# (autoloads/tutorial_steps.gd), kept separate from this raw progress
# tracker so content can be edited without touching save data shape.
var tutorial_step_index: int = 0
var tutorial_active: bool = false   # true once the walkthrough has actually begun, false once finished or skipped
var map_tutorial_seen: Dictionary = {
	"intro": false, "conquer": false, "build": false,
	"move_troops": false, "end_turn": false,
}

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
