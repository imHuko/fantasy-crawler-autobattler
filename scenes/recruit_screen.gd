extends Control

# -------------------------------------------------------
# Recruit Screen — spend Food/Gold (interchangeable) to recruit
# a new random unit. Stats roll with small variance, like gear.
# (Selling and upgrading gear lives in its own screen — see
# gear_shop_screen.gd.)
# -------------------------------------------------------

var resource_label: Label = null
var status_label: Label = null
var recruit_choices_container: VBoxContainer = null
var tutorial_back_btn: Button = null   # "Back to Management" button — exposed so the nav reminder can highlight it

const GENERATED_TROOP_FRAME_FOLDER := "res://assets/sprites/generated_troops_fixed96/frames/"

func get_tutorial_target(target_id: String) -> Control:
	match target_id:
		"mgmt_button": return tutorial_back_btn   # nav reminder: "Head to Management" → highlight Back to Management
		_: return null

func _ready() -> void:
	_build_ui()
	TutorialRouter.resolve_current_step(self)

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
	outer.custom_minimum_size = Vector2(420, 0)
	margin.add_child(outer)

	# Header
	var title = Label.new()
	title.text = "RECRUIT"
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

	var recruit_desc = Label.new()
	recruit_desc.text = "Adds a random unit to your roster. Stats roll with small variance, like gear."
	recruit_desc.add_theme_font_size_override("font_size", 12)
	recruit_desc.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	recruit_desc.autowrap_mode = TextServer.AUTOWRAP_WORD
	outer.add_child(recruit_desc)

	var recruit_btn = Button.new()
	var rcost = SaveManager.get_effective_recruit_cost()
	var choice_count = SaveManager.get_recruit_choice_count()
	var btn_label = "Recruit  (🌾🪙 %d combined)" % rcost
	if choice_count > 1:
		btn_label = "Recruit — choose 1 of %d  (🌾🪙 %d combined)" % [choice_count, rcost]
	recruit_btn.text = btn_label
	recruit_btn.custom_minimum_size = Vector2(0, 48)
	recruit_btn.add_theme_font_size_override("font_size", 14)
	recruit_btn.add_theme_color_override("font_color", Color(0.4, 0.9, 0.4))
	recruit_btn.pressed.connect(_on_recruit_pressed)
	outer.add_child(recruit_btn)

	recruit_choices_container = VBoxContainer.new()
	recruit_choices_container.add_theme_constant_override("separation", 8)
	outer.add_child(recruit_choices_container)

	var sep2 = HSeparator.new()
	outer.add_child(sep2)

	# Back button
	var back_btn = Button.new()
	back_btn.text = "Back to Management"
	back_btn.custom_minimum_size = Vector2(220, 44)
	back_btn.pressed.connect(func():
		get_tree().change_scene_to_file("res://scenes/management_screen.tscn"))
	outer.add_child(back_btn)
	tutorial_back_btn = back_btn

func _refresh_resource_label() -> void:
	resource_label.text = "🌾 Food: %d      🪙 Gold: %d      (combined: %d)" % [
		PlayerInventory.resources.get("food", 0),
		PlayerInventory.resources.get("gold", 0),
		PlayerInventory.get_total_resources(),
	]

func _on_recruit_pressed() -> void:
	var cost_total = SaveManager.get_effective_recruit_cost()
	var cost = {"food": 0, "gold": cost_total}
	if not PlayerInventory.can_afford(cost):
		_set_status("Not enough resources. Need %d combined Food+Gold." % cost_total)
		return

	PlayerInventory.spend_resources(cost)
	SaveManager.save_game()

	# Roll the candidate pool, ensuring no duplicate types when possible
	var choice_count = SaveManager.get_recruit_choice_count()
	var candidates = []
	var seen_types = []
	var tries = 0
	while candidates.size() < choice_count and tries < choice_count * 6:
		tries += 1
		var t = SaveManager.generate_recruit()
		if t.troop_type in seen_types and tries < choice_count * 4:
			continue
		candidates.append(t)
		seen_types.append(t.troop_type)

	_show_recruit_choices(candidates)
	_refresh_resource_label()

func _show_recruit_choices(candidates: Array) -> void:
	for child in recruit_choices_container.get_children():
		child.queue_free()

	if candidates.size() == 1:
		_finalize_recruit(candidates[0])
		return

	var prompt = Label.new()
	prompt.text = "Choose one to add to your roster:"
	prompt.add_theme_font_size_override("font_size", 13)
	prompt.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	recruit_choices_container.add_child(prompt)

	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	recruit_choices_container.add_child(hbox)

	for troop in candidates:
		hbox.add_child(_make_candidate_card(troop))

func _make_candidate_card(troop: TroopData) -> PanelContainer:
	var card = PanelContainer.new()
	card.custom_minimum_size = Vector2(160, 0)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	card.add_child(vbox)

	var portrait_path = _troop_portrait_path(troop.get_type_name())
	var portrait_texture = _load_troop_portrait_texture(portrait_path)
	if portrait_texture != null:
		var portrait = TextureRect.new()
		portrait.texture = portrait_texture
		portrait.custom_minimum_size = Vector2(80, 80)
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		portrait.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		portrait.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		vbox.add_child(portrait)

	var name_lbl = Label.new()
	name_lbl.text = "%s [%s]" % [troop.troop_name, troop.get_type_name()]
	name_lbl.add_theme_font_size_override("font_size", 13)
	name_lbl.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
	vbox.add_child(name_lbl)

	var stats_lbl = Label.new()
	var s = troop.base_stats
	stats_lbl.text = "HP:%d ATK:%d\nDEF:%d SPD:%d" % [s.get("hp",0), s.get("attack",0), s.get("defense",0), s.get("speed",0)]
	stats_lbl.add_theme_font_size_override("font_size", 11)
	stats_lbl.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75))
	vbox.add_child(stats_lbl)

	var pick_btn = Button.new()
	pick_btn.text = "Recruit"
	pick_btn.custom_minimum_size = Vector2(0, 36)
	pick_btn.add_theme_color_override("font_color", Color(0.4, 0.9, 0.4))
	pick_btn.pressed.connect(_finalize_recruit.bind(troop))
	vbox.add_child(pick_btn)

	return card

func _troop_portrait_path(type_name: String) -> String:
	var key := type_name.to_lower()
	var generated_path := GENERATED_TROOP_FRAME_FOLDER + key + "/idle.png"
	if FileAccess.file_exists(generated_path):
		return generated_path
	return "res://assets/sprites/troops/%s.png" % key

func _load_troop_portrait_texture(path: String) -> Texture2D:
	if path.begins_with(GENERATED_TROOP_FRAME_FOLDER) and FileAccess.file_exists(path):
		var bytes = FileAccess.get_file_as_bytes(path)
		var image = Image.new()
		if image.load_png_from_buffer(bytes) == OK:
			return ImageTexture.create_from_image(image)
	var texture = load(path)
	return texture as Texture2D

func _finalize_recruit(troop: TroopData) -> void:
	PlayerInventory.troop_roster.append(troop)
	Telemetry.log_event("troop_recruited", {
		"type": troop.get_type_name(),
		"hp": troop.base_stats.get("hp", 0),
		"attack": troop.base_stats.get("attack", 0),
		"roster_size": PlayerInventory.troop_roster.size(),
		"stage": PlayerInventory.current_stage,
	})
	SaveManager.save_game()
	_set_status("Recruited a new %s!" % troop.get_type_name())
	for child in recruit_choices_container.get_children():
		child.queue_free()

func _set_status(msg: String) -> void:
	if status_label: status_label.text = msg
