class_name StatPanel
extends Control

# Shared stats panel widget. Both HUD (in-run sidebar tab) and Outpost
# (Character pane) embed an instance and call render(stats_dict).
# Single rendering path → no more outpost-vs-HUD divergence.
# Pre-2026-06-06 each screen rolled its own stat layout with different
# fonts and missing rows; this panel shows EVERY stat (incl. 0 values)
# at uniform font sizes, scrolling when content overflows.
#
# Caller flow:
#   var sp := StatPanel.new()
#   sp.size = Vector2(w, h)
#   sp.editable = true                # outpost only — adds +/- alloc btns
#   sp.alloc_callback = Callable(...) # outpost wires up _on_stat_plus/minus
#   add_child(sp)
#   sp.render(StatCalc.compute(...))  # initial render, builds all rows
#   ...later: sp.render(StatCalc.compute(...))  # diff-only update

const COL_AMBER := Color(0.92, 0.78, 0.45)
const COL_DIM := Color(0.7, 0.6, 0.4)
const COL_GOLD := Color(1.0, 0.85, 0.3)
# Soft-cap exposure (a06 §4.4 / S3.4). Saturated yellow when the value
# is at its cap, dim yellow when within 10% of cap. Caps mirror the
# clamps in stat_calc.gd:275-316.
const COL_AT_CAP := Color(1.00, 0.85, 0.20)
const COL_NEAR_CAP := Color(1.00, 0.85, 0.55)
# Hover tooltips for STR/DEX/INT — explain what each stat governs so the
# player can read "this is the stat for me" at a glance (PLAYTEST #2).
const _PRIMARY_TOOLTIPS := {
	"str": "Strength\n+1.5% HP per excess point\nMelee weapon damage scales here",
	"dex": "Dexterity\n+0.5% Crit per excess point\n+1% Haste per excess point",
	"int": "Intelligence\n+1% Spell Damage per excess point\n+0.5% Spell Area per excess point\n+0.5% Spell Duration per excess point",
}
# Soft-cap table — stat key → ceiling value used by stat_calc.gd. Row
# colors lerp toward yellow as the displayed value approaches the cap.
# Entries omitted here render in their normal color.
const _STAT_SOFT_CAPS := {
	"crit_chance":          75.0,
	"crit_multiplier_pct":  35.0,
	"block_chance":         30.0,
	"block_amount":         20.0,
	"haste_pct":            200.0,
	"evasion":              75.0,
	"lifesteal_pct":        15.0,
	"spell_damage_pct":     120.0,
	"spell_area_pct":       100.0,
	"spell_cdr_pct":        50.0,
	"spell_duration_pct":   100.0,
	"spell_proj_speed_pct": 100.0,
	"spell_proj_bonus":     5.0,
}

# When true, the Primary section renders +/- alloc buttons and a Reset
# button so the player can spend stat points. Outpost only.
var editable: bool = false
# Optional callbacks the host wires up. Each is invoked with the stat
# key ("str" / "dex" / "int") as the only argument.
var alloc_plus_cb: Callable
var alloc_minus_cb: Callable
var alloc_reset_cb: Callable

# Cached row references — one per stat key. Each row: { lbl: Label, last: String }.
# Diff-render writes new text only when last_text differs.
var _rows: Dictionary = {}
var _scroll: ScrollContainer = null
var _content: VBoxContainer = null
var _built: bool = false

func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_PASS

# Public — pump the stats dict in. First call builds the layout; later
# calls diff-update labels.
func render(stats: Dictionary) -> void:
	if not _built:
		_build_layout(stats)
		_built = true
	_apply_values(stats)

