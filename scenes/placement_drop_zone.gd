extends Control
class_name PlacementDropZone

# An invisible Control covering the valid troop-placement area of the
# defense battlefield. Exists purely to host Godot's drag-and-drop
# callbacks (_can_drop_data/_drop_data), since those only exist on
# Control — field_node itself is a Node2D and can't receive them
# directly. Converts the drop's local position into field_node-relative
# coordinates before handing off, so the receiving callback can use the
# exact same coordinate space the existing click-to-place path already
# expects.

var field_node_ref: Node2D = null
var on_drop_callback: Callable

func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return typeof(data) == TYPE_DICTIONARY and data.get("type") == "roster_troop"

func _drop_data(at_position: Vector2, data: Variant) -> void:
	if not on_drop_callback.is_valid() or field_node_ref == null:
		return
	# at_position is local to this Control; convert to field_node-relative
	# coordinates (this Control's global position minus field_node's
	# global position, plus the local drop point) so the callback gets
	# exactly what _place_troop() already expects.
	var field_relative_pos = (global_position - field_node_ref.global_position) + at_position
	on_drop_callback.call(data["roster_idx"], field_relative_pos)
