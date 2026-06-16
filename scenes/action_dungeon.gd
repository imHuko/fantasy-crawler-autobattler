extends Node2D

# -------------------------------------------------------
# Action Dungeon — top-down WASD, auto-attack, room-based
# -------------------------------------------------------

const ROOM_W = 640
const ROOM_H = 480
const WALL_T = 32
const DOOR_W = 64

const HERO_SPEED_BASE = 180.0
const HERO_HP_BASE = 100
const ATTACK_INTERVAL = 0.8
const PROJECTILE_SPEED = 320.0
const PROJ_DAMAGE = 8

const C_FLOOR    = Color(0.18, 0.16, 0.22)
const C_WALL     = Color(0.30, 0.25, 0.35)
const C_DOOR_OFF = Color(0.55, 0.20, 0.20)
const C_DOOR_ON  = Color(0.20, 0.65, 0.30)
const C_HERO     = Color(0.30, 0.70, 1.00)
const C_ENEMY    = Color(0.85, 0.25, 0.25)
const C_BOSS     = Color(1.00, 0.10, 0.10)
const C_PROJ_H   = Color(0.50, 0.90, 1.00)
const C_PROJ_E   = Color(1.00, 0.55, 0.10)

const DIRS      = [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]
const DIR_NAMES = {Vector2i(1,0):"east", Vector2i(-1,0):"west", Vector2i(0,1):"south", Vector2i(0,-1):"north"}
const OPPOSITE  = {"east":"west","west":"east","north":"south","south":"north"}

# Door center positions (where the opening is)
const DOOR_CENTERS = {
	"north": Vector2(ROOM_W/2,        WALL_T/2),
	"south": Vector2(ROOM_W/2,        ROOM_H - WALL_T/2),
	"east":  Vector2(ROOM_W - WALL_T/2, ROOM_H/2),
	"west":  Vector2(WALL_T/2,        ROOM_H/2),
}

# Entry positions when coming through a door from outside
const ENTRY_POS = {
	"north": Vector2(ROOM_W/2, WALL_T + 40),
	"south": Vector2(ROOM_W/2, ROOM_H - WALL_T - 40),
	"east":  Vector2(ROOM_W - WALL_T - 40, ROOM_H/2),
	"west":  Vector2(WALL_T + 40, ROOM_H/2),
}

var rooms: Array = []
var current_room_idx: int = 0
var came_from_dir: String = ""
var run_gear: Array = []

var hero_hp: int = HERO_HP_BASE
var hero_max_hp: int = HERO_HP_BASE
var hero_speed: float = HERO_SPEED_BASE
var hero_attack: int = 12
var hero_armor: int = 0
var hero_crit_chance: float = 0.0
var hero_crit_damage: int = 0
var attack_timer: float = 0.0
var invincible_timer: float = 0.0

var hero_pos: Vector2 = Vector2(ROOM_W/2, ROOM_H/2)
var hero_vel: Vector2 = Vector2.ZERO

var enemies: Array = []        # {pos, hp, max_hp, speed, attack, shoot_t, is_boss, boss_p, boss_t, boss_a}
var hero_projs: Array = []     # {pos, dir}
var enemy_projs: Array = []    # {pos, dir, damage}

var room_node: Node2D = null
var hero_rect: ColorRect = null
var hud_hp: Label = null
var hud_room: Label = null
var hud_gear: Label = null
var minimap: Control = null
var door_rects: Dictionary = {}   # dir -> ColorRect
var enemy_rects: Array = []
var hero_proj_rects: Array = []
var enemy_proj_rects: Array = []

var game_over: bool = false

func _ready() -> void:
	_load_hero_stats()
	_generate_rooms()
	_build_hud()
	_enter_room(0, "")

