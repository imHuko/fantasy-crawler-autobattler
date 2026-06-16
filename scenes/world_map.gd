extends Node2D

# -------------------------------------------------------
# World Map — procedurally generated zone-based conquest
# -------------------------------------------------------

const MAP_W = 900
const MAP_H = 580

const ZONE_TYPES = ["city", "forest", "dungeon", "ruins", "mountain"]
const ZONE_TYPE_COLORS = {
	"city":     Color(0.90, 0.80, 0.30),
	"forest":   Color(0.25, 0.70, 0.30),
	"dungeon":  Color(0.50, 0.20, 0.60),
	"ruins":    Color(0.55, 0.45, 0.35),
	"mountain": Color(0.60, 0.60, 0.65),
}
const ZONE_TYPE_ICONS = {
	"city":     "⬛",
	"forest":   "▲",
	"dungeon":  "●",
	"ruins":    "◆",
	"mountain": "▲",
}

const OWNER_COLORS = {
	"player":  Color(0.30, 0.60, 1.00),
	"neutral": Color(0.50, 0.50, 0.50),
}

const ZONE_NAMES = [
	"Ashveil", "Stonemark", "Duskhaven", "Ironfeld", "Crestmoor",
	"Thornwall", "Embervast", "Greywatch", "Coldspire", "Mirewood",
	"Ravensholm", "Dustgate", "Cinderpass", "Hallowfen", "Bleakhurst",
	"Vaelmore", "Grimtide", "Sunderveil", "Brackmore", "Frostwall",
	"Saltmere", "Ironveil", "Ashenford", "Grimhold", "Dreadmere",
]

# Zone data structure
# { id, name, type, pos, owner, troops, connections, buildings,
#   dist_from_start, enemy_strength, troop_queue }
const TRAVEL_SPEED = 120.0  # distance units per turn

var zones: Array = []
var connections: Array = []   # pairs of zone ids
var selected_zone_id: int = -1
var popup_panel: Control = null
var turn: int = 1
var pending_attacks: Array = []   # {zone_id, turns_until, force_size}
var marching_troops: Array = []   # {troop_name, from_zone, to_zone, turns_left}
var mandatory_battle_queue: Array = []   # attacks that have triggered and must be resolved before continuing
var end_turn_button_ref: Button = null

# UI
var zone_nodes: Array = []
var connection_lines: Node2D
var hud_turn: Label
var hud_diff: Label
var notification_label: Label

func _ready() -> void:
	_generate_map()
	_build_ui()
	_apply_pending_battle_result()
	_draw_map()
	_refresh_hud()

	# If there are still mandatory battles queued (multiple simultaneous attacks),
	# force the next one immediately — no map interaction allowed until resolved
	if mandatory_battle_queue.size() > 0:
		call_deferred("_launch_next_mandatory_battle")

func _apply_pending_battle_result() -> void:
	var result = PlayerInventory.last_battle_result
	if result == "": return

	var zone_id = PlayerInventory.last_battle_zone
	var was_conquest = PlayerInventory.last_battle_was_conquest

	if zone_id < 0 or zone_id >= zones.size():
		PlayerInventory.last_battle_result = ""
		return

	if result == "won":
		zones[zone_id]["owner"] = "player"
		if was_conquest:
			_notify("Victory! %s is now under your control." % zones[zone_id]["name"])
		else:
			_notify("%s successfully defended!" % zones[zone_id]["name"])
	elif result == "lost":
		if was_conquest:
			_notify("The conquest of %s failed. The wilds remain in control." % zones[zone_id]["name"])
			# Zone stays neutral, no further setback for a failed conquest attempt
		else:
			# Defending and lost — zone falls back to neutral, troops there are lost
			zones[zone_id]["owner"] = "neutral"
			zones[zone_id]["troops"].clear()
			zones[zone_id]["buildings"].clear()
			_notify("%s has fallen to the wilds! All stationed troops and buildings lost." % zones[zone_id]["name"])
	elif result == "retreat":
		if not was_conquest:
			# Retreating from a defense = losing the zone too, but troops survive
			zones[zone_id]["owner"] = "neutral"
			_notify("You retreated from %s. The zone has fallen." % zones[zone_id]["name"])

	# Clear any pending attack warnings for this zone since it's now resolved
	var remaining_attacks = []
	for pa in pending_attacks:
		if pa["zone_id"] != zone_id:
			remaining_attacks.append(pa)
	pending_attacks = remaining_attacks

	# Pop this battle from the mandatory queue if it was one
	var remaining_queue = []
	for mb in mandatory_battle_queue:
		if mb["zone_id"] != zone_id:
			remaining_queue.append(mb)
	mandatory_battle_queue = remaining_queue

	PlayerInventory.last_battle_result = ""
	PlayerInventory.current_battle_zone = -1
	PlayerInventory.conquering_zone = false
	PlayerInventory.current_battle_zone_troop_names = []

