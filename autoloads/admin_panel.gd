extends Node

# -------------------------------------------------------
# Admin / Debug Panel — a testing tool, not part of the real game.
# Toggle with F9 (configurable below) from any screen. Lets you set
# resources, jump stages, force-trigger a wilds attack (map screen
# only), fully heal your roster, unlock every talent, and jump straight
# into a standalone defense battle or dungeon run for quick testing.
#
# SETUP REQUIRED: this is an autoload, so it must be registered once in
# Project > Project Settings > Autoload — add this script with the name
# "AdminPanel", same as your other autoloads (PlayerInventory, etc).
# -------------------------------------------------------

const TOGGLE_KEY = KEY_F9   # combined with Shift below, since F9 alone is a Godot editor/debugger shortcut

var overlay: CanvasLayer = null
var is_open: bool = false
var status_label: Label = null

# -------------------------------------------------------
# Sandbox state — persists across panel open/close so you
# can tweak the config, close, reopen, and adjust without
# losing your setup between launches.
# -------------------------------------------------------
var defense_sandbox: Dictionary = {
	"enabled": false,
	"wave_counts": { "BOSS": 0, "TANK": 0, "MELEE": 3, "RANGED": 2, "ROGUE": 0, "CHARGER": 0, "BUFFER": 0 },
	"hp_mult": 1.0,
	"dmg_mult": 1.0,
}

var dungeon_sandbox: Dictionary = {
	"enabled": false,
	"hp_mult": 1.0,
	"dmg_mult": 1.0,
	"speed_mult": 1.0,
	"scaling_mult": 1.0,   # difficulty progression speed: 2.0 = minute 5 feels like minute 10
	"spawn_weights": { "MELEE": 0, "BULL": 0, "CHARGER": 0, "RANGED": 0, "BUFFER": 0 },
}

# Builds the flat wave Array from wave_counts for defense_scene.gd to read.
func get_defense_sandbox_wave() -> Array:
	var wave = []
	for archetype in ["BOSS", "TANK", "MELEE", "RANGED", "ROGUE", "CHARGER", "BUFFER"]:
		var count = defense_sandbox["wave_counts"].get(archetype, 0)
		for i in range(count):
			wave.append(archetype)
	wave.shuffle()
	return wave

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == TOGGLE_KEY and event.shift_pressed:
		_toggle_panel()

func _toggle_panel() -> void:
	if is_open:
		_close_panel()
	else:
		_open_panel()

func _close_panel() -> void:
	Engine.time_scale = 1.0
	if overlay and is_instance_valid(overlay):
		overlay.queue_free()
	overlay = null
	is_open = false

func _open_panel() -> void:
	is_open = true
	overlay = CanvasLayer.new()
	overlay.layer = 100
	get_tree().root.add_child(overlay)

	var bg = ColorRect.new()
	bg.color = Color(0, 0, 0, 0.6)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(bg)

	var panel = PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	panel.position = Vector2(-400, 20)
	panel.custom_minimum_size = Vector2(375, 0)
	overlay.add_child(panel)

	# ScrollContainer so the panel can hold all sandbox controls without
	# running off the bottom of the screen.
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 560)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_ALWAYS
	panel.add_child(scroll)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox)

	var title = Label.new()
	title.text = "⚙ Admin Panel  (Shift+F9 to close)"
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", Color(1, 0.7, 0.2))
	vbox.add_child(title)

	vbox.add_child(HSeparator.new())

	# Detect current scene — sandbox live controls go FIRST so they're
	# immediately visible without scrolling when you're inside a battle.
	var scene = get_tree().current_scene
	var in_defense = scene and scene.has_method("sandbox_place_troop")
	var in_dungeon = scene and scene.scene_file_path.ends_with("action_dungeon.tscn")

	if in_defense:
		_add_section_label(vbox, "Defense Sandbox  [LIVE]")
		_build_defense_live_controls(vbox, scene)
		vbox.add_child(HSeparator.new())
	elif in_dungeon:
		_add_section_label(vbox, "Dungeon Sandbox  [LIVE]")
		_build_dungeon_live_controls(vbox, scene)
		vbox.add_child(HSeparator.new())

	_add_section_label(vbox, "Simulation Speed")
	_add_timescale_row(vbox)

	vbox.add_child(HSeparator.new())

	_add_section_label(vbox, "Resources")
	_add_resource_row(vbox, "Food", "food")
	_add_resource_row(vbox, "Gold", "gold")

	vbox.add_child(HSeparator.new())

	_add_section_label(vbox, "Progression")
	_add_stage_row(vbox)
	_add_button(vbox, "Unlock All Talents", _on_unlock_all_talents)
	_add_button(vbox, "Fully Heal All Troops", _on_heal_all_troops)

	vbox.add_child(HSeparator.new())

	_add_section_label(vbox, "Map (only works while on the World Map)")
	_add_button(vbox, "Force Attack on Random Owned Zone", _on_force_attack)

	vbox.add_child(HSeparator.new())

	_add_section_label(vbox, "Jump to Combat")
	_add_button(vbox, "Standalone Defense Battle (full roster)", _on_jump_defense)
	_add_button(vbox, "Action Dungeon (as Hero)", _on_jump_dungeon)

	vbox.add_child(HSeparator.new())

	if not in_defense:
		_add_section_label(vbox, "Defense Sandbox")
		_build_defense_prelaunch(vbox)
		vbox.add_child(HSeparator.new())

	if not in_dungeon:
		_add_section_label(vbox, "Dungeon Sandbox")
		_build_dungeon_prelaunch(vbox)
		vbox.add_child(HSeparator.new())

	status_label = Label.new()
	status_label.text = ""
	status_label.add_theme_font_size_override("font_size", 11)
	status_label.add_theme_color_override("font_color", Color(0.6, 0.9, 0.6))
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(status_label)

