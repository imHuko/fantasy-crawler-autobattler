extends Node2D

# -------------------------------------------------------
# Action Dungeon — top-down WASD, auto-attack, room-based
# -------------------------------------------------------

const ROOM_W = 640
const ROOM_H = 480
const WALL_T = 32
const MIN_SPAWN_DIST_FROM_HERO = 200.0
const DOOR_W = 64

const HERO_SPEED_BASE = 180.0
const HERO_HP_BASE = 100
const ATTACK_INTERVAL = 0.8

# Per-class playstyle in the action dungeon. Whichever troop is brought
# into the dungeon plays meaningfully differently rather than every run
# feeling like the same generic melee character. Melee classes (Knight/
# Rogue) get a short attack range that forces them to close distance —
# technically still an auto-fire range check rather than true melee
# collision, but tight enough to feel like melee in practice.
const CLASS_PROFILES = {
	"KNIGHT": { "hp_mult": 1.5,  "dmg_mult": 0.7, "interval_mult": 1.0, "range": 220.0, "self_heal": false },
	"ARCHER": { "hp_mult": 1.0,  "dmg_mult": 0.75,"interval_mult": 0.6, "range": 99999.0, "self_heal": false },
	"MAGE":   { "hp_mult": 0.85, "dmg_mult": 1.8, "interval_mult": 1.4, "range": 99999.0, "self_heal": false },
	"ROGUE":  { "hp_mult": 0.7,  "dmg_mult": 1.6, "interval_mult": 0.8, "range": 220.0, "self_heal": false },
	"HEALER": { "hp_mult": 0.8,  "dmg_mult": 0.5, "interval_mult": 1.0, "range": 99999.0, "self_heal": true },
}
const HEALER_SELF_HEAL_INTERVAL = 3.0   # seconds between passive self-heal ticks
const HEALER_SELF_HEAL_PCT = 0.08       # % of max HP healed per tick
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
var pending_room_gear: Array = []   # drops from the CURRENT room, not yet committed

var hero_hp: int = HERO_HP_BASE
var hero_max_hp: int = HERO_HP_BASE
var hero_speed: float = HERO_SPEED_BASE
var hero_attack: int = 12
var hero_armor: int = 0
var hero_crit_chance: float = 0.0
var hero_crit_damage: int = 0
var hero_attack_range: float = 99999.0
var hero_attack_interval: float = ATTACK_INTERVAL
var hero_self_heal: bool = false
var self_heal_timer: float = HEALER_SELF_HEAL_INTERVAL
var attack_timer: float = 0.0
var invincible_timer: float = 0.0

var hero_pos: Vector2 = Vector2(ROOM_W/2, ROOM_H/2)
var hero_vel: Vector2 = Vector2.ZERO

var enemies: Array = []        # {pos, hp, max_hp, speed, attack, shoot_t, is_boss, boss_p, boss_t, boss_a}
var hero_projs: Array = []     # {pos, dir}
var enemy_projs: Array = []    # {pos, dir, damage}

var room_node: Node2D = null
var hero_rect: UnitSprite = null
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
	var troop = _get_dungeon_troop()
	var eff = troop.get_effective_stats() if troop else {}
	var profile = CLASS_PROFILES.get(troop.get_type_name(), CLASS_PROFILES["KNIGHT"]) if troop else CLASS_PROFILES["KNIGHT"]

	hero_max_hp  = max(50,  int(eff.get("hp", HERO_HP_BASE) * profile["hp_mult"]))
	hero_speed   = max(100, HERO_SPEED_BASE + eff.get("speed", 0) * 8.0)
	hero_attack  = max(5,   int(eff.get("attack", 12) * profile["dmg_mult"]))
	hero_armor   = eff.get("armor", 0)
	hero_crit_chance = eff.get("crit_chance", 0.0)
	hero_crit_damage = eff.get("crit_damage", 0)
	hero_attack_range = profile["range"]
	hero_attack_interval = ATTACK_INTERVAL * profile["interval_mult"]
	hero_self_heal = profile["self_heal"]
	hero_hp = hero_max_hp

