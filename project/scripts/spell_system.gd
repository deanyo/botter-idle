class_name SpellSystem
extends RefCounted

# Autocast spells — combat pivot. Each equipped spell-item ticks down a
# cooldown, fires when ≤0, resets to base_cd × (1 - cdr_pct/100).
#
# This module is the orchestrator. Per-spell BEHAVIOR (homing fireball
# vs orbiting axes vs cone) lives in SpellData + the projectile / orbit /
# AoE node scripts. SpellSystem is just bookkeeping: which slots are
# armed, what their remaining cooldown is, and dispatching the fire on
# tick.
#
# Phase 1 (this file's first ship) is a STUB — process_tick does nothing
# yet. Real firing arrives Phase 2 with Fireball.
#
# State on the bot:
#   bot.spell_cooldowns : Dictionary[String, float]
#     keyed by slot id ("spell1".."spell5"); value = seconds until next
#     fire. Initialized to 0 on first tick of a freshly-loaded run so the
#     first cast happens after one base_cd.
#
# Why a static class instead of a node: the spell tick needs no scene-
# tree presence — it reads bot/dungeon state and tells dungeon to spawn
# projectiles. Keeping it stateless lets save/load shape stay simple.

const SPELL_SLOTS := ["spell1", "spell2", "spell3", "spell4", "spell5"]

# Initialize cooldown bookkeeping on a fresh run. Called from dungeon
# floor-build so each new floor / new run starts spells "armed" for an
# initial cast roughly base_cd from now (small jitter prevents the
# first fire on every spell from happening on the same frame, which
# would look like a single screen-flash burst).
static func init_run(bot: Node, items_db: Dictionary) -> void:
	_fire_count = 0
	_fire_by_arch = {}
	if bot == null:
		return
	if not "spell_cooldowns" in bot:
		return
	var cds: Dictionary = {}
	for i in SPELL_SLOTS.size():
		var slot: String = SPELL_SLOTS[i]
		var inst: Variant = bot.equipped.get(slot, null)
		if typeof(inst) != TYPE_DICTIONARY:
			cds[slot] = 0.0
			continue
		var base_id: String = String(inst.get("base_id", ""))
		if not items_db.has(base_id):
			cds[slot] = 0.0
			continue
		var base_cd: float = _base_cooldown_for(items_db[base_id])
		# Stagger initial cast — i * 0.15s nudges so 5 slot fires don't
		# all collapse to the same frame on first cast.
		cds[slot] = max(0.05, base_cd * 0.5 + i * 0.15)
	bot.spell_cooldowns = cds

# Per-frame tick. Decrement each slot's cooldown by delta; when ≤0,
# dispatch the appropriate fire function and reset cooldown.
static func process_tick(bot: Node, dungeon: Node, delta: float, items_db: Dictionary) -> void:
	if bot == null or not bot.is_alive:
		return
	if not "spell_cooldowns" in bot:
		return
	var cds: Dictionary = bot.spell_cooldowns
	for slot in SPELL_SLOTS:
		var inst: Variant = bot.equipped.get(slot, null)
		if typeof(inst) != TYPE_DICTIONARY:
			continue
		var base_id: String = String(inst.get("base_id", ""))
		if not items_db.has(base_id):
			continue
		var t: float = float(cds.get(slot, 0.0)) - delta
		if t <= 0.0:
			var item: Dictionary = items_db[base_id]
			# Merge per-instance archetype affix flags into the item view
			# so dispatch can read e.g. spell_dart_split / spell_drain_buff
			# off the same dict regardless of whether the flag came from
			# implicit_affixes or a rolled affix. 2026-06-04 spell expansion.
			var view: Dictionary = item.duplicate()
			_fold_inst_affixes_into(view, inst)
			_dispatch_fire(bot, dungeon, view)
			t = SpellData.compute_cooldown(bot, item)
		cds[slot] = t
	bot.spell_cooldowns = cds

