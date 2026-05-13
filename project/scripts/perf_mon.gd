class_name PerfMon
extends RefCounted

# Lightweight per-system µs accumulator. Begin/end pairs sample
# Time.get_ticks_usec(); a rolling window aggregates the means and feeds
# them to the debug HUD + the [perf] grind log. Zero allocation in the
# hot path — fixed-size dicts keyed on tag string.

const WINDOW_FRAMES := 240

# Tags we time. Adding a new tag is just adding a string here and a
# begin/end pair at the call site.
const TAG_FRAME       := "frame"
const TAG_FOG         := "fog"          # _refresh_fog (recompute + apply)
const TAG_LIGHTS      := "lights"       # _gather_lights + shader push
const TAG_FLICKER     := "flicker"      # FlickerDriver per-frame walk
const TAG_RENDER_FADE := "render"  # MapRenderer._process modulate fade
const TAG_AI          := "ai"           # _tick_bot + _tick_enemies

const ALL_TAGS := [TAG_FRAME, TAG_FOG, TAG_LIGHTS, TAG_FLICKER, TAG_RENDER_FADE, TAG_AI]

static var _starts: Dictionary = {}      # tag -> usec start
static var _accum_us: Dictionary = {}    # tag -> total usec in window
static var _calls: Dictionary = {}       # tag -> sample count in window
static var _frames_in_window: int = 0
static var _last_snapshot: Dictionary = {}  # tag -> avg us per frame
static var _last_frame_ms: float = 0.0
static var _last_fps: float = 0.0
static var _floor_accum_us: Dictionary = {}
static var _floor_frames: int = 0
static var _floor_label: String = ""

static func begin(tag: String) -> void:
	_starts[tag] = Time.get_ticks_usec()

static func end(tag: String) -> void:
	var s: Variant = _starts.get(tag, null)
	if s == null:
		return
	var dt: int = Time.get_ticks_usec() - int(s)
	_accum_us[tag] = int(_accum_us.get(tag, 0)) + dt
	_calls[tag] = int(_calls.get(tag, 0)) + 1
	_floor_accum_us[tag] = int(_floor_accum_us.get(tag, 0)) + dt

# Called once per frame after all begin/end pairs are settled. Rolls the
# window if the threshold is crossed and returns true to signal the
# caller may refresh the HUD / emit a perf log line.
static func tick_frame() -> bool:
	_frames_in_window += 1
	_floor_frames += 1
	if _frames_in_window < WINDOW_FRAMES:
		return false
	var snap: Dictionary = {}
	for tag in ALL_TAGS:
		var total: int = int(_accum_us.get(tag, 0))
		snap[tag] = float(total) / float(_frames_in_window)
	_last_snapshot = snap
	_last_frame_ms = float(snap.get(TAG_FRAME, 0.0)) / 1000.0
	_last_fps = float(Engine.get_frames_per_second())
	_accum_us.clear()
	_calls.clear()
	_frames_in_window = 0
	return true

static func snapshot() -> Dictionary:
	return _last_snapshot

static func frame_ms() -> float:
	return _last_frame_ms

static func format_hud_lines() -> Array:
	var s: Dictionary = _last_snapshot
	if s.is_empty():
		return ["perf: warming up"]
	var out: Array = []
	out.append("frame: %.2fms" % _last_frame_ms)
	out.append("fog %dus  light %dus  flick %dus" % [
		int(s.get(TAG_FOG, 0)), int(s.get(TAG_LIGHTS, 0)), int(s.get(TAG_FLICKER, 0)),
	])
	out.append("render %dus  ai %dus" % [
		int(s.get(TAG_RENDER_FADE, 0)), int(s.get(TAG_AI, 0)),
	])
	return out

static func format_log_suffix() -> String:
	var s: Dictionary = _last_snapshot
	if s.is_empty():
		return ""
	var draws: int = int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var objs: int = int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))
	var nodes: int = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	return "frame_ms=%.2f fps=%.0f draws=%d objs=%d nodes=%d fog_us=%d lights_us=%d flicker_us=%d render_us=%d ai_us=%d" % [
		_last_frame_ms, _last_fps, draws, objs, nodes,
		int(s.get(TAG_FOG, 0)), int(s.get(TAG_LIGHTS, 0)), int(s.get(TAG_FLICKER, 0)),
		int(s.get(TAG_RENDER_FADE, 0)), int(s.get(TAG_AI, 0)),
	]

# Per-floor accounting — Dungeon calls floor_begin on _build_floor and
# floor_end on _descend. Emits a [perf-floor] line so /benchmark can
# attribute cost to specific biome+vault combinations.
static func floor_begin(label: String) -> void:
	_floor_accum_us.clear()
	_floor_frames = 0
	_floor_label = label

static func floor_end_summary() -> String:
	if _floor_frames <= 0:
		return ""
	var parts: Array = ["label=%s" % _floor_label, "frames=%d" % _floor_frames]
	for tag in ALL_TAGS:
		var total: int = int(_floor_accum_us.get(tag, 0))
		var avg: float = float(total) / float(_floor_frames)
		parts.append("%s_us=%d" % [tag, int(avg)])
	return " ".join(parts)
