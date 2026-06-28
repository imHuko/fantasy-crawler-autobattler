extends CanvasLayer

# -------------------------------------------------------
# TutorialOverlay — dims the screen and shows an instruction panel
# positioned near whatever Control the current step is about. Call
# show_step_click(...) or show_step_info(...) from any screen.
#
# DESIGN NOTE — advancement is now ALWAYS explicit. This overlay does
# NOT auto-detect clicks on the target anymore. An earlier version
# auto-connected to the target Button's own "pressed" signal and
# compared object references after the fact to decide whether to
# advance — but that meant two separate systems (this overlay, and the
# real screen's own click handler) were both reacting to the same
# click, and whichever one ran first could change state the other one
# then read incorrectly. That caused several real, hard-to-diagnose
# bugs (steps advancing early, advancing twice, or never advancing at
# all) because the real game's UI is dynamic — popups open and close,
# buttons get rebuilt — and chasing a moving target through all of
# that turned out to be the actual source of the fragility, not any
# one specific bug.
#
# The fix: the screen's own code, which already knows for certain that
# the real action just succeeded (a building was actually built, an
# item was actually equipped, etc.), calls
# TutorialRouter.advance_step("the_step_id_it_expects") directly, right
# at that real point of success. No signal connecting, no object
# reference to keep in sync, no race between two listeners on the same
# button. The Next button remains as a permanent, always-available
# manual fallback on every step, for cases where the explicit call
# doesn't fit naturally or as a way to skip ahead.
#
# Register this as an autoload named "TutorialOverlay" in Project >
# Project Settings > Autoload, so it persists across scene changes.
#
# TARGET HIGHLIGHTING — a pulsing gold border drawn around current_target,
# in addition to the instruction panel. The position math is the part
# that actually matters here: it uses get_global_transform_with_canvas()
# rather than get_global_rect(). A Control's get_global_rect() resolves
# to pre-camera "canvas" coordinates — fine for anything in a CanvasLayer
# (the HUD, the World Map's persistent side panel), but WRONG for a
# target still living directly in a Camera2D-affected tree (e.g. the
# World Map's zone markers), since it ignores whatever the camera's
# current pan/zoom actually has on screen. get_global_transform_with_canvas()
# resolves all the way to real viewport pixels, camera included, and
# happens to agree exactly with get_global_rect() wherever there's no
# camera in play — so it's a safe universal replacement, used for both
# the highlight and the instruction panel's own positioning below.
# Tracking also runs every frame (_process), not just on show/resize,
# since the World Map doesn't pause during a click-mode step and the
# camera can move while the player is still looking for the target.
#
# INPUT LOCKING — the dim bands double as a click-blocker. Whenever
# blocking_enabled is true, the bands switch from MOUSE_FILTER_IGNORE to
# MOUSE_FILTER_STOP, so any click landing outside the bright cutout is
# intercepted before it reaches the real game UI underneath — only the
# cutout itself (the actual target) and the always-visible Next button
# can be clicked. blocking_enabled is true for an actual step
# (show_step_click/show_step_info — there's a defined right answer: hit
# the target, or hit Next) and false for show_navigation_reminder, since
# that one has no Next button and the player needs free use of the
# game's own screen-switching controls to physically reach wherever the
# next step lives — blocking everything there would strand them with no
# way to get there.
#
# dim_enabled controls whether the 4 dim bands are shown at all.
# Normally true, but set to false for show_step_free — used for any
# step where the player needs free access to the full game screen to
# complete it (e.g. the tutorial dungeon, which the player has to
# actually play through). In that case the instruction panel still
# shows, but nothing is dimmed or blocked.
#
# The World Map's own camera panning (middle-mouse drag, arrow keys) is
# unaffected either way: that's handled in world_map.gd's _input(),
# which Godot runs before GUI mouse_filter logic ever sees the event,
# regardless of what these bands are set to.
# -------------------------------------------------------

