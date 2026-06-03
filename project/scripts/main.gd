extends Node

const DUNGEON_SCENE := preload("res://scenes/dungeon.tscn")
const REPORT_SCENE := preload("res://scenes/run_report.tscn")
const OUTPOST_SCENE := preload("res://scenes/outpost.tscn")
const MAIN_MENU_SCENE := preload("res://scenes/main_menu.tscn")
const VIDEO_OPTIONS_SCENE := preload("res://scenes/video_options.tscn")
const FX_TUNER_SCENE := preload("res://scenes/fx_tuner.tscn")
const VS := preload("res://scripts/video_settings.gd")
const _PauseMenu := preload("res://scripts/pause_menu.gd")

var current_screen: Node = null
# Universal Esc-key pause menu. Created lazily after auto-grind/debug
# detection so headless harness modes don't paint a UI.
var pause_menu: Node = null  # PauseMenu — typed Node to avoid class-resolve order pain
var auto_grind: bool = false
var auto_grind_speed: float = 16.0
var auto_grind_max_runs: int = 999
var auto_grind_runs: int = 0
var auto_grind_floors: Dictionary = {}
var auto_grind_start_time: int = 0

func _ready() -> void:
	# Apply persisted video settings (window mode, resolution, vsync) before
	# anything paints, so the user's choice carries over launch-to-launch.
	# Skipped for grind/screenshot modes — those need a deterministic window.
	if not OS.has_environment("BOTTER_AUTO_GRIND") \
			and not FileAccess.file_exists("user://AUTO_GRIND.txt") \
			and not FileAccess.file_exists("user://DEBUG_FLOOR.txt"):
		VS.apply(VS.load_settings())
	# BOTTER_NO_VSYNC=1 — disable vsync for perf benchmarking. With ProMotion
	# 120Hz displays, vsync coupling can mask the real frame cost behind
	# discrete refresh windows.
	if OS.has_environment("BOTTER_NO_VSYNC"):
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = 0
	for arg in OS.get_cmdline_args():
		if arg == "--auto-grind" or arg == "auto-grind":
			auto_grind = true
		elif arg.begins_with("--max-runs="):
			auto_grind_max_runs = int(arg.substr(11))
		elif arg.begins_with("--speed="):
			auto_grind_speed = float(arg.substr(8))
	if OS.has_environment("BOTTER_AUTO_GRIND"):
		auto_grind = true
	if OS.has_environment("BOTTER_SPEED"):
		auto_grind_speed = float(OS.get_environment("BOTTER_SPEED"))
	if OS.has_environment("BOTTER_MAX_RUNS"):
		auto_grind_max_runs = int(OS.get_environment("BOTTER_MAX_RUNS"))

	# Fallback: marker file in user:// triggers auto-grind. Lets Claude drive without
	# needing to pass CLI args through Godot MCP run_project.
	if FileAccess.file_exists("user://AUTO_GRIND.txt"):
		var f := FileAccess.open("user://AUTO_GRIND.txt", FileAccess.READ)
		if f:
			var contents: String = f.get_as_text().strip_edges()
			auto_grind = true
			# Format: "speed,max_runs" e.g. "16,3"
			if contents != "":
				var parts: PackedStringArray = contents.split(",")
				if parts.size() >= 1:
					auto_grind_speed = float(parts[0])
				if parts.size() >= 2:
					auto_grind_max_runs = int(parts[1])

	# Debug-jump: marker file user://DEBUG_FLOOR.txt with format
	#   biome_id[,vault_name][,floor_num]
	# When set, the dungeon scene forces that biome on floor 1 (or the given
	# floor_num) and optionally forces a specific vault to stamp. Lets us
	# validate biome/vault rendering in seconds without grinding 10 floors.
	if FileAccess.file_exists("user://DEBUG_FLOOR.txt"):
		var df := FileAccess.open("user://DEBUG_FLOOR.txt", FileAccess.READ)
		if df:
			var contents: String = df.get_as_text().strip_edges()
			if contents != "":
				var parts: PackedStringArray = contents.split(",")
				var first: String = parts[0].strip_edges()
				if first == "showcase":
					# showcase[,no_screenshot] — hand-curated visual audit floor.
					DebugJump.showcase = true
					DebugJump.active = true
					DebugJump.biome_id = "dungeon"
					print("[debug-jump] showcase mode")
				else:
					DebugJump.biome_id = first
					if parts.size() >= 2 and parts[1].strip_edges() != "" and parts[1].strip_edges() != "_":
						DebugJump.vault_name = parts[1].strip_edges()
					if parts.size() >= 3 and parts[2].strip_edges() != "" and parts[2].strip_edges() != "_":
						DebugJump.floor_num = int(parts[2].strip_edges())
					if parts.size() >= 4 and parts[3].strip_edges() != "":
						DebugJump.screenshot = true
					DebugJump.active = true
					print("[debug-jump] biome=%s vault=%s floor=%d screenshot=%s" % [DebugJump.biome_id, DebugJump.vault_name, DebugJump.floor_num, str(DebugJump.screenshot)])

	# Debug-jump always takes priority over auto-grind so screenshots aren't
	# polluted by speed-scaled floor descents.
	if DebugJump.active:
		auto_grind = false
		Engine.time_scale = 1.0
	# Save-state isolation: benchmark and screenshot runs use a separate save
	# slot so they don't bake the playtest bot into a level-300 god.
	if auto_grind or DebugJump.active:
		SaveState.debug_mode = true
	# Invincible bot in grind mode — lets us reach floor 10 reliably so the
	# audit covers late-floor generation. Live playtest is unaffected.
	# Balance experiments (/duel, /sweep) opt out via BOTTER_NO_INVINCIBLE=1
	# so build comparisons can actually fail and produce a win-rate signal.
	if auto_grind and not OS.has_environment("BOTTER_NO_INVINCIBLE"):
		DebugJump.bot_invincible = true
	# Screenshot mode: set up audit-resolution window FROM SCENE START so the
	# Dungeon can render once at the right size without mid-capture mutations.
	# 1024x1024 is the practical sweet spot for Claude's image pipeline (no
	# additional downsampling beyond what claude.ai applies anyway).
	if DebugJump.active and DebugJump.screenshot:
		var win: Window = get_window()
		if win:
			win.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
			win.size = Vector2i(1024, 1024)
	if auto_grind:
		GrindLog.enable()
		GrindLog.log_line("[run] auto-grind ENABLED speed=%sx max_runs=%d" % [str(auto_grind_speed), auto_grind_max_runs])
		Engine.time_scale = auto_grind_speed
		auto_grind_start_time = Time.get_ticks_msec()
		_on_deploy()
	elif DebugJump.active:
		# Skip the garage; jump straight into the dungeon.
		_on_deploy()
	else:
		# Apply offline progress before the menu loads so the player sees
		# the loot in their inventory + a "While You Were Away" banner.
		# Skipped in grind/debug-jump because those use the debug save and
		# the timestamp diff would be misleading.
		_pending_offline_summary = _apply_offline_progress()
		# Instantiate the universal pause menu only for live play. Auto-
		# grind would freeze on its first Esc; screenshot mode would
		# capture the dimmed pause overlay over the dungeon.
		_install_pause_menu()
		_show_main_menu()

