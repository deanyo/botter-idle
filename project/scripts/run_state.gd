class_name RunState
extends RefCounted

# Floor lifecycle + run lifecycle state extracted from dungeon.gd 2026-06-09
# as the fourth Tier 3 sub-system split (audit Tier 3, follow-up to
# LootFactory / HUDInventoryController / DebugDump). Held by Dungeon as
# the `run` field; mutates via methods, exposes reads via plain fields.
#
# Behavior is a strict copy of dungeon.gd's prior code — any tuning
# belongs in a separate beat. Owns the things that get reset per run
# (run_plan, modifiers, counters), per floor (floor_* counters, portal
# overlay), and across the run (kills/dropped_items/journal/run-wide
# tallies). Save persistence + run-end report assembly live here so
# end_run + flush_to_save are localised on the helper.
#
# RefCounted helper held by Dungeon as a field. The dungeon orchestrates
# the node graph (build floors, spawn enemies, render); RunState
# computes the run-scoped state changes.

const C := preload("res://scripts/constants.gd")

# Floor + run identity.
var current_floor: int = 1
var branch_id: String = ""
var run_plan: Array = []

# Player-visible loot-feed strings + per-enemy-id kill tally + dropped
# instance trail. Replayed by the run report.
var loot_log: Array[String] = []
var kills: Dictionary = {}
var dropped_items: Array = []
# Per-floor journal entries. Each entry: {floor, biome, events: [String]}.
# Append a fresh dict on floor build, append strings into back().events
# during play. Dumped into the run report at end_run.
var journal: Array = []

# Portal overlay — set when the bot enters a portal interactable, cleared
# on the floor transition that returns to the run's main progression.
# While active, the dungeon's _build_floor swaps biome to portal_biome_override
# and chest counts respect portal_loot_bias.
var portal_active: bool = false
var portal_kind: String = ""
var portal_biome_override: Dictionary = {}
var portal_loot_bias: int = 0

# Per-floor accumulators. Reset on begin_floor; emitted in record_descend_summary
# and rolled into run-wide counters there.
var floor_start_tick: int = 0
var floor_kills: int = 0
var floor_loot_picked: int = 0
var floor_chests_opened: int = 0
var floor_altars_used: int = 0
var floor_fountains_used: int = 0
var floor_portals_entered: int = 0
var floor_stalls: int = 0
var floor_hard_recoveries: int = 0
var floor_starting_hp: int = 0
var floor_placed_vaults: Array = []

# Run-wide accumulators reported on the run end summary line.
var run_kills: int = 0
var run_loot_picked: int = 0
var run_portals_entered: int = 0
var run_stalls: int = 0
var run_vaults_stamped: Array = []
var run_biomes_visited: Array = []
# IDs of `unique: true` items already dropped this run. Each unique drops
# at most once per run; subsequent rolls excluding it.
var run_dropped_uniques: Array[String] = []

# Death retreat — kept as a value to preserve save-compat with old saves
# that read max_revives, even though death = run-end as of 2026-06-05.
var revives_remaining: int = 0
var retreats_this_run: int = 0

# Per-boss-floor lethality state. Captured on entry to the boss floor;
# read on boss death (bot won) or bot death (bot lost). Logged as
# [boss-killed] / [boss-died] for balance analysis.
var boss_floor_entry_hp: int = 0
var boss_floor_entry_ms: int = 0
var boss_floor_branch: String = ""
var boss_initial_hp: int = 0

# Active run modifiers (Crowded, Endless, etc). Set at run start from
# save.branch_modifiers[branch_id]; cached here so spawn-time code paths
# don't reload the save. Effects fold into enemy count, floor count,
# rarity, gold, and chest counts.
var active_modifiers: Array = []
# Per-run resolved floor counts. Default to constants but Endless extends
# them. boss_floor always equals floors_per_run (boss is final floor).
var floors_per_run: int = 6
var boss_floor: int = 6

# Idle-game time-of-day-ish counter. Bumped 4× per second; stamped in HUD
# stats / shown to player so the run feels grounded in time.
var run_turn: int = 0
var _turn_accum: float = 0.0


