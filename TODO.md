# Botter — TODO

Roadmap and deferred items. The "what works today" lives in `HANDOVER.md`;
the durable rules in `CLAUDE.md`. Update this file when committing.

---

## Active — next session

Full gameplay loop plan written: **`docs/gameplay-loop-plan.md`** (2026-05-15).
This is the primary reference for all loop-shaping work. Implements in 10
beats ordered by dependency. Read it before any of the items below.

Summary of what changed direction:
- Runs are now **6 floors** (5 regular + 1 boss), not random 10. Branch is
  player-selected in Garage, not random.
- Biomes organised into **5 tiers** gated by CR + boss kills. All 24 biomes
  assigned. See `docs/gameplay-loop-plan.md` Appendix B.
- **Affixes slimmed to 5**: Strength / Stamina / Agility / Regen / Crit.
  Old 30-affix system replaced in full. See Part 3.
- **Gear bloat solved**: inventory cap 50, loot filter (player sets min rarity
  for bot to pick up), auto-salvage below threshold → gold.
- **Death is a retreat**, not a run-end. Bot respawns floor 1 of same branch.
  Enables 1h+ unattended play.
- **Offline progress**: delta-time loot calc on load, capped at 1h.
- **Bot upgrades**: permanent gold-sink purchases (Conditioning, Combat Training,
  etc.) that persist across prestige.
- **Gold economy** defined per tier. See Part 7.

Pending beats (follow plan order):

- ⬜ **Beat 1 — Affix simplification** (`affixes.json` replace + crit wiring
  in `actor.gd` + save migration). ~1–2h.
- ⬜ **Beat 2 — Branch tier data** (`biomes.json` + `enemies.json` bosses +
  `constants.gd` floor count changes + TIER_SCALE). ~1h.
- ⬜ **Beat 3 — Save state migration** (new fields + `_migrate()`). ~30m.
- ⬜ **Beat 4 — Branch-aware run plan** (`BiomeData` + `dungeon.gd` scaling +
  boss spawn + unlock signal). ~1–2h.
- ⬜ **Beat 5 — Death retreat** (retreat instead of run-end). ~1h.
- ⬜ **Beat 6 — Gear bloat** (loot filter + inventory cap + auto-salvage). ~1–2h.
- ⬜ **Beat 7 — Bot upgrades** (`bot_upgrades.json` + Garage tab). ~2–3h.
- ⬜ **Beat 8 — Branch picker UI** (Garage branch list + CR indicator). ~2–3h.
- ⬜ **Beat 9 — Offline progress** (delta-time loot on load + "While Away" screen). ~1–2h.
- ⬜ **Beat 10 — Run report: unlock prominence** (boss-kill unlock shown first). ~30m.

Previous "run planning UI in Garage" item is superseded by Beats 4 + 8 above.

Other queued work (lower priority than the gameplay loop beats):

- **Garage / run_report layout review** — both scenes still use the
  portrait-era VBox layouts. Probably readable on 1600×900 but worth
  a once-over to use the wider canvas (e.g. equipped + inventory side
  by side, stats column on the right).

## Perf — done for now

Two passes complete. Pass 1 (2026-05-13) was CPU-side at 1600×900
windowed. Pass 2 (2026-05-14) was GPU + hitch at native Retina:
**fps min on forge 19 → 119, gen p95 1290ms → 18ms**. See HANDOVER for
the full breakdown.

Remaining items are all "nice to have" / "validate on other hardware":

- ⬜ **Validate on lower-tier hardware** — high-end PC, mid PC, low-end
  Windows laptop. Env-var A/B knobs (`BOTTER_NO_*`, `BOTTER_FORCE_BIOME`)
  are wired, ready for hypothesis tests on each platform. Forward+
  requires Vulkan — track which hardware falls back to gl_compatibility.
- ⬜ **Stretch mode `viewport`** — currently `canvas_items` (renders at
  window resolution). `viewport` mode renders at design size + GPU
  upscales — universal pixel-art-game perf trick on high-DPI. Changes
  pixel snap, needs a visual review under `/showcase` before shipping.
