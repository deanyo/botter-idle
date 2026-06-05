extends Control

# Item Generator — produces NEW item bases (recolored / reflavored
# variants of existing bases) to grow the items.json pool. Not a
# random-loot-roller — these are *base item definitions* you can
# paste into project/data/items.json.
#
# Each generated item:
# - Picks a parent base (random across all gear slots)
# - Picks a flavor (Crimson, Verdant, Voidwrought, Gilded, Prismatic,
#   etc.) — each flavor has a hue range, recolor mode, name prefix,
#   added flavor_tag, and an optional rarity bump.
# - Synthesizes id = "{parent_id}_{flavor_suffix}", name =
#   "{prefix} {parent_name}".
# - Copies the parent's combat stats untouched (so the new variant
#   slots cleanly into the same item_tier curve) but adds the
#   flavor's `default_tint` and flavor_tag.
#
# The screen shows side-by-side: parent (stock visual) vs the new
# variant (tinted visual), as inventory icon + on-bot paperdoll.
#
# Click ★ to select. Export Selected writes ready-to-paste JSON
# fragments to user://generated_items.json + clipboard.

signal back_pressed

const _GEAR_SLOTS := ["weapon", "armor", "helm", "shield", "boots", "gloves", "cloak", "ring", "amulet"]
const _ITEM_PREVIEW_PX := 80
const _COLUMNS := 5  # 5 wide → 20 rows for 100

# Curated flavor table. Each entry produces a thematically-distinct
# variant. hue is a range in degrees (0-360); mode is the recolor
# shader mode; suffix becomes part of the id; prefix becomes part of
# the name; tag is appended to flavor_tags (or "" for no tag);
# colorize_rgb is required for mode="colorize" (mixes toward this color
# instead of hue-rotating, for white-base sprites).
const _FLAVORS := [
	# id-suffix, prefix-word, hue-min, hue-max, sat-min, sat-max, mode, flavor_tag, colorize_rgb_or_null, rarity_bump
	["crimson",     "Crimson",     350.0, 15.0,  1.0, 1.3, "normal",    "fire",      null,                0],
	["bloodstained","Bloodstained",350.0, 10.0,  0.8, 1.0, "normal",    "vampiric",  null,                1],
	["verdant",     "Verdant",     100.0, 140.0, 0.9, 1.2, "normal",    "",          null,                0],
	["mossy",       "Mossy",       80.0,  120.0, 0.6, 0.9, "normal",    "poison",    null,                0],
	["azure",       "Azure",       200.0, 240.0, 0.9, 1.2, "normal",    "cold",      null,                0],
	["frostbound",  "Frostbound",  190.0, 220.0, 0.7, 1.0, "shimmer",   "cold",      null,                1],
	["voidwrought", "Voidwrought", 270.0, 310.0, 0.9, 1.2, "normal",    "dark",      null,                1],
	["shadowed",    "Shadowed",    260.0, 290.0, 0.5, 0.8, "normal",    "dark",      null,                0],
	["gilded",      "Gilded",      40.0,  55.0,  0.9, 1.2, "shimmer",   "holy",      null,                1],
	["sunsteel",    "Sunsteel",    35.0,  50.0,  0.7, 1.0, "shimmer",   "holy",      null,                1],
	["stormtouched","Stormtouched",220.0, 260.0, 0.8, 1.1, "shimmer",   "lightning", null,                1],
	["embered",     "Embered",     15.0,  30.0,  0.9, 1.2, "shimmer",   "fire",      null,                0],
	["inverse",     "Inverse",     0.0,   360.0, 0.7, 1.0, "inverted",  "",          null,                1],
	["twisted",     "Twisted",     0.0,   360.0, 0.6, 0.9, "inverted",  "shadow",    null,                1],
	["prismatic",   "Prismatic",   0.0,   360.0, 1.0, 1.0, "prismatic", "",          null,                2],
	["pale",        "Pale",        0.0,   0.0,   0.0, 0.0, "colorize",  "",          [0.92, 0.92, 0.96],  0],
	["bone",        "Bone",        0.0,   0.0,   0.0, 0.0, "colorize",  "",          [0.95, 0.92, 0.78],  0],
	["obsidian",    "Obsidian",    0.0,   0.0,   0.0, 0.0, "colorize",  "dark",      [0.15, 0.13, 0.18],  1],
	["ironclad",    "Ironclad",    0.0,   0.0,   0.0, 0.0, "colorize",  "",          [0.55, 0.58, 0.62],  0],
	["coppersworn", "Coppersworn", 20.0,  30.0,  0.6, 0.8, "normal",    "",          null,                0],
	["jadeforged",  "Jade-forged", 130.0, 160.0, 0.8, 1.1, "shimmer",   "poison",    null,                1],
	["rosegold",    "Rose-gold",   330.0, 350.0, 0.7, 1.0, "shimmer",   "holy",      null,                1],
	["nightblue",   "Nightblue",   215.0, 235.0, 0.9, 1.2, "normal",    "",          null,                0],
	["umbral",      "Umbral",      0.0,   0.0,   0.0, 0.0, "colorize",  "shadow",    [0.25, 0.20, 0.30],  1],
	["spectral",    "Spectral",    180.0, 200.0, 0.5, 0.8, "shimmer",   "",          null,                1],
]