func _load_hero_stats() -> void:
	PlayerInventory.ensure_hero_exists()
	var eff = PlayerInventory.hero.get_effective_stats()
	hero_max_hp  = max(50,  eff.get("hp",      HERO_HP_BASE))
	hero_speed   = max(100, HERO_SPEED_BASE + eff.get("speed", 0) * 8.0)
	hero_attack  = max(5,   eff.get("attack",  12))
	hero_armor   = eff.get("armor", 0)
	hero_crit_chance = eff.get("crit_chance", 0.0)
	hero_crit_damage = eff.get("crit_damage", 0)
	hero_hp = hero_max_hp

# -------------------------------------------------------
# Room generation
# -------------------------------------------------------
func _generate_rooms() -> void:
	var count = randi_range(6, 10)
	var grid: Dictionary = {}
	var start = Vector2i(0, 0)
	grid[start] = 0
	rooms.append({"pos": start, "doors": {}, "cleared": false, "is_boss": false})

	var frontier = [start]
	while rooms.size() < count and frontier.size() > 0:
		var cur = frontier[randi() % frontier.size()]
		var shuffled = DIRS.duplicate()
		shuffled.shuffle()
		for d in shuffled:
			var np = cur + d
			if not grid.has(np) and rooms.size() < count:
				var dn = DIR_NAMES[d]
				var on = OPPOSITE[dn]
				rooms[grid[cur]]["doors"][dn] = rooms.size()
				var nr = {"pos": np, "doors": {}, "cleared": false, "is_boss": false}
				nr["doors"][on] = grid[cur]
				grid[np] = rooms.size()
				rooms.append(nr)
				frontier.append(np)
				break
		frontier.erase(cur)

	rooms[rooms.size()-1]["is_boss"] = true

# -------------------------------------------------------
# Enter room
# -------------------------------------------------------
func _enter_room(idx: int, from_dir: String) -> void:
	current_room_idx = idx
	came_from_dir = from_dir
	game_over = false

	# Clear old visuals
	if room_node:
		room_node.queue_free()
	room_node = Node2D.new()
	add_child(room_node)
	move_child(room_node, 0)

	enemies.clear()
	enemy_rects.clear()
	hero_projs.clear()
	enemy_projs.clear()
	hero_proj_rects.clear()
	enemy_proj_rects.clear()
	door_rects.clear()

	# Place hero
	if from_dir == "":
		hero_pos = Vector2(ROOM_W/2, ROOM_H/2)
	else:
		hero_pos = ENTRY_POS[OPPOSITE[from_dir]]

	_build_room_visuals()
	_build_hero_rect()

	var room = rooms[idx]
	if not room["cleared"]:
		_spawn_enemies(room)

	_refresh_doors()
	_refresh_hud()
	_refresh_minimap()