# Finds the troop the player selected to bring into this dungeon run,
# via PlayerInventory.dungeon_troop_id. Falls back to the Hero if nothing
# was explicitly selected (e.g. the tutorial dungeon path).
func _get_dungeon_troop() -> TroopData:
	if PlayerInventory.dungeon_troop_id != "":
		for troop in PlayerInventory.troop_roster:
			if troop.troop_id == PlayerInventory.dungeon_troop_id:
				return troop
	return PlayerInventory.get_hero()

# -------------------------------------------------------
# Room generation
# -------------------------------------------------------
func _generate_rooms() -> void:
	var count_range = {"Quick": [4, 6], "Standard": [6, 10], "Deep Delve": [10, 15]}
	var range_for_tier = count_range.get(PlayerInventory.dungeon_tier, [6, 10])
	var count = randi_range(range_for_tier[0], range_for_tier[1])
	var grid: Dictionary = {}
	var start = Vector2i(0, 0)
	grid[start] = 0
	rooms.append({"pos": start, "doors": {}, "cleared": false, "is_boss": false, "is_final_boss": false})

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
				var nr = {"pos": np, "doors": {}, "cleared": false, "is_boss": false, "is_final_boss": false}
				nr["doors"][on] = grid[cur]
				grid[np] = rooms.size()
				rooms.append(nr)
				frontier.append(np)
				break
		frontier.erase(cur)

	rooms[rooms.size()-1]["is_boss"] = true
	rooms[rooms.size()-1]["is_final_boss"] = true

	# Deep Delve: small chance for an additional mini-boss room partway through.
	# This room reuses all boss spawn/combat logic but is NOT the final room,
	# so clearing it doesn't end the run.
	if PlayerInventory.dungeon_tier == "Deep Delve" and rooms.size() > 3 and randf() < 0.15:
		var mid_idx = randi_range(2, rooms.size() - 2)
		rooms[mid_idx]["is_boss"] = true
		rooms[mid_idx]["is_final_boss"] = false

# -------------------------------------------------------
# Enter room
# -------------------------------------------------------
func _enter_room(idx: int, from_dir: String) -> void:
	current_room_idx = idx
	came_from_dir = from_dir
	game_over = false
	pending_room_gear.clear()

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
	hero_rect = UnitSprite.new()
	hero_rect.setup(UnitSprite.UnitType.HERO, C_HERO, 24.0)
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
	var tier_mult = {"Quick": 0.8, "Standard": 1.0, "Deep Delve": 1.4}.get(PlayerInventory.dungeon_tier, 1.0)
	var boss_hp_mult = {"Quick": 4.0, "Standard": 5.0, "Deep Delve": 6.0}.get(PlayerInventory.dungeon_tier, 5.0)

	for i in range(count):
		var is_boss = room["is_boss"]
		var sz = 56.0 if is_boss else 28.0
		var max_hp = int((8 + stage * 6) * (boss_hp_mult if is_boss else 1.0) * tier_mult)
		var spd = 55.0 + stage * 4.0

		var ex: float
		var ey: float
		var tries = 0
		# Reroll until far enough from the hero's entry position — prevents
		# enemies (especially bosses) spawning right on top of the player
		# the moment a room loads.
		while true:
			ex = randf_range(WALL_T + 80, ROOM_W - WALL_T - 80)
			ey = randf_range(WALL_T + 80, ROOM_H - WALL_T - 80)
			tries += 1
			if hero_pos.distance_to(Vector2(ex, ey)) >= MIN_SPAWN_DIST_FROM_HERO or tries >= 20:
				break
		var epos = Vector2(ex, ey)

		var erect = UnitSprite.new()
		erect.setup(UnitSprite.UnitType.ENEMY_BOSS if is_boss else UnitSprite.UnitType.ENEMY_BASIC,
			C_BOSS if is_boss else C_ENEMY, sz)
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
			"speed": spd, "attack": int((4 + stage * 2) * tier_mult),
			"shoot_t": randf_range(1.5, 3.0),
			"is_boss": is_boss, "is_final_boss": room.get("is_final_boss", false), "sz": sz,
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
	_self_heal_tick(delta)
	_update_visuals()

