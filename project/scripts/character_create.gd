extends Control

# Character creation screen — pick a species. Locked once chosen
# (writes save.species). Reachable from the main-menu "Create
# Character" button. Two-pane layout:
#   Left: scrollable species list with sprite + name + brief stat
#         summary. Click selects.
#   Right: full preview — large sprite, lore text, stat-mod table,
#          Confirm button.

signal back_pressed
signal character_confirmed(species_id: String)

const COL_AMBER := Color(0.92, 0.78, 0.45)
const COL_DIM := Color(0.6, 0.55, 0.4)
const COL_PANEL := Color(0.0, 0.0, 0.0, 0.85)
const COL_PANEL_BORDER := Color(0.35, 0.3, 0.18, 0.65)
const COL_BUFF := Color(0.55, 0.95, 0.55)
const COL_NERF := Color(1.00, 0.50, 0.40)
const COL_NEUTRAL := Color(0.85, 0.85, 0.85)

const SPECIES_SPRITE_DIR := "res://assets/tiles/player/species/"

var selected_id: String = ""
var list_root: VBoxContainer = null
var preview_sprite: TextureRect = null
var preview_name: Label = null
var preview_lore: Label = null
var preview_stats: VBoxContainer = null

func _ready() -> void:
	var view := get_viewport().get_visible_rect().size
	# Title
	var title := Label.new()
	title.text = "CREATE CHARACTER"
	title.position = Vector2(0, 16)
	title.size = Vector2(view.x, 40)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", COL_AMBER)
	add_child(title)
	# Back button
	var back := Button.new()
	back.text = "← Back"
	back.position = Vector2(20, 20)
	back.size = Vector2(100, 32)
	back.pressed.connect(func(): back_pressed.emit())
	add_child(back)
	# Layout
	var top_y: int = 70
	var bottom_y: int = int(view.y) - 80
	var pane_h: int = bottom_y - top_y
	var left_w: int = int(view.x * 0.45)
	var right_w: int = int(view.x) - left_w - 32
	_build_list_pane(16, top_y, left_w, pane_h)
	_build_preview_pane(left_w + 32, top_y, right_w, pane_h)
	# Confirm row
	var confirm := Button.new()
	confirm.text = "CONFIRM"
	confirm.position = Vector2(int(view.x) / 2 - 100, int(view.y) - 64)
	confirm.size = Vector2(200, 48)
	confirm.add_theme_font_size_override("font_size", 18)
	confirm.pressed.connect(_on_confirm)
	add_child(confirm)
	# Default selection.
	var species: Array = SpeciesData.all()
	if not species.is_empty():
		_select(String(species[0].id))

func _build_list_pane(x: int, y: int, w: int, h: int) -> void:
	_panel(x, y, w, h, "Species")
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(x + 12, y + 36)
	scroll.size = Vector2(w - 24, h - 48)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	list_root = VBoxContainer.new()
	list_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_root.add_theme_constant_override("separation", 4)
	scroll.add_child(list_root)
	for sp in SpeciesData.all():
		list_root.add_child(_make_list_row(sp))

func _make_list_row(sp: Dictionary) -> Control:
	var btn := Button.new()
	btn.flat = true
	btn.custom_minimum_size = Vector2(0, 64)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.pressed.connect(func(): _select(String(sp.id)))
	# Sprite on left
	var sprite_path: String = SpeciesData.sprite_path_for(String(sp.id))
	if ResourceLoader.exists(sprite_path):
		var spr := TextureRect.new()
		spr.texture = load(sprite_path)
		spr.position = Vector2(8, 8)
		spr.size = Vector2(48, 48)
		spr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		spr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		spr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.add_child(spr)
	# Name + 1-line stat summary
	var name_lbl := Label.new()
	name_lbl.text = String(sp.name)
	name_lbl.position = Vector2(72, 8)
	name_lbl.size = Vector2(400, 22)
	name_lbl.add_theme_font_size_override("font_size", 16)
	name_lbl.add_theme_color_override("font_color", COL_AMBER)
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(name_lbl)
	var summary_lbl := Label.new()
	summary_lbl.text = _stat_summary(sp)
	summary_lbl.position = Vector2(72, 32)
	summary_lbl.size = Vector2(400, 24)
	summary_lbl.add_theme_font_size_override("font_size", 11)
	summary_lbl.add_theme_color_override("font_color", COL_DIM)
	summary_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(summary_lbl)
	return btn

