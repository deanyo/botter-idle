extends Control

# Spell Showcase screen — authoring/preview tool.
#
# Stages a stationary bot in the middle of the screen with five target
# dummies (three in a line for chain/projectile testing, two clustered
# for nova/cone). Sidebar lists every spell base from items.json filtered
# to the spell slot. Click one → it loads as the bot's spell1 and fires
# every cooldown tick. Right panel exposes params (sprite override,
# damage tweak, recolor preview, archetype-flag toggles).
#
# This is a dev-only scene — never reached during a normal run. Routed
# from the main menu's "Spell Showcase" button. Authoring 2026-06-05.

signal back_pressed

const C := preload("res://scripts/constants.gd")
const STAGE_BG_COL := Color(0.05, 0.05, 0.07, 1.0)
const TILE := C.TILE_SIZE  # 32

var _items_db: Dictionary = {}
var _spell_items: Array = []  # filtered to slot=spell
var _bot: Bot = null
var _dummies: Array[Enemy] = []
var _stage: Node2D = null
var _selected_id: String = ""
var _live_spell: Dictionary = {}  # mutable copy of the selected item
var _fire_timer: float = 0.0
var _fire_interval: float = 1.5  # seconds between auto-casts
var _paused: bool = false

# Right-panel widgets — kept as fields so live mutations rebuild without
# rebuilding the full panel.
var _list_root: VBoxContainer = null
var _params_root: VBoxContainer = null
var _info_lbl: Label = null

func _ready() -> void:
	_items_db = ItemsDb.items()
	for it in _items_db.values():
		if String(it.get("slot", "")) == "spell":
			_spell_items.append(it)
	_spell_items.sort_custom(func(a, b):
		var ka := String(a.get("base_type", "")) + ":" + String(a.get("name", ""))
		var kb := String(b.get("base_type", "")) + ":" + String(b.get("name", ""))
		return ka < kb)
	_build_chrome()
	_build_stage()
	_select_first_spell()

# --- Chrome -----------------------------------------------------------------

func _build_chrome() -> void:
	var view := get_viewport().get_visible_rect().size
	var bg := ColorRect.new()
	bg.color = UITheme.BG_DEEP
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	add_child(bg)
	# Top bar
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 12)
	bar.position = Vector2(16, 12)
	bar.size = Vector2(view.x - 32, 32)
	add_child(bar)
	var title := Label.new()
	title.text = "SPELL SHOWCASE"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", UITheme.COL_AMBER)
	bar.add_child(title)
	_info_lbl = Label.new()
	_info_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_info_lbl.add_theme_color_override("font_color", UITheme.COL_DIM)
	bar.add_child(_info_lbl)
	var fire_btn := Button.new()
	fire_btn.text = "Force fire"
	fire_btn.pressed.connect(_force_fire)
	bar.add_child(fire_btn)
	UITheme.style_button(fire_btn)
	var pause_btn := Button.new()
	pause_btn.text = "Pause"
	pause_btn.toggle_mode = true
	pause_btn.toggled.connect(func(v):
		_paused = v
		pause_btn.text = "Resume" if v else "Pause"
	)
	bar.add_child(pause_btn)
	UITheme.style_button(pause_btn)
	var copy_btn := Button.new()
	copy_btn.text = "Copy spell JSON"
	copy_btn.pressed.connect(_copy_spell_json)
	bar.add_child(copy_btn)
	UITheme.style_button(copy_btn)
	var back_btn := Button.new()
	back_btn.text = "← Back"
	back_btn.pressed.connect(func(): back_pressed.emit())
	bar.add_child(back_btn)
	UITheme.style_button(back_btn)
	# Spell list (left)
	var left := ScrollContainer.new()
	left.position = Vector2(16, 56)
	left.size = Vector2(240, view.y - 72)
	left.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(left)
	_list_root = VBoxContainer.new()
	_list_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_root.add_theme_constant_override("separation", 2)
	left.add_child(_list_root)
	for it in _spell_items:
		_list_root.add_child(_make_spell_row(it))
	# Params panel (right) — built in _refresh_params after a spell is
	# selected. Container reserved here.
	var right := ScrollContainer.new()
	right.position = Vector2(view.x - 360, 56)
	right.size = Vector2(344, view.y - 72)
	right.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(right)
	_params_root = VBoxContainer.new()
	_params_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_params_root.add_theme_constant_override("separation", 8)
	right.add_child(_params_root)