# -------------------------------------------------------
# Visuals
# -------------------------------------------------------
func _build_room_visuals() -> void:
	var room = rooms[current_room_idx]

	# Floor
	_add_rect(room_node, Vector2(WALL_T, WALL_T),
		Vector2(ROOM_W - WALL_T*2, ROOM_H - WALL_T*2), C_FLOOR)

	# Walls with door gaps
	# Top wall
	var has_n = room["doors"].has("north")
	if has_n:
		var gap_x = ROOM_W/2 - DOOR_W/2
		_add_rect(room_node, Vector2(0,0),          Vector2(gap_x, WALL_T), C_WALL)
		_add_rect(room_node, Vector2(gap_x+DOOR_W,0), Vector2(ROOM_W-(gap_x+DOOR_W), WALL_T), C_WALL)
	else:
		_add_rect(room_node, Vector2(0,0), Vector2(ROOM_W, WALL_T), C_WALL)

	# Bottom wall
	var has_s = room["doors"].has("south")
	if has_s:
		var gap_x = ROOM_W/2 - DOOR_W/2
		_add_rect(room_node, Vector2(0, ROOM_H-WALL_T), Vector2(gap_x, WALL_T), C_WALL)
		_add_rect(room_node, Vector2(gap_x+DOOR_W, ROOM_H-WALL_T), Vector2(ROOM_W-(gap_x+DOOR_W), WALL_T), C_WALL)
	else:
		_add_rect(room_node, Vector2(0, ROOM_H-WALL_T), Vector2(ROOM_W, WALL_T), C_WALL)

	# Left wall
	var has_w = room["doors"].has("west")
	if has_w:
		var gap_y = ROOM_H/2 - DOOR_W/2
		_add_rect(room_node, Vector2(0,0),           Vector2(WALL_T, gap_y), C_WALL)
		_add_rect(room_node, Vector2(0, gap_y+DOOR_W), Vector2(WALL_T, ROOM_H-(gap_y+DOOR_W)), C_WALL)
	else:
		_add_rect(room_node, Vector2(0,0), Vector2(WALL_T, ROOM_H), C_WALL)

	# Right wall
	var has_e = room["doors"].has("east")
	if has_e:
		var gap_y = ROOM_H/2 - DOOR_W/2
		_add_rect(room_node, Vector2(ROOM_W-WALL_T, 0),          Vector2(WALL_T, gap_y), C_WALL)
		_add_rect(room_node, Vector2(ROOM_W-WALL_T, gap_y+DOOR_W), Vector2(WALL_T, ROOM_H-(gap_y+DOOR_W)), C_WALL)
	else:
		_add_rect(room_node, Vector2(ROOM_W-WALL_T, 0), Vector2(WALL_T, ROOM_H), C_WALL)

	# Door indicator overlays
	for dir in room["doors"]:
		var dc = DOOR_CENTERS[dir]
		var dr = ColorRect.new()
		dr.size = Vector2(DOOR_W, WALL_T) if dir in ["north","south"] else Vector2(WALL_T, DOOR_W)
		dr.position = dc - dr.size/2
		dr.color = C_DOOR_ON
		room_node.add_child(dr)
		door_rects[dir] = dr

func _build_hero_rect() -> void:
	if hero_rect:
		hero_rect.queue_free()
	hero_rect = ColorRect.new()
	hero_rect.size = Vector2(24, 24)
	hero_rect.color = C_HERO
	room_node.add_child(hero_rect)
	hero_rect.position = hero_pos - Vector2(12, 12)

func _add_rect(parent: Node, pos: Vector2, sz: Vector2, col: Color) -> ColorRect:
	var r = ColorRect.new()
	r.position = pos
	r.size = sz
	r.color = col
	parent.add_child(r)
	return r

# -------------------------------------------------------
# Enemies
# -------------------------------------------------------
func _spawn_enemies(room: Dictionary) -> void:
	var count = 1 if room["is_boss"] else randi_range(2, 4)
	var stage = PlayerInventory.current_stage

	for i in range(count):
		var is_boss = room["is_boss"]
		var sz = 56.0 if is_boss else 28.0
		var max_hp = (8 + stage * 6) * (5 if is_boss else 1)
		var spd = 55.0 + stage * 4.0

		var ex = randf_range(WALL_T + 80, ROOM_W - WALL_T - 80)
		var ey = randf_range(WALL_T + 80, ROOM_H - WALL_T - 80)
		var epos = Vector2(ex, ey)

		var erect = ColorRect.new()
		erect.size = Vector2(sz, sz)
		erect.color = C_BOSS if is_boss else C_ENEMY
		erect.position = epos - Vector2(sz/2, sz/2)
		room_node.add_child(erect)

		var hp_bar_bg = null
		var hp_bar = null
		if is_boss:
			hp_bar_bg = ColorRect.new()
			hp_bar_bg.size = Vector2(80, 8)
			hp_bar_bg.color = Color(0.3, 0.1, 0.1)
			hp_bar_bg.position = epos - Vector2(40, 44)
			room_node.add_child(hp_bar_bg)

			hp_bar = ColorRect.new()
			hp_bar.size = Vector2(80, 8)
			hp_bar.color = Color(0.9, 0.2, 0.2)
			hp_bar.position = epos - Vector2(40, 44)
			room_node.add_child(hp_bar)

		var e = {
			"pos": epos, "hp": max_hp, "max_hp": max_hp,
			"speed": spd, "attack": 4 + stage * 2,
			"shoot_t": randf_range(1.5, 3.0),
			"is_boss": is_boss, "sz": sz,
			"boss_p": 0, "boss_t": 2.0, "boss_a": 0.0,
			"hp_bar": hp_bar, "hp_bar_bg": hp_bar_bg,
		}
		enemies.append(e)
		enemy_rects.append(erect)

