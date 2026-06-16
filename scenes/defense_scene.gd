extends Node2D

# -------------------------------------------------------
# Defense Scene — real-time auto-battler wave defense
# Place troops on the battlefield, they fight automatically
# Enemies walk from right to left toward your base
# -------------------------------------------------------

const FIELD_W = 800
const FIELD_H = 500
const BASE_X  = 60
const SPAWN_X = FIELD_W - 20

const C_BG       = Color(0.10, 0.12, 0.08)
const C_BASE     = Color(0.20, 0.40, 0.80)
const C_GROUND   = Color(0.15, 0.18, 0.12)
const C_TROOP_K  = Color(0.30, 0.60, 1.00)   # Knight - blue
const C_TROOP_A  = Color(0.20, 0.80, 0.30)   # Archer - green
const C_TROOP_M  = Color(0.80, 0.30, 0.90)   # Mage - purple
const C_TROOP_H  = Color(1.00, 0.80, 0.20)   # Healer - gold
const C_TROOP_R  = Color(0.85, 0.15, 0.35)   # Rogue - crimson
const C_ENEMY    = Color(0.85, 0.25, 0.20)
const C_PROJ_T   = Color(0.60, 0.90, 1.00)
const C_PROJ_E   = Color(1.00, 0.50, 0.10)
const C_HEAL     = Color(0.40, 1.00, 0.40)

const TROOP_COLORS = {
	"KNIGHT": C_TROOP_K, "ARCHER": C_TROOP_A,
	"MAGE":   C_TROOP_M, "HEALER": C_TROOP_H,
	"ROGUE":  C_TROOP_R,
}

const WAVE_INTERVAL   = 8.0    # seconds between waves
const PLACE_COOLDOWN  = 0.5    # prevent double-placing
const KNIGHT_AGGRO_BONUS = 60.0

var total_waves: int = 5
var current_wave: int = 0
var wave_timer: float = 3.0    # countdown to first wave
var wave_active: bool = false
var game_over: bool = false
var base_hp: int = 20
var base_max_hp: int = 20

# Zone context — set by world map before launching this scene
var battle_zone_id: int = -1
var is_conquering: bool = false
var attack_force_mult: float = 1.0
var battle_title: String = "Defend the Base"

# Troops placed on field: {data:TroopData, pos, hp, max_hp, attack_t, heal_t, rect, type_name}
var placed_troops: Array = []
# Enemies on field: {pos, hp, max_hp, attack, speed, rect, hp_bar}
var enemies: Array = []
# Projectiles: {pos, dir, damage, speed, is_troop, rect}
var projectiles: Array = []

# Roster slots UI
var roster_slots: Array = []    # {troop_data, btn, placed}
var selected_roster_idx: int = -1
var place_cooldown: float = 0.0

# UI nodes
var field_node: Node2D
var hud_wave: Label
var hud_base_hp: Label
var hud_timer: Label
var hud_status: Label
var base_rect: ColorRect
var base_hp_bar: ColorRect

func _ready() -> void:
	_load_battle_context()
	_build_ui()
	_build_field()
	_build_roster_ui()
	_refresh_hud()

func _load_battle_context() -> void:
	battle_zone_id = PlayerInventory.current_battle_zone
	is_conquering = PlayerInventory.conquering_zone
	attack_force_mult = PlayerInventory.current_attack_force

	if is_conquering:
		battle_title = "Conquer Zone"
		total_waves = 3   # conquering is shorter than full defense
	else:
		battle_title = "Defend the Base"
		total_waves = 5

	# Scale base HP and wave difficulty by force multiplier
	base_max_hp = int(20 * max(0.5, attack_force_mult))
	base_hp = base_max_hp

