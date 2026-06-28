extends Control
class_name TalentTreeScreen

# -------------------------------------------------------
# Talent Screen
#
# Builds its ENTIRE UI tree in code (top bar, grid area,
# description panel) — nothing needs to exist in the .tscn
# except the root Control node with this script attached.
#
# Builds the talent layout from TalentTreeData.NODES +
# TalentTreeLayout.POSITIONS (free-form normalized x/y
# coordinates per node, NOT a grid), so editing either of
# those files is all that's needed to change the tree later.
#
# Layout: scales to fit the available screen space. Every
# node's position is stored as a fraction (0.0-1.0) of the
# available area, so the whole free-form arrangement scales
# proportionally to any screen size while preserving each
# node's position relative to every other node.
#
# Connector lines are drawn on a layer added to the tree BEFORE
# the node buttons layer, so lines always render behind icons —
# they never visually cross over an icon. Each line is also
# pulled back from the icon's center toward its edge, so it
# visibly starts/ends just outside the icon. If a straight line
# would pass close to a third icon (possible in a free-form
# layout), it arcs around that icon instead.
# -------------------------------------------------------

const BRANCH_COLOR := {
	"Gear": Color("d85a30"),
	"Buildings": Color("ba7517"),
	"Recruiting": Color("7f77dd"),
	"Combat": Color("a32d2d"),
	"Economy": Color("639922"),
	"Standalone": Color("5f5e5a"),
	"Dungeon": Color("2d9fa8"),
}

const ICON_DIVISOR := 0.11   # icon size as a fraction of the smaller grid_area dimension

const TALENT_ICON_BASE_PATH := "res://assets/icons/talents/reference/"
const GRID_PADDING := 16.0   # px padding around the whole grid before scaling

# Adjust this to wherever your previous talent screen sent the
# player back to (world map, pause menu, etc).
const BACK_SCENE_PATH := "res://scenes/world_map.tscn"

var node_buttons: Dictionary = {}   # node_id -> Button
var selected_node_id: String = ""
var icon_size: float = 64.0

# UI references, assigned in _build_ui() since nothing exists
# in the .tscn for this screen.
var lines_layer: Control
var nodes_layer: Control
var grid_area: Control
var resource_label: Label
var desc_panel: PanelContainer
var desc_title: Label
var desc_text: Label
var desc_cost: Label
var desc_requirement: Label
var purchase_button: Button
var back_button: Button

func _ready() -> void:
	_build_ui()
	_build_grid_data_only()
	# grid_area.size is (0,0) on the very first frame in Godot 4.4+
	# until containers complete their first layout pass — deferring
	# guarantees real dimensions are available before we position
	# and size the icon buttons against it.
	call_deferred("_finish_initial_layout")
	TutorialRouter.resolve_current_step(self)

	resized.connect(_on_screen_resized)
	get_viewport().size_changed.connect(_on_screen_resized)

	# Catch clicks anywhere on the screen so we can detect "clicked
	# outside any talent icon" and deselect. Runs in the background
	# (doesn't consume the click) so node buttons still work normally.
	gui_input.connect(_on_screen_gui_input)

func _on_screen_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_deselect_talent()

func get_tutorial_target(target_id: String) -> Control:
	match target_id:
		"wilds_pact_talent":
			return node_buttons.get("toggle_invasions", null)
		_:
			return null

func _deselect_talent() -> void:
	if selected_node_id == "":
		return
	selected_node_id = ""
	desc_panel.visible = false

func _finish_initial_layout() -> void:
	_layout_grid()
	_draw_connector_lines()
	_refresh_resource_label()
	_refresh_all_node_states()

func _on_screen_resized() -> void:
	_layout_grid()
	_draw_connector_lines()

# -------------------------------------------------------
# UI construction (top bar, grid area, description panel)
# -------------------------------------------------------

