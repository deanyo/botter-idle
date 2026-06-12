extends GutTest

# Tests for SaveState._migrate. Locks idempotence and historic-shape
# coverage so future schema changes don't silently drop fields or
# re-trigger one-time migrations on every load.
#
# Critical regressions guarded:
#   - Octopode/Naga ring2-wipe (256ccc0): the legacy ring1/ring2 →
#     ring collapse must NOT run for species whose slot set includes
#     ring2.
#   - Stat-point retroactive grant must seed correct unspent count
#     for level > 1 saves.
#   - Spell slots / gloves / cloak / run-active forward-compat init.
#
# Run via:
#   /Applications/Godot.app/Contents/MacOS/Godot --path project --headless \
#       -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit

# ---------------------------------------------------------------------
# Pre-overhaul minimal save (every forward-compat default path fires)
# ---------------------------------------------------------------------

func test_pre_pivot_save_gets_all_current_keys() -> void:
	var save := _pre_pivot_save()
	SaveState._migrate(save)
	var equipped: Dictionary = save["equipped"]
	# Gloves + cloak slots added 2026-06-03.
	assert_true(equipped.has("gloves"), "gloves slot keyed")
	assert_true(equipped.has("cloak"), "cloak slot keyed")
	assert_eq(equipped["gloves"], null, "gloves default null")
	assert_eq(equipped["cloak"], null, "cloak default null")
	# Spell slots 1-5 added 2026-06-04.
	for sk in ["spell1", "spell2", "spell3", "spell4", "spell5"]:
		assert_true(equipped.has(sk), "%s slot keyed" % sk)
	# Spell1 gets the species starter granted retroactively.
	assert_not_null(equipped["spell1"], "spell1 starter granted")
	assert_eq(equipped["spell2"], null, "spell2 stays empty")
	# Run-active fields added 2026-06-04.
	assert_true(save.has("run_active"), "run_active key present")
	assert_eq(save["run_active"], false, "run_active default false")
	assert_true(save.has("run_branch"), "run_branch key present")
	assert_true(save.has("run_floor_reached"), "run_floor_reached key present")
	# Stat-alloc fields added 2026-06-04 item-overhaul v2.
	assert_true(save.has("stat_alloc_str"), "stat_alloc_str key present")
	assert_true(save.has("stat_alloc_dex"), "stat_alloc_dex key present")
	assert_true(save.has("stat_alloc_int"), "stat_alloc_int key present")
	# Species defaults to spriggan when missing.
	assert_eq(save["species"], "spriggan", "species defaults to spriggan")

func test_retroactive_stat_points_for_level_5_save() -> void:
	# Pre-overhaul level-5 save → 3 × (5 - 1) = 12 unspent points.
	var save := _pre_pivot_save()
	save["level"] = 5
	SaveState._migrate(save)
	assert_eq(int(save["stat_points_unspent"]), 12,
		"3 × (level-1) retroactive grant for level 5")

func test_existing_stat_points_unspent_preserved() -> void:
	# Save that already has stat_points_unspent set must not be overwritten.
	var save := _pre_pivot_save()
	save["level"] = 5
	save["stat_points_unspent"] = 7
	SaveState._migrate(save)
	assert_eq(int(save["stat_points_unspent"]), 7,
		"existing stat_points_unspent preserved")

# ---------------------------------------------------------------------
# Idempotence — _migrate must be safe to run twice
# ---------------------------------------------------------------------

func test_migrate_is_idempotent_on_pre_pivot_save() -> void:
	var save_a := _pre_pivot_save()
	var save_b := _pre_pivot_save()
	SaveState._migrate(save_a)
	SaveState._migrate(save_b)
	SaveState._migrate(save_b)  # twice
	assert_eq(JSON.stringify(save_a), JSON.stringify(save_b),
		"double-migrate matches single-migrate")

func test_migrate_is_idempotent_on_fresh_default() -> void:
	# Fresh saves shouldn't be mutated by _migrate at all (their shape
	# already includes every key that _migrate adds).
	var save_a := SaveState._default()
	# Stamp the migration flag the way create_character does.
	save_a["migration_v_ring_collapse"] = true
	var save_b := save_a.duplicate(true)
	SaveState._migrate(save_b)
	assert_eq(JSON.stringify(save_a), JSON.stringify(save_b),
		"fresh save unchanged by _migrate")

