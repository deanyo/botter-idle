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

# Signals fired when the player interacts with HUD inventory or
# paperdoll cells. Dungeon listens and forwards to the bot, then
# triggers a re-render. Keeps HUD a presentation layer — it doesn't
# own equipped state directly.
signal hud_unequip_requested(slot_id: String)
signal hud_drag_drop(payload: Dictionary, dst_slot: String)
# Fires when the player clicks the "Dump floor" button under the
# top-left debug log. Dungeon listens, builds a comprehensive
# JSON-serializable floor report, saves it to user://floor_dump_<ts>.json,
# and copies it to the clipboard. 2026-06-05.
signal debug_dump_requested

const C := preload("res://scripts/constants.gd")

const SIDEBAR_W := 356  # default fallback only — _sidebar_w is the live value
const SIDEBAR_PAD := 10
const MINIMAP_SIZE := SIDEBAR_W - SIDEBAR_PAD * 2  # default fallback only
const BAG_H := 180

# Live, viewport-sized values — set in _build_sidebar from
# UILayout.sidebar_width(view). Replaces the hardcoded SIDEBAR_W in
# the build path so ultrawide / smaller windows scale cleanly.
# UI polish pass 2026-06-04.
var _sidebar_w: int = SIDEBAR_W
var _minimap_size: int = MINIMAP_SIZE

const PAPERDOLL_SLOT_SIZE := 48
const INV_CELL_SIZE := 48

# Slots that exist in the data layer today.
const EQUIPPED_SLOTS := ["weapon", "armor", "helm", "shield", "boots", "gloves", "cloak", "ring", "amulet",
	"spell1", "spell2", "spell3", "spell4", "spell5"]
const SPELL_SLOTS := ["spell1", "spell2", "spell3", "spell4", "spell5"]