- ⬜ **Glow / bloom video options toggle** — `WorldEnvironment.glow_*`
  is on unconditionally for ~+1% cost. Add a graphics-options toggle
  for low-end targets. Low priority.
- ⬜ **Outlier vaults** — `des_grunt_crypt_end_deaths_head`,
  `des_quadcrypt_mu`, `des_hellmonk_crystal_mountain` consistently top
  the perf-floor ranking. Cosmetic perf — inspect for excess decor,
  light count, or pathological room shapes only if a low-end target
  struggles on these floors.
- ⬜ **Shadow filter for ambient decor** — drop PCF5 to NONE/PCF13 only
  if a low-end target shows shadows as the cost. Currently zero impact
  on M3 Pro. The `BOTTER_SHADOW_FILTER` env var is the test harness.
- ⬜ **MapRenderer fade dirty-set** — minor (~410µs); skip if not seen
  in the wild.
- ⬜ **`_carve_layout` p95 53ms** — biggest remaining gen hitch on
  forge. Already async-split at the build-floor level so the user
  sees it as a stutter, not a freeze. Could split internally if a
  weaker target shows it as a problem.

## New skills shipped

- ✅ `/showcase` — visual audit floor with one station per feature.
  See `.claude/skills/showcase/`. Use for any flicker / glow / terrain /
  loot-rarity visual iteration. Bot patrols a fixed path so each
  station enters its light radius in turn.

## Combat pass (queued)

User flagged for a future session:
- **Affix expansion** — wire crit / lifesteal / regen / dodge / thorns
  from items into combat. Currently 5 of 30 affixes affect gameplay; the
  other 25 are decorative. ~3h.
- **Real paper-doll** — not just weapon overlay. Body armor / helm /
  boots / shield / cloak each get a sprite layer matched to equipped
  item. ~1 day. Atlas already catalogs 975 paperdoll sprites.
- **Enemy attack effects** — currently bot has weapon overlay + swing
  animation. Enemies just have hit_squish on hit. Add per-enemy attack
  animations: dragon breath, mage cast, archer shoot.

## Active — directional tiles continuation

Edge overlays and sigils both shipped. Remaining: multi-tile creatures.

### Multi-tile creatures (deferred)

Visual scaling shipped — see HANDOVER.md "Big-creature visual scaling".
32 creatures (dragons, giants, sphinx, mummies, jellies, etc) render at
1.3-1.6× scale with proper anchor + z-ordering. Logical layer still 1
cell per creature.

True multi-cell mechanics (vine_segment chains, kraken with 4 tentacle
cells, serpent_of_hell) deferred because:

- Shipped CC0 DCSS pack is 32×32 only. The 32×64 unique-monster sprites
  DCSS uses for big creatures are not in our pack. Custom 32×64 art or
  bigger sprites would be needed.
- Pathfinding (AStarGrid2D) doesn't natively support multi-cell shape
  obstacles. Enemy class would need a `multi_tile_layout` of relative
  cell offsets; pathfinder must mark all occupied cells solid; bot
  attack-target picker needs nearest-cell-of-creature math; spawn
  validation needs N-cell open-region check.
- Tentacle chain solver (per-frame chain physics or grid-based tail
  follow) is its own beat.

Architectural sketch when we revisit: Enemy gets optional
`multi_tile_layout: Array[Vector2i]` (offsets from head). Pathfinder
treats all occupied cells as solid against other enemies. Bot adjacency
test = `min(chebyshev to any creature cell)`. Render: parent sprite at
head, child sprites at offsets. Spawn validates an N-cell open
"footprint" before placement.

## HP scaling — DONE (root cause identified + fixed)

Root cause: `Bot.gain_xp` was setting `hp = max_hp` on every level-up, fully
healing the bot every time it levelled. With 50% xp boost (Sif Muna) or
chained kills, level-ups happened mid-floor, so HP never appeared to drop.
Fix: level-up grants only the +8 max_hp slice (`hp = mini(max_hp, hp + 8)`),
no full heal.

Combined with save-state isolation (level-1 fresh start instead of grind-
inflated bot at lvl 247), the dungeon now correctly tests as hard. Bots
die at floor 2-3 unequipped; will need to playtest gear progression to
balance.