# Healer's passive sustain — periodically heals a % of max HP. This is
# Healer's actual strength in the dungeon despite being the weakest
# attacker by far: outlasting a fight rather than winning it quickly.
func _self_heal_tick(delta: float) -> void:
	if not hero_self_heal or hero_hp <= 0: return
	self_heal_timer -= delta
	if self_heal_timer <= 0:
		self_heal_timer = HEALER_SELF_HEAL_INTERVAL
		var healed = max(1, int(hero_max_hp * HEALER_SELF_HEAL_PCT))
		hero_hp = min(hero_hp + healed, hero_max_hp)
		_refresh_hud()

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

	# Melee classes (short hero_attack_range) simply can't fire until
	# something is actually close — this is what makes Knight/Rogue feel
	# like they need to close distance, even though it's still a range
	# check rather than true melee collision under the hood.
	if nearest and nearest_dist <= hero_attack_range:
		attack_timer = hero_attack_interval
		var dmg = hero_attack
		if randf() < hero_crit_chance:
			dmg = int(dmg * (1.0 + hero_crit_damage / 100.0))
		_fire(hero_pos, nearest["pos"], true, dmg, hero_rect)

func _fire(from: Vector2, toward: Vector2, is_hero: bool, dmg: int, attacker_sprite: UnitSprite = null) -> void:
	var dir = (toward - from).normalized()
	var proj = {"pos": Vector2(from.x, from.y),
				"dir": dir, "damage": dmg, "is_hero": is_hero}

	if attacker_sprite and is_instance_valid(attacker_sprite):
		attacker_sprite.face(dir)
		attacker_sprite.play_attack()

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
		var e_sprite = enemy_rects[i] if i < enemy_rects.size() else null
		if e["is_boss"]:
			_process_boss(e, delta, e_sprite)
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
					_fire(e["pos"], hero_pos, false, e["attack"], e_sprite)
				e["shoot_t"] = randf_range(1.8, 2.8)

			# Melee
			if invincible_timer <= 0 and e["pos"].distance_to(hero_pos) < e["sz"]/2 + 14:
				_take_damage(e["attack"])

func _process_boss(e: Dictionary, delta: float, e_sprite: UnitSprite = null) -> void:
	e["boss_t"] -= delta
	e["boss_a"] += delta * 120.0

	if e["boss_t"] <= 0:
		var pattern = e["boss_p"] % 3
		match pattern:
			0:  # Ring of 8
				for i in range(8):
					var angle = deg_to_rad(i * 45.0)
					_fire(e["pos"], e["pos"] + Vector2(cos(angle), sin(angle)) * 80, false, e["attack"], e_sprite)
				e["boss_t"] = 2.5
				e["boss_p"] += 1
			1:  # Spiral
				for i in range(3):
					var angle = deg_to_rad(e["boss_a"] + i * 120.0)
					_fire(e["pos"], e["pos"] + Vector2(cos(angle), sin(angle)) * 80, false, e["attack"], e_sprite)
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
					_fire(e["pos"], e["pos"] + rot * 80, false, e["attack"], e_sprite)
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

	# Gear drop — staged into pending_room_gear, not committed to the
	# permanent inventory until the room is actually cleared. This is what
	# makes retreat correctly forfeit loot from an in-progress room.
	var drop_chance = 1.0 if e["is_boss"] else 0.16
	if randf() < drop_chance:
		var diff = clamp(PlayerInventory.current_stage + (1 if e["is_boss"] else 0), 1, 10)
		if PlayerInventory.dungeon_tier == "Deep Delve":
			diff = clamp(diff + 1, 1, 10)
		var biomes = ["crypt","forest_ruins","dragon_lair"]
		var gear = GearGenerator.generate(biomes[randi() % biomes.size()], diff)
		pending_room_gear.append(gear)

	if enemies.is_empty():
		rooms[current_room_idx]["cleared"] = true
		_commit_pending_room_gear()
		_refresh_doors()
		_refresh_hud()
		if e.get("is_final_boss", e["is_boss"]):
			_on_run_complete()

# Moves all gear staged for the current room into the permanent inventory
# and the run's collected-gear tally. Called once a room is actually cleared.
func _commit_pending_room_gear() -> void:
	for gear in pending_room_gear:
		PlayerInventory.add_gear(gear)
		run_gear.append(gear)
	pending_room_gear.clear()

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
		_show_end_screen("lost")

