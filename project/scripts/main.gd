extends Node

const DUNGEON_SCENE := preload("res://scenes/dungeon.tscn")
const REPORT_SCENE := preload("res://scenes/run_report.tscn")
const GARAGE_SCENE := preload("res://scenes/garage.tscn")

var current_screen: Node = null
var auto_grind: bool = false
var auto_grind_speed: float = 16.0
var auto_grind_max_runs: int = 999
var auto_grind_runs: int = 0
var auto_grind_floors: Dictionary = {}
var auto_grind_start_time: int = 0

func _ready() -> void:
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
				DebugJump.biome_id = parts[0].strip_edges()
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
		_show_garage()

func _show_garage() -> void:
	_swap(GARAGE_SCENE.instantiate())
	current_screen.deploy_pressed.connect(_on_deploy)

func _on_deploy() -> void:
	var dungeon: Node = DUNGEON_SCENE.instantiate()
	_swap(dungeon)
	dungeon.run_ended.connect(_on_run_ended)
	if auto_grind:
		dungeon.floor_started.connect(_on_floor_started)
		dungeon.floor_cleared.connect(_on_floor_cleared)

func _on_floor_started(_floor_num: int) -> void:
	# Per-floor summary is emitted by Dungeon when the floor is cleared (see
	# _descend in dungeon.gd). Nothing else to log here.
	pass

func _on_floor_cleared(_floor_num: int) -> void:
	# Per-floor summary already emitted by Dungeon._descend before this signal.
	pass

func _on_run_ended(victory: bool, report: Dictionary) -> void:
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
	rpt.back_to_garage.connect(_show_garage)

func _swap(scene: Node) -> void:
	if current_screen:
		current_screen.queue_free()
	current_screen = scene
	add_child(scene)

func _log(msg: String) -> void:
	GrindLog.log_line("[grind] " + msg)