---

## Variety pass — partly shipped, rest pending

The "1.5 variety pass" originally listed as 9 sub-stages. Status:

- ✅ **1.5a Smart tile placement** — uniform walls (`wall_primary` + 5-10%
  `wall_accents`), Voronoi floor patches, strict prefix matching to avoid
  pulling directional overlays as primary.
- ✅ **Edge overlays** (was nominally part of 1.5e but shipped as its own
  beat) — grass / dirt / slime / shoreline directional autotile.
- ✅ **1.5-fog+light** — bot lantern, world Light2Ds (altars, fountains,
  legendaries, lava cells in Forge), per-cell visibility state machine,
  WorldEnvironment with bloom.
- ✅ **1.5-walls** (impassable terrain variety) — `wall_alternates` system,
  per-biome cluster themes (water in Shoals, trees in Forest, etc).
- ✅ **1.5b Decor scatter** — `AmbientDecor` system, per-biome decor pool
  with weighted ids and density.
- ✅ **1.5c Monster expansion** — went from 10 to ~177 unique monsters
  (per atlas). Many enemy pools now use 6-15 candidates per biome.
- ✅ **1.5d Artefact items** — legendaries pull from `item/weapon/artefact/`
  and `item/armor/artefact/` pools via `tile_override`.
- ✅ **Sigils + multi-tile decor** — single-tile room sigils on stone-tier
  biomes + multi-tile compositions via vault `decor_overlays` field. The
  `decor_overlays` system is general — reusable for future multi-tile
  decor (zot generators, abyss chaos rings, hive honeycomb patterns).
- ✅ **1.5e Special features (terrain)** — `L`/`l` (lava, 5%/0.5s damage),
  `W`/`w` (water, 50% move speed), `I` (ice visual-only). Six mini-vaults
  for forge/shoals/swamp/glacier/crypt with irregular organic shapes.
  Pathfinder weight 4.0 lava / 2.0 water. JSON sidecar exposes counts.
  Plus river/lake/pools builder converts FLOOR cells to T_WATER / T_LAVA
  procedurally on biomes with `liquid_type` set. Wired through both
  `basic_level` and `delve` paths. Still TODO: `t` (tree), `B` (bones),
  `M` (mushroom) impassable decor; ice-slip mechanic.
- ✅ **Floor pass** — per-cell hashed weighted variant pick (replaces
  Voronoi patches), directional sigils stripped from per-room placement,
  Lair dual-floor mix pilot via Perlin noise (lair-grass + moss),
  `liquid_type` field threaded through generators so caves layouts can
  also stamp rivers/lakes.
- ✅ **1.5f Door tiles** — vault `+` glyph renders as closed/runed/sealed
  door per biome (3 sprites, mapping in MapRenderer.DOOR_BY_BIOME).
- ✅ **1.5g Combat effects** — Effects helper class. Biome-themed kill
  flashes (fire/ice/blood), magic shimmer on legendary pickups + altar
  grants, gold sparkle on rares.
- ⬜ **1.5h Negative space** — partially done via fog; could be tighter
  (smaller playable area, tighter camera).
- ✅ **1.5i DCSS-style UI** — landscape 1280×720 viewport, right
  sidebar with minimap + stats + log feed, bottom-left bag panel
  (equipped slots + scrollable inventory), tiny top-left debug HUD
  (biome/vaults/cells/fps). Mobile port deferred — desktop is the
  primary target now.

## DCSS-port — phases

### Phase A — port DCSS algorithms (mostly done)

- ✅ `dgn_build_basic_level` → `DCSSLayouts.basic_level` (trail + rooms)
- ✅ `delve()` cave generator → `DCSSLayouts.delve` (with `caves`,
  `caves_tight`, `caves_open` parameter presets)
- ⬜ `dgn-shoals.cc` — branch-specific Shoals generator (tide pools, sand
  islands)
- ⬜ `dgn-swamp.cc` — branch-specific Swamp generator (boggy paths, water
  expanses)
