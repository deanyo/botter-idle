extends Control

# Rotating-stock shop screen. Refreshes every SHOP_REFRESH_SECS of real
# time (~15 min). Daily modifier biases buy/sell rates and (sometimes)
# stock quality. Player sells from inventory + buys from rotating
# stock. Favorited items are locked from accidental sell-all.
#
# Inspired by:
#   - Melvor Idle's bank tabs (filter chips, lock toggle)
#   - PoE rarity-as-language outline + named items
#   - WoW vendor screen (left=your bag, right=vendor stock, two-column)
#   - RuneScape Grand Exchange's "stock rotates while you're away"
#     rhythm — gives a reason to return between runs.

signal back_pressed

const ITEMS_PATH := "res://data/items.json"
const ITEM_TILE_DIR := "res://assets/tiles/items/"
const SHOP_MODS_PATH := "res://data/shop_modifiers.json"

# Real-time seconds between shop refreshes. 15 min picked so logging
# in once an hour rolls 4 different inventories — frequent enough to
# create anticipation but not so frequent that the player feels they
# missed a window every time.
const SHOP_REFRESH_SECS := 900
const SHOP_STOCK_SIZE := 6

const COL_AMBER := Color(0.92, 0.78, 0.45)
const COL_DIM := Color(0.6, 0.55, 0.4)
const COL_GOLD := Color(1.0, 0.85, 0.3)
const COL_PANEL := Color(0.0, 0.0, 0.0, 0.85)
const COL_PANEL_BORDER := Color(0.35, 0.3, 0.18, 0.65)
const RARITY_COLORS := {
	"common":    Color(0.85, 0.85, 0.85),
	"uncommon":  Color(0.4, 0.7, 1.0),
	"rare":      Color(1.0, 0.9, 0.3),
	"epic":      Color(1.0, 0.5, 0.2),
	"legendary": Color(1.0, 0.3, 0.3),
}
# Salvage values (kept in sync with dungeon.gd::_SALVAGE_VALUES).
# Sell price = 2× salvage × today's shop modifier.
const SALVAGE_VALUES := {
	"common": 2, "uncommon": 6, "rare": 18, "epic": 60, "legendary": 200,
}
const INV_CELL_SIZE := 64
const PANEL_PAD := 16

var state: Dictionary = {}
var items_db: Dictionary = {}
var shop_mods: Array = []

# UI references.
var lbl_gold: Label
var lbl_modifier: Label
var lbl_countdown: Label
var inventory_grid: GridContainer
var stock_grid: GridContainer

func _ready() -> void:
	state = SaveState.load_state()
	items_db = _load_items()
	shop_mods = _load_shop_mods()
	_ensure_shop_state()
	_maybe_refresh_stock()
	_build_layout()
	# Tick the countdown label once a second while the screen is open.
	set_process(true)
	if DragManager and not DragManager.drag_ended.is_connected(_on_drag_ended):
		DragManager.drag_ended.connect(_on_drag_ended)

func _exit_tree() -> void:
	if DragManager and DragManager.drag_ended.is_connected(_on_drag_ended):
		DragManager.drag_ended.disconnect(_on_drag_ended)

# WoW-style tooltip in shop. Same shape as HUD — main panel only.
var _shop_tooltip: ItemTooltip = null

func _on_cell_tooltip(cell: ItemCell, show: bool) -> void:
	if not show:
		if _shop_tooltip != null and is_instance_valid(_shop_tooltip):
			_shop_tooltip.queue_free()
			_shop_tooltip = null
		return
	if _shop_tooltip != null and is_instance_valid(_shop_tooltip):
		_shop_tooltip.queue_free()
	_shop_tooltip = ItemTooltip.new()
	add_child(_shop_tooltip)
	_shop_tooltip.render_for(cell.item, cell.inst, items_db)
	var view: Vector2 = get_viewport().get_visible_rect().size
	var anchor: Vector2 = get_viewport().get_mouse_position() + Vector2(16, 16)
	var sz_w: float = float(ItemTooltip.TOOLTIP_W)
	anchor.x = clampf(anchor.x, 4.0, max(4.0, view.x - sz_w - 4.0))
	anchor.y = clampf(anchor.y, 4.0, max(4.0, view.y - 240.0 - 4.0))
	_shop_tooltip.position = anchor

