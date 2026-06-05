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

# Cone wedge — sprite-driven particle fan from origin out to `length`,
# spanning ±half_angle around `facing`. Was a flat-color polygon plus
# 6 static sparkles, which read as "yellow shape, no detail". Now:
#   - Particles ride a delayed spawn across the lifetime so the cone
#     reads as a "spray" rather than a single burst.
#   - Each particle travels from origin to a randomized point inside
#     the cone over its sub-lifetime, with random rotation + scale.
#   - Particle texture + tint comes from per-flavor presets, so
#     Sandblast = sand sprites in tan/brown and Holy Beam = searing_ray
#     beam motes in white-gold (matches DCSS art for both spells).
#   - The translucent volume polygon stays but uses gradient alpha
#     (bright core at origin → faded at far edge) so it reads as
#     "energy passing through" rather than a flat fill. Drawn UNDER
#     particles so they're the lead visual.
#
# `flavor` is one of "holy" / "sand" / "" (legacy sparkle behavior).
# Callers should pass an explicit flavor — the empty default is just
# for back-compat with any old spawn_cone callsite that hasn't been
# migrated. 2026-06-05.
const _CONE_FLAVOR_PRESETS := {
	"holy": {
		# Searing ray frames — DCSS art for the holy beam.
		"sprites": [
			"res://assets/tiles/spells/effects/searing_ray0.png",
			"res://assets/tiles/spells/effects/searing_ray1.png",
			"res://assets/tiles/spells/effects/searing_ray2.png",
			"res://assets/tiles/spells/effects/searing_ray3.png",
			"res://assets/tiles/spells/effects/searing_ray4.png",
			"res://assets/tiles/spells/effects/searing_ray5.png",
		],
		"count": 14,
		"scale_min": 0.6, "scale_max": 1.0,
		"core_alpha": 0.55,  # bright origin glow alpha
		"rotation_speed_min": -1.5, "rotation_speed_max": 1.5,
		# Tint the sprite with this color — bright white core overrides
		# whatever the caller passed so holy reads bright not muddy. The
		# caller-provided color drives the volume fill instead.
		"sprite_tint_white_pct": 0.55,
	},
	"sand": {
		"sprites": [
			"res://assets/tiles/spells/effects/sandblast0.png",
			"res://assets/tiles/spells/effects/sandblast1.png",
			"res://assets/tiles/spells/effects/sandblast2.png",
			# Cloud-dust frames give the trailing dust haze.
			"res://assets/tiles/spells/effects/cloud_dust0.png",
			"res://assets/tiles/spells/effects/cloud_dust1.png",
			"res://assets/tiles/spells/effects/cloud_dust2.png",
		],
		"count": 18,
		"scale_min": 0.55, "scale_max": 1.1,
		"core_alpha": 0.30,
		"rotation_speed_min": -2.5, "rotation_speed_max": 2.5,
		"sprite_tint_white_pct": 0.10,  # mostly the caller's tan/brown
	},
}

