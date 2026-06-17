extends Node2D
class_name UnitSprite

# -------------------------------------------------------
# Unit visual — draws either a real image (if one's been assigned for
# this unit type) or falls back to a simple procedural shape silhouette.
# This means you can swap in real art one unit type at a time without
# anything else in the game needing to change.
#
# HOW TO ADD REAL ART FOR A UNIT TYPE:
# 1. Drop a PNG into a folder in your project, e.g. res://art/units/knight.png
# 2. Add a line to TEXTURE_PATHS below mapping that UnitType to the path
# 3. Run the game — that unit now shows the image instead of the shape.
#    No other code anywhere needs to change.
#
# Usage: UnitSprite.new(); sprite.setup(unit_type, base_color, size);
#        add_child(sprite); sprite.position = wherever
# Call sprite.play_idle() each frame (or just leave it running) and
# sprite.play_attack() when the unit performs an attack.
# -------------------------------------------------------

enum UnitType { KNIGHT, ARCHER, MAGE, HEALER, ROGUE, HERO, ENEMY_BASIC, ENEMY_BOSS }

# Map a UnitType to an image path here to use real art instead of the
# procedural shape for that type. Leave a type out (or leave this empty)
# to keep using the placeholder shape for it. Paths must point to an
# actual file in your project (e.g. under res://art/units/).
const TEXTURE_PATHS = {
	# UnitType.KNIGHT: "res://art/units/knight.png",
	# UnitType.ARCHER: "res://art/units/archer.png",
	# UnitType.MAGE:   "res://art/units/mage.png",
}

var unit_type: int = UnitType.ENEMY_BASIC
var base_color: Color = Color.WHITE
var unit_size: float = 28.0

var _bob_t: float = 0.0
var _attack_t: float = 0.0
var _attacking: bool = false
var _facing: float = 1.0   # 1 = facing right, -1 = facing left

var _texture_sprite: Sprite2D = null   # created only if a real image is assigned

func setup(p_unit_type: int, p_color: Color, p_size: float = 28.0) -> void:
	unit_type = p_unit_type
	base_color = p_color
	unit_size = p_size
	_setup_texture_if_available()
	queue_redraw()

# Builds (or rebuilds) the real-image child sprite if this unit type has
# a texture assigned in TEXTURE_PATHS. If not, leaves _texture_sprite
# null so _draw() falls back to the procedural shape as before.
func _setup_texture_if_available() -> void:
	if _texture_sprite:
		_texture_sprite.queue_free()
		_texture_sprite = null

	if not TEXTURE_PATHS.has(unit_type):
		return

	var path = TEXTURE_PATHS[unit_type]
	if not ResourceLoader.exists(path):
		push_warning("UnitSprite: texture path not found, falling back to shape: " + path)
		return

	var tex = load(path)
	_texture_sprite = Sprite2D.new()
	_texture_sprite.texture = tex
	# Scale the image to roughly match unit_size, same anchor convention
	# the procedural shapes use (centered at unit_size/2, unit_size/2).
	var tex_size = tex.get_size()
	if tex_size.x > 0:
		var scale_factor = unit_size / max(tex_size.x, tex_size.y)
		_texture_sprite.scale = Vector2(scale_factor, scale_factor)
	_texture_sprite.position = Vector2(unit_size / 2, unit_size / 2)
	add_child(_texture_sprite)

func set_color(p_color: Color) -> void:
	base_color = p_color
	if _texture_sprite:
		_texture_sprite.modulate = p_color
	queue_redraw()

func _process(delta: float) -> void:
	_bob_t += delta * 4.0
	if _attacking:
		_attack_t += delta * 10.0
		if _attack_t >= 1.0:
			_attacking = false
			_attack_t = 0.0

	if _texture_sprite:
		_update_texture_animation()
	else:
		queue_redraw()