# -------------------------------------------------------
# Build UI
# -------------------------------------------------------
func _build_ui() -> void:
	var bg = ColorRect.new()
	bg.color = Color(0.06, 0.06, 0.08)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var hud = CanvasLayer.new()
	add_child(hud)

	# Top bar
	var top_bar = PanelContainer.new()
	top_bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top_bar.size.y = 48
	hud.add_child(top_bar)

	var top_hbox = HBoxContainer.new()
	top_hbox.add_theme_constant_override("separation", 20)
	top_bar.add_child(top_hbox)

	hud_wave = Label.new()
	hud_wave.add_theme_font_size_override("font_size", 15)
	hud_wave.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
	top_hbox.add_child(hud_wave)

	hud_timer = Label.new()
	hud_timer.add_theme_font_size_override("font_size", 15)
	hud_timer.add_theme_color_override("font_color", Color(0.7, 0.9, 0.7))
	top_hbox.add_child(hud_timer)

	hud_base_hp = Label.new()
	hud_base_hp.add_theme_font_size_override("font_size", 15)
	hud_base_hp.add_theme_color_override("font_color", Color(0.4, 0.7, 1.0))
	top_hbox.add_child(hud_base_hp)

	hud_status = Label.new()
	hud_status.add_theme_font_size_override("font_size", 13)
	hud_status.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	hud_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_hbox.add_child(hud_status)

	var back_btn = Button.new()
	back_btn.text = "Retreat"
	back_btn.pressed.connect(_on_retreat)
	top_hbox.add_child(back_btn)

	# Bottom roster panel
	var bottom = PanelContainer.new()
	bottom.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.size.y = 110
	bottom.position.y = -110
	hud.add_child(bottom)

	var roster_vbox = VBoxContainer.new()
	bottom.add_child(roster_vbox)

	var roster_label = Label.new()
	roster_label.text = "TROOPS  (click to select, then click battlefield to place)"
	roster_label.add_theme_font_size_override("font_size", 11)
	roster_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	roster_vbox.add_child(roster_label)

	var roster_hbox = HBoxContainer.new()
	roster_hbox.add_theme_constant_override("separation", 6)
	roster_vbox.add_child(roster_hbox)

	# Build a slot button for each troop available to this battle
	var available_troops = _get_battle_roster()
	for i in range(available_troops.size()):
		var troop: TroopData = available_troops[i]
		var eff = troop.get_effective_stats()
		var col = TROOP_COLORS.get(troop.get_type_name(), Color.WHITE)

		var btn = Button.new()
		btn.custom_minimum_size = Vector2(130, 72)
		btn.text = "%s\n[%s]\nHP:%d ATK:%d\nDEF:%d SPD:%d" % [
			troop.troop_name, troop.get_type_name(),
			eff.get("hp",0), eff.get("attack",0),
			eff.get("defense",0), eff.get("speed",0)
		]
		btn.add_theme_color_override("font_color", col)
		btn.add_theme_font_size_override("font_size", 11)
		btn.pressed.connect(_on_roster_selected.bind(i))
		roster_hbox.add_child(btn)
		roster_slots.append({"troop": troop, "btn": btn, "placed": false})

	if available_troops.is_empty():
		var warn = Label.new()
		warn.text = "No troops stationed here! You'll have to fight with whatever you brought \\u2014 nothing."
		warn.add_theme_color_override("font_color", Color(0.9, 0.3, 0.3))
		roster_hbox.add_child(warn)

# Returns the troops eligible for this battle.
# If a zone is set, only troops stationed at that zone (by name) can be placed.
# Falls back to the full roster for battles with no zone context (e.g. quick dungeon test).
func _get_battle_roster() -> Array:
	if battle_zone_id < 0:
		return PlayerInventory.troop_roster.duplicate()

	var zone_troop_names = PlayerInventory.get_zone_troop_names(battle_zone_id)
	if zone_troop_names.is_empty():
		return []

	var result = []
	for troop in PlayerInventory.troop_roster:
		if troop.troop_name in zone_troop_names:
			result.append(troop)
	return result

