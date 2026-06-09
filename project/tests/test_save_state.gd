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
