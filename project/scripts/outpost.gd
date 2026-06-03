extends Control

# Outpost — pre-run loadout screen. Three-pane DCSS chrome:
#   left: paperdoll (matches HUD), center: stats + biographical text,
#   right: inventory icon grid (rarity-bordered, tooltip on hover).
# Bottom strip is a tier-grouped branch picker: clicking a branch deploys
# directly. Locked branches grey out with their unlock condition.
# Built in code so it can mirror the HUD's L-shape paperdoll geometry.

signal deploy_pressed(branch_id: String)

# Doc Appendix B mapping. Mirrors main.gd's _TIER_BRANCHES — kept in sync
# manually because GDScript's class members can't share consts cleanly.
const TIER_BRANCHES := {
	1: ["dungeon", "dungeon_dark", "mines"],
	2: ["lair", "forest", "orc", "temple"],
	3: ["shoals", "swamp", "snake", "spider", "hive"],
	4: ["vaults", "crypt", "tomb", "elf", "depths"],
	5: ["forge", "glacier", "slime", "labyrinth", "abyss", "pandemonium", "zot"],
}
const TIER_LABELS := {
	1: "Tier 1 — The Dungeon",
	2: "Tier 2 — The Surface",
	3: "Tier 3 — The Wilds",
	4: "Tier 4 — The Vaults",
	5: "Tier 5 — The Planes",
}

const ITEMS_PATH := "res://data/items.json"
const ITEM_TILE_DIR := "res://assets/tiles/items/"

const SLOTS := ["weapon", "armor", "helm", "boots", "shield", "ring", "amulet"]
const PAPERDOLL_RIGHT_COLUMN := ["helm", "amulet", "cloak", "gloves", "belt"]
const PAPERDOLL_BOTTOM_ROW := ["weapon", "armor", "shield", "ring", "boots"]
const SLOT_TOOLTIPS := {
	"weapon": "Weapon", "armor": "Body Armor", "helm": "Helm",
	"shield": "Shield", "boots": "Boots",
	"amulet": "Amulet", "cloak": "Cloak", "gloves": "Gloves",
	"belt": "Belt", "ring": "Ring",
}
const PAPERDOLL_BASE_PX := 32

const PAPERDOLL_SLOT_SIZE := 56
const INV_CELL_SIZE := 64
const PANEL_PAD := 16

# Colors mirror UITheme — see hud_chrome.gd note for why these are inline.
const COL_AMBER := Color(0.92, 0.78, 0.45)
const COL_DIM := Color(0.7, 0.6, 0.4)
const COL_GOLD := Color(1.0, 0.85, 0.3)
const COL_PANEL := Color(0.04, 0.04, 0.06, 0.85)
const COL_PANEL_BORDER := Color(0.35, 0.3, 0.18, 0.65)
const COL_BG := Color(0.05, 0.05, 0.07, 1.0)
const RARITY_COLORS := {
	"common":    Color(0.85, 0.85, 0.85),
	"uncommon":  Color(0.4, 0.7, 1.0),
	"rare":      Color(1.0, 0.9, 0.3),
	"epic":      Color(1.0, 0.5, 0.2),
	"legendary": Color(1.0, 0.3, 0.3),
}

var items_db: Dictionary = {}
var state: Dictionary = {}

# Paperdoll cells (slot → control refs).
var equipped_cells: Array = []
var paperdoll_holder: Node2D
var paperdoll_rig: Node2D = null
# Stats labels.
var lbl_name: Label
var lbl_level: Label
var lbl_xp: Label
var lbl_hp: Label
var lbl_atk: Label
var lbl_def: Label
var lbl_crit: Label
var lbl_haste: Label
var lbl_regen: Label
var lbl_gold: Label
var lbl_floor: Label
# Inventory grid.
var inventory_grid: GridContainer

func _ready() -> void:
	items_db = _load_items()
	state = SaveState.load_state()
	_reroll_branch_modifiers()
	_build_layout()
	_render()

# Per-Outpost-visit modifier roll. Every unlocked branch gets a fresh
# 1-2 modifier set; the player picks based on what tonight's offer
# looks like. Persists to save so a re-render uses the same set.
func _reroll_branch_modifiers() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var unlocked: Array = state.get("unlocked_branches", ["dungeon"])
	var rolled: Dictionary = {}
	for branch_id in unlocked:
		rolled[String(branch_id)] = RunModifiers.roll_for_branch(String(branch_id), rng)
	state["branch_modifiers"] = rolled
	SaveState.save_state(state)