func _build_field() -> void:
	field_node = Node2D.new()
	field_node.position = Vector2(0, 52)   # below top HUD bar
	add_child(field_node)

	# Ground
	var ground = ColorRect.new()
	ground.color = C_GROUND
	ground.position = Vector2(0, 0)
	ground.size = Vector2(FIELD_W, FIELD_H - 110)
	field_node.add_child(ground)

	# Base
	base_rect = ColorRect.new()
	base_rect.color = C_BASE
	base_rect.size = Vector2(40, FIELD_H - 110)
	base_rect.position = Vector2(BASE_X - 20, 0)
	field_node.add_child(base_rect)

	var base_label = Label.new()
	base_label.text = "BASE"
	base_label.add_theme_font_size_override("font_size", 11)
	base_label.add_theme_color_override("font_color", Color.WHITE)
	base_label.position = Vector2(BASE_X - 18, 10)
	field_node.add_child(base_label)

	# Base HP bar bg
	var bar_bg = ColorRect.new()
	bar_bg.color = Color(0.3, 0.1, 0.1)
	bar_bg.size = Vector2(40, 10)
	bar_bg.position = Vector2(BASE_X - 20, FIELD_H - 120)
	field_node.add_child(bar_bg)

	# Base HP bar
	base_hp_bar = ColorRect.new()
	base_hp_bar.color = Color(0.3, 0.6, 1.0)
	base_hp_bar.size = Vector2(40, 10)
	base_hp_bar.position = Vector2(BASE_X - 20, FIELD_H - 120)
	field_node.add_child(base_hp_bar)

	# Click to place troops
	var click_area = ColorRect.new()
	click_area.color = Color(0, 0, 0, 0)
	click_area.size = Vector2(FIELD_W, FIELD_H - 110)
	click_area.position = Vector2(0, 0)
	click_area.mouse_filter = Control.MOUSE_FILTER_STOP
	field_node.add_child(click_area)

func _build_roster_ui() -> void:
	pass  # already built in _build_ui

func _input(event: InputEvent) -> void:
	if game_over: return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if selected_roster_idx >= 0 and place_cooldown <= 0:
			var click_pos = event.position - field_node.position
			if click_pos.x > BASE_X + 30 and click_pos.x < FIELD_W - 60 \
			and click_pos.y > 10 and click_pos.y < FIELD_H - 120:
				_place_troop(selected_roster_idx, click_pos)

# -------------------------------------------------------
# Troop placement
# -------------------------------------------------------
func _on_roster_selected(idx: int) -> void:
	if roster_slots[idx]["placed"]:
		_set_status("That troop is already on the field!")
		return
	selected_roster_idx = idx
	for i in range(roster_slots.size()):
		var col = TROOP_COLORS.get(roster_slots[i]["troop"].get_type_name(), Color.WHITE)
		if i == idx:
			roster_slots[i]["btn"].add_theme_color_override("font_color", Color(1,1,0))
		else:
			roster_slots[i]["btn"].add_theme_color_override("font_color", col)
	_set_status("Click the battlefield to place " + roster_slots[idx]["troop"].troop_name)

func _place_troop(idx: int, pos: Vector2) -> void:
	var slot = roster_slots[idx]
	if slot["placed"]: return

	var troop: TroopData = slot["troop"]
	var eff = troop.get_effective_stats()
	var type_name = troop.get_type_name()
	var col = TROOP_COLORS.get(type_name, Color.WHITE)
	var sz = 30.0

	# Rect
	var rect = ColorRect.new()
	rect.color = col
	rect.size = Vector2(sz, sz)
	rect.position = pos - Vector2(sz/2, sz/2)
	field_node.add_child(rect)

	# Name label
	var lbl = Label.new()
	lbl.text = troop.troop_name.left(8)
	lbl.add_theme_font_size_override("font_size", 9)
	lbl.add_theme_color_override("font_color", Color.WHITE)
	lbl.position = pos - Vector2(20, sz/2 + 14)
	field_node.add_child(lbl)

	# HP bar bg
	var hpbg = ColorRect.new()
	hpbg.color = Color(0.3, 0.1, 0.1)
	hpbg.size = Vector2(sz, 5)
	hpbg.position = pos - Vector2(sz/2, sz/2 + 7)
	field_node.add_child(hpbg)

	# HP bar
	var hpbar = ColorRect.new()
	hpbar.color = Color(0.3, 0.9, 0.3)
	hpbar.size = Vector2(sz, 5)
	hpbar.position = pos - Vector2(sz/2, sz/2 + 7)
	field_node.add_child(hpbar)

	var max_hp = eff.get("hp", 100)
	var attack_speed = max(0.5, 2.5 - eff.get("speed", 3) * 0.15)

	placed_troops.append({
		"troop": troop, "pos": pos,
		"hp": max_hp, "max_hp": max_hp,
		"attack": eff.get("attack", 10),
		"defense": eff.get("defense", 5),
		"type": type_name,
		"attack_t": attack_speed,
		"attack_interval": attack_speed,
		"heal_t": 3.0,
		"rect": rect, "hp_bar": hpbar, "hp_bar_bg": hpbg,
		"sz": sz,
	})

	slot["placed"] = true
	slot["btn"].add_theme_color_override("font_color", Color(0.4, 0.4, 0.4))
	slot["btn"].text = slot["btn"].text + "\n[ON FIELD]"
	selected_roster_idx = -1
	place_cooldown = PLACE_COOLDOWN
	_set_status(troop.troop_name + " placed!")

