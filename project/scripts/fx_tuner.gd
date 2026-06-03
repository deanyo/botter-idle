extends Control

# Standalone visual-FX tuner. Live paperdoll preview that auto-swings
# every 3s + sliders for glow / hand enchant / trail / item tint
# strength + flavor & effect pickers so the user can isolate what
# they're tuning. Lives outside Video Settings to keep that screen
# focused on window/resolution/vsync/effect-toggles.

signal back_pressed

const VS := preload("res://scripts/video_settings.gd")
const PaperdollRendererCls := preload("res://scripts/paperdoll_renderer.gd")
const WeaponTrailsCls := preload("res://scripts/weapon_trails.gd")
const UIThemeCls := preload("res://scripts/ui_theme.gd")
const ITEMS_PATH := "res://data/items.json"

# Slider rows for continuous tunables.
const _TUNABLE_ROWS := [
	{ "key": "glow_strength",      "label": "Item glow strength",   "min": 0.0, "max": 3.0,  "step": 0.05 },
	{ "key": "glow_pulse_amount",  "label": "Item glow pulse",      "min": 0.0, "max": 1.5,  "step": 0.05 },
	{ "key": "glow_thickness",     "label": "Item glow thickness",  "min": 0.02, "max": 0.30, "step": 0.01 },
	{ "key": "hand_enchant_alpha", "label": "Hand enchant alpha",   "min": 0.0, "max": 0.8,  "step": 0.05 },
	{ "key": "hand_enchant_scale", "label": "Hand enchant scale",   "min": 0.4, "max": 1.8,  "step": 0.05 },
	{ "key": "trail_amount",       "label": "Trail particle amount","min": 0.0, "max": 3.0,  "step": 0.10 },
	{ "key": "trail_lifetime",     "label": "Trail lifetime",       "min": 0.2, "max": 2.5,  "step": 0.05 },
	{ "key": "item_tint_strength", "label": "Item tint strength",   "min": 0.0, "max": 2.0,  "step": 0.05 },
]

const _PREVIEW_EFFECTS := [
	{ "id": "both",   "label": "Both glow + trail" },
	{ "id": "glow",   "label": "Glow only" },
	{ "id": "trail",  "label": "Trail only" },
]
const _PREVIEW_FLAVORS := [
	"vampiric", "fire", "cold", "holy", "poison", "thunderous", "dark", "dragon_bane", "brutal",
]

const COL_AMBER := Color(0.92, 0.78, 0.45)
const COL_DIM := Color(0.6, 0.55, 0.4)

var _settings: Dictionary = {}
var _slider_rows: Dictionary = {}
var _export_status_label: Label = null

# Preview state.
var _preview_holder: Control = null
var _preview_rig: Node2D = null
var _preview_weapon_sprite: Sprite2D = null
var _preview_swing_tween: Tween = null
var _preview_swing_timer: float = 0.0
var _preview_flavor: String = "fire"
var _preview_effect_id: String = "both"
var _items_cache: Dictionary = {}

func _ready() -> void:
	_settings = VS.load_settings()
	_build_ui()
	set_process(true)

func _process(delta: float) -> void:
	_preview_swing_timer -= delta
	if _preview_swing_timer <= 0.0:
		_preview_swing_timer = 3.0
		_trigger_preview_swing()

