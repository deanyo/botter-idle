extends Node

const DUNGEON_SCENE := preload("res://scenes/dungeon.tscn")
const REPORT_SCENE := preload("res://scenes/run_report.tscn")
const OUTPOST_SCENE := preload("res://scenes/outpost.tscn")
const SHOP_SCENE := preload("res://scenes/shop.tscn")
const MAIN_MENU_SCENE := preload("res://scenes/main_menu.tscn")
const VIDEO_OPTIONS_SCENE := preload("res://scenes/video_options.tscn")
const FX_TUNER_SCENE := preload("res://scenes/fx_tuner.tscn")
const CHARACTER_CREATE_SCENE := preload("res://scenes/character_create.tscn")
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

# Last-ditch save flush on window close. On desktop/Steam this fires
# from the OS-level WM close (cmd-Q, X button); on web it fires from
# the engine's pagehide hook. Pairs with the JS-side pagehide listener
# we install via _install_web_close_handler — both paths converge on
# SaveState.flush_to_disk so an unsaved boss-kill / shop-purchase /
# run-end can't be lost to a tab close. Audit fix 2026-06-09.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		# Persist whatever the active screen has in memory — dungeon's
		# flush_to_save folds in-flight loot drops into the segment
		# array before the wrapper write.
		if current_screen and current_screen.has_method("flush_to_save"):
			current_screen.flush_to_save()
		# Re-write the current state through the atomic-rotate path,
		# then ask the underlying FS to durably commit.
		var save: Dictionary = SaveState.load_state()
		SaveState.save_state(save)
		SaveState.flush_to_disk()

func _ready() -> void:
	# Print the build version stamp + bake it into the window title
	# so users can verify which build they're running across browser
	# cache layers, even when the in-game debug HUD is occluded.
	var bf := FileAccess.open("res://data/build_version.json", FileAccess.READ)
	if bf != null:
		var bv: Variant = JSON.parse_string(bf.get_as_text())
		if typeof(bv) == TYPE_DICTIONARY:
			var ver: String = String(bv.get("version", "?"))
			var ts: String = String(bv.get("ts", "?"))
			print("[build] version=%s ts=%s" % [ver, ts])
			DisplayServer.window_set_title("Botter — build %s" % ver)
			# On HTML5 the window title becomes the browser tab label.
			if OS.has_feature("web"):
				JavaScriptBridge.eval(
					"document.title = 'Botter — build " + ver + "';",
					true)
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
		# Auto-grind picks a real branch instead of leaving _selected_branch
		# empty — empty triggers BiomeData.roll_run_plan's legacy "random
		# biome each floor" path, which deposits a level-1 bot in tier-3
		# Crypt floors and stalemates against liches. Picks the lowest
		# tier with under-cleared branches so the run mirrors a real
		# player progression. 2026-06-05.
		_selected_branch = _pick_grind_branch()
		GrindLog.log_line("[run] deploy branch=%s" % _selected_branch)
		_on_deploy()
	elif DebugJump.active:
		# Skip the garage; jump straight into the dungeon.
		_on_deploy()
	else:
		# Web-only: install a JS pagehide listener that fires
		# FS.syncfs the moment the browser detects the tab is closing
		# / navigating away / hiding. NOTIFICATION_WM_CLOSE_REQUEST is
		# unreliable on web (Chrome doesn't fire it for X-button close;
		# Safari fires it inconsistently); pagehide does. Modern
		# browsers run a small synchronous-ish window during pagehide
		# so an IDBFS commit started here typically completes before
		# the page unloads. Audit fix 2026-06-09.
		if OS.has_feature("web"):
			_install_web_close_handler()
		# Apply offline progress before the menu loads so the player sees
		# the loot in their inventory + a "While You Were Away" banner.
		# Skipped in grind/debug-jump because those use the debug save and
		# the timestamp diff would be misleading.
		# Side effect: ItemsDb caches items + enemies + monster_mods
		# during this call, which warms the dungeon load path so the
		# first deploy doesn't pay a 30-60ms parse hit. Perf pass
		# 2026-06-04.
		_pending_offline_summary = _apply_offline_progress()
		ItemsDb.preload_all()
		# Instantiate the universal pause menu only for live play. Auto-
		# grind would freeze on its first Esc; screenshot mode would
		# capture the dimmed pause overlay over the dungeon.
		_install_pause_menu()
		_show_main_menu()