# Fold an instance's archetype-flag affixes into a view dict so the
# fire functions can read flags via item.get("spell_<flag>", false).
# Implicit affixes from item.implicit_affixes resolve via the affix
# def's `stat` field; rolled affixes from inst.affixes also write to
# that stat. Either way the boolean ends up under view[stat] = true.
static func _fold_inst_affixes_into(view: Dictionary, inst: Dictionary) -> void:
	# Implicit affix ids declared on the items_db def itself.
	for aid in view.get("implicit_affixes", []):
		var def: Dictionary = AffixSystem.get_affix_def(String(aid))
		if def.is_empty():
			continue
		var stat: String = String(def.get("stat", ""))
		if stat != "":
			view[stat] = true
	# Rolled affixes on the instance — same stat → true mapping.
	if inst != null and typeof(inst) == TYPE_DICTIONARY:
		for entry in inst.get("affixes", []):
			if typeof(entry) != TYPE_DICTIONARY:
				continue
			var aid2: String = String(entry.get("id", ""))
			var def2: Dictionary = AffixSystem.get_affix_def(aid2)
			if def2.is_empty():
				continue
			var stat2: String = String(def2.get("stat", ""))
			if stat2 != "":
				view[stat2] = true

# Resolve effective cooldown for a spell item. Read by init_run for
# the initial stagger; the live tick uses SpellData.compute_cooldown
# directly so CDR is folded in.
static func _base_cooldown_for(item: Dictionary) -> float:
	var arch: Dictionary = SpellData.archetype_def(String(item.get("base_type", "")))
	return float(item.get("spell_cooldown", arch.get("cooldown", 3.0)))

# Module-level fire counter so /grind and /screenshot can verify spells
# are actually casting (impossible to see in headless mode without it).
# Reset on init_run. Also tracks per-archetype counts for the grind log.
static var _fire_count: int = 0
static var _fire_by_arch: Dictionary = {}

static func get_fire_count() -> int:
	return _fire_count

static func get_fire_by_arch() -> Dictionary:
	return _fire_by_arch.duplicate()

# Dispatch by archetype. Each archetype has its own fire function with
# a unified signature (bot, dungeon, item) — keeps the tick-loop body
# simple and lets Phase 3 add more archetypes by extending the match.
static func _dispatch_fire(bot: Node, dungeon: Node, item: Dictionary) -> void:
	var base_type: String = String(item.get("base_type", ""))
	var fired: bool = false
	match base_type:
		"spell_fireball":
			fired = _fire_fireball(bot, dungeon, item)
		"spell_frost_nova":
			fired = _fire_frost_nova(bot, dungeon, item)
		"spell_chain_lightning":
			fired = _fire_chain_lightning(bot, dungeon, item)
		"spell_holy_beam":
			fired = _fire_holy_beam(bot, dungeon, item)
		"spell_axes":
			fired = _fire_axes(bot, dungeon, item)
		"spell_magic_dart":
			fired = _fire_magic_dart(bot, dungeon, item)
		"spell_iron_shot":
			fired = _fire_iron_shot(bot, dungeon, item)
		"spell_sandblast":
			fired = _fire_sandblast(bot, dungeon, item)
		"spell_drain":
			fired = _fire_drain(bot, dungeon, item)
		"spell_shatter":
			fired = _fire_shatter(bot, dungeon, item)
	if fired:
		_fire_count += 1
		_fire_by_arch[base_type] = int(_fire_by_arch.get(base_type, 0)) + 1

