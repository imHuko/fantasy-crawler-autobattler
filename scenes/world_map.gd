extends Node2D

const SharedHeader := preload("res://scenes/shared_header.gd")

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

# Unit slot grid (side panel overview) — lower number sorts first.
# Matches TroopData's TroopType enum names exactly (get_type_name()).
const UNIT_PRIORITY = {
	"KNIGHT": 0,
	"ROGUE":  1,
	"ARCHER": 2,
	"MAGE":   3,
	"HEALER": 4,
}
const TOTAL_UNIT_SLOT_BOXES = 8   # fixed 2 rows of 4; bump this if the player's roster cap ever realistically approaches it
const TOTAL_BUILDING_SLOT_BOXES = 6   # single row; bump this if max_buildings_per_zone ever realistically approaches it

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
const SECONDS_PER_OLD_TURN = 30.0
const TRAVEL_SPEED = 120.0 / SECONDS_PER_OLD_TURN   # distance units per real second, base (1x)
const ATTACK_ROLL_INTERVAL = SECONDS_PER_OLD_TURN   # how often a new attack is rolled, in real seconds at 1x

var zones: Array = []
var connections: Array = []   # pairs of zone ids
var selected_zone_id: int = -1
var popup_panel: Control = null   # still used by _open_move_troops_panel, which is out of scope for the new persistent side panel (only the zone info/build flow was migrated)
var elapsed_seconds: float = 0.0   # total real-time elapsed on the map, replaces the old turn counter
var attack_roll_timer: float = 0.0
var pending_attacks: Array = []   # {zone_id, seconds_remaining, force_size}
var marching_troops: Array = []   # {troop_id, troop_name, from_zone, to_zone, from_pos, to_pos, progress (0-1), total_seconds}
var mandatory_battle_queue: Array = []   # attacks that have triggered and must be resolved before continuing

# -------------------------------------------------------
# Persistent zone side panel
# Replaces the old "spawn a brand new popup every click" approach.
# This panel is built ONCE in _build_ui() and never destroyed or
# recreated for the rest of the screen's lifetime — only its contents
# (text, button states) update when the player clicks a different zone
# or switches between the overview/build views. This is what makes the
# panel's own buttons safe and stable tutorial targets: a button
# reference handed to the tutorial system here can never go stale or
# point at a now-freed node, unlike the old popups where a fresh
# PanelContainer (and fresh Button instances inside it) were created
# from scratch on every single zone click and every Build Here click.
# The panel itself is a Control, not part of the Node2D/Camera2D-
# affected map drawing — so it's also naturally exempt from the
# camera-transform position bug that affected the in-map zone markers.
# -------------------------------------------------------
var side_panel: PanelContainer = null
var side_panel_zone_id: int = -1   # which zone the panel is currently showing, -1 = none/hidden
var side_panel_view: String = "overview"   # "overview" or "build"

const ZONE_ART_ATLAS   = "res://assets/zones/zone_types_a.png"
const ZONE_ART_COL_W   = 512    # image width 1536 / 3 columns = 512 exactly
const ZONE_ART_ROW_H   = 204    # image height 1024 / 5 rows = 204.8; using floor to avoid overshooting row bounds
const ZONE_ART_ROWS = {
	"forest":   0,
	"ruins":    1,
	"mountain": 2,
	"dungeon":  3,
	"city":     4,
}

# Overview view — built once, contents refreshed per zone
var sp_header_label: Label
var sp_zone_art: TextureRect
var sp_owner_label: Label
var sp_type_label: Label
var sp_unit_grid: GridContainer   # the 8-box unit slot display (2 rows of 4), rebuilt per zone in _refresh_side_panel_overview
var sp_building_grid: GridContainer   # the building slot row (single row), rebuilt per zone in _refresh_side_panel_overview
var sp_incoming_label: Label
var sp_action_container: VBoxContainer   # owner-dependent buttons (Build Here, Move Troops, Conquer, Explore) get rebuilt here per zone, but the container itself is stable
var sp_outer_vbox: VBoxContainer
var sp_overview_view: VBoxContainer
var sp_build_view: VBoxContainer
var tutorial_build_here_btn: Button = null   # re-set each time the overview view rebuilds its action buttons for a zone
var tutorial_mgmt_btn: Button = null         # Management nav button in the shared header, used by tutorial reminders

# Build view — built once, building rows refreshed per zone
var sp_build_title_label: Label
var sp_build_slots_label: Label
var sp_build_rows_container: VBoxContainer   # building rows get rebuilt here per zone/view-open, but the container itself is stable
var tutorial_build_farm_btn: Button = null   # re-set each time the build view rebuilds its rows

var time_speed: float = 1.0   # 1x to 5x, set by the speed slider
var is_paused: bool = false

# UI
var zone_nodes: Array = []
var map_camera: Camera2D = null
var is_panning: bool = false
const PAN_SPEED = 400.0   # arrow-key pan speed, pixels/sec
const CAMERA_MARGIN = 80.0   # how far past the map edge the camera is allowed to drift
var marching_dot_nodes: Array = []
var connection_lines: Node2D
var hud_time: Label
var hud_diff: Label
var hud_resources: Label
var notification_label: Label
var pause_btn: Button
var speed_slider: HSlider
var speed_label: Label

func _ready() -> void:
	_setup_camera()

	if PlayerInventory.map_generated:
		_load_map_state()
	else:
		_generate_map()
		_save_map_state()
		PlayerInventory.map_generated = true

	# Center the camera on the player's own zone now that zones actually
	# exist (they don't yet at _setup_camera() time, in either the fresh-
	# generation or load-from-save path above). Previously the camera
	# defaulted to the map's geometric center regardless of where the
	# player's own zone actually was, which on a map this size could
	# leave the starting zone partly or fully outside the initial view —
	# exactly what was causing the tutorial's first zone-click step to
	# spotlight a position the camera wasn't even showing yet.
	if zones.size() > 0:
		map_camera.position = zones[0]["pos"]
	_fit_camera_zoom_to_viewport()

	_build_ui()
	_apply_pending_battle_result()
	_draw_map()
	_refresh_hud()

	if not TutorialOverlay.step_advanced.is_connected(_on_tutorial_step_advanced):
		TutorialOverlay.step_advanced.connect(_on_tutorial_step_advanced)

	# If there are still mandatory battles queued (multiple simultaneous attacks),
	# force the next one immediately — no map interaction allowed until resolved
	if mandatory_battle_queue.size() > 0:
		call_deferred("_launch_next_mandatory_battle")
	elif PlayerInventory.tutorial_active:
		# The new forced walkthrough (TutorialRouter) fully supersedes
		# these older optional hint popups — both running at once would
		# stack two separate tutorial UIs on screen simultaneously.
		call_deferred("_resolve_tutorial_step")
	elif PlayerInventory.play_tutorial and not PlayerInventory.map_tutorial_seen["intro"]:
		call_deferred("_show_map_tutorial_popup", "intro")
		# Time-controls hint used to fire on the first End Turn click; now that
		# time flows on its own, just show it a few seconds after the intro.
		get_tree().create_timer(4.0).timeout.connect(func():
			if PlayerInventory.play_tutorial and not PlayerInventory.map_tutorial_seen["end_turn"]:
				_show_map_tutorial_popup("end_turn"))

func _load_map_state() -> void:
	zones = PlayerInventory.map_zones
	connections = PlayerInventory.map_connections
	elapsed_seconds = PlayerInventory.map_elapsed_seconds
	time_speed = PlayerInventory.map_time_speed
	is_paused = PlayerInventory.map_is_paused
	attack_roll_timer = PlayerInventory.map_attack_roll_timer
	pending_attacks = PlayerInventory.map_pending_attacks
	marching_troops = PlayerInventory.map_marching_troops
	mandatory_battle_queue = PlayerInventory.map_mandatory_battle_queue

# Sets up a Camera2D so the player can pan around the map — middle-mouse
# drag, or arrow keys. Limits are clamped to the actual map bounds (plus
# a small margin) so panning can't drift off into empty space far past
# where any zone or future scenery actually exists.
func _setup_camera() -> void:
	map_camera = Camera2D.new()
	map_camera.position = Vector2(MAP_W / 2.0, MAP_H / 2.0)
	map_camera.limit_left = -CAMERA_MARGIN
	map_camera.limit_top = -CAMERA_MARGIN
	map_camera.limit_right = MAP_W + CAMERA_MARGIN
	map_camera.limit_bottom = MAP_H + CAMERA_MARGIN
	map_camera.enabled = true
	add_child(map_camera)
	get_tree().get_root().size_changed.connect(_fit_camera_zoom_to_viewport)

# Makes sure the full MAP_W x MAP_H area is always visible regardless
# of window/viewport size — without this, a small enough resolution
# (the custom resolution field in Settings has no real upper limit on
# how small a player can type in, only a 640x480 floor, which is still
# smaller than this map) could leave zones, including the player's own
# starting zone, partially or fully outside the camera's view.
# NOTE: Godot's Camera2D.zoom is the opposite of what feels intuitive —
# values ABOVE 1.0 zoom OUT (show MORE world per screen pixel), values
# BELOW 1.0 zoom IN. Confirmed directly against Godot's own docs before
# writing this, since guessing the direction backwards here would have
# made small windows zoom IN on the map instead of out, the opposite of
# the actual fix needed.
func _fit_camera_zoom_to_viewport() -> void:
	if map_camera == null: return
	var viewport_size = Vector2(get_viewport().size)
	if viewport_size.x <= 0 or viewport_size.y <= 0: return

	var zoom_needed_x = MAP_W / viewport_size.x
	var zoom_needed_y = MAP_H / viewport_size.y
	# Use the LARGER requirement so both axes fit (the smaller axis just
	# shows a bit of margin) rather than the smaller one, which would
	# crop whichever axis needed more zoom-out.
	var zoom_factor = max(zoom_needed_x, zoom_needed_y)
	# Never zoom IN past 1.0 — a viewport already bigger than the map
	# doesn't need any correction, it already shows the whole thing
	# (and then some) at native scale.
	zoom_factor = max(zoom_factor, 1.0)
	map_camera.zoom = Vector2(zoom_factor, zoom_factor)