func _build_ui() -> void:
	anchor_right = 1.0
	anchor_bottom = 1.0
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var margin := MarginContainer.new()
	margin.name = "Margin"
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 16)
	add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.name = "VBox"
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	# --- Top bar ---
	var top_bar := HBoxContainer.new()
	top_bar.name = "TopBar"
	top_bar.add_theme_constant_override("separation", 16)
	vbox.add_child(top_bar)

	back_button = Button.new()
	back_button.text = "Back"
	back_button.pressed.connect(_on_back_pressed)
	top_bar.add_child(back_button)

	var title := Label.new()
	title.text = "Talents"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	top_bar.add_child(title)

	resource_label = Label.new()
	resource_label.text = "Resources: 0"
	resource_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	top_bar.add_child(resource_label)

	# --- Grid area ---
	grid_area = Control.new()
	grid_area.name = "GridArea"
	grid_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid_area.clip_contents = true
	vbox.add_child(grid_area)

	lines_layer = Control.new()
	lines_layer.name = "LinesLayer"
	lines_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grid_area.add_child(lines_layer)   # added first = renders behind nodes_layer

	nodes_layer = Control.new()
	nodes_layer.name = "NodesLayer"
	nodes_layer.mouse_filter = Control.MOUSE_FILTER_PASS
	grid_area.add_child(nodes_layer)   # added second = renders on top of lines

	# --- Description panel ---
	desc_panel = PanelContainer.new()
	desc_panel.name = "DescPanel"
	desc_panel.custom_minimum_size = Vector2(0, 110)
	desc_panel.visible = false
	vbox.add_child(desc_panel)

	var desc_vbox := VBoxContainer.new()
	desc_vbox.add_theme_constant_override("separation", 4)
	desc_panel.add_child(desc_vbox)

	desc_title = Label.new()
	desc_title.add_theme_font_size_override("font_size", 16)
	desc_vbox.add_child(desc_title)

	desc_text = Label.new()
	desc_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_text.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8, 1))
	desc_vbox.add_child(desc_text)

	desc_cost = Label.new()
	desc_cost.add_theme_color_override("font_color", Color(0.9, 0.8, 0.4, 1))
	desc_vbox.add_child(desc_cost)

	desc_requirement = Label.new()
	desc_requirement.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_requirement.add_theme_color_override("font_color", Color(0.9, 0.3, 0.3, 1))
	desc_requirement.visible = false
	desc_vbox.add_child(desc_requirement)

	purchase_button = Button.new()
	purchase_button.text = "Purchase"
	purchase_button.size_flags_horizontal = 0
	purchase_button.pressed.connect(_on_purchase_pressed)
	desc_vbox.add_child(purchase_button)

# -------------------------------------------------------
# Grid construction
# -------------------------------------------------------

func _build_grid_data_only() -> void:
	for node_id in TalentTreeData.NODES:
		var btn := _make_node_button(node_id)
		nodes_layer.add_child(btn)
		node_buttons[node_id] = btn

func _make_node_button(node_id: String) -> Button:
	var node_data: Dictionary = TalentTreeData.NODES[node_id]
	var branch: String = node_data["branch"]
	var color: Color = BRANCH_COLOR.get(branch, Color("5f5e5a"))

	var btn := Button.new()
	btn.name = "Node_%s" % node_id
	btn.toggle_mode = false
	btn.clip_text = true
	btn.text = node_data["name"]
	btn.tooltip_text = node_data["desc"]
	btn.focus_mode = Control.FOCUS_NONE
	# Godot 4.4+ re-applies the button's auto text-fit minimum size on
	# its own layout pass, which can stomp a manually-set .size to 0
	# height if no floor is given. Locking size_flags + giving an
	# explicit custom_minimum_size here prevents that; _layout_grid()
	# below updates custom_minimum_size every time it repositions
	# nodes, so the real per-cell size always wins after this.
	btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	btn.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	btn.custom_minimum_size = Vector2(48, 48)

	# Square icon styling — StyleBoxFlat so it tints per-branch and
	# can be visually dimmed for locked nodes without changing size.
	var style_normal := StyleBoxFlat.new()
	style_normal.bg_color = color
	style_normal.corner_radius_top_left = 8
	style_normal.corner_radius_top_right = 8
	style_normal.corner_radius_bottom_left = 8
	style_normal.corner_radius_bottom_right = 8
	style_normal.border_width_left = 2
	style_normal.border_width_right = 2
	style_normal.border_width_top = 2
	style_normal.border_width_bottom = 2
	style_normal.border_color = color.lightened(0.3)

	var style_hover := style_normal.duplicate()
	style_hover.border_color = Color.WHITE

	btn.add_theme_stylebox_override("normal", style_normal)
	btn.add_theme_stylebox_override("hover", style_hover)
	btn.add_theme_stylebox_override("pressed", style_hover)
	btn.add_theme_stylebox_override("disabled", style_normal)
	btn.add_theme_color_override("font_color", Color.WHITE)
	btn.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.55))
	btn.add_theme_font_size_override("font_size", 11)

	btn.pressed.connect(_on_node_pressed.bind(node_id))

	# Art icon — fills the button background when art exists for this node.
	# Text is cleared so the icon is the full visual; tooltip carries the name.
	var icon_texture := _load_talent_icon(node_id)
	if icon_texture:
		var tex := TextureRect.new()
		tex.texture = icon_texture
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.set_anchors_preset(Control.PRESET_FULL_RECT)
		tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.add_child(tex)
		btn.text = ""

	# Diagonal "locked" slash overlay — created once per button, hidden
	# by default, toggled visible in _refresh_node_state(). Lives as a
	# Line2D child purely for visuals; Line2D is a Node2D (not a
	# Control) so it has no mouse_filter and never intercepts input —
	# clicks pass straight through to the Button underneath.
	var slash := Line2D.new()
	slash.name = "LockSlash"
	slash.width = 3.0
	slash.default_color = Color(1, 1, 1, 0.5)
	slash.visible = false
	btn.add_child(slash)

	return btn

