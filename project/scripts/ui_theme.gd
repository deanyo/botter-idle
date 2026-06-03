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
const COL_PANEL := Color(0.0, 0.0, 0.0, 0.85)
const COL_PANEL_BORDER := Color(0.35, 0.3, 0.18, 0.65)
const COL_BG := Color(0.0, 0.0, 0.0, 1.0)

# Rarity tints — used for item borders / tooltips / outline glow.
const COL_RARITY := {
	"common":    Color(0.85, 0.85, 0.85),
	"uncommon":  Color(0.4, 0.7, 1.0),
	"rare":      Color(1.0, 0.9, 0.3),
	"epic":      Color(1.0, 0.5, 0.2),
	"legendary": Color(1.0, 0.3, 0.3),
}

# Type sizes
const FS_TITLE := 28
const FS_HEADER := 18
const FS_STAT := 16
const FS_BODY := 14
const FS_SMALL := 12
const FS_DEBUG := 12

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
	return tags

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
}
const _FLAVOR_PRIORITY := [
	"vampiric", "fire", "cold", "holy", "poison",
	"thunderous", "dark", "dragon_bane", "brutal",
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

# Resolve the *effective* color for an item: a flavor tag wins over
# rarity, and we lerp at the rarity strength so a common vampiric ring
# still tints (faintly) and a legendary vampiric ring is deep blood
# red. Returns Color(1,1,1,1) when no tint applies.
static func item_modulate(rarity: String, flavor_tags: Array = []) -> Color:
	var strength: float = float(_ICON_TINT_STRENGTH.get(rarity, 0.0))
	# Multiply by the FX Tuner item_tint_strength slider (default 1.0)
	# so dragging the slider visibly remaps every item's tint without
	# touching the per-rarity table.
	var slider: float = VideoSettings.tunable("item_tint_strength", 1.0)
	strength = clampf(strength * slider, 0.0, 1.0)
	# Flavor tags also imply at least uncommon-strength — items with
	# meaningful tags should always read tagged, even on commons. The
	# slider also scales the flavor floor so "0" really means "no tint."
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