- ⬜ `dgn-proclayouts.cc` — Worley/Perlin layouts (`RiverLayout`,
  `ColumnLayout`, `DiamondLayout`, `WastesLayout`)
- ⬜ `dgn-irregular-box.cc` — non-rectangular rooms

### Phase B — port DCSS data tables

- ⬜ `enemies.json` — replace stats with DCSS `mon-data.h` values (decades-
  tuned). Currently using a mix of hand-rolled and partial ports.
- ⬜ `items.json` + affix system — port from DCSS item definitions and `ego`
  enum. Currently 30 hand-rolled affixes; DCSS has more.
- ⬜ `biomes.json` → eventually rename to `branches.json`. One entry per
  real DCSS branch with its actual generator id, enemy pool, vault tags,
  ambient features.

### Phase C — bot AI + idle loop (the actual game)

This is the only Botter-unique creative work:

- ⬜ Configurable bot priorities (started — proximity-ranked behavior).
  Config UI in Garage screen. Bot AI now has aggro range cap (8 cells),
  current-room loot priority, low-HP retreat. Player exposing these as
  Garage sliders is the next step.
- ⬜ Run-config: which branches to attempt, gear loadout, behavioral
  preferences (greed vs caution, melee vs ranged).
- ⬜ Idle reward curves (offline progress, time-gated rewards).
- ⬜ Meta-progression (prestige, permanent unlocks, gear stash).
- ✅ Visual presentation (fog, lighting, sprite FX, edge overlays).

## Generation pipeline — DCSS-faithful gaps

Caught up substantially this session. Remaining gaps in the canonical
DCSS order:

- ⬜ **Doors aren't placed by the layout** — `_place_doors_in_corridors()`
  in `basic_level` is a stub. DCSS does it inside `_make_room`.
- ⬜ **Branch-entry vault stamping** — slot 4 in the pipeline is reserved
  but unused. Once we have branch transitions, this becomes meaningful.
- ⬜ **Chance vault gating** — DCSS has per-vault probability tables (e.g.
  "20% on D:2, fallback 0"). We use a flat `chance` field. Port the
  per-branch table.
- ⬜ **DEPTH algebra** — DCSS supports `D:2-7`, `Lair:1-3`, `!Zot`. We use
  simple `[min, max]` integer ranges.
- ⬜ **`SUBVAULT` glyph** — vaults can reference other vaults by name.
  Skipped intentionally per agent recommendation; revisit if vault authoring
  ever needs nesting.

## DCSS branch roster — port status

Phase 1 ship-ready (have biome + assets): D, Lair, Orc, Swamp, Vaults, Crypt,
Tomb, Zot — all in production.

Phase 2 (1-2 sprites needed): Elf ✅ shipped, Snake ✅, Spider ✅, Shoals ✅,
Depths ✅, Slime ✅, Forge ✅ (cross-pollinated with zot), Glacier ✅
(cross-pollinated with crypt). All in production.

Phase 3 (heavier lift, deferred):

- ⬜ Hell tier (Vestibule, Dis, Geh, Coc, Tar) — endgame branches with
  custom procgen and signature monster waves.
- ⬜ Pan / Abyss morphing geometry — DCSS regenerates these every step.
  Deferred; current biomes use static layouts as a stand-in.
- ⬜ Dedicated branch generators — Shoals tide pools, Swamp bogs (currently
  using `caves_open` / `caves` as approximations).

## Quality / regression telemetry

Already shipping:

- ✅ `[gen]` per-floor metrics (cells, largest region, regions, bbox, rooms)
- ✅ `[bad-floor]` flags (floor_count<250, largest_region<400, bbox<400,
  orphan_cells>60)
- ✅ Stall snapshots dumped on hard-recovery (`user://stall_snapshot_floor*.txt`)
- ✅ `[floor]` per-floor outcome (kills, loot, ticks, hp_lost)
- ✅ `[run]` per-run summary (kills, loot, portals, stalls, biomes,
  unique vaults)
- ✅ Auto-grind harness with N-run support

Still want:

- ⬜ **Aggregate end-of-grind report**: "5 runs, 50 floors, X% bad-floor rate".
  Currently you'd have to grep yourself.
