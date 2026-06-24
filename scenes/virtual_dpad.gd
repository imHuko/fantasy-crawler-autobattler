class_name VirtualDpad
extends CanvasLayer

# On-screen directional pad for mobile / touchscreen play.
# Add as a child of a dungeon scene and poll get_direction() each frame.

const BTN_SZ  = 84.0
const BTN_GAP = 6.0
const MARGIN  = 28.0

var _held: Dictionary = {"up": false, "down": false, "left": false, "right": false}

func _ready() -> void:
	layer = 15
	_build()

func _build() -> void:
	var vp   = get_viewport().get_visible_rect().size
	var step = BTN_SZ + BTN_GAP
	# D-pad cluster centre, bottom-left corner
	var cx   = MARGIN + step + BTN_SZ * 0.5
	var cy   = vp.y - MARGIN - step - BTN_SZ * 0.5

	_make_btn("↑", Vector2(cx,        cy - step), "up")
	_make_btn("↓", Vector2(cx,        cy + step), "down")
	_make_btn("←", Vector2(cx - step, cy),        "left")
	_make_btn("→", Vector2(cx + step, cy),        "right")

	# Centre pip — visual only, shows dpad anchor point
	var pip = ColorRect.new()
	pip.size     = Vector2(22, 22)
	pip.position = Vector2(cx - 11, cy - 11)
	pip.color    = Color(0.30, 0.32, 0.50, 0.45)
	add_child(pip)

func _make_btn(symbol: String, centre: Vector2, key: String) -> void:
	var normal = StyleBoxFlat.new()
	normal.bg_color     = Color(0.13, 0.15, 0.26, 0.68)
	normal.border_color = Color(0.44, 0.50, 0.78, 0.75)
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(int(BTN_SZ * 0.5))

	var hover = normal.duplicate()
	hover.bg_color = Color(0.20, 0.23, 0.38, 0.80)

	var pressed = normal.duplicate()
	pressed.bg_color     = Color(0.34, 0.40, 0.72, 0.92)
	pressed.border_color = Color(0.60, 0.68, 1.00, 1.00)

	var btn = Button.new()
	btn.text     = symbol
	btn.size     = Vector2(BTN_SZ, BTN_SZ)
	btn.position = centre - Vector2(BTN_SZ * 0.5, BTN_SZ * 0.5)
	btn.add_theme_font_size_override("font_size", 34)
	btn.add_theme_color_override("font_color", Color(0.92, 0.92, 1.00, 0.90))
	btn.add_theme_stylebox_override("normal",  normal)
	btn.add_theme_stylebox_override("hover",   hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_stylebox_override("focus",   StyleBoxEmpty.new())

	btn.button_down.connect(func(): _held[key] = true)
	btn.button_up.connect(func():   _held[key] = false)

	add_child(btn)

func get_direction() -> Vector2:
	var d = Vector2.ZERO
	if _held["up"]:    d.y -= 1
	if _held["down"]:  d.y += 1
	if _held["left"]:  d.x -= 1
	if _held["right"]: d.x += 1
	return d.normalized() if d.length() > 0 else Vector2.ZERO
