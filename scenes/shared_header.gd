extends RefCounted
class_name SharedHeader

const SCREEN_SETTINGS := "settings"
const SCREEN_WORLD_MAP := "world_map"
const SCREEN_MANAGEMENT := "management"
const SCREEN_RECRUIT := "recruit"
const SCREEN_GEAR_SHOP := "gear_shop"
const SCREEN_TALENTS := "talents"
const SCREEN_DUNGEON := "dungeon"

const CONTROL_TIME_LABEL := "time_label"
const CONTROL_DIFF_LABEL := "difficulty_label"
const CONTROL_RESOURCES_LABEL := "resources_label"
const CONTROL_NOTIFICATION_LABEL := "notification_label"
const CONTROL_PAUSE_BUTTON := "pause_button"
const CONTROL_SPEED_LABEL := "speed_label"
const CONTROL_SPEED_SLIDER := "speed_slider"

const BUTTONS := [
	{"id": SCREEN_SETTINGS, "name": "SettingsButton", "label": "Settings", "compact": "Settings"},
	{"id": SCREEN_WORLD_MAP, "name": "WorldMapButton", "label": "World Map", "compact": "Map"},
	{"id": SCREEN_MANAGEMENT, "name": "ManagementButton", "label": "Management", "compact": "Mgmt"},
	{"id": SCREEN_RECRUIT, "name": "RecruitButton", "label": "Recruit", "compact": "Recruit"},
	{"id": SCREEN_GEAR_SHOP, "name": "GearShopButton", "label": "Gear Shop", "compact": "Shop"},
	{"id": SCREEN_TALENTS, "name": "TalentsButton", "label": "Talents", "compact": "Talents"},
	{"id": SCREEN_DUNGEON, "name": "DungeonButton", "label": "Dungeon", "compact": "Dungeon"},
]

static func add_fixed(root: Node, current_screen: String, height: float = 40.0, compact: bool = true) -> Dictionary:
	var header = add_fixed_bar(root, height)
	return populate(header, current_screen, height - 8.0, compact)

static func add_fixed_bar(root: Node, height: float = 40.0) -> HBoxContainer:
	var layer = CanvasLayer.new()
	layer.name = "SharedHeaderLayer"
	layer.layer = 80
	root.add_child(layer)

	var panel = PanelContainer.new()
	panel.name = "SharedHeaderPanel"
	panel.anchor_left = 0.0
	panel.anchor_top = 0.0
	panel.anchor_right = 1.0
	panel.anchor_bottom = 0.0
	panel.offset_left = 0.0
	panel.offset_top = 0.0
	panel.offset_right = 0.0
	panel.offset_bottom = height
	panel.custom_minimum_size = Vector2(0, height)
	layer.add_child(panel)

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.08, 0.11, 0.97)
	style.border_color = Color(0.24, 0.27, 0.34)
	style.set_border_width(SIDE_BOTTOM, 1)
	panel.add_theme_stylebox_override("panel", style)

	var margin = MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 4)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 4)
	panel.add_child(margin)

	var header = HBoxContainer.new()
	header.name = "SharedHeader"
	header.add_theme_constant_override("separation", 8)
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(header)
	return header

static func add_to(parent: BoxContainer, current_screen: String, height: float = 44.0, compact: bool = false) -> Dictionary:
	var header = HBoxContainer.new()
	header.name = "SharedHeader"
	header.add_theme_constant_override("separation", 8)
	parent.add_child(header)
	return populate(header, current_screen, height, compact)

static func populate(header: BoxContainer, current_screen: String, height: float = 44.0, compact: bool = false) -> Dictionary:
	var buttons := populate_left(header, current_screen, height, compact)
	add_time_controls(header, buttons, height)
	append_settings(header, buttons, current_screen, height, compact)
	return buttons

static func populate_left(header: BoxContainer, current_screen: String, height: float = 44.0, compact: bool = false) -> Dictionary:
	var buttons := {}
	for spec in BUTTONS:
		if spec["id"] == SCREEN_SETTINGS:
			continue
		if spec["id"] == current_screen:
			continue
		var btn = _make_button(spec, height, compact)
		header.add_child(btn)
		buttons[spec["id"]] = btn

	return buttons