# ---------------------------------------------------------------------
# Octopode ring2 regression — Tier 1 fix 256ccc0
# ---------------------------------------------------------------------

func test_octopode_ring2_survives_repeated_loads() -> void:
	# Octopode has 4 ring slots: ring, ring2, ring3, ring4. Pre-fix,
	# the legacy ring-collapse block ran on every load and treated
	# ring2 as a stale legacy key, wiping it. Post-fix, the block is
	# gated on migration_v_ring_collapse AND skipped entirely when
	# ring2 is in the species' slot set.
	var save := SaveState._default()
	save["species"] = "octopode"
	# Simulate a real ring equipped in ring2 by an octopode.
	var equipped: Dictionary = save["equipped"]
	equipped["ring"] = null
	equipped["ring2"] = {
		"base_id": "ring_of_protection",
		"instance_id": "test_inst_1",
		"affixes": [],
	}
	# Strip starter armor that octopode can't wear (matches how
	# create_character would prep one).
	equipped["armor"] = null
	# Mark migration done since the save was created post-fix.
	save["migration_v_ring_collapse"] = true
	# Multiple migrate passes (simulating multiple load cycles).
	for _i in 3:
		SaveState._migrate(save)
	assert_not_null(save["equipped"]["ring2"],
		"octopode ring2 survives repeated loads")
	assert_eq(save["equipped"]["ring2"]["base_id"], "ring_of_protection",
		"octopode ring2 item identity preserved")

# ---------------------------------------------------------------------
# Pre-collapse legacy ring1/ring2 → ring promotion
# ---------------------------------------------------------------------

func test_pre_ring_collapse_save_promotes_ring1() -> void:
	# Pre-2026-06-02 save with ring1 + ring2 keys, no `ring`. Human
	# species (ring2 NOT in slot set) → legacy block fires.
	var save := SaveState._default()
	save["species"] = "human"
	# Wipe migration flag so legacy block is allowed to run.
	save.erase("migration_v_ring_collapse")
	# Pre-collapse saves predate schema_version too — drop it so the
	# v0→v7 migration actually fires on this fixture.
	save.erase("schema_version")
	var equipped: Dictionary = save["equipped"]
	equipped.erase("ring")
	equipped["ring1"] = {
		"base_id": "ring_of_strength",
		"instance_id": "legacy_ring1",
		"affixes": [],
	}
	equipped["ring2"] = {
		"base_id": "ring_of_haste",
		"instance_id": "legacy_ring2",
		"affixes": [],
	}
	save["equipped"] = equipped
	save["inventory"] = []
	SaveState._migrate(save)
	# ring1 promotes into `ring`.
	assert_not_null(save["equipped"].get("ring", null), "ring populated")
	assert_eq(save["equipped"]["ring"]["base_id"], "ring_of_strength",
		"ring1 item promoted into ring slot")
	# Displaced ring2 lands in inventory rather than vanishing.
	var inv: Array = save["inventory"]
	var ids: Array = []
	for inst in inv:
		if typeof(inst) == TYPE_DICTIONARY:
			ids.append(String(inst.get("base_id", "")))
	assert_true("ring_of_haste" in ids,
		"displaced ring2 pushed into inventory (got %s)" % str(ids))
	# Migration flag stamped.
	assert_eq(save["migration_v_ring_collapse"], true,
		"migration_v_ring_collapse stamped after run")
	# Legacy keys cleaned up.
	assert_false(save["equipped"].has("ring1"), "ring1 legacy key erased")
	assert_false(save["equipped"].has("ring2"), "ring2 legacy key erased")

# ---------------------------------------------------------------------
# Atomic save writes — torn-write recovery via .bak
# ---------------------------------------------------------------------
#
# Every test in this section runs against the DEBUG save path so the
# live playtest save is never touched. before_each / after_each scrub
# the test files so each case starts from a known-empty state.

func before_each() -> void:
	SaveState.debug_mode = true
	_scrub_test_files()

func after_each() -> void:
	_scrub_test_files()
	SaveState.debug_mode = false

