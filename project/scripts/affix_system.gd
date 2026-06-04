class_name AffixSystem
extends RefCounted

const AFFIXES_PATH := "res://data/affixes.json"
const BASE_TYPE_AFFIXES_PATH := "res://data/base_type_affixes.json"

static var _affixes_by_id: Dictionary = {}
static var _rarity_count: Dictionary = {}
static var _rarity_idx: Dictionary = {}
# Per-base-type affix weight maps. base_type → {affix_id: weight}.
# Higher weight = more likely. Missing base_types fall back to the
# applies_to filter on the global pool.
static var _base_type_weights: Dictionary = {}
static var _loaded: bool = false

static func _ensure_loaded() -> void:
	if _loaded:
		return
	var f := FileAccess.open(AFFIXES_PATH, FileAccess.READ)
	if f == null:
		push_error("Failed to open affixes.json")
		_loaded = true
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Failed to parse affixes.json")
		_loaded = true
		return
	var data: Dictionary = parsed
	for af in data.get("affixes", []):
		_affixes_by_id[af.id] = af
	_rarity_count = data.get("rarity_affix_count", {})
	_rarity_idx = data.get("rarity_tier_index", {})
	# Optional file — base-type affix tuning. Absent = global pool only.
	var bt_f := FileAccess.open(BASE_TYPE_AFFIXES_PATH, FileAccess.READ)
	if bt_f != null:
		var bt_parsed: Variant = JSON.parse_string(bt_f.get_as_text())
		if typeof(bt_parsed) == TYPE_DICTIONARY:
			_base_type_weights = bt_parsed.get("base_types", {})
	_loaded = true

static func roll_affixes_for(item: Dictionary, rng: RandomNumberGenerator) -> Array:
	_ensure_loaded()
	var rarity: String = String(item.get("rarity", "common"))
	var slot: String = String(item.get("slot", ""))
	var n: int = int(_rarity_count.get(rarity, 0))
	if n <= 0:
		return []
	var tier_idx: int = int(_rarity_idx.get(rarity, 0))
	# Priority chain for the affix pool:
	#   1. item.affix_pool override (per-item authored allowlist with
	#      weights, e.g. {"crit": 30, "haste": 10})
	#   2. base_type weights from data/base_type_affixes.json (e.g.
	#      a rapier favors crit; a tower_shield favors stamina)
	#   3. applies_to fallback — uniform pick over all affixes that
	#      can apply to the slot (legacy behavior)
	var weights: Dictionary = {}
	var item_pool: Variant = item.get("affix_pool", null)
	if typeof(item_pool) == TYPE_DICTIONARY and not item_pool.is_empty():
		weights = item_pool
	else:
		var base_type: String = String(item.get("base_type", ""))
		if base_type != "" and _base_type_weights.has(base_type):
			weights = _base_type_weights[base_type]
	# Build the pool: weighted entries from `weights`, or applies_to
	# fallback at uniform weight 1.
	var pool: Array = []
	if weights.is_empty():
		for id in _affixes_by_id.keys():
			var af: Dictionary = _affixes_by_id[id]
			var applies: Array = af.applies_to
			if applies.has(slot) or applies.has("any"):
				pool.append({"def": af, "weight": 1.0})
	else:
		for af_id in weights.keys():
			var w: float = float(weights[af_id])
			if w <= 0.0 or not _affixes_by_id.has(af_id):
				continue
			pool.append({"def": _affixes_by_id[af_id], "weight": w})
		# If the override pool somehow ended up empty (all weights 0
		# or unknown ids), fall back to applies_to so the item still
		# gets affixes — better than silently rolling nothing.
		if pool.is_empty():
			for id in _affixes_by_id.keys():
				var af: Dictionary = _affixes_by_id[id]
				var applies: Array = af.applies_to
				if applies.has(slot) or applies.has("any"):
					pool.append({"def": af, "weight": 1.0})
	var rolled: Array = []
	var used_ids: Dictionary = {}
	_roll_from_weighted(pool, n, used_ids, rolled, tier_idx, rng)
	return rolled

