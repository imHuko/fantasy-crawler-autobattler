extends Node

# -------------------------------------------------------
# TutorialRouter — drives the forced walkthrough. Owns the live
# "where are we in the sequence" state, decides whether the player's
# current screen matches what the active step needs (navigating them
# there if not), and listens for TutorialOverlay's step_advanced
# signal to move to the next step.
#
# This is intentionally the ONLY place that advances
# PlayerInventory.tutorial_step_index — screens never touch that
# directly, they just call resolve_current_step() when they're ready
# (typically from _ready()) and provide their own target Controls via
# a screen-specific lookup the router calls into.
#
# Register this as an autoload named "TutorialRouter" in Project >
# Project Settings > Autoload, so it persists across scene changes
# and can react to scene transitions the player makes on their own.
# -------------------------------------------------------

func _ready() -> void:
	TutorialOverlay.step_advanced.connect(_advance)

# Call this from a screen's _ready() once its UI is built. The router
# checks whether the active step belongs on this screen; if so, it
# resolves the step's target (via the screen's own
# get_tutorial_target(id) method, if it has one) and shows it. If the
# active step belongs on a DIFFERENT screen, this does nothing — the
# screen the player is actually supposed to be on is responsible for
# calling this itself once it loads.
func resolve_current_step(current_screen: Node) -> void:
	if not PlayerInventory.tutorial_active:
		return

	var step = TutorialSteps.get_step(PlayerInventory.tutorial_step_index)
	print("[TUTORIAL DEBUG] resolve_current_step() called from %s — current step is '%s' (index=%d)" % [current_screen.scene_file_path, step.get("id", "<empty>"), PlayerInventory.tutorial_step_index])
	if step.is_empty():
		# Walked off the end of the list — tutorial's actually done.
		print("[TUTORIAL DEBUG] resolve_current_step: step list exhausted -> finishing tutorial")
		_finish_tutorial()
		return

	var current_path = current_screen.scene_file_path
	if step["screen"] != current_path:
		# Screen mismatch — show the navigation reminder so the player
		# always has guidance, even after a save/load that lands them on
		# the wrong screen. This mirrors what _advance() does when a step
		# change requires a scene switch, so the reminder is never lost.
		print("[TUTORIAL DEBUG] resolve_current_step: screen mismatch (step wants %s, currently %s) -> showing nav reminder" % [step["screen"], current_path])
		var destination = TutorialSteps.get_screen_display_name(step["screen"])
		var nav_target: Control = null
		var nav_id = step.get("nav_target_id", "")
		if nav_id != "" and current_screen.has_method("get_tutorial_target"):
			nav_target = current_screen.get_tutorial_target(nav_id)
		var action_label = step.get("nav_action_label", "")
		var action_scene_path = step.get("nav_action_scene", "")
		var action_cb: Callable = Callable()
		if action_label != "" and action_scene_path != "":
			action_cb = func(): get_tree().change_scene_to_file(action_scene_path)
		TutorialOverlay.show_navigation_reminder("Head to %s to continue." % destination, nav_target, action_label, action_cb)
		return

	var target: Control = null
	if step["target_id"] != "" and current_screen.has_method("get_tutorial_target"):
		target = current_screen.get_tutorial_target(step["target_id"])

	print("[TUTORIAL DEBUG] resolve_current_step: mode=%s target_id='%s' target=%s" % [step["mode"], step["target_id"], target])

	if step["mode"] == "click":
		if target == null:
			push_warning("Tutorial step '%s' wants target '%s' but the screen didn't provide it." % [step["id"], step["target_id"]])
			print("[TUTORIAL DEBUG] resolve_current_step: click-mode step has NULL target, showing nothing")
			return
		TutorialOverlay.show_step_click(step["text"], target, not step.get("require_action", false))
	elif step.get("nodim", false):
		TutorialOverlay.show_step_free(step["text"])
	else:
		TutorialOverlay.show_step_info(step["text"], target)