# Sell drop zone — a Control that accepts dragged inventory items and
# sells them on drop. Wired up by _build_stock_pane in the lower-right
# of the stock column.
var _sell_zone: Control = null
const SELL_ZONE_H := 96
# Refresh-stock cost (gold). Diablo / PoE pattern: cheap enough to use
# but expensive enough to feel like a decision. Scales with player level.
const REFRESH_BASE_COST := 50
func _refresh_stock_cost() -> int:
	var lvl: int = int(state.get("level", 1))
	return REFRESH_BASE_COST + lvl * 25

# DragManager.drag_ended fires whenever a drag releases anywhere.
# Inside the shop, the only valid drop target is the sell zone — drop
# an inventory item there to sell it for gold.
func _on_drag_ended(payload: Dictionary, dropped_on: Variant) -> void:
	if dropped_on == null or not is_instance_valid(dropped_on):
		return
	if dropped_on != _sell_zone:
		return
	if String(payload.get("role", "")) != "inventory":
		return
	_sell_one(int(payload.get("inv_index", -1)))

func _process(_delta: float) -> void:
	if lbl_countdown != null and is_instance_valid(lbl_countdown):
		lbl_countdown.text = _countdown_text()
		# Auto-refresh if the timer ran out while the screen is open.
		if _seconds_until_refresh() <= 0:
			_maybe_refresh_stock(true)
			_render()

func _build_layout() -> void:
	var view := get_viewport().get_visible_rect().size
	# Title bar.
	var title := Label.new()
	title.text = "SHOP"
	title.position = Vector2(0, 12)
	title.size = Vector2(view.x, 36)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", COL_AMBER)
	add_child(title)
	# Back button — top-left.
	var back_btn := Button.new()
	back_btn.text = "← Back"
	back_btn.position = Vector2(20, 16)
	back_btn.size = Vector2(100, 32)
	back_btn.pressed.connect(func(): back_pressed.emit())
	add_child(back_btn)
	# Gold counter — top-right.
	lbl_gold = Label.new()
	lbl_gold.position = Vector2(int(view.x) - 220, 20)
	lbl_gold.size = Vector2(200, 24)
	lbl_gold.add_theme_font_size_override("font_size", 18)
	lbl_gold.add_theme_color_override("font_color", COL_GOLD)
	lbl_gold.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(lbl_gold)
	# Daily-modifier banner.
	var banner_y: int = 60
	var banner_h: int = 64
	_make_panel(PANEL_PAD, banner_y, int(view.x) - PANEL_PAD * 2, banner_h, "Today's Special")
	lbl_modifier = Label.new()
	lbl_modifier.position = Vector2(PANEL_PAD + 16, banner_y + 28)
	lbl_modifier.size = Vector2(int(view.x) - PANEL_PAD * 2 - 280, 32)
	lbl_modifier.add_theme_font_size_override("font_size", 14)
	lbl_modifier.add_theme_color_override("font_color", COL_AMBER)
	add_child(lbl_modifier)
	lbl_countdown = Label.new()
	lbl_countdown.position = Vector2(int(view.x) - PANEL_PAD - 260, banner_y + 28)
	lbl_countdown.size = Vector2(240, 32)
	lbl_countdown.add_theme_font_size_override("font_size", 14)
	lbl_countdown.add_theme_color_override("font_color", COL_DIM)
	lbl_countdown.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(lbl_countdown)
	# Two columns: inventory (left) + stock (right).
	var col_y: int = banner_y + banner_h + 16
	var col_h: int = int(view.y) - col_y - PANEL_PAD
	var col_w: int = int(view.x / 2) - PANEL_PAD - 8
	_build_inventory_pane(PANEL_PAD, col_y, col_w, col_h)
	_build_stock_pane(int(view.x / 2) + 8, col_y, col_w, col_h)
	_render()

func _build_inventory_pane(x: int, y: int, w: int, h: int) -> void:
	_make_panel(x, y, w, h, "Your Inventory — click to sell")
	var hint := Label.new()
	hint.text = "Right-click an item to ★favorite it (locked from sell-all)."
	hint.position = Vector2(x + 16, y + 32)
	hint.size = Vector2(w - 32, 18)
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", COL_DIM)
	add_child(hint)
	# Sell-all-junk button.
	var sell_btn := Button.new()
	sell_btn.text = "Sell all common/uncommon (★ favorites kept)"
	sell_btn.position = Vector2(x + 16, y + h - 44)
	sell_btn.size = Vector2(w - 32, 32)
	sell_btn.add_theme_font_size_override("font_size", 12)
	sell_btn.pressed.connect(_sell_all_junk)
	add_child(sell_btn)
	# Inventory grid.
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(x + 16, y + 56)
	scroll.size = Vector2(w - 32, h - 56 - 52)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	inventory_grid = GridContainer.new()
	inventory_grid.columns = max(1, int((w - 32) / (INV_CELL_SIZE + 8)))
	inventory_grid.add_theme_constant_override("h_separation", 8)
	inventory_grid.add_theme_constant_override("v_separation", 8)
	scroll.add_child(inventory_grid)

