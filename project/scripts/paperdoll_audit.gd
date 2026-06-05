extends Control

# Paperdoll Sprite Audit screen.
#
# Visualises every gear item in items.json on a base human paperdoll so
# the user can spot misaligned / oversized / off-pivot sprites at a
# glance (e.g. a 32×64 scythe rendered with a 32×32 anchor offset
# floats off the body; an item meant to be held in one hand draws over
# the chest). One click on a tile flags it as broken; pressing Export
# writes the flagged ids to user://paperdoll_flags.json so we have a
# triage list to work from.
#
# Reachable from main menu → "Paperdoll Audit" button. Authoring-only;
# the export file is never read at runtime.

signal back_pressed

const _ITEM_PREVIEW_PX := 96  # tile rendered at 3× since paperdoll art is 32×32
const _COLUMNS := 8
const _GEAR_SLOTS := ["weapon", "shield", "armor", "helm", "boots", "gloves", "cloak"]

var _items_db: Dictionary = {}
var _flagged: Dictionary = {}  # item_id → true
var _scroll: ScrollContainer = null
var _grid: GridContainer = null
var _stats_lbl: Label = null
var _slot_filter: String = ""  # "" = all
var _filter_dirty_flagged_only: bool = false
# Recolor preview mode — injects a `tint` dict into every cell's
# instance so the user can see what each item looks like under various
# hue/shimmer/inverted/prismatic recolors. Authoring 2026-06-05.
var _recolor_preview: String = "none"  # none / hue60 / hue180 / hue300 / shimmer / inverted / prismatic
# item_id → PanelContainer so toggle_flag can re-stylebox JUST that cell
# instead of rebuilding the whole grid (which previously caused 500ms+
# click latency since each rebuild instantiated 250 SubViewports +
# shader-glow rigs + tweens). Cleared on _build_grid.
var _cells_by_id: Dictionary = {}
# Pre-cached styleboxes — building these on every flag flip was free
# but the per-grid rebuild was the actual cost.
var _sb_normal: StyleBoxFlat = null
var _sb_flagged: StyleBoxFlat = null

func _ready() -> void:
	_items_db = ItemsDb.items()
	_build_chrome()
	_build_grid()

