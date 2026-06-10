class_name SpellCloud
extends Node2D

# DoT cloud / patch — stationary AoE that ticks damage on overlap.
# Used by Venom Cloud (poison) and Ember Bloom (fire). Spawns at a
# target cell, ticks every `tick_interval` seconds for `lifetime`,
# and queue_frees itself.
#
# Per a10 §3.2 rescopes:
#   - tick rate HARD-CAPPED at 2/s irrespective of of_lingering
#     (cloud lifetime scales with spell_duration_pct, but ticks-per-
#     second never exceed 2/s — closes the per-tick stack ceiling)
#   - 3-enemy max in cloud per tick (caps per-cast pack DPS)
#
# Lifetime is FIRE-AND-FORGET. The cloud parents itself to the
# dungeon's actor_layer; if dungeon frees mid-floor (descend, restart)
# the cloud frees with it via the scene tree — that's the idle-grind
# block for spell drops on floor change.

const TILE_SIZE := 32
const _SHARD_DIR := "res://assets/tiles/spells/effects/"

# Capped at 2/s by the rescope. Default 0.5s = 2 ticks/s.
const TICK_INTERVAL_MIN := 0.5
const ENEMIES_PER_TICK_CAP := 3

var damage_per_tick: int = 0
var damage_type: String = "poison"
var radius_cells: float = 2.0
var lifetime: float = 8.0
var tick_interval: float = TICK_INTERVAL_MIN
var caster: Node = null
var dungeon_ref: Node = null
var visual_color: Color = Color(0.5, 1.0, 0.4, 0.55)

var _elapsed: float = 0.0
var _next_tick: float = 0.0
var _hit_set_per_tick: Dictionary = {}

# Spawn helper — handles the per-cloud bookkeeping, sets up the visual,
# and parents the cloud to actor_layer so it dies with the dungeon. The
# `damage_per_tick` is the per-tick value AFTER spell_data scaling
# (caller should pre-multiply by stat_mult/dmg_mult/elem_mult).
static func spawn_cloud(dungeon: Node, world_pos: Vector2, damage_per_tick_v: int,
		damage_type_v: String, radius_cells_v: float, lifetime_v: float,
		visual_color_v: Color, caster_v: Node) -> SpellCloud:
	if dungeon == null or not is_instance_valid(dungeon):
		return null
	var c := SpellCloud.new()
	c.position = world_pos
	c.damage_per_tick = damage_per_tick_v
	c.damage_type = damage_type_v
	c.radius_cells = radius_cells_v
	c.lifetime = lifetime_v
	c.visual_color = visual_color_v
	c.caster = caster_v
	c.dungeon_ref = dungeon
	c.z_index = 6
	# Visual: pulsing translucent disc that fades on lifetime expire.
	c.draw.connect(c._on_draw)
	var parent: Node = dungeon.actor_layer if "actor_layer" in dungeon else dungeon
	parent.add_child(c)
	# First tick fires after one interval so spawning doesn't double-hit.
	c._next_tick = c.tick_interval
	return c


func _on_draw() -> void:
	var r_px: float = radius_cells * float(TILE_SIZE)
	var pulse: float = 0.65 + 0.35 * sin(_elapsed * 4.0)
	var c := visual_color
	c.a *= pulse * (1.0 - clampf(_elapsed / lifetime, 0.0, 1.0))
	draw_circle(Vector2.ZERO, r_px, c)
	var rim := visual_color
	rim.a = 0.85 * (1.0 - clampf(_elapsed / lifetime, 0.0, 1.0))
	draw_arc(Vector2.ZERO, r_px, 0.0, TAU, 64, rim, 1.5, true)


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= lifetime:
		queue_free()
		return
	_next_tick -= delta
	if _next_tick <= 0.0:
		_next_tick = max(TICK_INTERVAL_MIN, tick_interval)
		_do_tick()
	queue_redraw()


func _do_tick() -> void:
	if dungeon_ref == null or not is_instance_valid(dungeon_ref):
		return
	if not "enemies" in dungeon_ref:
		return
	var r_px: float = radius_cells * float(TILE_SIZE)
	var r_sq: float = r_px * r_px
	# 3-enemy max per tick — sort by distance, take the closest 3.
	var hits: Array = []
	for e in dungeon_ref.enemies:
		if not is_instance_valid(e) or not e.is_alive:
			continue
		var d_sq: float = position.distance_squared_to(e.position)
		if d_sq <= r_sq:
			hits.append({"e": e, "d": d_sq})
	if hits.is_empty():
		return
	hits.sort_custom(func(a, b): return a.d < b.d)
	var n: int = mini(ENEMIES_PER_TICK_CAP, hits.size())
	for i in n:
		var e: Node = hits[i].e
		if not is_instance_valid(e) or not e.is_alive:
			continue
		if e.has_method("take_damage"):
			e.take_damage(maxi(1, damage_per_tick), caster, damage_type)