# Layout — L-shape around a top-left sprite. Gloves/cloak now ACTIVE
# slots (added 2026-06-03 per DCSS source-of-truth). Belt placeholder
# kept for any future expansion.
const PAPERDOLL_RIGHT_COLUMN := ["helm", "amulet", "cloak", "gloves", "belt"]
const PAPERDOLL_BOTTOM_ROW := ["weapon", "armor", "shield", "ring", "boots"]
const SLOT_TOOLTIPS := {
	"weapon": "Weapon", "armor": "Body Armor", "helm": "Helm",
	"shield": "Shield", "boots": "Boots",
	"amulet": "Amulet", "cloak": "Cloak", "gloves": "Gloves",
	"belt": "Belt", "ring": "Ring",
	"spell1": "Spell I", "spell2": "Spell II", "spell3": "Spell III",
	"spell4": "Spell IV", "spell5": "Spell V",
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
const COL_PANEL := Color(0.0, 0.0, 0.0, 1.0)  # pure-black, OLED — UI pass 2026-06-04
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
# Cached active species — set in update_equipped, read in
# _make_inv_button so each freshly-built inventory cell can render
# the 🚫 overlay on items the bot can't wear.
var _active_species: String = ""
var _items_db_cache: Dictionary = {}

# Debug HUD
var debug_lbl: Label
var debug_dump_btn: Button = null
var debug_dump_status: Label = null
var _debug_status_timer: SceneTreeTimer = null

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
	if VideoSettings.hud_log_overlay():
		_build_log_overlay()
	_build_debug()
	_build_buff_bar()
	if DragManager and not DragManager.drag_ended.is_connected(_on_drag_ended):
		DragManager.drag_ended.connect(_on_drag_ended)

func _exit_tree() -> void:
	if DragManager and DragManager.drag_ended.is_connected(_on_drag_ended):
		DragManager.drag_ended.disconnect(_on_drag_ended)

# WoW-style tooltip — main panel only (no shift-compare in-run; that's
# an outpost-level ritual). Item-overhaul v2 2026-06-04.
var _hud_tooltip: ItemTooltip = null
var _hud_hover_cell: ItemCell = null
var _hud_alt_was_held: bool = false

func _on_cell_tooltip(cell: ItemCell, show: bool) -> void:
	if not show:
		_hud_hover_cell = null
		if _hud_tooltip != null and is_instance_valid(_hud_tooltip):
			_hud_tooltip.queue_free()
			_hud_tooltip = null
		return
	_hud_hover_cell = cell
	if _hud_tooltip != null and is_instance_valid(_hud_tooltip):
		_hud_tooltip.queue_free()
	_hud_tooltip = ItemTooltip.new()
	add_child(_hud_tooltip)
	_hud_tooltip.render_for(cell.item, cell.inst, _items_db_cache)
	_hud_tooltip.position = _hud_clamp_tooltip(get_viewport().get_mouse_position() + Vector2(16, 16))

# Per-frame poll for Alt-key state so the extended-affix view toggles
# live while the tooltip is up. CanvasLayer doesn't tick by default —
# the existing _process call in dungeon.gd handles game logic, so we
# add a lightweight _process here just for tooltip state.
func _process(_delta: float) -> void:
	if _hud_hover_cell == null or not is_instance_valid(_hud_hover_cell):
		return
	if _hud_tooltip == null or not is_instance_valid(_hud_tooltip):
		return
	var alt_now: bool = UILayout.alt_held()
	if alt_now != _hud_alt_was_held:
		_hud_tooltip.render_for(_hud_hover_cell.item, _hud_hover_cell.inst, _items_db_cache)
		_hud_alt_was_held = alt_now

func _hud_clamp_tooltip(anchor: Vector2) -> Vector2:
	var view: Vector2 = get_viewport().get_visible_rect().size
	var sz_w: float = float(ItemTooltip.TOOLTIP_W)
	var sz_h: float = 240.0
	var px: float = clampf(anchor.x, 4.0, max(4.0, view.x - sz_w - 4.0))
	var py: float = clampf(anchor.y, 4.0, max(4.0, view.y - sz_h - 4.0))
	return Vector2(px, py)

# Compatibility check for paperdoll drops in-game. Mirrors outpost.
func _paperdoll_accepts_drop(payload: Dictionary, slot_id: String) -> bool:
	if payload == null or payload.is_empty():
		return false
	var src_role: String = String(payload.get("role", ""))
	if src_role == "paperdoll":
		var src_slot: String = String(payload.get("slot_id", ""))
		if src_slot == slot_id:
			return false
		if src_slot.begins_with("spell") and slot_id.begins_with("spell"):
			return true
		if src_slot.begins_with("ring") and slot_id.begins_with("ring"):
			return true
		return src_slot == slot_id
	var item_slot: String = String(payload.get("item_slot", ""))
	if item_slot == "":
		return false
	if not slot_id.begins_with("spell") and _active_species != "" and not SpeciesData.can_wear(_active_species, slot_id):
		return false
	if item_slot == "spell" and slot_id.begins_with("spell"):
		return true
	if item_slot == "ring" and slot_id.begins_with("ring"):
		return true
	return item_slot == slot_id

# Click handler — left-click an equipped slot to unequip, sending the
# item back to inventory. Mirrors the outpost behavior.
func _on_paperdoll_left_click(cell: ItemCell) -> void:
	if cell.role != "paperdoll":
		return
	# Hand off to the dungeon — it owns the bot equipped state and inv.
	# HUD is a presentation layer; bubble via signal.
	emit_signal("hud_unequip_requested", cell.slot_id)

# DragManager fires this when a drag releases. We forward to dungeon
# via signals because mid-run swaps need to update bot.equipped (not
# just SaveState) so the runtime sees them immediately.
func _on_drag_ended(payload: Dictionary, dropped_on: Variant) -> void:
	if dropped_on == null or not is_instance_valid(dropped_on):
		return
	if not (dropped_on is ItemCell):
		return
	var dst: ItemCell = dropped_on
	if dst.role != "paperdoll":
		return
	emit_signal("hud_drag_drop", payload, dst.slot_id)

# ============================================================================
# Construction
# ============================================================================

func _build_sidebar() -> void:
	var view := get_viewport().get_visible_rect().size
	# UI polish 2026-06-04: sidebar width scales with viewport. 25% of
	# screen width clamped 320..480. Replaces the hardcoded 356px.
	_sidebar_w = UILayout.sidebar_width(view)
	_minimap_size = _sidebar_w - SIDEBAR_PAD * 2
	var x0: int = int(view.x) - _sidebar_w
	# Background panel.
	var bg := ColorRect.new()
	bg.color = COL_PANEL
	bg.position = Vector2(x0, 0)
	bg.size = Vector2(_sidebar_w, view.y)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var border := ColorRect.new()
	border.color = COL_PANEL_BORDER
	border.position = Vector2(x0, 0)
	border.size = Vector2(2, view.y)
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(border)

	# Minimap region (top of sidebar). Per UI pass 2026-06-04: backplate
	# is fully transparent so only map elements (floor / wall / bot dot
	# / stairs marker) render. The sidebar's BG_PANEL behind it provides
	# the dark backdrop on OLED panels — keeps the minimap from looking
	# like it lives in a grey square.
	var mm_origin := Vector2(x0 + (_sidebar_w - _minimap_size) / 2, SIDEBAR_PAD)
	var mm_bg := ColorRect.new()
	mm_bg.color = Color(0, 0, 0, 0)
	mm_bg.position = mm_origin
	mm_bg.size = Vector2(_minimap_size, _minimap_size)
	mm_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(mm_bg)
	minimap_root = TextureRect.new()
	minimap_root.position = mm_origin
	minimap_root.size = Vector2(_minimap_size, _minimap_size)
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
	var sy: int = SIDEBAR_PAD + _minimap_size + 10
	lbl_name = _add_label("Bot the Adventurer", sx, sy, 18, COL_AMBER); sy += 22
	lbl_place = _add_label("Place: D:1", sx, sy, 14, COL_DIM); sy += 22
	# HP row
	lbl_hp = _add_label("HP: 100/100", sx, sy, 14, COL_HP); sy += 18
	hp_bar_bg = ColorRect.new()
	hp_bar_bg.color = Color(0.18, 0.05, 0.05, 1.0)
	hp_bar_bg.position = Vector2(sx, sy)
	hp_bar_bg.size = Vector2(_sidebar_w - SIDEBAR_PAD * 2, 8)
	add_child(hp_bar_bg)
	hp_bar_fill = ColorRect.new()
	hp_bar_fill.color = COL_HP
	hp_bar_fill.position = Vector2(sx, sy)
	hp_bar_fill.size = Vector2(_sidebar_w - SIDEBAR_PAD * 2, 8)
	add_child(hp_bar_fill)
	sy += 18
	# Two-column stat block: combat on the left, support on the right.
	lbl_atk = _add_label("Dmg: 1-2", sx, sy, 14, COL_AMBER)
	lbl_def = _add_label("Armor: 0", sx + 140, sy, 14, COL_AMBER); sy += 22
	lbl_crit = _add_label("Crit: 0%", sx, sy, 14, COL_DIM)
	lbl_haste = _add_label("Haste: 0%", sx + 140, sy, 14, COL_DIM); sy += 22
	lbl_regen = _add_label("Regen: 0/s", sx, sy, 14, COL_DIM)
	lbl_gold = _add_label("Gold: 0", sx + 140, sy, 14, COL_GOLD); sy += 22

	# Paperdoll (fills the rest of the sidebar down to the bottom).
	# Paperdoll bottom must clear the bag panel (which lives at
	# view.y - BAG_H .. view.y). Previously we passed view.y - SIDEBAR_PAD
	# which made the spell row render UNDER the bag — invisible to the
	# player. UI polish 2026-06-04.
	_build_paperdoll(x0, sy + 6, int(view.y) - BAG_H - SIDEBAR_PAD)

func _build_paperdoll(sidebar_x0: int, top_y: int, bottom_y: int) -> void:
	# L-shape: bot sprite top-left, slots run down the right column and across
	# the bottom row. Slots have no on-screen labels — hover for tooltip.
	var slot := PAPERDOLL_SLOT_SIZE
	var inner_w: int = _sidebar_w - SIDEBAR_PAD * 2
	var header_h: int = 18
	var gap: int = 6
	# Header
	_add_label("Equipment", sidebar_x0 + SIDEBAR_PAD, top_y, 12, COL_DIM)
	var doll_top: int = top_y + header_h
	var doll_left: int = sidebar_x0 + SIDEBAR_PAD
	var available_h: int = bottom_y - doll_top
	# Bottom row + spell row each eat slot+gap. Sprite gets whatever's
	# left, clamped to a sane band so the sprite doesn't disappear on
	# narrow viewports. UI polish 2026-06-04 — previously the spell
	# row's height wasn't reserved here, so it overflowed under the bag.
	var sprite_block_h: int = available_h - (slot + gap) * 2
	sprite_block_h = clampi(sprite_block_h, 80, 260)
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
	# Species-resolved slot lists (mirrors outpost.gd). Converted slots
	# replaced with extra ring slots in column/row order.
	var species: String = String(SaveState.load_state().get("species", ""))
	var conv: Dictionary = SpeciesData.slot_conversions(species)
	var ring_pool: Array = SpeciesData.ring_slot_ids(species).slice(1)
	var ring_pool_idx: int = 0
	var resolved_right: Array = []
	for sid in PAPERDOLL_RIGHT_COLUMN:
		if conv.has(sid) and ring_pool_idx < ring_pool.size():
			resolved_right.append(ring_pool[ring_pool_idx])
			ring_pool_idx += 1
		else:
			resolved_right.append(sid)
	var resolved_bottom: Array = []
	for sid in PAPERDOLL_BOTTOM_ROW:
		if conv.has(sid) and ring_pool_idx < ring_pool.size():
			resolved_bottom.append(ring_pool[ring_pool_idx])
			ring_pool_idx += 1
		else:
			resolved_bottom.append(sid)
	# Right column slots.
	var right_x: int = doll_left + sprite_w + gap
	var col_h_budget: int = sprite_h
	var col_count: int = mini(resolved_right.size(), maxi(1, col_h_budget / (slot + gap)))
	for i in col_count:
		var sy_i: int = doll_top + i * (slot + gap)
		_make_paperdoll_slot(resolved_right[i], right_x, sy_i)
	# Bottom row slots.
	var row_y: int = doll_top + sprite_h + gap
	var row_count: int = mini(resolved_bottom.size(), maxi(1, inner_w / (slot + gap)))
	for i in row_count:
		var rx: int = doll_left + i * (slot + gap)
		_make_paperdoll_slot(resolved_bottom[i], rx, row_y)
	# Spell row — 5 autocast cells under the gear row. They reuse the
	# same cooldown overlay machinery already wired into _make_paperdoll_slot.
	# UI polish 2026-06-04: shrink spell cells to fit all 5 across the
	# pane width, wrapping to a second row only if even minimum size
	# (32px) doesn't fit. Mirrors outpost.gd behavior.
	var spell_row_y: int = row_y + slot + gap
	var spell_slot: int = clampi(int((inner_w - gap * 4) / 5), 32, slot)
	var per_row: int = mini(SPELL_SLOTS.size(), maxi(1, (inner_w + gap) / (spell_slot + gap)))
	for i in SPELL_SLOTS.size():
		var col: int = i % per_row
		var rowi: int = i / per_row
		var sx_spell: int = doll_left + col * (spell_slot + gap)
		var sy_spell: int = spell_row_y + rowi * (spell_slot + gap)
		_make_paperdoll_slot(SPELL_SLOTS[i], sx_spell, sy_spell, spell_slot)

# Tooltip for any slot, including extra ring slots (ring2..ringN).
# Mirrors outpost.gd::_tooltip_for_slot.
func _tooltip_for_slot(slot_id: String) -> String:
	if slot_id == "ring":
		return "Ring"
	if slot_id.begins_with("ring") and slot_id.length() > 4:
		var n: int = int(slot_id.substr(4))
		var roman := ["", "I", "II", "III", "IV", "V"]
		return "Ring %s" % (roman[n] if n < roman.size() else str(n))
	return SLOT_TOOLTIPS.get(slot_id, slot_id.capitalize())

func _make_paperdoll_slot(slot_id: String, x: int, y: int, override_size: int = 0) -> void:
	# Spell row passes a smaller override_size when the pane is narrow
	# so all 5 spells fit. Defaults to PAPERDOLL_SLOT_SIZE for gear.
	var slot := override_size if override_size > 0 else PAPERDOLL_SLOT_SIZE
	var is_real: bool = (slot_id in EQUIPPED_SLOTS) or slot_id.begins_with("ring") or slot_id.begins_with("spell")
	var is_placeholder: bool = not is_real
	# ItemCell — replaces the old hand-rolled bg/border/sprite tree.
	# DragManager + ItemCell.gui_input handle drag/drop; cooldown overlay
	# is added as a child of the cell so it follows the cell on layout.
	var cell := ItemCell.new()
	cell.cell_size = slot
	cell.role = "paperdoll"
	cell.slot_id = slot_id
	cell.blocked = is_placeholder
	cell.position = Vector2(x, y)
	cell.accepts_drop = Callable(self, "_paperdoll_accepts_drop").bind(slot_id)
	cell.on_left_click = Callable(self, "_on_paperdoll_left_click")
	cell.tooltip_owner = Callable(self, "_on_cell_tooltip")
	add_child(cell)
	# Cooldown overlay — sized + positioned to cover the cell. Toggled
	# by update_cooldowns. Sits above the sprite by being added after
	# the cell's sprite child (cell._ready already added the sprite).
	var cd_dim := ColorRect.new()
	cd_dim.color = Color(0, 0, 0, 0.55)
	cd_dim.position = Vector2.ZERO
	cd_dim.size = Vector2(slot, slot)
	cd_dim.visible = false
	cd_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(cd_dim)
	var cd_lbl := Label.new()
	cd_lbl.text = ""
	cd_lbl.position = Vector2(0, slot / 2 - 9)
	cd_lbl.size = Vector2(slot, 18)
	cd_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cd_lbl.add_theme_font_size_override("font_size", 14)
	cd_lbl.add_theme_color_override("font_color", COL_AMBER)
	cd_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	cd_lbl.add_theme_constant_override("outline_size", 2)
	cd_lbl.visible = false
	cd_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(cd_lbl)
	# Spell cells get an extra radial-sweep cooldown ring drawn via a
	# custom Node2D._draw. Rings sweep counter-clockwise from full at
	# fire time → empty at ready. Combat-pivot 2026-06-04.
	var cd_ring: Node2D = null
	if slot_id.begins_with("spell"):
		cd_ring = Node2D.new()
		cd_ring.position = Vector2(slot * 0.5, slot * 0.5)
		cd_ring.set_meta("cell_size", slot)
		cd_ring.set_meta("frac", 0.0)
		cd_ring.draw.connect(_draw_spell_cooldown_ring.bind(cd_ring))
		cell.add_child(cd_ring)
	equipped_cells.append({
		"slot": slot_id, "cell": cell,
		"cd_dim": cd_dim, "cd_lbl": cd_lbl,
		"cd_ring": cd_ring,
		"is_placeholder": is_placeholder,
	})

func _build_bag() -> void:
	var view := get_viewport().get_visible_rect().size
	var canvas_w: int = int(view.x) - _sidebar_w
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

	# Inventory list now spans the full bottom strip — the loot log
	# moved to a translucent overlay over the play area, toggled in
	# Video options as `hud_log_overlay`. UI polish 2026-06-04.
	var invx: int = SIDEBAR_PAD
	var invy: int = int(view.y) - BAG_H + SIDEBAR_PAD
	_add_label("Inventory", invx, invy, 13, COL_DIM)
	invy += 18
	inventory_scroll = ScrollContainer.new()
	inventory_scroll.position = Vector2(invx, invy)
	# Round the scroll height down to a whole-row multiple so the last
	# visible row is never half-cut. Each row = INV_CELL_SIZE + grid
	# v_separation (4px). UI polish 2026-06-04.
	var raw_scroll_h: int = BAG_H - SIDEBAR_PAD * 2 - 18
	var row_h: int = INV_CELL_SIZE + 4
	var visible_rows: int = maxi(1, raw_scroll_h / row_h)
	var scroll_h: int = visible_rows * row_h
	inventory_scroll.size = Vector2(canvas_w - invx - SIDEBAR_PAD, scroll_h)
	inventory_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(inventory_scroll)
	inventory_box = VBoxContainer.new()
	inventory_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inventory_box.add_theme_constant_override("separation", 4)
	inventory_scroll.add_child(inventory_box)
	# Columns budget (cells per row). Derived from container width here so
	# rebuild_segments doesn't need to recompute every refresh.
	_inv_columns = max(1, int((canvas_w - invx - SIDEBAR_PAD - 16) / (INV_CELL_SIZE + 6)))

func _build_log_overlay() -> void:
	# Translucent loot/combat log overlay, anchored bottom-left of the
	# play area (just above the inventory bag). LOG_LINE_COUNT lines
	# stacked, oldest at top, newest at bottom. UI polish 2026-06-04.
	# Toggled via Video Options (`hud_log_overlay`).
	var view := get_viewport().get_visible_rect().size
	var line_h: int = 18
	var pad: int = SIDEBAR_PAD
	var ow: int = mini(int(view.x * 0.32), 460)  # overlay width — narrow enough to leave play area uncluttered
	var oh: int = line_h * LOG_LINE_COUNT + pad
	var ox: int = pad
	var oy: int = int(view.y) - BAG_H - oh - pad
	# Faint dark backdrop so amber text reads against bright biome floors.
	var backdrop := ColorRect.new()
	backdrop.color = Color(0, 0, 0, 0.30)
	backdrop.position = Vector2(ox - 4, oy - 4)
	backdrop.size = Vector2(ow + 8, oh + 8)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)
	# Top→bottom fade: oldest message (index 0) softens to ~0.35 alpha,
	# newest (index LOG_LINE_COUNT-1) is fully opaque. Drives the eye
	# toward fresh combat/loot text. UI polish 2026-06-04.
	for i in LOG_LINE_COUNT:
		var lbl := Label.new()
		lbl.text = ""
		lbl.position = Vector2(ox, oy + i * line_h)
		lbl.size = Vector2(ow, line_h)
		lbl.add_theme_font_size_override("font_size", 14)
		lbl.add_theme_color_override("font_color", COL_AMBER)
		lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0))
		lbl.add_theme_constant_override("outline_size", 2)
		lbl.clip_text = true
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var fade_t: float = float(i + 1) / float(LOG_LINE_COUNT)
		lbl.modulate = Color(1, 1, 1, lerp(0.35, 1.0, fade_t))
		add_child(lbl)
		log_lines.append(lbl)

