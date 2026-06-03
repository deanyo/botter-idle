# DCSS-style HUD chrome.
#
# Layout for 1280×720 viewport:
#   - Dungeon canvas region: x=0..924 (camera viewport)
#   - Right sidebar:         x=924..1280 (356 wide), full height
#       └ Minimap            top, ~256×256
#       └ Stats panel        below minimap
#       └ Log feed           below stats, fills to bottom
#   - Bottom-left bag panel: x=0..924, y=560..720 (160 tall)
#       └ Equipped slots     left side
#       └ Loose inventory    right side, scrollable
#   - Tiny debug HUD:        top-left corner, monospace, dim
#
# DCSS reference: dungeon canvas left, m_stat_x_divider on the right
# splits the sidebar; CRT message log lives at the bottom.
# (Researched in dcss-source/crawl-ref/source/tilesdl.cc.)
class_name HudChrome
extends CanvasLayer

const C := preload("res://scripts/constants.gd")

const SIDEBAR_W := 356
const SIDEBAR_PAD := 10
const MINIMAP_SIZE := SIDEBAR_W - SIDEBAR_PAD * 2
const BAG_H := 180

const PAPERDOLL_SLOT_SIZE := 48
const INV_CELL_SIZE := 48

# Slots that exist in the data layer today.
const EQUIPPED_SLOTS := ["weapon", "armor", "helm", "shield", "boots", "ring", "amulet"]

# Layout — L-shape around a top-left sprite. Active slots intermix with
# placeholder slots reserved for future gear (cloak/gloves/belt/etc).
# Tooltips show the slot name; no on-screen labels.
const PAPERDOLL_RIGHT_COLUMN := ["helm", "amulet", "cloak", "gloves", "belt"]
const PAPERDOLL_BOTTOM_ROW := ["weapon", "armor", "shield", "ring", "boots"]
const SLOT_TOOLTIPS := {
	"weapon": "Weapon", "armor": "Body Armor", "helm": "Helm",
	"shield": "Shield", "boots": "Boots",
	"amulet": "Amulet", "cloak": "Cloak", "gloves": "Gloves",
	"belt": "Belt", "ring": "Ring",
}
const PAPERDOLL_BASE_PX := 32  # source bot sprite is 32×32 native

# Colors mirror UITheme.* — kept inline because GDScript const expressions
# can't reference class members. UITheme is the canonical source; if you
# change it there, update here too. Caught at first visual-diff playtest.
const COL_AMBER := Color(0.92, 0.78, 0.45)
const COL_DIM := Color(0.7, 0.6, 0.4)
const COL_HP := Color(0.55, 0.95, 0.5)
const COL_HP_LOW := Color(1.0, 0.45, 0.45)
const COL_GOLD := Color(1.0, 0.85, 0.3)
const COL_PANEL := Color(0.0, 0.0, 0.0, 0.85)
const COL_PANEL_BORDER := Color(0.35, 0.3, 0.18, 0.65)

# Stats panel labels
var lbl_name: Label
var lbl_place: Label
var lbl_hp: Label
var hp_bar_fill: ColorRect
var hp_bar_bg: ColorRect
var lbl_atk: Label
var lbl_def: Label
var lbl_crit: Label
var lbl_haste: Label
var lbl_regen: Label
var lbl_gold: Label

# Minimap
var minimap_root: TextureRect
var minimap_dot: ColorRect
var minimap_stairs: ColorRect

# Loot log (bottom-left, loot-tagged messages only)
var log_lines: Array[Label] = []
var log_buffer: Array[String] = []
const LOG_LINE_COUNT := 6

# Paperdoll (sidebar, below stats)
var paperdoll_holder: Node2D       # parent Node2D positioned in the panel
var paperdoll_rig: Node2D = null   # current rig (rebuilt on equip change)
var paperdoll_rig_scale: float = 1.0
var paperdoll_rig_anchor: Vector2 = Vector2.ZERO
var equipped_cells: Array = []   # [{slot, sprite, hover, is_placeholder}]

# Bag (bottom strip — loot log left, segmented inventory right)
var inventory_scroll: ScrollContainer
var inventory_box: VBoxContainer
var _inv_columns: int = 6
# Equip-request callback set by dungeon.gd: takes (segment_index, item_index)
# and returns whether the equip succeeded.
var equip_request_target: Object = null

# Debug HUD
var debug_lbl: Label

# WoW-style buff/debuff bar — top-of-screen row of 36×36 icons with
# timer text under each. Reads from bot._statuses; cells reused across
# updates (build pool once, hide unused) to keep cost bounded.
var _buff_bar_root: Control = null
var _buff_cells: Array = []  # each: { bg: ColorRect, icon: TextureRect, lbl: Label }
const BUFF_CELL_SIZE := 36
const BUFF_CELL_GAP := 4
const BUFF_BAR_TOP := 4
const BUFF_BAR_MAX := 12
const _StatusOverlay := preload("res://scripts/status_overlay.gd")

func _ready() -> void:
	layer = 50
	_build_sidebar()
	_build_bag()
	_build_debug()
	_build_buff_bar()

# ============================================================================
# Construction
# ============================================================================

