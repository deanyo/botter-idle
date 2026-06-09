extends Control

# Main menu — two-column splash. Left: saved-bot vignette (sprite + a few
# stat lines pulled from SaveState). Right: title + subtitle + button column.
# Built in code so it stays palette-aligned with the HUD/Outpost.

signal play_pressed
signal video_options_pressed
signal fx_tuner_pressed
signal paperdoll_audit_pressed
signal spell_showcase_pressed
signal item_generator_pressed
signal create_character_pressed

# Colors mirror UITheme — see hud_chrome.gd note for why these are inline.
const COL_AMBER := Color(0.92, 0.78, 0.45)
const COL_DIM := Color(0.7, 0.6, 0.4)
const COL_GOLD := Color(1.0, 0.85, 0.3)
const COL_PANEL := Color(0.0, 0.0, 0.0, 1.0)  # pure-black, OLED — UI pass 2026-06-04
const COL_PANEL_BORDER := Color(0.35, 0.3, 0.18, 0.65)
const COL_BG := Color(0.0, 0.0, 0.0, 1.0)

const ITEMS_PATH := "res://data/items.json"
const PAPERDOLL_BASE_PX := 32

func _ready() -> void:
	_build_layout()

# Set by main.gd before _ready. When non-empty, the menu shows a "While
# you were away" banner with the offline-progress numbers.
var offline_summary: Dictionary = {}

func _build_layout() -> void:
	var view := get_viewport().get_visible_rect().size
	var bg := ColorRect.new()
	bg.color = COL_BG
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	add_child(bg)
	var split_x: int = int(view.x * 0.45)
	_build_vignette(0, 0, split_x, int(view.y))
	_build_buttons(split_x, 0, int(view.x) - split_x, int(view.y))
	if not offline_summary.is_empty():
		_show_offline_banner(offline_summary)
	# Theme any buttons we missed (bot picker cards, delete buttons,
	# anything spawned outside _make_button). UI polish 2026-06-04.
	UITheme.style_all_buttons(self)

func _show_offline_banner(s: Dictionary) -> void:
	var dlg := AcceptDialog.new()
	dlg.title = "While you were away"
	var minutes: int = int(s.get("seconds", 0)) / 60
	var floors: int = int(s.get("floors", 0))
	var loot: int = int(s.get("loot_count", 0))
	var gold: int = int(s.get("gold", 0))
	var branch: String = String(s.get("branch", "the dungeon"))
	dlg.dialog_text = "Your bot kept exploring %s for %d minutes.\n\n• Cleared %d floor%s\n• Picked up %d item%s\n• Earned %d gold" % [
		branch, minutes,
		floors, "" if floors == 1 else "s",
		loot, "" if loot == 1 else "s",
		gold,
	]
	add_child(dlg)
	dlg.popup_centered(Vector2i(420, 200))

