extends GutTest

# Tests for RunState — the run + floor lifecycle module extracted from
# dungeon.gd 2026-06-09 (Tier 3 god-class split, fourth extraction).
# Locks the load-bearing invariants:
#
#   * init_run resets every per-run accumulator and rolls the run plan.
#   * note_* helpers increment the right counters and mirror into the
#     kills tally / dropped trail.
#   * Portal overlay enter / exit toggles the four portal_* fields
#     atomically.
#   * record_descend_summary aggregates per-floor counts into run-wide
#     totals + biome list, returns run_done == true exactly when the
#     current floor reaches floors_per_run.
#   * try_death_retreat decrements revives_remaining and resets
#     current_floor when allowed; returns false at zero revives.
#   * journal helpers gate event-append on a non-empty journal.

const RunStateScript := preload("res://scripts/run_state.gd")
const _StubBot := preload("res://tests/_stub_bot.gd")

var _run: RefCounted = null

func before_each() -> void:
	_run = RunStateScript.new()


# ---------------------------------------------------------------------
# init_run — resets every per-run accumulator
# ---------------------------------------------------------------------

func test_init_run_resets_floor_and_run_counters() -> void:
	# Pollute the state so init_run has to clean it up.
	_run.current_floor = 5
	_run.run_kills = 999
	_run.run_loot_picked = 50
	_run.kills["rat"] = 12
	_run.loot_log.append("stale")
	_run.dropped_items.append({"base_id": "x"})
	_run.run_dropped_uniques.append("urand_anything")
	_run.portal_active = true
	_run.portal_kind = "bazaar"
	var save := {"branch_modifiers": {}}
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	_run.init_run("dungeon", save, rng)
	assert_eq(_run.current_floor, 1, "current_floor reset to 1")
	assert_eq(_run.run_kills, 0, "run_kills cleared")
	assert_eq(_run.run_loot_picked, 0, "run_loot_picked cleared")
	assert_true(_run.kills.is_empty(), "kills dict cleared")
	assert_true(_run.loot_log.is_empty(), "loot_log cleared")
	assert_true(_run.dropped_items.is_empty(), "dropped_items cleared")
	assert_true(_run.run_dropped_uniques.is_empty(), "run_dropped_uniques cleared")
	assert_false(_run.portal_active, "portal_active cleared")
	assert_eq(_run.portal_kind, "", "portal_kind cleared")


func test_init_run_rolls_plan_sized_to_floors_per_run() -> void:
	var save := {"branch_modifiers": {}}
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	_run.init_run("dungeon", save, rng)
	assert_eq(_run.floors_per_run, 6, "default floors_per_run from C.FLOORS_PER_RUN")
	assert_eq(_run.boss_floor, _run.floors_per_run, "boss_floor pinned to floors_per_run")
	assert_eq(_run.run_plan.size(), _run.floors_per_run, "run_plan length matches floors_per_run")


func test_init_run_consumes_branch_modifier_entry() -> void:
	# RunState.init_run should erase the modifier list from
	# save.branch_modifiers so the next deploy re-rolls fresh.
	var save := {
		"branch_modifiers": {"dungeon": ["crowded"]},
	}
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	_run.init_run("dungeon", save, rng)
	# Modifiers cached on the run, save's branch_modifiers entry erased.
	assert_eq(_run.active_modifiers, ["crowded"], "active_modifiers cached on run")
	# NB the consumed save state is written back via SaveState.save_state
	# (touches disk on the test runner). The mutation on the in-memory
	# `save` Dictionary is observable here.
	assert_false(save.get("branch_modifiers", {}).has("dungeon"),
		"branch_modifiers entry erased after consume")


# ---------------------------------------------------------------------
# Per-event note_* helpers
# ---------------------------------------------------------------------

func test_note_kill_increments_floor_kills_and_kills_tally() -> void:
	_run.note_kill("rat")
	_run.note_kill("rat")
	_run.note_kill("goblin")
	assert_eq(_run.floor_kills, 3, "floor_kills counts every note_kill")
	assert_eq(int(_run.kills["rat"]), 2, "kills tally per enemy id")
	assert_eq(int(_run.kills["goblin"]), 1, "second enemy id tallied")


func test_note_loot_picked_increments_counter_and_appends_drop() -> void:
	var inst1 := {"base_id": "rusty_dagger", "instance_id": "a"}
	var inst2 := {"base_id": "rare_ring", "instance_id": "b"}
	_run.note_loot_picked(inst1)
	_run.note_loot_picked(inst2)
	assert_eq(_run.floor_loot_picked, 2, "floor_loot_picked bumped per drop")
	assert_eq(_run.dropped_items.size(), 2, "dropped_items trail")
	assert_eq(_run.dropped_items[1]["instance_id"], "b", "appended in order")


