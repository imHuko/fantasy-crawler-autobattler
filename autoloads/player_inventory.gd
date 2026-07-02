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
	show_damage_numbers = config.get_value("gameplay", "show_damage_numbers", true)
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
var show_damage_numbers: bool = true
var mobile_mode: bool = false   # shows on-screen D-pad in dungeon scenes; loaded from settings.cfg
var current_attack_force: float = 1.0
var conquering_zone: bool = false

# Dungeon run tier — chosen on the dungeon picker screen each time, not
# the same as the map's Easy/Normal/Hard/Nightmare difficulty above.
var dungeon_tier: String = "Standard"   # "Quick", "Standard", "Deep Delve"
var dungeon_duration_seconds: float = 600.0   # how long the next survival run should last, set by the duration picker
var current_dungeon_zone_id: int = -1
var current_dungeon_zone_type: String = "dungeon"
var commander_class: String = "ARCHER"   # class profile the Commander uses in dungeon runs
var commander_gear: Dictionary = {
	"WEAPON": null,
	"RING": null,
}

const COMMANDER_FIELD_TALENT := "combat_heros_resolve"

const COMMANDER_TROOP_TYPES := {
	"KNIGHT": "KNIGHT",
	"ARCHER": "ARCHER",
	"MAGE": "MAGE",
	"HEALER": "HEALER",
	"ROGUE": "ROGUE",
}

const COMMANDER_DEFENSE_BASE_STATS := {
	"KNIGHT": { "hp": 180, "attack": 16, "defense": 18, "speed": 2 },
	"ARCHER": { "hp": 110, "attack": 24, "defense": 8,  "speed": 5 },
	"MAGE":   { "hp": 90,  "attack": 30, "defense": 5,  "speed": 4, "spell_power": 0.25 },
	"HEALER": { "hp": 125, "attack": 9,  "defense": 10, "speed": 3, "spell_power": 0.20 },
	"ROGUE":  { "hp": 115, "attack": 26, "defense": 6,  "speed": 7 },
}

func is_commander_fielded() -> bool:
	return unlocked_talents.get(COMMANDER_FIELD_TALENT, false)

func make_commander_troop_data() -> TroopData:
	var class_key = COMMANDER_TROOP_TYPES.get(commander_class, "ARCHER")
	var troop = TroopData.new()
	troop.troop_id = "__commander__"
	troop.troop_name = player_name if player_name != "" else "Commander"
	troop.troop_type = TroopData.TroopType[class_key]
	troop.is_hero = true
	troop.base_stats = COMMANDER_DEFENSE_BASE_STATS.get(class_key, COMMANDER_DEFENSE_BASE_STATS["ARCHER"]).duplicate()
	troop.current_hp = -1
	for slot_key in commander_gear:
		if troop.equipped_gear.has(slot_key):
			troop.equipped_gear[slot_key] = commander_gear[slot_key]
	return troop

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
var map_time_speed: float = 1.0
var map_is_paused: bool = false
var map_attack_roll_timer: float = 30.0
var map_pending_attacks: Array = []
var map_marching_troops: Array = []
var map_mandatory_battle_queue: Array = []

const MAP_SECONDS_PER_OLD_TURN := 30.0
const MAP_TRAVEL_SPEED := 120.0 / MAP_SECONDS_PER_OLD_TURN
const MAP_ATTACK_ROLL_INTERVAL := MAP_SECONDS_PER_OLD_TURN

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

func _process(delta: float) -> void:
	process_world_map_time(delta)

func process_world_map_time(delta: float) -> void:
	if not map_generated or map_zones.is_empty():
		return
	if map_is_paused or _map_should_auto_pause_for_scene():
		return

	var sim_delta = delta * map_time_speed
	if sim_delta <= 0.0:
		return

	if not map_mandatory_battle_queue.is_empty():
		return

	map_elapsed_seconds += sim_delta
	_process_map_marching_troops(sim_delta)
	_process_map_resource_generation(sim_delta)
	_process_map_attack_countdowns(sim_delta)

	if map_mandatory_battle_queue.is_empty():
		map_attack_roll_timer -= sim_delta
		if map_attack_roll_timer <= 0.0:
			map_attack_roll_timer = MAP_ATTACK_ROLL_INTERVAL
			_maybe_spawn_map_attack()

func _map_should_auto_pause_for_scene() -> bool:
	var scene = get_tree().current_scene
	if scene == null:
		return false
	var path = scene.scene_file_path
	return path.ends_with("defense_scene.tscn") or path.ends_with("action_dungeon.tscn") or path.ends_with("tutorial_dungeon.tscn")

func _process_map_marching_troops(delta: float) -> void:
	var arrived := []
	for m in map_marching_troops:
		m["seconds_left"] -= delta
		if m["seconds_left"] <= 0:
			var to_zone = int(m["to_zone"])
			if to_zone >= 0 and to_zone < map_zones.size():
				map_zones[to_zone]["troops"].append(m["troop_id"])
			arrived.append(m)
	for a in arrived:
		map_marching_troops.erase(a)

func _process_map_resource_generation(delta: float) -> void:
	var food_gain := 0.0
	var gold_gain := 0.0
	var trade_routes = unlocked_talents.get("economy_trade_routes", false)
	for zone in map_zones:
		if zone.get("owner", "neutral") != "player":
			continue
		var has_farm = zone["buildings"].has("Farm")
		var has_barracks = zone["buildings"].has("Barracks")
		if has_farm:
			food_gain += 50.0 if unlocked_talents.get("economy_bountiful_harvest", false) else 30.0
		if has_barracks:
			gold_gain += 20.0
		if trade_routes and not has_farm and not has_barracks:
			gold_gain += 2.0 if unlocked_talents.get("economy_supply_network", false) else 1.0

	var income_mult = difficulty_settings.get("income_mult", 1.0)
	if food_gain > 0:
		resources["food"] += (food_gain * income_mult / MAP_SECONDS_PER_OLD_TURN) * delta
	if gold_gain > 0:
		resources["gold"] += (gold_gain * income_mult / MAP_SECONDS_PER_OLD_TURN) * delta

