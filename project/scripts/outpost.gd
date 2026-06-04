extends Control

# Outpost — pre-run loadout screen. Three-pane DCSS chrome:
#   left: paperdoll (matches HUD), center: stats + biographical text,
#   right: inventory icon grid (rarity-bordered, tooltip on hover).
# Bottom strip is a tier-grouped branch picker: clicking a branch deploys
# directly. Locked branches grey out with their unlock condition.
# Built in code so it can mirror the HUD's L-shape paperdoll geometry.

signal deploy_pressed(branch_id: String)
signal shop_pressed

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

const SLOTS := ["weapon", "armor", "helm", "boots", "shield", "gloves", "cloak", "ring", "amulet",
	"spell1", "spell2", "spell3", "spell4", "spell5"]
const SPELL_SLOTS := ["spell1", "spell2", "spell3", "spell4", "spell5"]
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
const PAPERDOLL_BASE_PX := 32

const PAPERDOLL_SLOT_SIZE := 56
const INV_CELL_SIZE := 64
const PANEL_PAD := 16

# Colors mirror UITheme — see hud_chrome.gd note for why these are inline.
const COL_AMBER := Color(0.92, 0.78, 0.45)
const COL_DIM := Color(0.7, 0.6, 0.4)
const COL_GOLD := Color(1.0, 0.85, 0.3)
const COL_PANEL := Color(0.0, 0.0, 0.0, 1.0)  # pure-black, OLED — UI pass 2026-06-04
const COL_PANEL_BORDER := Color(0.35, 0.3, 0.18, 0.65)
const COL_BG := Color(0.0, 0.0, 0.0, 1.0)
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
var lbl_str: Label
var lbl_dex: Label
var lbl_int: Label
var lbl_unspent: Label
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
	# Listen for drag drops anywhere in the outpost. Single subscription
	# at the outpost level keeps the per-cell wiring trivial.
	if DragManager and not DragManager.drag_ended.is_connected(_on_drag_ended):
		DragManager.drag_ended.connect(_on_drag_ended)
	# Live resize — debounced 250ms via UILayout. Tear down + rebuild
	# the layout so new sidebar widths / pane percentages take effect
	# on aspect-ratio crossings. UI polish 2026-06-04.
	UILayout.subscribe_resize(self, _on_viewport_resized)
	set_process(true)

func _on_viewport_resized() -> void:
	# Tear down everything and rebuild from scratch. State (state,
	# items_db) survives because they're cached on `self`. _render()
	# refreshes labels + grid post-rebuild.
	for child in get_children():
		# Skip auxiliary nodes that aren't part of the layout (Timers
		# from UILayout.subscribe_resize, paperdoll_holder cache, etc).
		if child is Timer:
			continue
		child.queue_free()
	equipped_cells.clear()
	paperdoll_holder = null
	paperdoll_rig = null
	inventory_grid = null
	_build_layout()
	_render()

func _exit_tree() -> void:
	if DragManager and DragManager.drag_ended.is_connected(_on_drag_ended):
		DragManager.drag_ended.disconnect(_on_drag_ended)

# WoW-style tooltip manager — owns one ItemTooltip widget plus an
# optional comparison tooltip rendered when Shift is held. Shown by
# ItemCell hover hooks via tooltip_owner. Item-overhaul v2 2026-06-04.
var _tooltip: ItemTooltip = null
var _compare_tooltips: Array = []   # sibling tooltips when Shift held
var _hover_cell: ItemCell = null
var _shift_was_held: bool = false
var _alt_was_held: bool = false

func _on_cell_tooltip(cell: ItemCell, show: bool) -> void:
	if not show:
		_hover_cell = null
		_destroy_tooltips()
		return
	_hover_cell = cell
	_show_main_tooltip(cell)
	if Input.is_key_pressed(KEY_SHIFT):
		_show_compare_tooltips(cell)
		_shift_was_held = true

func _process(_delta: float) -> void:
	if _hover_cell == null or not is_instance_valid(_hover_cell):
		return
	# Shift-state polling so the compare panel appears/disappears live.
	var shift_now: bool = Input.is_key_pressed(KEY_SHIFT)
	if shift_now and not _shift_was_held:
		_show_compare_tooltips(_hover_cell)
	elif not shift_now and _shift_was_held:
		_destroy_compare_tooltips()
	_shift_was_held = shift_now
	# Alt-state polling — re-renders the main tooltip so the extended
	# affix-detail lines toggle live. Tooltip reads Input.is_key_pressed
	# at render time, so we just rebuild content on Alt edge.
	var alt_now: bool = Input.is_key_pressed(KEY_ALT)
	if alt_now != _alt_was_held and _tooltip != null and is_instance_valid(_tooltip):
		_tooltip.render_for(_hover_cell.item, _hover_cell.inst, items_db)
	_alt_was_held = alt_now
	# Keep tooltip glued near cursor so it doesn't hover off the cell.
	if _tooltip != null and is_instance_valid(_tooltip):
		_tooltip.position = _clamp_tooltip_position(_compute_anchor(_hover_cell), _tooltip.size)

func _show_main_tooltip(cell: ItemCell) -> void:
	if _tooltip != null and is_instance_valid(_tooltip):
		_tooltip.queue_free()
	_tooltip = ItemTooltip.new()
	add_child(_tooltip)
	_tooltip.render_for(cell.item, cell.inst, items_db)
	_tooltip.position = _clamp_tooltip_position(_compute_anchor(cell), Vector2(ItemTooltip.TOOLTIP_W, 200))

func _show_compare_tooltips(cell: ItemCell) -> void:
	_destroy_compare_tooltips()
	# Only compare gear (not spells per design). Inventory cell
	# compare-vs-equipped same slot. Paperdoll cell compare-vs-NEXT
	# equipped same-slot would be redundant; skip.
	if cell.role != "inventory":
		return
	var item_slot: String = String(cell.item.get("slot", ""))
	if item_slot == "" or item_slot == "spell":
		return
	# For ring slot, tile ALL equipped rings vertically (WoW pattern).
	var slot_ids: Array = []
	if item_slot == "ring":
		slot_ids = SpeciesData.ring_slot_ids(String(state.get("species", "")))
	else:
		slot_ids = [item_slot]
	var x_offset: float = ItemTooltip.TOOLTIP_W + 8.0
	var y_offset: float = 0.0
	for sid in slot_ids:
		var equipped_inst: Variant = state.equipped.get(sid, null)
		if equipped_inst == null or typeof(equipped_inst) != TYPE_DICTIONARY:
			continue
		var equipped_id: String = String(equipped_inst.get("base_id", ""))
		if not items_db.has(equipped_id):
			continue
		var cmp := ItemTooltip.new()
		add_child(cmp)
		cmp.render_for(items_db[equipped_id], equipped_inst, items_db)
		cmp.position = _tooltip.position + Vector2(x_offset, y_offset)
		_compare_tooltips.append(cmp)
		y_offset += 200.0  # rough; actual height resolves async

