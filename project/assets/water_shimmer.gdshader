shader_type canvas_item;

// Water shimmer. Slow horizontal UV offset on the water cell sprite —
// makes water look like it's flowing without any actual particle system.
// Applied as a material on a Sprite2D covering each T_WATER cell (just
// the cell, no row-above behavior — water doesn't rise like heat).
//
// Cheaper than heat haze (no chromatic offset, single sample). Compatible
// with Godot 4.6's hint_screen_texture pattern.

render_mode blend_mix;

uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear;

// Horizontal flow speed (UV per second).
uniform float flow_speed : hint_range(0.0, 0.2) = 0.04;

// Wave amplitude in UV-space.
uniform float strength : hint_range(0.0, 0.05) = 0.005;

// Sine frequency along Y axis (creates the rippling rows).
uniform float frequency : hint_range(1.0, 30.0) = 6.0;

// Time-varying phase rate (wobble per second).
uniform float wobble_speed : hint_range(0.0, 5.0) = 0.8;

// Subtle blue tint added to the sample (fakes water absorption of red).
uniform vec3 water_tint : source_color = vec3(0.92, 0.97, 1.0);

void fragment() {
	// Horizontal flow + per-row sine wobble.
	float wobble = sin(UV.y * frequency + TIME * wobble_speed);
	vec2 warped_uv = SCREEN_UV + vec2(
		TIME * flow_speed * 0.05 + wobble * strength,
		wobble * strength * 0.3
	);
	vec3 col = texture(screen_tex, warped_uv).rgb * water_tint;
	COLOR = vec4(col, 1.0);
}
