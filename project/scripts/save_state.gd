class_name SaveState
extends RefCounted

const LIVE_PATH := "user://botter_save.json"
const DEBUG_PATH := "user://botter_save_debug.json"

# Set by main.gd when auto-grind / debug-jump markers are present so benchmark
# and screenshot runs don't pollute the live playtest save.
static var debug_mode: bool = false

static func _path() -> String:
	return DEBUG_PATH if debug_mode else LIVE_PATH

static func load_state() -> Dictionary:
	var path: String = _path()
	if not FileAccess.file_exists(path):
		return _default()
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return _default()
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return _default()
	var state: Dictionary = parsed
	for k in _default().keys():
		if not state.has(k):
			state[k] = _default()[k]
	return state

static func save_state(state: Dictionary) -> void:
	# Stamp the save with the current wall time so launch can compute
	# offline_seconds = now - last_seen_timestamp on the next boot. Done
	# here (not at run-end) so even mid-session saves accurately reflect
	# "when the game was last alive".
	state["last_seen_timestamp"] = int(Time.get_unix_time_from_system())
	var f := FileAccess.open(_path(), FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(state, "  "))

static func _default() -> Dictionary:
	# Starter gear: gives a level-1 fresh bot a fighting chance and ensures
	# the weapon overlay sprite has something to render. Chosen for shape
	# (dagger -> simple silhouette) and balance (low stats).
	return {
		"gold": 0,
		"level": 1,
		"xp": 0,
		"inventory": [],
		"equipped": {
			"weapon": {
				"base_id": "rusty_dagger",
				"instance_id": "starter_weapon",
				"affixes": [],
			},
			"armor": {
				"base_id": "tattered_hide",
				"instance_id": "starter_armor",
				"affixes": [],
			},
			"helm": null,
			"boots": null,
			"shield": null,
		},
		"runs_completed": 0,
		"highest_floor": 0,
		# Tier 1 (the Dungeon) is unlocked from the start. Boss kills
		# extend this list — see dungeon.gd boss_killed signal.
		"unlocked_branches": ["dungeon"],
		# Death retreat: max revives per run. On HP=0 the bot respawns at
		# floor 1 of the current branch instead of run-end, until revives
		# run out. Scaling later via bot upgrade ranks / gear affixes.
		"max_revives": 3,
		# Gear bloat controls. loot_filter: bot walks past loot below this
		# rarity (default common = everything goes in the bag). inventory_cap:
		# hard ceiling triggering auto-salvage when exceeded.
		"loot_filter": "common",
		"inventory_cap": 50,
		# Last branch the player deployed to. Offline progress simulates
		# floors of this branch while the game was closed. Empty until the
		# first deploy.
		"last_branch": "",
		# Reserved for future systems (gold-sink upgrades, prestige currency,
		# offline-progress timestamps). Leaving the keys present means save
		# loads don't need to add-with-defaults branches when those land.
		"bot_upgrades": {},
		"shards": 0,
		"last_seen_timestamp": 0,
	}
