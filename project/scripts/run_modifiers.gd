class_name RunModifiers
extends RefCounted

# Per-deploy random modifiers (Treasure Hoard, Crowded, Endless, etc.).
# Outpost rolls 1-2 per branch on visit; dungeon reads them at run start
# and folds the effects into spawn / loot / floor-count systems. Same
# static API shape as BiomeData / BotUpgrades so callers don't need an
# instance.

const PATH := "res://data/modifiers.json"

static var _defs: Array = []
static var _by_id: Dictionary = {}
static var _loaded: bool = false

static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		push_error("modifiers.json not found")
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("modifiers.json malformed")
		return
	_defs = parsed.get("modifiers", [])
	for d in _defs:
		_by_id[String(d.id)] = d

static func get_def(id: String) -> Dictionary:
	_ensure_loaded()
	return _by_id.get(id, {})

# Roll 1-2 modifiers eligible for the given branch. Returns an Array of
# modifier IDs. Idempotent for a given RNG seed.
static func roll_for_branch(branch_id: String, rng: RandomNumberGenerator) -> Array:
	_ensure_loaded()
	var tier: int = BiomeData.tier_for_biome(branch_id)
	var pool: Array = []
	for d in _defs:
		if int(d.get("min_tier", 1)) <= tier:
			pool.append(String(d.id))
	if pool.is_empty():
		return []
	# 1-2 modifiers. Bias toward 1 (60%) over 2 (40%).
	var n: int = 1 if rng.randf() < 0.6 else 2
	n = mini(n, pool.size())
	var picked: Array = []
	while picked.size() < n:
		var pick: String = pool[rng.randi() % pool.size()]
		if not picked.has(pick):
			picked.append(pick)
	return picked

# Sum the named effect across a list of modifier IDs. Defaults to 0 for
# additive (extra_chests_per_floor, extra_floors, rarity_bonus) and 1.0
# for multiplicative (enemy_count_mult, gold_mult, etc) — caller chooses
# which by passing the right default.
static func sum_effect(mod_ids: Array, key: String, default: float) -> float:
	_ensure_loaded()
	var result: float = default
	var is_multiplicative: bool = key.ends_with("_mult")
	for id in mod_ids:
		var def: Dictionary = _by_id.get(String(id), {})
		if def.is_empty():
			continue
		var effects: Dictionary = def.get("effects", {})
		if not effects.has(key):
			continue
		var v: float = float(effects[key])
		if is_multiplicative:
			result *= v
		else:
			result += v
	return result

# True if any of the modifiers wants an extra miniboss on the given floor.
static func has_extra_miniboss_on(mod_ids: Array, floor_num: int) -> bool:
	_ensure_loaded()
	for id in mod_ids:
		var def: Dictionary = _by_id.get(String(id), {})
		if def.is_empty():
			continue
		var floor_target: int = int(def.get("effects", {}).get("extra_miniboss_on_floor", -1))
		if floor_target == floor_num:
			return true
	return false

# Format human-readable name + desc for UI tooltips.
static func format_brief(mod_ids: Array) -> String:
	_ensure_loaded()
	if mod_ids.is_empty():
		return ""
	var parts: Array = []
	for id in mod_ids:
		var def: Dictionary = _by_id.get(String(id), {})
		if not def.is_empty():
			parts.append("+" + String(def.name))
	return " · ".join(parts)

static func format_tooltip(mod_ids: Array) -> String:
	_ensure_loaded()
	if mod_ids.is_empty():
		return ""
	var lines: Array = []
	for id in mod_ids:
		var def: Dictionary = _by_id.get(String(id), {})
		if not def.is_empty():
			lines.append("%s — %s" % [String(def.name), String(def.desc)])
	return "\n".join(lines)