# Fire a Fireball: one (or N with proj_count) homing projectile per cast,
# each picks the nearest live enemy and seeks. If no enemies in range,
# the cast is wasted (cooldown still resets — intentional, prevents
# infinite-charge cheese while exploring empty corridors).
static func _fire_fireball(bot: Node, dungeon: Node, item: Dictionary) -> bool:
	var arch: Dictionary = SpellData.archetype_def("spell_fireball")
	if arch.is_empty() or not is_instance_valid(bot) or dungeon == null:
		return false
	var range_cells: int = int(arch.get("range_cells", 8))
	# Build candidate target list — enemies within range_cells of the bot.
	var candidates: Array = []
	if "enemies" in dungeon:
		for e in dungeon.enemies:
			if not is_instance_valid(e) or not e.is_alive:
				continue
			var dx: int = abs(e.cell.x - bot.cell.x)
			var dy: int = abs(e.cell.y - bot.cell.y)
			var d: int = maxi(dx, dy)
			if d <= range_cells:
				candidates.append({"e": e, "d": d})
	if candidates.is_empty():
		return false
	# Sort by distance for deterministic per-projectile assignment when
	# proj_count > 1 (closest first; reuse if more projectiles than
	# enemies so they all do something instead of fizzling).
	candidates.sort_custom(func(a, b): return a.d < b.d)
	var proj_count: int = SpellData.compute_proj_count(bot, item)
	var damage: int = SpellData.compute_damage(bot, item)
	var sprite_path: String = String(arch.get("projectile", ""))
	var element: String = String(arch.get("element", ""))
	var base_speed: float = float(arch.get("projectile_speed", 320.0))
	var speed: float = base_speed * (1.0 + float(bot.spell_proj_speed_pct) / 100.0)
	var tint: Color = _visual_color_for_item(item, element if element != "" else "fire")
	# Spawn from bot center.
	var origin: Vector2 = bot.position + Vector2(C.TILE_SIZE * 0.5, C.TILE_SIZE * 0.5)
	for i in proj_count:
		var target: Node = candidates[i % candidates.size()].e
		Projectile.spawn_fireball(dungeon.actor_layer, origin, target, damage, speed, sprite_path, element, dungeon, tint)
	return true

# Frost Nova — radial AoE pulse around the bot. Hits all enemies in
# range, applies damage + slow status, no projectile (instant). Visual:
# expanding cyan ring via SpellAoe. proj_count adds extra ring pulses
# (one big + N smaller). area_pct widens radius.
static func _fire_frost_nova(bot: Node, dungeon: Node, item: Dictionary) -> bool:
	var arch: Dictionary = SpellData.archetype_def("spell_frost_nova")
	if arch.is_empty() or not is_instance_valid(bot) or dungeon == null:
		return false
	var range_cells: int = int(arch.get("range_cells", 3))
	var area_mult: float = 1.0 + float(bot.spell_area_pct) / 100.0
	var radius_cells: int = max(1, int(round(float(range_cells) * area_mult)))
	var enemies: Array = _enemies_in_range(bot, dungeon, radius_cells)
	if enemies.is_empty():
		return false
	var damage: int = SpellData.compute_damage(bot, item)
	var slow_dur: float = 2.0 * (1.0 + float(bot.spell_duration_pct) / 100.0)
	for entry in enemies:
		var e: Node = entry.e
		if is_instance_valid(e) and e.has_method("take_damage"):
			e.take_damage(damage)
			if e.has_method("add_status"):
				e.add_status("slowed", slow_dur)
	# Visual: expanding ring centered on bot. Color follows the EQUIPPED
	# item's flavor tags so a Naga Frost Nova reads cyan and an Octopode
	# Ink Burst reads purple — same archetype, themed visual.
	var origin: Vector2 = bot.position + Vector2(C.TILE_SIZE * 0.5, C.TILE_SIZE * 0.5)
	SpellAoe.spawn_ring(dungeon.actor_layer, origin, float(radius_cells) * float(C.TILE_SIZE), _visual_color_for_item(item, "cold"))
	return true

