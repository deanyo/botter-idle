class_name BotUpgrades
extends RefCounted

# Permanent gold-sink upgrades. Static API mirrors BiomeData / AffixSystem
# so callers don't have to instantiate. Definitions live in
# data/bot_upgrades.json; player progress lives in save_state.bot_upgrades
# as a {upgrade_id: rank_int} dict.

const PATH := "res://data/bot_upgrades.json"

static var _defs: Array = []
static var _by_id: Dictionary = {}
static var _loaded: bool = false

static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		push_error("bot_upgrades.json not found")
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("bot_upgrades.json malformed")
		return
	_defs = parsed.get("upgrades", [])
	for d in _defs:
		_by_id[String(d.id)] = d

static func all() -> Array:
	_ensure_loaded()
	return _defs

static func get_def(id: String) -> Dictionary:
	_ensure_loaded()
	return _by_id.get(id, {})

# Sum the contributed value of an upgrade across all owned ranks. e.g.
# rank 3 of conditioning (per_rank=5) returns 15. Returns 0 if the
# upgrade isn't owned or isn't defined.
static func value_for(state: Dictionary, id: String) -> float:
	_ensure_loaded()
	var def: Dictionary = _by_id.get(id, {})
	if def.is_empty():
		return 0.0
	var owned: Dictionary = state.get("bot_upgrades", {})
	var rank: int = int(owned.get(id, 0))
	if rank <= 0:
		return 0.0
	return float(def.get("per_rank", 0)) * float(rank)

# Total contribution to a given engine stat across all upgrades. Used by
# bot.gd::recompute_stats to fold upgrades into base stats.
static func total_for_stat(state: Dictionary, stat: String) -> float:
	_ensure_loaded()
	var sum: float = 0.0
	var owned: Dictionary = state.get("bot_upgrades", {})
	for d in _defs:
		if String(d.get("stat", "")) != stat:
			continue
		var rank: int = int(owned.get(String(d.id), 0))
		if rank > 0:
			sum += float(d.get("per_rank", 0)) * float(rank)
	return sum

# Cost of the next rank of `id` for the player. Returns -1 if maxed.
static func next_rank_cost(state: Dictionary, id: String) -> int:
	_ensure_loaded()
	var def: Dictionary = _by_id.get(id, {})
	if def.is_empty():
		return -1
	var owned: Dictionary = state.get("bot_upgrades", {})
	var rank: int = int(owned.get(id, 0))
	var costs: Array = def.get("costs", [])
	if rank >= costs.size():
		return -1
	return int(costs[rank])

# Try to purchase the next rank. Mutates `state` (caller persists). Returns
# true on success.
static func try_buy(state: Dictionary, id: String) -> bool:
	_ensure_loaded()
	var cost: int = next_rank_cost(state, id)
	if cost < 0:
		return false
	if int(state.get("gold", 0)) < cost:
		return false
	var owned: Dictionary = state.get("bot_upgrades", {})
	owned[id] = int(owned.get(id, 0)) + 1
	state["bot_upgrades"] = owned
	state["gold"] = int(state["gold"]) - cost
	return true