func _build_sidebar() -> void:
	var view := get_viewport().get_visible_rect().size
	var x0: int = int(view.x) - SIDEBAR_W
	# Background panel.
	var bg := ColorRect.new()
	bg.color = COL_PANEL
	bg.position = Vector2(x0, 0)
	bg.size = Vector2(SIDEBAR_W, view.y)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var border := ColorRect.new()
	border.color = COL_PANEL_BORDER
	border.position = Vector2(x0, 0)
	border.size = Vector2(2, view.y)
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(border)

	# Minimap region (top of sidebar).
	var mm_origin := Vector2(x0 + (SIDEBAR_W - MINIMAP_SIZE) / 2, SIDEBAR_PAD)
	var mm_bg := ColorRect.new()
	mm_bg.color = Color(0, 0, 0, 1)
	mm_bg.position = mm_origin
	mm_bg.size = Vector2(MINIMAP_SIZE, MINIMAP_SIZE)
	mm_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(mm_bg)
	minimap_root = TextureRect.new()
	minimap_root.position = mm_origin
	minimap_root.size = Vector2(MINIMAP_SIZE, MINIMAP_SIZE)
	minimap_root.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	minimap_root.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	minimap_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(minimap_root)
	# Stairs marker (yellow square).
	minimap_stairs = ColorRect.new()
	minimap_stairs.color = Color(1.0, 0.9, 0.2)
	minimap_stairs.size = Vector2(4, 4)
	minimap_stairs.visible = false
	add_child(minimap_stairs)
	# Bot dot (cyan).
	minimap_dot = ColorRect.new()
	minimap_dot.color = Color(0.4, 1.0, 1.0)
	minimap_dot.size = Vector2(5, 5)
	add_child(minimap_dot)

	# Stats column (below minimap).
	var sx: int = x0 + SIDEBAR_PAD
	var sy: int = SIDEBAR_PAD + MINIMAP_SIZE + 10
	lbl_name = _add_label("Bot the Adventurer", sx, sy, 18, COL_AMBER); sy += 22
	lbl_place = _add_label("Place: D:1", sx, sy, 14, COL_DIM); sy += 22
	# HP row
	lbl_hp = _add_label("HP: 100/100", sx, sy, 14, COL_HP); sy += 18
	hp_bar_bg = ColorRect.new()
	hp_bar_bg.color = Color(0.18, 0.05, 0.05, 1.0)
	hp_bar_bg.position = Vector2(sx, sy)
	hp_bar_bg.size = Vector2(SIDEBAR_W - SIDEBAR_PAD * 2, 8)
	add_child(hp_bar_bg)
	hp_bar_fill = ColorRect.new()
	hp_bar_fill.color = COL_HP
	hp_bar_fill.position = Vector2(sx, sy)
	hp_bar_fill.size = Vector2(SIDEBAR_W - SIDEBAR_PAD * 2, 8)
	add_child(hp_bar_fill)
	sy += 18
	# Two-column stat block: combat on the left, support on the right.
	lbl_atk = _add_label("ATK: 0", sx, sy, 14, COL_AMBER)
	lbl_def = _add_label("DEF: 0", sx + 140, sy, 14, COL_AMBER); sy += 22
	lbl_crit = _add_label("Crit: 0%", sx, sy, 14, COL_DIM)
	lbl_haste = _add_label("Haste: 0%", sx + 140, sy, 14, COL_DIM); sy += 22
	lbl_regen = _add_label("Regen: 0/s", sx, sy, 14, COL_DIM)
	lbl_gold = _add_label("Gold: 0", sx + 140, sy, 14, COL_GOLD); sy += 22

	# Paperdoll (fills the rest of the sidebar down to the bottom).
	_build_paperdoll(x0, sy + 6, int(view.y) - SIDEBAR_PAD)

func _build_paperdoll(sidebar_x0: int, top_y: int, bottom_y: int) -> void:
	# L-shape: bot sprite top-left, slots run down the right column and across
	# the bottom row. Slots have no on-screen labels — hover for tooltip.
	var slot := PAPERDOLL_SLOT_SIZE
	var inner_w: int = SIDEBAR_W - SIDEBAR_PAD * 2
	var header_h: int = 18
	var gap: int = 6
	# Header
	_add_label("Equipment", sidebar_x0 + SIDEBAR_PAD, top_y, 12, COL_DIM)
	var doll_top: int = top_y + header_h
	var doll_left: int = sidebar_x0 + SIDEBAR_PAD
	var available_h: int = bottom_y - doll_top
	# Bottom row eats slot+gap; sprite gets the rest minus a margin.
	var sprite_block_h: int = available_h - slot - gap
	sprite_block_h = clampi(sprite_block_h, 100, 260)
	# Right column width = slot. Sprite width fills remaining inner_w.
	var sprite_w: int = inner_w - slot - gap
	var sprite_h: int = sprite_block_h
	# Sprite frame top-left
	var sprite_box := ColorRect.new()
	sprite_box.color = Color(0, 0, 0, 0.35)
	sprite_box.position = Vector2(doll_left, doll_top)
	sprite_box.size = Vector2(sprite_w, sprite_h)
	sprite_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(sprite_box)
	# The paperdoll holder draws the bot rig (base + gear overlays) at the
	# native 32×32 art size, scaled to fit. update_equipped rebuilds the rig
	# from the renderer so what's shown matches the in-game bot.
	var fit: float = float(mini(sprite_w, sprite_h)) / float(PAPERDOLL_BASE_PX)
	paperdoll_rig_scale = floor(fit) if fit >= 1.0 else fit
	paperdoll_rig_scale = max(paperdoll_rig_scale, 1.0)
	paperdoll_rig_anchor = Vector2(doll_left + sprite_w / 2.0, doll_top + sprite_h / 2.0)
	paperdoll_holder = Node2D.new()
	paperdoll_holder.position = paperdoll_rig_anchor
	paperdoll_holder.scale = Vector2(paperdoll_rig_scale, paperdoll_rig_scale)
	add_child(paperdoll_holder)
	# Right column slots.
	var right_x: int = doll_left + sprite_w + gap
	var col_h_budget: int = sprite_h
	var col_count: int = mini(PAPERDOLL_RIGHT_COLUMN.size(), maxi(1, col_h_budget / (slot + gap)))
	for i in col_count:
		var slot_id: String = PAPERDOLL_RIGHT_COLUMN[i]
		var sy_i: int = doll_top + i * (slot + gap)
		_make_paperdoll_slot(slot_id, right_x, sy_i)
	# Bottom row slots.
	var row_y: int = doll_top + sprite_h + gap
	var row_count: int = mini(PAPERDOLL_BOTTOM_ROW.size(), maxi(1, inner_w / (slot + gap)))
	for i in row_count:
		var slot_id: String = PAPERDOLL_BOTTOM_ROW[i]
		var rx: int = doll_left + i * (slot + gap)
		_make_paperdoll_slot(slot_id, rx, row_y)

