extends Button
class_name DroppableSlotButton

# A troop gear-slot button that accepts a dragged gear item from the
# inventory list. Click-to-select (handled by management_screen.gd via
# the pressed signal) still works exactly as before — this only adds
# drag-and-drop as an alternative way to equip.

var troop_ref: TroopData = null
var slot_key_ref: String = ""

# Callback set by management_screen.gd so this button can trigger the
# same equip logic used by the click flow, without this script needing
# to know about the rest of the management screen.
var on_drop_callback: Callable

func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if typeof(data) != TYPE_DICTIONARY or data.get("type") != "gear":
		return false
	var gear: GearItem = data["gear"]
	if gear.get_slot_name() != slot_key_ref:
		return false
	# Visual feedback — brighten while a valid drag hovers over this slot
	modulate = Color(1.3, 1.3, 1.0)
	return true

func _drop_data(_at_position: Vector2, data: Variant) -> void:
	modulate = Color(1, 1, 1)
	if on_drop_callback.is_valid():
		on_drop_callback.call(data["gear"], troop_ref, slot_key_ref, self)

func _notification(what: int) -> void:
	# Reset the highlight if a drag leaves without dropping
	if what == NOTIFICATION_DRAG_END:
		modulate = Color(1, 1, 1)
