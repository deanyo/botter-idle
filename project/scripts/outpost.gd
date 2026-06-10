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
# Header labels — name + Lv + XP + highest floor live ABOVE the
# StatPanel widget since they're durable progression numbers, not
# stats. The Stats tab itself is fully delegated to StatPanel which
# owns its own row labels.
var lbl_name: Label
var lbl_level: Label
var lbl_xp: Label
var lbl_floor: Label
var _stat_panel_widget: StatPanel = null
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
	# Pre-warm tile textures while the player browses. Dungeon entry
	# would otherwise pay 15-25s of PNG decode + GPU upload at click
	# time on Web GL Compatibility. Spread across multiple deferred
	# frames so the outpost UI stays responsive.
	call_deferred("_prewarm_tiles_async")

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
	_stat_panel_widget = null
	_build_layout()
	_render()

func _exit_tree() -> void:
	if DragManager and DragManager.drag_ended.is_connected(_on_drag_ended):
		DragManager.drag_ended.disconnect(_on_drag_ended)

# Walk every unlocked branch and pre-warm its tile textures into the
# resource cache. One biome per frame keeps the outpost responsive
# while the heavy PNG decode + GPU upload work happens off the
# critical path. By the time the player clicks Deploy, the textures
# the dungeon needs are already resident.
func _prewarm_tiles_async() -> void:
	var unlocked: Array = state.get("unlocked_branches", ["dungeon"])
	for branch_id in unlocked:
		if not is_inside_tree():
			return
		var t0: int = Time.get_ticks_msec()
		var did: bool = BiomeData.prewarm_biome(String(branch_id))
		if did:
			print("[prewarm] biome=%s ms=%d" % [String(branch_id), Time.get_ticks_msec() - t0])
		await get_tree().process_frame

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
	if UILayout.shift_held():
		_show_compare_tooltips(cell)
		_shift_was_held = true