func _install_pause_menu() -> void:
	pause_menu = _PauseMenu.new()
	add_child(pause_menu)
	pause_menu.resume_requested.connect(func(): pass)  # no-op
	pause_menu.video_settings_requested.connect(func(): pass)  # handled in pause_menu
	pause_menu.main_menu_requested.connect(_pause_to_main_menu)
	pause_menu.abandon_requested.connect(_pause_abandon_run)
	pause_menu.quit_requested.connect(func(): get_tree().quit())

# Returning to the main menu mid-run discards the active dungeon. The
# save state is untouched (no run_ended emit), so loot picked up but
# not banked is lost. Mirrors Quit-then-relaunch behavior — clean.
func _pause_to_main_menu() -> void:
	_show_main_menu()

# Abandoning a run = treat it as a loss. Calls dungeon._end_run(false)
# so loot, retreats, salvage all flow through normal failure handling
# and the run report appears.
func _pause_abandon_run() -> void:
	if current_screen and current_screen.has_method("_end_run"):
		current_screen._end_run(false)

var _pending_offline_summary: Dictionary = {}

func _apply_offline_progress() -> Dictionary:
	var save: Dictionary = SaveState.load_state()
	var items_db: Dictionary = _load_items_db()
	if items_db.is_empty():
		return {}
	var summary: Dictionary = OfflineProgress.apply(save, items_db)
	if summary.get("floors", 0) > 0:
		SaveState.save_state(save)
	return summary

