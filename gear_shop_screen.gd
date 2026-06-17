extends Control

# -------------------------------------------------------
# Gear Shop Screen — sell or salvage unwanted gear, and spend salvage
# to upgrade gear you're keeping. Confirmation popups before
# selling/salvaging are gated by PlayerInventory.confirm_before_disposing_gear
# (toggle lives in Settings), since both actions are irreversible
# except via the recent-actions buyback list.
# -------------------------------------------------------

var resource_label: Label = null
var status_label: Label = null
var sell_list_container: VBoxContainer = null
var sell_checkboxes: Dictionary = {}   # GearItem -> CheckBox
var salvage_list_container: VBoxContainer = null
var salvage_checkboxes: Dictionary = {}   # GearItem -> CheckBox
var upgrade_list_container: VBoxContainer = null
var buyback_list_container: VBoxContainer = null

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
	outer.custom_minimum_size = Vector2(420, 0)
	margin.add_child(outer)

	# Header
	var title = Label.new()
	title.text = "GEAR SHOP"
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

	var sep_buyback = HSeparator.new()
	outer.add_child(sep_buyback)

	# --- BUYBACK SECTION ---
	var buyback_header = Label.new()
	buyback_header.text = "Buyback"
	buyback_header.add_theme_font_size_override("font_size", 18)
	buyback_header.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
	outer.add_child(buyback_header)

	var buyback_desc = Label.new()
	buyback_desc.text = "Your last %d sold/salvaged items \\u2014 buy one back for exactly what you got for it." % BUYBACK_MAX
	buyback_desc.add_theme_font_size_override("font_size", 12)
	buyback_desc.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	buyback_desc.autowrap_mode = TextServer.AUTOWRAP_WORD
	outer.add_child(buyback_desc)

	buyback_list_container = VBoxContainer.new()
	buyback_list_container.add_theme_constant_override("separation", 4)
	outer.add_child(buyback_list_container)
	_populate_buyback_list()

	var sep1 = HSeparator.new()
	outer.add_child(sep1)

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

	var sep2 = HSeparator.new()
	outer.add_child(sep2)

	# --- SALVAGE GEAR SECTION ---
	var salvage_header = Label.new()
	salvage_header.text = "Salvage Gear"
	salvage_header.add_theme_font_size_override("font_size", 18)
	salvage_header.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
	outer.add_child(salvage_header)

	var salvage_desc = Label.new()
	salvage_desc.text = "Break unwanted gear down into salvage material, used to upgrade gear you keep. Salvage type matches the item's rarity."
	salvage_desc.add_theme_font_size_override("font_size", 12)
	salvage_desc.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	salvage_desc.autowrap_mode = TextServer.AUTOWRAP_WORD
	outer.add_child(salvage_desc)

	var salvage_threshold_hbox = HBoxContainer.new()
	salvage_threshold_hbox.add_theme_constant_override("separation", 8)
	outer.add_child(salvage_threshold_hbox)

	for rarity_name in ["COMMON", "RARE", "EPIC"]:
		var bulk_btn = Button.new()
		bulk_btn.text = "Salvage all %s and below" % rarity_name.capitalize()
		bulk_btn.custom_minimum_size = Vector2(0, 36)
		bulk_btn.add_theme_font_size_override("font_size", 11)
		bulk_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bulk_btn.pressed.connect(_on_bulk_salvage_threshold.bind(rarity_name))
		salvage_threshold_hbox.add_child(bulk_btn)

	salvage_checkboxes.clear()
	salvage_list_container = VBoxContainer.new()
	salvage_list_container.add_theme_constant_override("separation", 4)
	outer.add_child(salvage_list_container)
	_populate_salvage_list()

	var salvage_selected_btn = Button.new()
	salvage_selected_btn.text = "Salvage Selected"
	salvage_selected_btn.custom_minimum_size = Vector2(0, 40)
	salvage_selected_btn.add_theme_color_override("font_color", Color(0.6, 0.8, 0.9))
	salvage_selected_btn.pressed.connect(_on_salvage_selected)
	outer.add_child(salvage_selected_btn)

	var sep_salvage = HSeparator.new()
	outer.add_child(sep_salvage)

	# --- UPGRADE GEAR SECTION ---
	var upgrade_header = Label.new()
	upgrade_header.text = "Upgrade Gear"
	upgrade_header.add_theme_font_size_override("font_size", 18)
	upgrade_header.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
	outer.add_child(upgrade_header)

	var upgrade_desc = Label.new()
	upgrade_desc.text = "Spend salvage matching an item's rarity to push it up to 6 upgrade levels, each adding a small boost to its own stats. Quality raises the cost."
	upgrade_desc.add_theme_font_size_override("font_size", 12)
	upgrade_desc.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	upgrade_desc.autowrap_mode = TextServer.AUTOWRAP_WORD
	outer.add_child(upgrade_desc)

	upgrade_list_container = VBoxContainer.new()
	upgrade_list_container.add_theme_constant_override("separation", 4)
	outer.add_child(upgrade_list_container)
	_populate_upgrade_list()

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
	resource_label.text = "🌾 Food: %d      🪙 Gold: %d\nSalvage \\u2014 Common: %d  Rare: %d  Epic: %d  Legendary: %d" % [
		PlayerInventory.resources.get("food", 0),
		PlayerInventory.resources.get("gold", 0),
		PlayerInventory.salvage.get("COMMON", 0),
		PlayerInventory.salvage.get("RARE", 0),
		PlayerInventory.salvage.get("EPIC", 0),
		PlayerInventory.salvage.get("LEGENDARY", 0),
	]

