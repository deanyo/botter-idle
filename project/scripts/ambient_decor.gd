class_name AmbientDecor
extends Node2D

const C := preload("res://scripts/constants.gd")
const FEATURE_DIR := "res://assets/tiles/features/"

const DECOR_SPECS := {
	"lantern":      { "tile": "lantern.png",      "light": "lantern_gold" },
	"lamp":         { "tile": "lamp.png",         "light": "lantern" },
	"magic_lamp":   { "tile": "magic_lamp.png",   "light": "lantern_gold" },
	"orb":          { "tile": "orb.png",          "light": "crystal_blue" },
	"orb_2":        { "tile": "orb_2.png",        "light": "crystal_purple" },
	"crystal_orb":  { "tile": "crystal_orb.png",  "light": "crystal_blue" },
	"zot_pillar":   { "tile": "zot_pillar.png",   "light": "crystal_purple" },
	"flame_0":      { "tile": "flame_0.png",      "light": "flame_yellow" },
	"flame_1":      { "tile": "flame_1.png",      "light": "flame_orange" },
	"flame_2":      { "tile": "flame_2.png",      "light": "flame_red" },
	"orb_glow_0":   { "tile": "orb_glow_0.png",   "light": "crystal_purple" },
	"orb_glow_1":   { "tile": "orb_glow_1.png",   "light": "crystal_blue" },
	"sparkles_1":   { "tile": "sparkles_1.png",   "light": "chest_gold" },
	"mold_1":       { "tile": "mold_1.png",       "light": "mushroom_glow" },
	"mold_2":       { "tile": "mold_2.png",       "light": "mushroom_glow" },
	"campfire":     { "tile": "flame_2.png",      "light": "campfire" },
}

var sprite: Sprite2D
var glow: Sprite2D
var ember_emitter: GPUParticles2D
var spec_id: String = ""
var light_spec_id: String = ""
var cell: Vector2i = Vector2i.ZERO

# Flicker driver state — populated from the LightSpec entry. Mirrors what
# FlickerDriver does for actor-tier PointLight2D lights, but here drives
# the additive glow Sprite2D's alpha + scale instead. Decor stays cheap on
# GPU (no PointLight2D = no per-light screen pass) while still reading as
# alive on screen.
var _flicker_t: float = 0.0
var _flicker_freq: float = 0.0
var _flicker_amp: float = 0.0
var _flicker_seed: int = 0
var _flicker_category: String = ""
var _glow_base_alpha: float = 0.0
var _glow_base_scale: float = 1.0
static var _shared_noise: FastNoiseLite = null
static var _next_seed: int = 1

static func _get_noise() -> FastNoiseLite:
	if _shared_noise == null:
		_shared_noise = FastNoiseLite.new()
		_shared_noise.noise_type = FastNoiseLite.TYPE_PERLIN
		_shared_noise.frequency = 1.0
	return _shared_noise

func setup(decor_id: String, at_cell: Vector2i) -> void:
	spec_id = decor_id
	cell = at_cell
	position = Vector2(at_cell.x * C.TILE_SIZE, at_cell.y * C.TILE_SIZE)
	var spec: Dictionary = DECOR_SPECS.get(decor_id, {})
	light_spec_id = String(spec.get("light", ""))

func _ready() -> void:
	var spec: Dictionary = DECOR_SPECS.get(spec_id, {})
	if spec.is_empty():
		return
	var tex: Texture2D = load(FEATURE_DIR + String(spec.tile))
	if tex == null:
		return
	sprite = Sprite2D.new()
	sprite.texture = tex
	sprite.centered = true
	sprite.position = Vector2(C.TILE_SIZE * 0.5, C.TILE_SIZE * 0.5)
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(sprite)
	if light_spec_id != "":
		_setup_glow_and_flicker()