func _make_paperdoll_slot(slot_id: String, x: int, y: int) -> void:
	var slot := PAPERDOLL_SLOT_SIZE
	var is_placeholder: bool = not (slot_id in EQUIPPED_SLOTS)
	var slot_bg := ColorRect.new()
	slot_bg.color = Color(0, 0, 0, 0.55) if not is_placeholder else Color(0, 0, 0, 0.30)
	slot_bg.position = Vector2(x, y)
	slot_bg.size = Vector2(slot, slot)
	slot_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(slot_bg)
	var slot_border := ReferenceRect.new()
	slot_border.position = Vector2(x, y)
	slot_border.size = Vector2(slot, slot)
	slot_border.border_color = Color(0.4, 0.35, 0.2, 0.8) if not is_placeholder else Color(0.25, 0.22, 0.14, 0.55)
	slot_border.border_width = 1.0
	slot_border.editor_only = false
	slot_border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(slot_border)
	var hover := Control.new()
	hover.position = Vector2(x, y)
	hover.size = Vector2(slot, slot)
	hover.mouse_filter = Control.MOUSE_FILTER_PASS
	hover.tooltip_text = SLOT_TOOLTIPS.get(slot_id, slot_id.capitalize())
	add_child(hover)
	var sprite := TextureRect.new()
	sprite.position = Vector2(x + 4, y + 4)
	sprite.size = Vector2(slot - 8, slot - 8)
	sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(sprite)
	# Cooldown overlay — hidden by default; toggled by update_cooldowns.
	# Lives ABOVE the sprite z-order (added later → drawn later in Godot).
	var cd_dim := ColorRect.new()
	cd_dim.color = Color(0, 0, 0, 0.55)
	cd_dim.position = Vector2(x, y)
	cd_dim.size = Vector2(slot, slot)
	cd_dim.visible = false
	cd_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(cd_dim)
	var cd_lbl := Label.new()
	cd_lbl.text = ""
	cd_lbl.position = Vector2(x, y + slot / 2 - 9)
	cd_lbl.size = Vector2(slot, 18)
	cd_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cd_lbl.add_theme_font_size_override("font_size", 14)
	cd_lbl.add_theme_color_override("font_color", COL_AMBER)
	cd_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	cd_lbl.add_theme_constant_override("outline_size", 2)
	cd_lbl.visible = false
	cd_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(cd_lbl)
	equipped_cells.append({
		"slot": slot_id, "sprite": sprite, "hover": hover,
		"cd_dim": cd_dim, "cd_lbl": cd_lbl,
		"border": slot_border,
		"is_placeholder": is_placeholder,
	})

func _build_bag() -> void:
	var view := get_viewport().get_visible_rect().size
	var canvas_w: int = int(view.x) - SIDEBAR_W
	var bg := ColorRect.new()
	bg.color = COL_PANEL
	bg.position = Vector2(0, view.y - BAG_H)
	bg.size = Vector2(canvas_w, BAG_H)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var border := ColorRect.new()
	border.color = COL_PANEL_BORDER
	border.position = Vector2(0, view.y - BAG_H)
	border.size = Vector2(canvas_w, 2)
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(border)

	# Loot log (left half of bottom strip).
	var log_x: int = SIDEBAR_PAD
	var log_y: int = int(view.y) - BAG_H + SIDEBAR_PAD
	var log_w: int = int(canvas_w * 0.42) - SIDEBAR_PAD * 2
	_add_label("Loot", log_x, log_y, 13, COL_DIM)
	var log_inner_top: int = log_y + 18
	var log_inner_bottom: int = int(view.y) - SIDEBAR_PAD
	var log_h: int = log_inner_bottom - log_inner_top
	var line_h: int = max(18, int(log_h / float(LOG_LINE_COUNT)))
	for i in LOG_LINE_COUNT:
		var lbl := Label.new()
		lbl.text = ""
		lbl.position = Vector2(log_x, log_inner_top + i * line_h)
		lbl.add_theme_font_size_override("font_size", 15)
		lbl.add_theme_color_override("font_color", COL_AMBER)
		lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0))
		lbl.add_theme_constant_override("outline_size", 2)
		lbl.size = Vector2(log_w, line_h)
		lbl.clip_text = true
		add_child(lbl)
		log_lines.append(lbl)

	# Inventory list (right half of bottom strip).
	var invx: int = log_x + log_w + 16
	var invy: int = int(view.y) - BAG_H + SIDEBAR_PAD
	_add_label("Inventory", invx, invy, 13, COL_DIM)
	invy += 18
	inventory_scroll = ScrollContainer.new()
	inventory_scroll.position = Vector2(invx, invy)
	inventory_scroll.size = Vector2(canvas_w - invx - SIDEBAR_PAD, BAG_H - SIDEBAR_PAD * 2 - 18)
	inventory_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(inventory_scroll)
	inventory_box = VBoxContainer.new()
	inventory_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inventory_box.add_theme_constant_override("separation", 4)
	inventory_scroll.add_child(inventory_box)
	# Columns budget (cells per row). Derived from container width here so
	# rebuild_segments doesn't need to recompute every refresh.
	_inv_columns = max(1, int((canvas_w - invx - SIDEBAR_PAD - 16) / (INV_CELL_SIZE + 6)))

