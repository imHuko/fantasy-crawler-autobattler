extends Control

const SharedHeader := preload("res://scenes/shared_header.gd")

# -------------------------------------------------------
# Dungeon Tier Picker — choose Quick / Standard / Deep Delve
# before launching the Action Dungeon.
# The destination scene is passed in via PlayerInventory so this
# screen can be reused for both entry points.
# -------------------------------------------------------

const TIERS = {
	"Quick": {
		"desc": "A short, low-risk run. Weaker, less varied enemies — a good warm-up.",
		"color": Color(0.5, 0.85, 1.0),
	},
	"Standard": {
		"desc": "A balanced run. Normal enemy strength and variety.",
		"color": Color(0.9, 0.8, 0.4),
	},
	"Deep Delve": {
		"desc": "A long, dangerous run. Much stronger and more varied enemies, better minimum gear quality, and more frequent mini-bosses.",
		"color": Color(0.9, 0.3, 0.3),
	},
}

const DURATION_PRESETS = [5, 10, 15, 20]   # minutes

var selected_tier: String = ""
var duration_field: LineEdit

# Set by whoever opens this screen (management_screen.gd) before changing
# to it, so we know where to go once a tier is picked.
var destination_scene: String = "res://scenes/action_dungeon.tscn"

func _ready() -> void:
	if PlayerInventory.has_meta("dungeon_picker_destination"):
		destination_scene = PlayerInventory.get_meta("dungeon_picker_destination")
	_build_ui()

func _build_ui() -> void:
	var bg = ColorRect.new()
	bg.color = Color(0.07, 0.07, 0.10)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	SharedHeader.add_fixed(self, SharedHeader.SCREEN_DUNGEON)

	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.offset_top = 48
	add_child(center)

	var outer = VBoxContainer.new()
	outer.add_theme_constant_override("separation", 16)
	outer.custom_minimum_size = Vector2(460, 0)
	center.add_child(outer)

	var title = Label.new()
	title.text = "Choose Dungeon Difficulty"
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	outer.add_child(title)

	for tier_name in ["Quick", "Standard", "Deep Delve"]:
		outer.add_child(_make_tier_card(tier_name))

func _make_tier_card(tier_name: String) -> PanelContainer:
	var tier = TIERS[tier_name]
	var card = PanelContainer.new()

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	card.add_child(vbox)

	var name_lbl = Label.new()
	name_lbl.text = tier_name
	name_lbl.add_theme_font_size_override("font_size", 17)
	name_lbl.add_theme_color_override("font_color", tier["color"])
	vbox.add_child(name_lbl)

	var desc_lbl = Label.new()
	desc_lbl.text = tier["desc"]
	desc_lbl.add_theme_font_size_override("font_size", 12)
	desc_lbl.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75))
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(desc_lbl)

	var choose_btn = Button.new()
	choose_btn.text = "Select " + tier_name
	choose_btn.custom_minimum_size = Vector2(0, 40)
	choose_btn.add_theme_color_override("font_color", tier["color"])
	choose_btn.pressed.connect(_on_tier_selected.bind(tier_name))
	vbox.add_child(choose_btn)

	return card

func _on_tier_selected(tier_name: String) -> void:
	selected_tier = tier_name
	PlayerInventory.dungeon_tier = tier_name
	_show_duration_step()

func _show_duration_step() -> void:
	var overlay = CanvasLayer.new()
	add_child(overlay)

	var bg = ColorRect.new()
	bg.color = Color(0, 0, 0, 0.85)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(bg)

	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)

	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(380, 0)
	center.add_child(panel)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	panel.add_child(vbox)

	var title = Label.new()
	title.text = "How long do you want to survive?"
	title.add_theme_font_size_override("font_size", 19)
	title.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(title)

	var sub = Label.new()
	sub.text = "Longer runs mean more time for enemies to escalate and more chances at mini-bosses — but a longer commitment if things go wrong."
	sub.add_theme_font_size_override("font_size", 12)
	sub.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75))
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(sub)

	vbox.add_child(HSeparator.new())

	var preset_label = Label.new()
	preset_label.text = "Quick picks (minutes):"
	preset_label.add_theme_font_size_override("font_size", 12)
	vbox.add_child(preset_label)

	var preset_hbox = HBoxContainer.new()
	preset_hbox.add_theme_constant_override("separation", 8)
	vbox.add_child(preset_hbox)
	for mins in DURATION_PRESETS:
		var btn = Button.new()
		btn.text = "%d" % mins
		btn.custom_minimum_size = Vector2(0, 36)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(_on_duration_chosen.bind(float(mins * 60)))
		preset_hbox.add_child(btn)

	var custom_label = Label.new()
	custom_label.text = "Or enter a custom number of minutes:"
	custom_label.add_theme_font_size_override("font_size", 12)
	vbox.add_child(custom_label)

	var custom_hbox = HBoxContainer.new()
	custom_hbox.add_theme_constant_override("separation", 8)
	vbox.add_child(custom_hbox)

	duration_field = LineEdit.new()
	duration_field.placeholder_text = "e.g. 12"
	duration_field.custom_minimum_size = Vector2(0, 0)
	duration_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	custom_hbox.add_child(duration_field)

	var custom_btn = Button.new()
	custom_btn.text = "Start"
	custom_btn.custom_minimum_size = Vector2(80, 0)
	custom_btn.pressed.connect(_on_custom_duration_pressed)
	custom_hbox.add_child(custom_btn)

	var back_btn = Button.new()
	back_btn.text = "Back"
	back_btn.custom_minimum_size = Vector2(0, 36)
	back_btn.pressed.connect(func(): overlay.queue_free())
	vbox.add_child(back_btn)

func _on_custom_duration_pressed() -> void:
	if not duration_field.text.is_valid_float() and not duration_field.text.is_valid_int():
		return
	var mins = float(duration_field.text)
	if mins <= 0:
		return
	_on_duration_chosen(mins * 60.0)

func _on_duration_chosen(seconds: float) -> void:
	PlayerInventory.dungeon_duration_seconds = seconds
	SaveManager.save_game()
	get_tree().change_scene_to_file(destination_scene)
