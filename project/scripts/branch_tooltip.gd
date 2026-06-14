class_name BranchTooltip
extends Control

# Item-tooltip-styled branch tooltip used by the Outpost dungeon-deploy
# picker. Mirrors ItemTooltip's structure (rarity border, title in rarity
# color, separators, color-coded modifier lines, italic flavor block) so
# the deploy buttons feel like inspecting a magic item — not a flat
# string. Caller passes a structured data dict to render().
#
# Data shape:
#   {
#     "name": String,                 # display name
#     "tier": int,                    # 1..5 (drives rarity color)
#     "rarity": String,               # common/uncommon/rare/epic/legendary
#     "is_unlocked": bool,
#     "status_line": String,          # "Unlocked · 1/2 boss kills"
#     "lock_hint": String,            # for locked branches
#     "cr": int,                      # recommended CR
#     "boss_name": String,
#     "enemies": Array[String],       # capped at 6
#     "enemy_overflow": int,
#     "vault_themes": Array[String],
#     "loot": Array[Dictionary],      # {name, is_boss_anchor}
#     "modifiers": Array[Dictionary], # {name, desc, category}
#   }

const TOOLTIP_W := 280
const PADDING := 10
const LINE_GAP := 4

const COL_BODY := Color(0.92, 0.92, 0.85)
const COL_DIM := Color(0.65, 0.62, 0.5)
const COL_HEADER := Color(0.92, 0.78, 0.45)         # amber section headers
const COL_SUBTITLE := Color(0.65, 0.62, 0.5)
const COL_BOSS := Color(1.00, 0.85, 0.30)           # boss line gold
const COL_LOOT_ANCHOR := Color(1.00, 0.78, 0.30)    # boss-drop anchors
const COL_LOOT_BIOME := Color(0.65, 0.85, 1.00)     # biome-pool drops
const COL_UNLOCKED := Color(0.55, 0.95, 0.55)
const COL_LOCKED := Color(0.95, 0.50, 0.40)
const COL_HOTKEY := Color(0.5, 0.5, 0.45)

# Modifier category colors — match the player's mental model:
#   reward = gold (loot/gold/chest stuff)
#   danger = red  (more enemies, harder enemies, extra elites)
#   utility = blue (structural — endless, etc.)
const COL_MOD_REWARD := Color(1.00, 0.85, 0.30)
const COL_MOD_DANGER := Color(0.95, 0.45, 0.40)
const COL_MOD_UTILITY := Color(0.55, 0.85, 1.00)
const COL_MOD_NEUTRAL := Color(0.85, 0.85, 0.75)

var _vbox: VBoxContainer = null
var _bg: ColorRect = null
var _border: ReferenceRect = null
var _glow_color: Color = Color(0, 0, 0, 0)
var _glow_alpha: float = 0.0
var _glow_pulse_t: float = 0.0
var _is_high_tier: bool = false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 200
	custom_minimum_size = Vector2(TOOLTIP_W, 0)
	_bg = ColorRect.new()
	_bg.color = Color(0.05, 0.04, 0.02, 0.94)
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg.anchor_right = 1.0
	_bg.anchor_bottom = 1.0
	add_child(_bg)
	_border = ReferenceRect.new()
	_border.border_color = COL_HEADER
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
	set_process(true)

# Layered halo behind the panel — same shape as ItemTooltip's draw, so
# both surfaces feel like the same family of UI affordance. Pulses on
# rare+ branches.
func _draw() -> void:
	if _glow_color.a <= 0.001 or size.x <= 0.0 or size.y <= 0.0:
		return
	var layers: int = 6
	var pulse: float = 1.0
	if _is_high_tier:
		pulse = 0.65 + 0.35 * sin(_glow_pulse_t * 2.6)
	for i in range(layers, 0, -1):
		var off: float = float(i) * 5.0
		var layer_alpha: float = _glow_alpha * pow(1.0 - float(i) / float(layers + 1), 1.8) * pulse
		var c: Color = Color(_glow_color.r, _glow_color.g, _glow_color.b, layer_alpha)
		draw_rect(Rect2(Vector2(-off, -off), size + Vector2(off * 2.0, off * 2.0)), c, false, 1.5)

func _process(delta: float) -> void:
	if _glow_alpha > 0.0 and _is_high_tier:
		_glow_pulse_t += delta
		queue_redraw()