func _build_chrome() -> void:
	var view := get_viewport().get_visible_rect().size
	var bg := ColorRect.new()
	bg.color = UITheme.BG_DEEP
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	add_child(bg)
	# Top bar — title, slot filter, stats, export, back.
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 12)
	bar.position = Vector2(16, 12)
	bar.size = Vector2(view.x - 32, 32)
	add_child(bar)
	var title := Label.new()
	title.text = "PAPERDOLL AUDIT"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", UITheme.COL_AMBER)
	bar.add_child(title)
	var slot_lbl := Label.new()
	slot_lbl.text = "Slot:"
	slot_lbl.add_theme_color_override("font_color", UITheme.COL_DIM)
	bar.add_child(slot_lbl)
	var slot_opt := OptionButton.new()
	slot_opt.add_item("All", 0)
	for i in _GEAR_SLOTS.size():
		slot_opt.add_item(_GEAR_SLOTS[i].capitalize(), i + 1)
	slot_opt.item_selected.connect(func(idx: int):
		_slot_filter = "" if idx == 0 else _GEAR_SLOTS[idx - 1]
		_build_grid()
	)
	bar.add_child(slot_opt)
	# Recolor preview dropdown — exercises item_recolor.gdshader live
	# so the user can see what hue/shimmer/inverted/prismatic do
	# without having to roll a recolored drop. 2026-06-05.
	var recolor_lbl := Label.new()
	recolor_lbl.text = "Recolor:"
	recolor_lbl.add_theme_color_override("font_color", UITheme.COL_DIM)
	bar.add_child(recolor_lbl)
	var recolor_opt := OptionButton.new()
	var modes := [
		"none",
		"hue60", "hue180", "hue300",
		"colorize60", "colorize180", "colorize300",
		"shimmer", "inverted", "prismatic"
	]
	for i in modes.size():
		recolor_opt.add_item(modes[i], i)
	recolor_opt.item_selected.connect(func(idx: int):
		_recolor_preview = modes[idx]
		_build_grid()
	)
	bar.add_child(recolor_opt)
	var only_flagged_cb := CheckBox.new()
	only_flagged_cb.text = "Only flagged"
	only_flagged_cb.toggled.connect(func(v: bool):
		_filter_dirty_flagged_only = v
		_build_grid()
	)
	bar.add_child(only_flagged_cb)
	_stats_lbl = Label.new()
	_stats_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stats_lbl.add_theme_color_override("font_color", UITheme.COL_DIM)
	bar.add_child(_stats_lbl)
	var export_btn := Button.new()
	export_btn.text = "Export Flagged"
	export_btn.pressed.connect(_export_flagged)
	bar.add_child(export_btn)
	UITheme.style_button(export_btn)
	var clear_btn := Button.new()
	clear_btn.text = "Clear"
	clear_btn.pressed.connect(func():
		_flagged.clear()
		_build_grid()
	)
	bar.add_child(clear_btn)
	UITheme.style_button(clear_btn)
	var back_btn := Button.new()
	back_btn.text = "← Back"
	back_btn.pressed.connect(func(): back_pressed.emit())
	bar.add_child(back_btn)
	UITheme.style_button(back_btn)
	# Help row under the bar.
	var help := Label.new()
	help.text = "Click a tile to flag it as misaligned. Export writes user://paperdoll_flags.json."
	help.position = Vector2(16, 48)
	help.size = Vector2(view.x - 32, 18)
	help.add_theme_color_override("font_color", UITheme.COL_DIM)
	help.add_theme_font_size_override("font_size", 12)
	add_child(help)
	# Scroll + grid container.
	_scroll = ScrollContainer.new()
	_scroll.position = Vector2(16, 76)
	_scroll.size = Vector2(view.x - 32, view.y - 92)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_scroll)
	_grid = GridContainer.new()
	_grid.columns = _COLUMNS
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", 8)
	_grid.add_theme_constant_override("v_separation", 8)
	_scroll.add_child(_grid)

func _build_grid() -> void:
	if _grid == null:
		return
	# Free children + drop the cached id→cell map; about to rebuild.
	for c in _grid.get_children():
		c.queue_free()
	_cells_by_id.clear()
	if _sb_normal == null:
		_sb_normal = StyleBoxFlat.new()
		_sb_normal.bg_color = UITheme.BG_PANEL
		_sb_normal.border_color = UITheme.BORDER_DIM
		_sb_normal.border_width_left = 1
		_sb_normal.border_width_top = 1
		_sb_normal.border_width_right = 1
		_sb_normal.border_width_bottom = 1
		_sb_normal.corner_radius_top_left = 3
		_sb_normal.corner_radius_top_right = 3
		_sb_normal.corner_radius_bottom_left = 3
		_sb_normal.corner_radius_bottom_right = 3
	if _sb_flagged == null:
		_sb_flagged = StyleBoxFlat.new()
		_sb_flagged.bg_color = Color(0.20, 0.05, 0.05)
		_sb_flagged.border_color = Color(0.95, 0.30, 0.30)
		_sb_flagged.border_width_left = 2
		_sb_flagged.border_width_top = 2
		_sb_flagged.border_width_right = 2
		_sb_flagged.border_width_bottom = 2
		_sb_flagged.corner_radius_top_left = 3
		_sb_flagged.corner_radius_top_right = 3
		_sb_flagged.corner_radius_bottom_left = 3
		_sb_flagged.corner_radius_bottom_right = 3
	# Build the candidate list. Filter by slot + only-flagged.
	var items: Array = []
	for it in _items_db.values():
		var slot: String = String(it.get("slot", ""))
		if not (slot in _GEAR_SLOTS):
			continue
		if _slot_filter != "" and slot != _slot_filter:
			continue
		if _filter_dirty_flagged_only and not _flagged.has(String(it.get("id", ""))):
			continue
		items.append(it)
	# Sort: slot first, then name.
	items.sort_custom(func(a, b):
		var ka: String = String(a.get("slot", "")) + ":" + String(a.get("name", ""))
		var kb: String = String(b.get("slot", "")) + ":" + String(b.get("name", ""))
		return ka < kb
	)
	for it in items:
		_grid.add_child(_build_item_cell(it))
	if _stats_lbl != null:
		var flagged_count: int = _flagged.size()
		_stats_lbl.text = "%d items shown · %d flagged" % [items.size(), flagged_count]