func _build_debug() -> void:
	debug_lbl = Label.new()
	debug_lbl.position = Vector2(6, 4)
	debug_lbl.add_theme_font_size_override("font_size", 12)
	debug_lbl.add_theme_color_override("font_color", Color(0.6, 0.7, 0.55, 0.85))
	debug_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	debug_lbl.add_theme_constant_override("outline_size", 2)
	debug_lbl.add_theme_font_override("font", _monospace_font())
	add_child(debug_lbl)

func _build_buff_bar() -> void:
	# Pool of BUFF_BAR_MAX cells, all hidden until populated by
	# update_buffs(). Centered horizontally above the dungeon canvas
	# (i.e. excluding the right sidebar). Re-laid-out on update so
	# adding/removing buffs re-centers the row.
	_buff_bar_root = Control.new()
	_buff_bar_root.position = Vector2(0, BUFF_BAR_TOP)
	_buff_bar_root.size = Vector2(0, BUFF_CELL_SIZE + 14)
	_buff_bar_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_buff_bar_root)
	for _i in BUFF_BAR_MAX:
		var cell := Control.new()
		cell.size = Vector2(BUFF_CELL_SIZE, BUFF_CELL_SIZE + 14)
		# PASS lets the cell receive hover/tooltip but still allow clicks
		# through to whatever sits behind it (debug HUD/dungeon canvas).
		cell.mouse_filter = Control.MOUSE_FILTER_PASS
		cell.visible = false
		var bg := ColorRect.new()
		bg.color = Color(0, 0, 0, 0.65)
		bg.size = Vector2(BUFF_CELL_SIZE, BUFF_CELL_SIZE)
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.add_child(bg)
		var border := ReferenceRect.new()
		border.size = Vector2(BUFF_CELL_SIZE, BUFF_CELL_SIZE)
		border.border_color = Color(0.4, 0.35, 0.2, 0.9)
		border.border_width = 1.0
		border.editor_only = false
		border.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.add_child(border)
		var icon := TextureRect.new()
		icon.position = Vector2(2, 2)
		icon.size = Vector2(BUFF_CELL_SIZE - 4, BUFF_CELL_SIZE - 4)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.add_child(icon)
		var lbl := Label.new()
		lbl.position = Vector2(0, BUFF_CELL_SIZE)
		lbl.size = Vector2(BUFF_CELL_SIZE, 14)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.add_theme_font_size_override("font_size", 11)
		lbl.add_theme_color_override("font_color", COL_AMBER)
		lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0))
		lbl.add_theme_constant_override("outline_size", 2)
		cell.add_child(lbl)
		_buff_bar_root.add_child(cell)
		_buff_cells.append({"cell": cell, "bg": bg, "border": border, "icon": icon, "lbl": lbl})

# Refresh the buff bar from a status dict (Actor._statuses shape:
# id → {expires_at, sprite, dot?}). Called every frame by dungeon
# (cheap: reuses pooled cells, only mutates visible/text/texture).
func update_buffs(statuses: Dictionary) -> void:
	if _buff_bar_root == null:
		return
	var view := get_viewport().get_visible_rect().size
	var canvas_w: int = int(view.x) - SIDEBAR_W
	var ids: Array = statuses.keys()
	# Sort by status `z` (defines render priority too — high z = important
	# stuff goes leftmost where the eye lands first).
	ids.sort_custom(func(a, b):
		var za: int = int(_StatusOverlay.get_def(a).get("z", 0))
		var zb: int = int(_StatusOverlay.get_def(b).get("z", 0))
		return za > zb)
	var n: int = mini(ids.size(), BUFF_BAR_MAX)
	# Center the visible row horizontally above the dungeon canvas.
	var row_w: int = n * BUFF_CELL_SIZE + max(0, n - 1) * BUFF_CELL_GAP
	var start_x: int = max(0, (canvas_w - row_w) / 2)
	var now: float = float(Time.get_ticks_msec()) / 1000.0
	for i in BUFF_BAR_MAX:
		var cell_data: Dictionary = _buff_cells[i]
		var ctrl: Control = cell_data["cell"]
		if i >= n:
			ctrl.visible = false
			continue
		var id: String = String(ids[i])
		var def: Dictionary = _StatusOverlay.get_def(id)
		var tex: Texture2D = _StatusOverlay.texture_for(id)
		var icon: TextureRect = cell_data["icon"]
		icon.texture = tex
		icon.modulate = def.get("tint", Color(1, 1, 1, 1))
		# Tooltip on the parent control — shows label + desc on hover.
		var label_str: String = String(def.get("label", id.capitalize()))
		var desc_str: String = String(def.get("desc", ""))
		ctrl.tooltip_text = label_str if desc_str.is_empty() else "%s\n%s" % [label_str, desc_str]
		var lbl: Label = cell_data["lbl"]
		var entry: Dictionary = statuses[id]
		var expires: float = float(entry.get("expires_at", 0.0))
		if expires > 0.0:
			# ceil so a renewing driver (e.g. dungeon refreshing regen
			# every frame at duration=1.0) reads as a stable "1s"
			# instead of flicking between 0s/1s as fractions tick.
			var remaining: float = expires - now
			var secs: int = max(1, int(ceil(remaining)))
			lbl.text = "%ds" % secs
		else:
			# Persistent (e.g. blessings) — no countdown.
			lbl.text = ""
		ctrl.position = Vector2(start_x + i * (BUFF_CELL_SIZE + BUFF_CELL_GAP), 0)
		ctrl.visible = true

