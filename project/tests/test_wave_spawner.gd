extends GutTest

# Tests for WaveSpawner — the VS-style wave + burst density layer
# extracted from dungeon.gd 2026-06-09 (Tier 3 god-class split, fifth
# sub-system). Locks the load-bearing invariants:
#
#   * begin_floor resets accumulators to 0 and re-jitters intervals
#     into the 6-10s / 30-50s bands.
#   * tick_wave doesn't fire below interval; fires at interval and
#     re-jitters; respects the ~70% target-density gate; respects
#     DENSITY_HARD_CAP; queues N spawn IDs into pending_wave_spawns.
#   * tick_burst gates on a lower (~half target) density threshold;
#     spawns a leader directly + queues N-1 packmates; emits [burst]
#     log line.
#   * drain_one pops one and triggers a spawn; empty queue is a no-op.

const WaveSpawnerScript := preload("res://scripts/wave_spawner.gd")
const StubDungeonScript := preload("res://tests/_stub_dungeon.gd")

var _dungeon: Node = null
var _wave: RefCounted = null


func before_each() -> void:
	_dungeon = StubDungeonScript.new()
	add_child_autofree(_dungeon)
	_dungeon.rng.seed = 7
	_wave = WaveSpawnerScript.new(_dungeon)


# ---------------------------------------------------------------------
# begin_floor — resets accumulators, jitters intervals
# ---------------------------------------------------------------------

func test_begin_floor_resets_accumulators_and_jitters_intervals() -> void:
	# Pollute the state so begin_floor has to clean it up.
	_wave.wave_accum = 5.0
	_wave.burst_accum = 22.0
	_wave.pending_wave_spawns.append("rat")
	_dungeon.rng.seed = 42
	_wave.begin_floor(_dungeon.rng)
	assert_eq(_wave.wave_accum, 0.0, "wave_accum reset")
	assert_eq(_wave.burst_accum, 0.0, "burst_accum reset")
	# Intervals jitter into the 6-10s / 30-50s bands.
	assert_gte(_wave.wave_interval, 6.0, "wave_interval >= 6s")
	assert_lt(_wave.wave_interval, 10.0, "wave_interval < 10s")
	assert_gte(_wave.burst_interval, 30.0, "burst_interval >= 30s")
	assert_lt(_wave.burst_interval, 50.0, "burst_interval < 50s")
	# pending queue is left alone — begin_floor only resets pacing, not
	# in-flight queued spawns. Locked here so a future drift doesn't
	# silently drop queued mobs from the prior floor.
	assert_eq(_wave.pending_wave_spawns.size(), 1, "pending queue preserved across begin_floor")


# ---------------------------------------------------------------------
# tick_wave — gating + queue
# ---------------------------------------------------------------------

func test_tick_wave_does_not_fire_before_interval() -> void:
	_wave.begin_floor(_dungeon.rng)
	# Sub-interval delta — no fire. Interval is in [6, 10) post-jitter,
	# so 1s tick is always under.
	_wave.tick_wave(1.0)
	assert_eq(_wave.pending_wave_spawns.size(), 0, "no queue under interval")
	assert_eq(_dungeon.spawn_calls.size(), 0, "no spawn calls under interval")


func test_tick_wave_fires_at_interval_queues_and_re_jitters() -> void:
	_wave.begin_floor(_dungeon.rng)
	var first_interval: float = _wave.wave_interval
	# Floor 1 target = 70 + 1*25 = 95. alive=0, so the wave fires.
	_wave.tick_wave(first_interval + 0.1)
	# Wave queues WAVE_MIN_MOBS..WAVE_MAX_MOBS spawn ids.
	assert_gte(_wave.pending_wave_spawns.size(), WaveSpawnerScript.WAVE_MIN_MOBS,
		"queue >= WAVE_MIN_MOBS")
	assert_lt(_wave.pending_wave_spawns.size(), WaveSpawnerScript.WAVE_MAX_MOBS + 1,
		"queue <= WAVE_MAX_MOBS")
	# Accumulator reset and interval re-jittered.
	assert_eq(_wave.wave_accum, 0.0, "wave_accum reset after fire")
	assert_gte(_wave.wave_interval, 6.0, "interval re-jittered into band")
	assert_lt(_wave.wave_interval, 10.0, "interval re-jittered into band")


func test_tick_wave_skips_when_alive_at_or_above_target() -> void:
	_wave.begin_floor(_dungeon.rng)
	# Floor 1 target = round(70 + 1*25) = 95. Push alive count up to
	# the gate so the wave should skip.
	_dungeon.current_floor = 1
	for _i in 95:
		_dungeon.add_alive_enemy()
	_wave.tick_wave(_wave.wave_interval + 0.1)
	assert_eq(_wave.pending_wave_spawns.size(), 0, "skipped at-or-above target")


func test_tick_wave_skips_at_density_hard_cap() -> void:
	_wave.begin_floor(_dungeon.rng)
	# Bump current_floor very high so the soft target would exceed
	# DENSITY_HARD_CAP, but keep alive at the cap so the cap branch
	# triggers explicitly.
	_dungeon.current_floor = 100
	for _i in WaveSpawnerScript.DENSITY_HARD_CAP:
		_dungeon.add_alive_enemy()
	_wave.tick_wave(_wave.wave_interval + 0.1)
	assert_eq(_wave.pending_wave_spawns.size(), 0, "skipped at DENSITY_HARD_CAP")