func _save_map_state() -> void:
	PlayerInventory.map_zones = zones
	PlayerInventory.map_connections = connections
	PlayerInventory.map_elapsed_seconds = elapsed_seconds
	PlayerInventory.map_time_speed = time_speed
	PlayerInventory.map_is_paused = is_paused
	PlayerInventory.map_attack_roll_timer = attack_roll_timer
	PlayerInventory.map_pending_attacks = pending_attacks
	PlayerInventory.map_marching_troops = marching_troops
	PlayerInventory.map_mandatory_battle_queue = mandatory_battle_queue

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
			Telemetry.log_event("zone_conquered", {
				"zone_id": zone_id, "zone_type": zones[zone_id]["type"],
				"zone_name": zones[zone_id]["name"], "stage": PlayerInventory.current_stage,
			})
		else:
			_notify("%s successfully defended!" % zones[zone_id]["name"])
			Telemetry.log_event("zone_defended", {
				"zone_id": zone_id, "zone_type": zones[zone_id]["type"], "stage": PlayerInventory.current_stage,
			})
	elif result == "lost":
		if was_conquest:
			_notify("The conquest of %s failed. The wilds remain in control." % zones[zone_id]["name"])
			Telemetry.log_event("conquest_failed", {
				"zone_id": zone_id, "zone_type": zones[zone_id]["type"], "stage": PlayerInventory.current_stage,
			})
		else:
			# Defending and lost — zone falls back to neutral, buildings are
			# destroyed, and stationed troops retreat wounded instead of
			# disappearing.
			var retreat_result = _retreat_zone_troops_after_loss(zone_id)
			zones[zone_id]["owner"] = "neutral"
			zones[zone_id]["buildings"].clear()
			if retreat_result["count"] > 0:
				_notify("%s has fallen! %d troop(s) retreated to %s at 1 HP. Buildings were lost." % [
					zones[zone_id]["name"], retreat_result["count"], retreat_result["destination_name"]
				])
			else:
				_notify("%s has fallen to the wilds! Buildings were lost." % zones[zone_id]["name"])
			Telemetry.log_event("zone_lost", {
				"zone_id": zone_id, "zone_type": zones[zone_id]["type"], "stage": PlayerInventory.current_stage,
				"troops_retreating": retreat_result["count"],
				"retreat_zone": retreat_result["destination_id"],
			})
	elif result == "retreat":
		if not was_conquest:
			# Retreating from a defense = losing the zone too, but troops survive
			zones[zone_id]["owner"] = "neutral"
			_notify("You retreated from %s. The zone has fallen." % zones[zone_id]["name"])
			Telemetry.log_event("zone_retreat", {
				"zone_id": zone_id, "zone_type": zones[zone_id]["type"], "stage": PlayerInventory.current_stage,
			})

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
	PlayerInventory.current_battle_forge_level = 0
	PlayerInventory.current_battle_shrine_level = 0
	_save_map_state()
	SaveManager.save_game()

# -------------------------------------------------------
# Map Generation
# -------------------------------------------------------
func _generate_map() -> void:
	var rng = RandomNumberGenerator.new()
	rng.seed = PlayerInventory.map_seed

	var zone_count = PlayerInventory.difficulty_settings.get("zone_count", 13)

	# Place starting zone left-center.
	# The player starts owning their city regardless of tutorial status.
	# The OLD tutorial design had this start neutral so conquering it was
	# the first map action (mirroring the old room-dungeon's "fight to get
	# something" lesson) — the new forced walkthrough (TutorialRouter)
	# teaches Building before any combat, which requires already owning a
	# buildable zone, so that conquest-first premise no longer applies.
	var start_pos = Vector2(120, MAP_H / 2)
	var start_owner = "player"
	zones.append(_make_zone(0, "city", start_pos, start_owner, "Your City"))
	zones[0]["dist_from_start"] = 0
	zones[0]["enemy_strength"] = 1   # always a gentle first fight
	if not PlayerInventory.play_tutorial and not zones[0]["buildings"].has("Farm"):
		zones[0]["buildings"]["Farm"] = 1

	# Station all starting troops at the home city.
	for troop in PlayerInventory.troop_roster:
		zones[0]["troops"].append(troop.troop_id)

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
		zone["enemy_strength"] = int(dist / 60.0)
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
		"buildings": {},   # { "Forge": 2, "Watchtower": 1 } — building name -> level
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
	bg.position = Vector2(-CAMERA_MARGIN, -CAMERA_MARGIN)
	bg.size = Vector2(MAP_W + CAMERA_MARGIN * 2, MAP_H + CAMERA_MARGIN * 2)
	add_child(bg)

	# Draw connection lines first (behind zones)
	connection_lines = Node2D.new()
	add_child(connection_lines)

	var header_buttons = SharedHeader.add_fixed(self, SharedHeader.SCREEN_WORLD_MAP, SHARED_HEADER_HEIGHT, true)
	tutorial_mgmt_btn = header_buttons.get(SharedHeader.SCREEN_MANAGEMENT, null)
	hud_time = header_buttons.get(SharedHeader.CONTROL_TIME_LABEL, null)
	hud_diff = header_buttons.get(SharedHeader.CONTROL_DIFF_LABEL, null)
	hud_resources = header_buttons.get(SharedHeader.CONTROL_RESOURCES_LABEL, null)
	notification_label = header_buttons.get(SharedHeader.CONTROL_NOTIFICATION_LABEL, null)
	pause_btn = header_buttons.get(SharedHeader.CONTROL_PAUSE_BUTTON, null)
	speed_label = header_buttons.get(SharedHeader.CONTROL_SPEED_LABEL, null)
	speed_slider = header_buttons.get(SharedHeader.CONTROL_SPEED_SLIDER, null)

	_build_side_panel()

# =========================================================
# ZONE SIDE PANEL — map of where things live
#
# _build_side_panel()            Builds the panel ONCE: the panel
#                                 itself + its style, the Close button,
#                                 the overview section (zone name, art
#                                 box, owner/type/incoming labels, unit
#                                 grid, building grid, action button
#                                 container), and the separate build
#                                 sub-view (the "Build Here" screen +
#                                 Back button). Nothing in here ever
#                                 gets destroyed/recreated later.
#
# _refresh_side_panel_overview() Runs every time a zone is clicked.
#                                 Does NOT rebuild structure — just
#                                 updates text and rebuilds the two
#                                 grids + action buttons to match
#                                 whichever zone is now selected.
#
# _refresh_side_panel_build()    Same idea as above, but for the
#                                 build sub-view's building list.
#
# _make_unit_slot_box() /
# _make_building_slot_box()      Draw one box each for the unit/
#                                 building grids (filled, empty, or
#                                 locked/crossed-out).
#
# _load_unit_icon() /
# _load_building_icon()          Load icons from the fixed
#                                 art/icons/units/<key>.png and
#                                 art/icons/buildings/<key>.png
#                                 convention, right next to the box
#                                 builders that use them.
#
# Sizing/sort knobs (all named constants, not buried in logic):
#   SIDE_PANEL_WIDTH, UNIT_SLOT_BOX_SIZE, BUILDING_SLOT_BOX_SIZE,
#   TOTAL_UNIT_SLOT_BOXES, TOTAL_BUILDING_SLOT_BOXES, UNIT_PRIORITY
# =========================================================

const SIDE_PANEL_WIDTH = 261.0
const SHARED_HEADER_HEIGHT = 40.0

