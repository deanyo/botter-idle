class_name SaveState
extends RefCounted

const LIVE_PATH := "user://botter_save.json"
const DEBUG_PATH := "user://botter_save_debug.json"

# Set by main.gd when auto-grind / debug-jump markers are present so benchmark
# and screenshot runs don't pollute the live playtest save.
static var debug_mode: bool = false

# Warnings the most recent _load_wrapper produced. Cleared on every load.
# main.gd / main_menu.gd surface these to the user (e.g. "save recovered
# from backup", "3 items from your save no longer exist"). Saved to disk
# via state.last_load_warnings so the run-report-side UI can pick them up
# even if main reads on a different frame than where they were generated.
static var last_load_warnings: Array = []

static func _path() -> String:
	return DEBUG_PATH if debug_mode else LIVE_PATH

static func _tmp_path() -> String: return _path() + ".tmp"
static func _bak_path() -> String: return _path() + ".bak"

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
	last_load_warnings = []
	var path: String = _path()
	var primary_existed: bool = FileAccess.file_exists(path)
	# Try the primary file. If it parses, use it. If it exists but fails to
	# parse (truncated mid-write, JSON corruption), preserve the corrupted
	# bytes for forensic recovery and fall through to the .bak. Only after
	# both the primary and the .bak are exhausted do we hand back defaults.
	var primary: Variant = _try_load_file(path)
	if typeof(primary) == TYPE_DICTIONARY:
		# Downgrade refusal: if the file was written by a future build
		# (schema_version > SCHEMA_VERSION on any character), refuse to
		# overwrite. Migrating a future save backward is not safe — we
		# don't know what fields the future build added. Back the file
		# up under .future-<version>-<ts> and load defaults so the user
		# at least gets a playable game; their future save is preserved
		# for when they switch back to the newer build.
		var future_v: int = _max_schema_version(primary)
		if future_v > SCHEMA_VERSION:
			_quarantine_future(path, future_v)
			if primary_existed:
				last_load_warnings.append("save_from_future_build")
			return {"characters": [_default()], "active": 0}
		return _finalize_loaded_wrapper(primary)
	if primary_existed:
		_quarantine_corrupted(path)
		last_load_warnings.append("save_recovered_from_backup")
	# Fall back to the .bak written before the most recent atomic rotate.
	var bak_path: String = _bak_path()
	if FileAccess.file_exists(bak_path):
		var fallback: Variant = _try_load_file(bak_path)
		if typeof(fallback) == TYPE_DICTIONARY:
			var future_v_bak: int = _max_schema_version(fallback)
			if future_v_bak > SCHEMA_VERSION:
				_quarantine_future(bak_path, future_v_bak)
				last_load_warnings.append("save_from_future_build")
				return {"characters": [_default()], "active": 0}
			return _finalize_loaded_wrapper(fallback)
		# Backup is also unreadable — preserve it too so a human can
		# recover later, then hand back defaults.
		_quarantine_corrupted(bak_path)
		last_load_warnings.append("save_could_not_be_loaded")
	elif primary_existed:
		# Primary was corrupted and there was no .bak (first-ever save, or
		# rotate hadn't happened yet). Bump the warning from "recovered"
		# to "could not be loaded" — there was no recovery available.
		last_load_warnings.erase("save_recovered_from_backup")
		last_load_warnings.append("save_could_not_be_loaded")
	return {"characters": [_default()], "active": 0}

