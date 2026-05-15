extends Control

# Main menu — two-column splash. Left: saved-bot vignette (sprite + a few
# stat lines pulled from SaveState). Right: title + subtitle + button column.
# Built in code so it stays palette-aligned with the HUD/Outpost.

signal play_pressed
signal video_options_pressed

# Colors mirror UITheme — see hud_chrome.gd note for why these are inline.
const COL_AMBER := Color(0.92, 0.78, 0.45)
const COL_DIM := Color(0.7, 0.6, 0.4)
const COL_GOLD := Color(1.0, 0.85, 0.3)
const COL_PANEL := Color(0.04, 0.04, 0.06, 0.85)
const COL_PANEL_BORDER := Color(0.35, 0.3, 0.18, 0.65)
const COL_BG := Color(0.05, 0.05, 0.07, 1.0)

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
	var built: Dictionary = PaperdollRenderer.build_rig(items_db, state.equipped)
	holder.add_child(built.rig)
	# Stat strip beneath the frame.
	var strip_y: int = frame_y + frame_h + 18
	var name_lbl := _label("Bot the Adventurer", x + pad, strip_y, 22, COL_AMBER); name_lbl.size = Vector2(frame_w, 28)
	strip_y += 32
	var meta_line := "Lv %d  ·  Floor %d reached  ·  %d runs  ·  %d gold" % [
		int(state.level), int(state.highest_floor),
		int(state.get("runs_completed", 0)), int(state.gold),
	]
	var meta_lbl := _label(meta_line, x + pad, strip_y, 14, COL_DIM); meta_lbl.size = Vector2(frame_w, 20)
	strip_y += 28
	# Computed combat stats (mirrors Outpost / Bot.recompute_stats so the
	# same numbers show on launch as on deploy).
	var derived: Dictionary = _derive_stats(state, items_db)
	var combat_line := "HP %d  ATK %d  DEF %d  Crit %d%%  Haste %d%%  Regen %d/s" % [
		int(derived.hp), int(derived.atk), int(derived.def),
		int(derived.crit), int(derived.haste), int(derived.regen),
	]
	var combat_lbl := _label(combat_line, x + pad, strip_y, 13, COL_AMBER); combat_lbl.size = Vector2(frame_w, 20)

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
	_make_button("Create Character (soon)", col_x, by, col_w, 44, 16, true, Callable()); by += 44 + gap
	_make_button("Video Options", col_x, by, col_w, 44, 16, false, _on_options); by += 44 + gap
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

# Mirrors Bot.recompute_stats — same base + gear + affix sums and same caps —
# so the menu vignette shows the exact stats the bot will deploy with.
const _DERIVE_SLOTS := ["weapon", "armor", "helm", "boots", "shield"]
func _derive_stats(s: Dictionary, db: Dictionary) -> Dictionary:
	var lv: int = int(s.get("level", 1))
	var hp: int = 50 + (lv - 1) * 8
	var atk: int = 5 + (lv - 1)
	var defense: int = 1 + int(lv / 3.0)
	var crit_sum: float = 0.0
	var haste_sum: float = 0.0
	var regen_sum: float = 0.0
	for slot in _DERIVE_SLOTS:
		var inst: Variant = s.get("equipped", {}).get(slot, null)
		if inst == null or typeof(inst) != TYPE_DICTIONARY:
			continue
		var base_id: String = String(inst.get("base_id", ""))
		if not db.has(base_id):
			continue
		var item: Dictionary = db[base_id]
		hp += int(item.get("hp", 0))
		atk += int(item.get("atk", 0))
		defense += int(item.get("def", 0))
		var sums: Dictionary = AffixSystem.sum_affix_stats(inst.get("affixes", []))
		hp += int(sums.get("hp", 0))
		atk += int(sums.get("atk", 0))
		defense += int(sums.get("def", 0))
		crit_sum += float(sums.get("crit_chance", 0))
		haste_sum += float(sums.get("atk_speed_pct", 0))
		regen_sum += float(sums.get("hp_regen", 0))
	return {
		"hp": hp, "atk": atk, "def": defense,
		"crit": clampf(crit_sum, 0.0, 75.0),
		"haste": clampf(haste_sum, 0.0, 200.0),
		"regen": regen_sum,
	}