func _load_talent_icon(node_id: String) -> Texture2D:
	var icon_path := "%s%s.png" % [TALENT_ICON_BASE_PATH, node_id]
	if not FileAccess.file_exists(icon_path):
		return null
	var image := Image.new()
	if image.load(icon_path) != OK:
		return null
	return ImageTexture.create_from_image(image)

# Redraws the lock-slash line across a button's current size. Called
# whenever a button is resized (in _layout_grid) since the slash's
# endpoints are in the button's local coordinate space.
func _update_lock_slash(btn: Button) -> void:
	var slash := btn.get_node("LockSlash") as Line2D
	if slash == null:
		return
	slash.clear_points()
	var pad: float = btn.size.x * 0.15
	slash.add_point(Vector2(pad, pad))
	slash.add_point(Vector2(btn.size.x - pad, btn.size.y - pad))

# Positions every node button according to TalentTreeLayout.POSITIONS
# (normalized 0.0-1.0 coordinates), scaling them against the actual
# grid_area size — so the whole free-form layout scales to fit the
# screen instead of using fixed pixels, while preserving every node's
# relative position to every other node exactly as designed.
func _layout_grid() -> void:
	var available_w: float = grid_area.size.x - GRID_PADDING * 2.0
	var available_h: float = grid_area.size.y - GRID_PADDING * 2.0
	if available_w <= 0 or available_h <= 0:
		return

	# Icon size scales off the smaller dimension so icons stay square
	# and never get cramped if the screen is much wider than tall (or
	# vice versa). ICON_DIVISOR controls how "dense" the layout feels —
	# tuned so 21 nodes at typical screen sizes land around 48-90px.
	icon_size = clamp(min(available_w, available_h) * ICON_DIVISOR, 40.0, 110.0)

	for node_id in node_buttons:
		var btn: Button = node_buttons[node_id]
		var norm: Vector2 = TalentTreeLayout.get_position(node_id)
		var center := Vector2(
			GRID_PADDING + norm.x * available_w,
			GRID_PADDING + norm.y * available_h
		)
		btn.position = center - Vector2(icon_size, icon_size) / 2.0
		btn.custom_minimum_size = Vector2(icon_size, icon_size)
		btn.size = Vector2(icon_size, icon_size)
		_update_lock_slash(btn)
		btn.add_theme_font_size_override("font_size", clamp(int(icon_size * 0.13), 9, 14))

	nodes_layer.custom_minimum_size = Vector2(
		GRID_PADDING * 2 + available_w,
		GRID_PADDING * 2 + available_h
	)
	lines_layer.custom_minimum_size = nodes_layer.custom_minimum_size

# -------------------------------------------------------
# Connector lines (prereq -> dependent), drawn BEHIND icons
# -------------------------------------------------------