# -------------------------------------------------------
# Map Generation
# -------------------------------------------------------
func _generate_map() -> void:
	var rng = RandomNumberGenerator.new()
	rng.seed = PlayerInventory.map_seed

	var zone_count = PlayerInventory.difficulty_settings.get("zone_count", 13)

	# Place starting zone left-center
	var start_pos = Vector2(120, MAP_H / 2)
	zones.append(_make_zone(0, "city", start_pos, "player", "Your City"))
	zones[0]["dist_from_start"] = 0

	# Station all starting troops at the home city
	for troop in PlayerInventory.troop_roster:
		zones[0]["troops"].append(troop.troop_name)

	# Generate remaining zones
	var used_positions = [start_pos]
	var attempts = 0
	while zones.size() < zone_count and attempts < 500:
		attempts += 1
		var pos = Vector2(
			rng.randf_range(80, MAP_W - 80),
			rng.randf_range(60, MAP_H - 60)
		)
		# Ensure minimum spacing
		var too_close = false
		for up in used_positions:
			if pos.distance_to(up) < 100:
				too_close = true
				break
		if too_close: continue

		var zone_id = zones.size()
		var dist = pos.distance_to(start_pos)
		var ztype = ZONE_TYPES[rng.randi() % ZONE_TYPES.size()]
		var zname = ZONE_NAMES[zone_id % ZONE_NAMES.size()]
		var owner = "neutral"

		var zone = _make_zone(zone_id, ztype, pos, owner, zname)
		zone["dist_from_start"] = dist
		zone["enemy_strength"] = int(dist / 80.0)
		zones.append(zone)
		used_positions.append(pos)

	# Connect zones — each zone connects to 2-3 nearest neighbors
	for i in range(zones.size()):
		var distances = []
		for j in range(zones.size()):
			if i == j: continue
			distances.append({"id": j, "dist": zones[i]["pos"].distance_to(zones[j]["pos"])})
		distances.sort_custom(func(a, b): return a["dist"] < b["dist"])

		var connect_count = rng.randi_range(2, 3)
		for k in range(min(connect_count, distances.size())):
			var pair = [min(i, distances[k]["id"]), max(i, distances[k]["id"])]
			if pair not in connections and distances[k]["dist"] < 280:
				connections.append(pair)
				zones[i]["connections"].append(distances[k]["id"])
				zones[distances[k]["id"]]["connections"].append(i)

	# Ensure start zone is connected to at least one other
	if zones[0]["connections"].is_empty():
		var nearest_id = 1
		connections.append([0, 1])
		zones[0]["connections"].append(1)
		zones[1]["connections"].append(0)

func _make_zone(id: int, ztype: String, pos: Vector2, owner: String, zname: String) -> Dictionary:
	return {
		"id": id, "name": zname, "type": ztype,
		"pos": pos, "owner": owner,
		"troops": [] if owner != "player" else [],
		"connections": [],
		"buildings": [],
		"dist_from_start": 0,
		"enemy_strength": 0,
		"troop_queue": [],
	}

