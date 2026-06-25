extends Node2D
class_name UnitSprite

# -------------------------------------------------------
# Unit visual — plays real animated sprite art (if frames have been
# assigned for this unit type) or falls back to a simple procedural
# shape silhouette. This means you can swap in real art one unit type
# at a time without anything else in the game needing to change.
#
# HOW TO ADD REAL ART FOR A UNIT TYPE:
# 1. Drop frame PNGs into a folder, named:
#      idle.png
#      walk_01.png ... walk_04.png
#      attack_01.png, attack_02.png
# 2. Point that UnitType at the folder in SPRITE_FOLDERS below.
# 3. Run the game — that unit now plays real animated art instead of
#    the procedural shape. No other code anywhere needs to change.
#    idle.png is used as the standing pose; walk frames loop while moving.
#    Either set can be partially missing (e.g. only an idle frame, no
#    walk/attack yet) and whatever IS present will still be used — only
#    the idle frame is required.
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

# Folder roots where animation frame PNGs live.
const GENERATED_TROOP_FRAME_FOLDER = "res://assets/sprites/generated_troops_fixed96/frames/"
const LEGACY_FRAME_FOLDER = "res://art/sprites/"
const DEBUG_SPRITE_LOAD := false

# Maps a UnitType to the folder containing idle/walk/attack frame PNGs.
# Leave a type out entirely to keep using the procedural shape.
const SPRITE_FOLDERS = {
	UnitType.KNIGHT: GENERATED_TROOP_FRAME_FOLDER + "knight/",
	UnitType.ARCHER: GENERATED_TROOP_FRAME_FOLDER + "archer/",
	UnitType.MAGE:   GENERATED_TROOP_FRAME_FOLDER + "mage/",
	UnitType.HEALER: GENERATED_TROOP_FRAME_FOLDER + "healer/",
	UnitType.ROGUE:  GENERATED_TROOP_FRAME_FOLDER + "rogue/",
}

const LEGACY_SPRITE_KEYS = {
	UnitType.TREANT:        "treant",
	UnitType.FAERIE:        "faerie",
	UnitType.BULL:          "bull",
	UnitType.SPORE_BOMBER:  "spore_bomber",
	UnitType.ANCIENT_TOTEM: "ancient_totem",
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
var _loaded_art_folder: String = ""

func setup(p_unit_type: int, p_color: Color, p_size: float = 28.0) -> void:
	unit_type = p_unit_type
	base_color = p_color
	unit_size = p_size
	_setup_sprite_if_available()
	queue_redraw()

func _load_texture(path: String) -> Texture2D:
	if not FileAccess.file_exists(path):
		return null
	var bytes = FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		return null
	var image = Image.new()
	var err = image.load_png_from_buffer(bytes)
	if err != OK:
		push_warning("UnitSprite: PNG decode failed for '%s' with error %d" % [path, err])
		return null
	return ImageTexture.create_from_image(image)

# Builds a SpriteFrames resource from idle.png, walk_01..walk_04.png, and
# attack_01..attack_02.png — whichever of those files actually exist. Returns
# null if even the idle frame is missing, which tells the caller to fall back
# to the procedural shape entirely.
func _build_sprite_frames(folder_path: String) -> SpriteFrames:
	var idle_path = folder_path + "idle.png"
	var idle_texture = _load_texture(idle_path)
	if idle_texture == null:
		return null

	var frames = SpriteFrames.new()
	frames.add_animation("idle")
	frames.set_animation_loop("idle", true)
	frames.add_frame("idle", idle_texture)

	_has_walk_anim = false
	frames.add_animation("walk")
	frames.set_animation_loop("walk", true)
	frames.set_animation_speed("walk", 8.0)
	for i in range(1, 5):
		var p = folder_path + "walk_%02d.png" % i
		var texture = _load_texture(p)
		if texture != null:
			frames.add_frame("walk", texture)
			_has_walk_anim = true
	if not _has_walk_anim:
		frames.remove_animation("walk")   # nothing to play — set_moving(true) will just stay on idle

	_has_attack_anim = false
	frames.add_animation("attack")
	frames.set_animation_loop("attack", false)
	frames.set_animation_speed("attack", 8.0)
	for i in range(1, 3):   # attack1, attack2
		var p = folder_path + "attack_%02d.png" % i
		var texture = _load_texture(p)
		if texture != null:
			frames.add_frame("attack", texture)
			_has_attack_anim = true
	if not _has_attack_anim:
		frames.remove_animation("attack")   # play_attack() will just no-op visually, lunge still happens

	return frames

func _build_legacy_sprite_frames(key: String) -> SpriteFrames:
	var idle_path = LEGACY_FRAME_FOLDER + key + "_walk1.png"
	var idle_texture = _load_texture(idle_path)
	if idle_texture == null:
		return null

	var frames = SpriteFrames.new()
	frames.add_animation("idle")
	frames.set_animation_loop("idle", true)
	frames.add_frame("idle", idle_texture)

	_has_walk_anim = false
	frames.add_animation("walk")
	frames.set_animation_loop("walk", true)
	frames.set_animation_speed("walk", 8.0)
	for i in range(2, 6):
		var p = LEGACY_FRAME_FOLDER + key + "_walk%d.png" % i
		var texture = _load_texture(p)
		if texture != null:
			frames.add_frame("walk", texture)
			_has_walk_anim = true
	if not _has_walk_anim:
		frames.remove_animation("walk")

	_has_attack_anim = false
	frames.add_animation("attack")
	frames.set_animation_loop("attack", false)
	frames.set_animation_speed("attack", 8.0)
	for i in range(1, 3):
		var p = LEGACY_FRAME_FOLDER + key + "_attack%d.png" % i
		var texture = _load_texture(p)
		if texture != null:
			frames.add_frame("attack", texture)
			_has_attack_anim = true
	if not _has_attack_anim:
		frames.remove_animation("attack")

	return frames

# Builds (or rebuilds) the real-art AnimatedSprite2D child if this unit
# type has an entry in SPRITE_FOLDERS AND its idle frame file actually
# exists. If not, leaves _anim_sprite null so _draw() falls back to the
# procedural shape, exactly as before.
func _setup_sprite_if_available() -> void:
	if _anim_sprite:
		_anim_sprite.queue_free()
		_anim_sprite = null

	if not SPRITE_FOLDERS.has(unit_type):
		if not LEGACY_SPRITE_KEYS.has(unit_type):
			return
		var legacy_key = LEGACY_SPRITE_KEYS[unit_type]
		var legacy_frames = _build_legacy_sprite_frames(legacy_key)
		if legacy_frames == null:
			push_warning("UnitSprite: no idle frame found for legacy key '%s', falling back to shape" % legacy_key)
			return
		_apply_sprite_frames(legacy_frames, LEGACY_FRAME_FOLDER + legacy_key)
		return

	var folder_path: String = SPRITE_FOLDERS[unit_type]
	var frames := _build_sprite_frames(folder_path)
	if frames == null:
		push_warning("UnitSprite: no idle frame found in '%s', falling back to shape" % folder_path)
		return

	_apply_sprite_frames(frames, folder_path)

func _apply_sprite_frames(frames: SpriteFrames, source_label: String) -> void:
	_anim_sprite = AnimatedSprite2D.new()
	_anim_sprite.sprite_frames = frames
	_anim_sprite.animation_finished.connect(_on_sprite_animation_finished)
	_anim_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_anim_sprite.z_index = 20
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
	_loaded_art_folder = source_label
	if DEBUG_SPRITE_LOAD:
		print("UnitSprite loaded art: ", source_label)

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