func _build_stock_pane(x: int, y: int, w: int, h: int) -> void:
	_make_panel(x, y, w, h, "Today's Stock — click to buy")
	# Refresh-stock button at the top-right of the stock pane.
	var refresh_btn := Button.new()
	var cost: int = _refresh_stock_cost()
	refresh_btn.text = "Refresh stock (%dg)" % cost
	refresh_btn.position = Vector2(x + w - 220, y + 6)
	refresh_btn.size = Vector2(204, 24)
	refresh_btn.add_theme_font_size_override("font_size", 11)
	refresh_btn.tooltip_text = "Reroll today's stock immediately. Costs %dg." % cost
	refresh_btn.pressed.connect(_on_refresh_pressed)
	add_child(refresh_btn)
	# Sell drop zone — bottom of the stock column.
	var zone_y: int = y + h - SELL_ZONE_H - 8
	_sell_zone = Control.new()
	_sell_zone.position = Vector2(x + 16, zone_y)
	_sell_zone.size = Vector2(w - 32, SELL_ZONE_H)
	_sell_zone.mouse_filter = Control.MOUSE_FILTER_STOP
	_sell_zone.tooltip_text = "Drop items here to sell"
	add_child(_sell_zone)
	var zone_bg := ColorRect.new()
	zone_bg.color = Color(0.10, 0.06, 0.02, 0.6)
	zone_bg.size = _sell_zone.size
	zone_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sell_zone.add_child(zone_bg)
	var zone_border := ReferenceRect.new()
	zone_border.size = _sell_zone.size
	zone_border.border_color = COL_GOLD
	zone_border.border_width = 2.0
	zone_border.editor_only = false
	zone_border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sell_zone.add_child(zone_border)
	var zone_lbl := Label.new()
	zone_lbl.text = "💰 SELL ZONE\nDrop items here for gold"
	zone_lbl.size = _sell_zone.size
	zone_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	zone_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	zone_lbl.add_theme_font_size_override("font_size", 14)
	zone_lbl.add_theme_color_override("font_color", COL_GOLD)
	zone_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sell_zone.add_child(zone_lbl)
	# Highlight on drag hover — green if a valid inventory item is being
	# dragged. Listen to the zone's mouse-enter while a drag is active.
	_sell_zone.mouse_entered.connect(_on_sell_zone_enter)
	_sell_zone.mouse_exited.connect(_on_sell_zone_exit)
	# Stock scroll — sits ABOVE the sell zone.
	var scroll_h: int = (zone_y - 8) - (y + 32)
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(x + 16, y + 32)
	scroll.size = Vector2(w - 32, scroll_h)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	stock_grid = GridContainer.new()
	stock_grid.columns = max(1, int((w - 32) / (INV_CELL_SIZE + 8)))
	stock_grid.add_theme_constant_override("h_separation", 8)
	stock_grid.add_theme_constant_override("v_separation", 8)
	scroll.add_child(stock_grid)

func _on_sell_zone_enter() -> void:
	if DragManager and DragManager.is_dragging():
		var p: Dictionary = DragManager.get_payload()
		var ok: bool = String(p.get("role", "")) == "inventory"
		DragManager.set_hover_target(_sell_zone, ok)

func _on_sell_zone_exit() -> void:
	if DragManager:
		DragManager.clear_hover_target(_sell_zone)

# Refresh-stock button: rerolls today's stock immediately for a gold
# fee. Scales with player level so endgame doesn't trivialize the cost.
func _on_refresh_pressed() -> void:
	var cost: int = _refresh_stock_cost()
	if int(state.get("gold", 0)) < cost:
		return
	state["gold"] = int(state.get("gold", 0)) - cost
	# Force-roll fresh stock + new modifier without resetting the
	# countdown timer (player isn't paying for the timer reset).
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	if not shop_mods.is_empty():
		state["shop"]["modifier_id"] = String(shop_mods[rng.randi() % shop_mods.size()].get("id", ""))
	state["shop"]["stock"] = _roll_stock(rng, _modifier_def(String(state["shop"].get("modifier_id", ""))))
	SaveState.save_state(state)
	# Rebuild layout so the refresh button shows the new cost.
	for c in get_children():
		c.queue_free()
	_build_layout()