func _build_debug() -> void:
	debug_lbl = Label.new()
	debug_lbl.position = Vector2(6, 4)
	debug_lbl.add_theme_font_size_override("font_size", 12)
	debug_lbl.add_theme_color_override("font_color", Color(0.6, 0.7, 0.55, 0.85))
	debug_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	debug_lbl.add_theme_constant_override("outline_size", 2)
	debug_lbl.add_theme_font_override("font", _monospace_font())
	add_child(debug_lbl)
	# "Dump floor" button under the debug text — emits
	# debug_dump_requested so the dungeon can write a comprehensive
	# floor report for triage. 2026-06-05.
	debug_dump_btn = Button.new()
	debug_dump_btn.text = "📋 Dump floor"
	debug_dump_btn.add_theme_font_size_override("font_size", 11)
	debug_dump_btn.position = Vector2(6, 0)  # repositioned each frame in update_debug
	debug_dump_btn.size = Vector2(110, 22)
	debug_dump_btn.tooltip_text = "Save + copy a JSON dump of this floor to clipboard.\nUseful for sharing weird floors with Claude."
	debug_dump_btn.pressed.connect(func(): debug_dump_requested.emit())
	add_child(debug_dump_btn)
	UITheme.style_button(debug_dump_btn)
	# Status label flashes the save path / clipboard byte count for ~3s
	# after a dump fires, then fades out.
	debug_dump_status = Label.new()
	debug_dump_status.position = Vector2(6, 0)  # repositioned each frame
	debug_dump_status.add_theme_font_size_override("font_size", 10)
	debug_dump_status.add_theme_color_override("font_color", Color(0.55, 0.95, 0.55, 0.95))
	debug_dump_status.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	debug_dump_status.add_theme_constant_override("outline_size", 2)
	debug_dump_status.add_theme_font_override("font", _monospace_font())
	debug_dump_status.visible = false
	add_child(debug_dump_status)

