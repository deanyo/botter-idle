extends Control

# Credits screen — renders CREDITS.md and NOTICE.md side-by-side in two
# scrollable RichTextLabel panels. Pre-public-launch attribution surface
# per the audit's "DCSS Legal" finding; the markdown sources are the
# authoritative attribution and this screen just makes them visible
# in-game.
#
# Reachable from main menu → "Credits" button. No state, no save reads —
# pure read-only view.

signal back_pressed

const _CREDITS_PATH := "res://data/credits.txt"
const _NOTICE_PATH := "res://data/notice.txt"

func _ready() -> void:
	_build_chrome()
	_build_panels()

func _build_chrome() -> void:
	var view := get_viewport().get_visible_rect().size
	var bg := ColorRect.new()
	bg.color = UITheme.BG_DEEP
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	add_child(bg)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 12)
	bar.position = Vector2(16, 12)
	bar.size = Vector2(view.x - 32, 32)
	add_child(bar)
	var title := Label.new()
	title.text = "CREDITS"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", UITheme.COL_AMBER)
	bar.add_child(title)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(spacer)
	var back_btn := Button.new()
	back_btn.text = "← Back"
	back_btn.pressed.connect(func(): back_pressed.emit())
	bar.add_child(back_btn)
	UITheme.style_button(back_btn)

func _build_panels() -> void:
	var view := get_viewport().get_visible_rect().size
	var pad := 16
	var top := 56
	var w := int((view.x - pad * 3) / 2)
	var h := int(view.y - top - pad)
	_make_panel("Game Credits", _CREDITS_PATH, pad, top, w, h)
	_make_panel("Third-Party Notices", _NOTICE_PATH, pad * 2 + w, top, w, h)

func _make_panel(heading: String, src_path: String, x: int, y: int, w: int, h: int) -> void:
	var panel := PanelContainer.new()
	panel.position = Vector2(x, y)
	panel.size = Vector2(w, h)
	add_child(panel)
	var sb := StyleBoxFlat.new()
	sb.bg_color = UITheme.BG_PANEL
	sb.border_color = UITheme.BORDER_DIM
	sb.set_border_width_all(1)
	panel.add_theme_stylebox_override("panel", sb)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	panel.add_child(v)
	var header := Label.new()
	header.text = heading
	header.add_theme_font_size_override("font_size", 16)
	header.add_theme_color_override("font_color", UITheme.COL_AMBER)
	v.add_child(header)
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = false
	rt.scroll_active = true
	rt.fit_content = false
	rt.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rt.add_theme_color_override("default_color", UITheme.COL_DIM)
	rt.text = _load_text(src_path)
	v.add_child(rt)

func _load_text(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return "(failed to load %s)" % path
	return f.get_as_text()
