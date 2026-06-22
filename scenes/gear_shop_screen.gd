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
var tutorial_sell_item_btn: Button = null   # first per-item Sell button in the list — tutorial highlight target
var salvage_list_container: VBoxContainer = null
var tutorial_salvage_item_btn: Button = null   # first per-item Salvage button — tutorial highlight target for salvage_intro
var upgrade_list_container: VBoxContainer = null
var tutorial_sell_common_btn: Button = null
var buyback_list_container: VBoxContainer = null
var sell_scroll: ScrollContainer = null
var salvage_scroll: ScrollContainer = null
var upgrade_scroll: ScrollContainer = null
var tab_buttons: Array = []   # [Sell, Salvage, Upgrade, Buyback] Button nodes — tutorial highlight targets
var tab_panels: Array = []    # matching content panels, shown/hidden by _switch_tab()
var current_tab: int = 0

func _ready() -> void:
	_build_ui()
	TutorialRouter.resolve_current_step(self)

func get_tutorial_target(target_id: String) -> Control:
	var result: Control = null
	var relevant_scroll: ScrollContainer = null
	match target_id:
		"sell_item_button":
			_switch_tab(0)
			result = tutorial_sell_item_btn
			relevant_scroll = sell_scroll
		"salvage_tab_button":
			# No auto-switch here — this step's whole point is having the
			# player click the tab themselves.
			result = tab_buttons[1] if tab_buttons.size() > 1 else null
		"salvage_item_button":
			result = tutorial_salvage_item_btn
			relevant_scroll = salvage_scroll
		"sell_selected_button":   # kept for back-compat
			_switch_tab(0)
			result = tutorial_sell_common_btn
			relevant_scroll = sell_scroll
		"upgrade_tab_button":
			result = tab_buttons[2] if tab_buttons.size() > 2 else null
		"first_upgrade_button":
			_switch_tab(2)
			result = _find_first_upgrade_button()
			relevant_scroll = upgrade_scroll
		_: result = null

	# Once a click-mode tutorial step is showing, the dim bands block
	# input outside the highlighted cutout — including scroll-wheel
	# input, since Godot treats it as a mouse-button event. So if the
	# target isn't already in view, the player would be stuck unable to
	# reach it. Scroll it into view ourselves rather than relying on the
	# player being able to.
	if result and relevant_scroll:
		relevant_scroll.ensure_control_visible(result)
	return result

# Finds the upgrade row for the Hero's currently-equipped weapon. By
# the time this step runs, no loose weapons remain (2 got equipped, 1
# sold, 1 salvaged) — the only one left to upgrade is whatever's
# actually equipped, so this matches by the row's "is_hero_weapon" tag
# rather than by item name or list position.
func _find_first_upgrade_button() -> Control:
	if upgrade_list_container == null: return null
	for row in upgrade_list_container.get_children():
		for child in row.get_children():
			if child is Button and child.get_meta("is_hero_weapon", false):
				return child
	return null

