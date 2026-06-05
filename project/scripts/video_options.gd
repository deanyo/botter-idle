extends Control

signal back_pressed

const VS := preload("res://scripts/video_settings.gd")

@onready var mode_opt: OptionButton = $V/Form/ModeRow/Mode
@onready var res_opt: OptionButton = $V/Form/ResRow/Resolution
@onready var vsync_opt: OptionButton = $V/Form/VsyncRow/Vsync
@onready var back_btn: Button = $V/Buttons/Back

# Dynamically-added graphics-effect toggles (built in _ready). Stored
# here so _on_changed can read their state.
var _gfx_checks: Dictionary = {}  # effect_name → CheckBox
# HUD-layout toggles built dynamically alongside the gfx checks.
var _hud_log_overlay_cb: CheckBox = null

# Friendly labels for each effect ID.
const _GFX_LABELS := {
	"color_grade":      "Per-biome color grading",
	"heat_haze":        "Heat haze on lava",
	"water_shimmer":    "Water shimmer",
	"memory_desat":     "Memory desaturation",
	"threat_outlines":  "Enemy threat outlines",
	"light_cookies":    "Light cookies (patterns)",
	"ench":             "Status overlays (fire/poison/etc)",
	"shadow":           "Actor shadows",
	"bloom":            "Bloom",
}

var settings: Dictionary = {}
var ready_done: bool = false

func _ready() -> void:
	settings = VS.load_settings()
	_populate_modes()
	_populate_resolutions()
	_populate_vsync()
	_populate_graphics()
	mode_opt.item_selected.connect(_on_changed)
	res_opt.item_selected.connect(_on_changed)
	vsync_opt.item_selected.connect(_on_changed)
	back_btn.pressed.connect(func(): back_pressed.emit())
	UITheme.style_all_buttons(self)
	ready_done = true

func _populate_graphics() -> void:
	# Append a "Graphics" header + one CheckBox per effect at the end of
	# the form. Done programmatically so the existing .tscn doesn't need
	# rewriting every time a new effect lands.
	var form: Node = $V/Form
	if form == null:
		return
	var header := Label.new()
	header.text = "Graphics effects"
	header.add_theme_color_override("font_color", Color(0.92, 0.78, 0.45, 1))
	header.add_theme_font_size_override("font_size", 18)
	form.add_child(header)
	var hint := Label.new()
	hint.text = "Toggle individual visual effects. Disabling reduces GPU cost."
	hint.add_theme_color_override("font_color", Color(0.6, 0.55, 0.4, 1))
	hint.add_theme_font_size_override("font_size", 13)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	form.add_child(hint)
	# Preset row — 3 buttons that batch-set every gfx toggle to a known
	# Low/Medium/High mix. Sits at the top of the graphics block so the
	# user can pick a baseline without flipping 9 individual checkboxes.
	# 2026-06-04.
	var preset_row := HBoxContainer.new()
	preset_row.add_theme_constant_override("separation", 8)
	for pair in [["Low", "low", VS.GFX_PRESET_LOW],
				 ["Medium", "medium", VS.GFX_PRESET_MEDIUM],
				 ["High", "high", VS.GFX_PRESET_HIGH]]:
		var btn := Button.new()
		btn.text = String(pair[0])
		btn.add_theme_font_size_override("font_size", 13)
		var name_id: String = String(pair[1])
		var preset: Dictionary = pair[2]
		btn.pressed.connect(func(): _apply_preset(name_id, preset))
		preset_row.add_child(btn)
		UITheme.style_button(btn)
	form.add_child(preset_row)
	var gfx: Dictionary = settings.get("gfx", {})
	for eff in VS.GFX_EFFECTS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var label := Label.new()
		label.text = String(_GFX_LABELS.get(eff, eff))
		label.custom_minimum_size = Vector2(220, 0)
		row.add_child(label)
		var cb := CheckBox.new()
		cb.button_pressed = bool(gfx.get(eff, true))
		cb.toggled.connect(func(_v): _on_changed())
		_gfx_checks[eff] = cb
		row.add_child(cb)
		form.add_child(row)
	# HUD layout section. Currently a single toggle for the loot/combat
	# log overlay (off → bag fills bottom strip, log hidden). Sits under
	# graphics so the user finds it next to the other "screen layout"
	# toggles. UI polish 2026-06-04.
	var hud_header := Label.new()
	hud_header.text = "HUD"
	hud_header.add_theme_color_override("font_color", Color(0.92, 0.78, 0.45, 1))
	hud_header.add_theme_font_size_override("font_size", 18)
	form.add_child(hud_header)
	var hud_row := HBoxContainer.new()
	hud_row.add_theme_constant_override("separation", 12)
	var hud_lbl := Label.new()
	hud_lbl.text = "Loot/combat log overlay"
	hud_lbl.custom_minimum_size = Vector2(220, 0)
	hud_row.add_child(hud_lbl)
	_hud_log_overlay_cb = CheckBox.new()
	_hud_log_overlay_cb.button_pressed = bool(settings.get("hud_log_overlay", true))
	_hud_log_overlay_cb.toggled.connect(func(_v): _on_changed())
	hud_row.add_child(_hud_log_overlay_cb)
	form.add_child(hud_row)