func _build_item_cell(item: Dictionary) -> Control:
	var item_id: String = String(item.get("id", ""))
	var slot_id: String = String(item.get("slot", ""))
	var box := PanelContainer.new()
	box.custom_minimum_size = Vector2(_ITEM_PREVIEW_PX + 16, _ITEM_PREVIEW_PX + 56)
	# Stylebox swap on flag toggle; the styleboxes themselves are
	# pre-built once in _build_grid so per-click flips are O(1).
	box.add_theme_stylebox_override("panel", _sb_flagged if _flagged.has(item_id) else _sb_normal)
	_cells_by_id[item_id] = box
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	box.add_child(v)
	# Preview pane.
	var preview_holder := SubViewportContainer.new()
	preview_holder.stretch = true
	preview_holder.custom_minimum_size = Vector2(_ITEM_PREVIEW_PX, _ITEM_PREVIEW_PX)
	v.add_child(preview_holder)
	var sub := SubViewport.new()
	sub.size = Vector2i(_ITEM_PREVIEW_PX, _ITEM_PREVIEW_PX)
	sub.disable_3d = true
	sub.transparent_bg = true
	sub.render_target_update_mode = SubViewport.UPDATE_ONCE
	preview_holder.add_child(sub)
	# Build a single-item paperdoll rig, scaled up so the 32×32 art is
	# legible. Centered in the subviewport.
	var inst: Dictionary = {"base_id": item_id, "instance_id": "audit_" + item_id, "affixes": []}
	# Tint resolution priority:
	#   1. Recolor preview dropdown (when set to anything but "none")
	#      — lets the user demo what each mode looks like.
	#   2. Item-authored default_tint from items.json — lets the
	#      authoring round-trip (set in item editor → see in audit).
	#   3. No tint — the sprite renders as-is.
	# 2026-06-05 — was always overwriting authored tint with preview.
	var preview_tint: Dictionary = _tint_for_preview(_recolor_preview)
	if not preview_tint.is_empty():
		inst["tint"] = preview_tint
	else:
		var authored: Variant = item.get("default_tint", null)
		if typeof(authored) == TYPE_DICTIONARY and String(authored.get("mode", "")) != "":
			inst["tint"] = authored
	var equipped: Dictionary = {slot_id: inst}
	# static_only=true skips the infinite-loop glow + hand-enchant
	# tweens. 250 cells with looping tweens caused 500ms+ click latency
	# (each tween writes a shader uniform per frame on every cell).
	# 2026-06-04 audit perf fix.
	var built: Dictionary = PaperdollRenderer.build_rig(_items_db, equipped, "", true)
	var rig: Node2D = built.get("rig", null)
	if rig != null:
		rig.scale = Vector2(3.0, 3.0)
		rig.position = Vector2(_ITEM_PREVIEW_PX * 0.5, _ITEM_PREVIEW_PX * 0.6)
		sub.add_child(rig)
	# Click toggles flag — wired on the box because the SubViewport
	# eats clicks in its own area.
	box.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			_toggle_flag(item_id)
	)
	box.mouse_filter = Control.MOUSE_FILTER_STOP
	# Item name + slot tag.
	var lbl := Label.new()
	lbl.text = String(item.get("name", item_id))
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", UITheme.rarity_color(String(item.get("rarity", "common"))))
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.clip_text = true
	v.add_child(lbl)
	var slot_lbl := Label.new()
	slot_lbl.text = "[%s] %s" % [slot_id, item_id]
	slot_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	slot_lbl.add_theme_font_size_override("font_size", 9)
	slot_lbl.add_theme_color_override("font_color", UITheme.COL_DIM)
	v.add_child(slot_lbl)
	return box