func _monospace_font() -> Font:
	# Godot's default monospace font.
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Menlo", "Monaco", "Consolas", "monospace"])
	return f

func _add_label(t: String, x: int, y: int, size: int, color: Color) -> Label:
	var lbl := Label.new()
	lbl.text = t
	lbl.position = Vector2(x, y)
	lbl.add_theme_font_size_override("font_size", size)
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	lbl.add_theme_constant_override("outline_size", 2)
	add_child(lbl)
	return lbl

# ============================================================================
# Public update API — called by dungeon.gd
# ============================================================================

var _last_place: String = ""
var _last_hp: int = -1
var _last_max_hp: int = -1
var _last_atk: int = -1
var _last_def: int = -1
var _last_crit: int = -1
var _last_haste: int = -1
var _last_regen: int = -1
var _last_gold: int = -1

func update_stats(bot_ref: Bot, place_str: String, _turn: int) -> void:
	# Setting Label.text triggers layout/relayout in Godot. Skipping
	# unchanged values turns this from "10 layouts/frame" into "0 most
	# frames, 1-2 when something changes."
	if not is_instance_valid(bot_ref):
		return
	if place_str != _last_place:
		lbl_place.text = "Place: %s" % place_str
		_last_place = place_str
	if bot_ref.hp != _last_hp or bot_ref.max_hp != _last_max_hp:
		lbl_hp.text = "HP: %d / %d" % [bot_ref.hp, bot_ref.max_hp]
		var hp_pct: float = clampf(float(bot_ref.hp) / maxf(1.0, float(bot_ref.max_hp)), 0.0, 1.0)
		hp_bar_fill.size = Vector2((SIDEBAR_W - SIDEBAR_PAD * 2) * hp_pct, 8)
		hp_bar_fill.color = COL_HP_LOW if hp_pct < 0.3 else COL_HP
		_last_hp = bot_ref.hp
		_last_max_hp = bot_ref.max_hp
	if bot_ref.atk != _last_atk:
		lbl_atk.text = "ATK: %d" % bot_ref.atk
		_last_atk = bot_ref.atk
	if bot_ref.defense != _last_def:
		lbl_def.text = "DEF: %d" % bot_ref.defense
		_last_def = bot_ref.defense
	# Crit / Haste / Regen come from the new affix system. Display rounded
	# ints — fractional precision isn't meaningful at the player surface.
	var crit_int: int = int(round(bot_ref.crit_chance))
	if crit_int != _last_crit:
		lbl_crit.text = "Crit: %d%%" % crit_int
		_last_crit = crit_int
	# Haste is derived from attack_interval (0.6s baseline). Inverse formula.
	var haste_int: int = int(round((0.6 / bot_ref.attack_interval - 1.0) * 100.0)) if bot_ref.attack_interval > 0.0 else 0
	if haste_int != _last_haste:
		lbl_haste.text = "Haste: %d%%" % haste_int
		_last_haste = haste_int
	var regen_int: int = int(round(bot_ref.hp_regen_per_sec))
	if regen_int != _last_regen:
		lbl_regen.text = "Regen: %d/s" % regen_int
		_last_regen = regen_int
	if bot_ref.gold != _last_gold:
		lbl_gold.text = "Gold: %d" % bot_ref.gold
		_last_gold = bot_ref.gold

func push_log(msg: String, tag: String = "combat") -> void:
	# Beat 1: only loot-tagged messages render. Combat/etc are accepted but
	# silently dropped until a separate combat log is wired up.
	if tag != "loot":
		return
	log_buffer.append(msg)
	while log_buffer.size() > LOG_LINE_COUNT:
		log_buffer.pop_front()
	for i in LOG_LINE_COUNT:
		if i < log_buffer.size():
			log_lines[i].text = log_buffer[i]
		else:
			log_lines[i].text = ""