func _install_web_close_handler() -> void:
	# Install a JS pagehide listener that runs FS.syncfs unconditionally
	# whenever the tab is hidden, closed, or navigated away from. The
	# bytes were already committed to IDBFS at save_state time; this
	# call promotes them from indexed-db's in-memory cache to durable
	# storage. visibilitychange covers mobile browser background-tab
	# transitions which don't always fire pagehide.
	JavaScriptBridge.eval("""
		(function() {
			if (typeof FS === 'undefined' || !FS.syncfs) return;
			if (window.__botter_close_handler_installed) return;
			window.__botter_close_handler_installed = true;
			var flush = function() {
				try { FS.syncfs(false, function(err) {}); } catch (e) {}
			};
			window.addEventListener('pagehide', flush);
			window.addEventListener('beforeunload', flush);
			document.addEventListener('visibilitychange', function() {
				if (document.visibilityState === 'hidden') flush();
			});
		})();
	""", true)

func _install_pause_menu() -> void:
	pause_menu = _PauseMenu.new()
	add_child(pause_menu)
	pause_menu.resume_requested.connect(func(): pass)  # no-op
	pause_menu.video_settings_requested.connect(func(): pass)  # handled in pause_menu
	pause_menu.main_menu_requested.connect(_pause_to_main_menu)
	pause_menu.abandon_requested.connect(_pause_abandon_run)
	pause_menu.quit_requested.connect(func(): get_tree().quit())

# Returning to the main menu mid-run discards the active dungeon
# scene. Pre-2026-06-07 the dungeon never serialized so loot picked
# up this run vanished — user catch. Now we flush the dungeon's
# in-memory state to disk first (gold/xp/level/inventory/equipped +
# the run_active flag so the outpost shows the in-progress banner).
# Pause-Abandon takes a different path (_pause_abandon_run) — that
# DOES treat the run as defeated and shows the run report.
func _pause_to_main_menu() -> void:
	if current_screen and current_screen.has_method("flush_to_save"):
		current_screen.flush_to_save()
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
	# Routes through ItemsDb's session cache so the parse only happens
	# once even though both main + dungeon need the dict. Perf pass
	# 2026-06-04.
	return ItemsDb.items()

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
	if menu.has_signal("create_character_pressed"):
		menu.create_character_pressed.connect(_show_character_create)
	if menu.has_signal("paperdoll_audit_pressed"):
		menu.paperdoll_audit_pressed.connect(_show_paperdoll_audit)
	if menu.has_signal("spell_showcase_pressed"):
		menu.spell_showcase_pressed.connect(_show_spell_showcase)
	if menu.has_signal("item_generator_pressed"):
		menu.item_generator_pressed.connect(_show_item_generator)
	if menu.has_signal("credits_pressed"):
		menu.credits_pressed.connect(_show_credits)

func _show_video_options() -> void:
	var opts: Node = VIDEO_OPTIONS_SCENE.instantiate()
	_swap(opts)
	opts.back_pressed.connect(_show_main_menu)

func _show_fx_tuner() -> void:
	var tuner: Node = FX_TUNER_SCENE.instantiate()
	_swap(tuner)
	tuner.back_pressed.connect(_show_main_menu)

func _show_paperdoll_audit() -> void:
	# Authoring screen — no .tscn; the script paints itself in _ready.
	var script := load("res://scripts/paperdoll_audit.gd")
	var screen: Control = script.new()
	_swap(screen)
	screen.back_pressed.connect(_show_main_menu)

func _show_spell_showcase() -> void:
	# Spell preview / authoring screen — same shape as paperdoll audit
	# (script-only, no .tscn). 2026-06-05.
	var script := load("res://scripts/spell_showcase.gd")
	var screen: Control = script.new()
	_swap(screen)
	screen.back_pressed.connect(_show_main_menu)

func _show_item_generator() -> void:
	# Random-item-generator screen — same script-only shape. Rolls 100
	# random instances, lets the user select + export favorites.
	# 2026-06-05.
	var script := load("res://scripts/item_generator.gd")
	var screen: Control = script.new()
	_swap(screen)
	screen.back_pressed.connect(_show_main_menu)

func _show_credits() -> void:
	var script := load("res://scripts/credits.gd")
	var screen: Control = script.new()
	_swap(screen)
	screen.back_pressed.connect(_show_main_menu)

func _show_character_create() -> void:
	var screen: Node = CHARACTER_CREATE_SCENE.instantiate()
	_swap(screen)
	screen.back_pressed.connect(_show_main_menu)
	# Confirming a species writes to save and routes back to main menu
	# so the player can immediately deploy with the new bot.
	if screen.has_signal("character_confirmed"):
		screen.character_confirmed.connect(func(_id): _show_main_menu())

var _selected_branch: String = ""
# Snapshot of unlocked_branches at run start so the run report can
# announce "new branches unlocked" diff against this baseline. Beat 10
# (run report unlock prominence) — 2026-06-04.
var _unlocked_at_run_start: Array = []