# -------------------------------------------------------
# Draw Map
# -------------------------------------------------------
func _build_ui() -> void:
	var bg = ColorRect.new()
	bg.color = Color(0.07, 0.08, 0.10)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# Draw connection lines first (behind zones)
	connection_lines = Node2D.new()
	add_child(connection_lines)

	# Top HUD
	var hud = CanvasLayer.new()
	add_child(hud)

	var top = PanelContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.size.y = 44
	hud.add_child(top)

	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 20)
	top.add_child(hbox)

	var title = Label.new()
	title.text = PlayerInventory.player_name + "'s Campaign"
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
	hbox.add_child(title)

	hud_turn = Label.new()
	hud_turn.add_theme_font_size_override("font_size", 14)
	hud_turn.add_theme_color_override("font_color", Color(0.7, 0.9, 0.7))
	hbox.add_child(hud_turn)

	hud_diff = Label.new()
	hud_diff.add_theme_font_size_override("font_size", 13)
	hbox.add_child(hud_diff)

	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(spacer)

	notification_label = Label.new()
	notification_label.add_theme_font_size_override("font_size", 13)
	notification_label.add_theme_color_override("font_color", Color(1, 0.5, 0.3))
	hbox.add_child(notification_label)

	# End Turn button
	var end_turn_btn = Button.new()
	end_turn_btn.text = "End Turn >"
	end_turn_btn.custom_minimum_size = Vector2(120, 32)
	end_turn_btn.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
	end_turn_btn.disabled = mandatory_battle_queue.size() > 0
	end_turn_btn.pressed.connect(_on_end_turn)
	hbox.add_child(end_turn_btn)
	end_turn_button_ref = end_turn_btn

	# Back to management
	var mgmt_btn = Button.new()
	mgmt_btn.text = "Management"
	mgmt_btn.custom_minimum_size = Vector2(110, 32)
	mgmt_btn.pressed.connect(func():
		SaveManager.save_game()
		get_tree().change_scene_to_file("res://scenes/management_screen.tscn"))
	hbox.add_child(mgmt_btn)

func _draw_map() -> void:
	# Clear old zone nodes
	for zn in zone_nodes:
		if is_instance_valid(zn): zn.queue_free()
	zone_nodes.clear()
	for c in connection_lines.get_children():
		c.queue_free()

	# Draw connections
	for pair in connections:
		var z1 = zones[pair[0]]
		var z2 = zones[pair[1]]
		var line = Line2D.new()
		line.points = [z1["pos"] + Vector2(0, 44), z2["pos"] + Vector2(0, 44)]
		line.width = 2.0
		line.default_color = Color(0.3, 0.3, 0.4, 0.7)
		connection_lines.add_child(line)

	# Draw zones
	for zone in zones:
		var znode = _make_zone_node(zone)
		add_child(znode)
		zone_nodes.append(znode)

func _make_zone_node(zone: Dictionary) -> Control:
	var container = Control.new()
	container.position = zone["pos"] + Vector2(0, 44)
	container.custom_minimum_size = Vector2(64, 64)

	# Zone circle background
	var circle = ColorRect.new()
	circle.size = Vector2(44, 44)
	circle.position = Vector2(-22, -22)
	circle.color = OWNER_COLORS[zone["owner"]].darkened(0.4)

	# Highlight if selected
	if zone["id"] == selected_zone_id:
		circle.color = Color(1, 1, 0, 0.3)

	container.add_child(circle)

	# Zone type icon
	var icon = Label.new()
	icon.text = ZONE_TYPE_ICONS[zone["type"]]
	icon.add_theme_font_size_override("font_size", 20)
	icon.add_theme_color_override("font_color", ZONE_TYPE_COLORS[zone["type"]])
	icon.position = Vector2(-10, -16)
	container.add_child(icon)

	# Owner indicator dot
	var dot = ColorRect.new()
	dot.size = Vector2(10, 10)
	dot.position = Vector2(14, -22)
	dot.color = OWNER_COLORS[zone["owner"]]
	container.add_child(dot)

	# Zone name
	var name_lbl = Label.new()
	name_lbl.text = zone["name"]
	name_lbl.add_theme_font_size_override("font_size", 10)
	name_lbl.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	name_lbl.position = Vector2(-30, 24)
	name_lbl.custom_minimum_size = Vector2(60, 0)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	container.add_child(name_lbl)

	# Troop count
	if zone["troops"].size() > 0:
		var troop_lbl = Label.new()
		troop_lbl.text = "⚔%d" % zone["troops"].size()
		troop_lbl.add_theme_font_size_override("font_size", 9)
		troop_lbl.add_theme_color_override("font_color", Color(0.6, 0.9, 1.0))
		troop_lbl.position = Vector2(-12, 10)
		container.add_child(troop_lbl)

	# Click area
	var btn = Button.new()
	btn.flat = true
	btn.size = Vector2(64, 64)
	btn.position = Vector2(-32, -32)
	btn.pressed.connect(_on_zone_clicked.bind(zone["id"]))
	container.add_child(btn)

	# Pending attack warning
	for attack in pending_attacks:
		if attack["zone_id"] == zone["id"]:
			var warn = Label.new()
			warn.text = "⚠%d" % attack["turns_until"]
			warn.add_theme_font_size_override("font_size", 11)
			warn.add_theme_color_override("font_color", Color(1, 0.3, 0.3))
			warn.position = Vector2(-8, -36)
			container.add_child(warn)

	# Incoming troops marker
	for m in marching_troops:
		if m["to_zone"] == zone["id"]:
			var march_lbl = Label.new()
			march_lbl.text = "→%d" % m["turns_left"]
			march_lbl.add_theme_font_size_override("font_size", 10)
			march_lbl.add_theme_color_override("font_color", Color(0.5, 0.9, 1.0))
			march_lbl.position = Vector2(16, 16)
			container.add_child(march_lbl)

	return container