static func append_settings(header: BoxContainer, buttons: Dictionary, current_screen: String, height: float = 44.0, compact: bool = false) -> void:
	if current_screen != SCREEN_SETTINGS:
		var spacer = Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		header.add_child(spacer)

		for spec in BUTTONS:
			if spec["id"] != SCREEN_SETTINGS:
				continue
			var btn = _make_button(spec, height, compact)
			header.add_child(btn)
			buttons[spec["id"]] = btn

static func add_time_controls(header: BoxContainer, controls: Dictionary, height: float = 32.0) -> void:
	var divider = VSeparator.new()
	header.add_child(divider)

	var time_label = Label.new()
	time_label.name = "MapTimeLabel"
	time_label.custom_minimum_size = Vector2(100, 0)
	time_label.add_theme_font_size_override("font_size", 14)
	time_label.add_theme_color_override("font_color", Color(0.7, 0.9, 0.7))
	header.add_child(time_label)
	controls[CONTROL_TIME_LABEL] = time_label

	var diff_label = Label.new()
	diff_label.name = "MapDifficultyLabel"
	diff_label.custom_minimum_size = Vector2(64, 0)
	diff_label.add_theme_font_size_override("font_size", 13)
	header.add_child(diff_label)
	controls[CONTROL_DIFF_LABEL] = diff_label

	var resources_label = Label.new()
	resources_label.name = "MapResourcesLabel"
	resources_label.custom_minimum_size = Vector2(92, 0)
	resources_label.add_theme_font_size_override("font_size", 13)
	resources_label.add_theme_color_override("font_color", Color(0.9, 0.8, 0.4))
	header.add_child(resources_label)
	controls[CONTROL_RESOURCES_LABEL] = resources_label

	var notification_label = Label.new()
	notification_label.name = "MapNotificationLabel"
	notification_label.custom_minimum_size = Vector2(52, 0)
	notification_label.add_theme_font_size_override("font_size", 13)
	notification_label.add_theme_color_override("font_color", Color(1, 0.5, 0.3))
	header.add_child(notification_label)
	controls[CONTROL_NOTIFICATION_LABEL] = notification_label

	var pause_btn = Button.new()
	pause_btn.name = "MapPauseButton"
	pause_btn.custom_minimum_size = Vector2(36, height)
	pause_btn.tooltip_text = "Pause or resume map time"
	pause_btn.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
	header.add_child(pause_btn)
	controls[CONTROL_PAUSE_BUTTON] = pause_btn

	var speed_label = Label.new()
	speed_label.name = "MapSpeedLabel"
	speed_label.custom_minimum_size = Vector2(34, 0)
	speed_label.add_theme_font_size_override("font_size", 12)
	speed_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	header.add_child(speed_label)
	controls[CONTROL_SPEED_LABEL] = speed_label

	var speed_slider = HSlider.new()
	speed_slider.name = "MapSpeedSlider"
	speed_slider.min_value = 1.0
	speed_slider.max_value = 5.0
	speed_slider.step = 0.5
	speed_slider.value = PlayerInventory.map_time_speed
	speed_slider.custom_minimum_size = Vector2(70, 0)
	speed_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	speed_slider.tooltip_text = "Map time speed"
	header.add_child(speed_slider)
	controls[CONTROL_SPEED_SLIDER] = speed_slider

	var update_controls := func():
		_refresh_time_controls(time_label, diff_label, resources_label, pause_btn, speed_label, speed_slider)

	pause_btn.pressed.connect(func():
		PlayerInventory.map_is_paused = not PlayerInventory.map_is_paused
		update_controls.call()
		if PlayerInventory.tutorial_active:
			TutorialRouter.advance_step("map_pause"))
	speed_slider.value_changed.connect(func(value: float):
		PlayerInventory.map_time_speed = value
		update_controls.call())

	var refresh_timer = Timer.new()
	refresh_timer.name = "MapHeaderRefreshTimer"
	refresh_timer.wait_time = 0.25
	refresh_timer.autostart = true
	refresh_timer.timeout.connect(update_controls)
	header.add_child(refresh_timer)
	update_controls.call()

