class_name ItemLevel
extends RefCounted

# Item Level scoring — single integer reflecting an item's combat
# contribution. Used by the tooltip footer and the outlier audit.
#
# Two paths:
#   compute_gear(item, inst)  → score for weapons / armor / jewellery
#   compute_spell(item, inst) → score for spell tomes
#
# Each path returns a Dictionary:
#   {
#     "level": int,              # the headline number
#     "rarity": String,           # for tooltip label
#     "components": Array,        # [(label, score), ...] for Alt detail
#   }
#
# Both paths are derived from items.json static data — no live bot stats.
# Re-run the audit after rebalancing affixes / item bases.
#
# Scoring philosophy: the iLvl should differentiate items WITHIN a
# (slot, rarity) bucket so a top-rolled rare and a poorly-authored
# rare both register, and an outlier (a rare priced like a legendary)
# stands out. Across rarity tiers, the deltas come from base stats +
# expected affix budget, not from raw scaling factors.

# --- Tunables --------------------------------------------------------------

# Affix-count budget per rarity. Same as data/affixes.json
# rarity_affix_count, copied here so the static helpers don't need to
# load the affixes JSON every call.
const _RARITY_AFFIX_COUNT := {
	"common": 0, "uncommon": 1, "rare": 2, "epic": 3, "legendary": 4,
}

# Per-rarity tier index for sampling affix bands (same as
# data/affixes.json rarity_tier_index).
const _RARITY_TIER_INDEX := {
	"common": 0, "uncommon": 1, "rare": 2, "epic": 3, "legendary": 4,
}

# Per-stat point-value coefficients. Translates the stat (str, hp,
# crit_chance, etc) into a uniform "score" so we can sum across
# different stats. Roughly matches how each stat scales bot DPS:
#  - 1 hp ≈ 0.5 score (vit affixes give 90-160, weapon stats give ~10)
#  - 1 atk/str ≈ 2 score (weapon damage sees direct mult)
#  - 1% crit ≈ 4 score (caps at 75%; ~4× a flat point of str)
#  - 1 armor ≈ 1.5 score
# These are approximations — perfectly tuned values would require
# running the actual combat sim. Used purely for cross-item comparison.
const _STAT_VALUE := {
	"str":                 2.0,
	"dex":                 2.0,
	"int":                 2.0,
	"hp":                  0.5,
	"hp_regen":            8.0,
	"armor":               1.5,
	"evasion":             3.0,   # %, scarce stat
	"crit_chance":         4.0,
	"haste_pct":           3.0,
	"lifesteal_pct":       5.0,   # capped lower so high values don't dominate
	"physical_extra":      2.5,
	"fire_extra":          2.5,
	"cold_extra":          2.5,
	"lightning_extra":     2.5,
	"holy_extra":          2.5,
	"poison_extra":        2.5,
	"dark_extra":          2.5,
	"fire_res":            1.0,
	"cold_res":            1.0,
	"lightning_res":       1.0,
	"holy_res":            1.0,
	"poison_res":          1.0,
	"dark_res":            1.0,
	"spell_cdr_pct":       3.5,
	"spell_damage_pct":    4.0,
	"spell_area_pct":      2.5,
	"spell_duration_pct":  2.0,
	"spell_proj_speed_pct":1.5,
	"spell_proj_bonus":    20.0,  # scarce — extra projectiles are huge
	"str_spell_dmg_pct":   3.0,
	"dex_spell_dmg_pct":   3.0,
	"int_spell_dmg_pct":   3.0,
}

# Meta-rarity multiplier (Primal/Ancient promote on top of base rarity).
const _META_RARITY_MULT := {
	"primal":  1.20,
	"ancient": 1.10,
}

# --- Helpers ---------------------------------------------------------------

# Mid-band stat value for an affix at this rarity tier.
# Affix tiers in data/affixes.json: [[lo,hi]×5]; we use the band's
# midpoint as the expected roll.
static func _expected_affix_value(affix_id: String, rarity: String) -> float:
	var def: Dictionary = AffixSystem.get_affix_def(affix_id)
	if def.is_empty():
		return 0.0
	var tier_idx: int = int(_RARITY_TIER_INDEX.get(rarity, 0))
	var tiers: Array = def.get("tiers", [])
	if tier_idx >= tiers.size():
		return 0.0
	var band: Variant = tiers[tier_idx]
	if not (band is Array) or (band as Array).size() < 2:
		return 0.0
	var lo: float = float((band as Array)[0])
	var hi: float = float((band as Array)[1])
	return (lo + hi) * 0.5

