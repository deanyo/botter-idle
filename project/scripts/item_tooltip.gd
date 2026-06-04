class_name ItemTooltip
extends Control

# WoW-style item tooltip widget. Spawned by HudChrome / Outpost when
# a cell is hovered; freed on hover-exit. Renders:
#   - Title in rarity color (with meta-rarity prefix if any)
#   - Subtitle: rarity · slot · weapon class
#   - Damage line (for weapons/spells): "min-max Type · 0.5s" white
#   - Bonus damage lines (one per element from extra_damage): "+X-Y Fire"
#   - Defensive lines (armor/evasion) for body slots
#   - Affix lines parsed from inst.affixes + item.implicit_affixes
#   - Italic flavor block (item.lore) if present
#   - Hotkey hint "Hold [Shift] to compare"
#
# When Shift is held + tooltip is for non-spell gear, a sibling
# ItemTooltip is rendered for the currently-equipped same-slot item
# (or all rings 1-4 for ring slot — WoW pattern). Item-overhaul v2
# 2026-06-04.

const TOOLTIP_W := 280
const PADDING := 10
const LINE_GAP := 4
const COLOR_TITLE_DEFAULT := Color(0.92, 0.78, 0.45)
const COLOR_SUBTITLE := Color(0.65, 0.62, 0.5)
const COLOR_BODY := Color(0.92, 0.92, 0.85)
const COLOR_AFFIX := Color(0.45, 0.85, 1.00)  # uncommon-blue affix line
const COLOR_FLAVOR := Color(0.65, 0.62, 0.5)
const COLOR_HOTKEY := Color(0.5, 0.5, 0.45)

var item: Dictionary = {}
var inst: Variant = null
var items_db: Dictionary = {}

var _vbox: VBoxContainer = null
var _bg: ColorRect = null
var _border: ReferenceRect = null

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE  # tooltip never eats clicks
	z_index = 200
	custom_minimum_size = Vector2(TOOLTIP_W, 0)
	# Background panel — rarity-tinted border + dark fill.
	_bg = ColorRect.new()
	_bg.color = Color(0.05, 0.04, 0.02, 0.94)
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg.anchor_right = 1.0
	_bg.anchor_bottom = 1.0
	add_child(_bg)
	_border = ReferenceRect.new()
	_border.border_color = COLOR_TITLE_DEFAULT
	_border.border_width = 1.5
	_border.editor_only = false
	_border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_border.anchor_right = 1.0
	_border.anchor_bottom = 1.0
	add_child(_border)
	_vbox = VBoxContainer.new()
	_vbox.position = Vector2(PADDING, PADDING)
	_vbox.add_theme_constant_override("separation", LINE_GAP)
	_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_vbox)

# Build the tooltip content from item + inst. Caller positions the
# tooltip and adds it to the scene tree.
func render_for(item_def: Dictionary, instance: Variant, db: Dictionary) -> void:
	item = item_def
	inst = instance
	items_db = db
	for c in _vbox.get_children():
		c.queue_free()
	if item.is_empty():
		return
	var rarity: String = String(item.get("rarity", "common"))
	var rarity_col: Color = UITheme.rarity_color(rarity)
	_border.border_color = rarity_col
	# Title — meta-rarity prefix folded in if present (Ancient/Primal).
	var disp_name: String = String(item.get("name", item.get("id", "?")))
	if typeof(inst) == TYPE_DICTIONARY:
		var meta: String = String(inst.get("meta_rarity", ""))
		if meta == "ancient":
			disp_name = "Ancient " + disp_name
		elif meta == "primal":
			disp_name = "Primal " + disp_name
	var title := _make_label(disp_name, 16, rarity_col, true)
	_vbox.add_child(title)
	# Subtitle: rarity · slot · weapon class (if weapon)
	var slot: String = String(item.get("slot", ""))
	var subtitle_parts: Array = [rarity.capitalize()]
	if slot != "":
		subtitle_parts.append(_pretty_slot_label(slot))
	if slot == "weapon":
		var wc: String = String(item.get("weapon_class", ""))
		if wc != "":
			subtitle_parts.append(wc)
	_vbox.add_child(_make_label(" · ".join(subtitle_parts), 11, COLOR_SUBTITLE, false))
	_vbox.add_child(_make_separator())
	# Damage block (weapons + spells).
	if slot == "weapon" or slot == "spell":
		_render_damage_block()
		_vbox.add_child(_make_separator())
	# Defensive block (body slots).
	if item.has("armor") or item.has("evasion"):
		var armor: int = int(item.get("armor", 0))
		var evasion: int = int(item.get("evasion", 0))
		if armor > 0:
			_vbox.add_child(_make_label("Armor: %d" % armor, 13, COLOR_BODY, false))
		if evasion > 0:
			_vbox.add_child(_make_label("Evasion: +%d%%" % evasion, 13, COLOR_BODY, false))
		if armor > 0 or evasion > 0:
			_vbox.add_child(_make_separator())
	# Affix block (implicit + rolled).
	var affix_lines: Array = _build_affix_lines()
	for line in affix_lines:
		_vbox.add_child(line)
	if not affix_lines.is_empty():
		_vbox.add_child(_make_separator())
	# Flavor / lore.
	var lore: String = String(item.get("lore", ""))
	if lore != "":
		var flavor_lbl := _make_label('"' + lore + '"', 11, COLOR_FLAVOR, false)
		flavor_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		flavor_lbl.add_theme_font_size_override("font_size", 11)
		flavor_lbl.custom_minimum_size = Vector2(TOOLTIP_W - PADDING * 2, 0)
		# Italics: Godot 4 doesn't have a free italic font, so we just
		# tint dim + smaller — the visual cue is enough.
		_vbox.add_child(flavor_lbl)
		_vbox.add_child(_make_separator())
	# Hotkey hint (gear only — spells don't compare).
	if slot != "spell" and slot != "":
		_vbox.add_child(_make_label("Hold [Shift] to compare", 10, COLOR_HOTKEY, false))
	# Resize the tooltip's height to fit the vbox.
	# Wait one frame for the vbox to lay out, then size ourselves.
	await get_tree().process_frame
	if is_instance_valid(self) and is_instance_valid(_vbox):
		size = Vector2(TOOLTIP_W, _vbox.size.y + PADDING * 2)