func _setup_glow_and_flicker() -> void:
	# Decor tier: NO PointLight2D node (each one is a separate full-screen
	# GPU pass on Apple GL Compatibility — 50 of them tanks fps from 120 to
	# 19). Instead we render a cheap additive glow sprite + animate it
	# with the same noise math FlickerDriver applies to actor-tier lights,
	# and (for fire-category) keep the GPUParticles2D embers since the
	# A/B sweep showed those are nearly free.
	var spec: Dictionary = LightSpec.SPECS.get(light_spec_id, {})
	if spec.is_empty():
		return
	var col: Color = spec.get("color", Color(1, 1, 1))
	var energy: float = float(spec.get("energy", 0.6))
	var range_tiles: float = float(spec.get("range", 3.0))
	_flicker_category = String(spec.get("category", "steady"))
	_flicker_freq = float(spec.get("freq", 1.0))
	_flicker_amp = float(spec.get("amp", 0.0))
	_flicker_seed = _next_seed
	_next_seed += 1
	# Stagger flicker phase so adjacent flames desync naturally — without
	# this every flame in a cluster pulses in lockstep.
	_flicker_t = float(_flicker_seed) * 0.137

	# Additive glow sprite. Scale follows light range so the glow covers
	# roughly the same area the PointLight2D would have lit. Alpha tuned
	# to read as a soft halo around the sprite — full PointLight2D-equivalent
	# brightness (energy * 0.7) blew out the screen.
	glow = Sprite2D.new()
	glow.centered = true
	glow.position = Vector2(C.TILE_SIZE * 0.5, C.TILE_SIZE * 0.5)
	glow.texture = LootDrop._make_glow_texture()
	# Halo brightness — additive blend, so 0.35 reads as a gentle warm
	# overlay rather than a glaring disc.
	_glow_base_alpha = clampf(energy * 0.35, 0.0, 0.45)
	glow.modulate = Color(col.r, col.g, col.b, _glow_base_alpha)
	# Glow radius — slightly tighter than the fog-shader light radius so
	# the local halo and the broad ambient warmth read as different cues.
	_glow_base_scale = clampf(range_tiles * 0.55, 1.3, 3.5)
	glow.scale = Vector2(_glow_base_scale, _glow_base_scale)
	glow.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# Additive blend so multiple glow sources accumulate brightness instead
	# of overlaying opaque colored discs.
	var add_mat := CanvasItemMaterial.new()
	add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	glow.material = add_mat
	add_child(glow)
	# Behind sprite so the icon stays readable on top of the halo.
	move_child(glow, 0)

	# Fire-category ember particles. Cheap relative to PointLight2D
	# (windowed A/B sweep showed disabling embers gained essentially
	# nothing), and they're the visual cue that says "this is fire,
	# not a static glowy thing".
	if _flicker_category == "fire" and not OS.has_environment("BOTTER_NO_EMBERS"):
		ember_emitter = LightSpec._attach_fire_particles(self, Vector2(C.TILE_SIZE * 0.5, C.TILE_SIZE * 0.5), spec)

func _process(delta: float) -> void:
	if glow == null or _flicker_amp <= 0.0:
		return
	_flicker_t += delta
	# Mirror FlickerDriver._animate_light's math so decor and actor-tier
	# lights pulse with the same character. The 0.35 scalar tones the
	# noise contribution down by 65% from the spec's amp — at full amp the
	# flicker reads as too aggressive (whole halo "throbbing"), at 35% it
	# reads as ambient liveliness without dragging the eye.
	const FLICKER_SCALE: float = 0.35
	var n: float = _get_noise().get_noise_2d(_flicker_t * _flicker_freq, float(_flicker_seed) * 17.3)
	if _flicker_category == "magic":
		var slow: float = sin(_flicker_t * _flicker_freq * 0.4 + float(_flicker_seed) * 0.7) * 0.4
		n = (n + slow) * 0.5
	var factor: float = 1.0 + n * _flicker_amp * FLICKER_SCALE
	var alpha: float = clampf(_glow_base_alpha * factor, 0.0, 1.0)
	glow.modulate.a = alpha
	if _flicker_category == "fire":
		var s: float = _glow_base_scale * (1.0 + (factor - 1.0) * 0.25)
		glow.scale = Vector2(s, s)
		# Sub-pixel position jitter on the glow. Same FLICKER_SCALE so
		# jitter scales with everything else.
		var jx: float = _get_noise().get_noise_2d(_flicker_t * _flicker_freq * 1.3, float(_flicker_seed) * 31.7) * 0.6 * FLICKER_SCALE
		var jy: float = _get_noise().get_noise_2d(_flicker_t * _flicker_freq * 1.3, float(_flicker_seed) * 47.3 + 100.0) * 0.6 * FLICKER_SCALE
		glow.position = Vector2(C.TILE_SIZE * 0.5 + jx, C.TILE_SIZE * 0.5 + jy)

func light_emit() -> Dictionary:
	var spec: Dictionary = LightSpec.SPECS.get(light_spec_id, {})
	if spec.is_empty():
		return {}
	return {
		"position": position + Vector2(C.TILE_SIZE * 0.5, C.TILE_SIZE * 0.5),
		"radius": C.TILE_SIZE * float(spec.get("range", 3.0)),
		"intensity": float(spec.get("energy", 0.6)),
		"color": spec.get("color", Color(1, 1, 1)),
	}