# Run start: resolve modifiers, roll the run plan, reset every per-run
# accumulator. Mirrors the body of dungeon.gd's _start_run /
# _resolve_active_modifiers from the pre-extraction code. Side effects:
# may erase the consumed modifier list from save.branch_modifiers and
# re-write the save.
func init_run(branch_id_in: String, save: Dictionary, rng: RandomNumberGenerator) -> void:
	current_floor = 1
	branch_id = branch_id_in
	loot_log.clear()
	kills.clear()
	dropped_items.clear()
	journal.clear()
	# Reset run-wide counters
	run_kills = 0
	run_loot_picked = 0
	run_portals_entered = 0
	run_stalls = 0
	run_vaults_stamped = []
	run_biomes_visited = []
	run_dropped_uniques.clear()
	# Revives removed 2026-06-05 — death = run over. Save may still
	# carry max_revives=3 from older versions; force to 0 here so old
	# saves don't get the legacy 3-retreat behaviour.
	revives_remaining = 0
	retreats_this_run = 0
	# Resolve modifiers up front so floor count + plan size reflect Endless
	# and any future floor-shaping mods.
	_resolve_active_modifiers(save)
	run_plan = BiomeData.roll_run_plan(rng, branch_id, floors_per_run)
	# Portal overlay is run-scoped — clear any stale state from the
	# previous run.
	portal_active = false
	portal_kind = ""
	portal_biome_override = {}
	portal_loot_bias = 0
	run_turn = 0
	_turn_accum = 0.0


# Called from init_run. Pulls the modifier list out of save (consuming
# the entry — modifiers are one-shot per deploy) and sets floors_per_run /
# boss_floor accordingly.
func _resolve_active_modifiers(save: Dictionary) -> void:
	var all_mods: Dictionary = save.get("branch_modifiers", {})
	active_modifiers = (all_mods.get(branch_id, []) as Array).duplicate() if branch_id != "" else []
	if branch_id != "" and all_mods.has(branch_id):
		all_mods.erase(branch_id)
		save["branch_modifiers"] = all_mods
		SaveState.save_state(save)
	if not active_modifiers.is_empty():
		GrindLog.log_line("[run] modifiers=%s" % str(active_modifiers))
	var extra_floors: int = int(RunModifiers.sum_effect(active_modifiers, "extra_floors", 0.0))
	floors_per_run = C.FLOORS_PER_RUN + extra_floors
	boss_floor = floors_per_run


# Floor build — reset every per-floor counter. Called from
# dungeon._async_build_floor early in the build pipeline. Captures the
# current process-frame as the floor_start_tick so descend can compute
# duration.
func begin_floor() -> void:
	floor_start_tick = Engine.get_process_frames()
	floor_kills = 0
	floor_loot_picked = 0
	floor_chests_opened = 0
	floor_altars_used = 0
	floor_fountains_used = 0
	floor_portals_entered = 0
	floor_stalls = 0
	floor_hard_recoveries = 0
	floor_placed_vaults = []


# Boss-floor lethality snapshot — captures the bot's entry HP and
# wall-clock so the [boss-killed] / [boss-died] log lines can report
# how lethal the boss was relative to bot capacity. Caller checks
# is_final_boss_floor + bot validity before calling. boss_initial_hp
# is reset before _spawn_enemies in dungeon.gd and populated by the
# boss-spawn paths.
func capture_boss_floor_entry(bot_hp: int, biome_id: String) -> void:
	boss_floor_entry_hp = bot_hp
	boss_floor_entry_ms = Time.get_ticks_msec()
	boss_floor_branch = biome_id


# Floor identity probes — used by spawn / loot logic to decide whether
# this floor needs a boss / miniboss / portal slot.
func is_final_boss_floor() -> bool:
	return current_floor >= boss_floor


func is_miniboss_floor(f: int) -> bool:
	return f != boss_floor and f in C.MINIBOSS_FLOORS


# Per-event counter bumps — keep per-system aggregation to a single
# call so the dungeon side stays a thin orchestrator. Each `note_*`
# also touches journal where appropriate.
func note_kill(enemy_id: String) -> void:
	floor_kills += 1
	kills[enemy_id] = int(kills.get(enemy_id, 0)) + 1


func note_loot_picked(inst: Dictionary) -> void:
	floor_loot_picked += 1
	dropped_items.append(inst)


func note_chest_opened() -> void:
	floor_chests_opened += 1


func note_altar_used() -> void:
	floor_altars_used += 1


func note_fountain_used() -> void:
	floor_fountains_used += 1


func note_portal_entered() -> void:
	floor_portals_entered += 1


func note_stall() -> void:
	floor_stalls += 1


func note_hard_recovery() -> void:
	floor_hard_recoveries += 1


# Vault placement — recorded once per floor. Caller passes the vault
# name strings; we dedupe across the run.
func record_floor_vaults(vault_names: Array) -> void:
	floor_placed_vaults = []
	for vname in vault_names:
		var s: String = String(vname)
		floor_placed_vaults.append(s)
		if not run_vaults_stamped.has(s):
			run_vaults_stamped.append(s)


