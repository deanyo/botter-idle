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
		var value: int = int(tiers[mini(tier_idx, tiers.size() - 1)])
		into.append({"id": picked.id, "value": value})
		want -= 1

static func get_affix_def(id: String) -> Dictionary:
	_ensure_loaded()
	return _affixes_by_id.get(id, {})

static func tier_index_for_rarity(rarity: String) -> int:
	_ensure_loaded()
	return int(_rarity_idx.get(rarity, 0))

static func format_item_name(base_name: String, affixes: Array) -> String:
	# Simplified to "BaseName [+Stat, +Stat]" — every affix is just an affix,
	# no prefix/suffix grammar. Empty-affix items show just the base name.
	_ensure_loaded()
	if affixes.is_empty():
		return base_name
	var tags: Array = []
	for af_inst in affixes:
		var def: Dictionary = _affixes_by_id.get(af_inst.id, {})
		if def.is_empty():
			continue
		tags.append("+" + String(def.name))
	if tags.is_empty():
		return base_name
	return "%s [%s]" % [base_name, ", ".join(tags)]

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
	var disp_name: String = format_item_name(String(item_def.get("name", "")), affixes)
	var rarity: String = String(item_def.get("rarity", "")).capitalize()
	var lines: Array = []
	lines.append("%s [%s]" % [disp_name, rarity] if rarity != "" else disp_name)
	var base_parts: Array = []
	var atk_v: int = int(item_def.get("atk", 0))
	var def_v: int = int(item_def.get("def", 0))
	var hp_v: int = int(item_def.get("hp", 0))
	if atk_v > 0: base_parts.append("+%d ATK" % atk_v)
	if def_v > 0: base_parts.append("+%d DEF" % def_v)
	if hp_v > 0: base_parts.append("+%d HP" % hp_v)
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
}

static func sum_affix_stats(affixes: Array) -> Dictionary:
	_ensure_loaded()
	var sums: Dictionary = {}
	for af_inst in affixes:
		var def: Dictionary = _affixes_by_id.get(af_inst.id, {})
		if def.is_empty():
			continue
		var stat: String = String(def.stat)
		sums[stat] = sums.get(stat, 0) + int(af_inst.value)
	return sums
