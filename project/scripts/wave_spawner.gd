class_name WaveSpawner
extends RefCounted

# VS-style wave + burst density layer extracted from dungeon.gd 2026-06-09
# as the fifth Tier 3 sub-system split (audit Tier 3, follow-up to
# LootFactory / HUDInventoryController / DebugDump / RunState). Held by
# Dungeon as the `wave` field.
#
# Two spawn paths run in parallel:
#   * wave — every 6-10s, top up the floor's mob count toward ~70-75%
#     of the floor's initial density target. Gates on _floor_ready and
#     bot.is_alive. Skips when alive >= target so an invincible/over-
#     geared bot can still finish floors.
#   * burst — every 30-50s, drop a 12-18 mob MAGIC pack from one
#     direction. Skips when alive >= ~half target so it stays a
#     dramatic event for thinned floors, not an "even more mobs"
#     multiplier.
#
# Both paths queue spawn IDs into pending_wave_spawns instead of
# materializing N enemies on a single frame; drain_one() pulls one per
# frame from Dungeon._process. The stagger spreads GPU texture-upload
# + node-add cost across frames so Web GL Compatibility doesn't stall.
#
# Behavior is a strict copy of dungeon.gd's prior code — any tuning
# belongs in a separate beat.

const _Enemy := preload("res://scripts/enemy.gd")

# Pacing knobs. Wave fires every 6-10s, burst every 30-50s. Both
# accumulators reset to 0 on begin_floor; intervals re-jitter on each
# fire so the rhythm doesn't feel metronomic.
var wave_accum: float = 0.0
var wave_interval: float = 8.0
var burst_accum: float = 0.0
var burst_interval: float = 35.0
# Spawn-ID queue drained one-per-frame by Dungeon._process so a wave/
# burst of N enemies spreads across N frames instead of synchronously
# uploading N textures on the same frame.
var pending_wave_spawns: Array = []

const WAVE_MIN_MOBS := 4
const WAVE_MAX_MOBS := 8
const BURST_MIN_MOBS := 12
const BURST_MAX_MOBS := 18
const DENSITY_HARD_CAP := 400  # never exceed this active mob count

# Bound dungeon ref. The spawner reaches back into the dungeon for the
# enemies array, _floor_ready / bot / rng / current_floor / current_biome
# state, and the spawn helpers (_spawn_specific, _random_walkable_cell_far_from_bot,
# _warp_in_last_spawn). Held as a weak-ish plain ref — the dungeon owns
# this RefCounted, so the parent's lifetime always exceeds the helper's.
var _dungeon: Node = null


func _init(dungeon: Node) -> void:
	_dungeon = dungeon


# Floor build resets accumulators and re-jitters the next-fire interval
# so the player isn't punished for a slow boss-floor with a 35s burst
# on entry. Call after _floor_ready flips true. rng is the dungeon's
# per-run RandomNumberGenerator so the wave/burst rhythm is deterministic
# under same-seed playback.
func begin_floor(rng: RandomNumberGenerator) -> void:
	wave_accum = 0.0
	burst_accum = 0.0
	wave_interval = 6.0 + rng.randf() * 4.0  # 6-10s
	burst_interval = 30.0 + rng.randf() * 20.0  # 30-50s


# Periodic wave spawn — every 6-10s, top up the floor's mob count back
# toward the floor's target density. Designed as a TOP-UP: only fires
# if the alive count has dropped meaningfully below the floor's initial
# density target. Prevents invincible-bot grinds from running forever
# (waves used to pile on top, so the floor never emptied). Combat
# pivot 2026-06-04.
func tick_wave(delta: float) -> void:
	if not _dungeon._floor_ready or not is_instance_valid(_dungeon.bot) or not _dungeon.bot.is_alive:
		return
	wave_accum += delta
	if wave_accum < wave_interval:
		return
	wave_accum = 0.0
	wave_interval = 6.0 + _dungeon.rng.randf() * 4.0
	var alive: int = _count_alive_enemies()
	# Don't refill above ~70% of the floor's target density — the bot
	# needs to be able to clear enough to reach the stairs. Without this
	# gate, an invincible/over-geared bot literally cannot finish floors
	# because waves spawn faster than they kill.
	var target: int = int(round(70.0 + float(_dungeon.current_floor) * 25.0))
	if alive >= target or alive >= DENSITY_HARD_CAP:
		return
	var pool: Array = _build_enemy_pool()
	if pool.is_empty():
		return
	var n: int = _dungeon.rng.randi_range(WAVE_MIN_MOBS, WAVE_MAX_MOBS)
	n = mini(n, target - alive)
	PerfMon.note_spike_context("wave_spawn n=%d alive=%d" % [n, alive])
	# Stagger wave spawns across frames. Spawning N enemies on the same
	# frame triggers a synchronous GPU sync on Web GL Compatibility
	# (texture uploads + scene-tree updates flushed together), reading
	# as a 1-2s freeze per enemy. Push them onto a queue and drain one
	# per frame; the player perceives a streaming wave instead of a
	# synchronized clump.
	for _i in n:
		var pick: String = String(pool[_dungeon.rng.randi_range(0, pool.size() - 1)])
		pending_wave_spawns.append(pick)