func test_other_floor_counters_increment_individually() -> void:
	_run.note_chest_opened()
	_run.note_chest_opened()
	_run.note_altar_used()
	_run.note_fountain_used()
	_run.note_portal_entered()
	_run.note_stall()
	_run.note_hard_recovery()
	assert_eq(_run.floor_chests_opened, 2)
	assert_eq(_run.floor_altars_used, 1)
	assert_eq(_run.floor_fountains_used, 1)
	assert_eq(_run.floor_portals_entered, 1)
	assert_eq(_run.floor_stalls, 1)
	assert_eq(_run.floor_hard_recoveries, 1)


# ---------------------------------------------------------------------
# Floor lifecycle — begin_floor resets per-floor counters
# ---------------------------------------------------------------------

func test_begin_floor_resets_per_floor_counters_only() -> void:
	# Set both per-floor and per-run counters.
	_run.note_kill("rat")
	_run.note_chest_opened()
	_run.note_loot_picked({"base_id": "x"})
	_run.run_kills = 99  # should NOT be cleared by begin_floor
	_run.run_loot_picked = 33
	_run.begin_floor()
	assert_eq(_run.floor_kills, 0, "floor_kills cleared on begin_floor")
	assert_eq(_run.floor_chests_opened, 0, "floor_chests cleared")
	assert_eq(_run.floor_loot_picked, 0, "floor_loot_picked cleared")
	assert_true(_run.floor_placed_vaults.is_empty(), "vault list cleared")
	# Run-wide counters preserved.
	assert_eq(_run.run_kills, 99, "run_kills NOT cleared by begin_floor")
	assert_eq(_run.run_loot_picked, 33, "run_loot_picked NOT cleared")


func test_record_floor_vaults_dedupes_against_run_set() -> void:
	_run.record_floor_vaults(["des_a", "des_b"])
	assert_eq(_run.floor_placed_vaults, ["des_a", "des_b"])
	assert_eq(_run.run_vaults_stamped, ["des_a", "des_b"])
	# Same vault on a later floor: floor list resets, run set deduplicated.
	_run.record_floor_vaults(["des_b", "des_c"])
	assert_eq(_run.floor_placed_vaults, ["des_b", "des_c"], "floor list replaced")
	assert_eq(_run.run_vaults_stamped, ["des_a", "des_b", "des_c"],
		"run set deduplicates across floors")


# ---------------------------------------------------------------------
# Portal overlay
# ---------------------------------------------------------------------

func test_enter_portal_sets_all_four_overlay_fields() -> void:
	var override := {"id": "vaults", "tier": 4}
	_run.enter_portal("bazaar", override, 2)
	assert_true(_run.portal_active)
	assert_eq(_run.portal_kind, "bazaar")
	assert_eq(_run.portal_biome_override, override)
	assert_eq(_run.portal_loot_bias, 2)


func test_exit_portal_clears_overlay() -> void:
	_run.enter_portal("trove", {"id": "labyrinth"}, 3)
	_run.exit_portal()
	assert_false(_run.portal_active)
	assert_eq(_run.portal_kind, "")
	assert_true(_run.portal_biome_override.is_empty())
	assert_eq(_run.portal_loot_bias, 0)


# ---------------------------------------------------------------------
# Boss floor probes
# ---------------------------------------------------------------------

func test_is_final_boss_floor_compares_against_boss_floor() -> void:
	_run.boss_floor = 6
	_run.current_floor = 5
	assert_false(_run.is_final_boss_floor())
	_run.current_floor = 6
	assert_true(_run.is_final_boss_floor())
	_run.current_floor = 7  # Endless modifier could push past
	assert_true(_run.is_final_boss_floor())


func test_capture_boss_floor_entry_stamps_three_fields() -> void:
	_run.capture_boss_floor_entry(120, "vaults")
	assert_eq(_run.boss_floor_entry_hp, 120)
	assert_eq(_run.boss_floor_branch, "vaults")
	assert_gt(_run.boss_floor_entry_ms, 0, "ms timestamp captured")


# ---------------------------------------------------------------------
# record_descend_summary — aggregates per-floor → run-wide
# ---------------------------------------------------------------------

