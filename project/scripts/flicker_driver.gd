class_name FlickerDriver
extends Node

# Drives organic flicker on every PointLight2D registered via
# LightSpec.attach. Lights stamp themselves on the "flicker_lights"
# group, so FlickerDriver doesn't have to walk the scene tree every
# frame.
#
# Each light's energy is animated by a shared FastNoiseLite, sampled at
# unique x/y coords per-light (derived from the light's seed). Fire
# lights also get sub-pixel position jitter and ember particles.
#
# Visibility gating: lights that aren't currently rendered (parent
# hidden by fog, or detached from tree) are skipped — no animation
# work, ember emitters paused. They flicker normally the moment they
# come back into view.

const C := preload("res://scripts/constants.gd")

var _noise: FastNoiseLite
var _t: float = 0.0
var _cached_lights: Array = []
# Coarse refresh cadence in seconds. Flicker lights only enter/leave the
# tree on floor build (~once per second of play at most), so refreshing 4×
# per second is more than enough — no need to wire signal listeners.
const REFRESH_INTERVAL: float = 0.25
var _refresh_accum: float = 0.0

func _ready() -> void:
	_noise = FastNoiseLite.new()
	_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	_noise.frequency = 1.0
	# Was: subscribed to tree.node_added/node_removed globally. Every blood
	# splat, hit flash, loot tween, attack effect node fired the signal,
	# marked the cache dirty, and forced a full tree walk on the next
	# frame. On forge with combat that's hundreds of refreshes per second.
	# Now: refresh on a coarse timer (every REFRESH_INTERVAL) and detect
	# stale entries inline during _process.

func _process(delta: float) -> void:
	_t += delta
	PerfMon.begin(PerfMon.TAG_FLICKER)
	_refresh_accum += delta
	if _refresh_accum >= REFRESH_INTERVAL:
		_refresh_accum = 0.0
		_cached_lights = get_tree().get_nodes_in_group("flicker_lights")
	for n in _cached_lights:
		if not is_instance_valid(n):
			# Stale slot — next refresh tick will drop it. We just skip.
			continue
		if not (n is PointLight2D):
			continue
		var light: PointLight2D = n
		# Visibility gating: hidden lights don't need per-frame work.
		# Pause embers too — fog hides the parent, the embers just burn
		# CPU/GPU for nothing.
		if not light.is_visible_in_tree():
			if light.has_meta("ember_emitter"):
				var em: GPUParticles2D = light.get_meta("ember_emitter")
				if is_instance_valid(em) and em.emitting:
					em.emitting = false
			continue
		if light.has_meta("ember_emitter"):
			var em2: GPUParticles2D = light.get_meta("ember_emitter")
			if is_instance_valid(em2) and not em2.emitting:
				em2.emitting = true
		_animate_light(light, delta)
	PerfMon.end(PerfMon.TAG_FLICKER)

func _animate_light(light: PointLight2D, _delta: float) -> void:
	if not light.has_meta("flicker"):
		return
	var meta: Dictionary = light.get_meta("flicker")
	var freq: float = float(meta.get("freq", 1.0))
	var amp: float = float(meta.get("amp", 0.0))
	if amp <= 0.0:
		return
	var base: float = float(meta.get("base_energy", light.energy))
	var seed_id: int = int(meta.get("seed", 0))
	var n: float = _noise.get_noise_2d(_t * freq, float(seed_id) * 17.3)
	var category: String = String(meta.get("category", ""))
	if category == "magic":
		var slow: float = sin(_t * freq * 0.4 + float(seed_id) * 0.7) * 0.4
		n = (n + slow) * 0.5
	light.energy = max(0.0, base * (1.0 + n * amp))
	if category == "fire":
		var base_off: Vector2 = meta.get("base_offset", light.offset)
		var jx: float = _noise.get_noise_2d(_t * freq * 1.3, float(seed_id) * 31.7) * 0.6
		var jy: float = _noise.get_noise_2d(_t * freq * 1.3, float(seed_id) * 47.3 + 100.0) * 0.6
		light.offset = base_off + Vector2(jx, jy)