func _build_side_panel() -> void:
	# The panel lives under its own CanvasLayer rather than being added
	# directly as a sibling of the map's own zone marker nodes. Godot
	# draws Node2D-tree siblings in the order they were added, and this
	# panel is built before _draw_map() ever creates its zone markers
	# (those are created lazily, the first time the map draws) — so
	# without this, every zone marker (icons, name labels) drew ON TOP
	# of the panel instead of underneath it, confirmed directly from a
	# screenshot showing a zone's name and icon bleeding through the
	# unit slot grid. A CanvasLayer's draw order depends only on its
	# explicit layer number, not on tree position or creation order,
	# which sidesteps this category of bug entirely — same mechanism
	# already used successfully for TutorialOverlay.
	var side_panel_layer = CanvasLayer.new()
	side_panel_layer.layer = 10   # above normal gameplay (layer 0), below TutorialOverlay (layer 90)
	add_child(side_panel_layer)

	side_panel = PanelContainer.new()
	side_panel.custom_minimum_size = Vector2(SIDE_PANEL_WIDTH, 0)
	side_panel.visible = false
	# Override the default theme's panel margin, which was reserving a
	# large gap on every side before any of this panel's own content
	# even starts — most noticeable on the left, where it stacked with
	# the centering of narrower rows like the unit/building grids.
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.12, 0.12, 0.14)
	panel_style.content_margin_left = 6
	panel_style.content_margin_right = 6
	panel_style.content_margin_top = 6
	panel_style.content_margin_bottom = 6
	side_panel.add_theme_stylebox_override("panel", panel_style)
	side_panel_layer.add_child(side_panel)
	_position_side_panel()
	get_tree().get_root().size_changed.connect(_position_side_panel)

	var outer_vbox = VBoxContainer.new()
	outer_vbox.add_theme_constant_override("separation", 8)
	outer_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# custom_minimum_size is set explicitly here (not just the expand
	# flag above) because a flag only describes how this node behaves
	# IF its parent hands it extra space — it doesn't force that space
	# to exist. Centering inside outer_vbox/overview wasn't visibly
	# working even with the flag set, which points at exactly this:
	# PanelContainer's single-child auto-fit may not actually be
	# stretching this child to the panel's full width on its own.
	outer_vbox.custom_minimum_size = Vector2(SIDE_PANEL_WIDTH - 12, 0)   # minus the panel's own 6px+6px margin
	side_panel.add_child(outer_vbox)
	sp_outer_vbox = outer_vbox

	# --- Overview sub-view ---
	var overview = VBoxContainer.new()
	overview.name = "OverviewView"
	overview.add_theme_constant_override("separation", 8)
	overview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer_vbox.add_child(overview)
	sp_overview_view = overview

	# Zone name
	sp_header_label = Label.new()
	sp_header_label.add_theme_font_size_override("font_size", 16)
	sp_header_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	overview.add_child(sp_header_label)

	var art_center = CenterContainer.new()
	art_center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	overview.add_child(art_center)
	sp_zone_art = TextureRect.new()
	sp_zone_art.custom_minimum_size = Vector2(192, 77)
	sp_zone_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	sp_zone_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art_center.add_child(sp_zone_art)

	sp_owner_label = Label.new()
	sp_owner_label.add_theme_font_size_override("font_size", 12)
	sp_owner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	overview.add_child(sp_owner_label)

	sp_type_label = Label.new()
	sp_type_label.add_theme_font_size_override("font_size", 11)
	sp_type_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	sp_type_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	overview.add_child(sp_type_label)

	sp_incoming_label = Label.new()
	sp_incoming_label.add_theme_font_size_override("font_size", 10)
	sp_incoming_label.add_theme_color_override("font_color", Color(0.5, 0.9, 1.0))
	sp_incoming_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	sp_incoming_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	overview.add_child(sp_incoming_label)

	# Small gap before the unit slot grid, per spec
	var gap_before_units = Control.new()
	gap_before_units.custom_minimum_size = Vector2(0, 4)
	overview.add_child(gap_before_units)

	# Unit slot grid — fixed 2 rows of 4 boxes (TOTAL_UNIT_SLOT_BOXES).
	# Filled boxes show one box per individual troop actually stationed
	# in this zone (grouped/ordered by UNIT_PRIORITY, NOT collapsed into
	# a single box per type — "2 Knights" is still 2 separate boxes,
	# just adjacent and using the same icon). Remaining boxes up to the
	# player's current PlayerInventory.unlocked_troop_slots show empty
	# with no slash. Anything beyond that, up to TOTAL_UNIT_SLOT_BOXES,
	# shows crossed-out/locked. This deliberately is NOT scoped to this
	# zone for the empty/locked portion — unlocked_troop_slots is a
	# single global number on the player, so those boxes represent
	# overall roster capacity, just displayed in whichever zone the
	# player happens to be looking at.
	sp_unit_grid = GridContainer.new()
	sp_unit_grid.columns = 4
	sp_unit_grid.add_theme_constant_override("h_separation", 4)
	sp_unit_grid.add_theme_constant_override("v_separation", 4)
	var unit_grid_center = CenterContainer.new()
	unit_grid_center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	unit_grid_center.add_child(sp_unit_grid)
	overview.add_child(unit_grid_center)

	# Small gap before the building slot row, per spec
	var gap_before_building_slots = Control.new()
	gap_before_building_slots.custom_minimum_size = Vector2(0, 4)
	overview.add_child(gap_before_building_slots)

	# Building slot row — single row of TOTAL_BUILDING_SLOT_BOXES boxes,
	# same idea as the unit slot grid above but smaller and zone-scoped
	# (a zone's buildings genuinely live in that zone, unlike troops
	# which roam, so the filled portion here doesn't need the same
	# "global capacity shown in a local context" reasoning units do).
	sp_building_grid = GridContainer.new()
	sp_building_grid.columns = TOTAL_BUILDING_SLOT_BOXES
	sp_building_grid.add_theme_constant_override("h_separation", 4)
	sp_building_grid.add_theme_constant_override("v_separation", 4)
	var building_grid_center = CenterContainer.new()
	building_grid_center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	building_grid_center.add_child(sp_building_grid)
	overview.add_child(building_grid_center)

	var overview_sep = HSeparator.new()
	overview.add_child(overview_sep)

	# Action buttons: Move Units, then a small gap, then Build Here and
	# Explore (and Conquer when applicable) — built fresh per zone in
	# _refresh_side_panel_overview, but always in this fixed order.
	sp_action_container = VBoxContainer.new()
	sp_action_container.add_theme_constant_override("separation", 8)
	overview.add_child(sp_action_container)

	# --- Build sub-view ---
	var build_view = VBoxContainer.new()
	build_view.name = "BuildView"
	build_view.add_theme_constant_override("separation", 8)
	build_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	build_view.visible = false
	outer_vbox.add_child(build_view)
	sp_build_view = build_view

	sp_build_title_label = Label.new()
	sp_build_title_label.add_theme_font_size_override("font_size", 14)
	sp_build_title_label.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
	build_view.add_child(sp_build_title_label)

	sp_build_slots_label = Label.new()
	sp_build_slots_label.add_theme_font_size_override("font_size", 11)
	build_view.add_child(sp_build_slots_label)

	var build_sep = HSeparator.new()
	build_view.add_child(build_sep)

	sp_build_rows_container = VBoxContainer.new()
	sp_build_rows_container.add_theme_constant_override("separation", 8)
	build_view.add_child(sp_build_rows_container)

	var back_btn = Button.new()
	back_btn.text = "Back"
	back_btn.pressed.connect(_show_side_panel_overview)
	build_view.add_child(back_btn)

	# Close lives outside both sub-views, as the last child of outer_vbox
	# — so it renders at the very bottom of the panel below whichever
	# sub-view is currently visible, rather than at the top where it
	# used to sit directly in the same screen region as the HUD's
	# Management button (see _position_side_panel() for the other half
	# of that fix).
	var close_sep = HSeparator.new()
	outer_vbox.add_child(close_sep)
	var close_btn = Button.new()
	close_btn.text = "Close"
	close_btn.pressed.connect(_close_side_panel)
	var close_btn_center = CenterContainer.new()
	close_btn_center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	close_btn_center.add_child(close_btn)
	outer_vbox.add_child(close_btn_center)


# Explicit position/size instead of an anchor preset — side_panel's
# parent (this script's own root) is a Node2D, not a plain Control or
# the root Viewport, and Godot's anchor system is documented to only
# behave predictably under one of those two parent types. Anchors
# silently doing nothing under a Node2D parent is exactly what caused
# the panel to render on the left instead of the requested right edge.
# Recalculating explicitly on resize (same pattern already used for
# the camera's zoom-to-fit elsewhere in this file) sidesteps that
# entirely. This function ONLY repositions/resizes the panel — it must
# never construct content, since it's connected to size_changed and
# runs on every window resize; content construction belongs in
# _build_side_panel() instead, which runs exactly once.
#
# Starts below the shared header so the panel cannot cover top-bar controls.
func _position_side_panel() -> void:
	if not side_panel:
		return
	var screen_size = Vector2(get_viewport().size)
	side_panel.position = Vector2(screen_size.x - SIDE_PANEL_WIDTH, SHARED_HEADER_HEIGHT)
	side_panel.size = Vector2(SIDE_PANEL_WIDTH, screen_size.y - SHARED_HEADER_HEIGHT)

	# Actively re-sync outer_vbox's width to the panel's actual content
	# area (panel width minus its own left+right margin) every time
	# this runs, rather than relying on a custom_minimum_size set once
	# at construction — that one-time value left a visible gap on the
	# right, since PanelContainer's real layout pass happens after
	# construction and wasn't reliably matching the pre-calculated
	# number.
	if sp_outer_vbox:
		sp_outer_vbox.custom_minimum_size = Vector2(SIDE_PANEL_WIDTH - 12, 0)

func _close_side_panel() -> void:
	side_panel.visible = false
	side_panel_zone_id = -1

func _show_side_panel_overview() -> void:
	side_panel_view = "overview"
	sp_overview_view.visible = true
	sp_build_view.visible = false
	if side_panel_zone_id >= 0:
		_refresh_side_panel_overview(side_panel_zone_id)

func _show_side_panel_build(zone_id: int) -> void:
	side_panel_view = "build"
	side_panel_zone_id = zone_id
	sp_overview_view.visible = false
	sp_build_view.visible = true
	if PlayerInventory.tutorial_active:
		TutorialRouter.advance_step("build_here")
	_refresh_side_panel_build(zone_id)   # this also calls TutorialRouter.resolve_current_step() internally once the rows are built

func _open_side_panel(zone_id: int) -> void:
	side_panel_zone_id = zone_id
	side_panel.visible = true
	_show_side_panel_overview()

func _refresh_side_panel_overview(zone_id: int) -> void:
	var zone = zones[zone_id]

	sp_header_label.text = "%s %s" % [ZONE_TYPE_ICONS[zone["type"]], zone["name"]]
	sp_header_label.add_theme_color_override("font_color", ZONE_TYPE_COLORS[zone["type"]])

	sp_owner_label.text = "Owner: %s" % zone["owner"].capitalize()
	sp_owner_label.add_theme_color_override("font_color", OWNER_COLORS[zone["owner"]])

	sp_type_label.text = "Type: %s  |  Threat: %d" % [zone["type"].capitalize(), zone["enemy_strength"]]

	if sp_zone_art and ResourceLoader.exists(ZONE_ART_ATLAS):
		var row = ZONE_ART_ROWS.get(zone["type"], 0)
		var atlas = AtlasTexture.new()
		atlas.atlas = load(ZONE_ART_ATLAS)
		atlas.region = Rect2(ZONE_ART_COL_W, row * ZONE_ART_ROW_H, ZONE_ART_COL_W, ZONE_ART_ROW_H)
		sp_zone_art.texture = atlas

	var stationed_troops: Array[TroopData] = []
	for troop_id in zone["troops"]:
		var t = _get_troop_data_by_id(troop_id)
		if t:
			stationed_troops.append(t)
	stationed_troops.sort_custom(func(a, b):
		return UNIT_PRIORITY.get(a.get_type_name(), 99) < UNIT_PRIORITY.get(b.get_type_name(), 99))

	for child in sp_unit_grid.get_children():
		sp_unit_grid.remove_child(child)
		child.queue_free()

	for troop in stationed_troops:
		sp_unit_grid.add_child(_make_unit_slot_box(troop.get_type_name(), false))

	var unlocked = PlayerInventory.unlocked_troop_slots
	var filled_count = stationed_troops.size()
	for i in range(filled_count, TOTAL_UNIT_SLOT_BOXES):
		var locked = i >= unlocked
		sp_unit_grid.add_child(_make_unit_slot_box("", locked))

	for child in sp_building_grid.get_children():
		sp_building_grid.remove_child(child)
		child.queue_free()

	# Iterate BUILDINGS' own declared order (Watchtower, Barracks, Farm,
	# Forge, Shrine) rather than zone["buildings"]'s own dictionary
	# order, so the row's ordering is stable and consistent across
	# every zone regardless of the order things happened to be built in.
	var built_names = []
	for bname in BUILDINGS:
		if zone["buildings"].has(bname):
			built_names.append(bname)

	for bname in built_names:
		sp_building_grid.add_child(_make_building_slot_box(bname, false))

	var building_cap = PlayerInventory.max_buildings_per_zone
	var building_filled_count = built_names.size()
	for i in range(building_filled_count, TOTAL_BUILDING_SLOT_BOXES):
		var building_locked = i >= building_cap
		sp_building_grid.add_child(_make_building_slot_box("", building_locked))

	var incoming = []
	for m in marching_troops:
		if m["to_zone"] == zone["id"]:
			incoming.append("%s (%ds)" % [m["troop_name"], int(ceil(m["seconds_left"]))])
	if incoming.size() > 0:
		sp_incoming_label.text = "Incoming: " + ", ".join(incoming)
		sp_incoming_label.visible = true
	else:
		sp_incoming_label.visible = false

	# Action buttons are owner-dependent, so the container's contents do
	# get rebuilt here — but the container itself (sp_action_container)
	# is the same stable node every time, never destroyed, which is
	# what actually matters for tutorial targeting: get_tutorial_target
	# always finds the button at the same place in the tree, never a
	# stale reference to something queue_free()'d moments ago.
	for child in sp_action_container.get_children():
		sp_action_container.remove_child(child)
		child.queue_free()
	tutorial_build_here_btn = null

	if zone["owner"] == "player":
		_add_sp_action_btn("Move Troops Here", Color(0.4, 0.8, 1.0), _on_move_troops.bind(zone["id"]))
		var action_gap = Control.new()
		action_gap.custom_minimum_size = Vector2(0, 4)
		sp_action_container.add_child(action_gap)
		tutorial_build_here_btn = _add_sp_action_btn("Build Here", Color(0.85, 0.75, 0.4), _on_build.bind(zone["id"]))
		var explore_tier = _get_explore_tier(zone["id"])
		if zone["troops"].is_empty():
			var no_troop_hint = Label.new()
			no_troop_hint.text = "Station a troop here to Explore (%s)" % explore_tier
			no_troop_hint.add_theme_font_size_override("font_size", 11)
			no_troop_hint.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
			no_troop_hint.autowrap_mode = TextServer.AUTOWRAP_WORD
			sp_action_container.add_child(no_troop_hint)
		else:
			_add_sp_action_btn("Explore  (%s)" % explore_tier, Color(0.65, 0.3, 0.9),
				_on_explore.bind(zone["id"], explore_tier))
	elif zone["owner"] == "neutral":
		var adj = _is_adjacent_to_player(zone["id"]) or zone["id"] == 0
		if adj:
			var threat_str = "Threat Level %d" % zone["enemy_strength"]
			_add_sp_action_btn("Conquer Zone  (%s)" % threat_str,
				Color(0.4, 0.9, 0.4), _on_conquer.bind(zone["id"]))
		else:
			var hint = Label.new()
			hint.text = "Must conquer adjacent zones first"
			hint.add_theme_font_size_override("font_size", 11)
			hint.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
			sp_action_container.add_child(hint)

	if PlayerInventory.tutorial_active:
		TutorialRouter.resolve_current_step(self)