# Public: dungeon calls this with the save path / chars-copied summary
# so the HUD can flash a confirmation under the dump button. Auto-hides
# after 3.5s.
func flash_debug_dump_status(msg: String) -> void:
	if debug_dump_status == null or not is_instance_valid(debug_dump_status):
		return
	debug_dump_status.text = msg
	debug_dump_status.visible = true
	# Reposition under the button before showing.
	if debug_dump_btn != null and is_instance_valid(debug_dump_btn):
		debug_dump_status.position = Vector2(6, debug_dump_btn.position.y + debug_dump_btn.size.y + 2)
	# Cancel any in-flight hide timer.
	_debug_status_timer = get_tree().create_timer(3.5)
	_debug_status_timer.timeout.connect(func():
		if debug_dump_status != null and is_instance_valid(debug_dump_status):
			debug_dump_status.visible = false
	)

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
	var canvas_w: int = int(view.x) - _sidebar_w
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
		hp_bar_fill.size = Vector2((_sidebar_w - SIDEBAR_PAD * 2) * hp_pct, 8)
		hp_bar_fill.color = COL_HP_LOW if hp_pct < 0.3 else COL_HP
		_last_hp = bot_ref.hp
		_last_max_hp = bot_ref.max_hp
	# Item-overhaul v2: damage line shows min-max + element + speed.
	# Defense splits into Armor (flat phys) and Evasion%.
	if bot_ref.damage_max != _last_atk:
		var dtype: String = String(bot_ref.weapon_damage_type)
		# Capitalize element label; "Phys" for physical for compactness.
		var dtype_label: String = dtype.capitalize() if dtype != "physical" else "Phys"
		lbl_atk.text = "Dmg: %d-%d %s · %.1fs" % [bot_ref.damage_min, bot_ref.damage_max, dtype_label, bot_ref.weapon_speed]
		_last_atk = bot_ref.damage_max
	if bot_ref.armor != _last_def:
		var ev_int: int = int(round(bot_ref.evasion))
		lbl_def.text = "Armor: %d · Eva: %d%%" % [bot_ref.armor, ev_int]
		_last_def = bot_ref.armor
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
	# Skip the visual update when the overlay is disabled — log_lines is
	# empty in that case. The buffer itself still tracks recent messages
	# in case we want a "recent loot" tooltip later.
	if log_lines.is_empty():
		return
	for i in LOG_LINE_COUNT:
		if i < log_buffer.size():
			log_lines[i].text = log_buffer[i]
		else:
			log_lines[i].text = ""