# -------------------------------------------------------
# Defense — live (in-scene) controls
# -------------------------------------------------------
func _build_defense_live_controls(vbox: VBoxContainer, scene: Node) -> void:
	var ally_lbl = Label.new()
	ally_lbl.text = "Add Ally (drops at random friendly position)"
	ally_lbl.add_theme_font_size_override("font_size", 11)
	ally_lbl.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
	vbox.add_child(ally_lbl)

	var ally_row = HBoxContainer.new()
	ally_row.add_theme_constant_override("separation", 4)
	vbox.add_child(ally_row)
	for type_name in ["KNIGHT", "ARCHER", "MAGE", "HEALER", "ROGUE"]:
		var btn = Button.new()
		btn.text = type_name.capitalize()
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.custom_minimum_size = Vector2(0, 28)
		btn.add_theme_font_size_override("font_size", 11)
		btn.pressed.connect(func(): scene.sandbox_place_troop(type_name))
		ally_row.add_child(btn)

	_add_button(vbox, "Repeat Wave (same composition, full reset)", func(): scene.sandbox_repeat_wave())

	var base_hp_lbl = Label.new()
	base_hp_lbl.text = "Set Base HP"
	base_hp_lbl.add_theme_font_size_override("font_size", 11)
	base_hp_lbl.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
	vbox.add_child(base_hp_lbl)

	var base_hp_row = HBoxContainer.new()
	base_hp_row.add_theme_constant_override("separation", 4)
	vbox.add_child(base_hp_row)

	var cur_lbl = Label.new()
	cur_lbl.text = "(%d)" % scene.get("base_hp")
	cur_lbl.custom_minimum_size = Vector2(40, 0)
	cur_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cur_lbl.add_theme_font_size_override("font_size", 12)

	for preset in [["→ 1", 1], ["→ Half", -1], ["→ Full", -2]]:
		var btn = Button.new()
		btn.text = preset[0]
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.custom_minimum_size = Vector2(0, 28)
		btn.add_theme_font_size_override("font_size", 12)
		btn.pressed.connect(func():
			var max_hp = scene.get("base_max_hp")
			var val = preset[1]
			if val == -1: val = max(1, max_hp / 2)
			elif val == -2: val = max_hp
			scene.sandbox_set_base_hp(val)
			cur_lbl.text = "(%d)" % scene.get("base_hp"))
		base_hp_row.add_child(btn)

	var minus_btn = Button.new()
	minus_btn.text = "-5"
	minus_btn.custom_minimum_size = Vector2(36, 28)
	minus_btn.add_theme_font_size_override("font_size", 12)
	minus_btn.pressed.connect(func():
		scene.sandbox_set_base_hp(scene.get("base_hp") - 5)
		cur_lbl.text = "(%d)" % scene.get("base_hp"))
	base_hp_row.add_child(minus_btn)

	base_hp_row.add_child(cur_lbl)

	var plus_btn = Button.new()
	plus_btn.text = "+5"
	plus_btn.custom_minimum_size = Vector2(36, 28)
	plus_btn.add_theme_font_size_override("font_size", 12)
	plus_btn.pressed.connect(func():
		scene.sandbox_set_base_hp(scene.get("base_hp") + 5)
		cur_lbl.text = "(%d)" % scene.get("base_hp"))
	base_hp_row.add_child(plus_btn)

	vbox.add_child(HSeparator.new())

	var enemy_lbl = Label.new()
	enemy_lbl.text = "Spawn Enemy (drops into enemy zone)"
	enemy_lbl.add_theme_font_size_override("font_size", 11)
	enemy_lbl.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
	vbox.add_child(enemy_lbl)

	var enemy_row1 = HBoxContainer.new()
	enemy_row1.add_theme_constant_override("separation", 4)
	vbox.add_child(enemy_row1)
	for archetype in ["MELEE", "RANGED", "ROGUE", "TANK"]:
		var btn = Button.new()
		btn.text = archetype.capitalize()
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.custom_minimum_size = Vector2(0, 28)
		btn.add_theme_font_size_override("font_size", 11)
		btn.pressed.connect(func(): scene.sandbox_spawn_enemy(archetype))
		enemy_row1.add_child(btn)

	var enemy_row2 = HBoxContainer.new()
	enemy_row2.add_theme_constant_override("separation", 4)
	vbox.add_child(enemy_row2)
	for archetype in ["CHARGER", "BUFFER", "BOSS"]:
		var btn = Button.new()
		btn.text = archetype.capitalize()
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.custom_minimum_size = Vector2(0, 28)
		btn.add_theme_font_size_override("font_size", 11)
		btn.pressed.connect(func(): scene.sandbox_spawn_enemy(archetype))
		enemy_row2.add_child(btn)

