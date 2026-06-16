extends Control

# -------------------------------------------------------
# Dungeon Scene — procedural room map, click through rooms
# Room types: combat, treasure, shop, rest
# -------------------------------------------------------

const BIOME_COLORS = {
	"crypt":        Color(0.45, 0.20, 0.55),
	"forest_ruins": Color(0.20, 0.50, 0.25),
	"dragon_lair":  Color(0.70, 0.25, 0.15),
}

const BIOME_NAMES = {
	"crypt":        "The Crypt",
	"forest_ruins": "Forest Ruins",
	"dragon_lair":  "Dragon's Lair",
}

const ROOM_TYPE_COLORS = {
	"combat":   Color(0.85, 0.25, 0.25),
	"treasure": Color(0.90, 0.75, 0.10),
	"shop":     Color(0.25, 0.70, 0.85),
	"rest":     Color(0.30, 0.80, 0.40),
	"boss":     Color(1.00, 0.10, 0.10),
}

const ROOM_ICONS = {
	"combat":   "⚔ Combat",
	"treasure": "★ Treasure",
	"shop":     "$ Shop",
	"rest":     "♥ Rest",
	"boss":     "☠ BOSS",
}

var current_biome: String = ""
var rooms: Array = []
var current_room_index: int = 0
var run_gear_collected: Array = []
var hero_hp: int = 100
var hero_max_hp: int = 100

# UI refs
var biome_label: Label
var room_map: VBoxContainer
var room_panel: PanelContainer
var room_content: VBoxContainer
var hero_hp_label: Label
var log_label: Label
var continue_btn: Button
var end_run_btn: Button

func _ready() -> void:
	_build_ui()
	_start_run()

# -------------------------------------------------------
# Run Setup
# -------------------------------------------------------

func _start_run() -> void:
	# Pick biome based on stage
	var stage = PlayerInventory.current_stage
	var biomes = ["crypt"]
	if stage >= 2: biomes.append("forest_ruins")
	if stage >= 5: biomes.append("dragon_lair")
	current_biome = biomes[randi() % biomes.size()]

	run_gear_collected.clear()
	hero_hp = hero_max_hp
	current_room_index = 0
	rooms = _generate_rooms()

	biome_label.text = BIOME_NAMES[current_biome] + "  |  " + PlayerInventory.dungeon_tier + "  |  Stage " + str(PlayerInventory.current_stage)
	biome_label.add_theme_color_override("font_color", BIOME_COLORS[current_biome])

	_refresh_map()
	_load_room(0)
	_log("You enter " + BIOME_NAMES[current_biome] + ". Good luck.")

func _generate_rooms() -> Array:
	var count_range = {"Quick": [5, 7], "Standard": [8, 12], "Deep Delve": [14, 18]}
	var range_for_tier = count_range.get(PlayerInventory.dungeon_tier, [8, 12])
	var count = randi_range(range_for_tier[0], range_for_tier[1])
	var result = []

	# First room always combat, last always boss
	result.append("combat")

	# Middle rooms weighted random
	var weights = { "combat": 50, "treasure": 20, "shop": 15, "rest": 15 }
	for i in range(count - 2):
		result.append(_weighted_pick(weights))

	result.append("boss")
	return result

func _weighted_pick(weights: Dictionary) -> String:
	var total = 0
	for w in weights.values(): total += w
	var roll = randi() % total
	var cumulative = 0
	for key in weights:
		cumulative += weights[key]
		if roll < cumulative:
			return key
	return "combat"

# -------------------------------------------------------
# Room Loading
# -------------------------------------------------------

func _load_room(index: int) -> void:
	current_room_index = index
	_refresh_map()

	# Clear room content
	for child in room_content.get_children():
		child.queue_free()
	continue_btn.visible = false

	var room_type = rooms[index]
	var is_last = (index == rooms.size() - 1)

	match room_type:
		"combat", "boss":
			_load_combat_room(room_type)
		"treasure":
			_load_treasure_room()
		"shop":
			_load_shop_room()
		"rest":
			_load_rest_room()