# Applies the same bob/lunge/facing animation to the real-image sprite
# that the procedural shapes already use, so swapping in art doesn't
# lose the existing animation feel.
func _update_texture_animation() -> void:
	var bob_offset = sin(_bob_t) * (unit_size * 0.06)
	var lunge_offset = 0.0
	if _attacking:
		lunge_offset = sin(_attack_t * PI) * unit_size * 0.35 * _facing

	_texture_sprite.position = Vector2(unit_size / 2, unit_size / 2) + Vector2(lunge_offset, bob_offset)
	_texture_sprite.flip_h = _facing < 0

func play_attack() -> void:
	_attacking = true
	_attack_t = 0.0

func face(direction: Vector2) -> void:
	if abs(direction.x) > 0.1:
		_facing = sign(direction.x)

func _draw() -> void:
	if _texture_sprite:
		return   # real image is handling visuals via _update_texture_animation

	var bob_offset = sin(_bob_t) * (unit_size * 0.06)
	var lunge_offset = 0.0
	if _attacking:
		# Quick forward lunge then return, like a simple attack swing
		lunge_offset = sin(_attack_t * PI) * unit_size * 0.35 * _facing

	var s = unit_size
	# Anchor like a top-left-positioned ColorRect of size (s, s), so existing
	# call sites that do `position = pos - Vector2(sz/2, sz/2)` keep working
	# unchanged when swapped from ColorRect to UnitSprite.
	var anchor_center = Vector2(s/2, s/2)
	var center = anchor_center + Vector2(lunge_offset, bob_offset)
	var dark = base_color.darkened(0.35)
	var light = base_color.lightened(0.25)

	match unit_type:
		UnitType.KNIGHT:
			_draw_knight(center, s, dark, light)
		UnitType.ARCHER:
			_draw_archer(center, s, dark, light)
		UnitType.MAGE:
			_draw_mage(center, s, dark, light)
		UnitType.HEALER:
			_draw_healer(center, s, dark, light)
		UnitType.ROGUE:
			_draw_rogue(center, s, dark, light)
		UnitType.HERO:
			_draw_hero(center, s, dark, light)
		UnitType.ENEMY_BOSS:
			_draw_enemy_boss(center, s, dark, light)
		_:
			_draw_enemy_basic(center, s, dark, light)

# Knight — square body, small helmet bump, shield-like rectangle to one side
func _draw_knight(c: Vector2, s: float, dark: Color, light: Color) -> void:
	draw_rect(Rect2(c - Vector2(s*0.4, s*0.4), Vector2(s*0.8, s*0.8)), base_color)
	draw_rect(Rect2(c - Vector2(s*0.4, s*0.4), Vector2(s*0.8, s*0.8)), dark, false, 2.0)
	draw_circle(c - Vector2(0, s*0.45), s*0.22, light)   # helmet
	draw_rect(Rect2(c + Vector2(s*0.25*_facing, -s*0.15), Vector2(s*0.18, s*0.5)), dark)   # shield/sword arm

# Archer — slim body, pointed shoulders, bow arc to the side
func _draw_archer(c: Vector2, s: float, dark: Color, light: Color) -> void:
	var pts = PackedVector2Array([
		c + Vector2(0, -s*0.5), c + Vector2(s*0.3, s*0.4), c + Vector2(-s*0.3, s*0.4)
	])
	draw_colored_polygon(pts, base_color)
	draw_circle(c - Vector2(0, s*0.55), s*0.18, light)   # head
	draw_arc(c + Vector2(s*0.3*_facing, 0), s*0.4, -PI*0.4, PI*0.4, 8, dark, 2.0)   # bow

# Mage — robe triangle, pointed hat, small glowing orb
func _draw_mage(c: Vector2, s: float, dark: Color, light: Color) -> void:
	var pts = PackedVector2Array([
		c + Vector2(0, -s*0.3), c + Vector2(s*0.38, s*0.45), c + Vector2(-s*0.38, s*0.45)
	])
	draw_colored_polygon(pts, base_color)
	var hat = PackedVector2Array([
		c + Vector2(0, -s*0.75), c + Vector2(s*0.22, -s*0.2), c + Vector2(-s*0.22, -s*0.2)
	])
	draw_colored_polygon(hat, dark)
	draw_circle(c + Vector2(s*0.35*_facing, s*0.05), s*0.12, light)   # orb

