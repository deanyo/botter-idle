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
	# from cast frequency. Re-tagged INT → DEX (S6, a03 §A.4): closes
	# the dagger-Halfling-spam archetype gap. Base damage bumped per
	# F-SPELL-02 so the t5 mid lands within 30% of chain_lightning.
	"spell_magic_dart": {
		"primary_stat": "dex",
		"cooldown": 0.7,
		"damage": 14,
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
	# sandblast → Dust Devil rework (S6, a05 dead-1). Was a tight
	# physical cone strictly outclassed by spell_holy_beam at every
	# floor depth. Now a moving cyclone: a vortex that sweeps 4 cells
	# in the bot's facing direction, hitting enemies inside a swept
	# rectangle (~1.5 cells wide) along its path. Differentiates by
	# shape, not numbers — same STR primary, same physical damage type.
	"spell_sandblast": {
		"primary_stat": "str",
		"cooldown": 2.6,
		"damage": 30,
		"range_cells": 4,
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
	# S10 expansion (a05 D + a10 §3.2 rescopes). 8 archetypes, mix of STR
	# (bone_spear, wrath_charge), DEX (echo_lance, stormcaller_totem,
	# curse_brittlebone), INT (venom_cloud, ember_bloom, wisp_servant).
	# All numbers come from a10's rescope decisions, NOT a05's originals.
	#
	# bone_spear: STR bouncing physical projectile. Fast, single-target
	# with chain potential (30% damage loss per bounce, max 4 bounces).
	# Anchors a STR projectile-stack build; of_multicast adds concurrent
	# spears, of_velocity speeds them up.
	"spell_bone_spear": {
		"primary_stat": "str",
		"cooldown": 1.8,
		"damage": 22,
		"range_cells": 7,
		"projectile": "res://assets/tiles/spells/effects/crystal_spear3.png",
		"trail_flavor": "earth",
		"element": "",
		"projectile_speed": 360.0,
	},
	# venom_cloud: INT poison DoT cloud. Stationary, ticks damage to
	# enemies inside its radius. a10 §3.2 rescope: 1.5 dmg/tick × 2
	# ticks/s × 8s × 3-enemy max (down from a05's 2.5/4/6/5 author-tuned
	# values). The `damage` field is the PER-TICK base damage, not the
	# per-cast total — Cloud node ticks every 0.5s and re-rolls. The
	# tick rate is HARD-CAPPED at 2/s irrespective of of_lingering.
	"spell_venom_cloud": {
		"primary_stat": "int",
		"cooldown": 4.5,
		"damage": 2,
		"range_cells": 5,
		"projectile": "",
		"trail_flavor": "poison",
		"element": "poison",
		"projectile_speed": 0.0,
	},
	# stormcaller_totem: DEX lightning turret. Drop at feet, zaps nearest
	# enemy every 0.6s for 4s base × duration_pct. Despawns on floor
	# change (idle-grind block: totem can't tick while bot offline since
	# the parent dungeon node freezes its _process tree).
	"spell_stormcaller_totem": {
		"primary_stat": "dex",
		"cooldown": 6.0,
		"damage": 12,
		"range_cells": 4,
		"projectile": "",
		"trail_flavor": "thunderous",
		"element": "thunderous",
		"projectile_speed": 0.0,
	},
	# curse_brittlebone: DEX multi-target debuff. Cursed enemies take
	# +15% damage (a10 rescope from +30%) and -50% armor for 4s × dur_pct.
	# 0 direct damage (1 to register kill log). Multi-target via
	# spell_proj_bonus — base targets nearest enemy + (proj_bonus) extras.
	"spell_curse_brittlebone": {
		"primary_stat": "dex",
		"cooldown": 8.0,
		"damage": 1,
		"range_cells": 6,
		"projectile": "",
		"trail_flavor": "dark",
		"element": "dark",
		"projectile_speed": 0.0,
	},
	# wrath_charge: STR self-buff. +20% weapon damage + +20% spell damage
	# for a HARD-CAPPED 4-second window (a10 rescope from +50/+50/8s
	# scalable). of_lingering MUST NOT extend it — the fixed window is
	# what keeps the rescope honest. Folds into ephemeral lanes so the
	# +30% per-swing / per-cast caps absorb stacking with other windows.
	"spell_wrath_charge": {
		"primary_stat": "str",
		"cooldown": 9.0,
		"damage": 0,
		"range_cells": 0,
		"projectile": "",
		"trail_flavor": "brutal",
		"element": "",
		"projectile_speed": 0.0,
	},
	# echo_lance: DEX bouncing-once projectile. Fast lance, hits one
	# target at full damage, then ricochets to nearest unhit enemy
	# within 4 cells at full damage (no falloff — exactly 1 ricochet).
	# Distinct from bone_spear's multi-bounce + chain_lightning's
	# point-to-point lightning. Base 11 (a10 rescope from 14).
	"spell_echo_lance": {
		"primary_stat": "dex",
		"cooldown": 1.4,
		"damage": 11,
		"range_cells": 8,
		"projectile": "res://assets/tiles/spells/effects/bolt5.png",
		"trail_flavor": "thunderous",
		"element": "thunderous",
		"projectile_speed": 480.0,
	},
	# wisp_servant: INT interim orbiter. Spawns N wisps that orbit the
	# bot and home into nearby enemies on contact. Base 4 (a10 rescope
	# from 8). Real minion AI is Tier-3; this is the "axes-but-flying-out"
	# shape that fills the niche today.
	"spell_wisp_servant": {
		"primary_stat": "int",
		"cooldown": 7.0,
		"damage": 4,
		"range_cells": 4,
		"projectile": "res://assets/tiles/spells/effects/orb_glow1.png",
		"trail_flavor": "arcane",
		"element": "",
		"projectile_speed": 220.0,
	},
	# ember_bloom: INT fire DoT patch. Same Cloud class as venom_cloud
	# with fire damage type. a10 §3.2 rescope: 2.0 dmg/tick × 2 ticks/s
	# × 5s × 3-enemy max (down from a05's 5 dmg/tick author-tuned).
	# Same per-tick semantics as venom_cloud.
	"spell_ember_bloom": {
		"primary_stat": "int",
		"cooldown": 5.0,
		"damage": 2,
		"range_cells": 4,
		"projectile": "",
		"trail_flavor": "fire",
		"element": "fire",
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
	# S4 Tier-1 spell-side affix contributions (a10 §3.2 rescopes). All
	# additively roll into the ephemeral lane so the +30% cap absorbs
	# them. Permanent-stat lanes (sage/hunter when always-on) intentionally
	# share the same ceiling — keeps the rescope projections honest.
	#   of_sage:    +sage_per_unspent_pct × min(unspent, 10) / 10 (peaks at 24%)
	#   of_hunter:  +hunter_pct (only on full-HP slot — spell branch
	#               cannot read the target HP here, so we surface it
	#               through ephemeral_spell_dmg_pct from the caller's
	#               write-site instead. Documented for callers that may
	#               want spell-side hunter: write to ephemeral_spell_dmg_pct
	#               at cast-resolve time when target ≥80% HP.)
	#   of_synergy: +synergy_pct (when synergy_active triplet present)
	# of_tempest's spell-damage leg already folds into spell_damage_pct
	# above; cd-penalty leg lands in compute_cooldown.
	var sage_pct: float = float(bot.get("sage_per_unspent_pct")) if bot.get("sage_per_unspent_pct") != null else 0.0
	if sage_pct > 0.0:
		var unspent: int = clampi(int(bot.get("unspent_points") if bot.get("unspent_points") != null else 0), 0, 10)
		eph_pct += sage_pct * float(unspent) / 10.0
	if bool(bot.get("synergy_active")) and float(bot.get("synergy_pct")) > 0.0:
		eph_pct += float(bot.get("synergy_pct"))
	# S10 — Wrath Charge spell-side leg (a05 prop-5 + a10 §3.2 rescope).
	# +20% spell damage while "wrath" status is up; fixed 4s window
	# baked at the cast site, of_lingering must NOT extend it.
	if bot.has_method("has_status") and bot.has_status("wrath"):
		eph_pct += 20.0
	# §1.H of_smoldering_step (a02 P-015) — spell damage while moving.
	# Reads bot._last_move_at_msec stamp set in step_movement; ≤400ms ago
	# qualifies as "moving" (matches the petrify pattern). Folds through
	# the ephemeral lane so the +30% per-cast ceiling absorbs the upper
	# tail when stacked with sage/synergy/wrath.
	var mv_pct: float = float(bot.get("move_spell_dmg_pct")) if bot.get("move_spell_dmg_pct") != null else 0.0
	if mv_pct > 0.0 and bot.get("_last_move_at_msec") != null:
		var since_move_spell: int = Time.get_ticks_msec() - int(bot.get("_last_move_at_msec"))
		if since_move_spell <= 400:
			eph_pct += mv_pct
	var eph_mult: float = 1.0 + minf(0.30, maxf(0.0, eph_pct / 100.0))
	var dmg: float = base_dmg * stat_mult * dmg_mult * elem_mult * class_mult * eph_mult
	# S9 spell crit (a06 §3.1, a10 rescope to ×1.25 base + half-rate crit-
	# multiplier composition). Pre-S9, spell_data.compute_damage never
	# rolled a crit — Dex-spec on a chain_lightning build was a no-op for
	# spell DPS. Now: crit_chance gates the roll; on crit, damage scales
	# by (1.25 + crit_multiplier_pct/100/2). The /2 keeps spells from
	# compounding the same crit-mult as melee (which already lands at
	# ×1.85 cap with the +35% rescope).
	if bot != null:
		var cc: float = float(bot.get("crit_chance")) if bot.get("crit_chance") != null else 0.0
		if cc > 0.0 and randf() * 100.0 < cc:
			var cmp_v: float = float(bot.get("crit_multiplier_pct")) if bot.get("crit_multiplier_pct") != null else 0.0
			var spell_crit_mult: float = 1.25 + cmp_v / 100.0 / 2.0
			dmg *= spell_crit_mult
	return int(round(dmg))

# Resolve the effective cooldown — base × (1 - cdr/100), clamped.
# CDR caps at 60% (DCSS-style diminishing returns; we don't want
# zero-cooldown spam at endgame).
static func compute_cooldown(bot: Node, item: Dictionary) -> float:
	var arch: Dictionary = archetype_def(String(item.get("base_type", "")))
	var base_cd: float = float(item.get("spell_cooldown", arch.get("cooldown", 3.0)))
	if bot == null:
		return base_cd
	var cdr: float = clampf(float(bot.spell_cdr_pct), 0.0, 60.0)
	# of_tempest cd-penalty leg (a02 P-10): subtracted from cdr — the
	# affix trades cooldown speed for spell damage. Net cdr can go
	# negative (longer cooldowns); clamp at -50% so a stacked Tempest
	# loadout doesn't grind a 1.5s spell to 4s+.
	var penalty: float = float(bot.get("tempest_cd_penalty_pct")) if bot.get("tempest_cd_penalty_pct") != null else 0.0
	var net_cdr: float = clampf(cdr - penalty, -50.0, 60.0)
	return max(0.3, base_cd * (1.0 - net_cdr / 100.0))

# Effective projectile-count: archetype-default + spell_proj_bonus +
# any per-item override. Each spell archetype interprets this its own
# way (fireball = N homing balls, axes = N orbiting axes, chain = N+1
# jumps).
static func compute_proj_count(bot: Node, item: Dictionary) -> int:
	var base_n: int = int(item.get("proj_count", 1))
	if bot == null:
		return max(1, base_n)
	return max(1, base_n + int(bot.spell_proj_bonus))