func _process(_delta: float) -> void:
	if _hover_cell == null or not is_instance_valid(_hover_cell):
		return
	# Shift-state polling so the compare panel appears/disappears live.
	var shift_now: bool = UILayout.shift_held()
	if shift_now and not _shift_was_held:
		_show_compare_tooltips(_hover_cell)
	elif not shift_now and _shift_was_held:
		_destroy_compare_tooltips()
	_shift_was_held = shift_now
	# Alt-state polling — re-renders the main tooltip so the extended
	# affix-detail lines toggle live. Tooltip reads Input.is_key_pressed
	# at render time, so we just rebuild content on Alt edge.
	var alt_now: bool = UILayout.alt_held()
	if alt_now != _alt_was_held and _tooltip != null and is_instance_valid(_tooltip):
		_tooltip.render_for(_hover_cell.item, _hover_cell.inst, items_db)
	_alt_was_held = alt_now
	# Keep tooltip glued near cursor so it doesn't hover off the cell.
	if _tooltip != null and is_instance_valid(_tooltip):
		_tooltip.position = _clamp_tooltip_position(_compute_anchor(_hover_cell), _tooltip.size)
	# Re-flow compare tooltips: stacked Y offsets need each panel's
	# actual height. Initial layout assumed 220 per cell which left tall
	# multi-affix rings overlapping each other.
	if _tooltip != null and is_instance_valid(_tooltip) and not _compare_tooltips.is_empty():
		var view: Vector2 = get_viewport().get_visible_rect().size
		var t_right_edge: float = _tooltip.position.x + _tooltip.size.x
		var place_right: bool = t_right_edge + 8.0 + ItemTooltip.TOOLTIP_W <= view.x - 4.0
		var x_offset: float = ItemTooltip.TOOLTIP_W + 8.0 if place_right else -(ItemTooltip.TOOLTIP_W + 8.0)
		var y_offset: float = 0.0
		for cmp in _compare_tooltips:
			if cmp == null or not is_instance_valid(cmp):
				continue
			var pos: Vector2 = _tooltip.position + Vector2(x_offset, y_offset)
			cmp.position = _clamp_tooltip_position(pos, cmp.size)
			y_offset += cmp.size.y + 8.0

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
	# Decide compare placement: right of main tooltip if there's room,
	# otherwise left of it. Main tooltip lives at _tooltip.position.
	# Edge-clamping prevents the compare panel from rendering off-screen
	# (the bug where shift-compare did nothing visible — tooltips were
	# appearing past the right edge of the viewport).
	var view: Vector2 = get_viewport().get_visible_rect().size
	var t_right_edge: float = _tooltip.position.x + ItemTooltip.TOOLTIP_W
	var place_right: bool = t_right_edge + 8.0 + ItemTooltip.TOOLTIP_W <= view.x - 4.0
	var x_offset: float
	if place_right:
		x_offset = ItemTooltip.TOOLTIP_W + 8.0
	else:
		x_offset = -(ItemTooltip.TOOLTIP_W + 8.0)
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
		var pos: Vector2 = _tooltip.position + Vector2(x_offset, y_offset)
		# Clamp to viewport edges so even an awkwardly-placed main
		# tooltip can't push the compare panel off-screen.
		pos.x = clampf(pos.x, 4.0, max(4.0, view.x - ItemTooltip.TOOLTIP_W - 4.0))
		pos.y = clampf(pos.y, 4.0, max(4.0, view.y - 220.0))
		cmp.position = pos
		_compare_tooltips.append(cmp)
		y_offset += 220.0  # rough; actual height resolves async

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
	# Title bar — title centered, but constrained between the End-Run
	# button (left) and Shop button (right) so the buttons can't sit
	# ON TOP of the title text. UI polish 2026-06-05.
	const TITLE_LEFT_RESERVE := 140  # End-Run button + padding
	const TITLE_RIGHT_RESERVE := 140  # Shop button + padding
	var title := Label.new()
	title.text = "OUTPOST"
	title.position = Vector2(TITLE_LEFT_RESERVE, 12)
	title.size = Vector2(view.x - TITLE_LEFT_RESERVE - TITLE_RIGHT_RESERVE, 36)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.clip_text = true
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
		banner.clip_text = true
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
	# Three panes between title (y≈56) and the picker. When the
	# run-in-progress banner is showing it spans y=48..72, so push the
	# pane top down to y=80 to avoid clipping it under the panels.
	# 2026-06-06.
	var top_y: int = 80 if bool(state.get("run_active", false)) else 60
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
	# Card-bound clipping: btn itself clips so any child label (name,
	# tier, chips, cr) can never bleed past the card rect on long branch
	# names like "Pandemonium" or "Dis (Hellish Vault)".
	btn.clip_contents = true
	var name_lbl := Label.new()
	name_lbl.text = pretty
	name_lbl.position = Vector2(8, 8)
	name_lbl.size = Vector2(_BRANCH_CARD_W - 16, 24)
	name_lbl.clip_text = true
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
	tier_lbl.clip_text = true
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
			chip.clip_text = true
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
		lbl.size = Vector2(w - 24, 22)
		lbl.clip_text = true
		lbl.add_theme_font_size_override("font_size", 14)
		lbl.add_theme_color_override("font_color", COL_DIM)
		add_child(lbl)

