extends Node2D

# -------------------------------------------------------
# Tutorial Dungeon — scripted intro, 3 short rooms,
# ends with a choice of 2 random recruits
# -------------------------------------------------------

const ROOM_W = 640
const ROOM_H = 480
const WALL_T = 32

const C_FLOOR  = Color(0.16, 0.14, 0.20)
const C_WALL   = Color(0.28, 0.24, 0.32)
const C_HERO   = Color(0.30, 0.70, 1.00)
const C_ENEMY  = Color(0.85, 0.25, 0.25)
const C_PROJ_H = Color(0.50, 0.90, 1.00)
const C_PROJ_E = Color(1.00, 0.55, 0.10)

const HERO_SPEED = 180.0
const ATTACK_INTERVAL = 0.7
const PROJ_SPEED = 320.0

var room_index: int = 0
var total_rooms: int = 3

var hero_hp: int = 120
var hero_max_hp: int = 120
var hero_attack: int = 16
var attack_timer: float = 0.0

var hero_pos: Vector2 = Vector2(ROOM_W/2, ROOM_H/2)
var enemies: Array = []
var hero_projs: Array = []
var enemy_projs: Array = []

var room_node: Node2D = null
var hero_rect: ColorRect = null
var hud_hp: Label = null
var hud_room: Label = null
var hud_tip: Label = null

var game_over: bool = false
var room_cleared: bool = false

func _ready() -> void:
	_build_hud()
	_load_room(0)

func _load_room(idx: int) -> void:
	room_index = idx
	room_cleared = false

	if room_node:
		room_node.queue_free()
	room_node = Node2D.new()
	add_child(room_node)
	move_child(room_node, 0)

	enemies.clear()
	hero_projs.clear()
	enemy_projs.clear()
	hero_pos = Vector2(ROOM_W/2, ROOM_H/2)

	_build_room_visuals()
	_build_hero()
	_spawn_room_enemies(idx)
	_refresh_hud()

	match idx:
		0: _set_tip("WASD to move. Get close to enemies \\u2014 you'll auto-attack the nearest one.")
		1: _set_tip("Keep moving \\u2014 standing still near multiple foes gets dangerous fast.")
		2: _set_tip("Last room! Clear it to find your first recruit.")

func _build_room_visuals() -> void:
	_add_rect(room_node, Vector2(WALL_T, WALL_T), Vector2(ROOM_W-WALL_T*2, ROOM_H-WALL_T*2), C_FLOOR)
	_add_rect(room_node, Vector2(0,0), Vector2(ROOM_W, WALL_T), C_WALL)
	_add_rect(room_node, Vector2(0, ROOM_H-WALL_T), Vector2(ROOM_W, WALL_T), C_WALL)
	_add_rect(room_node, Vector2(0,0), Vector2(WALL_T, ROOM_H), C_WALL)
	_add_rect(room_node, Vector2(ROOM_W-WALL_T, 0), Vector2(WALL_T, ROOM_H), C_WALL)

func _add_rect(parent: Node, pos: Vector2, sz: Vector2, col: Color) -> void:
	var r = ColorRect.new()
	r.position = pos
	r.size = sz
	r.color = col
	parent.add_child(r)

func _build_hero() -> void:
	if hero_rect: hero_rect.queue_free()
	hero_rect = ColorRect.new()
	hero_rect.size = Vector2(24, 24)
	hero_rect.color = C_HERO
	room_node.add_child(hero_rect)
	hero_rect.position = hero_pos - Vector2(12, 12)

func _spawn_room_enemies(idx: int) -> void:
	var count = [1, 2, 3][idx]
	for i in range(count):
		var ex = randf_range(WALL_T + 100, ROOM_W - WALL_T - 100)
		var ey = randf_range(WALL_T + 100, ROOM_H - WALL_T - 100)
		var sz = 28.0
		var max_hp = 18 + idx * 10

		var rect = ColorRect.new()
		rect.size = Vector2(sz, sz)
		rect.color = C_ENEMY
		rect.position = Vector2(ex - sz/2, ey - sz/2)
		room_node.add_child(rect)

		enemies.append({
			"pos": Vector2(ex, ey), "hp": max_hp, "max_hp": max_hp,
			"attack": 4 + idx * 2, "speed": 50.0,
			"shoot_t": randf_range(1.0, 2.0), "sz": sz, "rect": rect,
		})

