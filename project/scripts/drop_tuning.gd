class_name DropTuning
extends RefCounted

# Loader for project/data/drop_tuning.json — central tunable config
# the authoring portal can edit via sliders. Loaded once at boot;
# fields exposed as static getters with hardcoded fallbacks if a key
# is missing (so removing a key from the file never breaks the game).
#
# Item-overhaul follow-up 2026-06-04.

const PATH := "res://data/drop_tuning.json"

static var _data: Dictionary = {}
static var _loaded: bool = false

static func _ensure_loaded() -> void:
	if _loaded:
		return
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		_loaded = true
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) == TYPE_DICTIONARY:
		_data = parsed
	_loaded = true

# Meta-rarity drop chances (post-quality, independent of rarity).
static func primal_chance() -> float:
	_ensure_loaded()
	return float(_data.get("meta_rarity", {}).get("primal_chance", 0.001))

static func ancient_chance() -> float:
	_ensure_loaded()
	return float(_data.get("meta_rarity", {}).get("ancient_chance", 0.011))

# Quality tail-weight multiplier (applied to Rusted/Worn/Battered AND
# Mastercrafted/Masterwork tail entries).
static func quality_tail_mult() -> float:
	_ensure_loaded()
	return float(_data.get("quality", {}).get("tail_weight_mult", 1.0))

# Enchant rolls. global_chance_mult scales every item's authored
# enchant_chance; combo_chance is the secondary roll AFTER the first
# enchant lands.
static func enchant_chance_mult() -> float:
	_ensure_loaded()
	return float(_data.get("enchant", {}).get("global_chance_mult", 1.0))

static func enchant_combo_chance() -> float:
	_ensure_loaded()
	return float(_data.get("enchant", {}).get("combo_chance", 0.03))

# Tint / recolor rolls (item_recolor.gdshader).
static func tint_any_chance() -> float:
	_ensure_loaded()
	return float(_data.get("tint_recolor", {}).get("any_tint_chance", 0.30))

static func tint_shimmer_chance() -> float:
	_ensure_loaded()
	return float(_data.get("tint_recolor", {}).get("shimmer_chance", 0.005))

static func tint_inverted_chance() -> float:
	_ensure_loaded()
	return float(_data.get("tint_recolor", {}).get("inverted_chance", 0.001))

static func tint_prismatic_chance() -> float:
	_ensure_loaded()
	return float(_data.get("tint_recolor", {}).get("prismatic_chance", 0.0005))