# -------------------------------------------------------
# Process loop
# -------------------------------------------------------
func _process(delta: float) -> void:
	if game_over: return

	_move_hero(delta)
	_attack_tick(delta)
	_move_projectiles(delta)
	_process_enemies(delta)
	_check_door_transition()
	_update_visuals()

func _move_hero(delta: float) -> void:
	var dir = Vector2.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):    dir.y -= 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):  dir.y += 1
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):  dir.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): dir.x += 1
	if dir.length() > 0: dir = dir.normalized()

	hero_pos += dir * hero_speed * delta

	# Clamp inside room (walls are solid except door gaps)
	var room = rooms[current_room_idx]
	var min_x = WALL_T + 12
	var max_x = ROOM_W - WALL_T - 12
	var min_y = WALL_T + 12
	var max_y = ROOM_H - WALL_T - 12

	# Allow passing through door gaps
	if room["doors"].has("north") and abs(hero_pos.x - ROOM_W/2) < DOOR_W/2:
		min_y = 0
	if room["doors"].has("south") and abs(hero_pos.x - ROOM_W/2) < DOOR_W/2:
		max_y = ROOM_H
	if room["doors"].has("west") and abs(hero_pos.y - ROOM_H/2) < DOOR_W/2:
		min_x = 0
	if room["doors"].has("east") and abs(hero_pos.y - ROOM_H/2) < DOOR_W/2:
		max_x = ROOM_W

	hero_pos.x = clamp(hero_pos.x, min_x, max_x)
	hero_pos.y = clamp(hero_pos.y, min_y, max_y)

	# Invincibility frames
	if invincible_timer > 0:
		invincible_timer -= get_process_delta_time()

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
		var dmg = hero_attack
		if randf() < hero_crit_chance:
			dmg = int(dmg * (1.0 + hero_crit_damage / 100.0))
		_fire(hero_pos, nearest["pos"], true, dmg)

func _fire(from: Vector2, toward: Vector2, is_hero: bool, dmg: int) -> void:
	var dir = (toward - from).normalized()
	var proj = {"pos": Vector2(from.x, from.y),
				"dir": dir, "damage": dmg, "is_hero": is_hero}

	var prect = ColorRect.new()
	prect.size = Vector2(10, 10)
	prect.color = C_PROJ_H if is_hero else C_PROJ_E
	prect.position = from - Vector2(5, 5)
	room_node.add_child(prect)

	if is_hero:
		hero_projs.append(proj)
		hero_proj_rects.append(prect)
	else:
		enemy_projs.append(proj)
		enemy_proj_rects.append(prect)