func _build_layout(stats: Dictionary) -> void:
	# ScrollContainer pinned to fill the panel via anchors. Setting an
	# explicit size + anchors=1.0 can race in Godot's layout pass, so we
	# anchor-only and let the engine derive the size each frame.
	_scroll = ScrollContainer.new()
	_scroll.anchor_right = 1.0
	_scroll.anchor_bottom = 1.0
	_scroll.offset_right = 0
	_scroll.offset_bottom = 0
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_scroll)
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 2)
	_scroll.add_child(_content)

	# Build sections in order. Each `_section` adds a header + underline;
	# `_row` adds a stat row.
	#
	# PLAYTEST #2 — Primary stats lead the panel. STR/DEX/INT are the
	# core build-shape lever; burying them at the bottom under Vitals
	# made race choice / level-up alloc feel like decoration. Their
	# section also gets per-stat hover tooltips explaining what each
	# governs.
	_section("Primary")
	if editable:
		_attribute_row("str", "Str", UITheme.spell_class_color("str"))
		_attribute_row("dex", "Dex", UITheme.spell_class_color("dex"))
		_attribute_row("int", "Int", UITheme.spell_class_color("int"))
		_unspent_row()
	else:
		_row("str", "Str", UITheme.spell_class_color("str"))
		_row("dex", "Dex", UITheme.spell_class_color("dex"))
		_row("int", "Int", UITheme.spell_class_color("int"))

	_section("Vitals")
	_row("max_hp", "HP", UITheme.affix_stat_color("hp"))
	_row("hp_regen", "Regen / sec", UITheme.affix_stat_color("hp_regen"))
	_row("armor", "Armor", UITheme.affix_stat_color("armor"))
	_row("evasion", "Evasion", UITheme.affix_stat_color("evasion"))
	# One row per resistance element — always shown, 0 when unset.
	for elem in StatCalc.RESISTANCE_ELEMENTS:
		var col: Color = UITheme.damage_type_color(elem)
		_row("res_" + elem, "%s Res" % elem.capitalize(), col)

	_section("Combat")
	_row("damage", "Damage", UITheme.damage_type_color("physical"))
	_row("weapon_speed", "Weapon Speed", COL_DIM)
	_row("attack_interval", "Swing Interval", COL_AMBER)
	_row("crit_chance", "Crit", UITheme.affix_stat_color("crit_chance"))
	_row("crit_multiplier_pct", "Crit Damage", UITheme.affix_stat_color("crit_chance"))
	_row("block_chance", "Block Chance", UITheme.affix_stat_color("armor"))
	_row("block_amount", "Block Amount", UITheme.affix_stat_color("armor"))
	_row("haste_pct", "Haste", UITheme.affix_stat_color("haste_pct"))
	_row("lifesteal_pct", "Lifesteal", UITheme.affix_stat_color("lifesteal_pct"))
	# One row per element where extra-damage might appear; always shown.
	for elem in ["physical", "fire", "cold", "lightning", "holy", "poison", "dark"]:
		var col2: Color = UITheme.damage_type_color(elem)
		_row("extra_" + elem, "+%s Dmg" % elem.capitalize(), col2)

	_section("Spells")
	_row("spell_cdr_pct", "Cooldown Reduction", COL_AMBER)
	_row("spell_proj_bonus", "Extra Projectiles", COL_AMBER)
	_row("spell_proj_speed_pct", "Projectile Speed", COL_DIM)
	_row("spell_area_pct", "Area of Effect", COL_DIM)
	_row("spell_duration_pct", "Duration", COL_DIM)
	_row("spell_damage_pct", "Spell Damage", COL_AMBER)
	for elem in StatCalc.SPELL_ELEMENTS:
		var col3: Color = UITheme.damage_type_color(elem)
		_row("spell_" + elem + "_pct", "%s Spell Dmg" % elem.capitalize(), col3)

	_section("Misc")
	_row("move_speed", "Move Speed", COL_DIM)
	_row("aggro_bonus", "Aggro Bonus", COL_DIM)
	_row("loot_rarity_bonus", "Loot Rarity Bonus", COL_GOLD)
	_row("xp_gain_pct", "XP Gain Bonus", COL_DIM)
	_row("gold", "Gold", COL_GOLD)