# -------------------------------------------------------
# Zone Popup
# -------------------------------------------------------
func _on_zone_clicked(zone_id: int) -> void:
	selected_zone_id = zone_id
	_close_popup()
	_draw_map()
	_open_popup(zones[zone_id])

func _open_popup(zone: Dictionary) -> void:
	popup_panel = PanelContainer.new()

	# Position popup — keep on screen
	var px = min(zone["pos"].x + 50, MAP_W - 280)
	var py = max(zone["pos"].y + 44, 60)
	popup_panel.position = Vector2(px, py)
	popup_panel.custom_minimum_size = Vector2(260, 0)
	add_child(popup_panel)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	popup_panel.add_child(vbox)

	# Header
	var header = Label.new()
	header.text = "%s %s" % [ZONE_TYPE_ICONS[zone["type"]], zone["name"]]
	header.add_theme_font_size_override("font_size", 16)
	header.add_theme_color_override("font_color", ZONE_TYPE_COLORS[zone["type"]])
	vbox.add_child(header)

	var owner_lbl = Label.new()
	owner_lbl.text = "Owner: %s" % zone["owner"].capitalize()
	owner_lbl.add_theme_color_override("font_color", OWNER_COLORS[zone["owner"]])
	owner_lbl.add_theme_font_size_override("font_size", 12)
	vbox.add_child(owner_lbl)

	var type_lbl = Label.new()
	type_lbl.text = "Type: %s  |  Threat: %d" % [zone["type"].capitalize(), zone["enemy_strength"]]
	type_lbl.add_theme_font_size_override("font_size", 11)
	type_lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	vbox.add_child(type_lbl)

	# Troops
	var troop_lbl = Label.new()
	if zone["troops"].is_empty():
		troop_lbl.text = "Troops: None"
	else:
		var names = []
		for t in zone["troops"]:
			names.append(t if t is String else t.get("name", "Unknown"))
		troop_lbl.text = "Troops: " + ", ".join(names)
	troop_lbl.add_theme_font_size_override("font_size", 11)
	troop_lbl.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0))
	troop_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(troop_lbl)

	# Incoming troops
	var incoming = []
	for m in marching_troops:
		if m["to_zone"] == zone["id"]:
			incoming.append("%s (%d turn%s)" % [m["troop_name"], m["turns_left"], "s" if m["turns_left"] != 1 else ""])
	if incoming.size() > 0:
		var incoming_lbl = Label.new()
		incoming_lbl.text = "Incoming: " + ", ".join(incoming)
		incoming_lbl.add_theme_font_size_override("font_size", 10)
		incoming_lbl.add_theme_color_override("font_color", Color(0.5, 0.9, 1.0))
		incoming_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
		vbox.add_child(incoming_lbl)

	# Buildings
	var build_lbl = Label.new()
	build_lbl.text = "Buildings: " + (", ".join(zone["buildings"]) if not zone["buildings"].is_empty() else "None")
	build_lbl.add_theme_font_size_override("font_size", 11)
	build_lbl.add_theme_color_override("font_color", Color(0.85, 0.75, 0.5))
	vbox.add_child(build_lbl)

	var sep = HSeparator.new()
	vbox.add_child(sep)

	# Action buttons based on owner
	if zone["owner"] == "player":
		_add_popup_btn(vbox, "Move Troops Here", Color(0.4, 0.8, 1.0), _on_move_troops.bind(zone["id"]))
		_add_popup_btn(vbox, "Build Here", Color(0.85, 0.75, 0.4), _on_build.bind(zone["id"]))
		_add_popup_btn(vbox, "Enter Dungeon", Color(0.65, 0.3, 0.9), func():
			SaveManager.save_game()
			get_tree().change_scene_to_file("res://scenes/action_dungeon.tscn"))
	elif zone["owner"] == "neutral":
		var adj = _is_adjacent_to_player(zone["id"]) or zone["id"] == 0
		if adj:
			var threat_str = "Threat Level %d" % zone["enemy_strength"]
			_add_popup_btn(vbox, "Conquer Zone  (%s)" % threat_str,
				Color(0.4, 0.9, 0.4), _on_conquer.bind(zone["id"]))
		else:
			var hint = Label.new()
			hint.text = "Must conquer adjacent zones first"
			hint.add_theme_font_size_override("font_size", 11)
			hint.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
			vbox.add_child(hint)

	# Close button
	var close_btn = Button.new()
	close_btn.text = "Close"
	close_btn.pressed.connect(_close_popup)
	vbox.add_child(close_btn)