func test_record_descend_summary_rolls_into_run_totals() -> void:
	_run.current_floor = 1
	_run.floors_per_run = 6
	_run.boss_floor = 6
	_run.floor_starting_hp = 100
	_run.note_kill("rat")
	_run.note_kill("rat")
	_run.note_loot_picked({"base_id": "x"})
	_run.note_portal_entered()
	_run.note_stall()
	var ret: Dictionary = _run.record_descend_summary("dungeon", 80)
	assert_eq(_run.run_kills, 2, "run_kills picks up 2 floor kills")
	assert_eq(_run.run_loot_picked, 1, "run_loot_picked rolled in")
	assert_eq(_run.run_portals_entered, 1, "run_portals_entered rolled in")
	assert_eq(_run.run_stalls, 1, "run_stalls rolled in")
	assert_eq(_run.run_biomes_visited, ["dungeon"], "biome added to visited list")
	assert_eq(int(ret["hp_lost"]), 20, "hp_lost = floor_starting_hp - bot_hp")
	assert_false(bool(ret["run_done"]), "floor 1 of 6 → not done")


func test_record_descend_summary_run_done_at_floor_cap() -> void:
	_run.current_floor = 6
	_run.floors_per_run = 6
	var ret: Dictionary = _run.record_descend_summary("zot", 0)
	assert_true(bool(ret["run_done"]), "floor == cap → run_done")


func test_record_descend_summary_dedupes_biome_list() -> void:
	_run.current_floor = 1
	_run.floors_per_run = 6
	_run.record_descend_summary("dungeon", 100)
	_run.current_floor = 2
	_run.record_descend_summary("dungeon", 100)
	_run.current_floor = 3
	_run.record_descend_summary("lair", 100)
	assert_eq(_run.run_biomes_visited, ["dungeon", "lair"],
		"each biome counted once even on revisit")


# ---------------------------------------------------------------------
# advance_to_next_floor
# ---------------------------------------------------------------------

func test_advance_to_next_floor_increments() -> void:
	_run.current_floor = 1
	_run.advance_to_next_floor()
	assert_eq(_run.current_floor, 2)


# ---------------------------------------------------------------------
# Death retreat
# ---------------------------------------------------------------------

func test_try_death_retreat_returns_false_when_no_revives() -> void:
	_run.revives_remaining = 0
	_run.current_floor = 4
	var absorbed: bool = _run.try_death_retreat("test")
	assert_false(absorbed, "no revives → not absorbed")
	assert_eq(_run.current_floor, 4, "current_floor unchanged when retreat refused")


func test_try_death_retreat_decrements_and_resets_floor() -> void:
	# Retreats are deprecated but the bookkeeping path is still tested
	# so we don't accidentally re-enable the legacy code via an old save.
	_run.revives_remaining = 2
	_run.current_floor = 5
	var absorbed: bool = _run.try_death_retreat("test")
	assert_true(absorbed, "with revive available, retreat is absorbed")
	assert_eq(_run.revives_remaining, 1, "decremented")
	assert_eq(_run.retreats_this_run, 1, "retreats_this_run incremented")
	assert_eq(_run.current_floor, 1, "current_floor reset to 1")


# ---------------------------------------------------------------------
# tick_run_turn — accumulates 0.25s ticks
# ---------------------------------------------------------------------

func test_tick_run_turn_bumps_at_quarter_second_intervals() -> void:
	# Mirrors the pre-extraction `_turn_accum += delta; if accum >= 0.25:
	# accum -= 0.25; run_turn += 1` shape — at most one bump per tick,
	# matching the per-frame _process cadence.
	_run.run_turn = 0
	_run.tick_run_turn(0.1)
	assert_eq(_run.run_turn, 0, "tick under 0.25s → no bump")
	_run.tick_run_turn(0.2)
	assert_eq(_run.run_turn, 1, "0.3s accumulated → run_turn += 1")
	_run.tick_run_turn(0.5)
	assert_eq(_run.run_turn, 2, "single bump per tick (matches per-frame _process)")


# ---------------------------------------------------------------------
# Journal
# ---------------------------------------------------------------------

func test_journal_floor_entry_and_event_append() -> void:
	_run.journal_floor_entry({"floor": 1, "biome": "Dungeon", "events": []})
	_run.journal_event("Slew a rat")
	_run.journal_event("Opened a chest")
	assert_eq(_run.journal.size(), 1, "single floor entry")
	assert_eq((_run.journal[0]["events"] as Array).size(), 2, "two events on the back floor")


func test_journal_event_no_op_when_journal_empty() -> void:
	# No floor entry registered yet — events should silently drop
	# rather than throwing on journal.back().
	_run.journal_event("Should silently drop")
	assert_true(_run.journal.is_empty(), "journal stays empty")


# ---------------------------------------------------------------------
# Unique-drop tracking
# ---------------------------------------------------------------------

func test_unique_drop_tracking_rejects_duplicates() -> void:
	assert_false(_run.is_unique_dropped("urand_quickblade"))
	_run.note_dropped_unique("urand_quickblade")
	assert_true(_run.is_unique_dropped("urand_quickblade"))
	assert_false(_run.is_unique_dropped("urand_demon_blade"),
		"unrelated unique not flagged")
