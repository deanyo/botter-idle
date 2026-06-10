class_name SpellWisp
extends Node2D

# Wisp Servant — interim orbit-and-target visual. Spawns N wisps that
# orbit the bot at radius `orbit_radius_px` and zap the nearest live
# enemy every `zap_interval`. a05 prop-8: real minion AI is Tier-3.
# This is the "axes-but-flying-out" stand-in.
#
# a10 §3.2 approval: base 4 (rescoped from a05's 8). 1.0s zap interval.
#
# Lifetime is fire-and-forget — wisp queue_frees on lifetime expire OR
# when bot frees (parent reparents to actor_layer; bot-detach watcher
# checks each frame).

const TILE_SIZE := 32

var damage: int = 4
var lifetime: float = 6.0
var zap_interval: float = 1.0
var orbit_radius_px: float = 36.0
var orbit_speed: float = 4.5  # rad/sec
var orbit_phase: float = 0.0
var damage_type: String = "physical"
var element: String = ""
var caster: Node = null
var bot_ref: Node = null
var dungeon_ref: Node = null
var visual_color: Color = Color(0.5, 0.7, 1.0, 1.0)
var sprite_path: String = ""

var _elapsed: float = 0.0
var _next_zap: float = 0.0
var _sprite: Sprite2D = null


static func spawn_wisp(dungeon: Node, bot: Node, damage_v: int, lifetime_v: float,
		zap_interval_v: float, orbit_radius_px_v: float, orbit_phase_v: float,
		damage_type_v: String, element_v: String, sprite_path_v: String,
		visual_color_v: Color, caster_v: Node) -> SpellWisp:
	if dungeon == null or bot == null or not is_instance_valid(dungeon) or not is_instance_valid(bot):
		return null
	var w := SpellWisp.new()
	w.damage = damage_v
	w.lifetime = lifetime_v
	w.zap_interval = max(0.2, zap_interval_v)
	w.orbit_radius_px = orbit_radius_px_v
	w.orbit_phase = orbit_phase_v
	w.damage_type = damage_type_v
	w.element = element_v
	w.sprite_path = sprite_path_v
	w.visual_color = visual_color_v
	w.caster = caster_v
	w.bot_ref = bot
	w.dungeon_ref = dungeon
	w.z_index = 9
	# Place initial position around bot to avoid first-frame snap.
	var bot_center: Vector2 = bot.position + Vector2(TILE_SIZE * 0.5, TILE_SIZE * 0.5)
	w.position = bot_center + Vector2(orbit_radius_px_v * cos(orbit_phase_v), orbit_radius_px_v * sin(orbit_phase_v))
	# Texture
	if sprite_path_v != "" and ResourceLoader.exists(sprite_path_v):
		var spr := Sprite2D.new()
		spr.texture = load(sprite_path_v)
		spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		spr.scale = Vector2(0.55, 0.55)
		spr.modulate = visual_color_v
		w.add_child(spr)
		w._sprite = spr
	var parent: Node = dungeon.actor_layer if "actor_layer" in dungeon else dungeon
	parent.add_child(w)
	w._next_zap = w.zap_interval * 0.5
	return w


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= lifetime:
		queue_free()
		return
	if bot_ref == null or not is_instance_valid(bot_ref):
		queue_free()
		return
	# Orbit around bot.
	orbit_phase += orbit_speed * delta
	var bot_center: Vector2 = bot_ref.position + Vector2(TILE_SIZE * 0.5, TILE_SIZE * 0.5)
	position = bot_center + Vector2(orbit_radius_px * cos(orbit_phase), orbit_radius_px * sin(orbit_phase))
	if _sprite != null and is_instance_valid(_sprite):
		_sprite.rotation = orbit_phase + PI * 0.5
	_next_zap -= delta
	if _next_zap <= 0.0:
		_next_zap = zap_interval
		_zap_nearest()


func _zap_nearest() -> void:
	if dungeon_ref == null or not is_instance_valid(dungeon_ref):
		return
	if not "enemies" in dungeon_ref:
		return
	var r_px: float = float(TILE_SIZE) * 5.0  # 5-cell zap reach from wisp position
	var r_sq: float = r_px * r_px
	var best: Node = null
	var best_d: float = INF
	for e in dungeon_ref.enemies:
		if not is_instance_valid(e) or not e.is_alive:
			continue
		var d: float = position.distance_squared_to(e.position)
		if d < best_d and d <= r_sq:
			best_d = d
			best = e
	if best == null:
		return
	if best.has_method("take_damage"):
		var dt: String = damage_type
		if element != "":
			dt = SpellData.damage_type_for_element(element)
		best.take_damage(maxi(1, damage), caster, dt)
	# Visual zap line from wisp to target
	var actor_layer: Node = dungeon_ref.actor_layer if "actor_layer" in dungeon_ref else null
	if actor_layer != null:
		var pts := [position, best.position]
		SpellAoe.spawn_chain(actor_layer, pts, visual_color)
