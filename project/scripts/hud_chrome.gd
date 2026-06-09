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
# BAG_H sized to fit a header+chip row + ~3 visible rows of 48px cells.
# Was 340 which left ~42px black at the bottom (rounded-down visible_rows
# math). 2026-06-06 second pass: 240 = 32 (chip row) + 3 × 52 (rows of
# INV_CELL_SIZE=48 + 4 sep) + 8 padding + 8 trailing. Frees ~100px
# upward for the paperdoll panel which was bottoming out at the 36px
# slot floor and clipping the spell row off-screen.
const BAG_H := 240
# Ultrawide cap — beyond this canvas width the bag stops stretching and
# centers, leaving wider play area on the sides. Picked at 1600 because
# the project's design viewport is 1600×900 — anyone running narrower
# than that gets full-width bag (no clamp), anyone running wider gets
# the bag centered above a wider visible battlefield.
const BAG_MAX_W := 1600

# Live, viewport-sized values — set in _build_sidebar from
# UILayout.sidebar_width(view). Replaces the hardcoded SIDEBAR_W in
# the build path so ultrawide / smaller windows scale cleanly.
# UI polish pass 2026-06-04.
var _sidebar_w: int = SIDEBAR_W
var _minimap_size: int = MINIMAP_SIZE

const PAPERDOLL_SLOT_SIZE := 48
# When the paperdoll panel is taller than the 48px-slot layout needs,
# we let slots grow up to this larger ceiling instead of leaving black
# padding at the bottom. UI overhaul 2026-06-06.
const PAPERDOLL_SLOT_MAX := 72
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

# Always-visible header labels (above the tab container). The tabs
# themselves use StatPanel; only the name + HP-bar header has bespoke
# Label refs since they live OUTSIDE any tab and remain visible no
# matter which tab is active.
var lbl_name: Label
var lbl_hp: Label
var hp_bar_fill: ColorRect
var hp_bar_bg: ColorRect

# Per-section clipping panels. Every dynamic widget lives inside one of
# these so long item/affix/weapon names can't bleed past their section.
# UI overhaul 2026-06-06.
var _sidebar_root: Control = null      # full sidebar — clip_contents on
var _minimap_panel: Control = null     # holds minimap + dot + stairs
var _stats_panel: Control = null       # holds name/HP header + tabs
var _paperdoll_panel: Control = null   # holds equipment header + paperdoll + slot cells
var _bag_panel: Control = null         # holds inventory + filter chips
var _stats_tabs: TabContainer = null   # in-sidebar Stats/Weapon/Buffs
var _stats_tab_page: Control = null
var _weapon_tab_page: Control = null
var _buffs_tab_page: Control = null
# Pooled buff-tab rows — same trick as the buff bar pool. Each row:
# {row, name_lbl, time_lbl, icon}.
var _buff_tab_rows: Array = []
const BUFF_TAB_MAX := 14
const STATS_TAB_HEADER_H := 28
const HUD_CLIP_BORDER_COL := Color(0.35, 0.30, 0.18, 0.5)
const HUD_HEADER_H := 56  # name+lv line + HP bar + HP text rows

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

# Bag (bottom strip). Single flat GridContainer holds every inventory
# cell; filter chips control visibility per-cell. The legacy
# inventory_box VBox is gone — kept the var name as a redirect to the
# grid in case any external caller still pokes it (none in repo).
var inventory_scroll: ScrollContainer
var inventory_grid: GridContainer
var _inv_columns: int = 6
var _pending_scroll_restore: int = 0
# In-run inventory filter — mirrors the outpost rarity filter chip
# row. Read state.loot_filter at build, write back on chip click. The
# auto-pickup filter and the visibility filter share this key so
# changing either side stays consistent.
var _bag_filter_rarity: String = "common"
var _bag_filter_slot: String = "all"
var _bag_filter_chips: Array = []  # [{btn, id}]
const _BAG_FILTER_OPTIONS := [
	{ "id": "common",    "label": "All",       "min_rank": 0 },
	{ "id": "uncommon",  "label": "Uncommon+", "min_rank": 1 },
	{ "id": "rare",      "label": "Rare+",     "min_rank": 2 },
	{ "id": "epic",      "label": "Epic+",     "min_rank": 3 },
	{ "id": "legendary", "label": "Legendary", "min_rank": 4 },
]
# Slot filter — mirrors outpost.gd::_SLOT_FILTER_OPTIONS so the player
# uses the same dropdown shape between screens.
const _BAG_SLOT_FILTER_OPTIONS := [
	{ "id": "all",    "label": "All slots" },
	{ "id": "weapon", "label": "Weapon" },
	{ "id": "armor",  "label": "Armor" },
	{ "id": "helm",   "label": "Helm" },
	{ "id": "shield", "label": "Shield" },
	{ "id": "boots",  "label": "Boots" },
	{ "id": "gloves", "label": "Gloves" },
	{ "id": "cloak",  "label": "Cloak" },
	{ "id": "ring",   "label": "Ring" },
	{ "id": "amulet", "label": "Amulet" },
	{ "id": "spell",  "label": "Spells" },
]
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
# F8 Stat-Rollup Inspector (S3.5 / a06 §4.1). Read-only debug panel that
# renders the full StatCalc.compute output dict — every accumulator,
# soft-cap clamps, per-element resists. Toggles visibility on F8; never
# rebuilt mid-frame (cheap enough to render text in-place).
var _stat_inspector_panel: Control = null
var _stat_inspector_label: Label = null
var _stat_inspector_visible: bool = false

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
	_build_layout()
	if DragManager and not DragManager.drag_ended.is_connected(_on_drag_ended):
		DragManager.drag_ended.connect(_on_drag_ended)
	# NOTE: deliberately NOT subscribing to viewport size_changed during
	# play. Pre-2026-06-06 the HUD only built once and never reflowed.
	# Adding a resize listener caused 1-second freezes in-run (rebuilding
	# 100+ Controls every time something perturbs viewport reporting).
	# The HUD builds correctly on first ready() with the actual viewport
	# size (which `expand` aspect now provides), and the player rarely
	# resizes the window mid-run. Outpost still subscribes for between-
	# run resize; HUD doesn't.

func _build_layout() -> void:
	_build_minimap_overlay()  # top-left, small — must build BEFORE sidebar so
	#                            sidebar code knows minimap_root exists.
	_build_sidebar()
	_build_bag()
	if VideoSettings.hud_log_overlay():
		_build_log_overlay()
	_build_debug()
	_build_buff_bar()
	_build_stat_inspector()

# F8 unhandled-input gate — only toggles the inspector when no UI element
# is consuming the key. Lives on the HUD because the dungeon scene owns
# this CanvasLayer at run time; outpost / character_create don't need
# the inspector.
func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var k: InputEventKey = event
	if not k.pressed or k.echo:
		return
	if k.keycode == KEY_F8:
		_toggle_stat_inspector()
		get_viewport().set_input_as_handled()

func _on_viewport_resized() -> void:
	# Tear down + rebuild. Caches that point at the old node tree must be
	# cleared too — dungeon.gd will re-fire update_stats / update_equipped
	# / update_inventory_segments on the next frame, populating the new
	# tree. Worst case: one frame of stale visuals during the rebuild.
	for child in get_children():
		if child is Timer:
			continue
		child.queue_free()
	equipped_cells.clear()
	_buff_cells.clear()
	_buff_tab_rows.clear()
	_bag_filter_chips.clear()
	_flat_inv_cells.clear()
	# Null out node refs so the next update_stats / update_equipped /
	# update_buffs path either no-ops or rebuilds onto the fresh tree.
	paperdoll_holder = null
	paperdoll_rig = null
	inventory_scroll = null
	inventory_grid = null
	_minimap_panel = null
	_sidebar_root = null
	_stats_panel = null
	_paperdoll_panel = null
	_bag_panel = null
	_stats_tabs = null
	_stats_tab_page = null
	_weapon_tab_page = null
	_buffs_tab_page = null
	_weapon_tab_tooltip = null
	_weapon_tab_empty = null
	_buff_bar_root = null
	debug_lbl = null
	debug_dump_btn = null
	debug_dump_status = null
	# Diff caches refer to the old node tree — reset so the next update_*
	# call rebuilds onto the fresh tree instead of skipping with stale state.
	_last_rig_hash = -1
	_last_weapon_iid = "<unset>"
	_last_buffs_hash = -1
	_build_layout()

func _exit_tree() -> void:
	if DragManager and DragManager.drag_ended.is_connected(_on_drag_ended):
		DragManager.drag_ended.disconnect(_on_drag_ended)

# WoW-style tooltip — main panel only (no shift-compare in-run; that's
# an outpost-level ritual). Item-overhaul v2 2026-06-04.
var _hud_tooltip: ItemTooltip = null
var _hud_hover_cell: ItemCell = null
# Shift-compare panels — sibling tooltips spawned when Shift is held
# while hovering an inventory cell, mirroring the outpost pattern.
# 2026-06-07 user catch: was missing on HUD, only worked in outpost.
var _hud_compare_tooltips: Array = []
var _hud_shift_was_held: bool = false
var _hud_alt_was_held: bool = false