func _load_combat_room(room_type: String) -> void:
	var is_boss = (room_type == "boss")
	var difficulty = PlayerInventory.current_stage + (2 if is_boss else 0)
	difficulty = clamp(difficulty, 1, 10)

	var enemy = _generate_enemy(is_boss, difficulty)

	var title = Label.new()
	title.text = ("☠ BOSS: " if is_boss else "⚔ Enemy: ") + enemy["name"]
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", ROOM_TYPE_COLORS[room_type])
	room_content.add_child(title)

	var enemy_stats = Label.new()
	enemy_stats.text = "HP: %d  |  ATK: %d  |  DEF: %d" % [enemy["hp"], enemy["attack"], enemy["defense"]]
	enemy_stats.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	room_content.add_child(enemy_stats)

	var sep = HSeparator.new()
	room_content.add_child(sep)

	# Fight button
	var fight_btn = Button.new()
	fight_btn.text = "⚔  Fight!"
	fight_btn.custom_minimum_size = Vector2(160, 40)
	fight_btn.pressed.connect(_do_combat.bind(enemy, fight_btn))
	room_content.add_child(fight_btn)

func _load_treasure_room() -> void:
	var title = Label.new()
	title.text = "★ Treasure Room"
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", ROOM_TYPE_COLORS["treasure"])
	room_content.add_child(title)

	var diff = clamp(PlayerInventory.current_stage + randi_range(0, 2), 1, 10)
	if PlayerInventory.dungeon_tier == "Deep Delve":
		diff = clamp(diff + 2, 1, 10)
	var gear = GearGenerator.generate(current_biome, diff)
	run_gear_collected.append(gear)
	PlayerInventory.add_gear(gear)

	var desc = Label.new()
	desc.text = "You found:\n[%s] %s\n%s\nStats: %s" % [
		gear.get_rarity_name(), gear.item_name,
		gear.get_slot_name(), str(gear.stats)
	]
	desc.add_theme_color_override("font_color", _rarity_color(gear.get_rarity_name()))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD
	room_content.add_child(desc)

	_log("Found " + gear.item_name + "!")
	continue_btn.visible = true

func _load_shop_room() -> void:
	var title = Label.new()
	title.text = "$ Shop  (Coming soon — skip for now)"
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", ROOM_TYPE_COLORS["shop"])
	room_content.add_child(title)

	var desc = Label.new()
	desc.text = "The merchant nods. You browse but find nothing of interest today."
	desc.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD
	room_content.add_child(desc)

	_log("You visited the shop.")
	continue_btn.visible = true

func _load_rest_room() -> void:
	var title = Label.new()
	title.text = "♥ Rest Site"
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", ROOM_TYPE_COLORS["rest"])
	room_content.add_child(title)

	var heal_amount = int(hero_max_hp * 0.30)
	hero_hp = min(hero_hp + heal_amount, hero_max_hp)
	_refresh_hero_hp()

	var desc = Label.new()
	desc.text = "You rest by a campfire and recover %d HP.\nCurrent HP: %d / %d" % [heal_amount, hero_hp, hero_max_hp]
	desc.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	room_content.add_child(desc)

	_log("Rested and recovered %d HP." % heal_amount)
	continue_btn.visible = true

# -------------------------------------------------------
# Combat
# -------------------------------------------------------

func _generate_enemy(is_boss: bool, difficulty: int) -> Dictionary:
	var base_hp     = 30 + difficulty * 12
	var base_atk    = 5  + difficulty * 3
	var base_def    = 2  + difficulty * 2

	if is_boss:
		base_hp  = int(base_hp  * 2.5)
		base_atk = int(base_atk * 1.8)
		base_def = int(base_def * 1.5)

	# Dungeon tier scaling — Quick is gentler, Deep Delve is meaningfully harder,
	# matching the same multipliers used in the Action Dungeon for consistency.
	var tier_mult = {"Quick": 0.8, "Standard": 1.0, "Deep Delve": 1.4}.get(PlayerInventory.dungeon_tier, 1.0)
	base_hp = int(base_hp * tier_mult)
	base_atk = int(base_atk * tier_mult)
	base_def = int(base_def * tier_mult)

	var enemy_names = {
		"crypt":        ["Skeleton", "Ghoul", "Wraith", "Lich"],
		"forest_ruins": ["Goblin Scout", "Stone Golem", "Vine Horror", "Treant"],
		"dragon_lair":  ["Fire Drake", "Kobold Warlord", "Lava Elemental", "Elder Dragon"],
	}
	var boss_names = {
		"crypt":        "The Tomb King",
		"forest_ruins": "The Ancient Guardian",
		"dragon_lair":  "Ignarax the Destroyer",
	}

	var name_list = enemy_names.get(current_biome, enemy_names["crypt"])
	var ename = boss_names[current_biome] if is_boss else name_list[randi() % name_list.size()]

	return { "name": ename, "hp": base_hp, "attack": base_atk, "defense": base_def, "is_boss": is_boss }