func _process(delta: float) -> void:
	if game_over: return
	_move_hero(delta)
	_attack_tick(delta)
	_move_projectiles(delta)
	_process_enemies(delta)
	_update_visuals()
	_check_room_cleared()

func _move_hero(delta: float) -> void:
	var dir = Vector2.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):    dir.y -= 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):  dir.y += 1
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):  dir.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): dir.x += 1
	if dir.length() > 0: dir = dir.normalized()
	hero_pos += dir * HERO_SPEED * delta
	hero_pos.x = clamp(hero_pos.x, WALL_T + 12, ROOM_W - WALL_T - 12)
	hero_pos.y = clamp(hero_pos.y, WALL_T + 12, ROOM_H - WALL_T - 12)

func _attack_tick(delta: float) -> void:
	attack_timer -= delta
	if attack_timer > 0 or enemies.is_empty(): return
	var nearest = null
	var nearest_dist = INF
	for e in enemies:
		var d = hero_pos.distance_to(e["pos"])
		if d < nearest_dist:
			nearest_dist = d
			nearest = e
	if nearest:
		attack_timer = ATTACK_INTERVAL
		_fire(hero_pos, nearest["pos"], true, hero_attack)

func _fire(from: Vector2, toward: Vector2, is_hero: bool, dmg: int) -> void:
	var dir = (toward - from).normalized()
	var rect = ColorRect.new()
	rect.size = Vector2(9, 9)
	rect.color = C_PROJ_H if is_hero else C_PROJ_E
	rect.position = from - Vector2(4.5, 4.5)
	room_node.add_child(rect)
	var proj = {"pos": Vector2(from.x, from.y), "dir": dir, "damage": dmg, "rect": rect}
	if is_hero: hero_projs.append(proj)
	else: enemy_projs.append(proj)

func _move_projectiles(delta: float) -> void:
	var new_h = []
	for p in hero_projs:
		if not is_instance_valid(p["rect"]): continue
		p["pos"] += p["dir"] * PROJ_SPEED * delta
		var oob = p["pos"].x < WALL_T or p["pos"].x > ROOM_W-WALL_T or p["pos"].y < WALL_T or p["pos"].y > ROOM_H-WALL_T
		if oob:
			p["rect"].queue_free()
			continue
		var hit = false
		for e in enemies:
			if p["pos"].distance_to(e["pos"]) < e["sz"]/2 + 5:
				e["hp"] -= p["damage"]
				if e["hp"] <= 0:
					_kill_enemy(e)
				p["rect"].queue_free()
				hit = true
				break
		if not hit: new_h.append(p)
	hero_projs = new_h

	var new_e = []
	for p in enemy_projs:
		if not is_instance_valid(p["rect"]): continue
		p["pos"] += p["dir"] * (PROJ_SPEED * 0.6) * delta
		var oob = p["pos"].x < WALL_T or p["pos"].x > ROOM_W-WALL_T or p["pos"].y < WALL_T or p["pos"].y > ROOM_H-WALL_T
		if oob:
			p["rect"].queue_free()
			continue
		if p["pos"].distance_to(hero_pos) < 16:
			_take_damage(p["damage"])
			p["rect"].queue_free()
		else:
			new_e.append(p)
	enemy_projs = new_e

func _process_enemies(delta: float) -> void:
	for e in enemies:
		var dir = (hero_pos - e["pos"]).normalized()
		e["pos"] += dir * e["speed"] * delta
		e["pos"].x = clamp(e["pos"].x, WALL_T + e["sz"]/2, ROOM_W - WALL_T - e["sz"]/2)
		e["pos"].y = clamp(e["pos"].y, WALL_T + e["sz"]/2, ROOM_H - WALL_T - e["sz"]/2)

		e["shoot_t"] -= delta
		if e["shoot_t"] <= 0:
			if hero_pos.distance_to(e["pos"]) < 250:
				_fire(e["pos"], hero_pos, false, e["attack"])
			e["shoot_t"] = randf_range(1.6, 2.4)

		if e["pos"].distance_to(hero_pos) < e["sz"]/2 + 14:
			_take_damage(e["attack"])