func _build_paperdoll_pane(x: int, y: int, w: int, h: int) -> void:
	_make_panel(x, y, w, h, "Equipment")
	var gap := 8
	var inner_x := x + 16
	var inner_y := y + 36
	var inner_w := w - 32
	var inner_h := h - 52
	# Slot size shrinks to fit the right column (5 slots) AND the
	# bottom row (5 slots). Was a hard 56px which caused gloves to drop
	# off the right column when sprite_h was constrained, and bottom
	# row to overflow on narrow panes. UI polish 2026-06-05.
	# Reserve ~50% of inner_h for the bot sprite + spell row, the rest
	# for the right column. spell row eats 1 slot+gap+label, bottom
	# row eats 1 slot+gap.
	const _RIGHT_COLUMN_COUNT := 5  # PAPERDOLL_RIGHT_COLUMN.size()
	const _BOTTOM_ROW_COUNT := 5    # PAPERDOLL_BOTTOM_ROW.size()
	var max_slot_by_w: int = int((inner_w - gap * (_BOTTOM_ROW_COUNT - 1)) / _BOTTOM_ROW_COUNT)
	# Right column needs to fit 5 slots stacked under the sprite.
	# Spell row eats slot+label_h+gap below the bottom row. So total
	# vertical budget is sprite_h + bottom_slot + spell_label_h +
	# spell_slot + 3×gap.
	var max_slot_by_h: int = int((inner_h - 16 - gap * 4) / (_RIGHT_COLUMN_COUNT + 2))
	# This ↑ means: sprite_h ≥ right_col_slots × slot + (n-1)×gap.
	# We pick a slot size that fits both constraints, then sprite_h
	# is whatever's left.
	var slot: int = clampi(mini(max_slot_by_w, max_slot_by_h), 36, PAPERDOLL_SLOT_SIZE)
	# Sprite top-left, right column slots, bottom row slots.
	var sprite_w: int = inner_w - slot - gap
	var sprite_h: int = slot * _RIGHT_COLUMN_COUNT + gap * (_RIGHT_COLUMN_COUNT - 1)
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
	# Right column. The shrink-to-fit `slot` math above guarantees all
	# 5 cells fit; no silent clipping.
	var right_x: int = inner_x + sprite_w + gap
	for i in resolved_right.size():
		_make_paperdoll_slot(resolved_right[i], right_x, inner_y + i * (slot + gap), slot)
	# Bottom row. Same — slot is sized so the row fits.
	var row_y: int = inner_y + sprite_h + gap
	for i in resolved_bottom.size():
		_make_paperdoll_slot(resolved_bottom[i], inner_x + i * (slot + gap), row_y, slot)
	# Spell row — 5 autocast cells under the gear row. Wraps to a
	# second row if the pane is too narrow to fit all 5 across.
	# UI polish 2026-06-04: previously spell cells overflowed silently
	# when inner_w < 5*(slot+gap). Now we shrink + wrap.
	var spell_label_y: int = row_y + slot + gap
	var spell_lbl := Label.new()
	spell_lbl.text = "Spells"
	spell_lbl.position = Vector2(inner_x, spell_label_y)
	spell_lbl.add_theme_font_size_override("font_size", 11)
	spell_lbl.add_theme_color_override("font_color", COL_DIM)
	add_child(spell_lbl)
	var spell_row_y: int = spell_label_y + 16
	# Pick the largest cell size that lets all 5 fit in one row at
	# inner_w. Clamp 32..PAPERDOLL_SLOT_SIZE so it never goes too tiny.
	# If even the minimum doesn't fit 5 across, wrap to two rows.
	var spell_slot: int = clampi(int((inner_w - gap * 4) / 5), 32, PAPERDOLL_SLOT_SIZE)
	var per_row: int = mini(SPELL_SLOTS.size(), maxi(1, (inner_w + gap) / (spell_slot + gap)))
	for i in SPELL_SLOTS.size():
		var col: int = i % per_row
		var rowi: int = i / per_row
		var sx_spell: int = inner_x + col * (spell_slot + gap)
		var sy_spell: int = spell_row_y + rowi * (spell_slot + gap)
		_make_paperdoll_slot(SPELL_SLOTS[i], sx_spell, sy_spell, spell_slot)

