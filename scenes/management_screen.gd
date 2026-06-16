extends Control

# -------------------------------------------------------
# Management Screen — fully code-built, no scene tree needed
# -------------------------------------------------------

const RARITY_COLORS = {
	"COMMON":    Color(0.75, 0.75, 0.75),
	"UNCOMMON":  Color(0.25, 0.85, 0.25),
	"RARE":      Color(0.25, 0.50, 1.00),
	"LEGENDARY": Color(1.00, 0.65, 0.10),
}

const SLOT_ICONS = {
	"WEAPON":    "Wpn",
	"ARMOR":     "Arm",
	"RING":      "Rng",
	"ACCESSORY": "Acc",
}

var selected_troop: TroopData = null
var selected_slot: String = ""
var selected_slot_button: Button = null

var troop_list: VBoxContainer
var gear_list: VBoxContainer
var status_label: Label
var set_bonus_label: Label

func _ready() -> void:
	_build_ui()
	_populate_troops()
	_populate_gear()
	_update_status("Select a gear slot on a troop, then choose gear from the right.")

func _build_ui() -> void:
	# Dark background
	var bg = ColorRect.new()
	bg.color = Color(0.08, 0.08, 0.12, 1)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# Outer VBox fills screen
	var outer = VBoxContainer.new()
	outer.set_anchors_preset(Control.PRESET_FULL_RECT)
	outer.add_theme_constant_override("separation", 6)
	add_child(outer)

	# Title
	var title = Label.new()
	title.text = "GEAR MANAGEMENT"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
	outer.add_child(title)

	# Main split: left troops, right inventory
	var hbox = HBoxContainer.new()
	hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hbox.add_theme_constant_override("separation", 10)
	outer.add_child(hbox)

	# --- LEFT PANEL ---
	var left = VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 4)
	hbox.add_child(left)

	var left_header = Label.new()
	left_header.text = "TROOPS"
	left_header.add_theme_font_size_override("font_size", 14)
	left_header.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	left.add_child(left_header)

	var left_scroll = ScrollContainer.new()
	left_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(left_scroll)

	troop_list = VBoxContainer.new()
	troop_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	troop_list.add_theme_constant_override("separation", 6)
	left_scroll.add_child(troop_list)

	set_bonus_label = Label.new()
	set_bonus_label.text = "Set Bonuses: None active"
	set_bonus_label.add_theme_font_size_override("font_size", 12)
	set_bonus_label.add_theme_color_override("font_color", Color(0.5, 0.9, 0.5))
	set_bonus_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	left.add_child(set_bonus_label)

	# --- RIGHT PANEL ---
	var right = VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 4)
	hbox.add_child(right)

	var right_header = Label.new()
	right_header.text = "INVENTORY"
	right_header.add_theme_font_size_override("font_size", 14)
	right_header.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	right.add_child(right_header)

	var right_scroll = ScrollContainer.new()
	right_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(right_scroll)

	gear_list = VBoxContainer.new()
	gear_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gear_list.add_theme_constant_override("separation", 4)
	right_scroll.add_child(gear_list)

	# --- DUNGEON BUTTONS ---
	var dungeon_hbox = HBoxContainer.new()
	dungeon_hbox.add_theme_constant_override("separation", 10)
	outer.add_child(dungeon_hbox)

	var quick_btn = Button.new()
	quick_btn.text = "Quick Dungeon"
	quick_btn.custom_minimum_size = Vector2(180, 44)
	quick_btn.add_theme_font_size_override("font_size", 15)
	quick_btn.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0))
	quick_btn.tooltip_text = "Text-based dungeon crawl"
	quick_btn.pressed.connect(func():
		SaveManager.save_game()
		get_tree().change_scene_to_file("res://scenes/dungeon_scene.tscn"))
	dungeon_hbox.add_child(quick_btn)

	var action_btn = Button.new()
	action_btn.text = "Action Dungeon  >"
	action_btn.custom_minimum_size = Vector2(200, 44)
	action_btn.add_theme_font_size_override("font_size", 15)
	action_btn.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
	action_btn.tooltip_text = "Top-down WASD action dungeon"
	action_btn.pressed.connect(func():
		SaveManager.save_game()
		get_tree().change_scene_to_file("res://scenes/action_dungeon.tscn"))
	dungeon_hbox.add_child(action_btn)

	var defense_btn = Button.new()
	defense_btn.text = "⚔ Defend Base"
	defense_btn.custom_minimum_size = Vector2(200, 44)
	defense_btn.add_theme_font_size_override("font_size", 15)
	defense_btn.add_theme_color_override("font_color", Color(1, 0.5, 0.3))
	defense_btn.tooltip_text = "Place troops and defend against waves"
	defense_btn.pressed.connect(func():
		SaveManager.save_game()
		get_tree().change_scene_to_file("res://scenes/defense_scene.tscn"))
	dungeon_hbox.add_child(defense_btn)

	# --- STATUS BAR ---
	var status_panel = PanelContainer.new()
	outer.add_child(status_panel)

	status_label = Label.new()
	status_label.text = "Loading..."
	status_label.add_theme_font_size_override("font_size", 12)
	status_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	status_panel.add_child(status_label)