func _set_status(msg: String) -> void:
	if status_label: status_label.text = msg

# Rolling list of the last 10 disposed (sold/salvaged) items, for the
# Sub-step 3 buyback feature. Recording starts now so nothing is lost
# while that UI is still being built.
const BUYBACK_MAX = 10
var buyback_list: Array = []   # [{gear, refund_currency, refund_amount}, ...] most recent last

func _record_buyback(gear: GearItem, refund_currency: String, refund_amount: int) -> void:
	buyback_list.append({"gear": gear, "refund_currency": refund_currency, "refund_amount": refund_amount})
	if buyback_list.size() > BUYBACK_MAX:
		buyback_list.pop_front()

func _populate_buyback_list() -> void:
	if buyback_list_container == null: return
	for child in buyback_list_container.get_children():
		child.queue_free()

	if buyback_list.is_empty():
		var empty = Label.new()
		empty.text = "Nothing sold or salvaged yet this session."
		empty.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		buyback_list_container.add_child(empty)
		return

	# Most recent first, so the thing you just disposed of is at the top
	for i in range(buyback_list.size() - 1, -1, -1):
		buyback_list_container.add_child(_make_buyback_row(i))

func _get_currency_amount(currency_key: String) -> int:
	if currency_key == "gold":
		return PlayerInventory.resources.get("gold", 0)
	return PlayerInventory.salvage.get(currency_key, 0)

func _make_buyback_row(idx: int) -> HBoxContainer:
	var entry = buyback_list[idx]
	var gear: GearItem = entry["gear"]
	var currency_key: String = entry["refund_currency"]
	var amount: int = entry["refund_amount"]
	var currency_label = "Gold" if currency_key == "gold" else currency_key.capitalize() + " Salvage"

	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var lbl = Label.new()
	lbl.text = "%s [%s%s]" % [
		gear.item_name, gear.get_rarity_name(),
		(" " + gear.get_quality_name()) if gear.get_quality_name() != "" else "",
	]
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color", gear.get_display_color())
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lbl)

	var buy_btn = Button.new()
	var have = _get_currency_amount(currency_key)
	buy_btn.text = "Buy back (%d %s)" % [amount, currency_label]
	buy_btn.custom_minimum_size = Vector2(190, 32)
	buy_btn.add_theme_font_size_override("font_size", 11)
	buy_btn.disabled = have < amount
	buy_btn.pressed.connect(_on_buyback_pressed.bind(idx))
	row.add_child(buy_btn)

	return row

func _on_buyback_pressed(idx: int) -> void:
	if idx < 0 or idx >= buyback_list.size(): return
	var entry = buyback_list[idx]
	var gear: GearItem = entry["gear"]
	var currency_key: String = entry["refund_currency"]
	var amount: int = entry["refund_amount"]

	if _get_currency_amount(currency_key) < amount:
		_set_status("Not enough to buy that back.")
		return

	if currency_key == "gold":
		PlayerInventory.resources["gold"] -= amount
	else:
		PlayerInventory.salvage[currency_key] -= amount

	PlayerInventory.gear_inventory.append(gear)
	buyback_list.remove_at(idx)
	SaveManager.save_game()
	_set_status("Bought back %s." % gear.item_name)
	_refresh_resource_label()
	_populate_sell_list()
	_populate_salvage_list()
	_populate_upgrade_list()
	_populate_buyback_list()