signal step_advanced

const DIM_COLOR = Color(0, 0, 0, 0.55)
const PANEL_GAP = 16.0   # space between the target and the instruction panel

const HIGHLIGHT_COLOR = Color(1.0, 0.85, 0.2, 1.0)   # gold — matches the existing zone-selection tint in world_map.gd
const HIGHLIGHT_BORDER_WIDTH = 3
const HIGHLIGHT_CORNER_RADIUS = 6
const HIGHLIGHT_PADDING = 6.0      # how far the highlight extends past the target's own edges
const HIGHLIGHT_PULSE_MIN_ALPHA = 0.55
const HIGHLIGHT_PULSE_MAX_ALPHA = 1.0
const HIGHLIGHT_PULSE_DURATION = 0.6   # seconds for one fade direction of the pulse

var dim_top: ColorRect
var dim_bottom: ColorRect
var dim_left: ColorRect
var dim_right: ColorRect
var instruction_panel: PanelContainer
var instruction_label: Label
var next_btn: Button
var action_btn: Button   # optional "Go to X" shortcut button shown inside the panel on some nav reminders — see show_navigation_reminder
var highlight_rect: Panel
var highlight_pulse_tween: Tween

var current_target: Control = null
var is_active: bool = false
var blocking_enabled: bool = false
var dim_enabled: bool = true
var _pending_action: Callable = Callable()

func _ready() -> void:
	layer = 90   # below the Admin Panel (layer 100), above normal gameplay UI
	_build_nodes()
	visible = false
	get_tree().get_root().size_changed.connect(_on_viewport_resized)

func _on_viewport_resized() -> void:
	if not is_active: return
	_position_panel()

func _process(_delta: float) -> void:
	if not is_active: return
	if current_target == null or not is_instance_valid(current_target):
		return   # nothing moving to track — the centered/no-target cases don't change between frames
	_position_panel(false)   # quiet repositioning, no debug print spam every frame

# One piece of the 4-band dim "frame" — see _apply_dim_bands() for how
# the 4 are arranged to leave a bright cutout around the target instead
# of dimming straight over it.
func _make_dim_band() -> ColorRect:
	var band = ColorRect.new()
	band.color = DIM_COLOR
	add_child(band)
	return band

func _build_nodes() -> void:
	dim_top = _make_dim_band()
	dim_bottom = _make_dim_band()
	dim_left = _make_dim_band()
	dim_right = _make_dim_band()

	highlight_rect = Panel.new()
	highlight_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE   # purely visual, same reasoning as the dim bands/instruction_panel below
	var highlight_style = StyleBoxFlat.new()
	highlight_style.bg_color = Color(0, 0, 0, 0)   # fully transparent fill — outline only
	highlight_style.border_color = HIGHLIGHT_COLOR
	highlight_style.set_border_width_all(HIGHLIGHT_BORDER_WIDTH)
	highlight_style.set_corner_radius_all(HIGHLIGHT_CORNER_RADIUS)
	highlight_rect.add_theme_stylebox_override("panel", highlight_style)
	highlight_rect.visible = false
	add_child(highlight_rect)

	# Slow ambient pulse, left running continuously — when highlight_rect
	# is hidden the modulate change is simply invisible, so there's no
	# need to start/stop this alongside show/hide_overlay.
	highlight_pulse_tween = create_tween().set_loops()
	highlight_pulse_tween.tween_property(highlight_rect, "modulate:a", HIGHLIGHT_PULSE_MIN_ALPHA, HIGHLIGHT_PULSE_DURATION)
	highlight_pulse_tween.tween_property(highlight_rect, "modulate:a", HIGHLIGHT_PULSE_MAX_ALPHA, HIGHLIGHT_PULSE_DURATION)

	instruction_panel = PanelContainer.new()
	# Without this, the panel (a PanelContainer, which defaults to
	# blocking clicks) would physically intercept clicks on whatever
	# real game UI happens to be visually underneath it — confirmed as
	# the actual cause of a real bug where the "Head to Management to
	# continue" reminder sat on top of and blocked the real Farm button
	# in the build menu. MOUSE_FILTER_IGNORE here only affects this
	# panel's own background; next_btn below is a separate node with
	# its own default filter and remains fully clickable regardless.
	instruction_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(instruction_panel)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	# Same reasoning as instruction_panel above — each Control node
	# decides independently whether to block a click landing on it, so
	# the parent's IGNORE setting doesn't exempt this child on its own.
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	instruction_panel.add_child(vbox)

	instruction_label = Label.new()
	instruction_label.add_theme_font_size_override("font_size", 15)
	instruction_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	instruction_label.custom_minimum_size = Vector2(220, 0)
	# Same reasoning again — a Label is still its own Control with its
	# own hit-test area, regardless of having no interactive purpose.
	instruction_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(instruction_label)

	next_btn = Button.new()
	next_btn.text = "Next"
	next_btn.custom_minimum_size = Vector2(0, 28)
	next_btn.pressed.connect(_on_next_pressed)
	vbox.add_child(next_btn)

	action_btn = Button.new()
	action_btn.custom_minimum_size = Vector2(0, 28)
	action_btn.add_theme_color_override("font_color", Color(0.4, 0.9, 0.6))
	action_btn.visible = false
	vbox.add_child(action_btn)

