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

	var prefix_pool: Array = []
	var suffix_pool: Array = []
	for id in _affixes_by_id.keys():
		var af: Dictionary = _affixes_by_id[id]
		var applies: Array = af.applies_to
		if not (applies.has(slot) or applies.has("any")):
			continue
		if af.slot == "prefix":
			prefix_pool.append(af)
		else:
			suffix_pool.append(af)

	var rolled: Array = []
	var used_ids: Dictionary = {}
	var max_prefixes: int = int((n + 1) / 2.0)
	var max_suffixes: int = n - max_prefixes

	_roll_from(prefix_pool, max_prefixes, used_ids, rolled, tier_idx, rng)
	_roll_from(suffix_pool, max_suffixes, used_ids, rolled, tier_idx, rng)

	if rolled.size() < n:
		var remaining_pool: Array = prefix_pool + suffix_pool
		_roll_from(remaining_pool, n - rolled.size(), used_ids, rolled, tier_idx, rng)

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

static func format_item_name(base_name: String, affixes: Array) -> String:
	_ensure_loaded()
	var prefix_str := ""
	var suffix_str := ""
	for af_inst in affixes:
		var def: Dictionary = _affixes_by_id.get(af_inst.id, {})
		if def.is_empty():
			continue
		if def.slot == "prefix":
			prefix_str = String(def.name) + " "
		else:
			suffix_str = " " + String(def.name)
	return prefix_str + base_name + suffix_str

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
		"atk_pct": return "+%d%% ATK" % v
		"hp": return "+%d HP" % v
		"hp_pct": return "+%d%% HP" % v
		"def": return "+%d DEF" % v
		"crit_chance": return "+%d%% Crit" % v
		"crit_dmg": return "+%d%% Crit Dmg" % v
		"armor_pierce": return "+%d Armor Pierce" % v
		"lifesteal": return "%d Lifesteal" % v
		"block_chance": return "+%d%% Block" % v
		"thorns": return "%d Thorns" % v
		"move_speed_pct": return "+%d%% Move Spd" % v
		"atk_speed_pct": return "+%d%% Atk Spd" % v
		"gold_find_pct": return "+%d%% Gold Find" % v
		"magic_find_pct": return "+%d%% Magic Find" % v
		"xp_gain_pct": return "+%d%% XP" % v
		"hp_regen": return "%d HP/sec" % v
		"dodge_chance": return "+%d%% Dodge" % v
	return "+%d %s" % [v, stat]

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