func _add_sp_action_btn(text: String, color: Color, action: Callable) -> Button:
	var btn = Button.new()
	btn.text = text
	btn.add_theme_color_override("font_color", color)
	btn.custom_minimum_size = Vector2(0, 36)
	btn.pressed.connect(action)
	var center = CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.add_child(btn)
	sp_action_container.add_child(center)
	return btn

const UNIT_SLOT_BOX_SIZE = 45.0   # 20% smaller than the original 56
const BUILDING_SLOT_BOX_SIZE = UNIT_SLOT_BOX_SIZE * 0.7   # 70% of the unit box size, i.e. 30% smaller

# Builds one box for the unit slot grid:
#  - unit_type_name non-empty -> shows that unit's icon (filled slot)
#  - unit_type_name empty, locked=false -> empty outline, no slash
#    (an unlocked slot with no troop occupying it right now)
#  - unit_type_name empty, locked=true -> crossed-out box (a slot the
#    player hasn't unlocked yet, e.g. via a future talent)
func _make_unit_slot_box(unit_type_name: String, locked: bool) -> Control:
	var box = PanelContainer.new()
	box.custom_minimum_size = Vector2(UNIT_SLOT_BOX_SIZE, UNIT_SLOT_BOX_SIZE)

	if unit_type_name != "":
		var icon = _load_unit_icon(unit_type_name)
		if icon:
			var tex_rect = TextureRect.new()
			tex_rect.texture = icon
			tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			box.add_child(tex_rect)
		else:
			# Icon failed to load (shouldn't normally happen once the
			# placeholder PNGs are in place) — fall back to a labeled
			# colored box so a missing file is obvious rather than
			# silently blank.
			var fallback = ColorRect.new()
			fallback.color = Color(0.3, 0.3, 0.35)
			box.add_child(fallback)
			var lbl = Label.new()
			lbl.text = unit_type_name.substr(0, 2)
			lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			box.add_child(lbl)
		return box

	if locked:
		var locked_bg = ColorRect.new()
		locked_bg.color = Color(0.12, 0.12, 0.12)
		box.add_child(locked_bg)
		# A simple X drawn with two labels would be fragile to align;
		# a single slash character, centered and scaled up, reads
		# clearly enough as "locked" without needing custom drawing.
		var slash = Label.new()
		slash.text = "✕"
		slash.add_theme_font_size_override("font_size", 24)
		slash.add_theme_color_override("font_color", Color(0.4, 0.25, 0.25))
		slash.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		slash.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		box.add_child(slash)
	else:
		var empty_bg = ColorRect.new()
		empty_bg.color = Color(0.18, 0.18, 0.2)
		box.add_child(empty_bg)

	return box

# Loads a unit icon by the fixed res://art/icons/units/<key>.png
# convention. unit_type_name is the uppercase TroopType name (e.g.
# "KNIGHT"); the actual file is the lowercase key. Returns null if the
# file doesn't exist yet (e.g. before placeholder/real art is added),
# so callers can fall back gracefully instead of erroring.
func _load_unit_icon(unit_type_name: String) -> Texture2D:
	var path = "res://art/icons/units/%s.png" % unit_type_name.to_lower()
	if not ResourceLoader.exists(path):
		return null
	return load(path)

# Same idea as _make_unit_slot_box, but smaller (BUILDING_SLOT_BOX_SIZE)
# and keyed by building name (e.g. "Farm") rather than unit type.
func _make_building_slot_box(building_name: String, locked: bool) -> Control:
	var box = PanelContainer.new()
	box.custom_minimum_size = Vector2(BUILDING_SLOT_BOX_SIZE, BUILDING_SLOT_BOX_SIZE)

	if building_name != "":
		var icon = _load_building_icon(building_name)
		if icon:
			var tex_rect = TextureRect.new()
			tex_rect.texture = icon
			tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			box.add_child(tex_rect)
		else:
			var fallback = ColorRect.new()
			fallback.color = Color(0.3, 0.3, 0.35)
			box.add_child(fallback)
			var lbl = Label.new()
			lbl.text = building_name.substr(0, 2)
			lbl.add_theme_font_size_override("font_size", 10)
			lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			box.add_child(lbl)
		return box

	if locked:
		var locked_bg = ColorRect.new()
		locked_bg.color = Color(0.12, 0.12, 0.12)
		box.add_child(locked_bg)
		var slash = Label.new()
		slash.text = "✕"
		slash.add_theme_font_size_override("font_size", 16)
		slash.add_theme_color_override("font_color", Color(0.4, 0.25, 0.25))
		slash.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		slash.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		box.add_child(slash)
	else:
		var empty_bg = ColorRect.new()
		empty_bg.color = Color(0.18, 0.18, 0.2)
		box.add_child(empty_bg)

	return box

# Loads a building icon by the fixed res://art/icons/buildings/<key>.png
# convention. building_name is the display name (e.g. "Farm"); the
# actual file is the lowercase key. Returns null if the file doesn't
# exist yet, so callers can fall back gracefully instead of erroring.
func _load_building_icon(building_name: String) -> Texture2D:
	var path = "res://art/icons/buildings/%s.png" % building_name.to_lower()
	if not ResourceLoader.exists(path):
		return null
	return load(path)

func _refresh_side_panel_build(zone_id: int) -> void:
	sp_build_title_label.text = "Build in " + zones[zone_id]["name"]

	var slots_used = zones[zone_id]["buildings"].size()
	var slots_max = PlayerInventory.max_buildings_per_zone
	sp_build_slots_label.text = "Building slots: %d / %d" % [slots_used, slots_max]
	sp_build_slots_label.add_theme_color_override("font_color",
		Color(0.9, 0.5, 0.3) if slots_used >= slots_max else Color(0.6, 0.6, 0.6))

	for child in sp_build_rows_container.get_children():
		sp_build_rows_container.remove_child(child)
		child.queue_free()
	tutorial_build_farm_btn = null

	for bname in BUILDINGS:
		var b = BUILDINGS[bname]
		var current_level = zones[zone_id]["buildings"].get(bname, 0)
		var max_level = b.get("max_level", 1)
		var at_max = current_level >= max_level
		var zone_full = slots_used >= slots_max and current_level == 0
		var effective_cost = _get_building_cost(bname)
		# Free as long as the tutorial is active, this is the player's
		# own starting zone (zone 0 — the only zone the tutorial ever
		# directs the player to build in), and they don't have a Farm
		# yet. Checking ownership directly (current_level == 0) rather
		# than pinning to the exact "build_place_farm" step id, since
		# the step id and the player's actual progress can drift out of
		# sync, which previously caused the button to display "FREE"
		# while the real purchase still charged for it.
		var is_tutorial_free_farm = (bname == "Farm" and current_level == 0
			and zone_id == 0 and PlayerInventory.tutorial_active)
		var cant_afford = (not PlayerInventory.can_afford({"gold": effective_cost})) and not is_tutorial_free_farm

		var row_vbox = VBoxContainer.new()
		sp_build_rows_container.add_child(row_vbox)

		var btn = Button.new()
		var btn_text = bname
		if max_level > 1:
			btn_text += " (Lv%d/%d)" % [current_level, max_level]
		if at_max:
			btn_text += " ✓ MAX"
		elif zone_full:
			btn_text += " (zone full)"
		else:
			var action = "Upgrade" if current_level > 0 else "Build"
			if is_tutorial_free_farm:
				btn_text += "  [%s — FREE]" % action
			else:
				btn_text += "  [%s — %d 🪙]" % [action, effective_cost]
			if cant_afford:
				btn_text += " (can't afford)"

		btn.text = btn_text
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.add_theme_font_size_override("font_size", 12)
		btn.disabled = at_max or zone_full or cant_afford
		btn.add_theme_color_override("font_color",
			Color(0.4, 0.8, 0.4) if at_max else (Color(0.5,0.5,0.5) if (zone_full or cant_afford) else Color(0.85, 0.75, 0.4)))
		if current_level == 0:
			btn.pressed.connect(_confirm_build.bind(bname, zone_id))
		else:
			btn.pressed.connect(_on_build_selected.bind(bname, zone_id))
		row_vbox.add_child(btn)
		if bname == "Farm":
			tutorial_build_farm_btn = btn

		var desc = Label.new()
		desc.text = b["desc"]
		desc.add_theme_font_size_override("font_size", 10)
		desc.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD
		row_vbox.add_child(desc)

	if PlayerInventory.tutorial_active:
		TutorialRouter.resolve_current_step(self)