# Loot-feed string trail. Both grind logging and the run report read
# this; mirrors loot_log.append in the prior dungeon.gd code.
func append_loot_log(msg: String) -> void:
	loot_log.append(msg)


func note_dropped_unique(item_id: String) -> void:
	run_dropped_uniques.append(item_id)


func is_unique_dropped(item_id: String) -> bool:
	return run_dropped_uniques.has(item_id)


# Portal overlay — bot stepped onto a portal interactable. While active,
# the dungeon swaps the floor's biome to `override` and chest spawns
# fold loot_bias into rarity rolls. Cleared by exit_portal once the
# bot uses the stairs back to the main run progression.
func enter_portal(kind: String, override: Dictionary, loot_bias: int) -> void:
	portal_active = true
	portal_kind = kind
	portal_biome_override = override
	portal_loot_bias = loot_bias


func exit_portal() -> void:
	portal_active = false
	portal_kind = ""
	portal_biome_override = {}
	portal_loot_bias = 0


# Floor-end summary. Emits the [floor] grind log line, rolls per-floor
# accumulators into the run-wide tally, registers the floor's biome as
# visited. Caller emits floor_cleared, exits the portal overlay if it
# was active, and decides whether to advance_to_next_floor or end_run
# (run_done in the return tells them which).
func record_descend_summary(biome_id: String, bot_hp: int) -> Dictionary:
	var ticks: int = Engine.get_process_frames() - floor_start_tick
	var floor_label: String = "%s%s" % [biome_id, ".portal" if portal_active else ""]
	var hp_lost: int = max(0, floor_starting_hp - bot_hp)
	GrindLog.log_line("[floor] f=%d biome=%s ticks=%d kills=%d loot=%d chests=%d altars=%d fountains=%d portals=%d stalls=%d hp_lost=%d" % [
		current_floor, floor_label, ticks, floor_kills, floor_loot_picked,
		floor_chests_opened, floor_altars_used, floor_fountains_used,
		floor_portals_entered, floor_stalls, hp_lost,
	])
	# Run-wide accumulators
	run_kills += floor_kills
	run_loot_picked += floor_loot_picked
	run_portals_entered += floor_portals_entered
	run_stalls += floor_stalls
	if not run_biomes_visited.has(biome_id):
		run_biomes_visited.append(biome_id)
	return {
		"hp_lost": hp_lost,
		"run_done": current_floor >= floors_per_run,
	}


# Advance to the next floor. Caller already consumed
# record_descend_summary's return and decided whether to start a fresh
# floor build vs end the run.
func advance_to_next_floor() -> void:
	current_floor += 1


# Bot just hit HP=0. If the player has a revive left, retreat to floor 1
# of the current branch. When revives are exhausted, returns false and
# the caller should _end_run(false). Returns true if absorbed.
#
# NB the actual bot revive (HP reset, tween kill, scene state) stays
# in dungeon.gd because it touches the bot's tween + rig. RunState
# only owns the bookkeeping side: counter decrements, log line.
func try_death_retreat(reason: String) -> bool:
	if revives_remaining <= 0:
		return false
	revives_remaining -= 1
	retreats_this_run += 1
	GrindLog.log_line("[retreat] reason=\"%s\" revives_left=%d retreats_this_run=%d" % [
		reason, revives_remaining, retreats_this_run,
	])
	# Reset to floor 1 of the same branch.
	current_floor = 1
	return true


# Idle-game time-of-day-ish counter. Bumped 4× per second.
func tick_run_turn(delta: float) -> void:
	_turn_accum += delta
	if _turn_accum >= 0.25:
		_turn_accum -= 0.25
		run_turn += 1


# Journal helpers. Floor entry is a dict; events are strings appended
# into the most-recent entry.
func journal_floor_entry(entry: Dictionary) -> void:
	journal.append(entry)


func journal_event(msg: String) -> void:
	if not journal.is_empty():
		journal.back().events.append(msg)