func _show_outpost() -> void:
	_swap(OUTPOST_SCENE.instantiate())
	# Outpost emits deploy_pressed(branch_id). Older signal-without-arg
	# call sites (run report, debug-jump) bind via _deploy_branch.
	if current_screen.has_signal("deploy_pressed"):
		current_screen.deploy_pressed.connect(_deploy_branch)
	if current_screen.has_signal("shop_pressed"):
		current_screen.shop_pressed.connect(_show_shop)

func _show_shop() -> void:
	var shop: Node = SHOP_SCENE.instantiate()
	_swap(shop)
	shop.back_pressed.connect(_show_outpost)

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
	# Mark the run active so the outpost UI knows whether to label the
	# branch button "Deploy" or "Redeploy → Floor N." Cleared on victory
	# (in _on_run_ended) or by an explicit End Run button on the outpost.
	# Death keeps it true.
	var save: Dictionary = SaveState.load_state()
	save["run_active"] = true
	save["run_branch"] = _selected_branch
	SaveState.save_state(save)
	# Snapshot unlocked branches so the run report can list any that
	# unlocked DURING this run. Beat 10 — 2026-06-04.
	_unlocked_at_run_start = (save.get("unlocked_branches", ["dungeon"]) as Array).duplicate()
	# Dungeon instantiate() is the heaviest scene load in the game.
	# Paint the curtain BEFORE the heavy work so the player sees an
	# instant transition; keep it up until floor_started fires (real
	# end of the load), with a safety timeout in LoadingCurtain.
	# Perf pass 2026-06-04 — replaces the fixed-duration show_for_swap.
	var use_curtain: bool = not auto_grind and not OS.has_feature("dedicated_server")
	if use_curtain and LoadingCurtain:
		LoadingCurtain.show_curtain("Entering dungeon…")
		# Two frames so the curtain actually paints before the heavy
		# work blocks the main thread. One frame would still show a
		# blank curtain on slow loads.
		await get_tree().process_frame
		await get_tree().process_frame
	var dungeon: Node = DUNGEON_SCENE.instantiate()
	dungeon.branch_id = _selected_branch
	# Wire the curtain to the dungeon BEFORE _swap so the connection
	# is in place when floor_started fires.
	if use_curtain and LoadingCurtain:
		LoadingCurtain.hold_until_signal(dungeon, "floor_started", "Entering dungeon…")
	_swap(dungeon, true)  # skip the swap-fired curtain — we have our own
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
	# Next-tier unlock requires every tier-N branch to be cleared TWICE.
	# 2026-06-05: was 1 kill per branch. The user wants the dungeon to
	# feel meaningful — fully gearing up after a single run is too fast.
	# Two clears means players naturally re-roll loot through each branch
	# and the next tier unlocks when their build can survive a known
	# environment, not on a lucky one-shot.
	const KILLS_PER_BRANCH_TO_UNLOCK_NEXT_TIER: int = 2
	if tier < 5:
		var all_cleared: bool = true
		for sib in _TIER_BRANCHES.get(tier, []):
			if int(bosses_killed.get(sib, 0)) < KILLS_PER_BRANCH_TO_UNLOCK_NEXT_TIER:
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
	# Boss kill is the single most-impactful save in the game — losing
	# an unlock to a celebratory tab close was the audit's headline web
	# failure mode. Force the IDBFS commit immediately so the unlock is
	# durable before the player even sees the run report. Steam path
	# is no-op (FileAccess writes are already synchronous). 2026-06-09.
	SaveState.flush_to_disk()
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

