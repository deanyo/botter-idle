class_name UITheme
extends RefCounted

# Single source of truth for HUD / Outpost / main-menu styling. Each UI
# script previously redefined its own COL_AMBER / COL_PANEL / etc which
# drifted (HUD panel alpha 0.62 vs Outpost 0.85, etc.) — pulling from
# this class keeps the chrome visually identical across screens.

# Type colors (DCSS-amber palette)
const COL_AMBER := Color(0.92, 0.78, 0.45)
const COL_DIM := Color(0.7, 0.6, 0.4)
const COL_GOLD := Color(1.0, 0.85, 0.3)
const COL_HP := Color(0.55, 0.95, 0.5)
const COL_HP_LOW := Color(1.0, 0.45, 0.45)

# Panel / chrome. Pure black for OLED — saves backlight on Apple/AMOLED
# panels and reads cleaner against rarity-colored borders. The faint
# blue tint we used to use is gone (was 0.04/0.04/0.06).
# UI polish pass 2026-06-04 — bumped panel alpha 0.85 → 1.0 so the OS
# desktop / video bg can't bleed through. BG_DEEP and BG_PANEL alias
# COL_BG / COL_PANEL respectively for forward-compat of new code.
const COL_PANEL := Color(0.0, 0.0, 0.0, 1.0)
const COL_PANEL_BORDER := Color(0.35, 0.3, 0.18, 0.65)
const COL_BG := Color(0.0, 0.0, 0.0, 1.0)
const BG_DEEP := Color(0.0, 0.0, 0.0, 1.0)
const BG_PANEL := Color(0.0, 0.0, 0.0, 1.0)
const BG_OVERLAY := Color(0.0, 0.0, 0.0, 0.65)
const BORDER_DIM := Color(0.18, 0.15, 0.10, 0.85)
const BORDER_ACCENT := Color(0.35, 0.30, 0.18, 0.85)
# Stat-comparison colors — character-creator already had these; lifted
# here so any screen showing +/- deltas can pull from one place.
const COL_BUFF := Color(0.55, 0.95, 0.5)
const COL_NERF := Color(0.95, 0.55, 0.55)
const COL_NEUTRAL := Color(0.7, 0.7, 0.7)

# Rarity tints — used for item borders / tooltips / outline glow.
const COL_RARITY := {
	"common":    Color(0.85, 0.85, 0.85),
	"uncommon":  Color(0.4, 0.7, 1.0),
	"rare":      Color(1.0, 0.9, 0.3),
	"epic":      Color(1.0, 0.5, 0.2),
	"legendary": Color(1.0, 0.3, 0.3),
}

# Type sizes — semantic tiers, used everywhere. Avoid hard-coding
# numbers; pull from these instead. UI consistency pass 2026-06-06.
#
# When picking a tier:
#   FS_TITLE   28  Screen title ("Outpost", "Run Report")
#   FS_HEADER  18  Big in-screen heading ("Adventurer Lv 5")
#   FS_STAT    16  Primary stat readouts (HP value, dmg numbers)
#   FS_BODY    14  Standard label / button text
#   FS_SMALL   12  Stats column rows, secondary info, dim labels
#   FS_SECTION 11  Section headers ("Vitals", "Combat", etc.)
#   FS_TINY    10  Cooldown numbers, corner badges, fine-print
const FS_TITLE := 28
const FS_HEADER := 18
const FS_STAT := 16
const FS_BODY := 14
const FS_SMALL := 12
const FS_SECTION := 11
const FS_TINY := 10
const FS_DEBUG := 12  # alias of FS_SMALL — top-left debug log

# Build a Label with consistent font + color overrides applied. Most
# code paths in HUD/outpost/main-menu re-do the same five lines for
# every label; this reduces them to one call.
static func label(text: String, font_size: int, color: Color) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	lbl.add_theme_constant_override("outline_size", 2)
	return lbl

# Section header — used in Stats / Weapon panes. Tied to the
# `_add_section`-style amber-dim underline rule.
static func section_label(text: String) -> Label:
	return label(text, FS_SECTION, Color(0.55, 0.50, 0.36))

static func rarity_color(rarity: String) -> Color:
	return COL_RARITY.get(rarity, Color(0.5, 0.5, 0.5))

# Union of an item's static flavor_tags + the per-instance `enchant`
# rolled at drop time (see dungeon._create_item_instance). Shared by
# every surface that needs flavor info — bot rig, paperdolls, HUD,
# floor loot, run report — so a Vampires Tooth rolled with a fire
# enchant reads as both vampiric AND fire everywhere consistently.
static func combined_flavor_tags(item: Dictionary, inst: Variant) -> Array:
	var tags: Array = (item.get("flavor_tags", []) as Array).duplicate()
	if typeof(inst) == TYPE_DICTIONARY:
		var enchant: String = String(inst.get("enchant", ""))
		if enchant != "" and not (enchant in tags):
			tags.append(enchant)
		# Compound enchants — fold both component flavors into the tag
		# list so tint / glow / paperdoll color pipelines blend them.
		var combo_id: String = String(inst.get("enchant_combo", ""))
		if combo_id != "":
			for ct in EnchantCombos.components_for(combo_id):
				if not (String(ct) in tags):
					tags.append(String(ct))
	return tags

# Meta-rarity tint colors. Ancient = warm gold, Primal = saturated
# red. Returned as full Color (alpha=1.0) so callers can lerp toward
# them with the same strength scheme used for rarity tints.
const META_COLORS := {
	"ancient": Color(1.0, 0.78, 0.30),
	"primal":  Color(1.0, 0.18, 0.20),
}