func _make_panel(x: int, y: int, w: int, h: int, header: String) -> void:
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
	hdr.position = Vector2(x + 12, y + 6)
	hdr.size = Vector2(w - 24, 22)
	hdr.add_theme_font_size_override("font_size", 13)
	hdr.add_theme_color_override("font_color", COL_AMBER)
	add_child(hdr)

# ---- State / refresh ----

func _ensure_shop_state() -> void:
	if not state.has("shop") or typeof(state["shop"]) != TYPE_DICTIONARY:
		state["shop"] = { "last_refresh_ts": 0, "stock": [], "modifier_id": "" }

func _seconds_until_refresh() -> int:
	var now: int = int(Time.get_unix_time_from_system())
	var last: int = int(state["shop"].get("last_refresh_ts", 0))
	return max(0, (last + SHOP_REFRESH_SECS) - now)

func _maybe_refresh_stock(force: bool = false) -> void:
	var now: int = int(Time.get_unix_time_from_system())
	var last: int = int(state["shop"].get("last_refresh_ts", 0))
	# Schema check: if any stock item is missing the current schema
	# stamp, the stock was rolled by an older version (no affixes,
	# old stat shape, etc) — force-refresh so the player isn't stuck
	# with blank items until SHOP_REFRESH_SECS expires.
	var stale: bool = false
	for s in state["shop"].get("stock", []):
		if int(s.get("shop_schema_v", 0)) < _SHOP_SCHEMA_VERSION:
			stale = true
			break
	if stale:
		force = true
	if not force and last > 0 and (now - last) < SHOP_REFRESH_SECS:
		return
	# Roll a fresh modifier and stock list. Modifier rolls before stock
	# so the stock_quality_bonus (e.g. Scarcity) can affect rolls.
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var mod_id: String = ""
	if not shop_mods.is_empty():
		mod_id = String(shop_mods[rng.randi() % shop_mods.size()].get("id", ""))
	state["shop"]["modifier_id"] = mod_id
	state["shop"]["stock"] = _roll_stock(rng, _modifier_def(mod_id))
	state["shop"]["last_refresh_ts"] = now
	SaveState.save_state(state)

func _roll_stock(rng: RandomNumberGenerator, mod_def: Dictionary) -> Array:
	# Pick a level-appropriate rarity for each slot. Higher player
	# level shifts the rarity floor up (similar to Diablo vendor
	# scaling). Scarcity modifier bumps rarity by one tier.
	var quality_bonus: int = int(mod_def.get("stock_quality_bonus", 0))
	var stock: Array = []
	var ids_pool: Array = items_db.keys()
	if ids_pool.is_empty():
		return stock
	# Bias rarity by player level: level 5 ≈ uncommon mostly, level 15 rare, level 25 epic.
	var lvl: int = int(state.get("level", 1))
	for i in SHOP_STOCK_SIZE:
		var r_floor: float = rng.randf() - float(lvl) * 0.015 - float(quality_bonus) * 0.10
		var rarity: String
		if r_floor < 0.02: rarity = "legendary"
		elif r_floor < 0.10: rarity = "epic"
		elif r_floor < 0.30: rarity = "rare"
		elif r_floor < 0.65: rarity = "uncommon"
		else: rarity = "common"
		var pool: Array = []
		for id in ids_pool:
			if String(items_db[id].get("rarity", "")) == rarity:
				pool.append(id)
		if pool.is_empty():
			continue
		var picked: String = String(pool[rng.randi() % pool.size()])
		# Roll affixes the same way the dungeon does so shop items have
		# real stat rolls. Without this, jewelry / spell tomes (which
		# have zero baseline stats by design) show up totally blank.
		var picked_def: Dictionary = items_db[picked]
		var rolled: Array = AffixSystem.roll_affixes_for(picked_def, rng)
		stock.append({
			"base_id": picked,
			"instance_id": "shop_%d_%d" % [int(Time.get_unix_time_from_system()), i],
			"affixes": rolled,
			"shop_schema_v": _SHOP_SCHEMA_VERSION,
		})
	return stock

# Bump this when stock-rolling logic changes so existing saves
# auto-refresh. Item-overhaul v2 (2026-06-04) — shop items now roll
# real affixes instead of being blank.
const _SHOP_SCHEMA_VERSION := 2

# ---- Pricing ----