func _build_ui() -> void:
	var bg = ColorRect.new()
	bg.color = Color(0.07, 0.07, 0.10)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin = MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	add_child(margin)

	# Root vbox fills the whole screen — header stays fixed at the top,
	# the TabContainer below it expands to take up the rest, so nothing
	# on this screen needs its own page-wide scroll.
	var outer = VBoxContainer.new()
	outer.add_theme_constant_override("separation", 10)
	outer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(outer)

	# --- FIXED HEADER — title + Gold, never moves regardless of tab ---
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

	outer.add_child(HSeparator.new())

	# --- TABS — Sell / Salvage / Upgrade / Buyback ---
	# Built from real Button nodes instead of Godot's TabContainer, since
	# TabContainer draws its own tab bar internally with no individual
	# Control per tab to point a tutorial highlight at. This way each
	# tab button is a normal node the tutorial can target like any other.
	var tab_bar = HBoxContainer.new()
	tab_bar.add_theme_constant_override("separation", 4)
	outer.add_child(tab_bar)

	var tab_content_area = Control.new()
	tab_content_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(tab_content_area)

	var sell_tab = _build_sell_tab()
	var salvage_tab = _build_salvage_tab()
	var upgrade_tab = _build_upgrade_tab()
	var buyback_tab = _build_buyback_tab()

	for tab in [sell_tab, salvage_tab, upgrade_tab, buyback_tab]:
		tab.set_anchors_preset(Control.PRESET_FULL_RECT)
		tab_content_area.add_child(tab)

	tab_panels = [sell_tab, salvage_tab, upgrade_tab, buyback_tab]

	var tab_names = ["Sell", "Salvage", "Upgrade", "Buyback"]
	tab_buttons = []
	for i in range(tab_names.size()):
		var tbtn = Button.new()
		tbtn.text = tab_names[i]
		tbtn.custom_minimum_size = Vector2(120, 36)
		tbtn.toggle_mode = true
		tbtn.pressed.connect(_on_tab_button_pressed.bind(i))
		tab_bar.add_child(tbtn)
		tab_buttons.append(tbtn)

	_switch_tab(0)

	# --- FIXED FOOTER — Back button, always reachable regardless of tab ---
	var back_btn = Button.new()
	back_btn.text = "Back to Management"
	back_btn.custom_minimum_size = Vector2(220, 44)
	back_btn.pressed.connect(func():
		get_tree().change_scene_to_file("res://scenes/management_screen.tscn"))
	outer.add_child(back_btn)

# Pure visual tab switch — no tutorial side effects, since this also
# gets called programmatically (initial setup, auto-switching for an
# item target that doesn't require the player to click the tab itself).
func _switch_tab(idx: int) -> void:
	current_tab = idx
	for i in range(tab_panels.size()):
		tab_panels[i].visible = (i == idx)
		tab_buttons[i].button_pressed = (i == idx)

# What the tab buttons actually connect to — the player physically
# clicking one. Advances the tutorial if a "click this tab" step is
# currently waiting on it, checking the actual current step id rather
# than just the tab index (same reasoning as the equip-step fix in
# management_screen.gd — inferring intent from a generic property like
# index/slot-type breaks the moment two different steps could share it).
func _on_tab_button_pressed(idx: int) -> void:
	_switch_tab(idx)
	if not PlayerInventory.tutorial_active: return
	var current_step = TutorialSteps.get_step(PlayerInventory.tutorial_step_index)
	var current_step_id = current_step.get("id", "") if current_step else ""
	if current_step_id == "click_salvage_tab" and idx == 1:
		TutorialRouter.advance_step("click_salvage_tab")
	elif current_step_id == "click_upgrade_tab" and idx == 2:
		TutorialRouter.advance_step("click_upgrade_tab")

func _build_sell_tab() -> Control:
	var scroll = ScrollContainer.new()
	sell_scroll = scroll
	var col = VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.custom_minimum_size = Vector2(600, 0)
	scroll.add_child(col)

	var desc = Label.new()
	desc.text = "Sell unwanted gear for Gold. Value scales with rarity and quality tier."
	desc.add_theme_font_size_override("font_size", 12)
	desc.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD
	col.add_child(desc)

	sell_list_container = VBoxContainer.new()
	sell_list_container.add_theme_constant_override("separation", 4)
	col.add_child(sell_list_container)
	_populate_sell_list()

	var threshold_vbox = VBoxContainer.new()
	threshold_vbox.add_theme_constant_override("separation", 4)
	col.add_child(threshold_vbox)

	for rarity_name in ["COMMON", "RARE", "EPIC"]:
		var bulk_btn = Button.new()
		bulk_btn.text = "Sell all %s and below" % rarity_name.capitalize()
		bulk_btn.custom_minimum_size = Vector2(0, 36)
		bulk_btn.add_theme_font_size_override("font_size", 11)
		bulk_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bulk_btn.pressed.connect(_on_bulk_sell_threshold.bind(rarity_name))
		threshold_vbox.add_child(bulk_btn)
		if rarity_name == "COMMON":
			tutorial_sell_common_btn = bulk_btn

	return scroll