static func meta_rarity_color(meta: String) -> Color:
	return META_COLORS.get(meta, Color(0, 0, 0, 0))

# Greyscale-faded slot icon for an EMPTY paperdoll cell. Returns a
# path under project/assets/tiles/slot_icons/. The greyscale variant
# is pre-baked at build time (35% alpha + luma-only RGB) so the UI
# pays zero shader cost. Returns "" for unknown slots (caller should
# leave the cell blank).
# Spell class colors. Spells are tagged with primary_stat = str/dex/int
# (red/green/blue) so the player reads "this is a strength spell" at a
# glance. Drives spell cell border color, cooldown ring tint, drop halo,
# and tooltip header line. Mirrors RPG convention (red warrior, green
# ranger, blue mage). Phase 2-A — combat pivot.
const SPELL_CLASS_COLORS := {
	"str": Color(0.95, 0.30, 0.30),  # red — physical / brute / faith
	"dex": Color(0.50, 0.95, 0.40),  # green — precision / nature
	"int": Color(0.45, 0.85, 1.00),  # blue — arcane / elemental
}

static func spell_class_color(stat: String) -> Color:
	return SPELL_CLASS_COLORS.get(stat, Color(0.85, 0.85, 0.85))

# Resolve a spell item's primary_stat from its items.json def. Defaults
# to "int" for items without the field — keeps legacy / ad-hoc spells
# rendering as Int (blue) rather than uncolored.
static func spell_primary_stat(item: Dictionary) -> String:
	return String(item.get("primary_stat", "int"))

const _SLOT_ICON_DIR := "res://assets/tiles/slot_icons/"
static func empty_slot_icon_path(slot_id: String) -> String:
	# Extra ring slots (ring2/ring3/ring4) reuse the ring icon.
	var key: String = slot_id
	if slot_id.begins_with("ring") and slot_id.length() > 4:
		key = "ring"
	# All spell cells (spell1..spell5) share the same empty placeholder.
	if slot_id.begins_with("spell"):
		key = "spell"
	var path: String = _SLOT_ICON_DIR + key + "_empty.png"
	if not ResourceLoader.exists(path):
		return ""
	return path

# Per-instance recoloring shader (item_recolor.gdshader). Returns a
# ShaderMaterial when inst has a `tint` dict, else null. Caller assigns
# to sprite.material. Cheap fragment shader so applying to many cells
# is fine.
const _ITEM_RECOLOR_SHADER := preload("res://assets/item_recolor.gdshader")
const _MODE_INDEX := {
	"normal":    0,
	"shimmer":   1,
	"inverted":  2,
	"prismatic": 3,
	"colorize":  4,  # 2026-06-05 — forces hue onto white/grey art
}

static var _recolor_mat_cache: Dictionary = {}

static func recolor_material_for(inst: Variant) -> ShaderMaterial:
	return _recolor_material_for_inst(inst, "")

# Same shape, but pulls `default_tint_overlay` off the base item def
# when present (else falls through to the regular `default_tint`).
# Lets authors recolor the on-character paperdoll sprite independently
# of the inventory icon — e.g. inventory keeps its iconic art tint
# while the on-bot overlay reads a different hue. Used by paperdoll_
# renderer + bot.gd's _apply_rarity_decor for overlay sprites.
static func recolor_material_for_overlay(inst: Variant) -> ShaderMaterial:
	return _recolor_material_for_inst(inst, "overlay")

static func _recolor_material_for_inst(inst: Variant, surface: String) -> ShaderMaterial:
	# Web GL Compatibility compiles a shader pipeline per (texture ×
	# shader) combination synchronously on the main thread. Recolor
	# materials applied to dozens of unique item textures (each
	# inventory cell, paperdoll slot, floor loot drop, bot rig overlay)
	# triggered multi-second hangs whenever a new item appeared. Skip
	# the recolor entirely on web — items lose their per-roll tint
	# variation but the base art reads cleanly.
	if OS.has_feature("web"):
		return null
	if typeof(inst) != TYPE_DICTIONARY:
		return null
	# Per-surface tint key. Inventory uses inst.tint (per-roll random
	# tint applied at drop time) with default_tint as fallback. Overlay
	# prefers default_tint_overlay so authors can de-correlate the two
	# surfaces; falls back to inst.tint / default_tint if absent so
	# items that don't author a separate overlay tint look identical
	# to the inventory icon (the historical behavior).
	var tint: Variant = null
	if surface == "overlay":
		var base_id_o: String = String(inst.get("base_id", ""))
		if base_id_o != "":
			var base_o: Dictionary = ItemsDb.items().get(base_id_o, {})
			var dto: Variant = base_o.get("default_tint_overlay", null)
			if typeof(dto) == TYPE_DICTIONARY:
				tint = dto
	if typeof(tint) != TYPE_DICTIONARY:
		tint = inst.get("tint", null)
	# Fallback — instances spawned outside _create_item_instance (e.g.
	# starter spells in save_state.gd's new-save path) have no tint
	# field. Look up the base item's default_tint via ItemsDb so the
	# author-set scroll color still renders. 2026-06-05.
	if typeof(tint) != TYPE_DICTIONARY:
		var base_id: String = String(inst.get("base_id", ""))
		if base_id != "":
			var base: Dictionary = ItemsDb.items().get(base_id, {})
			var dt: Variant = base.get("default_tint", null)
			if typeof(dt) == TYPE_DICTIONARY:
				tint = dt
	if typeof(tint) != TYPE_DICTIONARY:
		return null
	# Cache by (hue, sat, mode, colorize_strength) — a 100-cell rebuild
	# was creating 100 fresh ShaderMaterials and on HTML5 / GL
	# compatibility every new ShaderMaterial triggers a synchronous
	# shader program compile, freezing the main thread for seconds when
	# the rarity filter chip rebuilt the inventory grid. Cache hits
	# return the same compiled material — no compile, no freeze.
	var hue: float = float(tint.get("hue", 0.0))
	var sat: float = float(tint.get("sat", 1.0))
	var mode: int = int(_MODE_INDEX.get(String(tint.get("mode", "normal")), 0))
	var col_str: float = float(tint.get("colorize_strength", 0.7))
	var key: String = "%.4f|%.4f|%d|%.4f" % [hue, sat, mode, col_str]
	var cached: Variant = _recolor_mat_cache.get(key, null)
	if cached != null and is_instance_valid(cached):
		return cached
	var mat := ShaderMaterial.new()
	mat.shader = _ITEM_RECOLOR_SHADER
	mat.set_shader_parameter("hue", hue)
	mat.set_shader_parameter("saturation", sat)
	mat.set_shader_parameter("mode", mode)
	# Per-instance colorize strength (only read by mode 4). Default
	# 0.7 — heavy enough to read on white plate, light enough that
	# luma variation still survives.
	mat.set_shader_parameter("colorize_strength", col_str)
	_recolor_mat_cache[key] = mat
	return mat