static func _make_button(spec: Dictionary, height: float, compact: bool) -> Button:
	var btn = Button.new()
	btn.name = spec["name"]
	btn.text = spec["compact"] if compact else spec["label"]
	var width := 130.0
	if compact:
		width = 86.0 if spec["id"] == SCREEN_SETTINGS else 72.0
	btn.custom_minimum_size = Vector2(width, height)
	btn.tooltip_text = spec["label"]
	btn.add_theme_font_size_override("font_size", 13 if compact else 15)
	_wire_button(btn, spec["id"])
	return btn

static func _refresh_time_controls(time_label: Label, diff_label: Label, resources_label: Label, pause_btn: Button, speed_label: Label, speed_slider: HSlider) -> void:
	var total_secs := int(PlayerInventory.map_elapsed_seconds)
	var mins := total_secs / 60
	var secs := total_secs % 60
	time_label.text = ("⏸ " if PlayerInventory.map_is_paused else "") + "Day %d, %02d:%02d" % [(mins / 60) + 1, mins % 60, secs]

	var col = {"Easy": Color(0.3, 0.9, 0.3), "Normal": Color(0.4, 0.7, 1.0),
		"Hard": Color(1.0, 0.65, 0.1), "Nightmare": Color(0.9, 0.2, 0.2)}
	diff_label.text = "[%s]" % PlayerInventory.difficulty
	diff_label.add_theme_color_override("font_color", col.get(PlayerInventory.difficulty, Color.WHITE))

	resources_label.text = "🌾%d 🪙%d" % [int(PlayerInventory.resources.get("food", 0)), int(PlayerInventory.resources.get("gold", 0))]
	pause_btn.text = "▶" if PlayerInventory.map_is_paused else "⏸"
	speed_label.text = "%.1fx" % PlayerInventory.map_time_speed
	if not is_equal_approx(float(speed_slider.value), PlayerInventory.map_time_speed):
		speed_slider.set_value_no_signal(PlayerInventory.map_time_speed)

static func _wire_button(btn: Button, target: String) -> void:
	match target:
		SCREEN_SETTINGS:
			btn.pressed.connect(func():
				AdminPanel._open_settings())
		SCREEN_WORLD_MAP:
			btn.pressed.connect(func():
				_go_to("res://scenes/world_map.tscn"))
		SCREEN_MANAGEMENT:
			btn.pressed.connect(func():
				_go_to("res://scenes/management_screen.tscn"))
		SCREEN_RECRUIT:
			btn.pressed.connect(func():
				if PlayerInventory.tutorial_active:
					TutorialRouter.advance_step("recruit_intro")
				_go_to("res://scenes/recruit_screen.tscn"))
		SCREEN_GEAR_SHOP:
			btn.pressed.connect(func():
				_go_to("res://scenes/gear_shop_screen.tscn"))
		SCREEN_TALENTS:
			btn.pressed.connect(func():
				if PlayerInventory.tutorial_active:
					TutorialRouter.advance_step("talents_intro")
				_go_to("res://scenes/talent_tree_screen.tscn"))
		SCREEN_DUNGEON:
			btn.pressed.connect(func():
				if PlayerInventory.tutorial_active:
					TutorialRouter.advance_step("dungeon_send")
					_go_to("res://scenes/tutorial_dungeon.tscn")
					return
				PlayerInventory.current_dungeon_zone_id = -1
				PlayerInventory.current_dungeon_zone_type = "dungeon"
				PlayerInventory.set_meta("dungeon_picker_destination", "res://scenes/action_dungeon.tscn")
				_go_to("res://scenes/dungeon_picker_screen.tscn"))

static func _go_to(path: String) -> void:
	SaveManager.save_game()
	var tree := Engine.get_main_loop() as SceneTree
	if tree:
		tree.change_scene_to_file(path)