# Chain Lightning — fires a bolt at the nearest enemy, then jumps to
# next-nearest unhit enemies up to N times, each with damage falloff.
# proj_count = +N additional jumps. range_cells gates the initial pick.
# Visual: Line2D segments between target chain.
static func _fire_chain_lightning(bot: Node, dungeon: Node, item: Dictionary) -> bool:
	var arch: Dictionary = SpellData.archetype_def("spell_chain_lightning")
	if arch.is_empty() or not is_instance_valid(bot) or dungeon == null:
		return false
	var range_cells: int = int(arch.get("range_cells", 7))
	var initial: Array = _enemies_in_range(bot, dungeon, range_cells)
	if initial.is_empty():
		return false
	initial.sort_custom(func(a, b): return a.d < b.d)
	var damage: int = SpellData.compute_damage(bot, item)
	var jump_count: int = 2 + int(bot.spell_proj_bonus)  # base 3 hits (1 + 2 jumps)
	var hit_set: Dictionary = {}
	var chain_points: Array = [bot.position + Vector2(C.TILE_SIZE * 0.5, C.TILE_SIZE * 0.5)]
	var current: Node = initial[0].e
	var dmg: float = float(damage)
	for jump_i in jump_count:
		if not is_instance_valid(current) or not current.is_alive:
			break
		current.take_damage(int(round(dmg)))
		hit_set[current.get_instance_id()] = true
		chain_points.append(current.position + Vector2(C.TILE_SIZE * 0.5, C.TILE_SIZE * 0.5))
		# Next target — closest live enemy not yet hit, within ~4 cells of current.
		var next_target: Node = null
		var best_d: float = INF
		for e in dungeon.enemies:
			if not is_instance_valid(e) or not e.is_alive:
				continue
			if hit_set.has(e.get_instance_id()):
				continue
			var d: float = current.position.distance_to(e.position)
			if d < best_d and d < float(C.TILE_SIZE) * 4.0:
				best_d = d
				next_target = e
		if next_target == null:
			break
		current = next_target
		dmg *= 0.7  # 30% falloff per jump
	# Visual: connect all chain points with a line. Color follows the
	# item flavor (vampire Blood Arc → red, deep elf Magic Missile →
	# arcane purple, etc.) — same archetype, themed visual.
	if chain_points.size() >= 2:
		SpellAoe.spawn_chain(dungeon.actor_layer, chain_points, _visual_color_for_item(item, "thunderous"))
	return true

# Holy Beam — cone in bot's facing direction. Hits all enemies in the
# cone (cells within range_cells AND within ±60° of facing). area_pct
# widens the cone angle. Damage applies once per enemy.
static func _fire_holy_beam(bot: Node, dungeon: Node, item: Dictionary) -> bool:
	var arch: Dictionary = SpellData.archetype_def("spell_holy_beam")
	if arch.is_empty() or not is_instance_valid(bot) or dungeon == null:
		return false
	var range_cells: int = int(arch.get("range_cells", 4))
	# Determine bot facing — use last move heading or, failing that,
	# nearest enemy direction so the beam always hits something.
	var origin: Vector2 = bot.position + Vector2(C.TILE_SIZE * 0.5, C.TILE_SIZE * 0.5)
	var facing: Vector2 = Vector2.RIGHT
	if "_facing_x" in bot:
		facing = Vector2(float(bot._facing_x), 0.0)
		if facing.length_squared() < 0.01:
			facing = Vector2.RIGHT
	# If a nearest enemy exists, override facing toward them.
	var nearest: Node = null
	var nearest_d: float = INF
	for e in dungeon.enemies:
		if not is_instance_valid(e) or not e.is_alive:
			continue
		var d: float = origin.distance_to(e.position)
		if d < nearest_d:
			nearest_d = d
			nearest = e
	if nearest != null:
		var dir: Vector2 = nearest.position - origin
		if dir.length_squared() > 0.01:
			facing = dir.normalized()
	var cone_half_angle: float = deg_to_rad(60.0) * (1.0 + float(bot.spell_area_pct) / 100.0)
	var max_dist: float = float(range_cells) * float(C.TILE_SIZE)
	var damage: int = SpellData.compute_damage(bot, item)
	var hits: int = 0
	for e in dungeon.enemies:
		if not is_instance_valid(e) or not e.is_alive:
			continue
		var to_e: Vector2 = e.position - origin
		var dist: float = to_e.length()
		if dist > max_dist or dist < 4.0:
			continue
		var ang: float = abs(to_e.angle_to(facing))
		if ang <= cone_half_angle:
			e.take_damage(damage)
			hits += 1
	if hits == 0:
		return false
	SpellAoe.spawn_cone(dungeon.actor_layer, origin, facing, max_dist, cone_half_angle, _visual_color_for_item(item, "holy"))
	return true