# -------------------------------------------------------
# Defense — pre-launch config (not yet in a defense scene)
# -------------------------------------------------------
func _build_defense_prelaunch(vbox: VBoxContainer) -> void:
	var hint = Label.new()
	hint.text = "Launch a defense first — live Add Ally / Spawn Enemy buttons appear here once you're inside a battle."
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(hint)

	var def_enable_btn = Button.new()
	def_enable_btn.text = "Custom Wave on Launch: %s" % ("ON" if defense_sandbox["enabled"] else "OFF")
	def_enable_btn.add_theme_color_override("font_color",
		Color(0.4, 0.9, 0.4) if defense_sandbox["enabled"] else Color(0.7, 0.7, 0.7))
	def_enable_btn.pressed.connect(func():
		defense_sandbox["enabled"] = not defense_sandbox["enabled"]
		_close_panel(); _open_panel())
	vbox.add_child(def_enable_btn)

	for archetype in ["BOSS", "TANK", "MELEE", "RANGED", "ROGUE", "CHARGER", "BUFFER"]:
		_add_counter_row(vbox, archetype, defense_sandbox["wave_counts"], archetype, 0, 30)

	_add_float_row(vbox, "Enemy HP Mult", defense_sandbox, "hp_mult", 0.1, 10.0, 0.25)
	_add_float_row(vbox, "Enemy Dmg Mult", defense_sandbox, "dmg_mult", 0.1, 10.0, 0.25)

	var def_clear_btn = Button.new()
	def_clear_btn.text = "Clear Wave"
	def_clear_btn.pressed.connect(func():
		for k in defense_sandbox["wave_counts"]:
			defense_sandbox["wave_counts"][k] = 0
		_close_panel(); _open_panel())
	vbox.add_child(def_clear_btn)

	_add_button(vbox, "▶ Launch Defense with Custom Wave", func():
		defense_sandbox["enabled"] = true
		PlayerInventory.current_battle_zone = -1
		PlayerInventory.current_attack_force = 1.0
		PlayerInventory.conquering_zone = false
		_close_panel()
		get_tree().change_scene_to_file("res://scenes/defense_scene.tscn"))