func _make_spell_row(item: Dictionary) -> Control:
	var btn := Button.new()
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	var bt: String = String(item.get("base_type", ""))
	var bt_short: String = bt.replace("spell_", "")
	btn.text = "[%s] %s" % [bt_short, item.get("name", item.get("id", "?"))]
	btn.add_theme_font_size_override("font_size", 11)
	btn.tooltip_text = "id: %s\nbase_type: %s\nrarity: %s" % [
		item.get("id", "?"), bt, item.get("rarity", "?")]
	btn.pressed.connect(_select_spell.bind(String(item.get("id", ""))))
	UITheme.style_button(btn)
	return btn

# --- Stage ------------------------------------------------------------------

func _build_stage() -> void:
	var view := get_viewport().get_visible_rect().size
	# Stage panel sits between the spell list and the params panel.
	# Pure Node2D so we can use world coordinates for the bot + dummies.
	var stage_bg := ColorRect.new()
	stage_bg.color = STAGE_BG_COL
	stage_bg.position = Vector2(272, 56)
	stage_bg.size = Vector2(view.x - 632 - 16, view.y - 72)
	stage_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(stage_bg)
	_stage = Node2D.new()
	# Center the stage origin so cell coords (-N..+N) read symmetrically.
	_stage.position = stage_bg.position + stage_bg.size * 0.5
	add_child(_stage)
	# Spawn the stationary bot.
	_bot = Bot.new()
	_bot.terrain_grid = _build_open_grid()  # all-floor 21x21
	_bot.cell = Vector2i(10, 10)
	_bot.position = Vector2.ZERO
	# Stub _items_db_cache so equip_from_inventory can resolve stats.
	_bot._items_db_cache = _items_db
	_stage.add_child(_bot)
	# Make the bot look beefy so its visuals don't get one-shot.
	_bot.max_hp = 999999
	_bot.hp = _bot.max_hp
	_bot.species_id = "spriggan"
	# Five dummies — three in a horizontal line east of the bot for
	# chain testing, two clustered NE for cone/nova.
	var dummy_offsets: Array[Vector2i] = [
		Vector2i(3, 0), Vector2i(5, 0), Vector2i(7, 0),
		Vector2i(4, -2), Vector2i(5, -3),
	]
	for off in dummy_offsets:
		var d := _make_dummy(off)
		_dummies.append(d)
	# A spell_cooldowns dict so SpellSystem.cooldown_fraction() / process_tick
	# don't error when the showcase spell uses tunables.
	_bot.spell_cooldowns = {"spell1": 0.0}
	_bot.equipped = {}
	# Recompute stats so primary_stat-scaling spells have something to
	# multiply against (str/dex/int defaults to 5/5/5).
	_bot.recompute_stats()

func _build_open_grid() -> Array:
	var g: Array = []
	for y in 21:
		var row: Array = []
		for x in 21:
			row.append(C.T_FLOOR)
		g.append(row)
	return g

func _make_dummy(cell_offset: Vector2i) -> Enemy:
	var e := Enemy.new()
	e.enemy_id = "showcase_dummy"
	e.display_name = "Target Dummy"
	e.max_hp = 9999
	e.hp = e.max_hp
	e.atk = 0  # passive
	e.defense = 0
	e.move_speed = 0.0  # stationary
	e.cell = Vector2i(10, 10) + cell_offset
	e.position = Vector2(cell_offset.x * TILE, cell_offset.y * TILE)
	# Use an existing enemy sprite as a stand-in dummy. Statue is on-theme.
	if ResourceLoader.exists("res://assets/tiles/features/statue_granite.png"):
		e.set_texture(load("res://assets/tiles/features/statue_granite.png"))
	if e.rig:
		e.rig.modulate = Color(0.85, 0.85, 0.85)
	_stage.add_child(e)
	return e

# --- Spell selection / params ----------------------------------------------

func _select_first_spell() -> void:
	if not _spell_items.is_empty():
		_select_spell(String(_spell_items[0].get("id", "")))