# Spinning Axes — spawns N orbiting axe sprites that circle the bot for
# ~2.5s × duration_pct. On contact with an enemy, hits + brief invuln
# window per-axe-per-enemy (so a single axe doesn't repeat-hit a stationary
# mob every frame). proj_count = additional orbiters.
static func _fire_axes(bot: Node, dungeon: Node, item: Dictionary) -> bool:
	var arch: Dictionary = SpellData.archetype_def("spell_axes")
	if arch.is_empty() or not is_instance_valid(bot) or dungeon == null:
		return false
	var n: int = SpellData.compute_proj_count(bot, item) + 1  # base 2 axes (proj_count=1 + base 1)
	var damage: int = SpellData.compute_damage(bot, item)
	var duration: float = 2.5 * (1.0 + float(bot.spell_duration_pct) / 100.0)
	var radius_px: float = 48.0 * (1.0 + float(bot.spell_area_pct) / 100.0)
	OrbitController.spawn_axes(dungeon.actor_layer, bot, n, radius_px, duration, damage, _visual_color_for_item(item, "brutal"))
	return true

# --- 2026-06-04 expansion archetypes -------------------------------

# Magic Dart — single fast homing projectile at very short CD. Cheap,
# constant damage feed. Reuses Projectile.spawn_fireball with the
# magic_dart sprite + arcane tint. Splintering Volley (archetype affix
# `spell_dart_split`) spawns two slower side-darts at hit.
static func _fire_magic_dart(bot: Node, dungeon: Node, item: Dictionary) -> bool:
	var arch: Dictionary = SpellData.archetype_def("spell_magic_dart")
	if arch.is_empty() or not is_instance_valid(bot) or dungeon == null:
		return false
	var range_cells: int = int(arch.get("range_cells", 9))
	var candidates: Array = _enemies_in_range(bot, dungeon, range_cells)
	if candidates.is_empty():
		return false
	candidates.sort_custom(func(a, b): return a.d < b.d)
	var damage: int = SpellData.compute_damage(bot, item)
	var sprite_path: String = String(arch.get("projectile", ""))
	var element: String = String(arch.get("element", ""))
	var base_speed: float = float(arch.get("projectile_speed", 420.0))
	var speed: float = base_speed * (1.0 + float(bot.spell_proj_speed_pct) / 100.0)
	var tint: Color = _visual_color_for_item(item, "arcane")
	var origin: Vector2 = bot.position + Vector2(C.TILE_SIZE * 0.5, C.TILE_SIZE * 0.5)
	var proj_count: int = SpellData.compute_proj_count(bot, item)
	# Splintering Volley affix — adds 2 extra side-darts at half damage
	# fanned ±25° from the main shot. Splinterfang unique carries this
	# implicitly. Spell expansion 2026-06-04.
	var split: bool = bool(item.get("spell_dart_split", false))
	for i in proj_count:
		var target: Node = candidates[i % candidates.size()].e
		Projectile.spawn_fireball(dungeon.actor_layer, origin, target, damage, speed, sprite_path, element, dungeon, tint)
		if split and is_instance_valid(target):
			# Side darts target enemies at ±1 in the candidate list when
			# they exist; otherwise fall back to the same target so the
			# sprites at least visualise the splinter.
			var alt_a: Node = candidates[(i + 1) % candidates.size()].e
			var alt_b: Node = candidates[(i + candidates.size() - 1) % candidates.size()].e
			Projectile.spawn_fireball(dungeon.actor_layer, origin, alt_a, int(damage * 0.5), speed, sprite_path, element, dungeon, tint)
			Projectile.spawn_fireball(dungeon.actor_layer, origin, alt_b, int(damage * 0.5), speed, sprite_path, element, dungeon, tint)
	return true

