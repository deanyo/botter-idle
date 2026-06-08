class_name OrbitController
extends Node2D

# Spinning Axes orbit handler. One controller node per cast — owns N
# orbiting child sprites that circle the bot for `lifetime` seconds.
# On contact with an enemy, applies damage with a per-axe-per-enemy
# invuln window (so a single axe doesn't repeat-hit a stationary mob
# every frame).
#
# The controller follows the bot's world position each frame so the
# orbit centers on the bot — even if the bot moves between rooms during
# the spell's duration.

const HIT_RADIUS_PX := 22.0
const HIT_INVULN_SEC := 0.25
# VS-style fast orbit. Was 5.5 rad/sec — felt sluggish. ~7.0 rad/sec
# completes a revolution in <1s so the axes always read as "orbiting"
# even on small radii. 2026-06-05.
const ANGULAR_VELOCITY := 7.0
# Each axe spins about its own center as it orbits — feels like a real
# whirling weapon instead of a frozen sprite tracking a circle.
const SPIN_VELOCITY := 18.0

var bot_ref: Node = null
var radius_px: float = 48.0
var lifetime: float = 2.5
var damage: int = 14
var elapsed: float = 0.0
var angle_offset: float = 0.0
var axes: Array = []  # [{sprite: Sprite2D, base_angle: float, hits: Dictionary}]

static func spawn_axes(parent: Node, bot: Node, count: int, radius: float, duration: float, dmg: int, tint: Color = Color(1, 1, 1, 1), sprite_path: String = "", scale_mult: float = 1.0) -> OrbitController:
	var ctrl := OrbitController.new()
	ctrl.bot_ref = bot
	ctrl.radius_px = radius
	ctrl.lifetime = duration
	ctrl.damage = dmg
	ctrl.z_index = 11
	parent.add_child(ctrl)
	# Build N axe sprites evenly spaced. Caller picks the texture (per
	# flavor) — fall back to a known-good axe in spells/weapons/. The
	# old hardcoded res://assets/tiles/items/hand_axe.png was missing,
	# which made the orbit invisible. 2026-06-05.
	var axe_tex_path: String = sprite_path
	if axe_tex_path == "" or not ResourceLoader.exists(axe_tex_path):
		axe_tex_path = "res://assets/tiles/spells/weapons/hand_axe_new.png"
	if not ResourceLoader.exists(axe_tex_path):
		axe_tex_path = "res://assets/tiles/spells/weapons/axe.png"
	var tex: Texture2D = null
	if ResourceLoader.exists(axe_tex_path):
		tex = load(axe_tex_path)
	# If the caller didn't tint (alpha=1, white), fall back to the Str
	# class color. Otherwise honour the per-item flavor color so a
	# Demonspawn Hellfire reads orange and a Spriggan Forest Spinner
	# reads green.
	var resolved_tint: Color = tint
	if tint == Color(1, 1, 1, 1):
		resolved_tint = UITheme.spell_class_color("str")
	for i in count:
		var spr := Sprite2D.new()
		spr.texture = tex
		spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		# Bigger sprite + a soft glow trailing the orbit so each axe
		# reads as a real spinning weapon instead of a tiny moving icon.
		# Combat-pivot follow-up 2026-06-04.
		# Larger scale — DCSS hand sprites are 32×32, but on the orbit
		# radius (~48px) a 1× sprite reads tiny. 1.5× base; rarity-tier
		# scale_mult bumps Legendary executioner-axes to ~1.95×. 2026-06-05.
		var s: float = 1.5 * scale_mult
		spr.scale = Vector2(s, s)
		spr.modulate = resolved_tint
		ctrl.add_child(spr)
		# Trailing glow Sprite2D — same texture at lower alpha + bigger
		# scale, sitting one frame behind the lead sprite. Cheap to add
		# and gives every axe a visible motion arc.
		var glow := Sprite2D.new()
		glow.texture = tex
		glow.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		var gs: float = 1.85 * scale_mult
		glow.scale = Vector2(gs, gs)
		glow.modulate = Color(resolved_tint.r, resolved_tint.g, resolved_tint.b, 0.35)
		glow.z_index = -1  # behind the lead axe sprite
		ctrl.add_child(glow)
		ctrl.axes.append({
			"sprite": spr,
			"glow": glow,
			"base_angle": float(i) * (TAU / float(count)),
			"prev_angle": float(i) * (TAU / float(count)),
			"hits": {},  # enemy_id → expires_at
		})
	return ctrl

func _process(delta: float) -> void:
	if not is_instance_valid(bot_ref):
		queue_free()
		return
	elapsed += delta
	if elapsed >= lifetime:
		queue_free()
		return
	# Center on bot.
	const TILE_SIZE := 32
	position = bot_ref.position + Vector2(TILE_SIZE * 0.5, TILE_SIZE * 0.5)
	angle_offset += ANGULAR_VELOCITY * delta
	# Place each axe + check for hits.
	var dungeon: Node = get_parent().get_parent() if get_parent() != null else null
	for axe in axes:
		var ang: float = axe.base_angle + angle_offset
		var spr: Sprite2D = axe.sprite
		var pos: Vector2 = Vector2.from_angle(ang) * radius_px
		spr.position = pos
		# Spin each axe about its own center so the visual reads as a
		# whirling weapon, not a sprite tracked along a circle. The
		# blade catches light at every angle. Combat-pivot 2026-06-04.
		spr.rotation = elapsed * SPIN_VELOCITY + axe.base_angle
		# Glow sits a fraction of a radian behind the lead sprite,
		# tracing the orbit arc. Same spin so it reads as a single object.
		var glow: Sprite2D = axe.get("glow", null)
		if glow != null and is_instance_valid(glow):
			var trail_ang: float = ang - 0.18
			glow.position = Vector2.from_angle(trail_ang) * radius_px
			glow.rotation = spr.rotation
		# Hit check — every enemy within HIT_RADIUS_PX of the axe world pos.
		var world_pos: Vector2 = position + pos
		var hits: Dictionary = axe.hits
		# Expire stale invulns.
		for k in hits.keys():
			if elapsed > float(hits[k]):
				hits.erase(k)
		# Resolve enemies via the dungeon scene root (one level up from actor_layer).
		if dungeon != null and "enemies" in dungeon:
			for e in dungeon.enemies:
				if not is_instance_valid(e) or not e.is_alive:
					continue
				if hits.has(e.get_instance_id()):
					continue
				if world_pos.distance_squared_to(e.position) < HIT_RADIUS_PX * HIT_RADIUS_PX:
					if e.has_method("take_damage"):
						# Spinning Axes archetype has no element — physical.
						# Pass bot_ref as the attacker so the defender's
						# tag-driven mitigation (harm/willpower/thorns/etc)
						# evaluates against the bot's weapon tags.
						e.take_damage(damage, bot_ref, "physical")
					hits[e.get_instance_id()] = elapsed + HIT_INVULN_SEC
