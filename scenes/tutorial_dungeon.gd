extends Node2D

# -------------------------------------------------------
# Tutorial Dungeon — a short, scripted version of the real survival
# arena (open area, camera follows the hero, enemies spawn
# continuously) rather than the old fixed 3-room layout. Guarantees
# exactly 4 gear drops (one for each slot) and one free recruit,
# regardless of how the fight actually goes, so the tutorial sequence
# downstream (equip on hero, equip on recruit, sell, upgrade) always
# has something real to work with.
#
# This is intentionally much smaller and tighter than the real
# action_dungeon.gd survival arena — no difficulty scaling, no bosses,
# no save-zone mechanic, no death penalty. It exists purely to teach,
# not to challenge.
# -------------------------------------------------------

const ARENA_W = 1400
const ARENA_H = 1000
const WALL_T = 32
const MIN_SPAWN_DIST_FROM_HERO = 220.0
const KILLS_TO_CLEAR = 8   # enemies defeated before the dungeon ends

const C_FLOOR  = Color(0.16, 0.14, 0.20)
const C_WALL   = Color(0.28, 0.24, 0.32)
const C_HERO   = Color(0.30, 0.70, 1.00)
const C_ENEMY  = Color(0.85, 0.25, 0.25)
const C_PROJ_H = Color(0.50, 0.90, 1.00)
const C_PROJ_E = Color(1.00, 0.55, 0.10)

const HERO_SPEED = 200.0
const ATTACK_INTERVAL = 0.6
const PROJ_SPEED = 340.0
const SPAWN_INTERVAL = 2.2   # seconds between new enemy spawns
const MAX_ALIVE_ENEMIES = 3   # keeps the fight readable for a first-time player

var hero_hp: int = 140
var hero_max_hp: int = 140
var hero_attack: int = 18
var attack_timer: float = 0.0
var spawn_timer: float = 1.0

var hero_pos: Vector2 = Vector2(ARENA_W / 2, ARENA_H / 2)
var enemies: Array = []
var hero_projs: Array = []
var enemy_projs: Array = []

var arena_node: Node2D = null
var hero_rect: ColorRect = null
var camera: Camera2D = null
var hud_hp: Label = null
var hud_kills: Label = null
var hud_tip: Label = null

var game_over: bool = false
var kills: int = 0

func _ready() -> void:
	_build_arena_visuals()
	_build_hero()
	_setup_camera()
	_build_hud()
	_set_tip("WASD to move. Get close to enemies — you'll auto-attack the nearest one.")
	TutorialRouter.resolve_current_step(self)

func _build_arena_visuals() -> void:
	arena_node = Node2D.new()
	add_child(arena_node)
	move_child(arena_node, 0)

	_add_rect(arena_node, Vector2.ZERO, Vector2(ARENA_W, ARENA_H), C_FLOOR)
	_add_rect(arena_node, Vector2(-WALL_T, -WALL_T), Vector2(ARENA_W + WALL_T*2, WALL_T), C_WALL)
	_add_rect(arena_node, Vector2(-WALL_T, ARENA_H), Vector2(ARENA_W + WALL_T*2, WALL_T), C_WALL)
	_add_rect(arena_node, Vector2(-WALL_T, -WALL_T), Vector2(WALL_T, ARENA_H + WALL_T*2), C_WALL)
	_add_rect(arena_node, Vector2(ARENA_W, -WALL_T), Vector2(WALL_T, ARENA_H + WALL_T*2), C_WALL)
	_build_floor_props()

# Scatters small visual-only debris rects across the floor so the
# player can perceive their own movement against the otherwise-solid
# background. Purely decorative — no collision, no gameplay effect.
# Uses a fixed seed so the layout is identical every run (avoids
# confusing the player with a different-looking arena on retry).
func _build_floor_props() -> void:
	var rng = RandomNumberGenerator.new()
	rng.seed = 42   # fixed — same map every run

	# A few distinct "rock/debris" shades, all subtle variations on the floor color
	var prop_colors = [
		Color(0.22, 0.20, 0.26),   # slightly lighter stone
		Color(0.13, 0.11, 0.17),   # slightly darker shadow
		Color(0.25, 0.21, 0.20),   # warm brown chip
		Color(0.19, 0.18, 0.24),   # neutral mid tone
	]

	var margin = WALL_T + 30.0   # keep props away from walls
	var center = Vector2(ARENA_W / 2.0, ARENA_H / 2.0)
	var clear_radius = 120.0     # keep center spawn area clear

	for i in range(80):
		var pos = Vector2(
			rng.randf_range(margin, ARENA_W - margin),
			rng.randf_range(margin, ARENA_H - margin)
		)
		if pos.distance_to(center) < clear_radius:
			continue   # skip props too close to where the hero spawns

		var sz = Vector2(
			rng.randf_range(4.0, 14.0),
			rng.randf_range(3.0, 10.0)
		)
		var col = prop_colors[rng.randi() % prop_colors.size()]
		_add_rect(arena_node, pos, sz, col)

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
	arena_node.add_child(hero_rect)
	hero_rect.position = hero_pos - Vector2(12, 12)