func _build_salvage_tab() -> Control:
	var scroll = ScrollContainer.new()
	salvage_scroll = scroll
	var col = VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.custom_minimum_size = Vector2(600, 0)
	scroll.add_child(col)

	var desc = Label.new()
	desc.text = "Break unwanted gear down into salvage material, used to upgrade gear you keep. Salvage type matches the item's rarity."
	desc.add_theme_font_size_override("font_size", 12)
	desc.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD
	col.add_child(desc)

	salvage_list_container = VBoxContainer.new()
	salvage_list_container.add_theme_constant_override("separation", 4)
	col.add_child(salvage_list_container)
	_populate_salvage_list()

	var threshold_vbox = VBoxContainer.new()
	threshold_vbox.add_theme_constant_override("separation", 4)
	col.add_child(threshold_vbox)

	for rarity_name in ["COMMON", "RARE", "EPIC"]:
		var bulk_btn = Button.new()
		bulk_btn.text = "Salvage all %s and below" % rarity_name.capitalize()
		bulk_btn.custom_minimum_size = Vector2(0, 36)
		bulk_btn.add_theme_font_size_override("font_size", 11)
		bulk_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bulk_btn.pressed.connect(_on_bulk_salvage_threshold.bind(rarity_name))
		threshold_vbox.add_child(bulk_btn)

	return scroll

func _build_upgrade_tab() -> Control:
	var scroll = ScrollContainer.new()
	upgrade_scroll = scroll
	var col = VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.custom_minimum_size = Vector2(600, 0)
	scroll.add_child(col)

	var desc = Label.new()
	desc.text = "Spend salvage matching an item's rarity to push it up to 6 upgrade levels, each adding a small boost to its own stats. Quality raises the cost. Works on equipped gear too, not just loose."
	desc.add_theme_font_size_override("font_size", 12)
	desc.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD
	col.add_child(desc)

	upgrade_list_container = VBoxContainer.new()
	upgrade_list_container.add_theme_constant_override("separation", 4)
	col.add_child(upgrade_list_container)
	_populate_upgrade_list()

	return scroll

func _build_buyback_tab() -> Control:
	var scroll = ScrollContainer.new()
	var col = VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.custom_minimum_size = Vector2(600, 0)
	scroll.add_child(col)

	var desc = Label.new()
	desc.text = "Your last %d sold/salvaged items \u2014 buy one back for exactly what you got for it." % BUYBACK_MAX
	desc.add_theme_font_size_override("font_size", 12)
	desc.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD
	col.add_child(desc)

	buyback_list_container = VBoxContainer.new()
	buyback_list_container.add_theme_constant_override("separation", 4)
	col.add_child(buyback_list_container)
	_populate_buyback_list()

	return scroll

func _refresh_resource_label() -> void:
	resource_label.text = "🪙 Gold: %d\nSalvage \u2014 Common: %d  Rare: %d  Epic: %d  Legendary: %d" % [
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
	if not PlayerInventory.confirm_before_disposing_gear or PlayerInventory.tutorial_active:
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
	tutorial_sell_item_btn = null

	if PlayerInventory.gear_inventory.is_empty():
		var empty = Label.new()
		empty.text = "No gear to sell."
		empty.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		sell_list_container.add_child(empty)
		return

	for gear in PlayerInventory.gear_inventory:
		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)

		var name_lbl = Label.new()
		name_lbl.text = gear.item_name
		name_lbl.add_theme_font_size_override("font_size", 12)
		name_lbl.add_theme_color_override("font_color", gear.get_display_color())
		row.add_child(name_lbl)

		var sell_btn = Button.new()
		sell_btn.text = "Sell"
		sell_btn.custom_minimum_size = Vector2(50, 26)
		sell_btn.add_theme_font_size_override("font_size", 11)
		sell_btn.add_theme_color_override("font_color", Color(0.9, 0.8, 0.4))
		sell_btn.pressed.connect(_on_sell_single.bind(gear))
		row.add_child(sell_btn)

		var details_lbl = Label.new()
		details_lbl.text = "[%s%s] \u2014 %d\uD83E\uDE99" % [
			gear.get_rarity_name(),
			(" " + gear.get_quality_name()) if gear.get_quality_name() != "" else "",
			gear.get_sell_price(),
		]
		details_lbl.add_theme_font_size_override("font_size", 12)
		details_lbl.add_theme_color_override("font_color", Color(0.65, 0.65, 0.65))
		details_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(details_lbl)

		sell_list_container.add_child(row)

		# Matched by slot, not a specific name — every tutorial weapon is
		# identical ("Practice Sword" x4), so any one of them works here.
		if gear.get_slot_name() == "WEAPON" and tutorial_sell_item_btn == null:
			tutorial_sell_item_btn = sell_btn