func _make_paperdoll_slot(slot_id: String, x: int, y: int, override_size: int = 0) -> void:
	# Spell row passes a smaller override_size when the pane is narrow
	# so the 5 spell cells fit without overflowing. Defaults to the
	# canonical PAPERDOLL_SLOT_SIZE (56) for gear cells.
	var slot := override_size if override_size > 0 else PAPERDOLL_SLOT_SIZE
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
	cell.slot_label = _tooltip_for_slot(slot_id)
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
	# 2026-06-06 redesign: was a single jammed column with "Bot" / "Bot
	# the Adventurer" repeated in the panel header, name label, and
	# tooltip. Now split into TabContainer with three tabs:
	#   Stats — name (one place), level/xp/floor, primary stats, derived
	#           combat stats, instructions
	#   Weapon — equipped weapon stats, damage type, weapon flavor
	#   Upgrades — gold-sink permanent purchases (was a tiny sub-scroll;
	#              now gets the full panel height)
	_make_panel(x, y, w, h, "Character")
	var inner_x: int = x + 12
	var inner_y: int = y + 36
	var inner_w: int = w - 24
	var inner_h: int = h - 48
	var tabs := TabContainer.new()
	tabs.position = Vector2(inner_x, inner_y)
	tabs.size = Vector2(inner_w, inner_h)
	tabs.tabs_visible = true
	tabs.clip_contents = true
	add_child(tabs)
	_build_stats_tab(tabs, inner_w, inner_h)
	_build_weapon_tab(tabs, inner_w, inner_h)
	_build_upgrades_tab(tabs, inner_w, inner_h)
	_build_instructions_tab(tabs, inner_w, inner_h)

func _build_stats_tab(tabs: TabContainer, w: int, h: int) -> void:
	# Stats tab — fully delegated to StatPanel. Same widget the HUD
	# uses, fed by the same StatCalc.compute() output, so the two
	# screens always show identical numbers. The header (name / Lv /
	# XP / highest floor) lives ABOVE the panel since it's durable
	# progression info, not stats. UI consistency pass 2026-06-06.
	var page := Control.new()
	page.name = "Stats"
	page.custom_minimum_size = Vector2(w, h - 36)
	page.clip_contents = true
	tabs.add_child(page)
	var sx: int = 8
	var sy: int = 8
	lbl_name = _add_stat_to(page, sx, sy, UITheme.FS_HEADER, COL_AMBER, "Adventurer"); sy += 28
	lbl_level = _add_stat_to(page, sx, sy, UITheme.FS_BODY, COL_DIM, "Level —"); sy += 20
	lbl_xp = _add_stat_to(page, sx, sy, UITheme.FS_SMALL, COL_DIM, "XP —"); sy += 18
	lbl_floor = _add_stat_to(page, sx, sy, UITheme.FS_SMALL, COL_DIM, "Highest floor: —"); sy += 24
	_stat_panel_widget = StatPanel.new()
	_stat_panel_widget.position = Vector2(0, sy)
	_stat_panel_widget.size = Vector2(w, h - 36 - sy)
	_stat_panel_widget.editable = true
	_stat_panel_widget.alloc_plus_cb = Callable(self, "_on_stat_plus_pressed")
	_stat_panel_widget.alloc_minus_cb = Callable(self, "_on_stat_minus_pressed")
	_stat_panel_widget.alloc_reset_cb = Callable(self, "_on_stat_reset_pressed")
	page.add_child(_stat_panel_widget)

# Tab 4 (new): Bot Instructions — pickup filter + inventory cap readout.
# Was a "Bot Instructions" section at the bottom of the Stats tab; moved
# to its own tab so the Stats tab is purely numbers + attributes.
# UI consistency pass 2026-06-06.
func _build_instructions_tab(tabs: TabContainer, w: int, h: int) -> void:
	var page := Control.new()
	page.name = "Instructions"
	page.custom_minimum_size = Vector2(w, h - 36)
	page.clip_contents = true
	tabs.add_child(page)
	var sx: int = 8
	var sy: int = 8
	_add_section(page, sx, sy, "Loot Pickup"); sy += 22
	var pickup_lbl := UITheme.label("Auto-pickup rarity threshold", UITheme.FS_SMALL, COL_DIM)
	pickup_lbl.position = Vector2(sx, sy)
	pickup_lbl.size = Vector2(w - 16, 18)
	pickup_lbl.clip_text = true
	page.add_child(pickup_lbl); sy += 22
	var filter_btn := OptionButton.new()
	filter_btn.position = Vector2(sx, sy)
	filter_btn.size = Vector2(w - 16, 28)
	for filter_name in ["Common+ (everything)", "Uncommon+", "Rare+", "Epic+", "Legendary only"]:
		filter_btn.add_item(filter_name)
	var filter_idx: int = LootDrop.RARITY_RANK.get(String(state.get("loot_filter", "common")), 0)
	filter_btn.selected = filter_idx
	filter_btn.item_selected.connect(_on_loot_filter_changed)
	page.add_child(filter_btn); sy += 36
	_add_section(page, sx, sy, "Inventory"); sy += 22
	var inv_count: int = int(state.get("inventory", []).size())
	var cap: int = int(state.get("inventory_cap", 200)) + int(BotUpgrades.total_for_stat(state, "inventory_cap"))
	var inv_lbl := _add_stat_to(page, sx, sy, UITheme.FS_BODY, COL_DIM, "Carrying %d / %d" % [inv_count, cap])
	inv_lbl.size = Vector2(w - 16, 20)
	inv_lbl.clip_text = true; sy += 22
	var inv_hint := UITheme.label("Pouch upgrade increases the cap.", UITheme.FS_SMALL, Color(0.5, 0.45, 0.35))
	inv_hint.position = Vector2(sx, sy)
	inv_hint.size = Vector2(w - 16, 18)
	inv_hint.clip_text = true
	page.add_child(inv_hint)