const _RARITY_TIERS := ["common", "uncommon", "rare", "epic", "legendary"]

var _items_db: Dictionary = {}
var _all_bases: Array = []
var _generated: Array = []  # Array of new item DEFs (full base dicts, not instances)
var _selected: Dictionary = {}
var _grid: GridContainer = null
var _scroll: ScrollContainer = null
var _stats_lbl: Label = null
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.randomize()
	_items_db = ItemsDb.items()
	for it in _items_db.values():
		var slot: String = String(it.get("slot", ""))
		# Filter to gear-with-tile only — jewellery sometimes lacks
		# a paperdoll overlay, but inventory icons all work.
		if slot in _GEAR_SLOTS and String(it.get("tile", "")) != "":
			_all_bases.append(it)
	_build_chrome()
	_generate_batch(100)

# --- chrome / layout -------------------------------------------------------

func _build_chrome() -> void:
	var view := get_viewport().get_visible_rect().size
	var bg := ColorRect.new()
	bg.color = UITheme.BG_DEEP
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	add_child(bg)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 12)
	bar.position = Vector2(16, 12)
	bar.size = Vector2(view.x - 32, 32)
	add_child(bar)
	var title := Label.new()
	title.text = "ITEM GENERATOR"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", UITheme.COL_AMBER)
	bar.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "— recolored / reflavored variants of existing bases (paste into items.json)"
	subtitle.add_theme_font_size_override("font_size", 12)
	subtitle.add_theme_color_override("font_color", UITheme.COL_DIM)
	bar.add_child(subtitle)
	_stats_lbl = Label.new()
	_stats_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stats_lbl.add_theme_color_override("font_color", UITheme.COL_DIM)
	bar.add_child(_stats_lbl)
	var regen_btn := Button.new()
	regen_btn.text = "↺ Regenerate 100"
	regen_btn.tooltip_text = "Roll a fresh batch of 100 new item variants."
	regen_btn.pressed.connect(func(): _generate_batch(100))
	bar.add_child(regen_btn)
	UITheme.style_button(regen_btn)
	var clear_btn := Button.new()
	clear_btn.text = "Clear selection"
	clear_btn.pressed.connect(_clear_selection)
	bar.add_child(clear_btn)
	UITheme.style_button(clear_btn)
	var export_btn := Button.new()
	export_btn.text = "⬇ Export selected"
	export_btn.tooltip_text = "Write the selected variants as items.json fragments → user://generated_items.json + clipboard."
	export_btn.pressed.connect(_export_selected)
	bar.add_child(export_btn)
	UITheme.style_button(export_btn)
	var back_btn := Button.new()
	back_btn.text = "← Back"
	back_btn.pressed.connect(func(): back_pressed.emit())
	bar.add_child(back_btn)
	UITheme.style_button(back_btn)
	# Help row
	var help := Label.new()
	help.text = "Each tile shows STOCK | NEW. Click ★ to select keepers; Export drops them as ready-to-paste JSON. Re-roll for a fresh batch."
	help.position = Vector2(16, 48)
	help.size = Vector2(view.x - 32, 18)
	help.add_theme_color_override("font_color", UITheme.COL_DIM)
	help.add_theme_font_size_override("font_size", 12)
	add_child(help)
	# Scroll + grid
	_scroll = ScrollContainer.new()
	_scroll.position = Vector2(16, 76)
	_scroll.size = Vector2(view.x - 32, view.y - 92)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_scroll)
	_grid = GridContainer.new()
	_grid.columns = _COLUMNS
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", 10)
	_grid.add_theme_constant_override("v_separation", 10)
	_scroll.add_child(_grid)

