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

# Stats that display and roll as percentages rather than flat numbers
const PERCENT_STATS = ["crit_chance", "attack_speed", "spell_power", "lifesteal", "move_speed"]
var focus_troop: TroopData = null   # "working on" troop, used by hover-compare when no slot is selected
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
	set_bonus_label.text = "Sets: none equipped"
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

	var admin_btn = Button.new()
	admin_btn.text = "⚙ Admin"
	admin_btn.custom_minimum_size = Vector2(100, 48)
	admin_btn.add_theme_font_size_override("font_size", 15)
	admin_btn.add_theme_color_override("font_color", Color(1, 0.7, 0.2))
	admin_btn.tooltip_text = "Testing tools — resources, stage, talents, troop healing, jump to combat"
	admin_btn.pressed.connect(func(): AdminPanel._toggle_panel())
	top_nav_hbox.add_child(admin_btn)

	# --- DUNGEON BUTTON ---
	var dungeon_hbox = HBoxContainer.new()
	dungeon_hbox.add_theme_constant_override("separation", 10)
	outer.add_child(dungeon_hbox)

	var action_btn = Button.new()
	action_btn.text = "⚔ Dungeon  >"
	action_btn.custom_minimum_size = Vector2(200, 44)
	action_btn.add_theme_font_size_override("font_size", 15)
	action_btn.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
	action_btn.tooltip_text = "Top-down WASD action dungeon"
	action_btn.pressed.connect(func():
		PlayerInventory.dungeon_troop_id = ""   # standalone path always uses the Hero
		SaveManager.save_game()
		PlayerInventory.set_meta("dungeon_picker_destination", "res://scenes/action_dungeon.tscn")
		get_tree().change_scene_to_file("res://scenes/dungeon_picker_screen.tscn"))
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

	var map_label = Label.new()
	map_label.text = "🗺 TROOPS  (stationed on the world map, fight in defense battles)"
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
		gear_list.add_child(_make_gear_row(gear))

func _make_gear_row(gear: GearItem) -> HBoxContainer:
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)

	row.add_child(_make_gear_button(gear))

	var sell_btn = Button.new()
	sell_btn.text = "Sell (%d🪙)" % gear.get_sell_price()
	sell_btn.custom_minimum_size = Vector2(90, 0)
	sell_btn.add_theme_font_size_override("font_size", 11)
	sell_btn.add_theme_color_override("font_color", Color(0.9, 0.8, 0.4))
	sell_btn.pressed.connect(_on_sell_gear.bind(gear))
	row.add_child(sell_btn)

	return row

func _on_sell_gear(gear: GearItem) -> void:
	var price = gear.get_sell_price()
	PlayerInventory.remove_gear(gear)
	PlayerInventory.resources["gold"] += price
	if selected_gear == gear:
		_clear_selection()
	SaveManager.save_game()
	_update_status("Sold %s for %d Gold." % [gear.item_name, price])
	_populate_gear()

