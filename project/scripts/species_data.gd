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
#   hp_pct      float  — multiplicative on the StatCalc max_hp roll-up
#   atk_pct     float  — multiplicative on damage_min/max after flat upgrades
#   def_pct     float  — multiplicative on armor after flat upgrades
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

# Slot conversions per species (DCSS body-shape pattern). Octopode
# loses armor/boots/helm — those slots are CONVERTED to extra ring
# slots so the build identity is "ring stacking" instead of "you
# just lost armor." Naga loses boots → 1 extra ring (their barding-
# replacement). Empty = no conversions, all slots usable normally.
#
# Schema in species.json:
#   slot_conversions: { "armor": "ring", "boots": "ring", "helm": "ring" }
# Reads as: original `armor` slot is replaced with an extra `ring`
# slot. Equip flow routes ring-slot items into ring/ring2/ring3/ring4
# depending on species; non-ring items in converted slots can never
# be equipped.
static func slot_conversions(id: String) -> Dictionary:
	var d: Dictionary = get_def(id)
	return d.get("slot_conversions", {})

# The set of slots a species CANNOT equip its native item in. Derived
# from slot_conversions keys for back-compat with code that asks
# "can species X wear slot Y." A converted slot is "disallowed" in
# the sense that the original-shape item won't fit; the converted-
# target item (a ring, usually) is what goes there instead.
static func disallowed_slots(id: String) -> Array:
	var conv: Dictionary = slot_conversions(id)
	# Legacy fallback for any species still using the old field.
	if conv.is_empty():
		var d: Dictionary = get_def(id)
		return d.get("disallowed_slots", [])
	return conv.keys()

# Convenience: true if this species can wear gear in `slot`. Reads
# the disallowed list; converted slots show up as disallowed.
static func can_wear(id: String, slot: String) -> bool:
	return not (slot in disallowed_slots(id))

# How many extra ring slots this species gets via slot_conversions.
# Octopode has 3 (armor + boots + helm all → ring); naga has 1.
# Default species: 0. Read by save schema (creates ring2..ringN keys
# on character creation), bot equip flow (resolves "ring" → first
# empty), and paperdoll layout (renders extra ring cells instead of
# the original slots).
static func extra_ring_slots(id: String) -> int:
	var conv: Dictionary = slot_conversions(id)
	var n: int = 0
	for src in conv:
		if String(conv[src]) == "ring":
			n += 1
	return n

# Returns ["ring", "ring2", "ring3", ...] for the active species —
# all ring slot ids the bot has access to. Always includes the base
# "ring" slot.
static func ring_slot_ids(id: String) -> Array:
	var out: Array = ["ring"]
	for i in range(1, extra_ring_slots(id) + 1):
		out.append("ring" + str(i + 1))
	return out

# True iff the named species carries `tag` in its innate_tags array.
# Used by S5 race-anchor gating: items with `requires_innate_tag` only
# fire their implicit_affixes when the wearer's species matches.
# Empty/unknown id → false (humans return false for every tag — the
# baseline-by-design choice from a04 §5.1).
static func has_innate_tag(species_id: String, tag: String) -> bool:
	if species_id == "" or tag == "":
		return false
	var d: Dictionary = get_def(species_id)
	for t in d.get("innate_tags", []):
		if String(t) == tag:
			return true
	return false