func test_tick_wave_skips_when_floor_not_ready() -> void:
	_wave.begin_floor(_dungeon.rng)
	_dungeon._floor_ready = false
	_wave.tick_wave(_wave.wave_interval + 0.1)
	# Accumulator advanced ZERO because the early-return is before
	# the increment — guards against ticking accumulators during a
	# build (which would race the floor-ready flip).
	assert_eq(_wave.wave_accum, 0.0, "no accumulator advance during build")
	assert_eq(_wave.pending_wave_spawns.size(), 0, "no queue while floor not ready")


func test_tick_wave_skips_when_bot_dead() -> void:
	_wave.begin_floor(_dungeon.rng)
	_dungeon.bot.is_alive = false
	_wave.tick_wave(_wave.wave_interval + 0.1)
	assert_eq(_wave.pending_wave_spawns.size(), 0, "no queue when bot dead")


func test_tick_wave_caps_queue_size_at_remaining_target() -> void:
	_wave.begin_floor(_dungeon.rng)
	# Target = 95 at floor 1. Add 92 alive so target - alive = 3, which
	# is below WAVE_MIN_MOBS (4). Queue should cap at 3.
	_dungeon.current_floor = 1
	for _i in 92:
		_dungeon.add_alive_enemy()
	_wave.tick_wave(_wave.wave_interval + 0.1)
	assert_eq(_wave.pending_wave_spawns.size(), 3, "queue capped at target - alive")


# ---------------------------------------------------------------------
# tick_burst — gating + leader spawn + packmates queued
# ---------------------------------------------------------------------

func test_tick_burst_does_not_fire_before_interval() -> void:
	_wave.begin_floor(_dungeon.rng)
	_wave.tick_burst(5.0)
	assert_eq(_dungeon.spawn_calls.size(), 0, "no spawn under interval")
	assert_eq(_wave.pending_wave_spawns.size(), 0, "no queue under interval")


func test_tick_burst_fires_spawns_leader_and_queues_packmates() -> void:
	_wave.begin_floor(_dungeon.rng)
	var n_alive_before: int = _dungeon.spawn_calls.size()
	# Push past the burst interval so it fires.
	_wave.tick_burst(_wave.burst_interval + 0.1)
	# Leader spawned directly via _spawn_specific.
	assert_eq(_dungeon.spawn_calls.size(), n_alive_before + 1, "leader spawned directly")
	var leader: Dictionary = _dungeon.spawn_calls[-1]
	# Leader rolls MAGIC tier — the last arg in the recorded call.
	assert_eq(leader["tier"], 1, "leader spawned with PACK_MAGIC tier (Enemy.PACK_MAGIC = 1)")
	# Packmates queued: BURST_MIN_MOBS-1 .. BURST_MAX_MOBS-1.
	assert_gte(_wave.pending_wave_spawns.size(), WaveSpawnerScript.BURST_MIN_MOBS - 1,
		"packmates >= BURST_MIN_MOBS - 1")
	assert_lt(_wave.pending_wave_spawns.size(), WaveSpawnerScript.BURST_MAX_MOBS,
		"packmates <= BURST_MAX_MOBS - 1")
	# Every queued packmate uses the leader's id.
	var pack_id: String = String(leader["id"])
	for entry in _wave.pending_wave_spawns:
		assert_eq(String(entry), pack_id, "packmate id matches leader")


func test_tick_burst_skips_above_half_target() -> void:
	_wave.begin_floor(_dungeon.rng)
	# Floor 1 burst threshold = round(50 + 1*20) = 70. Add 70 alive so
	# the gate fires.
	_dungeon.current_floor = 1
	for _i in 70:
		_dungeon.add_alive_enemy()
	_wave.tick_burst(_wave.burst_interval + 0.1)
	assert_eq(_dungeon.spawn_calls.size(), 0, "no leader spawn above burst threshold")
	assert_eq(_wave.pending_wave_spawns.size(), 0, "no queue above burst threshold")


# ---------------------------------------------------------------------
# drain_one — pop + spawn + warp
# ---------------------------------------------------------------------

func test_drain_one_pops_and_spawns() -> void:
	_wave.pending_wave_spawns.append("rat")
	_wave.pending_wave_spawns.append("kobold")
	_wave.drain_one()
	assert_eq(_wave.pending_wave_spawns.size(), 1, "queue popped one")
	assert_eq(String(_wave.pending_wave_spawns[0]), "kobold", "FIFO order preserved")
	assert_eq(_dungeon.spawn_calls.size(), 1, "spawn invoked")
	var call: Dictionary = _dungeon.spawn_calls[0]
	assert_eq(String(call["id"]), "rat", "popped front and spawned it")
	# tier=0 because Enemy.PACK_NORMAL == 0 in the project. Lock the
	# value here so a future PACK_NORMAL renumber surfaces in the test.
	assert_eq(call["tier"], 0, "drain spawns at PACK_NORMAL")


func test_drain_one_no_op_on_empty_queue() -> void:
	assert_eq(_wave.pending_wave_spawns.size(), 0, "queue empty precondition")
	_wave.drain_one()
	assert_eq(_dungeon.spawn_calls.size(), 0, "no spawn on empty queue")