func update_equipped(equipped: Dictionary, items_db: Dictionary) -> void:
	# equipped: slot → instance dict; items_db: id → static def. The L-shape
	# slot grid keeps using the item-card icon; the bot rig draws actual
	# body/weapon/helm overlay sprites.
	for cell in equipped_cells:
		var slot: String = cell.slot
		var inst: Variant = equipped.get(slot, null)
		var sprite: TextureRect = cell.sprite
		var hover: Control = cell.hover
		var base_tooltip: String = SLOT_TOOLTIPS.get(slot, slot.capitalize())
		var tex: Texture2D = null
		var item_name: String = ""
		var slot_rarity: String = ""
		var slot_flavor: Array = []
		if inst != null and typeof(inst) == TYPE_DICTIONARY:
			var item_id: String = String(inst.get("base_id", inst.get("id", "")))
			var item_def: Dictionary = items_db.get(item_id, {})
			item_name = String(item_def.get("name", item_id))
			slot_rarity = String(item_def.get("rarity", ""))
			slot_flavor = item_def.get("flavor_tags", [])
			var tile_path: String = "res://assets/tiles/items/" + String(item_def.get("tile", ""))
			if ResourceLoader.exists(tile_path):
				tex = load(tile_path)
		sprite.texture = tex
		# Tint the equipped slot icon — flavor tag wins, rarity falls
		# back. Matches the bot rig overlay so HUD ↔ game stay in sync.
		sprite.modulate = UITheme.item_modulate(slot_rarity, slot_flavor)
		var border: ReferenceRect = cell.get("border", null)
		# Tooltip: empty slot shows "Wpn / Bdy / etc"; equipped slot shows
		# the canonical multi-line item tooltip used everywhere else.
		# Border color tracks rarity — gives the equipped paperdoll slot
		# the same rarity tell as inventory cells.
		if inst != null and typeof(inst) == TYPE_DICTIONARY:
			var item_id2: String = String(inst.get("base_id", inst.get("id", "")))
			var item_def2: Dictionary = items_db.get(item_id2, {})
			hover.tooltip_text = AffixSystem.format_item_tooltip(item_def2, inst)
			var rarity: String = String(item_def2.get("rarity", ""))
			if border != null and rarity != "":
				border.border_color = UITheme.rarity_color(rarity)
			sprite.material = null
		else:
			hover.tooltip_text = base_tooltip
			# Empty slot reverts to the default amber border. Placeholder
			# slots (amulet/cloak/etc) keep their dimmer border.
			if border != null:
				border.border_color = Color(0.25, 0.22, 0.14, 0.55) if cell.get("is_placeholder", false) else Color(0.4, 0.35, 0.2, 0.8)
			sprite.material = null
	# Rebuild the bot rig with the latest equipped set so the paperdoll shows
	# what the bot is actually wearing.
	if paperdoll_holder != null:
		if is_instance_valid(paperdoll_rig):
			paperdoll_rig.queue_free()
		var built: Dictionary = PaperdollRenderer.build_rig(items_db, equipped)
		paperdoll_rig = built.rig
		paperdoll_holder.add_child(paperdoll_rig)

# Segment-based inventory render. Each segment is {header, items}.
#
# Diff-rendering: rather than tearing down the whole VBox every loot
# pickup (the cause of a visible stutter on heavy inventories — 50-100
# Buttons + decor recreated per pickup), we cache per-segment grids
# and only rebuild segments whose item count changed. The typical
# loot-pickup path = 1 segment grew by 1 item; we just append one cell.
# Equip-swap = 1 segment shrank by 1; we rebuild that segment only.
# A new floor segment appearing = full rebuild (rare, once per floor).
var _seg_grids: Array = []  # per-segment Dict {hdr, grid_or_empty, count}

func update_inventory_segments(segments: Array, items_db: Dictionary, slot_cooldowns: Dictionary) -> void:
	if inventory_box == null:
		return
	# A "shape change" is when existing segment headers reorder or
	# disappear — that requires a full teardown. The common case
	# of segments[].size() growing by 1 (new floor reached) only
	# needs the new segment appended; the old grids stay valid. The
	# previous code rebuilt the whole panel on every floor descent,
	# which is the visible stutter we're tracking down.
	var prev_n: int = _seg_grids.size()
	var new_n: int = segments.size()
	var headers_match: bool = true
	for i in mini(prev_n, new_n):
		if String(segments[i].get("header", "")) != String(_seg_grids[i].get("header", "")):
			headers_match = false
			break
	var shape_changed: bool = not headers_match or new_n < prev_n
	if shape_changed:
		_rebuild_inventory_full(segments, items_db, slot_cooldowns)
		return
	# Same-or-grown shape. Append-only-new-segments path: build any
	# segments past the cached count without touching existing grids.
	for i in range(prev_n, new_n):
		_seg_grids.append({})
		_build_segment_into(i, segments, items_db, slot_cooldowns)
	# Same shape — diff per segment by item count. If a segment shrank
	# (equip-swap) or items reordered, do a per-segment full rebuild.
	# If it grew by N (loot pickup), append the N new cells.
	for i in segments.size():
		var seg: Dictionary = segments[i]
		var items: Array = seg.get("items", [])
		var cached: Dictionary = _seg_grids[i]
		var prev_count: int = int(cached.get("count", 0))
		var new_count: int = items.size()
		if new_count == prev_count:
			continue  # no change
		if new_count > prev_count:
			# Growth path. If we already have a grid (segment had items
			# before), append new cells. If this segment was empty
			# previously (prev_count == 0, empty_label was rendered),
			# tear out the empty label and create the grid in place
			# without queue_freeing the cached header — that header
			# rebuild was the visible loot-pickup stutter on the first
			# item of every new floor segment.
			var grid: GridContainer = cached.get("grid", null)
			if grid != null and is_instance_valid(grid):
				for k in range(prev_count, new_count):
					grid.add_child(_make_inv_button(i, k, items[k], items_db, slot_cooldowns))
				cached["count"] = new_count
				continue
			if prev_count == 0:
				# Replace empty-label with a fresh grid, leave the
				# header alone, append cells. Saves an Outpost-sized
				# tree rebuild on every floor's first pickup.
				var empty: Variant = cached.get("empty_label", null)
				if empty != null and is_instance_valid(empty):
					empty.queue_free()
				var new_grid := GridContainer.new()
				new_grid.columns = _inv_columns
				new_grid.add_theme_constant_override("h_separation", 4)
				new_grid.add_theme_constant_override("v_separation", 4)
				# Insert grid right after the header in the segment's
				# slot so visual order is preserved.
				var hdr_node: Variant = cached.get("header_node", null)
				inventory_box.add_child(new_grid)
				if hdr_node != null and is_instance_valid(hdr_node):
					inventory_box.move_child(new_grid, hdr_node.get_index() + 1)
				for k in items.size():
					new_grid.add_child(_make_inv_button(i, k, items[k], items_db, slot_cooldowns))
				cached["grid"] = new_grid
				cached["empty_label"] = null
				cached["count"] = new_count
				continue
		# Shrink or grid missing — rebuild this segment only.
		_rebuild_one_segment(i, segments, items_db, slot_cooldowns)
	if inventory_scroll != null:
		inventory_scroll.scroll_vertical = 0

