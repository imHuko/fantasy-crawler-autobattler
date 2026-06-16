extends Control

# -------------------------------------------------------
# Recruit Choice Screen — shown when the tutorial is skipped.
# No dungeon crawl, just a direct pick between 2 random units
# to fill out the starting roster before heading to the map.
# -------------------------------------------------------

func _ready() -> void:
	_build_ui()

func _build_ui() -> void:
	var bg = ColorRect.new()
	bg.color = Color(0.07, 0.07, 0.10)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var center = VBoxContainer.new()
	center.set_anchors_preset(Control.PRESET_CENTER)
	center.add_theme_constant_override("separation", 16)
	center.position -= Vector2(220, 140)
	center.custom_minimum_size = Vector2(440, 0)
	add_child(center)

	var title = Label.new()
	title.text = "Choose Your Second Unit"
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(title)

	var sub = Label.new()
	sub.text = "Two recruits are available to join your roster alongside your Knight."
	sub.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD
	center.add_child(sub)

	# Roll 2 distinct random recruits
	var t1 = SaveManager.generate_recruit()
	var t2 = SaveManager.generate_recruit()
	var tries = 0
	while t2.troop_type == t1.troop_type and tries < 10:
		t2 = SaveManager.generate_recruit()
		tries += 1

	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 16)
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(hbox)

	_add_recruit_card(hbox, t1)
	_add_recruit_card(hbox, t2)

func _add_recruit_card(parent: HBoxContainer, troop: TroopData) -> void:
	var card = PanelContainer.new()
	card.custom_minimum_size = Vector2(190, 0)
	parent.add_child(card)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	card.add_child(vbox)

	var name_lbl = Label.new()
	name_lbl.text = troop.troop_name
	name_lbl.add_theme_font_size_override("font_size", 16)
	name_lbl.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(name_lbl)

	var type_lbl = Label.new()
	type_lbl.text = "[%s]" % troop.get_type_name()
	type_lbl.add_theme_font_size_override("font_size", 12)
	type_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(type_lbl)

	var stats_lbl = Label.new()
	stats_lbl.text = "HP:%d ATK:%d\nDEF:%d SPD:%d" % [
		troop.base_stats.get("hp", 0), troop.base_stats.get("attack", 0),
		troop.base_stats.get("defense", 0), troop.base_stats.get("speed", 0)
	]
	stats_lbl.add_theme_font_size_override("font_size", 11)
	stats_lbl.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75))
	stats_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(stats_lbl)

	var choose_btn = Button.new()
	choose_btn.text = "Recruit"
	choose_btn.custom_minimum_size = Vector2(0, 38)
	choose_btn.add_theme_color_override("font_color", Color(0.4, 0.9, 0.4))
	choose_btn.pressed.connect(_on_recruit_chosen.bind(troop))
	vbox.add_child(choose_btn)

func _on_recruit_chosen(troop: TroopData) -> void:
	PlayerInventory.troop_roster.append(troop)
	PlayerInventory.tutorial_complete = true
	SaveManager.save_game()
	get_tree().change_scene_to_file("res://scenes/world_map.tscn")
