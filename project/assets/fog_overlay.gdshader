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

// Wall mask: r channel == 1.0 wall, 0.0 walkable. Ray-marched per fragment
// to test LoS from the fragment's world-pos to the bot's world-pos. This
// replaces the old per-cell visibility texture which produced tile-aligned
// "ticks" as the bot moved cell-to-cell, and Bresenham stripe artifacts in
// corridors. filter_linear softens wall edges so the LoS occlusion line
// is anti-aliased rather than stair-stepping at cell boundaries.
uniform sampler2D wall_mask_tex : filter_linear;
uniform vec2 grid_size = vec2(80.0, 80.0);
uniform float tile_size_px = 32.0;
uniform float visibility_in_use = 0.0;
uniform vec2 bot_world = vec2(0.0, 0.0);
uniform float bot_radius_px = 256.0;
// March step count — tradeoff between LoS sharpness and per-pixel cost.
// 24 steps × ~10px each at the bot's full radius keeps walls airtight
// while giving us enough samples to soft-occlude rather than hard-cut.
const int MARCH_STEPS = 24;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// Sample wall mask at a world-pixel position. 1.0 = wall, 0.0 = walkable.
// Out-of-bounds is treated as wall so rays into the void instantly occlude
// — this prevents lights from leaking onto fragments outside the map and
// producing ghostly grey blobs at the edges where there's no tile to
// render against.
float wall_at(vec2 world_pos) {
	vec2 cell_uv = (world_pos / tile_size_px) / grid_size;
	if (cell_uv.x < 0.0 || cell_uv.x > 1.0 || cell_uv.y < 0.0 || cell_uv.y > 1.0) return 1.0;
	return texture(wall_mask_tex, cell_uv).r;
}

// March from `from` to `to`. Accumulates wall density along the path and
// returns a soft 0..1 occlusion (1 = fully clear LoS, 0 = fully blocked).
// Soft accumulation gives the fog rim a gradient at occlusion boundaries
// instead of a hard cut, so diagonal walls feather smoothly instead of
// stair-stepping. Each sample contributes a little blockage, and once
// total blockage exceeds 1, we treat the ray as fully blocked. The first
// and last steps skip the wall test so the bot can stand "on" the wall
// edge of its own cell and lights anchored at wall cells (sconces) still
// light the floor in front of them.
float los_clear(vec2 from, vec2 to) {
	vec2 dir = to - from;
	float dist = length(dir);
	if (dist < 1.0) return 1.0;
	dir /= dist;
	float step_px = dist / float(MARCH_STEPS);
	float t = tile_size_px * 0.5;
	float blockage = 0.0;
	// Each opaque sample contributes step-distance worth of blockage,
	// normalized to one tile. So a single full-wall sample of one tile
	// width fully blocks; a half-occluded sample (filter_linear at a
	// wall edge) only contributes half. This is the soft-occlusion shape.
	float per_step = step_px / tile_size_px;
	for (int i = 1; i < MARCH_STEPS; i++) {
		float s = t + float(i) * step_px;
		if (s >= dist - tile_size_px * 0.5) break;
		vec2 pos = from + dir * s;
		blockage += wall_at(pos) * per_step;
		if (blockage >= 1.0) return 0.0;
	}
	return clamp(1.0 - blockage, 0.0, 1.0);
}

void fragment() {
	vec2 screen_px = SCREEN_UV * viewport_size;
	vec2 world_px = camera_world + (screen_px - viewport_size * 0.5) / camera_zoom;
	// Out-of-bounds detection. The shader can't early-return (Godot
	// disallows it from fragment()), so we compute the OOB flag once and
	// fold it through the rest of the math: OOB fragments end up with
	// zero visibility/lit and full opaque-black darkness.
	vec2 oob_uv = (world_px / tile_size_px) / grid_size;
	float oob_factor = 0.0;
	if (visibility_in_use > 0.5) {
		oob_factor = (oob_uv.x < -0.01 || oob_uv.x > 1.01 || oob_uv.y < -0.01 || oob_uv.y > 1.01) ? 1.0 : 0.0;
	}
	// Bot vision: the LoS test (ray-march to bot, in radius) gates whether
	// the fragment is "visible" at all — this used to be the per-cell
	// visibility texture. `visibility` is a smooth 0..1 mask scaling the
	// fog alpha; `bot_lit` separately drives the radial brightness inside
	// that mask so the centre of the bot's view is well-lit and the rim
	// fades out softly. Falloff spans ~3 tiles at the rim so the lit→dark
	// transition is a feathered gradient, not a hard line.
	float visibility = 0.0;
	float bot_lit = 0.0;
	if (visibility_in_use > 0.5 && bot_radius_px > 1.0) {
		float d_bot = distance(world_px, bot_world);
		if (d_bot < bot_radius_px) {
			float clear = los_clear(world_px, bot_world);
			visibility = (1.0 - smoothstep(bot_radius_px * 0.60, bot_radius_px, d_bot)) * clear;
			bot_lit = (1.0 - smoothstep(bot_radius_px * 0.30, bot_radius_px * 0.95, d_bot)) * clear;
		}
	}
	// External lights (torches, sconces, fire dragons) — same ray-march
	// keeps them from leaking through walls. Each light extends both the
	// visibility mask AND the brightness level.
	float lit = bot_lit;
	vec3 tint_accum = vec3(0.0);
	float tint_weight = 0.0;
	for (int i = 0; i < MAX_LIGHTS; i++) {
		if (i >= active_light_count) break;
		float d = distance(world_px, light_positions[i]);
		float r = light_radii[i];
		if (d < r) {
			float clear = los_clear(world_px, light_positions[i]);
			float t = pow(1.0 - smoothstep(r * 0.25, r, d), 1.6);
			float contribution = t * light_intensities[i] * clear;
			lit += contribution;
			tint_accum += light_colors[i].rgb * contribution;
			tint_weight += contribution;
			// Light also reveals the area to the player (visibility mask).
			// Wide fade at the rim matches the bot's feather so light/dark
			// boundaries blend instead of cutting hard.
			float light_vis = (1.0 - smoothstep(r * 0.55, r, d)) * clear;
			visibility = max(visibility, light_vis);
		}
	}
	// OOB fragments collapse all lighting/visibility — anything outside
	// the map renders as opaque black so light halos don't bleed onto
	// the void. Done with multiplication rather than early-return because
	// Godot disallows return from fragment().
	lit *= (1.0 - oob_factor);
	visibility *= (1.0 - oob_factor);
	tint_weight *= (1.0 - oob_factor);
	lit = clamp(lit, 0.0, 1.0);
	float w_visible = visibility;
	float visibility_alpha = mix(1.0, base_darkness * (1.0 - lit), w_visible);
	vec3 dark_color = vec3(0.0);
	if (tint_weight > 0.001 && w_visible > 0.001) {
		vec3 tint = tint_accum / tint_weight;
		dark_color = tint * 0.04 * (1.0 - visibility_alpha) * w_visible;
	}
	float n = hash(floor(screen_px / 2.0)) * 0.025;
	float final_alpha = clamp(visibility_alpha + n * visibility_alpha, 0.0, 1.0);
	// Force OOB fragments to fully opaque black regardless of computed alpha.
	final_alpha = mix(final_alpha, 1.0, oob_factor);
	COLOR = vec4(dark_color, final_alpha);
}
