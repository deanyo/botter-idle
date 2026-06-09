class_name SpellData
extends RefCounted

# Per-spell-archetype static config. Maps a spell item's `base_type` to
# its behavior shape (cooldown / damage / range / projectile tile / fire
# func name) so `items.json` only needs to declare which archetype + what
# affixes — the FX, projectile path, and combat math live here.
#
# Phase 2-B: only spell_fireball is fully wired. Phase 3 fills the rest.
#
# Schema per archetype:
#   primary_stat   default str/dex/int (overridable per item)
#   cooldown       seconds between casts at base, before CDR
#   damage         base damage at primary_stat=5 (baseline)
#   range_cells    cells (chebyshev) the spell can reach
#   projectile     path under assets/tiles/ for the projectile sprite
#                  (nullable for non-projectile shapes like nova/cone)
#   trail_flavor   key into weapon_trails::_FLAVOR_SPECS for impact burst
#   element        which element key the spell scales off
#                  (fire/cold/thunderous/holy/poison/dark/"" = none)

const ARCHETYPES := {
	"spell_fireball": {
		"primary_stat": "int",
		"cooldown": 1.6,
		"damage": 18,
		"range_cells": 8,
		"projectile": "res://assets/tiles/projectiles/fireball.png",
		"trail_flavor": "fire",
		"element": "fire",
		"projectile_speed": 320.0,  # px/sec at proj_speed_pct = 0
	},
	"spell_axes": {
		"primary_stat": "str",
		"cooldown": 5.0,
		"damage": 14,
		"range_cells": 2,
		"projectile": "res://assets/tiles/items/hand_axe.png",
		"trail_flavor": "thunderous",
		"element": "",
		"projectile_speed": 0.0,  # orbits, not flying
	},
	"spell_holy_beam": {
		"primary_stat": "str",
		"cooldown": 3.2,
		"damage": 26,
		"range_cells": 4,
		"projectile": "",
		"trail_flavor": "holy",
		"element": "holy",
		"projectile_speed": 0.0,
	},
	"spell_chain_lightning": {
		"primary_stat": "dex",
		"cooldown": 2.4,
		"damage": 16,
		"range_cells": 7,
		"projectile": "",
		"trail_flavor": "thunderous",
		"element": "thunderous",
		"projectile_speed": 0.0,
	},
	"spell_frost_nova": {
		"primary_stat": "int",
		"cooldown": 4.0,
		"damage": 16,
		"range_cells": 3,
		"projectile": "",
		"trail_flavor": "cold",
		"element": "cold",
		"projectile_speed": 0.0,
	},
	# 2026-06-04 expansion — 5 new archetypes covering the unfilled
	# corners of the spell design space.
	#
	# magic_dart: cheap fast projectile, very short CD. The "filler"
	# spell that fires constantly. Low single-hit damage but high DPS
	# from cast frequency.
	"spell_magic_dart": {
		"primary_stat": "int",
		"cooldown": 0.7,
		"damage": 9,
		"range_cells": 9,
		"projectile": "res://assets/tiles/projectiles/magic_dart.png",
		"trail_flavor": "arcane",
		"element": "",
		"projectile_speed": 420.0,
	},
	# iron_shot: slow heavy piercing projectile. One target hit,
	# continues through and damages everyone in the line.
	"spell_iron_shot": {
		"primary_stat": "str",
		"cooldown": 3.5,
		"damage": 32,
		"range_cells": 9,
		"projectile": "res://assets/tiles/projectiles/iron_shot.png",
		"trail_flavor": "earth",
		"element": "",
		"projectile_speed": 220.0,
	},
	# sandblast: tight short cone, physical. Like holy_beam at half
	# the range with higher damage; closer-quarters caster.
	"spell_sandblast": {
		"primary_stat": "str",
		"cooldown": 2.6,
		"damage": 30,
		"range_cells": 3,
		"projectile": "",
		"trail_flavor": "earth",
		"element": "",
		"projectile_speed": 0.0,
	},
	# drain: homing dark projectile that heals the bot for a %
	# of damage dealt on hit (built-in lifesteal even without
	# items_db lifesteal_pct rolls).
	"spell_drain": {
		"primary_stat": "int",
		"cooldown": 2.4,
		"damage": 22,
		"range_cells": 8,
		"projectile": "res://assets/tiles/projectiles/drain.png",
		"trail_flavor": "dark",
		"element": "dark",
		"projectile_speed": 280.0,
	},
	# shatter: radial physical AoE with stun. Slower than Frost Nova
	# but bigger raw damage and brief CC.
	"spell_shatter": {
		"primary_stat": "str",
		"cooldown": 5.0,
		"damage": 28,
		"range_cells": 4,
		"projectile": "",
		"trail_flavor": "earth",
		"element": "",
		"projectile_speed": 0.0,
	},
}

static func archetype_def(base_type: String) -> Dictionary:
	return ARCHETYPES.get(base_type, {})

# Map an archetype `element` key to the `damage_type` key used by
# Actor.take_damage / resolve_swing. Spells with no element (axes,
# magic_dart, iron_shot, sandblast, shatter) read as physical so they
# route through armor mitigation. `thunderous` is the spell-element /
# affix-name, but `lightning` is the resistance / damage_type key.
static func damage_type_for_element(element: String) -> String:
	match element:
		"fire", "cold", "holy", "poison", "dark": return element
		"thunderous": return "lightning"
		_: return "physical"

static func is_spell_archetype(base_type: String) -> bool:
	return ARCHETYPES.has(base_type)

