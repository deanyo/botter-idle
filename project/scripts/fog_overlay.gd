class_name FogOverlay
extends CanvasLayer

const C := preload("res://scripts/constants.gd")
const SHADER := preload("res://assets/fog_overlay.gdshader")
const MAX_LIGHTS := 24

var rect: ColorRect
var mat: ShaderMaterial
var camera: Camera2D
var viewport_size: Vector2 = Vector2(540, 960)
var elapsed: float = 0.0

# Reusable buffers — preallocated to MAX_LIGHTS so update_lights() never
# allocates in the hot path. Pushed to the shader only when contents
# actually change (or camera moves / time advances), see update_lights().
var _buf_positions: PackedVector2Array
var _buf_radii: PackedFloat32Array
var _buf_intensities: PackedFloat32Array
var _buf_colors: PackedColorArray
var _last_active_count: int = -1
var _last_camera_world: Vector2 = Vector2(INF, INF)
var _last_camera_zoom: float = -1.0

func setup(cam: Camera2D, view_size: Vector2 = Vector2(540, 960)) -> void:
	camera = cam
	viewport_size = view_size
	if rect != null:
		return
	layer = 5
	rect = ColorRect.new()
	rect.anchor_right = 1
	rect.anchor_bottom = 1
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mat = ShaderMaterial.new()
	mat.shader = SHADER
	rect.material = mat
	mat.set_shader_parameter("base_darkness", 0.97)
	mat.set_shader_parameter("viewport_size", viewport_size)
	mat.set_shader_parameter("active_light_count", 0)
	mat.set_shader_parameter("visibility_in_use", 0.0)
	mat.set_shader_parameter("tile_size_px", float(C.TILE_SIZE))
	# Preallocate the packed arrays once. update_lights() resizes (cheap)
	# and overwrites slots in place, never reallocating.
	_buf_positions = PackedVector2Array()
	_buf_positions.resize(MAX_LIGHTS)
	_buf_radii = PackedFloat32Array()
	_buf_radii.resize(MAX_LIGHTS)
	_buf_intensities = PackedFloat32Array()
	_buf_intensities.resize(MAX_LIGHTS)
	_buf_colors = PackedColorArray()
	_buf_colors.resize(MAX_LIGHTS)
	add_child(rect)

func set_visibility_grid(fog: FogSystem) -> void:
	# Marks the shader as "fog active" — the per-cell visibility texture is
	# no longer sampled (replaced by shader-side ray-march against
	# wall_mask_tex). Callers still invoke this so we keep the entry point
	# stable; it now only flips the in_use flag and records grid_size.
	if mat == null or fog == null:
		return
	mat.set_shader_parameter("grid_size", Vector2(float(fog.grid_w), float(fog.grid_h)))
	mat.set_shader_parameter("visibility_in_use", 1.0)

# Build (or rebuild) the wall mask texture from the dungeon's tile grid.
# Called once per floor by dungeon._build_floor. R8: 1.0 = wall, 0.0 = walkable.
# The shader ray-marches against this mask to test LoS — if any sample on
# the ray from a fragment to the bot is opaque, the fragment is dark. This
# replaces the per-cell binary visibility texture which produced the
# tile-aligned "tick" and Bresenham stripe artifacts.
var _wall_mask_image: Image = null
var _wall_mask_tex: ImageTexture = null
func set_wall_mask_from_grid(grid: Array) -> void:
	if mat == null:
		return
	var h: int = grid.size()
	var w: int = grid[0].size() if h > 0 else 0
	if w == 0 or h == 0:
		return
	if _wall_mask_image == null or _wall_mask_image.get_width() != w or _wall_mask_image.get_height() != h:
		_wall_mask_image = Image.create(w, h, false, Image.FORMAT_R8)
	for y in h:
		var row: Array = grid[y]
		for x in w:
			# Anything not in WALKABLE_TERRAIN blocks light. Doors block until
			# opened — we treat any T_DOOR as walkable here so the interior of
			# rooms isn't solid-black before entry.
			var is_wall: bool = (row[x] == C.T_WALL)
			_wall_mask_image.set_pixel(x, y, Color(1.0 if is_wall else 0.0, 0, 0, 1))
	if _wall_mask_tex == null:
		_wall_mask_tex = ImageTexture.create_from_image(_wall_mask_image)
	else:
		_wall_mask_tex.update(_wall_mask_image)
	mat.set_shader_parameter("wall_mask_tex", _wall_mask_tex)
	mat.set_shader_parameter("grid_size", Vector2(float(w), float(h)))

