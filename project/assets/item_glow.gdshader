// Sprite-localised glow that hugs the silhouette of the actual sprite
// instead of drawing a big circular blob behind it. Replaces the
// radial PNG halo for paperdoll/weapon glows so a thin sword glows
// like a thin sword and a chunky shield glows like a chunky shield.
//
// Technique: 8-direction neighbor sampling at multiple radii, take the
// max alpha, multiply by (1 - own alpha) to confine the glow to
// outside the sprite, then add. Soft via radial falloff across the
// sample radii.
//
// Cost: 16 texture samples per fragment (2 rings × 8 directions). For
// a 32×32 sprite that's ~1024 fragments × 16 = 16k samples — trivial
// on any GPU. Only attached to weapon overlays (1-2 per visible bot),
// not every dungeon tile.

shader_type canvas_item;
render_mode unshaded;

uniform vec4 glow_color : source_color = vec4(1.0, 0.8, 0.3, 0.9);
// 0..1. Glow alpha multiplier — driver tweens this for the pulse so
// we don't burn a tween on the texture sampler.
uniform float glow_strength : hint_range(0.0, 1.0) = 0.6;
// Glow ring thickness in UV. ~0.10 ≈ 3px on a 32×32 sprite, which is
// the sweet spot — thinner reads as crispy outline, thicker bleeds
// into a foggy aura. Driver picks based on rarity.
uniform float thickness : hint_range(0.0, 0.3) = 0.10;

void fragment() {
	vec4 base = texture(TEXTURE, UV);
	// Two-ring sample so the glow fades smoothly outward instead of
	// being a hard outline ring. Outer ring contributes less.
	vec2 px = TEXTURE_PIXEL_SIZE;
	float r1 = thickness * 32.0;
	float r2 = r1 * 0.5;
	float a_outer = 0.0;
	float a_inner = 0.0;
	// 8 cardinal+diagonal samples. Diagonals scaled by 1/sqrt(2) so the
	// effective radius is consistent across angles.
	const vec2 DIRS[8] = vec2[](
		vec2( 1.0,  0.0), vec2(-1.0,  0.0), vec2( 0.0,  1.0), vec2( 0.0, -1.0),
		vec2( 0.707,  0.707), vec2(-0.707, 0.707),
		vec2( 0.707, -0.707), vec2(-0.707, -0.707)
	);
	for (int i = 0; i < 8; i++) {
		vec2 d = DIRS[i];
		a_outer = max(a_outer, texture(TEXTURE, UV + d * px * r1).a);
		a_inner = max(a_inner, texture(TEXTURE, UV + d * px * r2).a);
	}
	// Soft falloff. Earlier the inner ring was clamped to full alpha
	// which produced a hard pixel-perfect outline at peak pulse. Now
	// both rings contribute at roughly 0.55 max and we square the
	// result so the brightest fragments are far less than 1.0 — the
	// glow reads as a gradient instead of a crisp ring.
	float ring = max(a_inner * 0.55, a_outer * 0.50);
	ring = ring * ring;
	float mask = ring * (1.0 - base.a);
	vec4 glow = vec4(glow_color.rgb, glow_color.a * mask * glow_strength);
	// Premultiply-style add so the glow brightens transparent areas
	// without darkening the sprite itself.
	COLOR = vec4(base.rgb * base.a + glow.rgb * glow.a, base.a + glow.a);
}