# --- generation ------------------------------------------------------------

func _generate_batch(count: int) -> void:
	_generated.clear()
	_selected.clear()
	# Track id collisions inside this batch so two rolls don't both
	# produce e.g. "long_sword_3_crimson".
	var used_ids: Dictionary = {}
	var attempts: int = 0
	while _generated.size() < count and attempts < count * 6:
		attempts += 1
		var item_def: Dictionary = _make_variant()
		if item_def.is_empty():
			continue
		var new_id: String = String(item_def.get("id", ""))
		if new_id == "" or used_ids.has(new_id) or _items_db.has(new_id):
			continue
		used_ids[new_id] = true
		_generated.append(item_def)
	_render_grid()

# Build one new variant: pick parent + flavor, synthesize a new
# {id, name, tile, default_tint, ...stats} block.
func _make_variant() -> Dictionary:
	if _all_bases.is_empty() or _FLAVORS.is_empty():
		return {}
	var parent: Dictionary = _all_bases[_rng.randi_range(0, _all_bases.size() - 1)]
	var flavor: Array = _FLAVORS[_rng.randi_range(0, _FLAVORS.size() - 1)]
	# Skip flavors that would fight an existing default_tint on the
	# parent (e.g. parent already "Crimson" in design — applying
	# another tint reads muddy). We fall back to inverted/prismatic/
	# colorize since those override the underlying color.
	var parent_has_tint: bool = typeof(parent.get("default_tint", null)) == TYPE_DICTIONARY
	var mode: String = String(flavor[6])
	if parent_has_tint and mode == "normal":
		# Re-roll once to a non-normal flavor; if that fails, give up.
		var alt: Array = _FLAVORS[_rng.randi_range(0, _FLAVORS.size() - 1)]
		if String(alt[6]) == "normal":
			return {}
		flavor = alt
		mode = String(flavor[6])
	var suffix: String = String(flavor[0])
	var prefix: String = String(flavor[1])
	# Build id — strip parent's existing flavor suffix if any (to avoid
	# "long_sword_crimson_voidwrought") by just appending. items.json
	# id collisions are rejected upstream, so this stays safe.
	var parent_id: String = String(parent.get("id", ""))
	var new_id: String = "%s_%s" % [parent_id, suffix]
	var parent_name: String = String(parent.get("name", parent_id))
	# Strip a trailing rarity-prefix word from parent name when its
	# rarity is "uncommon"/"rare"/etc — the result reads cleaner. But
	# for v1 just prepend.
	var new_name: String = "%s %s" % [prefix, parent_name]
	# Build tint dict.
	var tint: Dictionary = {}
	if mode == "colorize":
		var rgb: Array = flavor[8]
		tint = {
			"hue": 0.0,
			"sat": 1.0,
			"mode": "colorize",
			"target_rgb": [float(rgb[0]), float(rgb[1]), float(rgb[2])],
		}
	elif mode == "prismatic":
		tint = {"hue": _rng.randf_range(0.0, 360.0), "sat": 1.0, "mode": "prismatic"}
	elif mode == "inverted":
		tint = {"hue": _rng.randf_range(float(flavor[2]), float(flavor[3])), "sat": _rng.randf_range(float(flavor[4]), float(flavor[5])), "mode": "inverted"}
	elif mode == "shimmer":
		tint = {"hue": _wrapped_hue(float(flavor[2]), float(flavor[3])), "sat": _rng.randf_range(float(flavor[4]), float(flavor[5])), "mode": "shimmer"}
	else:
		tint = {"hue": _wrapped_hue(float(flavor[2]), float(flavor[3])), "sat": _rng.randf_range(float(flavor[4]), float(flavor[5])), "mode": "normal"}
	# Rarity — bump by flavor's rarity_bump, capped at legendary.
	var parent_rarity: String = String(parent.get("rarity", "common"))
	var rarity_idx: int = _RARITY_TIERS.find(parent_rarity)
	if rarity_idx < 0:
		rarity_idx = 0
	var bump: int = int(flavor[9])
	rarity_idx = clampi(rarity_idx + bump, 0, _RARITY_TIERS.size() - 1)
	var new_rarity: String = _RARITY_TIERS[rarity_idx]
	# Flavor tags — keep parent's, add the flavor's.
	var tags: Array = []
	for t in parent.get("flavor_tags", []):
		tags.append(String(t))
	var added_tag: String = String(flavor[7])
	if added_tag != "" and not tags.has(added_tag):
		tags.append(added_tag)
	# Build the final base dict — copy combat-relevant fields directly
	# from parent so the new variant slots cleanly into the same
	# tier/curve. We override id, name, rarity, flavor_tags,
	# default_tint, lore. Drop default_tint and overlay from parent
	# (parent's own tint or overlay would override our new one).
	var keep_fields: Array = [
		"slot", "tile", "base_type", "weapon_class", "damage_min",
		"damage_max", "damage_type", "speed", "armor", "evasion",
		"item_tier", "drop_weights", "enchant_chance", "enchant_pool",
		"implicit_affixes", "affix_pool", "unique", "overlay",
		"hp", "atk", "def",
	]
	var def: Dictionary = {
		"id": new_id,
		"name": new_name,
		"rarity": new_rarity,
		"flavor_tags": tags,
		"default_tint": tint,
		"lore": _flavor_lore(prefix, parent_name),
	}
	for k in keep_fields:
		if parent.has(k):
			def[k] = parent[k]
	# Stash the parent for the side-by-side preview (won't be exported).
	def["_parent_id"] = parent_id
	def["_parent_name"] = parent_name
	def["_flavor_suffix"] = suffix
	return def