# Shared confirmation popup for any irreversible disposal action (sell,
# salvage). Skips straight to on_confirm if the player has turned
# confirmations off in Settings.
func _confirm_then(message: String, on_confirm: Callable) -> void:
	if not PlayerInventory.confirm_before_disposing_gear:
		on_confirm.call()
		return

	var overlay = CanvasLayer.new()
	add_child(overlay)

	var bg = ColorRect.new()
	bg.color = Color(0, 0, 0, 0.7)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(bg)

	var panel = PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	overlay.add_child(panel)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	panel.add_child(vbox)

	var msg_lbl = Label.new()
	msg_lbl.text = message
	msg_lbl.add_theme_font_size_override("font_size", 14)
	msg_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	msg_lbl.custom_minimum_size = Vector2(280, 0)
	msg_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(msg_lbl)

	var hint = Label.new()
	hint.text = "(You can turn this off in Settings.)"
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(hint)

	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	vbox.add_child(hbox)

	var cancel_btn = Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.custom_minimum_size = Vector2(120, 40)
	cancel_btn.pressed.connect(func(): overlay.queue_free())
	hbox.add_child(cancel_btn)

	var confirm_btn = Button.new()
	confirm_btn.text = "Confirm"
	confirm_btn.custom_minimum_size = Vector2(120, 40)
	confirm_btn.add_theme_color_override("font_color", Color(0.9, 0.6, 0.3))
	confirm_btn.pressed.connect(func():
		overlay.queue_free()
		on_confirm.call())
	hbox.add_child(confirm_btn)

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

	_confirm_then("Sell %d item(s) at or below %s for Gold?" % [to_sell.size(), max_rarity.capitalize()],
		func(): _do_sell(to_sell))

func _on_sell_selected() -> void:
	var to_sell = []
	for gear in sell_checkboxes:
		if sell_checkboxes[gear].button_pressed:
			to_sell.append(gear)

	if to_sell.is_empty():
		_set_status("No items selected.")
		return

	_confirm_then("Sell %d selected item(s) for Gold?" % to_sell.size(), func(): _do_sell(to_sell))

func _do_sell(to_sell: Array) -> void:
	var total_gold = 0
	for gear in to_sell:
		total_gold += gear.get_sell_price()
		_record_buyback(gear, "gold", gear.get_sell_price())
		PlayerInventory.remove_gear(gear)

	PlayerInventory.resources["gold"] += total_gold
	SaveManager.save_game()
	_set_status("Sold %d items for %d Gold." % [to_sell.size(), total_gold])
	_refresh_resource_label()
	_populate_sell_list()
	_populate_salvage_list()
	_populate_buyback_list()

# -------------------------------------------------------
# Salvage Gear
# -------------------------------------------------------
func _populate_salvage_list() -> void:
	for child in salvage_list_container.get_children():
		child.queue_free()
	salvage_checkboxes.clear()

	if PlayerInventory.gear_inventory.is_empty():
		var empty = Label.new()
		empty.text = "No gear to salvage."
		empty.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		salvage_list_container.add_child(empty)
		return

	for gear in PlayerInventory.gear_inventory:
		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)

		var cb = CheckBox.new()
		salvage_checkboxes[gear] = cb
		row.add_child(cb)

		var lbl = Label.new()
		lbl.text = "%s [%s%s] \\u2014 %d %s Salvage" % [
			gear.item_name, gear.get_rarity_name(),
			(" " + gear.get_quality_name()) if gear.get_quality_name() != "" else "",
			gear.get_salvage_amount(), gear.get_rarity_name().capitalize(),
		]
		lbl.add_theme_font_size_override("font_size", 12)
		lbl.add_theme_color_override("font_color", gear.get_display_color())
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(lbl)

		salvage_list_container.add_child(row)

func _on_bulk_salvage_threshold(max_rarity: String) -> void:
	var rarity_order = ["COMMON", "RARE", "EPIC", "LEGENDARY"]
	var max_idx = rarity_order.find(max_rarity)

	var to_salvage = []
	for gear in PlayerInventory.gear_inventory:
		if rarity_order.find(gear.get_rarity_name()) <= max_idx:
			to_salvage.append(gear)

	if to_salvage.is_empty():
		_set_status("Nothing to salvage at or below %s." % max_rarity.capitalize())
		return

	_confirm_then("Salvage %d item(s) at or below %s?" % [to_salvage.size(), max_rarity.capitalize()],
		func(): _do_salvage(to_salvage))