func _make_troop_card(troop: TroopData) -> PanelContainer:
	var card = PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	card.add_child(vbox)

	# Header
	var header_hbox = HBoxContainer.new()
	header_hbox.add_theme_constant_override("separation", 8)
	vbox.add_child(header_hbox)

	var header = Label.new()
	var hero_tag = "⚔ " if troop.is_hero else ""
	header.text = hero_tag + troop.troop_name + "  [" + troop.get_type_name() + "]"
	header.add_theme_font_size_override("font_size", 15)
	header.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_hbox.add_child(header)

	var is_focused = (focus_troop == troop)
	var focus_btn = Button.new()
	focus_btn.text = "★ Focused" if is_focused else "☆ Focus"
	focus_btn.custom_minimum_size = Vector2(90, 0)
	focus_btn.add_theme_font_size_override("font_size", 11)
	focus_btn.add_theme_color_override("font_color", Color(1, 0.85, 0.3) if is_focused else Color(0.6, 0.6, 0.6))
	focus_btn.tooltip_text = "Mark this troop as the one you're working on, so hovering gear compares against their equipped items."
	focus_btn.pressed.connect(_on_focus_troop_pressed.bind(troop))
	header_hbox.add_child(focus_btn)

	if is_focused:
		card.add_theme_color_override("font_color", Color(1, 0.85, 0.3))

	# Stats
	var stats_label = Label.new()
	stats_label.name = "Stats"
	_refresh_stats_text(stats_label, troop)
	stats_label.add_theme_font_size_override("font_size", 11)
	stats_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	stats_label.set_meta("troop", troop)
	vbox.add_child(stats_label)

	# HP row — shows current/max HP and lets the player spend food to
	# heal missing HP at a 1 food : 1 HP rate. Wounds persist from
	# defense battles until healed here.
	var hp_hbox = HBoxContainer.new()
	hp_hbox.add_theme_constant_override("separation", 8)
	hp_hbox.name = "HPRow"
	vbox.add_child(hp_hbox)

	var hp_label = Label.new()
	hp_label.name = "HPLabel"
	hp_label.add_theme_font_size_override("font_size", 12)
	hp_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hp_hbox.add_child(hp_label)

	var heal_btn = Button.new()
	heal_btn.name = "HealBtn"
	heal_btn.add_theme_font_size_override("font_size", 11)
	heal_btn.pressed.connect(_on_heal_troop_pressed.bind(troop, card))
	hp_hbox.add_child(heal_btn)

	_refresh_hp_row(hp_label, heal_btn, troop)

	# Gear slot buttons
	var slots_hbox = HBoxContainer.new()
	slots_hbox.add_theme_constant_override("separation", 4)
	vbox.add_child(slots_hbox)

	for slot_key in ["WEAPON", "ARMOR", "RING", "ACCESSORY"]:
		var slot_container = VBoxContainer.new()
		slot_container.add_theme_constant_override("separation", 2)

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
		btn.mouse_entered.connect(_on_slot_hover.bind(troop, slot_key, btn))
		btn.mouse_exited.connect(_on_slot_unhover.bind(btn, troop, slot_key))
		slot_container.add_child(btn)
		all_slot_buttons.append(btn)

		var unequip_btn = Button.new()
		unequip_btn.text = "Unequip"
		unequip_btn.custom_minimum_size = Vector2(80, 22)
		unequip_btn.add_theme_font_size_override("font_size", 10)
		unequip_btn.pressed.connect(_on_unequip_pressed.bind(troop, slot_key, btn))
		slot_container.add_child(unequip_btn)

		slots_hbox.add_child(slot_container)

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

func _on_slot_hover(troop: TroopData, slot_key: String, btn: Button) -> void:
	var gear: GearItem = troop.equipped_gear[slot_key]
	if gear:
		btn.text = _gear_display_text(gear, true)

func _on_slot_unhover(btn: Button, troop: TroopData, slot_key: String) -> void:
	_refresh_slot_button(btn, troop, slot_key)

func _on_unequip_pressed(troop: TroopData, slot_key: String, slot_btn: Button) -> void:
	var gear: GearItem = troop.unequip(slot_key)
	if gear == null:
		_update_status("Nothing equipped in that slot.")
		return

	PlayerInventory.add_gear(gear)

	_update_status("Unequipped %s from %s." % [gear.item_name, troop.troop_name])
	_refresh_slot_button(slot_btn, troop, slot_key)

	var stats_label = slot_btn.get_meta("stats_label")
	_refresh_stats_text(stats_label, troop)

	_populate_gear()
	_update_set_bonuses()

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
	var item_lvl = gear.item_level if "item_level" in gear else 5
	var budget_pct = gear.get_stat_budget_pct() if gear.has_method("get_stat_budget_pct") else 100
	var header = "[%s] iLvl%d (%d%%) %s%s" % [gear.get_rarity_name()[0], item_lvl, budget_pct, gear.item_name, quality_suffix]
	var slot_line = gear.get_slot_name()
	if gear.set_name != "":
		slot_line += " | Set: " + gear.set_name

	var stat_lines = ""
	for stat in gear.stats:
		var val = gear.stats[stat]
		var stat_str = ""
		if stat in PERCENT_STATS:
			stat_str = "%s: %.0f%%" % [stat.replace("_", " "), val * 100]
		elif stat == "crit_damage":
			stat_str = "crit dmg: +%d%%" % val
		else:
			stat_str = "%s: %d" % [stat.replace("_", " "), val]

		var stack_count = gear.stat_ranges.get(stat, {}).get("stacked", 1)
		if stack_count > 1:
			stat_str += " (x%d stacked!)" % stack_count

		if show_ranges and gear.stat_ranges.has(stat):
			var r = gear.stat_ranges[stat]
			var is_q = r.get("is_quality", false)
			if stat in PERCENT_STATS:
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