func render(data: Dictionary) -> void:
	for c in _vbox.get_children():
		c.queue_free()
	if data.is_empty():
		return
	var rarity: String = String(data.get("rarity", "common"))
	var rarity_col: Color = UITheme.rarity_color(rarity)
	_border.border_color = rarity_col
	# Border thickness escalates with tier so T5 deploys read as
	# "weight" before the player parses any text — same pattern as
	# ItemTooltip's rarity-thickness mapping.
	_border.border_width = {
		"common": 1.0, "uncommon": 1.5, "rare": 2.0,
		"epic": 2.5, "legendary": 3.0,
	}.get(rarity, 1.5)
	_glow_color = rarity_col
	_glow_alpha = {
		"common": 0.0, "uncommon": 0.10, "rare": 0.20,
		"epic": 0.32, "legendary": 0.45,
	}.get(rarity, 0.0)
	_is_high_tier = (rarity == "epic" or rarity == "legendary")
	_glow_pulse_t = 0.0
	queue_redraw()
	# Title — branch name in rarity color.
	var title := _make_label(String(data.get("name", "?")), 16, rarity_col, true)
	title.custom_minimum_size = Vector2(TOOLTIP_W - PADDING * 2, 0)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_vbox.add_child(title)
	# Pulse the title color on epic/legendary tiers (same trick as
	# ItemTooltip — makes the deploy "shine" before commitment).
	if _is_high_tier:
		var t := title.create_tween().set_loops()
		t.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		t.tween_property(title, "modulate", Color(1.15, 1.10, 0.95), 0.7)
		t.tween_property(title, "modulate", Color(1.0, 1.0, 1.0), 0.7)
	# Subtitle: "Tier N · Branch · CR M".
	var subtitle_parts: Array = ["Tier %d" % int(data.get("tier", 1))]
	subtitle_parts.append("Branch")
	var cr: int = int(data.get("cr", 0))
	if cr > 0:
		subtitle_parts.append("CR %d recommended" % cr)
	_vbox.add_child(_make_label(" · ".join(subtitle_parts), 11, COL_SUBTITLE, false))
	# Status line — green when unlocked, red + lock-hint when locked.
	var is_unlocked: bool = bool(data.get("is_unlocked", false))
	var status_line: String = String(data.get("status_line", ""))
	if is_unlocked and status_line != "":
		_vbox.add_child(_make_label(status_line, 12, COL_UNLOCKED, true))
	elif not is_unlocked:
		var lock_hint: String = String(data.get("lock_hint", "LOCKED"))
		var lock_lbl := _make_label(lock_hint, 12, COL_LOCKED, true)
		lock_lbl.custom_minimum_size = Vector2(TOOLTIP_W - PADDING * 2, 0)
		lock_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_vbox.add_child(lock_lbl)
	_vbox.add_child(_make_separator())
	# Boss line — gold, bold (echoes ItemTooltip damage line).
	var boss_name: String = String(data.get("boss_name", ""))
	if boss_name != "":
		_vbox.add_child(_make_label("Boss: " + boss_name, 13, COL_BOSS, true))
	# Enemy roster — section header + body line.
	var enemies: Array = data.get("enemies", [])
	if enemies.size() > 0:
		_vbox.add_child(_make_section_header("Enemies"))
		var line: String = ", ".join(enemies)
		var overflow: int = int(data.get("enemy_overflow", 0))
		if overflow > 0:
			line += "  +%d more" % overflow
		var enemy_lbl := _make_label(line, 11, COL_BODY, false)
		enemy_lbl.custom_minimum_size = Vector2(TOOLTIP_W - PADDING * 2, 0)
		enemy_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_vbox.add_child(enemy_lbl)
	# Vault themes.
	var themes: Array = data.get("vault_themes", [])
	if themes.size() > 0:
		_vbox.add_child(_make_section_header("Vault themes"))
		var theme_strs: Array = []
		for t in themes:
			theme_strs.append(String(t).capitalize())
		_vbox.add_child(_make_label(", ".join(theme_strs), 11, COL_BODY, false))
	if (enemies.size() > 0 or themes.size() > 0) and (data.get("loot", []) as Array).size() > 0:
		_vbox.add_child(_make_separator())
	# Loot — boss anchor in gold, biome-pool entries in cool blue. Each
	# on its own line so the entries pop visually.
	var loot: Array = data.get("loot", [])
	if loot.size() > 0:
		_vbox.add_child(_make_section_header("Notable loot"))
		for entry in loot:
			if not (entry is Dictionary):
				continue
			var nm: String = String(entry.get("name", "?"))
			var anchor: bool = bool(entry.get("is_boss_anchor", false))
			var loot_text: String = "• " + nm
			if anchor:
				loot_text += "  (boss anchor)"
			var loot_color: Color = COL_LOOT_ANCHOR if anchor else COL_LOOT_BIOME
			_vbox.add_child(_make_label(loot_text, 12, loot_color, anchor))
	# Run modifiers — each one a colored "+ Name" line plus dim wrapped
	# desc beneath. Color reflects category (reward/danger/utility) so
	# the player reads "this deploy is loaded with gold and danger" at
	# a glance instead of parsing a wall of plain text.
	var modifiers: Array = data.get("modifiers", [])
	if modifiers.size() > 0:
		_vbox.add_child(_make_separator())
		_vbox.add_child(_make_section_header("Run modifiers"))
		for m in modifiers:
			if not (m is Dictionary):
				continue
			var m_name: String = String(m.get("name", "?"))
			var m_desc: String = String(m.get("desc", ""))
			var m_cat: String = String(m.get("category", "neutral"))
			var m_col: Color = _modifier_color(m_cat)
			_vbox.add_child(_make_label("+ " + m_name, 12, m_col, true))
			if m_desc != "":
				var desc_lbl := _make_label("  " + m_desc, 10, COL_DIM, false)
				desc_lbl.custom_minimum_size = Vector2(TOOLTIP_W - PADDING * 2, 0)
				desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				_vbox.add_child(desc_lbl)
	# Click hint — same kind of footer ItemTooltip uses.
	if is_unlocked:
		_vbox.add_child(_make_separator())
		_vbox.add_child(_make_label("[Click] deploy", 10, COL_HOTKEY, false))
	# Resize to content.
	await get_tree().process_frame
	if is_instance_valid(self) and is_instance_valid(_vbox):
		size = Vector2(TOOLTIP_W, _vbox.size.y + PADDING * 2)

func _modifier_color(category: String) -> Color:
	match category:
		"reward": return COL_MOD_REWARD
		"danger": return COL_MOD_DANGER
		"utility": return COL_MOD_UTILITY
		_: return COL_MOD_NEUTRAL

func _make_section_header(text: String) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.add_theme_color_override("font_color", COL_HEADER)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return lbl

func _make_label(text: String, size_pt: int, color: Color, bold: bool) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size_pt)
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
