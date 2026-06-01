class_name StatusOverlay
extends RefCounted

# DCSS-style status-effect overlay registry.
#
# Each Actor (Bot + Enemies) can carry N visible status icons stacked
# above its sprite. Driven by mechanic-side hooks: lava cells add
# "burning", water cells add "slowed", altars add "blessed", etc.
# These mechanics already exist; ENCH just makes them visible so the
# player can SEE why the bot is at 30% HP.
#
# Pattern mirrors DCSS tiledoll.cc::TILEP_PART_ENCH — overlays are
# stat-status driven, not equipment driven.
#
# Adding a status: actor.add_status("burning", 0.6) — duration in
# seconds. Renewing extends. duration <= 0 = persistent until
# remove_status(id) is called explicitly (used for blessings).

const PLAYER_DIR := "res://assets/tiles/player/status/"

# Status definitions. Each:
#   icon  — sprite path under PLAYER_DIR
#   tint  — modulate color (allows one base sprite tinted variants)
#   pulse — true = sin-modulated alpha for emphasis
#   z     — render order within the status layer (higher = on top)
const STATUSES := {
	"burning":  { "icon": "fire.png",   "tint": Color(1, 0.55, 0.20), "pulse": true, "z": 5 },
	"poisoned": { "icon": "poison.png", "tint": Color(0.55, 1, 0.45), "pulse": true, "z": 4 },
	"frozen":   { "icon": "frost.png",  "tint": Color(0.55, 0.85, 1), "pulse": false, "z": 6 },
	"slowed":   { "icon": "drop.png",   "tint": Color(0.45, 0.7, 1), "pulse": false, "z": 2 },
	"regen":    { "icon": "plus.png",   "tint": Color(0.55, 1, 0.6), "pulse": true, "z": 3 },
	"berserk":  { "icon": "rage.png",   "tint": Color(1, 0.3, 0.2), "pulse": true, "z": 7 },
	"blessed":  { "icon": "halo.png",   "tint": Color(1, 0.95, 0.55), "pulse": false, "z": 1 },
	"wounded":  { "icon": "blood.png",  "tint": Color(1, 0.25, 0.25), "pulse": true, "z": 0 },
	"shielded": { "icon": "ward.png",   "tint": Color(0.6, 0.85, 1), "pulse": false, "z": 8 },
}

static func has_status(id: String) -> bool:
	return STATUSES.has(id)

static func get_def(id: String) -> Dictionary:
	return STATUSES.get(id, {})

# Texture loader. Caches per-id so we don't pay the disk hit on every
# add_status call. Returns null if the sprite asset is missing — the
# caller should treat that as "skip this overlay".
static var _tex_cache: Dictionary = {}

static func texture_for(id: String) -> Texture2D:
	if _tex_cache.has(id):
		return _tex_cache[id]
	var def: Dictionary = STATUSES.get(id, {})
	var icon: String = String(def.get("icon", ""))
	if icon == "":
		_tex_cache[id] = null
		return null
	var path: String = PLAYER_DIR + icon
	if not ResourceLoader.exists(path):
		_tex_cache[id] = null
		return null
	var t: Texture2D = load(path)
	_tex_cache[id] = t
	return t
