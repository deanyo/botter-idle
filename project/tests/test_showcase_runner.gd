extends GutTest

# Tests for ShowcaseRunner — the visual-audit floor integration glue
# extracted from dungeon.gd 2026-06-09 (Tier 3 god-class split, sixth
# and final sub-system). Locks the load-bearing invariants:
#
#   * is_active() reads through to DebugJump.showcase.
#   * build_floor_data() resets patrol_idx and returns a dict with the
#     expected keys (grid, rooms, spawn, stairs_down, dist_to_stairs,
#     vault_results) — downstream code in _async_build_floor reads
#     these fields by name.
#   * tick_patrol advances patrol_idx and wraps at the loop end.
#
# Visual-audit content (STATIONS roster, patrol_path) lives in
# scripts/showcase.gd and is intentionally NOT pinned here — locking
# field-by-field equality on the roster would discourage adding new
# stations (the whole point of the file).

const ShowcaseRunnerScript := preload("res://scripts/showcase_runner.gd")
const StubDungeonScript := preload("res://tests/_stub_showcase_dungeon.gd")

var _dungeon: Node = null
var _show: RefCounted = null


func before_each() -> void:
	_dungeon = StubDungeonScript.new()
	add_child_autofree(_dungeon)
	_show = ShowcaseRunnerScript.new(_dungeon)


func after_each() -> void:
	# Tests flip DebugJump.showcase; reset so a leaked-true doesn't
	# bleed into a later GUT script.
	DebugJump.showcase = false


# ---------------------------------------------------------------------
# is_active — reads DebugJump.showcase
# ---------------------------------------------------------------------

func test_is_active_reads_debug_jump_showcase() -> void:
	DebugJump.showcase = false
	assert_false(_show.is_active(), "is_active false when DebugJump.showcase off")
	DebugJump.showcase = true
	assert_true(_show.is_active(), "is_active true when DebugJump.showcase on")


# ---------------------------------------------------------------------
# build_floor_data — resets patrol_idx, returns expected shape
# ---------------------------------------------------------------------

func test_build_floor_data_resets_patrol_and_returns_expected_keys() -> void:
	# Pollute patrol state so build_floor_data has to reset it.
	_show.patrol_idx = 12
	_show.patrol = [Vector2i(0, 0)]
	var data: Dictionary = _show.build_floor_data()
	assert_eq(_show.patrol_idx, 0, "patrol_idx reset to 0")
	assert_gte(_show.patrol.size(), 1, "patrol seeded from Showcase.patrol_path()")
	# The dict keys downstream code in _async_build_floor reads by name.
	assert_true(data.has("grid"), "data has grid")
	assert_true(data.has("rooms"), "data has rooms")
	assert_true(data.has("spawn"), "data has spawn")
	assert_true(data.has("stairs_down"), "data has stairs_down")
	assert_true(data.has("dist_to_stairs"), "data has dist_to_stairs")
	assert_true(data.has("vault_results"), "data has vault_results")
	# Spawn cell must equal the first patrol cell (so the bot starts on
	# the loop and the patrol tick has somewhere to walk to).
	assert_eq(data["spawn"], _show.patrol[0],
		"spawn cell == first patrol cell")


# ---------------------------------------------------------------------
# tick_patrol — advances patrol_idx, wraps at end
# ---------------------------------------------------------------------

func test_tick_patrol_no_op_on_empty_patrol() -> void:
	_show.patrol = []
	_show.tick_patrol(0.1)
	assert_eq(_dungeon.bot.step_calls, 0, "no step_movement when patrol empty")
	assert_eq(_dungeon.bot.set_path_calls.size(), 0, "no set_path when patrol empty")


func test_tick_patrol_steps_when_path_in_flight() -> void:
	# Bot mid-path: tick_patrol should just call step_movement and not
	# advance the patrol index or request a new path.
	_show.build_floor_data()
	var idx_before: int = _show.patrol_idx
	# Simulate a path in flight.
	var path: PackedVector2Array = PackedVector2Array()
	path.append(Vector2(20, 14))
	path.append(Vector2(21, 14))
	_dungeon.bot.path = path
	_dungeon.bot.path_index = 0
	_show.tick_patrol(0.1)
	assert_eq(_dungeon.bot.step_calls, 1, "step_movement called once")
	assert_eq(_show.patrol_idx, idx_before, "patrol_idx unchanged mid-path")
	assert_eq(_dungeon.bot.set_path_calls.size(), 0, "no new path requested mid-path")


func test_tick_patrol_advances_idx_and_requests_path_at_arrival() -> void:
	# Build the floor data so patrol is seeded; bot starts at patrol[0].
	_show.build_floor_data()
	# Empty path → bot has arrived; tick should advance to patrol[1].
	_dungeon.bot.path = PackedVector2Array()
	_dungeon.bot.path_index = 0
	_dungeon.bot.cell = _show.patrol[0]
	# Since cell == patrol[0] which is also the current target after
	# advance to idx 1 only if patrol[1] happened to equal cell — but
	# patrol cells are distinct anchors, so this is normal.
	_show.tick_patrol(0.1)
	assert_eq(_show.patrol_idx, 1, "patrol_idx advanced to 1")
	assert_eq(_dungeon.bot_target_kind, "showcase_patrol",
		"bot_target_kind set to showcase_patrol")
	assert_eq(_dungeon.bot.set_path_calls.size(), 1, "new path requested")
	assert_eq(_dungeon.bot.step_calls, 1, "step_movement called after path set")


func test_tick_patrol_wraps_at_loop_end() -> void:
	_show.build_floor_data()
	var n: int = _show.patrol.size()
	# Set patrol_idx to the last entry; next advance should wrap to 0.
	_show.patrol_idx = n - 1
	_dungeon.bot.path = PackedVector2Array()
	_dungeon.bot.cell = _show.patrol[n - 1]
	_show.tick_patrol(0.1)
	# Wrapped from n-1 → 0. (If patrol[0] == bot.cell the runner skips
	# once more to patrol[1] — handle both via the modulo.)
	assert_true(_show.patrol_idx == 0 or _show.patrol_idx == 1,
		"patrol_idx wrapped to 0 or skipped to 1")
