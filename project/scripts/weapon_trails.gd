class_name WeaponTrails
extends RefCounted

# Per-flavor swing-trail particle bursts.
#
# We pay no per-frame cost when not swinging — each particle node is
# lazily created on first burst, parked under the weapon sprite, set
# to one_shot. Calling `emit_burst()` flips emitting=true; particles
# auto-stop after lifetime. Cheap enough to spawn on every swing
# (~0.18s window, ~12-24 particles).
#
# Pattern intentionally mirrors LightSpec.attach() — code-built rather
# than scene-authored so we don't need to ship a .tscn per flavor.
#
# Flavors covered (priority match against item flavor_tags):
#   fire        → ember sparks + orange smoke
#   cold        → frost shards + cyan steam
#   vampiric    → blood mist red drips
#   thunderous  → electric arc-spec sparks (white/blue)
#   holy        → gold motes
#   poison      → green wisps
#
# Anything not in this map → no trail.

const _FLAVOR_PRIORITY := [
	"fire", "cold", "vampiric", "thunderous", "holy", "poison",
]

const _FLAVOR_SPECS := {
	"fire": {
		"color":        Color(1.0, 0.55, 0.18, 0.95),
		"color_end":    Color(0.6, 0.05, 0.0, 0.0),
		"count":        18,
		"lifetime":     0.45,
		"speed_min":    35.0,
		"speed_max":    85.0,
		"scale_start":  0.55,
		"scale_end":    0.05,
		"gravity":      Vector2(0, -120.0),  # rises like flame
	},
	"cold": {
		"color":        Color(0.65, 0.92, 1.0, 0.95),
		"color_end":    Color(0.25, 0.5, 0.85, 0.0),
		"count":        20,
		"lifetime":     0.55,
		"speed_min":    25.0,
		"speed_max":    65.0,
		"scale_start":  0.45,
		"scale_end":    0.0,
		"gravity":      Vector2(0, 30.0),
	},
	"vampiric": {
		"color":        Color(0.85, 0.10, 0.10, 0.95),
		"color_end":    Color(0.35, 0.0, 0.0, 0.0),
		"count":        14,
		"lifetime":     0.50,
		"speed_min":    20.0,
		"speed_max":    55.0,
		"scale_start":  0.5,
		"scale_end":    0.05,
		"gravity":      Vector2(0, 200.0),  # blood drips down
	},
	"thunderous": {
		"color":        Color(0.85, 0.92, 1.0, 1.0),
		"color_end":    Color(0.45, 0.6, 1.0, 0.0),
		"count":        16,
		"lifetime":     0.30,
		"speed_min":    60.0,
		"speed_max":    140.0,
		"scale_start":  0.40,
		"scale_end":    0.05,
		"gravity":      Vector2(0, 0.0),
	},
	"holy": {
		"color":        Color(1.0, 0.92, 0.55, 0.95),
		"color_end":    Color(1.0, 0.78, 0.20, 0.0),
		"count":        14,
		"lifetime":     0.65,
		"speed_min":    20.0,
		"speed_max":    50.0,
		"scale_start":  0.35,
		"scale_end":    0.10,
		"gravity":      Vector2(0, -45.0),  # ascends slowly
	},
	"poison": {
		"color":        Color(0.55, 0.95, 0.4, 0.85),
		"color_end":    Color(0.2, 0.45, 0.15, 0.0),
		"count":        12,
		"lifetime":     0.70,
		"speed_min":    15.0,
		"speed_max":    40.0,
		"scale_start":  0.50,
		"scale_end":    0.10,
		"gravity":      Vector2(0, -15.0),
	},
}

# Pick the highest-priority trail flavor for a weapon's tag set.
# Empty string = no trail.
static func flavor_for_tags(flavor_tags: Array) -> String:
	if flavor_tags == null or flavor_tags.is_empty():
		return ""
	for tag in _FLAVOR_PRIORITY:
		if tag in flavor_tags:
			return tag
	return ""