# Subtle rarity wash applied to item icons (paperdoll slots, inventory
# cells, equipped slots) so the bot's gold legendary sword looks gold
# in the inventory too — matches bot.gd::_apply_rarity_decor and
# paperdoll_renderer.gd::_apply_rarity_modulate. Common stays white so
# the original sprite art reads cleanly.
const _ICON_TINT_STRENGTH := {
	"common": 0.0, "uncommon": 0.18, "rare": 0.28, "epic": 0.38, "legendary": 0.50,
}

# Flavor-tag-driven colors — mechanically meaningful tags get a real
# color story so a vampiric weapon reads RED everywhere, not just
# orange-because-it's-epic. Listed in priority order — first match in
# an item's flavor_tags wins. Picked to be visually distinct against
# DCSS art's typical metal/wood greys.
const DAMAGE_TYPE_COLORS := {
	"physical":  Color(0.92, 0.92, 0.85),   # bone-white
	"fire":      Color(1.00, 0.55, 0.18),
	"cold":      Color(0.45, 0.85, 1.00),
	"lightning": Color(0.65, 0.80, 1.00),
	"holy":      Color(1.00, 0.92, 0.55),
	"poison":    Color(0.50, 0.95, 0.40),
	"dark":      Color(0.55, 0.30, 0.85),
}

static func damage_type_color(damage_type: String) -> Color:
	return DAMAGE_TYPE_COLORS.get(damage_type, Color(0.92, 0.92, 0.85))

# Per-stat color used by tooltips + (mirror of) the affix-editor's
# rarityHexForStat(). One source of truth so the in-game tooltip
# matches what authors see in dnyo.co.uk/botter-idle/tools/affix_editor.html.
# Item-overhaul v2 + tooltip flair pass 2026-06-04.
const AFFIX_STAT_COLORS := {
	# Primary stats — Str/Dex/Int red/green/blue.
	"str":                  Color(0.95, 0.30, 0.30),
	"dex":                  Color(0.50, 0.95, 0.40),
	"int":                  Color(0.45, 0.85, 1.00),
	# Defensive baseline.
	"hp":                   Color(0.37, 0.78, 0.47),
	"hp_regen":             Color(0.66, 0.37, 1.00),
	"armor":                Color(0.73, 0.73, 0.73),
	"evasion":              Color(0.85, 0.85, 0.85),
	# Universal combat.
	"crit_chance":          Color(1.00, 0.85, 0.30),
	"crit_multiplier_pct":  Color(1.00, 0.78, 0.20),
	"block_chance":         Color(0.65, 0.78, 0.95),
	"block_amount":         Color(0.65, 0.78, 0.95),
	"haste_pct":            Color(1.00, 0.67, 0.23),
	"lifesteal_pct":        Color(0.85, 0.23, 0.23),
	# Spell modifiers — soft purple/cyan family.
	"spell_cdr_pct":        Color(0.69, 0.55, 0.87),
	"spell_proj_bonus":     Color(0.80, 0.69, 1.00),
	"spell_proj_speed_pct": Color(0.80, 0.69, 1.00),
	"spell_area_pct":       Color(0.66, 0.56, 1.00),
	"spell_duration_pct":   Color(0.61, 0.71, 1.00),
	"spell_damage_pct":     Color(0.64, 0.67, 1.00),
	# Class spell-mastery (matches primary, dimmed toward purple).
	"str_spell_dmg_pct":    Color(0.88, 0.48, 0.60),
	"dex_spell_dmg_pct":    Color(0.61, 0.88, 0.54),
	"int_spell_dmg_pct":    Color(0.53, 0.75, 0.88),
	# Range-affix elemental damage adders.
	"physical_extra":       Color(0.92, 0.92, 0.85),
	"fire_extra":           Color(1.00, 0.55, 0.18),
	"cold_extra":           Color(0.45, 0.85, 1.00),
	"lightning_extra":      Color(0.65, 0.80, 1.00),
	"holy_extra":           Color(1.00, 0.92, 0.55),
	"poison_extra":         Color(0.50, 0.95, 0.40),
	"dark_extra":           Color(0.55, 0.30, 0.85),
	# Element resistances — dimmer shade of each element.
	"fire_res":             Color(0.80, 0.43, 0.15),
	"cold_res":             Color(0.36, 0.68, 0.80),
	"lightning_res":        Color(0.52, 0.65, 0.80),
	"holy_res":             Color(0.80, 0.73, 0.43),
	"poison_res":           Color(0.40, 0.76, 0.32),
	"dark_res":             Color(0.44, 0.29, 0.69),
	# Archetype unique-affix flags — gold (item-defining).
	"spell_axes_bleed":          Color(1.00, 0.83, 0.47),
	"spell_fireball_ground":     Color(1.00, 0.83, 0.47),
	"spell_frost_root":          Color(1.00, 0.83, 0.47),
	"spell_chain_extra_jumps":   Color(1.00, 0.83, 0.47),
	"spell_holy_radiance":       Color(1.00, 0.83, 0.47),
	"spell_dart_split":          Color(1.00, 0.83, 0.47),
	"spell_iron_dust":           Color(1.00, 0.83, 0.47),
	"spell_sandblast_blind":     Color(1.00, 0.83, 0.47),
	"spell_drain_buff":          Color(1.00, 0.83, 0.47),
	"spell_shatter_aftershock":  Color(1.00, 0.83, 0.47),
}

