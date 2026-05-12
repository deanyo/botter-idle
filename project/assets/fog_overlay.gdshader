shader_type canvas_item;
render_mode unshaded, blend_mix;

const int MAX_LIGHTS = 24;

uniform vec2 light_positions[MAX_LIGHTS];
uniform float light_radii[MAX_LIGHTS];
uniform float light_intensities[MAX_LIGHTS];
uniform vec4 light_colors[MAX_LIGHTS];
uniform int active_light_count = 0;
uniform float base_darkness : hint_range(0.0, 1.0) = 0.97;
uniform vec2 viewport_size = vec2(540.0, 960.0);
uniform vec2 camera_world = vec2(0.0, 0.0);
uniform float camera_zoom = 1.5;
uniform float ambient_warm : hint_range(0.0, 0.3) = 0.0;
uniform float time_seconds = 0.0;

// Per-cell visibility: r channel == 1.0 visible, 0.5 explored, 0.0 unseen.
uniform sampler2D visibility_tex : filter_linear;
uniform vec2 grid_size = vec2(60.0, 60.0);
uniform float tile_size_px = 32.0;
uniform float visibility_in_use = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float sample_visibility(vec2 world_pos) {
	if (visibility_in_use < 0.5) return 1.0;
	vec2 cell_uv = (world_pos / tile_size_px) / grid_size;
	if (cell_uv.x < 0.0 || cell_uv.x > 1.0 || cell_uv.y < 0.0 || cell_uv.y > 1.0) return 0.0;
	return texture(visibility_tex, cell_uv).r;
}

void fragment() {
	vec2 screen_px = SCREEN_UV * viewport_size;
	vec2 world_px = camera_world + (screen_px - viewport_size * 0.5) / camera_zoom;
	float vis = sample_visibility(world_px);
	float lit = 0.0;
	vec3 tint_accum = vec3(0.0);
	float tint_weight = 0.0;
	for (int i = 0; i < MAX_LIGHTS; i++) {
		if (i >= active_light_count) break;
		float d = distance(world_px, light_positions[i]);
		float r = light_radii[i];
		if (d < r) {
			float t = pow(1.0 - smoothstep(r * 0.25, r, d), 1.6);
			float contribution = t * light_intensities[i];
			lit += contribution;
			tint_accum += light_colors[i].rgb * contribution;
			tint_weight += contribution;
		}
	}
	lit = clamp(lit, 0.0, 1.0);
	// Active-aura visibility only. Anything not currently visible (including
	// previously explored cells) renders fully black — no greyed-out map
	// memory. The bilinear gradient at the visibility-texture edge plus a
	// smoothstep gives the soft falloff at the LoS rim.
	float w_visible = smoothstep(0.55, 0.95, vis);
	lit *= w_visible;

	float visibility_alpha;
	if (visibility_in_use > 0.5) {
		float lit_alpha = base_darkness * (1.0 - lit);
		visibility_alpha = mix(1.0, lit_alpha, w_visible);
	} else {
		visibility_alpha = base_darkness * (1.0 - lit);
	}

	vec3 dark_color = vec3(0.0);
	if (tint_weight > 0.001 && w_visible > 0.001) {
		vec3 tint = tint_accum / tint_weight;
		dark_color = tint * 0.04 * (1.0 - visibility_alpha) * w_visible;
	}
	float n = hash(floor(screen_px / 2.0)) * 0.025;
	float final_alpha = clamp(visibility_alpha + n * visibility_alpha, 0.0, 1.0);
	COLOR = vec4(dark_color, final_alpha);
}