func _populate_modes() -> void:
	mode_opt.clear()
	var modes: Array = [VS.MODE_WINDOWED, VS.MODE_BORDERLESS, VS.MODE_FULLSCREEN]
	var labels: Array = ["Windowed", "Borderless", "Fullscreen"]
	for i in modes.size():
		mode_opt.add_item(labels[i])
		mode_opt.set_item_metadata(i, modes[i])
	var current: String = String(settings.get("mode", VS.MODE_WINDOWED))
	for i in modes.size():
		if modes[i] == current:
			mode_opt.select(i)
			break

func _populate_resolutions() -> void:
	res_opt.clear()
	for i in VS.PRESETS.size():
		var p: Dictionary = VS.PRESETS[i]
		res_opt.add_item(String(p.label))
		res_opt.set_item_metadata(i, String(p.value))
	var current: String = String(settings.get("resolution", "native"))
	for i in VS.PRESETS.size():
		if String(VS.PRESETS[i].value) == current:
			res_opt.select(i)
			break

func _populate_vsync() -> void:
	vsync_opt.clear()
	vsync_opt.add_item("On")
	vsync_opt.set_item_metadata(0, true)
	vsync_opt.add_item("Off")
	vsync_opt.set_item_metadata(1, false)
	vsync_opt.select(0 if bool(settings.get("vsync", true)) else 1)

# Apply a Low/Medium/High preset — flips each gfx checkbox to match
# the preset's truth-table, then triggers a normal save. Keeps gfx_quality
# tagged with the preset name (Low/Medium/High) until the user touches a
# checkbox, after which _on_changed re-tags it as "custom". 2026-06-04.
func _apply_preset(name_id: String, preset: Dictionary) -> void:
	for eff in _gfx_checks.keys():
		var cb: CheckBox = _gfx_checks[eff]
		if preset.has(eff):
			cb.button_pressed = bool(preset[eff])
	var gfx: Dictionary = settings.get("gfx", {})
	for eff in preset.keys():
		gfx[eff] = bool(preset[eff])
	settings["gfx"] = gfx
	settings["gfx_quality"] = name_id
	if _hud_log_overlay_cb != null:
		settings["hud_log_overlay"] = _hud_log_overlay_cb.button_pressed
	VS.save_settings(settings)
	VS.apply(settings)

func _on_changed(_idx: int = 0) -> void:
	if not ready_done:
		return
	settings["mode"] = String(mode_opt.get_item_metadata(mode_opt.selected))
	settings["resolution"] = String(res_opt.get_item_metadata(res_opt.selected))
	settings["vsync"] = bool(vsync_opt.get_item_metadata(vsync_opt.selected))
	# Read graphics-effect checkboxes.
	var gfx: Dictionary = settings.get("gfx", {})
	for eff in _gfx_checks.keys():
		var cb: CheckBox = _gfx_checks[eff]
		gfx[eff] = cb.button_pressed
	settings["gfx"] = gfx
	if _hud_log_overlay_cb != null:
		settings["hud_log_overlay"] = _hud_log_overlay_cb.button_pressed
	# Mark quality preset as "custom" once user touches anything (so
	# next preset selection cleanly overrides).
	settings["gfx_quality"] = "custom"
	VS.save_settings(settings)
	VS.apply(settings)
	# Note: gfx changes apply on the next floor build (shader uniforms
	# and effect attachment happen at scene init), not retroactively to
	# the currently-rendered floor. Acceptable UX — the change is visible
	# the next time the bot descends or a new run starts.