# Compress stat mods into a one-line summary like "HP -30%, Haste
# +20%, Crit +5". Skips zero entries. Used in the list row.
func _stat_summary(sp: Dictionary) -> String:
	var parts: Array = []
	var hp_pct: float = float(sp.get("hp_pct", 0))
	var atk_pct: float = float(sp.get("atk_pct", 0))
	var def_pct: float = float(sp.get("def_pct", 0))
	var haste_pct: float = float(sp.get("haste_pct", 0))
	var crit: float = float(sp.get("crit_flat", 0))
	var regen: float = float(sp.get("regen_flat", 0))
	var xp: float = float(sp.get("xp_pct", 0))
	var loot: float = float(sp.get("loot_pct", 0))
	if hp_pct != 0: parts.append("HP %+d%%" % int(hp_pct))
	if atk_pct != 0: parts.append("ATK %+d%%" % int(atk_pct))
	if def_pct != 0: parts.append("DEF %+d%%" % int(def_pct))
	if haste_pct != 0: parts.append("Haste %+d%%" % int(haste_pct))
	if crit != 0: parts.append("Crit %+d" % int(crit))
	if regen != 0: parts.append("Regen %+.1f" % regen)
	if xp != 0: parts.append("XP %+d%%" % int(xp))
	if loot != 0: parts.append("Loot %+d%%" % int(loot))
	if parts.is_empty():
		return "Balanced — no modifiers."
	return "  ".join(parts)

func _build_preview_pane(x: int, y: int, w: int, h: int) -> void:
	_panel(x, y, w, h, "Preview")
	# Big sprite.
	preview_sprite = TextureRect.new()
	preview_sprite.position = Vector2(x + 16, y + 40)
	preview_sprite.size = Vector2(128, 128)
	preview_sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview_sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(preview_sprite)
	# Name to the right of the sprite.
	preview_name = Label.new()
	preview_name.position = Vector2(x + 160, y + 50)
	preview_name.size = Vector2(w - 180, 32)
	preview_name.add_theme_font_size_override("font_size", 22)
	preview_name.add_theme_color_override("font_color", COL_AMBER)
	add_child(preview_name)
	# Lore text below the name.
	preview_lore = Label.new()
	preview_lore.position = Vector2(x + 160, y + 86)
	preview_lore.size = Vector2(w - 180, 80)
	preview_lore.add_theme_font_size_override("font_size", 13)
	preview_lore.add_theme_color_override("font_color", COL_DIM)
	preview_lore.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(preview_lore)
	# Stat-mod block below the sprite.
	preview_stats = VBoxContainer.new()
	preview_stats.position = Vector2(x + 16, y + 184)
	preview_stats.size = Vector2(w - 32, h - 200)
	preview_stats.add_theme_constant_override("separation", 4)
	add_child(preview_stats)

func _panel(x: int, y: int, w: int, h: int, header: String) -> void:
	var bg := ColorRect.new()
	bg.color = COL_PANEL
	bg.position = Vector2(x, y)
	bg.size = Vector2(w, h)
	add_child(bg)
	var border := ReferenceRect.new()
	border.position = Vector2(x, y)
	border.size = Vector2(w, h)
	border.border_color = COL_PANEL_BORDER
	border.border_width = 1.0
	border.editor_only = false
	add_child(border)
	var hdr := Label.new()
	hdr.text = header
	hdr.position = Vector2(x + 12, y + 8)
	hdr.size = Vector2(w - 24, 22)
	hdr.add_theme_font_size_override("font_size", 14)
	hdr.add_theme_color_override("font_color", COL_AMBER)
	add_child(hdr)

