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
	"burning":  { "icon": "fire.png",   "tint": Color(1, 0.55, 0.20), "pulse": true,  "z": 5,
		"label": "Burning", "desc": "Taking fire damage over time." },
	"poisoned": { "icon": "poison.png", "tint": Color(0.55, 1, 0.45), "pulse": true,  "z": 4,
		"label": "Poisoned", "desc": "Taking poison damage over time." },
	"frozen":   { "icon": "frost.png",  "tint": Color(0.55, 0.85, 1), "pulse": false, "z": 6,
		"label": "Frozen", "desc": "Vulnerable: incoming attacks deal +20%." },
	"slowed":   { "icon": "drop.png",   "tint": Color(0.45, 0.7, 1), "pulse": false, "z": 2,
		"label": "Slowed", "desc": "Movement speed reduced (in water)." },
	"regen":    { "icon": "plus.png",   "tint": Color(0.55, 1, 0.6), "pulse": true,  "z": 3,
		"label": "Regen", "desc": "Healing per second from gear/blessings." },
	"berserk":  { "icon": "rage.png",   "tint": Color(1, 0.3, 0.2), "pulse": true,   "z": 7,
		"label": "Berserk", "desc": "Increased attack speed and power." },
	"blessed":  { "icon": "halo.png",   "tint": Color(1, 0.95, 0.55), "pulse": false, "z": 1,
		"label": "Blessed", "desc": "Granted divine favor at an altar." },
	"wounded":  { "icon": "blood.png",  "tint": Color(1, 0.25, 0.25), "pulse": true,  "z": 0,
		"label": "Wounded", "desc": "Below 30% HP — retreat or finish the fight." },
	"shielded": { "icon": "ward.png",   "tint": Color(0.6, 0.85, 1), "pulse": false, "z": 8,
		"label": "Shielded", "desc": "Reducing or absorbing damage." },
}

# Enemy-id substrings that classify each holy/bane category. The
# `holy` weapon tag deals +50% to anything matching `undead` or
# `demon`; `dragon_bane` matches dragons/wyrms. Substring match is
# loose on purpose — DCSS does roughly the same via mons-classid.h.
const HOLY_HATES := ["undead", "zombie", "skeleton", "wraith", "lich",
	"mummy", "ghost", "vampire", "shadow", "demon", "cacodemon", "imp",
	"hellion", "balrog", "fiend"]
const DRAGON_HATES := ["dragon", "wyrm", "drake"]

static func enemy_matches_any(enemy_id: String, needles: Array) -> bool:
	if enemy_id == "":
		return false
	var lc: String = enemy_id.to_lower()
	for needle in needles:
		if lc.find(String(needle)) >= 0:
			return true
	return false

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