func _kill_enemy(e: Dictionary) -> void:
	if is_instance_valid(e["rect"]): e["rect"].queue_free()
	enemies.erase(e)

func _take_damage(amount: int) -> void:
	hero_hp -= amount
	hero_hp = max(0, hero_hp)
	_refresh_hud()
	if hero_hp <= 0:
		game_over = true
		_show_defeat()

func _check_room_cleared() -> void:
	if room_cleared or not enemies.is_empty(): return
	room_cleared = true
	_drop_fixed_gear(room_index)
	if room_index + 1 < total_rooms:
		get_tree().create_timer(1.0).timeout.connect(func(): _load_room(room_index + 1))
	else:
		game_over = true
		get_tree().create_timer(0.8).timeout.connect(_show_recruit_choice)

# -------------------------------------------------------
# Fixed tutorial gear — same every run, teaches the gear system
# without randomization confusing a first-time player
# -------------------------------------------------------
func _drop_fixed_gear(idx: int) -> void:
	var gear = GearItem.new()
	match idx:
		0:
			gear.item_name = "Apprentice's Blade"
			gear.rarity = GearItem.Rarity.COMMON
			gear.slot = GearItem.Slot.WEAPON
			gear.stats = {"attack": 6}
		1:
			gear.item_name = "Worn Chainmail"
			gear.rarity = GearItem.Rarity.RARE
			gear.slot = GearItem.Slot.ARMOR
			gear.stats = {"hp": 25, "armor": 8}
		2:
			gear.item_name = "Survivor's Band"
			gear.rarity = GearItem.Rarity.EPIC
			gear.slot = GearItem.Slot.RING
			gear.stats = {"attack": 8, "crit_chance": 0.06, "hp": 15}

	PlayerInventory.add_gear(gear)
	_set_tip("Found: %s! Check your inventory back at Management." % gear.item_name)

func _update_visuals() -> void:
	if hero_rect and is_instance_valid(hero_rect):
		hero_rect.position = hero_pos - Vector2(12, 12)
	for e in enemies:
		if is_instance_valid(e["rect"]):
			e["rect"].position = e["pos"] - Vector2(e["sz"]/2, e["sz"]/2)
	for p in hero_projs:
		if is_instance_valid(p["rect"]):
			p["rect"].position = p["pos"] - Vector2(4.5, 4.5)
	for p in enemy_projs:
		if is_instance_valid(p["rect"]):
			p["rect"].position = p["pos"] - Vector2(4.5, 4.5)

# -------------------------------------------------------
# HUD
# -------------------------------------------------------
func _build_hud() -> void:
	var hud = CanvasLayer.new()
	add_child(hud)

	var panel = PanelContainer.new()
	panel.position = Vector2(8, 8)
	hud.add_child(panel)

	var vbox = VBoxContainer.new()
	panel.add_child(vbox)

	hud_hp = Label.new()
	hud_hp.add_theme_font_size_override("font_size", 14)
	vbox.add_child(hud_hp)

	hud_room = Label.new()
	hud_room.add_theme_font_size_override("font_size", 12)
	hud_room.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	vbox.add_child(hud_room)

	# Tip banner top center
	var tip_panel = PanelContainer.new()
	tip_panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	tip_panel.position.y = 8
	hud.add_child(tip_panel)

	hud_tip = Label.new()
	hud_tip.add_theme_font_size_override("font_size", 13)
	hud_tip.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
	hud_tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tip_panel.add_child(hud_tip)

	_refresh_hud()