func _add_popup_btn(parent: VBoxContainer, text: String, col: Color, callback: Callable) -> void:
	var btn = Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(0, 34)
	btn.add_theme_color_override("font_color", col)
	btn.pressed.connect(callback)
	parent.add_child(btn)

func _close_popup() -> void:
	if popup_panel and is_instance_valid(popup_panel):
		popup_panel.queue_free()
		popup_panel = null

# -------------------------------------------------------
# Zone Actions
# -------------------------------------------------------
func _is_adjacent_to_player(zone_id: int) -> bool:
	for conn in zones[zone_id]["connections"]:
		if zones[conn]["owner"] == "player":
			return true
	return false

func _on_battle_won(zone_id: int) -> void:
	zones[zone_id]["owner"] = "player"
	_notify("Conquered %s!" % zones[zone_id]["name"])
	_draw_map()

func _on_battle_lost(zone_id: int) -> void:
	# If defending — zone reverts to neutral
	if not PlayerInventory.conquering_zone:
		zones[zone_id]["owner"] = "neutral"
		_notify("%s was lost to the wilds!" % zones[zone_id]["name"])
	_draw_map()

func _on_conquer(zone_id: int) -> void:
	_close_popup()
	# Always triggers a battle — zone has guards based on distance
	PlayerInventory.current_battle_zone = zone_id
	PlayerInventory.current_attack_force = max(0.5, zones[zone_id]["enemy_strength"] * 0.3)
	PlayerInventory.conquering_zone = true

	# Conquering uses troops from the nearest adjacent zone you already own,
	# since the target zone itself has no player troops stationed yet.
	var staging_zone_id = -1
	for conn_id in zones[zone_id]["connections"]:
		if zones[conn_id]["owner"] == "player":
			staging_zone_id = conn_id
			break
	if staging_zone_id == -1:
		staging_zone_id = 0  # fallback to home city

	PlayerInventory.set_battle_roster_from_zone_troops(zones[staging_zone_id]["troops"])
	SaveManager.save_game()
	get_tree().change_scene_to_file("res://scenes/defense_scene.tscn")



func _on_move_troops(zone_id: int) -> void:
	_close_popup()
	_open_move_troops_panel(zone_id)

func _on_build(zone_id: int) -> void:
	_close_popup()
	_open_build_panel(zone_id)

# -------------------------------------------------------
# Move Troops Panel
# -------------------------------------------------------
func _open_move_troops_panel(target_zone_id: int) -> void:
	popup_panel = PanelContainer.new()
	popup_panel.position = Vector2(MAP_W / 2 - 160, MAP_H / 2 - 100)
	popup_panel.custom_minimum_size = Vector2(320, 0)
	add_child(popup_panel)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	popup_panel.add_child(vbox)

	var title = Label.new()
	title.text = "Move Troops to " + zones[target_zone_id]["name"]
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
	vbox.add_child(title)

	var hint = Label.new()
	hint.text = "Select troops from your roster to station here."
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	vbox.add_child(hint)

	for i in range(PlayerInventory.troop_roster.size()):
		var troop = PlayerInventory.troop_roster[i]
		var already_here = troop.troop_name in zones[target_zone_id]["troops"]

		var btn = Button.new()
		btn.text = "%s [%s]%s" % [
			troop.troop_name,
			troop.get_type_name(),
			" ✓ HERE" if already_here else ""
		]
		btn.add_theme_font_size_override("font_size", 12)
		btn.add_theme_color_override("font_color",
			Color(0.4, 1.0, 0.4) if already_here else Color(0.8, 0.8, 0.8))
		btn.pressed.connect(_on_assign_troop.bind(troop.troop_name, target_zone_id))
		vbox.add_child(btn)

	var close_btn = Button.new()
	close_btn.text = "Done"
	close_btn.pressed.connect(_close_popup)
	vbox.add_child(close_btn)