func _refresh_hp_row(hp_label: Label, heal_btn: Button, troop: TroopData) -> void:
	var current = troop.get_current_hp()
	var max_hp = troop.get_max_hp()
	var missing = troop.get_missing_hp()

	hp_label.text = "HP: %d / %d" % [current, max_hp]
	var hp_pct = float(current) / max(1, max_hp)
	if hp_pct <= 0.15:
		hp_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.25))
	elif hp_pct <= 0.5:
		hp_label.add_theme_color_override("font_color", Color(1.0, 0.7, 0.3))
	else:
		hp_label.add_theme_color_override("font_color", Color(0.5, 0.9, 0.5))

	if missing <= 0:
		heal_btn.text = "Full HP"
		heal_btn.disabled = true
	else:
		var food_available = PlayerInventory.resources.get("food", 0)
		var food_cost = missing   # 1 food : 1 HP
		heal_btn.text = "Heal (%d food)" % food_cost
		heal_btn.disabled = food_available <= 0

func _on_heal_troop_pressed(troop: TroopData, card: PanelContainer) -> void:
	var missing = troop.get_missing_hp()
	if missing <= 0:
		return

	var food_available = PlayerInventory.resources.get("food", 0)
	if food_available <= 0:
		_update_status("Not enough food to heal %s." % troop.troop_name)
		return

	# Spend whatever food is available, up to what's actually needed —
	# lets the player partially heal if they don't have enough for a
	# full heal, rather than requiring the full amount upfront.
	var food_to_spend = min(missing, food_available)
	var healed = troop.heal(food_to_spend)
	PlayerInventory.resources["food"] -= healed

	if healed >= missing:
		_update_status("%s fully healed for %d food." % [troop.troop_name, healed])
	else:
		_update_status("%s healed %d HP for %d food (need more food for the rest)." % [troop.troop_name, healed, healed])

	var hp_label = card.find_child("HPLabel", true, false)
	var heal_btn = card.find_child("HealBtn", true, false)
	if hp_label and heal_btn:
		_refresh_hp_row(hp_label, heal_btn, troop)

func _on_focus_troop_pressed(troop: TroopData) -> void:
	focus_troop = null if focus_troop == troop else troop
	_populate_troops()

func _on_gear_hover(gear: GearItem, btn: Button) -> void:
	btn.text = _gear_display_text(gear, true)
	# Show compare against an explicitly selected slot if there is one,
	# otherwise fall back to the focused troop's equipped item of the
	# matching slot type, so browsing gear doesn't require pre-selecting
	# a slot first.
	if selected_troop != null and selected_slot != "":
		_show_compare(gear)
	elif focus_troop != null:
		_show_compare(gear, focus_troop, gear.get_slot_name())

func _on_gear_unhover(gear: GearItem, btn: Button) -> void:
	btn.text = _gear_display_text(gear, true)
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
		set_bonus_label.text = "Sets: none equipped"
		return
	var lines = ["Sets equipped:"]
	for sname in counts:
		var c = counts[sname]
		lines.append("  %s: %d pc" % [sname, c])
	set_bonus_label.text = "\n".join(lines)

func _update_status(msg: String) -> void:
	status_label.text = msg

func _show_compare(hover_gear: GearItem, override_troop: TroopData = null, override_slot: String = "") -> void:
	_hide_compare()
	var compare_troop = override_troop if override_troop != null else selected_troop
	var compare_slot = override_slot if override_slot != "" else selected_slot
	if compare_troop == null or compare_slot == "": return
	var equipped: GearItem = compare_troop.equipped_gear[compare_slot]
	if equipped == null: return
	if hover_gear.get_slot_name() != compare_slot: return

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
	left_title.text = "Equipped (%s)" % compare_troop.troop_name
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
		if stat in PERCENT_STATS:
			left_lbl.text = "%s: %.0f%%" % [stat.replace("_"," "), old_val * 100]
		else:
			left_lbl.text = "%s: %s" % [stat.replace("_"," "), str(old_val)]
		left_vbox.add_child(left_lbl)

		var right_lbl = Label.new()
		right_lbl.add_theme_font_size_override("font_size", 11)
		var diff_str = ""
		if diff > 0:   diff_str = " (▲%s)" % str(snappedf(diff, 0.01) if stat in PERCENT_STATS else diff)
		elif diff < 0: diff_str = " (▼%s)" % str(snappedf(-diff, 0.01) if stat in PERCENT_STATS else -diff)
		if stat in PERCENT_STATS:
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