# Emit one swing-trail burst from `parent` (typically the weapon
# Sprite2D so the particles ride the swing transform). Reuses an
# existing GPUParticles2D child if present, else creates one.
static func emit_burst(parent: Node2D, flavor: String) -> void:
	if flavor == "" or not _FLAVOR_SPECS.has(flavor):
		return
	if parent == null or not is_instance_valid(parent):
		return
	var spec: Dictionary = _FLAVOR_SPECS[flavor]
	var node_name: String = "_WeaponTrail_" + flavor
	var p: GPUParticles2D = parent.get_node_or_null(node_name) as GPUParticles2D
	if p == null:
		p = _build_particles(spec)
		p.name = node_name
		# Sit BEHIND the weapon sprite so the blade is the front-most
		# element; particles trail visually around/behind it.
		p.z_index = -1
		parent.add_child(p)
	# Restart so consecutive swings re-emit instead of waiting out
	# the previous burst.
	p.restart()
	p.emitting = true

static func _build_particles(spec: Dictionary) -> GPUParticles2D:
	var p := GPUParticles2D.new()
	# Slider-driven amount + lifetime multipliers so the user can dial
	# trails up/down from video options. Default 1.0 = stock spec.
	var amt_mult: float = VideoSettings.tunable("trail_amount", 1.0)
	var life_mult: float = VideoSettings.tunable("trail_lifetime", 1.0)
	p.amount = maxi(1, int(round(float(spec.get("count", 16)) * amt_mult)))
	p.lifetime = maxf(0.05, float(spec.get("lifetime", 0.5)) * life_mult)
	p.one_shot = true
	p.explosiveness = 0.6  # most particles spawn near t=0 — feels like a burst
	p.local_coords = false  # particles drift in world space after spawn
	p.texture = _make_dot_texture()
	p.process_material = _build_process_material(spec)
	# Don't auto-emit on add. emit_burst() flips it on.
	p.emitting = false
	return p

static func _build_process_material(spec: Dictionary) -> ParticleProcessMaterial:
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = 4.0
	# Spread the burst around the full circle — we don't know the
	# weapon's local "tip" direction at material-build time, and the
	# parent Sprite2D's rotation already aimed the burst.
	mat.spread = 180.0
	mat.initial_velocity_min = float(spec.get("speed_min", 30.0))
	mat.initial_velocity_max = float(spec.get("speed_max", 80.0))
	var grav: Vector2 = spec.get("gravity", Vector2.ZERO)
	mat.gravity = Vector3(grav.x, grav.y, 0.0)
	mat.scale_min = float(spec.get("scale_start", 0.5))
	mat.scale_max = float(spec.get("scale_start", 0.5))
	# Scale curve: shrinks toward scale_end across lifetime.
	var sc := Curve.new()
	sc.add_point(Vector2(0.0, 1.0))
	sc.add_point(Vector2(1.0, float(spec.get("scale_end", 0.0)) / max(0.01, float(spec.get("scale_start", 0.5)))))
	var sct := CurveTexture.new()
	sct.curve = sc
	mat.scale_curve = sct
	mat.color = spec.get("color", Color(1, 1, 1, 1))
	# Color ramp: fades to color_end alpha 0 by end of life.
	var grad := Gradient.new()
	grad.add_point(0.0, spec.get("color", Color(1, 1, 1, 1)))
	grad.add_point(1.0, spec.get("color_end", Color(1, 1, 1, 0)))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	mat.color_ramp = gt
	# Slight angle randomness so trails don't read as parallel beams.
	mat.angle_min = -180.0
	mat.angle_max = 180.0
	return mat

# 8×8 soft circular dot. Built once, cached. Same trick LootDrop uses.
static var _DOT_TEX: Texture2D = null
static func _make_dot_texture() -> Texture2D:
	if _DOT_TEX != null:
		return _DOT_TEX
	var size := 8
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := float(size) * 0.5 - 0.5
	for y in size:
		for x in size:
			var dx: float = float(x) - c
			var dy: float = float(y) - c
			var r: float = sqrt(dx * dx + dy * dy) / c
			var a: float = clampf(1.0 - r, 0.0, 1.0)
			# soft falloff
			a = a * a
			img.set_pixel(x, y, Color(1, 1, 1, a))
	var tex := ImageTexture.create_from_image(img)
	_DOT_TEX = tex
	return tex
