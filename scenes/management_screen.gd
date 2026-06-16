extends Control

# -------------------------------------------------------
# Management Screen — fully code-built, no scene tree needed
# -------------------------------------------------------

const RARITY_COLORS = {
	"COMMON":    Color(0.75, 0.75, 0.75),
	"RARE":      Color(0.25, 0.50, 1.00),
	"EPIC":      Color(0.65, 0.25, 0.90),
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
var selected_gear: GearItem = null
var selected_gear_button: Button = null
var show_suggestions: bool = true
var compare_panel: PanelContainer = null
var all_slot_buttons: Array = []   # every gear slot button across every troop card, for cross-card highlighting

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

	# --- WORLD MAP / SHOP BUTTONS ---
	var top_nav_hbox = HBoxContainer.new()
	top_nav_hbox.add_theme_constant_override("separation", 10)
	outer.add_child(top_nav_hbox)

	var map_btn = Button.new()
	map_btn.text = "🗺 World Map"
	map_btn.custom_minimum_size = Vector2(200, 48)
	map_btn.add_theme_font_size_override("font_size", 17)
	map_btn.add_theme_color_override("font_color", Color(0.4, 0.9, 0.6))
	map_btn.pressed.connect(func():
		SaveManager.save_game()
		get_tree().change_scene_to_file("res://scenes/world_map.tscn"))
	top_nav_hbox.add_child(map_btn)

	var shop_btn = Button.new()
	shop_btn.text = "🛒 Shop  (🌾%d 🪙%d)" % [PlayerInventory.resources.get("food", 0), PlayerInventory.resources.get("gold", 0)]
	shop_btn.custom_minimum_size = Vector2(200, 48)
	shop_btn.add_theme_font_size_override("font_size", 15)
	shop_btn.add_theme_color_override("font_color", Color(0.9, 0.8, 0.4))
	shop_btn.tooltip_text = "Spend Food and Gold on recruiting new units"
	shop_btn.pressed.connect(func():
		SaveManager.save_game()
		get_tree().change_scene_to_file("res://scenes/shop_screen.tscn"))
	top_nav_hbox.add_child(shop_btn)

	var talent_btn = Button.new()
	talent_btn.text = "🌳 Talents"
	talent_btn.custom_minimum_size = Vector2(160, 48)
	talent_btn.add_theme_font_size_override("font_size", 15)
	talent_btn.add_theme_color_override("font_color", Color(0.6, 0.9, 0.7))
	talent_btn.tooltip_text = "Spend resources to unlock permanent upgrades"
	talent_btn.pressed.connect(func():
		SaveManager.save_game()
		get_tree().change_scene_to_file("res://scenes/talent_tree_screen.tscn"))
	top_nav_hbox.add_child(talent_btn)

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
	all_slot_buttons.clear()

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

	var gear_to_show = PlayerInventory.gear_inventory.duplicate()

	# Determine which slot type to prioritize: either a directly selected
	# slot, or the slot type of currently selected gear (so clicking a ring
	# first also bubbles other rings to the top of the list).
	var priority_slot = selected_slot
	if priority_slot == "" and selected_gear != null:
		priority_slot = selected_gear.get_slot_name()

	if priority_slot != "":
		gear_to_show.sort_custom(func(a, b):
			var a_match = a.get_slot_name() == priority_slot
			var b_match = b.get_slot_name() == priority_slot
			if a_match and not b_match: return true
			if b_match and not a_match: return false
			return false)

	for gear in gear_to_show:
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
		var btn = DroppableSlotButton.new()
		btn.custom_minimum_size = Vector2(80, 50)
		btn.set_meta("troop", troop)
		btn.set_meta("slot", slot_key)
		btn.set_meta("stats_label", stats_label)
		btn.troop_ref = troop
		btn.slot_key_ref = slot_key
		btn.on_drop_callback = _equip_gear_to_slot
		_refresh_slot_button(btn, troop, slot_key)
		btn.pressed.connect(_on_slot_pressed.bind(btn, troop, slot_key))
		slots_hbox.add_child(btn)
		all_slot_buttons.append(btn)

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
	var btn = DraggableGearButton.new()
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.custom_minimum_size = Vector2(0, 56)
	btn.set_meta("gear", gear)
	btn.gear_item = gear

	btn.text = _gear_display_text(gear, false)
	if selected_gear == gear:
		btn.add_theme_color_override("font_color", Color(1, 1, 0))
		selected_gear_button = btn
	else:
		btn.add_theme_color_override("font_color", gear.get_display_color())
	btn.pressed.connect(_on_gear_selected.bind(gear, btn))

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
	# Clicking the same slot again = deselect
	if selected_slot_button == btn:
		_clear_selection()
		_update_status("Selection cleared.")
		return

	# If gear was already selected first, this completes the equip directly
	if selected_gear != null:
		if selected_gear.get_slot_name() != slot_key:
			_update_status("Wrong slot! That's a %s piece — you clicked a %s slot." % [selected_gear.get_slot_name(), slot_key])
			return
		_equip_gear_to_slot(selected_gear, troop, slot_key, btn)
		return

	# Otherwise, just select this slot and wait for a gear pick
	_clear_selection()
	selected_troop = troop
	selected_slot = slot_key
	selected_slot_button = btn
	btn.add_theme_color_override("font_color", Color(1, 1, 0))
	_update_status("Selected %s slot on %s — now pick a %s from inventory." % [slot_key, troop.troop_name, slot_key])
	_populate_gear()   # re-sort gear list to prioritize this slot type

func _on_gear_selected(gear: GearItem, btn: Button) -> void:
	# Clicking the same gear again = deselect.
	# Compare by the GearItem itself, not the button — the button gets
	# destroyed and recreated every time _populate_gear() runs, so a stale
	# button reference would never match after the list refreshes.
	if selected_gear == gear:
		_clear_selection()
		_update_status("Selection cleared.")
		return

	# If a slot was already selected first, this completes the equip directly
	if selected_troop != null and selected_slot != "":
		if gear.get_slot_name() != selected_slot:
			_update_status("Wrong slot! That's a %s piece — you selected a %s slot." % [gear.get_slot_name(), selected_slot])
			return
		_equip_gear_to_slot(gear, selected_troop, selected_slot, selected_slot_button)
		return

	# Otherwise, select this gear and highlight every matching slot across all troops
	_clear_selection()
	selected_gear = gear
	selected_gear_button = btn
	btn.add_theme_color_override("font_color", Color(1, 1, 0))

	var matching_slot = gear.get_slot_name()
	var highlighted = 0
	for slot_btn in all_slot_buttons:
		if slot_btn.get_meta("slot") == matching_slot:
			slot_btn.add_theme_color_override("font_color", Color(0.5, 1.0, 0.5))
			highlighted += 1

	_update_status("Selected %s — highlighted %d matching %s slot(s). Click one to equip." % [gear.item_name, highlighted, matching_slot])
	_populate_gear()

# Shared equip logic used regardless of which was clicked first (slot or gear)
func _equip_gear_to_slot(gear: GearItem, troop: TroopData, slot_key: String, slot_btn: Button) -> void:
	# Return old gear to inventory
	var old_gear: GearItem = troop.equipped_gear[slot_key]
	if old_gear:
		PlayerInventory.add_gear(old_gear)

	# Equip new gear
	troop.equip(gear)
	PlayerInventory.remove_gear(gear)

	_update_status("Equipped %s to %s!" % [gear.item_name, troop.troop_name])

	_clear_selection()
	_refresh_slot_button(slot_btn, troop, slot_key)

	# Refresh stats label on that card
	var stats_label = slot_btn.get_meta("stats_label")
	_refresh_stats_text(stats_label, troop)

	_populate_gear()
	_update_set_bonuses()

func _clear_selection() -> void:
	if selected_slot_button:
		_refresh_slot_button(selected_slot_button,
			selected_slot_button.get_meta("troop"),
			selected_slot_button.get_meta("slot"))
	# Un-highlight any cross-card matched slots
	for slot_btn in all_slot_buttons:
		if slot_btn != selected_slot_button:
			_refresh_slot_button(slot_btn, slot_btn.get_meta("troop"), slot_btn.get_meta("slot"))
	selected_troop = null
	selected_slot = ""
	selected_slot_button = null
	selected_gear = null
	selected_gear_button = null

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