func _on_assign_troop(troop_name: String, zone_id: int) -> void:
	# Find which zone this troop is currently in (if any)
	var from_zone_id = -1
	for z in zones:
		if troop_name in z["troops"]:
			from_zone_id = z["id"]
			break

	# Cancel any existing march for this troop
	for m in marching_troops.duplicate():
		if m["troop_name"] == troop_name:
			marching_troops.erase(m)

	if from_zone_id == zone_id:
		_close_popup()
		_notify("%s is already stationed there." % troop_name)
		return

	# Calculate travel time based on distance
	var travel_turns = 0
	if from_zone_id >= 0:
		var dist = zones[from_zone_id]["pos"].distance_to(zones[zone_id]["pos"])
		travel_turns = max(1, int(ceil(dist / TRAVEL_SPEED)))
	else:
		travel_turns = 1  # unassigned troop, quick mobilization

	if travel_turns <= 1 and from_zone_id >= 0:
		# Close enough — arrives same turn
		zones[from_zone_id]["troops"].erase(troop_name)
		zones[zone_id]["troops"].append(troop_name)
		_notify("%s stationed at %s" % [troop_name, zones[zone_id]["name"]])
	else:
		# Remove from origin immediately (troop is "marching")
		if from_zone_id >= 0:
			zones[from_zone_id]["troops"].erase(troop_name)
		marching_troops.append({
			"troop_name": troop_name, "from_zone": from_zone_id,
			"to_zone": zone_id, "turns_left": travel_turns
		})
		_notify("%s marching to %s \u2014 arrives in %d turn(s)" % [troop_name, zones[zone_id]["name"], travel_turns])

	_close_popup()
	_draw_map()

# -------------------------------------------------------
# Build Panel
# -------------------------------------------------------
const BUILDINGS = {
	"Barracks":   {"desc": "Unlocks an additional troop slot.", "cost": 3},
	"Watchtower": {"desc": "Gives +1 turn warning on incoming attacks.", "cost": 2},
	"Farm":       {"desc": "Generates food resources each turn.", "cost": 2},
	"Dungeon":    {"desc": "Allows dungeon runs from this zone.", "cost": 4},
}

func _open_build_panel(zone_id: int) -> void:
	popup_panel = PanelContainer.new()
	popup_panel.position = Vector2(MAP_W / 2 - 160, MAP_H / 2 - 120)
	popup_panel.custom_minimum_size = Vector2(320, 0)
	add_child(popup_panel)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	popup_panel.add_child(vbox)

	var title = Label.new()
	title.text = "Build in " + zones[zone_id]["name"]
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
	vbox.add_child(title)

	for bname in BUILDINGS:
		var b = BUILDINGS[bname]
		var already_built = bname in zones[zone_id]["buildings"]

		var hbox = HBoxContainer.new()
		vbox.add_child(hbox)

		var btn = Button.new()
		btn.text = bname + (" ✓" if already_built else " (Cost: %d turns)" % b["cost"])
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.add_theme_font_size_override("font_size", 12)
		btn.disabled = already_built
		btn.add_theme_color_override("font_color",
			Color(0.4, 0.8, 0.4) if already_built else Color(0.85, 0.75, 0.4))
		btn.pressed.connect(_on_build_selected.bind(bname, zone_id))
		hbox.add_child(btn)

		var desc = Label.new()
		desc.text = b["desc"]
		desc.add_theme_font_size_override("font_size", 10)
		desc.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD
		desc.custom_minimum_size = Vector2(0, 0)
		vbox.add_child(desc)

	var close_btn = Button.new()
	close_btn.text = "Cancel"
	close_btn.pressed.connect(_close_popup)
	vbox.add_child(close_btn)

func _on_build_selected(building_name: String, zone_id: int) -> void:
	if building_name not in zones[zone_id]["buildings"]:
		zones[zone_id]["buildings"].append(building_name)
		if building_name == "Barracks":
			PlayerInventory.unlock_troop_slot()
	_close_popup()
	_draw_map()
	_notify("Built %s in %s!" % [building_name, zones[zone_id]["name"]])

