// Pass-through tile shader. Was used to fade dungeon tiles per-cell
// using FogSystem.vis_texture, but that produced "ticking grey" trails
// because the discrete cell-aligned visibility lagged the smooth fog
// overlay. The new fog_overlay.gdshader drives ALL fog from above using
// shader-side ray-march; tiles render at full alpha and the overlay's
// darkness alone gates what the player sees.
//
// Kept as a separate material (instead of dropping the material on the
// TileMapLayer) so any future per-tile effects (damage flash, biome
// modulation, etc.) can plug in without re-plumbing.
shader_type canvas_item;

void fragment() {
	COLOR = texture(TEXTURE, UV);
}
