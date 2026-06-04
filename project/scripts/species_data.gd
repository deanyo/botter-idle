class_name SpeciesData
extends RefCounted

# Player species roster. Loaded once from data/species.json and held
# in static fields. Bot.recompute_stats reads via get_def() to apply
# the species-specific stat modifiers.
#
# Schema per entry:
#   id          string — primary key
#   name        string — display name
#   sprite      string — filename under assets/tiles/player/species/
#   lore        string — flavor text shown on character-create
#   hp_pct      float  — multiplicative on base_max_hp
#   atk_pct     float  — multiplicative on base_atk
#   def_pct     float  — multiplicative on base_def
#   haste_pct   float  — additive on Haste % (caps at 200 like everything else)
#   crit_flat   float  — additive on crit_chance
#   regen_flat  float  — additive on hp_regen_per_sec
#   aggro_flat  int    — additive on Bot.aggro_bonus (drives AGGRO_DISTANCE)
#   xp_pct      float  — additive on xp_gain_pct
#   loot_pct    float  — additive on loot_rarity_bonus
#   innate_tags array  — flavor tags every member of the species carries
#                        as if they were defender-worn (vampire→"vampiric",
#                        demonspawn→"demon"). Read by combat_defense_tags.

const PATH := "res://data/species.json"

static var _by_id: Dictionary = {}
static var _all: Array = []
static var _loaded: bool = false
static var _default_id: String = "spriggan"

static func _ensure_loaded() -> void:
	if _loaded:
		return
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		push_error("Failed to open species.json")
		_loaded = true
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Failed to parse species.json")
		_loaded = true
		return
	var data: Dictionary = parsed
	for sp in data.get("species", []):
		var d: Dictionary = sp
		_by_id[d.id] = d
		_all.append(d)
	_loaded = true

static func all() -> Array:
	_ensure_loaded()
	return _all

static func get_def(id: String) -> Dictionary:
	_ensure_loaded()
	if _by_id.has(id):
		return _by_id[id]
	# Unknown species id — fall back to default so the game never
	# crashes on a stale save. Logged once at first miss so we know
	# something drifted.
	if _by_id.has(_default_id):
		return _by_id[_default_id]
	return {}

static func sprite_path_for(id: String) -> String:
	var d: Dictionary = get_def(id)
	var sprite: String = String(d.get("sprite", ""))
	if sprite == "":
		return ""
	return "res://assets/tiles/player/species/" + sprite

# Slots this species cannot equip (DCSS body-shape restrictions).
# Octopode has no torso/feet/head; naga has no feet. Empty = can wear
# anything. Read by Bot.recompute_stats (skips contributions from
# disallowed slots' equipped items, just in case stale data lingers)
# AND by the equip flow (blocks new equips into disallowed slots).
static func disallowed_slots(id: String) -> Array:
	var d: Dictionary = get_def(id)
	return d.get("disallowed_slots", [])

# Convenience: true if this species can wear gear in `slot`.
static func can_wear(id: String, slot: String) -> bool:
	return not (slot in disallowed_slots(id))