# -------------------------------------------------------
# Dungeon — live (in-scene) controls
# -------------------------------------------------------
func _build_dungeon_live_controls(vbox: VBoxContainer, scene: Node) -> void:
	var class_lbl = Label.new()
	class_lbl.text = "Play As (swaps stats + art, keeps your gear/level)"
	class_lbl.add_theme_font_size_override("font_size", 11)
	class_lbl.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
	class_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(class_lbl)

	var class_row = HBoxContainer.new()
	class_row.add_theme_constant_override("separation", 4)
	vbox.add_child(class_row)
	for class_key in ["KNIGHT", "ARCHER", "MAGE", "HEALER", "ROGUE"]:
		var btn = Button.new()
		btn.text = class_key.capitalize()
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.custom_minimum_size = Vector2(0, 28)
		btn.add_theme_font_size_override("font_size", 11)
		if scene.has_method("sandbox_set_hero_class"):
			btn.pressed.connect(scene.sandbox_set_hero_class.bind(class_key))
		class_row.add_child(btn)

	vbox.add_child(HSeparator.new())

	_add_section_label(vbox, "Live Run Stats")

	var stats_lbl = Label.new()
	stats_lbl.add_theme_font_size_override("font_size", 11)
	stats_lbl.add_theme_color_override("font_color", Color(0.85, 0.95, 0.85))
	stats_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD

	var _refresh_stats = func():
		var s = scene.sandbox_get_run_stats()
		var lines = []
		lines.append("Min %.1f  |  %ds left  |  Lv %d  |  %d kills  |  %d enemies" % [
			s["minute"], s["remaining"], s["level"], s["kill_count"], s["enemy_count"]])
		lines.append("Scales — HP ×%.2f  DMG ×%.2f  SPD ×%.2f" % [
			s["hp_scale"], s["dmg_scale"], s["spd_scale"]])
		lines.append("Hero — %d/%d HP  |  %d ATK  |  %.0f SPD" % [
			s["hero_hp"], s["hero_max_hp"], s["hero_atk"], s["hero_spd"]])
		lines.append("─── Enemy stats (next spawn) ───")
		for arch in ["MELEE", "BULL", "CHARGER", "RANGED", "BUFFER"]:
			var a = s["archetypes"][arch]
			lines.append("  %-8s  HP %-4d  ATK %-3d  SPD %.0f" % [arch, a["hp"], a["atk"], a["spd"]])
		stats_lbl.text = "\n".join(lines)

	_refresh_stats.call()
	vbox.add_child(stats_lbl)
	_add_button(vbox, "Refresh Stats", func(): _refresh_stats.call())

	vbox.add_child(HSeparator.new())

	var skip_lbl = Label.new()
	skip_lbl.text = "Skip Time"
	skip_lbl.add_theme_font_size_override("font_size", 11)
	skip_lbl.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
	vbox.add_child(skip_lbl)

	var skip_row = HBoxContainer.new()
	skip_row.add_theme_constant_override("separation", 4)
	vbox.add_child(skip_row)
	for amount in [["+1 min", 60.0], ["+2 min", 120.0], ["+5 min", 300.0]]:
		var btn = Button.new()
		btn.text = amount[0]
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.custom_minimum_size = Vector2(0, 28)
		btn.add_theme_font_size_override("font_size", 12)
		btn.pressed.connect(func(): scene.sandbox_skip_time(amount[1]))
		skip_row.add_child(btn)

	_add_button(vbox, "Force Mini-Boss Spawn", func(): scene.sandbox_force_miniboss())
	_add_button(vbox, "Force Level-Up (open skill pick)", func(): scene.sandbox_force_levelup())

	vbox.add_child(HSeparator.new())

	var skill_lbl = Label.new()
	skill_lbl.text = "Apply Skill Directly  (stacks/max shown)"
	skill_lbl.add_theme_font_size_override("font_size", 11)
	skill_lbl.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
	vbox.add_child(skill_lbl)

	var grid = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 3)
	vbox.add_child(grid)

	var pool = scene.sandbox_get_skill_pool()
	for skill in pool:
		var sid   = skill["id"]
		var sname = skill["name"]
		var smax  = skill["max_stacks"]
		var btn = Button.new()
		var cur = scene.sandbox_get_skill_stacks(sid)
		btn.text = "%s (%d/%d)" % [sname, cur, smax]
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.custom_minimum_size = Vector2(0, 26)
		btn.add_theme_font_size_override("font_size", 10)
		btn.pressed.connect(func():
			scene.sandbox_apply_skill(sid)
			var new_ct = scene.sandbox_get_skill_stacks(sid)
			btn.text = "%s (%d/%d)" % [sname, new_ct, smax]
			btn.add_theme_color_override("font_color",
				Color(0.5, 0.5, 0.5) if new_ct >= smax else Color(1, 1, 1)))
		if cur >= smax:
			btn.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		grid.add_child(btn)

	vbox.add_child(HSeparator.new())

	var god_btn = Button.new()
	god_btn.text = "God Mode: %s" % ("ON" if scene.get("_sandbox_god_mode") else "OFF")
	god_btn.add_theme_color_override("font_color",
		Color(0.4, 0.9, 0.4) if scene.get("_sandbox_god_mode") else Color(0.7, 0.7, 0.7))
	god_btn.pressed.connect(func():
		var on = scene.sandbox_toggle_god_mode()
		god_btn.text = "God Mode: %s" % ("ON" if on else "OFF")
		god_btn.add_theme_color_override("font_color",
			Color(0.4, 0.9, 0.4) if on else Color(0.7, 0.7, 0.7)))
	vbox.add_child(god_btn)

	vbox.add_child(HSeparator.new())

	var hint = Label.new()
	hint.text = "Spawn weight changes take effect on the next wave. 0 = include in normal pool."
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(hint)

	for archetype in ["MELEE", "BULL", "CHARGER", "RANGED", "BUFFER"]:
		_add_counter_row(vbox, archetype, dungeon_sandbox["spawn_weights"], archetype, 0, 200)

	_add_float_row(vbox, "Enemy HP Mult", dungeon_sandbox, "hp_mult", 0.1, 20.0, 0.25)
	_add_float_row(vbox, "Enemy Dmg Mult", dungeon_sandbox, "dmg_mult", 0.1, 20.0, 0.25)
	_add_float_row(vbox, "Enemy Speed Mult", dungeon_sandbox, "speed_mult", 0.1, 5.0, 0.25)
	_add_float_row(vbox, "Progression Speed", dungeon_sandbox, "scaling_mult", 0.25, 5.0, 0.25)

	var reset_btn = Button.new()
	reset_btn.text = "Reset All to Default"
	reset_btn.pressed.connect(func():
		for k in dungeon_sandbox["spawn_weights"]:
			dungeon_sandbox["spawn_weights"][k] = 0
		dungeon_sandbox["hp_mult"] = 1.0
		dungeon_sandbox["dmg_mult"] = 1.0
		dungeon_sandbox["speed_mult"] = 1.0
		dungeon_sandbox["scaling_mult"] = 1.0
		_close_panel(); _open_panel())
	vbox.add_child(reset_btn)

