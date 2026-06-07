shader_type canvas_item;

// Desaturate the texture by a configurable amount. Used by
// item_cell.gd::render to grey out species-blocked items so the
// player can still tell what the item is at a glance, without the
// loud "🚫 over a sprite at 0.45 alpha" treatment.
//
// 0.0 = full color (passthrough).
// 1.0 = full greyscale.
//
// dim_alpha additionally scales the output alpha so blocked cells
// read fainter than equipped items.

uniform float saturation : hint_range(0.0, 1.0) = 0.0;
uniform float dim_alpha   : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	vec4 src = texture(TEXTURE, UV);
	float luma = dot(src.rgb, vec3(0.299, 0.587, 0.114));
	vec3 grey = vec3(luma);
	COLOR.rgb = mix(grey, src.rgb, saturation);
	COLOR.a = src.a * dim_alpha;
}
