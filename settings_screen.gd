extends Control

# -------------------------------------------------------
# Settings Screen — display options now, audio later. Persisted
# separately from the game save (settings.cfg via ConfigFile), since
# display preferences belong to the player/device, not to a specific
# campaign save.
# -------------------------------------------------------

const CONFIG_PATH = "user://settings.cfg"

const RESOLUTION_PRESETS = [
	Vector2i(1280, 720),
	Vector2i(1600, 900),
	Vector2i(1920, 1080),
]

var width_field: LineEdit
var height_field: LineEdit
var fullscreen_check: CheckBox
var borderless_check: CheckBox
var confirm_dispose_check: CheckBox
var damage_numbers_check: CheckBox
var status_label: Label
var return_target: String = "res://scenes/world_map.tscn"
var close_as_overlay: bool = false
var _ui_updating: bool = false   # guard against recursive checkbox signals

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	offset_left = 0
	offset_top = 0
	offset_right = 0
	offset_bottom = 0
	mouse_filter = Control.MOUSE_FILTER_STOP

	# Remember which screen to return to, so Settings can be opened from
	# anywhere without hardcoding a single "back" destination.
	if not close_as_overlay and PlayerInventory.settings_return_scene != "":
		return_target = PlayerInventory.settings_return_scene

	_build_ui()
	_load_current_into_fields()