func _populate_troops() -> void:
	for child in troop_list.get_children():
		child.queue_free()

	for troop in PlayerInventory.troop_roster:
		troop_list.add_child(_make_troop_card(troop))

func _populate_gear() -> void:
	for child in gear_list.get_children():
		child.queue_free()

	if PlayerInventory.gear_inventory.is_empty():
		var empty = Label.new()
		empty.text = "No gear in inventory."
		empty.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		gear_list.add_child(empty)
		return

	for gear in PlayerInventory.gear_inventory:
		gear_list.add_child(_make_gear_button(gear))

func _make_troop_card(troop: TroopData) -> PanelContainer:
	var card = PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	card.add_child(vbox)

	# Header
	var header = Label.new()
	header.text = troop.troop_name + "  [" + troop.get_type_name() + "]"
	header.add_theme_font_size_override("font_size", 15)
	header.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
	vbox.add_child(header)

	# Stats
	var stats_label = Label.new()
	stats_label.name = "Stats"
	_refresh_stats_text(stats_label, troop)
	stats_label.add_theme_font_size_override("font_size", 11)
	stats_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	stats_label.set_meta("troop", troop)
	vbox.add_child(stats_label)

	# Gear slot buttons
	var slots_hbox = HBoxContainer.new()
	slots_hbox.add_theme_constant_override("separation", 4)
	vbox.add_child(slots_hbox)

	for slot_key in ["WEAPON", "ARMOR", "RING", "ACCESSORY"]:
		var btn = Button.new()
		btn.custom_minimum_size = Vector2(80, 50)
		btn.set_meta("troop", troop)
		btn.set_meta("slot", slot_key)
		btn.set_meta("stats_label", stats_label)
		_refresh_slot_button(btn, troop, slot_key)
		btn.pressed.connect(_on_slot_pressed.bind(btn, troop, slot_key))
		slots_hbox.add_child(btn)

	return card

func _refresh_stats_text(label: Label, troop: TroopData) -> void:
	var eff = troop.get_effective_stats()
	label.text = "HP:%d  ATK:%d  DEF:%d  SPD:%d" % [
		eff.get("hp", 0), eff.get("attack", 0),
		eff.get("defense", 0), eff.get("speed", 0)
	]

func _refresh_slot_button(btn: Button, troop: TroopData, slot_key: String) -> void:
	var gear: GearItem = troop.equipped_gear[slot_key]
	if gear:
		btn.text = "%s\n%s\n[%s]" % [
			SLOT_ICONS[slot_key],
			_short_name(gear.item_name),
			gear.get_rarity_name()[0]
		]
		btn.add_theme_color_override("font_color", RARITY_COLORS[gear.get_rarity_name()])
	else:
		btn.text = SLOT_ICONS[slot_key] + "\n[empty]"
		btn.add_theme_color_override("font_color", Color(0.45, 0.45, 0.45))

