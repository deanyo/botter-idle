class_name ColorGrade
extends CanvasLayer

# Per-biome post-process color grade. Sits on a canvas layer above gameplay
# but below the HUD chrome (layer = 50; chrome = 100).
#
# Reads `color_grade` field on the biome dict. Shape:
#   "color_grade": {
#       "tint":          [1.0, 1.0, 1.0],
#       "saturation":    1.0,
#       "contrast":      1.0,
#       "brightness":    0.0,
#       "vignette":      0.0,
#       "vignette_tint": [0.0, 0.0, 0.0],
#       "mix":           1.0
#   }
#
# All keys optional. Missing = identity (no-op).

const SHADER := preload("res://assets/color_grade.gdshader")

var _rect: ColorRect


func _init() -> void:
	# Layer above tile/light rendering (CanvasModulate sits at 0); below HUD.
	# fog_overlay uses its own layer; we sit on top of fog so the grade
	# applies to the final lit + fogged scene.
	layer = 60
	# Don't intercept input.
	# (CanvasLayer doesn't have mouse_filter; the ColorRect inherits IGNORE.)

	_rect = ColorRect.new()
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.anchor_right = 1.0
	_rect.anchor_bottom = 1.0
	_rect.material = ShaderMaterial.new()
	_rect.material.shader = SHADER
	# Default: no-op identity (so absent biome config = pass-through).
	apply_grade({})
	add_child(_rect)


# Accept a Dictionary (biome's `color_grade` value) and push uniforms.
# Missing keys → identity.
func apply_grade(grade: Dictionary) -> void:
	if _rect == null or _rect.material == null:
		return
	var mat: ShaderMaterial = _rect.material as ShaderMaterial
	mat.set_shader_parameter("tint", _v3(grade.get("tint", [1.0, 1.0, 1.0])))
	mat.set_shader_parameter("saturation", float(grade.get("saturation", 1.0)))
	mat.set_shader_parameter("contrast", float(grade.get("contrast", 1.0)))
	mat.set_shader_parameter("brightness", float(grade.get("brightness", 0.0)))
	mat.set_shader_parameter("vignette", float(grade.get("vignette", 0.0)))
	mat.set_shader_parameter("vignette_tint", _v3(grade.get("vignette_tint", [0.0, 0.0, 0.0])))
	mat.set_shader_parameter("mix_amount", float(grade.get("mix", 1.0)))


# Smoothly transition from current uniforms to target over `duration` seconds.
# Useful at biome transitions to avoid a hard pop.
func transition_to(grade: Dictionary, duration: float = 0.5) -> void:
	if _rect == null or _rect.material == null or duration <= 0.0:
		apply_grade(grade)
		return
	var tween := create_tween()
	tween.set_parallel(true)
	var mat: ShaderMaterial = _rect.material as ShaderMaterial
	# Tween mix_amount low→full so partial-apply does the cross-fade work.
	# Cheap; doesn't require interpolating every uniform separately.
	mat.set_shader_parameter("mix_amount", 0.0)
	apply_grade(grade)
	tween.tween_method(
		func(v): mat.set_shader_parameter("mix_amount", v),
		0.0, float(grade.get("mix", 1.0)), duration
	)


static func _v3(arr) -> Vector3:
	if arr is Vector3:
		return arr
	if arr is Array and arr.size() >= 3:
		return Vector3(float(arr[0]), float(arr[1]), float(arr[2]))
	return Vector3(1.0, 1.0, 1.0)