func _build_ui() -> void:
	var bg = ColorRect.new()
	bg.color = Color(0, 0, 0, 0.62) if close_as_overlay else Color(0.07, 0.08, 0.10)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)

	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var panel = PanelContainer.new()
	center.add_child(panel)

	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.10, 0.11, 0.14, 0.98)
	panel_style.border_color = Color(0.32, 0.35, 0.42)
	panel_style.set_border_width_all(1)
	panel_style.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel", panel_style)

	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	panel.add_child(margin)

	var available_size = get_viewport_rect().size
	var popup_width = min(560.0, max(360.0, available_size.x - 48.0))
	var popup_height = min(720.0, max(280.0, available_size.y - 80.0))

	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(popup_width, popup_height)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_ALWAYS
	scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	margin.add_child(scroll)

	var outer = VBoxContainer.new()
	outer.custom_minimum_size = Vector2(max(300.0, popup_width - 38.0), 0)
	outer.add_theme_constant_override("separation", 14)
	scroll.add_child(outer)

	var title = Label.new()
	title.text = "Settings"
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	outer.add_child(title)

	outer.add_child(HSeparator.new())

	# --- Display ---
	var display_label = Label.new()
	display_label.text = "Display"
	display_label.add_theme_font_size_override("font_size", 16)
	display_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	outer.add_child(display_label)

	# Match Screen — fills a windowed window to the device's actual resolution
	var screen_res = DisplayServer.screen_get_size()
	var match_btn = Button.new()
	match_btn.text = "Match Screen  (%d × %d)" % [screen_res.x, screen_res.y]
	match_btn.custom_minimum_size = Vector2(0, 36)
	match_btn.add_theme_color_override("font_color", Color(0.4, 1.0, 0.6))
	match_btn.pressed.connect(func():
		_on_preset_pressed(screen_res))
	outer.add_child(match_btn)

	var preset_label = Label.new()
	preset_label.text = "Common presets:"
	preset_label.add_theme_font_size_override("font_size", 12)
	outer.add_child(preset_label)

	var preset_hbox = HBoxContainer.new()
	preset_hbox.add_theme_constant_override("separation", 8)
	outer.add_child(preset_hbox)
	for res in RESOLUTION_PRESETS:
		var btn = Button.new()
		btn.text = "%dx%d" % [res.x, res.y]
		btn.custom_minimum_size = Vector2(0, 32)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(_on_preset_pressed.bind(res))
		preset_hbox.add_child(btn)

	var custom_label = Label.new()
	custom_label.text = "Custom resolution:"
	custom_label.add_theme_font_size_override("font_size", 12)
	outer.add_child(custom_label)

	var custom_hbox = HBoxContainer.new()
	custom_hbox.add_theme_constant_override("separation", 8)
	outer.add_child(custom_hbox)

	width_field = LineEdit.new()
	width_field.placeholder_text = "Width"
	width_field.custom_minimum_size = Vector2(100, 0)
	custom_hbox.add_child(width_field)

	var x_label = Label.new()
	x_label.text = "x"
	custom_hbox.add_child(x_label)

	height_field = LineEdit.new()
	height_field.placeholder_text = "Height"
	height_field.custom_minimum_size = Vector2(100, 0)
	custom_hbox.add_child(height_field)

	var apply_custom_btn = Button.new()
	apply_custom_btn.text = "Apply"
	apply_custom_btn.pressed.connect(_on_apply_custom_resolution)
	custom_hbox.add_child(apply_custom_btn)

	var fullscreen_hbox = HBoxContainer.new()
	fullscreen_hbox.add_theme_constant_override("separation", 8)
	outer.add_child(fullscreen_hbox)

	fullscreen_check = CheckBox.new()
	fullscreen_check.toggled.connect(_on_fullscreen_toggled)
	fullscreen_hbox.add_child(fullscreen_check)

	var fullscreen_label = Label.new()
	fullscreen_label.text = "Fullscreen  (exclusive)"
	fullscreen_hbox.add_child(fullscreen_label)

	var borderless_hbox = HBoxContainer.new()
	borderless_hbox.add_theme_constant_override("separation", 8)
	outer.add_child(borderless_hbox)

	borderless_check = CheckBox.new()
	borderless_check.toggled.connect(_on_borderless_toggled)
	borderless_hbox.add_child(borderless_check)

	var borderless_label = Label.new()
	borderless_label.text = "Borderless Windowed  (fills screen, no title bar)"
	borderless_hbox.add_child(borderless_label)

	var hint = Label.new()
	hint.text = "Tip: when windowed, you can also drag the window's edges or corners to resize freely."
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	outer.add_child(hint)

	outer.add_child(HSeparator.new())

	# --- Gameplay ---
	var gameplay_label = Label.new()
	gameplay_label.text = "Gameplay"
	gameplay_label.add_theme_font_size_override("font_size", 16)
	gameplay_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	outer.add_child(gameplay_label)

	var confirm_hbox = HBoxContainer.new()
	confirm_hbox.add_theme_constant_override("separation", 8)
	outer.add_child(confirm_hbox)

	confirm_dispose_check = CheckBox.new()
	confirm_dispose_check.button_pressed = PlayerInventory.confirm_before_disposing_gear
	confirm_dispose_check.toggled.connect(_on_confirm_dispose_toggled)
	confirm_hbox.add_child(confirm_dispose_check)

	var confirm_label = Label.new()
	confirm_label.text = "Always confirm before selling or salvaging gear"
	confirm_hbox.add_child(confirm_label)

	var damage_hbox = HBoxContainer.new()
	damage_hbox.add_theme_constant_override("separation", 8)
	outer.add_child(damage_hbox)

	damage_numbers_check = CheckBox.new()
	damage_numbers_check.button_pressed = PlayerInventory.show_damage_numbers
	damage_numbers_check.toggled.connect(_on_damage_numbers_toggled)
	damage_hbox.add_child(damage_numbers_check)

	var damage_label = Label.new()
	damage_label.text = "Show damage numbers in action dungeons"
	damage_hbox.add_child(damage_label)

	outer.add_child(HSeparator.new())

	# --- Controls ---
	var controls_label = Label.new()
	controls_label.text = "Controls"
	controls_label.add_theme_font_size_override("font_size", 16)
	controls_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	outer.add_child(controls_label)

	var mobile_hbox = HBoxContainer.new()
	mobile_hbox.add_theme_constant_override("separation", 8)
	outer.add_child(mobile_hbox)

	var mobile_check = CheckBox.new()
	mobile_check.button_pressed = PlayerInventory.mobile_mode
	mobile_check.toggled.connect(_on_mobile_mode_toggled)
	mobile_hbox.add_child(mobile_check)

	var mobile_label = Label.new()
	mobile_label.text = "Mobile Mode  (shows on-screen D-pad in dungeons)"
	mobile_hbox.add_child(mobile_label)

	outer.add_child(HSeparator.new())

	# --- Audio (placeholder for when sound is added) ---
	var audio_label = Label.new()
	audio_label.text = "Audio"
	audio_label.add_theme_font_size_override("font_size", 16)
	audio_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	outer.add_child(audio_label)

	var audio_hint = Label.new()
	audio_hint.text = "No sound in the game yet — volume controls will appear here once that's added."
	audio_hint.add_theme_font_size_override("font_size", 11)
	audio_hint.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
	audio_hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	outer.add_child(audio_hint)

	outer.add_child(HSeparator.new())

	status_label = Label.new()
	status_label.text = ""
	status_label.add_theme_font_size_override("font_size", 12)
	status_label.add_theme_color_override("font_color", Color(0.6, 0.9, 0.6))
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	outer.add_child(status_label)

	var back_btn = Button.new()
	back_btn.text = "Close" if close_as_overlay else "Back"
	back_btn.custom_minimum_size = Vector2(0, 36)
	back_btn.pressed.connect(_on_back_pressed)
	outer.add_child(back_btn)