# -------------------------------------------------------
# Dungeon — pre-launch config (not yet in dungeon)
# -------------------------------------------------------
func _build_dungeon_prelaunch(vbox: VBoxContainer) -> void:
	var hint = Label.new()
	hint.text = "Launch the dungeon first — live spawn weight controls appear here once you're inside a run."
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(hint)

	var dun_enable_btn = Button.new()
	dun_enable_btn.text = "Sandbox on Launch: %s" % ("ON" if dungeon_sandbox["enabled"] else "OFF")
	dun_enable_btn.add_theme_color_override("font_color",
		Color(0.4, 0.9, 0.4) if dungeon_sandbox["enabled"] else Color(0.7, 0.7, 0.7))
	dun_enable_btn.pressed.connect(func():
		dungeon_sandbox["enabled"] = not dungeon_sandbox["enabled"]
		_close_panel(); _open_panel())
	vbox.add_child(dun_enable_btn)

	_add_float_row(vbox, "Enemy HP Mult", dungeon_sandbox, "hp_mult", 0.1, 20.0, 0.25)
	_add_float_row(vbox, "Enemy Dmg Mult", dungeon_sandbox, "dmg_mult", 0.1, 20.0, 0.25)
	_add_float_row(vbox, "Enemy Speed Mult", dungeon_sandbox, "speed_mult", 0.1, 5.0, 0.25)
	_add_float_row(vbox, "Progression Speed", dungeon_sandbox, "scaling_mult", 0.25, 5.0, 0.25)

	for archetype in ["MELEE", "BULL", "CHARGER", "RANGED", "BUFFER"]:
		_add_counter_row(vbox, archetype, dungeon_sandbox["spawn_weights"], archetype, 0, 200)

	var reset_btn = Button.new()
	reset_btn.text = "Reset Weights to Default"
	reset_btn.pressed.connect(func():
		for k in dungeon_sandbox["spawn_weights"]:
			dungeon_sandbox["spawn_weights"][k] = 0
		_close_panel(); _open_panel())
	vbox.add_child(reset_btn)

	_add_button(vbox, "▶ Launch Dungeon with Sandbox", func():
		dungeon_sandbox["enabled"] = true
		PlayerInventory.dungeon_tier = "Standard"
		_close_panel()
		get_tree().change_scene_to_file("res://scenes/action_dungeon.tscn"))

