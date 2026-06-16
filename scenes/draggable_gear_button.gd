extends Button
class_name DraggableGearButton

# A gear inventory button that can be dragged onto a slot to equip it.
# Click-to-select (handled by management_screen.gd via the pressed signal)
# still works exactly as before — this only adds drag-and-drop on top.

var gear_item: GearItem = null

func _get_drag_data(_at_position: Vector2) -> Variant:
	if gear_item == null:
		return null

	# Simple preview that follows the cursor while dragging
	var preview = Label.new()
	preview.text = "📦 " + gear_item.item_name
	preview.add_theme_color_override("font_color", gear_item.get_display_color())
	var preview_bg = PanelContainer.new()
	preview_bg.add_child(preview)
	set_drag_preview(preview_bg)

	return {"type": "gear", "gear": gear_item, "source_button": self}