func _select_spell(id: String) -> void:
	_selected_id = id
	if not _items_db.has(id):
		return
	# Mutable copy so editor sliders can tweak damage / cooldown without
	# touching the canonical items_db. The fire path reads from
	# _live_spell. 2026-06-05.
	_live_spell = (_items_db[id] as Dictionary).duplicate(true)
	# Reset dummies + fire timer.
	_reset_dummies()
	_fire_timer = 0.0
	_refresh_params()
	if _info_lbl != null:
		_info_lbl.text = "Selected: %s (%s)" % [
			_live_spell.get("name", "?"), _live_spell.get("base_type", "?")]

func _refresh_params() -> void:
	for c in _params_root.get_children():
		c.queue_free()
	if _live_spell.is_empty():
		return
	# Header: base_type + a tiny sprite preview.
	var head := Label.new()
	head.text = String(_live_spell.get("base_type", ""))
	head.add_theme_font_size_override("font_size", 14)
	head.add_theme_color_override("font_color", UITheme.COL_AMBER)
	_params_root.add_child(head)
	var sub := Label.new()
	sub.text = String(_live_spell.get("name", ""))
	sub.add_theme_color_override("font_color", UITheme.COL_DIM)
	_params_root.add_child(sub)
	# Damage min / max
	_add_field("Damage min", str(int(_live_spell.get("damage_min", 0))), func(v):
		_live_spell["damage_min"] = int(v))
	_add_field("Damage max", str(int(_live_spell.get("damage_max", 0))), func(v):
		_live_spell["damage_max"] = int(v))
	_add_field("Cooldown (s)", str(_live_spell.get("spell_cooldown", 1.5)), func(v):
		_live_spell["spell_cooldown"] = float(v))
	# Auto-fire interval (showcase-only — separate from in-game cooldown).
	_add_field("Auto-fire every (s)", str(_fire_interval), func(v):
		_fire_interval = max(0.2, float(v)))
	# Recolor mode picker — same shape as item editor's Look section.
	var modes := ["none", "normal", "colorize", "shimmer", "inverted", "prismatic"]
	var mode_row := HBoxContainer.new()
	mode_row.add_theme_constant_override("separation", 6)
	var mode_lbl := Label.new()
	mode_lbl.text = "Recolor:"
	mode_lbl.add_theme_color_override("font_color", UITheme.COL_DIM)
	mode_row.add_child(mode_lbl)
	var mode_opt := OptionButton.new()
	for i in modes.size():
		mode_opt.add_item(modes[i], i)
	var current_tint: Variant = _live_spell.get("default_tint", null)
	var current_mode: String = "none"
	if typeof(current_tint) == TYPE_DICTIONARY:
		current_mode = String(current_tint.get("mode", "none"))
	mode_opt.selected = max(0, modes.find(current_mode))
	mode_opt.item_selected.connect(func(idx: int):
		var m: String = modes[idx]
		if m == "none":
			_live_spell.erase("default_tint")
		else:
			var t: Dictionary = (_live_spell.get("default_tint", {}) as Dictionary).duplicate()
			if t.is_empty():
				t = {"hue": 0.0, "sat": 1.0, "mode": m}
			else:
				t["mode"] = m
			_live_spell["default_tint"] = t)
	mode_row.add_child(mode_opt)
	_params_root.add_child(mode_row)
	# Hue + sat sliders only when a recolor is active.
	if current_mode != "none":
		_add_slider("Hue", float(current_tint.get("hue", 0.0)), 0, 360, 5, func(v):
			var t: Dictionary = (_live_spell.get("default_tint", {}) as Dictionary).duplicate()
			t["hue"] = v
			_live_spell["default_tint"] = t)
		_add_slider("Saturation", float(current_tint.get("sat", 1.0)), 0, 2, 0.05, func(v):
			var t: Dictionary = (_live_spell.get("default_tint", {}) as Dictionary).duplicate()
			t["sat"] = v
			_live_spell["default_tint"] = t)
	# Archetype affix toggles — read AffixSystem for archetype-family
	# affixes that apply to spells, present them as flag checkboxes.
	var arch_section := Label.new()
	arch_section.text = "Archetype affixes (flags)"
	arch_section.add_theme_color_override("font_color", UITheme.COL_AMBER)
	_params_root.add_child(arch_section)
	var arch_affixes: Array = AffixSystem.affixes_by_family("archetype")
	var implicits: Array = _live_spell.get("implicit_affixes", []) as Array
	for af in arch_affixes:
		var aid: String = String(af.get("id", ""))
		var cb := CheckBox.new()
		cb.text = String(af.get("name", aid))
		cb.button_pressed = implicits.has(aid)
		cb.toggled.connect(func(on: bool):
			var arr: Array = (_live_spell.get("implicit_affixes", []) as Array).duplicate()
			if on:
				if not arr.has(aid):
					arr.append(aid)
			else:
				arr.erase(aid)
			_live_spell["implicit_affixes"] = arr)
		_params_root.add_child(cb)