# Burst event — every 30-50s, spawn a 12-18 mob MAGIC pack from one
# direction relative to the bot. No telegraph yet (Phase 4 polish);
# the cluster shape itself is the telegraph (mobs visibly stream in).
func tick_burst(delta: float) -> void:
	if not _dungeon._floor_ready or not is_instance_valid(_dungeon.bot) or not _dungeon.bot.is_alive:
		return
	burst_accum += delta
	if burst_accum < burst_interval:
		return
	burst_accum = 0.0
	burst_interval = 30.0 + _dungeon.rng.randf() * 20.0
	var alive: int = _count_alive_enemies()
	# Bursts skip if the floor's already populated — they're dramatic
	# events for a thinned floor, not an "even more mobs" multiplier.
	var burst_threshold: int = int(round(50.0 + float(_dungeon.current_floor) * 20.0))
	if alive >= burst_threshold or alive >= DENSITY_HARD_CAP:
		return
	var pool: Array = _build_enemy_pool()
	if pool.is_empty():
		return
	# Pick one cluster center far from the bot — packmates spawn within
	# _PACK_RADIUS so they read as a coherent burst.
	var pack_id: String = String(pool[_dungeon.rng.randi_range(0, pool.size() - 1)])
	var center: Vector2i = _dungeon._random_walkable_cell_far_from_bot()
	var n: int = _dungeon.rng.randi_range(BURST_MIN_MOBS, BURST_MAX_MOBS)
	n = mini(n, DENSITY_HARD_CAP - alive)
	# Leader rolls MAGIC tier so the burst has a visible elite.
	_dungeon._spawn_specific(pack_id, center, _Enemy.PACK_MAGIC)
	warp_in_last_spawn()
	# Packmates queued for staggered spawn (one per frame) — same reason
	# as wave spawns: synchronous GPU stalls on Web GL when N enemies
	# spawn in the same frame.
	for i in range(n - 1):
		pending_wave_spawns.append(pack_id)
	GrindLog.log_line("[burst] f=%d id=%s n=%d" % [_dungeon.current_floor, pack_id, n])


# Spawn at most one queued wave/burst enemy per frame so the GPU
# texture-upload + node-add cost spreads across frames. See tick_wave
# for the rationale.
func drain_one() -> void:
	if pending_wave_spawns.is_empty():
		return
	var pick: String = String(pending_wave_spawns.pop_front())
	# Stamp context BEFORE spawn so a spike during this spawn carries
	# the enemy id — narrows down which texture / shader is the culprit
	# when the spike detector fires.
	PerfMon.note_spike_context("drain_spawn id=%s queue=%d" % [pick, pending_wave_spawns.size()])
	var cell: Vector2i = _dungeon._random_walkable_cell_far_from_bot()
	_dungeon._spawn_specific(pick, cell, _Enemy.PACK_NORMAL)
	warp_in_last_spawn()


# Brief warp-in tween on the most recently spawned enemy. Scale 0.4 → 1
# + alpha 0 → 1 over 250ms so wave / burst arrivals don't look like
# they were always there. Initial-floor _spawn_packs skips this — the
# floor builds before the player sees anything anyway.
func warp_in_last_spawn() -> void:
	var enemies: Array = _dungeon.enemies
	if enemies.is_empty():
		return
	var e = enemies[enemies.size() - 1]
	if not is_instance_valid(e) or e.rig == null:
		return
	var rig: Node2D = e.rig
	var target_scale: Vector2 = rig.scale
	rig.scale = target_scale * 0.4
	rig.modulate.a = 0.0
	var tw := rig.create_tween().set_parallel(true)
	tw.tween_property(rig, "scale", target_scale, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(rig, "modulate:a", 1.0, 0.20).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


# Helper to rebuild the per-floor enemy pool — same logic as
# _spawn_enemies pool construction. Kept on the spawner so wave/burst
# can pull from the live biome roster without duplicating code.
func _build_enemy_pool() -> Array:
	var pool: Array = []
	var current_biome: Dictionary = _dungeon.current_biome
	if current_biome.is_empty():
		return pool
	var raw_pool: Variant = current_biome.get("enemy_pool", null)
	if raw_pool is Array:
		for entry in raw_pool:
			if entry is String:
				pool.append(entry)
			elif entry is Dictionary and entry.has("id"):
				pool.append(String(entry["id"]))
	return pool


func _count_alive_enemies() -> int:
	var alive: int = 0
	for e in _dungeon.enemies:
		if is_instance_valid(e) and e.is_alive:
			alive += 1
	return alive