# Call this directly from a screen's own code, at the exact point a
# real action actually succeeds (e.g. right after a building is
# granted, an item is equipped, gold is spent on a recruit) — this is
# the ONLY way a click-mode step should advance now. expected_step_id
# is a safety check: if the tutorial isn't currently on that exact
# step, this does nothing, so a call left over from a previous step
# (or one that fires for an unrelated reason) can't accidentally skip
# the wrong step. Screens should still keep the Next button as the
# fallback — this is purely an additional, more immediate way to
# advance when the real action is unambiguous.
func advance_step(expected_step_id: String) -> void:
	if not PlayerInventory.tutorial_active:
		return
	var current_step = TutorialSteps.get_step(PlayerInventory.tutorial_step_index)
	print("[TUTORIAL DEBUG] advance_step called with expected='%s', current actual step is '%s' (index=%d)" % [expected_step_id, current_step.get("id", "<empty>"), PlayerInventory.tutorial_step_index])
	if current_step.get("id", "") != expected_step_id:
		# Not currently on the step this call expected — either it
		# already advanced (e.g. via Next) or this call fired from a
		# stale state. Either way, do nothing rather than risk skipping
		# whatever step is actually current.
		print("[TUTORIAL DEBUG] advance_step REJECTED (mismatch)")
		return
	print("[TUTORIAL DEBUG] advance_step ACCEPTED, advancing now")
	_advance()

func _advance() -> void:
	var prev_step = TutorialSteps.get_step(PlayerInventory.tutorial_step_index)
	print("[TUTORIAL DEBUG] _advance() called — leaving step '%s' (index=%d)" % [prev_step.get("id", "<empty>"), PlayerInventory.tutorial_step_index])
	PlayerInventory.tutorial_step_index += 1
	SaveManager.save_game()
	TutorialOverlay.hide_overlay()

	var next_step = TutorialSteps.get_step(PlayerInventory.tutorial_step_index)
	print("[TUTORIAL DEBUG] now on step '%s' (index=%d)" % [next_step.get("id", "<empty>"), PlayerInventory.tutorial_step_index])
	if next_step.is_empty():
		print("[TUTORIAL DEBUG] step list exhausted -> finishing tutorial")
		_finish_tutorial()
		return

	# If the next step is on the same screen we're already looking at,
	# show it immediately rather than waiting for a future _ready()
	# call that may never come (e.g. two consecutive steps on the World
	# Map shouldn't require a scene reload between them).
	var current_scene = get_tree().current_scene
	if current_scene and current_scene.scene_file_path == next_step["screen"]:
		print("[TUTORIAL DEBUG] same screen (%s) -> resolving immediately" % current_scene.scene_file_path)
		resolve_current_step(current_scene)
	else:
		print("[TUTORIAL DEBUG] showing nav reminder: current_scene=%s next_step_screen=%s" % [current_scene.scene_file_path if current_scene else "<none>", next_step["screen"]])
		# The player needs to navigate to a different screen before the
		# next step can show anything real — without this, they'd be
		# left looking at nothing at all until they happened to find
		# their own way there, which can look like the tutorial just
		# stopped. This reminder is purely informational (see
		# TutorialOverlay.show_navigation_reminder) and disappears on
		# its own the moment the destination screen's own
		# resolve_current_step() call takes over.
		var destination = TutorialSteps.get_screen_display_name(next_step["screen"])
		var nav_target: Control = null
		var nav_id = next_step.get("nav_target_id", "")
		if nav_id != "" and current_scene and current_scene.has_method("get_tutorial_target"):
			nav_target = current_scene.get_tutorial_target(nav_id)
		var action_label = next_step.get("nav_action_label", "")
		var action_scene = next_step.get("nav_action_scene", "")
		var action_cb: Callable = Callable()
		if action_label != "" and action_scene != "":
			action_cb = func(): get_tree().change_scene_to_file(action_scene)
		TutorialOverlay.show_navigation_reminder("Head to %s to continue." % destination, nav_target, action_label, action_cb)

func _finish_tutorial() -> void:
	PlayerInventory.tutorial_active = false
	PlayerInventory.tutorial_complete = true
	TutorialOverlay.hide_overlay()
	SaveManager.save_game()

# Called once, from new_game_screen.gd, right after a fresh game is
# created with the tutorial checkbox checked.
func start_tutorial() -> void:
	PlayerInventory.tutorial_active = true
	PlayerInventory.tutorial_step_index = 0
	PlayerInventory.tutorial_complete = false

# Called if the player unchecks the tutorial checkbox at game start —
# skips the whole walkthrough outright, same end state as finishing it.
func skip_tutorial() -> void:
	PlayerInventory.tutorial_active = false
	PlayerInventory.tutorial_complete = true
	TutorialOverlay.hide_overlay()