# Persist mid-run state to disk WITHOUT ending the run. Called by
# main.gd when the player goes back to the main menu mid-run so
# loot/gold/xp earned this run isn't lost when the dungeon scene
# discards. Pre-2026-06-07 the back-to-menu path bypassed any save
# and items vanished — user catch.
#
# Caller passes the bot + inv refs explicitly so the helper never
# reads back into dungeon for live state. inv may be null for
# headless/early paths; guard inside.
func flush_to_save(bot: Node, inv: RefCounted) -> void:
	if not is_instance_valid(bot):
		return
	# Fold any live LootDrops the bot hadn't finished walking to into the
	# inventory before we serialize. Pre-fix, chests rolled their loot at
	# OPEN time + spawned drops, but items only entered the inventory
	# cache when complete_loot_pickup ran (after the bot stood on each
	# drop for ~0.4-0.8s). Esc → Main Menu mid-pickup discarded
	# everything. Audit fix 2026-06-08 (commit f80376b).
	if inv != null:
		inv.flush_pending_drops(current_floor)
		inv.maybe_auto_salvage_if_pending()
	var save: Dictionary = SaveState.load_state()
	save.gold = bot.gold
	save.level = bot.level
	save.xp = bot.xp
	save.inventory = inv.hud_inv_cache.duplicate(true) if inv != null else []
	save.equipped = bot.equipped.duplicate(true)
	save.highest_floor = maxi(int(save.get("highest_floor", 0)), current_floor)
	save.stat_points_unspent = int(bot.upgrade_state.get("stat_points_unspent", 0))
	save.stat_alloc_str = int(bot.upgrade_state.get("stat_alloc_str", 0))
	save.stat_alloc_dex = int(bot.upgrade_state.get("stat_alloc_dex", 0))
	save.stat_alloc_int = int(bot.upgrade_state.get("stat_alloc_int", 0))
	# Mark the run as still-active so the outpost shows the "Run in
	# progress: <branch> — Floor N" banner when the player returns.
	# Same flag _end_run sets on defeat (so they can redeploy).
	save.run_active = true
	save.run_branch = String(run_plan[0]) if run_plan.size() > 0 else ""
	save.run_floor_reached = current_floor
	SaveState.save_state(save)


# Run is over. Final salvage pass, persist save, build the run-report
# dict that the dungeon emits on `run_ended`. Caller emits the signal
# and handles the spell-system summary log line.
#
# Returns the report dict; caller passes it as the second arg of the
# run_ended signal emit.
func end_run(victory: bool, bot: Node, inv: RefCounted, items_db: Dictionary) -> Dictionary:
	# Final salvage pass before we serialize. Done unconditionally so
	# the saved inventory respects the cap even if the run ended on a
	# pickup that overflowed without a chance to flush.
	if inv != null:
		inv.maybe_auto_salvage_if_pending()
	# Loot is loot — banked on victory or death. The idle-game loop is "watch
	# the bot fill your stash"; a 50% death tax punishes idle play.
	var save: Dictionary = SaveState.load_state()
	save.gold = bot.gold
	save.level = bot.level
	save.xp = bot.xp
	# Persist whatever is currently in the live HUD inventory cache. That's
	# the source of truth — it includes base inventory + everything looted
	# this run, minus anything that got equipped mid-run (those moved to
	# bot.equipped, also persisted below).
	save.inventory = inv.hud_inv_cache.duplicate(true) if inv != null else []
	save.equipped = bot.equipped.duplicate(true) if is_instance_valid(bot) else save.get("equipped", {})
	save.runs_completed = int(save.get("runs_completed", 0)) + 1
	save.highest_floor = maxi(int(save.get("highest_floor", 0)), current_floor)
	# Stat-point allocation: bot.upgrade_state IS the save dict during a
	# run (set by reference in apply_gear), so any in-run mutations
	# (level-up adds 3 unspent) are already reflected when we re-load
	# save above. Pull them across explicitly so they survive even if
	# something rebinds bot.upgrade_state.
	if is_instance_valid(bot):
		save.stat_points_unspent = int(bot.upgrade_state.get("stat_points_unspent", 0))
		save.stat_alloc_str = int(bot.upgrade_state.get("stat_alloc_str", 0))
		save.stat_alloc_dex = int(bot.upgrade_state.get("stat_alloc_dex", 0))
		save.stat_alloc_int = int(bot.upgrade_state.get("stat_alloc_int", 0))
	SaveState.save_state(save)
	var kept: Array = dropped_items.duplicate(true)
	return {
		"victory": victory,
		"floor": current_floor,
		"level": bot.level,
		"xp": bot.xp,
		"gold": bot.gold,
		"hp": bot.hp,
		"max_hp": bot.max_hp,
		"retreats": retreats_this_run,
		"salvaged_count": inv.run_salvaged_count if inv != null else 0,
		"salvaged_gold": inv.run_salvaged_gold if inv != null else 0,
		"kills": kills.duplicate(),
		"loot_log": loot_log.duplicate(),
		"dropped": dropped_items.duplicate(),
		"kept": kept,
		"journal": journal.duplicate(true),
		"items_db": items_db,
	}