func _move_projectiles(delta: float) -> void:
	# Hero projectiles — build new lists each frame
	var new_hprojs = []
	var new_hprects = []
	for i in range(hero_projs.size()):
		var p = hero_projs[i]
		var pr = hero_proj_rects[i]
		p["pos"] += p["dir"] * PROJECTILE_SPEED * delta

		var oob = (p["pos"].x < WALL_T or p["pos"].x > ROOM_W - WALL_T
				or p["pos"].y < WALL_T or p["pos"].y > ROOM_H - WALL_T)
		if oob:
			if is_instance_valid(pr): pr.queue_free()
			continue

		var hit = false
		for ei in range(enemies.size()):
			if p["pos"].distance_to(enemies[ei]["pos"]) < enemies[ei]["sz"] / 2 + 5:
				enemies[ei]["hp"] -= p["damage"]
				_update_boss_bar(enemies[ei])
				if enemies[ei]["hp"] <= 0:
					_kill_enemy(ei)
				if is_instance_valid(pr): pr.queue_free()
				hit = true
				break
		if not hit:
			new_hprojs.append(p)
			new_hprects.append(pr)

	hero_projs = new_hprojs
	hero_proj_rects = new_hprects

	# Enemy projectiles
	var new_eprojs = []
	var new_eprects = []
	for i in range(enemy_projs.size()):
		var p = enemy_projs[i]
		var pr = enemy_proj_rects[i]
		p["pos"] += p["dir"] * (PROJECTILE_SPEED * 0.65) * delta

		var oob = (p["pos"].x < WALL_T or p["pos"].x > ROOM_W - WALL_T
				or p["pos"].y < WALL_T or p["pos"].y > ROOM_H - WALL_T)
		if oob:
			if is_instance_valid(pr): pr.queue_free()
			continue

		if invincible_timer <= 0 and p["pos"].distance_to(hero_pos) < 16:
			_take_damage(p["damage"])
			if is_instance_valid(pr): pr.queue_free()
		else:
			new_eprojs.append(p)
			new_eprects.append(pr)

	enemy_projs = new_eprojs
	enemy_proj_rects = new_eprects

func _process_enemies(delta: float) -> void:
	for i in range(enemies.size()):
		var e = enemies[i]
		if e["is_boss"]:
			_process_boss(e, delta)
		else:
			# Move toward hero
			var move_dir = (hero_pos - e["pos"]).normalized()
			e["pos"] += move_dir * e["speed"] * delta

			# Clamp enemy inside room
			e["pos"].x = clamp(e["pos"].x, WALL_T + e["sz"]/2, ROOM_W - WALL_T - e["sz"]/2)
			e["pos"].y = clamp(e["pos"].y, WALL_T + e["sz"]/2, ROOM_H - WALL_T - e["sz"]/2)

			# Shoot at player
			e["shoot_t"] -= delta
			if e["shoot_t"] <= 0:
				if hero_pos.distance_to(e["pos"]) < 300:
					_fire(e["pos"], hero_pos, false, e["attack"])
				e["shoot_t"] = randf_range(1.8, 2.8)

			# Melee
			if invincible_timer <= 0 and e["pos"].distance_to(hero_pos) < e["sz"]/2 + 14:
				_take_damage(e["attack"])

func _process_boss(e: Dictionary, delta: float) -> void:
	e["boss_t"] -= delta
	e["boss_a"] += delta * 120.0

	if e["boss_t"] <= 0:
		var pattern = e["boss_p"] % 3
		match pattern:
			0:  # Ring of 8
				for i in range(8):
					var angle = deg_to_rad(i * 45.0)
					_fire(e["pos"], e["pos"] + Vector2(cos(angle), sin(angle)) * 80, false, e["attack"])
				e["boss_t"] = 2.5
				e["boss_p"] += 1
			1:  # Spiral
				for i in range(3):
					var angle = deg_to_rad(e["boss_a"] + i * 120.0)
					_fire(e["pos"], e["pos"] + Vector2(cos(angle), sin(angle)) * 80, false, e["attack"])
				e["boss_t"] = 0.15
				if e["boss_a"] > 360.0:
					e["boss_a"] = 0.0
					e["boss_p"] += 1
					e["boss_t"] = 2.0
			2:  # Aimed burst of 5
				for i in range(5):
					var spread = deg_to_rad((i - 2) * 18.0)
					var base_dir = (hero_pos - e["pos"]).normalized()
					var rot = base_dir.rotated(spread)
					_fire(e["pos"], e["pos"] + rot * 80, false, e["attack"])
				e["boss_t"] = 2.0
				e["boss_p"] += 1