# Section header — amber-dim text + thin underline, matching the
# outpost `_add_section` look.
func _section(title: String) -> void:
	var hdr_holder := Control.new()
	hdr_holder.custom_minimum_size = Vector2(0, 22)
	hdr_holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var hdr := UITheme.section_label(title)
	hdr.position = Vector2(0, 4)
	hdr_holder.add_child(hdr)
	var line := ColorRect.new()
	line.color = Color(0.35, 0.30, 0.18, 0.45)
	line.position = Vector2(0, 18)
	line.size = Vector2(120, 1)
	hdr_holder.add_child(line)
	_content.add_child(hdr_holder)

# Standard stat row — name on left, value on right, fixed font size.
# Both labels get SIZE_EXPAND_FILL so the HBox lays them out predictably:
# 60% to the name, 40% to the value column. Pre-fix the value label had
# only `custom_minimum_size` and no expand flag — it could collapse to
# zero width and show nothing while the name still rendered, leaving
# the user staring at "labels with no values."
func _row(key: String, label_text: String, color: Color) -> void:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 6)
	var name_lbl := UITheme.label(label_text, UITheme.FS_SMALL, COL_DIM)
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.size_flags_stretch_ratio = 0.6
	name_lbl.clip_text = true
	# PLAYTEST #2 — per-stat hover tooltips explain what STR/DEX/INT
	# governs. Engine native tooltip — Control.tooltip_text. Mouse_filter
	# pass so the row's hover area dispatches the engine tooltip.
	var hover: String = String(_PRIMARY_TOOLTIPS.get(key, ""))
	if hover != "":
		name_lbl.mouse_filter = Control.MOUSE_FILTER_STOP
		name_lbl.tooltip_text = hover
	row.add_child(name_lbl)
	var val_lbl := UITheme.label("—", UITheme.FS_SMALL, color)
	val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	val_lbl.size_flags_stretch_ratio = 0.4
	val_lbl.clip_text = true
	row.add_child(val_lbl)
	_content.add_child(row)
	_rows[key] = {"lbl": val_lbl, "last": "", "base_color": color}

# Attribute row (outpost editable mode) — name + value + − value + buttons.
func _attribute_row(stat: String, label_text: String, color: Color) -> void:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 6)
	var name_lbl := UITheme.label(label_text, UITheme.FS_SMALL, COL_DIM)
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.size_flags_stretch_ratio = 0.6
	name_lbl.clip_text = true
	# PLAYTEST #2 — same per-stat tooltip surface used by _row().
	var hover: String = String(_PRIMARY_TOOLTIPS.get(stat, ""))
	if hover != "":
		name_lbl.mouse_filter = Control.MOUSE_FILTER_STOP
		name_lbl.tooltip_text = hover
	row.add_child(name_lbl)
	var val_lbl := UITheme.label("—", UITheme.FS_SMALL, color)
	val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	val_lbl.size_flags_stretch_ratio = 0.4
	val_lbl.custom_minimum_size = Vector2(40, 0)
	val_lbl.clip_text = true
	row.add_child(val_lbl)
	var minus := Button.new()
	minus.text = "−"
	minus.custom_minimum_size = Vector2(24, 22)
	minus.add_theme_font_size_override("font_size", UITheme.FS_BODY)
	minus.tooltip_text = "Refund 1 point from %s" % label_text
	if alloc_minus_cb.is_valid():
		minus.pressed.connect(alloc_minus_cb.bind(stat))
	row.add_child(minus)
	var plus := Button.new()
	plus.text = "+"
	plus.custom_minimum_size = Vector2(24, 22)
	plus.add_theme_font_size_override("font_size", UITheme.FS_BODY)
	plus.tooltip_text = "Spend 1 point on %s" % label_text
	if alloc_plus_cb.is_valid():
		plus.pressed.connect(alloc_plus_cb.bind(stat))
	row.add_child(plus)
	_content.add_child(row)
	_rows[stat] = {"lbl": val_lbl, "last": "", "base_color": color}