# -------------------------------------------------------
# Public API
# -------------------------------------------------------

# Shows a step that's about a specific control. text appears in the
# instruction panel, positioned near target for reference; the panel
# always shows a Next button as a manual fallback. target is purely
# visual here now — clicking it does NOT auto-advance the step. The
# screen itself is responsible for calling
# TutorialRouter.advance_step(step_id) at its own real point of success.
func show_step_click(text: String, target: Control, allow_next: bool = true) -> void:
	current_target = target
	instruction_label.text = text
	next_btn.visible = allow_next
	blocking_enabled = true
	visible = true
	is_active = true
	_position_panel()

# Shows a step with no specific control to click — just an explanation
# and a Next button. Used for orientation steps (e.g. "this is the
# World Map") where there's nothing the player needs to do yet. target
# is optional; if given, the panel positions itself near it, otherwise
# the panel centers on screen.
func show_step_info(text: String, target: Control = null) -> void:
	current_target = target
	instruction_label.text = text
	next_btn.visible = true
	blocking_enabled = true
	visible = true
	is_active = true
	_position_panel()

# Shows a lightweight, purely informational reminder naming where the
# player needs to go next — used when the active tutorial step's
# screen differs from wherever the player currently is, so they're not
# left with literally nothing on screen until they happen to navigate
# there themselves. Deliberately has NO Next button — this is purely
# informational and self-resolving: it just disappears once the player
# actually reaches the right screen and that screen's own
# resolve_current_step() call takes over with the real step.
func show_navigation_reminder(text: String, target: Control = null, action_label: String = "", action_callback: Callable = Callable()) -> void:
	current_target = target
	instruction_label.text = text
	next_btn.visible = false
	# action_btn — shown when an explicit shortcut makes sense (e.g. "Go to
	# Management" after the recruit-screen dead-end), hidden for the first
	# nav reminder where the highlighted button in the HUD is self-evident.
	if action_label != "" and action_callback.is_valid():
		action_btn.text = action_label
		# Disconnect any previously connected callback so stale scene
		# references from a prior nav reminder don't linger.
		if action_btn.pressed.is_connected(_on_action_pressed):
			action_btn.pressed.disconnect(_on_action_pressed)
		_pending_action = action_callback
		action_btn.pressed.connect(_on_action_pressed)
		action_btn.visible = true
	else:
		action_btn.visible = false
	blocking_enabled = false
	dim_enabled = true
	visible = true
	is_active = true
	_position_panel()

