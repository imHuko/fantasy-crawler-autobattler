extends Control

# -------------------------------------------------------
# Main Menu — entry point, load/new game
# -------------------------------------------------------

const SAVE_PATH = "user://savegame.json"

@onready var title_label: Label
@onready var stage_label: Label

func _ready() -> void:
	_build_ui()

func _build_ui() -> void:
	var bg = ColorRect.new()
	bg.color = Color(0.06, 0.06, 0.10)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var center = VBoxContainer.new()
	center.set_anchors_preset(Control.PRESET_CENTER)
	center.add_theme_constant_override("separation", 16)
	center.position -= Vector2(150, 180)
	center.custom_minimum_size = Vector2(300, 360)
	add_child(center)

	# Title
	var title = Label.new()
	title.text = "GEAR CRAWLER"
	title.add_theme_font_size_override("font_size", 38)
	title.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(title)

	var subtitle = Label.new()
	subtitle.text = "dungeon • gear • defend"
	subtitle.add_theme_font_size_override("font_size", 13)
	subtitle.add_theme_color_override("font_color", Color(0.5, 0.5, 0.6))
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(subtitle)

	var sep = HSeparator.new()
	center.add_child(sep)

	# Save info label
	stage_label = Label.new()
	stage_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stage_label.add_theme_font_size_override("font_size", 12)
	stage_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	center.add_child(stage_label)
	_refresh_save_label()

	# Continue button (only if save exists)
	if _save_exists():
		var continue_btn = Button.new()
		continue_btn.text = "Continue"
		continue_btn.custom_minimum_size = Vector2(260, 48)
		continue_btn.add_theme_font_size_override("font_size", 18)
		continue_btn.add_theme_color_override("font_color", Color(0.4, 0.9, 0.4))
		continue_btn.pressed.connect(_on_continue)
		center.add_child(continue_btn)

	# New Game button
	var new_btn = Button.new()
	new_btn.text = "New Game" if _save_exists() else "Start Game"
	new_btn.custom_minimum_size = Vector2(260, 48)
	new_btn.add_theme_font_size_override("font_size", 18)
	new_btn.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
	new_btn.pressed.connect(_on_new_game)
	center.add_child(new_btn)

	if _save_exists():
		var delete_btn = Button.new()
		delete_btn.text = "Delete Save"
		delete_btn.custom_minimum_size = Vector2(260, 36)
		delete_btn.add_theme_font_size_override("font_size", 13)
		delete_btn.add_theme_color_override("font_color", Color(0.6, 0.3, 0.3))
		delete_btn.pressed.connect(_on_delete_save)
		center.add_child(delete_btn)

func _refresh_save_label() -> void:
	if _save_exists():
		var data = _load_raw()
		stage_label.text = "Save found — Stage %d  |  %d troops  |  %d gear items" % [
			data.get("stage", 1),
			data.get("troop_count", 0),
			data.get("gear_count", 0),
		]
	else:
		stage_label.text = "No save file found"

func _on_continue() -> void:
	SaveManager.load_game()
	get_tree().change_scene_to_file("res://scenes/management_screen.tscn")

func _on_new_game() -> void:
	get_tree().change_scene_to_file("res://scenes/new_game_screen.tscn")

func _on_delete_save() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)
	get_tree().reload_current_scene()

func _save_exists() -> bool:
	return FileAccess.file_exists(SAVE_PATH)

func _load_raw() -> Dictionary:
	if not FileAccess.file_exists(SAVE_PATH):
		return {}
	var f = FileAccess.open(SAVE_PATH, FileAccess.READ)
	var data = JSON.parse_string(f.get_as_text())
	f.close()
	return data if data else {}