func _do_combat(enemy: Dictionary, fight_btn: Button) -> void:
	fight_btn.disabled = true

	# Get hero effective stats from first troop (player's hero stand-in for now)
	var hero_atk = 20
	var hero_def = 10
	PlayerInventory.ensure_hero_exists()
	var eff = PlayerInventory.hero.get_effective_stats()
	hero_atk = eff.get("attack", 20)
	hero_def = eff.get("defense", 10)

	var enemy_hp = enemy["hp"]
	var rounds = 0
	var combat_log = []

	while enemy_hp > 0 and hero_hp > 0 and rounds < 20:
		rounds += 1
		# Hero attacks
		var hero_dmg = max(1, hero_atk - enemy["defense"] + randi_range(-3, 5))
		enemy_hp -= hero_dmg
		# Enemy attacks
		var enemy_dmg = max(1, enemy["attack"] - hero_def + randi_range(-2, 4))
		if enemy_hp > 0:
			hero_hp -= enemy_dmg
			hero_hp = max(0, hero_hp)
		combat_log.append("Rnd %d: You deal %d dmg. Enemy deals %d dmg." % [rounds, hero_dmg, enemy_dmg])

	_refresh_hero_hp()

	# Show last 3 rounds
	var shown = combat_log.slice(max(0, combat_log.size() - 3))
	for line in shown:
		_log(line)

	if hero_hp <= 0:
		_on_run_failed()
	elif enemy_hp <= 0:
		var is_boss = enemy.get("is_boss", false)
		_log("Victory! " + enemy["name"] + " defeated.")

		# Drop gear on combat win
		var diff = clamp(PlayerInventory.current_stage + (2 if is_boss else 0), 1, 10)
		if PlayerInventory.dungeon_tier == "Deep Delve":
			diff = clamp(diff + 2, 1, 10)
		var gear = GearGenerator.generate(current_biome, diff)
		run_gear_collected.append(gear)
		PlayerInventory.add_gear(gear)
		_log("Dropped: [%s] %s" % [gear.get_rarity_name(), gear.item_name])

		if is_boss:
			_on_run_complete()
		else:
			continue_btn.visible = true

func _on_run_failed() -> void:
	_log("You have been defeated... Run over.")
	hero_hp = hero_max_hp  # Reset for next run

	var result_label = Label.new()
	result_label.text = "DEFEATED\nYou collected %d gear items this run.\nReturning to management..." % run_gear_collected.size()
	result_label.add_theme_color_override("font_color", Color(0.9, 0.3, 0.3))
	result_label.add_theme_font_size_override("font_size", 16)
	room_content.add_child(result_label)

	end_run_btn.text = "Back to Management"
	end_run_btn.visible = true

func _on_run_complete() -> void:
	PlayerInventory.current_stage += 1

	# Unlock troop slot at stages 3, 5, 8
	if PlayerInventory.current_stage in [3, 5, 8]:
		PlayerInventory.unlock_troop_slot()
		_log("New troop slot unlocked!")

	var result_label = Label.new()
	result_label.text = "RUN COMPLETE!\nStage %d cleared.\nGear collected: %d items.\nReturning to management..." % [
		PlayerInventory.current_stage - 1,
		run_gear_collected.size()
	]
	result_label.add_theme_color_override("font_color", Color(0.3, 0.9, 0.3))
	result_label.add_theme_font_size_override("font_size", 16)
	room_content.add_child(result_label)

	end_run_btn.text = "Back to Management"
	end_run_btn.visible = true

# -------------------------------------------------------
# UI
# -------------------------------------------------------

