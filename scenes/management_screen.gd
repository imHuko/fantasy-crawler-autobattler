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
var show_suggestions: bool = true
var compare_panel: PanelContainer = null

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

	# Title row
	var title_hbox = HBoxContainer.new()
	outer.add_child(title_hbox)

	var title = Label.new()
	title.text = "GEAR MANAGEMENT"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_hbox.add_child(title)

	var suggest_btn = Button.new()
	suggest_btn.text = "Suggestions: ON"
	suggest_btn.add_theme_font_size_override("font_size", 11)
	suggest_btn.pressed.connect(func():
		show_suggestions = !show_suggestions
		suggest_btn.text = "Suggestions: " + ("ON" if show_suggestions else "OFF")
		_populate_gear())
	title_hbox.add_child(suggest_btn)

	var alt_hint = Label.new()
	alt_hint.text = " Hold Alt on gear to see stat ranges"
	alt_hint.add_theme_font_size_override("font_size", 10)
	alt_hint.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	outer.add_child(alt_hint)

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

	# --- WORLD MAP BUTTON ---
	var map_btn = Button.new()
	map_btn.text = "🗺 World Map"
	map_btn.custom_minimum_size = Vector2(200, 48)
	map_btn.add_theme_font_size_override("font_size", 17)
	map_btn.add_theme_color_override("font_color", Color(0.4, 0.9, 0.6))
	map_btn.pressed.connect(func():
		SaveManager.save_game()
		get_tree().change_scene_to_file("res://scenes/world_map.tscn"))
	outer.add_child(map_btn)

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

	PlayerInventory.ensure_hero_exists()
	var hero_label = Label.new()
	hero_label.text = "⚔ DUNGEON HERO  (used in dungeon runs only)"
	hero_label.add_theme_font_size_override("font_size", 12)
	hero_label.add_theme_color_override("font_color", Color(0.6, 0.9, 1.0))
	troop_list.add_child(hero_label)
	troop_list.add_child(_make_troop_card(PlayerInventory.hero))

	var sep = HSeparator.new()
	troop_list.add_child(sep)

	var map_label = Label.new()
	map_label.text = "🗺 MAP TROOPS  (stationed on the world map)"
	map_label.add_theme_font_size_override("font_size", 12)
	map_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	troop_list.add_child(map_label)

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
	btn.custom_minimum_size = Vector2(0, 56)
	btn.set_meta("gear", gear)

	btn.text = _gear_display_text(gear, false)
	btn.add_theme_color_override("font_color", gear.get_display_color())
	btn.pressed.connect(_on_gear_selected.bind(gear))

	# Alt held = show stat ranges
	btn.mouse_entered.connect(_on_gear_hover.bind(gear, btn))
	btn.mouse_exited.connect(_on_gear_unhover.bind(gear, btn))
	return btn

func _gear_display_text(gear: GearItem, show_ranges: bool) -> String:
	var quality_suffix = gear.get_quality_suffix()
	var header = "[%s] %s%s" % [gear.get_rarity_name()[0], gear.item_name, quality_suffix]
	var slot_line = gear.get_slot_name()
	if gear.set_name != "":
		slot_line += " | Set: " + gear.set_name

	var stat_lines = ""
	for stat in gear.stats:
		var val = gear.stats[stat]
		var stat_str = ""
		if stat in ["crit_chance", "attack_speed"]:
			stat_str = "%s: %.0f%%" % [stat.replace("_", " "), val * 100]
		elif stat == "crit_damage":
			stat_str = "crit dmg: +%d%%" % val
		else:
			stat_str = "%s: %d" % [stat.replace("_", " "), val]

		if show_ranges and gear.stat_ranges.has(stat):
			var r = gear.stat_ranges[stat]
			var is_q = r.get("is_quality", false)
			if stat in ["crit_chance", "attack_speed"]:
				stat_str += " [%.0f-%.0f%%]%s" % [r["min"]*100, r["max"]*100, " ✦" if is_q else ""]
			else:
				stat_str += " [%s-%s]%s" % [str(r["min"]), str(r["max"]), " ✦" if is_q else ""]

		stat_lines += "
  " + stat_str

	# Unit suggestions
	var suggest_str = ""
	if show_suggestions:
		var suggestions = gear.get_suggested_units()
		if suggestions.size() > 0:
			suggest_str = "\n  » " + " / ".join(suggestions)

	return header + "\n" + slot_line + stat_lines + suggest_str

