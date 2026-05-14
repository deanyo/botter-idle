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

static func defaults() -> Dictionary:
	return {
		"mode": MODE_WINDOWED,
		"resolution": "native",
		"vsync": true,
	}

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