func _build_vignette(x: int, y: int, w: int, h: int) -> void:
	var pad := 48
	# Sprite frame fills most of the column.
	var frame_w: int = w - pad * 2
	var frame_h: int = int(h * 0.62)
	var frame_x: int = x + pad
	var frame_y: int = y + int(h * 0.12)
	var frame_bg := ColorRect.new()
	frame_bg.color = COL_PANEL
	frame_bg.position = Vector2(frame_x, frame_y)
	frame_bg.size = Vector2(frame_w, frame_h)
	add_child(frame_bg)
	var border := ReferenceRect.new()
	border.position = Vector2(frame_x, frame_y)
	border.size = Vector2(frame_w, frame_h)
	border.border_color = COL_PANEL_BORDER
	border.border_width = 2.0
	border.editor_only = false
	add_child(border)
	# Layered bot rig — same renderer the in-game bot uses.
	var state: Dictionary = SaveState.load_state()
	var items_db: Dictionary = _load_items()
	var fit: float = float(mini(frame_w, frame_h)) / float(PAPERDOLL_BASE_PX)
	var rig_scale: float = floor(fit) if fit >= 1.0 else fit
	rig_scale = max(rig_scale, 1.0)
	var holder := Node2D.new()
	holder.position = Vector2(frame_x + frame_w / 2.0, frame_y + frame_h / 2.0)
	holder.scale = Vector2(rig_scale, rig_scale)
	add_child(holder)
	var built: Dictionary = PaperdollRenderer.build_rig(items_db, state.equipped, String(state.get("species", "")))
	holder.add_child(built.rig)
	# Stat strip beneath the frame. Main menu shows only the durable
	# progression numbers (level, floor reached, runs, gold) — combat
	# stats live in the outpost / in-game HUD where the player is
	# actually preparing for or running a deploy. UI cleanup 2026-06-06.
	var strip_y: int = frame_y + frame_h + 18
	var name_lbl := _label("Adventurer", x + pad, strip_y, UITheme.FS_HEADER, COL_AMBER)
	name_lbl.size = Vector2(frame_w, 24)
	name_lbl.clip_text = true
	strip_y += 28
	var meta_line := "Lv %d  ·  Floor %d reached  ·  %d runs  ·  %d gold" % [
		int(state.level), int(state.highest_floor),
		int(state.get("runs_completed", 0)), int(state.gold),
	]
	var meta_lbl := _label(meta_line, x + pad, strip_y, UITheme.FS_BODY, COL_DIM)
	meta_lbl.size = Vector2(frame_w, 20)
	meta_lbl.clip_text = true
	strip_y += 32
	# Multi-character picker. Lists all bots; click any non-active one
	# to switch to it. Scrollable so 10+ bots stay usable.
	var bots: Array = SaveState.list_characters()
	if bots.size() >= 1:
		var hdr := _label("Bots (%d)" % bots.size(), x + pad, strip_y, 13, COL_DIM)
		hdr.size = Vector2(frame_w, 18)
		strip_y += 22
		_build_bot_picker(x + pad, strip_y, frame_w, 110, bots)

# Horizontal scrollable bot picker. Each bot is a card showing its
# species sprite + level + species name. Active bot is highlighted;
# others are clickable to switch (re-instantiates the menu so the
# vignette updates). A small ✕ in the corner deletes a non-active bot.
func _build_bot_picker(x: int, y: int, w: int, h: int, bots: Array) -> void:
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(x, y)
	scroll.size = Vector2(w, h)
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	scroll.add_child(hbox)
	for b in bots:
		hbox.add_child(_make_bot_card(b))

const _BOT_CARD_W := 96
const _BOT_CARD_H := 100