func _add_timescale_row(parent: VBoxContainer) -> void:
	var hint = Label.new()
	hint.text = "Affects all scenes globally. Resets to 1× when panel is closed."
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	parent.add_child(hint)

	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	parent.add_child(row)

	var val_lbl = Label.new()
	val_lbl.text = "%.2f×" % Engine.time_scale
	val_lbl.custom_minimum_size = Vector2(44, 0)
	val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	val_lbl.add_theme_font_size_override("font_size", 13)

	for speed in [0.25, 0.5, 1.0, 2.0, 5.0]:
		var btn = Button.new()
		btn.text = ("%.2f" % speed).trim_suffix("0").trim_suffix("0").trim_suffix(".") + "×"
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.custom_minimum_size = Vector2(0, 28)
		btn.add_theme_font_size_override("font_size", 12)
		btn.pressed.connect(func():
			Engine.time_scale = speed
			val_lbl.text = "%.2f×" % speed)
		row.add_child(btn)

	row.add_child(val_lbl)

func _add_section_label(parent: VBoxContainer, text: String) -> void:
	var lbl = Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	parent.add_child(lbl)

func _add_button(parent: VBoxContainer, text: String, callback: Callable) -> void:
	var btn = Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(0, 30)
	btn.pressed.connect(callback)
	parent.add_child(btn)

# Integer counter row: label | [-] [value] [+]
# Reads/writes dict[key]. Clamps to [min_val, max_val].
func _add_counter_row(parent: VBoxContainer, label_text: String, dict: Dictionary, key: String, min_val: int, max_val: int) -> void:
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	parent.add_child(row)

	var lbl = Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size = Vector2(90, 0)
	lbl.add_theme_font_size_override("font_size", 12)
	row.add_child(lbl)

	var val_lbl = Label.new()
	val_lbl.text = str(dict.get(key, 0))
	val_lbl.custom_minimum_size = Vector2(36, 0)
	val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	val_lbl.add_theme_font_size_override("font_size", 12)

	var minus_btn = Button.new()
	minus_btn.text = "-"
	minus_btn.custom_minimum_size = Vector2(28, 26)
	minus_btn.pressed.connect(func():
		dict[key] = max(min_val, dict.get(key, 0) - 1)
		val_lbl.text = str(dict[key]))
	row.add_child(minus_btn)
	row.add_child(val_lbl)

	var plus_btn = Button.new()
	plus_btn.text = "+"
	plus_btn.custom_minimum_size = Vector2(28, 26)
	plus_btn.pressed.connect(func():
		dict[key] = min(max_val, dict.get(key, 0) + 1)
		val_lbl.text = str(dict[key]))
	row.add_child(plus_btn)

# Float row: label | [-] [value] [+] — steps by `step`
func _add_float_row(parent: VBoxContainer, label_text: String, dict: Dictionary, key: String, min_val: float, max_val: float, step: float) -> void:
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	parent.add_child(row)

	var lbl = Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size = Vector2(130, 0)
	lbl.add_theme_font_size_override("font_size", 12)
	row.add_child(lbl)

	var val_lbl = Label.new()
	val_lbl.text = "%.2f" % dict.get(key, 1.0)
	val_lbl.custom_minimum_size = Vector2(44, 0)
	val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	val_lbl.add_theme_font_size_override("font_size", 12)

	var minus_btn = Button.new()
	minus_btn.text = "-"
	minus_btn.custom_minimum_size = Vector2(28, 26)
	minus_btn.pressed.connect(func():
		dict[key] = snappedf(clamp(dict.get(key, 1.0) - step, min_val, max_val), 0.01)
		val_lbl.text = "%.2f" % dict[key])
	row.add_child(minus_btn)
	row.add_child(val_lbl)

	var plus_btn = Button.new()
	plus_btn.text = "+"
	plus_btn.custom_minimum_size = Vector2(28, 26)
	plus_btn.pressed.connect(func():
		dict[key] = snappedf(clamp(dict.get(key, 1.0) + step, min_val, max_val), 0.01)
		val_lbl.text = "%.2f" % dict[key])
	row.add_child(plus_btn)