# Iron Shot — slow heavy projectile that hits every enemy along its
# travel line until lifetime expires. Pierces. Damage drops 25% per
# enemy beyond the first so a wall of mobs absorbs increasingly less.
# Implementation: spawn an iron_shot projectile aimed at the nearest
# enemy, but mark it as "piercing" so on impact it does NOT free —
# instead it tags the enemy as already-hit and keeps flying. Only the
# Projectile class needs that tag; here we pass through a special
# damage path via the dungeon-side actor_layer hit loop.
static func _fire_iron_shot(bot: Node, dungeon: Node, item: Dictionary) -> bool:
	var arch: Dictionary = SpellData.archetype_def("spell_iron_shot")
	if arch.is_empty() or not is_instance_valid(bot) or dungeon == null:
		return false
	var range_cells: int = int(arch.get("range_cells", 9))
	var candidates: Array = _enemies_in_range(bot, dungeon, range_cells)
	if candidates.is_empty():
		return false
	candidates.sort_custom(func(a, b): return a.d < b.d)
	var damage: int = SpellData.compute_damage(bot, item)
	var sprite_path: String = String(arch.get("projectile", ""))
	var element: String = String(arch.get("element", ""))
	var base_speed: float = float(arch.get("projectile_speed", 220.0))
	var speed: float = base_speed * (1.0 + float(bot.spell_proj_speed_pct) / 100.0)
	var tint: Color = _visual_color_for_item(item, "earth")
	var origin: Vector2 = bot.position + Vector2(C.TILE_SIZE * 0.5, C.TILE_SIZE * 0.5)
	var target: Node = candidates[0].e
	var p: Projectile = Projectile.spawn_fireball(dungeon.actor_layer, origin, target, damage, speed, sprite_path, element, dungeon, tint)
	if p != null:
		p.piercing = true
		p.pierce_falloff = 0.75
		# Earthbreaker affix — pierce hits also slow the target for 1.5s.
		# Carried implicitly on the Ironcrash unique. Spell expansion 2026-06-04.
		if bool(item.get("spell_iron_dust", false)):
			p.pierce_apply_status = "slowed"
			p.pierce_apply_duration = 1.5
	return true

# Sandblast — short cone in bot facing. Same shape as holy_beam but
# tighter (range 3, half-angle 45°). Earth/physical so no element_pct
# scaling but raw damage is higher per cast.
static func _fire_sandblast(bot: Node, dungeon: Node, item: Dictionary) -> bool:
	var arch: Dictionary = SpellData.archetype_def("spell_sandblast")
	if arch.is_empty() or not is_instance_valid(bot) or dungeon == null:
		return false
	var range_cells: int = int(arch.get("range_cells", 3))
	var origin: Vector2 = bot.position + Vector2(C.TILE_SIZE * 0.5, C.TILE_SIZE * 0.5)
	var facing: Vector2 = Vector2.RIGHT
	if "_facing_x" in bot:
		facing = Vector2(float(bot._facing_x), 0.0)
		if facing.length_squared() < 0.01:
			facing = Vector2.RIGHT
	var nearest: Node = null
	var nearest_d: float = INF
	for e in dungeon.enemies:
		if not is_instance_valid(e) or not e.is_alive:
			continue
		var d: float = origin.distance_to(e.position)
		if d < nearest_d:
			nearest_d = d
			nearest = e
	if nearest != null:
		var dir: Vector2 = nearest.position - origin
		if dir.length_squared() > 0.01:
			facing = dir.normalized()
	var cone_half_angle: float = deg_to_rad(45.0) * (1.0 + float(bot.spell_area_pct) / 100.0)
	var max_dist: float = float(range_cells) * float(C.TILE_SIZE)
	var damage: int = SpellData.compute_damage(bot, item)
	# Blinding Grit affix flag — apply blinded debuff (miss chance) on hit.
	var blind: bool = bool(item.get("spell_sandblast_blind", false))
	var hits: int = 0
	for e in dungeon.enemies:
		if not is_instance_valid(e) or not e.is_alive:
			continue
		var to_e: Vector2 = e.position - origin
		var dist: float = to_e.length()
		if dist > max_dist or dist < 4.0:
			continue
		var ang: float = abs(to_e.angle_to(facing))
		if ang <= cone_half_angle:
			e.take_damage(damage)
			if blind and e.has_method("add_status"):
				e.add_status("blinded", 2.0)
			hits += 1
	if hits == 0:
		return false
	SpellAoe.spawn_cone(dungeon.actor_layer, origin, facing, max_dist, cone_half_angle, _visual_color_for_item(item, "earth"))
	return true