func _on_cell_tooltip(cell: ItemCell, show: bool) -> void:
	if not show:
		_hud_hover_cell = null
		if _hud_tooltip != null and is_instance_valid(_hud_tooltip):
			_hud_tooltip.queue_free()
			_hud_tooltip = null
		_hud_destroy_compare_tooltips()
		return
	_hud_hover_cell = cell
	if _hud_tooltip != null and is_instance_valid(_hud_tooltip):
		_hud_tooltip.queue_free()
	_hud_tooltip = ItemTooltip.new()
	add_child(_hud_tooltip)
	_hud_tooltip.render_for(cell.item, cell.inst, _items_db_cache)
	_hud_tooltip.position = _hud_clamp_tooltip(get_viewport().get_mouse_position() + Vector2(16, 16))
	if UILayout.shift_held():
		_hud_show_compare_tooltips(cell)
		_hud_shift_was_held = true

# Per-frame poll for Alt-key state so the extended-affix view toggles
# live while the tooltip is up. CanvasLayer doesn't tick by default —
# the existing _process call in dungeon.gd handles game logic, so we
# add a lightweight _process here just for tooltip state.
func _process(_delta: float) -> void:
	# Keep the fullscreen button anchored to the viewport's right edge.
	# CanvasLayer doesn't auto-reflow on browser-window resize.
	if _fullscreen_btn != null and is_instance_valid(_fullscreen_btn):
		var vp: Vector2 = get_viewport().get_visible_rect().size
		var target_x: float = vp.x - 40
		if absf(_fullscreen_btn.position.x - target_x) > 1.0:
			_fullscreen_btn.position.x = target_x
	if _hud_hover_cell == null or not is_instance_valid(_hud_hover_cell):
		return
	if _hud_tooltip == null or not is_instance_valid(_hud_tooltip):
		return
	var alt_now: bool = UILayout.alt_held()
	if alt_now != _hud_alt_was_held:
		_hud_tooltip.render_for(_hud_hover_cell.item, _hud_hover_cell.inst, _items_db_cache)
		_hud_alt_was_held = alt_now
	# Shift-compare: spawn / dismiss compare panels live as Shift is
	# pressed / released. Mirrors outpost behavior. 2026-06-07.
	var shift_now: bool = UILayout.shift_held()
	if shift_now and not _hud_shift_was_held:
		_hud_show_compare_tooltips(_hud_hover_cell)
	elif not shift_now and _hud_shift_was_held:
		_hud_destroy_compare_tooltips()
	_hud_shift_was_held = shift_now

func _hud_show_compare_tooltips(cell: ItemCell) -> void:
	_hud_destroy_compare_tooltips()
	# Only compare gear from inventory; paperdoll-on-paperdoll compare
	# is redundant. Spells skip per design.
	if cell == null or not is_instance_valid(cell):
		return
	if cell.role != "inventory":
		return
	var item_slot: String = String(cell.item.get("slot", ""))
	if item_slot == "" or item_slot == "spell":
		return
	# Resolve equipped instance for the same slot. Bot is the source
	# of truth — equip_request_target points at the dungeon which
	# owns bot. Fall back to nothing if we can't reach it.
	if equip_request_target == null or not is_instance_valid(equip_request_target):
		return
	if not "bot" in equip_request_target:
		return
	var bot_ref = equip_request_target.bot
	if bot_ref == null or not is_instance_valid(bot_ref):
		return
	var slot_ids: Array = []
	if item_slot == "ring":
		slot_ids = SpeciesData.ring_slot_ids(_active_species)
	else:
		slot_ids = [item_slot]
	# Decide left/right placement based on screen real estate.
	var view: Vector2 = get_viewport().get_visible_rect().size
	var t_right_edge: float = _hud_tooltip.position.x + ItemTooltip.TOOLTIP_W
	var place_right: bool = t_right_edge + 8.0 + ItemTooltip.TOOLTIP_W <= view.x - 4.0
	var x_offset: float = ItemTooltip.TOOLTIP_W + 8.0 if place_right else -(ItemTooltip.TOOLTIP_W + 8.0)
	var y_offset: float = 0.0
	for sid in slot_ids:
		var equipped_inst: Variant = bot_ref.equipped.get(sid, null)
		if equipped_inst == null or typeof(equipped_inst) != TYPE_DICTIONARY:
			continue
		var equipped_id: String = String(equipped_inst.get("base_id", ""))
		if not _items_db_cache.has(equipped_id):
			continue
		var cmp := ItemTooltip.new()
		add_child(cmp)
		cmp.render_for(_items_db_cache[equipped_id], equipped_inst, _items_db_cache)
		var pos: Vector2 = _hud_tooltip.position + Vector2(x_offset, y_offset)
		pos.x = clampf(pos.x, 4.0, max(4.0, view.x - ItemTooltip.TOOLTIP_W - 4.0))
		pos.y = clampf(pos.y, 4.0, max(4.0, view.y - 220.0))
		cmp.position = pos
		_hud_compare_tooltips.append(cmp)
		y_offset += 220.0

func _hud_destroy_compare_tooltips() -> void:
	for t in _hud_compare_tooltips:
		if t != null and is_instance_valid(t):
			t.queue_free()
	_hud_compare_tooltips.clear()

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

const MINIMAP_OVERLAY_SIZE := 160
const MINIMAP_OVERLAY_PAD := 6

# Top-left minimap overlay — moved out of the sidebar 2026-06-06 so the
# sidebar can give its full vertical to stats + paperdoll. WoW-style
# fixed-size minimap pinned above the play area.
func _build_minimap_overlay() -> void:
	_minimap_size = MINIMAP_OVERLAY_SIZE
	_minimap_panel = Control.new()
	_minimap_panel.position = Vector2(MINIMAP_OVERLAY_PAD, MINIMAP_OVERLAY_PAD)
	_minimap_panel.size = Vector2(MINIMAP_OVERLAY_SIZE, MINIMAP_OVERLAY_SIZE)
	_minimap_panel.clip_contents = true
	_minimap_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_minimap_panel)
	# Slight dark backdrop so the minimap reads against bright biome
	# floors (lava/ice). Lower alpha than COL_PANEL since this overlay
	# sits over the dungeon canvas.
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.55)
	bg.size = Vector2(MINIMAP_OVERLAY_SIZE, MINIMAP_OVERLAY_SIZE)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_minimap_panel.add_child(bg)
	var border := ReferenceRect.new()
	border.size = Vector2(MINIMAP_OVERLAY_SIZE, MINIMAP_OVERLAY_SIZE)
	border.border_color = COL_PANEL_BORDER
	border.border_width = 1.0
	border.editor_only = false
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_minimap_panel.add_child(border)
	minimap_root = TextureRect.new()
	minimap_root.position = Vector2(2, 2)
	minimap_root.size = Vector2(MINIMAP_OVERLAY_SIZE - 4, MINIMAP_OVERLAY_SIZE - 4)
	minimap_root.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	minimap_root.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	minimap_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_minimap_panel.add_child(minimap_root)
	minimap_stairs = ColorRect.new()
	minimap_stairs.color = Color(1.0, 0.9, 0.2)
	minimap_stairs.size = Vector2(4, 4)
	minimap_stairs.visible = false
	_minimap_panel.add_child(minimap_stairs)
	minimap_dot = ColorRect.new()
	minimap_dot.color = Color(0.4, 1.0, 1.0)
	minimap_dot.size = Vector2(5, 5)
	_minimap_panel.add_child(minimap_dot)

func _build_sidebar() -> void:
	# Sidebar layout — top to bottom (post-minimap-relocation 2026-06-06):
	#   [Stats panel]    name/Lv + HP bar header + TabContainer (Stats/Weapon/Buffs)
	#   [Paperdoll panel] equipment grid + spell row
	# Minimap moved out to a top-left overlay (see _build_minimap_overlay).
	# Each panel is its own Control with clip_contents=true so dynamic
	# strings can never bleed past the panel rect.
	var view := get_viewport().get_visible_rect().size
	_sidebar_w = UILayout.sidebar_width(view)
	var x0: int = int(view.x) - _sidebar_w

	# Sidebar root — contains all sidebar widgets so clip_contents on the
	# root catches anything that escapes a child panel's bounds.
	_sidebar_root = Control.new()
	_sidebar_root.position = Vector2(x0, 0)
	_sidebar_root.size = Vector2(_sidebar_w, view.y)
	_sidebar_root.clip_contents = true
	_sidebar_root.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_sidebar_root)

	# Background fill + left border (sit inside the sidebar root so they
	# scroll/resize as one unit).
	var bg := ColorRect.new()
	bg.color = COL_PANEL
	bg.size = Vector2(_sidebar_w, view.y)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sidebar_root.add_child(bg)
	var border := ColorRect.new()
	border.color = COL_PANEL_BORDER
	border.size = Vector2(2, view.y)
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sidebar_root.add_child(border)

	# Geometry — sidebar fills the full screen height. Bag (bottom strip)
	# only covers the LEFT canvas, not the sidebar column, so paperdoll
	# can extend all the way down to view.y. Stats panel takes the upper
	# ~55% of the sidebar; paperdoll anchors to view.y with the rest.
	# UI consistency pass 2026-06-06.
	var sidebar_h: int = int(view.y)
	var stats_h: int = clampi(int(sidebar_h * 0.55), HUD_HEADER_H + 220, HUD_HEADER_H + 360)
	var paperdoll_top: int = stats_h
	var paperdoll_h: int = sidebar_h - paperdoll_top

	# === Stats panel: always-visible header + tab container ===
	_stats_panel = _make_clip_panel(0, 0, _sidebar_w, stats_h, _sidebar_root)
	_build_stats_pane(_sidebar_w, stats_h)

	# === Paperdoll panel ===
	_paperdoll_panel = _make_clip_panel(0, paperdoll_top, _sidebar_w, paperdoll_h, _sidebar_root)
	_build_paperdoll(0, 0, paperdoll_h)