func _build_layout() -> void:
	var view := get_viewport().get_visible_rect().size
	# Background.
	var bg := ColorRect.new()
	bg.color = COL_BG
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	add_child(bg)
	# Title bar.
	var title := Label.new()
	title.text = "OUTPOST"
	title.position = Vector2(0, 12)
	title.size = Vector2(view.x, 36)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", COL_AMBER)
	add_child(title)
	# Branch picker at bottom — replaces the single Deploy button. Each
	# branch is a button; clicking deploys directly to that branch.
	var picker_h := 96
	_build_branch_picker(0, int(view.y) - picker_h - 8, int(view.x), picker_h)
	# Three panes between title (y≈56) and the picker.
	var top_y: int = 60
	var bottom_y: int = int(view.y) - picker_h - 24
	var pane_h: int = bottom_y - top_y
	# Pane widths: 32% left, 30% center, 38% right.
	var left_w: int = int(view.x * 0.32)
	var center_w: int = int(view.x * 0.30)
	var right_w: int = int(view.x) - left_w - center_w - PANEL_PAD * 4
	var x: int = PANEL_PAD
	_build_paperdoll_pane(x, top_y, left_w, pane_h)
	x += left_w + PANEL_PAD
	_build_stats_pane(x, top_y, center_w, pane_h)
	x += center_w + PANEL_PAD
	_build_inventory_pane(x, top_y, right_w, pane_h)

func _build_branch_picker(x: int, y: int, w: int, h: int) -> void:
	_make_panel(x, y, w, h, "Deploy — choose a branch")
	# Horizontal scroll so all 24 branches fit even at narrow widths.
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(x + 12, y + 28)
	scroll.size = Vector2(w - 24, h - 36)
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 24)
	scroll.add_child(hbox)
	var unlocked: Array = state.get("unlocked_branches", ["dungeon"])
	for tier in [1, 2, 3, 4, 5]:
		hbox.add_child(_make_tier_column(tier, unlocked))

func _make_tier_column(tier: int, unlocked: Array) -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	var hdr := Label.new()
	hdr.text = String(TIER_LABELS.get(tier, "Tier %d" % tier))
	hdr.add_theme_font_size_override("font_size", 11)
	hdr.add_theme_color_override("font_color", COL_DIM)
	col.add_child(hdr)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	col.add_child(row)
	for branch_id in TIER_BRANCHES.get(tier, []):
		row.add_child(_make_branch_button(branch_id, unlocked.has(branch_id)))
	return col

func _make_branch_button(branch_id: String, is_unlocked: bool) -> Button:
	# Button is the outer node so the whole cell (name + modifier strip)
	# is one click target. The display label is set as the Button's text;
	# modifier strip is a child Label drawn over the button face.
	var b := Button.new()
	b.custom_minimum_size = Vector2(150, 64)
	# Display name from biomes.json — falls back to capitalised id.
	# biomes use "the Dungeon" style names; trim the article for buttons.
	var biome: Dictionary = BiomeData.get_biome(branch_id)
	var display: String = String(biome.get("display_name", branch_id.capitalize()))
	if display.to_lower().begins_with("the "):
		display = display.substr(4)
	var pretty: String = display.capitalize() if display == display.to_lower() else display
	b.add_theme_font_size_override("font_size", 13)
	# Modifier strip — pulled from save.branch_modifiers, set on Outpost open.
	var mods: Array = state.get("branch_modifiers", {}).get(branch_id, [])
	var mod_brief: String = RunModifiers.format_brief(mods) if is_unlocked else ""
	if is_unlocked:
		# Full text: name on top, dim modifier line below. Use Button.text
		# for the name + a child Label for the colored modifier strip so
		# the modifier line can be a different color.
		b.text = pretty
		b.alignment = HORIZONTAL_ALIGNMENT_CENTER
		var tooltip: String = "%s (CR %d recommended)" % [display, int(biome.get("cr_recommended", 0))]
		var mod_tip: String = RunModifiers.format_tooltip(mods)
		if mod_tip != "":
			tooltip += "\n\n" + mod_tip
		b.tooltip_text = tooltip
		b.pressed.connect(func(): deploy_pressed.emit(branch_id))
		if mod_brief != "":
			var mod_lbl := Label.new()
			mod_lbl.text = mod_brief
			mod_lbl.position = Vector2(4, 38)
			mod_lbl.size = Vector2(142, 24)
			mod_lbl.add_theme_font_size_override("font_size", 10)
			mod_lbl.add_theme_color_override("font_color", COL_AMBER)
			mod_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			mod_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			mod_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			b.add_child(mod_lbl)
	else:
		b.text = pretty
		b.disabled = true
		b.tooltip_text = "%s — locked. Clear all branches in the previous tier to unlock." % display
	return b

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
	border.border_width = 2.0
	border.editor_only = false
	add_child(border)
	if header != "":
		var lbl := Label.new()
		lbl.text = header
		lbl.position = Vector2(x + 12, y + 8)
		lbl.add_theme_font_size_override("font_size", 14)
		lbl.add_theme_color_override("font_color", COL_DIM)
		add_child(lbl)

