extends Node

# -------------------------------------------------------
# SaveManager autoload — handles all save/load operations
# -------------------------------------------------------

const SAVE_PATH = "user://savegame.json"

func save_game() -> void:
	var data = {
		"stage": PlayerInventory.current_stage,
		"unlocked_slots": PlayerInventory.unlocked_troop_slots,
		"gear_count": PlayerInventory.gear_inventory.size(),
		"troop_count": PlayerInventory.troop_roster.size(),
		"talents": PlayerInventory.talents,
		"unlocked_talents": PlayerInventory.unlocked_talents,
		"max_buildings_per_zone": PlayerInventory.max_buildings_per_zone,
		"resources": PlayerInventory.resources,
		"salvage": PlayerInventory.salvage,
		"map_generated": PlayerInventory.map_generated,
		"map_elapsed_seconds": PlayerInventory.map_elapsed_seconds,
		"map_zones": _serialize_zones(PlayerInventory.map_zones),
		"map_connections": PlayerInventory.map_connections,
		"play_tutorial": PlayerInventory.play_tutorial,
		"map_tutorial_seen": PlayerInventory.map_tutorial_seen,
		"player_name": PlayerInventory.player_name,
		"map_seed": PlayerInventory.map_seed,
		"difficulty": PlayerInventory.difficulty,
		"difficulty_settings": PlayerInventory.difficulty_settings,
		"invasions_enabled": PlayerInventory.invasions_enabled,
		"dungeon_tier": PlayerInventory.dungeon_tier,
		"tutorial_complete": PlayerInventory.tutorial_complete,
		"gear": [],
		"troops": [],
	}

	# Save gear
	for gear in PlayerInventory.gear_inventory:
		data["gear"].append({
			"name": gear.item_name,
			"rarity": gear.rarity,
			"slot": gear.slot,
			"quality": gear.quality,
			"item_level": gear.item_level,
			"stats": gear.stats,
			"stat_ranges": gear.stat_ranges,
			"set_name": gear.set_name,
			"upgrade_level": gear.upgrade_level,
		})

	# Save troops and their equipped gear
	for troop in PlayerInventory.troop_roster:
		var t_data = {
			"id": troop.troop_id,
			"name": troop.troop_name,
			"type": troop.troop_type,
			"base_stats": troop.base_stats,
			"is_hero": troop.is_hero,
			"current_hp": troop.current_hp,
			"equipped": {},
		}
		for slot_key in troop.equipped_gear:
			var gear = troop.equipped_gear[slot_key]
			if gear:
				t_data["equipped"][slot_key] = {
					"name": gear.item_name,
					"rarity": gear.rarity,
					"slot": gear.slot,
					"quality": gear.quality,
					"item_level": gear.item_level,
					"stats": gear.stats,
					"stat_ranges": gear.stat_ranges,
					"set_name": gear.set_name,
					"upgrade_level": gear.upgrade_level,
				}
		data["troops"].append(t_data)

	var f = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	print("[SaveManager] Game saved — Stage %d, %d troops, %d gear" % [
		data["stage"], data["troops"].size(), data["gear"].size()])

