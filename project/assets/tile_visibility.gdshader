// Per-cell tile shader. Originally a pass-through after the fog overlay
// rewrite. Now adds memory-desaturation: tiles that are in fog memory
// (seen but not currently lit) render with reduced saturation, giving
// exploration history visible weight without changing readability.
//
// Reads FogSystem.vis_texture (R8 grayscale, encoded by fog_system.gd's
// _update_texture):
//   r = 0.0 → unseen        (covered by opaque fog overlay anyway)
//   r = 0.5 → memory        (desaturate)
//   r = 1.0 → currently visible (full color)
//
// Note: the previous abandoned approach used this same texture to fade
// alpha per-cell, which produced "ticking grey" trails as the bot moved
// cell-to-cell. Saturation shifts are far less perceptually jarring than
// alpha shifts, and the fog OVERLAY (continuous shader-side ray-march)
// already handles the smooth visible/dark transition. So memory
// desaturation reads as a soft historical-memory tint, not a tick.

shader_type canvas_item;

uniform sampler2D visibility_tex : filter_linear, repeat_disable;
uniform vec2 grid_size = vec2(80.0, 80.0);
uniform float tile_size_px = 32.0;
// 0.0 disables desaturation entirely (legacy / no-grid path). When the
// dungeon pushes a real visibility texture this stays at 1.0.
uniform float memory_strength : hint_range(0.0, 1.0) = 0.6;

void fragment() {
	vec4 base = texture(TEXTURE, UV);

	// Convert this fragment's screen-space position back to a grid cell.
	// Sample visibility at cell-uv, default to 1.0 (visible) when no
	// texture provided.
	vec2 world_px = SCREEN_UV * (1.0 / SCREEN_PIXEL_SIZE);
	// We can't reach world coords from a tile shader without piping camera
	// state in — but we don't need to: VERTEX is in local-tile space, and
	// we can recover the cell from FRAGCOORD using grid_size + tile_size.
	// Simpler approach: read visibility per-pixel using the canvas-item's
	// own VERTEX-space coords. Both TileMapLayers in this project sit at
	// (0,0) with no transform, so VERTEX in pixels === world pixels.
	vec2 cell_uv = (VERTEX / tile_size_px) / grid_size;
	cell_uv = clamp(cell_uv, vec2(0.0), vec2(1.0));
	float vis = texture(visibility_tex, cell_uv).r;

	// vis == 1.0 → fully visible, no change
	// vis ~= 0.5 → memory state, desaturate
	// vis == 0.0 → unseen, but fog overlay covers this anyway
	float desat_t = (1.0 - smoothstep(0.4, 0.95, vis)) * memory_strength;
	float luma = dot(base.rgb, vec3(0.2126, 0.7152, 0.0722));
	vec3 desaturated = mix(base.rgb, vec3(luma) * 0.85, desat_t);

	COLOR = vec4(desaturated, base.a);
}
