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
		"player_name": PlayerInventory.player_name,
		"map_seed": PlayerInventory.map_seed,
		"difficulty": PlayerInventory.difficulty,
		"difficulty_settings": PlayerInventory.difficulty_settings,
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
			"stats": gear.stats,
			"stat_ranges": gear.stat_ranges,
			"set_name": gear.set_name,
		})

	# Save troops and their equipped gear
	for troop in PlayerInventory.troop_roster:
		var t_data = {
			"name": troop.troop_name,
			"type": troop.troop_type,
			"base_stats": troop.base_stats,
			"equipped": {},
		}
		for slot_key in troop.equipped_gear:
			var gear = troop.equipped_gear[slot_key]
			if gear:
				t_data["equipped"][slot_key] = {
					"name": gear.item_name,
					"rarity": gear.rarity,
					"slot": gear.slot,
					"stats": gear.stats,
					"set_name": gear.set_name,
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
	PlayerInventory.tutorial_complete = data.get("tutorial_complete", false)
	if data.has("talents"):
		for key in data["talents"]:
			if PlayerInventory.talents.has(key):
				PlayerInventory.talents[key] = data["talents"][key]
	PlayerInventory.gear_inventory.clear()
	PlayerInventory.troop_roster.clear()

	# Load gear inventory
	for g in data.get("gear", []):
		var gear = _dict_to_gear(g)
		PlayerInventory.gear_inventory.append(gear)

	# Load troops
	for t in data.get("troops", []):
		var troop = TroopData.new()
		troop.troop_name = t["name"]
		troop.troop_type = int(t["type"])
		troop.base_stats = t["base_stats"]
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

	# Starting troop — just the Knight. A second unit is earned via the tutorial dungeon.
	var knight = TroopData.new()
	knight.troop_name = "Sir Aldric"
	knight.troop_type = TroopData.TroopType.KNIGHT
	knight.base_stats = { "hp": 200, "attack": 15, "defense": 20, "speed": 2 }
	PlayerInventory.troop_roster.append(knight)

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
	"KNIGHT": ["Sir Garran", "Dame Wrenna", "Sir Tobias"],
	"ARCHER": ["Mira", "Fenwick", "Lyssa Swift"],
	"MAGE":   ["Lyra", "Oswin the Pale", "Vesper"],
	"HEALER": ["Brother Edwyn", "Sister Maren", "Calder"],
	"ROGUE":  ["Vex", "Shade", "Quinn Blackpool"],
}

const RECRUIT_BASE_STATS = {
	"KNIGHT": { "hp": 200, "attack": 15, "defense": 20, "speed": 2 },
	"ARCHER": { "hp": 100, "attack": 22, "defense": 8,  "speed": 5 },
	"MAGE":   { "hp": 80,  "attack": 30, "defense": 5,  "speed": 4 },
	"HEALER": { "hp": 120, "attack": 8,  "defense": 10, "speed": 3 },
	"ROGUE":  { "hp": 110, "attack": 26, "defense": 6,  "speed": 7 },
}

# Generates a random recruitable TroopData of the given type (or fully random if omitted)
func generate_recruit(troop_type: String = "") -> TroopData:
	if troop_type == "":
		var types = RECRUIT_NAME_POOL.keys()
		troop_type = types[randi() % types.size()]

	var troop = TroopData.new()
	troop.troop_type = TroopData.TroopType[troop_type]
	var names = RECRUIT_NAME_POOL[troop_type]
	troop.troop_name = names[randi() % names.size()]
	troop.base_stats = RECRUIT_BASE_STATS[troop_type].duplicate()
	return troop

func _dict_to_gear(d: Dictionary) -> GearItem:
	var gear = GearItem.new()
	gear.item_name   = d.get("name", "Unknown")
	gear.rarity      = int(d.get("rarity", 0))
	gear.slot        = int(d.get("slot", 0))
	gear.quality     = int(d.get("quality", 0))
	gear.stats       = d.get("stats", {})
	gear.stat_ranges = d.get("stat_ranges", {})
	gear.set_name    = d.get("set_name", "")
	return gear
