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
# §3.A (S12) — aura mode. When `follow_target` is set, the totem snaps
# its position to the target each frame instead of staying stationary.
# Used by spell_aura_* to ride at the bot's feet. `aura_buff` is the
# status_id applied to the follow_target on _ready and removed on free
# (e.g. "grace" / "wisdom"). Empty string = no buff (vanilla totem).
var follow_target: Node = null
var aura_buff: String = ""

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

# §3.A aura primitive — spawn a totem that follows `caster_v` (typically
# the bot) and applies `aura_buff_v` as a status while it ticks. The
# damage path stays the same as a stationary totem (so a damaging aura
# IS possible — set damage > 0 for "thorns aura"-style effects). For
# pure-buff auras (grace/wisdom) pass damage=0 and the zap path no-ops
# on null targets.
static func spawn_aura(dungeon: Node, follow_target_v: Node, damage_v: int,
		radius_cells_v: float, lifetime_v: float, zap_interval_v: float,
		damage_type_v: String, visual_color_v: Color, caster_v: Node,
		aura_buff_v: String) -> SpellTotem:
	if dungeon == null or not is_instance_valid(dungeon):
		return null
	if follow_target_v == null or not is_instance_valid(follow_target_v):
		return null
	var t := SpellTotem.new()
	t.position = follow_target_v.position
	t.damage = damage_v
	t.radius_cells = radius_cells_v
	t.lifetime = lifetime_v
	t.zap_interval = max(0.2, zap_interval_v)
	t.damage_type = damage_type_v
	t.visual_color = visual_color_v
	t.caster = caster_v
	t.dungeon_ref = dungeon
	t.follow_target = follow_target_v
	t.aura_buff = aura_buff_v
	t.z_index = 7
	t.draw.connect(t._on_draw)
	var parent: Node = dungeon.actor_layer if "actor_layer" in dungeon else dungeon
	parent.add_child(t)
	# First zap happens after one tick window so the buff has time to
	# render before any damaging pulse.
	t._next_zap = max(0.2, zap_interval_v)
	# Apply the buff status immediately so the player sees the aura
	# light up on cast. Removed on _exit_tree.
	if aura_buff_v != "" and follow_target_v.has_method("add_status"):
		follow_target_v.add_status(aura_buff_v, lifetime_v)
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
	# §3.A: snap to follow_target each frame so the aura visual + zap
	# origin track the bot. Skip if target's been freed (idle-grind
	# floor teardown) — totem will lifetime-expire naturally next tick.
	if follow_target != null:
		if is_instance_valid(follow_target):
			position = follow_target.position
		else:
			follow_target = null  # stop chasing a freed reference
	_next_zap -= delta
	if _next_zap <= 0.0:
		_next_zap = zap_interval
		# Pure-buff auras (damage == 0) skip the zap path entirely so
		# they don't hit allies that aren't there. The buff itself is
		# applied at spawn_aura time + refreshed below if lingering.
		if damage > 0:
			# §3.B: damaging auras (aura_buff != "" AND damage > 0)
			# pulse to ALL enemies in radius — flavor is "thorny aura",
			# not "turret". Stationary totems with aura_buff == ""
			# keep single-nearest "turret" behavior.
			if aura_buff != "":
				_zap_all_in_radius()
			else:
				_zap_nearest()
	# §3.A: refresh the aura status so it doesn't expire mid-aura if
	# the totem's lifetime is longer than `add_status`'s default tick.
	# Cheap — re-applying an existing status updates its expires_at.
	if aura_buff != "" and follow_target != null and is_instance_valid(follow_target):
		if follow_target.has_method("add_status"):
			follow_target.add_status(aura_buff, max(0.5, lifetime - _elapsed))
	queue_redraw()

# §3.A: clear the aura buff when the totem despawns so the player
# stops getting the bonus the moment the visual disappears.
func _exit_tree() -> void:
	if aura_buff != "" and follow_target != null and is_instance_valid(follow_target):
		if follow_target.has_method("remove_status"):
			follow_target.remove_status(aura_buff)


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

# §3.B damaging-aura tick. Pulses damage to every enemy inside the
# radius, not just the nearest. Used by spell_thorn_aura. Visual: a
# faint expanding ring at the radius edge so the player can see
# the pulse beat. Cap-respecting via existing damage_type routing
# (resists / armor / mit all apply on take_damage).
func _zap_all_in_radius() -> void:
	if dungeon_ref == null or not is_instance_valid(dungeon_ref):
		return
	if not "enemies" in dungeon_ref:
		return
	var r_px: float = radius_cells * float(TILE_SIZE)
	var r_sq: float = r_px * r_px
	var hit_count: int = 0
	for e in dungeon_ref.enemies:
		if not is_instance_valid(e) or not e.is_alive:
			continue
		var d: float = position.distance_squared_to(e.position)
		if d <= r_sq:
			if e.has_method("take_damage"):
				e.take_damage(maxi(1, damage), caster, damage_type)
				hit_count += 1
	if hit_count == 0:
		return
	# Visual: expanding ring pulse at the aura's edge. SpellAoe handles
	# its own lifetime + cleanup.
	var actor_layer: Node = dungeon_ref.actor_layer if "actor_layer" in dungeon_ref else null
	if actor_layer != null:
		SpellAoe.spawn_ring(actor_layer, position, r_px, visual_color)