# Used for steps where the player must freely interact with the game to
# complete them — the instruction panel still shows with a Next button,
# but nothing is dimmed or blocked. The panel sits at the top of the
# screen (centered, just below the dungeon's own HUD bar) so it doesn't
# obscure gameplay while still being readable.
func show_step_free(text: String) -> void:
	current_target = null
	instruction_label.text = text
	next_btn.visible = false   # no Next — steps using this mode advance via the game's own completion (e.g. dungeon Continue button)
	blocking_enabled = false
	dim_enabled = false
	visible = true
	is_active = true
	_position_panel()

func hide_overlay() -> void:
	visible = false
	is_active = false
	current_target = null
	blocking_enabled = false
	dim_enabled = true
	action_btn.visible = false
	if action_btn.pressed.is_connected(_on_action_pressed):
		action_btn.pressed.disconnect(_on_action_pressed)
	_pending_action = Callable()

# -------------------------------------------------------
# Internal
# -------------------------------------------------------

func _on_next_pressed() -> void:
	if not next_btn.visible: return   # the navigation reminder hides this button entirely; defensive guard in case that ever changes
	step_advanced.emit()

func _on_action_pressed() -> void:
	var cb = _pending_action
	hide_overlay()   # clears _pending_action first so hide_overlay's disconnect is safe
	if cb.is_valid():
		cb.call()

# Resolves target's actual on-screen rect, accounting for whatever
# Camera2D (if any) currently affects it. See the TARGET HIGHLIGHTING
# note near the top of this file for why this matters.
func _get_target_screen_rect(target: Control) -> Rect2:
	var xform = target.get_global_transform_with_canvas()
	return Rect2(xform.origin, target.size * xform.get_scale())

# Returns the padded cutout rect around target — used both to draw the
# gold border and to tell _apply_dim_bands() exactly which area to leave
# undimmed, so the highlighted target isn't itself sitting under the dim.
func _update_highlight(rect: Rect2) -> Rect2:
	var cutout = Rect2(rect.position - Vector2(HIGHLIGHT_PADDING, HIGHLIGHT_PADDING),
		rect.size + Vector2(HIGHLIGHT_PADDING, HIGHLIGHT_PADDING) * 2.0)
	highlight_rect.visible = true
	highlight_rect.position = cutout.position
	highlight_rect.size = cutout.size
	return cutout

# Arranges the 4 dim bands so together they cover the full screen
# except for `cutout`, which is left at normal brightness rather than
# dimmed-then-outlined. An empty/zero-size cutout (the no-target case)
# collapses this back down to one band covering the whole screen, with
# the other three at zero size — no separate "no target" branch needed.
# Also sets each band's mouse_filter from blocking_enabled — see the
# INPUT LOCKING note near the top of this file.
func _apply_dim_bands(screen_size: Vector2, cutout: Rect2) -> void:
	var filter = Control.MOUSE_FILTER_STOP if blocking_enabled else Control.MOUSE_FILTER_IGNORE
	var cx = clamp(cutout.position.x, 0.0, screen_size.x)
	var cy = clamp(cutout.position.y, 0.0, screen_size.y)
	var cw = clamp(cutout.size.x, 0.0, screen_size.x - cx)
	var ch = clamp(cutout.size.y, 0.0, screen_size.y - cy)

	dim_top.mouse_filter = filter
	dim_top.position = Vector2.ZERO
	dim_top.size = Vector2(screen_size.x, cy)

	dim_bottom.mouse_filter = filter
	dim_bottom.position = Vector2(0, cy + ch)
	dim_bottom.size = Vector2(screen_size.x, screen_size.y - dim_bottom.position.y)

	dim_left.mouse_filter = filter
	dim_left.position = Vector2(0, cy)
	dim_left.size = Vector2(cx, ch)

	dim_right.mouse_filter = filter
	dim_right.position = Vector2(cx + cw, cy)
	dim_right.size = Vector2(screen_size.x - dim_right.position.x, ch)