func _render_damage_block() -> void:
	var slot: String = String(item.get("slot", ""))
	var dmin: int = int(item.get("damage_min", 0))
	var dmax: int = int(item.get("damage_max", 0))
	var dtype: String = String(item.get("damage_type", "physical"))
	if dmin <= 0 and dmax <= 0:
		return
	var dtype_label: String = dtype.capitalize() if dtype != "physical" else "Physical"
	var dmg_color: Color = UITheme.damage_type_color(dtype)
	_vbox.add_child(_make_label("%d-%d %s" % [dmin, dmax, dtype_label], 14, dmg_color, true))
	# Speed (weapons) / cooldown (spells).
	if slot == "weapon":
		var sp: float = float(item.get("speed", 1.0))
		_vbox.add_child(_make_label("%.2fs Attack Speed" % sp, 12, COLOR_BODY, false))
	elif slot == "spell":
		var cd: float = float(item.get("spell_cooldown", 3.0))
		_vbox.add_child(_make_label("%.1fs Cooldown" % cd, 12, COLOR_BODY, false))

# Build affix lines from inst.affixes + item.implicit_affixes. Each
# line is a Label colored by family (uncommon-blue for generic /
# class affixes, gold for archetype implicits since they're item-
# defining). Range affixes ("of Embers") emit "+X-Y Fire" with the
# element's color; flat affixes show "+N Strength" etc.
func _build_affix_lines() -> Array:
	var out: Array = []
	# Implicit affixes first — rendered in gold (item-defining).
	for a in item.get("implicit_affixes", []):
		var def: Dictionary = AffixSystem.get_affix_def(String(a))
		if def.is_empty():
			continue
		var line_text: String = _format_affix_line(def, _implicit_value_at_rarity(def, String(item.get("rarity", "common"))))
		out.append(_make_label(line_text, 12, Color(1.0, 0.85, 0.30), false))
	# Rolled affixes — uncommon-blue.
	if typeof(inst) == TYPE_DICTIONARY:
		for af_inst in inst.get("affixes", []):
			var def: Dictionary = AffixSystem.get_affix_def(String(af_inst.get("id", "")))
			if def.is_empty():
				continue
			var line_text: String = _format_affix_line(def, af_inst)
			# Colour by family: range affixes use damage-type color, flat
			# affixes default to magic blue.
			var line_color: Color = COLOR_AFFIX
			if String(def.get("kind", "flat")) == "range":
				var stat: String = String(def.get("stat", ""))
				var elem: String = stat.replace("_extra", "")
				line_color = UITheme.damage_type_color(elem)
			out.append(_make_label(line_text, 12, line_color, false))
	return out

