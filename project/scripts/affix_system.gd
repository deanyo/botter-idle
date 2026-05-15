class_name AffixSystem
extends RefCounted

const AFFIXES_PATH := "res://data/affixes.json"

static var _affixes_by_id: Dictionary = {}
static var _rarity_count: Dictionary = {}
static var _rarity_idx: Dictionary = {}
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
	_loaded = true

static func roll_affixes_for(item: Dictionary, rng: RandomNumberGenerator) -> Array:
	_ensure_loaded()
	var rarity: String = String(item.get("rarity", "common"))
	var slot: String = String(item.get("slot", ""))
	var n: int = int(_rarity_count.get(rarity, 0))
	if n <= 0:
		return []
	var tier_idx: int = int(_rarity_idx.get(rarity, 0))
	var pool: Array = []
	for id in _affixes_by_id.keys():
		var af: Dictionary = _affixes_by_id[id]
		var applies: Array = af.applies_to
		if applies.has(slot) or applies.has("any"):
			pool.append(af)
	var rolled: Array = []
	var used_ids: Dictionary = {}
	_roll_from(pool, n, used_ids, rolled, tier_idx, rng)
	return rolled

static func _roll_from(pool: Array, want: int, used_ids: Dictionary, into: Array, tier_idx: int, rng: RandomNumberGenerator) -> void:
	if pool.is_empty():
		return
	var attempts: int = 0
	while want > 0 and attempts < 30:
		attempts += 1
		var pick: Dictionary = pool[rng.randi_range(0, pool.size() - 1)]
		if used_ids.has(pick.id):
			continue
		used_ids[pick.id] = true
		var tiers: Array = pick.tiers
		var value: int = int(tiers[mini(tier_idx, tiers.size() - 1)])
		into.append({"id": pick.id, "value": value})
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
	return "\n".join(lines)

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