func _add_field(label: String, val: String, on_change: Callable) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var lbl := Label.new()
	lbl.text = label
	lbl.custom_minimum_size = Vector2(150, 0)
	lbl.add_theme_color_override("font_color", UITheme.COL_DIM)
	row.add_child(lbl)
	var inp := LineEdit.new()
	inp.text = val
	inp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inp.text_submitted.connect(on_change)
	inp.focus_exited.connect(func(): on_change.call(inp.text))
	row.add_child(inp)
	_params_root.add_child(row)

func _add_slider(label: String, val: float, lo: float, hi: float, step: float, on_change: Callable) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var lbl := Label.new()
	lbl.text = label
	lbl.custom_minimum_size = Vector2(110, 0)
	lbl.add_theme_color_override("font_color", UITheme.COL_DIM)
	row.add_child(lbl)
	var slider := HSlider.new()
	slider.min_value = lo
	slider.max_value = hi
	slider.step = step
	slider.value = val
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size = Vector2(120, 0)
	row.add_child(slider)
	var num := Label.new()
	num.custom_minimum_size = Vector2(48, 0)
	num.text = str(val)
	row.add_child(num)
	slider.value_changed.connect(func(v: float):
		num.text = str(v)
		on_change.call(v))
	_params_root.add_child(row)

# --- Fire / dummy lifecycle -------------------------------------------------

func _process(delta: float) -> void:
	if _paused or _live_spell.is_empty():
		return
	_fire_timer += delta
	if _fire_timer >= _fire_interval:
		_fire_timer = 0.0
		_force_fire()
	# Keep dummies alive — regen any HP they lost between auto-fires so
	# the visual loop runs forever. Cheap.
	for d in _dummies:
		if not is_instance_valid(d):
			continue
		if d.hp < d.max_hp:
			d.hp = d.max_hp

func _force_fire() -> void:
	if _bot == null or _live_spell.is_empty():
		return
	# Equip the spell into bot.equipped["spell1"] so the dispatch path
	# reads the right instance — some spell fire functions read affixes
	# off the inst. Quick stamp + re-fire.
	var inst: Dictionary = {
		"base_id": String(_live_spell.get("id", "")),
		"instance_id": "showcase_" + String(_live_spell.get("id", "")),
		"affixes": [],
	}
	_bot.equipped["spell1"] = inst
	# The dispatcher reads from items_db, so swap our live copy in
	# under the spell's id for the duration of the call.
	var saved: Variant = _items_db.get(_live_spell.get("id", ""), null)
	_items_db[String(_live_spell.get("id", ""))] = _live_spell
	SpellSystem.test_fire_spell(_bot, self, _live_spell)
	if saved != null:
		_items_db[String(_live_spell.get("id", ""))] = saved

func _reset_dummies() -> void:
	for d in _dummies:
		if not is_instance_valid(d):
			continue
		d.hp = d.max_hp

# Some fire paths read `dungeon.actor_layer` and `dungeon.enemies` —
# expose them as properties so `self` can stand in for the dungeon node.
var actor_layer: Node2D:
	get: return _stage
var enemies: Array:
	get: return _dummies

# --- Copy spell JSON --------------------------------------------------------

func _copy_spell_json() -> void:
	if _live_spell.is_empty():
		if _info_lbl != null:
			_info_lbl.text = "No spell selected."
		return
	var text: String = JSON.stringify(_live_spell, "  ")
	DisplayServer.clipboard_set(text)
	if _info_lbl != null:
		_info_lbl.text = "Copied %d chars to clipboard — paste back to discuss / merge." % text.length()