# -------------------------------------------------------
# Wave spawning
# -------------------------------------------------------
func _spawn_wave(wave_num: int) -> void:
	var stage = PlayerInventory.current_stage
	var base_count = 4 + wave_num * 2
	var count = max(2, int(base_count * attack_force_mult))
	var is_boss_wave = (wave_num == total_waves - 1)

	for i in range(count):
		var delay = i * 0.8
		get_tree().create_timer(delay).timeout.connect(_spawn_one_enemy.bind(wave_num, is_boss_wave and i == 0))

func _spawn_one_enemy(wave_num: int, is_boss: bool) -> void:
	var stage = PlayerInventory.current_stage
	var sz = 50.0 if is_boss else 24.0
	var max_hp = int((20 + wave_num * 15 + stage * 8) * (4 if is_boss else 1) * max(0.6, attack_force_mult))
	var spd = 40.0 + wave_num * 5.0
	var atk = int((3 + wave_num * 2 + stage) * max(0.6, attack_force_mult))

	var ey = randf_range(30, FIELD_H - 140)

	var rect = ColorRect.new()
	rect.color = Color(1, 0.2, 0.1) if is_boss else C_ENEMY
	rect.size = Vector2(sz, sz)
	rect.position = Vector2(SPAWN_X - sz, ey - sz/2)
	field_node.add_child(rect)

	var hpbg = ColorRect.new()
	hpbg.color = Color(0.3, 0.1, 0.1)
	hpbg.size = Vector2(sz, 5)
	hpbg.position = Vector2(SPAWN_X - sz, ey - sz/2 - 7)
	field_node.add_child(hpbg)

	var hpbar = ColorRect.new()
	hpbar.color = Color(0.9, 0.2, 0.2)
	hpbar.size = Vector2(sz, 5)
	hpbar.position = Vector2(SPAWN_X - sz, ey - sz/2 - 7)
	field_node.add_child(hpbar)

	enemies.append({
		"pos": Vector2(SPAWN_X - sz/2, ey),
		"hp": max_hp, "max_hp": max_hp,
		"attack": atk, "speed": spd,
		"sz": sz, "is_boss": is_boss,
		"attack_t": 1.5,
		"rect": rect, "hp_bar": hpbar, "hp_bar_bg": hpbg,
	})

# -------------------------------------------------------
# Process
# -------------------------------------------------------
func _process(delta: float) -> void:
	if game_over: return
	place_cooldown -= delta

	# Wave timer
	if not wave_active:
		wave_timer -= delta
		hud_timer.text = "Next wave in: %.1fs" % max(0, wave_timer)
		if wave_timer <= 0:
			current_wave += 1
			wave_active = true
			_spawn_wave(current_wave - 1)
			_refresh_hud()
			_set_status("Wave %d incoming!" % current_wave)
	else:
		hud_timer.text = "Wave %d active" % current_wave

	_process_enemies(delta)
	_process_troops(delta)
	_move_projectiles(delta)
	_update_visuals()

	# Check wave cleared
	if wave_active and enemies.is_empty():
		wave_active = false
		if current_wave >= total_waves:
			_on_victory()
		else:
			wave_timer = WAVE_INTERVAL
			_set_status("Wave %d cleared! Next wave in %.0fs..." % [current_wave, WAVE_INTERVAL])