# Synthesize a value dict for an implicit affix at the given item rarity.
# Implicits don't have rolled values — we approximate the mid-tier
# range so tooltips show reasonable numbers.
func _implicit_value_at_rarity(def: Dictionary, rarity: String) -> Dictionary:
	var tiers: Array = def.get("tiers", [])
	var idx: int = AffixSystem.tier_index_for_rarity(rarity)
	idx = clampi(idx, 0, tiers.size() - 1)
	if tiers.is_empty():
		return {"id": def.get("id", ""), "value": 0}
	var tier_entry = tiers[idx]
	if tier_entry is Array and tier_entry.size() >= 2:
		var lo: int = int(tier_entry[0])
		var hi: int = int(tier_entry[1])
		var out_d: Dictionary = {"id": def.get("id", ""), "value": int(round((lo + hi) / 2.0))}
		if String(def.get("kind", "flat")) == "range":
			out_d["value_min"] = lo
			out_d["value_max"] = hi
		return out_d
	return {"id": def.get("id", ""), "value": int(tier_entry)}

# Format one affix instance into a human-readable string. Inspects
# def.kind to choose between flat / pct / range / flag rendering.
func _format_affix_line(def: Dictionary, af_inst: Dictionary) -> String:
	var kind: String = String(def.get("kind", "flat"))
	var stat: String = String(def.get("stat", ""))
	var name: String = String(def.get("name", ""))
	if kind == "range":
		var lo: int = int(af_inst.get("value_min", 0))
		var hi: int = int(af_inst.get("value_max", 0))
		var elem_label: String = stat.replace("_extra", "").capitalize()
		return "+%d-%d %s" % [lo, hi, elem_label]
	if kind == "pct":
		var v: int = int(af_inst.get("value", 0))
		# Percent stats render with their canonical labels — fall back
		# to the affix name itself if we don't have a stat-specific one.
		var label: String = _STAT_PCT_LABELS.get(stat, name)
		# CDR is negative-displayed (cooldown reduction).
		if stat == "spell_cdr_pct":
			return "-%d%% Spell Cooldown" % v
		return "+%d%% %s" % [v, label]
	if kind == "flag":
		# Archetype unique-affixes — show the affix name + a one-liner
		# description. Description map below.
		var desc: String = _ARCHETYPE_DESCRIPTIONS.get(String(def.get("id", "")), name)
		return desc
	# kind == "flat" (default).
	var v_flat: int = int(af_inst.get("value", 0))
	var label_flat: String = _STAT_FLAT_LABELS.get(stat, name)
	return "+%d %s" % [v_flat, label_flat]

const _STAT_FLAT_LABELS := {
	"str": "Strength", "dex": "Dexterity", "int": "Intelligence",
	"hp": "Health", "armor": "Armor", "hp_regen": "HP/sec",
	"spell_proj_bonus": "Spell Projectiles",
}
const _STAT_PCT_LABELS := {
	"evasion": "Evasion", "spell_cdr_pct": "Spell Cooldown",
	"spell_area_pct": "Spell Area", "spell_duration_pct": "Spell Duration",
	"spell_proj_speed_pct": "Projectile Speed",
	"spell_damage_pct": "Spell Damage",
	"crit_chance": "Crit Chance", "haste_pct": "Haste",
	"lifesteal_pct": "Lifesteal",
	"fire_res": "Fire Resistance", "cold_res": "Cold Resistance",
	"lightning_res": "Lightning Resistance", "holy_res": "Holy Resistance",
	"poison_res": "Poison Resistance", "dark_res": "Dark Resistance",
	"str_spell_dmg_pct": "Strength Spell Damage",
	"dex_spell_dmg_pct": "Dexterity Spell Damage",
	"int_spell_dmg_pct": "Intelligence Spell Damage",
}
const _ARCHETYPE_DESCRIPTIONS := {
	"bleeding_edge": "Spinning Axes leave a bleed on hit",
	"comet_trail":   "Fireball ignites the ground for 3s",
	"frostbite":     "Frost Nova roots enemies for 1s",
	"storm_brand":   "Chain Lightning chains +2 times",
	"radiance":      "Holy Beam length +50% but cooldown +30%",
}

func _pretty_slot_label(slot_id: String) -> String:
	if slot_id.begins_with("spell"):
		return "Spell"
	if slot_id.begins_with("ring"):
		return "Ring"
	return slot_id.capitalize()

func _make_label(text: String, size: int, color: Color, bold: bool) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if bold:
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.5))
		l.add_theme_constant_override("outline_size", 2)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _make_separator() -> Control:
	var sep := ColorRect.new()
	sep.color = Color(1, 1, 1, 0.10)
	sep.custom_minimum_size = Vector2(TOOLTIP_W - PADDING * 2, 1)
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return sep