# Wrap hue ranges that cross 0/360 (e.g. crimson 350→15 means red).
func _wrapped_hue(h_min: float, h_max: float) -> float:
	if h_min <= h_max:
		return _rng.randf_range(h_min, h_max)
	# Cross-zero wrap: pick from [h_min, 360) ∪ [0, h_max]
	var span_high: float = 360.0 - h_min
	var span_low: float = h_max
	var pick: float = _rng.randf_range(0.0, span_high + span_low)
	if pick < span_high:
		return h_min + pick
	return pick - span_high

func _flavor_lore(prefix: String, parent_name: String) -> String:
	# Single-line lore. Generic enough that any flavor + slot reads
	# fine without authoring per-flavor sentences.
	return "A %s reflavor of the standard %s." % [prefix.to_lower(), parent_name.to_lower()]

# --- grid render -----------------------------------------------------------

func _render_grid() -> void:
	if _grid == null:
		return
	for c in _grid.get_children():
		c.queue_free()
	for i in _generated.size():
		_grid.add_child(_make_cell(i, _generated[i]))
	if _stats_lbl != null:
		_stats_lbl.text = "%d generated · %d selected" % [_generated.size(), _selected.size()]

func _make_cell(idx: int, def: Dictionary) -> Control:
	var slot_id: String = String(def.get("slot", ""))
	var rarity: String = String(def.get("rarity", "common"))
	var box := PanelContainer.new()
	var sb := _stylebox_for(rarity, _selected.has(idx))
	box.add_theme_stylebox_override("panel", sb)
	box.custom_minimum_size = Vector2(_ITEM_PREVIEW_PX * 2 + 32, _ITEM_PREVIEW_PX + 78)
	box.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			_toggle_select(idx))
	box.mouse_filter = Control.MOUSE_FILTER_STOP
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	box.add_child(v)
	# Header — variant name in rarity color, parent name beneath in dim.
	var name_lbl := Label.new()
	name_lbl.text = String(def.get("name", "?"))
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.add_theme_font_size_override("font_size", 11)
	name_lbl.add_theme_color_override("font_color", UITheme.rarity_color(rarity))
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.clip_text = true
	v.add_child(name_lbl)
	var parent_lbl := Label.new()
	parent_lbl.text = "from " + String(def.get("_parent_name", "?"))
	parent_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent_lbl.add_theme_font_size_override("font_size", 9)
	parent_lbl.add_theme_color_override("font_color", UITheme.COL_DIM)
	v.add_child(parent_lbl)
	# Side-by-side: stock parent (no tint) vs new variant (tinted).
	var previews := HBoxContainer.new()
	previews.add_theme_constant_override("separation", 4)
	previews.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(previews)
	var parent_def: Dictionary = _items_db.get(String(def.get("_parent_id", "")), {})
	# Stock side — parent rendered with whatever default it has.
	previews.add_child(_build_preview_pair(parent_def, slot_id, false))
	# Arrow.
	var arrow := Label.new()
	arrow.text = "→"
	arrow.add_theme_color_override("font_color", UITheme.COL_DIM)
	arrow.add_theme_font_size_override("font_size", 16)
	arrow.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	previews.add_child(arrow)
	# New side — synthesized variant.
	previews.add_child(_build_preview_pair(def, slot_id, true))
	# Footer — flavor + tint mode + tags.
	var bits: Array = ["★ " + String(def.get("_flavor_suffix", "?"))]
	var tint: Dictionary = def.get("default_tint", {})
	if not tint.is_empty():
		bits.append(String(tint.get("mode", "?")))
	var tags: Array = def.get("flavor_tags", [])
	if not tags.is_empty():
		bits.append("[" + ", ".join(tags.map(func(t): return String(t))) + "]")
	var footer := Label.new()
	footer.text = " · ".join(bits.map(func(s): return String(s)))
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer.add_theme_font_size_override("font_size", 9)
	footer.add_theme_color_override("font_color", UITheme.COL_DIM)
	v.add_child(footer)
	return box