func _make_bot_card(bot: Dictionary) -> Control:
	var sp_id: String = String(bot.get("species", "spriggan"))
	var sp_def: Dictionary = SpeciesData.get_def(sp_id)
	var sp_name: String = String(sp_def.get("name", sp_id.capitalize()))
	var card := Button.new()
	card.flat = true
	card.custom_minimum_size = Vector2(_BOT_CARD_W, _BOT_CARD_H)
	card.tooltip_text = "%s · Lv %d · %d runs" % [sp_name, int(bot.level), int(bot.runs_completed)]
	if not bool(bot.is_active):
		card.pressed.connect(_on_switch_bot.bind(int(bot.idx)))
	# Highlight active.
	var bg := ColorRect.new()
	bg.color = Color(0.92, 0.78, 0.45, 0.20) if bool(bot.is_active) else Color(0, 0, 0, 0.45)
	bg.size = Vector2(_BOT_CARD_W, _BOT_CARD_H)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(bg)
	# Sprite.
	var sprite_path: String = SpeciesData.sprite_path_for(sp_id)
	if ResourceLoader.exists(sprite_path):
		var spr := TextureRect.new()
		spr.texture = load(sprite_path)
		spr.position = Vector2(_BOT_CARD_W / 2 - 24, 8)
		spr.size = Vector2(48, 48)
		spr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		spr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		spr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(spr)
	# Name + level beneath. Cards are 96px wide — species like
	# "Demonspawn" can overflow at font_size 11. clip_text + clipping
	# the card itself catches overflow at both layers.
	card.clip_contents = true
	var name_lbl := Label.new()
	name_lbl.text = sp_name
	name_lbl.position = Vector2(0, 58)
	name_lbl.size = Vector2(_BOT_CARD_W, 16)
	name_lbl.clip_text = true
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.add_theme_font_size_override("font_size", 11)
	name_lbl.add_theme_color_override("font_color", COL_AMBER if bool(bot.is_active) else COL_DIM)
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(name_lbl)
	var lv_lbl := Label.new()
	lv_lbl.text = "Lv %d" % int(bot.level)
	lv_lbl.position = Vector2(0, 76)
	lv_lbl.size = Vector2(_BOT_CARD_W, 16)
	lv_lbl.clip_text = true
	lv_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lv_lbl.add_theme_font_size_override("font_size", 10)
	lv_lbl.add_theme_color_override("font_color", COL_DIM)
	lv_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(lv_lbl)
	# Delete button on non-active cards.
	if not bool(bot.is_active):
		var del := Button.new()
		del.text = "✕"
		del.position = Vector2(_BOT_CARD_W - 20, 0)
		del.size = Vector2(20, 20)
		del.flat = true
		del.add_theme_font_size_override("font_size", 12)
		del.add_theme_color_override("font_color", Color(1, 0.5, 0.5))
		del.tooltip_text = "Delete this bot."
		del.pressed.connect(_on_delete_bot.bind(bot))
		card.add_child(del)
	return card

func _on_switch_bot(idx: int) -> void:
	SaveState.set_active(idx)
	# Easiest refresh — request a re-show of the main menu so the
	# vignette + picker pick up the new active bot. main.gd routes
	# play_pressed → outpost; we need a way to ask main.gd to
	# rebuild this scene. Cheapest approach: force a reload by
	# reloading the same scene.
	get_tree().reload_current_scene()

func _on_delete_bot(bot: Dictionary) -> void:
	var idx: int = int(bot.get("idx", 0))
	var sp_id: String = String(bot.get("species", "spriggan"))
	var sp_name: String = String(SpeciesData.get_def(sp_id).get("name", sp_id.capitalize()))
	var dlg := ConfirmationDialog.new()
	dlg.title = "Delete bot"
	dlg.dialog_text = "Permanently delete %s · Lv %d  ·  %d runs  ·  %d gold?\n\nThis cannot be undone." % [
		sp_name, int(bot.get("level", 1)),
		int(bot.get("runs_completed", 0)), int(bot.get("gold", 0)),
	]
	add_child(dlg)
	dlg.confirmed.connect(func():
		SaveState.delete_character(idx)
		get_tree().reload_current_scene()
	)
	dlg.popup_centered(Vector2i(420, 180))

