# Botter — Handover

Point-in-time snapshot of what's actually shipping. Updated as we go. The
durable rules and process live in `CLAUDE.md`; the roadmap and open work
items live in `TODO.md`.

Last refresh: 2026-05-14 (perf pass 2 — native Retina, fps min 19 → 119 on forge).

## Perf pass 2 — 2026-05-14 (native Retina + 1×)

User reported 10-23 fps on most maps and 10 fps in lava/forge vaults
despite the previous pass logging 19 → 112 fps. Root cause: the previous
pass measured at 1600×900 windowed, which is ~5× fewer pixels than M3 Pro
native Retina. CPU side was fine; everything was GPU- and floor-build-
hitch-bound at native res. Six surgical wins:

1. **PointLight2D node count was the GPU killer.** Forge spawns ~50
   ambient-decor lights per floor; each is a separate full-coverage screen
   pass on Godot's GL Compatibility renderer, dropping fps from 120 to
   19 at native res. Added `LightSpec.TIER_DECOR` — for decor lights,
   skip the PointLight2D node entirely. The fog-overlay shader's
   24-source `light_intensities[]` uniform handles the broad warmth, and
   a per-decor additive glow Sprite2D + GPUParticles2D embers handle the
   "this is a flame" visual.
2. **Decor flicker animation moved CPU-side.** When PointLight2D went
   away, FlickerDriver lost its lights to animate. Per-decor `_process`
   now runs the same noise math (FastNoiseLite, scoped at 35% spec
   amplitude), driving glow alpha + scale + sub-pixel jitter. Visually
   equivalent to actor-tier flicker, zero GPU cost.
3. **FlickerDriver tree-signal churn.** Was subscribed to global
   `tree.node_added`/`node_removed`; every blood splat / hit flash /
   tween-spawned sprite forced a full tree walk to refresh the cache.
   Replaced with a 0.25s coarse refresh tick. **CPU avg 515µs → 254µs.**
4. **HUD inventory pool.** `update_inventory` was queue_freeing every
   `TextureRect` and re-creating; now grows a pool once and toggles
   visibility + texture. No more per-build node churn.
5. **Forward+ renderer.** Flipped `rendering_method` from
   `gl_compatibility` to `forward_plus`. Boots cleanly on Apple Metal.
   **fps min 58 → 100** (much smoother frametimes); CPU per-system tags
   ~doubled but well within budget. Caveat: requires Vulkan, will fall
   back to gl_compatibility on hardware without it (mobile profile keeps
   compat anyway).
6. **Orphan-connect O(N×W×H) → O(W×H).** `_connect_orphans_to_main` was
   doing per-orphan-cell expanding-spiral nearest-cell searches. p95
   1290ms, max 2016ms — that's the 2-second hitch users actually saw.
   Rewrote as a single multi-source BFS from main_region walking through
   walls + parent backtrace. **p95 18ms, max 26ms (-98.7%).**
   `[gen-phases]` log line stays in for future regressions.

### Final M3 Pro numbers (1× windowed, native Retina, forge)

| Metric | Pre-pass | Final | Δ |
|---|---|---|---|
| fps median | 73 | **120** (vsync cap) | +64% |
| fps min | **19** | **119** | **+526%** |
| frame_ms max | (variable, 0.80+) | 0.55 | smooth |
| gen p95 | 1290ms hitch | 18ms | -98.7% |
| build_floor avg | 1500+ms tail | 432ms | -71% |

### New tooling

- **`/showcase` skill** — hand-curated visual audit floor with one
  station per visual feature (fire/magic/crystal decor, campfire actor-
  tier reference, lava/water/ice, altars, fountains, loot rarities,
  chests, portal, fire/ice creatures with light_spec). Bot patrols a
  fixed loop so its light reveals each station. Use for any visual
  iteration without waiting for procgen to roll the right combination.
  See `.claude/skills/showcase/`.
- **`BOTTER_FORCE_BIOME=<id>`** env var — pins every floor of an
  auto-grind to a single biome. Used for biome-specific A/B sweeps.
- **`[gen-phases]`** log line — per-floor `carve_us / vault_us /
  connect_us / dist_us` profile. Stays in to flag any future generator
  hot spot.

### Hardware caveat (unchanged)

Baseline is M3 Pro Retina. The remaining sub-vsync floors (gen 30-75ms,
vault 10-40ms) are not yet split across frames; on a low-end Windows
laptop these may need further work. Forward+ requires Vulkan — older
hardware will hit the gl_compatibility fallback and lose the smoother-
min benefit.

---

## Perf pass 1 — 2026-05-13 (full session arc)

