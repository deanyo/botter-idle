shader_type canvas_item;

// Heat haze. Applied per T_LAVA cell as a Sprite2D covering cell + 2
// rows above. Renders a subtle red-orange shimmer as additive overlay,
// pulsing with TIME and fading with vertical position.
//
// IMPORTANT: previous version sampled SCREEN_TEXTURE with a per-fragment
// UV warp. That caused the warp pattern to appear anchored to the screen
// rather than to the world (because the warp was computed in sprite-
// local UV but applied to camera-local SCREEN_UV). When the camera
// panned, the splotches drifted across the world.
//
// Fix: drop SCREEN_TEXTURE entirely. Instead emit a small additive tint
// that pulses with time. Looks like rising heat without distorting
// what's behind. Cheaper too (no texture sample).

render_mode blend_add;

uniform vec3 heat_color : source_color = vec3(1.0, 0.45, 0.1);
uniform float intensity : hint_range(0.0, 1.0) = 0.35;
uniform float frequency : hint_range(1.0, 30.0) = 6.0;
uniform float speed : hint_range(0.0, 10.0) = 2.5;
uniform float vertical_falloff : hint_range(0.0, 4.0) = 1.6;

void fragment() {
	// Strongest at bottom (lava cell), fades up the heat plume.
	float fade = pow(1.0 - UV.y, vertical_falloff);

	// Two superimposed waves at different frequencies create the sense
	// of multiple heat rivulets rather than a single ripple.
	float w1 = sin(UV.y * frequency + TIME * speed + UV.x * 4.0);
	float w2 = sin(UV.y * frequency * 1.7 + TIME * speed * 1.3 + UV.x * 9.0);
	float pulse = (w1 * 0.5 + w2 * 0.3 + 0.6); // 0..1.4 ish
	pulse = clamp(pulse, 0.0, 1.0);

	// Final additive tint — small enough to not blow out the underlying
	// pixels, big enough to read as "this is hot".
	float strength = intensity * fade * pulse;
	COLOR = vec4(heat_color * strength, strength);
}