- ⬜ **Generator unit-style harness**: headless script that calls
  `DungeonGenerator.generate()` 200× per layout, prints bad-floor rate per
  layout. Run before merging generator changes.

## Tooling — infrastructure

Quality-of-life upgrades to land before more feature work piles up.

### Permission allowlist — DONE

Shipped. .claude/settings.json now allows common patterns: read-only git
(status/log/diff/show), python3, bash skills, find/grep/sed/awk/jq, file
ops, etc. Destructive ops (rm, git push, git reset --hard, gh) stay
behind `ask`.

### Save-state isolation — DONE

Shipped: `SaveState.debug_mode = true` when AUTO_GRIND or DEBUG_FLOOR
markers are present, routing IO to `user://botter_save_debug.json`. Live
`botter_save.json` is untouched by benchmark/screenshot runs.

### class_name refresh wrapper — DONE

Shipped: `tools/refresh_class_cache.sh` wraps `godot --headless --import`
and reports class count. Both `/screenshot` and `/grind` skills auto-detect
"Parse Error: ... not declared" in their log output and re-run with
refresh.

### Pre-commit headless validation

Run a 1-floor-per-biome smoke build, grep for `[bad-floor]` or any `ERROR`/
`SCRIPT ERROR` in the output, exit non-zero if found. Wire as a pre-commit
hook OR as a `tools/check_before_commit.sh` script. Catches generator
regressions and parse errors before they land. Should take <30s with
debug-jump's per-biome 1-floor mode.

## Tooling — skills

- ✅ `/screenshot <biome> [vault] [floor]` — captures one PNG + JSON sidecar
  per call. See `.claude/skills/screenshot/`.
- ✅ `/grind <runs> [speed]` — N-run headless harness, structured summary.
- ✅ `/benchmark <duration_s> [speed] [label] [headless|windowed]` —
  time-bounded headless run with PerfMon telemetry; `parse_perf.py`
  ranks worst floors / vaults; `compare.sh` diffs two logs.
- ⬜ **Batch screenshot mode** — single Godot process with TCP eval to
  capture N biomes at the cost of one cold start. The fork
  `tugcantopaloglu/godot-mcp` (cloned to `/Users/dyo/claude/external/godot-mcp-fork`)
  shows the pattern: an autoload TCP server accepts JSON commands. Worth
  porting if we ever need a 24-biome audit in one shot.

## Asset utilization — gaps

- ⬜ **Doors** — 30 door sprites, none used (vault `+` renders as plain floor)
- ⬜ **Traps** — 24 trap sprites, none used
- ⬜ **Effects** — 238 effect frames (blood, fire, ice, magic), none used
- ⬜ **Player paper-doll** — 975 layered sprites for custom bot appearance.
  Deferred to post-MVP cosmetics. Architecture sketch: base body + per-slot
  overlays, `equipped` dict picks `tile_override` per slot.
- ✅ **God altar variants** — expanded from 7 to 22. Beogh/Makhleb/Yred/
  TSO/Lugonu/Jiyva/Fedhas/Cheibriados/Xom/Ashenzari/Dithmenos/Gozag/
  Qazlal/Nemelex/Ru added with thematic blessings + glow colors.
- ✅ **Organic flame jitter** — done. FlickerDriver runs FastNoiseLite
  per-light with unique seeds so flames desync. Sub-pixel jitter on
  fire-category lights. Ember particles on flame sources.

## Open questions — defer until needed

- PvP (async — your bot vs. another player's dungeon config)
- Prestige / rebirth for endgame
- Clan / guild social features
- Steam Deck support alongside mobile
- Monetization model

## Out of scope (decided no)

- DCSS *source code* in the project (GPLv2+ would force the whole game
  open-source). Tiles only (CC0).
- Lua hooks in vaults — code-in-data is bad.
- Original HTML prototype's structure — was a visual mockup, not a target
  architecture.
- Auto-running the editor or auto-screenshotting in normal sessions — the
  user opens Godot themselves. Screenshot mode is opt-in via
  `DEBUG_FLOOR.txt` marker, captured by the `/screenshot` skill.