func _make_gear_button(gear: GearItem) -> Button:
	var btn = Button.new()
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.custom_minimum_size = Vector2(0, 48)
	btn.set_meta("gear", gear)

	var stat_str = ""
	for stat in gear.stats:
		var val = gear.stats[stat]
		if stat == "crit_chance":
			stat_str += " crit:%.0f%%" % (val * 100)
		else:
			stat_str += " %s:%d" % [stat.left(3), val]

	btn.text = "[%s] %s\n%s |%s" % [
		gear.get_rarity_name()[0],
		gear.item_name,
		gear.get_slot_name(),
		stat_str
	]
	btn.add_theme_color_override("font_color", RARITY_COLORS[gear.get_rarity_name()])
	btn.pressed.connect(_on_gear_selected.bind(gear))
	return btn

func _on_slot_pressed(btn: Button, troop: TroopData, slot_key: String) -> void:
	# Clicking same slot again = deselect
	if selected_slot_button == btn:
		_clear_selection()
		_update_status("Selection cleared.")
		return

	# Deselect previous
	if selected_slot_button:
		_refresh_slot_button(selected_slot_button,
			selected_slot_button.get_meta("troop"),
			selected_slot_button.get_meta("slot"))

	selected_troop = troop
	selected_slot = slot_key
	selected_slot_button = btn
	btn.add_theme_color_override("font_color", Color(1, 1, 0))
	_update_status("Selected %s slot on %s — now pick a %s from inventory." % [slot_key, troop.troop_name, slot_key])

func _on_gear_selected(gear: GearItem) -> void:
	if selected_troop == null:
		_update_status("Pick a gear slot on a troop first!")
		return

	if gear.get_slot_name() != selected_slot:
		_update_status("Wrong slot! That's a %s piece — you selected a %s slot." % [gear.get_slot_name(), selected_slot])
		return

	# Return old gear to inventory
	var old_gear: GearItem = selected_troop.equipped_gear[selected_slot]
	if old_gear:
		PlayerInventory.add_gear(old_gear)

	# Equip new gear
	selected_troop.equip(gear)
	PlayerInventory.remove_gear(gear)

	_update_status("Equipped %s to %s!" % [gear.item_name, selected_troop.troop_name])

	# Refresh slot button and stats
	var prev_btn = selected_slot_button
	var prev_troop = selected_troop
	var prev_slot = selected_slot
	_clear_selection()
	_refresh_slot_button(prev_btn, prev_troop, prev_slot)

	# Refresh stats label on that card
	var stats_label = prev_btn.get_meta("stats_label")
	_refresh_stats_text(stats_label, prev_troop)

	_populate_gear()
	_update_set_bonuses()

func _clear_selection() -> void:
	if selected_slot_button:
		_refresh_slot_button(selected_slot_button,
			selected_slot_button.get_meta("troop"),
			selected_slot_button.get_meta("slot"))
	selected_troop = null
	selected_slot = ""
	selected_slot_button = null

func _update_set_bonuses() -> void:
	var counts = PlayerInventory.get_global_set_counts()
	if counts.is_empty():
		set_bonus_label.text = "Set Bonuses: None active"
		return
	var lines = ["Set Bonuses:"]
	for sname in counts:
		var c = counts[sname]
		var t = "  %s: %d pc" % [sname, c]
		if c >= 4: t += " (2pc+4pc active!)"
		elif c >= 2: t += " (2pc active!)"
		lines.append(t)
	set_bonus_label.text = "\n".join(lines)

func _update_status(msg: String) -> void:
	status_label.text = msg

func _short_name(full_name: String) -> String:
	if full_name.length() <= 10:
		return full_name
	return full_name.left(9) + "…"