func _modifier_def(id: String) -> Dictionary:
	for m in shop_mods:
		if String(m.get("id", "")) == id:
			return m
	return {}

# Returns true if today's modifier applies to this item (for buy/sell
# multipliers). A modifier with no slot/rarity gates applies to
# everything.
func _modifier_applies(mod_def: Dictionary, item: Dictionary) -> bool:
	if mod_def.is_empty():
		return false
	if mod_def.has("applies_slot"):
		return String(item.get("slot", "")) == String(mod_def.applies_slot)
	if mod_def.has("applies_slots"):
		var slots: Array = mod_def.applies_slots
		if not (String(item.get("slot", "")) in slots):
			return false
	if mod_def.has("applies_min_rarity"):
		var min_rank: int = int(LootDrop.RARITY_RANK.get(String(mod_def.applies_min_rarity), 0))
		var item_rank: int = int(LootDrop.RARITY_RANK.get(String(item.get("rarity", "common")), 0))
		if item_rank < min_rank:
			return false
	return true

func _sell_price(inst: Dictionary, item: Dictionary) -> int:
	var rarity: String = String(item.get("rarity", "common"))
	var base: int = int(SALVAGE_VALUES.get(rarity, 1)) * 2
	var mult: float = 1.0
	var mod_def: Dictionary = _modifier_def(String(state["shop"].get("modifier_id", "")))
	if _modifier_applies(mod_def, item):
		mult = float(mod_def.get("sell_mult", 1.0))
	return int(round(float(base) * mult))

func _buy_price(item: Dictionary) -> int:
	# Buy price: ~5× sell base so the gold sink is meaningful.
	# Modifier buy_mult multiplies (less-than-1 = discount).
	var rarity: String = String(item.get("rarity", "common"))
	var base: int = int(SALVAGE_VALUES.get(rarity, 1)) * 10
	var mult: float = 1.0
	var mod_def: Dictionary = _modifier_def(String(state["shop"].get("modifier_id", "")))
	if _modifier_applies(mod_def, item):
		mult = float(mod_def.get("buy_mult", 1.0))
	return int(round(float(base) * mult))

# ---- Render ----

func _render() -> void:
	if lbl_gold != null:
		lbl_gold.text = "Gold: %d" % int(state.gold)
	if lbl_modifier != null:
		var mod: Dictionary = _modifier_def(String(state["shop"].get("modifier_id", "")))
		if mod.is_empty():
			lbl_modifier.text = "(no special today)"
		else:
			lbl_modifier.text = "%s — %s" % [String(mod.get("name", "")), String(mod.get("description", ""))]
	_render_inventory()
	_render_stock()

func _render_inventory() -> void:
	if inventory_grid == null:
		return
	for c in inventory_grid.get_children():
		c.queue_free()
	for i in state.inventory.size():
		var inst: Variant = state.inventory[i]
		if typeof(inst) != TYPE_DICTIONARY:
			continue
		var base_id: String = String(inst.get("base_id", ""))
		if not items_db.has(base_id):
			continue
		var item: Dictionary = items_db[base_id]
		inventory_grid.add_child(_make_item_cell(i, inst, item, true))

func _render_stock() -> void:
	if stock_grid == null:
		return
	for c in stock_grid.get_children():
		c.queue_free()
	var stock: Array = state["shop"].get("stock", [])
	for i in stock.size():
		var inst: Variant = stock[i]
		if typeof(inst) != TYPE_DICTIONARY:
			continue
		var base_id: String = String(inst.get("base_id", ""))
		if not items_db.has(base_id):
			continue
		var item: Dictionary = items_db[base_id]
		stock_grid.add_child(_make_item_cell(i, inst, item, false))

func _make_item_cell(idx: int, inst: Dictionary, item: Dictionary, is_inventory: bool) -> Control:
	# Wrapper container so we can stack a price label below the cell.
	var wrapper := Control.new()
	wrapper.custom_minimum_size = Vector2(INV_CELL_SIZE, INV_CELL_SIZE + 18)
	wrapper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cell := ItemCell.new()
	cell.cell_size = INV_CELL_SIZE
	cell.role = "inventory" if is_inventory else "shop"
	cell.inv_index = idx if is_inventory else -1
	cell.shop_index = idx if not is_inventory else -1
	cell.inst = inst
	cell.item = item
	cell.on_left_click = Callable(self, "_on_cell_left_click")
	cell.on_right_click = Callable(self, "_on_cell_right_click")
	cell.tooltip_owner = Callable(self, "_on_cell_tooltip")
	cell.ready.connect(cell.render)
	wrapper.add_child(cell)
	# Price label under the sprite.
	var price: int = _sell_price(inst, item) if is_inventory else _buy_price(item)
	var price_lbl := Label.new()
	price_lbl.text = "%dg" % price
	price_lbl.position = Vector2(0, INV_CELL_SIZE)
	price_lbl.size = Vector2(INV_CELL_SIZE, 16)
	price_lbl.add_theme_font_size_override("font_size", 10)
	price_lbl.add_theme_color_override("font_color", COL_GOLD if is_inventory else COL_AMBER)
	price_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	price_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrapper.add_child(price_lbl)
	return wrapper