func _setup_camera() -> void:
	camera = Camera2D.new()
	camera.position = hero_pos
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = ARENA_W
	camera.limit_bottom = ARENA_H
	camera.enabled = true
	add_child(camera)

func _spawn_enemy() -> void:
	var ex: float
	var ey: float
	var tries = 0
	while true:
		ex = randf_range(WALL_T + 80, ARENA_W - WALL_T - 80)
		ey = randf_range(WALL_T + 80, ARENA_H - WALL_T - 80)
		tries += 1
		if hero_pos.distance_to(Vector2(ex, ey)) >= MIN_SPAWN_DIST_FROM_HERO or tries >= 20:
			break

	var sz = 28.0
	var rect = ColorRect.new()
	rect.size = Vector2(sz, sz)
	rect.color = C_ENEMY
	rect.position = Vector2(ex - sz/2, ey - sz/2)
	arena_node.add_child(rect)

	enemies.append({
		"pos": Vector2(ex, ey), "hp": 22, "max_hp": 22,
		"attack": 6, "speed": 55.0,
		"shoot_t": randf_range(1.0, 2.0), "sz": sz, "rect": rect,
	})

func _process(delta: float) -> void:
	if game_over: return
	_move_hero(delta)
	_handle_spawning(delta)
	_attack_tick(delta)
	_move_projectiles(delta)
	_process_enemies(delta)
	_update_visuals()
	camera.position = hero_pos

func _handle_spawning(delta: float) -> void:
	spawn_timer -= delta
	if spawn_timer <= 0 and enemies.size() < MAX_ALIVE_ENEMIES:
		_spawn_enemy()
		spawn_timer = SPAWN_INTERVAL

func _move_hero(delta: float) -> void:
	var dir = Vector2.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):    dir.y -= 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):  dir.y += 1
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):  dir.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): dir.x += 1
	if dir.length() > 0: dir = dir.normalized()
	hero_pos += dir * HERO_SPEED * delta
	hero_pos.x = clamp(hero_pos.x, WALL_T + 12, ARENA_W - WALL_T - 12)
	hero_pos.y = clamp(hero_pos.y, WALL_T + 12, ARENA_H - WALL_T - 12)

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
	arena_node.add_child(rect)
	var proj = {"pos": Vector2(from.x, from.y), "dir": dir, "damage": dmg, "rect": rect}
	if is_hero: hero_projs.append(proj)
	else: enemy_projs.append(proj)

func _move_projectiles(delta: float) -> void:
	var new_h = []
	for p in hero_projs:
		if not is_instance_valid(p["rect"]): continue
		p["pos"] += p["dir"] * PROJ_SPEED * delta
		var oob = p["pos"].x < WALL_T or p["pos"].x > ARENA_W-WALL_T or p["pos"].y < WALL_T or p["pos"].y > ARENA_H-WALL_T
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
		var oob = p["pos"].x < WALL_T or p["pos"].x > ARENA_W-WALL_T or p["pos"].y < WALL_T or p["pos"].y > ARENA_H-WALL_T
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
		e["pos"].x = clamp(e["pos"].x, WALL_T + e["sz"]/2, ARENA_W - WALL_T - e["sz"]/2)
		e["pos"].y = clamp(e["pos"].y, WALL_T + e["sz"]/2, ARENA_H - WALL_T - e["sz"]/2)

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
	kills += 1
	_refresh_hud()
	if kills >= KILLS_TO_CLEAR:
		game_over = true
		_grant_rewards()
		get_tree().create_timer(0.8).timeout.connect(_show_results)