# Weighted pick without replacement. Same shape as the prior
# uniform-pick loop, just biased by the per-affix weight.
static func _roll_from_weighted(pool: Array, want: int, used_ids: Dictionary, into: Array, tier_idx: int, rng: RandomNumberGenerator) -> void:
	if pool.is_empty():
		return
	var attempts: int = 0
	while want > 0 and attempts < 30:
		attempts += 1
		var total_w: float = 0.0
		for entry in pool:
			if not used_ids.has(entry.def.id):
				total_w += float(entry.weight)
		if total_w <= 0.0:
			break  # all options used or weighted out
		var roll: float = rng.randf() * total_w
		var acc: float = 0.0
		var picked: Dictionary = {}
		for entry in pool:
			if used_ids.has(entry.def.id):
				continue
			acc += float(entry.weight)
			if roll <= acc:
				picked = entry.def
				break
		if picked.is_empty():
			continue
		used_ids[picked.id] = true
		var tiers: Array = picked.tiers
		var tier_entry = tiers[mini(tier_idx, tiers.size() - 1)]
		# v2 schema: tier is [min, max]. v1 schema: tier is a single int.
		# Handle both — single int means "fixed value, no range roll."
		var rolled: Dictionary = {"id": picked.id}
		if tier_entry is Array and tier_entry.size() >= 2:
			var lo: int = int(tier_entry[0])
			var hi: int = int(tier_entry[1])
			if String(picked.get("kind", "flat")) == "range":
				# Range affixes carry both bounds — used by tooltip to
				# render "+X-Y" lines and by combat to roll per-hit.
				rolled["value_min"] = lo
				rolled["value_max"] = hi
				# Legacy single-value field gets the midpoint so
				# sum_affix_stats keeps working for callers that don't
				# read value_min/max yet.
				rolled["value"] = int(round((lo + hi) / 2.0))
			else:
				rolled["value"] = rng.randi_range(lo, hi)
		else:
			rolled["value"] = int(tier_entry)
		into.append(rolled)
		want -= 1

static func get_affix_def(id: String) -> Dictionary:
	_ensure_loaded()
	return _affixes_by_id.get(id, {})

static func tier_index_for_rarity(rarity: String) -> int:
	_ensure_loaded()
	return int(_rarity_idx.get(rarity, 0))

static func format_item_name(base_name: String, affixes: Array, inst: Variant = null) -> String:
	# Simplified to "BaseName [+Stat, +Stat]" — every affix is just an affix,
	# no prefix/suffix grammar. Empty-affix items show just the base name.
	# Optional `inst` arg: when supplied and inst.meta_rarity is set,
	# prefix the name with "Ancient" / "Primal" so the meta-rarity is
	# visible everywhere format_item_name is called from (HUD inv,
	# Outpost, run report, tooltips).
	_ensure_loaded()
	var prefix: String = ""
	if typeof(inst) == TYPE_DICTIONARY:
		# Quality tier prefix — "Pristine Iron Dagger" / "Rusted Tower
		# Shield" / "Mouldering Fireball Tome". Always rendered if
		# present, regardless of meta-rarity. Skips "Standard" since
		# that's the no-op baseline. Item-overhaul follow-up 2026-06-04.
		var quality: String = String(inst.get("quality", ""))
		if quality != "" and quality != "Standard":
			prefix = quality + " "
		var meta: String = String(inst.get("meta_rarity", ""))
		if meta == "ancient":
			prefix = "Ancient " + prefix
		elif meta == "primal":
			prefix = "Primal " + prefix
	var name_with_prefix: String = prefix + base_name
	if affixes.is_empty():
		return name_with_prefix
	var tags: Array = []
	for af_inst in affixes:
		var def: Dictionary = _affixes_by_id.get(af_inst.id, {})
		if def.is_empty():
			continue
		tags.append("+" + String(def.name))
	if tags.is_empty():
		return name_with_prefix
	return "%s [%s]" % [name_with_prefix, ", ".join(tags)]

static func format_affix_lines(affixes: Array) -> Array:
	_ensure_loaded()
	var lines: Array = []
	for af_inst in affixes:
		var def: Dictionary = _affixes_by_id.get(af_inst.id, {})
		if def.is_empty():
			continue
		var stat: String = String(def.stat)
		var v: int = int(af_inst.value)
		lines.append(_format_stat_line(stat, v))
	return lines