# Score one affix at a given rarity. Range affixes (of_embers etc)
# emit two values (min + max) — score the average.
static func _score_affix(affix_id: String, rarity: String) -> float:
	var def: Dictionary = AffixSystem.get_affix_def(affix_id)
	if def.is_empty():
		return 0.0
	var stat: String = String(def.get("stat", ""))
	var value: float = _expected_affix_value(affix_id, rarity)
	var coef: float = float(_STAT_VALUE.get(stat, 1.0))
	return value * coef

# Score the expected affix budget for this rarity from the item's
# affix_pool (weighted average of the pool, multiplied by the affix
# count budget). When the pool is empty, we fall back to a generic
# average — the result is approximate but consistent across items.
static func _score_expected_affixes(item: Dictionary, rarity: String) -> float:
	var count: int = int(_RARITY_AFFIX_COUNT.get(rarity, 0))
	if count <= 0:
		return 0.0
	var pool: Dictionary = item.get("affix_pool", {})
	if pool.is_empty():
		# Generic fallback — assume a 5-score average affix at this rarity.
		return float(count) * 5.0 * _RARITY_TIER_INDEX.get(rarity, 0)
	var total_weight: float = 0.0
	var weighted_score: float = 0.0
	for affix_id in pool.keys():
		var w: float = float(pool[affix_id])
		if w <= 0.0:
			continue
		var s: float = _score_affix(String(affix_id), rarity)
		weighted_score += s * w
		total_weight += w
	if total_weight <= 0.0:
		return float(count) * 5.0
	var avg_per_affix: float = weighted_score / total_weight
	return avg_per_affix * float(count)

# Sum the implicit-affix contribution. Implicits don't roll; each one
# fires every drop, so we score them at full value (using the rarity's
# tier index as the band).
static func _score_implicits(item: Dictionary, rarity: String) -> float:
	var implicits: Array = item.get("implicit_affixes", [])
	var total: float = 0.0
	for af_id in implicits:
		total += _score_affix(String(af_id), rarity)
	return total

# Damage-type / flavor tags that carry mechanical weight (combat procs,
# not just visuals). Each adds a flat boost to the score.
const _COMBAT_FLAVOR_BONUS := {
	"vampiric":   12.0,    # lifesteal proc
	"fire":       6.0,
	"cold":       6.0,
	"holy":       6.0,
	"poison":     6.0,
	"thunderous": 6.0,
	"dark":       6.0,
	"regen":      8.0,
	"swiftness":  4.0,
	"fortified":  4.0,
	"warding":    3.0,
}

static func _score_flavor_tags(item: Dictionary) -> float:
	var tags: Array = item.get("flavor_tags", [])
	var total: float = 0.0
	for t in tags:
		total += float(_COMBAT_FLAVOR_BONUS.get(String(t), 0.0))
	return total

# --- Public: gear ----------------------------------------------------------

static func compute_gear(item: Dictionary, inst: Variant = null) -> Dictionary:
	if typeof(item) != TYPE_DICTIONARY or item.is_empty():
		return {"level": 0, "rarity": "common", "components": []}
	var rarity: String = String(item.get("rarity", "common"))
	var components: Array = []
	# Base damage (weapons): average of damage_min/max × _STAT_VALUE coef.
	var base_score: float = 0.0
	if item.get("slot", "") == "weapon":
		var dmin: float = float(item.get("damage_min", 0))
		var dmax: float = float(item.get("damage_max", 0))
		var avg_dmg: float = (dmin + dmax) * 0.5
		var speed: float = float(item.get("speed", 1.0))
		# DPS proxy — damage / swing time. Faster weapons score higher
		# at the same damage band.
		var dps: float = avg_dmg / max(0.3, speed)
		base_score += dps * 1.5
		if base_score > 0:
			components.append(["dmg %.0f-%.0f / %.2fs" % [dmin, dmax, speed], int(round(base_score))])
	# Armor + evasion (body / boots / helm / shield / etc).
	var armor_v: float = float(item.get("armor", 0))
	var evas_v: float = float(item.get("evasion", 0))
	if armor_v > 0:
		var s: float = armor_v * float(_STAT_VALUE.get("armor", 1.5))
		base_score += s
		components.append(["armor %d" % int(armor_v), int(round(s))])
	if evas_v > 0:
		var s: float = evas_v * float(_STAT_VALUE.get("evasion", 3.0))
		base_score += s
		components.append(["evasion %d%%" % int(evas_v), int(round(s))])
	# Static stat fields some items carry directly (hp/atk/def adders).
	for stat in ["hp", "atk", "def"]:
		var v: float = float(item.get(stat, 0))
		if v > 0:
			# atk/def map to str/armor for scoring.
			var key: String = stat
			if stat == "atk": key = "str"
			elif stat == "def": key = "armor"
			var s: float = v * float(_STAT_VALUE.get(key, 1.0))
			base_score += s
			components.append(["%s %d" % [stat, int(v)], int(round(s))])
	# Implicit affixes (always present).
	var imp_score: float = _score_implicits(item, rarity)
	if imp_score > 0:
		components.append(["implicits", int(round(imp_score))])
	# Expected affix budget for this rarity.
	var aff_score: float = _score_expected_affixes(item, rarity)
	if aff_score > 0:
		components.append(["affixes (%d × ~%.0f)" % [
			int(_RARITY_AFFIX_COUNT.get(rarity, 0)),
			aff_score / max(1.0, float(_RARITY_AFFIX_COUNT.get(rarity, 1))),
		], int(round(aff_score))])
	# Combat-flavor tag bonuses.
	var tag_score: float = _score_flavor_tags(item)
	if tag_score > 0:
		components.append(["flavor tags", int(round(tag_score))])
	# Meta-rarity instance multiplier (Primal/Ancient).
	var total: float = base_score + imp_score + aff_score + tag_score
	if typeof(inst) == TYPE_DICTIONARY:
		var meta: String = String(inst.get("meta_rarity", ""))
		if _META_RARITY_MULT.has(meta):
			var mult: float = _META_RARITY_MULT[meta]
			var bonus: float = total * (mult - 1.0)
			components.append(["%s (+%d%%)" % [meta, int(round((mult - 1.0) * 100.0))], int(round(bonus))])
			total += bonus
	return {
		"level": int(round(total)),
		"rarity": rarity,
		"components": components,
	}