func _build_buttons(x: int, y: int, w: int, h: int) -> void:
	var pad := 64
	var col_w: int = mini(380, w - pad * 2)
	var col_x: int = x + (w - col_w) / 2
	# Title.
	var title := _label("BOTTER", col_x, y + int(h * 0.20), 64, COL_AMBER)
	title.size = Vector2(col_w, 72)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Subtitle.
	var sub := _label("Idle dungeon-crawler. Configure. Deploy. Watch.",
		col_x, y + int(h * 0.20) + 76, 16, COL_DIM)
	sub.size = Vector2(col_w, 22)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Button column.
	var by: int = y + int(h * 0.42)
	var btn_h := 56
	var gap := 12
	_make_button("PLAY", col_x, by, col_w, btn_h, 24, false, _on_play); by += btn_h + gap
	_make_button("Create Character", col_x, by, col_w, 44, 16, false, _on_create_character); by += 44 + gap
	_make_button("Video Options", col_x, by, col_w, 44, 16, false, _on_options); by += 44 + gap
	# Dev-only authoring tools — hidden in release builds. Set
	# BOTTER_DEV=1 to surface them in a release export.
	if OS.is_debug_build() or OS.has_environment("BOTTER_DEV"):
		_make_button("FX Tuner", col_x, by, col_w, 44, 16, false, _on_fx_tuner); by += 44 + gap
		_make_button("Paperdoll Audit", col_x, by, col_w, 44, 16, false, _on_paperdoll_audit); by += 44 + gap
		_make_button("Spell Showcase", col_x, by, col_w, 44, 16, false, _on_spell_showcase); by += 44 + gap
		_make_button("Item Generator", col_x, by, col_w, 44, 16, false, _on_item_generator); by += 44 + gap
	_make_button("Reset Save", col_x, by, col_w, 44, 16, false, _on_reset); by += 44 + gap
	_make_button("Quit", col_x, by, col_w, 44, 16, false, _on_quit)

func _make_button(txt: String, x: int, y: int, w: int, h: int, font_size: int, disabled: bool, cb: Callable) -> Button:
	var b := Button.new()
	b.text = txt
	b.position = Vector2(x, y)
	b.size = Vector2(w, h)
	b.add_theme_font_size_override("font_size", font_size)
	b.disabled = disabled
	if not disabled and cb.is_valid():
		b.pressed.connect(cb)
	add_child(b)
	UITheme.style_button(b)
	return b

func _label(t: String, x: int, y: int, size: int, color: Color) -> Label:
	var lbl := Label.new()
	lbl.text = t
	lbl.position = Vector2(x, y)
	lbl.add_theme_font_size_override("font_size", size)
	lbl.add_theme_color_override("font_color", color)
	add_child(lbl)
	return lbl

func _on_play() -> void:
	play_pressed.emit()

func _on_options() -> void:
	video_options_pressed.emit()

func _on_fx_tuner() -> void:
	fx_tuner_pressed.emit()

func _on_paperdoll_audit() -> void:
	paperdoll_audit_pressed.emit()

func _on_spell_showcase() -> void:
	spell_showcase_pressed.emit()

func _on_item_generator() -> void:
	item_generator_pressed.emit()

func _on_create_character() -> void:
	create_character_pressed.emit()

func _on_quit() -> void:
	get_tree().quit()

# ============================================================================
# Reset save — confirm dialog requires the user to type "reset" exactly.
# ============================================================================

func _on_reset() -> void:
	var dlg := ConfirmationDialog.new()
	dlg.title = "Reset save"
	dlg.dialog_text = "This will wipe your current bot, gear, and progress. Type reset below to confirm. This cannot be undone."
	dlg.get_ok_button().disabled = true
	dlg.get_ok_button().text = "Reset"
	var input := LineEdit.new()
	input.placeholder_text = "type \"reset\" to confirm"
	input.size = Vector2(280, 28)
	input.custom_minimum_size = Vector2(280, 28)
	# Sized after add_child so the dialog has a vbox to put it in.
	dlg.add_child(input)
	input.text_changed.connect(func(t: String):
		dlg.get_ok_button().disabled = (t.strip_edges().to_lower() != "reset")
	)
	dlg.confirmed.connect(func():
		_perform_reset()
		dlg.queue_free()
	)
	dlg.canceled.connect(func(): dlg.queue_free())
	add_child(dlg)
	dlg.popup_centered(Vector2i(440, 200))
	input.grab_focus()

func _perform_reset() -> void:
	var path := "user://botter_save.json"
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	# Re-render so the vignette reflects the wiped save.
	for c in get_children():
		c.queue_free()
	_build_layout()

func _load_items() -> Dictionary:
	var f := FileAccess.open(ITEMS_PATH, FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	var by_id: Dictionary = {}
	for it in parsed.get("items", []):
		by_id[it.id] = it
	return by_id