# -------------------------------------------------------
# Visual updates each frame
# -------------------------------------------------------
func _update_visuals() -> void:
	if hero_rect and is_instance_valid(hero_rect):
		hero_rect.position = hero_pos - Vector2(12, 12)
		# Flash when invincible
		hero_rect.set_color(Color(1,1,1) if fmod(invincible_timer, 0.15) > 0.075 else C_HERO)

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

	var retreat_btn = Button.new()
	retreat_btn.text = "Retreat"
	retreat_btn.custom_minimum_size = Vector2(0, 32)
	retreat_btn.add_theme_font_size_override("font_size", 12)
	retreat_btn.add_theme_color_override("font_color", Color(0.9, 0.5, 0.3))
	retreat_btn.pressed.connect(_on_retreat_pressed)
	vbox.add_child(retreat_btn)

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
	_show_end_screen("won")

func _on_retreat_pressed() -> void:
	if game_over: return
	_show_retreat_confirm()

func _show_retreat_confirm() -> void:
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
	title.text = "Retreat?"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(0.9, 0.6, 0.3))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var msg = Label.new()
	var pending_count = pending_room_gear.size()
	if pending_count > 0:
		msg.text = "You'll keep loot from cleared rooms, but lose %d item(s) found in this room." % pending_count
	else:
		msg.text = "You'll keep all loot found so far. This room hasn't dropped anything yet."
	msg.add_theme_font_size_override("font_size", 13)
	msg.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	msg.autowrap_mode = TextServer.AUTOWRAP_WORD
	msg.custom_minimum_size = Vector2(280, 0)
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(msg)

	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	vbox.add_child(hbox)

	var cancel_btn = Button.new()
	cancel_btn.text = "Keep Fighting"
	cancel_btn.custom_minimum_size = Vector2(140, 40)
	cancel_btn.pressed.connect(func(): overlay.queue_free())
	hbox.add_child(cancel_btn)

	var confirm_btn = Button.new()
	confirm_btn.text = "Retreat"
	confirm_btn.custom_minimum_size = Vector2(140, 40)
	confirm_btn.add_theme_color_override("font_color", Color(0.9, 0.5, 0.3))
	confirm_btn.pressed.connect(func():
		overlay.queue_free()
		_do_retreat())
	hbox.add_child(confirm_btn)

func _do_retreat() -> void:
	game_over = true
	pending_room_gear.clear()   # forfeited, per the retreat loot rule
	_show_end_screen("retreated")

func _show_end_screen(outcome: String) -> void:
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
	var title_text = {"won": "RUN COMPLETE!", "lost": "DEFEATED", "retreated": "RETREATED"}.get(outcome, "RUN OVER")
	var title_color = {"won": Color(0.3,0.9,0.3), "lost": Color(0.9,0.2,0.2), "retreated": Color(0.9,0.6,0.3)}.get(outcome, Color.WHITE)
	title.text = title_text
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", title_color)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var info = Label.new()
	info.text = "Gear collected this run: %d item%s" % [run_gear.size(), "" if run_gear.size() == 1 else "s"]
	info.add_theme_color_override("font_color", Color(0.9, 0.75, 0.2))
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(info)

	if run_gear.size() > 0:
		var scroll = ScrollContainer.new()
		scroll.custom_minimum_size = Vector2(280, min(220, run_gear.size() * 26))
		vbox.add_child(scroll)

		var gear_list_vbox = VBoxContainer.new()
		gear_list_vbox.add_theme_constant_override("separation", 2)
		scroll.add_child(gear_list_vbox)

		for gear in run_gear:
			var row = Label.new()
			var quality_tag = (" " + gear.get_quality_name()) if gear.get_quality_name() != "" else ""
			row.text = "%s  [%s%s]" % [gear.item_name, gear.get_rarity_name(), quality_tag]
			row.add_theme_font_size_override("font_size", 12)
			row.add_theme_color_override("font_color", gear.get_display_color())
			row.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			gear_list_vbox.add_child(row)
	else:
		var none_lbl = Label.new()
		none_lbl.text = "No gear found this run."
		none_lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
		none_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(none_lbl)

	var btn = Button.new()
	var first_time = not PlayerInventory.map_generated
	btn.text = "Continue to World Map" if first_time else "Back to Management"
	btn.custom_minimum_size = Vector2(220, 44)
	btn.pressed.connect(func():
		var dest = "res://scenes/world_map.tscn" if first_time else "res://scenes/management_screen.tscn"
		get_tree().change_scene_to_file(dest))
	vbox.add_child(btn)