static func affix_stat_color(stat: String) -> Color:
	return AFFIX_STAT_COLORS.get(stat, Color(1.00, 0.72, 0.30))  # amber default

const FLAVOR_COLORS := {
	"vampiric":    Color(0.85, 0.15, 0.15),   # blood red
	"fire":        Color(1.00, 0.55, 0.18),   # ember orange
	"cold":        Color(0.45, 0.85, 1.00),   # frost cyan
	"holy":        Color(1.00, 0.92, 0.55),   # gold
	"poison":      Color(0.50, 0.95, 0.40),   # toxic green
	"thunderous":  Color(0.65, 0.80, 1.00),   # electric blue-white
	"dark":        Color(0.55, 0.30, 0.85),   # void purple
	"dragon_bane": Color(0.85, 0.50, 0.20),   # scaled bronze
	"brutal":      Color(0.95, 0.30, 0.30),   # menacing red
	# Less-priority flavors get colors too so the editor preview /
	# inventory tint reflects them, but they sit lower in the
	# priority list so a vampiric-fire weapon still tints red.
	"arcane":      Color(0.70, 0.40, 1.00),   # mage purple
	"elemental":   Color(0.50, 1.00, 0.85),   # primal teal
	"willpower":   Color(0.85, 0.70, 1.00),   # mind lavender
	"fortified":   Color(0.75, 0.75, 0.85),   # iron grey
	"swiftness":   Color(0.70, 1.00, 0.55),   # spring green
	"regen":       Color(0.55, 1.00, 0.65),   # life green
	"stealth":     Color(0.30, 0.30, 0.50),   # shadow indigo
	"lordly":      Color(1.00, 0.85, 0.45),   # noble gold
	"footwork":    Color(0.75, 0.95, 1.00),   # quicksilver
	"warding":     Color(0.55, 0.70, 1.00),   # ward blue
	"wisdom":      Color(0.65, 0.80, 1.00),   # sky blue
	"fire_res":    Color(1.00, 0.75, 0.55),   # warm sand
	"cold_res":    Color(0.85, 0.95, 1.00),   # ice white
	"poison_res":  Color(0.80, 1.00, 0.65),   # antidote green
	"vision":      Color(1.00, 0.95, 0.70),   # eye gold
	"rampaging":   Color(1.00, 0.45, 0.20),   # charge orange
	"flying":      Color(0.85, 0.95, 1.00),   # sky cyan
	"fortune":     Color(1.00, 0.80, 0.30),   # luck gold
	"faith":       Color(0.95, 0.90, 0.65),   # halo cream
	"acrobat":     Color(0.80, 1.00, 0.85),   # mint
	"death":       Color(0.40, 0.10, 0.40),   # death purple
	"earth":       Color(0.65, 0.50, 0.35),   # loam brown
	"guardian":    Color(0.65, 0.85, 1.00),   # aegis blue
	"demon":       Color(0.55, 0.20, 0.50),   # demonic magenta
	"crystal":     Color(0.85, 0.95, 1.00),   # crystal pale
	"dual":        Color(0.85, 0.85, 0.95),   # twin silver
	"sound":       Color(0.95, 0.85, 1.00),   # echo lilac
	"ponderous":   Color(0.55, 0.55, 0.65),   # heavy slate
	"slaying":     Color(1.00, 0.50, 0.35),   # bloody coral
	"psychic":     Color(0.90, 0.55, 1.00),   # psi pink
	# Wired flavor mechanics that previously lacked a color entry — see
	# actor.gd: thorns/reflective return paths, harm dmg in/out,
	# rage on-kill atk_pct, precision anti-streak crit, vitality regen.
	"thorns":      Color(0.85, 0.55, 0.55),   # blood briar
	"reflective":  Color(0.70, 0.85, 1.00),   # mirror cyan
	"harm":        Color(1.00, 0.35, 0.25),   # crimson
	"rage":        Color(1.00, 0.40, 0.20),   # fury red-orange
	"precision":   Color(1.00, 0.85, 0.50),   # marksman gold
	"vitality":    Color(0.55, 1.00, 0.55),   # vital green
	"agility":     Color(0.70, 1.00, 0.65),   # nimble lime
	"shadow":      Color(0.40, 0.30, 0.55),   # umbra purple
	# S5 race-anchor conditional flavors (a04 §5 + a10 rescopes).
	"feast":       Color(0.55, 0.85, 0.45),   # ravenous green
	"first_blood": Color(0.95, 0.55, 0.40),   # opening-strike coral
	"petrify":     Color(0.65, 0.65, 0.55),   # petrified stone
	# S11 boss-anchor flavor colors (a07 §6.1-6.12). Used by the boss
	# anchor uniques' display flavor_tags — no combat mechanic of their
	# own, just the chrome surface.
	"bloody":      Color(0.75, 0.20, 0.25),   # arterial red
	"bloodlust":   Color(0.95, 0.30, 0.40),   # battle red
	"tide":        Color(0.45, 0.75, 0.95),   # tidal blue
}
# Priority order — wired-mechanic flavors first because their COLOR
# carries the most meaning. Decorative-but-wired ones below. Anything
# missing here resolves to alpha=0 in flavor_color_for() and falls
# back to rarity tint.
const _FLAVOR_PRIORITY := [
	"vampiric", "fire", "cold", "holy", "poison", "thunderous",
	"dark", "dragon_bane", "brutal", "arcane", "elemental",
	"willpower", "fortified", "swiftness", "regen", "stealth",
	"lordly", "footwork", "warding", "wisdom",
	"fire_res", "cold_res", "poison_res", "vision",
	"rampaging", "flying", "fortune", "faith", "acrobat",
	"death", "earth", "guardian", "demon", "crystal",
	"dual", "sound", "ponderous", "slaying", "psychic",
]