# Vampiric Drain — homing dark projectile that heals the bot for 35%
# of damage dealt on hit. Stacks with item lifesteal_pct on top.
# Ravenous affix (`spell_drain_buff`) additionally adds a 4-second
# +haste-on-hit buff so chained drains snowball.
static func _fire_drain(bot: Node, dungeon: Node, item: Dictionary) -> bool:
	var arch: Dictionary = SpellData.archetype_def("spell_drain")
	if arch.is_empty() or not is_instance_valid(bot) or dungeon == null:
		return false
	var range_cells: int = int(arch.get("range_cells", 8))
	var candidates: Array = _enemies_in_range(bot, dungeon, range_cells)
	if candidates.is_empty():
		return false
	candidates.sort_custom(func(a, b): return a.d < b.d)
	var damage: int = SpellData.compute_damage(bot, item)
	var sprite_path: String = String(arch.get("projectile", ""))
	var element: String = String(arch.get("element", ""))
	var base_speed: float = float(arch.get("projectile_speed", 280.0))
	var speed: float = base_speed * (1.0 + float(bot.spell_proj_speed_pct) / 100.0)
	var tint: Color = _visual_color_for_item(item, "dark")
	var origin: Vector2 = bot.position + Vector2(C.TILE_SIZE * 0.5, C.TILE_SIZE * 0.5)
	var proj_count: int = SpellData.compute_proj_count(bot, item)
	var ravenous: bool = bool(item.get("spell_drain_buff", false))
	for i in proj_count:
		var target: Node = candidates[i % candidates.size()].e
		var p: Projectile = Projectile.spawn_fireball(dungeon.actor_layer, origin, target, damage, speed, sprite_path, element, dungeon, tint)
		if p != null:
			p.lifesteal_pct = 35.0
			p.lifesteal_target = bot
			if ravenous:
				p.lifesteal_buff_bot = true
	return true