func _build_ui() -> void:
	# Outer column spans most of the screen and centers a scrollable
	# form. Title at top, Back button at bottom.
	var v := VBoxContainer.new()
	v.anchor_left = 0.5
	v.anchor_right = 0.5
	v.anchor_top = 0.0
	v.anchor_bottom = 1.0
	v.offset_left = -360.0
	v.offset_right = 360.0
	v.offset_top = 24.0
	v.offset_bottom = -24.0
	v.add_theme_constant_override("separation", 12)
	add_child(v)

	var title := Label.new()
	title.text = "FX TUNER"
	title.add_theme_color_override("font_color", COL_AMBER)
	title.add_theme_font_size_override("font_size", 32)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)

	var hint := Label.new()
	hint.text = "Live preview auto-swings every 3s. Pick an effect + flavor, drag sliders. Saves persist; live game reflects changes on next gear refresh."
	hint.add_theme_color_override("font_color", COL_DIM)
	hint.add_theme_font_size_override("font_size", 13)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(hint)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	v.add_child(scroll)

	var form := VBoxContainer.new()
	form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form.add_theme_constant_override("separation", 10)
	scroll.add_child(form)

	_populate_pickers(form)
	_populate_preview(form)
	_populate_tunables(form)

	# Bottom row — Reset Defaults / Export / Back. Export copies the
	# current tunables (and current preview pickers) to the clipboard
	# as JSON so the user can paste their preferred setup back to me
	# for review.
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 12)
	var reset_btn := Button.new()
	reset_btn.text = "Reset to defaults"
	reset_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reset_btn.custom_minimum_size = Vector2(0, 48)
	reset_btn.add_theme_font_size_override("font_size", 16)
	reset_btn.pressed.connect(_reset_to_defaults)
	btn_row.add_child(reset_btn)
	var export_btn := Button.new()
	export_btn.text = "Export to clipboard"
	export_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	export_btn.custom_minimum_size = Vector2(0, 48)
	export_btn.add_theme_font_size_override("font_size", 16)
	export_btn.pressed.connect(_export_settings)
	btn_row.add_child(export_btn)
	var back_btn := Button.new()
	back_btn.text = "Back"
	back_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	back_btn.custom_minimum_size = Vector2(0, 48)
	back_btn.add_theme_font_size_override("font_size", 18)
	back_btn.pressed.connect(func(): back_pressed.emit())
	btn_row.add_child(back_btn)
	v.add_child(btn_row)
	# Export confirmation label — fades back out after a few seconds.
	_export_status_label = Label.new()
	_export_status_label.text = ""
	_export_status_label.add_theme_color_override("font_color", COL_AMBER)
	_export_status_label.add_theme_font_size_override("font_size", 13)
	_export_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_export_status_label)

func _populate_pickers(form: Node) -> void:
	# Effect + flavor picker row.
	var picker_row := HBoxContainer.new()
	picker_row.add_theme_constant_override("separation", 12)
	var eff_lbl := Label.new()
	eff_lbl.text = "Effect:"
	eff_lbl.custom_minimum_size = Vector2(60, 0)
	picker_row.add_child(eff_lbl)
	var eff_opt := OptionButton.new()
	for i in _PREVIEW_EFFECTS.size():
		eff_opt.add_item(String(_PREVIEW_EFFECTS[i].label))
		eff_opt.set_item_metadata(i, String(_PREVIEW_EFFECTS[i].id))
	eff_opt.select(0)
	eff_opt.item_selected.connect(func(idx):
		_preview_effect_id = String(eff_opt.get_item_metadata(idx))
		_rebuild_preview_rig()
	)
	picker_row.add_child(eff_opt)
	var flv_lbl := Label.new()
	flv_lbl.text = "Flavor:"
	flv_lbl.custom_minimum_size = Vector2(60, 0)
	picker_row.add_child(flv_lbl)
	var flv_opt := OptionButton.new()
	for i in _PREVIEW_FLAVORS.size():
		flv_opt.add_item(String(_PREVIEW_FLAVORS[i]).capitalize())
		flv_opt.set_item_metadata(i, String(_PREVIEW_FLAVORS[i]))
	flv_opt.select(1)  # fire — most visually obvious
	_preview_flavor = "fire"
	flv_opt.item_selected.connect(func(idx):
		_preview_flavor = String(flv_opt.get_item_metadata(idx))
		_rebuild_preview_rig()
	)
	picker_row.add_child(flv_opt)
	form.add_child(picker_row)

func _populate_preview(form: Node) -> void:
	var holder := Panel.new()
	holder.custom_minimum_size = Vector2(0, 280)
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	holder.add_theme_stylebox_override("panel", _preview_panel_style())
	form.add_child(holder)
	_preview_holder = holder
	_rebuild_preview_rig()