func _draw_connector_lines() -> void:
	for child in lines_layer.get_children():
		child.queue_free()

	var pull_back: float = icon_size / 2.0 + 4.0

	for node_id in TalentTreeData.NODES:
		var node_data: Dictionary = TalentTreeData.NODES[node_id]
		var prereq_id: String = node_data["prereq"]
		if prereq_id == "" or not TalentTreeLayout.POSITIONS.has(prereq_id):
			continue

		var from_center := _node_center_px(prereq_id)
		var to_center := _node_center_px(node_id)

		# If some other icon's center sits close to the straight line
		# between this prereq and its dependent (a near-miss given the
		# free-form layout), route the connector in a small arc so it
		# clears that icon instead of cutting through it.
		var passes_through := _line_passes_near_other_node(node_id, prereq_id, from_center, to_center)

		if not passes_through:
			_draw_arrow(from_center, to_center, pull_back)
		else:
			_draw_arced_arrow(from_center, to_center, pull_back)

func _node_center_px(node_id: String) -> Vector2:
	var btn: Button = node_buttons[node_id]
	return btn.position + btn.size / 2.0

# Returns true if some other node's icon center lies close enough to
# the straight segment between from_pt and to_pt that a direct line
# would visually cut through it.
func _line_passes_near_other_node(self_id: String, prereq_id: String, from_pt: Vector2, to_pt: Vector2) -> bool:
	var threshold: float = icon_size * 0.65
	for other_id in TalentTreeLayout.POSITIONS:
		if other_id == self_id or other_id == prereq_id:
			continue
		var p := _node_center_px(other_id)
		var d := _point_segment_distance(p, from_pt, to_pt)
		if d < threshold:
			return true
	return false