# Build a vertical stack: inventory icon on top, paperdoll beneath.
# `instance_like` is the item DEF (used as both "item def" and
# "instance" — the recolor shader reads default_tint as a fallback
# when no inst tint is set, so this works for both stock and new).
func _build_preview_pair(item_def: Dictionary, slot_id: String, _is_new: bool) -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	# Inventory icon SubViewport.
	var inv_holder := SubViewportContainer.new()
	inv_holder.stretch = true
	inv_holder.custom_minimum_size = Vector2(_ITEM_PREVIEW_PX, _ITEM_PREVIEW_PX)
	col.add_child(inv_holder)
	var inv_sub := SubViewport.new()
	inv_sub.size = Vector2i(_ITEM_PREVIEW_PX, _ITEM_PREVIEW_PX)
	inv_sub.disable_3d = true
	inv_sub.transparent_bg = true
	inv_sub.render_target_update_mode = SubViewport.UPDATE_ONCE
	inv_holder.add_child(inv_sub)
	var inv_root := Node2D.new()
	inv_sub.add_child(inv_root)
	var inv_sprite := Sprite2D.new()
	var tile_path: String = "res://assets/tiles/items/" + String(item_def.get("tile", ""))
	if ResourceLoader.exists(tile_path):
		inv_sprite.texture = load(tile_path)
	inv_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	inv_sprite.scale = Vector2(2.0, 2.0)
	inv_sprite.position = Vector2(_ITEM_PREVIEW_PX * 0.5, _ITEM_PREVIEW_PX * 0.5)
	# recolor_material_for reads inst.tint (not default_tint). The
	# in-game flow is: dungeon copies default_tint → instance.tint at
	# spawn. Here we mock an instance that carries the def's
	# default_tint as tint so the same shader fires.
	var fake_inst: Dictionary = {"tint": item_def.get("default_tint", null)}
	inv_sprite.material = UITheme.recolor_material_for(fake_inst)
	var rar: String = String(item_def.get("rarity", "common"))
	var meta: String = ""
	inv_sprite.modulate = UITheme.item_modulate(rar, item_def.get("flavor_tags", []), meta)
	inv_root.add_child(inv_sprite)
	# Paperdoll preview below — only for slots with overlays.
	if slot_id in ["weapon", "armor", "helm", "shield", "boots", "gloves", "cloak"]:
		var pd_holder := SubViewportContainer.new()
		pd_holder.stretch = true
		pd_holder.custom_minimum_size = Vector2(_ITEM_PREVIEW_PX, _ITEM_PREVIEW_PX)
		col.add_child(pd_holder)
		var pd_sub := SubViewport.new()
		pd_sub.size = Vector2i(_ITEM_PREVIEW_PX, _ITEM_PREVIEW_PX)
		pd_sub.disable_3d = true
		pd_sub.transparent_bg = true
		pd_sub.render_target_update_mode = SubViewport.UPDATE_ONCE
		pd_holder.add_child(pd_sub)
		# build_rig wants both a base item DB and an equipped dict.
		# Ours: temporarily inject the new def into the db so the rig
		# can find it by id. For the parent, the db already has it.
		var local_db: Dictionary = _items_db
		var inst_id: String = String(item_def.get("id", ""))
		if not _items_db.has(inst_id):
			local_db = _items_db.duplicate()
			local_db[inst_id] = item_def
		# Equipped dict carries a faux instance with tint copied from
		# the def's default_tint, mirroring how dungeon._create_item_
		# instance does it at drop time. Without this, the paperdoll
		# overlay would render untinted while the inventory icon shows
		# the new color — exactly the visual desync the user just
		# called out.
		var equipped: Dictionary = {
			slot_id: {
				"base_id": inst_id,
				"tint": item_def.get("default_tint", null),
			}
		}
		var built: Dictionary = PaperdollRenderer.build_rig(local_db, equipped, "", true)
		var rig: Node2D = built.get("rig", null)
		if rig != null:
			rig.scale = Vector2(2.0, 2.0)
			rig.position = Vector2(_ITEM_PREVIEW_PX * 0.5, _ITEM_PREVIEW_PX * 0.6)
			pd_sub.add_child(rig)
	return col

