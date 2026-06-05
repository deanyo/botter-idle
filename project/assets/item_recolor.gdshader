// Per-instance item recoloring shader. Applies hue rotation,
// saturation modulation, optional inversion, animated shimmer, and
// colorize (forces a hue onto low-saturation sprites). Driven by
// uniforms set per-sprite from inst.tint.
//
// Cheap: per-fragment math is a 3x3 hue-rotation matrix. No texture
// samples beyond the base. ~12 instructions per fragment.
//
// Modes (set via `mode` uniform):
//   0 = normal           — apply hue/sat only (works on saturated art)
//   1 = shimmer          — adds animated brightness wave along U axis
//   2 = inverted         — inverts RGB after hue/sat
//   3 = prismatic        — hue rotates over time (psychedelic legendary)
//   4 = colorize         — forces hue onto low-sat sprites (white/grey),
//                          preserving brightness. The right pick for
//                          white plate, silver dragon scales, etc.
//                          where pure hue rotation does nothing.
//
// 2026-06-05: added mode 4. The hue-only path can't tint white because
// HSV white has saturation=0 and rotating undefined hue is a no-op.
// Colorize sidesteps that by computing target_rgb at the requested
// hue + full saturation, then mixing the original luma toward it.

shader_type canvas_item;
render_mode unshaded;

uniform float hue : hint_range(0.0, 360.0) = 0.0;     // degrees
uniform float saturation : hint_range(0.0, 2.0) = 1.0;
uniform int   mode : hint_range(0, 4) = 0;
uniform float shimmer_speed : hint_range(0.0, 8.0) = 2.0;
uniform float prismatic_speed : hint_range(0.0, 360.0) = 60.0;  // degrees/sec
// Colorize strength — 0.0 keeps the sprite as-is, 1.0 fully replaces
// the chroma at the requested hue. Defaults at 0.7 — leaves enough
// luma variation to keep highlights/shadows readable.
uniform float colorize_strength : hint_range(0.0, 1.0) = 0.7;

vec3 rgb_to_hsv(vec3 c) {
	float cmax = max(max(c.r, c.g), c.b);
	float cmin = min(min(c.r, c.g), c.b);
	float d = cmax - cmin;
	float h = 0.0;
	if (d > 0.0) {
		if (cmax == c.r) h = mod((c.g - c.b) / d, 6.0);
		else if (cmax == c.g) h = (c.b - c.r) / d + 2.0;
		else h = (c.r - c.g) / d + 4.0;
		h *= 60.0;
		if (h < 0.0) h += 360.0;
	}
	float s = (cmax > 0.0) ? d / cmax : 0.0;
	return vec3(h, s, cmax);
}
vec3 hsv_to_rgb(vec3 c) {
	float h = c.x;
	float s = c.y;
	float v = c.z;
	float chroma = v * s;
	float hp = h / 60.0;
	float x = chroma * (1.0 - abs(mod(hp, 2.0) - 1.0));
	vec3 rgb;
	if      (hp < 1.0) rgb = vec3(chroma, x, 0.0);
	else if (hp < 2.0) rgb = vec3(x, chroma, 0.0);
	else if (hp < 3.0) rgb = vec3(0.0, chroma, x);
	else if (hp < 4.0) rgb = vec3(0.0, x, chroma);
	else if (hp < 5.0) rgb = vec3(x, 0.0, chroma);
	else               rgb = vec3(chroma, 0.0, x);
	float m = v - chroma;
	return rgb + vec3(m);
}

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	if (c.a <= 0.001) {
		COLOR = c;
	} else {
		vec3 hsv = rgb_to_hsv(c.rgb);
		// Apply hue rotation + saturation modulation.
		float h_offset = hue;
		if (mode == 3) {
			// Prismatic: hue cycles continuously.
			h_offset += TIME * prismatic_speed;
		}
		hsv.x = mod(hsv.x + h_offset, 360.0);
		hsv.y = clamp(hsv.y * saturation, 0.0, 1.0);
		vec3 rgb = hsv_to_rgb(hsv);
		// Shimmer: animated brightness wave traveling across the
		// sprite. Reads as a thin highlight sweep.
		if (mode == 1) {
			float wave = 0.5 + 0.5 * sin((UV.x - TIME * 0.5) * 6.0 * shimmer_speed);
			rgb = mix(rgb, rgb * 1.6, wave * 0.4);
		}
		// Inverted: invert RGB after the hue/sat work so the
		// inversion is interpretable (preserved silhouette, swapped
		// colors).
		if (mode == 2) {
			rgb = vec3(1.0) - rgb;
		}
		// Colorize: force the requested hue onto a low-sat sprite so
		// white plate / silver scales / grey rings still take a tint.
		// Build a target RGB from (hue, full_sat, original_luma) and
		// mix the original toward it by colorize_strength. Original
		// luma is the value channel of HSV — preserves highlights and
		// shadows so the silhouette doesn't flatten.
		if (mode == 4) {
			vec3 target = hsv_to_rgb(vec3(hue, 1.0, hsv.z));
			// Mix amount tapers with original sat — already-saturated
			// pixels get a softer tint so vivid art doesn't get pasted
			// over. White (sat=0) gets full strength.
			float mix_amt = colorize_strength * (1.0 - hsv.y * 0.5);
			rgb = mix(rgb, target, mix_amt);
		}
		COLOR = vec4(rgb, c.a);
	}
}
