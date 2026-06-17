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

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == TOGGLE_KEY and event.shift_pressed:
		_toggle_panel()

func _toggle_panel() -> void:
	if is_open:
		_close_panel()
	else:
		_open_panel()

func _close_panel() -> void:
	if overlay and is_instance_valid(overlay):
		overlay.queue_free()
	overlay = null
	is_open = false

func _open_panel() -> void:
	is_open = true
	overlay = CanvasLayer.new()
	overlay.layer = 100   # always render above whatever screen is active
	get_tree().root.add_child(overlay)

	var bg = ColorRect.new()
	bg.color = Color(0, 0, 0, 0.6)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(bg)

	var panel = PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	panel.position = Vector2(-340, 20)
	panel.custom_minimum_size = Vector2(320, 0)
	overlay.add_child(panel)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)

	var title = Label.new()
	title.text = "⚙ Admin Panel  (Shift+F9 to close)"
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", Color(1, 0.7, 0.2))
	vbox.add_child(title)

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

	status_label = Label.new()
	status_label.text = ""
	status_label.add_theme_font_size_override("font_size", 11)
	status_label.add_theme_color_override("font_color", Color(0.6, 0.9, 0.6))
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(status_label)

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
	PlayerInventory.dungeon_troop_id = ""   # falls back to the Hero
	PlayerInventory.dungeon_tier = "Standard"
	_close_panel()
	get_tree().change_scene_to_file("res://scenes/action_dungeon.tscn")

func _set_status(msg: String) -> void:
	if status_label:
		status_label.text = msg