func _process_enemies(delta: float) -> void:
	var new_enemies = []
	for e in enemies:
		if not is_instance_valid(e["rect"]):
			continue

		# Find best target troop — knights get an effective aggro bonus
		# (their real distance is reduced for targeting purposes, pulling enemies toward them)
		var target_troop = null
		var target_score = INF
		for t in placed_troops:
			if t["hp"] <= 0: continue
			var d = e["pos"].distance_to(t["pos"])
			var score = d - (KNIGHT_AGGRO_BONUS if t["type"] == "KNIGHT" else 0.0)
			if score < target_score:
				target_score = score
				target_troop = t

		var melee_range = 0.0
		var real_dist = INF
		if target_troop:
			melee_range = e["sz"] / 2 + target_troop["sz"] / 2 + 6
			real_dist = e["pos"].distance_to(target_troop["pos"])

		if target_troop and real_dist <= melee_range:
			# In melee range — stop and fight
			e["attack_t"] -= delta
			if e["attack_t"] <= 0:
				_damage_troop(target_troop, e["attack"])
				e["attack_t"] = 1.2
		elif target_troop:
			# Move toward target troop
			var dir = (target_troop["pos"] - e["pos"]).normalized()
			e["pos"] += dir * e["speed"] * delta
			# Keep enemy inside the field bounds
			e["pos"].x = clamp(e["pos"].x, BASE_X, FIELD_W - 20)
			e["pos"].y = clamp(e["pos"].y, 10, FIELD_H - 130)
		elif e["pos"].x <= BASE_X + 30:
			# No troops left — attack base
			e["attack_t"] -= delta
			if e["attack_t"] <= 0:
				_damage_base(e["attack"])
				e["attack_t"] = 1.0
		else:
			# No troops — march toward base
			e["pos"].x -= e["speed"] * delta

		# Reached base
		if e["pos"].x <= BASE_X:
			_damage_base(e["attack"] * 2)
			if is_instance_valid(e["rect"]): e["rect"].queue_free()
			if is_instance_valid(e["hp_bar"]): e["hp_bar"].queue_free()
			if is_instance_valid(e["hp_bar_bg"]): e["hp_bar_bg"].queue_free()
			continue

		new_enemies.append(e)
	enemies = new_enemies

func _process_troops(delta: float) -> void:
	for t in placed_troops:
		if t["hp"] <= 0: continue

		match t["type"]:
			"KNIGHT":
				# Tank — melee, also taunts: enemies within range prefer to target knights
				t["attack_t"] -= delta
				if t["attack_t"] <= 0:
					var nearest = _nearest_enemy(t["pos"], 120)
					if nearest:
						_damage_enemy(nearest, t["attack"])
						t["attack_t"] = t["attack_interval"]
			"ROGUE":
				# Fast melee striker — short range but hits hard and fast, no taunt
				t["attack_t"] -= delta
				if t["attack_t"] <= 0:
					var nearest = _nearest_enemy(t["pos"], 90)
					if nearest:
						_damage_enemy(nearest, int(t["attack"] * 1.3))
						t["attack_t"] = t["attack_interval"] * 0.6
			"ARCHER":
				# Ranged — shoots nearest enemy anywhere on the field
				t["attack_t"] -= delta
				if t["attack_t"] <= 0:
					var nearest = _nearest_enemy(t["pos"], 500)
					if nearest:
						_fire_proj(t["pos"], nearest["pos"], t["attack"], true)
						t["attack_t"] = t["attack_interval"]
			"MAGE":
				# AoE — damages all enemies in a large radius
				t["attack_t"] -= delta
				if t["attack_t"] <= 0:
					var hit_any = false
					for e in enemies:
						if t["pos"].distance_to(e["pos"]) < 250:
							_damage_enemy(e, int(t["attack"] * 0.7))
							hit_any = true
					if hit_any:
						t["attack_t"] = t["attack_interval"] * 1.5
					else:
						t["attack_t"] = 0.2
			"HEALER":
				# Heals nearest wounded troop AND attacks nearby enemies
				t["attack_t"] -= delta
				if t["attack_t"] <= 0:
					var nearest = _nearest_enemy(t["pos"], 200)
					if nearest:
						_fire_proj(t["pos"], nearest["pos"], int(t["attack"] * 0.4), true)
					t["attack_t"] = t["attack_interval"]
				t["heal_t"] -= delta
				if t["heal_t"] <= 0:
					var target = _nearest_wounded_troop(t["pos"])
					if target:
						var heal = max(5, int(t["attack"] * 0.5))
						target["hp"] = min(target["hp"] + heal, target["max_hp"])
						_show_heal_effect(target["pos"])
						_update_troop_hp_bar(target)
					t["heal_t"] = 2.5