func _scrub_test_files() -> void:
	var d := DirAccess.open("user://")
	if d == null:
		return
	for ext: String in ["", ".tmp", ".bak"]:
		var p: String = SaveState.DEBUG_PATH + ext
		if FileAccess.file_exists(p):
			d.remove(p)
	# Quarantine residue from prior runs. test_future_version_save_quarantined_on_load
	# writes a save with schema_version > current, which the loader renames
	# to .future-v<N>-<ts>; without explicit cleanup these accumulate
	# indefinitely (one per test invocation × one per pre-commit run).
	for fname: String in d.get_files():
		if fname.begins_with("botter_save_debug.json.corrupted-"):
			d.remove(fname)
		if fname.begins_with("botter_save_debug.json.future-"):
			d.remove(fname)
		# Recovery promotes a quarantine and renames the stale primary
		# to .stale-<ts>; scrub those too.
		if fname.begins_with("botter_save_debug.json.stale-"):
			d.remove(fname)

func test_atomic_write_creates_final_and_no_tmp_after_save() -> void:
	# Happy path: a successful save leaves <path> on disk and no <path>.tmp
	# residue. .bak appears only after the SECOND save (rotation moves the
	# previous final into .bak).
	var save := SaveState._default()
	save["gold"] = 42
	SaveState.save_state(save)
	assert_true(FileAccess.file_exists(SaveState.DEBUG_PATH),
		"primary file written")
	assert_false(FileAccess.file_exists(SaveState.DEBUG_PATH + ".tmp"),
		"tmp residue cleaned up after rename")
	# First save: no prior final to rotate, so no .bak yet.
	assert_false(FileAccess.file_exists(SaveState.DEBUG_PATH + ".bak"),
		"no .bak after first save (nothing to rotate)")
	# Second save rotates the first final → .bak.
	save["gold"] = 100
	SaveState.save_state(save)
	assert_true(FileAccess.file_exists(SaveState.DEBUG_PATH + ".bak"),
		".bak written on second save (rotation)")
	# .bak holds the prior generation.
	var bak_text: String = FileAccess.open(
		SaveState.DEBUG_PATH + ".bak", FileAccess.READ).get_as_text()
	var bak_parsed: Dictionary = JSON.parse_string(bak_text)
	assert_eq(int(bak_parsed["characters"][0]["gold"]), 42,
		".bak preserves the prior generation's gold=42")

func test_load_falls_back_to_bak_when_primary_corrupted() -> void:
	# Write twice so .bak exists.
	var save := SaveState._default()
	save["gold"] = 1234
	SaveState.save_state(save)
	save["gold"] = 5678
	SaveState.save_state(save)
	# Corrupt the primary (truncate mid-JSON — invalid syntax).
	var f := FileAccess.open(SaveState.DEBUG_PATH, FileAccess.WRITE)
	f.store_string('{"characters": [{"gold": 5')  # truncated
	f.close()
	# Loader should detect the parse failure, quarantine the corrupted
	# primary, and fall through to the .bak (which holds gold=1234).
	var loaded := SaveState.load_state()
	# Quarantine path emits one push_error — claim it so it doesn't fail
	# the test as an "unexpected error."
	assert_push_error("corrupted file quarantined")
	assert_eq(int(loaded["gold"]), 1234,
		"loader recovered gold=1234 from .bak")
	# Warning surfaced.
	assert_true("save_recovered_from_backup" in loaded.get("last_load_warnings", []),
		"save_recovered_from_backup warning surfaced")
	# Corrupted file quarantined (renamed, not deleted).
	var d := DirAccess.open("user://")
	var found_quarantine := false
	for fname: String in d.get_files():
		if fname.begins_with("botter_save_debug.json.corrupted-"):
			found_quarantine = true
			break
	assert_true(found_quarantine, "corrupted primary preserved as .corrupted-<ts>")

func test_load_returns_defaults_when_both_primary_and_bak_corrupted() -> void:
	# Both files exist but neither parses. Loader returns defaults and
	# surfaces the harder warning.
	var f1 := FileAccess.open(SaveState.DEBUG_PATH, FileAccess.WRITE)
	f1.store_string("not json")
	f1.close()
	var f2 := FileAccess.open(SaveState.DEBUG_PATH + ".bak", FileAccess.WRITE)
	f2.store_string("also not json")
	f2.close()
	var loaded := SaveState.load_state()
	# Both files quarantined → 2 push_error calls.
	assert_push_error_count(2)
	# Default save shape — gold=0, level=1, etc.
	assert_eq(int(loaded["gold"]), 0, "loader returned defaults")
	assert_eq(int(loaded["level"]), 1, "loader returned defaults level")
	assert_true("save_could_not_be_loaded" in loaded.get("last_load_warnings", []),
		"save_could_not_be_loaded warning surfaced")