# Helper: build a sidebar sub-panel that clips its contents. Caller
# parents children to the returned Control with panel-local coords.
func _make_clip_panel(x: int, y: int, w: int, h: int, parent: Node) -> Control:
	var panel := Control.new()
	panel.position = Vector2(x, y)
	panel.size = Vector2(w, h)
	panel.clip_contents = true
	panel.mouse_filter = Control.MOUSE_FILTER_PASS
	parent.add_child(panel)
	return panel

# Always-visible HP/name header + Stats/Weapon/Buffs TabContainer.
# Lives inside _stats_panel so all coords are panel-local (0..w, 0..h).
func _build_stats_pane(w: int, h: int) -> void:
	var inner_x: int = SIDEBAR_PAD
	var inner_w: int = w - SIDEBAR_PAD * 2
	# Always-visible header — name+lv on top line, HP text + HP bar below.
	# These remain visible no matter which tab is active.
	lbl_name = _add_label_to(_stats_panel, "Adventurer", inner_x, 4, 16, COL_AMBER)
	lbl_name.size = Vector2(inner_w, 22)
	lbl_name.clip_text = true
	lbl_hp = _add_label_to(_stats_panel, "HP: 100/100", inner_x, 26, 13, COL_HP)
	lbl_hp.size = Vector2(inner_w, 18)
	lbl_hp.clip_text = true
	hp_bar_bg = ColorRect.new()
	hp_bar_bg.color = Color(0.18, 0.05, 0.05, 1.0)
	hp_bar_bg.position = Vector2(inner_x, 44)
	hp_bar_bg.size = Vector2(inner_w, 6)
	hp_bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stats_panel.add_child(hp_bar_bg)
	hp_bar_fill = ColorRect.new()
	hp_bar_fill.color = COL_HP
	hp_bar_fill.position = Vector2(inner_x, 44)
	hp_bar_fill.size = Vector2(inner_w, 6)
	hp_bar_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stats_panel.add_child(hp_bar_fill)

	# Tab container — fills the panel below the header.
	var tabs_y: int = HUD_HEADER_H
	var tabs_h: int = h - HUD_HEADER_H - 4
	_stats_tabs = TabContainer.new()
	_stats_tabs.position = Vector2(inner_x, tabs_y)
	_stats_tabs.size = Vector2(inner_w, tabs_h)
	_stats_tabs.tabs_visible = true
	_stats_tabs.clip_contents = true
	_stats_panel.add_child(_stats_tabs)

	var page_w: int = inner_w
	var page_h: int = tabs_h - STATS_TAB_HEADER_H
	_build_stats_tab(page_w, page_h)
	_build_weapon_tab(page_w, page_h)
	_build_buffs_tab(page_w, page_h)

var _stat_panel_widget: StatPanel = null

func _build_stats_tab(w: int, h: int) -> void:
	# Stats tab — fully delegated to the shared StatPanel widget. Same
	# panel the outpost uses, fed by the same StatCalc.compute output,
	# so HUD and outpost can never disagree on the numbers.
	_stats_tab_page = _make_tab_page("Stats", w, h)
	_stat_panel_widget = StatPanel.new()
	_stat_panel_widget.position = Vector2(0, 0)
	_stat_panel_widget.size = Vector2(w, h)
	_stat_panel_widget.editable = false
	_stats_tab_page.add_child(_stat_panel_widget)

func _build_weapon_tab(w: int, h: int) -> void:
	# Weapon tab embeds a live ItemTooltip — the same widget hover-tooltips
	# use over inventory cells. Single renderer for "describe an item",
	# wrapped in a ScrollContainer so very long affix lists scroll instead
	# of bleeding past the tab.
	_weapon_tab_page = _make_tab_page("Weapon", w, h)
	var scroll := ScrollContainer.new()
	scroll.name = "weapon_scroll"
	scroll.position = Vector2(0, 0)
	scroll.size = Vector2(w, h)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_weapon_tab_page.add_child(scroll)

func _build_buffs_tab(w: int, h: int) -> void:
	_buffs_tab_page = _make_tab_page("Buffs", w, h)
	# Pre-pool BUFF_TAB_MAX rows so update_buffs just toggles visibility
	# + mutates labels — same pattern as the buff bar.
	var row_h: int = 26
	for i in BUFF_TAB_MAX:
		var row := Control.new()
		row.position = Vector2(4, 4 + i * (row_h + 2))
		row.size = Vector2(w - 8, row_h)
		row.visible = false
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.clip_contents = true
		var icon := TextureRect.new()
		icon.position = Vector2(0, 1)
		icon.size = Vector2(row_h - 2, row_h - 2)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		row.add_child(icon)
		var name_lbl := Label.new()
		name_lbl.position = Vector2(row_h + 4, 4)
		name_lbl.size = Vector2(w - row_h - 60, 18)
		name_lbl.clip_text = true
		name_lbl.add_theme_font_size_override("font_size", 12)
		name_lbl.add_theme_color_override("font_color", COL_AMBER)
		row.add_child(name_lbl)
		var time_lbl := Label.new()
		time_lbl.position = Vector2(w - 56, 4)
		time_lbl.size = Vector2(48, 18)
		time_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		time_lbl.clip_text = true
		time_lbl.add_theme_font_size_override("font_size", 12)
		time_lbl.add_theme_color_override("font_color", COL_DIM)
		row.add_child(time_lbl)
		_buffs_tab_page.add_child(row)
		_buff_tab_rows.append({"row": row, "icon": icon, "name_lbl": name_lbl, "time_lbl": time_lbl})

func _make_tab_page(title: String, w: int, h: int) -> Control:
	var page := Control.new()
	page.name = title
	page.custom_minimum_size = Vector2(w, h)
	page.size = Vector2(w, h)
	page.clip_contents = true
	_stats_tabs.add_child(page)
	return page