var zone_dynamic_refs: Dictionary = {}   # zone_id -> {warn_icon, countdown_lbl, troop_lbl, march_lbl, circle}

func _draw_map() -> void:
	# Connections and marching dots are cheap, non-interactive visuals —
	# safe to fully rebuild every redraw without affecting clickability.
	for c in connection_lines.get_children():
		c.queue_free()

	for pair in connections:
		var z1 = zones[pair[0]]
		var z2 = zones[pair[1]]
		var line = Line2D.new()
		line.points = [z1["pos"] + Vector2(0, 44), z2["pos"] + Vector2(0, 44)]
		line.width = 2.0
		line.default_color = Color(0.0, 0.0, 0.0, 0.8)
		connection_lines.add_child(line)

	# Zone nodes (which contain the actual clickable buttons) are built
	# ONCE and then updated in place on every subsequent redraw. Rebuilding
	# them from scratch every cycle meant clicks landed on a button that
	# had already been destroyed and replaced, making the map effectively
	# unclickable while the clock was running.
	if zone_nodes.is_empty():
		for zone in zones:
			var znode = _make_zone_node(zone)
			add_child(znode)
			zone_nodes.append(znode)
	else:
		for zone in zones:
			_update_zone_node(zone)

	# Marching dots are cheap and non-interactive — fine to fully rebuild.
	for d in marching_dot_nodes:
		if is_instance_valid(d): d.queue_free()
	marching_dot_nodes.clear()

	for m in marching_troops:
		var from_pos = zones[m["from_zone"]]["pos"] if m["from_zone"] >= 0 else zones[m["to_zone"]]["pos"]
		var to_pos = zones[m["to_zone"]]["pos"]
		var progress = 1.0 - (m["seconds_left"] / max(0.01, m["total_seconds"]))
		progress = clamp(progress, 0.0, 1.0)
		var march_pos = from_pos.lerp(to_pos, progress) + Vector2(0, 44)

		var dot = ColorRect.new()
		dot.size = Vector2(10, 10)
		dot.position = march_pos - Vector2(5, 5)
		dot.color = Color(0.5, 0.9, 1.0)
		add_child(dot)
		marching_dot_nodes.append(dot)

func _make_zone_node(zone: Dictionary) -> Control:
	var container = Control.new()
	container.position = zone["pos"] + Vector2(0, 44)
	container.custom_minimum_size = Vector2(64, 64)

	var refs = {}

	# Zone circle background
	var circle = ColorRect.new()
	circle.size = Vector2(44, 44)
	circle.position = Vector2(-22, -22)
	circle.color = OWNER_COLORS[zone["owner"]].darkened(0.4)
	if zone["id"] == selected_zone_id:
		circle.color = Color(1, 1, 0, 0.3)
	container.add_child(circle)
	refs["circle"] = circle

	# Zone type icon — emoji placeholder (atlas icons TODO)
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
	refs["owner_dot"] = dot

	# Zone name
	var name_lbl = Label.new()
	name_lbl.text = zone["name"]
	name_lbl.add_theme_font_size_override("font_size", 10)
	name_lbl.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	name_lbl.position = Vector2(-30, 24)
	name_lbl.custom_minimum_size = Vector2(60, 0)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	container.add_child(name_lbl)

	# Troop count (created hidden if empty, toggled visible/updated later)
	var troop_lbl = Label.new()
	troop_lbl.add_theme_font_size_override("font_size", 9)
	troop_lbl.add_theme_color_override("font_color", Color(0.6, 0.9, 1.0))
	troop_lbl.position = Vector2(-12, 10)
	troop_lbl.visible = zone["troops"].size() > 0
	troop_lbl.text = "⚔%d" % zone["troops"].size()
	container.add_child(troop_lbl)
	refs["troop_lbl"] = troop_lbl

	# Attack warning indicator — pulsing icon + numeric countdown
	var warn_icon = Label.new()
	warn_icon.text = "⚠"
	warn_icon.add_theme_font_size_override("font_size", 18)
	warn_icon.add_theme_color_override("font_color", Color(1.0, 0.3, 0.2))
	warn_icon.position = Vector2(12, -34)
	warn_icon.visible = false
	container.add_child(warn_icon)
	refs["warn_icon"] = warn_icon

	var tween = create_tween().set_loops()
	tween.tween_property(warn_icon, "scale", Vector2(1.3, 1.3), 0.5)
	tween.tween_property(warn_icon, "scale", Vector2(1.0, 1.0), 0.5)

	var countdown_lbl = Label.new()
	countdown_lbl.add_theme_font_size_override("font_size", 10)
	countdown_lbl.add_theme_color_override("font_color", Color(1.0, 0.6, 0.4))
	countdown_lbl.position = Vector2(10, -16)
	countdown_lbl.visible = false
	container.add_child(countdown_lbl)
	refs["countdown_lbl"] = countdown_lbl

	# Click area — built once, never destroyed on redraw
	var btn = Button.new()
	btn.flat = true
	btn.size = Vector2(64, 64)
	btn.position = Vector2(-32, -32)
	btn.pressed.connect(_on_zone_clicked.bind(zone["id"]))
	container.add_child(btn)
	refs["click_btn"] = btn

	# Incoming troops marker
	var march_lbl = Label.new()
	march_lbl.add_theme_font_size_override("font_size", 10)
	march_lbl.add_theme_color_override("font_color", Color(0.5, 0.9, 1.0))
	march_lbl.position = Vector2(16, 16)
	march_lbl.visible = false
	container.add_child(march_lbl)
	refs["march_lbl"] = march_lbl

	zone_dynamic_refs[zone["id"]] = refs
	return container

# Updates only the parts of a zone node that can change between redraws
# (ownership color, troop count, attack countdown, incoming march timer)
# without touching the button or destroying/recreating anything — this is
# what keeps zones clickable while the map clock is running.
func _update_zone_node(zone: Dictionary) -> void:
	var refs = zone_dynamic_refs.get(zone["id"])
	if refs == null: return

	if is_instance_valid(refs.get("circle")):
		refs["circle"].color = Color(1, 1, 0, 0.3) if zone["id"] == selected_zone_id else OWNER_COLORS[zone["owner"]].darkened(0.4)
	if is_instance_valid(refs.get("owner_dot")):
		refs["owner_dot"].color = OWNER_COLORS[zone["owner"]]

	if is_instance_valid(refs.get("troop_lbl")):
		var has_troops = zone["troops"].size() > 0
		refs["troop_lbl"].visible = has_troops
		if has_troops:
			refs["troop_lbl"].text = "⚔%d" % zone["troops"].size()

	var pending_attack = null
	for attack in pending_attacks:
		if attack["zone_id"] == zone["id"]:
			pending_attack = attack
			break

	if is_instance_valid(refs.get("warn_icon")):
		refs["warn_icon"].visible = pending_attack != null
	if is_instance_valid(refs.get("countdown_lbl")):
		refs["countdown_lbl"].visible = pending_attack != null
		if pending_attack != null:
			refs["countdown_lbl"].text = "%ds" % int(ceil(pending_attack["seconds_remaining"]))

	var incoming_march = null
	for m in marching_troops:
		if m["to_zone"] == zone["id"]:
			incoming_march = m
			break

	if is_instance_valid(refs.get("march_lbl")):
		refs["march_lbl"].visible = incoming_march != null
		if incoming_march != null:
			refs["march_lbl"].text = "→%ds" % int(ceil(incoming_march["seconds_left"]))

# -------------------------------------------------------
# Zone Popup
# -------------------------------------------------------
func _on_zone_clicked(zone_id: int) -> void:
	selected_zone_id = zone_id
	_draw_map()
	if PlayerInventory.tutorial_active and zone_id == 0:
		TutorialRouter.advance_step("build_open_zone")
	_open_side_panel(zone_id)

func _get_explore_tier(zone_id: int) -> String:
	var dist = zones[zone_id].get("dist_from_start", 0.0)
	if dist < 220.0:
		return "Quick"
	elif dist < 480.0:
		return "Standard"
	else:
		return "Deep Delve"

func _on_explore(zone_id: int, suggested_tier: String) -> void:
	var zone = zones[zone_id]
	PlayerInventory.dungeon_tier = suggested_tier
	PlayerInventory.current_stage = zone["enemy_strength"]
	PlayerInventory.current_dungeon_zone_id = zone_id
	PlayerInventory.current_dungeon_zone_type = zone["type"]
	PlayerInventory.set_meta("dungeon_picker_destination", "res://scenes/action_dungeon.tscn")
	SaveManager.save_game()
	get_tree().change_scene_to_file("res://scenes/dungeon_picker_screen.tscn")

func _get_troop_type_by_id(troop_id: String) -> String:
	for troop in PlayerInventory.troop_roster:
		if troop.troop_id == troop_id:
			return troop.get_type_name()
	return "?"

func _add_popup_btn(parent: VBoxContainer, text: String, col: Color, callback: Callable) -> Button:
	var btn = Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(0, 34)
	btn.add_theme_color_override("font_color", col)
	btn.pressed.connect(callback)
	parent.add_child(btn)
	return btn

func _close_popup() -> void:
	if popup_panel and is_instance_valid(popup_panel):
		popup_panel.queue_free()
		popup_panel = null