func test_warnings_not_persisted_through_save_cycle() -> void:
	# A fresh load with no corruption surfaces no warnings, AND a save
	# cycle does not bake last_load_warnings into the on-disk state.
	var save := SaveState._default()
	save["gold"] = 7
	# Manually plant a (stale) warning to confirm it gets stripped on save.
	save["last_load_warnings"] = ["save_recovered_from_backup"]
	SaveState.save_state(save)
	# Read the on-disk file directly.
	var raw_text := FileAccess.open(SaveState.DEBUG_PATH, FileAccess.READ).get_as_text()
	var raw: Dictionary = JSON.parse_string(raw_text)
	var ch: Dictionary = raw["characters"][0]
	assert_false(ch.has("last_load_warnings"),
		"last_load_warnings not persisted to disk")
	# A fresh load (no corruption) returns no warnings on the loaded dict.
	var reloaded := SaveState.load_state()
	assert_false(reloaded.has("last_load_warnings"),
		"clean load surfaces no warnings")

# ---------------------------------------------------------------------
# Orphan base_id validation — _validate_loaded_state
# ---------------------------------------------------------------------

func test_orphan_equipped_item_pushed_to_orphaned_items() -> void:
	# Save with an equipped item whose base_id doesn't exist in items.json.
	# Loader should null the slot, push the orphan to orphaned_items, and
	# surface an orphan_items_count warning.
	var save := SaveState._default()
	save["equipped"]["weapon"] = {
		"base_id": "definitely_not_a_real_item_id_xyz",
		"instance_id": "orphan_inst_1",
		"affixes": [],
	}
	var wrapper := {"characters": [save], "active": 0}
	var f := FileAccess.open(SaveState.DEBUG_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(wrapper))
	f.close()
	var loaded := SaveState.load_state()
	assert_eq(loaded["equipped"]["weapon"], null,
		"orphan slot nulled")
	var orphans: Array = loaded.get("orphaned_items", [])
	assert_eq(orphans.size(), 1, "1 orphan preserved")
	assert_eq(String(orphans[0]["base_id"]), "definitely_not_a_real_item_id_xyz",
		"orphan base_id intact for forensic recovery")
	var warnings: Array = loaded.get("last_load_warnings", [])
	var saw_orphan_warning := false
	for w: String in warnings:
		if w.begins_with("orphan_items_count_"):
			saw_orphan_warning = true
	assert_true(saw_orphan_warning, "orphan_items_count warning surfaced")

func test_real_equipped_item_not_evicted() -> void:
	# A real items.json id (rusty_dagger from the starter armor / weapon
	# pair) must not be evicted. Sanity check that the validator isn't
	# false-positive evicting healthy saves.
	var save := SaveState._default()
	# Default already has rusty_dagger equipped. Save and reload.
	var wrapper := {"characters": [save], "active": 0}
	var f := FileAccess.open(SaveState.DEBUG_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(wrapper))
	f.close()
	var loaded := SaveState.load_state()
	assert_not_null(loaded["equipped"]["weapon"], "real item not evicted")
	assert_eq(String(loaded["equipped"]["weapon"]["base_id"]), "rusty_dagger",
		"real item identity preserved")
	assert_eq(int(loaded.get("orphaned_items", []).size()), 0,
		"no orphans for a healthy save")

