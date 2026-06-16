extends Control

# -------------------------------------------------------
# Dungeon Tier Picker — choose Quick / Standard / Deep Delve
# before launching either the Action Dungeon or Quick Dungeon.
# The destination scene is passed in via PlayerInventory so this
# screen can be reused for both entry points.
# -------------------------------------------------------

const TIERS = {
	"Quick": {
		"desc": "A short, low-risk run. Fewer rooms, weaker enemies, faster to finish.",
		"color": Color(0.5, 0.85, 1.0),
	},
	"Standard": {
		"desc": "A balanced run. Normal room count and enemy strength.",
		"color": Color(0.9, 0.8, 0.4),
	},
	"Deep Delve": {
		"desc": "A long, dangerous run. Many more rooms, much stronger enemies, better minimum gear quality, and a chance at an extra mini-boss.",
		"color": Color(0.9, 0.3, 0.3),
	},
}

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

	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
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

	var back_btn = Button.new()
	back_btn.text = "Back"
	back_btn.custom_minimum_size = Vector2(0, 40)
	back_btn.pressed.connect(func():
		get_tree().change_scene_to_file("res://scenes/management_screen.tscn"))
	outer.add_child(back_btn)

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
	PlayerInventory.dungeon_tier = tier_name
	SaveManager.save_game()
	get_tree().change_scene_to_file(destination_scene)