# Pick the flavor color that should drive an item's tint, or empty
# Color() (alpha=0) when no priority tag is present. Caller checks alpha.
static func flavor_color_for(flavor_tags: Array) -> Color:
	if flavor_tags == null or flavor_tags.is_empty():
		return Color(0, 0, 0, 0)
	for tag in _FLAVOR_PRIORITY:
		if tag in flavor_tags:
			return FLAVOR_COLORS.get(tag, Color(0, 0, 0, 0))
	return Color(0, 0, 0, 0)

# --- Overlay-icon badges --------------------------------------------------
# Inventory cells get a tiny corner badge based on the item's flavor /
# meta-rarity / spell-status. Same DCSS i-*.png pictogram used for many
# different meanings — TINT carries the difference (skull green = poison,
# skull red = vampiric, skull purple = death, etc). Lets us reuse 26
# pictogram icons across hundreds of item meanings. 2026-06-05.
const _BADGE_BASE := "res://assets/tiles/items/spells/scrolls/"

# Priority-ordered map: flavor tag → (icon stem, optional color override).
# When override is "" the badge tint falls back to FLAVOR_COLORS[tag] so
# the same i-torment.png reads green for poison, red for vampiric, etc.
const _FLAVOR_BADGE := {
	# meta-rarity overrides — handled separately, see badge_for_item.
	# Wired-mechanic flavors first.
	"vampiric":   "i-torment",            # skull → red
	"fire":       "i-immolation",         # flame → orange
	"cold":       "i-fog",                # mist → cyan
	"holy":       "i-holy_word",          # cross → gold
	"poison":     "i-poison",             # flask → green
	"thunderous": "i-noise",              # wave → electric blue
	"lightning":  "i-noise",
	"dark":       "i-torment",            # skull → purple (different tint than vampiric)
	"brutal":     "i-immolation",         # flame → red
	"arcane":     "i-magic_mapping",      # eye → purple
	# Defensive flavors get distinct icons.
	"fortified":  "i-enchant_armour",
	"warding":    "i-remove_curse",
	"regen":      "i-recharging",
	"stealth":    "i-amnesia",
	"swiftness":  "i-blinking",
	"footwork":   "i-blinking",
	"flying":     "i-blinking",
	# Other-utility flavors.
	"vision":     "i-identify",
	"wisdom":     "i-magic_mapping",
	"fortune":    "i-acquirement",
	"faith":      "i-holy_word",
	"acrobat":    "i-blinking",
	"death":      "i-torment",
	"earth":      "i-noise",
	"demon":      "i-unholy_creation",
	"crystal":    "i-fog",
	"dragon_bane":"i-fear",
	"slaying":    "i-vulnerability",
	"psychic":    "i-fear",
	"sound":      "i-noise",
	"lordly":     "i-holy_word",
	"willpower":  "i-magic_mapping",
	"elemental":  "i-immolation",
	"rampaging":  "i-fear",
	"ponderous":  "i-curse_armour",
	"dual":       "i-brand-weapon",
	"fire_res":   "i-immolation",
	"cold_res":   "i-fog",
	"poison_res": "i-poison",
}

# Meta-rarity badges (Primal / Ancient) take priority over flavor badges
# since they're visually distinctive item-overhaul promotions.
const _META_BADGE := {
	"primal":  ["i-curse_weapon", Color(1.00, 0.30, 0.30)],   # cursed-red glyph
	"ancient": ["i-acquirement", Color(1.00, 0.85, 0.30)],    # treasure gold
}