# Arranges the dim bands (full screen, minus a bright cutout around the
# target if one was given), the highlight, and the instruction panel
# near the target — falling back to a full dim + screen-centered panel
# if the target's position can't be read, is missing, or comes back
# degenerate. Tolerant of the target's reported position being somewhat
# off, since "near" only needs to be approximately right to still feel
# correct to the player.
# log_debug suppresses the print when called every frame from _process()
# for live camera tracking, so the console isn't flooded with a line
# per frame on top of the original per-event prints.
func _position_panel(log_debug: bool = true) -> void:
	var screen_size = Vector2(get_viewport().size)

	if not dim_enabled:
		# Free-play mode (e.g. dungeon) — hide all bands and position
		# the panel at the top-center of the screen below the HUD.
		for band in [dim_top, dim_bottom, dim_left, dim_right]:
			band.size = Vector2.ZERO
		highlight_rect.visible = false
		_position_free_panel(screen_size, log_debug)
		return

	if current_target == null or not is_instance_valid(current_target):
		_apply_dim_bands(screen_size, Rect2())
		_center_panel_on_screen(screen_size, log_debug)
		return

	var rect = _get_target_screen_rect(current_target)
	if rect.size.x <= 0 or rect.size.y <= 0:
		# Couldn't resolve a usable position for the target — center the
		# panel on screen rather than place it somewhere nonsensical.
		# Still names the target in instruction_label's own text, set by
		# whichever screen called show_step_click()/show_step_info(), so
		# the player isn't left without guidance even in this fallback.
		_apply_dim_bands(screen_size, Rect2())
		_center_panel_on_screen(screen_size, log_debug)
		return

	var cutout = _update_highlight(rect)
	_apply_dim_bands(screen_size, cutout)

	var panel_size = instruction_panel.size
	var below_y = rect.position.y + rect.size.y + PANEL_GAP
	var pos: Vector2
	if below_y + panel_size.y > screen_size.y:
		pos = Vector2(rect.position.x, rect.position.y - panel_size.y - PANEL_GAP)
	else:
		pos = Vector2(rect.position.x, below_y)
	pos.x = clamp(pos.x, 16, max(16, screen_size.x - panel_size.x - 16))
	pos.y = clamp(pos.y, 16, max(16, screen_size.y - panel_size.y - 16))
	instruction_panel.position = pos
	if log_debug:
		print("[TUTORIAL DEBUG] panel positioned at %s size=%s (target_rect=%s, target_id=%d) | filters: panel=%d next_btn=%d" % [instruction_panel.position, panel_size, rect, current_target.get_instance_id(), instruction_panel.mouse_filter, next_btn.mouse_filter])

func _center_panel_on_screen(screen_size: Vector2, log_debug: bool = true) -> void:
	highlight_rect.visible = false
	var panel_size = instruction_panel.size
	instruction_panel.position = (screen_size - panel_size) / 2.0
	if log_debug:
		print("[TUTORIAL DEBUG] panel centered at %s size=%s | filters: panel=%d next_btn=%d" % [instruction_panel.position, panel_size, instruction_panel.mouse_filter, next_btn.mouse_filter])

func _position_free_panel(screen_size: Vector2, log_debug: bool = true) -> void:
	# Panel size may not be accurate on the very first frame after text
	# is set — if it reads as zero, defer one frame and try again.
	var panel_size = instruction_panel.size
	if panel_size.x <= 0:
		call_deferred("_position_panel")
		return
	instruction_panel.position = Vector2(
		(screen_size.x - panel_size.x) / 2.0,
		56.0   # just below the dungeon's HP/kills HUD bar (panel at y=8, ~40px tall)
	)
	if log_debug:
		print("[TUTORIAL DEBUG] free panel at %s size=%s" % [instruction_panel.position, panel_size])