# -------------------------------------------------------
# Map Tutorial Popups
# Short narrated hints shown once each, only when play_tutorial is on.
# -------------------------------------------------------
const TUTORIAL_HINTS = {
	"intro": {
		"title": "The World Map",
		"body": "This is your campaign map. Your City sits unclaimed — conquer it first to establish your base. From there, expand outward: build up zones, station troops, and push back the creatures of the wilds.",
	},
	"conquer": {
		"title": "Conquering Zones",
		"body": "Conquering a neutral zone always triggers a battle against its guards. Stronger zones lie further from your territory. You can only conquer zones adjacent to ground you already hold.",
	},
	"build": {
		"title": "Building Up",
		"body": "Each zone can hold up to 2 buildings. Watchtowers warn you of attacks earlier, Farms and Barracks generate resources, and Forges/Shrines buff troops stationed nearby. Choose wisely — you can't build everything everywhere.",
	},
	"move_troops": {
		"title": "Positioning Troops",
		"body": "Troops take time to travel between zones based on distance. Keep your border zones defended — reinforcements from far away won't always arrive in time.",
	},
	"end_turn": {
		"title": "Time Flows on Its Own",
		"body": "The map runs in real time now — resources accrue, troops march, and the wilds may move against you continuously. Use the pause button if you need a moment to think, and the speed slider to fast-forward when things are quiet.",
	},
}

func _resolve_tutorial_step() -> void:
	# If a save/reload landed us at the defense_battle step while still
	# on the world map (the scripted attack already advanced the step but
	# the scene change hadn't persisted), trigger the attack now instead
	# of showing a dead-end navigation reminder with no action button.
	if PlayerInventory.tutorial_active:
		var step = TutorialSteps.get_step(PlayerInventory.tutorial_step_index)
		if step.get("id", "") == "defense_battle":
			_start_scripted_tutorial_defense()
			return
	TutorialRouter.resolve_current_step(self)

# Fires on every tutorial step advance while this screen is loaded.
# TutorialRouter connects to TutorialOverlay.step_advanced in its own
# _ready() — autoloads initialize before any scene, so that connection
# is made before this one, meaning by the time THIS handler runs,
# tutorial_step_index has already moved to the NEXT step. So this
# checks for "defense_battle" (the step that follows the info-only
# "defense_intro"), not "defense_intro" itself.
func _on_tutorial_step_advanced() -> void:
	if not PlayerInventory.tutorial_active: return
	var step = TutorialSteps.get_step(PlayerInventory.tutorial_step_index)
	if step.get("id", "") == "defense_battle":
		call_deferred("_start_scripted_tutorial_defense")

# A guaranteed, scripted attack on the player's own city — winnable by
# a wide margin, since the tutorial design explicitly requires this
# fight to never realistically be lost, just to feel like it costs
# something. Uses 1.0 (neutral scaling): enemies have baseline ATK/HP,
# the Knight's percentage-based DEF reduction keeps it alive through
# the fight, and the base has enough HP to survive if 1-2 enemies slip
# through. The wave is also capped in defense_scene._plan_wave().
const TUTORIAL_DEFENSE_FORCE_MULT = 1.0

func _start_scripted_tutorial_defense() -> void:
	var zone = zones[0]
	_notify("⚔ %s is under attack! You must defend it now." % zone["name"])
	PlayerInventory.current_battle_zone = 0
	PlayerInventory.current_stage = zones[0]["enemy_strength"]  # = 1, always gentle
	PlayerInventory.current_attack_force = TUTORIAL_DEFENSE_FORCE_MULT
	PlayerInventory.conquering_zone = false
	PlayerInventory.set_battle_roster_from_zone_troops(zone["troops"])
	PlayerInventory.set_battle_zone_buffs(get_best_forge_level(0), get_best_shrine_level(0))
	SaveManager.save_game()
	get_tree().change_scene_to_file("res://scenes/defense_scene.tscn")

# Maps a tutorial step's target_id (see autoloads/tutorial_steps.gd) to
# an actual Control on this screen. Sub-step 3 fills these in properly
# as each step's real hookup is built; pause_button and speed_slider
# are wired now since both already exist as named vars on this screen.
func get_tutorial_target(target_id: String) -> Control:
	match target_id:
		"time_label": return hud_time
		"pause_button": return pause_btn
		"speed_slider": return speed_slider
		"owned_zone_marker":
			if zone_dynamic_refs.has(0) and zone_dynamic_refs[0].has("click_btn"):
				return zone_dynamic_refs[0]["click_btn"]
			return null
		"build_here_button":
			# If the player hit Next in build_open_zone without clicking the zone,
			# the side panel was never opened. Open it now so the button exists.
			if tutorial_build_here_btn == null:
				_open_side_panel(0)
			return tutorial_build_here_btn
		"farm_button": return tutorial_build_farm_btn
		"mgmt_button": return tutorial_mgmt_btn
		_: return null

func _show_map_tutorial_popup(hint_key: String) -> void:
	if PlayerInventory.tutorial_active:
		return   # the new forced walkthrough (TutorialRouter) supersedes these older optional hints entirely
	if PlayerInventory.map_tutorial_seen.get(hint_key, true):
		return
	PlayerInventory.map_tutorial_seen[hint_key] = true

	var hint = TUTORIAL_HINTS[hint_key]

	var overlay = CanvasLayer.new()
	add_child(overlay)

	var bg = ColorRect.new()
	bg.color = Color(0, 0, 0, 0.6)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(bg)

	var panel = PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(380, 0)
	overlay.add_child(panel)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	panel.add_child(vbox)

	var title = Label.new()
	title.text = hint["title"]
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
	vbox.add_child(title)

	var body = Label.new()
	body.text = hint["body"]
	body.add_theme_font_size_override("font_size", 13)
	body.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	body.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(body)

	var btn = Button.new()
	btn.text = "Got it"
	btn.custom_minimum_size = Vector2(0, 38)
	btn.add_theme_color_override("font_color", Color(0.4, 0.9, 0.4))
	btn.pressed.connect(func(): overlay.queue_free())
	vbox.add_child(btn)

# -------------------------------------------------------
# Zone Actions
# -------------------------------------------------------
func _is_adjacent_to_player(zone_id: int) -> bool:
	for conn in zones[zone_id]["connections"]:
		if zones[conn]["owner"] == "player":
			return true
	return false

func _get_retreat_zone_for_loss(zone_id: int) -> int:
	var source_dist = zones[zone_id].get("dist_from_start", 0.0)
	var best_id = -1
	var best_dist = INF

	# Prefer an owned connected zone closer to home: this feels like
	# falling back along the route the player expanded through.
	for conn_id in zones[zone_id]["connections"]:
		if zones[conn_id]["owner"] != "player":
			continue
		var conn_dist = zones[conn_id].get("dist_from_start", 0.0)
		if conn_dist <= source_dist and conn_dist < best_dist:
			best_id = conn_id
			best_dist = conn_dist

	if best_id >= 0:
		return best_id

	# If the local front line is cut off, preserve the troops by sending
	# them to the closest remaining owned zone, normally Your City.
	for i in range(zones.size()):
		if i == zone_id or zones[i]["owner"] != "player":
			continue
		var dist = zones[i]["dist_from_start"]
		if dist < best_dist:
			best_id = i
			best_dist = dist

	return best_id

func _retreat_zone_troops_after_loss(zone_id: int) -> Dictionary:
	var troop_ids = zones[zone_id]["troops"].duplicate()
	zones[zone_id]["troops"].clear()

	var retreat_zone_id = _get_retreat_zone_for_loss(zone_id)
	if retreat_zone_id < 0:
		return {"count": 0, "destination_id": -1, "destination_name": "nowhere"}

	var retreated_count = 0
	for troop_id in troop_ids:
		var troop = _get_troop_data_by_id(troop_id)
		if troop != null:
			troop.current_hp = 1
		if troop_id not in zones[retreat_zone_id]["troops"]:
			zones[retreat_zone_id]["troops"].append(troop_id)
		retreated_count += 1

	return {
		"count": retreated_count,
		"destination_id": retreat_zone_id,
		"destination_name": zones[retreat_zone_id]["name"],
	}

func _on_battle_won(zone_id: int) -> void:
	zones[zone_id]["owner"] = "player"
	_notify("Conquered %s!" % zones[zone_id]["name"])
	_draw_map()

func _on_battle_lost(zone_id: int) -> void:
	# If defending — zone reverts to neutral
	if not PlayerInventory.conquering_zone:
		var retreat_result = _retreat_zone_troops_after_loss(zone_id)
		zones[zone_id]["owner"] = "neutral"
		if retreat_result["count"] > 0:
			_notify("%s was lost to the wilds! %d troop(s) retreated to %s at 1 HP." % [
				zones[zone_id]["name"], retreat_result["count"], retreat_result["destination_name"]
			])
		else:
			_notify("%s was lost to the wilds!" % zones[zone_id]["name"])
	_draw_map()

func _on_conquer(zone_id: int) -> void:
	_close_popup()

	var any_zone_owned = false
	for z in zones:
		if z["owner"] == "player":
			any_zone_owned = true
			break

	var staging_troop_ids: Array

	if not any_zone_owned and zone_id == 0:
		# First-ever conquest, no territory yet — use the full roster directly.
		staging_troop_ids = []
		for troop in PlayerInventory.troop_roster:
			staging_troop_ids.append(troop.troop_id)
	else:
		# Conquering uses troops from the nearest adjacent zone you already own,
		# since the target zone itself has no player troops stationed yet.
		if PlayerInventory.play_tutorial and not PlayerInventory.map_tutorial_seen["conquer"]:
			_show_map_tutorial_popup("conquer")

		var staging_zone_id = -1
		for conn_id in zones[zone_id]["connections"]:
			if zones[conn_id]["owner"] == "player":
				staging_zone_id = conn_id
				break

		if staging_zone_id == -1:
			_notify("You must own an adjacent zone to launch a conquest from.")
			return

		staging_troop_ids = zones[staging_zone_id]["troops"]
		PlayerInventory.set_battle_zone_buffs(
			get_best_forge_level(staging_zone_id), get_best_shrine_level(staging_zone_id))

	# Always triggers a battle — difficulty scales purely with zone distance
	PlayerInventory.current_battle_zone = int(zone_id)
	PlayerInventory.current_stage = zones[zone_id]["enemy_strength"]
	var diff_force = PlayerInventory.difficulty_settings.get("force_size", 1.0)
	if PlayerInventory.unlocked_talents.get("diplomatic_tongue", false):
		diff_force *= 0.8
	PlayerInventory.current_attack_force = diff_force
	PlayerInventory.conquering_zone = true
	PlayerInventory.set_battle_roster_from_zone_troops(staging_troop_ids)
	SaveManager.save_game()
	get_tree().change_scene_to_file("res://scenes/defense_scene.tscn")