# Returns an Array of badge dicts {"icon": String, "tint": Color}.
# Order is highest-priority first (meta_rarity wins over flavor; within
# flavors, _FLAVOR_PRIORITY rules). Cap at 3 — past that the badge cycle
# moves too fast to read. Empty array when no badge applies.
# 2026-06-05 — multi-badge: cells fade between them on a loop so a
# Vampiric Fire weapon shows BOTH a red skull + an orange flame.
# 2026-06-05 follow-up: common-rarity items get NO flavor badge.
# Reason: a "Shadowed Leather Cloak" rolled at common rarity reads as
# misleading — name promises a shadow theme, but the item has 0 affixes
# (rarity_affix_count=0), no implicit, and the default_tint mode=normal
# can't visibly recolor a white-base sprite. Showing a shadow corner
# badge made it look "special" while delivering nothing. Meta-rarity
# (Primal/Ancient) badges still fire on commons since those ARE
# meaningful upgrades regardless of base rarity.
static func badges_for_item(item: Dictionary, inst: Variant) -> Array:
	if typeof(item) != TYPE_DICTIONARY or item.is_empty():
		return []
	var out: Array = []
	# Meta-rarity always leads — fires regardless of base rarity since
	# Primal / Ancient is mechanically meaningful by itself.
	if typeof(inst) == TYPE_DICTIONARY:
		var meta: String = String(inst.get("meta_rarity", ""))
		if _META_BADGE.has(meta):
			var entry: Array = _META_BADGE[meta]
			out.append({
				"icon": _BADGE_BASE + String(entry[0]) + ".png",
				"tint": entry[1],
			})
	# Flavor badges only render when stat-backed — i.e. an enchant or
	# a rolled/implicit affix whose stat aligns with the flavor.
	# Pre-2026-06-07 a "mossy" common boot (poison flavor_tag, 0
	# stats) got a poison badge from the cosmetic tag alone. Now
	# the badge appears only when the item actually does poison
	# things. Plus: still suppressed on commons regardless (commons
	# now roll 1 affix but their badge would still be misleading
	# on items where the rolled affix doesn't match the flavor).
	var rarity: String = String(item.get("rarity", "common"))
	if rarity != "common":
		var tags: Array = stat_backed_flavor_tags(item, inst)
		for tag in _FLAVOR_PRIORITY:
			if tag in tags and _FLAVOR_BADGE.has(tag):
				out.append({
					"icon": _BADGE_BASE + String(_FLAVOR_BADGE[tag]) + ".png",
					"tint": FLAVOR_COLORS.get(tag, Color(0.95, 0.95, 0.95, 1.0)),
				})
			if out.size() >= 3:
				break
	return out

# Back-compat single-badge helper.
static func badge_for_item(item: Dictionary, inst: Variant) -> Dictionary:
	var arr: Array = badges_for_item(item, inst)
	return arr[0] if not arr.is_empty() else {}

# Affix id → flavor tag mapping. Used by `stat_backed_flavor_tags` to
# decide whether a flavor badge has stat backing (a rolled or implicit
# affix whose stat aligns with the flavor). Pre-2026-06-07 a "mossy"
# (poison-flavor) common boot got a poison badge from the cosmetic
# flavor_tag alone, even with 0 stats. Now the badge appears only
# when the item carries an enchant matching the flavor OR a rolled
# affix in this map.
const _AFFIX_FLAVOR_MAP := {
	"of_lifesteal":      "vampiric",
	"of_fire_resist":    "fire",
	"of_cold_resist":    "cold",
	"of_lightning_resist": "lightning",
	"of_holy_resist":    "holy",
	"of_poison_resist":  "poison",
	"of_dark_resist":    "dark",
	"of_embers":         "fire",
	"of_frost":          "cold",
	"of_static":         "lightning",
	"of_radiance":       "holy",
	"of_venom":          "poison",
	"of_shadow":         "dark",
}

# Tags whose payload comes from item enchants OR rolled affixes that
# carry a matching stat. Decorative `item.flavor_tags` entries don't
# count. Used by badges_for_item to suppress cosmetic badges.
static func stat_backed_flavor_tags(item: Dictionary, inst: Variant) -> Array:
	var out: Array = []
	if typeof(inst) != TYPE_DICTIONARY:
		return out
	# Per-instance enchant always counts (it's a real payload).
	var enchant: String = String(inst.get("enchant", ""))
	if enchant != "" and not (enchant in out):
		out.append(enchant)
	# Compound enchants split into their components.
	var combo_id: String = String(inst.get("enchant_combo", ""))
	if combo_id != "":
		for ct in EnchantCombos.components_for(combo_id):
			var s: String = String(ct)
			if not (s in out):
				out.append(s)
	# Implicit affixes — these ARE the item's mechanical identity
	# (uniques like Vampire's Tooth always lifesteal regardless of
	# rolls), so they count as stat-backed.
	for aid in item.get("implicit_affixes", []):
		var flavor: String = String(_AFFIX_FLAVOR_MAP.get(String(aid), ""))
		if flavor != "" and not (flavor in out):
			out.append(flavor)
	# Rolled affixes — map by id to flavor where applicable.
	for entry in inst.get("affixes", []):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var aid2: String = String(entry.get("id", ""))
		var flavor2: String = String(_AFFIX_FLAVOR_MAP.get(aid2, ""))
		if flavor2 != "" and not (flavor2 in out):
			out.append(flavor2)
	return out

