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
# Caster — passed as the `attacker` arg to take_damage so the defender's
# resist / willpower / harm / earth / thorns / crystal tag-rolls evaluate
# against the bot's weapon tags (atk_tags inside actor.resolve_swing).
# Set by spawn_fireball; falls back to lifesteal_target on Drain
# projectiles that omit it for back-compat.
var caster: Node = null

# 2026-06-04 spell expansion — pierce + lifesteal + buff hooks. Iron
# Shot sets piercing=true so the projectile keeps flying after impact;
# Vampiric Drain sets lifesteal_pct + lifesteal_target so each hit
# heals the caster.
var piercing: bool = false
var pierce_falloff: float = 1.0  # damage multiplier per pierce; 0.75 = 25% drop per hit
var pierce_count: int = 0  # how many enemies already hit, used to dim damage
var pierce_hit_set: Dictionary = {}  # instance_id → true; same-target double-hit guard
var pierce_apply_status: String = ""  # status id to apply on each pierce hit (e.g. "slowed")
var pierce_apply_duration: float = 0.0
var lifesteal_pct: float = 0.0
var lifesteal_target: Node = null  # bot-side healer; usually the bot
var lifesteal_buff_bot: bool = false  # Ravenous affix — apply hasted on hit

# S10 — bounce mode. Used by Bone Spear (max 4 bounces, 30% damage loss
# per bounce) and Echo Lance (max 1 bounce, 0% loss). On impact:
# instead of free-on-hit, pick the nearest unhit live enemy within
# `bounce_seek_radius_px` and re-target. After `bounce_max` bounces,
# the projectile's next impact frees as normal.
var bounce_mode: bool = false
var bounce_max: int = 0
var bounce_count: int = 0
var bounce_falloff: float = 0.7  # damage multiplier per bounce
var bounce_seek_radius_px: float = float(32 * 4)
var bounce_hit_set: Dictionary = {}

@onready var sprite: Sprite2D = $Sprite

static func spawn_fireball(parent: Node, world_pos: Vector2, target_enemy: Node, dmg: int, speed: float, sprite_path: String, element_key: String, dungeon: Node, tint: Color = Color(0, 0, 0, 0), scale_mult: float = 1.0, caster: Node = null) -> Projectile:
	var p := Projectile.new()
	p.position = world_pos
	p.damage = dmg
	p.element = element_key
	p.speed_px = speed
	p.target = target_enemy
	p.dungeon_ref = dungeon
	p.caster = caster
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
	# Base 0.75× (24px tile read); scale_mult bumps it to ~1.0× at
	# legendary so a Comet Tome's projectile is visibly bigger than a
	# Common Fireball Scroll's. 2026-06-05.
	var base_scale: float = 0.75 * scale_mult
	spr.scale = Vector2(base_scale, base_scale)
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
	# Hit check. Piercing projectiles scan ALL live enemies near the
	# current position so a slow iron shot moving through a pack hits
	# every body in its path. Non-piercing projectiles just check the
	# original target.
	if piercing and dungeon_ref != null and is_instance_valid(dungeon_ref) and "enemies" in dungeon_ref:
		for e in dungeon_ref.enemies:
			if not is_instance_valid(e) or not e.is_alive:
				continue
			if pierce_hit_set.has(e.get_instance_id()):
				continue
			if position.distance_squared_to(e.position) < HIT_RADIUS_PX * HIT_RADIUS_PX:
				pierce_hit_set[e.get_instance_id()] = true
				_pierce_hit(e)
		return
	if is_instance_valid(target) and target.is_alive:
		if position.distance_squared_to(target.position) < HIT_RADIUS_PX * HIT_RADIUS_PX:
			_impact_on(target)
			return