func _on_move_troops(zone_id: int) -> void:
	_close_popup()
	if PlayerInventory.play_tutorial and not PlayerInventory.map_tutorial_seen["move_troops"]:
		_show_map_tutorial_popup("move_troops")
	_open_move_troops_panel(zone_id)

func _on_build(zone_id: int) -> void:
	if PlayerInventory.play_tutorial and not PlayerInventory.map_tutorial_seen["build"]:
		_show_map_tutorial_popup("build")
	_show_side_panel_build(zone_id)

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
		var already_here = troop.troop_id in zones[target_zone_id]["troops"]

		var btn = Button.new()
		btn.text = "%s [%s]%s" % [
			troop.troop_name,
			troop.get_type_name(),
			" ✓ HERE" if already_here else ""
		]
		btn.add_theme_font_size_override("font_size", 12)
		btn.add_theme_color_override("font_color",
			Color(0.4, 1.0, 0.4) if already_here else Color(0.8, 0.8, 0.8))
		btn.pressed.connect(_on_assign_troop.bind(troop.troop_id, target_zone_id))
		vbox.add_child(btn)

	var close_btn = Button.new()
	close_btn.text = "Done"
	close_btn.pressed.connect(_close_popup)
	vbox.add_child(close_btn)

func _on_assign_troop(troop_id: String, zone_id: int) -> void:
	var troop_display_name = _get_troop_name_by_id(troop_id)

	# Find which zone this troop is currently in (if any)
	var from_zone_id = -1
	for z in zones:
		if troop_id in z["troops"]:
			from_zone_id = z["id"]
			break

	# Cancel any existing march for this troop
	for m in marching_troops.duplicate():
		if m["troop_id"] == troop_id:
			marching_troops.erase(m)

	if from_zone_id == zone_id:
		_close_popup()
		_notify("%s is already stationed there." % troop_display_name)
		return

	# Calculate travel time based on distance, in real seconds (at 1x speed)
	var travel_seconds = 0.0
	if from_zone_id >= 0:
		var effective_speed = TRAVEL_SPEED
		if PlayerInventory.unlocked_talents.get("combat_forced_march", false):
			effective_speed *= 1.5
		var dist = zones[from_zone_id]["pos"].distance_to(zones[zone_id]["pos"])
		travel_seconds = max(2.0, dist / effective_speed)
	else:
		travel_seconds = 2.0  # unassigned troop, quick mobilization

	if travel_seconds <= 2.0 and from_zone_id >= 0:
		# Close enough — arrives almost immediately
		zones[from_zone_id]["troops"].erase(troop_id)
		zones[zone_id]["troops"].append(troop_id)
		_notify("%s stationed at %s" % [troop_display_name, zones[zone_id]["name"]])
	else:
		# Remove from origin immediately (troop is "marching")
		if from_zone_id >= 0:
			zones[from_zone_id]["troops"].erase(troop_id)
		marching_troops.append({
			"troop_id": troop_id, "troop_name": troop_display_name, "from_zone": from_zone_id,
			"to_zone": zone_id, "seconds_left": travel_seconds, "total_seconds": travel_seconds,
		})
		_notify("%s marching to %s — arrives in %ds" % [troop_display_name, zones[zone_id]["name"], int(travel_seconds)])

	_close_popup()
	_save_map_state()
	_draw_map()

func _get_troop_name_by_id(troop_id: String) -> String:
	for troop in PlayerInventory.troop_roster:
		if troop.troop_id == troop_id:
			return troop.troop_name
	return "Unknown Unit"

# Same lookup as _get_troop_name_by_id, but returns the full TroopData
# object — needed by the unit slot grid for troop_type (icon + sort
# priority), not just the display name.
func _get_troop_data_by_id(troop_id: String) -> TroopData:
	for troop in PlayerInventory.troop_roster:
		if troop.troop_id == troop_id:
			return troop
	return null

# -------------------------------------------------------
# Build Panel
# -------------------------------------------------------
const BUILDINGS = {
	"Watchtower": {
		"desc": "Extends attack warning by +1 turn for this zone and its neighbors.",
		"cost": 30, "max_level": 1,
	},
	"Barracks": {
		"desc": "Unlocks an additional troop slot. Generates a trickle of Gold each turn.",
		"cost": 45, "max_level": 1,
	},
	"Farm": {
		"desc": "Generates Food each turn.",
		"cost": 30, "max_level": 1,
	},
	"Forge": {
		"desc": "Troops stationed here or in adjacent zones gain bonus attack. +5% per level.",
		"cost": 45, "max_level": 4,
	},
	"Shrine": {
		"desc": "Troops stationed here or in adjacent zones gain bonus HP. +5% per level.",
		"cost": 45, "max_level": 4,
	},
}

func _confirm_build(building_name: String, zone_id: int) -> void:
	# Tutorial-free farm skips confirm to avoid disrupting tutorial flow.
	var is_tutorial_free = (building_name == "Farm" and zone_id == 0 and PlayerInventory.tutorial_active)
	if is_tutorial_free:
		_on_build_selected(building_name, zone_id)
		return

	_close_popup()
	popup_panel = PanelContainer.new()
	popup_panel.position = Vector2(MAP_W / 2 - 160, MAP_H / 2 - 80)
	popup_panel.custom_minimum_size = Vector2(320, 0)
	add_child(popup_panel)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	popup_panel.add_child(vbox)

	var title = Label.new()
	title.text = "Build %s?" % building_name
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
	vbox.add_child(title)

	var cost = _get_building_cost(building_name)
	var msg = Label.new()
	msg.text = "Cost: %d gold\nBuildings are permanent and cannot be removed." % cost
	msg.add_theme_font_size_override("font_size", 12)
	msg.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75))
	msg.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(msg)

	var btn_row = HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 8)
	vbox.add_child(btn_row)

	var confirm_btn = Button.new()
	confirm_btn.text = "Confirm"
	confirm_btn.custom_minimum_size = Vector2(130, 36)
	confirm_btn.add_theme_font_size_override("font_size", 13)
	confirm_btn.add_theme_color_override("font_color", Color(0.3, 0.9, 0.3))
	confirm_btn.pressed.connect(func():
		_close_popup()
		_on_build_selected(building_name, zone_id)
	)
	btn_row.add_child(confirm_btn)

	var cancel_btn = Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.custom_minimum_size = Vector2(130, 36)
	cancel_btn.add_theme_font_size_override("font_size", 13)
	cancel_btn.pressed.connect(_close_popup)
	btn_row.add_child(cancel_btn)

func _on_build_selected(building_name: String, zone_id: int) -> void:
	print("[TUTORIAL DEBUG] _on_build_selected FIRED: building=%s zone_id=%d" % [building_name, zone_id])
	var zone = zones[zone_id]
	var current_level = zone["buildings"].get(building_name, 0)
	var max_level = BUILDINGS[building_name].get("max_level", 1)
	var is_new_building = current_level == 0

	if is_new_building and zone["buildings"].size() >= PlayerInventory.max_buildings_per_zone:
		_notify("This zone's building slots are full!")
		return

	if current_level >= max_level:
		return

	var cost = _get_building_cost(building_name)
	# Free as long as the tutorial is active, this is the player's own
	# starting zone (zone 0), and they don't have a Farm yet — matches
	# the same check used when building this menu's button text/
	# affordability above, rather than pinning to the exact
	# "build_place_farm" step id (which could drift out of sync with
	# the step index and cause the button to display "FREE" while this
	# function still charged for it).
	var is_tutorial_free_farm = (building_name == "Farm" and is_new_building
		and zone_id == 0 and PlayerInventory.tutorial_active)
	print("[TUTORIAL DEBUG] is_tutorial_free_farm=%s (is_new_building=%s tutorial_active=%s)" % [is_tutorial_free_farm, is_new_building, PlayerInventory.tutorial_active])
	if not is_tutorial_free_farm:
		if not PlayerInventory.can_afford({"gold": cost}):
			_notify("Not enough Gold — need %d." % cost)
			return
		PlayerInventory.spend_resources({"gold": cost})
	zone["buildings"][building_name] = current_level + 1
	if is_tutorial_free_farm:
		TutorialRouter.advance_step("build_place_farm")

	if building_name == "Barracks" and current_level == 0:
		PlayerInventory.unlock_troop_slot()

	_refresh_side_panel_build(zone_id)
	_draw_map()
	_refresh_hud()

	if current_level == 0:
		_notify("Built %s in %s!" % [building_name, zone["name"]])
		Telemetry.log_event("building_built", {
			"building": building_name, "zone_type": zone["type"], "stage": PlayerInventory.current_stage,
		})
	else:
		_notify("Upgraded %s to Lv%d in %s!" % [building_name, current_level + 1, zone["name"]])
		Telemetry.log_event("building_upgraded", {
			"building": building_name, "level": current_level + 1,
			"zone_type": zone["type"], "stage": PlayerInventory.current_stage,
		})

# Returns the resource cost to build/upgrade a building, with the
# Efficient Construction talent discount applied (-25%, minimum 10).
func _get_building_cost(building_name: String) -> int:
	var base_cost = BUILDINGS[building_name]["cost"]
	if PlayerInventory.unlocked_talents.get("buildings_efficient_construction", false):
		return max(10, int(base_cost * 0.75))
	return base_cost

# -------------------------------------------------------
# Building Effects
# -------------------------------------------------------

# Returns the warning-time bonus for a zone from its own Watchtower
# plus any adjacent zone's Watchtower. Reinforced Towers talent makes
# each contributing Watchtower worth +2 turns instead of +1.
func get_watchtower_bonus(zone_id: int) -> int:
	var per_tower = 2 if PlayerInventory.unlocked_talents.get("buildings_reinforced_towers", false) else 1
	var bonus = 0
	if zones[zone_id]["buildings"].has("Watchtower"):
		bonus = per_tower
	for conn_id in zones[zone_id]["connections"]:
		if zones[conn_id]["buildings"].has("Watchtower"):
			bonus = max(bonus, per_tower)
	return bonus

# Returns the best Forge level affecting this zone. Normally only itself
# or directly adjacent zones count; the Wider Reach talent extends this
# to zones up to 2 connections away.
func get_best_forge_level(zone_id: int) -> int:
	return _get_best_building_level_in_range(zone_id, "Forge")

# Returns the best Shrine level affecting this zone (same range rules as Forge)
func get_best_shrine_level(zone_id: int) -> int:
	return _get_best_building_level_in_range(zone_id, "Shrine")