# Resolve the *effective* color for an item: meta-rarity > flavor tag
# > rarity. Lerp at the rarity strength so a common vampiric ring
# still tints (faintly) and a legendary vampiric ring is deep blood
# red. An Ancient item lerps toward gold; a Primal item lerps deep
# red regardless of rarity/flavor. Returns Color(1,1,1,1) when no
# tint applies.
static func item_modulate(rarity: String, flavor_tags: Array = [], meta_rarity: String = "") -> Color:
	var strength: float = float(_ICON_TINT_STRENGTH.get(rarity, 0.0))
	var slider: float = VideoSettings.tunable("item_tint_strength", 1.0)
	strength = clampf(strength * slider, 0.0, 1.0)
	# Meta-rarity wins over flavor + rarity. Always at least
	# "epic-strength" lerp so it reads dramatically.
	var meta_col: Color = meta_rarity_color(meta_rarity)
	if meta_col.a > 0.0:
		var ms: float = max(strength, clampf(0.55 * slider, 0.0, 1.0))
		return Color(
			lerp(1.0, meta_col.r, ms),
			lerp(1.0, meta_col.g, ms),
			lerp(1.0, meta_col.b, ms),
			1.0,
		)
	# Flavor tags imply at least uncommon-strength — items with
	# meaningful tags always read tagged, even on commons. Slider
	# scales the flavor floor so "0" really means "no tint."
	var fc: Color = flavor_color_for(flavor_tags)
	if fc.a > 0.0:
		strength = max(strength, clampf(0.30 * slider, 0.0, 1.0))
		if strength <= 0.0:
			return Color(1, 1, 1, 1)
		return Color(
			lerp(1.0, fc.r, strength),
			lerp(1.0, fc.g, strength),
			lerp(1.0, fc.b, strength),
			1.0,
		)
	if strength <= 0.0:
		return Color(1, 1, 1, 1)
	var col: Color = rarity_color(rarity)
	return Color(
		lerp(1.0, col.r, strength),
		lerp(1.0, col.g, strength),
		lerp(1.0, col.b, strength),
		1.0,
	)

# Back-compat alias — old call sites used rarity_icon_modulate. Kept
# so the call surface stays one line; new code prefers item_modulate
# which folds flavor tags in.
static func rarity_icon_modulate(rarity: String) -> Color:
	return item_modulate(rarity, [])

# Glow color matching the same priority: flavor tag wins, else rarity.
# Returns Color(0,0,0,0) when no glow should draw.
static func item_glow_color(rarity: String, flavor_tags: Array = []) -> Color:
	var fc: Color = flavor_color_for(flavor_tags)
	if fc.a > 0.0:
		return Color(fc.r, fc.g, fc.b, 0.85)
	# Rarity-only glow gates at epic+ (matches the prior behavior).
	if rarity == "legendary":
		var c: Color = rarity_color("legendary")
		return Color(c.r, c.g, c.b, 0.80)
	if rarity == "epic":
		var c2: Color = rarity_color("epic")
		return Color(c2.r, c2.g, c2.b, 0.65)
	return Color(0, 0, 0, 0)

# Rarity decoration for an inventory / equipped cell. Drawn as a square
# border + an inset halo that fades from the rarity color at the edges
# toward transparent at the center, sitting behind the item sprite. The
# old silhouette-tracing shader produced a halo that hugged the sprite
# outline (good for floor loot drops, busy in cramped UI cells); the cell
# decoration here is geometric and predictable.
#
# Children added (in z order, lowest first):
#   1. halo: ColorRect filling the cell at full rarity tint
#   2. center mask: ColorRect inset by `inset` px filling with COL_PANEL,
#      carving out the center so only the edge ring stays tinted
#   3. border: ReferenceRect at full cell size in rarity color
# The caller adds the sprite + button on top so they sit above the halo.
# Enchant-aware version of add_rarity_cell_decor. When `flavor_tags`
# contains a priority flavor (vampiric/fire/cold/holy/etc.), the
# border color tweens between the rarity color and the flavor color
# in a slow pulse — visually telegraphs "this item rolled an enchant"
# without an extra widget. Falls back to the static version when no
# flavor is present.
static func add_item_cell_decor(parent: Control, size_px: int, rarity: String, flavor_tags: Array, halo_strength: float = 0.35) -> void:
	var fc: Color = flavor_color_for(flavor_tags)
	if fc.a <= 0.0:
		# No enchant — same as before.
		add_rarity_cell_decor(parent, size_px, rarity, halo_strength)
		return
	var col: Color = rarity_color(rarity)
	if halo_strength > 0.0:
		var halo := ColorRect.new()
		halo.color = Color(col.r, col.g, col.b, halo_strength)
		halo.size = Vector2(size_px, size_px)
		halo.mouse_filter = Control.MOUSE_FILTER_IGNORE
		parent.add_child(halo)
		var inset: int = maxi(4, int(size_px * 0.22))
		var mask := ColorRect.new()
		mask.color = Color(0.0, 0.0, 0.0, 0.55)
		mask.position = Vector2(inset, inset)
		mask.size = Vector2(size_px - inset * 2, size_px - inset * 2)
		mask.mouse_filter = Control.MOUSE_FILTER_IGNORE
		parent.add_child(mask)
	# Border pulses between rarity color and flavor color so the cell
	# reads as both "rare/legendary" AND "enchanted with fire."
	var border := ReferenceRect.new()
	border.position = Vector2.ZERO
	border.size = Vector2(size_px, size_px)
	border.border_color = col
	border.border_width = 1.5
	border.editor_only = false
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(border)
	var pulse := border.create_tween().set_loops()
	pulse.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	pulse.tween_property(border, "border_color", fc, 1.2)
	pulse.tween_property(border, "border_color", col, 1.2)