func _impact_on(enemy: Node) -> void:
	if dead:
		return
	# S10 — bounce mode: bone_spear / echo_lance handle impact differently.
	# Instead of freeing on hit, deal damage, mark target as hit, find the
	# nearest unhit live enemy within radius, and re-target. After
	# bounce_max bounces, the next impact frees normally.
	if bounce_mode and is_instance_valid(enemy) and enemy.has_method("take_damage") and bounce_count < bounce_max:
		var dt_b: String = SpellData.damage_type_for_element(element)
		var src_b: Node = caster if caster != null else lifesteal_target
		enemy.take_damage(damage, src_b, dt_b)
		bounce_hit_set[enemy.get_instance_id()] = true
		bounce_count += 1
		damage = maxi(1, int(round(float(damage) * bounce_falloff)))
		# Find next target — closest unhit live enemy within bounce_seek_radius.
		var next_target: Node = null
		var best_d: float = INF
		if dungeon_ref != null and is_instance_valid(dungeon_ref) and "enemies" in dungeon_ref:
			for e in dungeon_ref.enemies:
				if not is_instance_valid(e) or not e.is_alive:
					continue
				if bounce_hit_set.has(e.get_instance_id()):
					continue
				var d_sq: float = position.distance_squared_to(e.position)
				if d_sq < best_d and d_sq <= bounce_seek_radius_px * bounce_seek_radius_px:
					best_d = d_sq
					next_target = e
		if next_target != null:
			target = next_target
			var to_t: Vector2 = next_target.position - position
			if to_t.length_squared() > 0.01:
				heading = to_t.normalized()
			# Visual: little spark to mark the bounce.
			if dungeon_ref != null and is_instance_valid(dungeon_ref) and "actor_layer" in dungeon_ref:
				Effects.magic_shimmer(dungeon_ref.actor_layer, position)
			return  # don't free; keep flying
		# No more targets — free as normal.
		queue_free()
		dead = true
		return
	dead = true
	var dealt: int = 0
	if is_instance_valid(enemy) and enemy.has_method("take_damage"):
		# Pipe element + attacker so resists/willpower/harm/thorns evaluate
		# correctly. SpellData maps element keys (fire/cold/thunderous/holy
		# /poison/dark) to damage_type keys; thunderous→lightning so the
		# resistance lookup hits the right bucket. caster falls back to
		# lifesteal_target on Drain projectiles that don't set caster
		# explicitly (back-compat).
		var dt: String = SpellData.damage_type_for_element(element)
		var src: Node = caster if caster != null else lifesteal_target
		dealt = enemy.take_damage(damage, src, dt)
	# Lifesteal — heal the bot (lifesteal_target) by a % of dealt damage
	# regardless of the bot's gear lifesteal_pct. Drain spell wires this.
	if lifesteal_pct > 0.0 and is_instance_valid(lifesteal_target) and dealt > 0:
		var heal: int = int(round(float(dealt) * lifesteal_pct / 100.0))
		if heal > 0 and "hp" in lifesteal_target and "max_hp" in lifesteal_target:
			lifesteal_target.hp = mini(lifesteal_target.max_hp, lifesteal_target.hp + heal)
			if lifesteal_target.has_method("_update_hp_bar"):
				lifesteal_target._update_hp_bar()
		if lifesteal_buff_bot and lifesteal_target.has_method("add_status"):
			lifesteal_target.add_status("hasted", 4.0)
	# Element-flavored impact burst (existing FX module).
	if dungeon_ref != null and is_instance_valid(dungeon_ref):
		var parent: Node = dungeon_ref.actor_layer if "actor_layer" in dungeon_ref else null
		if parent != null:
			match element:
				"fire":  Effects.fire_flash(parent, position)
				"cold":  Effects.ice_shatter(parent, position)
				_:       Effects.magic_shimmer(parent, position)
	queue_free()

# Piercing impact — same damage path as _impact_on but does NOT free
# the projectile. Damage decays with pierce_count so the 5th body hit
# takes 0.75⁴ × damage. Used by Iron Shot.
func _pierce_hit(enemy: Node) -> void:
	if not is_instance_valid(enemy) or not enemy.has_method("take_damage"):
		return
	var dmg_now: float = float(damage) * pow(pierce_falloff, float(pierce_count))
	# Pierce hits also need to evaluate resists and route thorns/crystal
	# back to the caster — pass element + attacker like _impact_on does.
	var dt: String = SpellData.damage_type_for_element(element)
	var src: Node = caster if caster != null else lifesteal_target
	enemy.take_damage(maxi(1, int(round(dmg_now))), src, dt)
	pierce_count += 1
	if pierce_apply_status != "" and pierce_apply_duration > 0.0 and enemy.has_method("add_status"):
		enemy.add_status(pierce_apply_status, pierce_apply_duration)
	# Element burst on each body so the hit reads visually.
	if dungeon_ref != null and is_instance_valid(dungeon_ref):
		var parent: Node = dungeon_ref.actor_layer if "actor_layer" in dungeon_ref else null
		if parent != null:
			Effects.magic_shimmer(parent, enemy.position)

func _die() -> void:
	dead = true
	queue_free()