static func _format_stat_line(stat: String, v: int) -> String:
	match stat:
		"atk": return "+%d ATK" % v
		"hp": return "+%d HP" % v
		"def": return "+%d DEF" % v
		"hp_regen": return "+%d HP/sec" % v
		"crit_chance": return "+%d%% Crit" % v
		"atk_speed_pct": return "+%d%% Haste" % v
		"str": return "+%d Str" % v
		"dex": return "+%d Dex" % v
		"int": return "+%d Int" % v
		"spell_cdr_pct": return "-%d%% Spell Cooldown" % v
		"spell_proj_bonus": return "+%d Spell Projectile" % v if v == 1 else "+%d Spell Projectiles" % v
		"spell_proj_speed_pct": return "+%d%% Projectile Speed" % v
		"spell_area_pct": return "+%d%% Spell Area" % v
		"spell_duration_pct": return "+%d%% Spell Duration" % v
		"spell_damage_pct": return "+%d%% Spell Damage" % v
		"fire_dmg_pct": return "+%d%% Fire Damage" % v
		"cold_dmg_pct": return "+%d%% Cold Damage" % v
		"thunderous_dmg_pct": return "+%d%% Lightning Damage" % v
		"holy_dmg_pct": return "+%d%% Holy Damage" % v
		"poison_dmg_pct": return "+%d%% Poison Damage" % v
		"dark_dmg_pct": return "+%d%% Dark Damage" % v
	return "+%d %s" % [v, stat]

# Canonical hover tooltip for an item. Used by every UI surface that shows
# items so the format never drifts between HUD / Outpost / menu.
#   Line 1: "Item Name [rarity]"
#   Line 2: base "+X ATK +Y DEF +Z HP" (zeros suppressed)
#   Line N: each affix on its own line
static func format_item_tooltip(item_def: Dictionary, inst: Variant) -> String:
	if item_def.is_empty():
		return ""
	var affixes: Array = []
	if typeof(inst) == TYPE_DICTIONARY:
		affixes = inst.get("affixes", [])
	var disp_name: String = format_item_name(String(item_def.get("name", "")), affixes, inst)
	var rarity: String = String(item_def.get("rarity", "")).capitalize()
	var lines: Array = []
	# Append 2H badge to the rarity slot when applicable.
	var rarity_chunk: String = rarity
	if Bot.is_two_handed_base_type(String(item_def.get("base_type", ""))):
		rarity_chunk = (rarity + " · 2H") if rarity != "" else "2H"
	lines.append("%s [%s]" % [disp_name, rarity_chunk] if rarity_chunk != "" else disp_name)
	# Meta-rarity line — Ancient (1%) or Primal (0.1%) per drop. Stat
	# multiplier is +20% / +50% baked into bot.recompute_stats so the
	# numbers in the line below already reflect it; this line just
	# tells the player WHY their stats look beefier than usual.
	if typeof(inst) == TYPE_DICTIONARY:
		var meta: String = String(inst.get("meta_rarity", ""))
		if meta == "ancient":
			lines.append("[Ancient]  +20% base stats")
		elif meta == "primal":
			lines.append("[Primal]  +50% base stats — extremely rare")
		# Tint roll line — describes what visual treatment the item
		# rolled and the stat lean that came with it.
		var tint: Variant = inst.get("tint", null)
		if typeof(tint) == TYPE_DICTIONARY:
			var mode: String = String(tint.get("mode", "normal"))
			var lean: String = String(tint.get("lean", ""))
			var lean_pct: float = float(tint.get("lean_pct", 0.0))
			var mode_labels: Dictionary = {
				"normal": "Tinted",
				"shimmer": "✦ Shimmering",
				"inverted": "⌧ Inverted",
				"prismatic": "◇ Prismatic",
			}
			var mode_label: String = String(mode_labels.get(mode, "Tinted"))
			lines.append("[%s]  +%.0f%% %s" % [mode_label, lean_pct, lean])
	var base_parts: Array = []
	var atk_v: int = int(item_def.get("atk", 0))
	var def_v: int = int(item_def.get("def", 0))
	var hp_v: int = int(item_def.get("hp", 0))
	if atk_v > 0: base_parts.append("+%d ATK" % atk_v)
	if def_v > 0: base_parts.append("+%d DEF" % def_v)
	if hp_v > 0: base_parts.append("+%d HP" % hp_v)
	# Item secondary stats — direct contributions distinct from
	# rolled affixes. Hidden when zero so most items stay clean.
	var crit_v: float = float(item_def.get("crit_chance", 0))
	var hst_v: float = float(item_def.get("atk_speed_pct", 0))
	var rgn_v: float = float(item_def.get("hp_regen", 0))
	if crit_v > 0: base_parts.append("+%d%% Crit" % int(round(crit_v)))
	if hst_v > 0: base_parts.append("+%d%% Haste" % int(round(hst_v)))
	if rgn_v > 0: base_parts.append("+%.1f HP/s" % rgn_v)
	if not base_parts.is_empty():
		lines.append("  ".join(base_parts))
	var affix_lines: Array = format_affix_lines(affixes)
	lines.append_array(affix_lines)
	# Per-instance enchant line. Drop chance is rolled in
	# dungeon._create_item_instance and stored on inst.enchant; we
	# render a short mechanic blurb so the player understands what
	# the rolled flavor does.
	if typeof(inst) == TYPE_DICTIONARY:
		var enchant: String = String(inst.get("enchant", ""))
		if enchant != "":
			var blurb: String = ENCHANT_BLURBS.get(enchant, "")
			if blurb != "":
				lines.append("✦ Enchant — %s: %s" % [enchant.capitalize(), blurb])
			else:
				lines.append("✦ Enchant — %s" % enchant.capitalize())
	return "\n".join(lines)