func _maybe_spawn_map_attack() -> void:
	var can_toggle = difficulty_settings.get("invasions_toggleable", true)
	var talent_unlocked = unlocked_talents.get("toggle_invasions", false)
	if can_toggle and not (talent_unlocked and invasions_enabled):
		return

	var attack_chance = difficulty_settings.get("attack_frequency", 0.6) * 0.25
	var warning_turns = int(difficulty_settings.get("warning_turns", 3))
	var max_simultaneous = int(difficulty_settings.get("max_simultaneous_attacks", 1))
	if map_pending_attacks.size() >= max_simultaneous:
		return
	if randf() > attack_chance:
		return

	var targets := []
	for zone in map_zones:
		if zone.get("owner", "neutral") != "player":
			continue
		var already_pending = false
		for pa in map_pending_attacks:
			if int(pa["zone_id"]) == int(zone["id"]):
				already_pending = true
				break
		if already_pending:
			continue
		for conn_id in zone["connections"]:
			if conn_id >= 0 and conn_id < map_zones.size() and map_zones[conn_id].get("owner", "neutral") == "neutral":
				targets.append(int(zone["id"]))
				break
	if targets.is_empty():
		return

	var target_id = targets[randi() % targets.size()]
	var base_force = difficulty_settings.get("force_size", 1.0)
	var zone_force = map_zones[target_id]["enemy_strength"] * 0.15
	var force = max(base_force, zone_force)
	var effective_warning_turns = warning_turns + get_map_watchtower_bonus(target_id)
	var effective_warning_seconds = effective_warning_turns * MAP_SECONDS_PER_OLD_TURN
	map_pending_attacks.append({
		"zone_id": target_id,
		"seconds_remaining": effective_warning_seconds,
		"total_seconds": effective_warning_seconds,
		"force_size": force,
	})

	if map_pending_attacks.size() < max_simultaneous and randf() < attack_chance * 0.5:
		_maybe_spawn_map_attack()

func _process_map_attack_countdowns(delta: float) -> void:
	var remaining := []
	var triggered := []
	for attack in map_pending_attacks:
		attack["seconds_remaining"] -= delta
		if attack["seconds_remaining"] <= 0:
			triggered.append(attack)
		else:
			remaining.append(attack)
	map_pending_attacks = remaining
	if not triggered.is_empty():
		map_mandatory_battle_queue.append_array(triggered)
		launch_next_map_mandatory_battle()

func launch_next_map_mandatory_battle() -> void:
	if map_mandatory_battle_queue.is_empty() or _map_should_auto_pause_for_scene():
		return
	var attack = map_mandatory_battle_queue[0]
	var zone_id = int(attack["zone_id"])
	if zone_id < 0 or zone_id >= map_zones.size():
		map_mandatory_battle_queue.pop_front()
		return
	var zone = map_zones[zone_id]
	current_battle_zone = zone_id
	current_stage = zone["enemy_strength"]
	current_attack_force = attack["force_size"]
	conquering_zone = false
	set_battle_roster_from_zone_troops(zone["troops"])
	set_battle_zone_buffs(get_best_map_building_level_in_range(zone_id, "Forge"), get_best_map_building_level_in_range(zone_id, "Shrine"))
	SaveManager.save_game()
	get_tree().change_scene_to_file("res://scenes/defense_scene.tscn")

func get_map_watchtower_bonus(zone_id: int) -> int:
	var per_tower = 2 if unlocked_talents.get("buildings_reinforced_towers", false) else 1
	var bonus = 0
	if map_zones[zone_id]["buildings"].has("Watchtower"):
		bonus += per_tower * int(map_zones[zone_id]["buildings"]["Watchtower"])
	for conn_id in map_zones[zone_id]["connections"]:
		if conn_id >= 0 and conn_id < map_zones.size() and map_zones[conn_id]["buildings"].has("Watchtower"):
			bonus += per_tower * int(map_zones[conn_id]["buildings"]["Watchtower"])
	return bonus

func get_best_map_building_level_in_range(zone_id: int, building_name: String) -> int:
	var wider_reach = unlocked_talents.get("buildings_wider_reach", false)
	var best = map_zones[zone_id]["buildings"].get(building_name, 0)
	for conn_id in map_zones[zone_id]["connections"]:
		if conn_id < 0 or conn_id >= map_zones.size():
			continue
		best = max(best, map_zones[conn_id]["buildings"].get(building_name, 0))
		if wider_reach:
			for conn2_id in map_zones[conn_id]["connections"]:
				if conn2_id >= 0 and conn2_id < map_zones.size():
					best = max(best, map_zones[conn2_id]["buildings"].get(building_name, 0))
	return int(best)

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

func has_open_troop_slot() -> bool:
	return troop_roster.size() < unlocked_troop_slots

func add_troop(troop: TroopData) -> bool:
	if troop_roster.size() < unlocked_troop_slots:
		troop_roster.append(troop)
		print("[Inventory] Added troop: ", troop.troop_name)
		return true
	print("[Inventory] Cannot add troop — all slots filled.")
	return false

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
	if is_commander_fielded():
		for slot_key in commander_gear:
			var gear: GearItem = commander_gear[slot_key]
			if gear != null and gear.set_name != "":
				counts[gear.set_name] = counts.get(gear.set_name, 0) + 1
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
