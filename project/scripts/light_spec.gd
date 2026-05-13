class_name LightSpec
extends RefCounted

const C := preload("res://scripts/constants.gd")

# Light category drives flicker/particle behaviour.
#   "fire"    → broadband noise flicker + ember particles + sub-pixel jitter
#   "magic"   → noise + slow sine pulse, no particles
#   "crystal" → slow noise wobble, steady position, no particles
#   "steady"  → no flicker (e.g. soft fountain glow)
const SPECS := {
	# --- Flame family (fire category) ---
	"torch":           { "color": Color(1.0, 0.7, 0.35),  "energy": 0.9,  "range": 4.0, "category": "fire", "freq": 6.0, "amp": 0.30 },
	"flame_yellow":    { "color": Color(1.0, 0.85, 0.4),  "energy": 0.95, "range": 4.0, "category": "fire", "freq": 6.5, "amp": 0.28 },
	"flame_orange":    { "color": Color(1.0, 0.55, 0.2),  "energy": 1.0,  "range": 4.5, "category": "fire", "freq": 6.0, "amp": 0.32 },
	"flame_red":       { "color": Color(1.0, 0.35, 0.15), "energy": 1.05, "range": 4.5, "category": "fire", "freq": 5.5, "amp": 0.34 },
	"campfire":        { "color": Color(1.0, 0.6, 0.25),  "energy": 1.1,  "range": 5.0, "category": "fire", "freq": 5.0, "amp": 0.30 },
	"lava":            { "color": Color(1.0, 0.4, 0.1),   "energy": 1.2,  "range": 4.5, "category": "fire", "freq": 5.0, "amp": 0.32 },
	# Held weapons / unique fire artefacts
	"firestarter":     { "color": Color(1.0, 0.5, 0.15),  "energy": 0.95, "range": 3.0, "category": "fire", "freq": 7.0, "amp": 0.32 },
	"hellfire":        { "color": Color(1.0, 0.25, 0.1),  "energy": 1.0,  "range": 3.5, "category": "fire", "freq": 6.5, "amp": 0.35 },
	# Fire creatures
	"fire_creature":   { "color": Color(1.0, 0.5, 0.2),   "energy": 0.85, "range": 3.0, "category": "fire", "freq": 6.0, "amp": 0.28 },
	"lava_creature":   { "color": Color(1.0, 0.4, 0.1),   "energy": 0.9,  "range": 3.0, "category": "fire", "freq": 5.5, "amp": 0.30 },

	# --- Lantern family (magic category, no embers) ---
	"lantern":         { "color": Color(1.0, 0.9, 0.55),  "energy": 0.85, "range": 4.5, "category": "magic", "freq": 1.5, "amp": 0.10 },
	"lantern_gold":    { "color": Color(1.0, 0.85, 0.35), "energy": 0.95, "range": 5.0, "category": "magic", "freq": 1.2, "amp": 0.12 },
	"magic_lamp":      { "color": Color(1.0, 0.85, 0.45), "energy": 0.9,  "range": 4.5, "category": "magic", "freq": 1.5, "amp": 0.15 },

	# --- Crystal family (steady wobble, no particles) ---
	"ice":             { "color": Color(0.55, 0.8, 1.0),  "energy": 0.45, "range": 3.0, "category": "crystal", "freq": 0.8, "amp": 0.12 },
	"crystal_blue":    { "color": Color(0.55, 0.8, 1.0),  "energy": 0.6,  "range": 3.5, "category": "crystal", "freq": 0.9, "amp": 0.18 },
	"crystal_purple":  { "color": Color(0.85, 0.55, 1.0), "energy": 0.6,  "range": 3.5, "category": "magic",   "freq": 1.1, "amp": 0.22 },
	"crystal_green":   { "color": Color(0.55, 1.0, 0.7),  "energy": 0.6,  "range": 3.5, "category": "crystal", "freq": 0.9, "amp": 0.18 },
	"crystal":         { "color": Color(0.7, 0.9, 1.0),   "energy": 0.6,  "range": 3.5, "category": "crystal", "freq": 0.9, "amp": 0.18 },
	"ice_creature":    { "color": Color(0.6, 0.85, 1.0),  "energy": 0.55, "range": 2.8, "category": "crystal", "freq": 0.7, "amp": 0.15 },

	# --- Magic family (pulse) ---
	"sigil":           { "color": Color(0.6, 0.4, 1.0),   "energy": 0.55, "range": 2.5, "category": "magic",  "freq": 1.2, "amp": 0.28 },
	"demon_blade":     { "color": Color(0.85, 0.3, 0.6),  "energy": 0.7,  "range": 2.5, "category": "magic",  "freq": 1.5, "amp": 0.30 },
	"firefly":         { "color": Color(0.85, 1.0, 0.45), "energy": 0.5,  "range": 1.8, "category": "magic",  "freq": 2.0, "amp": 0.35 },
	"mushroom_glow":   { "color": Color(0.65, 1.0, 0.5),  "energy": 0.45, "range": 2.8, "category": "magic",  "freq": 0.9, "amp": 0.18 },
	"slime_glow":      { "color": Color(0.7, 1.0, 0.4),   "energy": 0.4,  "range": 2.5, "category": "magic",  "freq": 1.1, "amp": 0.25 },

	# --- Altars / fountains (steady-ish) ---
	"altar_trog":          { "color": Color(1.0, 0.3, 0.2),  "energy": 0.7,  "range": 3.5, "category": "magic", "freq": 1.0, "amp": 0.18 },
	"altar_okawaru":       { "color": Color(0.95, 0.85, 0.4),"energy": 0.7,  "range": 3.5, "category": "magic", "freq": 1.0, "amp": 0.18 },
	"altar_zin":           { "color": Color(1.0, 1.0, 0.85), "energy": 0.85, "range": 4.0, "category": "magic", "freq": 0.8, "amp": 0.12 },
	"altar_elyvilon":      { "color": Color(0.7, 1.0, 0.75), "energy": 0.7,  "range": 3.5, "category": "magic", "freq": 0.9, "amp": 0.18 },
	"altar_vehumet":       { "color": Color(0.8, 0.4, 1.0),  "energy": 0.8,  "range": 4.0, "category": "magic", "freq": 1.3, "amp": 0.28 },
	"altar_kikubaaqudgha": { "color": Color(0.5, 0.25, 0.7), "energy": 0.65, "range": 3.5, "category": "magic", "freq": 1.1, "amp": 0.22 },
	"altar_sif_muna":      { "color": Color(0.5, 0.75, 1.0), "energy": 0.7,  "range": 3.5, "category": "magic", "freq": 0.9, "amp": 0.18 },
	"fountain_sparkling":  { "color": Color(0.7, 0.95, 1.0), "energy": 0.65, "range": 3.0, "category": "magic", "freq": 1.0, "amp": 0.18 },
	"fountain_blue":       { "color": Color(0.4, 0.7, 1.0),  "energy": 0.5,  "range": 2.8, "category": "magic", "freq": 0.9, "amp": 0.18 },
	"fountain_blood":      { "color": Color(1.0, 0.3, 0.3),  "energy": 0.55, "range": 2.8, "category": "magic", "freq": 0.9, "amp": 0.18 },
	"chest_gold":          { "color": Color(1.0, 0.85, 0.4), "energy": 0.6,  "range": 3.0, "category": "magic", "freq": 0.8, "amp": 0.13 },
	"chest_orange":        { "color": Color(1.0, 0.55, 0.2), "energy": 0.7,  "range": 3.2, "category": "magic", "freq": 0.9, "amp": 0.18 },
	"loot_uncommon":       { "color": Color(0.4, 0.7, 1.0),  "energy": 0.45, "range": 2.0, "category": "magic", "freq": 0.9, "amp": 0.13 },
	"loot_rare":           { "color": Color(1.0, 0.9, 0.3),  "energy": 0.6,  "range": 2.5, "category": "magic", "freq": 1.0, "amp": 0.18 },
	"loot_epic":           { "color": Color(1.0, 0.55, 0.2), "energy": 0.75, "range": 3.0, "category": "magic", "freq": 1.2, "amp": 0.22 },
	"loot_legendary":      { "color": Color(1.0, 0.3, 0.3),  "energy": 0.95, "range": 3.5, "category": "magic", "freq": 1.4, "amp": 0.28 },
}

