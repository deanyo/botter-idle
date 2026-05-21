# Botter — Visual Effects Plan

The bot plays itself, so visual polish carries disproportionate weight —
players spend most of their time *watching*, not inputting. The render
stack already ships custom fog ray-march, WorldEnvironment bloom,
per-light flicker (FastNoiseLite), ember particles, sprite FX. The
biggest gap isn't a missing effect; it's that **biomes don't feel
distinct enough beyond their tilesets**. Crypt and lair render with the
same overall mood.

This doc captures the prioritized roadmap of post-process and per-tile
shaders to elevate that distinctiveness. Effort and impact are
estimated, not measured.

## Shipped 2026-05-21

### ✅ Per-biome color grading (`color_grade.gdshader`)

Full-screen post-process shader on a CanvasLayer (layer 60, between
fog and HUD). 6 uniforms: tint (vec3), saturation, contrast,
brightness, vignette + vignette_tint, mix_amount.

Reads `current_biome.color_grade` dict; missing keys default to
identity. `transition_to(grade, 0.4)` cross-fades on biome change via
mix-amount tween.

8 of 24 biomes curated:
- **dungeon** — Cool stone-vault, slight desaturation
- **lair** — Warm lush green, oversaturated
- **swamp** — Murky desaturated olive
- **crypt** — Cold washed-out blue-grey, heavy vignette
- **tomb** — Sandy sun-bleached
- **forge** — Hot saturated red-orange
- **glacier** — Cold blue-cyan, frosted
- **slime** — Sickly green murky

Gated by `BOTTER_NO_GRADE=1`. Sub-microsecond cost.

## Queued — high impact, low effort

### Heat haze on T_LAVA tiles

Vertex-distortion shader applied per-cell to lava tiles AND the row of
floor/wall tiles directly above. Vertical sine-wave UV warp creates the
shimmer that makes lava feel hot. Currently lava is just a static red
sprite — players don't intuit "this damages me."

Approach:
- New `assets/heat_haze.gdshader`, applied as material override on
  T_LAVA cells and their row-above neighbors during render.
- Uniforms: `time` (animated), `strength` (0.5 default), `frequency`
  (3.0 default).
- Cost: per-affected-cell vertex distortion, no full-screen pass.
  Negligible.

~30 lines of shader + ~15 lines of GDScript wiring in `map_renderer.gd`.

### Water shimmer on T_WATER

Same shape as heat haze, slower frequency, horizontal UV offset
instead of vertical warp. Makes water look like it's flowing.

Approach mirrors heat haze. Most code reusable.

### Per-biome color grading — extend remaining 16 biomes

Once the 8-biome A/B screenshots come back from `color_grade_showcase`
(queued after the experiment chain), extend the curated values to:

dungeon_dark, mines, forest, snake, shoals, orc, spider, hive,
labyrinth, abyss, pandemonium, zot, elf, temple, depths.

~30 min once visual direction is locked.

## Queued — medium impact, medium effort

### Light cookies on PointLight2D

Pattern textures projected through lights. Adds character without
changing how lighting works.

Examples:
- Stained glass in elf/temple — soft fragmented colors on floor
- Prison bars in tomb — vertical stripes at low intensity
- Webs in spider — radial pattern fading outward

Approach:
- Add optional `texture` field to `light_spec` definitions.
- `LightSpec.attach()` reads it, sets `point_light_2d.texture` if
  present.
- Author 4-6 cookie textures (seamlessly tileable, monochrome alpha).

~5 lines of code + asset authoring time.

### Threat-tier outline on enemies

Pulsing aura scaled to enemy power-vs-bot. Functional info layered as
visual feedback:
- Trivial (bot atk × 5 > enemy hp): dim/no aura
- Even match: faint white pulse
- Dangerous (enemy hp > bot atk × 5): red pulse, growing intensity
- Boss/miniboss: always red pulse

Hooks into existing `light_spec` system as a synthetic light tier.

### Memory desaturation

Tiles previously seen but currently in fog memory render with reduced
saturation. The fog system already tracks per-cell visibility state;
data is there.

Approach: extend `tile_visibility.gdshader` with a `memory_saturation`
mix branch — fog state 1 (memory) blends toward grayscale, state 2
(visible) stays full color, state 0 (unseen) stays opaque.

Adds visual weight to exploration history without changing readability.

## Queued — toggleable graphics options

### Scanlines / CRT shader

Polarizing — some players love retro authenticity, others find it
eye-strain. Default off. Wire as a video option in
`scenes/video_options.tscn`.

### Palette quantization

Force render output through fixed N-color palette (PICO-8 32-color,
custom Botter palette). Strong unified look but kills DCSS sprite
color variety. Highly subjective; ship as opt-in only.

### Dithered fog transitions (bayer)

4×4 bayer threshold replacing the smooth alpha gradient. More
"authentically retro" but mismatches the current clean look. Subjective.

## Out of scope (decided no, for now)

- **Full-screen pixelation pass.** Source art is already pixel-perfect;
  doubling up is muddy.
- **Tilemap displacement on the bot's footstep.** Cute but doesn't
  serve the idle-watching fantasy.
- **Particle weather** (rain, snow, embers across the screen). Already
  have GPUParticles2D embers per-light; full-screen weather competes
  with the fog overlay.

## Decision log

- **Color grading layer = 60.** Above ambient_modulate (0) and fog (40
  in current setup), below HUD (100). So the grade applies to fully-lit
  fully-fogged scene, not raw tile output. Confirmed correct after
  smoke testing — vignette correctly darkens corners after fog applies.
- **Mix-amount cross-fade on biome change.** Simpler than tweening
  every uniform separately. The shader does `mix(base, graded,
  mix_amount)` so 0 = pass-through, 1 = full grade. Tween 0→target
  over 0.4s = smooth biome transition without code complexity.
- **`BOTTER_NO_GRADE=1` for opt-out.** Matches existing
  `BOTTER_NO_GLOW`/`BOTTER_NO_FOG`/etc pattern for perf A/B testing on
  lower-tier hardware.

## Verification workflow

When changing visuals:
1. Edit shader / config
2. `python3 -m http.server 8080` from repo root, open
   `tools/biome_editor.html` for tile-level review (existing tool)
3. For shader review across multiple biomes: run
   `tools/capture_color_grade_showcase.sh` (or extend it). Captures
   the same biome floor with/without the effect. Side-by-side
   comparison without waiting for procgen rolls.
4. For "does it feel right in motion": `/showcase` skill drops a
   curated audit floor with one station per visual feature; bot
   patrols a fixed loop so the camera reveals each station in turn.