func load_game() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		print("[SaveManager] No save file found, starting new game.")
		new_game()
		return

	var f = FileAccess.open(SAVE_PATH, FileAccess.READ)
	var data = JSON.parse_string(f.get_as_text())
	f.close()

	if data == null:
		print("[SaveManager] Save file corrupt, starting new game.")
		new_game()
		return

	PlayerInventory.current_stage = data.get("stage", 1)
	PlayerInventory.unlocked_troop_slots = data.get("unlocked_slots", 3)
	PlayerInventory.player_name = data.get("player_name", "Commander")
	PlayerInventory.map_seed = data.get("map_seed", 0)
	PlayerInventory.difficulty = data.get("difficulty", "Normal")
	PlayerInventory.difficulty_settings = data.get("difficulty_settings", PlayerInventory.difficulty_settings)
	PlayerInventory.invasions_enabled = data.get("invasions_enabled", true)
	PlayerInventory.dungeon_tier = data.get("dungeon_tier", "Standard")
	PlayerInventory.tutorial_complete = data.get("tutorial_complete", false)

	if data.has("talents"):
		for key in data["talents"]:
			if PlayerInventory.talents.has(key):
				PlayerInventory.talents[key] = data["talents"][key]
	if data.has("unlocked_talents"):
		PlayerInventory.unlocked_talents = data["unlocked_talents"]
	PlayerInventory.max_buildings_per_zone = data.get("max_buildings_per_zone", 2)
	if data.has("resources"):
		for key in data["resources"]:
			if PlayerInventory.resources.has(key):
				PlayerInventory.resources[key] = data["resources"][key]
	if data.has("salvage"):
		for key in data["salvage"]:
			if PlayerInventory.salvage.has(key):
				PlayerInventory.salvage[key] = data["salvage"][key]

	PlayerInventory.map_generated = data.get("map_generated", false)
	PlayerInventory.map_elapsed_seconds = data.get("map_elapsed_seconds", 0.0)
	if data.has("map_zones"):
		PlayerInventory.map_zones = _deserialize_zones(data["map_zones"])
	if data.has("map_connections"):
		PlayerInventory.map_connections = data["map_connections"]
	PlayerInventory.play_tutorial = data.get("play_tutorial", true)
	if data.has("map_tutorial_seen"):
		for key in data["map_tutorial_seen"]:
			if PlayerInventory.map_tutorial_seen.has(key):
				PlayerInventory.map_tutorial_seen[key] = data["map_tutorial_seen"][key]
	PlayerInventory.gear_inventory.clear()
	PlayerInventory.troop_roster.clear()

	# Load gear inventory
	for g in data.get("gear", []):
		var gear = _dict_to_gear(g)
		PlayerInventory.gear_inventory.append(gear)

	# Load troops
	for t in data.get("troops", []):
		var troop = TroopData.new()
		if t.has("id") and t["id"] != "":
			troop.troop_id = t["id"]
		troop.troop_name = t["name"]
		troop.troop_type = int(t["type"])
		troop.base_stats = t["base_stats"]
		troop.is_hero = t.get("is_hero", false)
		troop.current_hp = int(t.get("current_hp", -1))
		for slot_key in t.get("equipped", {}):
			var gear = _dict_to_gear(t["equipped"][slot_key])
			troop.equipped_gear[slot_key] = gear
		PlayerInventory.troop_roster.append(troop)

	print("[SaveManager] Game loaded — Stage %d, %d troops, %d gear" % [
		PlayerInventory.current_stage,
		PlayerInventory.troop_roster.size(),
		PlayerInventory.gear_inventory.size()])

func new_game() -> void:
	PlayerInventory.current_stage = 1
	PlayerInventory.unlocked_troop_slots = 2
	PlayerInventory.gear_inventory.clear()
	PlayerInventory.troop_roster.clear()
	PlayerInventory.tutorial_complete = false
	PlayerInventory.map_generated = false
	PlayerInventory.map_zones = []
	PlayerInventory.map_connections = []
	PlayerInventory.map_elapsed_seconds = 0.0
	PlayerInventory.map_tutorial_seen = {
		"intro": false, "conquer": false, "build": false,
		"move_troops": false, "end_turn": false,
	}
	PlayerInventory.resources = {"food": 0, "gold": 0}
	PlayerInventory.salvage = {"COMMON": 0, "RARE": 0, "EPIC": 0, "LEGENDARY": 0}
	PlayerInventory.unlocked_talents = {}
	PlayerInventory.max_buildings_per_zone = 2

	# Starting troop — just the Hero, who is now a normal roster member
	# usable on the map (stationed, marched, fights in defense battles)
	# AND in the action dungeon. A second unit is earned via the tutorial.
	var hero = TroopData.new()
	hero.is_hero = true
	hero.troop_name = "Hero"
	hero.troop_type = TroopData.TroopType.KNIGHT
	hero.base_stats = { "hp": 160, "attack": 16, "defense": 12, "speed": 3 }
	PlayerInventory.troop_roster.append(hero)

	# Starting gear — a few commons to get going
	for i in range(3):
		var biomes = ["crypt", "forest_ruins"]
		PlayerInventory.gear_inventory.append(
			GearGenerator.generate(biomes[randi() % biomes.size()], 1))

	print("[SaveManager] New game started.")

# -------------------------------------------------------
# Recruitable unit pool — used for tutorial reward and
# any future dungeon recruit events
# -------------------------------------------------------
const RECRUIT_NAME_POOL = {
	"KNIGHT": ["Knight"],
	"ARCHER": ["Archer"],
	"MAGE":   ["Mage"],
	"HEALER": ["Healer"],
	"ROGUE":  ["Rogue"],
}