func _destroy_compare_tooltips() -> void:
	for t in _compare_tooltips:
		if t != null and is_instance_valid(t):
			t.queue_free()
	_compare_tooltips.clear()

func _destroy_tooltips() -> void:
	if _tooltip != null and is_instance_valid(_tooltip):
		_tooltip.queue_free()
		_tooltip = null
	_destroy_compare_tooltips()
	_shift_was_held = false

func _compute_anchor(cell: ItemCell) -> Vector2:
	if not is_instance_valid(cell):
		return get_viewport().get_mouse_position()
	# Place the tooltip's top-left near the cursor with a small offset,
	# anchored to mouse so it follows during hovers.
	return get_viewport().get_mouse_position() + Vector2(16, 16)

func _clamp_tooltip_position(anchor: Vector2, sz: Vector2) -> Vector2:
	var view: Vector2 = get_viewport().get_visible_rect().size
	var px: float = clampf(anchor.x, 4.0, max(4.0, view.x - sz.x - 4.0))
	var py: float = clampf(anchor.y, 4.0, max(4.0, view.y - sz.y - 4.0))
	return Vector2(px, py)

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
	# Shop button — top-right, opens the shop screen.
	var shop_btn := Button.new()
	shop_btn.text = "🏪 Shop"
	shop_btn.position = Vector2(int(view.x) - 140, 16)
	shop_btn.size = Vector2(120, 32)
	shop_btn.add_theme_font_size_override("font_size", 14)
	shop_btn.pressed.connect(func(): shop_pressed.emit())
	add_child(shop_btn)
	# Run-in-progress banner — only when the player has a defeated-but-
	# alive run. Shows the floor reached + the branch + an "End Run"
	# button so the player can actively close it. Positioned just below
	# the title, centered. Combat-pivot 2026-06-04.
	if bool(state.get("run_active", false)):
		var banner := Label.new()
		var br: String = String(state.get("run_branch", ""))
		var fl: int = int(state.get("run_floor_reached", 0))
		banner.text = "Run in progress: %s — Floor %d (defeated, redeploy to continue)" % [br.capitalize(), fl]
		banner.position = Vector2(0, 48)
		banner.size = Vector2(view.x, 24)
		banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		banner.add_theme_font_size_override("font_size", 13)
		banner.add_theme_color_override("font_color", Color(0.95, 0.65, 0.35))
		add_child(banner)
		var end_btn := Button.new()
		end_btn.text = "End Run"
		end_btn.position = Vector2(16, 16)
		end_btn.size = Vector2(110, 32)
		end_btn.add_theme_font_size_override("font_size", 13)
		end_btn.pressed.connect(_on_end_run_pressed)
		add_child(end_btn)
	# Branch picker at bottom — item-card-style strip. Each branch is
	# a tall card with biome name, tier label, modifier list visible
	# without hover, rarity tint by tier (T1 white, T2 blue, T3 gold,
	# T4 orange, T5 red), and a soft glow per modifier so the card
	# reads like a piece of loot. Bigger than the old 96px strip so
	# it doesn't feel cramped at the bottom of the screen.
	var picker_h := 220
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
	scroll.position = Vector2(x + 12, y + 32)
	scroll.size = Vector2(w - 24, h - 40)
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 16)
	scroll.add_child(hbox)
	var unlocked: Array = state.get("unlocked_branches", ["dungeon"])
	# Render branches grouped by tier with a thin separator between
	# tiers — keeps tier-scaling readable while letting the cards
	# breathe. Tier label sits above each tier's card row.
	for tier in [1, 2, 3, 4, 5]:
		hbox.add_child(_make_tier_column(tier, unlocked))

# Tier → rarity color, per the user's spec:
# T1 white (common) → T5 red (legendary). Used to tint card border +
# header glow so the player reads "this branch is harder = redder."
const _TIER_TO_RARITY := {
	1: "common", 2: "uncommon", 3: "rare", 4: "epic", 5: "legendary",
}

func _make_tier_column(tier: int, unlocked: Array) -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	var hdr := Label.new()
	hdr.text = String(TIER_LABELS.get(tier, "Tier %d" % tier))
	hdr.add_theme_font_size_override("font_size", 12)
	# Tier header in its rarity color so the column reads as "this is
	# the legendary tier."
	var rarity: String = String(_TIER_TO_RARITY.get(tier, "common"))
	hdr.add_theme_color_override("font_color", UITheme.rarity_color(rarity))
	col.add_child(hdr)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	col.add_child(row)
	for branch_id in TIER_BRANCHES.get(tier, []):
		row.add_child(_make_branch_card(branch_id, unlocked.has(branch_id), tier))
	return col

# Item-card-style branch button. Vertical: name (top), tier label,
# modifier list (visible without hover), CR recommended (footer).
# Border + faint halo tinted by tier rarity. Each modifier renders
# as a chip in COL_AMBER (visible at-a-glance) with a glow gradient
# behind it for the highest-tier branches so they read as "loaded
# with effects."
const _BRANCH_CARD_W := 168
const _BRANCH_CARD_H := 168