# Shared noise generator. Each light gets a unique seed so flames desync.
static var _noise: FastNoiseLite = null
static var _next_seed: int = 1

static func _get_noise() -> FastNoiseLite:
	if _noise == null:
		_noise = FastNoiseLite.new()
		_noise.noise_type = FastNoiseLite.TYPE_PERLIN
		_noise.frequency = 1.0
	return _noise

static func attach(parent: Node2D, spec_id: String, offset_px: Vector2 = Vector2(C.TILE_SIZE * 0.5, C.TILE_SIZE * 0.5)) -> PointLight2D:
	var spec: Dictionary = SPECS.get(spec_id, {})
	if spec.is_empty():
		return null
	var light := PointLight2D.new()
	light.texture = _radial_texture()
	light.texture_scale = float(spec.get("range", 3.0))
	light.offset = offset_px
	light.energy = float(spec.get("energy", 0.7))
	light.color = spec.get("color", Color(1, 1, 1))
	light.range_z_min = -1024
	light.range_z_max = 1024
	light.shadow_enabled = true
	light.shadow_filter = Light2D.SHADOW_FILTER_PCF5
	light.shadow_filter_smooth = 1.5

	# Stamp metadata FlickerDriver reads each frame to drive organic flicker.
	# Each light gets a unique seed so flames desync naturally.
	var seed_id: int = _next_seed
	_next_seed += 1
	light.set_meta("flicker", {
		"base_energy": light.energy,
		"base_offset": offset_px,
		"category": String(spec.get("category", "steady")),
		"freq": float(spec.get("freq", 1.0)),
		"amp": float(spec.get("amp", 0.0)),
		"seed": seed_id,
	})

	parent.add_child(light)

	# Particle effects on flame-category sources only.
	if String(spec.get("category", "")) == "fire":
		_attach_fire_particles(parent, offset_px, spec)

	return light

