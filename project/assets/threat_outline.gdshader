// Threat-tier outline. Adds a tinted pulsing outline around an enemy
// sprite by sampling neighboring pixels. Tier picks the color:
//   0 = trivial: no outline
//   1 = even:    faint white pulse
//   2 = dangerous: orange pulse
//   3 = lethal/boss: red pulse, bright
//
// Cost: 4-sample neighbor read for the outline mask. Cheap.

shader_type canvas_item;

// 0..3, picks outline color.
uniform int tier = 0;

// Pack-tier override. When alpha > 0, this color replaces the threat
// table — used to give magic/rare/boss/miniboss enemies a stable
// visual identity regardless of their bot-relative threat. The
// threat tier still drives outline thickness via _strength so a
// rare-but-trivial mob outlines faintly while a rare-and-deadly
// mob outlines brightly.
uniform vec4 pack_color = vec4(0.0, 0.0, 0.0, 0.0);

// Pulse rate (Hz).
uniform float pulse_speed = 2.0;

// Outline thickness in UV. ~0.05 ≈ 1.6px on a 32×32 sprite (eyeballed
// to feel right with NEAREST filtering).
uniform float thickness : hint_range(0.0, 0.2) = 0.06;

// Color table indexed by tier.
const vec4 TIER_COLOR[4] = vec4[](
	vec4(0.0, 0.0, 0.0, 0.0),       // 0: no outline
	vec4(0.95, 0.95, 1.0, 0.45),    // 1: faint white
	vec4(1.0, 0.65, 0.25, 0.65),    // 2: orange
	vec4(1.0, 0.20, 0.18, 0.85)     // 3: red
);

void fragment() {
	vec4 base = texture(TEXTURE, UV);

	bool has_pack = pack_color.a > 0.001;
	// Pack tier always outlines; threat tier 0 only draws if no pack.
	if (tier <= 0 && !has_pack) {
		COLOR = base;
	} else {
		// 4-direction neighbor sample. If the base sprite is transparent
		// here but any neighbor is opaque, this fragment is on the outline.
		vec2 px = TEXTURE_PIXEL_SIZE * thickness * 32.0;
		float n = texture(TEXTURE, UV + vec2(0.0, -px.y)).a;
		float s = texture(TEXTURE, UV + vec2(0.0,  px.y)).a;
		float e = texture(TEXTURE, UV + vec2( px.x, 0.0)).a;
		float w = texture(TEXTURE, UV + vec2(-px.x, 0.0)).a;
		float neighbor_alpha = max(max(n, s), max(e, w));
		float outline_mask = (1.0 - base.a) * neighbor_alpha;

		// Pulse intensity 0..1.
		float pulse = 0.5 + 0.5 * sin(TIME * pulse_speed * 6.2831);

		// Pick color: pack override if present, else threat table.
		vec4 outline_col;
		if (has_pack) {
			outline_col = pack_color;
		} else {
			int t = clamp(tier, 0, 3);
			outline_col = TIER_COLOR[t];
		}
		outline_col.a *= mix(0.6, 1.0, pulse);

		// Mix outline into base. Where base is opaque, base wins (no
		// recoloring of the sprite itself). Where outline_mask is 1
		// and base is transparent, outline shows through.
		vec4 final_col = base + outline_col * outline_mask * (1.0 - base.a);
		COLOR = final_col;
	}
}