func _rebuild_inventory_full(segments: Array, items_db: Dictionary, slot_cooldowns: Dictionary) -> void:
	for c in inventory_box.get_children():
		c.queue_free()
	_seg_grids.clear()
	# Render newest-first so the freshest pickups are always visible at the
	# top of the panel without needing to scroll. Older floors and the Base
	# stash live below. We still iterate segments[] in source order though
	# so _seg_grids[i] aligns with segments[i].
	# (Visual newest-first is provided by the caller filling segments
	# with new floor segments at the END of the array — main.gd does
	# this and renders them at the TOP via the loop's reverse insert.)
	# Build a placeholder array first so indices line up.
	for i in segments.size():
		_seg_grids.append({})
	for i in range(segments.size() - 1, -1, -1):
		_build_segment_into(i, segments, items_db, slot_cooldowns)
	if inventory_scroll != null:
		inventory_scroll.scroll_vertical = 0

func _rebuild_one_segment(idx: int, segments: Array, items_db: Dictionary, slot_cooldowns: Dictionary) -> void:
	# Tear down the cached header + grid for this segment.
	var cached: Dictionary = _seg_grids[idx]
	for k in ["header_node", "grid", "empty_label"]:
		var n: Variant = cached.get(k, null)
		if n != null and is_instance_valid(n):
			n.queue_free()
	_seg_grids[idx] = {}
	_build_segment_into(idx, segments, items_db, slot_cooldowns)

func _build_segment_into(idx: int, segments: Array, items_db: Dictionary, slot_cooldowns: Dictionary) -> void:
	var seg: Dictionary = segments[idx]
	var items: Array = seg.get("items", [])
	var hdr := Label.new()
	hdr.text = String(seg.get("header", ""))
	hdr.add_theme_font_size_override("font_size", 12)
	hdr.add_theme_color_override("font_color", COL_DIM)
	inventory_box.add_child(hdr)
	# Insert the new header at the right position so the visual order
	# (newest segment first) is preserved when this is a one-segment
	# rebuild rather than a full clear.
	var pack: Dictionary = {
		"header": String(seg.get("header", "")),
		"header_node": hdr,
		"grid": null,
		"empty_label": null,
		"count": items.size(),
	}
	if items.is_empty():
		var empty := Label.new()
		empty.text = "  · empty ·"
		empty.add_theme_font_size_override("font_size", 10)
		empty.add_theme_color_override("font_color", Color(0.5, 0.45, 0.35))
		inventory_box.add_child(empty)
		pack["empty_label"] = empty
		_seg_grids[idx] = pack
		return
	var grid := GridContainer.new()
	grid.columns = _inv_columns
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	inventory_box.add_child(grid)
	for item_idx in items.size():
		grid.add_child(_make_inv_button(idx, item_idx, items[item_idx], items_db, slot_cooldowns))
	pack["grid"] = grid
	_seg_grids[idx] = pack

func _make_inv_button(seg_idx: int, item_idx: int, inst: Variant, items_db: Dictionary, slot_cooldowns: Dictionary) -> Control:
	# The clickable Button is the OUTER node of the cell so its hover region
	# always matches the cell's footprint. Decorations (bg, sprite, dim,
	# countdown) are children with MOUSE_FILTER_IGNORE so the button keeps
	# its tooltip and click hit-test.
	var btn := Button.new()
	btn.flat = true
	btn.custom_minimum_size = Vector2(INV_CELL_SIZE, INV_CELL_SIZE)
	if typeof(inst) != TYPE_DICTIONARY:
		return btn
	var item_id: String = String(inst.get("base_id", inst.get("id", "")))
	var item_def: Dictionary = items_db.get(item_id, {})
	var slot: String = String(item_def.get("slot", ""))
	var rarity: String = String(item_def.get("rarity", ""))
	var flavor: Array = item_def.get("flavor_tags", [])
	var cd: float = float(slot_cooldowns.get(slot, 0.0))
	var tooltip: String = AffixSystem.format_item_tooltip(item_def, inst)
	if cd > 0.0:
		tooltip = "[on cooldown: %ds]\n%s" % [int(ceil(cd)), tooltip]
	btn.tooltip_text = tooltip
	btn.pressed.connect(_on_inv_cell_pressed.bind(seg_idx, item_idx))
	# Background.
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.45)
	bg.size = Vector2(INV_CELL_SIZE, INV_CELL_SIZE)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(bg)
	# Square border + inset halo.
	if rarity != "":
		var halo: float = {
			"common": 0.0, "uncommon": 0.18, "rare": 0.30,
			"epic": 0.42, "legendary": 0.55,
		}.get(rarity, 0.0)
		UITheme.add_rarity_cell_decor(btn, INV_CELL_SIZE, rarity, halo)
	# Sprite on top.
	var sprite := TextureRect.new()
	sprite.size = Vector2(INV_CELL_SIZE, INV_CELL_SIZE)
	sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tile_path: String = "res://assets/tiles/items/" + String(item_def.get("tile", ""))
	if ResourceLoader.exists(tile_path):
		sprite.texture = load(tile_path)
	sprite.modulate = UITheme.item_modulate(rarity, flavor)
	btn.add_child(sprite)
	return btn