func _add_resource_row(parent: VBoxContainer, label_text: String, resource_key: String) -> void:
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	parent.add_child(row)

	var lbl = Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size = Vector2(50, 0)
	row.add_child(lbl)

	var field = LineEdit.new()
	field.text = str(PlayerInventory.resources.get(resource_key, 0))
	field.custom_minimum_size = Vector2(80, 0)
	row.add_child(field)

	var set_btn = Button.new()
	set_btn.text = "Set"
	set_btn.pressed.connect(func():
		var val = int(field.text) if field.text.is_valid_int() else 0
		PlayerInventory.resources[resource_key] = max(0, val)
		_set_status("%s set to %d." % [label_text, val]))
	row.add_child(set_btn)

	var add_btn = Button.new()
	add_btn.text = "+1000"
	add_btn.pressed.connect(func():
		PlayerInventory.resources[resource_key] = PlayerInventory.resources.get(resource_key, 0) + 1000
		field.text = str(PlayerInventory.resources[resource_key])
		_set_status("%s +1000." % label_text))
	row.add_child(add_btn)

func _add_stage_row(parent: VBoxContainer) -> void:
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	parent.add_child(row)

	var lbl = Label.new()
	lbl.text = "Stage"
	lbl.custom_minimum_size = Vector2(50, 0)
	row.add_child(lbl)

	var field = LineEdit.new()
	field.text = str(PlayerInventory.current_stage)
	field.custom_minimum_size = Vector2(80, 0)
	row.add_child(field)

	var set_btn = Button.new()
	set_btn.text = "Set"
	set_btn.pressed.connect(func():
		var val = int(field.text) if field.text.is_valid_int() else 1
		PlayerInventory.current_stage = max(1, val)
		_set_status("Stage set to %d." % PlayerInventory.current_stage))
	row.add_child(set_btn)

	var add_btn = Button.new()
	add_btn.text = "+1"
	add_btn.pressed.connect(func():
		PlayerInventory.current_stage += 1
		field.text = str(PlayerInventory.current_stage)
		_set_status("Stage +1 -> %d." % PlayerInventory.current_stage))
	row.add_child(add_btn)

func _on_unlock_all_talents() -> void:
	for talent_id in TalentTreeData.NODES.keys():
		PlayerInventory.unlocked_talents[talent_id] = true
	_set_status("All %d talents unlocked." % TalentTreeData.NODES.size())

func _on_heal_all_troops() -> void:
	var count = 0
	for troop in PlayerInventory.troop_roster:
		troop.current_hp = troop.get_max_hp()
		count += 1
	_set_status("Fully healed %d troop(s)." % count)

func _on_force_attack() -> void:
	var map_scene = get_tree().current_scene
	if map_scene == null or not map_scene.has_method("_maybe_spawn_attack"):
		_set_status("Not on the World Map screen — can't force an attack from here.")
		return
	# Bypass the normal random chance/cooldown gating and force one
	# attack attempt right now, using the map's own targeting logic.
	if map_scene.has_method("force_admin_attack"):
		var result = map_scene.force_admin_attack()
		_set_status(result)
	else:
		_set_status("World Map doesn't support forced attacks yet.")

func _on_jump_defense() -> void:
	PlayerInventory.current_battle_zone = -1   # standalone test battle, full roster available
	PlayerInventory.current_attack_force = 1.0
	PlayerInventory.conquering_zone = false
	_close_panel()
	get_tree().change_scene_to_file("res://scenes/defense_scene.tscn")

func _on_jump_dungeon() -> void:
	PlayerInventory.dungeon_tier = "Standard"
	_close_panel()
	get_tree().change_scene_to_file("res://scenes/action_dungeon.tscn")

func _set_status(msg: String) -> void:
	if status_label:
		status_label.text = msg