func _build_paperdoll(_sidebar_x0_unused: int, top_y: int, bottom_y: int) -> void:
	# L-shape: bot sprite top-left, slots run down the right column and across
	# the bottom row. Slots have no on-screen labels — hover for tooltip.
	# Coords are panel-local within _paperdoll_panel (which clips children).
	# 2026-06-06: dropped the "Equipment" header — bot rig art often
	# extends above its anchor (helmets, antennae, headgear) and was
	# visually overlapping the header. The panel's role is self-evident
	# from the rig + slot grid.
	var inner_w: int = _sidebar_w - SIDEBAR_PAD * 2
	var gap: int = 6
	var doll_top: int = top_y + 4
	var doll_left: int = SIDEBAR_PAD
	var available_h: int = bottom_y - doll_top
	# Slot size shrinks to fit BOTH the right column (5 slots) and the
	# bottom row (5 slots) in the available space. Pre-2026-06-05 was
	# a hard 56px which silently dropped the lower right-column slots
	# (gloves/cloak) when sprite_h was constrained. UI polish 2026-06-05.
	const _RIGHT_COLUMN_COUNT := 5  # PAPERDOLL_RIGHT_COLUMN.size()
	const _BOTTOM_ROW_COUNT := 5    # PAPERDOLL_BOTTOM_ROW.size()
	var max_slot_by_w: int = int((inner_w - gap * (_BOTTOM_ROW_COUNT - 1)) / _BOTTOM_ROW_COUNT)
	# Vertical budget: right column slots + bottom row slot + spell row
	# slot + 6×gap + spell-label height (~12px). Layout:
	#   doll_top
	#   ├─ right_col: 5 slots × slot, separated by gap → height = 5*slot + 4*gap
	#   ├─ gap
	#   ├─ bottom_row: 1 slot
	#   ├─ gap
	#   ├─ spell_label_band ~12px (built by the spell label inside the row)
	#   └─ spell_row: 1 slot
	# Total = 7*slot + 6*gap + 12 ≤ available_h
	# Solve: slot ≤ (available_h - 6*gap - 12) / 7
	var max_slot_by_h: int = int((available_h - gap * 6 - 12) / (_RIGHT_COLUMN_COUNT + 2))
	# Slot floor: 30 so the spell row doesn't get clipped off the bottom
	# on a tight panel. Ceiling: PAPERDOLL_SLOT_MAX (72) on roomy panels —
	# was PAPERDOLL_SLOT_SIZE (48) but on tall sidebars (e.g. 1600×1039
	# from `expand` aspect on a M3 MBP 14") that left ~110px black under
	# the paperdoll. Letting slots grow eats the space without a
	# centering hack.
	var slot: int = clampi(mini(max_slot_by_w, max_slot_by_h), 30, PAPERDOLL_SLOT_MAX)
	# Right column width = slot. Sprite width fills remaining inner_w.
	var sprite_w: int = inner_w - slot - gap
	var sprite_h: int = slot * _RIGHT_COLUMN_COUNT + gap * (_RIGHT_COLUMN_COUNT - 1)
	# Sprite frame top-left (panel-local coords inside _paperdoll_panel)
	var sprite_box := ColorRect.new()
	sprite_box.color = Color(0, 0, 0, 0.35)
	sprite_box.position = Vector2(doll_left, doll_top)
	sprite_box.size = Vector2(sprite_w, sprite_h)
	sprite_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_paperdoll_panel.add_child(sprite_box)
	# The paperdoll holder draws the bot rig (base + gear overlays) at the
	# native 32×32 art size, scaled to fit. update_equipped rebuilds the rig
	# from the renderer so what's shown matches the in-game bot.
	# Anchor uses panel-local coords; clip_contents on _paperdoll_panel
	# keeps any oversized rig overlay from leaking past the panel edge.
	var fit: float = float(mini(sprite_w, sprite_h)) / float(PAPERDOLL_BASE_PX)
	paperdoll_rig_scale = floor(fit) if fit >= 1.0 else fit
	paperdoll_rig_scale = max(paperdoll_rig_scale, 1.0)
	paperdoll_rig_anchor = Vector2(doll_left + sprite_w / 2.0, doll_top + sprite_h / 2.0)
	paperdoll_holder = Node2D.new()
	paperdoll_holder.position = paperdoll_rig_anchor
	paperdoll_holder.scale = Vector2(paperdoll_rig_scale, paperdoll_rig_scale)
	_paperdoll_panel.add_child(paperdoll_holder)
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
	# Right column slots — the slot-shrink math above guarantees fit.
	var right_x: int = doll_left + sprite_w + gap
	for i in resolved_right.size():
		var sy_i: int = doll_top + i * (slot + gap)
		_make_paperdoll_slot(resolved_right[i], right_x, sy_i, slot)
	# Bottom row slots.
	var row_y: int = doll_top + sprite_h + gap
	for i in resolved_bottom.size():
		var rx: int = doll_left + i * (slot + gap)
		_make_paperdoll_slot(resolved_bottom[i], rx, row_y, slot)
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
	cell.slot_label = _tooltip_for_slot(slot_id)
	cell.blocked = is_placeholder
	cell.position = Vector2(x, y)
	cell.accepts_drop = Callable(self, "_paperdoll_accepts_drop").bind(slot_id)
	cell.on_left_click = Callable(self, "_on_paperdoll_left_click")
	cell.tooltip_owner = Callable(self, "_on_cell_tooltip")
	_paperdoll_panel.add_child(cell)
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
	var raw_canvas_w: int = int(view.x) - _sidebar_w
	# Ultrawide handling: cap the bag at a sensible max width and center
	# it horizontally over the play canvas. The play area itself stays
	# full width (more battlefield = good on a 32:9 ultrawide), so the
	# bag floats above a wider visible dungeon. UI 2026-06-06.
	var canvas_w: int = mini(raw_canvas_w, BAG_MAX_W)
	var bag_x: int = (raw_canvas_w - canvas_w) / 2
	# Bag panel — clipped Control so inventory cells, filter chips, and
	# header all live inside a clean rect. UI overhaul 2026-06-06.
	_bag_panel = Control.new()
	_bag_panel.position = Vector2(bag_x, view.y - BAG_H)
	_bag_panel.size = Vector2(canvas_w, BAG_H)
	_bag_panel.clip_contents = true
	_bag_panel.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_bag_panel)
	var bg := ColorRect.new()
	bg.color = COL_PANEL
	bg.size = Vector2(canvas_w, BAG_H)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bag_panel.add_child(bg)
	var border := ColorRect.new()
	border.color = COL_PANEL_BORDER
	border.size = Vector2(canvas_w, 2)
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bag_panel.add_child(border)

	# Header + filter row layout:
	#   [Inventory] [Slot ▼] [All | Uncommon+ | Rare+ | Epic+ | Legendary]
	var invx: int = SIDEBAR_PAD
	var invy: int = SIDEBAR_PAD
	var hdr_lbl := Label.new()
	hdr_lbl.text = "Inventory"
	hdr_lbl.position = Vector2(invx, invy)
	hdr_lbl.size = Vector2(80, 22)
	hdr_lbl.clip_text = true
	hdr_lbl.add_theme_font_size_override("font_size", 13)
	hdr_lbl.add_theme_color_override("font_color", COL_DIM)
	_bag_panel.add_child(hdr_lbl)
	# Slot dropdown — mirror outpost. State is in-run only (no persist).
	var slot_dd := OptionButton.new()
	slot_dd.position = Vector2(invx + 90, invy - 2)
	slot_dd.size = Vector2(120, 24)
	slot_dd.add_theme_font_size_override("font_size", 11)
	for i in _BAG_SLOT_FILTER_OPTIONS.size():
		var opt: Dictionary = _BAG_SLOT_FILTER_OPTIONS[i]
		slot_dd.add_item(String(opt.label))
		slot_dd.set_item_metadata(i, String(opt.id))
	slot_dd.select(0)
	slot_dd.item_selected.connect(_on_bag_slot_filter_changed.bind(slot_dd))
	_bag_panel.add_child(slot_dd)
	# Rarity chip row — one selected at a time via ButtonGroup so only
	# one can be pressed and the active one is always visible.
	# Selecting a chip filters the visible inventory cells; data model is
	# untouched. State persists via state.loot_filter (same key the outpost
	# uses) so the in-game filter and the auto-pickup filter stay in sync.
	var chips_x: int = invx + 220
	_build_bag_filter_chips(chips_x, invy, canvas_w - chips_x - SIDEBAR_PAD)

	# Single flat scroll grid for all inventory items, newest at bottom.
	# Drops the prior per-floor segment headers — clutter that grew with
	# every floor descended. Items still live segmented in dungeon's
	# `_loot_segments`; this is a render flatten only. UI overhaul 2026-06-06.
	var grid_y: int = invy + 28
	inventory_scroll = ScrollContainer.new()
	inventory_scroll.position = Vector2(invx, grid_y)
	# Use the FULL available bag height. Pre-2026-06-06 we floored to a
	# whole-row multiple, leaving ~36px black dead space at the bottom of
	# the bag. The last row partially renders into the panel which the
	# user can still see (partial row = "more below, scroll"); much
	# better signal than empty black.
	var scroll_h: int = BAG_H - grid_y - SIDEBAR_PAD
	inventory_scroll.size = Vector2(canvas_w - invx - SIDEBAR_PAD, scroll_h)
	inventory_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_bag_panel.add_child(inventory_scroll)
	# GridContainer holds every visible inventory cell (filter applies
	# render-time visibility). Replaces the old VBox-of-segments layout.
	inventory_grid = GridContainer.new()
	inventory_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inventory_grid.add_theme_constant_override("h_separation", 4)
	inventory_grid.add_theme_constant_override("v_separation", 4)
	inventory_grid.columns = max(1, int((canvas_w - invx - SIDEBAR_PAD * 2 - 16) / (INV_CELL_SIZE + 6)))
	inventory_scroll.add_child(inventory_grid)
	_inv_columns = inventory_grid.columns

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
	# Park debug HUD below the minimap — pre-2026-06-06 it lived at
	# (6, 4) but the new top-left minimap occupies that pixel range.
	# Park at a y just below the minimap's bottom edge.
	var debug_top: int = MINIMAP_OVERLAY_PAD * 2 + MINIMAP_OVERLAY_SIZE + 4
	debug_lbl = Label.new()
	debug_lbl.position = Vector2(6, debug_top)
	debug_lbl.add_theme_font_size_override("font_size", 11)
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
	_build_fullscreen_button()

# F8 Stat-Rollup Inspector (S3.5). Read-only debug panel that dumps the
# full StatCalc.compute output dict — every accumulator, every clamped
# resist, the soft-cap-pressure values. Hidden by default; toggle with
# F8. Useful for "did this affix actually wire up?" without reading code.
func _build_stat_inspector() -> void:
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var w: int = mini(int(vp.x) - 80, 520)
	var h: int = mini(int(vp.y) - 80, 640)
	_stat_inspector_panel = Control.new()
	_stat_inspector_panel.position = Vector2(40, 40)
	_stat_inspector_panel.size = Vector2(w, h)
	_stat_inspector_panel.visible = false
	_stat_inspector_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stat_inspector_panel.z_index = 100
	add_child(_stat_inspector_panel)
	var bg := ColorRect.new()
	bg.color = Color(0.0, 0.0, 0.0, 0.92)
	bg.size = Vector2(w, h)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stat_inspector_panel.add_child(bg)
	var border := ReferenceRect.new()
	border.size = Vector2(w, h)
	border.border_color = COL_AMBER
	border.border_width = 1.5
	border.editor_only = false
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stat_inspector_panel.add_child(border)
	var hdr := Label.new()
	hdr.text = "Stat Rollup [F8]"
	hdr.position = Vector2(8, 4)
	hdr.add_theme_font_size_override("font_size", 12)
	hdr.add_theme_color_override("font_color", COL_GOLD)
	_stat_inspector_panel.add_child(hdr)
	# Scrollable text area — set as a Label inside a ScrollContainer so
	# the dict can grow without needing layout math.
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(8, 24)
	scroll.size = Vector2(w - 16, h - 32)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	_stat_inspector_panel.add_child(scroll)
	_stat_inspector_label = Label.new()
	_stat_inspector_label.text = "(no bot)"
	_stat_inspector_label.add_theme_font_size_override("font_size", 11)
	_stat_inspector_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.75))
	_stat_inspector_label.add_theme_font_override("font", _monospace_font())
	_stat_inspector_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stat_inspector_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_stat_inspector_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	scroll.add_child(_stat_inspector_label)

