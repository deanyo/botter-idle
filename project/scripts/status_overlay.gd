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
const FEATURES_DIR := "res://assets/tiles/features/"

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
	"bleeding": { "icon": "blood.png",  "tint": Color(0.75, 0.10, 0.10), "pulse": true, "z": 4,
		"label": "Bleeding", "desc": "Taking flat physical damage over time (of_bloodletting)." },
	"smite":    { "icon": "halo.png",   "tint": Color(1.0, 0.95, 0.55), "pulse": true,  "z": 4,
		"label": "Smite", "desc": "Taking flat holy damage over time (of_zealous_strike)." },
	"revenge":  { "icon": "rage.png",   "tint": Color(1.0, 0.40, 0.10, 0.85), "pulse": true,  "z": 7,
		"label": "Revenge", "desc": "+damage for 3s after taking a hit (of_avenger)." },
	"marked":   { "icon": "ward.png",   "tint": Color(1.0, 0.30, 0.30, 0.95), "pulse": true,  "z": 6,
		"label": "Marked", "desc": "Takes +damage from all sources for 4s (of_hunter_mark)." },
	"recouping":{ "icon": "plus.png",   "tint": Color(0.40, 1.0, 0.55, 0.95), "pulse": true,  "z": 3,
		"label": "Recouping", "desc": "Healing a fraction of damage taken over 4s (of_recoup)." },
	"grace":    { "icon": "halo.png",   "tint": Color(0.55, 0.95, 0.65, 0.85), "pulse": true,  "z": 8,
		"label": "Grace Aura", "desc": "+evasion + DEX-spell damage while the aura ticks (spell_aura_grace)." },
	"wisdom":   { "icon": "halo.png",   "tint": Color(0.55, 0.75, 1.00, 0.85), "pulse": true,  "z": 8,
		"label": "Wisdom Aura", "desc": "+spell-cdr + INT-spell damage while the aura ticks (spell_aura_wisdom)." },
	"shielded": { "icon": "ward.png",   "tint": Color(0.6, 0.85, 1), "pulse": false, "z": 8,
		"label": "Shielded", "desc": "Reducing or absorbing damage." },
	"stunned":  { "icon": "rage.png",   "tint": Color(1, 0.9, 0.4), "pulse": true,   "z": 9,
		"label": "Stunned", "desc": "Skips next attack." },
	"stealthy": { "icon": "ward.png",   "tint": Color(0.4, 0.4, 0.8, 0.7), "pulse": false, "z": 0,
		"label": "Stealthy", "desc": "Next attack lands a +25% bonus." },
	# 2026-06-04 spell expansion. Blinded = miss chance increase from
	# Sandblast's Blinding Grit affix. Read by Actor.attempt_attack
	# alongside dodge math; 30% miss while up.
	"blinded":  { "icon": "ward.png",   "tint": Color(0.85, 0.75, 0.30, 0.85), "pulse": true, "z": 9,
		"label": "Blinded", "desc": "30% chance to miss attacks." },
	# S10 spell-archetype expansion. Wrath Charge writes "wrath" on the
	# bot for a HARD 4-second window — ephemeral_dmg_pct + ephemeral_spell_
	# dmg_pct each gain +20% while it ticks. of_lingering must NOT extend
	# this duration (a10 §3.2 prop-5 rescope: fixed 4s OR the +50% is
	# always-on at endgame). Curse of Brittlebone writes "cursed" on
	# enemies for 4s × duration_pct — incoming damage amplified +15%
	# (a10 rescope from +30%) and effective armor -50% on physical hits.
	"wrath":    { "icon": "rage.png",   "tint": Color(1, 0.45, 0.20, 0.95), "pulse": true,  "z": 10,
		"label": "Wrath", "desc": "+20% weapon AND spell damage (Wrath Charge)." },
	"cursed":   { "icon": "blood.png",  "tint": Color(0.55, 0.25, 0.55, 0.95), "pulse": true, "z": 4,
		"label": "Cursed", "desc": "+15% damage taken; armor halved (Curse of Brittlebone)." },
	# Per-god blessing statuses (2026-06-08). Replaces the single
	# generic "blessed" icon — each altar emits its own status with
	# its altar tile as the buff-bar icon, so the player sees a row
	# of distinct deities in the buff bar when they've blessed at
	# multiple altars in a run. Run-scoped: cleared at run start by
	# Bot.clear_blessings, never on floor descent.
	"blessed_trog":            { "icon": "res://assets/tiles/features/altar_trog.png",            "tint": Color(1.0, 0.30, 0.20),  "pulse": false, "z": 1, "label": "Trog's Rage",         "desc": "+20% ATK (run)" },
	"blessed_okawaru":         { "icon": "res://assets/tiles/features/altar_okawaru.png",         "tint": Color(0.85, 0.75, 0.40), "pulse": false, "z": 1, "label": "Okawaru's Boon",      "desc": "+15 ATK +5 DEF (run)" },
	"blessed_zin":             { "icon": "res://assets/tiles/features/altar_zin.png",             "tint": Color(1.0, 1.0, 0.70),   "pulse": false, "z": 1, "label": "Zin's Light",         "desc": "+30% Max HP (run)" },
	"blessed_elyvilon":        { "icon": "res://assets/tiles/features/altar_elyvilon.png",        "tint": Color(0.60, 1.0, 0.70),  "pulse": false, "z": 1, "label": "Elyvilon's Mercy",    "desc": "Regen 3 HP/sec (run)" },
	"blessed_vehumet":         { "icon": "res://assets/tiles/features/altar_vehumet.png",         "tint": Color(0.70, 0.40, 1.0),  "pulse": false, "z": 1, "label": "Vehumet's Power",     "desc": "+25% loot rarity (run)" },
	"blessed_kikubaaqudgha":   { "icon": "res://assets/tiles/features/altar_kikubaaqudgha.png",   "tint": Color(0.40, 0.20, 0.60), "pulse": false, "z": 1, "label": "Kiku's Hunger",       "desc": "Lifesteal 4 HP/hit (run)" },
	"blessed_sif_muna":        { "icon": "res://assets/tiles/features/altar_sif_muna.png",        "tint": Color(0.40, 0.70, 1.0),  "pulse": false, "z": 1, "label": "Sif Muna's Wisdom",   "desc": "+50% XP gain (run)" },
	"blessed_beogh":           { "icon": "res://assets/tiles/features/altar_beogh.png",           "tint": Color(0.90, 0.50, 0.20), "pulse": false, "z": 1, "label": "Beogh's Warband",     "desc": "+25% ATK (run)" },
	"blessed_makhleb":         { "icon": "res://assets/tiles/features/altar_makhleb.png",         "tint": Color(1.0, 0.40, 0.10),  "pulse": false, "z": 1, "label": "Makhleb's Frenzy",    "desc": "Lifesteal 6 HP/hit (run)" },
	"blessed_yredelemnul":     { "icon": "res://assets/tiles/features/altar_yredelemnul.png",     "tint": Color(0.50, 0.10, 0.40), "pulse": false, "z": 1, "label": "Yred's Reaping",      "desc": "+25 ATK (run)" },
	"blessed_the_shining_one": { "icon": "res://assets/tiles/features/altar_the_shining_one.png", "tint": Color(1.0, 0.95, 0.50),  "pulse": false, "z": 1, "label": "TSO's Halo",          "desc": "+15 DEF +20% Max HP (run)" },
	"blessed_lugonu":          { "icon": "res://assets/tiles/features/altar_lugonu.png",          "tint": Color(0.30, 0.10, 0.30), "pulse": false, "z": 1, "label": "Lugonu's Corruption", "desc": "+35% ATK (run)" },
	"blessed_jiyva":           { "icon": "res://assets/tiles/features/altar_jiyva.png",           "tint": Color(0.40, 0.85, 0.30), "pulse": false, "z": 1, "label": "Jiyva's Slime",       "desc": "Regen 5 HP/sec (run)" },
	"blessed_fedhas":          { "icon": "res://assets/tiles/features/altar_fedhas.png",          "tint": Color(0.30, 0.85, 0.40), "pulse": false, "z": 1, "label": "Fedhas's Garden",     "desc": "+40% Max HP (run)" },
	"blessed_cheibriados":     { "icon": "res://assets/tiles/features/altar_cheibriados.png",     "tint": Color(0.50, 0.50, 0.40), "pulse": false, "z": 1, "label": "Cheibriados's Patience", "desc": "+30 DEF (run)" },
	"blessed_xom":             { "icon": "res://assets/tiles/features/altar_xom.png",             "tint": Color(1.0, 0.40, 0.80),  "pulse": false, "z": 1, "label": "Xom's Whim",          "desc": "+50% ATK (run)" },
	"blessed_ashenzari":       { "icon": "res://assets/tiles/features/altar_ashenzari.png",       "tint": Color(0.70, 0.65, 0.45), "pulse": false, "z": 1, "label": "Ashenzari's Sight",   "desc": "+40% loot rarity (run)" },
	"blessed_dithmenos":       { "icon": "res://assets/tiles/features/altar_dithmenos.png",       "tint": Color(0.20, 0.20, 0.30), "pulse": false, "z": 1, "label": "Dithmenos's Shadow",  "desc": "+20 ATK +10 DEF (run)" },
	"blessed_gozag":           { "icon": "res://assets/tiles/features/altar_gozag.png",           "tint": Color(1.0, 0.85, 0.30),  "pulse": false, "z": 1, "label": "Gozag's Gold",        "desc": "+60% loot rarity (run)" },
	"blessed_qazlal":          { "icon": "res://assets/tiles/features/altar_qazlal.png",          "tint": Color(0.60, 0.70, 0.95), "pulse": false, "z": 1, "label": "Qazlal's Storm",      "desc": "+30% ATK (run)" },
	"blessed_nemelex":         { "icon": "res://assets/tiles/features/altar_nemelex.png",         "tint": Color(0.90, 0.40, 0.80), "pulse": false, "z": 1, "label": "Nemelex's Deck",      "desc": "+50% loot rarity (run)" },
	"blessed_ru":              { "icon": "res://assets/tiles/features/altar_ru.png",              "tint": Color(0.90, 0.85, 0.70), "pulse": false, "z": 1, "label": "Ru's Sacrifice",      "desc": "+75% ATK -25% Max HP (run)" },
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
	# Absolute paths (e.g. "res://assets/tiles/features/altar_trog.png")
	# pass through; bare filenames default to the player/status/ dir.
	var path: String = icon if icon.begins_with("res://") else PLAYER_DIR + icon
	if not ResourceLoader.exists(path):
		_tex_cache[id] = null
		return null
	var t: Texture2D = load(path)
	_tex_cache[id] = t
	return t
