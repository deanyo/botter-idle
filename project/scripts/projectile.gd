class_name Projectile
extends Node2D

# Homing projectile node for autocast spells (Phase 2-B: Fireball;
# Phase 3+: chain segments, holy beam wedge).
#
# Lifecycle:
#   spawn(parent, world_pos, target_enemy, damage, speed_px, sprite_path,
#         element, dungeon)
# Self-frees on impact or after `MAX_LIFETIME` if target dies first.
#
# Physics: simple per-frame seek-and-rotate. Each tick, if target alive,
# rotate position toward target.position and step `speed_px * delta`. If
# target died mid-flight, keep flying along last heading until lifetime
# expires (avoids "fireball mid-flight just stops").

const MAX_LIFETIME := 4.0
const HIT_RADIUS_PX := 18.0  # px from sprite center → enemy center

var damage: int = 0
var element: String = ""
var speed_px: float = 320.0
var heading: Vector2 = Vector2.RIGHT
var target: Node = null
var dungeon_ref: Node = null
var lifetime: float = 0.0
var dead: bool = false

@onready var sprite: Sprite2D = $Sprite

static func spawn_fireball(parent: Node, world_pos: Vector2, target_enemy: Node, dmg: int, speed: float, sprite_path: String, element_key: String, dungeon: Node, tint: Color = Color(0, 0, 0, 0)) -> Projectile:
	var p := Projectile.new()
	p.position = world_pos
	p.damage = dmg
	p.element = element_key
	p.speed_px = speed
	p.target = target_enemy
	p.dungeon_ref = dungeon
	# Initial heading toward target so the first frame already moves.
	if is_instance_valid(target_enemy):
		var to_target: Vector2 = target_enemy.position - world_pos
		if to_target.length_squared() > 0.01:
			p.heading = to_target.normalized()
	var spr := Sprite2D.new()
	spr.name = "Sprite"
	if sprite_path != "" and ResourceLoader.exists(sprite_path):
		spr.texture = load(sprite_path)
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	spr.scale = Vector2(0.75, 0.75)  # readable at 24px not 32
	# Per-item flavor tint wins (alpha>0 = caller passed one). Otherwise
	# resolve from element_key (fire→orange, etc.), or fall back to the
	# Int class blue if no element.
	if tint.a > 0.0:
		spr.modulate = Color(tint.r, tint.g, tint.b, 1.0)
	elif element_key != "":
		var fc: Color = UITheme.flavor_color_for([element_key])
		spr.modulate = Color(fc.r, fc.g, fc.b, 1.0) if fc.a > 0.0 else UITheme.spell_class_color("int")
	else:
		spr.modulate = UITheme.spell_class_color("int")
	p.add_child(spr)
	p.z_index = 11  # above actor_layer (10) so projectiles read above mobs
	parent.add_child(p)
	return p

func _process(delta: float) -> void:
	if dead:
		return
	lifetime += delta
	if lifetime >= MAX_LIFETIME:
		_die()
		return
	# Re-orient toward live target each frame for homing behavior. If
	# the target died, keep flying along the last heading.
	if is_instance_valid(target) and target.has_method("get") and target.is_alive:
		var to_target: Vector2 = target.position - position
		if to_target.length_squared() > 0.01:
			heading = to_target.normalized()
	position += heading * speed_px * delta
	if is_instance_valid(sprite):
		sprite.rotation = heading.angle()
	# Hit check — distance to live target.
	if is_instance_valid(target) and target.is_alive:
		if position.distance_squared_to(target.position) < HIT_RADIUS_PX * HIT_RADIUS_PX:
			_impact_on(target)
			return

func _impact_on(enemy: Node) -> void:
	if dead:
		return
	dead = true
	if is_instance_valid(enemy) and enemy.has_method("take_damage"):
		enemy.take_damage(damage)
	# Element-flavored impact burst (existing FX module).
	if dungeon_ref != null and is_instance_valid(dungeon_ref):
		var parent: Node = dungeon_ref.actor_layer if "actor_layer" in dungeon_ref else null
		if parent != null:
			match element:
				"fire":  Effects.fire_flash(parent, position)
				"cold":  Effects.ice_shatter(parent, position)
				_:       Effects.magic_shimmer(parent, position)
	queue_free()

func _die() -> void:
	dead = true
	queue_free()
