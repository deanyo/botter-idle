class_name SpellAoe
extends RefCounted

# Shared AoE renderer for spells. Three flavors:
#   spawn_ring(parent, origin, radius_px, color)  — frost-nova style
#       expanding ring; alpha pulses out → in → off over 0.45s
#   spawn_cone(parent, origin, facing, length, half_angle, color) — holy
#       beam wedge; fades over 0.4s
#   spawn_chain(parent, points, color) — chain-lightning Line2D between
#       sequential points; lifetime 0.18s
#
# All three are fire-and-forget — they tween themselves out and free.
# No persistent state, no pooling needed (spell cooldowns gate spawn rate
# below 1/sec per slot, so spawn churn is tiny).

const RING_LIFETIME := 0.45
const CONE_LIFETIME := 0.40
const CHAIN_LIFETIME := 0.18

# Expanding ring AoE — drawn as a Node2D with a custom _draw that paints
# a 2px ring at the current radius. Radius eases out with EASE_OUT_QUART.
# Combat-pivot follow-up 2026-06-04: also scatters ice_shatter sprite
# motes along the expanding ring perimeter so frost-nova reads as
# shrapnel, not just an outline.
const _RING_SHARD_PATH := "res://assets/tiles/effects/ice_shatter.png"
const _RING_SHARD_COUNT := 12
static func spawn_ring(parent: Node, origin: Vector2, radius_px: float, color: Color) -> void:
	var node := Node2D.new()
	node.position = origin
	node.z_index = 12
	node.set_meta("col", color)
	node.set_meta("r", 0.0)
	node.set_meta("max_r", radius_px)
	node.set_meta("alpha", 0.85)
	node.draw.connect(func():
		var r: float = float(node.get_meta("r"))
		var c: Color = node.get_meta("col")
		c.a = float(node.get_meta("alpha"))
		node.draw_arc(Vector2.ZERO, r, 0.0, TAU, 64, c, 2.5, true)
		var inner: Color = c
		inner.a *= 0.4
		node.draw_arc(Vector2.ZERO, r * 0.85, 0.0, TAU, 64, inner, 1.5, true)
	)
	parent.add_child(node)
	# Sprite shrapnel — N tile sprites on the perimeter, riding the ring
	# expansion outward. Adds visible "fragments flying" texture so the
	# spell reads as elemental impact, not abstract geometry.
	var shard_tex: Texture2D = null
	if ResourceLoader.exists(_RING_SHARD_PATH):
		shard_tex = load(_RING_SHARD_PATH)
	var shards: Array = []
	if shard_tex != null:
		for i in _RING_SHARD_COUNT:
			var spr := Sprite2D.new()
			spr.texture = shard_tex
			spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			spr.scale = Vector2(0.55, 0.55)
			spr.modulate = Color(color.r, color.g, color.b, 0.95)
			var ang: float = float(i) * (TAU / float(_RING_SHARD_COUNT))
			spr.rotation = ang
			spr.position = Vector2.ZERO
			node.add_child(spr)
			shards.append({"spr": spr, "ang": ang})
	var tween := node.create_tween().set_parallel(true)
	tween.tween_method(
		func(v: float):
			node.set_meta("r", v)
			# Place each shard at the live ring radius along its angle.
			for sh in shards:
				var s: Sprite2D = sh.spr
				if is_instance_valid(s):
					s.position = Vector2.from_angle(float(sh.ang)) * v
			node.queue_redraw(),
		0.0, radius_px, RING_LIFETIME
	).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	tween.tween_method(
		func(a: float):
			node.set_meta("alpha", a)
			for sh in shards:
				var s: Sprite2D = sh.spr
				if is_instance_valid(s):
					s.modulate.a = a * 1.1
			node.queue_redraw(),
		0.85, 0.0, RING_LIFETIME
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(node.queue_free)

# Cone wedge — drawn as a filled triangle fan from origin spanning
# ±half_angle around `facing`. Alpha fades over CONE_LIFETIME. Combat-
# pivot follow-up 2026-06-04: scatters gold_sparkle sprites along the
# cone for sprite-driven impact texture.
const _CONE_SPARK_PATH := "res://assets/tiles/effects/gold_sparkle.png"
const _CONE_SPARK_COUNT := 6
static func spawn_cone(parent: Node, origin: Vector2, facing: Vector2, length: float, half_angle: float, color: Color) -> void:
	var node := Node2D.new()
	node.position = origin
	node.z_index = 12
	node.set_meta("col", color)
	node.set_meta("alpha", 0.7)
	node.set_meta("facing", facing.normalized() if facing.length_squared() > 0.01 else Vector2.RIGHT)
	node.set_meta("len", length)
	node.set_meta("half", half_angle)
	node.draw.connect(func():
		var c: Color = node.get_meta("col")
		c.a = float(node.get_meta("alpha"))
		var f: Vector2 = node.get_meta("facing")
		var l: float = float(node.get_meta("len"))
		var h: float = float(node.get_meta("half"))
		# Build wedge polygon: origin + N points along the arc at distance l.
		var pts := PackedVector2Array()
		pts.append(Vector2.ZERO)
		var steps: int = 18
		for i in steps + 1:
			var t: float = float(i) / float(steps)
			var ang: float = f.angle() - h + t * (2.0 * h)
			pts.append(Vector2.from_angle(ang) * l)
		var cols := PackedColorArray()
		for _i in pts.size():
			cols.append(c)
		node.draw_polygon(pts, cols)
	)
	parent.add_child(node)
	var tween := node.create_tween()
	tween.tween_method(
		func(a: float):
			node.set_meta("alpha", a)
			node.queue_redraw(),
		0.7, 0.0, CONE_LIFETIME
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_callback(node.queue_free)
	# Sprite sparks along the cone — distance-randomised across the
	# beam length, slight angular jitter inside the wedge so they don't
	# line up rigidly. Each spark expands + fades over CONE_LIFETIME.
	if not ResourceLoader.exists(_CONE_SPARK_PATH):
		return
	var spark_tex: Texture2D = load(_CONE_SPARK_PATH)
	var f_norm: Vector2 = facing.normalized() if facing.length_squared() > 0.01 else Vector2.RIGHT
	for i in _CONE_SPARK_COUNT:
		var spr := Sprite2D.new()
		spr.texture = spark_tex
		spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		spr.scale = Vector2(0.55, 0.55)
		spr.modulate = Color(color.r, color.g, color.b, 0.9)
		var t: float = (float(i) + 0.5) / float(_CONE_SPARK_COUNT)
		var ang_jit: float = (randf() - 0.5) * half_angle * 1.4
		var dir: Vector2 = f_norm.rotated(ang_jit)
		spr.position = origin + dir * length * lerpf(0.35, 0.95, t)
		spr.z_index = 13
		parent.add_child(spr)
		var st := spr.create_tween()
		st.tween_property(spr, "scale", Vector2(0.95, 0.95), CONE_LIFETIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		st.parallel().tween_property(spr, "modulate:a", 0.0, CONE_LIFETIME)
		st.tween_callback(spr.queue_free)

# Chain Line2D between successive points. Width pulses out → in.
# Combat-pivot follow-up 2026-06-04: also drops a magic-shimmer sprite
# at each chain node so the strike reads as multi-target arc-impact.
const _CHAIN_NODE_SPRITE := "res://assets/tiles/effects/magic_shimmer.png"
static func spawn_chain(parent: Node, points: Array, color: Color) -> void:
	if points.size() < 2:
		return
	var line := Line2D.new()
	line.z_index = 12
	line.default_color = color
	line.width = 4.5
	line.joint_mode = Line2D.LINE_JOINT_ROUND
	for p in points:
		line.add_point(p)
	parent.add_child(line)
	var tween := line.create_tween()
	tween.tween_property(line, "width", 1.0, CHAIN_LIFETIME).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(line, "modulate:a", 0.0, CHAIN_LIFETIME)
	tween.tween_callback(line.queue_free)
	# Spark sprite at each node so the line has visible impact points.
	if not ResourceLoader.exists(_CHAIN_NODE_SPRITE):
		return
	var spark_tex: Texture2D = load(_CHAIN_NODE_SPRITE)
	for p in points:
		var spr := Sprite2D.new()
		spr.texture = spark_tex
		spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		spr.scale = Vector2(0.6, 0.6)
		spr.modulate = Color(color.r, color.g, color.b, 0.95)
		spr.position = p
		spr.z_index = 13
		parent.add_child(spr)
		var st := spr.create_tween()
		st.tween_property(spr, "scale", Vector2(1.1, 1.1), CHAIN_LIFETIME * 1.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		st.parallel().tween_property(spr, "modulate:a", 0.0, CHAIN_LIFETIME * 1.4)
		st.tween_callback(spr.queue_free)
