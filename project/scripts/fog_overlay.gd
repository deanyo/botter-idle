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
	add_child(rect)

func set_visibility_grid(fog: FogSystem) -> void:
	if mat == null or fog == null or fog.vis_texture == null:
		return
	mat.set_shader_parameter("visibility_tex", fog.vis_texture)
	mat.set_shader_parameter("grid_size", Vector2(float(fog.grid_w), float(fog.grid_h)))
	mat.set_shader_parameter("visibility_in_use", 1.0)

func set_darkness(amount: float) -> void:
	if mat:
		mat.set_shader_parameter("base_darkness", clampf(amount, 0.0, 1.0))

func update_lights(world_lights: Array, delta: float) -> void:
	if mat == null or camera == null:
		return
	elapsed += delta
	var positions: PackedVector2Array = PackedVector2Array()
	var radii: PackedFloat32Array = PackedFloat32Array()
	var intensities: PackedFloat32Array = PackedFloat32Array()
	var colors: PackedColorArray = PackedColorArray()
	var n: int = mini(world_lights.size(), MAX_LIGHTS)
	for i in n:
		var l: Dictionary = world_lights[i]
		positions.append(l.position)
		radii.append(l.radius)
		intensities.append(l.intensity)
		colors.append(l.color)
	while positions.size() < MAX_LIGHTS:
		positions.append(Vector2.ZERO)
		radii.append(0.0)
		intensities.append(0.0)
		colors.append(Color(1, 1, 1, 1))
	mat.set_shader_parameter("light_positions", positions)
	mat.set_shader_parameter("light_radii", radii)
	mat.set_shader_parameter("light_intensities", intensities)
	mat.set_shader_parameter("light_colors", colors)
	mat.set_shader_parameter("active_light_count", n)
	mat.set_shader_parameter("camera_world", camera.global_position)
	mat.set_shader_parameter("camera_zoom", camera.zoom.x)
	mat.set_shader_parameter("time_seconds", elapsed)
