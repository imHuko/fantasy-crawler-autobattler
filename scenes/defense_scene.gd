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

const PLACE_COOLDOWN  = 0.5    # prevent double-placing
const KNIGHT_AGGRO_BONUS = 60.0

var battle_active: bool = false
var _all_enemies_spawned: bool = true
var game_over: bool = false
var base_hp: int = 20
var base_max_hp: int = 20

# Zone context — set by world map before launching this scene
var battle_zone_id: int = -1
var battle_started: bool = false   # true once player presses Begin Battle
var begin_battle_btn: Button = null
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
	_plan_wave()
	_build_ui()
	_build_field()
	_spawn_battle_force()
	_build_roster_ui()
	_refresh_hud()
	_show_wave_preview()

func _load_battle_context() -> void:
	battle_zone_id = PlayerInventory.current_battle_zone
	is_conquering = PlayerInventory.conquering_zone
	attack_force_mult = PlayerInventory.current_attack_force

	battle_title = "Conquer Zone" if is_conquering else "Defend the Base"

	# Scale base HP by force multiplier
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

	if PlayerInventory.current_battle_forge_level > 0 or PlayerInventory.current_battle_shrine_level > 0:
		var buff_lbl = Label.new()
		var parts = []
		if PlayerInventory.current_battle_forge_level > 0:
			parts.append("Forge +%d%% ATK" % (PlayerInventory.current_battle_forge_level * 5))
		if PlayerInventory.current_battle_shrine_level > 0:
			parts.append("Shrine +%d%% HP" % (PlayerInventory.current_battle_shrine_level * 5))
		buff_lbl.text = "  ".join(parts)
		buff_lbl.add_theme_font_size_override("font_size", 12)
		buff_lbl.add_theme_color_override("font_color", Color(1.0, 0.7, 0.3))
		top_hbox.add_child(buff_lbl)

	hud_status = Label.new()
	hud_status.add_theme_font_size_override("font_size", 13)
	hud_status.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	hud_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_hbox.add_child(hud_status)

	var scout_btn = Button.new()
	scout_btn.text = "👁 Scout"
	scout_btn.custom_minimum_size = Vector2(80, 32)
	scout_btn.tooltip_text = "Review the incoming enemy composition"
	scout_btn.pressed.connect(_show_wave_preview)
	top_hbox.add_child(scout_btn)

	begin_battle_btn = Button.new()
	begin_battle_btn.text = "⚔ Begin Battle"
	begin_battle_btn.custom_minimum_size = Vector2(140, 32)
	begin_battle_btn.add_theme_color_override("font_color", Color(1, 0.6, 0.3))
	begin_battle_btn.pressed.connect(_on_begin_battle_pressed)
	top_hbox.add_child(begin_battle_btn)

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

	var zone_troop_ids = PlayerInventory.get_zone_troop_names(battle_zone_id)
	if zone_troop_ids.is_empty():
		return []

	var result = []
	for troop in PlayerInventory.troop_roster:
		if troop.troop_id in zone_troop_ids:
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

	# Placement boundary — troops can only be placed left of this line,
	# keeping the whole right half clear for the enemy approach and
	# ensuring every placed troop stays visible on screen.
	var placement_limit_x = FIELD_W / 2.0
	var boundary_line = Line2D.new()
	boundary_line.add_point(Vector2(placement_limit_x, 0))
	boundary_line.add_point(Vector2(placement_limit_x, FIELD_H - 110))
	boundary_line.width = 2.0
	boundary_line.default_color = Color(1.0, 0.85, 0.3, 0.5)
	field_node.add_child(boundary_line)

	var boundary_label = Label.new()
	boundary_label.text = "Placement Limit"
	boundary_label.add_theme_font_size_override("font_size", 10)
	boundary_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3, 0.8))
	boundary_label.position = Vector2(placement_limit_x - 70, 6)
	field_node.add_child(boundary_label)

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
			# Middle of the map is a hard boundary — troops can only be
			# placed on your half, keeping them clear of the enemy
			# approach and visible on screen before the battle starts.
			var placement_limit_x = FIELD_W / 2.0
			if click_pos.x > BASE_X + 30 and click_pos.x < placement_limit_x \
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

	# Sprite (procedural shape-based placeholder, swap for real art later)
	var unit_type_map = {
		"KNIGHT": UnitSprite.UnitType.KNIGHT, "ARCHER": UnitSprite.UnitType.ARCHER,
		"MAGE": UnitSprite.UnitType.MAGE, "HEALER": UnitSprite.UnitType.HEALER,
		"ROGUE": UnitSprite.UnitType.ROGUE,
	}
	var rect = UnitSprite.new()
	rect.setup(unit_type_map.get(type_name, UnitSprite.UnitType.KNIGHT), col, sz)
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
	var attack_val = eff.get("attack", 10)
	var spell_power_pct = eff.get("spell_power", 0.0)   # % bonus to Mage damage / Healer heal
	var lifesteal_pct = eff.get("lifesteal", 0.0)         # % of damage dealt returned as self-heal
	var thorns_val = eff.get("thorns", 0.0)               # flat damage reflected on melee hits taken
	var move_speed_bonus = eff.get("move_speed", 0.0)     # bonus to movement, matters most for melee

	# Carry over persisted HP from outside this battle, rather than
	# always starting at full — wounded troops stay wounded until healed
	# with food back at Management. Scaled proportionally so a Shrine's
	# max HP buff (applied below) doesn't distort how wounded this reads.
	var hp_pct_before_buffs = float(troop.get_current_hp()) / max(1, troop.get_max_hp())

	# Apply zone Forge/Shrine buffs — 5% per level
	var forge_lvl = PlayerInventory.current_battle_forge_level
	var shrine_lvl = PlayerInventory.current_battle_shrine_level
	if forge_lvl > 0:
		attack_val = int(attack_val * (1.0 + forge_lvl * 0.05))
	if shrine_lvl > 0:
		max_hp = int(max_hp * (1.0 + shrine_lvl * 0.05))

	var starting_hp = max(1, int(max_hp * hp_pct_before_buffs))

	var attack_speed = max(0.5, 2.5 - eff.get("speed", 3) * 0.15)

	placed_troops.append({
		"troop": troop, "pos": pos,
		"hp": starting_hp, "max_hp": max_hp,
		"attack": attack_val,
		"defense": eff.get("defense", 5),
		"spell_power": spell_power_pct,
		"lifesteal": lifesteal_pct,
		"thorns": thorns_val,
		"move_speed_bonus": move_speed_bonus,
		"type": type_name,
		"attack_t": attack_speed,
		"attack_interval": attack_speed,
		"heal_t": 3.0,
		"rect": rect, "hp_bar": hpbar, "hp_bar_bg": hpbg, "label": lbl,
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
var _enemies_pending_spawn: int = 0

# -------------------------------------------------------
# Enemy archetypes — each plays meaningfully differently rather than
# every enemy being the same stat profile with a different number.
# -------------------------------------------------------
const ENEMY_ARCHETYPES = {
	"MELEE":   { "hp_mult": 1.0,  "dmg_mult": 1.0,  "speed_mult": 1.0,  "color": Color(0.7, 0.25, 0.25), "symbol": "⚔", "label": "Melee" },
	"RANGED":  { "hp_mult": 0.75, "dmg_mult": 0.9,  "speed_mult": 0.9,  "color": Color(0.25, 0.6, 0.3), "symbol": "➹", "label": "Ranged" },
	"ROGUE":   { "hp_mult": 0.6,  "dmg_mult": 1.3,  "speed_mult": 1.6,  "color": Color(0.55, 0.2, 0.65), "symbol": "✦", "label": "Bypasser" },
	"TANK":    { "hp_mult": 2.6,  "dmg_mult": 0.55, "speed_mult": 0.55, "color": Color(0.4, 0.4, 0.45), "symbol": "▣", "label": "Tank" },
	"BUFFER":  { "hp_mult": 0.5,  "dmg_mult": 0.0,  "speed_mult": 0.85, "color": Color(0.85, 0.75, 0.2), "symbol": "✪", "label": "Buffer" },
	"CHARGER": { "hp_mult": 0.4,  "dmg_mult": 2.5,  "speed_mult": 2.4,  "color": Color(0.9, 0.45, 0.1), "symbol": "✹", "label": "Charger" },
}
const RANGED_ATTACK_RANGE = 260.0
const CHARGER_BURST_RANGE = 50.0
const BUFFER_AURA_RANGE = 180.0
const BUFFER_BUFF_INTERVAL = 4.0
const BUFFER_DMG_BOOST_PCT = 0.35
const BUFFER_DMG_BOOST_DURATION = 3.0

# Which archetypes can appear at a given stage, and their relative spawn
# weight. Early stages are mostly plain melee; more complex types are
# introduced gradually so the player isn't hit with everything at once.
func _get_archetype_weights(stage: int) -> Dictionary:
	if stage <= 1:
		return {"MELEE": 100}
	elif stage <= 2:
		return {"MELEE": 70, "RANGED": 30}
	elif stage <= 3:
		return {"MELEE": 55, "RANGED": 25, "ROGUE": 20}
	elif stage <= 4:
		return {"MELEE": 40, "RANGED": 20, "ROGUE": 20, "TANK": 20}
	elif stage <= 6:
		return {"MELEE": 30, "RANGED": 20, "ROGUE": 20, "TANK": 20, "CHARGER": 10}
	else:
		return {"MELEE": 22, "RANGED": 18, "ROGUE": 18, "TANK": 18, "CHARGER": 14, "BUFFER": 10}

func _roll_archetype(stage: int) -> String:
	var weights = _get_archetype_weights(stage)
	var total = 0
	for w in weights.values(): total += w
	var roll = randi() % total
	var cumulative = 0
	for archetype in weights:
		cumulative += weights[archetype]
		if roll < cumulative:
			return archetype
	return "MELEE"

var planned_wave: Array = []   # pre-rolled archetype list for this battle, set by _plan_wave()

# Rolls the full wave composition once, before the player places any
# troops, so it can be shown in a preview panel. Spawning later just
# consumes this same list rather than rolling fresh per-enemy, so what
# the player sees in the preview is exactly what they'll actually fight.
func _plan_wave() -> void:
	var stage = PlayerInventory.current_stage
	var base_count = 6 + stage
	var count = max(5, int(base_count * attack_force_mult))
	if is_conquering:
		count = max(4, int(count * 0.7))   # conquest fights are a bit smaller, but never trivial

	planned_wave.clear()
	for i in range(count):
		var is_boss = (i == count - 1) and count >= 4
		planned_wave.append("BOSS" if is_boss else _roll_archetype(stage))

func _get_wave_composition_counts() -> Dictionary:
	var counts = {}
	for archetype in planned_wave:
		counts[archetype] = counts.get(archetype, 0) + 1
	return counts

# Shows the enemy wave composition before the player places troops, so
# picking a roster is an informed decision rather than a guess. Closing
# this just dismisses it — troop placement and Begin Battle work exactly
# as before underneath it.
func _show_wave_preview() -> void:
	var overlay = CanvasLayer.new()
	add_child(overlay)

	var bg = ColorRect.new()
	bg.color = Color(0, 0, 0, 0.75)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(bg)

	var panel = PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	overlay.add_child(panel)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	vbox.custom_minimum_size = Vector2(260, 0)
	panel.add_child(vbox)

	var title = Label.new()
	title.text = "Incoming Forces"
	title.add_theme_font_size_override("font_size", 18)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var sep = HSeparator.new()
	vbox.add_child(sep)

	var counts = _get_wave_composition_counts()
	# Show BOSS first if present, then the rest in a stable, readable order
	var order = ["BOSS", "TANK", "MELEE", "RANGED", "ROGUE", "CHARGER", "BUFFER"]
	for archetype in order:
		if not counts.has(archetype): continue
		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		vbox.add_child(row)

		var symbol_lbl = Label.new()
		var color = Color(1, 0.3, 0.2) if archetype == "BOSS" else ENEMY_ARCHETYPES[archetype]["color"]
		var symbol = "☠" if archetype == "BOSS" else ENEMY_ARCHETYPES[archetype]["symbol"]
		symbol_lbl.text = symbol
		symbol_lbl.add_theme_font_size_override("font_size", 16)
		symbol_lbl.add_theme_color_override("font_color", color)
		symbol_lbl.custom_minimum_size = Vector2(24, 0)
		row.add_child(symbol_lbl)

		var name_lbl = Label.new()
		var display_name = "Boss" if archetype == "BOSS" else ENEMY_ARCHETYPES[archetype]["label"]
		name_lbl.text = display_name
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_lbl)

		var count_lbl = Label.new()
		count_lbl.text = "x%d" % counts[archetype]
		count_lbl.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
		row.add_child(count_lbl)

	var sep2 = HSeparator.new()
	vbox.add_child(sep2)

	var close_btn = Button.new()
	close_btn.text = "Got it"
	close_btn.custom_minimum_size = Vector2(0, 32)
	close_btn.pressed.connect(func(): overlay.queue_free())
	vbox.add_child(close_btn)

# Which horizontal band of the enemy zone each archetype starts in,
# front-to-back relative to the player's line. Tank/Melee hold the
# front since they're built to engage directly. Bypasser/Charger sit in
# the middle — their whole identity is about reaching a specific target
# rather than holding a position, so starting them mid-field telegraphs
# the threat instead of burying it at the very back where it'd be
# invisible until it's already past your troops. Ranged/Buffer hold the
# back since they want distance from the front line.
const ARCHETYPE_BAND = {
	"TANK": 0, "MELEE": 0, "BOSS": 0,
	"ROGUE": 1, "CHARGER": 1,
	"RANGED": 2, "BUFFER": 2,
}

func _spawn_battle_force() -> void:
	var stage = PlayerInventory.current_stage
	_all_enemies_spawned = true
	_enemies_pending_spawn = 0

	# Enemies occupy the right half of the field, mirroring the player's
	# placement boundary on the left — both sides fully visible before
	# the battle starts, instead of trickling in one at a time once it does.
	var enemy_zone_left = FIELD_W / 2.0 + 20.0
	var enemy_zone_right = FIELD_W - 40.0
	var zone_width = enemy_zone_right - enemy_zone_left
	var count = planned_wave.size()

	for i in range(count):
		var archetype = planned_wave[i]
		var band = ARCHETYPE_BAND.get(archetype, 1)
		var band_left = enemy_zone_left + zone_width * (band / 3.0)
		var band_right = enemy_zone_left + zone_width * ((band + 1) / 3.0)
		var ex = randf_range(band_left, band_right)
		var ey = randf_range(30, FIELD_H - 140)
		_spawn_one_enemy(stage, archetype, Vector2(ex, ey))

func _spawn_one_enemy(stage: int, archetype: String, spawn_pos: Vector2) -> void:
	var is_boss = archetype == "BOSS"
	var profile = ENEMY_ARCHETYPES["MELEE"] if is_boss else ENEMY_ARCHETYPES[archetype]

	var sz = 50.0 if is_boss else 24.0
	var max_hp = int((18 + stage * 10) * (4 if is_boss else 1) * max(0.6, attack_force_mult) * profile["hp_mult"])
	var spd = (45.0 + stage * 4.0) * profile["speed_mult"]
	var atk = int((3 + stage * 2) * max(0.6, attack_force_mult) * profile["dmg_mult"])

	var ex = spawn_pos.x
	var ey = spawn_pos.y

	var rect = UnitSprite.new()
	var sprite_color = Color(1, 0.2, 0.1) if is_boss else profile["color"]
	rect.setup(UnitSprite.UnitType.ENEMY_BOSS if is_boss else UnitSprite.UnitType.ENEMY_BASIC,
		sprite_color, sz)
	rect.position = Vector2(ex - sz/2, ey - sz/2)
	field_node.add_child(rect)

	var type_lbl = Label.new()
	type_lbl.text = "BOSS" if is_boss else profile["symbol"]
	type_lbl.add_theme_font_size_override("font_size", 13 if is_boss else 12)
	type_lbl.add_theme_color_override("font_color", Color(1, 1, 1))
	type_lbl.position = Vector2(ex - sz/2 - 4, ey - sz/2 - 22)
	field_node.add_child(type_lbl)

	var hpbg = ColorRect.new()
	hpbg.color = Color(0.3, 0.1, 0.1)
	hpbg.size = Vector2(sz, 5)
	hpbg.position = Vector2(ex - sz/2, ey - sz/2 - 7)
	field_node.add_child(hpbg)

	var hpbar = ColorRect.new()
	hpbar.color = Color(0.9, 0.2, 0.2)
	hpbar.size = Vector2(sz, 5)
	hpbar.position = Vector2(ex - sz/2, ey - sz/2 - 7)
	field_node.add_child(hpbar)

	enemies.append({
		"pos": Vector2(ex, ey),
		"hp": max_hp, "max_hp": max_hp,
		"attack": atk, "speed": spd,
		"sz": sz, "is_boss": is_boss,
		"enemy_type": "BOSS" if is_boss else archetype,
		"attack_t": 1.5,
		"buff_t": BUFFER_BUFF_INTERVAL,
		"dmg_boost_t": 0.0,
		"rect": rect, "hp_bar": hpbar, "hp_bar_bg": hpbg, "type_lbl": type_lbl,
	})

# -------------------------------------------------------
# Process
# -------------------------------------------------------
func _process(delta: float) -> void:
	if game_over: return
	place_cooldown -= delta

	if not battle_active:
		if battle_started:
			# Player pressed Begin Battle — the wave is already on the
			# field from scene load, this just lets combat logic begin.
			battle_active = true
			battle_started = false
			_refresh_hud()
			_set_status("Charge!")
			if begin_battle_btn: begin_battle_btn.visible = false
		else:
			hud_timer.text = "Place your troops, then press Begin Battle"
	else:
		hud_timer.text = "Battle in progress..."

	if battle_active:
		_process_enemies(delta)
		_process_troops(delta)
		_move_projectiles(delta)
	_update_visuals()

	# Check battle won — all enemies cleared, including any still in spawn queue
	if battle_active and enemies.is_empty() and _all_enemies_spawned:
		_on_victory()

func _process_enemies(delta: float) -> void:
	var new_enemies = []
	for e in enemies:
		if not is_instance_valid(e["rect"]):
			continue

		var enemy_type = e.get("enemy_type", "MELEE")

		if enemy_type == "BUFFER":
			_process_buffer_enemy(e, delta)
			new_enemies.append(e)
			continue

		if e.get("dmg_boost_t", 0.0) > 0.0:
			e["dmg_boost_t"] -= delta

		var target_troop = _find_enemy_target(e, enemy_type)

		var attack_range = 0.0
		var real_dist = INF
		if target_troop:
			if enemy_type == "RANGED":
				attack_range = RANGED_ATTACK_RANGE
			else:
				attack_range = e["sz"] / 2 + target_troop["sz"] / 2 + 6
			real_dist = e["pos"].distance_to(target_troop["pos"])

		var effective_atk = e["attack"]
		if e.get("dmg_boost_t", 0.0) > 0.0:
			effective_atk = int(effective_atk * (1.0 + BUFFER_DMG_BOOST_PCT))

		if target_troop and real_dist <= attack_range:
			# In range — stop and fight (melee swing or ranged shot)
			e["attack_t"] -= delta
			if e["attack_t"] <= 0:
				if enemy_type == "RANGED":
					_fire_proj(e["pos"], target_troop["pos"], effective_atk, false)
					e["attack_t"] = 1.4
				elif enemy_type == "CHARGER":
					# One big burst, then the charger detonates and is removed
					_damage_troop(target_troop, effective_atk, e)
					if is_instance_valid(e["rect"]): e["rect"].queue_free()
					if is_instance_valid(e["hp_bar"]): e["hp_bar"].queue_free()
					if is_instance_valid(e["hp_bar_bg"]): e["hp_bar_bg"].queue_free()
					if is_instance_valid(e.get("type_lbl")): e["type_lbl"].queue_free()
					continue
				else:
					_damage_troop(target_troop, effective_atk, e)
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
				_damage_base(effective_atk)
				e["attack_t"] = 1.0
		else:
			# No troops — march toward base
			e["pos"].x -= e["speed"] * delta

		# Reached base
		if e["pos"].x <= BASE_X:
			_damage_base(effective_atk * 2)
			if is_instance_valid(e["rect"]): e["rect"].queue_free()
			if is_instance_valid(e["hp_bar"]): e["hp_bar"].queue_free()
			if is_instance_valid(e["hp_bar_bg"]): e["hp_bar_bg"].queue_free()
			if is_instance_valid(e.get("type_lbl")): e["type_lbl"].queue_free()
			continue

		new_enemies.append(e)
	enemies = new_enemies

# Picks which troop an enemy should target. Most archetypes use the
# standard Knight-aggro formula (nearest troop, with Knights pulling
# extra attention). Rogue ignores that entirely and explicitly hunts
# backline roles (Mage/Healer/Archer) regardless of distance, falling
# back to nearest-any-troop only if no backline role is present.
func _find_enemy_target(e: Dictionary, enemy_type: String) -> Dictionary:
	if enemy_type == "ROGUE":
		var backline_target = {}
		var backline_dist = INF
		for t in placed_troops:
			if t["hp"] <= 0: continue
			if t["type"] in ["MAGE", "HEALER", "ARCHER"]:
				var d = e["pos"].distance_to(t["pos"])
				if d < backline_dist:
					backline_dist = d
					backline_target = t
		if not backline_target.is_empty():
			return backline_target
		# No backline role on the field — fall back to nearest of anyone

	var target_troop = {}
	var target_score = INF
	for t in placed_troops:
		if t["hp"] <= 0: continue
		var d = e["pos"].distance_to(t["pos"])
		var score = d - (KNIGHT_AGGRO_BONUS if t["type"] == "KNIGHT" else 0.0)
		if score < target_score:
			target_score = score
			target_troop = t
	return target_troop

# Buffer enemy — doesn't attack troops at all. Periodically grants a
# temporary damage boost to nearby allied enemies, making it a real
# priority-kill target rather than just another body in the wave.
func _process_buffer_enemy(e: Dictionary, delta: float) -> void:
	# Drift slowly toward the action rather than standing frozen at spawn
	if placed_troops.size() > 0:
		var nearest_troop_dist = INF
		for t in placed_troops:
			if t["hp"] <= 0: continue
			nearest_troop_dist = min(nearest_troop_dist, e["pos"].distance_to(t["pos"]))
		if nearest_troop_dist > BUFFER_AURA_RANGE * 1.5:
			e["pos"].x -= e["speed"] * delta * 0.6
			e["pos"].x = clamp(e["pos"].x, BASE_X, FIELD_W - 20)

	e["buff_t"] -= delta
	if e["buff_t"] <= 0:
		e["buff_t"] = BUFFER_BUFF_INTERVAL
		for other in enemies:
			if other == e: continue
			if e["pos"].distance_to(other["pos"]) <= BUFFER_AURA_RANGE:
				other["dmg_boost_t"] = BUFFER_DMG_BOOST_DURATION

func _process_troops(delta: float) -> void:
	for t in placed_troops:
		if t["hp"] <= 0: continue

		match t["type"]:
			"KNIGHT":
				# Tank — melee, also taunts: enemies within range prefer to target knights
				_melee_engage(t, delta, 120.0, 70.0, t["attack"], 1.0)
			"ROGUE":
				# Fast melee striker — short range but hits hard and fast, no taunt
				_melee_engage(t, delta, 90.0, 95.0, int(t["attack"] * 1.3), 0.6)
			"ARCHER":
				# Ranged — shoots nearest enemy anywhere on the field, doesn't need to move
				t["attack_t"] -= delta
				if t["attack_t"] <= 0:
					var nearest = _nearest_enemy(t["pos"], 500)
					if nearest:
						_fire_proj(t["pos"], nearest["pos"], t["attack"], true, t)
						t["attack_t"] = t["attack_interval"]
			"MAGE":
				# AoE — damages all enemies in a large radius.
				# If nothing is in range, drifts slowly toward the action instead
				# of staying frozen at its placement spot forever.
				var in_range = false
				for e in enemies:
					if t["pos"].distance_to(e["pos"]) < 250:
						in_range = true
						break

				if not in_range:
					var target = _nearest_enemy_anywhere(t["pos"])
					if not target.is_empty():
						var dir = (target["pos"] - t["pos"]).normalized()
						t["pos"] += dir * 40.0 * delta   # slow drift, much slower than melee
						t["pos"].x = clamp(t["pos"].x, BASE_X + 10, FIELD_W - 20)
						t["pos"].y = clamp(t["pos"].y, 10, FIELD_H - 130)

				t["attack_t"] -= delta
				if t["attack_t"] <= 0:
					var hit_any = false
					var spell_dmg = int(t["attack"] * 0.7 * (1.0 + t.get("spell_power", 0.0)))
					for e in enemies:
						if t["pos"].distance_to(e["pos"]) < 250:
							_damage_enemy(e, spell_dmg, t)
							hit_any = true
					if hit_any:
						t["attack_t"] = t["attack_interval"] * 1.5
					else:
						t["attack_t"] = 0.2
			"HEALER":
				# Heals nearest wounded troop AND attacks nearby enemies, stays put
				t["attack_t"] -= delta
				if t["attack_t"] <= 0:
					var nearest = _nearest_enemy(t["pos"], 200)
					if nearest:
						_fire_proj(t["pos"], nearest["pos"], int(t["attack"] * 0.4), true, t)
					t["attack_t"] = t["attack_interval"]
				t["heal_t"] -= delta
				if t["heal_t"] <= 0:
					var target = _nearest_wounded_troop(t["pos"])
					if target:
						var heal = max(5, int(t["attack"] * 0.5 * (1.0 + t.get("spell_power", 0.0))))
						target["hp"] = min(target["hp"] + heal, target["max_hp"])
						_show_heal_effect(target["pos"])
						_update_troop_hp_bar(target)
					t["heal_t"] = 2.5

func _fire_proj(from: Vector2, toward: Vector2, dmg: int, is_troop: bool, source: Dictionary = {}) -> void:
	var dir = (toward - from).normalized()
	var rect = ColorRect.new()
	rect.size = Vector2(8, 8)
	rect.color = C_PROJ_T if is_troop else C_PROJ_E
	rect.position = from - Vector2(4, 4)
	field_node.add_child(rect)
	projectiles.append({"pos": Vector2(from.x, from.y), "dir": dir,
		"damage": dmg, "is_troop": is_troop, "rect": rect, "source": source})

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
					_damage_enemy(e, p["damage"], p.get("source", {}))
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
func _damage_enemy(e: Dictionary, amount: int, source_troop: Dictionary = {}) -> void:
	e["hp"] -= max(1, amount)

	# Lifesteal — heals the attacking troop for a % of damage dealt.
	# Inert on Healer since they don't call this function as the attacker
	# (their heal logic is separate), so this naturally does nothing for them.
	if not source_troop.is_empty():
		var lifesteal_pct = source_troop.get("lifesteal", 0.0)
		if lifesteal_pct > 0.0 and source_troop["hp"] > 0:
			var healed = max(1, int(amount * lifesteal_pct))
			source_troop["hp"] = min(source_troop["hp"] + healed, source_troop["max_hp"])
			_update_troop_hp_bar(source_troop)

	if e["hp"] <= 0:
		e["hp"] = 0
		if is_instance_valid(e["rect"]): e["rect"].queue_free()
		if is_instance_valid(e["hp_bar"]): e["hp_bar"].queue_free()
		if is_instance_valid(e["hp_bar_bg"]): e["hp_bar_bg"].queue_free()
		if is_instance_valid(e.get("type_lbl")): e["type_lbl"].queue_free()
		enemies.erase(e)
	else:
		_update_enemy_hp_bar(e)

func _damage_troop(t: Dictionary, amount: int, source_enemy: Dictionary = {}) -> void:
	var reduced = max(1, amount - int(t["defense"] * 0.4))
	t["hp"] -= reduced

	# Thorns — reflects flat damage back to a melee attacker. Only passed
	# in by the genuine melee-range hit, so ranged/projectile damage to a
	# troop never triggers this — matches Thorns being melee-only.
	var thorns_val = t.get("thorns", 0.0)
	if thorns_val > 0.0 and not source_enemy.is_empty():
		_damage_enemy(source_enemy, int(thorns_val))

	if t["hp"] <= 0:
		t["hp"] = 0
		if is_instance_valid(t["rect"]) and t["rect"] is UnitSprite:
			t["rect"].set_color(Color(0.3, 0.3, 0.3))
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

# Unlike _nearest_enemy, this has no range cap — used so melee troops can
# always see and walk toward a target even before it's in attack range.
func _nearest_enemy_anywhere(from: Vector2) -> Dictionary:
	var nearest = {}
	var nearest_dist = INF
	for e in enemies:
		if e["hp"] <= 0: continue
		var d = from.distance_to(e["pos"])
		if d < nearest_dist:
			nearest_dist = d
			nearest = e
	return nearest

# Shared logic for melee troops (Knight, Rogue): walk toward the nearest
# enemy if out of range, attack if in range. Mirrors how enemies already
# behave, so both sides actively close the distance and engage.
func _melee_engage(t: Dictionary, delta: float, attack_range: float, move_speed: float,
		dmg: int, attack_speed_mult: float) -> void:
	var target = _nearest_enemy_anywhere(t["pos"])
	if target.is_empty(): return

	var dist = t["pos"].distance_to(target["pos"])
	if dist <= attack_range:
		t["attack_t"] -= delta
		if t["attack_t"] <= 0:
			_damage_enemy(target, dmg, t)
			t["attack_t"] = t["attack_interval"] * attack_speed_mult
	else:
		var dir = (target["pos"] - t["pos"]).normalized()
		# Move Speed stat boosts closing speed — most meaningful here on
		# melee units, since this is the path that actually needs to close
		# distance; ranged/stationary units rarely hit this branch at all.
		var effective_speed = move_speed * (1.0 + t.get("move_speed_bonus", 0.0))
		t["pos"] += dir * effective_speed * delta
		# Keep troop inside the battlefield bounds
		t["pos"].x = clamp(t["pos"].x, BASE_X + 10, FIELD_W - 20)
		t["pos"].y = clamp(t["pos"].y, 10, FIELD_H - 130)

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
			# Detect an attack firing by watching for attack_t resetting to
			# a high value — purely cosmetic, doesn't touch combat logic.
			if e["rect"] is UnitSprite:
				var prev = e.get("_prev_attack_t", 0.0)
				if e["attack_t"] > prev + 0.3:
					e["rect"].play_attack()
				e["_prev_attack_t"] = e["attack_t"]
				e["rect"].face(Vector2(-1, 0))   # enemies face left toward the base
		if is_instance_valid(e["hp_bar"]):
			e["hp_bar"].position = e["pos"] - Vector2(e["sz"]/2, e["sz"]/2 + 7)
		if is_instance_valid(e["hp_bar_bg"]):
			e["hp_bar_bg"].position = e["pos"] - Vector2(e["sz"]/2, e["sz"]/2 + 7)
		if is_instance_valid(e.get("type_lbl")):
			e["type_lbl"].position = e["pos"] - Vector2(e["sz"]/2 + 4, e["sz"]/2 + 22)

	for t in placed_troops:
		if t["hp"] <= 0: continue
		var sz = t["sz"]
		if is_instance_valid(t["rect"]):
			t["rect"].position = t["pos"] - Vector2(sz/2, sz/2)
			if t["rect"] is UnitSprite:
				var prev = t.get("_prev_attack_t", 0.0)
				if t["attack_t"] > prev + 0.3:
					t["rect"].play_attack()
				t["_prev_attack_t"] = t["attack_t"]
				t["rect"].face(Vector2(1, 0))   # troops face right toward enemies
		if is_instance_valid(t["hp_bar"]):
			t["hp_bar"].position = t["pos"] - Vector2(sz/2, sz/2 + 7)
		if is_instance_valid(t["hp_bar_bg"]):
			t["hp_bar_bg"].position = t["pos"] - Vector2(sz/2, sz/2 + 7)
		if t.has("label") and is_instance_valid(t["label"]):
			t["label"].position = t["pos"] - Vector2(20, sz/2 + 14)

# -------------------------------------------------------
# HUD
# -------------------------------------------------------
func _refresh_hud() -> void:
	if hud_wave:
		hud_wave.text = battle_title
	if hud_base_hp:
		hud_base_hp.text = "Base HP: %d / %d" % [base_hp, base_max_hp]
		var col = Color(0.9,0.2,0.2) if base_hp < base_max_hp * 0.3 else Color(0.4,0.7,1.0)
		hud_base_hp.add_theme_color_override("font_color", col)

func _set_status(msg: String) -> void:
	if hud_status: hud_status.text = msg

func _on_begin_battle_pressed() -> void:
	if battle_active: return
	battle_started = true
	_set_status("Charge!")

# Writes each placed troop's HP at the end of this battle back to their
# persistent TroopData, so wounds carry over outside of battle. Troops
# never drop below 1 HP here — they can be reduced to "down" (0 HP) for
# the rest of THIS fight, but the persisted result is always at least 1,
# matching the no-permanent-death design. Healing back up from there
# costs food, handled separately in Management.
func _persist_troop_hp() -> void:
	for t in placed_troops:
		var troop: TroopData = t["troop"]
		var max_hp = t["max_hp"]
		var final_hp = max(1, t["hp"])
		# Store as an absolute value scaled back against the troop's real
		# (unbuffed-by-this-battle) max, in case Forge/Shrine inflated
		# max_hp for this fight specifically.
		var real_max = troop.get_max_hp()
		var pct = float(final_hp) / max(1, max_hp)
		troop.current_hp = max(1, int(real_max * pct))

func _on_retreat() -> void:
	_persist_troop_hp()
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
	_persist_troop_hp()
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
	_persist_troop_hp()

	# Losing a defense of your home zone (zone 0) specifically is a real
	# campaign-ending event, distinct from any other lost fight. Skip the
	# normal autosave here so the player's last save still reflects the
	# state BEFORE this loss — otherwise "load last save" would just
	# reload the same defeat, making it a meaningless option.
	var capital_has_fallen = battle_zone_id == 0 and not is_conquering

	if capital_has_fallen:
		_show_capital_fallen_screen()
		return

	if battle_zone_id >= 0:
		PlayerInventory.last_battle_result = "lost"
		PlayerInventory.last_battle_zone = battle_zone_id
		PlayerInventory.last_battle_was_conquest = is_conquering

	SaveManager.save_game()
	_show_end_screen(false)

# Shown specifically when your home zone falls — a real campaign-ending
# event, but gentler than a hard game over: the player can reload their
# last save (rewinding to before this loss) or start a fresh campaign,
# rather than being stuck with no path forward.
func _show_capital_fallen_screen() -> void:
	var overlay = CanvasLayer.new()
	add_child(overlay)

	var bg = ColorRect.new()
	bg.color = Color(0, 0, 0, 0.85)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(bg)

	var panel = PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	overlay.add_child(panel)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	panel.add_child(vbox)

	var title = Label.new()
	title.text = "YOUR CAPITAL HAS FALLEN"
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(0.9, 0.2, 0.2))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var sub = Label.new()
	sub.text = "Without your home zone, the campaign cannot continue."
	sub.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(sub)

	var load_btn = Button.new()
	load_btn.text = "Load Last Save"
	load_btn.tooltip_text = "Reload your save from before this defeat"
	load_btn.custom_minimum_size = Vector2(240, 44)
	load_btn.pressed.connect(func():
		SaveManager.load_game()
		get_tree().change_scene_to_file("res://scenes/world_map.tscn"))
	vbox.add_child(load_btn)

	var new_game_btn = Button.new()
	new_game_btn.text = "Start New Campaign"
	new_game_btn.custom_minimum_size = Vector2(240, 44)
	new_game_btn.pressed.connect(func():
		get_tree().change_scene_to_file("res://scenes/new_game_screen.tscn"))
	vbox.add_child(new_game_btn)

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
	sub.text = "The battle is won!" if won else "Your base has fallen."
	sub.add_theme_color_override("font_color", Color(0.8,0.8,0.8))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(sub)

	var btn = Button.new()
	btn.text = "Return to Map" if battle_zone_id >= 0 else "Back to Management"
	btn.custom_minimum_size = Vector2(220, 44)
	btn.pressed.connect(_on_return)
	vbox.add_child(btn)