func _preview_panel_style() -> StyleBoxFlat:
	# Pure black so faint glow alphas read against neutral background
	# instead of the slightly-blue panel that washed them out.
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.0, 0.0, 0.0, 1.0)
	sb.border_color = Color(0.35, 0.30, 0.18, 0.65)
	sb.border_width_left = 1
	sb.border_width_right = 1
	sb.border_width_top = 1
	sb.border_width_bottom = 1
	return sb

func _items_db() -> Dictionary:
	if not _items_cache.is_empty():
		return _items_cache
	var f := FileAccess.open(ITEMS_PATH, FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	for it in parsed.get("items", []):
		_items_cache[it["id"]] = it
	return _items_cache

func _preview_equipped() -> Dictionary:
	var db: Dictionary = _items_db()
	var base_id: String = "demon_blade"
	if not db.has(base_id):
		for k in db.keys():
			var it: Dictionary = db[k]
			if it.get("slot", "") == "weapon" and it.get("rarity", "") == "legendary":
				base_id = String(k)
				break
	# Patch flavor_tags so the live preview renderer uses our flavor.
	if db.has(base_id):
		db[base_id] = db[base_id].duplicate()
		db[base_id]["flavor_tags"] = [_preview_flavor]
	return {
		"weapon": {
			"base_id": base_id,
			"instance_id": "preview_weapon",
			"affixes": [],
		},
	}

func _rebuild_preview_rig() -> void:
	if _preview_holder == null:
		return
	if _preview_rig != null and is_instance_valid(_preview_rig):
		_preview_rig.queue_free()
	_preview_rig = null
	_preview_weapon_sprite = null
	# Save settings before rebuild so the renderer reads the latest.
	VS.save_settings(_settings)
	var built: Dictionary = PaperdollRendererCls.build_rig(_items_db(), _preview_equipped())
	var rig: Node2D = built.get("rig", null)
	if rig == null:
		return
	# Center the rig in the preview panel; size_flags makes the panel
	# expand to the available width, so we use a deferred call to grab
	# the actual width once layout has settled.
	rig.position = Vector2(180, 140)
	rig.scale = Vector2(4.0, 4.0)
	_preview_holder.add_child(rig)
	_preview_rig = rig
	# Nudge to center horizontally once Panel has its real width.
	call_deferred("_recenter_preview_rig")
	var slots: Dictionary = built.get("slots", {})
	_preview_weapon_sprite = slots.get("weapon", null)
	_apply_preview_effect_filter()

func _recenter_preview_rig() -> void:
	if _preview_rig != null and _preview_holder != null and is_instance_valid(_preview_rig):
		_preview_rig.position = Vector2(_preview_holder.size.x * 0.5, 140)

func _apply_preview_effect_filter() -> void:
	if _preview_weapon_sprite == null:
		return
	if _preview_effect_id == "trail":
		# Strip the glow shader so only the trail shows on swing.
		_preview_weapon_sprite.material = null
		# Hide the hand enchant child too.
		for c in _preview_weapon_sprite.get_children():
			if c is Sprite2D:
				c.visible = false

func _trigger_preview_swing() -> void:
	if _preview_weapon_sprite == null or not is_instance_valid(_preview_weapon_sprite):
		return
	if _preview_swing_tween and _preview_swing_tween.is_valid():
		_preview_swing_tween.kill()
	if _preview_effect_id != "glow":
		WeaponTrailsCls.emit_burst(_preview_weapon_sprite, _preview_flavor)
	var w: Sprite2D = _preview_weapon_sprite
	w.rotation = 0.0
	w.scale = Vector2(1, 1)
	w.position = Vector2.ZERO
	_preview_swing_tween = w.create_tween()
	_preview_swing_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_preview_swing_tween.tween_property(w, "rotation", deg_to_rad(35.0), 0.07)
	_preview_swing_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_preview_swing_tween.tween_property(w, "rotation", deg_to_rad(-110.0), 0.10)
	_preview_swing_tween.parallel().tween_property(w, "scale", Vector2(1.35, 1.35), 0.10)
	_preview_swing_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	_preview_swing_tween.tween_property(w, "rotation", 0.0, 0.18)
	_preview_swing_tween.parallel().tween_property(w, "scale", Vector2(1, 1), 0.18)

func _populate_tunables(form: Node) -> void:
	var header := Label.new()
	header.text = "Visual tunables"
	header.add_theme_color_override("font_color", COL_AMBER)
	header.add_theme_font_size_override("font_size", 18)
	form.add_child(header)
	var t: Dictionary = _settings.get("gfx_tunables", {})
	for row_def in _TUNABLE_ROWS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var lbl := Label.new()
		lbl.text = String(row_def.label)
		lbl.custom_minimum_size = Vector2(220, 0)
		row.add_child(lbl)
		var slider := HSlider.new()
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.min_value = float(row_def.min)
		slider.max_value = float(row_def.max)
		slider.step = float(row_def.step)
		var key: String = String(row_def.key)
		slider.value = float(t.get(key, VS.GFX_TUNABLE_DEFAULTS.get(key, 0.0)))
		var value_lbl := Label.new()
		value_lbl.custom_minimum_size = Vector2(60, 0)
		value_lbl.text = "%.2f" % slider.value
		slider.value_changed.connect(func(v):
			value_lbl.text = "%.2f" % v
			_on_tunable_changed(key, v)
		)
		row.add_child(slider)
		row.add_child(value_lbl)
		form.add_child(row)
		_slider_rows[key] = { "slider": slider, "value_label": value_lbl }

func _on_tunable_changed(key: String, value: float) -> void:
	var t: Dictionary = _settings.get("gfx_tunables", {})
	t[key] = value
	_settings["gfx_tunables"] = t
	VS.save_settings(_settings)
	_rebuild_preview_rig()

# Export the current tunables (and the preview pickers) as JSON to the
# clipboard so the user can paste their preferred setup back to me for
# review / merging into defaults. Also written to stdout so it's
# greppable in logs if clipboard access is restricted.
func _export_settings() -> void:
	var payload: Dictionary = {
		"gfx_tunables":   _settings.get("gfx_tunables", {}),
		"preview_flavor": _preview_flavor,
		"preview_effect": _preview_effect_id,
		"timestamp":      Time.get_datetime_string_from_system(),
	}
	var text: String = JSON.stringify(payload, "  ")
	DisplayServer.clipboard_set(text)
	print("[fx_tuner] export:\n", text)
	if _export_status_label != null:
		_export_status_label.text = "Copied %d bytes to clipboard. Paste it back to share your setup." % text.length()
		# Self-clearing after 4s — light helper instead of a Timer node.
		var t := create_tween()
		t.tween_interval(4.0)
		t.tween_callback(func():
			if _export_status_label != null and is_instance_valid(_export_status_label):
				_export_status_label.text = ""
		)

# Restore tunables to the canonical defaults. Useful for "I broke
# everything, start over". Doesn't touch the picker state.
func _reset_to_defaults() -> void:
	_settings["gfx_tunables"] = VS.GFX_TUNABLE_DEFAULTS.duplicate()
	VS.save_settings(_settings)
	# Re-sync slider controls to the new values.
	for key in _slider_rows.keys():
		var row: Dictionary = _slider_rows[key]
		var slider: HSlider = row.slider
		var lbl: Label = row.value_label
		var v: float = float(VS.GFX_TUNABLE_DEFAULTS.get(key, slider.value))
		slider.value = v
		lbl.text = "%.2f" % v
	_rebuild_preview_rig()
	if _export_status_label != null:
		_export_status_label.text = "Reset to defaults."
		var t := create_tween()
		t.tween_interval(2.0)
		t.tween_callback(func():
			if _export_status_label != null and is_instance_valid(_export_status_label):
				_export_status_label.text = ""
		)