func _toggle_stat_inspector() -> void:
	_stat_inspector_visible = not _stat_inspector_visible
	if _stat_inspector_panel != null and is_instance_valid(_stat_inspector_panel):
		_stat_inspector_panel.visible = _stat_inspector_visible
	# Invalidate the equip-hash gate so update_stats pumps a fresh dict
	# next tick — otherwise toggling on with no equip change leaves the
	# panel stale.
	_last_equip_hash_for_stats = 0

# Pump the latest StatCalc.compute output into the inspector. Cheap when
# the panel is hidden — early-returns before formatting.
func update_stat_inspector(stats: Dictionary) -> void:
	if not _stat_inspector_visible:
		return
	if _stat_inspector_label == null or not is_instance_valid(_stat_inspector_label):
		return
	_stat_inspector_label.text = _format_stat_inspector(stats)

# Render the dict as aligned key=value lines, grouped by section. Soft-
# capped values get an inline "(cap N)" suffix so we can tell at a
# glance whether the value is at or below its ceiling.
func _format_stat_inspector(s: Dictionary) -> String:
	var caps := {
		"crit_chance": 75.0, "haste_pct": 200.0, "evasion": 75.0,
		"lifesteal_pct": 15.0, "spell_damage_pct": 120.0,
		"spell_area_pct": 100.0, "spell_cdr_pct": 50.0,
		"spell_duration_pct": 100.0, "spell_proj_speed_pct": 100.0,
		"spell_proj_bonus": 5.0, "str_spell_dmg_pct": 100.0,
		"dex_spell_dmg_pct": 100.0, "int_spell_dmg_pct": 100.0,
	}
	var sections := [
		["Identity", ["species_id", "level", "xp", "gold"]],
		["Primary",  ["str", "dex", "int", "alloc_str", "alloc_dex", "alloc_int", "unspent_points"]],
		["Vitals",   ["max_hp", "hp_regen", "armor", "evasion"]],
		["Combat",   ["damage_min", "damage_max", "weapon_speed", "weapon_damage_type", "weapon_class", "attack_interval", "crit_chance", "haste_pct", "lifesteal_pct"]],
		["Spell",    ["spell_damage_pct", "spell_cdr_pct", "spell_proj_bonus", "spell_proj_speed_pct", "spell_area_pct", "spell_duration_pct", "str_spell_dmg_pct", "dex_spell_dmg_pct", "int_spell_dmg_pct"]],
		["Misc",     ["move_speed", "aggro_bonus", "loot_rarity_bonus", "xp_gain_pct"]],
	]
	var lines: Array = []
	for sec in sections:
		var title: String = sec[0]
		var keys: Array = sec[1]
		lines.append("[%s]" % title)
		for k in keys:
			var v: Variant = s.get(k, null)
			var v_str: String = _stat_value_repr(v)
			var cap: Variant = caps.get(k, null)
			if cap != null and v != null and (v is float or v is int):
				v_str = "%s   (cap %s)" % [v_str, _stat_value_repr(cap)]
			lines.append("  %s = %s" % [_stat_pad(k, 24), v_str])
		lines.append("")
	# Resistances and per-element spell-pct collapse to a single line each
	# so the panel stays compact.
	var res: Dictionary = s.get("resistances", {})
	if not res.is_empty():
		var parts: Array = []
		for elem in res.keys():
			parts.append("%s=%s" % [elem, _stat_value_repr(res[elem])])
		lines.append("[Resistances]")
		lines.append("  " + ", ".join(parts))
		lines.append("")
	var spe: Dictionary = s.get("spell_element_pct", {})
	if not spe.is_empty():
		var parts2: Array = []
		for elem in spe.keys():
			parts2.append("%s=%s" % [elem, _stat_value_repr(spe[elem])])
		lines.append("[Spell Element %]")
		lines.append("  " + ", ".join(parts2))
		lines.append("")
	var ed: Dictionary = s.get("extra_damage", {})
	if not ed.is_empty():
		lines.append("[Extra Damage]")
		for elem in ed.keys():
			var rng: Dictionary = ed[elem]
			lines.append("  %s = %d-%d" % [_stat_pad(elem, 24), int(rng.get("min", 0)), int(rng.get("max", 0))])
	return "\n".join(lines)

func _stat_value_repr(v: Variant) -> String:
	if v == null:
		return "(null)"
	match typeof(v):
		TYPE_FLOAT:
			return "%.2f" % float(v)
		TYPE_INT:
			return str(int(v))
		TYPE_STRING:
			return String(v)
		TYPE_BOOL:
			return "true" if bool(v) else "false"
	return str(v)

func _stat_pad(s: String, n: int) -> String:
	var out: String = s
	while out.length() < n:
		out += " "
	return out

func _build_fullscreen_button() -> void:
	# Always-visible fullscreen toggle. CanvasLayer ignores Control
	# anchor presets, so position by viewport size directly. We re-place
	# on viewport resize via the existing resize hook.
	var btn := Button.new()
	btn.name = "FullscreenBtn"
	btn.text = "⛶"
	btn.tooltip_text = "Toggle fullscreen"
	btn.add_theme_font_size_override("font_size", 18)
	btn.size = Vector2(32, 32)
	var vp_size: Vector2 = get_viewport().get_visible_rect().size
	btn.position = Vector2(vp_size.x - 40, 6)
	btn.pressed.connect(_toggle_fullscreen)
	add_child(btn)
	UITheme.style_button(btn)
	_fullscreen_btn = btn

var _fullscreen_btn: Button = null

func _toggle_fullscreen() -> void:
	# In HTML5 the browser requires a user-gesture-initiated JS
	# Element.requestFullscreen() — Godot's DisplayServer call won't
	# actually expand the canvas. Use JavaScriptBridge to call the
	# real DOM API directly. Other platforms fall through to the
	# DisplayServer path.
	if OS.has_feature("web"):
		JavaScriptBridge.eval("""
			(function() {
				var canvas = document.querySelector('canvas');
				if (document.fullscreenElement) {
					document.exitFullscreen();
				} else if (canvas) {
					if (canvas.requestFullscreen) canvas.requestFullscreen();
					else if (canvas.webkitRequestFullscreen) canvas.webkitRequestFullscreen();
				}
			})();
		""", true)
		return
	var mode: int = DisplayServer.window_get_mode()
	if mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)

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
var _last_buffs_hash: int = -1

func update_buffs(statuses: Dictionary) -> void:
	if _buff_bar_root == null:
		return
	# Skip the whole pass when nothing changed since last frame. statuses
	# is rebuilt from bot._statuses every dungeon._process tick, so its
	# hash changes only when a buff appears, expires, or its expires_at
	# advances by ≥1 second (rounded for display). When the stable case
	# hits, the entire bar/tab update is a hash compare + early return.
	# Caveat: ticking countdown labels still need to run, so we compute a
	# combined hash that includes ceil(remaining) per buff.
	var now: float = float(Time.get_ticks_msec()) / 1000.0
	var ids: Array = statuses.keys()
	ids.sort_custom(func(a, b):
		var za: int = int(_StatusOverlay.get_def(a).get("z", 0))
		var zb: int = int(_StatusOverlay.get_def(b).get("z", 0))
		return za > zb)
	# Hash combines id list + per-buff ceil(remaining) so countdown
	# changes still trigger an update.
	var h_arr: Array = []
	for id in ids:
		var entry: Dictionary = statuses[id]
		var exp: float = float(entry.get("expires_at", 0.0))
		var secs: int = 0
		if exp > 0.0:
			secs = max(0, int(ceil(exp - now)))
		h_arr.append([id, secs])
	var h: int = h_arr.hash()
	if h == _last_buffs_hash:
		return
	_last_buffs_hash = h
	var view := get_viewport().get_visible_rect().size
	var canvas_w: int = int(view.x) - _sidebar_w
	var n: int = mini(ids.size(), BUFF_BAR_MAX)
	# Center the visible row horizontally above the dungeon canvas.
	var row_w: int = n * BUFF_CELL_SIZE + max(0, n - 1) * BUFF_CELL_GAP
	var start_x: int = max(0, (canvas_w - row_w) / 2)
	for i in BUFF_BAR_MAX:
		var cell_data: Dictionary = _buff_cells[i]
		var ctrl: Control = cell_data["cell"]
		if i >= n:
			if ctrl.visible:
				ctrl.visible = false
			continue
		var id: String = String(ids[i])
		var def: Dictionary = _StatusOverlay.get_def(id)
		var icon: TextureRect = cell_data["icon"]
		# Diff: only refresh icon + tooltip when this cell changes which
		# buff it represents. Was running every frame which triggered a
		# texture binding + tooltip string compose per cell × every frame.
		var prev_id: String = String(cell_data.get("last_id", ""))
		if prev_id != id:
			icon.texture = _StatusOverlay.texture_for(id)
			icon.modulate = def.get("tint", Color(1, 1, 1, 1))
			var label_str: String = String(def.get("label", id.capitalize()))
			var desc_str: String = String(def.get("desc", ""))
			ctrl.tooltip_text = label_str if desc_str.is_empty() else "%s\n%s" % [label_str, desc_str]
			cell_data["last_id"] = id
		var lbl: Label = cell_data["lbl"]
		var entry: Dictionary = statuses[id]
		var expires: float = float(entry.get("expires_at", 0.0))
		var time_str: String
		if expires > 0.0:
			var remaining: float = expires - now
			var secs: int = max(1, int(ceil(remaining)))
			time_str = "%ds" % secs
		else:
			time_str = ""
		if String(cell_data.get("last_time", "")) != time_str:
			lbl.text = time_str
			cell_data["last_time"] = time_str
		var px: float = float(start_x + i * (BUFF_CELL_SIZE + BUFF_CELL_GAP))
		if ctrl.position.x != px:
			ctrl.position = Vector2(px, 0)
		if not ctrl.visible:
			ctrl.visible = true
	# Mirror to the in-sidebar Buffs tab. Same data, list form.
	_update_buffs_tab(ids, statuses, now)