func _build_paperdoll_pane(x: int, y: int, w: int, h: int) -> void:
	_make_panel(x, y, w, h, "Equipment")
	var slot := PAPERDOLL_SLOT_SIZE
	var gap := 8
	var inner_x := x + 16
	var inner_y := y + 36
	var inner_w := w - 32
	var inner_h := h - 52
	# Sprite top-left, right column slots, bottom row slots.
	var sprite_w: int = inner_w - slot - gap
	var sprite_h: int = inner_h - slot - gap
	# Bot sprite frame.
	var sprite_box := ColorRect.new()
	sprite_box.color = Color(0, 0, 0, 0.35)
	sprite_box.position = Vector2(inner_x, inner_y)
	sprite_box.size = Vector2(sprite_w, sprite_h)
	add_child(sprite_box)
	# Layered bot rig — same renderer the in-game bot uses, scaled to fit.
	var fit: float = float(mini(sprite_w, sprite_h)) / float(PAPERDOLL_BASE_PX)
	var rig_scale: float = floor(fit) if fit >= 1.0 else fit
	rig_scale = max(rig_scale, 1.0)
	paperdoll_holder = Node2D.new()
	paperdoll_holder.position = Vector2(inner_x + sprite_w / 2.0, inner_y + sprite_h / 2.0)
	paperdoll_holder.scale = Vector2(rig_scale, rig_scale)
	add_child(paperdoll_holder)
	# Right column.
	var right_x: int = inner_x + sprite_w + gap
	var col_count: int = mini(PAPERDOLL_RIGHT_COLUMN.size(), maxi(1, sprite_h / (slot + gap)))
	for i in col_count:
		var slot_id: String = PAPERDOLL_RIGHT_COLUMN[i]
		_make_paperdoll_slot(slot_id, right_x, inner_y + i * (slot + gap))
	# Bottom row.
	var row_y: int = inner_y + sprite_h + gap
	var row_count: int = mini(PAPERDOLL_BOTTOM_ROW.size(), maxi(1, inner_w / (slot + gap)))
	for i in row_count:
		var slot_id: String = PAPERDOLL_BOTTOM_ROW[i]
		_make_paperdoll_slot(slot_id, inner_x + i * (slot + gap), row_y)

func _make_paperdoll_slot(slot_id: String, x: int, y: int) -> void:
	var slot := PAPERDOLL_SLOT_SIZE
	var is_placeholder: bool = not (slot_id in SLOTS)
	var slot_bg := ColorRect.new()
	slot_bg.color = Color(0, 0, 0, 0.55) if not is_placeholder else Color(0, 0, 0, 0.30)
	slot_bg.position = Vector2(x, y)
	slot_bg.size = Vector2(slot, slot)
	add_child(slot_bg)
	var slot_border := ReferenceRect.new()
	slot_border.position = Vector2(x, y)
	slot_border.size = Vector2(slot, slot)
	slot_border.border_color = Color(0.4, 0.35, 0.2, 0.8) if not is_placeholder else Color(0.25, 0.22, 0.14, 0.55)
	slot_border.border_width = 1.0
	slot_border.editor_only = false
	add_child(slot_border)
	var btn := Button.new()
	btn.position = Vector2(x, y)
	btn.size = Vector2(slot, slot)
	btn.flat = true
	btn.tooltip_text = SLOT_TOOLTIPS.get(slot_id, slot_id.capitalize())
	if not is_placeholder:
		btn.pressed.connect(_unequip.bind(slot_id))
	else:
		btn.disabled = true
	add_child(btn)
	var sprite := TextureRect.new()
	sprite.position = Vector2(x + 6, y + 6)
	sprite.size = Vector2(slot - 12, slot - 12)
	sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(sprite)
	equipped_cells.append({
		"slot": slot_id, "sprite": sprite, "btn": btn, "border": slot_border,
		"is_placeholder": is_placeholder,
	})