# --- Public: spell --------------------------------------------------------

static func compute_spell(item: Dictionary, inst: Variant = null) -> Dictionary:
	if typeof(item) != TYPE_DICTIONARY or item.is_empty():
		return {"level": 0, "rarity": "common", "components": []}
	var rarity: String = String(item.get("rarity", "common"))
	var components: Array = []
	# DPS proxy: avg damage / effective cooldown. Floor cooldown at 1.0
	# so micro-CD spells (magic_dart at 0.7s) don't get a runaway DPS
	# score that puts them 2σ above bucket mean at every rarity.
	var dmin: float = float(item.get("damage_min", 0))
	var dmax: float = float(item.get("damage_max", 0))
	var cd: float = float(item.get("spell_cooldown", 3.0))
	var eff_cd: float = max(1.0, cd)
	var avg_dmg: float = (dmin + dmax) * 0.5
	var dps: float = avg_dmg / eff_cd
	var base_score: float = dps * 3.0  # spells weighted heavier than weapon DPS since they go through bot's spell_damage_pct
	if base_score > 0:
		components.append(["dmg %.0f-%.0f / %.1fs" % [dmin, dmax, cd], int(round(base_score))])
	# Implicit archetype affixes — these are the bleed/comet/storm-brand
	# unique procs on the named legendaries.
	var imp_score: float = 0.0
	for af_id in item.get("implicit_affixes", []):
		var def: Dictionary = AffixSystem.get_affix_def(String(af_id))
		if def.is_empty():
			continue
		# Archetype implicits are flag-kind (no stat value) — fixed
		# 30 score per to reflect the unique mechanic they unlock.
		var kind: String = String(def.get("kind", "flat"))
		if kind == "flag":
			imp_score += 30.0
		else:
			imp_score += _score_affix(String(af_id), rarity)
	if imp_score > 0:
		components.append(["implicits", int(round(imp_score))])
	# Spell affix-pool budget (mostly spell_damage_pct, of_quickcast,
	# of_resonance, etc). Same approach as gear.
	var aff_score: float = _score_expected_affixes(item, rarity)
	if aff_score > 0:
		components.append(["affixes (%d × ~%.0f)" % [
			int(_RARITY_AFFIX_COUNT.get(rarity, 0)),
			aff_score / max(1.0, float(_RARITY_AFFIX_COUNT.get(rarity, 1))),
		], int(round(aff_score))])
	var total: float = base_score + imp_score + aff_score
	if typeof(inst) == TYPE_DICTIONARY:
		var meta: String = String(inst.get("meta_rarity", ""))
		if _META_RARITY_MULT.has(meta):
			var mult: float = _META_RARITY_MULT[meta]
			var bonus: float = total * (mult - 1.0)
			components.append(["%s (+%d%%)" % [meta, int(round((mult - 1.0) * 100.0))], int(round(bonus))])
			total += bonus
	return {
		"level": int(round(total)),
		"rarity": rarity,
		"components": components,
	}

# Convenience: dispatches to gear/spell based on slot.
static func compute(item: Dictionary, inst: Variant = null) -> Dictionary:
	if String(item.get("slot", "")) == "spell":
		return compute_spell(item, inst)
	return compute_gear(item, inst)