func _get_best_building_level_in_range(zone_id: int, building_name: String) -> int:
	var wider_reach = PlayerInventory.unlocked_talents.get("buildings_wider_reach", false)
	var best = zones[zone_id]["buildings"].get(building_name, 0)

	# Range 1: directly adjacent zones (always applies)
	for conn_id in zones[zone_id]["connections"]:
		best = max(best, zones[conn_id]["buildings"].get(building_name, 0))

	# Range 2: zones adjacent to those adjacent zones (only with the talent)
	if wider_reach:
		for conn_id in zones[zone_id]["connections"]:
			for conn2_id in zones[conn_id]["connections"]:
				if conn2_id == zone_id: continue
				best = max(best, zones[conn2_id]["buildings"].get(building_name, 0))

	return best

# Generates resources from Farm/Barracks each turn
func _process_resource_generation(delta: float) -> void:
	var farm_yield = 50.0 if PlayerInventory.unlocked_talents.get("economy_bountiful_harvest", false) else 30.0
	var barracks_yield = 4.0 if PlayerInventory.unlocked_talents.get("economy_steady_coffers", false) else 2.0
	var trade_routes = PlayerInventory.unlocked_talents.get("economy_trade_routes", false)

	var food_gain = 0.0
	var gold_gain = 0.0

	for zone in zones:
		if zone["owner"] != "player": continue
		var has_farm = zone["buildings"].has("Farm")
		var has_barracks = zone["buildings"].has("Barracks")
		if has_farm:
			food_gain += farm_yield
		if has_barracks:
			gold_gain += barracks_yield
		if trade_routes and not has_farm and not has_barracks:
			gold_gain += 2.0 if PlayerInventory.unlocked_talents.get("economy_supply_network", false) else 1.0

	var income_mult = PlayerInventory.difficulty_settings.get("income_mult", 1.0)
	if food_gain > 0:
		PlayerInventory.resources["food"] += (food_gain * income_mult / SECONDS_PER_OLD_TURN) * delta
	if gold_gain > 0:
		PlayerInventory.resources["gold"] += (gold_gain * income_mult / SECONDS_PER_OLD_TURN) * delta

# -------------------------------------------------------
# Real-Time Clock
# -------------------------------------------------------
func _process(delta: float) -> void:
	_process_camera_pan(delta)
	_sync_runtime_from_inventory()
	PlayerInventory.launch_next_map_mandatory_battle()
	_refresh_hud()
	_draw_map()

func _sync_runtime_from_inventory() -> void:
	zones = PlayerInventory.map_zones
	connections = PlayerInventory.map_connections
	elapsed_seconds = PlayerInventory.map_elapsed_seconds
	time_speed = PlayerInventory.map_time_speed
	is_paused = PlayerInventory.map_is_paused
	attack_roll_timer = PlayerInventory.map_attack_roll_timer
	pending_attacks = PlayerInventory.map_pending_attacks
	marching_troops = PlayerInventory.map_marching_troops
	mandatory_battle_queue = PlayerInventory.map_mandatory_battle_queue

# Arrow-key panning, works even while the map is paused since looking
# around shouldn't require the clock to be running.
func _process_camera_pan(delta: float) -> void:
	if not map_camera: return
	var dir = Vector2.ZERO
	if Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_A):
		dir.x -= 1
	if Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D):
		dir.x += 1
	if Input.is_key_pressed(KEY_UP) or Input.is_key_pressed(KEY_W):
		dir.y -= 1
	if Input.is_key_pressed(KEY_DOWN) or Input.is_key_pressed(KEY_S):
		dir.y += 1
	if dir != Vector2.ZERO:
		map_camera.position += dir.normalized() * PAN_SPEED * delta

func _process_marching_troops(delta: float) -> void:
	var arrived = []
	for m in marching_troops:
		m["seconds_left"] -= delta
		if m["seconds_left"] <= 0:
			zones[m["to_zone"]]["troops"].append(m["troop_id"])
			_notify("%s arrived at %s" % [m["troop_name"], zones[m["to_zone"]]["name"]])
			arrived.append(m)
	for a in arrived:
		marching_troops.erase(a)

# Called by the Admin Panel to force one attack attempt right now,
# ignoring the normal random chance and max-simultaneous cooldown.
# Reuses the exact same targeting rule as the real attack system —
# a player-owned zone adjacent to a neutral one — so testing reflects
# genuine attack behavior. Returns a status string for the panel to show.
func force_admin_attack() -> String:
	_sync_runtime_from_inventory()
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

	if targets.is_empty():
		return "No valid target zones found (need a player-owned zone adjacent to a neutral one, not already under attack)."

	var target_id = targets[randi() % targets.size()]
	var diff_settings = PlayerInventory.difficulty_settings
	var force = diff_settings.get("force_size", 1.0)
	var warning_seconds = 3.0   # short, for fast testing rather than the real warning_turns delay

	pending_attacks.append({
		"zone_id": target_id,
		"seconds_remaining": warning_seconds,
		"total_seconds": warning_seconds,
		"force_size": force,
	})
	PlayerInventory.map_pending_attacks = pending_attacks
	SaveManager.save_game()
	_notify("⚠ [Admin] Forced attack on %s in %ds!" % [zones[target_id]["name"], int(warning_seconds)])
	return "Forced attack queued on %s." % zones[target_id]["name"]

func _maybe_spawn_attack() -> void:
	var diff_settings = PlayerInventory.difficulty_settings

	# On Easy/Normal, invasions are gated behind the "Wilds Pact" talent — they
	# don't happen at all until the talent is unlocked. Once unlocked, the player
	# can also toggle them off. Hard/Nightmare always invade regardless.
	var can_toggle = diff_settings.get("invasions_toggleable", true)
	var talent_unlocked = PlayerInventory.unlocked_talents.get("toggle_invasions", false)
	if can_toggle and not (talent_unlocked and PlayerInventory.invasions_enabled):
		return

	var attack_chance = diff_settings.get("attack_frequency", 0.6) * 0.25
	var warning_turns = int(diff_settings.get("warning_turns", 3))
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
	var base_force = diff_settings.get("force_size", 1.0)
	var zone_force = zones[target_id]["enemy_strength"] * 0.15
	var force = max(base_force, zone_force)
	var effective_warning_turns = warning_turns + get_watchtower_bonus(target_id)
	var effective_warning_seconds = effective_warning_turns * SECONDS_PER_OLD_TURN
	pending_attacks.append({
		"zone_id": target_id,
		"seconds_remaining": effective_warning_seconds,
		"total_seconds": effective_warning_seconds,
		"force_size": force,
	})
	_notify("⚠ Creatures from the wilds will attack %s in %ds!" % [zones[target_id]["name"], int(effective_warning_seconds)])

	# Nightmare/Hard can roll a second attack at the same time
	if pending_attacks.size() < max_simultaneous and randf() < attack_chance * 0.5:
		_maybe_spawn_attack()

func _process_attack_countdowns(delta: float) -> void:
	var remaining = []
	var triggered = []
	for attack in pending_attacks:
		attack["seconds_remaining"] -= delta
		if attack["seconds_remaining"] <= 0:
			triggered.append(attack)
		else:
			remaining.append(attack)
	pending_attacks = remaining

	if triggered.size() > 0:
		mandatory_battle_queue.append_array(triggered)
		_launch_next_mandatory_battle()

func _launch_next_mandatory_battle() -> void:
	if mandatory_battle_queue.is_empty():
		return
	var attack = mandatory_battle_queue[0]
	var zone = zones[int(attack["zone_id"])]
	_notify("⚔ %s is under attack from the wilds! You must defend it now." % zone["name"])
	PlayerInventory.current_battle_zone = int(attack["zone_id"])
	PlayerInventory.current_stage = zones[int(attack["zone_id"])]["enemy_strength"]
	PlayerInventory.current_attack_force = attack["force_size"]
	PlayerInventory.conquering_zone = false
	# Roster is snapshotted NOW, at the moment the attack actually lands —
	# not when it was first announced — so troops that marched in partway
	# through the warning countdown are present and able to help defend.
	PlayerInventory.set_battle_roster_from_zone_troops(zone["troops"])
	PlayerInventory.set_battle_zone_buffs(
		get_best_forge_level(int(attack["zone_id"])), get_best_shrine_level(int(attack["zone_id"])))
	SaveManager.save_game()
	get_tree().change_scene_to_file("res://scenes/defense_scene.tscn")

# -------------------------------------------------------
# HUD
# -------------------------------------------------------
func _refresh_hud() -> void:
	if hud_time:
		var total_secs = int(elapsed_seconds)
		var mins = total_secs / 60
		var secs = total_secs % 60
		hud_time.text = ("⏸ " if is_paused else "") + "Day %d, %02d:%02d" % [(mins / 60) + 1, mins % 60, secs]
	if hud_diff:
		var col = {"Easy": Color(0.3,0.9,0.3), "Normal": Color(0.4,0.7,1.0),
				   "Hard": Color(1.0,0.65,0.1), "Nightmare": Color(0.9,0.2,0.2)}
		hud_diff.text = "[%s]" % PlayerInventory.difficulty
		hud_diff.add_theme_color_override("font_color",
			col.get(PlayerInventory.difficulty, Color.WHITE))
	if hud_resources:
		hud_resources.text = "🌾%d 🪙%d" % [int(PlayerInventory.resources.get("food", 0)), int(PlayerInventory.resources.get("gold", 0))]

func _on_pause_pressed() -> void:
	is_paused = not is_paused
	PlayerInventory.map_is_paused = is_paused
	pause_btn.text = "▶" if is_paused else "⏸"
	_refresh_hud()
	if PlayerInventory.tutorial_active:
		TutorialRouter.advance_step("map_pause")

func _on_speed_changed(value: float) -> void:
	time_speed = value
	PlayerInventory.map_time_speed = value
	speed_label.text = "%.1fx" % value

func _notify(msg: String) -> void:
	if notification_label:
		notification_label.text = msg
		# Clear after 4 seconds
		get_tree().create_timer(4.0).timeout.connect(func():
			if is_instance_valid(notification_label):
				notification_label.text = "")

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			_close_popup()
			_close_side_panel()
			selected_zone_id = -1
			_draw_map()
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			is_panning = event.pressed
	if event is InputEventMouseMotion and is_panning and map_camera:
		map_camera.position -= event.relative
	if event is InputEventKey and event.pressed and event.keycode == KEY_SPACE:
		_on_pause_pressed()
