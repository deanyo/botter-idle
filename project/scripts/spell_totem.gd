class_name SpellTotem
extends Node2D

# Lightning turret — drops at the bot's feet, zaps the closest enemy
# every `zap_interval` seconds for `lifetime`. Self-frees on lifetime
# expire OR when its parent dungeon frees (idle-grind block — totem
# can't tick while the floor is being torn down).
#
# Per a05 prop-3 + a10 approval:
#   - base 12 dmg per zap, 4-cell radius, 4s lifetime × duration_pct
#   - zap_interval 0.6s — totem is consistent rather than bursty
#   - drop-and-walk pattern — bot keeps moving, totem keeps zapping
#   - element: thunderous → damage_type lightning (S8 enemy resists
#     read this lookup so storm-walking through forge with a totem
#     anchor lands proper resistance routing)

const TILE_SIZE := 32

var damage: int = 12
var radius_cells: float = 4.0
var lifetime: float = 4.0
var zap_interval: float = 0.6
var damage_type: String = "lightning"
var caster: Node = null
var dungeon_ref: Node = null
var visual_color: Color = Color(0.5, 0.8, 1.0, 0.85)

var _elapsed: float = 0.0
var _next_zap: float = 0.0


static func spawn_totem(dungeon: Node, world_pos: Vector2, damage_v: int,
		radius_cells_v: float, lifetime_v: float, zap_interval_v: float,
		damage_type_v: String, visual_color_v: Color, caster_v: Node) -> SpellTotem:
	if dungeon == null or not is_instance_valid(dungeon):
		return null
	var t := SpellTotem.new()
	t.position = world_pos
	t.damage = damage_v
	t.radius_cells = radius_cells_v
	t.lifetime = lifetime_v
	t.zap_interval = max(0.2, zap_interval_v)
	t.damage_type = damage_type_v
	t.visual_color = visual_color_v
	t.caster = caster_v
	t.dungeon_ref = dungeon
	t.z_index = 7
	t.draw.connect(t._on_draw)
	var parent: Node = dungeon.actor_layer if "actor_layer" in dungeon else dungeon
	parent.add_child(t)
	t._next_zap = 0.4  # first zap quickly so totem reads as immediately-active
	return t


func _on_draw() -> void:
	var s: float = 0.7 + 0.3 * sin(_elapsed * 5.0)
	var size_px: float = 10.0 + 4.0 * s
	var c := visual_color
	c.a = 0.95 * (1.0 - clampf(_elapsed / lifetime, 0.0, 1.0) * 0.4)
	draw_circle(Vector2.ZERO, size_px, c)
	# Inner core pulse
	var core := visual_color
	core.a = 1.0
	draw_circle(Vector2.ZERO, size_px * 0.55, Color(1.0, 1.0, 1.0, 0.85))
	# Outer ring suggests aoe radius (faint)
	var ring := visual_color
	ring.a = 0.18
	draw_arc(Vector2.ZERO, radius_cells * float(TILE_SIZE), 0.0, TAU, 48, ring, 1.5, true)


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= lifetime:
		queue_free()
		return
	_next_zap -= delta
	if _next_zap <= 0.0:
		_next_zap = zap_interval
		_zap_nearest()
	queue_redraw()


func _zap_nearest() -> void:
	if dungeon_ref == null or not is_instance_valid(dungeon_ref):
		return
	if not "enemies" in dungeon_ref:
		return
	var r_px: float = radius_cells * float(TILE_SIZE)
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
		best.take_damage(maxi(1, damage), caster, damage_type)
	# Visual: short Line2D between totem and target. Reuse SpellAoe.spawn_chain
	# for the existing chain-lightning visual.
	var actor_layer: Node = dungeon_ref.actor_layer if "actor_layer" in dungeon_ref else null
	if actor_layer != null:
		var pts := [position, best.position]
		SpellAoe.spawn_chain(actor_layer, pts, visual_color)