func _build_stats_pane(x: int, y: int, w: int, h: int) -> void:
	_make_panel(x, y, w, h, "Bot")
	var sx: int = x + 16
	var sy: int = y + 40
	lbl_name = _add_stat(sx, sy, 22, COL_AMBER, "Bot the Adventurer"); sy += 30
	lbl_level = _add_stat(sx, sy, 16, COL_DIM, "Level —"); sy += 22
	lbl_xp = _add_stat(sx, sy, 14, COL_DIM, "XP —"); sy += 22
	lbl_floor = _add_stat(sx, sy, 14, COL_DIM, "Highest floor: —"); sy += 30
	# Stat block.
	var hdr := Label.new()
	hdr.text = "Stats"
	hdr.position = Vector2(sx, sy)
	hdr.add_theme_font_size_override("font_size", 13)
	hdr.add_theme_color_override("font_color", COL_DIM)
	add_child(hdr); sy += 22
	lbl_hp = _add_stat(sx, sy, 18, COL_AMBER, "HP —"); sy += 24
	lbl_atk = _add_stat(sx, sy, 18, COL_AMBER, "ATK —"); sy += 24
	lbl_def = _add_stat(sx, sy, 18, COL_AMBER, "DEF —"); sy += 24
	lbl_crit = _add_stat(sx, sy, 16, COL_DIM, "Crit —"); sy += 22
	lbl_haste = _add_stat(sx, sy, 16, COL_DIM, "Haste —"); sy += 22
	lbl_regen = _add_stat(sx, sy, 16, COL_DIM, "Regen —"); sy += 22
	lbl_gold = _add_stat(sx, sy, 16, COL_GOLD, "Gold —"); sy += 30
	# Bot instructions — loot filter dictates what the bot bothers picking
	# up during a run. Auto-salvage uses the same threshold to convert
	# overflow loot to gold when the inventory cap is hit.
	var instr_hdr := Label.new()
	instr_hdr.text = "Bot Instructions"
	instr_hdr.position = Vector2(sx, sy)
	instr_hdr.add_theme_font_size_override("font_size", 13)
	instr_hdr.add_theme_color_override("font_color", COL_DIM)
	add_child(instr_hdr); sy += 22
	var filter_lbl := _add_stat(sx, sy, 13, COL_DIM, "Pick up:"); sy += 18
	filter_lbl.size = Vector2(w - 32, 18)
	var filter_btn := OptionButton.new()
	filter_btn.position = Vector2(sx, sy)
	filter_btn.size = Vector2(w - 32, 28)
	for filter_name in ["Common+ (everything)", "Uncommon+", "Rare+", "Epic+", "Legendary only"]:
		filter_btn.add_item(filter_name)
	var filter_idx: int = LootDrop.RARITY_RANK.get(String(state.get("loot_filter", "common")), 0)
	filter_btn.selected = filter_idx
	filter_btn.item_selected.connect(_on_loot_filter_changed)
	add_child(filter_btn); sy += 32
	# Inventory cap readout (folds in Pouch upgrade contribution).
	var inv_count: int = int(state.get("inventory", []).size())
	var cap: int = int(state.get("inventory_cap", 50)) + int(BotUpgrades.total_for_stat(state, "inventory_cap"))
	var inv_lbl := _add_stat(sx, sy, 13, COL_DIM, "Inventory: %d / %d" % [inv_count, cap]); sy += 28
	inv_lbl.size = Vector2(w - 32, 18)
	# Upgrades panel — gold-sink permanent purchases. Lives in the rest
	# of the stats column; scrolls if it overflows.
	_build_upgrades_section(sx, sy, w - 32, y + h - sy - 16)

# Tracks the upgrade rows so refresh can update them in-place after a buy
# without rebuilding the whole pane. Keyed by upgrade id.
var _upgrade_rows: Dictionary = {}