# Tab 2: Weapon — embeds an ItemTooltip rendered for the equipped
# weapon. Single renderer for "describe an item" — same widget the
# hover tooltip uses, so the tab matches what the player sees on
# inventory hover. UI consistency pass 2026-06-06.
func _build_weapon_tab(tabs: TabContainer, w: int, h: int) -> void:
	var page := Control.new()
	page.name = "Weapon"
	page.custom_minimum_size = Vector2(w, h - 36)
	page.clip_contents = true
	tabs.add_child(page)
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(0, 0)
	scroll.size = Vector2(w, h - 36)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page.add_child(scroll)
	var weapon_inst: Variant = state.get("equipped", {}).get("weapon", null)
	var item: Dictionary = {}
	if typeof(weapon_inst) == TYPE_DICTIONARY:
		item = items_db.get(String(weapon_inst.get("base_id", "")), {})
	if item.is_empty():
		var none_lbl := UITheme.label("No weapon equipped.", UITheme.FS_BODY, COL_DIM)
		none_lbl.position = Vector2(8, 8)
		none_lbl.size = Vector2(w - 16, 22)
		none_lbl.clip_text = true
		scroll.add_child(none_lbl)
		return
	var tt := ItemTooltip.new()
	tt.static_mode = true  # no glow pulse / particles for the embedded tab
	scroll.add_child(tt)
	tt.render_for(item, weapon_inst, items_db)

# Tab 3: Upgrades — full panel height for the upgrade list.
func _build_upgrades_tab(tabs: TabContainer, w: int, h: int) -> void:
	var page := Control.new()
	page.name = "Upgrades"
	page.custom_minimum_size = Vector2(w, h - 36)
	tabs.add_child(page)
	# 8px inset, scroll fills the rest of the page.
	_build_upgrades_section_in(page, 8, 8, w - 16, h - 52)

# Helpers used by the tabbed stats pane.
func _add_stat_to(parent: Node, x: int, y: int, font_size: int, color: Color, text: String) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.position = Vector2(x, y)
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", color)
	parent.add_child(lbl)
	return lbl

func _add_section(parent: Node, x: int, y: int, text: String) -> void:
	var hdr := Label.new()
	hdr.text = text
	hdr.position = Vector2(x, y)
	hdr.add_theme_font_size_override("font_size", 12)
	hdr.add_theme_color_override("font_color", Color(0.55, 0.50, 0.36))
	parent.add_child(hdr)
	# Underline.
	var line := ColorRect.new()
	line.color = Color(0.35, 0.30, 0.18, 0.45)
	line.position = Vector2(x, y + 16)
	line.size = Vector2(120, 1)
	parent.add_child(line)