func _update_boss_bar(e: Dictionary) -> void:
	if e["hp_bar"] == null or not is_instance_valid(e["hp_bar"]): return
	var pct = float(e["hp"]) / float(e["max_hp"])
	e["hp_bar"].size.x = 80.0 * pct

func _kill_enemy(idx: int) -> void:
	var e = enemies[idx]
	var er = enemy_rects[idx]
	if is_instance_valid(er): er.queue_free()

	# Also remove hp bars
	if e["hp_bar"] != null and is_instance_valid(e["hp_bar"]):
		e["hp_bar"].queue_free()
	if e["hp_bar_bg"] != null and is_instance_valid(e["hp_bar_bg"]):
		e["hp_bar_bg"].queue_free()

	enemies.remove_at(idx)
	enemy_rects.remove_at(idx)

	# Gear drop
	var drop_chance = 1.0 if e["is_boss"] else 0.35
	if randf() < drop_chance:
		var diff = clamp(PlayerInventory.current_stage + (2 if e["is_boss"] else 0), 1, 10)
		var biomes = ["crypt","forest_ruins","dragon_lair"]
		var gear = GearGenerator.generate(biomes[randi() % biomes.size()], diff)
		PlayerInventory.add_gear(gear)
		run_gear.append(gear)

	if enemies.is_empty():
		rooms[current_room_idx]["cleared"] = true
		_refresh_doors()
		_refresh_hud()
		if e["is_boss"]:
			_on_run_complete()

func _check_door_transition() -> void:
	if not rooms[current_room_idx]["cleared"]: return
	var room = rooms[current_room_idx]

	for dir in room["doors"]:
		var dc = DOOR_CENTERS[dir]
		if hero_pos.distance_to(dc) < 24:
			var next_idx = room["doors"][dir]
			_enter_room(next_idx, dir)
			return

func _take_damage(amount: int) -> void:
	if invincible_timer > 0: return
	var reduced = max(1, amount - int(hero_armor * 0.5))
	hero_hp -= reduced
	hero_hp = max(0, hero_hp)
	invincible_timer = 0.6
	_refresh_hud()
	if hero_hp <= 0:
		game_over = true
		_show_end_screen(false)

# -------------------------------------------------------
# Visual updates each frame
# -------------------------------------------------------
func _update_visuals() -> void:
	if hero_rect and is_instance_valid(hero_rect):
		hero_rect.position = hero_pos - Vector2(12, 12)
		# Flash when invincible
		hero_rect.color = Color(1,1,1) if fmod(invincible_timer, 0.15) > 0.075 else C_HERO

	for i in range(min(enemies.size(), enemy_rects.size())):
		var e = enemies[i]
		var er = enemy_rects[i]
		if is_instance_valid(er):
			er.position = e["pos"] - Vector2(e["sz"]/2, e["sz"]/2)
		if e["hp_bar"] != null and is_instance_valid(e["hp_bar"]):
			e["hp_bar"].position = e["pos"] - Vector2(40, 44)
		if e["hp_bar_bg"] != null and is_instance_valid(e["hp_bar_bg"]):
			e["hp_bar_bg"].position = e["pos"] - Vector2(40, 44)

	for i in range(min(hero_projs.size(), hero_proj_rects.size())):
		var pr = hero_proj_rects[i]
		if is_instance_valid(pr):
			pr.position = hero_projs[i]["pos"] - Vector2(5,5)

	for i in range(min(enemy_projs.size(), enemy_proj_rects.size())):
		var pr = enemy_proj_rects[i]
		if is_instance_valid(pr):
			pr.position = enemy_projs[i]["pos"] - Vector2(5,5)

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

	hud_gear = Label.new()
	hud_gear.add_theme_font_size_override("font_size", 11)
	hud_gear.add_theme_color_override("font_color", Color(0.9, 0.75, 0.2))
	vbox.add_child(hud_gear)

	var controls = Label.new()
	controls.text = "WASD to move"
	controls.add_theme_font_size_override("font_size", 10)
	controls.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	vbox.add_child(controls)

	minimap = Control.new()
	minimap.custom_minimum_size = Vector2(150, 150)
	minimap.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	minimap.position = Vector2(-158, 8)
	hud.add_child(minimap)

	_refresh_hud()

