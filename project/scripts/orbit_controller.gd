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

const HIT_RADIUS_PX := 16.0
const HIT_INVULN_SEC := 0.3
const ANGULAR_VELOCITY := 4.5  # rad/sec at base speed

var bot_ref: Node = null
var radius_px: float = 48.0
var lifetime: float = 2.5
var damage: int = 14
var elapsed: float = 0.0
var angle_offset: float = 0.0
var axes: Array = []  # [{sprite: Sprite2D, base_angle: float, hits: Dictionary}]

static func spawn_axes(parent: Node, bot: Node, count: int, radius: float, duration: float, dmg: int, tint: Color = Color(1, 1, 1, 1)) -> OrbitController:
	var ctrl := OrbitController.new()
	ctrl.bot_ref = bot
	ctrl.radius_px = radius
	ctrl.lifetime = duration
	ctrl.damage = dmg
	ctrl.z_index = 11
	parent.add_child(ctrl)
	# Build N axe sprites evenly spaced.
	var axe_tex_path := "res://assets/tiles/items/hand_axe.png"
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
		spr.scale = Vector2(0.7, 0.7)
		spr.modulate = resolved_tint
		ctrl.add_child(spr)
		ctrl.axes.append({
			"sprite": spr,
			"base_angle": float(i) * (TAU / float(count)),
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
		spr.rotation = ang + PI * 0.5  # tangent to orbit so axe head faces forward
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
						e.take_damage(damage)
					hits[e.get_instance_id()] = elapsed + HIT_INVULN_SEC