func _load_items_db() -> Dictionary:
	var f := FileAccess.open("res://data/items.json", FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	var by_id: Dictionary = {}
	for it in parsed.get("items", []):
		by_id[it.id] = it
	return by_id

func _show_main_menu() -> void:
	var menu: Node = MAIN_MENU_SCENE.instantiate()
	# Hand the offline summary to the menu BEFORE adding to tree so the
	# menu's _ready can render it as a banner. One-shot — clear after.
	if not _pending_offline_summary.is_empty() and "offline_summary" in menu:
		menu.offline_summary = _pending_offline_summary
		_pending_offline_summary = {}
	_swap(menu)
	menu.play_pressed.connect(_show_outpost)
	menu.video_options_pressed.connect(_show_video_options)
	if menu.has_signal("fx_tuner_pressed"):
		menu.fx_tuner_pressed.connect(_show_fx_tuner)

func _show_video_options() -> void:
	var opts: Node = VIDEO_OPTIONS_SCENE.instantiate()
	_swap(opts)
	opts.back_pressed.connect(_show_main_menu)

func _show_fx_tuner() -> void:
	var tuner: Node = FX_TUNER_SCENE.instantiate()
	_swap(tuner)
	tuner.back_pressed.connect(_show_main_menu)

var _selected_branch: String = ""

func _show_outpost() -> void:
	_swap(OUTPOST_SCENE.instantiate())
	# Outpost emits deploy_pressed(branch_id). Older signal-without-arg
	# call sites (run report, debug-jump) bind via _deploy_branch.
	if current_screen.has_signal("deploy_pressed"):
		current_screen.deploy_pressed.connect(_deploy_branch)

func _deploy_branch(branch_id: String) -> void:
	_selected_branch = branch_id
	# Persist the picked branch so offline progress knows where the bot
	# was farming when the game closed.
	if branch_id != "":
		var save: Dictionary = SaveState.load_state()
		save["last_branch"] = branch_id
		SaveState.save_state(save)
	_on_deploy()

func _on_deploy() -> void:
	var dungeon: Node = DUNGEON_SCENE.instantiate()
	dungeon.branch_id = _selected_branch
	_swap(dungeon)
	dungeon.run_ended.connect(_on_run_ended)
	dungeon.boss_killed.connect(_on_boss_killed)
	if auto_grind:
		dungeon.floor_started.connect(_on_floor_started)
		dungeon.floor_cleared.connect(_on_floor_cleared)

# When the player kills a branch boss, unlock all sibling branches at the
# same tier and (if it's the only-unlocked branch in this tier) the first
# branch of the next tier. Mirrors the Melvor-style "clear a dungeon →
# unlock the next" hook.
const _TIER_BRANCHES := {
	1: ["dungeon", "dungeon_dark", "mines"],
	2: ["lair", "forest", "orc", "temple"],
	3: ["shoals", "swamp", "snake", "spider", "hive"],
	4: ["vaults", "crypt", "tomb", "elf", "depths"],
	5: ["forge", "glacier", "slime", "labyrinth", "abyss", "pandemonium", "zot"],
}

func _on_boss_killed(branch_id: String) -> void:
	# Always print so the user can see this fired in normal play (Godot's
	# stdout — visible from the editor or `godot --path` runs).
	print("[unlock] boss_killed signal received: branch_id=%s" % branch_id)
	if branch_id == "":
		return
	var save: Dictionary = SaveState.load_state()
	var unlocked: Array = save.get("unlocked_branches", ["dungeon"])
	var bosses_killed: Dictionary = save.get("bosses_killed", {})
	var tier: int = BiomeData.tier_for_biome(branch_id)
	if tier < 1:
		print("[unlock] skipped — tier_for_biome(%s) returned %d" % [branch_id, tier])
		return
	# Record the kill (used for the "every tier-N boss cleared" check below).
	bosses_killed[branch_id] = int(bosses_killed.get(branch_id, 0)) + 1
	var added: Array = []
	# Sibling unlock — clearing any tier-N boss unlocks the rest of tier N.
	for sib in _TIER_BRANCHES.get(tier, []):
		if not unlocked.has(sib):
			unlocked.append(sib)
			added.append(sib)
	# Next-tier unlock requires EVERY tier-N branch to have at least one
	# boss kill recorded. Stricter than the doc's "any 2" but matches the
	# user's "you should have to beat them all" call. Encourages back-
	# tracking through earlier branches with their freshly-rolled mods.
	if tier < 5:
		var all_cleared: bool = true
		for sib in _TIER_BRANCHES.get(tier, []):
			if int(bosses_killed.get(sib, 0)) <= 0:
				all_cleared = false
				break
		if all_cleared:
			for nxt in _TIER_BRANCHES.get(tier + 1, []):
				if not unlocked.has(nxt):
					unlocked.append(nxt)
					added.append(nxt)
	save.unlocked_branches = unlocked
	save.bosses_killed = bosses_killed
	SaveState.save_state(save)
	var tier_complete: bool = false
	for sib in _TIER_BRANCHES.get(tier, []):
		if int(bosses_killed.get(sib, 0)) <= 0:
			tier_complete = false
			break
		tier_complete = true
	print("[unlock] tier=%d killed=%s tier_complete=%s new=%s total=%d" % [
		tier, branch_id, str(tier_complete), str(added), unlocked.size(),
	])
	GrindLog.log_line("[unlock] killed boss=%s tier=%d tier_complete=%s new_branches=%s" % [
		branch_id, tier, str(tier_complete), str(added),
	])

func _on_floor_started(_floor_num: int) -> void:
	# Per-floor summary is emitted by Dungeon when the floor is cleared (see
	# _descend in dungeon.gd). Nothing else to log here.
	pass

func _on_floor_cleared(_floor_num: int) -> void:
	# Per-floor summary already emitted by Dungeon._descend before this signal.
	pass

func _on_run_ended(victory: bool, report: Dictionary) -> void:
	# Fallback unlock path. The primary trigger is the boss_killed signal,
	# but if anything fails (signal disconnected, boss didn't have is_boss
	# set, etc.) a victorious run on a branch should still unlock that
	# branch's tier and the next. Idempotent — _on_boss_killed only adds
	# new entries, so calling it twice is fine.
	if victory and _selected_branch != "":
		_on_boss_killed(_selected_branch)
	if auto_grind:
		auto_grind_runs += 1
		var elapsed_ms: int = Time.get_ticks_msec() - auto_grind_start_time
		var d: Node = current_screen
		var run_kills: int = int(d.run_kills) if d and "run_kills" in d else 0
		var run_loot: int = int(d.run_loot_picked) if d and "run_loot_picked" in d else 0
		var run_portals: int = int(d.run_portals_entered) if d and "run_portals_entered" in d else 0
		var run_stalls: int = int(d.run_stalls) if d and "run_stalls" in d else 0
		var run_biomes: Array = d.run_biomes_visited if d and "run_biomes_visited" in d else []
		var run_vaults: Array = d.run_vaults_stamped if d and "run_vaults_stamped" in d else []
		GrindLog.log_line("[run] end #%d victory=%s floor=%d level=%d gold=%d kills=%d loot=%d portals=%d stalls=%d biomes=%d uniq_vaults=%d elapsed=%.1fs" % [
			auto_grind_runs, str(victory), int(report.floor), int(report.level), int(report.gold),
			run_kills, run_loot, run_portals, run_stalls,
			run_biomes.size(), run_vaults.size(),
			elapsed_ms / 1000.0,
		])
		GrindLog.log_line("[run] biomes=%s" % str(run_biomes))
		if auto_grind_runs >= auto_grind_max_runs:
			GrindLog.log_line("[run] auto-grind COMPLETE total=%d runs" % auto_grind_runs)
			get_tree().quit()
			return
		_on_deploy()
		return
	var rpt: Node = REPORT_SCENE.instantiate()
	_swap(rpt)
	rpt.show_report(victory, report)
	rpt.deploy_again.connect(_on_deploy)
	rpt.back_to_garage.connect(_show_outpost)

func _swap(scene: Node) -> void:
	if current_screen:
		current_screen.queue_free()
	current_screen = scene
	add_child(scene)
	# Tell the pause menu what kind of screen we're on so it can show
	# context-appropriate buttons (Abandon Run only in dungeon, etc).
	if pause_menu != null and is_instance_valid(pause_menu):
		var ctx: String = ""
		if scene.scene_file_path == "res://scenes/dungeon.tscn":
			ctx = "dungeon"
		elif scene.scene_file_path == "res://scenes/main_menu.tscn":
			ctx = "main_menu"
		elif scene.scene_file_path == "res://scenes/outpost.tscn":
			ctx = "outpost"
		elif scene.scene_file_path == "res://scenes/run_report.tscn":
			ctx = "run_report"
		pause_menu.set_context(ctx)

func _log(msg: String) -> void:
	GrindLog.log_line("[grind] " + msg)
