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
const MINIMAP_SIZE := 256
const BAG_H := 160

const SLOT_TILE_SIZE := 40
const EQUIPPED_SLOTS := ["weapon", "armor", "helm", "shield", "boots"]
const SLOT_LABELS := {
	"weapon": "Wpn", "armor": "Bdy", "helm": "Hlm",
	"shield": "Shd", "boots": "Bts",
}

const COL_AMBER := Color(0.92, 0.78, 0.45)
const COL_DIM := Color(0.7, 0.6, 0.4)
const COL_HP := Color(0.55, 0.95, 0.5)
const COL_HP_LOW := Color(1.0, 0.45, 0.45)
const COL_GOLD := Color(1.0, 0.85, 0.3)
const COL_PANEL := Color(0.04, 0.04, 0.06, 0.62)
const COL_PANEL_BORDER := Color(0.35, 0.3, 0.18, 0.65)

# Stats panel labels
var lbl_name: Label
var lbl_place: Label
var lbl_hp: Label
var hp_bar_fill: ColorRect
var hp_bar_bg: ColorRect
var lbl_atk: Label
var lbl_def: Label
var lbl_level: Label
var lbl_gold: Label
var lbl_turn: Label

# Minimap
var minimap_root: TextureRect
var minimap_dot: ColorRect
var minimap_stairs: ColorRect

# Log feed
var log_lines: Array[Label] = []
var log_buffer: Array[String] = []
const LOG_LINE_COUNT := 8

# Bag (bottom-left)
var equipped_cells: Array = []   # [{slot:String, sprite:TextureRect, name:Label}]
var inventory_grid: GridContainer

# Debug HUD
var debug_lbl: Label

func _ready() -> void:
	layer = 50
	_build_sidebar()
	_build_bag()
	_build_debug()

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
	add_child(bg)
	var border := ColorRect.new()
	border.color = COL_PANEL_BORDER
	border.position = Vector2(x0, 0)
	border.size = Vector2(2, view.y)
	add_child(border)

	# Minimap region (top of sidebar).
	var mm_origin := Vector2(x0 + (SIDEBAR_W - MINIMAP_SIZE) / 2, SIDEBAR_PAD)
	var mm_bg := ColorRect.new()
	mm_bg.color = Color(0, 0, 0, 1)
	mm_bg.position = mm_origin
	mm_bg.size = Vector2(MINIMAP_SIZE, MINIMAP_SIZE)
	add_child(mm_bg)
	minimap_root = TextureRect.new()
	minimap_root.position = mm_origin
	minimap_root.size = Vector2(MINIMAP_SIZE, MINIMAP_SIZE)
	minimap_root.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	minimap_root.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
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
	# ATK / DEF
	lbl_atk = _add_label("ATK: 0", sx, sy, 14, COL_AMBER)
	lbl_def = _add_label("DEF: 0", sx + 140, sy, 14, COL_AMBER); sy += 22
	# Level / gold
	lbl_level = _add_label("XL: 1", sx, sy, 14, COL_DIM)
	lbl_gold = _add_label("Gold: 0", sx + 140, sy, 14, COL_GOLD); sy += 22
	# Turn counter
	lbl_turn = _add_label("Turn: 0", sx, sy, 12, COL_DIM); sy += 22

	# Log feed (fills remaining bottom of sidebar above the bag).
	# Bag overlaps the bottom-left of the dungeon canvas, not the sidebar,
	# so the log can use sidebar bottom freely.
	var log_top: int = sy + 8
	var log_bottom: int = int(view.y) - SIDEBAR_PAD
	var log_h: int = log_bottom - log_top
	var line_h: int = max(14, int(log_h / float(LOG_LINE_COUNT)))
	var ly: int = log_bottom - line_h * LOG_LINE_COUNT
	# Header tab
	_add_label("Recent events", sx, log_top, 11, COL_DIM)
	for i in LOG_LINE_COUNT:
		var lbl := Label.new()
		lbl.text = ""
		lbl.position = Vector2(sx, ly + i * line_h + 16)
		lbl.add_theme_font_size_override("font_size", 11)
		lbl.add_theme_color_override("font_color", COL_DIM)
		lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0))
		lbl.add_theme_constant_override("outline_size", 2)
		lbl.size = Vector2(SIDEBAR_W - SIDEBAR_PAD * 2, line_h)
		lbl.clip_text = true
		add_child(lbl)
		log_lines.append(lbl)

