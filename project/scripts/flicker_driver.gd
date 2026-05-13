class_name FlickerDriver
extends Node

# Drives organic flicker on every PointLight2D in the scene that carries a
# "flicker" meta dict (set by LightSpec.attach). One driver per dungeon
# scene; finds lights via group "flicker_lights" so we don't have to track
# them manually.
#
# Each light's energy is animated by a shared FastNoiseLite, sampled at
# unique x/y coords per-light (derived from light's seed). This guarantees
# desync — every torch in the same biome flickers independently.
#
# Fire-category lights also get sub-pixel position jitter so the flame's
# core appears to shimmer.

const C := preload("res://scripts/constants.gd")

var _noise: FastNoiseLite
var _t: float = 0.0

func _ready() -> void:
	_noise = FastNoiseLite.new()
	_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	_noise.frequency = 1.0

func _process(delta: float) -> void:
	_t += delta
	# Group-based discovery; LightSpec.attach calls add_to_group("flicker_lights").
	# We add lights to the group here lazily — see _ensure_group below.
	# Iterate ALL nodes in the scene with the meta. Cheap once cached.
	var root: Node = get_tree().current_scene
	if root == null:
		return
	_walk_and_animate(root, delta)

func _walk_and_animate(node: Node, delta: float) -> void:
	if node is PointLight2D and node.has_meta("flicker"):
		_animate_light(node, delta)
	for child in node.get_children():
		_walk_and_animate(child, delta)

func _animate_light(light: PointLight2D, _delta: float) -> void:
	var meta: Dictionary = light.get_meta("flicker")
	var freq: float = float(meta.get("freq", 1.0))
	var amp: float = float(meta.get("amp", 0.0))
	if amp <= 0.0:
		return
	var base: float = float(meta.get("base_energy", light.energy))
	var seed_id: int = int(meta.get("seed", 0))
	# Sample noise at (t * freq, seed_y). The seed maps to a Y offset so each
	# light samples a different "row" of the noise field, fully desyncing.
	var n: float = _noise.get_noise_2d(_t * freq, float(seed_id) * 17.3)
	# Layer in a slow secondary wobble for "magic" pulse feel
	var category: String = String(meta.get("category", ""))
	if category == "magic":
		var slow: float = sin(_t * freq * 0.4 + float(seed_id) * 0.7) * 0.4
		n = (n + slow) * 0.5
	light.energy = max(0.0, base * (1.0 + n * amp))
	# Sub-pixel jitter on fire lights only — the flame's center shimmers.
	if category == "fire":
		var base_off: Vector2 = meta.get("base_offset", light.offset)
		var jx: float = _noise.get_noise_2d(_t * freq * 1.3, float(seed_id) * 31.7) * 0.6
		var jy: float = _noise.get_noise_2d(_t * freq * 1.3, float(seed_id) * 47.3 + 100.0) * 0.6
		light.offset = base_off + Vector2(jx, jy)