func _on_salvage_selected() -> void:
	var to_salvage = []
	for gear in salvage_checkboxes:
		if salvage_checkboxes[gear].button_pressed:
			to_salvage.append(gear)

	if to_salvage.is_empty():
		_set_status("No items selected.")
		return

	_confirm_then("Salvage %d selected item(s)?" % to_salvage.size(), func(): _do_salvage(to_salvage))

func _do_salvage(to_salvage: Array) -> void:
	var totals_by_rarity = {"COMMON": 0, "RARE": 0, "EPIC": 0, "LEGENDARY": 0}
	for gear in to_salvage:
		var rarity_key = gear.get_rarity_name()
		var amount = gear.get_salvage_amount()
		totals_by_rarity[rarity_key] = totals_by_rarity.get(rarity_key, 0) + amount
		_record_buyback(gear, rarity_key, amount)
		PlayerInventory.remove_gear(gear)

	for rarity_key in totals_by_rarity:
		PlayerInventory.salvage[rarity_key] = PlayerInventory.salvage.get(rarity_key, 0) + totals_by_rarity[rarity_key]

	SaveManager.save_game()
	var summary_parts = []
	for rarity_key in totals_by_rarity:
		if totals_by_rarity[rarity_key] > 0:
			summary_parts.append("%d %s" % [totals_by_rarity[rarity_key], rarity_key.capitalize()])
	_set_status("Salvaged %d items for %s." % [to_salvage.size(), ", ".join(summary_parts)])
	_refresh_resource_label()
	_populate_sell_list()
	_populate_salvage_list()
	_populate_upgrade_list()
	_populate_buyback_list()

# -------------------------------------------------------
# Upgrade Gear
# -------------------------------------------------------
func _populate_upgrade_list() -> void:
	for child in upgrade_list_container.get_children():
		child.queue_free()

	if PlayerInventory.gear_inventory.is_empty():
		var empty = Label.new()
		empty.text = "No gear to upgrade."
		empty.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		upgrade_list_container.add_child(empty)
		return

	for gear in PlayerInventory.gear_inventory:
		upgrade_list_container.add_child(_make_upgrade_row(gear))

func _make_upgrade_row(gear: GearItem) -> HBoxContainer:
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var lbl = Label.new()
	var level_text = "+%d/%d" % [gear.upgrade_level, gear.MAX_UPGRADE_LEVEL]
	lbl.text = "%s [%s%s] %s" % [
		gear.item_name, gear.get_rarity_name(),
		(" " + gear.get_quality_name()) if gear.get_quality_name() != "" else "",
		level_text,
	]
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color", gear.get_display_color())
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lbl)

	var upgrade_btn = Button.new()
	if gear.is_max_upgrade():
		upgrade_btn.text = "Maxed"
		upgrade_btn.disabled = true
	else:
		var cost = gear.get_next_upgrade_cost()
		var rarity_key = gear.get_rarity_name()
		var have = PlayerInventory.salvage.get(rarity_key, 0)
		upgrade_btn.text = "Upgrade (%d/%d %s)" % [have, cost, rarity_key.capitalize()]
		upgrade_btn.disabled = have < cost
		upgrade_btn.pressed.connect(_on_upgrade_pressed.bind(gear))
	upgrade_btn.custom_minimum_size = Vector2(190, 32)
	upgrade_btn.add_theme_font_size_override("font_size", 11)
	row.add_child(upgrade_btn)

	return row

func _on_upgrade_pressed(gear: GearItem) -> void:
	var cost = gear.get_next_upgrade_cost()
	var rarity_key = gear.get_rarity_name()
	if PlayerInventory.salvage.get(rarity_key, 0) < cost:
		_set_status("Not enough %s Salvage." % rarity_key.capitalize())
		return

	PlayerInventory.salvage[rarity_key] -= cost
	gear.upgrade()
	SaveManager.save_game()
	_set_status("Upgraded %s to +%d!" % [gear.item_name, gear.upgrade_level])
	_refresh_resource_label()
	_populate_upgrade_list()
	_populate_buyback_list()