# Unspent points row + Reset button (outpost editable mode).
func _unspent_row() -> void:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 6)
	var name_lbl := UITheme.label("Unspent", UITheme.FS_SMALL, COL_AMBER)
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.size_flags_stretch_ratio = 0.6
	name_lbl.clip_text = true
	row.add_child(name_lbl)
	var val_lbl := UITheme.label("—", UITheme.FS_SMALL, COL_AMBER)
	val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	val_lbl.size_flags_stretch_ratio = 0.4
	val_lbl.custom_minimum_size = Vector2(40, 0)
	val_lbl.clip_text = true
	row.add_child(val_lbl)
	var reset_btn := Button.new()
	reset_btn.text = "Reset"
	reset_btn.custom_minimum_size = Vector2(60, 22)
	reset_btn.add_theme_font_size_override("font_size", UITheme.FS_SECTION)
	reset_btn.tooltip_text = "Refund all spent stat points"
	if alloc_reset_cb.is_valid():
		reset_btn.pressed.connect(alloc_reset_cb)
	row.add_child(reset_btn)
	_content.add_child(row)
	_rows["unspent_points"] = {"lbl": val_lbl, "last": "", "base_color": COL_AMBER}

# Diff-update every row's text from the stats dict. Cheap: only writes
# Label.text when the formatted value changed (skips the layout pass).
func _apply_values(stats: Dictionary) -> void:
	_set_text("max_hp", "%d" % int(stats.get("max_hp", 0)))
	_set_text("hp_regen", _fmt_float(float(stats.get("hp_regen", 0)), 1))
	_set_text("armor", "%d" % int(stats.get("armor", 0)))
	var evasion_v: float = float(stats.get("evasion", 0))
	_set_text("evasion", "%d%%" % int(round(evasion_v)), evasion_v)
	var resistances: Dictionary = stats.get("resistances", {})
	for elem in StatCalc.RESISTANCE_ELEMENTS:
		_set_text("res_" + elem, "%d%%" % int(round(float(resistances.get(elem, 0)))))
	# Combat block.
	var dmin: int = int(stats.get("damage_min", 0))
	var dmax: int = int(stats.get("damage_max", 0))
	var dtype: String = String(stats.get("weapon_damage_type", "physical")).capitalize()
	_set_text("damage", "%d-%d %s" % [dmin, dmax, dtype])
	_set_text("weapon_speed", "%.2fs" % float(stats.get("weapon_speed", 1.0)))
	_set_text("attack_interval", "%.2fs/swing" % float(stats.get("attack_interval", 1.0)))
	var crit_v: float = float(stats.get("crit_chance", 0))
	_set_text("crit_chance", "%d%%" % int(round(crit_v)), crit_v)
	var cmp_v: float = float(stats.get("crit_multiplier_pct", 0))
	_set_text("crit_multiplier_pct", "+%d%%" % int(round(cmp_v)), cmp_v)
	var bc_v: float = float(stats.get("block_chance", 0))
	_set_text("block_chance", "%d%%" % int(round(bc_v)), bc_v)
	var ba_v: float = float(stats.get("block_amount", 0))
	_set_text("block_amount", "%d" % int(ba_v), ba_v)
	var haste_v: float = float(stats.get("haste_pct", 0))
	_set_text("haste_pct", "+%d%%" % int(round(haste_v)), haste_v)
	var ls_v: float = float(stats.get("lifesteal_pct", 0))
	_set_text("lifesteal_pct", "%d%%" % int(round(ls_v)), ls_v)
	var extra: Dictionary = stats.get("extra_damage", {})
	for elem in ["physical", "fire", "cold", "lightning", "holy", "poison", "dark"]:
		var rng: Dictionary = extra.get(elem, {"min": 0, "max": 0})
		var lo: int = int(rng.get("min", 0))
		var hi: int = int(rng.get("max", 0))
		_set_text("extra_" + elem, "—" if (lo == 0 and hi == 0) else "%d-%d" % [lo, hi])
	# Spells block. Soft-capped values pass their numeric so cap-pressure
	# colors fire (S3.4).
	var cdr_v: float = float(stats.get("spell_cdr_pct", 0))
	_set_text("spell_cdr_pct", "%d%%" % int(round(cdr_v)), cdr_v)
	var proj_v: float = float(stats.get("spell_proj_bonus", 0))
	_set_text("spell_proj_bonus", "+%d" % int(proj_v), proj_v)
	var pspeed_v: float = float(stats.get("spell_proj_speed_pct", 0))
	_set_text("spell_proj_speed_pct", "%d%%" % int(round(pspeed_v)), pspeed_v)
	var sarea_v: float = float(stats.get("spell_area_pct", 0))
	_set_text("spell_area_pct", "%d%%" % int(round(sarea_v)), sarea_v)
	var sdur_v: float = float(stats.get("spell_duration_pct", 0))
	_set_text("spell_duration_pct", "%d%%" % int(round(sdur_v)), sdur_v)
	var sdmg_v: float = float(stats.get("spell_damage_pct", 0))
	_set_text("spell_damage_pct", "%d%%" % int(round(sdmg_v)), sdmg_v)
	var spell_elem: Dictionary = stats.get("spell_element_pct", {})
	for elem in StatCalc.SPELL_ELEMENTS:
		_set_text("spell_" + elem + "_pct", "%d%%" % int(round(float(spell_elem.get(elem, 0)))))
	# Primary.
	_set_text("str", "%d" % int(stats.get("str", 5)))
	_set_text("dex", "%d" % int(stats.get("dex", 5)))
	_set_text("int", "%d" % int(stats.get("int", 5)))
	if editable:
		_set_text("unspent_points", "%d" % int(stats.get("unspent_points", 0)))
	# Misc.
	_set_text("move_speed", "%.1f" % float(stats.get("move_speed", 4.0)))
	_set_text("aggro_bonus", "+%d" % int(stats.get("aggro_bonus", 0)))
	_set_text("loot_rarity_bonus", "%d%%" % int(round(float(stats.get("loot_rarity_bonus", 0)))))
	_set_text("xp_gain_pct", "%d%%" % int(round(float(stats.get("xp_gain_pct", 0)))))
	_set_text("gold", "%d" % int(stats.get("gold", 0)))