func _build_bag() -> void:
	var view := get_viewport().get_visible_rect().size
	var canvas_w: int = int(view.x) - SIDEBAR_W
	var bg := ColorRect.new()
	bg.color = COL_PANEL
	bg.position = Vector2(0, view.y - BAG_H)
	bg.size = Vector2(canvas_w, BAG_H)
	add_child(bg)
	var border := ColorRect.new()
	border.color = COL_PANEL_BORDER
	border.position = Vector2(0, view.y - BAG_H)
	border.size = Vector2(canvas_w, 2)
	add_child(border)

	# Equipped slots (left chunk of bag).
	var eqx := SIDEBAR_PAD
	var eqy := int(view.y) - BAG_H + SIDEBAR_PAD
	_add_label("Equipped", eqx, eqy, 11, COL_DIM)
	eqy += 14
	for i in EQUIPPED_SLOTS.size():
		var slot: String = EQUIPPED_SLOTS[i]
		var col := i % 5
		var ox = eqx + col * (SLOT_TILE_SIZE + 18)
		# Slot background
		var slot_bg := ColorRect.new()
		slot_bg.color = Color(0, 0, 0, 0.40)
		slot_bg.position = Vector2(ox, eqy)
		slot_bg.size = Vector2(SLOT_TILE_SIZE, SLOT_TILE_SIZE)
		add_child(slot_bg)
		# Border
		var slot_border := ReferenceRect.new()
		slot_border.position = Vector2(ox, eqy)
		slot_border.size = Vector2(SLOT_TILE_SIZE, SLOT_TILE_SIZE)
		slot_border.border_color = Color(0.4, 0.35, 0.2, 0.8)
		slot_border.border_width = 1.0
		slot_border.editor_only = false
		add_child(slot_border)
		# Slot label
		var slot_lbl := Label.new()
		slot_lbl.text = SLOT_LABELS.get(slot, slot)
		slot_lbl.position = Vector2(ox, eqy + SLOT_TILE_SIZE + 1)
		slot_lbl.add_theme_font_size_override("font_size", 9)
		slot_lbl.add_theme_color_override("font_color", COL_DIM)
		add_child(slot_lbl)
		# Sprite (item tile, set later)
		var sprite := TextureRect.new()
		sprite.position = Vector2(ox + 4, eqy + 4)
		sprite.size = Vector2(SLOT_TILE_SIZE - 8, SLOT_TILE_SIZE - 8)
		sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		add_child(sprite)
		# Item name label (below)
		var name_lbl := Label.new()
		name_lbl.text = ""
		name_lbl.position = Vector2(ox - 4, eqy + SLOT_TILE_SIZE + 12)
		name_lbl.size = Vector2(SLOT_TILE_SIZE + 16, 14)
		name_lbl.add_theme_font_size_override("font_size", 9)
		name_lbl.add_theme_color_override("font_color", COL_DIM)
		name_lbl.clip_text = true
		add_child(name_lbl)
		equipped_cells.append({"slot": slot, "sprite": sprite, "name_lbl": name_lbl})

	# Inventory list (right chunk of bag).
	var invx := eqx + 5 * (SLOT_TILE_SIZE + 18) + 16
	var invy := int(view.y) - BAG_H + SIDEBAR_PAD
	_add_label("Inventory", invx, invy, 11, COL_DIM)
	invy += 14
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(invx, invy)
	scroll.size = Vector2(canvas_w - invx - SIDEBAR_PAD, BAG_H - SIDEBAR_PAD * 2 - 14)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	inventory_grid = GridContainer.new()
	inventory_grid.columns = max(1, int((canvas_w - invx - SIDEBAR_PAD - 16) / (SLOT_TILE_SIZE + 4)))
	scroll.add_child(inventory_grid)

func _build_debug() -> void:
	debug_lbl = Label.new()
	debug_lbl.position = Vector2(6, 4)
	debug_lbl.add_theme_font_size_override("font_size", 10)
	debug_lbl.add_theme_color_override("font_color", Color(0.6, 0.7, 0.55, 0.85))
	debug_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	debug_lbl.add_theme_constant_override("outline_size", 2)
	debug_lbl.add_theme_font_override("font", _monospace_font())
	add_child(debug_lbl)

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
var _last_level: int = -1
var _last_gold: int = -1
var _last_turn: int = -1