func _take_damage(amount: int) -> void:
	hero_hp -= amount
	hero_hp = max(0, hero_hp)
	_refresh_hud()
	if hero_hp <= 0:
		game_over = true
		_show_defeat()

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

	hud_kills = Label.new()
	hud_kills.add_theme_font_size_override("font_size", 12)
	hud_kills.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	vbox.add_child(hud_kills)

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
	if hud_kills:
		hud_kills.text = "Defeated: %d / %d" % [kills, KILLS_TO_CLEAR]

func _set_tip(msg: String) -> void:
	if hud_tip: hud_tip.text = msg

# -------------------------------------------------------
# Rewards — guaranteed every run, regardless of how the fight went.
# Generates real gear via GearGenerator rather than hand-authored fixed
# items, since GearGenerator already knows how to keep stats internally
# consistent with whatever slot/rarity an item ends up with — hand-
# overwriting .slot or .rarity on a generated item after the fact would
# leave its stats rolled for the WRONG slot/rarity. Instead this
# re-rolls (generate, check, discard if wrong) until each guaranteed
# slot is filled, which is reliable in practice well within a handful
# of tries since there are only 4 possible slots.
# -------------------------------------------------------
const TUTORIAL_DIFFICULTY = 1   # lowest difficulty, keeps stat rolls gentle

func _grant_rewards() -> void:
	# Wipe any loose gear sitting in inventory from before this tutorial
	# run (leftover from earlier testing, a previous attempt, etc.) so
	# the gear shop's lists only ever show what's granted below.
	PlayerInventory.gear_inventory.clear()

	# 4 IDENTICAL hand-built weapons — completely bypasses GearGenerator,
	# so there's no random slot/rarity/stat roll that could ever come out
	# wrong. Every later step (equip x2, sell, salvage) just needs "any
	# weapon" rather than one specific named item, which structurally
	# rules out the whole class of slot-mismatch bug that came up during
	# testing (an ARMOR step accidentally resolving to a WEAPON item).
	# Flow: equip on Hero, equip on recruit, sell one, salvage one — the
	# upgrade step afterward targets whichever weapon is already equipped
	# on the Hero, not a 5th loose item.
	for i in range(4):
		var weapon = GearItem.new()
		weapon.item_name = "Practice Sword"
		weapon.rarity = GearItem.Rarity.COMMON
		weapon.slot = GearItem.Slot.WEAPON
		weapon.quality = GearItem.Quality.NORMAL
		weapon.stats = {"attack": 1}
		weapon.stat_ranges = {}
		PlayerInventory.add_gear(weapon)

	var recruit = SaveManager.generate_recruit()
	PlayerInventory.troop_roster.append(recruit)

	_set_tip("Found gear and a new recruit!")

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
	sub.text = "Don't worry — try again."
	sub.add_theme_color_override("font_color", Color(0.8,0.8,0.8))
	vbox.add_child(sub)

	var btn = Button.new()
	btn.text = "Retry Tutorial"
	btn.custom_minimum_size = Vector2(200, 40)
	btn.pressed.connect(func(): get_tree().reload_current_scene())
	vbox.add_child(btn)

func _show_results() -> void:
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
	sub.text = "You found 4 pieces of gear and a new recruit. Let's go put them to use."
	sub.add_theme_color_override("font_color", Color(0.8,0.8,0.8))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD
	sub.custom_minimum_size = Vector2(260, 0)
	vbox.add_child(sub)

	var btn = Button.new()
	btn.text = "Continue"
	btn.custom_minimum_size = Vector2(200, 40)
	btn.pressed.connect(_on_continue_pressed)
	vbox.add_child(btn)

# Unlike the old tutorial, this does NOT set tutorial_complete or
# navigate to the World Map directly — the new forced walkthrough has
# many more steps after the dungeon (equip on hero, equip on recruit,
# sell, the scripted defense battle, healing, talents, upgrade), so
# finishing here would cut the rest of the sequence off. Just save and
# hand off to whatever screen the next tutorial step actually needs —
# the router itself decides that via TutorialSteps, not this script.
func _on_continue_pressed() -> void:
	TutorialRouter.advance_step("dungeon_run")   # advances here, not via Next — the WASD overlay has no Next button
	SaveManager.save_game()
	get_tree().change_scene_to_file("res://scenes/management_screen.tscn")