func _build_upgrades_section(x: int, y: int, w: int, h: int) -> void:
	var hdr := Label.new()
	hdr.text = "Upgrades"
	hdr.position = Vector2(x, y)
	hdr.add_theme_font_size_override("font_size", 13)
	hdr.add_theme_color_override("font_color", COL_DIM)
	add_child(hdr)
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(x, y + 22)
	scroll.size = Vector2(w, max(0, h - 22))
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	scroll.add_child(box)
	for def in BotUpgrades.all():
		box.add_child(_make_upgrade_row(def))

func _make_upgrade_row(def: Dictionary) -> Control:
	var row := PanelContainer.new()
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 2)
	row.add_child(inner)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	inner.add_child(top)
	var name_lbl := Label.new()
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.add_theme_font_size_override("font_size", 13)
	name_lbl.add_theme_color_override("font_color", COL_AMBER)
	top.add_child(name_lbl)
	var rank_lbl := Label.new()
	rank_lbl.add_theme_font_size_override("font_size", 12)
	rank_lbl.add_theme_color_override("font_color", COL_DIM)
	top.add_child(rank_lbl)
	var desc_lbl := Label.new()
	desc_lbl.add_theme_font_size_override("font_size", 11)
	desc_lbl.add_theme_color_override("font_color", COL_DIM)
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inner.add_child(desc_lbl)
	var btn := Button.new()
	btn.add_theme_font_size_override("font_size", 12)
	inner.add_child(btn)
	var id: String = String(def.id)
	btn.pressed.connect(_on_upgrade_buy.bind(id))
	var refs: Dictionary = {
		"row": row, "name": name_lbl, "rank": rank_lbl,
		"desc": desc_lbl, "btn": btn,
	}
	_upgrade_rows[id] = refs
	_refresh_upgrade_row(id)
	return row

func _refresh_upgrade_row(id: String) -> void:
	var refs: Dictionary = _upgrade_rows.get(id, {})
	if refs.is_empty():
		return
	var def: Dictionary = BotUpgrades.get_def(id)
	if def.is_empty():
		return
	var owned: Dictionary = state.get("bot_upgrades", {})
	var rank: int = int(owned.get(id, 0))
	var max_rank: int = int(def.get("max_rank", 0))
	var name_lbl: Label = refs.name
	var rank_lbl: Label = refs.rank
	var desc_lbl: Label = refs.desc
	var btn: Button = refs.btn
	name_lbl.text = String(def.name)
	rank_lbl.text = "%d / %d" % [rank, max_rank]
	desc_lbl.text = String(def.desc)
	var cost: int = BotUpgrades.next_rank_cost(state, id)
	if cost < 0:
		btn.text = "MAXED"
		btn.disabled = true
	else:
		btn.text = "Buy — %dg" % cost
		btn.disabled = int(state.get("gold", 0)) < cost

func _on_upgrade_buy(id: String) -> void:
	if not BotUpgrades.try_buy(state, id):
		return
	SaveState.save_state(state)
	# Refresh the bought row + the gold readout + every other row's button
	# (gold may have crossed below another upgrade's threshold).
	_refresh_upgrade_row(id)
	for other_id in _upgrade_rows.keys():
		if other_id != id:
			_refresh_upgrade_row(other_id)
	if lbl_gold:
		lbl_gold.text = "Gold %d" % int(state.gold)

const _FILTER_IDS := ["common", "uncommon", "rare", "epic", "legendary"]
func _on_loot_filter_changed(idx: int) -> void:
	if idx < 0 or idx >= _FILTER_IDS.size():
		return
	state["loot_filter"] = _FILTER_IDS[idx]
	SaveState.save_state(state)

func _add_stat(x: int, y: int, size: int, color: Color, txt: String) -> Label:
	var lbl := Label.new()
	lbl.text = txt
	lbl.position = Vector2(x, y)
	lbl.add_theme_font_size_override("font_size", size)
	lbl.add_theme_color_override("font_color", color)
	add_child(lbl)
	return lbl

func _build_inventory_pane(x: int, y: int, w: int, h: int) -> void:
	_make_panel(x, y, w, h, "Inventory — click to equip")
	var inner_x := x + 12
	var inner_y := y + 36
	var inner_w := w - 24
	var inner_h := h - 48
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(inner_x, inner_y)
	scroll.size = Vector2(inner_w, inner_h)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	inventory_grid = GridContainer.new()
	inventory_grid.columns = max(1, int(inner_w / (INV_CELL_SIZE + 8)))
	inventory_grid.add_theme_constant_override("h_separation", 8)
	inventory_grid.add_theme_constant_override("v_separation", 8)
	scroll.add_child(inventory_grid)