func _point_segment_distance(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var ab_len_sq := ab.length_squared()
	if ab_len_sq < 0.0001:
		return p.distance_to(a)
	var t: float = clamp((p - a).dot(ab) / ab_len_sq, 0.08, 0.92)
	var closest := a + ab * t
	return p.distance_to(closest)

func _draw_arrow(from_pt: Vector2, to_pt: Vector2, pull_back: float) -> void:
	var dir := (to_pt - from_pt)
	var dist := dir.length()
	if dist < 0.001:
		return
	dir = dir / dist
	var start := from_pt + dir * pull_back
	var end := to_pt - dir * pull_back

	var line := Line2D.new()
	line.width = 3.0
	line.default_color = Color(1, 1, 1, 0.35)
	line.add_point(start)
	line.add_point(end)
	lines_layer.add_child(line)

	_add_arrowhead(end, dir)

# Routes the connector in a shallow arc that lifts above (or beside)
# the row/column so it clears any icon sitting between the two
# endpoints, instead of drawing straight through it.
func _draw_arced_arrow(from_pt: Vector2, to_pt: Vector2, pull_back: float) -> void:
	var dir := (to_pt - from_pt)
	var dist := dir.length()
	if dist < 0.001:
		return
	dir = dir / dist
	var start := from_pt + dir * pull_back
	var end := to_pt - dir * pull_back

	# Perpendicular offset, lifted toward the top of the grid so the
	# arc clears the icon row it's skipping over.
	var perp := Vector2(-dir.y, dir.x)
	if perp.y > 0:
		perp = -perp
	var arc_height: float = icon_size * 0.55
	var mid := (start + end) / 2.0 + perp * arc_height

	var curve := Curve2D.new()
	curve.add_point(start)
	curve.add_point(mid)
	curve.add_point(end)
	var points := curve.tessellate(4, 4)

	var line := Line2D.new()
	line.width = 3.0
	line.default_color = Color(1, 1, 1, 0.35)
	for p in points:
		line.add_point(p)
	lines_layer.add_child(line)

	# Arrowhead direction follows the final segment of the arc, not
	# the overall straight-line direction, so it points correctly
	# into the destination icon.
	var final_dir := (points[points.size() - 1] - points[points.size() - 2])
	if final_dir.length() > 0.001:
		final_dir = final_dir.normalized()
	else:
		final_dir = dir
	_add_arrowhead(end, final_dir)

func _add_arrowhead(tip: Vector2, dir: Vector2) -> void:
	var arrow_len: float = 10.0
	var arrow_width: float = 7.0
	var back := tip - dir * arrow_len
	var perp := Vector2(-dir.y, dir.x)
	var left := back + perp * (arrow_width / 2.0)
	var right := back - perp * (arrow_width / 2.0)

	var head := Line2D.new()
	head.width = 3.0
	head.default_color = Color(1, 1, 1, 0.35)
	head.add_point(left)
	head.add_point(tip)
	head.add_point(right)
	lines_layer.add_child(head)

# -------------------------------------------------------
# Node state (locked / available / owned)
# -------------------------------------------------------

func _refresh_all_node_states() -> void:
	for node_id in node_buttons:
		_refresh_node_state(node_id)

func _refresh_node_state(node_id: String) -> void:
	var btn: Button = node_buttons[node_id]
	var owned: bool = PlayerInventory.unlocked_talents.get(node_id, false)
	var prereq_ok: bool = TalentTreeData.prereq_met(node_id)
	var stage_ok: bool = TalentTreeData.stage_met(node_id)
	var locked: bool = not prereq_ok or not stage_ok

	if locked and not owned:
		# Dimmed but still clearly visible/readable, not fully greyed out.
		btn.modulate = Color(1, 1, 1, 0.55)
	else:
		btn.modulate = Color(1, 1, 1, 1)
	btn.disabled = false   # still clickable so the description (and lock reason) can be viewed

	var slash := btn.get_node_or_null("LockSlash")
	if slash:
		slash.visible = locked and not owned

	# Owned nodes get a highlighted border.
	if owned:
		var owned_style: StyleBoxFlat = btn.get_theme_stylebox("normal").duplicate()
		owned_style.border_color = Color("9fe1cb")
		owned_style.border_width_left = 3
		owned_style.border_width_right = 3
		owned_style.border_width_top = 3
		owned_style.border_width_bottom = 3
		btn.add_theme_stylebox_override("normal", owned_style)
		btn.add_theme_stylebox_override("disabled", owned_style)

# -------------------------------------------------------
# Selection / description panel
# -------------------------------------------------------

func _on_node_pressed(node_id: String) -> void:
	selected_node_id = node_id
	_show_description(node_id)

func _show_description(node_id: String) -> void:
	var node_data: Dictionary = TalentTreeData.NODES[node_id]
	desc_panel.visible = true
	desc_title.text = node_data["name"]
	desc_text.text = node_data["desc"]

	var owned: bool = PlayerInventory.unlocked_talents.get(node_id, false)
	var prereq_ok: bool = TalentTreeData.prereq_met(node_id)
	var stage_ok: bool = TalentTreeData.stage_met(node_id)
	var cost: int = TalentTreeData.get_scaled_cost(node_id)
	var can_afford: bool = PlayerInventory.can_afford({"gold": cost})

	var normal_color := Color(0.9, 0.8, 0.4, 1)
	var red_color := Color(0.9, 0.3, 0.3, 1)

	if owned:
		desc_cost.text = "Owned"
		desc_cost.add_theme_color_override("font_color", normal_color)
		desc_requirement.visible = false
		purchase_button.visible = false
	else:
		desc_cost.text = "Free" if cost <= 0 else "Cost: %d 🪙" % cost
		desc_cost.add_theme_color_override("font_color", red_color if not can_afford else normal_color)

		# Requirement line — only shown (and only red) when a prereq
		# or stage gate isn't met yet.
		if not prereq_ok:
			var prereq_name: String = TalentTreeData.NODES.get(node_data["prereq"], {}).get("name", node_data["prereq"])
			desc_requirement.text = "Requires: %s" % prereq_name
			desc_requirement.visible = true
		elif not stage_ok:
			desc_requirement.text = "Requires Stage %d" % node_data["min_stage"]
			desc_requirement.visible = true
		else:
			desc_requirement.visible = false

		purchase_button.visible = true
		purchase_button.disabled = not TalentTreeData.can_purchase(node_id)

func _on_purchase_pressed() -> void:
	if selected_node_id == "":
		return
	if TalentTreeData.purchase(selected_node_id):
		if selected_node_id == "toggle_invasions":
			TutorialRouter.advance_step("talents_wilds_pact")
		_refresh_resource_label()
		_refresh_all_node_states()
		_show_description(selected_node_id)

func _refresh_resource_label() -> void:
	resource_label.text = "Gold: %d" % int(PlayerInventory.resources.get("gold", 0))

# -------------------------------------------------------
# Navigation
# -------------------------------------------------------

func _on_back_pressed() -> void:
	get_tree().change_scene_to_file(BACK_SCENE_PATH)
