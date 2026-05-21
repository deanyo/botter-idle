# Video settings persistence + apply.
# Stored at user://video_settings.json. Applied at startup (main.gd _ready)
# so the user's chosen window mode / resolution / vsync are remembered
# across launches.
class_name VideoSettings
extends RefCounted

const SAVE_PATH := "user://video_settings.json"

# Window modes — names match the dropdown order in the options screen.
const MODE_WINDOWED := "windowed"
const MODE_BORDERLESS := "borderless"
const MODE_FULLSCREEN := "fullscreen"

# Resolution presets. "native" means "use the screen's current size",
# resolved at apply-time.
const PRESETS: Array = [
	{"label": "Native", "value": "native"},
	{"label": "1280×720", "value": "1280x720"},
	{"label": "1600×900", "value": "1600x900"},
	{"label": "1920×1080", "value": "1920x1080"},
	{"label": "2560×1440", "value": "2560x1440"},
	{"label": "3840×2160", "value": "3840x2160"},
]

# Graphics-effect toggles. Each effect can be turned off independently.
# Quality presets ("high"/"medium"/"low") pick defaults; users can override
# individual toggles after that.
#
# Subsystems read these via VideoSettings.is_effect_enabled(name). Env-var
# overrides (BOTTER_NO_<EFFECT>=1) take precedence for dev A/B testing.
const GFX_EFFECTS := [
	"color_grade", "heat_haze", "water_shimmer", "memory_desat",
	"threat_outlines", "light_cookies", "bloom",
]

# Quality presets. Each lists which effects are on by default.
const GFX_PRESET_HIGH := {
	"color_grade": true, "heat_haze": true, "water_shimmer": true,
	"memory_desat": true, "threat_outlines": true, "light_cookies": true,
	"bloom": true,
}
const GFX_PRESET_MEDIUM := {
	"color_grade": true, "heat_haze": true, "water_shimmer": true,
	"memory_desat": true, "threat_outlines": true, "light_cookies": false,
	"bloom": true,
}
const GFX_PRESET_LOW := {
	"color_grade": false, "heat_haze": false, "water_shimmer": false,
	"memory_desat": false, "threat_outlines": false, "light_cookies": false,
	"bloom": false,
}

static func defaults() -> Dictionary:
	var gfx: Dictionary = GFX_PRESET_HIGH.duplicate()
	return {
		"mode": MODE_WINDOWED,
		"resolution": "native",
		"vsync": true,
		"gfx_quality": "high",  # high | medium | low | custom
		"gfx": gfx,
	}

# Read a single effect toggle. Env-var override always wins so dev A/B
# testing still works after this lands.
static func is_effect_enabled(effect: String) -> bool:
	# Env override: BOTTER_NO_HEAT_HAZE=1 disables, BOTTER_FORCE_HEAT_HAZE=1 enables.
	var upper: String = effect.to_upper()
	if OS.has_environment("BOTTER_NO_" + upper):
		return false
	if OS.has_environment("BOTTER_FORCE_" + upper):
		return true
	# Otherwise read from saved settings.
	var d: Dictionary = load_settings()
	var gfx: Dictionary = d.get("gfx", {})
	return bool(gfx.get(effect, true))

static func load_settings() -> Dictionary:
	var d: Dictionary = defaults()
	if not FileAccess.file_exists(SAVE_PATH):
		return d
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return d
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return d
	for k in d.keys():
		if parsed.has(k):
			d[k] = parsed[k]
	# Forward-compat: merge missing gfx toggles into older saves so
	# new effects get their default enabled-state without overwriting
	# existing user choices.
	var gfx_defaults: Dictionary = defaults()["gfx"]
	if not d.has("gfx") or typeof(d["gfx"]) != TYPE_DICTIONARY:
		d["gfx"] = gfx_defaults.duplicate()
	else:
		for k in gfx_defaults.keys():
			if not d["gfx"].has(k):
				d["gfx"][k] = gfx_defaults[k]
	return d

static func save_settings(d: Dictionary) -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(d, "  "))

# Apply via DisplayServer — talks to the OS window directly, which is more
# reliable than poking SceneTree.root properties (which can no-op when the
# editor's "Embed Game" is enabled, and have ordering quirks for fullscreen
# transitions). Returns true if the apply landed on an OS window.
static func apply(d: Dictionary) -> bool:
	# vsync is independent of window mode and always works, even when embedded.
	var vsync: bool = bool(d.get("vsync", true))
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED
	)
	var mode_str: String = String(d.get("mode", MODE_WINDOWED))
	var size: Vector2i = _resolve_size(String(d.get("resolution", "native")))
	var screen: int = DisplayServer.window_get_current_screen()
	match mode_str:
		MODE_FULLSCREEN:
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		MODE_BORDERLESS:
			# Borderless windowed: drop fullscreen, set borderless flag, size to screen.
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
			var screen_size: Vector2i = DisplayServer.screen_get_size(screen)
			DisplayServer.window_set_size(screen_size)
			DisplayServer.window_set_position(DisplayServer.screen_get_position(screen))
		_:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
			if size.x > 0 and size.y > 0:
				DisplayServer.window_set_size(size)
				_center_window(size, screen)
	return true

static func _resolve_size(resolution: String) -> Vector2i:
	if resolution == "native" or resolution == "":
		var screen: int = DisplayServer.window_get_current_screen()
		return DisplayServer.screen_get_size(screen)
	var parts: PackedStringArray = resolution.split("x")
	if parts.size() != 2:
		return Vector2i.ZERO
	return Vector2i(int(parts[0]), int(parts[1]))

static func _center_window(size: Vector2i, screen: int) -> void:
	var screen_pos: Vector2i = DisplayServer.screen_get_position(screen)
	var screen_size: Vector2i = DisplayServer.screen_get_size(screen)
	DisplayServer.window_set_position(screen_pos + (screen_size - size) / 2)