# ============================================================================
# Render
# ============================================================================

func _render() -> void:
	_render_stats()
	_render_equipped()
	_render_inventory()

func _render_stats() -> void:
	# Mirror Bot.recompute_stats for the equipped set so the Outpost shows
	# what the bot will actually have on deploy.
	var max_hp := 50 + (int(state.level) - 1) * 8
	var atk := 5 + (int(state.level) - 1)
	var defense := 1 + int(int(state.level) / 3.0)
	var crit_sum: float = 0.0
	var haste_sum: float = 0.0
	var regen_sum: float = 0.0
	for slot in SLOTS:
		var inst: Variant = state.equipped.get(slot, null)
		if inst == null or typeof(inst) != TYPE_DICTIONARY:
			continue
		var base_id: String = String(inst.get("base_id", ""))
		if not items_db.has(base_id):
			continue
		var item: Dictionary = items_db[base_id]
		max_hp += int(item.get("hp", 0))
		atk += int(item.get("atk", 0))
		defense += int(item.get("def", 0))
		var sums: Dictionary = AffixSystem.sum_affix_stats(inst.get("affixes", []))
		max_hp += int(sums.get("hp", 0))
		atk += int(sums.get("atk", 0))
		defense += int(sums.get("def", 0))
		crit_sum += float(sums.get("crit_chance", 0))
		haste_sum += float(sums.get("atk_speed_pct", 0))
		regen_sum += float(sums.get("hp_regen", 0))
	# Match the bot's caps so the displayed value equals the in-game value.
	crit_sum = clampf(crit_sum, 0.0, 75.0)
	haste_sum = clampf(haste_sum, 0.0, 200.0)
	lbl_level.text = "Level %d" % int(state.level)
	lbl_xp.text = "XP %d" % int(state.xp)
	lbl_floor.text = "Highest floor: %d" % int(state.highest_floor)
	lbl_hp.text = "HP  %d" % max_hp
	lbl_atk.text = "ATK %d" % atk
	lbl_def.text = "DEF %d" % defense
	lbl_crit.text = "Crit %d%%" % int(round(crit_sum))
	lbl_haste.text = "Haste %d%%" % int(round(haste_sum))
	lbl_regen.text = "Regen %d/s" % int(round(regen_sum))
	lbl_gold.text = "Gold %d" % int(state.gold)

func _render_equipped() -> void:
	for cell in equipped_cells:
		var slot: String = cell.slot
		var sprite: TextureRect = cell.sprite
		var border: ReferenceRect = cell.border
		var btn: Button = cell.btn
		var inst: Variant = state.equipped.get(slot, null)
		var tex: Texture2D = null
		var item_name: String = ""
		var rarity: String = ""
		if inst != null and typeof(inst) == TYPE_DICTIONARY:
			var base_id: String = String(inst.get("base_id", ""))
			if items_db.has(base_id):
				var item: Dictionary = items_db[base_id]
				item_name = AffixSystem.format_item_name(String(item.name), inst.get("affixes", []))
				rarity = String(item.get("rarity", ""))
				var tile_path: String = ITEM_TILE_DIR + String(item.get("tile", ""))
				if ResourceLoader.exists(tile_path):
					tex = load(tile_path)
		sprite.texture = tex
		# Tint the icon — flavor tag wins over rarity (vampiric=red,
		# fire=orange) so equipped paperdoll slots match the bot rig.
		var tint_flavor: Array = []
		if inst != null and typeof(inst) == TYPE_DICTIONARY:
			var bid: String = String(inst.get("base_id", ""))
			if items_db.has(bid):
				tint_flavor = items_db[bid].get("flavor_tags", [])
		sprite.modulate = UITheme.item_modulate(rarity, tint_flavor)
		var base_tooltip: String = SLOT_TOOLTIPS.get(slot, slot.capitalize())
		btn.tooltip_text = base_tooltip if item_name.is_empty() else _build_item_tooltip(slot, inst)
		# Rarity-tint border when something's equipped (kept for empty
		# state) plus an outline+halo on the item sprite itself.
		if not cell.is_placeholder:
			if rarity != "" and RARITY_COLORS.has(rarity):
				border.border_color = RARITY_COLORS[rarity]
			else:
				border.border_color = Color(0.4, 0.35, 0.2, 0.8)
		# Rarity decoration on equipped slots is just the border color set
		# above — paperdoll slot art is small enough that a haloed cell
		# would compete with the equipped sprite for attention.
		sprite.material = null
	# Rebuild the bot rig with the latest equipped set.
	if paperdoll_holder != null:
		if is_instance_valid(paperdoll_rig):
			paperdoll_rig.queue_free()
		var built: Dictionary = PaperdollRenderer.build_rig(items_db, state.equipped)
		paperdoll_rig = built.rig
		paperdoll_holder.add_child(paperdoll_rig)