func test_orphan_inventory_item_pushed_to_orphaned_items() -> void:
	# Inventory side of orphan eviction — the kept array must shrink and
	# the orphan must end up on orphaned_items, not lost.
	var save := SaveState._default()
	save["inventory"] = [
		{
			"base_id": "rusty_dagger",  # real
			"instance_id": "real_inv_1",
			"affixes": [],
		},
		{
			"base_id": "another_definitely_not_real_item_xyz",
			"instance_id": "orphan_inv_1",
			"affixes": [],
		},
	]
	var wrapper := {"characters": [save], "active": 0}
	var f := FileAccess.open(SaveState.DEBUG_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(wrapper))
	f.close()
	var loaded := SaveState.load_state()
	assert_eq(int(loaded["inventory"].size()), 1,
		"orphan dropped from inventory; real item kept")
	assert_eq(int(loaded.get("orphaned_items", []).size()), 1,
		"orphan preserved on orphaned_items")
	assert_eq(String(loaded["orphaned_items"][0]["base_id"]),
		"another_definitely_not_real_item_xyz",
		"orphan identity intact")

# ---------------------------------------------------------------------
# Schema version chain — versioned _migrate
# ---------------------------------------------------------------------

func test_pre_v7_save_gets_stamped_after_migrate() -> void:
	# Pre-versioned saves had no schema_version key. _migrate should
	# stamp it to current after running the v0→v7 step.
	var save := _pre_pivot_save()
	assert_false(save.has("schema_version"), "fixture has no schema_version")
	SaveState._migrate(save)
	assert_eq(int(save["schema_version"]), SaveState.SCHEMA_VERSION,
		"schema_version stamped after migrate")

func test_current_version_save_short_circuits_migrate() -> void:
	# A save already at SCHEMA_VERSION must not be mutated by _migrate.
	# Specifically, the v0→v7 step (which contained legacy ring-collapse)
	# must not fire.
	var save := SaveState._default()
	save["migration_v_ring_collapse"] = true
	var snapshot := JSON.stringify(save)
	SaveState._migrate(save)
	assert_eq(JSON.stringify(save), snapshot,
		"current-version save unchanged by _migrate")

func test_future_version_save_quarantined_on_load() -> void:
	# Write a save with schema_version one above SCHEMA_VERSION. Loader
	# should refuse to overwrite, move it to .future-vN-<ts>, and return
	# defaults with the save_from_future_build warning.
	var future := SaveState._default()
	future["schema_version"] = SaveState.SCHEMA_VERSION + 1
	future["gold"] = 9999
	var wrapper := {"characters": [future], "active": 0}
	var f := FileAccess.open(SaveState.DEBUG_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(wrapper, "  "))
	f.close()
	var loaded := SaveState.load_state()
	# Engine emits one push_error for the future-version preservation.
	assert_push_error("save from future build")
	# Default save returned (gold=0 not 9999).
	assert_eq(int(loaded["gold"]), 0,
		"loader returned defaults when future-version save was refused")
	assert_true("save_from_future_build" in loaded.get("last_load_warnings", []),
		"save_from_future_build warning surfaced")
	# File preserved as .future-vN-<ts>.
	var d := DirAccess.open("user://")
	var found_future := false
	for fname: String in d.get_files():
		if fname.begins_with("botter_save_debug.json.future-v"):
			found_future = true
			break
	assert_true(found_future, "future-version save preserved as .future-v<n>-<ts>")

# ---------------------------------------------------------------------
# Equipped slot backfill — ensures every load has the 14 canonical
# slot keys regardless of input shape. Repairs the "spriggan with
# just a spell" symptom seen on 2026-06-11 where char[1]/char[2]
# saved with sparse equipped dicts (only ring/spell*/gloves/cloak,
# no weapon/armor/helm/boots/shield/amulet). Bot.apply_gear copies
# whatever shape comes in, so any read from a missing slot returned
# null and stayed null.
# ---------------------------------------------------------------------

func test_load_backfills_missing_slot_keys() -> void:
	var save := SaveState._default()
	save["equipped"] = {
		"ring": null, "gloves": null, "cloak": null,
		"spell1": null, "spell2": null, "spell3": null,
		"spell4": null, "spell5": null,
	}
	var wrapper := {"characters": [save], "active": 0}
	var f := FileAccess.open(SaveState.DEBUG_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(wrapper))
	f.close()
	var loaded := SaveState.load_state()
	var equipped: Dictionary = loaded["equipped"]
	for sk in ["weapon", "armor", "helm", "boots", "shield",
	           "gloves", "cloak", "ring", "amulet",
	           "spell1", "spell2", "spell3", "spell4", "spell5"]:
		assert_true(equipped.has(sk),
			"slot key '%s' present after backfill" % sk)
		assert_eq(equipped[sk], null,
			"slot '%s' defaults to null when missing" % sk)

