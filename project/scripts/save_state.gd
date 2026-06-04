class_name SaveState
extends RefCounted

const LIVE_PATH := "user://botter_save.json"
const DEBUG_PATH := "user://botter_save_debug.json"

# Set by main.gd when auto-grind / debug-jump markers are present so benchmark
# and screenshot runs don't pollute the live playtest save.
static var debug_mode: bool = false

static func _path() -> String:
	return DEBUG_PATH if debug_mode else LIVE_PATH

# Top-level save shape (multi-character):
#   {
#     "characters": [<char_dict>, ...],
#     "active":     <int>,
#   }
# Older single-character saves (pre-2026-06-04) get auto-wrapped into
# characters[0]. Callers never see the wrapper directly — load_state()
# always returns the ACTIVE character's dict; save_state() updates that
# slot. Multi-bot management uses list_characters / create_character /
# set_active / delete_character.

static func _load_wrapper() -> Dictionary:
	var path: String = _path()
	if not FileAccess.file_exists(path):
		return {"characters": [_default()], "active": 0}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {"characters": [_default()], "active": 0}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return {"characters": [_default()], "active": 0}
	var raw: Dictionary = parsed
	# Detect legacy single-character shape — top-level had `species`,
	# `equipped`, `inventory` etc. Wrap into characters[0].
	if not raw.has("characters") or typeof(raw.get("characters", [])) != TYPE_ARRAY:
		var legacy: Dictionary = raw
		# Fill missing defaults + run migrations.
		for k in _default().keys():
			if not legacy.has(k):
				legacy[k] = _default()[k]
		_migrate(legacy)
		return {"characters": [legacy], "active": 0}
	# Multi-character shape — fill defaults + migrate per character.
	var chars: Array = raw.get("characters", [])
	for ch in chars:
		if typeof(ch) != TYPE_DICTIONARY:
			continue
		for k in _default().keys():
			if not ch.has(k):
				ch[k] = _default()[k]
		_migrate(ch)
	if chars.is_empty():
		chars.append(_default())
	var active: int = clampi(int(raw.get("active", 0)), 0, chars.size() - 1)
	return {"characters": chars, "active": active}

static func _save_wrapper(wrapper: Dictionary) -> void:
	var f := FileAccess.open(_path(), FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(wrapper, "  "))

static func load_state() -> Dictionary:
	# Returns the active character's dict so existing callers don't need
	# to know about the wrapper. New character-management calls use the
	# top-level helpers below.
	var w: Dictionary = _load_wrapper()
	var chars: Array = w["characters"]
	var active: int = int(w["active"])
	return chars[active]

# Per-character utility helpers ------------------------------------------

# Return a copy of the wrapper for read-only inspection (e.g. main menu
# wants to list all bots without committing a save).
static func load_wrapper_readonly() -> Dictionary:
	return _load_wrapper()

# List all characters as a summary array. Each entry: {idx, species,
# level, runs_completed, gold, last_seen_timestamp}. Used by the
# main-menu bot picker.
static func list_characters() -> Array:
	var w: Dictionary = _load_wrapper()
	var out: Array = []
	for i in w.characters.size():
		var ch: Dictionary = w.characters[i]
		out.append({
			"idx":               i,
			"is_active":         i == int(w.active),
			"species":           String(ch.get("species", "spriggan")),
			"level":             int(ch.get("level", 1)),
			"runs_completed":    int(ch.get("runs_completed", 0)),
			"gold":              int(ch.get("gold", 0)),
			"last_seen_timestamp": int(ch.get("last_seen_timestamp", 0)),
		})
	return out

# Create a new character with the given species. Becomes active. Returns
# the new index. Each character is a fresh _default() with `species`
# replaced + starter gear filtered by the species' disallowed_slots
# (an Octopode shouldn't start with body armor it can't equip) +
# extra ring slot keys initialized for species that convert
# (Octopode → 3 extra rings, Naga → 1 extra ring).
static func create_character(species: String) -> int:
	var w: Dictionary = _load_wrapper()
	var ch: Dictionary = _default()
	ch["species"] = species
	var equipped: Dictionary = ch.get("equipped", {})
	# Strip starter gear in disallowed slots.
	var disallowed: Array = SpeciesData.disallowed_slots(species)
	for slot in disallowed:
		equipped[slot] = null
	# Init extra ring slot keys (ring2 / ring3 / ring4) for species
	# that get them via slot_conversions. The slot ids match what
	# Bot.equip_from_inventory expects.
	for ring_id in SpeciesData.ring_slot_ids(species):
		if not equipped.has(ring_id):
			equipped[ring_id] = null
	# Starter spell — every species ships with one autocast spell
	# pre-equipped to spell1 so combat is interesting from minute one.
	# Item id is "starter_<species>_spell" and lives in items.json.
	# spell2..spell5 stay empty until drops/shop fill them.
	equipped["spell1"] = {
		"base_id": "starter_" + species + "_spell",
		"instance_id": "starter_spell_" + species,
		"affixes": [],
	}
	ch["equipped"] = equipped
	w.characters.append(ch)
	w["active"] = w.characters.size() - 1
	_save_wrapper(w)
	return int(w["active"])

# Switch the active character. Out-of-range = no-op.
static func set_active(idx: int) -> void:
	var w: Dictionary = _load_wrapper()
	if idx < 0 or idx >= w.characters.size():
		return
	w["active"] = idx
	_save_wrapper(w)