func _make_branch_card(branch_id: String, is_unlocked: bool, tier: int) -> Control:
	var biome: Dictionary = BiomeData.get_biome(branch_id)
	var display: String = String(biome.get("display_name", branch_id.capitalize()))
	if display.to_lower().begins_with("the "):
		display = display.substr(4)
	var pretty: String = display.capitalize() if display == display.to_lower() else display
	var mods: Array = state.get("branch_modifiers", {}).get(branch_id, [])
	var rarity: String = String(_TIER_TO_RARITY.get(tier, "common"))
	var rarity_col: Color = UITheme.rarity_color(rarity)
	# Outer Button is the click target; everything else is decor inside.
	var btn := Button.new()
	btn.flat = true
	btn.custom_minimum_size = Vector2(_BRANCH_CARD_W, _BRANCH_CARD_H)
	btn.size = Vector2(_BRANCH_CARD_W, _BRANCH_CARD_H)
	# Card background: black with rarity-tint halo strength scaled by
	# tier so T5 cards feel "loaded." Reuses UITheme decor helper.
	var halo_strength: float = float({
		"common": 0.15, "uncommon": 0.22, "rare": 0.30,
		"epic": 0.42, "legendary": 0.55,
	}.get(rarity, 0.20))
	UITheme.add_rarity_cell_decor(btn, _BRANCH_CARD_W, rarity, halo_strength)
	# Biome icon — large, centered, sits BEHIND the text labels at
	# low alpha so it reads as a watermark identifying the area.
	# Curated under project/assets/tiles/biome_icons/<id>.png. DCSS
	# enter_<branch>.png where available; thematic substitutes
	# (lava cell, ice tile, mangrove tree) for branches without a
	# direct gateway sprite.
	var icon_path: String = "res://assets/tiles/biome_icons/" + branch_id + ".png"
	if ResourceLoader.exists(icon_path):
		# Center the icon in the FULL card (the title sits over it
		# with an outline, so true-center reads better than
		# top-biased). 96px feels like a stronger watermark on a
		# 168px card than the previous 80px.
		var icon_size: int = 96
		var icon := TextureRect.new()
		icon.texture = load(icon_path)
		icon.position = Vector2((_BRANCH_CARD_W - icon_size) / 2, (_BRANCH_CARD_H - icon_size) / 2)
		icon.size = Vector2(icon_size, icon_size)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.modulate = Color(1, 1, 1, 0.85 if is_unlocked else 0.40)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.add_child(icon)
	# Name label at top.
	var name_lbl := Label.new()
	name_lbl.text = pretty
	name_lbl.position = Vector2(8, 8)
	name_lbl.size = Vector2(_BRANCH_CARD_W - 16, 24)
	name_lbl.add_theme_font_size_override("font_size", 16)
	name_lbl.add_theme_color_override("font_color", rarity_col if is_unlocked else COL_DIM)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Drop-shadow so the name reads cleanly over the icon watermark.
	name_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	name_lbl.add_theme_constant_override("outline_size", 4)
	btn.add_child(name_lbl)
	# Tier label below the name.
	var tier_lbl := Label.new()
	tier_lbl.text = "Tier %d" % tier
	tier_lbl.position = Vector2(8, 32)
	tier_lbl.size = Vector2(_BRANCH_CARD_W - 16, 16)
	tier_lbl.add_theme_font_size_override("font_size", 11)
	tier_lbl.add_theme_color_override("font_color", COL_DIM)
	tier_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	tier_lbl.add_theme_constant_override("outline_size", 4)
	tier_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tier_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(tier_lbl)
	if is_unlocked:
		# Modifier chips, one per line, visible without hover. Each
		# row is "+ Modifier name". Gold (amber) so they pop against
		# the rarity tint without competing with the name color.
		var mod_y: int = _BRANCH_CARD_H - 22 - 14 * mods.size()
		var line_h: int = 14
		for mod_id in mods:
			var mod_def: Dictionary = RunModifiers.get_def(String(mod_id))
			var label: String = String(mod_def.get("name", mod_id))
			var chip := Label.new()
			chip.text = "+ " + label
			chip.position = Vector2(12, mod_y)
			chip.size = Vector2(_BRANCH_CARD_W - 24, line_h + 2)
			chip.add_theme_font_size_override("font_size", 11)
			chip.add_theme_color_override("font_color", COL_AMBER)
			chip.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
			chip.add_theme_constant_override("outline_size", 4)
			chip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
			btn.add_child(chip)
			mod_y += line_h
		# CR footer.
		# Tier label MOVED to under name (right after Tier label) is
		# already there. CR footer pinned to the bottom of the card.
		# Skip rendering it if there are mods so the chips own the
		# bottom of the card cleanly.
		if mods.is_empty():
			var cr_lbl := Label.new()
			cr_lbl.text = "CR %d" % int(biome.get("cr_recommended", 0))
			cr_lbl.position = Vector2(8, _BRANCH_CARD_H - 22)
			cr_lbl.size = Vector2(_BRANCH_CARD_W - 16, 16)
			cr_lbl.add_theme_font_size_override("font_size", 10)
			cr_lbl.add_theme_color_override("font_color", COL_DIM)
			cr_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
			cr_lbl.add_theme_constant_override("outline_size", 4)
			cr_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			cr_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			btn.add_child(cr_lbl)
		# Tooltip kept for full modifier descriptions (hover for detail).
		var tooltip: String = "%s — CR %d recommended" % [display, int(biome.get("cr_recommended", 0))]
		var mod_tip: String = RunModifiers.format_tooltip(mods)
		if mod_tip != "":
			tooltip += "\n\n" + mod_tip
		btn.tooltip_text = tooltip
		btn.pressed.connect(func(): deploy_pressed.emit(branch_id))
	else:
		btn.disabled = true
		btn.tooltip_text = "%s — locked. Clear all branches in the previous tier to unlock." % display
		# Locked overlay: fade the card.
		btn.modulate = Color(0.55, 0.55, 0.55, 1.0)
	return btn

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
	# Build species-resolved slot lists. Converted slots
	# (octopode armor/boots/helm → ring) become extra ring cells; the
	# original slot positions are filled with ring2/ring3/ring4 in the
	# order they appear in the column/row.
	var species: String = String(state.get("species", ""))
	var conv: Dictionary = SpeciesData.slot_conversions(species)
	var ring_pool: Array = SpeciesData.ring_slot_ids(species).slice(1)  # ring2..N
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
	# Right column.
	var right_x: int = inner_x + sprite_w + gap
	var col_count: int = mini(resolved_right.size(), maxi(1, sprite_h / (slot + gap)))
	for i in col_count:
		_make_paperdoll_slot(resolved_right[i], right_x, inner_y + i * (slot + gap))
	# Bottom row.
	var row_y: int = inner_y + sprite_h + gap
	var row_count: int = mini(resolved_bottom.size(), maxi(1, inner_w / (slot + gap)))
	for i in row_count:
		_make_paperdoll_slot(resolved_bottom[i], inner_x + i * (slot + gap), row_y)
	# Spell row — 5 autocast cells under the gear row, with a small
	# divider label so the player reads them as a separate concept.
	var spell_label_y: int = row_y + slot + gap
	var spell_lbl := Label.new()
	spell_lbl.text = "Spells"
	spell_lbl.position = Vector2(inner_x, spell_label_y)
	spell_lbl.add_theme_font_size_override("font_size", 11)
	spell_lbl.add_theme_color_override("font_color", COL_DIM)
	add_child(spell_lbl)
	var spell_row_y: int = spell_label_y + 16
	var spell_count: int = mini(SPELL_SLOTS.size(), maxi(1, inner_w / (slot + gap)))
	for i in spell_count:
		_make_paperdoll_slot(SPELL_SLOTS[i], inner_x + i * (slot + gap), spell_row_y)