# Diff-set: write Label.text only when the new value differs. Pre-fix
# this saved the per-frame relayout cost in update_stats; same idea here.
func _set_text(key: String, value: String, numeric: float = NAN) -> void:
	var refs: Variant = _rows.get(key, null)
	if refs == null:
		return
	if String(refs.get("last", "")) == value:
		return
	var lbl: Label = refs.get("lbl", null)
	if lbl != null and is_instance_valid(lbl):
		lbl.text = value
		# Soft-cap exposure (S3.4 / a06 §4.4). When the stat is in the
		# soft-cap table and the caller fed a numeric value, recolor the
		# row so cap-pressure is legible: saturated yellow at cap, faint
		# yellow within 10% of cap, base color otherwise.
		if not is_nan(numeric) and _STAT_SOFT_CAPS.has(key):
			var cap: float = float(_STAT_SOFT_CAPS[key])
			var base_color: Color = refs.get("base_color", COL_AMBER)
			if cap > 0.0 and numeric >= cap - 0.001:
				lbl.add_theme_color_override("font_color", COL_AT_CAP)
			elif cap > 0.0 and numeric >= cap * 0.90:
				lbl.add_theme_color_override("font_color", COL_NEAR_CAP)
			else:
				lbl.add_theme_color_override("font_color", base_color)
	refs["last"] = value

# Round a float to N decimals, dropping trailing ".0" for cleanliness.
# Used for hp_regen so 0.0 reads as "0" instead of "0.0".
func _fmt_float(v: float, decimals: int) -> String:
	if absf(v) < 0.05:
		return "0"
	var s: String = ("%.*f" % [decimals, v]) if decimals > 0 else "%d" % int(v)
	return s