func _on_gear_hover(gear: GearItem, btn: Button) -> void:
	var show_ranges = Input.is_key_pressed(KEY_ALT)
	btn.text = _gear_display_text(gear, show_ranges)
	# Show compare if a slot is selected
	if selected_troop != null and selected_slot != "":
		_show_compare(gear)

func _on_gear_unhover(gear: GearItem, btn: Button) -> void:
	btn.text = _gear_display_text(gear, false)
	_hide_compare()

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

func _show_compare(hover_gear: GearItem) -> void:
	_hide_compare()
	if selected_troop == null or selected_slot == "": return
	var equipped: GearItem = selected_troop.equipped_gear[selected_slot]
	if equipped == null: return
	if hover_gear.get_slot_name() != selected_slot: return

	compare_panel = PanelContainer.new()
	compare_panel.position = Vector2(get_viewport().size.x / 2 - 160, 80)
	compare_panel.custom_minimum_size = Vector2(320, 0)
	add_child(compare_panel)

	var vbox = VBoxContainer.new()
	compare_panel.add_child(vbox)

	var title = Label.new()
	title.text = "COMPARE"
	title.add_theme_font_size_override("font_size", 13)
	title.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	vbox.add_child(title)

	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 16)
	vbox.add_child(hbox)

	# Equipped column
	var left_vbox = VBoxContainer.new()
	left_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(left_vbox)
	var left_title = Label.new()
	left_title.text = "Equipped"
	left_title.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	left_vbox.add_child(left_title)
	var left_name = Label.new()
	left_name.text = equipped.item_name + equipped.get_quality_suffix()
	left_name.add_theme_color_override("font_color", equipped.get_display_color())
	left_name.autowrap_mode = TextServer.AUTOWRAP_WORD
	left_vbox.add_child(left_name)

	# New item column
	var right_vbox = VBoxContainer.new()
	right_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(right_vbox)
	var right_title = Label.new()
	right_title.text = "New Item"
	right_title.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	right_vbox.add_child(right_title)
	var right_name = Label.new()
	right_name.text = hover_gear.item_name + hover_gear.get_quality_suffix()
	right_name.add_theme_color_override("font_color", hover_gear.get_display_color())
	right_name.autowrap_mode = TextServer.AUTOWRAP_WORD
	right_vbox.add_child(right_name)

	# Stat diffs
	var all_stats = []
	for s in equipped.stats: if s not in all_stats: all_stats.append(s)
	for s in hover_gear.stats: if s not in all_stats: all_stats.append(s)

	for stat in all_stats:
		var old_val = equipped.stats.get(stat, 0)
		var new_val = hover_gear.stats.get(stat, 0)
		var diff = new_val - old_val

		var left_lbl = Label.new()
		left_lbl.add_theme_font_size_override("font_size", 11)
		if stat in ["crit_chance", "attack_speed"]:
			left_lbl.text = "%s: %.0f%%" % [stat.replace("_"," "), old_val * 100]
		else:
			left_lbl.text = "%s: %s" % [stat.replace("_"," "), str(old_val)]
		left_vbox.add_child(left_lbl)

		var right_lbl = Label.new()
		right_lbl.add_theme_font_size_override("font_size", 11)
		var diff_str = ""
		if diff > 0:   diff_str = " (▲%s)" % str(snappedf(diff, 0.01) if stat in ["crit_chance","attack_speed"] else diff)
		elif diff < 0: diff_str = " (▼%s)" % str(snappedf(-diff, 0.01) if stat in ["crit_chance","attack_speed"] else -diff)
		if stat in ["crit_chance", "attack_speed"]:
			right_lbl.text = "%s: %.0f%%%s" % [stat.replace("_"," "), new_val * 100, diff_str]
		else:
			right_lbl.text = "%s: %s%s" % [stat.replace("_"," "), str(new_val), diff_str]
		var col = Color(0.3,0.9,0.3) if diff > 0 else (Color(0.9,0.3,0.3) if diff < 0 else Color(0.8,0.8,0.8))
		right_lbl.add_theme_color_override("font_color", col)
		right_vbox.add_child(right_lbl)

func _hide_compare() -> void:
	if compare_panel and is_instance_valid(compare_panel):
		compare_panel.queue_free()
		compare_panel = null

func _short_name(full_name: String) -> String:
	if full_name.length() <= 10:
		return full_name
	return full_name.left(9) + "…"