func test_load_does_not_overwrite_existing_slots() -> void:
	# Backfill must NOT clobber slots that already have items —
	# only fills missing keys.
	var save := SaveState._default()
	save["equipped"]["weapon"] = {
		"base_id": "rusty_dagger",
		"instance_id": "live_weapon",
		"affixes": [],
	}
	# Drop a couple of slot keys to exercise the partial backfill.
	save["equipped"].erase("helm")
	save["equipped"].erase("amulet")
	var wrapper := {"characters": [save], "active": 0}
	var f := FileAccess.open(SaveState.DEBUG_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(wrapper))
	f.close()
	var loaded := SaveState.load_state()
	var equipped: Dictionary = loaded["equipped"]
	assert_eq(String(equipped["weapon"]["base_id"]), "rusty_dagger",
		"existing weapon preserved through backfill")
	assert_true(equipped.has("helm"), "missing helm key restored")
	assert_eq(equipped["helm"], null, "restored helm defaults to null")
	assert_true(equipped.has("amulet"), "missing amulet key restored")
	assert_eq(equipped["amulet"], null, "restored amulet defaults to null")

# ---------------------------------------------------------------------
# Quarantine recovery — repairs the CDN-downgrade save-loss regression.
# Symptom: itch.io serves a stale older build to a tab right after a
# new build push. The older build sees the new save's higher
# schema_version, quarantines it as `.future-v<N>-<ts>`, and returns
# defaults. When the player force-refreshes back to the current build,
# the primary save is gone and the quarantine sits unused.
#
# Fix path 1 (Test E): no primary, only `.future-v<N>` files in the
# directory — pick the newest one whose N ≤ ours, restore as primary.
# Fix path 2 (Test F): healthy primary + a fresher `.future-v<N>`
# quarantine — prefer the quarantine (the primary is likely a fresh
# `_default()` written by the older build after it nuked the real
# save).
# ---------------------------------------------------------------------

func test_load_recovers_from_quarantine_when_no_primary() -> void:
	# Set up: only a `.future-vN-<ts>` file exists in user://, no primary.
	# Loader should find it, parse it, migrate forward, and rename it
	# back to primary.
	var save := SaveState._default()
	save["gold"] = 4242
	save["level"] = 17
	var wrapper := {"characters": [save], "active": 0}
	var qpath: String = SaveState.DEBUG_PATH + ".future-v%d-1717000000" % SaveState.SCHEMA_VERSION
	var f := FileAccess.open(qpath, FileAccess.WRITE)
	f.store_string(JSON.stringify(wrapper))
	f.close()
	# No primary exists.
	assert_false(FileAccess.file_exists(SaveState.DEBUG_PATH),
		"sanity: no primary file before recovery")
	var loaded := SaveState.load_state()
	# Recovered the gold + level we wrote into the quarantine.
	assert_eq(int(loaded["gold"]), 4242,
		"recovered save's gold survived through quarantine")
	assert_eq(int(loaded["level"]), 17,
		"recovered save's level survived through quarantine")
	assert_true("save_recovered_from_quarantine" in loaded.get("last_load_warnings", []),
		"save_recovered_from_quarantine warning surfaced")
	# Quarantine file was promoted back to primary.
	assert_true(FileAccess.file_exists(SaveState.DEBUG_PATH),
		"quarantine promoted back to primary after recovery")
	assert_false(FileAccess.file_exists(qpath),
		"quarantine file removed after promotion")

