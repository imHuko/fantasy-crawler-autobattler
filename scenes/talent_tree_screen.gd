extends Control

# -------------------------------------------------------
# Talent Tree Screen — branches laid out as columns, each node
# shows its cost, description, and lock state (locked by prereq,
# locked by stage, affordable, or already owned).
# -------------------------------------------------------

var resource_label: Label = null
var status_label: Label = null
var branches_hbox: HBoxContainer = null

const BRANCH_COLORS = {
	"Gear": Color(0.65, 0.25, 0.90),
	"Buildings": Color(0.85, 0.75, 0.4),
	"Recruiting": Color(0.4, 0.9, 0.6),
	"Combat": Color(0.9, 0.3, 0.3),
	"Economy": Color(0.4, 0.8, 0.4),
	"Standalone": Color(0.6, 0.6, 0.9),
}

func _ready() -> void:
	_build_ui()
	_populate_branches()

func _build_ui() -> void:
	var bg = ColorRect.new()
	bg.color = Color(0.06, 0.06, 0.09)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var scroll = ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(scroll)

	var margin = MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	scroll.add_child(margin)

	var outer = VBoxContainer.new()
	outer.add_theme_constant_override("separation", 12)
	margin.add_child(outer)

	var header_hbox = HBoxContainer.new()
	header_hbox.add_theme_constant_override("separation", 16)
	outer.add_child(header_hbox)

	var title = Label.new()
	title.text = "TALENT TREE"
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
	header_hbox.add_child(title)

	resource_label = Label.new()
	resource_label.add_theme_font_size_override("font_size", 15)
	resource_label.add_theme_color_override("font_color", Color(0.8, 0.9, 0.8))
	header_hbox.add_child(resource_label)

	status_label = Label.new()
	status_label.add_theme_font_size_override("font_size", 13)
	status_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	outer.add_child(status_label)

	var sep = HSeparator.new()
	outer.add_child(sep)

	branches_hbox = HBoxContainer.new()
	branches_hbox.add_theme_constant_override("separation", 20)
	outer.add_child(branches_hbox)

	var sep2 = HSeparator.new()
	outer.add_child(sep2)

	var back_btn = Button.new()
	back_btn.text = "Back to Management"
	back_btn.custom_minimum_size = Vector2(220, 44)
	back_btn.pressed.connect(func():
		get_tree().change_scene_to_file("res://scenes/management_screen.tscn"))
	outer.add_child(back_btn)

	_refresh_resource_label()

func _refresh_resource_label() -> void:
	resource_label.text = "🌾%d 🪙%d  (combined: %d)" % [
		PlayerInventory.resources.get("food", 0),
		PlayerInventory.resources.get("gold", 0),
		PlayerInventory.get_total_resources(),
	]

func _populate_branches() -> void:
	for child in branches_hbox.get_children():
		child.queue_free()

	for branch in TalentTreeData.BRANCHES:
		var nodes = TalentTreeData.get_branch_nodes(branch)
		if nodes.is_empty():
			continue
		branches_hbox.add_child(_make_branch_column(branch, nodes))

func _make_branch_column(branch: String, node_ids: Array) -> VBoxContainer:
	var col = VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	col.custom_minimum_size = Vector2(220, 0)

	var header = Label.new()
	header.text = branch
	header.add_theme_font_size_override("font_size", 16)
	header.add_theme_color_override("font_color", BRANCH_COLORS.get(branch, Color.WHITE))
	col.add_child(header)

	for node_id in node_ids:
		col.add_child(_make_node_card(node_id))

	return col

func _make_node_card(node_id: String) -> PanelContainer:
	var node = TalentTreeData.NODES[node_id]
	var card = PanelContainer.new()

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	card.add_child(vbox)

	var owned = PlayerInventory.unlocked_talents.get(node_id, false)
	var prereq_ok = TalentTreeData.prereq_met(node_id)
	var stage_ok = TalentTreeData.stage_met(node_id)
	var affordable = PlayerInventory.can_afford({"food": 0, "gold": node["cost"]})

	var name_lbl = Label.new()
	name_lbl.text = ("✓ " if owned else "") + node["name"]
	name_lbl.add_theme_font_size_override("font_size", 13)
	name_lbl.add_theme_color_override("font_color",
		Color(0.4, 0.9, 0.4) if owned else (Color(0.9, 0.85, 0.6) if (prereq_ok and stage_ok) else Color(0.5, 0.5, 0.5)))
	vbox.add_child(name_lbl)

	var desc_lbl = Label.new()
	desc_lbl.text = node["desc"]
	desc_lbl.add_theme_font_size_override("font_size", 10)
	desc_lbl.add_theme_color_override("font_color", Color(0.65, 0.65, 0.65))
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(desc_lbl)

	if not owned:
		var requirement_lbl = Label.new()
		var reqs = []
		if not prereq_ok:
			reqs.append("requires: " + TalentTreeData.NODES[node["prereq"]]["name"])
		if not stage_ok:
			reqs.append("requires stage %d+" % node["min_stage"])
		if reqs.size() > 0:
			requirement_lbl.text = " / ".join(reqs)
			requirement_lbl.add_theme_font_size_override("font_size", 10)
			requirement_lbl.add_theme_color_override("font_color", Color(0.9, 0.4, 0.3))
			requirement_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
			vbox.add_child(requirement_lbl)

		var buy_btn = Button.new()
		var can_buy = prereq_ok and stage_ok and affordable
		buy_btn.text = "Unlock (%d 🌾🪙)" % node["cost"] if can_buy or (prereq_ok and stage_ok) else "Locked"
		buy_btn.custom_minimum_size = Vector2(0, 34)
		buy_btn.add_theme_font_size_override("font_size", 11)
		buy_btn.disabled = not can_buy
		buy_btn.add_theme_color_override("font_color", Color(0.4, 0.9, 0.4) if can_buy else Color(0.5, 0.5, 0.5))
		buy_btn.pressed.connect(_on_node_purchase.bind(node_id))
		vbox.add_child(buy_btn)

	return card

func _on_node_purchase(node_id: String) -> void:
	if TalentTreeData.purchase(node_id):
		SaveManager.save_game()
		_set_status("Unlocked: %s!" % TalentTreeData.NODES[node_id]["name"])
		_refresh_resource_label()
		_populate_branches()
	else:
		_set_status("Can't unlock that right now.")

func _set_status(msg: String) -> void:
	if status_label: status_label.text = msg
