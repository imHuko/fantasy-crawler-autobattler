extends Button
class_name DraggableRosterButton

# A defense-battle roster button that can be dragged onto the
# battlefield to place that troop, mirroring the same drag pattern
# already used for gear equipping (see draggable_gear_button.gd).
# Click-to-select (handled by defense_scene.gd via the pressed signal,
# followed by a battlefield click) still works exactly as before —
# this only adds drag-and-drop as a faster alternative.

var roster_idx: int = -1
var troop_name: String = ""
var display_color: Color = Color.WHITE

func _get_drag_data(_at_position: Vector2) -> Variant:
	if roster_idx < 0:
		return null

	# Simple preview that follows the cursor while dragging
	var preview = Label.new()
	preview.text = "🛡 " + troop_name
	preview.add_theme_color_override("font_color", display_color)
	var preview_bg = PanelContainer.new()
	preview_bg.add_child(preview)
	set_drag_preview(preview_bg)

	return {"type": "roster_troop", "roster_idx": roster_idx}