The session opened with a "fairly simplistic game running at variable
30-120fps" complaint. By end, **avg fps 19 → 112, p50 → 120 (vsync
cap), min 17 → 49** on M3 Pro 1× windowed.

### What turned out to actually be slow (in order of impact)

1. **HUD update was the dominant cost** — `_update_biome_hud` ran every
   frame and (a) called `SaveState.load_state()` (file open + JSON parse
   + migrate) every frame, (b) queue_freed and recreated up to 1745
   `TextureRect` nodes for the inventory grid, (c) repainted a 6400-pixel
   minimap image, (d) wrote 7 Label.text values triggering Godot
   layout/relayout. Throttling these to "data-changed" / 0.25s ticks
   alone took fps from 19 → ~80. **This single class of fix dwarfed
   everything else.**

2. **Tile rendering as per-cell Sprite2D** — 6400 individual canvas
   items × 2 layers = thousands of draw calls per frame. Migrated to
   `TileMapLayer` with a runtime-baked packed atlas (one
   `TileSetAtlasSource` per floor, every biome texture blitted into
   one `Image`). Draws fell from ~6400 to ~150. Per-cell modulate
   visibility fade replaced with a canvas shader sampling the fog
   visibility texture.

3. **Async floor build** — `_build_floor` is now split across 4 frames
   via `await get_tree().process_frame` between gen / atlas-bake / decor
   / spawn phases. The single-frame 70-600ms freeze on stairs descent
   is gone. Build-generation counter cancels stale awaits when a new
   build preempts (fixes the race when runs end mid-build).

4. **AI repath thundering herd** — every enemy initialised
   `repath_timer = 0` so they all fired A* on the same frame; with
   24 enemies that was 24 × ~1ms paths per repath cycle. Fixes:
   stagger `repath_timer = randf_range(0, REPATH_INTERVAL)` at spawn,
   cap `MAX_REPATHS_PER_FRAME = 3` in `_tick_enemies`. ai_us max
   went 12741 → 276µs (46×).

5. **Three CPU opts (already shipped earlier in the session)** —
   - **Fog refresh gate** (`bot.cell` change + invalidate_fog events;
     dedupes `_world_light_sources` to once per refresh). avg -29%,
     p95 -44%.
   - **Shader buffer reuse** in `FogOverlay` — preallocated MAX_LIGHTS
     packed arrays, per-slot diffing skips redundant
     `set_shader_parameter` calls. avg -49%.
   - **FlickerDriver group cache + visibility gating** — replaced
     scene-tree walk with `flicker_lights` group; lights not visible
     in tree skip animation AND pause ember `GPUParticles2D.emitting`.
     avg -96%.

### What I expected to be slow but wasn't

- **PointLight2D shadow filter (PCF5) against ~1500 wall occluders.**
  Disabling shadows entirely gained zero fps. Counterintuitive.
- **WorldEnvironment glow.** Disabling gave ~+1% fps.
- **GPUParticles2D embers.** Disabling gave 0%.
- **Floor enemy count.** ai_us was flat across f1 (6 enemies) → f8
  (24 enemies); the spike was paths firing simultaneously, not the
  scale of work.

### Telemetry that landed

- **`scripts/perf_mon.gd`** — static µs accumulator. Tags
  `frame/fog/lights/flicker/render/ai`. 240-frame rolling window.
  HUD line, `[perf]` log every snapshot, `[perf-floor]` per-floor
  with `label=biome|vault[,vault]|fN`. The `[perf]` line also
  reports `draws=` (RenderingServer draw calls) + `objs=` + `nodes=`.
- **`scripts/dungeon.gd`** — `[build-floor]` line per floor with
  total/gen/render/decor/spawn ms. Pinpoints which phase is slow.
- **`/benchmark` skill** — `.claude/skills/benchmark/`.
  `benchmark.sh [duration_s] [speed] [label] [headless|windowed]`,
  `parse_perf.py` ranks worst floors/vaults/floor-numbers,
  `compare.sh` diffs two logs.

### Hardware A/B knobs (kept for future hardware testing)

Env vars that disable individual systems at scene start, for
hypothesis-testing perf on lower hardware:

`BOTTER_NO_TILES`, `BOTTER_NO_LIGHTS`, `BOTTER_NO_FOG`,
`BOTTER_NO_GLOW`, `BOTTER_NO_EMBERS`, `BOTTER_NO_SHADOWS`,
`BOTTER_NO_OCCLUDERS`, `BOTTER_NO_VSYNC`,
`BOTTER_SHADOW_FILTER=none|pcf5|pcf13`.

`BOTTER_NO_TILES=1 BOTTER_NO_LIGHTS=1 bash benchmark.sh 30 1
all-off windowed` is a useful "what's the platform's ceiling".

