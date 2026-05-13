// Per-tile visibility fade for dungeon TileMapLayers. Replaces the
// per-cell modulate loop the old per-Sprite2D MapRenderer ran every
// frame. Reads FogSystem.vis_texture (R8: 1.0 = visible, 0.5 =
// explored, 0.0 = unseen) and modulates the tile's alpha.
//
// world position via varying: VERTEX is in the TileMapLayer's local
// coords, MODEL_MATRIX takes it to world.
shader_type canvas_item;

uniform sampler2D visibility_tex : filter_linear, repeat_disable;
uniform vec2 grid_size = vec2(80.0, 80.0);
uniform float tile_size_px = 32.0;
uniform float reveal_strength : hint_range(0.0, 1.0) = 1.0;

varying vec2 v_world;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	vec2 cell_uv = (v_world / tile_size_px) / grid_size;
	float vis = 0.0;
	if (cell_uv.x >= 0.0 && cell_uv.x <= 1.0 && cell_uv.y >= 0.0 && cell_uv.y <= 1.0) {
		vis = texture(visibility_tex, cell_uv).r;
	}
	// Smoothstep gives the soft falloff at LoS rim that the old fade did.
	float alpha = smoothstep(0.45, 0.95, vis * reveal_strength);
	vec4 base = texture(TEXTURE, UV);
	COLOR = vec4(base.rgb, base.a * alpha);
}