# Shatter — radial physical AoE pulse. Bigger raw damage than Frost
# Nova but no slow — instead a brief stun on hit. Aftershock affix
# (`spell_shatter_aftershock`) fires a second smaller pulse 0.4s later.
static func _fire_shatter(bot: Node, dungeon: Node, item: Dictionary) -> bool:
	var arch: Dictionary = SpellData.archetype_def("spell_shatter")
	if arch.is_empty() or not is_instance_valid(bot) or dungeon == null:
		return false
	var range_cells: int = int(arch.get("range_cells", 4))
	var area_mult: float = 1.0 + float(bot.spell_area_pct) / 100.0
	var radius_cells: int = max(1, int(round(float(range_cells) * area_mult)))
	var enemies: Array = _enemies_in_range(bot, dungeon, radius_cells)
	if enemies.is_empty():
		return false
	var damage: int = SpellData.compute_damage(bot, item)
	for entry in enemies:
		var e: Node = entry.e
		if is_instance_valid(e) and e.has_method("take_damage"):
			e.take_damage(damage)
			if e.has_method("add_status"):
				e.add_status("stunned", 0.6)
	var origin: Vector2 = bot.position + Vector2(C.TILE_SIZE * 0.5, C.TILE_SIZE * 0.5)
	SpellAoe.spawn_ring(dungeon.actor_layer, origin, float(radius_cells) * float(C.TILE_SIZE), _visual_color_for_item(item, "earth"))
	# Aftershock — second smaller pulse via SceneTree timer. Timer is
	# auto-freed; the lambda captures the current radius/damage which
	# is fine because they're values, not refs. Half damage, 70% radius.
	if bool(item.get("spell_shatter_aftershock", false)):
		var t := Timer.new()
		t.one_shot = true
		t.wait_time = 0.4
		dungeon.add_child(t)
		t.timeout.connect(func():
			if not is_instance_valid(bot) or not is_instance_valid(dungeon):
				t.queue_free()
				return
			var late_origin: Vector2 = bot.position + Vector2(C.TILE_SIZE * 0.5, C.TILE_SIZE * 0.5)
			var radius2_cells: int = max(1, int(round(float(radius_cells) * 0.7)))
			var enemies2: Array = _enemies_in_range(bot, dungeon, radius2_cells)
			for entry2 in enemies2:
				var e2: Node = entry2.e
				if is_instance_valid(e2) and e2.has_method("take_damage"):
					e2.take_damage(int(damage * 0.5))
			SpellAoe.spawn_ring(dungeon.actor_layer, late_origin, float(radius2_cells) * float(C.TILE_SIZE), _visual_color_for_item(item, "earth"))
			t.queue_free()
		)
		t.start()
	return true

# Resolve the visual color for a spell instance — read flavor_tags
# from the item def first (so a Blood Arc reads RED even though it
# uses the Chain Lightning archetype), falling back to a default
# tag if the item has none. The default is the archetype-natural
# tag (e.g. "thunderous" for chain) so vanilla items still look
# right. Combat pivot 2026-06-04 — re-themed species variants
# need this hook.
static func _visual_color_for_item(item: Dictionary, default_tag: String) -> Color:
	var tags: Array = item.get("flavor_tags", [])
	if tags is Array and not tags.is_empty():
		var c: Color = UITheme.flavor_color_for(tags)
		if c.a > 0.0:
			return c
	return UITheme.flavor_color_for([default_tag])

# Helper: enemies within `radius_cells` chebyshev of bot. Used by all
# AoE / range-gated spells.
static func _enemies_in_range(bot: Node, dungeon: Node, radius_cells: int) -> Array:
	var out: Array = []
	if not "enemies" in dungeon:
		return out
	for e in dungeon.enemies:
		if not is_instance_valid(e) or not e.is_alive:
			continue
		var dx: int = abs(e.cell.x - bot.cell.x)
		var dy: int = abs(e.cell.y - bot.cell.y)
		var d: int = maxi(dx, dy)
		if d <= radius_cells:
			out.append({"e": e, "d": d})
	return out

# C constants for tile size — projectile origin uses TILE_SIZE/2 to center.
const C = preload("res://scripts/constants.gd")

# Helper: get the remaining cooldown fraction (0..1) for HUD overlay.
# 1.0 = just fired; 0.0 = ready to fire.
static func cooldown_fraction(bot: Node, slot: String, items_db: Dictionary) -> float:
	if bot == null or not "spell_cooldowns" in bot:
		return 0.0
	var inst: Variant = bot.equipped.get(slot, null)
	if typeof(inst) != TYPE_DICTIONARY:
		return 0.0
	var base_id: String = String(inst.get("base_id", ""))
	if not items_db.has(base_id):
		return 0.0
	var base_cd: float = _base_cooldown_for(items_db[base_id])
	if base_cd <= 0.001:
		return 0.0
	var remaining: float = float(bot.spell_cooldowns.get(slot, 0.0))
	return clampf(remaining / base_cd, 0.0, 1.0)