### Headless vs windowed

- `--headless` skips the GPU renderer entirely. CPU timers (fog, ai,
  flicker, render-fade, light pack) are honest; **GPU shader / shadow
  / particle costs are NOT exercised**. Useful for fast CPU-only A/B.
- `windowed` launches the actual game window so the full renderer
  runs. Required for any GPU-related measurement.
- Important: at 16× speed_scale the bot ticks 16× per real second,
  so CPU work scales but GPU per-frame cost stays constant.
  GPU-cost measurements need 1× speed.

### Final M3 Pro numbers (2min windowed 1×)

| Metric | Pre-pass | Final | Δ |
|---|---|---|---|
| fps avg | 19 | **112** | 5.9× |
| fps p50 | 18 | **120** (vsync cap) | 6.7× |
| fps p05 | 19 | **56** | 2.9× |
| fps min | 17 | **49** | 2.9× |
| ai_us max | 12,741 | **276** | 46× |
| draws | ~6400 (per-cell sprites) | ~150 (packed atlas) | 40× |

### Hardware caveats

Baseline is **MacBook M3 Pro**. Re-run `/benchmark` on the high-end PC,
mid PC, low-end Windows laptop when those become available — a 200µs
win on M3 Pro can be 2ms on the laptop.

### Outlier maps/vaults — perf hot floors

From baseline 5min, 16×, M3 Pro:

- `crypt|des_grunt_crypt_end_deaths_head` and
  `crypt|des_quadcrypt_mu` — top frame_ms floors.
- `pandemonium|des_hellmonk_crystal_mountain`,
  `pandemonium|des_infiniplex_zot_generator`.
- `lair|des_grunt_forest_small_clearing_treed` — small sample but high
  ms; likely big-tree decor.

These are candidates for inspection if perf still hurts on lower-tier
hardware after these opts.



## Marathon session summary — what just shipped

16+ commits in one session. Highlights:

- **Vault stamping rate 14% → 75-83%** (the fundamental fix to the user's
  "maps look like random messes, no notable loot rooms" complaint)
- **Map size 60×60 → 80×80** for breathing room
- **Bot AI tuning**: aggro range cap, current-room loot priority, low-HP
  retreat. Loot pickup rate jumped from 20 to 125 per run.
- **Starter gear** (rusty_dagger + tattered_hide) so a fresh bot can
  actually progress
- **Weapon overlay sprite** + swing animation on attacks
- **Bot light + z-order fixes** (no more white-out, bot draws over chests)
- **Special-feature terrain** (lava damages, water slows, ice visual)
- **Sigil floor decorations** (single + multi-tile compositions via
  decor_overlays vault format extension)