# Resolve the EFFECTIVE primary_stat for a spell item — item-level
# override wins over archetype default. Lets a Demonspawn-flavored
# Hellfire (axes archetype, but Int-scaled) declare itself as Int.
static func primary_stat_for_item(item: Dictionary) -> String:
	if item.has("primary_stat"):
		return String(item["primary_stat"])
	var arch: Dictionary = archetype_def(String(item.get("base_type", "")))
	return String(arch.get("primary_stat", "int"))

# Returns the bot's effective primary-stat value for damage scaling.
# Each point above the 5 baseline = +2% damage on this spell.
static func primary_stat_value(bot: Node, primary_stat: String) -> int:
	if bot == null:
		return 5
	match primary_stat:
		"str": return int(bot.str_stat)
		"dex": return int(bot.dex_stat)
		"int": return int(bot.int_stat)
	return 5

# Compute final spell damage:
#   roll [damage_min..damage_max] × (meta_mult × quality_mult)  base
#       × (1 + (primary - 5) × 0.02)         primary stat scaling
#       × (1 + spell_damage_pct/100)          gear "+spell damage"
#       × (1 + element_dmg_pct/100)           gear element-specific
#
# Pre-2026-06-08 we read item.get("damage", arch.damage) — but every
# spell item declares damage_min/damage_max with no `damage` key, so
# every cast fell through to the archetype default and per-tome rarity
# / quality / meta_rarity scaling was purely cosmetic. Now: roll over
# the item's range when present, scale by meta-rarity (Ancient ×1.20,
# Primal ×1.50) and Quality multiplier (Sublime ×1.20 etc.) the same
# way StatCalc does for weapons, fall back to arch.damage only when
# the item declares no range.
static func compute_damage(bot: Node, item: Dictionary, inst: Variant = null) -> int:
	var arch: Dictionary = archetype_def(String(item.get("base_type", "")))
	if arch.is_empty():
		return 0
	var base_dmg: float
	if item.has("damage_min") or item.has("damage_max"):
		var dmin: int = int(item.get("damage_min", item.get("damage_max", 1)))
		var dmax: int = int(item.get("damage_max", dmin))
		base_dmg = float(randi_range(min(dmin, dmax), max(dmin, dmax)))
	else:
		base_dmg = float(item.get("damage", arch.get("damage", 10)))
	# Meta-rarity + quality multipliers off the per-instance dict.
	# Ancient = 20% stat boost, Primal = 50% (matches StatCalc weapon path).
	# Quality.multiplier_for handles missing inst gracefully (returns 1.0).
	if inst != null:
		var meta: String = ""
		if typeof(inst) == TYPE_DICTIONARY:
			meta = String(inst.get("meta_rarity", ""))
		var meta_mult: float = 1.0
		if meta == "ancient":
			meta_mult = 1.20
		elif meta == "primal":
			meta_mult = 1.50
		var qmult: float = Quality.multiplier_for(inst)
		# Mirror StatCalc baseline rollback (a10 §5.3) — cap meta×quality
		# at ×1.30 so spell base rolls stay inside ceiling.
		base_dmg *= clampf(meta_mult * qmult, 0.0, 1.30)
	var pstat: String = primary_stat_for_item(item)
	var pval: int = primary_stat_value(bot, pstat)
	var stat_mult: float = 1.0 + float(pval - 5) * 0.02
	var dmg_mult: float = 1.0 + float(bot.spell_damage_pct) / 100.0
	var elem: String = String(arch.get("element", ""))
	var elem_mult: float = 1.0
	if elem != "" and bot.spell_element_pct.has(elem):
		elem_mult = 1.0 + float(bot.spell_element_pct[elem]) / 100.0
	# Class-mastery multiplier (of_str/dex/int_mastery). Reads the bot's
	# class lane that matches the spell's primary_stat — pure-Str spells
	# benefit from of_str_mastery, Int from of_int_mastery, etc.
	var class_pct: float = 0.0
	match pstat:
		"str": class_pct = float(bot.get("str_spell_dmg_pct"))
		"dex": class_pct = float(bot.get("dex_spell_dmg_pct"))
		"int": class_pct = float(bot.get("int_spell_dmg_pct"))
	var class_mult: float = 1.0 + class_pct / 100.0
	# Ephemeral conditional spell bonus, capped at +30% per cast (a10
	# §5.1). Conditional/trigger-based spell affixes write into the
	# bot's ephemeral_spell_dmg_pct accumulator; cap is applied here so
	# stacking multiple windows can't burst the ceiling.
	var eph_pct: float = float(bot.get("ephemeral_spell_dmg_pct")) if bot.get("ephemeral_spell_dmg_pct") != null else 0.0
	var eph_mult: float = 1.0 + minf(0.30, maxf(0.0, eph_pct / 100.0))
	return int(round(base_dmg * stat_mult * dmg_mult * elem_mult * class_mult * eph_mult))

# Resolve the effective cooldown — base × (1 - cdr/100), clamped.
# CDR caps at 60% (DCSS-style diminishing returns; we don't want
# zero-cooldown spam at endgame).
static func compute_cooldown(bot: Node, item: Dictionary) -> float:
	var arch: Dictionary = archetype_def(String(item.get("base_type", "")))
	var base_cd: float = float(item.get("spell_cooldown", arch.get("cooldown", 3.0)))
	if bot == null:
		return base_cd
	var cdr: float = clampf(float(bot.spell_cdr_pct), 0.0, 60.0)
	return max(0.3, base_cd * (1.0 - cdr / 100.0))

# Effective projectile-count: archetype-default + spell_proj_bonus +
# any per-item override. Each spell archetype interprets this its own
# way (fireball = N homing balls, axes = N orbiting axes, chain = N+1
# jumps).
static func compute_proj_count(bot: Node, item: Dictionary) -> int:
	var base_n: int = int(item.get("proj_count", 1))
	if bot == null:
		return max(1, base_n)
	return max(1, base_n + int(bot.spell_proj_bonus))
