extends Control

# -------------------------------------------------------
# Shop Screen — spend Food/Gold (interchangeable) to recruit
# a new random unit. Stats roll with small variance, like gear.
# -------------------------------------------------------

var resource_label: Label = null
var status_label: Label = null

func _ready() -> void:
	_build_ui()

func _build_ui() -> void:
	var bg = ColorRect.new()
	bg.color = Color(0.07, 0.07, 0.10)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var scroll = ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(scroll)

	var margin = MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	scroll.add_child(margin)

	var outer = VBoxContainer.new()
	outer.add_theme_constant_override("separation", 14)
	margin.add_child(outer)

	# Header
	var title = Label.new()
	title.text = "SHOP"
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
	outer.add_child(title)

	resource_label = Label.new()
	resource_label.add_theme_font_size_override("font_size", 15)
	resource_label.add_theme_color_override("font_color", Color(0.8, 0.9, 0.8))
	outer.add_child(resource_label)
	_refresh_resource_label()

	status_label = Label.new()
	status_label.add_theme_font_size_override("font_size", 13)
	status_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	outer.add_child(status_label)

	var sep1 = HSeparator.new()
	outer.add_child(sep1)

	# --- RECRUIT SECTION ---
	var recruit_header = Label.new()
	recruit_header.text = "Recruit a New Unit"
	recruit_header.add_theme_font_size_override("font_size", 18)
	recruit_header.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
	outer.add_child(recruit_header)

	var recruit_desc = Label.new()
	recruit_desc.text = "Adds a random unit to your roster. Stats roll with small variance, like gear."
	recruit_desc.add_theme_font_size_override("font_size", 12)
	recruit_desc.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	recruit_desc.autowrap_mode = TextServer.AUTOWRAP_WORD
	outer.add_child(recruit_desc)

	var recruit_btn = Button.new()
	var rcost = SaveManager.RECRUIT_COST
	recruit_btn.text = "Recruit Random Unit  (🌾%d + 🪙%d, or any combination)" % [rcost["food"], rcost["gold"]]
	recruit_btn.custom_minimum_size = Vector2(0, 48)
	recruit_btn.add_theme_font_size_override("font_size", 14)
	recruit_btn.add_theme_color_override("font_color", Color(0.4, 0.9, 0.4))
	recruit_btn.pressed.connect(_on_recruit_pressed)
	outer.add_child(recruit_btn)

	var sep2 = HSeparator.new()
	outer.add_child(sep2)

	# Back button
	var back_btn = Button.new()
	back_btn.text = "Back to Management"
	back_btn.custom_minimum_size = Vector2(220, 44)
	back_btn.pressed.connect(func():
		get_tree().change_scene_to_file("res://scenes/management_screen.tscn"))
	outer.add_child(back_btn)

func _refresh_resource_label() -> void:
	resource_label.text = "🌾 Food: %d      🪙 Gold: %d      (combined: %d)" % [
		PlayerInventory.resources.get("food", 0),
		PlayerInventory.resources.get("gold", 0),
		PlayerInventory.get_total_resources(),
	]

func _on_recruit_pressed() -> void:
	var cost = SaveManager.RECRUIT_COST
	if not PlayerInventory.can_afford(cost):
		_set_status("Not enough resources. Need %d combined Food+Gold." % (cost["food"] + cost["gold"]))
		return

	PlayerInventory.spend_resources(cost)
	var new_troop = SaveManager.generate_recruit()
	PlayerInventory.troop_roster.append(new_troop)
	SaveManager.save_game()

	_set_status("Recruited a new %s!" % new_troop.get_type_name())
	_refresh_resource_label()

func _set_status(msg: String) -> void:
	if status_label: status_label.text = msg