# Buffs tab — text+icon row form of the same data the buff bar shows.
# Diffs against the prior write so we don't trigger a Label relayout
# every frame for unchanged rows. Same diff trick `update_stats` uses.
func _update_buffs_tab(ids: Array, statuses: Dictionary, now: float) -> void:
	if _buff_tab_rows.is_empty():
		return
	var n: int = mini(ids.size(), BUFF_TAB_MAX)
	for i in BUFF_TAB_MAX:
		var refs: Dictionary = _buff_tab_rows[i]
		var row: Control = refs["row"]
		if i >= n:
			if row.visible:
				row.visible = false
			continue
		var id: String = String(ids[i])
		var def: Dictionary = _StatusOverlay.get_def(id)
		var icon: TextureRect = refs["icon"]
		var prev_id: String = String(refs.get("last_id", ""))
		if prev_id != id:
			icon.texture = _StatusOverlay.texture_for(id)
			icon.modulate = def.get("tint", Color(1, 1, 1, 1))
			refs["name_lbl"].text = String(def.get("label", id.capitalize()))
			refs["last_id"] = id
		var time_lbl: Label = refs["time_lbl"]
		var entry: Dictionary = statuses[id]
		var expires: float = float(entry.get("expires_at", 0.0))
		var time_str: String
		if expires > 0.0:
			var remaining: float = expires - now
			var secs: int = max(1, int(ceil(remaining)))
			time_str = "%ds" % secs
		else:
			time_str = ""
		if String(refs.get("last_time", "")) != time_str:
			time_lbl.text = time_str
			refs["last_time"] = time_str
		if not row.visible:
			row.visible = true

func _monospace_font() -> Font:
	# Godot's default monospace font.
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Menlo", "Monaco", "Consolas", "monospace"])
	return f

func _add_label(t: String, x: int, y: int, size: int, color: Color) -> Label:
	return _add_label_to(self, t, x, y, size, color)

# Add a label as a child of `parent` (instead of the HUD root). Use
# this so labels inside per-section panels inherit the panel's
# clip_contents bounds.
func _add_label_to(parent: Node, t: String, x: int, y: int, size: int, color: Color) -> Label:
	var lbl := Label.new()
	lbl.text = t
	lbl.position = Vector2(x, y)
	lbl.add_theme_font_size_override("font_size", size)
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	lbl.add_theme_constant_override("outline_size", 2)
	parent.add_child(lbl)
	return lbl

# ============================================================================
# Public update API — called by dungeon.gd
# ============================================================================

var _last_hp: int = -1
var _last_max_hp: int = -1
var _last_lvl: int = -1
# Stale-period suppressor — feed StatCalc only when an input changed.
# Pre-fix this called SaveState.load_state (file open + JSON parse) plus
# StatCalc.compute every frame even when nothing relevant changed; the
# audit flagged it as the dominant per-frame stall during waves.
var _last_equip_hash_for_stats: int = 0

func update_stats(bot_ref: Bot, place_str: String, _turn: int) -> void:
	# Always-visible header (name + Lv + HP bar) updates per-tick from
	# bot fields. The Stats / Weapon / Buffs tabs rebuild from
	# StatCalc.compute via the StatPanel widget — same dict the outpost
	# uses, so the two screens always agree. Pre-2026-06-06 each layer
	# computed haste differently; that's gone.
	if not is_instance_valid(bot_ref):
		return
	# Always-visible header — name + level.
	var lvl: int = int(bot_ref.level)
	if lvl != _last_lvl:
		lbl_name.text = "Adventurer  Lv %d" % lvl
		_last_lvl = lvl
	if bot_ref.hp != _last_hp or bot_ref.max_hp != _last_max_hp:
		lbl_hp.text = "HP: %d / %d" % [bot_ref.hp, bot_ref.max_hp]
		var hp_pct: float = clampf(float(bot_ref.hp) / maxf(1.0, float(bot_ref.max_hp)), 0.0, 1.0)
		hp_bar_fill.size = Vector2(hp_bar_bg.size.x * hp_pct, hp_bar_bg.size.y)
		hp_bar_fill.color = COL_HP_LOW if hp_pct < 0.3 else COL_HP
		_last_hp = bot_ref.hp
		_last_max_hp = bot_ref.max_hp
	# Stats tab — recompute only when something feeding StatCalc has
	# actually changed. bot.upgrade_state is the live save dict by
	# reference (set in Bot.apply_gear), so we read it directly instead
	# of reopening the JSON file every frame.
	if _stat_panel_widget != null and is_instance_valid(_stat_panel_widget):
		var hash_keys: Array = [
			bot_ref.equipped.hash(),
			bot_ref.upgrade_state.hash(),
			bot_ref.blessings.hash(),
			bot_ref.species_id,
			bot_ref.level, bot_ref.xp, bot_ref.gold,
		]
		var input_hash: int = hash_keys.hash()
		if input_hash != _last_equip_hash_for_stats:
			var stats: Dictionary = StatCalc.compute(
				bot_ref.equipped, _items_db_cache, bot_ref.upgrade_state, bot_ref.species_id,
				bot_ref.level, bot_ref.xp, bot_ref.gold, bot_ref.blessings,
			)
			_stat_panel_widget.render(stats)
			update_stat_inspector(stats)
			_last_equip_hash_for_stats = input_hash

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

const _RIG_OVERLAY_SLOTS := ["weapon", "armor", "helm", "shield", "boots", "gloves", "cloak"]
var _last_rig_hash: int = -1
var _last_weapon_iid: String = "<unset>"

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
	# Rebuild the bot rig only when an OVERLAY slot changed. Equipping a
	# ring/amulet/spell doesn't change the rig — pre-2026-06-06 we still
	# rebuilt + reattached looping tweens which compounded into the equip
	# stutter.
	var rig_keys: Array = []
	for slot_name in _RIG_OVERLAY_SLOTS:
		var rig_inst: Variant = equipped.get(slot_name, null)
		var iid: String = ""
		if typeof(rig_inst) == TYPE_DICTIONARY:
			iid = String(rig_inst.get("instance_id", rig_inst.get("base_id", "")))
		rig_keys.append([slot_name, iid])
	rig_keys.append(species)  # species change reshapes the base sprite
	var rig_hash: int = rig_keys.hash()
	if paperdoll_holder != null and rig_hash != _last_rig_hash:
		if is_instance_valid(paperdoll_rig):
			paperdoll_rig.queue_free()
		# static_only=true: skip the looping glow + hand-pulse tweens
		# on the HUD-side paperdoll. The thumbnail is too small to
		# appreciate the animation and the tweens compound across runs.
		var built: Dictionary = PaperdollRenderer.build_rig(items_db, equipped, species, true)
		paperdoll_rig = built.rig
		paperdoll_holder.add_child(paperdoll_rig)
		_last_rig_hash = rig_hash
	# Rebuild the Weapon tab only when the equipped weapon changed.
	var weapon_inst: Variant = equipped.get("weapon", null)
	var weapon_iid: String = ""
	if typeof(weapon_inst) == TYPE_DICTIONARY:
		weapon_iid = String(weapon_inst.get("instance_id", weapon_inst.get("base_id", "")))
	if weapon_iid != _last_weapon_iid:
		_rebuild_weapon_tab(equipped, items_db)
		_last_weapon_iid = weapon_iid

