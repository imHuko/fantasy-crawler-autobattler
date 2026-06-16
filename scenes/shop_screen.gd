extends Control

# -------------------------------------------------------
# Shop Screen — spend Food/Gold (interchangeable) to recruit
# a new random unit. Stats roll with small variance, like gear.
# -------------------------------------------------------

var resource_label: Label = null
var status_label: Label = null
var recruit_choices_container: VBoxContainer = null
var sell_list_container: VBoxContainer = null
var sell_checkboxes: Dictionary = {}   # GearItem -> CheckBox

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
	var rcost = SaveManager.get_effective_recruit_cost()
	var choice_count = SaveManager.get_recruit_choice_count()
	var btn_label = "Recruit  (🌾🪙 %d combined)" % rcost
	if choice_count > 1:
		btn_label = "Recruit \\u2014 choose 1 of %d  (🌾🪙 %d combined)" % [choice_count, rcost]
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

	# --- SELL GEAR SECTION ---
	var sell_header = Label.new()
	sell_header.text = "Sell Gear"
	sell_header.add_theme_font_size_override("font_size", 18)
	sell_header.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
	outer.add_child(sell_header)

	var sell_desc = Label.new()
	sell_desc.text = "Sell unwanted gear for Gold. Value scales with rarity and quality tier."
	sell_desc.add_theme_font_size_override("font_size", 12)
	sell_desc.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	sell_desc.autowrap_mode = TextServer.AUTOWRAP_WORD
	outer.add_child(sell_desc)

	# Quick bulk-sell by rarity threshold
	var threshold_hbox = HBoxContainer.new()
	threshold_hbox.add_theme_constant_override("separation", 8)
	outer.add_child(threshold_hbox)

	for rarity_name in ["COMMON", "RARE", "EPIC"]:
		var bulk_btn = Button.new()
		bulk_btn.text = "Sell all %s and below" % rarity_name.capitalize()
		bulk_btn.custom_minimum_size = Vector2(0, 36)
		bulk_btn.add_theme_font_size_override("font_size", 11)
		bulk_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bulk_btn.pressed.connect(_on_bulk_sell_threshold.bind(rarity_name))
		threshold_hbox.add_child(bulk_btn)

	# Individual checkbox selection for precise control
	sell_checkboxes.clear()
	sell_list_container = VBoxContainer.new()
	sell_list_container.add_theme_constant_override("separation", 4)
	outer.add_child(sell_list_container)
	_populate_sell_list()

	var sell_selected_btn = Button.new()
	sell_selected_btn.text = "Sell Selected"
	sell_selected_btn.custom_minimum_size = Vector2(0, 40)
	sell_selected_btn.add_theme_color_override("font_color", Color(0.9, 0.8, 0.4))
	sell_selected_btn.pressed.connect(_on_sell_selected)
	outer.add_child(sell_selected_btn)

	var sep3 = HSeparator.new()
	outer.add_child(sep3)

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

func _finalize_recruit(troop: TroopData) -> void:
	PlayerInventory.troop_roster.append(troop)
	SaveManager.save_game()
	_set_status("Recruited a new %s!" % troop.get_type_name())
	for child in recruit_choices_container.get_children():
		child.queue_free()

func _set_status(msg: String) -> void:
	if status_label: status_label.text = msg

# -------------------------------------------------------
# Sell Gear
# -------------------------------------------------------
func _populate_sell_list() -> void:
	for child in sell_list_container.get_children():
		child.queue_free()
	sell_checkboxes.clear()

	if PlayerInventory.gear_inventory.is_empty():
		var empty = Label.new()
		empty.text = "No gear to sell."
		empty.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		sell_list_container.add_child(empty)
		return

	for gear in PlayerInventory.gear_inventory:
		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)

		var cb = CheckBox.new()
		sell_checkboxes[gear] = cb
		row.add_child(cb)

		var lbl = Label.new()
		lbl.text = "%s [%s%s] \\u2014 %d🪙" % [
			gear.item_name, gear.get_rarity_name(),
			(" " + gear.get_quality_name()) if gear.get_quality_name() != "" else "",
			gear.get_sell_price(),
		]
		lbl.add_theme_font_size_override("font_size", 12)
		lbl.add_theme_color_override("font_color", gear.get_display_color())
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(lbl)

		sell_list_container.add_child(row)

func _on_bulk_sell_threshold(max_rarity: String) -> void:
	var rarity_order = ["COMMON", "RARE", "EPIC", "LEGENDARY"]
	var max_idx = rarity_order.find(max_rarity)

	var to_sell = []
	for gear in PlayerInventory.gear_inventory:
		if rarity_order.find(gear.get_rarity_name()) <= max_idx:
			to_sell.append(gear)

	if to_sell.is_empty():
		_set_status("Nothing to sell at or below %s." % max_rarity.capitalize())
		return

	var total_gold = 0
	for gear in to_sell:
		total_gold += gear.get_sell_price()
		PlayerInventory.remove_gear(gear)

	PlayerInventory.resources["gold"] += total_gold
	SaveManager.save_game()
	_set_status("Sold %d items for %d Gold." % [to_sell.size(), total_gold])
	_refresh_resource_label()
	_populate_sell_list()

func _on_sell_selected() -> void:
	var to_sell = []
	for gear in sell_checkboxes:
		if sell_checkboxes[gear].button_pressed:
			to_sell.append(gear)

	if to_sell.is_empty():
		_set_status("No items selected.")
		return

	var total_gold = 0
	for gear in to_sell:
		total_gold += gear.get_sell_price()
		PlayerInventory.remove_gear(gear)

	PlayerInventory.resources["gold"] += total_gold
	SaveManager.save_game()
	_set_status("Sold %d items for %d Gold." % [to_sell.size(), total_gold])
	_refresh_resource_label()
	_populate_sell_list()