func _refresh_map() -> void:
	for child in room_map.get_children():
		child.queue_free()

	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 2)
	room_map.add_child(hbox)

	for i in range(rooms.size()):
		var room_type = rooms[i]
		var btn = Button.new()
		btn.custom_minimum_size = Vector2(36, 36)
		btn.text = str(i + 1)
		btn.tooltip_text = ROOM_ICONS[room_type]

		if i < current_room_index:
			btn.add_theme_color_override("font_color", Color(0.4, 0.4, 0.4))
		elif i == current_room_index:
			btn.add_theme_color_override("font_color", Color(1, 1, 0))
		else:
			btn.add_theme_color_override("font_color", ROOM_TYPE_COLORS[room_type])

		btn.disabled = true
		hbox.add_child(btn)

func _refresh_hero_hp() -> void:
	hero_hp_label.text = "Hero HP: %d / %d" % [hero_hp, hero_max_hp]
	if hero_hp < hero_max_hp * 0.3:
		hero_hp_label.add_theme_color_override("font_color", Color(0.9, 0.2, 0.2))
	elif hero_hp < hero_max_hp * 0.6:
		hero_hp_label.add_theme_color_override("font_color", Color(0.9, 0.7, 0.2))
	else:
		hero_hp_label.add_theme_color_override("font_color", Color(0.3, 0.9, 0.3))

func _log(msg: String) -> void:
	log_label.text = msg + "\n" + log_label.text
	# Keep last 6 lines
	var lines = log_label.text.split("\n")
	if lines.size() > 6:
		lines = lines.slice(0, 6)
	log_label.text = "\n".join(lines)

func _rarity_color(rarity_name: String) -> Color:
	match rarity_name:
		"COMMON":    return Color(0.75, 0.75, 0.75)
		"RARE":      return Color(0.25, 0.50, 1.00)
		"EPIC":      return Color(0.65, 0.25, 0.90)
		"LEGENDARY": return Color(1.00, 0.65, 0.10)
	return Color.WHITE

func _build_ui() -> void:
	var bg = ColorRect.new()
	bg.color = Color(0.08, 0.08, 0.12, 1)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var outer = VBoxContainer.new()
	outer.set_anchors_preset(Control.PRESET_FULL_RECT)
	outer.add_theme_constant_override("separation", 6)
	add_child(outer)

	# Biome title
	biome_label = Label.new()
	biome_label.text = "Dungeon"
	biome_label.add_theme_font_size_override("font_size", 20)
	outer.add_child(biome_label)

	# Hero HP
	hero_hp_label = Label.new()
	hero_hp_label.text = "Hero HP: 100 / 100"
	hero_hp_label.add_theme_font_size_override("font_size", 13)
	outer.add_child(hero_hp_label)

	# Room map (scrollable row of room buttons)
	var map_scroll = ScrollContainer.new()
	map_scroll.custom_minimum_size = Vector2(0, 50)
	outer.add_child(map_scroll)

	room_map = VBoxContainer.new()
	map_scroll.add_child(room_map)

	var sep = HSeparator.new()
	outer.add_child(sep)

	# Room panel
	room_panel = PanelContainer.new()
	room_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(room_panel)

	room_content = VBoxContainer.new()
	room_content.add_theme_constant_override("separation", 8)
	room_panel.add_child(room_content)

	# Continue / End Run buttons
	continue_btn = Button.new()
	continue_btn.text = "Continue >"
	continue_btn.custom_minimum_size = Vector2(140, 38)
	continue_btn.visible = false
	continue_btn.pressed.connect(_on_continue)
	outer.add_child(continue_btn)

	end_run_btn = Button.new()
	end_run_btn.text = "Back to Management"
	end_run_btn.custom_minimum_size = Vector2(200, 38)
	end_run_btn.visible = false
	end_run_btn.pressed.connect(_on_end_run)
	outer.add_child(end_run_btn)

	# Combat log
	var log_header = Label.new()
	log_header.text = "— Log —"
	log_header.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	outer.add_child(log_header)

	log_label = Label.new()
	log_label.text = ""
	log_label.add_theme_font_size_override("font_size", 11)
	log_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	log_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	outer.add_child(log_label)

func _on_continue() -> void:
	continue_btn.visible = false
	if current_room_index + 1 < rooms.size():
		_load_room(current_room_index + 1)
	else:
		_on_run_complete()

func _on_end_run() -> void:
	get_tree().change_scene_to_file("res://scenes/management_screen.tscn")