# Apply a default focus + hover stylebox set to a Button. Default Godot
# focus is a thin white outline that reads as "broken UI" in the dark
# amber palette; hover is a flat gray fill. We ship a consistent
# amber-accent treatment so every Button on every screen feels part of
# the same chrome. UI polish 2026-06-04.
#
# Pure-additive — caller can still override individual styleboxes if a
# specific button (e.g. Deploy) wants a stronger treatment.
static func style_button(btn: Button) -> void:
	if btn == null:
		return
	# Normal — transparent fill, dim border so the button "sits in" the
	# panel rather than being a callout. Padding kept default so existing
	# layouts don't shift.
	var sb_normal := StyleBoxFlat.new()
	sb_normal.bg_color = Color(0.0, 0.0, 0.0, 0.0)
	sb_normal.border_color = BORDER_DIM
	sb_normal.border_width_left = 1
	sb_normal.border_width_top = 1
	sb_normal.border_width_right = 1
	sb_normal.border_width_bottom = 1
	sb_normal.corner_radius_top_left = 3
	sb_normal.corner_radius_top_right = 3
	sb_normal.corner_radius_bottom_left = 3
	sb_normal.corner_radius_bottom_right = 3
	# Hover — faint amber wash so the cursor visibly lands on something.
	var sb_hover := sb_normal.duplicate() as StyleBoxFlat
	sb_hover.bg_color = Color(COL_AMBER.r, COL_AMBER.g, COL_AMBER.b, 0.10)
	sb_hover.border_color = COL_AMBER
	# Pressed — slightly darker bg + brighter border for tactile feedback.
	var sb_pressed := sb_normal.duplicate() as StyleBoxFlat
	sb_pressed.bg_color = Color(COL_AMBER.r, COL_AMBER.g, COL_AMBER.b, 0.18)
	sb_pressed.border_color = COL_GOLD
	# Focus — keyboard-nav ring. 2px gold outline so tab-target is obvious
	# without screen-reader noise.
	var sb_focus := StyleBoxFlat.new()
	sb_focus.bg_color = Color(0.0, 0.0, 0.0, 0.0)
	sb_focus.border_color = COL_GOLD
	sb_focus.border_width_left = 2
	sb_focus.border_width_top = 2
	sb_focus.border_width_right = 2
	sb_focus.border_width_bottom = 2
	sb_focus.corner_radius_top_left = 3
	sb_focus.corner_radius_top_right = 3
	sb_focus.corner_radius_bottom_left = 3
	sb_focus.corner_radius_bottom_right = 3
	# Disabled — flat dim bg so the visual carries the disabled cue
	# regardless of font color (some screens override font_disabled_color).
	var sb_disabled := sb_normal.duplicate() as StyleBoxFlat
	sb_disabled.bg_color = Color(0.0, 0.0, 0.0, 0.30)
	sb_disabled.border_color = Color(BORDER_DIM.r, BORDER_DIM.g, BORDER_DIM.b, 0.45)
	btn.add_theme_stylebox_override("normal", sb_normal)
	btn.add_theme_stylebox_override("hover", sb_hover)
	btn.add_theme_stylebox_override("pressed", sb_pressed)
	btn.add_theme_stylebox_override("focus", sb_focus)
	btn.add_theme_stylebox_override("disabled", sb_disabled)
	btn.add_theme_color_override("font_color", COL_AMBER)
	btn.add_theme_color_override("font_hover_color", Color(1.0, 0.92, 0.55))
	btn.add_theme_color_override("font_pressed_color", COL_GOLD)
	btn.add_theme_color_override("font_disabled_color", COL_DIM)

# Apply style_button() to every Button descendant of `root`. Call from
# screen scripts AFTER all dynamically-built buttons have been added.
# Cheap: walks the tree once, checks each node's class.
static func style_all_buttons(root: Node) -> void:
	if root == null:
		return
	if root is Button:
		style_button(root as Button)
	for child in root.get_children():
		style_all_buttons(child)

static func add_rarity_cell_decor(parent: Control, size_px: int, rarity: String, halo_strength: float = 0.35) -> void:
	var col: Color = rarity_color(rarity)
	if halo_strength > 0.0:
		var halo := ColorRect.new()
		halo.color = Color(col.r, col.g, col.b, halo_strength)
		halo.size = Vector2(size_px, size_px)
		halo.mouse_filter = Control.MOUSE_FILTER_IGNORE
		parent.add_child(halo)
		# Inset mask: cuts a darker square out of the middle so the halo
		# only shows as a ring on the cell's edges. Inset depth scales
		# with cell size — about 25% in from each side.
		var inset: int = maxi(4, int(size_px * 0.22))
		var mask := ColorRect.new()
		mask.color = Color(0.0, 0.0, 0.0, 0.55)
		mask.position = Vector2(inset, inset)
		mask.size = Vector2(size_px - inset * 2, size_px - inset * 2)
		mask.mouse_filter = Control.MOUSE_FILTER_IGNORE
		parent.add_child(mask)
	# Square border in the rarity color. Always 1px so common (white)
	# items still get a clean cell outline.
	var border := ReferenceRect.new()
	border.position = Vector2.ZERO
	border.size = Vector2(size_px, size_px)
	border.border_color = col
	border.border_width = 1.0
	border.editor_only = false
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(border)

