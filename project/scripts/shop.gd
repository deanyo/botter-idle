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
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(x + 16, y + 32)
	scroll.size = Vector2(w - 32, h - 44)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	stock_grid = GridContainer.new()
	stock_grid.columns = max(1, int((w - 32) / (INV_CELL_SIZE + 8)))
	stock_grid.add_theme_constant_override("h_separation", 8)
	stock_grid.add_theme_constant_override("v_separation", 8)
	scroll.add_child(stock_grid)

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
		stock.append({
			"base_id": picked,
			"instance_id": "shop_%d_%d" % [int(Time.get_unix_time_from_system()), i],
			"affixes": [],
		})
	return stock

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
	var rarity: String = String(item.get("rarity", "common"))
	var cell := Control.new()
	cell.custom_minimum_size = Vector2(INV_CELL_SIZE, INV_CELL_SIZE + 18)
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.45)
	bg.size = Vector2(INV_CELL_SIZE, INV_CELL_SIZE)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(bg)
	var halo: float = {
		"common": 0.0, "uncommon": 0.18, "rare": 0.30,
		"epic": 0.42, "legendary": 0.55,
	}.get(rarity, 0.0)
	UITheme.add_item_cell_decor(cell, INV_CELL_SIZE, rarity, UITheme.combined_flavor_tags(item, inst), halo)
	# Sprite.
	var sprite := TextureRect.new()
	sprite.size = Vector2(INV_CELL_SIZE, INV_CELL_SIZE)
	sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tile_path: String = ITEM_TILE_DIR + String(item.get("tile", ""))
	if ResourceLoader.exists(tile_path):
		sprite.texture = load(tile_path)
	sprite.modulate = UITheme.item_modulate(rarity, UITheme.combined_flavor_tags(item, inst))
	cell.add_child(sprite)
	# Price label below the sprite.
	var price: int = _sell_price(inst, item) if is_inventory else _buy_price(item)
	var price_lbl := Label.new()
	price_lbl.text = "%dg" % price
	price_lbl.position = Vector2(0, INV_CELL_SIZE)
	price_lbl.size = Vector2(INV_CELL_SIZE, 16)
	price_lbl.add_theme_font_size_override("font_size", 10)
	price_lbl.add_theme_color_override("font_color", COL_GOLD if is_inventory else COL_AMBER)
	price_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	price_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(price_lbl)
	# Click handler.
	var btn := Button.new()
	btn.size = Vector2(INV_CELL_SIZE, INV_CELL_SIZE)
	btn.flat = true
	btn.tooltip_text = AffixSystem.format_item_tooltip(item, inst)
	if is_inventory:
		btn.tooltip_text += "\n\n[click] Sell for %dg\n[right-click] Toggle ★ favorite" % price
		btn.pressed.connect(_sell_one.bind(idx))
		btn.gui_input.connect(_on_inv_input.bind(idx))
	else:
		btn.tooltip_text += "\n\n[click] Buy for %dg" % price
		btn.pressed.connect(_buy_one.bind(idx))
	cell.add_child(btn)
	# Favorite star (inventory only).
	if is_inventory:
		var star := Label.new()
		star.text = "★"
		star.add_theme_font_size_override("font_size", 18)
		star.add_theme_color_override("font_color", Color(1.0, 0.85, 0.30, 1.0))
		star.position = Vector2(INV_CELL_SIZE - 22, -4)
		star.size = Vector2(22, 22)
		star.mouse_filter = Control.MOUSE_FILTER_IGNORE
		star.modulate = Color(1, 1, 1, 1.0 if bool(inst.get("favorite", false)) else 0.0)
		cell.add_child(star)
	return cell

# ---- Actions ----

func _on_inv_input(event: InputEvent, inv_index: int) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb: InputEventMouseButton = event
	if not mb.pressed:
		return
	if mb.button_index == MOUSE_BUTTON_RIGHT:
		_toggle_favorite(inv_index)

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
