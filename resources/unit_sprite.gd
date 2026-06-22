extends Node2D
class_name UnitSprite

# -------------------------------------------------------
# Unit visual — plays real animated sprite art (if frames have been
# assigned for this unit type) or falls back to a simple procedural
# shape silhouette. This means you can swap in real art one unit type
# at a time without anything else in the game needing to change.
#
# HOW TO ADD REAL ART FOR A UNIT TYPE:
# 1. Drop frame PNGs into SPRITE_FOLDER below, named:
#      <key>_walk1.png ... <key>_walk5.png   (walk1 = idle/standing pose)
#      <key>_attack1.png, <key>_attack2.png
#    e.g. res://art/sprites/knight_walk1.png
# 2. Uncomment that UnitType's line in SPRITE_KEYS below.
# 3. Run the game — that unit now plays real animated art instead of
#    the procedural shape. No other code anywhere needs to change.
#    Frame 1 of the walk set is used as the idle/standing pose; frames
#    2-5 play as a looping walk cycle. Either set can be partially
#    missing (e.g. only an idle frame, no walk/attack yet) and whatever
#    IS present will still be used — only the idle frame is required.
#
# Usage: UnitSprite.new(); sprite.setup(unit_type, base_color, size);
#        add_child(sprite); sprite.position = wherever
# Call sprite.set_moving(true/false) each frame to switch idle/walk,
# and sprite.play_attack() when the unit performs an attack.
# -------------------------------------------------------

enum UnitType {
	KNIGHT, ARCHER, MAGE, HEALER, ROGUE, HERO, ENEMY_BASIC, ENEMY_BOSS,
	TREANT, FAERIE, BULL, SPORE_BOMBER, ANCIENT_TOTEM,
}

# Folder where animation frame PNGs live — change this one line if you
# move the art folder later; nothing else needs to change.
const SPRITE_FOLDER = "res://art/sprites/"

# Maps a UnitType to an "art key" — the filename prefix used to find
# this unit's frames, e.g. "knight" -> res://art/sprites/knight_walk1.png.
# Leave a type commented out (or out entirely) to keep using the
# procedural shape for it. Uncomment one line at a time as you import
# each unit's art — everything else keeps working unchanged either way.
const SPRITE_KEYS = {
	UnitType.KNIGHT:       "knight",
	UnitType.ARCHER:       "archer",
	UnitType.MAGE:         "mage",
	UnitType.HEALER:       "healer",
	UnitType.ROGUE:        "rogue",
	UnitType.TREANT:       "treant",
	UnitType.FAERIE:       "faerie",
	UnitType.BULL:         "bull",
	UnitType.SPORE_BOMBER: "spore_bomber",
	UnitType.ANCIENT_TOTEM:"ancient_totem",
}

var unit_type: int = UnitType.ENEMY_BASIC
var base_color: Color = Color.WHITE
var unit_size: float = 28.0

var _bob_t: float = 0.0
var _attack_t: float = 0.0
var _attacking: bool = false
var _facing: float = 1.0   # 1 = facing right, -1 = facing left
var _is_moving: bool = false   # set via set_moving() — picks idle vs walk animation

var _anim_sprite: AnimatedSprite2D = null   # created only if real art frames are found
var _has_walk_anim: bool = false
var _has_attack_anim: bool = false

func setup(p_unit_type: int, p_color: Color, p_size: float = 28.0) -> void:
	unit_type = p_unit_type
	base_color = p_color
	unit_size = p_size
	_setup_sprite_if_available()
	queue_redraw()

# Builds a SpriteFrames resource from <key>_walk1.png (idle), <key>_walk2-5.png
# (walk loop), and <key>_attack1-2.png (attack, played once) — whichever of
# those files actually exist. Returns null if even the idle frame is missing,
# which tells the caller to fall back to the procedural shape entirely.
# Minimum file size (bytes) for a frame PNG to be considered real art.
# Placeholder/stub frames (tiny icons in a large transparent canvas) are
# typically < 8 KB; genuine animation frames start at ~40 KB. Using 10 KB
# as the cutoff cleanly separates the two without touching any files.
const MIN_FRAME_FILE_BYTES = 10_000

func _png_file_size(path: String) -> int:
	var f = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return 0
	var sz = f.get_length()
	f.close()
	return sz

