shader_type canvas_item;

// Water shimmer. Applied per T_WATER cell. Adds a subtle blue-white
// caustic-pattern overlay that ripples with time. Doesn't distort
// underlying tiles (which would require world-anchored screen sampling
// — see the comment in heat_haze.gdshader for why that approach
// produced screen-anchored "splotch drift").

render_mode blend_add;

uniform vec3 caustic_color : source_color = vec3(0.5, 0.8, 1.0);
uniform float intensity : hint_range(0.0, 0.6) = 0.18;
uniform float frequency : hint_range(1.0, 30.0) = 7.0;
uniform float speed : hint_range(0.0, 5.0) = 1.0;

void fragment() {
	// Two slow sine waves at different angles produce a faint caustic
	// pattern. Animated by TIME so it ripples in place — the cell stays
	// world-anchored so the shimmer reads as flowing water, not as
	// screen-anchored splotches.
	float w1 = sin(UV.x * frequency + TIME * speed + UV.y * 2.0);
	float w2 = cos(UV.y * frequency * 0.8 + TIME * speed * 0.7 + UV.x * 3.0);
	float caustic = (w1 + w2) * 0.5; // -1..1
	float bright = clamp(caustic * 0.5 + 0.4, 0.0, 1.0);

	float strength = intensity * bright;
	COLOR = vec4(caustic_color * strength, strength);
}