func _refresh_hud() -> void:
	if hud_hp:
		hud_hp.text = "HP: %d / %d" % [hero_hp, hero_max_hp]
		hud_hp.add_theme_color_override("font_color",
			Color(0.9,0.2,0.2) if hero_hp < hero_max_hp*0.3 else Color(0.3,0.9,0.3))
	if hud_room:
		hud_room.text = "Room %d / %d" % [room_index + 1, total_rooms]

func _set_tip(msg: String) -> void:
	if hud_tip: hud_tip.text = msg

# -------------------------------------------------------
# End states
# -------------------------------------------------------
func _show_defeat() -> void:
	var overlay = CanvasLayer.new()
	add_child(overlay)
	var bg = ColorRect.new()
	bg.color = Color(0,0,0,0.75)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(bg)

	var panel = PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	overlay.add_child(panel)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	panel.add_child(vbox)

	var title = Label.new()
	title.text = "Defeated"
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(0.9,0.2,0.2))
	vbox.add_child(title)

	var sub = Label.new()
	sub.text = "Don't worry \\u2014 try again. Sir Aldric is tougher than he looks."
	sub.add_theme_color_override("font_color", Color(0.8,0.8,0.8))
	vbox.add_child(sub)

	var btn = Button.new()
	btn.text = "Retry Tutorial"
	btn.custom_minimum_size = Vector2(200, 40)
	btn.pressed.connect(func(): get_tree().reload_current_scene())
	vbox.add_child(btn)

func _show_recruit_choice() -> void:
	var overlay = CanvasLayer.new()
	add_child(overlay)
	var bg = ColorRect.new()
	bg.color = Color(0,0,0,0.8)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(bg)

	var panel = PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	overlay.add_child(panel)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	panel.add_child(vbox)

	var title = Label.new()
	title.text = "Dungeon Cleared!"
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(0.3,0.9,0.3))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var sub = Label.new()
	sub.text = "You've found two survivors. Choose one to join your roster."
	sub.add_theme_color_override("font_color", Color(0.8,0.8,0.8))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(sub)

	# Roll 2 distinct random recruits
	var t1 = SaveManager.generate_recruit()
	var t2 = SaveManager.generate_recruit()
	var tries = 0
	while t2.troop_type == t1.troop_type and tries < 10:
		t2 = SaveManager.generate_recruit()
		tries += 1

	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 16)
	vbox.add_child(hbox)

	_add_recruit_card(hbox, t1)
	_add_recruit_card(hbox, t2)

func _add_recruit_card(parent: HBoxContainer, troop: TroopData) -> void:
	var card = PanelContainer.new()
	card.custom_minimum_size = Vector2(180, 0)
	parent.add_child(card)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	card.add_child(vbox)

	var name_lbl = Label.new()
	name_lbl.text = troop.troop_name
	name_lbl.add_theme_font_size_override("font_size", 15)
	name_lbl.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(name_lbl)

	var type_lbl = Label.new()
	type_lbl.text = "[%s]" % troop.get_type_name()
	type_lbl.add_theme_font_size_override("font_size", 12)
	type_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(type_lbl)

	var stats_lbl = Label.new()
	stats_lbl.text = "HP:%d ATK:%d\nDEF:%d SPD:%d" % [
		troop.base_stats.get("hp",0), troop.base_stats.get("attack",0),
		troop.base_stats.get("defense",0), troop.base_stats.get("speed",0)
	]
	stats_lbl.add_theme_font_size_override("font_size", 11)
	stats_lbl.add_theme_color_override("font_color", Color(0.75,0.75,0.75))
	stats_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(stats_lbl)

	var choose_btn = Button.new()
	choose_btn.text = "Recruit"
	choose_btn.custom_minimum_size = Vector2(0, 36)
	choose_btn.add_theme_color_override("font_color", Color(0.4, 0.9, 0.4))
	choose_btn.pressed.connect(_on_recruit_chosen.bind(troop))
	vbox.add_child(choose_btn)

func _on_recruit_chosen(troop: TroopData) -> void:
	PlayerInventory.troop_roster.append(troop)
	PlayerInventory.tutorial_complete = true
	SaveManager.save_game()
	get_tree().change_scene_to_file("res://scenes/world_map.tscn")