func _refresh_hud() -> void:
	if hud_hp:
		hud_hp.text = "HP: %d / %d" % [hero_hp, hero_max_hp]
		var col = Color(0.9,0.2,0.2) if hero_hp < hero_max_hp * 0.3 else (
			Color(0.9,0.7,0.2) if hero_hp < hero_max_hp * 0.6 else Color(0.3,0.9,0.3))
		hud_hp.add_theme_color_override("font_color", col)
	if hud_room:
		var room = rooms[current_room_idx]
		var rtype = "BOSS" if room["is_boss"] else ("Cleared" if room["cleared"] else "%d enemies" % enemies.size())
		hud_room.text = "Room %d/%d  [%s]" % [current_room_idx+1, rooms.size(), rtype]
	if hud_gear:
		hud_gear.text = "Gear found: %d" % run_gear.size()

func _refresh_doors() -> void:
	var cleared = rooms[current_room_idx]["cleared"]
	for dir in door_rects:
		if is_instance_valid(door_rects[dir]):
			door_rects[dir].color = C_DOOR_ON if cleared else C_DOOR_OFF

func _refresh_minimap() -> void:
	if minimap == null: return
	for c in minimap.get_children(): c.queue_free()
	var sc = 14
	var off = Vector2(75, 75)
	for i in range(rooms.size()):
		var r = rooms[i]
		var rp = Vector2(r["pos"].x, r["pos"].y) * (sc + 2) + off
		var rect = ColorRect.new()
		rect.size = Vector2(sc, sc)
		rect.position = rp - Vector2(sc/2, sc/2)
		if i == current_room_idx:
			rect.color = Color(0.3, 0.7, 1.0)
		elif r["is_boss"]:
			rect.color = Color(0.9, 0.2, 0.2)
		elif r["cleared"]:
			rect.color = Color(0.3, 0.6, 0.3)
		else:
			rect.color = Color(0.5, 0.5, 0.5)
		minimap.add_child(rect)

# -------------------------------------------------------
# End states
# -------------------------------------------------------
func _on_run_complete() -> void:
	PlayerInventory.current_stage += 1
	if PlayerInventory.current_stage in [3, 5, 8]:
		PlayerInventory.unlock_troop_slot()
	_show_end_screen(true)

func _show_end_screen(won: bool) -> void:
	var overlay = CanvasLayer.new()
	add_child(overlay)

	var bg = ColorRect.new()
	bg.color = Color(0, 0, 0, 0.7)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(bg)

	var panel = PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	overlay.add_child(panel)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	panel.add_child(vbox)

	var title = Label.new()
	title.text = "RUN COMPLETE!" if won else "DEFEATED"
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(0.3,0.9,0.3) if won else Color(0.9,0.2,0.2))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var info = Label.new()
	info.text = "Gear collected this run: %d items" % run_gear.size()
	info.add_theme_color_override("font_color", Color(0.9, 0.75, 0.2))
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(info)

	var btn = Button.new()
	var first_time = not PlayerInventory.map_generated
	btn.text = "Continue to World Map" if first_time else "Back to Management"
	btn.custom_minimum_size = Vector2(220, 44)
	btn.pressed.connect(func():
		var dest = "res://scenes/world_map.tscn" if first_time else "res://scenes/management_screen.tscn"
		get_tree().change_scene_to_file(dest))
	vbox.add_child(btn)