func _select(id: String) -> void:
	selected_id = id
	var sp: Dictionary = SpeciesData.get_def(id)
	if sp.is_empty():
		return
	if preview_name != null:
		preview_name.text = String(sp.name)
	if preview_lore != null:
		preview_lore.text = String(sp.lore)
	var sprite_path: String = SpeciesData.sprite_path_for(id)
	if preview_sprite != null and ResourceLoader.exists(sprite_path):
		preview_sprite.texture = load(sprite_path)
	_render_stat_table(sp)

# Render a stat-mod row per non-zero modifier with color cues —
# green for buff, red for nerf, white for neutral xp/loot/aggro.
func _render_stat_table(sp: Dictionary) -> void:
	if preview_stats == null:
		return
	for c in preview_stats.get_children():
		c.queue_free()
	var rows: Array = [
		{"label": "Max HP",    "key": "hp_pct",     "fmt": "%+d%%", "buff_when_pos": true},
		{"label": "Attack",    "key": "atk_pct",    "fmt": "%+d%%", "buff_when_pos": true},
		{"label": "Defense",   "key": "def_pct",    "fmt": "%+d%%", "buff_when_pos": true},
		{"label": "Haste",     "key": "haste_pct",  "fmt": "%+d%%", "buff_when_pos": true},
		{"label": "Crit",      "key": "crit_flat",  "fmt": "%+d",   "buff_when_pos": true},
		{"label": "HP Regen",  "key": "regen_flat", "fmt": "%+.1f /s", "buff_when_pos": true},
		{"label": "Aggro range", "key": "aggro_flat", "fmt": "%+d cells", "buff_when_pos": false},
		{"label": "XP gain",   "key": "xp_pct",     "fmt": "%+d%%", "buff_when_pos": true},
		{"label": "Loot rarity", "key": "loot_pct", "fmt": "%+d%%", "buff_when_pos": true},
	]
	var any_shown: bool = false
	for r in rows:
		var v: float = float(sp.get(r.key, 0))
		if v == 0:
			continue
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 12)
		var lbl := Label.new()
		lbl.text = String(r.label)
		lbl.custom_minimum_size = Vector2(140, 0)
		lbl.add_theme_font_size_override("font_size", 13)
		lbl.add_theme_color_override("font_color", COL_DIM)
		hb.add_child(lbl)
		var val := Label.new()
		val.text = (String(r.fmt) % int(v)) if String(r.fmt).find("d") >= 0 else (String(r.fmt) % v)
		val.add_theme_font_size_override("font_size", 13)
		var buff: bool = (v > 0) == bool(r.buff_when_pos)
		val.add_theme_color_override("font_color", COL_BUFF if buff else COL_NERF)
		hb.add_child(val)
		preview_stats.add_child(hb)
		any_shown = true
	# Innate flavor tags (vampire/demonspawn).
	var tags: Array = sp.get("innate_tags", [])
	if not tags.is_empty():
		var tag_lbl := Label.new()
		tag_lbl.text = "Innate: " + ", ".join(tags)
		tag_lbl.add_theme_font_size_override("font_size", 13)
		tag_lbl.add_theme_color_override("font_color", COL_AMBER)
		preview_stats.add_child(tag_lbl)
		any_shown = true
	if not any_shown:
		var none := Label.new()
		none.text = "Balanced — no modifiers."
		none.add_theme_font_size_override("font_size", 13)
		none.add_theme_color_override("font_color", COL_NEUTRAL)
		preview_stats.add_child(none)

func _on_confirm() -> void:
	if selected_id == "":
		return
	# Persist the species pick into the save.
	var state: Dictionary = SaveState.load_state()
	state["species"] = selected_id
	SaveState.save_state(state)
	character_confirmed.emit(selected_id)