# Refresh the Weapon tab from the currently-equipped weapon. Reuses
# the in-game ItemTooltip widget so the tab text matches the hover
# tooltip exactly — affixes, traits, iLvl footer, all from one
# renderer. UI consistency pass 2026-06-06.
var _weapon_tab_tooltip: ItemTooltip = null
var _weapon_tab_empty: Label = null

func _rebuild_weapon_tab(equipped: Dictionary, items_db: Dictionary) -> void:
	if _weapon_tab_page == null or not is_instance_valid(_weapon_tab_page):
		return
	var scroll: ScrollContainer = _weapon_tab_page.get_node_or_null("weapon_scroll")
	if scroll == null:
		return
	var weapon_inst: Variant = equipped.get("weapon", null)
	var item: Dictionary = {}
	if typeof(weapon_inst) == TYPE_DICTIONARY:
		item = items_db.get(String(weapon_inst.get("base_id", "")), {})
	if item.is_empty():
		# No weapon → show one-line "No weapon equipped." Tear down the
		# tooltip if it was previously visible.
		if _weapon_tab_tooltip != null and is_instance_valid(_weapon_tab_tooltip):
			_weapon_tab_tooltip.queue_free()
			_weapon_tab_tooltip = null
		if _weapon_tab_empty == null or not is_instance_valid(_weapon_tab_empty):
			_weapon_tab_empty = UITheme.label("No weapon equipped.", UITheme.FS_BODY, COL_DIM)
			_weapon_tab_empty.position = Vector2(8, 8)
			_weapon_tab_empty.size = Vector2(scroll.size.x - 16, 22)
			_weapon_tab_empty.clip_text = true
			scroll.add_child(_weapon_tab_empty)
		return
	# Weapon is equipped — show the ItemTooltip rendering.
	if _weapon_tab_empty != null and is_instance_valid(_weapon_tab_empty):
		_weapon_tab_empty.queue_free()
		_weapon_tab_empty = null
	if _weapon_tab_tooltip == null or not is_instance_valid(_weapon_tab_tooltip):
		_weapon_tab_tooltip = ItemTooltip.new()
		_weapon_tab_tooltip.static_mode = true  # no glow pulse / particles for the embedded tab
		scroll.add_child(_weapon_tab_tooltip)
	_weapon_tab_tooltip.render_for(item, weapon_inst, items_db)

# Flat-grid inventory cache. Each entry: {seg_idx, item_idx, instance_id, cell}.
# Caller (dungeon.gd) still passes segments (a list of {header, items}),
# but we render every item.flatten()ed into one GridContainer with newest
# at the bottom. Filter chips drive cell.visible without re-rendering.
# UI overhaul 2026-06-06.
var _flat_inv_cells: Array = []  # ordered same as the visible grid (seg_idx,item_idx walk forward)

func update_inventory_segments(segments: Array, items_db: Dictionary, slot_cooldowns: Dictionary) -> void:
	if inventory_grid == null:
		return
	# Build the canonical flat list (seg, item, instance_id) in source
	# order — newest segment last, so the freshest items appear at the
	# bottom of the grid where the player's eye lands.
	var fresh_keys: Array = []
	for si in segments.size():
		var items: Array = segments[si].get("items", [])
		for ii in items.size():
			fresh_keys.append({"seg": si, "item": ii, "id": _inst_key(items[ii])})
	# Diff against cached list. Three fast paths cover the common cases
	# without a full teardown — the latter caused visible loot-pickup
	# spikes (each pickup tearing down 100+ ItemCells).
	var prev_n: int = _flat_inv_cells.size()
	var new_n: int = fresh_keys.size()
	var prev_matches_new_prefix: bool = true
	var prefix_len: int = mini(prev_n, new_n)
	for i in prefix_len:
		if String(_flat_inv_cells[i].get("id", "")) != String(fresh_keys[i]["id"]) \
				or int(_flat_inv_cells[i].get("seg", -1)) != int(fresh_keys[i]["seg"]) \
				or int(_flat_inv_cells[i].get("item", -1)) != int(fresh_keys[i]["item"]):
			prev_matches_new_prefix = false
			break
	# Path 1 — same flat list, nothing to do.
	if prev_matches_new_prefix and prev_n == new_n:
		_apply_inventory_filter()
		return
	# Path 2 — append-only (typical loot pickup: 1+ items added at the end).
	# Append cells without touching existing ones. This is the hot path —
	# every loot drop hits this.
	if prev_matches_new_prefix and new_n > prev_n:
		for i in range(prev_n, new_n):
			var entry: Dictionary = fresh_keys[i]
			var si: int = int(entry["seg"])
			var ii: int = int(entry["item"])
			var inst: Variant = segments[si]["items"][ii]
			var cell := _make_inv_button(si, ii, inst, items_db, slot_cooldowns)
			inventory_grid.add_child(cell)
			_flat_inv_cells.append({
				"seg": si, "item": ii, "id": String(entry["id"]),
				"cell": cell, "inst": inst,
			})
		_apply_inventory_filter()
		return
	# Path 3 — single-cell removal (typical equip-swap: an item leaves the
	# inventory). Find the missing index, queue_free that one cell.
	if prev_matches_new_prefix and new_n == prev_n - 1:
		# The first index that differs (or the tail) is where the removal happened.
		_remove_inv_cell_at(prev_n - 1)  # tail removal — fastest case
		_apply_inventory_filter()
		return
	# General mismatch — find the first differing index and surgically
	# remove the cell that disappeared OR rebuild from there.
	var first_diff: int = -1
	for i in prefix_len:
		if String(_flat_inv_cells[i].get("id", "")) != String(fresh_keys[i]["id"]):
			first_diff = i
			break
	if first_diff >= 0 and new_n == prev_n - 1:
		# Single removal at first_diff: cells shifted left by one from there.
		_remove_inv_cell_at(first_diff)
		# Update the seg/item indices on the shifted-left cells so
		# _resolve_flat_index walks the updated list cleanly.
		for i in range(first_diff, _flat_inv_cells.size()):
			var entry: Dictionary = fresh_keys[i]
			var refs: Dictionary = _flat_inv_cells[i]
			refs["seg"] = int(entry["seg"])
			refs["item"] = int(entry["item"])
			refs["id"] = String(entry["id"])
			var cell: Variant = refs.get("cell", null)
			if cell != null and is_instance_valid(cell):
				cell.set_meta("seg_idx", int(entry["seg"]))
				cell.set_meta("item_idx", int(entry["item"]))
				cell.set_meta("instance_id", String(entry["id"]))
		_apply_inventory_filter()
		return
	# Path 4 — swap equip (1 picked, 1 displaced): same total count, but
	# one instance_id disappeared and one new one appeared. Find the
	# missing-from-prev id and the new-in-fresh id; surgically remove
	# the picked cell and append the displaced one. Avoids the full
	# rebuild that was the equip-stutter culprit.
	if new_n == prev_n:
		var prev_ids: Dictionary = {}  # id → flat_idx in prev
		for i in prev_n:
			prev_ids[String(_flat_inv_cells[i].get("id", ""))] = i
		var fresh_ids: Dictionary = {}
		for i in new_n:
			fresh_ids[String(fresh_keys[i]["id"])] = i
		var removed_idx: int = -1
		for id in prev_ids:
			if not fresh_ids.has(id):
				removed_idx = int(prev_ids[id])
				break
		var added_in_fresh: int = -1
		for id in fresh_ids:
			if not prev_ids.has(id):
				added_in_fresh = int(fresh_ids[id])
				break
		# Single swap: exactly one removal, exactly one addition.
		if removed_idx >= 0 and added_in_fresh >= 0:
			# Verify only ONE of each — otherwise it's a multi-shuffle, full rebuild.
			var removed_count: int = 0
			for id in prev_ids:
				if not fresh_ids.has(id):
					removed_count += 1
			var added_count: int = 0
			for id in fresh_ids:
				if not prev_ids.has(id):
					added_count += 1
			if removed_count == 1 and added_count == 1:
				_remove_inv_cell_at(removed_idx)
				# Resync seg/item meta for cells whose flat-index shifted by
				# the removal. The displaced item gets appended at the tail
				# in the data model, so cells from removed_idx onward shift
				# left by one until the very end where we append the new cell.
				for i in range(removed_idx, _flat_inv_cells.size()):
					var entry: Dictionary = fresh_keys[i]
					var refs: Dictionary = _flat_inv_cells[i]
					refs["seg"] = int(entry["seg"])
					refs["item"] = int(entry["item"])
					refs["id"] = String(entry["id"])
					var c: Variant = refs.get("cell", null)
					if c != null and is_instance_valid(c):
						c.set_meta("seg_idx", int(entry["seg"]))
						c.set_meta("item_idx", int(entry["item"]))
						c.set_meta("instance_id", String(entry["id"]))
				# Append the new cell at the tail.
				var tail_entry: Dictionary = fresh_keys[new_n - 1]
				var t_si: int = int(tail_entry["seg"])
				var t_ii: int = int(tail_entry["item"])
				var t_inst: Variant = segments[t_si]["items"][t_ii]
				var new_cell := _make_inv_button(t_si, t_ii, t_inst, items_db, slot_cooldowns)
				inventory_grid.add_child(new_cell)
				_flat_inv_cells.append({
					"seg": t_si, "item": t_ii, "id": String(tail_entry["id"]),
					"cell": new_cell, "inst": t_inst,
				})
				_apply_inventory_filter()
				return
	# Last resort — full rebuild. Reorder events (e.g. cross-segment
	# 2H+shield+other-displacement) end up here. Cost is real but rare.
	var saved_scroll: int = 0
	if inventory_scroll != null:
		saved_scroll = inventory_scroll.scroll_vertical
	for c in inventory_grid.get_children():
		c.queue_free()
	_flat_inv_cells.clear()
	for entry in fresh_keys:
		var si: int = int(entry["seg"])
		var ii: int = int(entry["item"])
		var inst: Variant = segments[si]["items"][ii]
		var cell := _make_inv_button(si, ii, inst, items_db, slot_cooldowns)
		inventory_grid.add_child(cell)
		_flat_inv_cells.append({
			"seg": si, "item": ii, "id": String(entry["id"]),
			"cell": cell, "inst": inst,
		})
	_apply_inventory_filter()
	if inventory_scroll != null and saved_scroll > 0:
		_pending_scroll_restore = saved_scroll
		call_deferred("_apply_scroll_restore")

