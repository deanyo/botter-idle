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

# Panel / chrome
const COL_PANEL := Color(0.04, 0.04, 0.06, 0.85)
const COL_PANEL_BORDER := Color(0.35, 0.3, 0.18, 0.65)
const COL_BG := Color(0.05, 0.05, 0.07, 1.0)

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
		mask.color = Color(0.04, 0.04, 0.06, 0.55)
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