func _build_upgrades_section_in(parent: Node, x: int, y: int, w: int, h: int) -> void:
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(x, y)
	scroll.size = Vector2(w, h)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	parent.add_child(scroll)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)
	for def in BotUpgrades.all():
		box.add_child(_make_upgrade_row(def))

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
	# Refresh the bought row + every other row's button (gold may have
	# crossed below another upgrade's threshold) + re-render stats so
	# the Gold row + any upgrade-affected stats (HP / Crit / etc) tick.
	_refresh_upgrade_row(id)
	for other_id in _upgrade_rows.keys():
		if other_id != id:
			_refresh_upgrade_row(other_id)
	_render_stats()

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
	# Filter chip row — wrap into a HFlowContainer so on narrow panes
	# the dropdowns reflow onto a second line instead of overflowing
	# off the right edge of the inventory pane. Reserve up to 2 rows
	# of vertical space for the filters before the grid starts.
	# UI polish 2026-06-05.
	var chip_row := HFlowContainer.new()
	chip_row.position = Vector2(inner_x, inner_y)
	chip_row.size = Vector2(inner_w, 64)  # 2 rows max
	chip_row.add_theme_constant_override("h_separation", 6)
	chip_row.add_theme_constant_override("v_separation", 4)
	add_child(chip_row)
	_build_filter_chips(chip_row)
	# Wait one frame for HFlowContainer to lay out, then read its
	# actual height to position the grid below.
	# Grid sits below the chip row. Reserve 64px so a wrapped 2-row
	# chip layout still fits cleanly.
	var grid_y: int = inner_y + 68
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

func _build_filter_chips(parent: Container) -> void:
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
	# Theme any buttons spawned during render (filter chips, sort
	# buttons, deploy button). UI polish 2026-06-04.
	UITheme.style_all_buttons(self)

func _render_stats() -> void:
	# Single-source-of-truth path: feed StatCalc.compute the same
	# inputs the bot uses; pass the result dict to StatPanel.render.
	# Pre-2026-06-06 outpost ignored meta_mult, Quality, BotUpgrades,
	# species seeds, and worn-tag passives — so a Pristine Ancient Iron
	# Dagger read different stats here vs in-run. Now both screens
	# pull from the same canonical formula.
	if lbl_level != null and is_instance_valid(lbl_level):
		lbl_level.text = "Level %d" % int(state.level)
	if lbl_xp != null and is_instance_valid(lbl_xp):
		lbl_xp.text = "XP %d" % int(state.xp)
	if lbl_floor != null and is_instance_valid(lbl_floor):
		lbl_floor.text = "Highest floor: %d" % int(state.highest_floor)
	if _stat_panel_widget == null or not is_instance_valid(_stat_panel_widget):
		return
	var stats: Dictionary = StatCalc.compute(
		state.get("equipped", {}), items_db, state, String(state.get("species", "")),
		int(state.get("level", 1)), int(state.get("xp", 0)), int(state.get("gold", 0)),
		[],  # outpost is between-runs — no live blessings
	)
	_stat_panel_widget.render(stats)

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
	if slot == "weapon" and Bot.is_two_handed(item):
		var current_shield: Variant = state.equipped.get("shield", null)
		if current_shield != null and typeof(current_shield) == TYPE_DICTIONARY:
			inv.append(current_shield)
			state.equipped["shield"] = null
	elif slot == "shield":
		var current_weapon: Variant = state.equipped.get("weapon", null)
		if current_weapon != null and typeof(current_weapon) == TYPE_DICTIONARY:
			var w_id: String = String(current_weapon.get("base_id", ""))
			if w_id != "" and items_db.has(w_id):
				if Bot.is_two_handed(items_db[w_id]):
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
	# 2H/dual ↔ shield exclusion still applies even with explicit-slot
	# drops. is_two_handed() folds in dual-wield uniques.
	if dst_slot == "weapon" and Bot.is_two_handed(item):
		var current_shield: Variant = state.equipped.get("shield", null)
		if current_shield != null and typeof(current_shield) == TYPE_DICTIONARY:
			inv.append(current_shield)
			state.equipped["shield"] = null
	elif dst_slot == "shield":
		var current_weapon: Variant = state.equipped.get("weapon", null)
		if current_weapon != null and typeof(current_weapon) == TYPE_DICTIONARY:
			var w_id: String = String(current_weapon.get("base_id", ""))
			if w_id != "" and items_db.has(w_id):
				if Bot.is_two_handed(items_db[w_id]):
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
