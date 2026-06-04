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
}

static func archetype_def(base_type: String) -> Dictionary:
	return ARCHETYPES.get(base_type, {})

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
#   base × (1 + (primary - 5) × 0.02)         primary stat scaling
#       × (1 + spell_damage_pct/100)          gear "+spell damage"
#       × (1 + element_dmg_pct/100)           gear element-specific
static func compute_damage(bot: Node, item: Dictionary) -> int:
	var arch: Dictionary = archetype_def(String(item.get("base_type", "")))
	if arch.is_empty():
		return 0
	var base_dmg: float = float(item.get("damage", arch.get("damage", 10)))
	var pstat: String = primary_stat_for_item(item)
	var pval: int = primary_stat_value(bot, pstat)
	var stat_mult: float = 1.0 + float(pval - 5) * 0.02
	var dmg_mult: float = 1.0 + float(bot.spell_damage_pct) / 100.0
	var elem: String = String(arch.get("element", ""))
	var elem_mult: float = 1.0
	if elem != "" and bot.spell_element_pct.has(elem):
		elem_mult = 1.0 + float(bot.spell_element_pct[elem]) / 100.0
	return int(round(base_dmg * stat_mult * dmg_mult * elem_mult))

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