func _on_inv_cell_pressed(seg_idx: int, item_idx: int) -> void:
	if equip_request_target == null:
		return
	if equip_request_target.has_method("try_equip_from_segment"):
		equip_request_target.try_equip_from_segment(seg_idx, item_idx)

# Light per-frame cooldown refresh — only updates the paperdoll countdown
# labels; doesn't rebuild the inventory grid. Called from dungeon._process.
func update_cooldowns(slot_cooldowns: Dictionary) -> void:
	for cell in equipped_cells:
		var slot: String = cell.slot
		var cd: float = float(slot_cooldowns.get(slot, 0.0))
		var on_cd: bool = cd > 0.0
		var cd_dim: ColorRect = cell.get("cd_dim", null)
		var cd_lbl: Label = cell.get("cd_lbl", null)
		if cd_dim != null:
			cd_dim.visible = on_cd
		if cd_lbl != null:
			cd_lbl.visible = on_cd
			if on_cd:
				cd_lbl.text = "%ds" % int(ceil(cd))

# Minimap: pass the current grid + bot cell + stairs cell. Renders downscaled.
var _minimap_image: Image
var _minimap_tex: ImageTexture
var _last_grid_dims := Vector2i(-1, -1)

func update_minimap(grid: Array, bot_cell: Vector2i, stairs: Vector2i, fog_visible_cells: Dictionary = {}) -> void:
	var h := grid.size()
	var w: int = grid[0].size() if h > 0 else 0
	if w == 0 or h == 0:
		return
	var dims := Vector2i(w, h)
	if _minimap_image == null or dims != _last_grid_dims:
		_minimap_image = Image.create(w, h, false, Image.FORMAT_RGBA8)
		_last_grid_dims = dims
	# Re-paint each frame is cheap at 80x80.
	# Pure transparent backdrop so OLED panels don't burn the minimap
	# rectangle's background; the surrounding chrome's own COL_PANEL
	# (also pure black now) gives the minimap visual containment.
	_minimap_image.fill(Color(0, 0, 0, 0))
	var has_fog: bool = not fog_visible_cells.is_empty()
	for y in h:
		for x in w:
			var v: int = grid[y][x]
			var col: Color
			match v:
				C.T_FLOOR: col = Color(0.35, 0.32, 0.22)
				C.T_WALL: col = Color(0.10, 0.09, 0.07)
				C.T_DOOR: col = Color(0.55, 0.42, 0.18)
				C.T_STAIRS_DOWN: col = Color(1.0, 0.9, 0.2)
				C.T_LAVA: col = Color(0.85, 0.25, 0.0)
				C.T_WATER: col = Color(0.18, 0.40, 0.85)
				C.T_ICE: col = Color(0.65, 0.85, 1.0)
				_: col = Color(0.10, 0.09, 0.07)
			if has_fog and not fog_visible_cells.has(Vector2i(x, y)):
				col = col.darkened(0.55)
			_minimap_image.set_pixel(x, y, col)
	if _minimap_tex == null:
		_minimap_tex = ImageTexture.create_from_image(_minimap_image)
	else:
		_minimap_tex.update(_minimap_image)
	minimap_root.texture = _minimap_tex
	# Position dot/stairs in screen-space within the minimap rect.
	var mm_origin := minimap_root.position
	var mm_size := minimap_root.size
	# Maintain aspect: figure out the actual rect the texture renders into.
	var tex_aspect: float = float(w) / float(h)
	var box_aspect: float = mm_size.x / mm_size.y
	var inner_w: float = mm_size.x
	var inner_h: float = mm_size.y
	if tex_aspect > box_aspect:
		inner_h = mm_size.x / tex_aspect
	else:
		inner_w = mm_size.y * tex_aspect
	var ox: float = mm_origin.x + (mm_size.x - inner_w) / 2
	var oy: float = mm_origin.y + (mm_size.y - inner_h) / 2
	if bot_cell.x >= 0 and bot_cell.y >= 0:
		minimap_dot.position = Vector2(
			ox + (bot_cell.x + 0.5) * inner_w / w - 2,
			oy + (bot_cell.y + 0.5) * inner_h / h - 2,
		)
	if stairs.x >= 0 and stairs.y >= 0:
		minimap_stairs.visible = true
		minimap_stairs.position = Vector2(
			ox + (stairs.x + 0.5) * inner_w / w - 2,
			oy + (stairs.y + 0.5) * inner_h / h - 2,
		)
	else:
		minimap_stairs.visible = false

var _last_debug_text: String = ""

func update_debug(lines: Array) -> void:
	var t: String = "\n".join(lines.map(func(s): return String(s)))
	if t != _last_debug_text:
		debug_lbl.text = t
		_last_debug_text = t
