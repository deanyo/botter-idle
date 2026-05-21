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

## Settings + UI architecture (shipped 2026-05-21)

All effects are toggleable from the in-game Video Options menu:

- `VideoSettings.gfx` sub-dict persists per-effect bools to
  `user://video_settings.json`.
- `VideoSettings.is_effect_enabled(effect)` reads env override
  (`BOTTER_NO_<EFFECT>` / `BOTTER_FORCE_<EFFECT>`) → settings.
  Subsystems gate their effect attachment on this.
- `video_options.gd::_populate_graphics()` programmatically appends
  one CheckBox per effect to the existing options form. Toggles
  save+apply on change.
- Quality presets (`GFX_PRESET_HIGH/MEDIUM/LOW`) defined in
  `video_settings.gd` but no quick-set UI buttons yet (TODO).

## Queued — high impact, low effort

### ✅ Heat haze on T_LAVA tiles (shipped 2026-05-21)

Sine-wave UV warp on a Sprite2D covering each lava cell + 2 rows above.
Vertical falloff so the shimmer is strongest at the lava and fades upward.
Slight chromatic offset fakes refraction.

Pipeline:
- `assets/heat_haze.gdshader` — `hint_screen_texture` uniform (Godot 4.6
  required), strength/frequency/speed/vertical_falloff uniforms.
- `map_renderer.gd::_attach_heat_haze(lava_cells)` — gathers T_LAVA
  positions during the base-layer pass, creates one Sprite2D per cell
  on `_heat_haze_layer` (z_index 50). 1×1 white texture scaled to
  cover cell + 2 rows above.
- Gated by `BOTTER_NO_HEAT_HAZE=1`. Skipped entirely when no lava
  cells exist.

Cost: per-fragment sin/cos + 3 SCREEN_TEXTURE samples (chromatic), only
within the small affected zones. Total cost scales with lava cell count
(typically 5-30 cells in forge/lava-vaults).

**Note**: Initial implementation used `SCREEN_TEXTURE` builtin which Godot
4.6 deprecated — must declare as a `hint_screen_texture` uniform. Same
fix applied to `color_grade.gdshader` (was also using deprecated builtin
but hadn't been exercised yet).

### ✅ Water shimmer on T_WATER (shipped 2026-05-21)

Per-cell horizontal flow + per-row sine wobble shader. Subtle blue
tint multiplies the sample to fake water light absorption. Single
sample per fragment (no chromatic offset like heat haze). Cheaper
than heat haze.

### ✅ Per-biome color grading — all 24 biomes (shipped 2026-05-21)

All 24 biomes have curated `color_grade` entries. The remaining 16
were authored from the original 8 as a base — see commit history
for the per-biome values.

## Queued — medium impact, medium effort

### ✅ Light cookies on PointLight2D (shipped 2026-05-21)

Optional `cookie` field on `light_spec.SPECS` entries. When present
+ enabled, replaces the default radial PointLight2D texture with
a pattern. Four starter cookies authored programmatically:
- `cookie_stained_glass.png` — 4-color quadrant pattern
- `cookie_prison_bars.png` — vertical bar mask
- `cookie_web.png` — radial spokes + concentric rings
- `cookie_stardust.png` — random sparkle points

Wired specs: `sigil` → stained glass, `firefly` → stardust. Hand-
authored cookies for biomes (elf arches, tomb bars, spider webs)
remain TODO — see TODO.md.

### ✅ Threat-tier outline on enemies (shipped 2026-05-21)

4-direction neighbor-sample shader on enemy sprites.
`Enemy.apply_threat_aura(tier)` swaps in a ShaderMaterial and pushes
the tier uniform. Tier color table:
- 0 = trivial (no outline drawn — early-out in shader)
- 1 = even match (faint white pulse)
- 2 = dangerous (orange pulse)
- 3 = lethal/boss (red pulse, brightest)

`dungeon._apply_threat_auras()` walks all spawned enemies after
`_spawn_enemies()`, classifying by:
- `e.is_boss` → always 3
- `e.is_miniboss` → always 2
- otherwise: hits-to-kill (`e.max_hp / max(1, bot.atk - e.defense)`)
  + enemy-damage-as-fraction-of-bot-HP (`e.atk / bot.max_hp`)

Pulses at 2 Hz, modulated by per-tier color alpha.

### ✅ Memory desaturation (shipped 2026-05-21)

`tile_visibility.gdshader` extended to read `FogSystem.vis_texture`
(R8, encoding 0/0.5/1.0 = unseen/memory/visible). Memory cells
desaturate toward 85% gray luma at strength 0.6. Saturation shifts
are perceptually subtler than the alpha shifts that caused the
abandoned per-cell "ticking" artifact, so the same per-cell texture
that was problematic for opacity works fine for saturation.

`memory_strength` uniform is set by `map_renderer.gd::_build_tileset_and_layers`
from `VideoSettings.is_effect_enabled("memory_desat")`.

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