- **Multi-tile decor glyphs** (t/B/M for trees/bones/mushrooms)
- **Big-creature visual scaling** (32 enemies render 1.3-1.6× scale)
- **22 god altars** (was 7) with thematic blessings
- **Combat effects** (blood/fire/ice on kill, magic shimmer on legendary)
- **Doors** (per-biome variants — wooden/runed/sealed)
- **Save-state isolation** (debug runs don't pollute live save)
- **Bot invincibility** in grind mode
- **Permission allowlist** expanded (saves session clicks)
- **Pre-commit validation** (`tools/check_before_commit.sh`)
- **class_name refresh wrapper** (`tools/refresh_class_cache.sh`) +
  auto-recovery in skill scripts
- **Richer /grind summary** (per-biome breakdown, portal kinds, terrain
  counts)
- **HP scaling bug fix** (level-up no longer fully heals)
- **Run-end-on-boss-kill** gated to actual boss floor
- **Bot visual swap** — spriggan_female base + mummy body armor +
  battleaxe weapon overlay (testing the layered sprite system)
- **Desktop pivot + DCSS chrome**:
  - Viewport 540×960 → **1600×900** landscape. `keep` aspect stretch.
  - New `HudChrome` CanvasLayer (`scripts/hud_chrome.gd`):
    right sidebar (minimap top, stats panel, recent-events log feed),
    bottom-left bag panel (5 equipped slots + scrollable inventory
    grid), tiny top-left debug HUD (biome/floor/layout/recent vault
    names/grid dims/enemy + interactable counts/fps).
  - Subtle translucency on chrome (panel α 0.62, slot bg α 0.40) so
    the dungeon shows under the chrome in the cracks.
  - Camera `offset` shifts world view so the bot stays in the centre
    of the dungeon-visible region (not under the sidebar/bag).
    Screenshot mode bypasses the offset.
  - Old top-left HUD (`hud_name_label`, `hud_hp_bar`, etc.) removed —
    chrome owns all stats.
  - DCSS GUI tile assets copied to `project/assets/tiles/gui/`
    (tab labels, checkboxes, prompt yes/no).
- **Biome editor (per-tile review tool)** — `tools/biome_editor.html`:
  - Visual editor showing every tile that could render per biome
    (floor primary/secondary/accent, wall primary/accent/alternates,
    edge overlay with 3×3 directional grid + N/S/E/W/NE/NW/SE/SW/FULL
    labels, sigil set), per-tile **Replace** dropdown via picker modal,
    Duplicate / New blank / Delete buttons, raw-JSON textarea for
    advanced fields, `⬇ Export biomes.json` downloads modified file.
  - Biome JSON schema extended: `@stem` literal-tile syntax alongside
    prefixes (`biome_data.gd._expand_prefixes`); `wall_primary` now
    accepts arrays as well as strings; `wall_alternates` supports
    `prefixes:` list as well as legacy `prefix:`.
  - `tools/build_biome_manifest.py` bakes asset directory listings →
    `tools/biome_manifest.json` for the static editor.
- **Vault chest cap** — `vault_stamper` enforces
  `CHEST_MAX_PER_VAULT = 8` and `LOOT_MAX_PER_VAULT = 12` with stride
  sampling; `vault_library` precomputes `_chest_count` at load and
  `_effective_weight` divides by 8 (4-7 chests) or 20 (8+) before
  `pick_weighted` rolls. `des_vaults_vault` (28×22 = 608 chest glyphs)
  used to spawn 613 chests and tank perf — now picks ~1/600th as often
  AND caps at 8 chests when it does.
- **Skill marker hygiene** — `grind.sh` and `screenshot.sh` now
  unconditionally `rm -f` their markers (`AUTO_GRIND.txt`,
  `DEBUG_FLOOR.txt`, parked variants) on exit so the user's next
  interactive Godot launch always lands in normal-speed play.
- **Floor pass** (DCSS-faithful):
  - Per-cell hashed weighted variant pick replaces Voronoi patches —
    floors read as "textured" instead of chunky-patches. Weights match
    DCSS's 6/3/1 distribution.
  - Real liquid terrain: river/lake/pools convert FLOOR cells to
    T_WATER / T_LAVA (was: T_WALL stub). Biome-gated via
    `liquid_type: "water"|"lava"|""` in biomes.json (forge / pandemonium
    / abyss → lava; shoals / swamp / lair / snake / forest / slime →
    water). Wired through both `basic_level` and `delve` paths so
    caves layouts also get rivers.
  - Sigil set audit: directional sigils stripped from per-room sigil
    placement (they were designed to layer, not scatter). Defaulted to
    safe single-tile [sigil_circle, sigil_cross, sigil_rhombus].
  - Lair pilot dual-floor mix: Perlin noise (one octave, freq 0.045)
    selects between `floor_primary` (lair) and `floor_secondary` (moss)
    so cells transition organically across the map.

---

## Core gameplay loop — fully working

Garage → Deploy → 10-floor dungeon → Run report → back to Garage with new loot
→ equip → redeploy. Boss on floor 10 (Minotaur). Mini-bosses on floors 5/10/15/20/25
(1.8× HP, 1.4× ATK, larger sprite, red tint, "Greater [Enemy]" name).

## Bot AI

Sticky-target priority engine in `dungeon.gd`:

1. Adjacent live enemy → attack (lock, don't switch).
2. Has unfinished path? → keep walking, don't repick target.
3. Target invalid (enemy died, interactable consumed) → drop path, repick.
4. **Low-HP retreat**: HP < 30% max → head to nearest unconsumed fountain.
5. **Current-room loot priority**: if bot is inside a BSP room and that
   room contains an unconsumed interactable, target it before chasing
   distant enemies.
6. **Aggro range cap (8 cells)**: nearest-enemy chase only if within 8
   cells. Beyond that, bot keeps exploring; combat happens when paths
   cross.
7. Nearest interactable globally → walk toward.
8. Nearest unvisited room → walk toward.
9. Stairs → descend.

The bot reads the full grid for pathing (autoexplore-style); the player
watches through fog. That's intentional and matches DCSS's autoexplore.

**Enemy soft-collision**: enemies hold their tick if their next path-cell
is occupied by another live enemy (excluding the bot's cell). Prevents
the visual stacking when a horde converges on the bot.

## Map size

80×80 cells (was 60×60). Bigger maps mean more breathing room for both
caves and procedural rooms, more space for vaults to land, less cramped
combat. Each tile is 32 px so maps render at 2560×2560 internal coords.

## Vault stamping reliability — FIXED

Earlier sessions saw most floors with `vaults=[]` (vaults rare). Root
causes diagnosed and fixed:

1. **Float stamper picked one random vault, tried once.** If the picked
   vault was 30×20 and no detected room was 32×22, the floor got zero
   vaults — even though plenty of 8×8 vaults would have fit. Fixed:
   stamper now retries up to 16 candidate picks per slot with a size
   filter that pre-screens for fitting candidates.
2. **First and last rooms were always skipped** in the room-shuffle
   loop (legacy attempt to keep spawn/stairs vault-free). On caves
   layouts where room order is arbitrary this discarded ~20% of valid
   placements. Fixed: try every room.
3. **Vault-stamped boss enemies ended the run prematurely.** Vaults
   like `des_shoals_end_hellmonk_lost_city` have `spawns: [..., minotaur]`
   and minotaur is boss-flagged, so killing it on floor 5 ended the run
   "victorious". Fixed: run-end-on-boss-kill only triggers on the actual
   final-boss floor (`current_floor >= BOSS_FLOOR`).

Result: vault stamp rate jumped from 14% to 75-83% per floor. A typical
3-run grind now stamps 14-17 unique vaults across 30 floors.

## Bot invincibility (grind only)

When auto-grind is active, `DebugJump.bot_invincible = true` and
`Bot.take_damage` no-ops. Lets benchmark runs reach floor 10 reliably so
late-floor generation is audited even if the bot's combat balance is off.
Live playtest is unaffected.

## Generation pipeline (DCSS-faithful)

Order in `dungeon_generator.gd`:

1. **Encompass-vault short-circuit.** ~25% gate; if hit, the vault IS the level. Stairs come from vault `<`/`>` glyphs.
2. **Procedural layout.** Picked from `BiomeData.roll_layout()` weighted pool — `basic_level` / `caves` / `caves_tight` / `caves_open`. Each biome ships 2-3 layouts so the same biome can look different across runs.
3. **Oriented vault stamp.** N/S/E/W/centre vaults attached to the matching map edge.
4. **Float vaults.** ~1-2 per floor (2 on floor 7+), filtered by biome `vault_themes` array.
5. **Connectivity verification.** BFS from spawn; orphans get carved corridors, full regen if needed.

Generator regenerates if a layout produces < 200 floor cells (up to 5 attempts).

## Biome roster — 24 biomes, all wired

`dungeon, dungeon_dark, mines, lair, forest, swamp, snake, shoals, orc,
vaults, crypt, tomb, forge, glacier, slime, hive, labyrinth, abyss,
pandemonium, zot, elf, spider, temple, depths`

Each declares `vault_themes` (which vault tags it pulls), `layouts` (weighted
pool), `floor_primary`/`wall_primary`/`wall_alternates` tile prefixes,
`enemy_pool`, `ambient_decor`, `darkness`, `modulate`, and an optional
`edge_overlay`.

`BiomeData.roll_run_plan()` currently builds a fully-random 10-floor plan
(every floor independently rolled). Locked-in chain mode (D:1-3 → Lair:1-2 →
…) is in TODO.

## Vault library — 1320 ported DCSS vaults

All in `project/data/vaults/des_*.json`. **No hand-typed ASCII vaults remain**
— they were redundant with the ported pool and were deleted.

Filter rules in `vault_library.gd` `_theme_match_any`:

- A vault matches a biome if they share at least one non-`dungeon` tag, OR
- The vault has only `dungeon` (universal), OR
- The biome's only request is `dungeon` (then dungeon-tagged vaults match).

This stops Lair-tagged vaults from leaking into Crypt biomes etc.

Lair sub-branch tags (`swamp`, `snake`, `shoals`, `spider`, `forest`, `hive`)
are mutually exclusive with `lair` on ported vaults — i.e. a swamp-tagged
vault no longer also has `lair`. So Swamp pulls 293 vaults, Snake 272, Shoals
275, Spider 243, Hive 164, Forest 173 — each distinct rather than all sharing
the 620-strong Lair pool.

## Portals — DCSS-style mini-floors

8 portal kinds (`sewer, bailey, bazaar, ossuary, wizlab, trove, ziggurat,
hive`) live in `Portal.PORTAL_KINDS`. 15% spawn rate per eligible floor
(2-9). Stepping on a portal interactable swaps the current floor in-place to
the portal's biome with bonus chests (+1 to +2 count, rarity bias).
Descending the portal floor's stairs continues the run normally; the floor
counter does not advance during the side-trip.

## Visible loot, interactables, FX

- **Loot drops**: Items physically drop on floor with rarity-coded glow + idle
  wobble. Bot kneels (squish + lean) to pick up. Rarity-scaled pickup
  duration (common 0.35s → legendary 0.8s).
- **Affix system**: 30 affixes (Sharp, Vicious, of Vigor, of Fortune, etc).
  Roll 0-4 per item by rarity. Items get "Sharp Iron Sword of Vigor"-style
  names. 5 stats wired to combat (hp/atk/def/hp_pct/atk_pct); 24 others parse
  but don't affect gameplay yet.
- **Interactables**: chests (burst items in arcs on open), fountains (heal
  40-60% HP, bot only stops if injured), altars (22 god-themed
  run-ephemeral blessings — Trog/Okawaru/Zin/Elyvilon/Vehumet/Kiku/Sif Muna
  + Beogh/Makhleb/Yred/TSO/Lugonu/Jiyva/Fedhas/Cheibriados/Xom/Ashenzari/
  Dithmenos/Gozag/Qazlal/Nemelex/Ru), portals (above).
- **Sprite FX**: per-actor Tween-driven squash/stretch — attack lunge
  (with bright color flash on swing), hit squish + flash, death spin/
  shrink, kneel-on-interact, loot pop.
- **Run journal**: per-floor narrative log (DCSS-morgue style) shown on run
  report alongside loot recovered/lost.

## Fog of war + dynamic lighting

Radius-based reveal (FogSystem `REVEAL_RADIUS=7`) plus `PointLight2D`-driven
lighting from world sources (altars, fountains, lava, legendary loot, lit
chests). Tile sprites have a 3-state visibility system (UNSEEN/EXPLORED/VISIBLE)
applied as per-cell modulate.

**Walls don't yet block vision** — that's the line-of-sight upgrade in TODO.

### Organic flicker + ember particles

`LightSpec.attach()` stamps a "flicker" meta dict on each PointLight2D
instead of running a tween. A single `FlickerDriver` node walks the
scene each frame and animates every light via a shared FastNoiseLite,
sampled at unique seeds per-light so flames desync naturally. Three
flicker categories:

- **fire** — broadband noise, sub-pixel position jitter, ember particles
  (GPUParticles2D with per-spec colour gradient)
- **magic** — noise + slow sine pulse, no jitter, no particles
- **crystal** — slow noise wobble, no jitter, no particles

Light specs added: `firestarter`, `hellfire`, `demon_blade`, `firefly`,
`fire_creature`, `lava_creature`, `ice_creature`, `magic_lamp`.

### Per-creature emitter lights

`enemies.json` entries can declare a `light_spec` field. The spawner
calls `LightSpec.attach(enemy, spec)` so fire dragons / ice giants /
fireflies emit their own light. 8 creatures tagged: fire_giant,
fire_dragon, salamander, cacodemon, ice_dragon, ice_beast, frost_giant,
blizzard_demon.

### Fire weapons emit light

`Bot.WEAPON_LIGHTS` maps weapon `base_id` -> light spec. Fire-tagged
weapons (firestarter, hellfire, demon_blade, flaming_sword/axe) attach
their light to the weapon overlay sprite, so the glow follows the bot's
held hand.

## Edge-overlay autotile system

In `MapRenderer._apply_edge_overlay`. Floor cells that border walls get a
second sprite layer with directional pieces (north/south/east/west + 4
corners). 57 directional tiles in `project/assets/tiles/overlays/` — 5 sets:
`grass, dirt, slime_overlay, shallow_water_wave, deep_water_wave`.

Wired to biomes:
- **lair / forest** → `grass` (high density)
- **swamp / snake / spider / hive** → `dirt`
- **slime** → `slime_overlay`
- **shoals** → `shallow_water_wave`

The renderer reads `biome.edge_overlay = {"prefix": "grass", "density": 0.85,
"patch_density": 0.06}`.

## Special-feature terrain (lava / water / ice)

Three new walkable-with-effect cell types:
- `T_LAVA` — walkable but damages bot 5% max-hp every 0.5s on the cell.
  Pathfinder weight 4.0 (avoid if any safe path exists).
- `T_WATER` — walkable, halves move_speed while bot is on the cell.
  Pathfinder weight 2.0. Affects enemies symmetrically.
- `T_ICE` — visual-only for v1 (slip mechanic deferred).

Wired via VaultStamper glyphs `L`/`l` (lava), `W`/`w` (water), `I` (ice).
Six mini-vaults in `project/data/vaults/`:
`forge_lava_pit_5x5`, `forge_lava_bridge_7x3`, `shoals_tide_pool_5x5`,
`swamp_bog_5x5`, `glacier_ice_shrine_5x5`, `crypt_blood_pool_3x3`.
All authored as **irregular organic shapes** — no rectangular blobs.

Sprites in `project/assets/tiles/terrain/{lava, water, ice}.png`.

The vault-stamping system has a debug-only fallback: if `DebugJump.vault_name`
matches the vault being stamped AND no rooms are available (caves layout),
the stamper does a bounded random-region scan to place it for screenshot
verification. Outside debug mode, vaults strictly require BSP rooms.

JSON sidecar exposes `floor.terrain_cells: {lava: N, water: N, ice: N}`.

## Doors

Vault `+` glyph renders as `closed_door`/`runed_door`/`sealed_door` based
on biome. Stone-tier biomes (vaults/depths) get sealed iron; ritual
biomes (crypt/tomb/elf/zot/pandemonium/abyss) get runed; everywhere else
gets the plain wooden closed door. Three sprites in
`project/assets/tiles/features/`. Mapping in `MapRenderer.DOOR_BY_BIOME`.

## Combat effects

Lightweight `Effects` helper (`scripts/effects.gd`) — one-shot Sprite2D
fades. Hooks:

- Enemy died → biome-themed kill flash. Forge/Pandemonium → fire,
  Glacier → ice, everywhere else → blood splat.
- Legendary loot picked up → magic shimmer.
- Rare loot picked up → gold sparkle.
- Altar grant → magic shimmer at the altar.

7 effect tiles in `project/assets/tiles/effects/`. Each spawn tweens
scale + alpha and queue_frees itself; no persistent state.

## Big-creature visual scaling

In `Actor.apply_visual_scale(scale, anchor, z)`. 32 creatures in
`enemies.json` carry optional `visual_scale` / `visual_anchor` /
`visual_z` fields. Dragons, giants, sphinxes, mummies render at 1.5x
ground-anchored (sprite bottom pinned to cell bottom, body extends up).
Jellies/oozes/spiders render at 1.4x centre-anchored (sprawls outward).
Champion variants stack on top (1.5 × 1.25 = 1.875). Miniboss variants
stack to 1.5 × 1.4 = 2.1, capped at 2.5.

Logical layer (cell, hp, attack adjacency, pathfinding) untouched —
every creature still occupies one cell. The visual scale is purely
sprite-render. Z-ordering means big creatures draw over decor and
adjacent smaller enemies. Screenshot JSON sidecar exposes
`entities.enemies[].visual_scale` and `visual_anchor`.

True multi-cell creatures and tentacle-segment chains are deferred —
the shipped CC0 DCSS pack only contains 32×32 sprites; multi-cell
mechanics need 32×64 art we don't have plus pathfinding/collision
rewrites.

## Sigil floor decorations

Two systems, both shipping in `project/assets/tiles/sigils/` (70 PNGs).

**Single-tile room sigils** (`MapRenderer._stamp_room_sigils`): each BSP
room in stone-tier biomes gets 1-2 random sigil rune marks (`sigil_circle`,
`sigil_cross`, `sigil_algiz_*`, `sigil_y_*`, etc). Per-biome `sigil_set`
array + `sigil_density: [min, max]` field in biomes.json. Wired biomes:
vaults, crypt, tomb, elf, temple, depths, zot, labyrinth, pandemonium.
Skips cells in `vault_results.protected_cells` so vault-stamped features
aren't covered. Caves layouts (rooms == []) skip the pass.

**Multi-tile sigil compositions** via vault `decor_overlays` field. Six
mini-vaults in `data/vaults/sigil_*.json` (3×3 cross, 3×3 pinwheel, 5×1
straight line, 3×3 compass, 5×5 runed circle, 5×3 paired-Y) compose
several pieces into pre-arranged shapes. Stamper writes `decor_marks` to
results, renderer stamps the named texture over the floor cell. Pure
cosmetic, no terrain impact, system reusable for future multi-tile decor
beyond sigils.

Both systems expose their placements in the screenshot JSON sidecar's
`entities.sigils_stamped` and `entities.decor_marks` arrays.

## Logging — structured per-floor + per-run

In `GrindLog.log_line`. Tags:

- `[run]` — `start hp/level/gold`, `end #N victory=… kills=… loot=… …`,
  `auto-grind ENABLED/COMPLETE`
- `[gen]` — per-floor generation: `f=1 biome=lair layout=caves_open
  cells=900 largest=900 regions=1 bbox=… rooms=18 vaults=[…]`
- `[floor]` — per-floor outcome: `f=1 biome=lair ticks=338 kills=6 loot=2
  chests=1 altars=0 fountains=0 portals=0 stalls=0 hp_lost=14`
- `[portal]` — `entered=wizlab -> biome=elf bias=2 on_floor=3`
- `[stall]` — only on actual stalls (bot 120t without movement)
- `[bad-floor]` — generator regression flags
- `[render]` — debugging only: confirms which biome/textures the renderer
  loaded for a build

`[grind-debug]` ticker (every 240 frames in `_tick_bot`) was REMOVED — it
emitted nothing useful and drowned the log.

## Asset atlas — 6945 PNGs catalogued

`project/data/tile_atlas.json` (1.5 MB) is built from DCSS source
`rltiles/dc-*.txt` plus filesystem walk. Per-tile fields: `category`,
`subcategory` (item subcat), `enum`, `biome_tags`, `class_hints`,
`variant_set`, `variant_index`, `directional`, `direction`, `weight`.

Browse interactively: open a local web server in the repo root
(`python3 -m http.server 8080`) and visit `tools/atlas_viewer.html`. Filter
by category / biome / class / subcategory, group by subdir / variant_set.

Rebuild: `python3 tools/build_atlas.py`.

## Test harnesses

### `/screenshot` skill — biome / vault visual verification

```
bash .claude/skills/screenshot/screenshot.sh <biome> [vault|_] [floor]
```

Drives the `DEBUG_FLOOR.txt` marker, launches Godot at 1024×1024, captures
viewport, writes BOTH a PNG and a JSON sidecar, prints both absolute paths.
**The JSON is authoritative.** Use the PNG for shape/silhouette only — color
hallucinations and small-text misreads are common at compressed thumbnail
size. The JSON contains: HUD strings, biome id + display name, layout id,
all loaded floor/wall/overlay textures (resource paths), every
enemy/interactable/loot with cell+kind, room rects, stairs/spawn cells,
ambient settings, modulate values.

Logs land in `logs/screenshots/<timestamp>_<biome>_<vault>_<floor>.log`.
Screenshots in `~/Library/Application Support/Godot/app_userdata/Botter/debug_screenshots/`.

### Save-state isolation

When `AUTO_GRIND.txt` or `DEBUG_FLOOR.txt` markers are present, `main.gd`
sets `SaveState.debug_mode = true`. SaveState then reads/writes
`user://botter_save_debug.json` instead of `user://botter_save.json`.
Live playtest save is untouched by benchmark or screenshot runs.

To reset the debug save: delete `botter_save_debug.json` from the user
data dir. To reset live: delete `botter_save.json`.

### Auto-grind — headless N-run benchmark

```
echo "16,5" > "$HOME/Library/Application Support/Godot/app_userdata/Botter/AUTO_GRIND.txt"
/Applications/Godot.app/Contents/MacOS/Godot --path /Users/dyo/claude/botter/project --headless
```

`<speed>,<max_runs>` in the marker. Bot auto-deploys at N× speed, plays
through `max_runs` complete runs, prints structured logs, exits.
Implementation in `main.gd` `_ready()`.

### Debug-jump — same as `/screenshot` skill but without the screenshot

Marker `<biome>[,<vault>][,<floor>]` in `DEBUG_FLOOR.txt`. Skips garage,
spawns directly into that biome+floor with optional forced vault stamp.
The 4-field form `biome,vault,floor,1` enables screenshot mode (the
`/screenshot` skill drives this).

## Decisions on record

- **Stack**: Godot 4.6.2-stable + GDScript. No C# / GDExtension.
- **Pathfinding**: `AStarGrid2D` over NavigationAgent2D / custom A* —
  engine-native C++, grid-aligned, `set_point_solid` maps 1:1 to wall tiles.
- **Number ceiling**: ~1500 HP / ~300 ATK / ~100 DEF endgame; ~300-400 peak
  damage. User explicitly rejected idle-game number creep.
- **DCSS source**: shallow-cloned (132 MB) into `dcss-source/`. **Research
  only — GPLv2+, never copy code.** Gitignored.
- **DCSS tile pack**: gitignored (35 MB CC0 art); only the curated subset
  under `project/assets/tiles/` ships.
- **Run plan**: currently fully-random per floor. Locked-in DCSS-style chain
  (D:1-3 → Lair:1-2 → …) is the planned default once branches feel
  content-complete.

## Open balance knobs (next time we touch combat)

- **Vault frequency** — currently ~75-83% per floor with retry-up-to-16
  candidates. Feels right; may need to dial back for atmosphere on some
  biomes.
- **Common gear power** — Rusty Dagger is +16 ATK on a 6 ATK base.
  Starter bot is dramatically stronger than a no-gear bot. May want to
  trim early-tier item stats once playtesting reveals balance gaps.
- **24 affix stats not yet wired into combat** (crit, lifesteal, gold
  find, dodge, regen, thorns, etc). Affix system rolls them on items
  and prints them in tooltips but they have no gameplay effect.
- **Aggro range cap (8 cells)** is conservative; may be too restrictive
  on bigger 80×80 maps where cluster combat would feel more alive.