func test_load_prefers_newer_quarantine_over_stale_primary() -> void:
	# Set up: a stale `_default()`-shaped primary AND a newer (by mtime)
	# `.future-vN-<ts>` quarantine. The quarantine should win — primary
	# is what an older build wrote after it nuked the real save.
	var stale := SaveState._default()
	stale["gold"] = 0
	stale["level"] = 1
	var stale_wrapper := {"characters": [stale], "active": 0}
	var f := FileAccess.open(SaveState.DEBUG_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(stale_wrapper))
	f.close()
	# Tick the clock so the quarantine's mtime is strictly greater than
	# primary's. Godot's get_modified_time has 1-second resolution.
	OS.delay_msec(1100)
	var real := SaveState._default()
	real["gold"] = 9999
	real["level"] = 50
	var real_wrapper := {"characters": [real], "active": 0}
	var qpath: String = SaveState.DEBUG_PATH + ".future-v%d-1717000001" % SaveState.SCHEMA_VERSION
	var f2 := FileAccess.open(qpath, FileAccess.WRITE)
	f2.store_string(JSON.stringify(real_wrapper))
	f2.close()
	var loaded := SaveState.load_state()
	# Loader picked the newer quarantine.
	assert_eq(int(loaded["gold"]), 9999,
		"newer quarantine's gold preferred over stale primary")
	assert_eq(int(loaded["level"]), 50,
		"newer quarantine's level preferred over stale primary")
	assert_true("save_recovered_from_quarantine" in loaded.get("last_load_warnings", []),
		"recovery warning surfaced when newer quarantine wins")
	# Stale primary kept aside as `.stale-<ts>` for forensics.
	var d := DirAccess.open("user://")
	var found_stale := false
	for fname: String in d.get_files():
		if fname.begins_with("botter_save_debug.json.stale-"):
			found_stale = true
			break
	assert_true(found_stale, "stale primary preserved as .stale-<ts>")

func test_load_keeps_primary_when_quarantine_older() -> void:
	# Set up: a healthy primary AND an older quarantine. Primary should
	# win — quarantine is residue from a previous incident, not fresher
	# state. We don't want to clobber a good primary with stale data.
	var stale_q := SaveState._default()
	stale_q["gold"] = 1
	var stale_q_wrapper := {"characters": [stale_q], "active": 0}
	var qpath: String = SaveState.DEBUG_PATH + ".future-v%d-1717000000" % SaveState.SCHEMA_VERSION
	var f := FileAccess.open(qpath, FileAccess.WRITE)
	f.store_string(JSON.stringify(stale_q_wrapper))
	f.close()
	OS.delay_msec(1100)
	var fresh_primary := SaveState._default()
	fresh_primary["gold"] = 8888
	var fresh_wrapper := {"characters": [fresh_primary], "active": 0}
	var f2 := FileAccess.open(SaveState.DEBUG_PATH, FileAccess.WRITE)
	f2.store_string(JSON.stringify(fresh_wrapper))
	f2.close()
	var loaded := SaveState.load_state()
	# Loader kept the primary because the quarantine wasn't fresher.
	assert_eq(int(loaded["gold"]), 8888,
		"primary preferred when quarantine is older")
	assert_false("save_recovered_from_quarantine" in loaded.get("last_load_warnings", []),
		"no recovery warning when primary wins")

# ---------------------------------------------------------------------
# Forward-compat: unknown keys preserved
# ---------------------------------------------------------------------

func test_migrate_preserves_unknown_keys() -> void:
	# Future schema fields or experimental dev fields must not be
	# silently stripped by _migrate.
	var save := _pre_pivot_save()
	save["__future_field"] = "preserved"
	save["__experimental_dict"] = {"k": "v"}
	SaveState._migrate(save)
	assert_eq(save.get("__future_field", ""), "preserved",
		"unknown top-level scalar preserved")
	assert_eq(save.get("__experimental_dict", {}).get("k", ""), "v",
		"unknown top-level dict preserved")

# ---------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------

# Minimal pre-pivot single-character save shape — predates spell slots,
# stat alloc, run_active, gloves/cloak, species selector. Roughly what
# a save written before 2026-06-03 looked like.
func _pre_pivot_save() -> Dictionary:
	return {
		"gold": 0,
		"level": 1,
		"xp": 0,
		"inventory": [],
		"equipped": {
			"weapon": null,
			"armor": null,
			"helm": null,
			"boots": null,
			"shield": null,
			"ring": null,
			"amulet": null,
		},
		"runs_completed": 0,
		"highest_floor": 0,
		"unlocked_branches": ["dungeon"],
		"bosses_killed": {},
		"max_revives": 3,
		"loot_filter": "common",
		"inventory_cap": 50,
		"last_branch": "",
		"branch_modifiers": {},
		"bot_upgrades": {},
		"shards": 0,
		"last_seen_timestamp": 0,
	}