func _fire_proj(from: Vector2, toward: Vector2, dmg: int, is_troop: bool) -> void:
	var dir = (toward - from).normalized()
	var rect = ColorRect.new()
	rect.size = Vector2(8, 8)
	rect.color = C_PROJ_T if is_troop else C_PROJ_E
	rect.position = from - Vector2(4, 4)
	field_node.add_child(rect)
	projectiles.append({"pos": Vector2(from.x, from.y), "dir": dir,
		"damage": dmg, "is_troop": is_troop, "rect": rect})

func _move_projectiles(delta: float) -> void:
	var new_projs = []
	for p in projectiles:
		if not is_instance_valid(p["rect"]): continue
		p["pos"] += p["dir"] * 280.0 * delta

		var oob = p["pos"].x < 0 or p["pos"].x > FIELD_W or p["pos"].y < 0 or p["pos"].y > FIELD_H
		if oob:
			p["rect"].queue_free()
			continue

		var hit = false
		if p["is_troop"]:
			for e in enemies:
				if p["pos"].distance_to(e["pos"]) < e["sz"]/2 + 4:
					_damage_enemy(e, p["damage"])
					p["rect"].queue_free()
					hit = true
					break
		else:
			for t in placed_troops:
				if t["hp"] > 0 and p["pos"].distance_to(t["pos"]) < t["sz"]/2 + 4:
					_damage_troop(t, p["damage"])
					p["rect"].queue_free()
					hit = true
					break
		if not hit:
			new_projs.append(p)
	projectiles = new_projs

# -------------------------------------------------------
# Damage helpers
# -------------------------------------------------------
func _damage_enemy(e: Dictionary, amount: int) -> void:
	e["hp"] -= max(1, amount)
	if e["hp"] <= 0:
		e["hp"] = 0
		if is_instance_valid(e["rect"]): e["rect"].queue_free()
		if is_instance_valid(e["hp_bar"]): e["hp_bar"].queue_free()
		if is_instance_valid(e["hp_bar_bg"]): e["hp_bar_bg"].queue_free()
		enemies.erase(e)
	else:
		_update_enemy_hp_bar(e)

func _damage_troop(t: Dictionary, amount: int) -> void:
	var reduced = max(1, amount - int(t["defense"] * 0.4))
	t["hp"] -= reduced
	if t["hp"] <= 0:
		t["hp"] = 0
		if is_instance_valid(t["rect"]): t["rect"].color = Color(0.3, 0.3, 0.3)
	_update_troop_hp_bar(t)

func _damage_base(amount: int) -> void:
	base_hp -= amount
	base_hp = max(0, base_hp)
	_refresh_hud()
	base_hp_bar.size.x = 40.0 * float(base_hp) / float(base_max_hp)
	if base_hp <= 0:
		_on_defeat()

func _update_enemy_hp_bar(e: Dictionary) -> void:
	if is_instance_valid(e["hp_bar"]):
		e["hp_bar"].size.x = e["sz"] * float(e["hp"]) / float(e["max_hp"])

func _update_troop_hp_bar(t: Dictionary) -> void:
	if is_instance_valid(t["hp_bar"]):
		var pct = float(t["hp"]) / float(t["max_hp"])
		t["hp_bar"].size.x = t["sz"] * pct
		t["hp_bar"].color = Color(0.9,0.2,0.2) if pct < 0.3 else (
			Color(0.9,0.7,0.2) if pct < 0.6 else Color(0.3,0.9,0.3))

func _show_heal_effect(pos: Vector2) -> void:
	var lbl = Label.new()
	lbl.text = "+HP"
	lbl.add_theme_color_override("font_color", C_HEAL)
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.position = pos - Vector2(12, 30)
	field_node.add_child(lbl)
	get_tree().create_timer(0.6).timeout.connect(func(): if is_instance_valid(lbl): lbl.queue_free())

# -------------------------------------------------------
# Targeting helpers
# -------------------------------------------------------
func _nearest_enemy(from: Vector2, max_range: float) -> Dictionary:
	var nearest = {}
	var nearest_dist = max_range
	for e in enemies:
		if e["hp"] <= 0: continue
		var d = from.distance_to(e["pos"])
		if d < nearest_dist:
			nearest_dist = d
			nearest = e
	return nearest

