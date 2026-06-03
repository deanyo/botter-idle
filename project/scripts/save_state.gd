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
	_migrate(state)
	return state

# In-place migrations applied on load. Idempotent — running twice is a no-op.
static func _migrate(state: Dictionary) -> void:
	# Ring collapse (2026-06-02): old saves had ring1/ring2 slots; new layout
	# uses one `ring` slot. Promote ring1 (or ring2 if ring1 was empty); push
	# the displaced ring2 item, if any, to the inventory so it isn't lost.
	var equipped: Dictionary = state.get("equipped", {})
	# Gloves + cloak slots added 2026-06-03. Ensure existing saves
	# have the keys present (default null) so equip flow can populate
	# them without missing-key errors. Forward-compat only — nothing
	# to migrate AWAY from since these slots didn't exist before.
	if not equipped.has("gloves"):
		equipped["gloves"] = null
	if not equipped.has("cloak"):
		equipped["cloak"] = null
	if not equipped.has("ring") or equipped.get("ring", null) == null:
		var promote: Variant = equipped.get("ring1", null)
		if promote == null:
			promote = equipped.get("ring2", null)
			equipped["ring2"] = null
		if promote != null:
			equipped["ring"] = promote
	# If both old slots were full, ring1 went into the new `ring` slot above
	# and ring2's item still lives at equipped.ring2 — push it to inventory
	# rather than silently drop it.
	var leftover: Variant = equipped.get("ring2", null)
	if leftover != null and typeof(leftover) == TYPE_DICTIONARY:
		var inv: Array = state.get("inventory", [])
		inv.append(leftover)
		state["inventory"] = inv
	equipped.erase("ring1")
	equipped.erase("ring2")
	state["equipped"] = equipped

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
			# DCSS-faithful slot list: ARM_GLOVES + ARM_CLOAK are
			# distinct from boots/armor in DCSS. Adding them lets us
			# correctly carry items like Fencer's Gloves and the
			# Ratskin Cloak instead of forcing them into boots/armor.
			"gloves": null,
			"cloak": null,
			# DCSS has two ring slots; we collapsed to one ring + one amulet
			# (amulet fills the trinket role) — clearer UX, every slot is
			# filled by something visually distinct, and players can always
			# equip a fresh pickup. Old saves with `ring2` still load (load_state
			# preserves unknown keys) but ring2 is no longer surfaced anywhere.
			"ring": null,
			"amulet": null,
		},
		"runs_completed": 0,
		"highest_floor": 0,
		# Tier 1 (the Dungeon) is unlocked from the start. Boss kills
		# extend this list — see dungeon.gd boss_killed signal.
		"unlocked_branches": ["dungeon"],
		# Per-branch boss-kill counts. Drives the "clear every tier-N
		# boss to unlock tier-(N+1)" progression rule. {branch_id: count}.
		"bosses_killed": {},
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
		# Per-branch run modifiers, rolled fresh on Outpost visit when
		# empty. {branch_id: [modifier_id, ...]}. Cleared after a deploy
		# of that branch so the next visit re-rolls.
		"branch_modifiers": {},
		# Reserved for future systems (gold-sink upgrades, prestige currency,
		# offline-progress timestamps). Leaving the keys present means save
		# loads don't need to add-with-defaults branches when those land.
		"bot_upgrades": {},
		"shards": 0,
		"last_seen_timestamp": 0,
		# Shop state — rotating real-time stock + daily modifier. The
		# shop refreshes every SHOP_REFRESH_SECS (~15 minutes) measured
		# against last_refresh_ts. Stock is an array of item instances
		# (same shape as inventory items), modifier_id is one entry from
		# data/shop_modifiers.json. shop.gd handles all reads/writes.
		"shop": {
			"last_refresh_ts": 0,
			"stock": [],
			"modifier_id": "",
		},
	}
