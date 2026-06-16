extends Control

# -------------------------------------------------------
# New Game Setup Screen
# Player name, difficulty, map seed
# -------------------------------------------------------

const DIFFICULTIES = {
	"Easy": {
		"desc": "Relaxed pace. Attacks are rare, telegraphed early, and only ever hit one zone at a time.",
		"attack_frequency": 0.3,
		"warning_turns": 4,
		"force_size": 0.6,
		"max_simultaneous_attacks": 1,
		"zone_count": 10,
		"color": Color(0.3, 0.9, 0.3),
	},
	"Normal": {
		"desc": "Balanced challenge. Moderate attack frequency, one zone at a time.\nRecommended for first playthrough.",
		"attack_frequency": 0.6,
		"warning_turns": 3,
		"force_size": 1.0,
		"max_simultaneous_attacks": 1,
		"zone_count": 13,
		"color": Color(0.4, 0.7, 1.0),
	},
	"Hard": {
		"desc": "Frequent attacks. Occasionally two zones threatened at once \u2014 you'll need to choose where to commit.",
		"attack_frequency": 1.0,
		"warning_turns": 3,
		"force_size": 1.3,
		"max_simultaneous_attacks": 2,
		"zone_count": 18,
		"color": Color(1.0, 0.65, 0.1),
	},
	"Nightmare": {
		"desc": "A larger world under constant pressure. Up to three zones can be threatened simultaneously \u2014 spreading your forces thin is a losing strategy.",
		"attack_frequency": 1.5,
		"warning_turns": 3,
		"force_size": 1.6,
		"max_simultaneous_attacks": 3,
		"zone_count": 24,
		"color": Color(0.9, 0.2, 0.2),
	},
}

var selected_difficulty: String = "Normal"
var player_name_field: LineEdit
var seed_field: LineEdit
var desc_label: Label
var diff_buttons: Dictionary = {}

func _ready() -> void:
	_build_ui()

func _build_ui() -> void:
	var bg = ColorRect.new()
	bg.color = Color(0.06, 0.06, 0.10)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var center = VBoxContainer.new()
	center.set_anchors_preset(Control.PRESET_CENTER)
	center.add_theme_constant_override("separation", 18)
	center.position -= Vector2(220, 260)
	center.custom_minimum_size = Vector2(440, 520)
	add_child(center)

	# Title
	var title = Label.new()
	title.text = "NEW GAME"
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(title)

	var sep1 = HSeparator.new()
	center.add_child(sep1)

	# Player name
	var name_label = Label.new()
	name_label.text = "Commander Name"
	name_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	center.add_child(name_label)

	player_name_field = LineEdit.new()
	player_name_field.placeholder_text = "Enter your name..."
	player_name_field.custom_minimum_size = Vector2(440, 38)
	player_name_field.add_theme_font_size_override("font_size", 15)
	center.add_child(player_name_field)

	var sep2 = HSeparator.new()
	center.add_child(sep2)

	# Difficulty
	var diff_label = Label.new()
	diff_label.text = "Difficulty"
	diff_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	center.add_child(diff_label)

	var diff_hbox = HBoxContainer.new()
	diff_hbox.add_theme_constant_override("separation", 6)
	center.add_child(diff_hbox)

	for diff_name in DIFFICULTIES:
		var btn = Button.new()
		btn.text = diff_name
		btn.custom_minimum_size = Vector2(100, 40)
		btn.add_theme_font_size_override("font_size", 14)
		btn.add_theme_color_override("font_color", DIFFICULTIES[diff_name]["color"])
		btn.pressed.connect(_on_difficulty_selected.bind(diff_name))
		diff_hbox.add_child(btn)
		diff_buttons[diff_name] = btn

	# Difficulty description
	desc_label = Label.new()
	desc_label.custom_minimum_size = Vector2(440, 52)
	desc_label.add_theme_font_size_override("font_size", 12)
	desc_label.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75))
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	center.add_child(desc_label)

	var sep3 = HSeparator.new()
	center.add_child(sep3)

	# Map seed
	var seed_hbox = HBoxContainer.new()
	center.add_child(seed_hbox)

	var seed_label = Label.new()
	seed_label.text = "Map Seed  "
	seed_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	seed_hbox.add_child(seed_label)

	var seed_hint = Label.new()
	seed_hint.text = "(leave blank for random)"
	seed_hint.add_theme_font_size_override("font_size", 11)
	seed_hint.add_theme_color_override("font_color", Color(0.45, 0.45, 0.45))
	seed_hbox.add_child(seed_hint)

	seed_field = LineEdit.new()
	seed_field.placeholder_text = "e.g. 42069"
	seed_field.custom_minimum_size = Vector2(440, 36)
	seed_field.add_theme_font_size_override("font_size", 14)
	center.add_child(seed_field)

	var sep4 = HSeparator.new()
	center.add_child(sep4)

	# Buttons row
	var btn_hbox = HBoxContainer.new()
	btn_hbox.add_theme_constant_override("separation", 12)
	center.add_child(btn_hbox)

	var back_btn = Button.new()
	back_btn.text = "Back"
	back_btn.custom_minimum_size = Vector2(140, 44)
	back_btn.add_theme_font_size_override("font_size", 15)
	back_btn.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/main_menu.tscn"))
	btn_hbox.add_child(back_btn)

	var start_btn = Button.new()
	start_btn.text = "Start Game  >"
	start_btn.custom_minimum_size = Vector2(280, 44)
	start_btn.add_theme_font_size_override("font_size", 16)
	start_btn.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
	start_btn.pressed.connect(_on_start)
	btn_hbox.add_child(start_btn)

	# Set default difficulty
	_on_difficulty_selected("Normal")

func _on_difficulty_selected(diff_name: String) -> void:
	selected_difficulty = diff_name
	desc_label.text = DIFFICULTIES[diff_name]["desc"]

	# Highlight selected button
	for name in diff_buttons:
		var btn = diff_buttons[name]
		if name == diff_name:
			btn.add_theme_color_override("font_color", Color(1, 1, 1))
			btn.add_theme_stylebox_override("normal", _make_highlight_style(DIFFICULTIES[name]["color"]))
		else:
			btn.add_theme_color_override("font_color", DIFFICULTIES[name]["color"])
			btn.remove_theme_stylebox_override("normal")

func _make_highlight_style(col: Color) -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = col.darkened(0.6)
	style.border_color = col
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	return style

func _on_start() -> void:
	var pname = player_name_field.text.strip_edges()
	if pname == "":
		pname = "Commander"

	# Parse seed
	var seed_text = seed_field.text.strip_edges()
	var map_seed = 0
	if seed_text != "":
		if seed_text.is_valid_int():
			map_seed = seed_text.to_int()
		else:
			# Hash the string so text seeds work too
			map_seed = seed_text.hash()
	else:
		map_seed = randi()

	# Store in PlayerInventory
	PlayerInventory.player_name = pname
	PlayerInventory.map_seed = map_seed
	PlayerInventory.difficulty = selected_difficulty
	PlayerInventory.difficulty_settings = DIFFICULTIES[selected_difficulty]

	SaveManager.new_game()
	get_tree().change_scene_to_file("res://scenes/tutorial_dungeon.tscn")