# Pick a deploy branch for the next auto-grind run that simulates a
# real player progression. Walks tiers low → high, picks the FIRST
# tier whose branches haven't all been cleared (bosses_killed[branch] <
# KILLS_PER_BRANCH_TO_UNLOCK_NEXT_TIER), and within that tier selects
# the branch with the fewest kills (so progression spreads evenly
# across siblings). Falls back to the highest unlocked branch if every
# unlocked tier is fully cleared.
# 2026-06-05 — was: branch_id="" → random per-floor biome ignoring tier.
func _pick_grind_branch() -> String:
	# Forced override via env var. /grind --branch <id> sets this so a
	# regression sweep can pin every run to a specific biome (e.g. "lair"
	# to verify lair-spawn loadouts after a balance change).
	if OS.has_environment("BOTTER_GRIND_BRANCH"):
		var forced: String = OS.get_environment("BOTTER_GRIND_BRANCH")
		if forced != "":
			return forced
	var save: Dictionary = SaveState.load_state()
	var unlocked: Array = save.get("unlocked_branches", ["dungeon"])
	var bosses_killed: Dictionary = save.get("bosses_killed", {})
	# Match the next-tier-unlock threshold so the picker advances exactly
	# when the unlock fires. Keep in sync with _on_boss_killed's constant.
	const KILLS_PER_BRANCH_TO_UNLOCK_NEXT_TIER: int = 2
	for tier in range(1, 6):
		var sibs: Array = _TIER_BRANCHES.get(tier, [])
		var unlocked_sibs: Array = []
		for s in sibs:
			if unlocked.has(s):
				unlocked_sibs.append(s)
		if unlocked_sibs.is_empty():
			continue
		# Pick the under-cleared sibling with the fewest kills so the
		# bot tends to balance kills across the tier. Ties broken by
		# round-robin so a 0/0/0 tier-1 doesn't always land on the
		# first entry — without this all tier-1 deploys went to
		# `dungeon` and `mines` was never visited. 2026-06-05.
		var candidates: Array = []
		var min_k: int = 9999
		for s in unlocked_sibs:
			var k: int = int(bosses_killed.get(s, 0))
			if k >= KILLS_PER_BRANCH_TO_UNLOCK_NEXT_TIER:
				continue
			if k < min_k:
				min_k = k
				candidates = [s]
			elif k == min_k:
				candidates.append(s)
		if not candidates.is_empty():
			# Round-robin among ties using auto_grind_runs as the cursor
			# so consecutive grind runs cycle through siblings. Outside
			# auto-grind (e.g. manual deploy fallback) just pick the
			# first.
			var idx: int = auto_grind_runs % candidates.size()
			var best: String = String(candidates[idx])
			return best
	# Every unlocked branch is fully cleared — pick the highest-tier
	# unlocked branch as the "endgame loop" target.
	for tier in range(5, 0, -1):
		for s in _TIER_BRANCHES.get(tier, []):
			if unlocked.has(s):
				return s
	return "dungeon"  # safety fallback

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
	# Run-active flag bookkeeping. Victory closes the run; defeat keeps
	# it active so the outpost label reads "Redeploy → Floor N" until
	# the player explicitly ends the run from the outpost.
	var save_state_dict: Dictionary = SaveState.load_state()
	if victory:
		save_state_dict["run_active"] = false
		save_state_dict["run_branch"] = ""
		save_state_dict["run_floor_reached"] = 0
	else:
		save_state_dict["run_floor_reached"] = int(report.get("floor", 0))
	SaveState.save_state(save_state_dict)
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
		# Re-pick a branch each run so progression unlocks change which
		# branch the next run targets. Without this every run after the
		# first would re-use _selected_branch from the boot pick.
		_selected_branch = _pick_grind_branch()
		GrindLog.log_line("[run] deploy branch=%s" % _selected_branch)
		_on_deploy()
		return
	# Compute any branches newly unlocked during this run so the run
	# report can announce them with a banner. Beat 10 — 2026-06-04.
	var save_now: Dictionary = SaveState.load_state()
	var unlocked_now: Array = save_now.get("unlocked_branches", []) as Array
	var newly_unlocked: Array = []
	for b in unlocked_now:
		if not _unlocked_at_run_start.has(b):
			newly_unlocked.append(b)
	if not newly_unlocked.is_empty():
		report["newly_unlocked"] = newly_unlocked
	var rpt: Node = REPORT_SCENE.instantiate()
	_swap(rpt)
	rpt.show_report(victory, report)
	rpt.deploy_again.connect(_on_deploy)
	rpt.back_to_garage.connect(_show_outpost)
	# Block run-report dismissal until the run-end save is durably
	# flushed to IDBFS. On Steam the flush callback fires synchronously,
	# so the buttons never appear disabled. On web the typical syncfs
	# round-trip is <100ms — short enough that the player won't notice
	# the brief "Saving…" hint, but long enough that a fast tab close
	# could otherwise drop the unlock. Audit fix 2026-06-09.
	if not auto_grind:
		rpt.mark_durable_save_pending()
		SaveState.flush_to_disk(func() -> void:
			if is_instance_valid(rpt):
				rpt.mark_durable_save_complete())

func _swap(scene: Node, skip_curtain: bool = false) -> void:
	# UI polish 2026-06-04 — fire the loading curtain over every scene
	# transition. Synchronous swap (no await) so signal callers can
	# connect on the new scene immediately afterward. The curtain
	# auto-hides after a short delay set in show_for_swap; on heavy
	# scene loads (dungeon), this provides a brief deliberate
	# "Loading…" frame instead of the macOS spinner.
	#
	# `skip_curtain` is set by callers that have already wired their
	# own curtain timing (e.g. _on_deploy uses hold_until_signal so
	# the curtain stays up until the floor is actually built).
	#
	# Auto-bypassed in auto_grind so headless runs don't pay the
	# cosmetic delay.
	var use_curtain: bool = not auto_grind and not OS.has_feature("dedicated_server") and not skip_curtain
	if use_curtain and LoadingCurtain:
		LoadingCurtain.show_for_swap()
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