static func _attach_fire_particles(parent: Node2D, offset_px: Vector2, spec: Dictionary) -> void:
	var p := GPUParticles2D.new()
	p.position = offset_px
	p.amount = 14
	p.lifetime = 1.0
	p.speed_scale = 1.0
	p.preprocess = 0.5  # Pre-fill so newly-spawned lights aren't bare
	p.local_coords = true
	p.z_index = 4

	var mat := ParticleProcessMaterial.new()
	# Drift upward
	mat.gravity = Vector3(0, -25, 0)
	mat.initial_velocity_min = 4.0
	mat.initial_velocity_max = 16.0
	mat.angle_min = -180
	mat.angle_max = 180
	mat.scale_min = 0.6
	mat.scale_max = 1.4
	mat.scale_curve = _ember_scale_curve()
	# Random spawn within a small disc
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = 4.0
	mat.spread = 35.0
	# Color: hot core fading to ash
	var col: Color = spec.get("color", Color(1, 0.6, 0.2))
	mat.color = col
	mat.color_ramp = _ember_gradient(col)
	p.process_material = mat

	# Tiny ember dot texture
	p.texture = _ember_texture()
	parent.add_child(p)

static var _cached_radial: Texture2D = null

static func _radial_texture() -> Texture2D:
	if _cached_radial != null:
		return _cached_radial
	var size_px: int = 96
	var img := Image.create(size_px, size_px, false, Image.FORMAT_RGBA8)
	var center := Vector2(size_px * 0.5, size_px * 0.5)
	var max_d: float = size_px * 0.5
	for y in size_px:
		for x in size_px:
			var d: float = Vector2(x, y).distance_to(center)
			var t: float = clampf(1.0 - d / max_d, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, t * t))
	_cached_radial = ImageTexture.create_from_image(img)
	return _cached_radial

static var _cached_ember: Texture2D = null

static func _ember_texture() -> Texture2D:
	if _cached_ember != null:
		return _cached_ember
	var size_px: int = 8
	var img := Image.create(size_px, size_px, false, Image.FORMAT_RGBA8)
	var center := Vector2(size_px * 0.5, size_px * 0.5)
	var max_d: float = size_px * 0.5
	for y in size_px:
		for x in size_px:
			var d: float = Vector2(x, y).distance_to(center)
			var t: float = clampf(1.0 - d / max_d, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, t))
	_cached_ember = ImageTexture.create_from_image(img)
	return _cached_ember

static func _ember_gradient(base: Color) -> GradientTexture1D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.4, 1.0])
	g.colors = PackedColorArray([
		Color(base.r, base.g, base.b, 1.0),
		Color(base.r * 0.7, base.g * 0.4, base.b * 0.2, 0.7),
		Color(0.2, 0.2, 0.2, 0.0),
	])
	var tex := GradientTexture1D.new()
	tex.gradient = g
	return tex

static func _ember_scale_curve() -> CurveTexture:
	var c := Curve.new()
	c.add_point(Vector2(0.0, 1.0))
	c.add_point(Vector2(0.7, 0.6))
	c.add_point(Vector2(1.0, 0.0))
	var ct := CurveTexture.new()
	ct.curve = c
	return ct