# Delete a character. Cannot delete the last one. Active shifts to a
# valid neighbor.
static func delete_character(idx: int) -> void:
	var w: Dictionary = _load_wrapper()
	if w.characters.size() <= 1:
		return
	if idx < 0 or idx >= w.characters.size():
		return
	w.characters.remove_at(idx)
	if int(w.active) >= w.characters.size():
		w["active"] = w.characters.size() - 1
	elif int(w.active) > idx:
		w["active"] = int(w.active) - 1
	_save_wrapper(w)

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
	# Spell slots added 2026-06-04 (combat pivot to autocast). Five
	# slots default empty — existing characters can pick up their
	# first spell from a tome chest or shop. Forward-compat init.
	for sk in ["spell1", "spell2", "spell3", "spell4", "spell5"]:
		if not equipped.has(sk):
			equipped[sk] = null
	# Run-active fields added 2026-06-04 (combat pivot — death no longer
	# permadeaths the run). Idempotent forward-compat init.
	if not state.has("run_active"):
		state["run_active"] = false
	if not state.has("run_branch"):
		state["run_branch"] = ""
	if not state.has("run_floor_reached"):
		state["run_floor_reached"] = 0
	# Item-overhaul v2 (2026-06-04): stat-point allocation. Existing
	# characters get retroactive points = 3 × (level - 1) the first time
	# they load post-overhaul, fully unspent so the player can allocate.
	if not state.has("stat_points_unspent"):
		state["stat_points_unspent"] = 3 * max(0, int(state.get("level", 1)) - 1)
	if not state.has("stat_alloc_str"):
		state["stat_alloc_str"] = 0
	if not state.has("stat_alloc_dex"):
		state["stat_alloc_dex"] = 0
	if not state.has("stat_alloc_int"):
		state["stat_alloc_int"] = 0
	# Starter spell grant for existing characters that were created
	# pre-pivot — give them their species' starter on spell1 so the
	# combat overhaul is immediately playable.
	if equipped.get("spell1", null) == null:
		var sp_id: String = String(state.get("species", "spriggan"))
		equipped["spell1"] = {
			"base_id": "starter_" + sp_id + "_spell",
			"instance_id": "starter_spell_" + sp_id,
			"affixes": [],
		}
	# Species selector added 2026-06-03. Existing saves had no species
	# field; default to "spriggan" since that's the sprite they were
	# wearing. New characters can pick any species at creation.
	if not state.has("species") or String(state["species"]) == "":
		state["species"] = "spriggan"
	# Body-shape correction (2026-06-04): if a character has gear
	# equipped in slots their species can't wear (e.g. an octopode
	# created before disallowed_slots existed got a starter chest),
	# unequip it back into inventory rather than silently keeping the
	# stat boost. Idempotent — running on a clean save no-ops.
	var sp_disallowed: Array = SpeciesData.disallowed_slots(String(state["species"]))
	if not sp_disallowed.is_empty():
		var inv: Array = state.get("inventory", [])
		for slot in sp_disallowed:
			var current: Variant = equipped.get(slot, null)
			if current != null and typeof(current) == TYPE_DICTIONARY:
				inv.append(current)
				equipped[slot] = null
		state["inventory"] = inv
		state["equipped"] = equipped
	# Extra ring slot init for species with slot_conversions
	# (octopode 3 rings, naga 1 ring). Idempotent.
	for ring_id in SpeciesData.ring_slot_ids(String(state["species"])):
		if not equipped.has(ring_id):
			equipped[ring_id] = null
	state["equipped"] = equipped
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
	# Stamp the active character with wall time + persist to disk.
	# Existing callers pass a single-character dict (from load_state);
	# we slot it back into the wrapper at the active index.
	state["last_seen_timestamp"] = int(Time.get_unix_time_from_system())
	var w: Dictionary = _load_wrapper()
	var active: int = int(w.get("active", 0))
	if active < 0 or active >= w.characters.size():
		# Wrapper somehow desynced — recover by writing a single-char
		# wrapper. Avoids losing the player's data on a corrupt file.
		w = {"characters": [state], "active": 0}
	else:
		w.characters[active] = state
	_save_wrapper(w)

static func _default() -> Dictionary:
	# Starter gear: gives a level-1 fresh bot a fighting chance and ensures
	# the weapon overlay sprite has something to render. Chosen for shape
	# (dagger -> simple silhouette) and balance (low stats).
	return {
		# Picked at character creation; locked per character. Defaults
		# to "spriggan" because that matches the historic bot sprite —
		# pre-character-select saves migrate to spriggan via _migrate.
		"species": "spriggan",
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
			# Five autocast spell slots. Every species ships with a starter
			# spell pre-equipped to spell1; the remaining four start empty
			# and fill via mob drops, shop entries, tome chests, and boss
			# guarantees. The default spriggan-flavored starter sits in
			# spell1 — create_character() / _migrate() overwrite it with
			# the chosen species' starter when species changes from default.
			"spell1": {
				"base_id": "starter_spriggan_spell",
				"instance_id": "starter_spell_spriggan",
				"affixes": [],
			},
			"spell2": null,
			"spell3": null,
			"spell4": null,
			"spell5": null,
		},
		"runs_completed": 0,
		"highest_floor": 0,
		# Item-overhaul v2: stat-point allocation. Each level grants 3
		# unspent points; player allocates via the outpost stats panel.
		# Free respec from outpost (resets alloc, refills unspent to
		# 3 × level).
		"stat_points_unspent": 0,
		"stat_alloc_str": 0,
		"stat_alloc_dex": 0,
		"stat_alloc_int": 0,
		# "Run active" flag — set true on Deploy, false on Victory or
		# explicit End-Run. Death keeps it true so the outpost button
		# reads "Redeploy → Floor N" instead of "Deploy" until the
		# player actively cleans up. Combat pivot 2026-06-04.
		"run_active": false,
		"run_branch": "",
		"run_floor_reached": 0,
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