func set_darkness(amount: float) -> void:
	if mat:
		mat.set_shader_parameter("base_darkness", clampf(amount, 0.0, 1.0))

var _last_bot_world: Vector2 = Vector2(INF, INF)
var _last_bot_radius_px: float = -1.0

# bot_world: continuous world-pixel position of the bot (centre of its sprite).
# bot_radius_px: LoS radius in world pixels (cells × tile_size_px).
# Both are pushed every frame so the shader ray-march tracks bot motion
# smoothly between cell boundaries — fixes the "tick" that the per-cell
# visibility texture produced.
func update_lights(world_lights: Array, delta: float, bot_world: Vector2 = Vector2(INF, INF), bot_radius_px: float = 0.0) -> void:
	if mat == null or camera == null:
		return
	elapsed += delta
	if bot_world.x != INF:
		if bot_world != _last_bot_world:
			mat.set_shader_parameter("bot_world", bot_world)
			_last_bot_world = bot_world
		if not is_equal_approx(bot_radius_px, _last_bot_radius_px):
			mat.set_shader_parameter("bot_radius_px", bot_radius_px)
			_last_bot_radius_px = bot_radius_px
	var n: int = mini(world_lights.size(), MAX_LIGHTS)
	# Detect content change. Light list size + per-slot position/radius/
	# intensity/color comparison. Cheap because n <= 24 and we early-exit
	# on the first mismatch.
	var lights_changed: bool = (n != _last_active_count)
	for i in n:
		var l: Dictionary = world_lights[i]
		var lp: Vector2 = l.position
		var lr: float = l.radius
		var li: float = l.intensity
		var lc: Color = l.color
		if not lights_changed:
			if _buf_positions[i] != lp \
					or not is_equal_approx(_buf_radii[i], lr) \
					or not is_equal_approx(_buf_intensities[i], li) \
					or _buf_colors[i] != lc:
				lights_changed = true
		_buf_positions[i] = lp
		_buf_radii[i] = lr
		_buf_intensities[i] = li
		_buf_colors[i] = lc
	# Zero-pad unused slots only when active_count shrinks.
	if n < _last_active_count:
		for i in range(n, MAX_LIGHTS):
			_buf_positions[i] = Vector2.ZERO
			_buf_radii[i] = 0.0
			_buf_intensities[i] = 0.0
			_buf_colors[i] = Color(1, 1, 1, 1)
	if lights_changed:
		mat.set_shader_parameter("light_positions", _buf_positions)
		mat.set_shader_parameter("light_radii", _buf_radii)
		mat.set_shader_parameter("light_intensities", _buf_intensities)
		mat.set_shader_parameter("light_colors", _buf_colors)
		mat.set_shader_parameter("active_light_count", n)
		_last_active_count = n
	# Camera-derived params only change when the camera moves.
	# camera.offset shifts the viewport's world-centre away from camera.position
	# (Dungeon uses it to recentre the bot inside the chrome-free region of the
	# screen). Both must be summed so the shader resolves world_px to the same
	# point the canvas renderer is showing — otherwise the lit halo drifts off
	# the bot sprite.
	var cam_world: Vector2 = camera.global_position + camera.offset
	var cam_zoom: float = camera.zoom.x
	if cam_world != _last_camera_world:
		mat.set_shader_parameter("camera_world", cam_world)
		_last_camera_world = cam_world
	if not is_equal_approx(cam_zoom, _last_camera_zoom):
		mat.set_shader_parameter("camera_zoom", cam_zoom)
		_last_camera_zoom = cam_zoom
	# time_seconds drives shader-side animation (e.g. flicker on the
	# per-light tint), so push it every frame.
	mat.set_shader_parameter("time_seconds", elapsed)