func _on_sell_single(gear: GearItem) -> void:
	_confirm_then("Sell %s for %d Gold?" % [gear.item_name, gear.get_sell_price()],
		func(): _do_sell([gear]))

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

func _do_sell(to_sell: Array) -> void:
	var total_gold = 0
	for gear in to_sell:
		total_gold += gear.get_sell_price()
		_record_buyback(gear, "gold", gear.get_sell_price())
		PlayerInventory.remove_gear(gear)

	if PlayerInventory.unlocked_talents.get("economy_guild_contracts", false):
		total_gold = int(ceil(total_gold * 1.20))
	PlayerInventory.resources["gold"] += total_gold
	SaveManager.save_game()
	_set_status("Sold %d items for %d Gold." % [to_sell.size(), total_gold])
	if PlayerInventory.tutorial_active:
		TutorialRouter.advance_step("inventory_sell")
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
	tutorial_salvage_item_btn = null

	if PlayerInventory.gear_inventory.is_empty():
		var empty = Label.new()
		empty.text = "No gear to salvage."
		empty.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		salvage_list_container.add_child(empty)
		return

	for gear in PlayerInventory.gear_inventory:
		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)

		var name_lbl = Label.new()
		name_lbl.text = gear.item_name
		name_lbl.add_theme_font_size_override("font_size", 12)
		name_lbl.add_theme_color_override("font_color", gear.get_display_color())
		row.add_child(name_lbl)

		var salvage_btn = Button.new()
		salvage_btn.text = "Salvage"
		salvage_btn.custom_minimum_size = Vector2(66, 26)
		salvage_btn.add_theme_font_size_override("font_size", 11)
		salvage_btn.add_theme_color_override("font_color", Color(0.6, 0.8, 0.9))
		salvage_btn.pressed.connect(_on_salvage_single.bind(gear))
		row.add_child(salvage_btn)

		var details_lbl = Label.new()
		details_lbl.text = "[%s%s] \u2014 %d %s Salvage" % [
			gear.get_rarity_name(),
			(" " + gear.get_quality_name()) if gear.get_quality_name() != "" else "",
			gear.get_salvage_amount(), gear.get_rarity_name().capitalize(),
		]
		details_lbl.add_theme_font_size_override("font_size", 12)
		details_lbl.add_theme_color_override("font_color", Color(0.65, 0.65, 0.65))
		details_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(details_lbl)

		salvage_list_container.add_child(row)

		# Matched by slot, not a specific name — same reasoning as the
		# sell list above. Any of the 4 identical tutorial weapons works.
		if gear.get_slot_name() == "WEAPON" and tutorial_salvage_item_btn == null:
			tutorial_salvage_item_btn = salvage_btn

func _on_salvage_single(gear: GearItem) -> void:
	_confirm_then("Salvage %s for %d %s Salvage?" % [gear.item_name, gear.get_salvage_amount(), gear.get_rarity_name().capitalize()],
		func(): _do_salvage([gear]))

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

func _do_salvage(to_salvage: Array) -> void:
	var totals_by_rarity = {"COMMON": 0, "RARE": 0, "EPIC": 0, "LEGENDARY": 0}
	var salvage_mastery = PlayerInventory.unlocked_talents.get("gear_salvage_mastery", false)
	for gear in to_salvage:
		var rarity_key = gear.get_rarity_name()
		var amount = gear.get_salvage_amount()
		if salvage_mastery:
			amount = int(ceil(amount * 1.5))
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
	if PlayerInventory.tutorial_active:
		TutorialRouter.advance_step("salvage_intro")
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

	var has_any = false

	# Equipped gear first — across every troop, including the Hero.
	# Upgrading doesn't care whether a piece is loose or worn; gear.upgrade()
	# just mutates the item's own upgrade_level wherever it's referenced
	# from, so there's no reason to limit this list to the loose pool.
	for troop in PlayerInventory.troop_roster:
		for slot_key in troop.equipped_gear:
			var equipped = troop.equipped_gear[slot_key]
			if equipped == null: continue
			has_any = true
			var is_hero_weapon = (troop == PlayerInventory.troop_roster[0]) and equipped.get_slot_name() == "WEAPON"
			upgrade_list_container.add_child(_make_upgrade_row(equipped, troop.troop_name, is_hero_weapon))

	for gear in PlayerInventory.gear_inventory:
		has_any = true
		upgrade_list_container.add_child(_make_upgrade_row(gear))

	if not has_any:
		var empty = Label.new()
		empty.text = "No gear to upgrade."
		empty.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		upgrade_list_container.add_child(empty)