func _make_paperdoll_slot(slot_id: String, x: int, y: int) -> void:
	var slot := PAPERDOLL_SLOT_SIZE
	var is_real_slot: bool = (slot_id in SLOTS) or slot_id.begins_with("ring") or slot_id.begins_with("spell")
	var is_placeholder: bool = not is_real_slot
	# Species body-shape lock — gear-only; spell slots are universal.
	var species_blocked: bool = false
	if not slot_id.begins_with("spell"):
		species_blocked = not SpeciesData.can_wear(String(state.get("species", "")), slot_id)
	# ItemCell replaces the old Button + ColorRect/ReferenceRect tree.
	# Drag-and-drop is handled by DragManager + ItemCell._gui_input;
	# left-click unequips via on_left_click.
	var cell := ItemCell.new()
	cell.cell_size = slot
	cell.role = "paperdoll"
	cell.slot_id = slot_id
	cell.blocked = species_blocked or is_placeholder
	cell.position = Vector2(x, y)
	cell.accepts_drop = Callable(self, "_paperdoll_accepts_drop").bind(slot_id)
	cell.on_left_click = Callable(self, "_on_cell_left_click")
	cell.tooltip_owner = Callable(self, "_on_cell_tooltip")
	add_child(cell)
	equipped_cells.append({
		"slot": slot_id, "cell": cell,
		"is_placeholder": is_placeholder, "species_blocked": species_blocked,
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
	lbl_atk = _add_stat(sx, sy, 18, COL_AMBER, "Dmg —"); sy += 24
	lbl_def = _add_stat(sx, sy, 18, COL_AMBER, "Armor —"); sy += 24
	# Primary axis trio. Drawn in their class colors so the player sees
	# Str/Dex/Int as the same red/green/blue scheme as the spell cells.
	# +/- buttons next to each row let the player allocate unspent
	# stat points (3 per level granted on level-up).
	lbl_str = _add_stat(sx, sy, 16, UITheme.spell_class_color("str"), "Str —")
	_add_stat_alloc_buttons(sx + 130, sy, "str")
	sy += 22
	lbl_dex = _add_stat(sx, sy, 16, UITheme.spell_class_color("dex"), "Dex —")
	_add_stat_alloc_buttons(sx + 130, sy, "dex")
	sy += 22
	lbl_int = _add_stat(sx, sy, 16, UITheme.spell_class_color("int"), "Int —")
	_add_stat_alloc_buttons(sx + 130, sy, "int")
	sy += 22
	# Unspent counter + Reset button.
	lbl_unspent = _add_stat(sx, sy, 13, COL_AMBER, "Unspent —")
	var reset_btn := Button.new()
	reset_btn.text = "Reset"
	reset_btn.position = Vector2(sx + 140, sy - 2)
	reset_btn.size = Vector2(60, 22)
	reset_btn.add_theme_font_size_override("font_size", 11)
	reset_btn.tooltip_text = "Refund all spent stat points"
	reset_btn.pressed.connect(_on_stat_reset_pressed)
	add_child(reset_btn)
	sy += 24
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

# Explicit "End Run" button — clears the run-active flag without
# spending another deploy. The player keeps gold/xp/inventory/equipped
# (which never roll back on death anyway) but the branch/floor state
# is wiped so the next deploy starts fresh from floor 1 of whatever
# branch they pick.
func _on_end_run_pressed() -> void:
	state["run_active"] = false
	state["run_branch"] = ""
	state["run_floor_reached"] = 0
	SaveState.save_state(state)
	# Rebuild the layout so the banner + button disappear.
	for child in get_children():
		child.queue_free()
	equipped_cells.clear()
	_build_layout()
	_render()

# Stat-point allocation buttons — one row of [-] [+] beside each Str /
# Dex / Int label. Click + to spend an unspent point on that stat;
# - refunds a spent point. Bounded by the unspent counter and by the
# alloc value (can't refund below 0). Item-overhaul v2 2026-06-04.
func _add_stat_alloc_buttons(x: int, y: int, stat_key: String) -> void:
	var minus_btn := Button.new()
	minus_btn.text = "-"
	minus_btn.position = Vector2(x, y - 2)
	minus_btn.size = Vector2(22, 22)
	minus_btn.add_theme_font_size_override("font_size", 12)
	minus_btn.tooltip_text = "Refund 1 %s point" % stat_key.capitalize()
	minus_btn.pressed.connect(_on_stat_minus_pressed.bind(stat_key))
	add_child(minus_btn)
	var plus_btn := Button.new()
	plus_btn.text = "+"
	plus_btn.position = Vector2(x + 26, y - 2)
	plus_btn.size = Vector2(22, 22)
	plus_btn.add_theme_font_size_override("font_size", 12)
	plus_btn.tooltip_text = "Spend 1 unspent point on %s" % stat_key.capitalize()
	plus_btn.pressed.connect(_on_stat_plus_pressed.bind(stat_key))
	add_child(plus_btn)

func _on_stat_plus_pressed(stat_key: String) -> void:
	var unspent: int = int(state.get("stat_points_unspent", 0))
	if unspent <= 0:
		return
	var key: String = "stat_alloc_" + stat_key
	state[key] = int(state.get(key, 0)) + 1
	state["stat_points_unspent"] = unspent - 1
	SaveState.save_state(state)
	_render_stats()

func _on_stat_minus_pressed(stat_key: String) -> void:
	var key: String = "stat_alloc_" + stat_key
	var alloc: int = int(state.get(key, 0))
	if alloc <= 0:
		return
	state[key] = alloc - 1
	state["stat_points_unspent"] = int(state.get("stat_points_unspent", 0)) + 1
	SaveState.save_state(state)
	_render_stats()

func _on_stat_reset_pressed() -> void:
	# Refund all allocated points → unspent. Free respec.
	var refund: int = int(state.get("stat_alloc_str", 0)) + int(state.get("stat_alloc_dex", 0)) + int(state.get("stat_alloc_int", 0))
	state["stat_alloc_str"] = 0
	state["stat_alloc_dex"] = 0
	state["stat_alloc_int"] = 0
	state["stat_points_unspent"] = int(state.get("stat_points_unspent", 0)) + refund
	SaveState.save_state(state)
	_render_stats()

func _add_stat(x: int, y: int, size: int, color: Color, txt: String) -> Label:
	var lbl := Label.new()
	lbl.text = txt
	lbl.position = Vector2(x, y)
	lbl.add_theme_font_size_override("font_size", size)
	lbl.add_theme_color_override("font_color", color)
	add_child(lbl)
	return lbl

func _build_inventory_pane(x: int, y: int, w: int, h: int) -> void:
	_make_panel(x, y, w, h, "Inventory — click to equip, right-click to favorite")
	var inner_x := x + 12
	var inner_y := y + 36
	var inner_w := w - 24
	# Filter chip row above the grid.
	var chip_row := HBoxContainer.new()
	chip_row.position = Vector2(inner_x, inner_y)
	chip_row.size = Vector2(inner_w, 28)
	chip_row.add_theme_constant_override("separation", 6)
	add_child(chip_row)
	_build_filter_chips(chip_row)
	# Grid sits below the chip row.
	var grid_y: int = inner_y + 32
	var inner_h := h - (grid_y - y) - 12
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(inner_x, grid_y)
	scroll.size = Vector2(inner_w, inner_h)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	inventory_grid = GridContainer.new()
	inventory_grid.columns = max(1, int(inner_w / (INV_CELL_SIZE + 8)))
	inventory_grid.add_theme_constant_override("h_separation", 8)
	inventory_grid.add_theme_constant_override("v_separation", 8)
	scroll.add_child(inventory_grid)

# Active filter state. "all" (slot/rarity) means no constraint;
# "favorites" means only show favorited items. Slot filter constrains
# to one specific slot id.
var _filter_slot: String = "all"
var _filter_rarity: String = "all"
var _filter_favorites: bool = false

const _SLOT_FILTER_OPTIONS := [
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
# Sort orderings — applied to the filtered inventory before render.
# "recency" preserves the original drop order (the inventory is
# already drop-ordered).
const _SORT_OPTIONS := [
	{ "id": "recency", "label": "Recently dropped" },
	{ "id": "rarity",  "label": "Rarity (high → low)" },
	{ "id": "slot",    "label": "Slot grouping" },
	{ "id": "name",    "label": "Name (A → Z)" },
]
var _sort_mode: String = "recency"
# Rarity ordering — chips toggle by clicking through. Empty = no filter.
const _RARITY_FILTER_OPTIONS := [
	{ "id": "all",       "label": "All rarities", "min_rank": -1 },
	{ "id": "uncommon+", "label": "Uncommon+",    "min_rank": 1 },
	{ "id": "rare+",     "label": "Rare+",        "min_rank": 2 },
	{ "id": "epic+",     "label": "Epic+",        "min_rank": 3 },
	{ "id": "legendary", "label": "Legendary",    "min_rank": 4 },
]

func _build_filter_chips(parent: HBoxContainer) -> void:
	# Slot filter dropdown.
	var slot_opt := OptionButton.new()
	for i in _SLOT_FILTER_OPTIONS.size():
		slot_opt.add_item(String(_SLOT_FILTER_OPTIONS[i].label))
		slot_opt.set_item_metadata(i, String(_SLOT_FILTER_OPTIONS[i].id))
	slot_opt.select(0)
	slot_opt.item_selected.connect(func(idx):
		_filter_slot = String(slot_opt.get_item_metadata(idx))
		_render_inventory()
	)
	parent.add_child(slot_opt)
	# Rarity filter dropdown.
	var rarity_opt := OptionButton.new()
	for i in _RARITY_FILTER_OPTIONS.size():
		rarity_opt.add_item(String(_RARITY_FILTER_OPTIONS[i].label))
		rarity_opt.set_item_metadata(i, String(_RARITY_FILTER_OPTIONS[i].id))
	rarity_opt.select(0)
	rarity_opt.item_selected.connect(func(idx):
		_filter_rarity = String(rarity_opt.get_item_metadata(idx))
		_render_inventory()
	)
	parent.add_child(rarity_opt)
	# Sort dropdown.
	var sort_opt := OptionButton.new()
	for i in _SORT_OPTIONS.size():
		sort_opt.add_item(String(_SORT_OPTIONS[i].label))
		sort_opt.set_item_metadata(i, String(_SORT_OPTIONS[i].id))
	sort_opt.select(0)
	sort_opt.item_selected.connect(func(idx):
		_sort_mode = String(sort_opt.get_item_metadata(idx))
		_render_inventory()
	)
	parent.add_child(sort_opt)
	# Favorites toggle.
	var fav_btn := CheckButton.new()
	fav_btn.text = "★ Favorites only"
	fav_btn.toggled.connect(func(v):
		_filter_favorites = v
		_render_inventory()
	)
	parent.add_child(fav_btn)

# Returns true if `inst` should render given the active filters.
func _passes_filter(inst: Dictionary, item: Dictionary) -> bool:
	if _filter_slot != "all" and String(item.get("slot", "")) != _filter_slot:
		return false
	if _filter_rarity != "all":
		var min_rank: int = -1
		for opt in _RARITY_FILTER_OPTIONS:
			if String(opt.id) == _filter_rarity:
				min_rank = int(opt.min_rank)
				break
		var item_rank: int = int(LootDrop.RARITY_RANK.get(String(item.get("rarity", "common")), 0))
		if item_rank < min_rank:
			return false
	if _filter_favorites and not bool(inst.get("favorite", false)):
		return false
	return true

# ============================================================================
# Render
# ============================================================================

func _render() -> void:
	_render_stats()
	_render_equipped()
	_render_inventory()

func _render_stats() -> void:
	# Mirror Bot.recompute_stats v2 for the equipped set so the Outpost
	# shows what the bot will actually have on deploy.
	var max_hp := 80 + (int(state.level) - 1) * 8
	var armor: int = 0
	var evasion: float = 0.0
	var crit_sum: float = 0.0
	var haste_sum: float = 0.0
	var regen_sum: float = 0.0
	# Weapon-derived display values default to bare-handed.
	var dmin: int = 1
	var dmax: int = 2
	var w_speed: float = 1.0
	var w_dtype: String = "physical"
	# Primary stats — base 5/5/5 + species + level + alloc + gear affixes.
	var sp_def: Dictionary = SpeciesData.get_def(String(state.get("species", "")))
	var lvl_bonus: int = max(0, int(state.level) - 1)
	var alloc_str: int = int(state.get("stat_alloc_str", 0))
	var alloc_dex: int = int(state.get("stat_alloc_dex", 0))
	var alloc_int: int = int(state.get("stat_alloc_int", 0))
	var str_v: int = 5 + int(sp_def.get("str_flat", 0)) + lvl_bonus + alloc_str
	var dex_v: int = 5 + int(sp_def.get("dex_flat", 0)) + lvl_bonus + alloc_dex
	var int_v: int = 5 + int(sp_def.get("int_flat", 0)) + lvl_bonus + alloc_int
	for slot in SLOTS:
		var inst: Variant = state.equipped.get(slot, null)
		if inst == null or typeof(inst) != TYPE_DICTIONARY:
			continue
		var base_id: String = String(inst.get("base_id", ""))
		if not items_db.has(base_id):
			continue
		var item: Dictionary = items_db[base_id]
		if slot == "weapon":
			dmin = int(item.get("damage_min", 1))
			dmax = int(item.get("damage_max", 2))
			w_speed = float(item.get("speed", 1.0))
			w_dtype = String(item.get("damage_type", "physical"))
		else:
			armor += int(item.get("armor", 0))
			evasion += float(item.get("evasion", 0))
		var sums: Dictionary = AffixSystem.sum_affix_stats(inst.get("affixes", []))
		max_hp += int(sums.get("hp", 0))
		armor += int(sums.get("armor", 0))
		evasion += float(sums.get("evasion", 0))
		crit_sum += float(sums.get("crit_chance", 0))
		haste_sum += float(sums.get("haste_pct", 0))
		regen_sum += float(sums.get("hp_regen", 0))
		str_v += int(sums.get("str", 0))
		dex_v += int(sums.get("dex", 0))
		int_v += int(sums.get("int", 0))
	# Mirror Bot.recompute_stats derived contributions.
	var str_excess: int = str_v - 5
	var dex_excess: int = dex_v - 5
	max_hp = int(round(float(max_hp) * (1.0 + float(str_excess) * 0.015)))
	crit_sum += float(dex_excess) * 0.5
	haste_sum += float(dex_excess) * 1.0
	# Caps to match in-game values exactly.
	crit_sum = clampf(crit_sum, 0.0, 75.0)
	haste_sum = clampf(haste_sum, 0.0, 200.0)
	evasion = clampf(evasion, 0.0, 75.0)
	# Effective attack interval: weapon speed / haste mult.
	var interval: float = max(0.15, w_speed / (1.0 + haste_sum / 100.0))
	var dtype_label: String = w_dtype.capitalize() if w_dtype != "physical" else "Phys"
	lbl_level.text = "Level %d" % int(state.level)
	lbl_xp.text = "XP %d" % int(state.xp)
	lbl_floor.text = "Highest floor: %d" % int(state.highest_floor)
	lbl_hp.text = "HP  %d" % max_hp
	lbl_atk.text = "Dmg %d-%d %s · %.1fs" % [dmin, dmax, dtype_label, interval]
	lbl_def.text = "Armor %d · Eva %d%%" % [armor, int(round(evasion))]
	lbl_str.text = "Str %d" % str_v
	lbl_dex.text = "Dex %d" % dex_v
	lbl_int.text = "Int %d" % int_v
	if lbl_unspent != null:
		var unspent: int = int(state.get("stat_points_unspent", 0))
		lbl_unspent.text = "Unspent: %d" % unspent
		lbl_unspent.modulate = Color(1.0, 0.9, 0.4, 1.0) if unspent > 0 else Color(0.5, 0.5, 0.5, 1.0)
	lbl_crit.text = "Crit %d%%" % int(round(crit_sum))
	lbl_haste.text = "Haste %d%%" % int(round(haste_sum))
	lbl_regen.text = "Regen %d/s" % int(round(regen_sum))
	lbl_gold.text = "Gold %d" % int(state.gold)

func _render_equipped() -> void:
	for entry in equipped_cells:
		var slot: String = String(entry.slot)
		var cell: ItemCell = entry.cell
		var inst: Variant = state.equipped.get(slot, null)
		cell.inst = inst
		if inst != null and typeof(inst) == TYPE_DICTIONARY and items_db.has(String(inst.get("base_id", ""))):
			cell.item = items_db[String(inst.get("base_id", ""))]
		else:
			cell.item = {}
		cell.blocked = bool(entry.get("species_blocked", false))
		cell.render()
	# Rebuild the bot rig with the latest equipped set.
	if paperdoll_holder != null:
		if is_instance_valid(paperdoll_rig):
			paperdoll_rig.queue_free()
		var built: Dictionary = PaperdollRenderer.build_rig(items_db, state.equipped, String(state.get("species", "")))
		paperdoll_rig = built.rig
		paperdoll_holder.add_child(paperdoll_rig)

func _render_inventory() -> void:
	if inventory_grid == null:
		return
	for c in inventory_grid.get_children():
		c.queue_free()
	var inv: Array = state.inventory
	# Build (index, inst, item) triples so the sort can rearrange display
	# while preserving the original inv_index for click handlers.
	var triples: Array = []
	for i in inv.size():
		var inst: Variant = inv[i]
		if typeof(inst) != TYPE_DICTIONARY:
			continue
		var base_id: String = String(inst.get("base_id", ""))
		if not items_db.has(base_id):
			continue
		var item: Dictionary = items_db[base_id]
		if not _passes_filter(inst, item):
			continue
		triples.append({"i": i, "inst": inst, "item": item})
	# Apply sort. "recency" leaves order alone (drop-order is the natural
	# inventory order). Other modes use a stable comparator.
	var rarity_rank: Dictionary = LootDrop.RARITY_RANK
	match _sort_mode:
		"rarity":
			triples.sort_custom(func(a, b):
				var ra: int = int(rarity_rank.get(String(a.item.get("rarity", "")), 0))
				var rb: int = int(rarity_rank.get(String(b.item.get("rarity", "")), 0))
				if ra != rb:
					return ra > rb
				return String(a.item.get("name", "")) < String(b.item.get("name", ""))
			)
		"slot":
			triples.sort_custom(func(a, b):
				var sa: String = String(a.item.get("slot", ""))
				var sb: String = String(b.item.get("slot", ""))
				if sa != sb:
					return sa < sb
				var ra: int = int(rarity_rank.get(String(a.item.get("rarity", "")), 0))
				var rb: int = int(rarity_rank.get(String(b.item.get("rarity", "")), 0))
				return ra > rb
			)
		"name":
			triples.sort_custom(func(a, b):
				return String(a.item.get("name", "")) < String(b.item.get("name", ""))
			)
	for t in triples:
		inventory_grid.add_child(_make_inv_cell(int(t.i), t.inst, t.item))

func _make_inv_cell(inv_index: int, inst: Dictionary, item: Dictionary) -> Control:
	var item_slot: String = String(item.get("slot", ""))
	var blocked: bool = item_slot != "" and not SpeciesData.can_wear(String(state.get("species", "")), item_slot)
	var cell := ItemCell.new()
	cell.cell_size = INV_CELL_SIZE
	cell.role = "inventory"
	# inv_index is informational only — equip resolves the live position
	# by instance_id at click time. Using the stale index would let a
	# rapid-fire double-click target whatever item happened to fall into
	# that slot after the first equip (the duplication bug).
	cell.inv_index = inv_index
	cell.set_meta("instance_id", String(inst.get("instance_id", "")))
	cell.inst = inst
	cell.item = item
	cell.blocked = blocked
	cell.on_left_click = Callable(self, "_on_cell_left_click")
	cell.on_right_click = Callable(self, "_on_cell_right_click")
	cell.tooltip_owner = Callable(self, "_on_cell_tooltip")
	# Trigger render after the node enters the tree so child layout works.
	cell.ready.connect(cell.render)
	return cell

# Click handler installed on every ItemCell. Behavior depends on role:
#   inventory  → auto-equip via _equip(inv_index)
#   paperdoll  → unequip via _unequip(slot_id)
#   shop/sell  → handled by shop screen, not outpost
func _on_cell_left_click(cell: ItemCell) -> void:
	if cell.role == "inventory":
		# Resolve the LIVE inventory index by instance_id at click time.
		# Stale index from cell-construction is not safe — a rapid-fire
		# second click on a queue_freed-but-not-yet-deleted cell would
		# equip whichever item fell into that slot after the first
		# equip (presents as "duplication" to the player).
		var iid: String = String(cell.get_meta("instance_id", ""))
		var live_idx: int = _live_inv_index(iid)
		if live_idx < 0:
			return  # already equipped / removed — second click no-ops
		_equip(live_idx)
	elif cell.role == "paperdoll":
		_unequip(cell.slot_id)

func _on_cell_right_click(cell: ItemCell) -> void:
	# Right-click toggles favorite on inventory cells only. Paperdoll
	# right-click is reserved for a future "compare with currently
	# equipped" tooltip.
	if cell.role == "inventory":
		var iid: String = String(cell.get_meta("instance_id", ""))
		var live_idx: int = _live_inv_index(iid)
		if live_idx >= 0:
			_toggle_favorite(live_idx)

# Resolve the current state.inventory index for the given instance_id.
# Returns -1 if the item isn't in inventory anymore (already equipped,
# salvaged, or removed). Same anti-stale-index pattern as the HUD's
# flat_index_resolver.
func _live_inv_index(instance_id: String) -> int:
	if instance_id == "":
		return -1
	for i in state.inventory.size():
		var inst: Variant = state.inventory[i]
		if typeof(inst) == TYPE_DICTIONARY and String(inst.get("instance_id", "")) == instance_id:
			return i
	return -1

# Hover-time check for whether a paperdoll slot can accept a drag
# payload. Called from ItemCell._on_mouse_entered while a drag is
# in flight. Returns true → cell glows green; false → glows red.
func _paperdoll_accepts_drop(payload: Dictionary, slot_id: String) -> bool:
	if payload == null or payload.is_empty():
		return false
	var src_role: String = String(payload.get("role", ""))
	# A drag from paperdoll → paperdoll only valid between same-family
	# slots (spell↔spell, ring↔ring, gear↔same gear).
	if src_role == "paperdoll":
		var src_slot: String = String(payload.get("slot_id", ""))
		if src_slot == slot_id:
			return false  # noop
		if src_slot.begins_with("spell") and slot_id.begins_with("spell"):
			return true
		if src_slot.begins_with("ring") and slot_id.begins_with("ring"):
			return true
		# Allow weapon↔weapon or shield↔shield etc (degenerate but valid).
		return src_slot == slot_id
	# Inventory drag — check item slot family matches the target slot.
	var item_slot: String = String(payload.get("item_slot", ""))
	if item_slot == "":
		return false
	# Species block: can't wear in dst slot.
	if not slot_id.begins_with("spell") and not SpeciesData.can_wear(String(state.get("species", "")), slot_id):
		return false
	if item_slot == "spell" and slot_id.begins_with("spell"):
		return true
	if item_slot == "ring" and slot_id.begins_with("ring"):
		return true
	return item_slot == slot_id

# Centralised drop handler — fires on every drag release in the
# outpost. Reads the DragManager payload + final hover target and
# performs the swap. dropped_on is null when the drop missed every
# valid target (drag returns to source).
func _on_drag_ended(payload: Dictionary, dropped_on: Variant) -> void:
	if dropped_on == null or not is_instance_valid(dropped_on):
		return
	if not (dropped_on is ItemCell):
		return
	var dst: ItemCell = dropped_on
	var src_role: String = String(payload.get("role", ""))
	if dst.role == "paperdoll":
		if src_role == "inventory":
			# Resolve LIVE inv index by instance_id rather than the
			# stale cell-built index (anti-duplication).
			var iid: String = String(payload.get("instance_id", ""))
			var live_idx: int = _live_inv_index(iid)
			if live_idx < 0:
				return
			_drag_equip_from_inv(live_idx, dst.slot_id)
		elif src_role == "paperdoll":
			_drag_swap_slots(String(payload.get("slot_id", "")), dst.slot_id)
		SaveState.save_state(state)
		_render()

func _toggle_favorite(inv_index: int) -> void:
	var inv: Array = state.inventory
	if inv_index < 0 or inv_index >= inv.size():
		return
	var inst: Variant = inv[inv_index]
	if typeof(inst) != TYPE_DICTIONARY:
		return
	inst["favorite"] = not bool(inst.get("favorite", false))
	inv[inv_index] = inst
	SaveState.save_state(state)
	_render_inventory()

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
	var item: Dictionary = items_db[base_id]
	var slot: String = _resolve_equip_slot(String(item.get("slot", "")))
	# Block if the active character's species can't wear this slot.
	# Outpost has no toast; the click silently fails. Player sees the
	# 🚫 icon on the cell that matches.
	if not SpeciesData.can_wear(String(state.get("species", "")), slot):
		return
	# 2H ↔ shield exclusion (mirrors Bot.equip_from_inventory). A 2H
	# weapon clears the shield slot back to inventory; a shield
	# clears a 2H weapon back to inventory. Per-base_type list lives
	# on Bot so paperdoll/UI/tooltip share one source of truth.
	if slot == "weapon" and Bot.is_two_handed_base_type(String(item.get("base_type", ""))):
		var current_shield: Variant = state.equipped.get("shield", null)
		if current_shield != null and typeof(current_shield) == TYPE_DICTIONARY:
			inv.append(current_shield)
			state.equipped["shield"] = null
	elif slot == "shield":
		var current_weapon: Variant = state.equipped.get("weapon", null)
		if current_weapon != null and typeof(current_weapon) == TYPE_DICTIONARY:
			var w_id: String = String(current_weapon.get("base_id", ""))
			if w_id != "" and items_db.has(w_id):
				if Bot.is_two_handed_base_type(String(items_db[w_id].get("base_type", ""))):
					inv.append(current_weapon)
					state.equipped["weapon"] = null
	var current: Variant = state.equipped.get(slot, null)
	inv.remove_at(inv_index)
	if current != null and typeof(current) == TYPE_DICTIONARY:
		inv.append(current)
	state.equipped[slot] = inst
	SaveState.save_state(state)
	_render()

# Tooltip for any slot id, including the species-specific extra
# ring slots (ring2/ring3/ring4). Defaults to SLOT_TOOLTIPS for the
# canonical slot list.
func _tooltip_for_slot(slot_id: String) -> String:
	if slot_id == "ring":
		return "Ring"
	if slot_id.begins_with("ring") and slot_id.length() > 4:
		# ring2 → "Ring II", ring3 → "Ring III", etc. Roman-style for
		# the octopode's tentacle-ring stacking flavor.
		var n: int = int(slot_id.substr(4))
		var roman := ["", "I", "II", "III", "IV", "V"]
		return "Ring %s" % (roman[n] if n < roman.size() else str(n))
	return SLOT_TOOLTIPS.get(slot_id, slot_id.capitalize())

# Resolve the equipped-dict slot id for an item. Most slots are
# 1:1 (helm → helm). Rings need species-aware routing — octopode/
# naga have extra ring slots from slot_conversions. Spells route into
# spell1..spell5 the same way (first empty wins; all-full displaces
# spell1). Mirrors bot.gd::equip_from_inventory.
func _resolve_equip_slot(item_slot: String) -> String:
	if item_slot == "ring":
		var species: String = String(state.get("species", ""))
		for r in SpeciesData.ring_slot_ids(species):
			if state.equipped.get(r, null) == null:
				return r
		return "ring"
	if item_slot == "spell":
		for s in SPELL_SLOTS:
			if state.equipped.get(s, null) == null:
				return s
		return "spell1"  # all full — displace spell1
	return item_slot

func _unequip(slot: String) -> void:
	var current: Variant = state.equipped.get(slot, null)
	if current == null or typeof(current) != TYPE_DICTIONARY:
		return
	state.inventory.append(current)
	state.equipped[slot] = null
	SaveState.save_state(state)
	_render()

# Inventory → paperdoll. Equip exactly into the target slot (no auto-
# routing) and displace whatever was there back to inventory.
func _drag_equip_from_inv(inv_index: int, dst_slot: String) -> void:
	var inv: Array = state.inventory
	if inv_index < 0 or inv_index >= inv.size():
		return
	var inst: Dictionary = inv[inv_index]
	var base_id: String = String(inst.get("base_id", ""))
	if not items_db.has(base_id):
		return
	var item: Dictionary = items_db[base_id]
	# 2H↔shield exclusion still applies even with explicit-slot drops.
	if dst_slot == "weapon" and Bot.is_two_handed_base_type(String(item.get("base_type", ""))):
		var current_shield: Variant = state.equipped.get("shield", null)
		if current_shield != null and typeof(current_shield) == TYPE_DICTIONARY:
			inv.append(current_shield)
			state.equipped["shield"] = null
	elif dst_slot == "shield":
		var current_weapon: Variant = state.equipped.get("weapon", null)
		if current_weapon != null and typeof(current_weapon) == TYPE_DICTIONARY:
			var w_id: String = String(current_weapon.get("base_id", ""))
			if w_id != "" and items_db.has(w_id):
				if Bot.is_two_handed_base_type(String(items_db[w_id].get("base_type", ""))):
					inv.append(current_weapon)
					state.equipped["weapon"] = null
	var prev: Variant = state.equipped.get(dst_slot, null)
	inv.remove_at(inv_index)
	if prev != null and typeof(prev) == TYPE_DICTIONARY:
		inv.append(prev)
	state.equipped[dst_slot] = inst

# Paperdoll → paperdoll. Swap the two slot contents. If src == dst it
# no-ops. If dst is empty, just moves src; if src is empty (shouldn't
# happen because empty cells refuse drag-out), no-ops.
func _drag_swap_slots(src_slot: String, dst_slot: String) -> void:
	if src_slot == "" or src_slot == dst_slot:
		return
	var a: Variant = state.equipped.get(src_slot, null)
	if a == null or typeof(a) != TYPE_DICTIONARY:
		return
	var b: Variant = state.equipped.get(dst_slot, null)
	state.equipped[dst_slot] = a
	state.equipped[src_slot] = b if (b != null and typeof(b) == TYPE_DICTIONARY) else null

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