func _render_inventory() -> void:
	for c in inventory_grid.get_children():
		c.queue_free()
	var inv: Array = state.inventory
	for i in inv.size():
		var inst: Variant = inv[i]
		if typeof(inst) != TYPE_DICTIONARY:
			continue
		var base_id: String = String(inst.get("base_id", ""))
		if not items_db.has(base_id):
			continue
		var item: Dictionary = items_db[base_id]
		inventory_grid.add_child(_make_inv_cell(i, inst, item))

func _make_inv_cell(inv_index: int, inst: Dictionary, item: Dictionary) -> Control:
	var rarity: String = String(item.get("rarity", "common"))
	var cell := Control.new()
	cell.custom_minimum_size = Vector2(INV_CELL_SIZE, INV_CELL_SIZE)
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.45)
	bg.size = Vector2(INV_CELL_SIZE, INV_CELL_SIZE)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(bg)
	# Square border + inset halo (rarity-tinted ring around the edges).
	var halo: float = {
		"common": 0.0, "uncommon": 0.18, "rare": 0.30,
		"epic": 0.42, "legendary": 0.55,
	}.get(rarity, 0.0)
	UITheme.add_rarity_cell_decor(cell, INV_CELL_SIZE, rarity, halo)
	# Sprite on top of the decor.
	var sprite := TextureRect.new()
	sprite.size = Vector2(INV_CELL_SIZE, INV_CELL_SIZE)
	sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tile_path: String = ITEM_TILE_DIR + String(item.get("tile", ""))
	if ResourceLoader.exists(tile_path):
		sprite.texture = load(tile_path)
	sprite.modulate = UITheme.item_modulate(rarity, item.get("flavor_tags", []))
	cell.add_child(sprite)
	var btn := Button.new()
	btn.size = Vector2(INV_CELL_SIZE, INV_CELL_SIZE)
	btn.flat = true
	btn.tooltip_text = _build_item_tooltip(String(item.get("slot", "")), inst)
	btn.pressed.connect(_equip.bind(inv_index))
	cell.add_child(btn)
	return cell

func _build_item_tooltip(slot: String, inst: Variant) -> String:
	if inst == null or typeof(inst) != TYPE_DICTIONARY:
		return SLOT_TOOLTIPS.get(slot, slot.capitalize())
	var base_id: String = String(inst.get("base_id", ""))
	if not items_db.has(base_id):
		return base_id
	return AffixSystem.format_item_tooltip(items_db[base_id], inst)

func _equip(inv_index: int) -> void:
	var inv: Array = state.inventory
	if inv_index < 0 or inv_index >= inv.size():
		return
	var inst: Dictionary = inv[inv_index]
	var base_id: String = String(inst.get("base_id", ""))
	if not items_db.has(base_id):
		return
	var slot: String = _resolve_equip_slot(String(items_db[base_id].slot))
	var current: Variant = state.equipped.get(slot, null)
	inv.remove_at(inv_index)
	if current != null and typeof(current) == TYPE_DICTIONARY:
		inv.append(current)
	state.equipped[slot] = inst
	SaveState.save_state(state)
	_render()

# items.json declares slot=="ring"; we collapsed to a single ring slot
# (amulet covers the other trinket spot). Older saves with ring1/ring2
# are migrated in save_state._migrate.
func _resolve_equip_slot(item_slot: String) -> String:
	return item_slot

func _unequip(slot: String) -> void:
	var current: Variant = state.equipped.get(slot, null)
	if current == null or typeof(current) != TYPE_DICTIONARY:
		return
	state.inventory.append(current)
	state.equipped[slot] = null
	SaveState.save_state(state)
	_render()

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