func _stylebox_for(rarity: String, selected: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = UITheme.BG_PANEL if not selected else Color(0.10, 0.20, 0.10)
	sb.border_color = UITheme.rarity_color(rarity)
	var bw: int = 3 if selected else 1
	sb.border_width_left = bw
	sb.border_width_top = bw
	sb.border_width_right = bw
	sb.border_width_bottom = bw
	sb.corner_radius_top_left = 3
	sb.corner_radius_top_right = 3
	sb.corner_radius_bottom_left = 3
	sb.corner_radius_bottom_right = 3
	return sb

func _toggle_select(idx: int) -> void:
	if _selected.has(idx):
		_selected.erase(idx)
	else:
		_selected[idx] = true
	# Single-cell stylebox flip — no full grid rebuild.
	if idx >= 0 and idx < _grid.get_child_count():
		var cell: Control = _grid.get_child(idx) as Control
		if cell is PanelContainer:
			var rar: String = String(_generated[idx].get("rarity", "common"))
			cell.add_theme_stylebox_override("panel", _stylebox_for(rar, _selected.has(idx)))
	if _stats_lbl != null:
		_stats_lbl.text = "%d generated · %d selected" % [_generated.size(), _selected.size()]

func _clear_selection() -> void:
	_selected.clear()
	for i in _grid.get_child_count():
		var cell: Control = _grid.get_child(i) as Control
		if cell is PanelContainer:
			var rar: String = String(_generated[i].get("rarity", "common"))
			cell.add_theme_stylebox_override("panel", _stylebox_for(rar, false))
	if _stats_lbl != null:
		_stats_lbl.text = "%d generated · %d selected" % [_generated.size(), _selected.size()]

# --- export ----------------------------------------------------------------

# Export selected variants as items.json fragments. Strips the
# preview-only meta keys (_parent_id, _parent_name, _flavor_suffix)
# so the exported JSON is paste-ready.
func _export_selected() -> void:
	if _selected.is_empty():
		if _stats_lbl != null:
			_stats_lbl.text = "Nothing selected — click tiles to ★ them first."
		return
	var out: Array = []
	var keys: Array = _selected.keys()
	keys.sort()
	for idx in keys:
		if idx < 0 or idx >= _generated.size():
			continue
		var clean: Dictionary = _generated[idx].duplicate(true)
		clean.erase("_parent_id")
		clean.erase("_parent_name")
		clean.erase("_flavor_suffix")
		out.append(clean)
	var payload: Dictionary = {
		"_doc": "Item-base variants generated by the in-game Item Generator. Each entry is a paste-ready items.json item def — recolored / reflavored variants of existing bases. Append to the items[] array in project/data/items.json.",
		"timestamp_unix": int(Time.get_unix_time_from_system()),
		"count": out.size(),
		"items": out,
	}
	var text: String = JSON.stringify(payload, "  ")
	var path := "user://generated_items.json"
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(text)
		f.close()
	DisplayServer.clipboard_set(text)
	var fs_path: String = ProjectSettings.globalize_path(path)
	if _stats_lbl != null:
		_stats_lbl.text = "Exported %d variants → %s · %d chars copied to clipboard" % [out.size(), fs_path, text.length()]