func _remove_inv_cell_at(idx: int) -> void:
	if idx < 0 or idx >= _flat_inv_cells.size():
		return
	var refs: Dictionary = _flat_inv_cells[idx]
	var cell: Variant = refs.get("cell", null)
	if cell != null and is_instance_valid(cell):
		cell.queue_free()
	_flat_inv_cells.remove_at(idx)

# Build the rarity filter chip row using a ButtonGroup so only one
# chip is pressed at a time. Pre-2026-06-06 we used five independent
# toggle buttons + manual button_pressed gymnastics, which was buggy
# (clicking the active chip "deselected" it leaving zero chips lit).
# State persists via state.loot_filter (shared with auto-pickup).
func _build_bag_filter_chips(x: int, y: int, w: int) -> void:
	# Read the active filter from save state. "common" = show all (rank 0+).
	var state: Dictionary = SaveState.load_state()
	_bag_filter_rarity = String(state.get("loot_filter", "common"))
	var chip_w: int = clampi(int(w / _BAG_FILTER_OPTIONS.size()) - 4, 56, 110)
	var cx: int = x
	var bg_group := ButtonGroup.new()
	bg_group.allow_unpress = false  # one chip is always pressed
	for opt in _BAG_FILTER_OPTIONS:
		var btn := Button.new()
		btn.text = String(opt.label)
		btn.position = Vector2(cx, y - 2)
		btn.size = Vector2(chip_w, 22)
		btn.toggle_mode = true
		btn.button_group = bg_group
		btn.add_theme_font_size_override("font_size", 11)
		btn.button_pressed = (String(opt.id) == _bag_filter_rarity)
		# Use `pressed` (fires when user clicks an UNpressed chip) — the
		# ButtonGroup auto-unsets the previously-pressed chip, so we don't
		# need to walk every chip on each click.
		btn.pressed.connect(_on_bag_rarity_chip_pressed.bind(String(opt.id)))
		_bag_panel.add_child(btn)
		_bag_filter_chips.append({"btn": btn, "id": String(opt.id)})
		cx += chip_w + 4

func _on_bag_rarity_chip_pressed(id: String) -> void:
	if id == _bag_filter_rarity:
		return  # no-op, chip is already active
	_bag_filter_rarity = id
	# Persist — auto-pickup and the visual filter share state.loot_filter
	# so the player's "show me Rare+ chip" mid-run also stops the bot
	# from picking up commons.
	var state: Dictionary = SaveState.load_state()
	state["loot_filter"] = _bag_filter_rarity
	SaveState.save_state(state)
	_apply_inventory_filter()

func _on_bag_slot_filter_changed(idx: int, dd: OptionButton) -> void:
	_bag_filter_slot = String(dd.get_item_metadata(idx))
	_apply_inventory_filter()

# Toggle inventory cell visibility based on active rarity + slot filters.
# Fast: just sets cell.visible — no node creation. Called after every
# rebuild and on filter change.
func _apply_inventory_filter() -> void:
	var min_rank: int = 0
	for opt in _BAG_FILTER_OPTIONS:
		if String(opt.id) == _bag_filter_rarity:
			min_rank = int(opt.min_rank)
			break
	var slot_filter: String = _bag_filter_slot
	for entry in _flat_inv_cells:
		var inst: Variant = entry.get("inst", null)
		var cell: Control = entry.get("cell", null)
		if cell == null or not is_instance_valid(cell):
			continue
		var visible: bool = true
		if typeof(inst) == TYPE_DICTIONARY:
			var item_def: Dictionary = _items_db_cache.get(String(inst.get("base_id", "")), {})
			# Rarity filter.
			if min_rank > 0:
				var rarity: String = String(item_def.get("rarity", "common"))
				var rank: int = int(LootDrop.RARITY_RANK.get(rarity, 0))
				if rank < min_rank:
					visible = false
			# Slot filter — match item.slot, with "spell" matching any
			# spell-class slot via the item's slot value already being "spell".
			if visible and slot_filter != "all":
				var item_slot: String = String(item_def.get("slot", ""))
				if item_slot != slot_filter:
					visible = false
		if cell.visible != visible:
			cell.visible = visible

func _apply_scroll_restore() -> void:
	if inventory_scroll == null or not is_instance_valid(inventory_scroll):
		return
	if _pending_scroll_restore > 0:
		inventory_scroll.scroll_vertical = _pending_scroll_restore
	_pending_scroll_restore = 0

# Identity key for an instance — instance_id when available, else
# (base_id + index) so duplicate-base items still get distinct keys.
func _inst_key(inst: Variant) -> String:
	if typeof(inst) != TYPE_DICTIONARY:
		return ""
	var id: String = String(inst.get("instance_id", ""))
	return id if id != "" else String(inst.get("base_id", ""))

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
# to populate cell.inv_index before begin_drag fires. Walks the
# rendered _flat_inv_cells list (which mirrors the visible grid order)
# for an authoritative flat offset.
func _resolve_flat_index(cell: ItemCell) -> void:
	if not cell.has_meta("instance_id"):
		return
	var iid: String = String(cell.get_meta("instance_id"))
	if iid == "":
		return
	for i in _flat_inv_cells.size():
		if String(_flat_inv_cells[i].get("id", "")) == iid:
			cell.inv_index = i
			return

func _on_hud_inv_left_click(cell: ItemCell) -> void:
	if equip_request_target == null:
		return
	# Guard the meta lookups — paperdoll cells route through the same
	# Callable but only inventory cells set seg_idx/item_idx/instance_id.
	# get_meta on a missing key spams stderr in Godot 4.6 even with a
	# default param.
	if not cell.has_meta("seg_idx") or not cell.has_meta("item_idx"):
		return
	var seg_idx: int = int(cell.get_meta("seg_idx"))
	var item_idx: int = int(cell.get_meta("item_idx"))
	# Verify the (seg_idx, item_idx) still points at the SAME item
	# instance_id the cell was built with. A queue_freed-but-not-yet-
	# deleted cell can fire a second click after equip; without this
	# guard we'd equip whatever slid into that index — feels like
	# item duplication. UI polish 2026-06-04.
	var iid: String = String(cell.get_meta("instance_id")) if cell.has_meta("instance_id") else ""
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

# Cached signature of the last minimap repaint inputs. Skip the 6400
# set_pixel + dict-lookup loop when fog hasn't advanced — biggest
# stutter cost on HTML5 where set_pixel is JS-bound. Native it was
# fine; web at 4× per second adds up.
var _last_minimap_sig: int = 0

func update_minimap(grid: Array, bot_cell: Vector2i, stairs: Vector2i, fog_visible_cells: Dictionary = {}) -> void:
	var h := grid.size()
	var w: int = grid[0].size() if h > 0 else 0
	if w == 0 or h == 0:
		return
	var dims := Vector2i(w, h)
	if _minimap_image == null or dims != _last_grid_dims:
		_minimap_image = Image.create(w, h, false, Image.FORMAT_RGBA8)
		_last_grid_dims = dims
		_last_minimap_sig = 0  # force first paint after dim change
	# Cheap signature: grid hash + fog-revealed cell count is enough
	# to detect "anything visible changed" without comparing pixel-by-
	# pixel. Grid changes on floor descent (rare); fog grows as the
	# bot walks. New cells revealed → count goes up → repaint.
	var sig: int = grid.hash() * 31 + fog_visible_cells.size()
	if sig == _last_minimap_sig:
		# Still repaint dot/stairs positions below — those shift each
		# tick — but skip the per-pixel base layer.
		_paint_minimap_markers(bot_cell, stairs, w, h)
		return
	_last_minimap_sig = sig
	# Re-paint each frame is cheap at 80x80.
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
	_paint_minimap_markers(bot_cell, stairs, w, h)
	return

# Move the bot dot + stairs marker each tick without re-running the
# full pixel paint. Pulled out so the cached-signature path can still
# update positions.
func _paint_minimap_markers(bot_cell: Vector2i, stairs: Vector2i, w: int, h: int) -> void:
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