func _tint_for_preview(mode: String) -> Dictionary:
	# Map the preview-mode dropdown to the same `tint` dict shape that
	# dungeon._create_item_instance writes at drop time.
	# `colorize*` previews mode 4 — useful for white/silver sprites
	# that ignore plain hue rotation (no chroma to rotate).
	match mode:
		"hue60":       return {"hue":  60.0, "sat": 1.0, "mode": "normal"}
		"hue180":      return {"hue": 180.0, "sat": 1.0, "mode": "normal"}
		"hue300":      return {"hue": 300.0, "sat": 1.0, "mode": "normal"}
		"colorize60":  return {"hue":  60.0, "sat": 1.0, "mode": "colorize"}
		"colorize180": return {"hue": 180.0, "sat": 1.0, "mode": "colorize"}
		"colorize300": return {"hue": 300.0, "sat": 1.0, "mode": "colorize"}
		"shimmer":     return {"hue":   0.0, "sat": 1.0, "mode": "shimmer"}
		"inverted":    return {"hue":   0.0, "sat": 1.0, "mode": "inverted"}
		"prismatic":   return {"hue":   0.0, "sat": 1.0, "mode": "prismatic"}
	return {}

func _toggle_flag(item_id: String) -> void:
	var newly_flagged: bool = not _flagged.has(item_id)
	if newly_flagged:
		_flagged[item_id] = true
	else:
		_flagged.erase(item_id)
	# In-place stylebox swap on the clicked cell — no grid rebuild,
	# no SubViewport / rig recreate. This was the 500ms click-latency
	# culprit; full rebuild instantiates 250+ SubViewports.
	# 2026-06-04 — paperdoll audit perf.
	var cell: Variant = _cells_by_id.get(item_id, null)
	if cell != null and is_instance_valid(cell):
		cell.add_theme_stylebox_override("panel", _sb_flagged if newly_flagged else _sb_normal)
	if _stats_lbl != null:
		_stats_lbl.text = "%d flagged" % _flagged.size()
	# When the "Only flagged" filter is active, unflagging an item
	# means it should disappear from the visible set — that DOES need
	# a rebuild. Skip the rebuild otherwise.
	if _filter_dirty_flagged_only and not newly_flagged:
		_build_grid()

func _export_flagged() -> void:
	# Group flagged ids by slot so the fix-up workflow is per-base-type.
	var by_slot: Dictionary = {}
	for item_id in _flagged.keys():
		if not _items_db.has(item_id):
			continue
		var slot_id: String = String(_items_db[item_id].get("slot", "?"))
		var arr: Array = by_slot.get(slot_id, [])
		var entry: Dictionary = {
			"id": item_id,
			"name": String(_items_db[item_id].get("name", item_id)),
			"base_type": String(_items_db[item_id].get("base_type", "")),
			"tile": String(_items_db[item_id].get("tile", "")),
		}
		arr.append(entry)
		by_slot[slot_id] = arr
	var payload: Dictionary = {
		"timestamp_unix": int(Time.get_unix_time_from_system()),
		"flagged_count": _flagged.size(),
		"by_slot": by_slot,
	}
	var path := "user://paperdoll_flags.json"
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(payload, "  "))
	# Visible feedback in the stats line.
	if _stats_lbl != null:
		_stats_lbl.text = "Exported %d flagged items → %s" % [_flagged.size(), path]
