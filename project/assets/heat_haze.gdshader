shader_type canvas_item;

// Vertex-distortion heat haze. Applied as a material on a screen-space
// Sprite2D that covers a small region (lava cell + the row of tiles
// directly above). Reads BACKBUFFER and warps the UV by a vertical
// sine wave. Effect: things rendered behind shimmer.
//
// Cheap — sin/cos per fragment, no full-screen pass.

render_mode blend_mix;

// Godot 4.6 requires screen_tex be declared as a uniform.
uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear;

// Wave amplitude in UV-space (0..1). 0.005 = subtle ripple; 0.02 = strong.
uniform float strength : hint_range(0.0, 0.05) = 0.008;

// Wave frequency.
uniform float frequency : hint_range(1.0, 30.0) = 10.0;

// Wave speed.
uniform float speed : hint_range(0.0, 10.0) = 1.5;

// Falloff with distance from the heat source (lava cell). The haze is
// strongest at the bottom of the affected region and fades upward —
// matches real heat-rising behavior.
uniform float vertical_falloff : hint_range(0.0, 4.0) = 1.5;

void fragment() {
	// Vertical fade: 1.0 at bottom, 0.0 at top. UV.y = 0 is top.
	float fade = pow(1.0 - UV.y, vertical_falloff);

	// Sine warp. Phase shifts horizontally so each column ripples slightly
	// out of sync (more organic than a single sine wave for the whole region).
	float phase = UV.x * frequency * 0.5 + TIME * speed;
	float wave = sin(UV.y * frequency + phase);
	vec2 warped_uv = SCREEN_UV + vec2(wave * strength * fade, 0.0);

	// Chromatic-ish slight offset on the warp — fakes refraction.
	vec3 col;
	col.r = textureLod(screen_tex, warped_uv + vec2(0.001 * fade, 0.0), 0.0).r;
	col.g = textureLod(screen_tex, warped_uv, 0.0).g;
	col.b = textureLod(screen_tex, warped_uv - vec2(0.001 * fade, 0.0), 0.0).b;

	COLOR = vec4(col, 1.0);
}