func update_stats(bot_ref: Bot, place_str: String, turn: int) -> void:
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
	if bot_ref.level != _last_level:
		lbl_level.text = "XL: %d" % bot_ref.level
		_last_level = bot_ref.level
	if bot_ref.gold != _last_gold:
		lbl_gold.text = "Gold: %d" % bot_ref.gold
		_last_gold = bot_ref.gold
	if turn != _last_turn:
		lbl_turn.text = "Turn: %d" % turn
		_last_turn = turn

func push_log(msg: String) -> void:
	log_buffer.append(msg)
	while log_buffer.size() > LOG_LINE_COUNT:
		log_buffer.pop_front()
	for i in LOG_LINE_COUNT:
		if i < log_buffer.size():
			log_lines[i].text = log_buffer[i]
		else:
			log_lines[i].text = ""

func update_equipped(equipped: Dictionary, items_db: Dictionary) -> void:
	# equipped: slot → instance dict ({id, ...}); items_db: id → static def
	for cell in equipped_cells:
		var slot: String = cell.slot
		var inst: Variant = equipped.get(slot, null)
		var sprite: TextureRect = cell.sprite
		var name_lbl: Label = cell.name_lbl
		if inst == null or typeof(inst) != TYPE_DICTIONARY:
			sprite.texture = null
			name_lbl.text = ""
			continue
		# Equipped instances use `base_id` (item template) and `instance_id`
		# (uuid). Items_db is keyed by base id.
		var item_id: String = String(inst.get("base_id", inst.get("id", "")))
		var item_def: Dictionary = items_db.get(item_id, {})
		var tile_path: String = "res://assets/tiles/items/" + String(item_def.get("tile", ""))
		if ResourceLoader.exists(tile_path):
			sprite.texture = load(tile_path)
		else:
			sprite.texture = null
		name_lbl.text = String(item_def.get("name", item_id))

const INVENTORY_DISPLAY_CAP := 64

# Pool of TextureRect cells, kept alive across update_inventory calls.
# Cells past the current item count get hidden, not freed — replacing the
# queue_free + new TextureRect churn that profiled at ~250ms on a 1745-item
# save and was triggered every floor build.
var _inv_cell_pool: Array = []

func update_inventory(loose: Array, items_db: Dictionary) -> void:
	# loose: array of {id, ...} dicts. Capped at INVENTORY_DISPLAY_CAP —
	# stash sizes can balloon to hundreds/thousands.
	var n: int = mini(loose.size(), INVENTORY_DISPLAY_CAP)
	var start: int = loose.size() - n
	# Grow pool to current need (only ever grows; cells are reused).
	while _inv_cell_pool.size() < n:
		var cell := TextureRect.new()
		cell.custom_minimum_size = Vector2(SLOT_TILE_SIZE - 4, SLOT_TILE_SIZE - 4)
		cell.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		cell.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		cell.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		inventory_grid.add_child(cell)
		_inv_cell_pool.append(cell)
	# Update visible cells in place — no node creation, no queue_free.
	for i in n:
		var inst: Variant = loose[start + i]
		var pool_cell: TextureRect = _inv_cell_pool[i]
		if typeof(inst) != TYPE_DICTIONARY:
			pool_cell.visible = false
			continue
		var item_id: String = String(inst.get("base_id", inst.get("id", "")))
		var item_def: Dictionary = items_db.get(item_id, {})
		pool_cell.tooltip_text = String(item_def.get("name", item_id))
		var tile_path: String = "res://assets/tiles/items/" + String(item_def.get("tile", ""))
		var tex: Texture2D = null
		if ResourceLoader.exists(tile_path):
			tex = load(tile_path)
		pool_cell.texture = tex
		pool_cell.visible = true
	# Hide any pool slots past the current item count.
	for i in range(n, _inv_cell_pool.size()):
		_inv_cell_pool[i].visible = false

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
	_minimap_image.fill(Color(0.05, 0.05, 0.07, 1))
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
