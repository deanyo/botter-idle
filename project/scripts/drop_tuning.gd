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
# §2.B (S12): the single tail_weight_mult collapsed both ends of the
# quality curve into one knob — boosting low-quality drops always
# ALSO boosted the top-tier (Masterwork/Sublime). Split into
# low_quality_tail_mult + high_quality_tail_mult so the authoring
# portal can dial each tail independently. Legacy `tail_weight_mult`
# is honored as a fallback for both halves to avoid breaking saves /
# JSON-edits that haven't migrated.
static func quality_tail_mult() -> float:
	_ensure_loaded()
	return float(_data.get("quality", {}).get("tail_weight_mult", 1.0))

static func low_quality_tail_mult() -> float:
	_ensure_loaded()
	var q: Dictionary = _data.get("quality", {})
	# Split key wins; fall through to legacy single key.
	if q.has("low_quality_tail_mult"):
		return float(q["low_quality_tail_mult"])
	return float(q.get("tail_weight_mult", 1.0))

static func high_quality_tail_mult() -> float:
	_ensure_loaded()
	var q: Dictionary = _data.get("quality", {})
	if q.has("high_quality_tail_mult"):
		return float(q["high_quality_tail_mult"])
	return float(q.get("tail_weight_mult", 1.0))

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

# §2.A (S12) — band weights consumed by LootFactory.roll_rarity_for_class.
# Per-tier × floor-band [common, uncommon, rare, epic, legendary] weights
# authored under §1.I. Returns the matching band as a 5-int Array;
# fallback to a hardcoded sane curve (mirrors the legacy hardcoded
# rarity ladder at floor 1) if any key is missing so absence-of-data
# can never crash a drop roll.
static func tier_drop_band(src_tier: int, current_floor: int) -> Array:
	_ensure_loaded()
	var bands: Dictionary = _data.get("tier_drop_band", {})
	var tier_key: String = "T%d" % clampi(src_tier, 1, 5)
	var tier_bands: Dictionary = bands.get(tier_key, {})
	# Floor band: 1-3 vs 4-6 per the authored shape.
	var band_key: String = "1-3" if current_floor <= 3 else "4-6"
	var weights: Variant = tier_bands.get(band_key, null)
	if weights is Array and (weights as Array).size() == 5:
		return weights
	# Fallback — pre-§2.A baseline curve (matches the old hardcoded
	# thresholds at floor 1, tier 1: 55% common / 30% unc / 15% rare /
	# 8% epic / 2% legendary, normalized).
	return [55, 30, 15, 8, 2]

static func boss_step() -> int:
	_ensure_loaded()
	return int(_data.get("tier_drop_band", {}).get("boss_step", 1))

static func elite_step() -> int:
	_ensure_loaded()
	return int(_data.get("tier_drop_band", {}).get("elite_step", 1))

static func trash_ceiling() -> String:
	_ensure_loaded()
	return String(_data.get("tier_drop_band", {}).get("trash_ceiling", "uncommon"))