const RECRUIT_BASE_STATS = {
	"KNIGHT": { "hp": 200, "attack": 15, "defense": 20, "speed": 2 },
	"ARCHER": { "hp": 100, "attack": 22, "defense": 8,  "speed": 5 },
	"MAGE":   { "hp": 80,  "attack": 30, "defense": 5,  "speed": 4 },
	"HEALER": { "hp": 120, "attack": 8,  "defense": 10, "speed": 3 },
	"ROGUE":  { "hp": 110, "attack": 26, "defense": 6,  "speed": 7 },
}

const RECRUIT_COST = {"food": 15, "gold": 15}

# Returns the recruit cost as a combined Food+Gold total, with the Talent
# Scout discount applied if unlocked (-20%, minimum 10).
func get_effective_recruit_cost() -> int:
	var base_cost = RECRUIT_COST["food"] + RECRUIT_COST["gold"]
	if PlayerInventory.unlocked_talents.get("recruiting_talent_scout", false):
		return max(10, int(base_cost * 0.8))
	return base_cost

# Returns how many recruit choices the shop should offer at once.
# Base is 1; Pick of the Litter raises it to 2, Cream of the Crop to 3.
func get_recruit_choice_count() -> int:
	if PlayerInventory.unlocked_talents.get("recruiting_cream_of_the_crop", false):
		return 3
	if PlayerInventory.unlocked_talents.get("recruiting_pick_of_the_litter", false):
		return 2
	return 1

# Generates a random recruitable TroopData of the given type (or fully random if omitted).
# Stats roll with small variance (±10%) around the type's base stats, so units
# of the same type aren't perfectly identical without overshadowing gear as the
# primary power source.
func generate_recruit(troop_type: String = "") -> TroopData:
	if troop_type == "":
		var types = RECRUIT_NAME_POOL.keys()
		troop_type = types[randi() % types.size()]

	var troop = TroopData.new()
	troop.troop_type = TroopData.TroopType[troop_type]
	var names = RECRUIT_NAME_POOL[troop_type]
	troop.troop_name = names[randi() % names.size()]
	troop.base_stats = _roll_stats(RECRUIT_BASE_STATS[troop_type])
	return troop

# Rolls each stat within ±10% of its base value, rounded to a whole number
# (minimum 1) so stats never roll down to zero or negative.
func _roll_stats(base: Dictionary) -> Dictionary:
	var rolled = {}
	for stat in base:
		var val = base[stat]
		var variance = val * 0.1
		rolled[stat] = max(1, int(round(val + randf_range(-variance, variance))))
	return rolled

func _dict_to_gear(d: Dictionary) -> GearItem:
	var gear = GearItem.new()
	gear.item_name   = d.get("name", "Unknown")
	gear.rarity      = int(d.get("rarity", 0))
	gear.slot        = int(d.get("slot", 0))
	gear.quality     = int(d.get("quality", 0))
	gear.item_level  = int(d.get("item_level", 5))   # default for saves predating item level
	gear.stats       = d.get("stats", {})
	gear.stat_ranges = d.get("stat_ranges", {})
	gear.set_name    = d.get("set_name", "")
	gear.upgrade_level = int(d.get("upgrade_level", 0))   # default for saves predating upgrades
	return gear


# -------------------------------------------------------
# World map zone serialization
# Zones contain Vector2 positions which JSON can't store directly,
# so we convert pos <-> {x, y} on save/load. Buildings dict (name -> level)
# and troops array (id strings) are already JSON-safe.
# -------------------------------------------------------
func _serialize_zones(zones: Array) -> Array:
	var result = []
	for zone in zones:
		var z = zone.duplicate(true)
		z["pos"] = {"x": zone["pos"].x, "y": zone["pos"].y}
		result.append(z)
	return result

func _deserialize_zones(zones_data: Array) -> Array:
	var result = []
	for z in zones_data:
		var zone = z.duplicate(true)
		zone["pos"] = Vector2(z["pos"]["x"], z["pos"]["y"])
		# JSON has no int/float distinction — every number becomes a
		# float on load. id and connections are used as array indices
		# elsewhere, where a stray float can cause silent lookup bugs,
		# so cast them back explicitly.
		zone["id"] = int(zone.get("id", 0))
		zone["enemy_strength"] = int(zone.get("enemy_strength", 0))
		var fixed_connections = []
		for c in zone.get("connections", []):
			fixed_connections.append(int(c))
		zone["connections"] = fixed_connections
		result.append(zone)
	return result