func update_equipped(equipped: Dictionary, items_db: Dictionary, species: String = "") -> void:
	# equipped: slot → instance dict; items_db: id → static def. The L-shape
	# slot grid uses ItemCell to render — same widget as outpost so equip
	# state, drag-drop, and visuals stay in sync.
	_active_species = species
	_items_db_cache = items_db
	for entry in equipped_cells:
		var slot: String = String(entry.slot)
		var cell: ItemCell = entry.cell
		var inst: Variant = equipped.get(slot, null)
		var species_blocked: bool = species != "" and not slot.begins_with("spell") and not SpeciesData.can_wear(species, slot)
		cell.inst = inst
		if inst != null and typeof(inst) == TYPE_DICTIONARY and items_db.has(String(inst.get("base_id", ""))):
			cell.item = items_db[String(inst.get("base_id", ""))]
		else:
			cell.item = {}
		cell.blocked = species_blocked or bool(entry.get("is_placeholder", false))
		cell.render()
	# Rebuild the bot rig with the latest equipped set so the paperdoll shows
	# what the bot is actually wearing.
	if paperdoll_holder != null:
		if is_instance_valid(paperdoll_rig):
			paperdoll_rig.queue_free()
		var built: Dictionary = PaperdollRenderer.build_rig(items_db, equipped, species)
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
				var grow_ids: Array = cached.get("ids", [])
				for k in range(prev_count, new_count):
					grow_ids.append(_inst_key(items[k]))
				cached["ids"] = grow_ids
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
				var fresh_ids: Array = []
				for it in items:
					fresh_ids.append(_inst_key(it))
				cached["ids"] = fresh_ids
				continue
		# Shrink path — try to surgically remove the single cell that
		# disappeared instead of rebuilding the whole segment (which
		# reorders the remaining cells visually). We diff the cached
		# instance ids against the new items to find which index dropped.
		var grid_s: GridContainer = cached.get("grid", null)
		var prev_ids: Array = cached.get("ids", [])
		if grid_s != null and is_instance_valid(grid_s) and not prev_ids.is_empty() \
				and new_count == prev_count - 1:
			var new_ids: Array = []
			for it in items:
				new_ids.append(_inst_key(it))
			var removed_idx: int = _diff_first_removed(prev_ids, new_ids)
			if removed_idx >= 0 and removed_idx < grid_s.get_child_count():
				var node: Node = grid_s.get_child(removed_idx)
				if node != null and is_instance_valid(node):
					node.queue_free()
				# Renumber subsequent siblings — their `item_idx` meta
				# pointed at indices that just shifted left by one when
				# the data array compacted. Without this, drag/click
				# on a remaining cell looks up _loot_segments[seg].items
				# at a stale index → equips the WRONG item (presents
				# as the dragged-spell-equipped-as-cloak bug).
				for child_idx in range(removed_idx, grid_s.get_child_count()):
					var sibling: Node = grid_s.get_child(child_idx)
					if sibling == node:
						continue  # the queued-free node is still in the tree this frame
					if sibling.has_method("set_meta"):
						var old_item_idx: int = int(sibling.get_meta("item_idx", -1))
						if old_item_idx > removed_idx:
							sibling.set_meta("item_idx", old_item_idx - 1)
				cached["count"] = new_count
				cached["ids"] = new_ids
				continue
		# General shrink / grid missing — fall back to rebuild.
		_rebuild_one_segment(i, segments, items_db, slot_cooldowns)
	if inventory_scroll != null:
		inventory_scroll.scroll_vertical = 0

