shader_type canvas_item;

// Per-biome post-process. Applied as a full-screen blend over the rendered
// scene. Reads BACKBUFFER (the rendered frame so far), grades it, writes back.
// Toggleable via uniforms — defaults are no-op so a missing biome config
// renders unchanged.

render_mode blend_mix;

// Godot 4.6 requires SCREEN_TEXTURE be declared as a uniform.
uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear;

// Tint: multiplied with the base color. (1,1,1) = no tint.
uniform vec3 tint = vec3(1.0);

// Saturation: 1.0 = unchanged, 0.0 = grayscale, >1.0 = oversaturated.
uniform float saturation = 1.0;

// Contrast: 1.0 = unchanged. Higher pushes toward black/white.
uniform float contrast = 1.0;

// Brightness: additive. 0.0 = unchanged.
uniform float brightness = 0.0;

// Vignette: 0..1 strength. Darkens corners. 0 = off.
uniform float vignette = 0.0;

// Vignette tint — color the vignette. (0,0,0) = black corners.
uniform vec3 vignette_tint = vec3(0.0);

// Mix amount: 1.0 = full effect, 0.0 = no effect (passes through).
// Useful for fading the grade in/out at biome transitions.
uniform float mix_amount : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	vec3 base = texture(screen_tex, SCREEN_UV).rgb;

	// Saturation around luma (Rec. 709 weights).
	float luma = dot(base, vec3(0.2126, 0.7152, 0.0722));
	vec3 graded = mix(vec3(luma), base, saturation);

	// Contrast around mid-grey 0.5.
	graded = (graded - 0.5) * contrast + 0.5;

	// Brightness offset.
	graded += brightness;

	// Tint multiply.
	graded *= tint;

	// Vignette: dist from center → fade toward vignette_tint near edges.
	float d = length(SCREEN_UV - vec2(0.5)) * 1.4142; // 0 center, 1 corner
	float v = smoothstep(0.5, 1.0, d) * vignette;
	graded = mix(graded, vignette_tint, v);

	// Final blend with original to support partial application.
	graded = mix(base, graded, mix_amount);

	COLOR = vec4(graded, 1.0);
}