func _build_sprite_frames(key: String) -> SpriteFrames:
	var idle_path = SPRITE_FOLDER + key + "_walk1.png"
	if not ResourceLoader.exists(idle_path):
		return null

	var frames = SpriteFrames.new()
	frames.add_animation("idle")
	frames.set_animation_loop("idle", true)
	frames.add_frame("idle", load(idle_path))

	_has_walk_anim = false
	frames.add_animation("walk")
	frames.set_animation_loop("walk", true)
	frames.set_animation_speed("walk", 8.0)
	for i in range(2, 6):   # walk2..walk5 — walk1 is reserved for idle above
		var p = SPRITE_FOLDER + key + "_walk%d.png" % i
		if ResourceLoader.exists(p) and _png_file_size(p) >= MIN_FRAME_FILE_BYTES:
			frames.add_frame("walk", load(p))
			_has_walk_anim = true
	if not _has_walk_anim:
		frames.remove_animation("walk")   # nothing to play — set_moving(true) will just stay on idle

	_has_attack_anim = false
	frames.add_animation("attack")
	frames.set_animation_loop("attack", false)
	frames.set_animation_speed("attack", 8.0)
	for i in range(1, 3):   # attack1, attack2
		var p = SPRITE_FOLDER + key + "_attack%d.png" % i
		if ResourceLoader.exists(p) and _png_file_size(p) >= MIN_FRAME_FILE_BYTES:
			frames.add_frame("attack", load(p))
			_has_attack_anim = true
	if not _has_attack_anim:
		frames.remove_animation("attack")   # play_attack() will just no-op visually, lunge still happens

	return frames

# Builds (or rebuilds) the real-art AnimatedSprite2D child if this unit
# type has an entry in SPRITE_KEYS AND its idle frame file actually
# exists. If not, leaves _anim_sprite null so _draw() falls back to the
# procedural shape, exactly as before.
func _setup_sprite_if_available() -> void:
	if _anim_sprite:
		_anim_sprite.queue_free()
		_anim_sprite = null

	if not SPRITE_KEYS.has(unit_type):
		return

	var key = SPRITE_KEYS[unit_type]
	var frames = _build_sprite_frames(key)
	if frames == null:
		push_warning("UnitSprite: no idle frame found for key '%s' (expected %s%s_walk1.png), falling back to shape" % [key, SPRITE_FOLDER, key])
		return

	_anim_sprite = AnimatedSprite2D.new()
	_anim_sprite.sprite_frames = frames
	_anim_sprite.animation_finished.connect(_on_sprite_animation_finished)
	# Same centered-on-box-middle anchor convention the procedural shapes
	# use (anchor_center = s/2,s/2 in _draw()) — keeps real art positioned
	# consistently with the shape fallback and with how callers already
	# place this node (`position = pos - Vector2(sz/2, sz/2)`).
	_anim_sprite.centered = true
	_anim_sprite.modulate = Color.WHITE

	# Scale from the idle frame's actual height, not a hardcoded number —
	# if you ever re-export the art at a different resolution, this still
	# comes out the right on-screen size with zero code changes.
	var idle_tex = frames.get_frame_texture("idle", 0)
	if idle_tex and idle_tex.get_height() > 0:
		var scale_factor = unit_size / idle_tex.get_height()
		_anim_sprite.scale = Vector2(scale_factor, scale_factor)

	add_child(_anim_sprite)
	_anim_sprite.play("idle")

func set_color(p_color: Color) -> void:
	base_color = p_color
	if _anim_sprite:
		_anim_sprite.modulate = p_color
	queue_redraw()

func _process(delta: float) -> void:
	_bob_t += delta * 4.0
	if _attacking:
		_attack_t += delta * 10.0
		if _attack_t >= 1.0:
			_attacking = false
			_attack_t = 0.0

	if _anim_sprite:
		_update_sprite_animation()
	else:
		queue_redraw()

# Applies the same bob/lunge/facing motion to the real animated sprite
# that the procedural shapes already use, so swapping in art doesn't
# lose the existing animation feel — the walk/attack frame art handles
# the actual pose, this just adds a little physical punch on top.
func _update_sprite_animation() -> void:
	var bob_offset = sin(_bob_t) * (unit_size * 0.06)
	var lunge_offset = 0.0
	if _attacking:
		lunge_offset = sin(_attack_t * PI) * unit_size * 0.35 * _facing

	_anim_sprite.position = Vector2(unit_size / 2, unit_size / 2) + Vector2(lunge_offset, bob_offset)
	_anim_sprite.flip_h = _facing < 0

# Called when "attack" finishes playing — returns to walk or idle
# depending on whatever set_moving() last reported.
func _on_sprite_animation_finished() -> void:
	if _anim_sprite.animation == "attack":
		_anim_sprite.play("walk" if (_is_moving and _has_walk_anim) else "idle")

# Call each frame (or whenever movement state changes) to switch between
# the idle and walk animations. Safe to call even before real art is
# assigned for this unit — it's just a no-op against the shape fallback.
func set_moving(moving: bool) -> void:
	_is_moving = moving
	if _anim_sprite and not _attacking:
		var target = "walk" if (moving and _has_walk_anim) else "idle"
		if _anim_sprite.animation != target:
			_anim_sprite.play(target)

func play_attack() -> void:
	_attacking = true
	_attack_t = 0.0
	if _anim_sprite and _has_attack_anim:
		_anim_sprite.play("attack")

func face(direction: Vector2) -> void:
	if abs(direction.x) > 0.1:
		_facing = sign(direction.x)

func _draw() -> void:
	if _anim_sprite:
		return   # real animated art is handling visuals via _update_sprite_animation

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