# One-line mechanic descriptions per enchant flavor — surfaced in the
# tooltip so the player understands what they rolled. Numbers track
# the actual mechanics in actor.gd::attempt_attack and elsewhere; if
# those are tuned, update here too.
const ENCHANT_BLURBS := {
	"vampiric":    "8% of damage dealt heals you.",
	"fire":        "On hit, burns target for 4% max HP × 3 ticks.",
	"cold":        "15% chance to freeze; +20% damage vs frozen.",
	"holy":        "+50% damage vs undead and demons.",
	"poison":      "On hit, poisons target for 3% max HP × 4 ticks.",
	"thunderous":  "On hit, splash 50% to one adjacent enemy.",
	"dark":        "Grim aura. (passive flavor)",
	"dragon_bane": "+50% damage vs dragons and wyrms.",
	"brutal":      "+25% damage vs targets ≤30% HP.",
	"precision":   "Anti-streak crit: +5%/swing toward +50% cap.",
	"rage":        "+5% atk per kill within 6s, cap +30%.",
	"thorns":      "Returns 15% of damage taken to attackers.",
	"reflective":  "10% chance to fully negate an incoming hit.",
	"harm":        "+25% damage dealt and taken.",
	"vitality":    "+1 HP regen per second.",
	"fortified":   "+20% defense (per source, cap +50%).",
	"willpower":   "-25% damage from elemental and arcane attackers.",
	"swiftness":   "+10% move speed (per source, cap +30%).",
	"regen":       "+0.5 HP regen per second.",
	"stealth":     "First attack each floor lands +25%.",
	"lordly":      "+15% XP gained.",
	"footwork":    "8% chance to fully evade an attack.",
	"warding":     "-20% damage from boss / miniboss attackers.",
	"elemental":   "+1% damage per character level (scales with you).",
	"wisdom":      "+15% XP gained.",
	"arcane":      "Every 4th swing: +50% magic burst.",
	"fire_res":    "-50% fire damage; immune to burn DoT.",
	"cold_res":    "-50% cold damage; immune to freeze.",
	"poison_res":  "Immune to poison DoT.",
	"vision":      "+1 aggro range (engage enemies further out).",
	"rampaging":   "On kill, refund attack cooldown.",
	"flying":      "Ignore water slow.",
	"fortune":     "+20% loot drop chance.",
	"faith":       "+50% fountain heal; +0.5 HP regen.",
	"acrobat":     "When below 30% HP, -17% damage taken.",
	"death":       "On kill, 25% chance to splash 5% atk to adjacent.",
	"earth":       "-15% damage from physical attackers.",
	"guardian":    "Flat -10% damage taken.",
	"demon":       "+25% damage vs undead and demons.",
	"crystal":     "Returns 5% of damage taken (passive thorns).",
	"dual":        "15% chance to attack twice.",
	"sound":       "10% chance to stun for 1s on hit.",
	"ponderous":   "+10% damage but -10% attack speed.",
	"slaying":     "Stat-flavor (already on base atk).",
	"psychic":     "Mind-shielded. (decorative for now)",
}

static func sum_affix_stats(affixes: Array) -> Dictionary:
	_ensure_loaded()
	var sums: Dictionary = {}
	for af_inst in affixes:
		var def: Dictionary = _affixes_by_id.get(af_inst.id, {})
		if def.is_empty():
			continue
		var stat: String = String(def.stat)
		sums[stat] = sums.get(stat, 0) + int(af_inst.get("value", 0))
		# Range affixes (kind=range, e.g. of_embers, of_sharpness) also
		# carry value_min / value_max so combat can roll a fresh value
		# per hit. We accumulate the bounds under "<stat>_min" /
		# "<stat>_max" keys so callers can reach them without re-walking
		# the affix list.
		if af_inst.has("value_min") and af_inst.has("value_max"):
			sums[stat + "_min"] = sums.get(stat + "_min", 0) + int(af_inst["value_min"])
			sums[stat + "_max"] = sums.get(stat + "_max", 0) + int(af_inst["value_max"])
	return sums