# -------------------------------------------------------
# Turn System
# -------------------------------------------------------
func _on_end_turn() -> void:
	_close_popup()
	turn += 1
	_process_marching_troops()
	_process_enemy_expansion()
	_process_pending_attacks()
	_maybe_spawn_attack()
	_refresh_hud()
	_draw_map()

func _process_marching_troops() -> void:
	var arrived = []
	for m in marching_troops:
		m["turns_left"] -= 1
		if m["turns_left"] <= 0:
			zones[m["to_zone"]]["troops"].append(m["troop_name"])
			_notify("%s arrived at %s" % [m["troop_name"], zones[m["to_zone"]]["name"]])
			arrived.append(m)
	for a in arrived:
		marching_troops.erase(a)

func _process_enemy_expansion() -> void:
	# The wilds don't expand — neutral zones stay neutral until conquered
	# Only zones the player loses revert to neutral
	pass

func _maybe_spawn_attack() -> void:
	var diff_settings = PlayerInventory.difficulty_settings
	var attack_chance = diff_settings.get("attack_frequency", 0.6) * 0.25
	var warning = int(diff_settings.get("warning_turns", 3))
	var max_simultaneous = int(diff_settings.get("max_simultaneous_attacks", 1))

	if pending_attacks.size() >= max_simultaneous: return
	if randf() > attack_chance: return

	# Attacks come from the wilds — any player zone adjacent to a neutral zone
	var targets = []
	for zone in zones:
		if zone["owner"] != "player": continue
		var already_pending = false
		for pa in pending_attacks:
			if pa["zone_id"] == zone["id"]: already_pending = true
		if already_pending: continue
		for conn_id in zone["connections"]:
			if zones[conn_id]["owner"] == "neutral":
				targets.append(zone["id"])
				break

	if targets.is_empty(): return

	var target_id = targets[randi() % targets.size()]
	var force = diff_settings.get("force_size", 1.0)
	pending_attacks.append({
		"zone_id": target_id,
		"turns_until": warning,
		"force_size": force,
	})
	_notify("⚠ Creatures from the wilds will attack %s in %d turns!" % [zones[target_id]["name"], warning])

	# Nightmare/Hard can roll a second attack same turn
	if pending_attacks.size() < max_simultaneous and randf() < attack_chance * 0.5:
		_maybe_spawn_attack()

func _process_pending_attacks() -> void:
	var remaining = []
	var triggered = []
	for attack in pending_attacks:
		attack["turns_until"] -= 1
		if attack["turns_until"] <= 0:
			triggered.append(attack)
		else:
			remaining.append(attack)
	pending_attacks = remaining

	if triggered.size() > 0:
		mandatory_battle_queue.append_array(triggered)
		_launch_next_mandatory_battle()

func _launch_next_mandatory_battle() -> void:
	if mandatory_battle_queue.is_empty(): return
	var attack = mandatory_battle_queue[0]
	var zone = zones[attack["zone_id"]]
	_notify("⚔ %s is under attack from the wilds! You must defend it now." % zone["name"])
	PlayerInventory.current_battle_zone = attack["zone_id"]
	PlayerInventory.current_attack_force = attack["force_size"]
	PlayerInventory.conquering_zone = false
	PlayerInventory.set_battle_roster_from_zone_troops(zone["troops"])
	SaveManager.save_game()
	get_tree().change_scene_to_file("res://scenes/defense_scene.tscn")

# -------------------------------------------------------
# HUD
# -------------------------------------------------------
func _refresh_hud() -> void:
	if hud_turn:
		hud_turn.text = "Turn %d" % turn
	if hud_diff:
		var col = {"Easy": Color(0.3,0.9,0.3), "Normal": Color(0.4,0.7,1.0),
				   "Hard": Color(1.0,0.65,0.1), "Nightmare": Color(0.9,0.2,0.2)}
		hud_diff.text = "[%s]" % PlayerInventory.difficulty
		hud_diff.add_theme_color_override("font_color",
			col.get(PlayerInventory.difficulty, Color.WHITE))

func _notify(msg: String) -> void:
	if notification_label:
		notification_label.text = msg
		# Clear after 4 seconds
		get_tree().create_timer(4.0).timeout.connect(func():
			if is_instance_valid(notification_label):
				notification_label.text = "")

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_close_popup()
			selected_zone_id = -1
			_draw_map()