func _nearest_troop(from: Vector2) -> Dictionary:
	var nearest = {}
	var nearest_dist = INF
	for t in placed_troops:
		if t["hp"] <= 0: continue
		var d = from.distance_to(t["pos"])
		if d < nearest_dist:
			nearest_dist = d
			nearest = t
	return nearest

func _nearest_wounded_troop(from: Vector2) -> Dictionary:
	var nearest = {}
	var nearest_dist = INF
	for t in placed_troops:
		if t["hp"] <= 0 or t["hp"] >= t["max_hp"]: continue
		var d = from.distance_to(t["pos"])
		if d < nearest_dist:
			nearest_dist = d
			nearest = t
	return nearest

# -------------------------------------------------------
# Visuals
# -------------------------------------------------------
func _update_visuals() -> void:
	for e in enemies:
		if is_instance_valid(e["rect"]):
			e["rect"].position = e["pos"] - Vector2(e["sz"]/2, e["sz"]/2)
		if is_instance_valid(e["hp_bar"]):
			e["hp_bar"].position = e["pos"] - Vector2(e["sz"]/2, e["sz"]/2 + 7)
		if is_instance_valid(e["hp_bar_bg"]):
			e["hp_bar_bg"].position = e["pos"] - Vector2(e["sz"]/2, e["sz"]/2 + 7)

# -------------------------------------------------------
# HUD
# -------------------------------------------------------
func _refresh_hud() -> void:
	if hud_wave:
		hud_wave.text = "Wave %d / %d" % [current_wave, total_waves]
	if hud_base_hp:
		hud_base_hp.text = "Base HP: %d / %d" % [base_hp, base_max_hp]
		var col = Color(0.9,0.2,0.2) if base_hp < base_max_hp * 0.3 else Color(0.4,0.7,1.0)
		hud_base_hp.add_theme_color_override("font_color", col)

func _set_status(msg: String) -> void:
	if hud_status: hud_status.text = msg

func _on_retreat() -> void:
	if battle_zone_id >= 0:
		PlayerInventory.last_battle_result = "retreat"
		PlayerInventory.last_battle_zone = battle_zone_id
		PlayerInventory.last_battle_was_conquest = is_conquering
		get_tree().change_scene_to_file("res://scenes/world_map.tscn")
	else:
		get_tree().change_scene_to_file("res://scenes/management_screen.tscn")

func _on_return() -> void:
	if battle_zone_id >= 0:
		get_tree().change_scene_to_file("res://scenes/world_map.tscn")
	else:
		get_tree().change_scene_to_file("res://scenes/management_screen.tscn")

# -------------------------------------------------------
# End states
# -------------------------------------------------------
func _on_victory() -> void:
	game_over = true
	PlayerInventory.current_stage += 1
	if PlayerInventory.current_stage in [3, 5, 8]:
		PlayerInventory.unlock_troop_slot()

	# Report result to map
	if battle_zone_id >= 0:
		PlayerInventory.last_battle_result = "won"
		PlayerInventory.last_battle_zone = battle_zone_id
		PlayerInventory.last_battle_was_conquest = is_conquering

	SaveManager.save_game()
	_show_end_screen(true)

func _on_defeat() -> void:
	game_over = true

	if battle_zone_id >= 0:
		PlayerInventory.last_battle_result = "lost"
		PlayerInventory.last_battle_zone = battle_zone_id
		PlayerInventory.last_battle_was_conquest = is_conquering

	SaveManager.save_game()
	_show_end_screen(false)

func _show_end_screen(won: bool) -> void:
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
	vbox.add_theme_constant_override("separation", 14)
	panel.add_child(vbox)

	var title = Label.new()
	title.text = "VICTORY!" if won else "BASE DESTROYED"
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color(0.3,0.9,0.3) if won else Color(0.9,0.2,0.2))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var sub = Label.new()
	sub.text = ("All %d waves survived!" % total_waves) if won else "Your base has fallen."
	sub.add_theme_color_override("font_color", Color(0.8,0.8,0.8))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(sub)

	var btn = Button.new()
	btn.text = "Return to Map" if battle_zone_id >= 0 else "Back to Management"
	btn.custom_minimum_size = Vector2(220, 44)
	btn.pressed.connect(_on_return)
	vbox.add_child(btn)