# Identity key for an instance — instance_id when available, else
# (base_id + index) so duplicate-base items still get distinct keys.
func _inst_key(inst: Variant) -> String:
	if typeof(inst) != TYPE_DICTIONARY:
		return ""
	var id: String = String(inst.get("instance_id", ""))
	return id if id != "" else String(inst.get("base_id", ""))

# Find the first index in `prev` that doesn't appear at the same
# position in `new`. Returns -1 if `new` matches `prev` start-to-start
# (means the missing element is at the tail).
func _diff_first_removed(prev: Array, new: Array) -> int:
	var n: int = mini(prev.size(), new.size())
	for i in n:
		if String(prev[i]) != String(new[i]):
			return i
	# Tail removal — last index of prev.
	if new.size() < prev.size():
		return new.size()
	return -1

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
	var ids_arr: Array = []
	for it in items:
		ids_arr.append(_inst_key(it))
	var pack: Dictionary = {
		"header": String(seg.get("header", "")),
		"header_node": hdr,
		"grid": null,
		"empty_label": null,
		"count": items.size(),
		"ids": ids_arr,
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
	# Inventory cells in the run HUD now use ItemCell — same drag/drop
	# pipeline as outpost. Left-click still equips via the existing
	# (seg_idx, item_idx) path for back-compat. Drag releases bubble
	# through DragManager → HudChrome._on_drag_ended → dungeon's
	# _on_hud_drag_drop (which mutates bot.equipped directly so the
	# autocast tick sees the new spell on the next frame).
	if typeof(inst) != TYPE_DICTIONARY:
		var blank := Control.new()
		blank.custom_minimum_size = Vector2(INV_CELL_SIZE, INV_CELL_SIZE)
		return blank
	var item_id: String = String(inst.get("base_id", inst.get("id", "")))
	var item_def: Dictionary = items_db.get(item_id, {})
	var slot: String = String(item_def.get("slot", ""))
	var blocked: bool = _active_species != "" and slot != "" and not SpeciesData.can_wear(_active_species, slot)
	var cell := ItemCell.new()
	cell.cell_size = INV_CELL_SIZE
	cell.role = "inventory"
	# inv_index is computed JUST IN TIME from (seg_idx, item_idx) when
	# the drag actually starts — see ItemCell._gui_input override below
	# in this file. Storing a stale flat index at cell creation time
	# was incorrect during _rebuild_inventory_full's reverse-build
	# order (segments past index 0 had wrong offsets, which routed
	# drags to the WRONG item — felt like duplication to the player).
	cell.inv_index = -1
	cell.inst = inst
	cell.item = item_def
	cell.blocked = blocked
	cell.set_meta("seg_idx", seg_idx)
	cell.set_meta("item_idx", item_idx)
	cell.set_meta("instance_id", String(inst.get("instance_id", "")))
	cell.on_left_click = Callable(self, "_on_hud_inv_left_click")
	cell.tooltip_owner = Callable(self, "_on_cell_tooltip")
	# Resolve flat inv_index lazily — DragManager.begin_drag reads
	# cell.inv_index, so we set it just before the drag stages. Hook
	# via a one-frame "before drag" callback by subscribing to the
	# cell's _gui_input through a wrapper.
	cell.set_meta("flat_index_resolver", Callable(self, "_resolve_flat_index").bind(cell))
	cell.ready.connect(cell.render)
	return cell

# Lazy flat-index resolver — called by ItemCell._gui_input on press
# to populate cell.inv_index before begin_drag fires. Walks the live
# _seg_grids (now stable, post-rebuild) for an authoritative offset.
func _resolve_flat_index(cell: ItemCell) -> void:
	var seg_idx: int = int(cell.get_meta("seg_idx", -1))
	var item_idx: int = int(cell.get_meta("item_idx", -1))
	if seg_idx < 0 or item_idx < 0:
		return
	var offset: int = 0
	for i in seg_idx:
		if i < _seg_grids.size():
			offset += int(_seg_grids[i].get("count", 0))
	cell.inv_index = offset + item_idx

func _on_hud_inv_left_click(cell: ItemCell) -> void:
	if equip_request_target == null:
		return
	var seg_idx: int = int(cell.get_meta("seg_idx", -1))
	var item_idx: int = int(cell.get_meta("item_idx", -1))
	# Verify the (seg_idx, item_idx) still points at the SAME item
	# instance_id the cell was built with. A queue_freed-but-not-yet-
	# deleted cell can fire a second click after equip; without this
	# guard we'd equip whatever slid into that index — feels like
	# item duplication. UI polish 2026-06-04.
	var iid: String = String(cell.get_meta("instance_id", ""))
	if iid != "" and equip_request_target.has_method("instance_at_segment_idx"):
		var live_iid: String = String(equip_request_target.call("instance_at_segment_idx", seg_idx, item_idx))
		if live_iid != iid:
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

# Spell cooldown ring overlay — drives the per-spell radial sweep from
# bot.spell_cooldowns + the spell item's base cooldown via SpellSystem.
# Combat-pivot 2026-06-04. Called every dungeon._process tick.
func update_spell_cooldowns(bot_ref: Node, items_db: Dictionary) -> void:
	if bot_ref == null:
		return
	for cell in equipped_cells:
		var slot: String = cell.slot
		if not slot.begins_with("spell"):
			continue
		var ring: Node2D = cell.get("cd_ring", null)
		if ring == null or not is_instance_valid(ring):
			continue
		var frac: float = SpellSystem.cooldown_fraction(bot_ref, slot, items_db)
		var prev_frac: float = float(ring.get_meta("frac", 0.0))
		# Skip redraw when nothing changed at the rendered precision.
		if absf(frac - prev_frac) < 0.005:
			continue
		ring.set_meta("frac", frac)
		ring.queue_redraw()

func _draw_spell_cooldown_ring(node: Node2D) -> void:
	# Sweeps counter-clockwise from full-circle (just fired) to empty
	# (ready). Drawn as a slightly transparent dim arc to read against
	# the spell sprite without hiding it.
	var frac: float = float(node.get_meta("frac", 0.0))
	if frac <= 0.001:
		return
	var size: int = int(node.get_meta("cell_size", 56))
	var r: float = float(size) * 0.50
	# Fill — wedge from -90° (top) sweeping clockwise by `frac × 360`.
	# draw_circle_arc-style polyline approach: build a triangle fan
	# via draw_polygon. Simpler: draw_circle for full, draw_arc for
	# the cut. We ship the dim wedge as a series of triangles via
	# `draw_polygon` which is one draw call.
	var start: float = -PI * 0.5
	var end: float = start + TAU * frac
	var seg: int = maxi(8, int(24.0 * frac))
	var pts := PackedVector2Array()
	pts.append(Vector2.ZERO)
	for i in seg + 1:
		var t: float = float(i) / float(seg)
		var ang: float = lerpf(start, end, t)
		pts.append(Vector2(cos(ang), sin(ang)) * r)
	var col := Color(0, 0, 0, 0.55)
	var cols := PackedColorArray()
	for i in pts.size():
		cols.append(col)
	node.draw_polygon(pts, cols)
	# Outline arc — soft amber sweep mirroring the wedge edge so the
	# cooldown is visible even at a glance.
	var arc_col := Color(0.92, 0.78, 0.45, 0.85)
	node.draw_arc(Vector2.ZERO, r - 1.5, start, end, seg, arc_col, 2.0, true)

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
	# Park the Dump-floor button + status label below the debug text.
	# Cheap layout — only updates when the line count changes since
	# debug_lbl.size auto-resizes to its content.
	if debug_dump_btn != null and is_instance_valid(debug_dump_btn) and debug_lbl != null:
		var by: float = debug_lbl.position.y + debug_lbl.size.y + 4.0
		debug_dump_btn.position = Vector2(6, by)
		if debug_dump_status != null and is_instance_valid(debug_dump_status) and debug_dump_status.visible:
			debug_dump_status.position = Vector2(6, by + debug_dump_btn.size.y + 2.0)