# Click handlers — left = sell/buy, right = favorite (inventory only).
func _on_cell_left_click(cell: ItemCell) -> void:
	if cell.role == "inventory":
		_sell_one(cell.inv_index)
	elif cell.role == "shop":
		_buy_one(cell.shop_index)

func _on_cell_right_click(cell: ItemCell) -> void:
	if cell.role == "inventory":
		_toggle_favorite(cell.inv_index)

# ---- Actions ----

func _toggle_favorite(inv_index: int) -> void:
	if inv_index < 0 or inv_index >= state.inventory.size():
		return
	var inst: Variant = state.inventory[inv_index]
	if typeof(inst) != TYPE_DICTIONARY:
		return
	inst["favorite"] = not bool(inst.get("favorite", false))
	state.inventory[inv_index] = inst
	SaveState.save_state(state)
	_render_inventory()

func _sell_one(inv_index: int) -> void:
	if inv_index < 0 or inv_index >= state.inventory.size():
		return
	var inst: Variant = state.inventory[inv_index]
	if typeof(inst) != TYPE_DICTIONARY:
		return
	if bool(inst.get("favorite", false)):
		return  # favorited items are locked
	var base_id: String = String(inst.get("base_id", ""))
	if not items_db.has(base_id):
		return
	var item: Dictionary = items_db[base_id]
	var price: int = _sell_price(inst, item)
	state.inventory.remove_at(inv_index)
	state.gold = int(state.get("gold", 0)) + price
	SaveState.save_state(state)
	_render()

func _sell_all_junk() -> void:
	# Sells common + uncommon items, skipping favorites and starter
	# gear. WoW "sell junk" pattern.
	var starter_ids := ["rusty_dagger", "tattered_hide"]
	var earned: int = 0
	var sold: int = 0
	var i: int = 0
	while i < state.inventory.size():
		var inst: Variant = state.inventory[i]
		if typeof(inst) != TYPE_DICTIONARY:
			i += 1
			continue
		if bool(inst.get("favorite", false)):
			i += 1
			continue
		var base_id: String = String(inst.get("base_id", ""))
		if base_id in starter_ids:
			i += 1
			continue
		if not items_db.has(base_id):
			i += 1
			continue
		var item: Dictionary = items_db[base_id]
		var rarity: String = String(item.get("rarity", "common"))
		if not (rarity == "common" or rarity == "uncommon"):
			i += 1
			continue
		earned += _sell_price(inst, item)
		sold += 1
		state.inventory.remove_at(i)
	if sold > 0:
		state.gold = int(state.get("gold", 0)) + earned
		SaveState.save_state(state)
		_render()

func _buy_one(stock_index: int) -> void:
	var stock: Array = state["shop"].get("stock", [])
	if stock_index < 0 or stock_index >= stock.size():
		return
	var inst: Variant = stock[stock_index]
	if typeof(inst) != TYPE_DICTIONARY:
		return
	var base_id: String = String(inst.get("base_id", ""))
	if not items_db.has(base_id):
		return
	var item: Dictionary = items_db[base_id]
	var price: int = _buy_price(item)
	if int(state.get("gold", 0)) < price:
		return
	state.gold = int(state.gold) - price
	state.inventory.append(inst.duplicate(true))
	stock.remove_at(stock_index)
	state["shop"]["stock"] = stock
	SaveState.save_state(state)
	_render()

# ---- Helpers ----

func _countdown_text() -> String:
	var s: int = _seconds_until_refresh()
	var m: int = s / 60
	var ss: int = s % 60
	return "Next refresh in %d:%02d" % [m, ss]

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

func _load_shop_mods() -> Array:
	var f := FileAccess.open(SHOP_MODS_PATH, FileAccess.READ)
	if f == null:
		return []
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return []
	return parsed.get("modifiers", [])