# Read + parse one file. Returns the parsed dict, or null on any failure
# (file missing, open failed, JSON parse failed, top-level not a dict).
# Uses JSON.new().parse() rather than JSON.parse_string() so a corrupted
# file routes through the JSON instance's error channel instead of
# emitting an engine-level push_error — the loader handles "is this
# corrupted" itself and a noisy engine error during recovery would be
# misleading (the recovery is working as designed).
static func _try_load_file(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var text: String = f.get_as_text()
	f.close()
	var json := JSON.new()
	var err: int = json.parse(text)
	if err != OK:
		return null
	var parsed: Variant = json.data
	if typeof(parsed) != TYPE_DICTIONARY:
		return null
	return parsed

# Wrap a parsed top-level dict in the canonical {"characters", "active"}
# shape, run migrations on each character, and validate equipped/inventory
# against the items_db so orphaned base_ids don't crash the equip pipeline.
#
# Order matters: _migrate runs BEFORE the default-key fill. If we filled
# defaults first the schema_version key from _default() would mask the
# missing-or-low version on a pre-v7 save and the migration chain would
# short-circuit instead of upgrading the shape.
static func _finalize_loaded_wrapper(raw: Dictionary) -> Dictionary:
	if not raw.has("characters") or typeof(raw.get("characters", [])) != TYPE_ARRAY:
		# Legacy single-character shape — top-level had `species`, `equipped`,
		# `inventory` etc. Wrap into characters[0].
		var legacy: Dictionary = raw
		_migrate(legacy)
		for k in _default().keys():
			if not legacy.has(k):
				legacy[k] = _default()[k]
		_backfill_equipped_slots(legacy)
		_validate_loaded_state(legacy)
		return {"characters": [legacy], "active": 0}
	var chars: Array = raw.get("characters", [])
	for ch in chars:
		if typeof(ch) != TYPE_DICTIONARY:
			continue
		_migrate(ch)
		for k in _default().keys():
			if not ch.has(k):
				ch[k] = _default()[k]
		_backfill_equipped_slots(ch)
		_validate_loaded_state(ch)
	if chars.is_empty():
		chars.append(_default())
	var active: int = clampi(int(raw.get("active", 0)), 0, chars.size() - 1)
	return {"characters": chars, "active": active}

# Ensure every character's `equipped` dict has every canonical slot
# key, defaulting any missing one to null. Idempotent.
#
# Why this runs unconditionally on every load (not just v0→v7
# migration): saves on disk at schema_version 9 have already passed
# the migration chain, so a one-shot backfill there wouldn't repair
# them. Some characters in the wild ended up with sparse equipped
# dicts ({ring, spell1..5, gloves, cloak} but no weapon/armor/helm/
# boots/shield/amulet) — bot.apply_gear copies that sparse dict, then
# every `equipped.get("weapon", null)` resolves to null forever, so
# the bot renders as "spriggan with just a spell." The original
# v0→v7 migration backfilled gloves/cloak/spell* but never the
# six base ARPG slots. Backfilling on every load patches the
# in-the-wild broken saves AND any future regression that produces
# a sparse dict (cheap belt-and-suspenders — the `not has(k)` probe
# is no-op for healthy saves).
static func _backfill_equipped_slots(state: Dictionary) -> void:
	var equipped: Dictionary = state.get("equipped", {})
	for sk in ["weapon", "armor", "helm", "boots", "shield",
	           "gloves", "cloak", "ring", "amulet",
	           "spell1", "spell2", "spell3", "spell4", "spell5"]:
		if not equipped.has(sk):
			equipped[sk] = null
	state["equipped"] = equipped

# Walk equipped + inventory, evict any item whose base_id no longer
# exists in items.json. Orphaned items are pushed to state.orphaned_items
# so a player who started a build around (say) `urand_arc_blade` doesn't
# wake up to find their weapon silently vanished — the entry is
# recoverable as soon as the item is re-added to the catalog.
#
# Audit fix 2026-06-09: items.json churn is constant during dev (renames,
# deletions). Pre-fix, equipping an orphan triggered cascading failures
# in StatCalc / paperdoll / tooltips. Post-fix, the orphan is sidelined,
# the slot is null, and a "N items hidden — saved separately" warning
# surfaces via state.last_load_warnings.
static func _validate_loaded_state(state: Dictionary) -> void:
	var items_db: Dictionary = ItemsDb.items()
	if items_db.is_empty():
		# Loader running before ItemsDb is warmed (rare — main._ready
		# preloads ItemsDb before scenes load). Skip rather than evict
		# every item on a save written by a healthy build.
		return
	var equipped: Dictionary = state.get("equipped", {})
	var orphans: Array = []
	for slot: String in equipped.keys():
		var inst: Variant = equipped[slot]
		if typeof(inst) != TYPE_DICTIONARY:
			continue
		var base_id: String = String(inst.get("base_id", ""))
		if base_id == "" or items_db.has(base_id):
			continue
		orphans.append(inst)
		equipped[slot] = null
	state["equipped"] = equipped
	var inv: Array = state.get("inventory", [])
	var kept: Array = []
	for inst in inv:
		if typeof(inst) != TYPE_DICTIONARY:
			continue
		var base_id: String = String(inst.get("base_id", ""))
		if base_id == "" or items_db.has(base_id):
			kept.append(inst)
		else:
			orphans.append(inst)
	if not orphans.is_empty():
		var prior: Array = state.get("orphaned_items", [])
		state["orphaned_items"] = prior + orphans
		state["inventory"] = kept
		last_load_warnings.append("orphan_items_count_%d" % orphans.size())

# Move a corrupted file to .corrupted-<unix_ts> so the next write doesn't
# clobber it. Best-effort — failure to rename does NOT abort the load
# (we still want to fall through to .bak).
static func _quarantine_corrupted(path: String) -> void:
	var ts: int = int(Time.get_unix_time_from_system())
	var quarantine: String = "%s.corrupted-%d" % [path, ts]
	var d := DirAccess.open("user://")
	if d == null:
		return
	# DirAccess.rename_absolute takes os-level paths; in Godot the user://
	# scheme resolves transparently for files in user_data. Use rename
	# (relative) when both are user:// paths.
	d.rename(path, quarantine)
	push_error("[save] corrupted file quarantined: %s" % quarantine)

# Move a future-version file aside so the user's newer-build save
# isn't overwritten by an older build. The newer build can still find
# it under user:// for forensic recovery.
static func _quarantine_future(path: String, future_v: int) -> void:
	var ts: int = int(Time.get_unix_time_from_system())
	var quarantine: String = "%s.future-v%d-%d" % [path, future_v, ts]
	var d := DirAccess.open("user://")
	if d == null:
		return
	d.rename(path, quarantine)
	push_error("[save] save from future build (v%d > v%d) preserved at %s" % [
		future_v, SCHEMA_VERSION, quarantine,
	])

# Highest schema_version found across any character in the wrapper.
# Returns 0 if the wrapper is in legacy single-character shape (no
# characters key) — those predate schema_version and migrate cleanly
# through _migrate_to_v7.
static func _max_schema_version(wrapper: Dictionary) -> int:
	if not wrapper.has("characters"):
		return int(wrapper.get("schema_version", 0))
	var max_v: int = 0
	var chars: Array = wrapper.get("characters", [])
	for ch in chars:
		if typeof(ch) == TYPE_DICTIONARY:
			max_v = max(max_v, int(ch.get("schema_version", 0)))
	return max_v

# Atomic write: write-to-tmp, rotate-old-to-bak, rename-tmp-to-final.
# A torn write leaves either the previous .bak intact (rename failed
# mid-flight) or the new .tmp on disk to be cleaned up next boot. The
# previous final never gets clobbered until the new tmp is fully flushed
# to disk.
static func _save_wrapper(wrapper: Dictionary) -> void:
	var path: String = _path()
	var tmp: String = _tmp_path()
	var bak: String = _bak_path()
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_error("[save] could not open %s for write" % tmp)
		return
	f.store_string(JSON.stringify(wrapper, "  "))
	# Force the bytes to disk before the rename so the final-name pointer
	# never moves to a half-flushed file.
	f.flush()
	f.close()
	var d := DirAccess.open("user://")
	if d == null:
		push_error("[save] could not open user:// for rename")
		return
	# Rotate previous final → .bak (if there is a previous final). Drop
	# the older .bak in the process — we keep at most one generation.
	if FileAccess.file_exists(path):
		if FileAccess.file_exists(bak):
			d.remove(bak)
		d.rename(path, bak)
	# Move .tmp into place. If this fails the previous .bak still has the
	# last-known-good save and the next load will find it.
	var err: int = d.rename(tmp, path)
	if err != OK:
		push_error("[save] rename %s -> %s failed (err=%d)" % [tmp, path, err])

static func load_state() -> Dictionary:
	# Returns the active character's dict so existing callers don't need
	# to know about the wrapper. New character-management calls use the
	# top-level helpers below.
	var w: Dictionary = _load_wrapper()
	var chars: Array = w["characters"]
	var active: int = int(w["active"])
	var ch: Dictionary = chars[active]
	# Stamp warnings the loader collected so UI surfaces (main menu,
	# run report) can read them without poking at module-level state.
	# Runtime-only — not persisted; on the next save the field is
	# unconditionally cleared so warnings don't haunt future loads.
	if not last_load_warnings.is_empty():
		ch["last_load_warnings"] = last_load_warnings.duplicate()
	else:
		ch.erase("last_load_warnings")
	return ch

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
	# New characters are already at the current schema. Stamp both the
	# version field and the historic ring-collapse flag so _migrate
	# short-circuits (the legacy ring-collapse block lives inside
	# _migrate_to_v7 which would otherwise wipe ring2 for octopode/naga).
	ch["schema_version"] = SCHEMA_VERSION
	ch["migration_v_ring_collapse"] = true
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

# Schema version for the save format. Bumped whenever a migration ships.
#
# Historical context: pre-2026-06-09 the save format had 6+ probe-based
# schema bumps that ran on every load via `if not state.has(key)` checks.
# Audit 2026-06-08 flagged the probe approach as unsafe — re-running an
# already-applied migration on a future save would silently re-fire it
# (the ring1/ring2 wipe regression that hit octopode/naga saves was an
# instance of this). Versioned chain replaces probe gating with explicit
# `if v < N` ordering. Starting at 7 acknowledges the historic bumps so
# any future references to "older save shapes" use real version numbers.
const SCHEMA_VERSION := 9

# In-place migrations applied on load. Idempotent — once schema_version
# matches SCHEMA_VERSION, every step short-circuits.
#
# Each migration step takes a state dict at version N and brings it to
# version N+1. Step bodies are unconditional inside their gate — the
# version check above replaces the historic `if not state.has(key)`
# probes. Steps must be IDEMPOTENT against the input version they
# expect (re-running v3→v4 on an already-v4 state must be a no-op).
static func _migrate(state: Dictionary) -> void:
	var v: int = int(state.get("schema_version", 0))
	if v < 7:
		_migrate_to_v7(state)
		v = 7
	if v < 8:
		_migrate_to_v8(state)
		v = 8
	if v < 9:
		_migrate_to_v9(state)
		v = 9
	state["schema_version"] = SCHEMA_VERSION

# v0 → v7: subsumes every historic probe-based migration into one step.
# These were applied unconditionally pre-2026-06-09 on every load via
# has-key probes. In the versioned chain they fire exactly once when an
# unstamped save is first loaded under the new format, then never again.
#
# Each block here corresponds to a historic schema bump:
#   - Gloves + cloak slots (2026-06-03)
#   - Spell slots 1-5 (2026-06-04 combat pivot)
#   - Run-active fields (2026-06-04)
#   - Stat-point allocation (2026-06-04 item-overhaul v2)
#   - Starter spell retroactive grant (2026-06-04)
#   - Species selector (2026-06-03)
#   - Body-shape correction for disallowed_slots (2026-06-04)
#   - Extra ring slot init for slot_conversion species
#   - Legacy ring1/ring2 → ring collapse (2026-06-02, gated 2026-06-08)
static func _migrate_to_v7(state: Dictionary) -> void:
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
	# Legacy ring1/ring2 → ring collapse (2026-06-02). Pre-collapse saves had
	# ring1 + ring2 slots; new layout has a single `ring` slot. Promote ring1
	# (or ring2 if ring1 was empty) into `ring`; push any displaced ring2
	# item to inventory rather than dropping it.
	#
	# ONE-TIME ONLY: gated on migration_v_ring_collapse. Pre-fix this ran on
	# every load — for octopode (4 rings) and naga (2 rings) it was wiping
	# ring2 every restart because their species init recreates ring2 as a
	# real slot, and the legacy block then promoted/inv-pushed it as if it
	# were a stale legacy key. Audit fix 2026-06-08.
	#
	# Skip entirely for species that legitimately use ring2 — the legacy
	# block has nothing to do for them; ring2 is part of their slot set,
	# never a key from the pre-collapse era.
	if not state.get("migration_v_ring_collapse", false):
		var ring_ids: Array = SpeciesData.ring_slot_ids(String(state["species"]))
		if not ("ring2" in ring_ids):
			if not equipped.has("ring") or equipped.get("ring", null) == null:
				var promote: Variant = equipped.get("ring1", null)
				if promote == null:
					promote = equipped.get("ring2", null)
					equipped["ring2"] = null
				if promote != null:
					equipped["ring"] = promote
			var leftover: Variant = equipped.get("ring2", null)
			if leftover != null and typeof(leftover) == TYPE_DICTIONARY:
				var inv: Array = state.get("inventory", [])
				inv.append(leftover)
				state["inventory"] = inv
			equipped.erase("ring1")
			equipped.erase("ring2")
			state["equipped"] = equipped
		state["migration_v_ring_collapse"] = true

# v7 → v8: rename rolled `of_venom` (pct) instances to `of_envenom`. The
# affix id collided with the older `of_venom` (range, poison_extra) in
# affixes.json — pre-2026-06-09 the loader silently overwrote one with
# the other. The pct version's instances on saves are disambiguated by
# the absence of `value_min` / `value_max` (range affixes carry both).
# Walk every char's equipped slots + inventory + container affix arrays
# and rename. Idempotent: once stamped at v8, re-running is a no-op
# because the matching ids are already migrated.
static func _migrate_to_v8(state: Dictionary) -> void:
	var equipped: Dictionary = state.get("equipped", {})
	for slot in equipped.keys():
		_v8_migrate_inst(equipped[slot])
	var inventory: Array = state.get("inventory", [])
	for inst in inventory:
		_v8_migrate_inst(inst)

static func _migrate_to_v9(state: Dictionary) -> void:
	# Bump default inventory_cap from 50 → 200. Players reported the cap
	# wasn't enforcing during play (shop bypassed it; soft-cap only
	# triggered at floor/run-end) and was too low even when it did. Old
	# saves carry the explicit 50 value, so a defaults-fill won't catch
	# them — apply the bump here for any save still on the legacy 50.
	# Custom values above 50 (player upgraded the cap) are preserved.
	if int(state.get("inventory_cap", 50)) <= 50:
		state["inventory_cap"] = 200

static func _v8_migrate_inst(inst: Variant) -> void:
	if typeof(inst) != TYPE_DICTIONARY:
		return
	var affixes: Variant = inst.get("affixes", null)
	if typeof(affixes) != TYPE_ARRAY:
		return
	for af in affixes:
		if typeof(af) != TYPE_DICTIONARY:
			continue
		if String(af.get("id", "")) != "of_venom":
			continue
		# Range version carries value_min + value_max; pct does not.
		if not af.has("value_min") and not af.has("value_max"):
			af["id"] = "of_envenom"

# Flush the underlying user:// filesystem to durable storage. No-op on
# Steam / desktop / mobile (Godot's FileAccess.flush + close already
# committed the bytes synchronously). On HTML5 the engine writes to
# IDBFS, an in-memory virtualization of indexed-db; bytes only persist
# across sessions when FS.syncfs(false, ...) flushes them.
#
# Callers should run this AFTER any save_state() call whose data must
# survive an immediate tab close — boss kills, run-report writes,
# shop purchases. The browser allows a partial async window during
# pagehide for the IDBFS commit to complete; without an explicit
# flush, "I tabbed away and lost my unlock" is a recurring class of
# web-only data loss.
#
# `on_done` (optional Callable taking no args) is invoked once the
# syncfs callback fires on web. Run-report dismissal gates on this so
# the "Continue" button can't be clicked before the unlock is durable.
# On non-web platforms `on_done` runs synchronously before return.
static func flush_to_disk(on_done: Callable = Callable()) -> void:
	if not OS.has_feature("web"):
		if on_done.is_valid():
			on_done.call()
		return
	# Wire a one-shot global callback so JS can call back into GDScript
	# when syncfs settles. JavaScriptBridge.create_callback keeps a strong
	# reference until the JS side drops it; we explicitly drop after
	# firing to avoid leaking a callback per flush.
	if on_done.is_valid():
		var cb_ref: Array = [null]
		var cb := JavaScriptBridge.create_callback(func(_args: Array) -> void:
			on_done.call()
			cb_ref[0] = null  # drop reference after firing
		)
		cb_ref[0] = cb
		var window: JavaScriptObject = JavaScriptBridge.get_interface("window")
		window["__botter_syncfs_cb"] = cb
		JavaScriptBridge.eval("""
			(function() {
				if (typeof FS !== 'undefined' && FS.syncfs) {
					FS.syncfs(false, function(err) {
						if (window.__botter_syncfs_cb) {
							window.__botter_syncfs_cb();
							delete window.__botter_syncfs_cb;
						}
					});
				} else if (window.__botter_syncfs_cb) {
					// IDBFS not present (running outside emscripten harness?)
					// — fire callback synchronously so the caller never hangs.
					window.__botter_syncfs_cb();
					delete window.__botter_syncfs_cb;
				}
			})();
		""", true)
		return
	# Fire-and-forget — no callback wiring, just kick off the syncfs
	# (used by tab-close handlers where we can't wait for a callback
	# anyway).
	JavaScriptBridge.eval("""
		(function() {
			if (typeof FS !== 'undefined' && FS.syncfs) {
				FS.syncfs(false, function(err) {});
			}
		})();
	""", true)

static func save_state(state: Dictionary) -> void:
	# Stamp the active character with wall time + persist to disk.
	# Existing callers pass a single-character dict (from load_state);
	# we slot it back into the wrapper at the active index.
	state["last_seen_timestamp"] = int(Time.get_unix_time_from_system())
	# last_load_warnings is a runtime-only field (set by load_state from
	# the loader's warning array). Don't bake it into disk state — that
	# would make a one-time recovery warning sticky across every future
	# load until something else cleared it.
	state.erase("last_load_warnings")
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
		# Schema version of this character's payload. _migrate runs the
		# version-N→version-N+1 chain whenever this is below SCHEMA_VERSION;
		# loaders refuse to overwrite saves with a higher value (downgrade
		# protection). Defaults to current so fresh characters skip the
		# v0→v7 historic migration entirely.
		"schema_version": SCHEMA_VERSION,
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
		# Death = run over. Was 3-revive retreats; user removed in the
		# 2026-06-05 balance pass to make per-run gear decisions matter.
		# Field kept for save-compat with old saves that still read it.
		"max_revives": 0,
		# Gear bloat controls. loot_filter: bot walks past loot below this
		# rarity (default common = everything goes in the bag). inventory_cap:
		# hard ceiling triggering auto-salvage when exceeded.
		"loot_filter": "common",
		"inventory_cap": 200,
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
		# Items whose base_id was removed from items.json since the save
		# was written. _validate_loaded_state moves them here so the
		# player isn't silently robbed of build-defining gear when an
		# item is renamed or deleted between builds. Recoverable when
		# the base_id reappears.
		"orphaned_items": [],
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