static func spawn_cone(parent: Node, origin: Vector2, facing: Vector2, length: float, half_angle: float, color: Color, flavor: String = "") -> void:
	var f_norm: Vector2 = facing.normalized() if facing.length_squared() > 0.01 else Vector2.RIGHT
	# --- Volume polygon (under-layer) ---
	# Same wedge geometry as before but rendered as a vertex-colored
	# polygon — bright at origin, fading along the length AND the
	# angular edges. Reads as "field of effect" instead of "flat shape".
	var node := Node2D.new()
	node.position = origin
	node.z_index = 12
	node.set_meta("col", color)
	node.set_meta("alpha", 0.6)
	node.set_meta("facing", f_norm)
	node.set_meta("len", length)
	node.set_meta("half", half_angle)
	node.draw.connect(func():
		var c: Color = node.get_meta("col")
		var base_a: float = float(node.get_meta("alpha"))
		var f: Vector2 = node.get_meta("facing")
		var l: float = float(node.get_meta("len"))
		var h: float = float(node.get_meta("half"))
		# Per-slice triangles, drawn one by one. draw_polygon in Godot
		# 4 treats the input as a single closed polygon (triangulating
		# internally), so a flat list of triangle verts won't paint
		# correctly. Per-triangle draw_polygon calls with their own
		# 3-vertex color arrays give us the gradient. 18 slices × 3
		# tris = 54 draw calls per redraw — cheap for a one-shot.
		var steps: int = 18
		for i in steps:
			var t0: float = float(i) / float(steps)
			var t1: float = float(i + 1) / float(steps)
			var a0: float = f.angle() - h + t0 * (2.0 * h)
			var a1: float = f.angle() - h + t1 * (2.0 * h)
			# Edge falloff — alpha lower near the angular edges.
			var edge0: float = 1.0 - abs(t0 * 2.0 - 1.0)
			var edge1: float = 1.0 - abs(t1 * 2.0 - 1.0)
			edge0 = lerpf(0.35, 1.0, edge0)
			edge1 = lerpf(0.35, 1.0, edge1)
			var p_origin: Vector2 = Vector2.ZERO
			var p_mid0: Vector2 = Vector2.from_angle(a0) * (l * 0.5)
			var p_mid1: Vector2 = Vector2.from_angle(a1) * (l * 0.5)
			var p_far0: Vector2 = Vector2.from_angle(a0) * l
			var p_far1: Vector2 = Vector2.from_angle(a1) * l
			var c_origin: Color = c; c_origin.a = base_a * 0.95
			var c_mid0: Color = c;  c_mid0.a  = base_a * 0.55 * edge0
			var c_mid1: Color = c;  c_mid1.a  = base_a * 0.55 * edge1
			var c_far0: Color = c;  c_far0.a  = base_a * 0.10 * edge0
			var c_far1: Color = c;  c_far1.a  = base_a * 0.10 * edge1
			# tri 1: origin → mid0 → mid1
			node.draw_polygon(PackedVector2Array([p_origin, p_mid0, p_mid1]),
				PackedColorArray([c_origin, c_mid0, c_mid1]))
			# tri 2: mid0 → far0 → mid1
			node.draw_polygon(PackedVector2Array([p_mid0, p_far0, p_mid1]),
				PackedColorArray([c_mid0, c_far0, c_mid1]))
			# tri 3: mid1 → far0 → far1
			node.draw_polygon(PackedVector2Array([p_mid1, p_far0, p_far1]),
				PackedColorArray([c_mid1, c_far0, c_far1]))
	)
	parent.add_child(node)
	var tween := node.create_tween()
	tween.tween_method(
		func(a: float):
			node.set_meta("alpha", a)
			node.queue_redraw(),
		0.6, 0.0, CONE_LIFETIME
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_callback(node.queue_free)

	# --- Particle fan (top layer) ---
	# Resolve preset. Empty flavor falls back to legacy gold-sparkle look.
	var preset: Dictionary = _CONE_FLAVOR_PRESETS.get(flavor, {})
	var sprite_paths: Array = preset.get("sprites", ["res://assets/tiles/effects/gold_sparkle.png"])
	var count: int = int(preset.get("count", 6))
	var scale_min: float = float(preset.get("scale_min", 0.55))
	var scale_max: float = float(preset.get("scale_max", 0.95))
	var rot_speed_min: float = float(preset.get("rotation_speed_min", 0.0))
	var rot_speed_max: float = float(preset.get("rotation_speed_max", 0.0))
	var white_mix: float = float(preset.get("sprite_tint_white_pct", 0.0))
	# Pre-load every sprite that exists (skip silently when missing so
	# the cone still renders if assets get reorganized later).
	var loaded_textures: Array = []
	for p in sprite_paths:
		if ResourceLoader.exists(p):
			loaded_textures.append(load(p))
	if loaded_textures.is_empty():
		return
	var sprite_tint := Color(
		lerpf(color.r, 1.0, white_mix),
		lerpf(color.g, 1.0, white_mix),
		lerpf(color.b, 1.0, white_mix),
		1.0
	)
	for i in count:
		var spr := Sprite2D.new()
		spr.texture = loaded_textures[randi() % loaded_textures.size()]
		spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		spr.z_index = 13
		# Each particle picks a target inside the cone — angular
		# jitter inside ±half_angle, distance jitter in [0.4, 1.0]×length.
		var ang_jit: float = (randf() * 2.0 - 1.0) * half_angle * 0.95
		var travel_dir: Vector2 = f_norm.rotated(ang_jit)
		var travel_dist: float = lerpf(0.40, 1.0, randf()) * length
		var target_pos: Vector2 = origin + travel_dir * travel_dist
		spr.position = origin
		var s0: float = lerpf(scale_min, scale_max, randf())
		spr.scale = Vector2(s0, s0)
		spr.rotation = randf() * TAU
		spr.modulate = Color(sprite_tint.r, sprite_tint.g, sprite_tint.b, 0.0)
		parent.add_child(spr)
		# Per-particle stagger — particles spawn across the first 60%
		# of the cone's lifetime so the cone reads as a "spray", not a
		# single burst. Each particle's own life = remaining time after
		# spawn.
		var spawn_delay: float = (float(i) / float(count)) * (CONE_LIFETIME * 0.45)
		var per_life: float = CONE_LIFETIME - spawn_delay
		var rot_speed: float = lerpf(rot_speed_min, rot_speed_max, randf())
		var t := spr.create_tween()
		t.tween_interval(spawn_delay)
		# Fade in fast (15% of per_life) then travel + fade out for the rest.
		t.tween_property(spr, "modulate:a", 0.95, per_life * 0.15)
		t.parallel().tween_property(spr, "position", target_pos, per_life).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		t.parallel().tween_property(spr, "scale", Vector2(s0 * 1.4, s0 * 1.4), per_life).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		# Rotation drift — apply via a tween_method so it accumulates.
		t.parallel().tween_method(
			func(rad: float):
				if is_instance_valid(spr):
					spr.rotation += rad,
			0.0, rot_speed * per_life, per_life
		)
		# Fade out across the back half of per_life. Add as a separate
		# tween chained after the fade-in so it runs in series, not
		# parallel-with-fade-in.
		t.tween_property(spr, "modulate:a", 0.0, per_life * 0.85).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		t.tween_callback(spr.queue_free)

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