# Healer — robe similar to mage but rounder, with a small cross/plus mark
func _draw_healer(c: Vector2, s: float, dark: Color, light: Color) -> void:
	draw_circle(c + Vector2(0, s*0.1), s*0.42, base_color)
	draw_circle(c - Vector2(0, s*0.4), s*0.2, light)   # head
	draw_rect(Rect2(c - Vector2(s*0.06, s*0.18), Vector2(s*0.12, s*0.36)), dark)   # plus vertical
	draw_rect(Rect2(c - Vector2(s*0.18, s*0.06), Vector2(s*0.36, s*0.12)), dark)   # plus horizontal

# Rogue — small angular body leaning forward, dagger glint
func _draw_rogue(c: Vector2, s: float, dark: Color, light: Color) -> void:
	var pts = PackedVector2Array([
		c + Vector2(s*0.3*_facing, -s*0.35), c + Vector2(s*0.35, s*0.4), c + Vector2(-s*0.35, s*0.4)
	])
	draw_colored_polygon(pts, base_color)
	draw_circle(c + Vector2(s*0.05*_facing, -s*0.45), s*0.16, light)
	draw_line(c + Vector2(s*0.25*_facing, -s*0.1), c + Vector2(s*0.45*_facing, s*0.1), dark, 3.0)

# Hero — knight-like but with a small cape flourish and brighter accent
func _draw_hero(c: Vector2, s: float, dark: Color, light: Color) -> void:
	draw_rect(Rect2(c - Vector2(s*0.42, s*0.42), Vector2(s*0.84, s*0.84)), base_color)
	draw_circle(c - Vector2(0, s*0.48), s*0.24, light)
	var cape = PackedVector2Array([
		c + Vector2(-s*0.4, -s*0.1), c + Vector2(-s*0.55, s*0.5), c + Vector2(-s*0.2, s*0.4)
	])
	draw_colored_polygon(cape, dark)
	draw_circle(c - Vector2(0, s*0.48), s*0.08, Color(1, 0.85, 0.2))   # gold accent

# Basic enemy — jagged irregular blob, feels feral/wild
func _draw_enemy_basic(c: Vector2, s: float, dark: Color, light: Color) -> void:
	var pts = PackedVector2Array([
		c + Vector2(0, -s*0.45), c + Vector2(s*0.4, -s*0.1), c + Vector2(s*0.3, s*0.4),
		c + Vector2(-s*0.3, s*0.4), c + Vector2(-s*0.4, -s*0.1),
	])
	draw_colored_polygon(pts, base_color)
	draw_circle(c + Vector2(s*0.15, -s*0.1), s*0.08, Color(1, 0.2, 0.2))   # eye
	draw_circle(c + Vector2(-s*0.15, -s*0.1), s*0.08, Color(1, 0.2, 0.2))   # eye

# Boss enemy — larger spiky silhouette with glowing eyes
func _draw_enemy_boss(c: Vector2, s: float, dark: Color, light: Color) -> void:
	var pts = PackedVector2Array([
		c + Vector2(0, -s*0.5), c + Vector2(s*0.25, -s*0.35), c + Vector2(s*0.45, 0),
		c + Vector2(s*0.35, s*0.45), c + Vector2(-s*0.35, s*0.45), c + Vector2(-s*0.45, 0),
		c + Vector2(-s*0.25, -s*0.35),
	])
	draw_colored_polygon(pts, base_color)
	draw_colored_polygon(pts, Color.TRANSPARENT)
	draw_polyline(pts + PackedVector2Array([pts[0]]), dark, 3.0)
	draw_circle(c + Vector2(s*0.18, -s*0.15), s*0.1, Color(1, 0.9, 0.2))
	draw_circle(c + Vector2(-s*0.18, -s*0.15), s*0.1, Color(1, 0.9, 0.2))