func _load_current_into_fields() -> void:
	var current_size = DisplayServer.window_get_size()
	width_field.text = str(current_size.x)
	height_field.text = str(current_size.y)
	fullscreen_check.button_pressed = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	borderless_check.button_pressed = DisplayServer.window_get_flag(DisplayServer.WINDOW_FLAG_BORDERLESS)

func _on_preset_pressed(res: Vector2i) -> void:
	_apply_resolution(res)
	width_field.text = str(res.x)
	height_field.text = str(res.y)

func _on_apply_custom_resolution() -> void:
	if not width_field.text.is_valid_int() or not height_field.text.is_valid_int():
		_set_status("Width and height must both be whole numbers.")
		return
	var w = int(width_field.text)
	var h = int(height_field.text)
	if w < 640 or h < 480:
		_set_status("Resolution must be at least 640x480.")
		return
	_apply_resolution(Vector2i(w, h))

func _apply_resolution(res: Vector2i) -> void:
	_ui_updating = true
	if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		fullscreen_check.button_pressed = false
	if DisplayServer.window_get_flag(DisplayServer.WINDOW_FLAG_BORDERLESS):
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
		borderless_check.button_pressed = false
	_ui_updating = false
	DisplayServer.window_set_size(res)
	_center_window()
	_save_settings()
	_set_status("Resolution set to %dx%d." % [res.x, res.y])

func _on_fullscreen_toggled(is_on: bool) -> void:
	if _ui_updating: return
	if is_on:
		_ui_updating = true
		borderless_check.button_pressed = false
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
		_ui_updating = false
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		_set_status("Fullscreen enabled.")
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		_center_window()
		_set_status("Windowed mode enabled.")
	_save_settings()

func _on_borderless_toggled(is_on: bool) -> void:
	if _ui_updating: return
	if is_on:
		_ui_updating = true
		fullscreen_check.button_pressed = false
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		_ui_updating = false
		var screen = DisplayServer.screen_get_size()
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
		DisplayServer.window_set_size(screen)
		DisplayServer.window_set_position(Vector2i.ZERO)
		width_field.text = str(screen.x)
		height_field.text = str(screen.y)
		_set_status("Borderless windowed enabled.")
	else:
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
		_center_window()
		_set_status("Windowed mode enabled.")
	_save_settings()

func _center_window() -> void:
	var screen_size = DisplayServer.screen_get_size()
	var window_size = DisplayServer.window_get_size()
	DisplayServer.window_set_position((screen_size - window_size) / 2)

func _on_confirm_dispose_toggled(is_on: bool) -> void:
	PlayerInventory.confirm_before_disposing_gear = is_on
	_save_settings()

func _on_damage_numbers_toggled(is_on: bool) -> void:
	PlayerInventory.show_damage_numbers = is_on
	_save_settings()

func _on_mobile_mode_toggled(is_on: bool) -> void:
	PlayerInventory.mobile_mode = is_on
	_save_settings()
	_set_status("Mobile mode %s — takes effect next time you enter a dungeon." % ("enabled" if is_on else "disabled"))

func _save_settings() -> void:
	var config = ConfigFile.new()
	config.set_value("display", "width", DisplayServer.window_get_size().x)
	config.set_value("display", "height", DisplayServer.window_get_size().y)
	config.set_value("display", "fullscreen", DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN)
	config.set_value("display", "borderless", DisplayServer.window_get_flag(DisplayServer.WINDOW_FLAG_BORDERLESS))
	config.set_value("gameplay", "confirm_before_disposing_gear", PlayerInventory.confirm_before_disposing_gear)
	config.set_value("gameplay", "show_damage_numbers", PlayerInventory.show_damage_numbers)
	config.set_value("controls", "mobile_mode", PlayerInventory.mobile_mode)
	config.save(CONFIG_PATH)

func _set_status(msg: String) -> void:
	if status_label:
		status_label.text = msg

func _on_back_pressed() -> void:
	if close_as_overlay:
		queue_free()
		return
	get_tree().change_scene_to_file(return_target)