func _make_upgrade_row(gear: GearItem, owner_label: String = "", is_hero_weapon: bool = false) -> HBoxContainer:
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var lbl = Label.new()
	var level_text = "+%d/%d" % [gear.upgrade_level, gear.MAX_UPGRADE_LEVEL]
	var owner_suffix = " (%s, equipped)" % owner_label if owner_label != "" else ""
	lbl.text = "%s [%s%s] %s%s" % [
		gear.item_name, gear.get_rarity_name(),
		(" " + gear.get_quality_name()) if gear.get_quality_name() != "" else "",
		level_text, owner_suffix,
	]
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color", gear.get_display_color())
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lbl)

	var upgrade_btn = Button.new()
	# Matches the same condition used in the actual upgrade action below
	# (_on_upgrade_pressed) — checking the item's own upgrade_level
	# directly rather than the step id, so the two can't drift out of
	# sync with each other the way the Farm building's display/action
	# once did.
	var is_tutorial_free_upgrade = (PlayerInventory.tutorial_active and gear.upgrade_level == 0)
	if gear.is_max_upgrade():
		upgrade_btn.text = "Maxed"
		upgrade_btn.disabled = true
	else:
		var cost = gear.get_next_upgrade_cost()
		var rarity_key = gear.get_rarity_name()
		var have = PlayerInventory.salvage.get(rarity_key, 0)
		if is_tutorial_free_upgrade:
			upgrade_btn.text = "Upgrade (FREE)"
			upgrade_btn.disabled = false
		else:
			upgrade_btn.text = "Upgrade (%d/%d %s)" % [have, cost, rarity_key.capitalize()]
			upgrade_btn.disabled = have < cost
		upgrade_btn.pressed.connect(_on_upgrade_pressed.bind(gear))
	upgrade_btn.custom_minimum_size = Vector2(190, 32)
	upgrade_btn.add_theme_font_size_override("font_size", 11)
	upgrade_btn.set_meta("item_name", gear.item_name)
	upgrade_btn.set_meta("is_hero_weapon", is_hero_weapon)   # lets _find_first_upgrade_button() match the Hero's equipped weapon specifically
	row.add_child(upgrade_btn)

	return row

func _on_upgrade_pressed(gear: GearItem) -> void:
	var cost = gear.get_next_upgrade_cost()
	var rarity_key = gear.get_rarity_name()
	# Free as long as the tutorial is active and this specific item
	# hasn't been upgraded yet — checking the item's own state directly
	# rather than pinning to the exact "upgrade_intro" step id, which
	# could drift out of sync the same way the Farm building's free
	# condition once did (see world_map.gd's _on_build_selected for that
	# earlier fix).
	var is_tutorial_free_upgrade = (PlayerInventory.tutorial_active and gear.upgrade_level == 0)

	if not is_tutorial_free_upgrade:
		if PlayerInventory.salvage.get(rarity_key, 0) < cost:
			_set_status("Not enough %s Salvage." % rarity_key.capitalize())
			return
		PlayerInventory.salvage[rarity_key] -= cost

	gear.upgrade()
	SaveManager.save_game()
	_set_status("Upgraded %s to +%d!" % [gear.item_name, gear.upgrade_level])
	if is_tutorial_free_upgrade:
		TutorialRouter.advance_step("upgrade_intro")
	_refresh_resource_label()
	_populate_upgrade_list()
	_populate_buyback_list()
