# Botter — TODO

Roadmap and deferred items. The "what works today" lives in `HANDOVER.md`;
the durable rules in `CLAUDE.md`. Update this file when committing.

---

## Gameplay loop overhaul — DONE 2026-05-15

All 10 beats from `docs/gameplay-loop-plan.md` implemented + several
extras. Latest snapshot lives in `HANDOVER.md` "Gameplay loop overhaul"
section. 5 commits ahead of `origin/main`:

```
52a9ab5 Stricter progression + per-deploy run modifiers
70aff1b Death retreat + gear bloat + bot upgrades + offline progress
5fad84a Smooth shader-driven fog of war
6ead4a6 UI rework — Outpost (was Garage), shared paperdoll, rarity decor
b88eb83 Gameplay loop overhaul — 6 affixes + branch tiers + idle-friendly inventory
```

Beat status:
- ✅ **Beat 1 — Affix simplification** (6 affixes — added Haste vs the
  doc's 5; crit + haste wired in `actor.gd`; no save migration, dev saves
  nuked instead)
- ✅ **Beat 2 — Branch tier data** (`biomes.json` tagged tier 1-5 +
  cr_recommended; `constants.gd` FLOORS_PER_RUN 10→6, MINIBOSS_FLOORS [3],
  TIER_SCALE [1.0, 1.4, 2.0, 3.2, 5.0])
- ✅ **Beat 3 — Save state expansion** (unlocked_branches, bosses_killed,
  max_revives, loot_filter, inventory_cap, last_branch, branch_modifiers,
  bot_upgrades, shards, last_seen_timestamp)
- ✅ **Beat 4 — Branch-aware run plan** (BiomeData.roll_run_plan accepts
  branch_id + floors; runtime tier scaling at spawn; branch boss = strongest
  pool member; boss_killed signal)
- ✅ **Beat 5 — Death retreat with revives stat** (max_revives default 3;
  HP=0 → revive at floor 1 of same branch; lava death routed through
  retreat too)
- ✅ **Beat 6 — Gear bloat** (loot_filter + inventory_cap + auto-salvage,
  Outpost UI surfaced)
- ✅ **Beat 7 — Bot upgrades** (data/bot_upgrades.json with 6 upgrades,
  Outpost upgrades panel, stats fold into bot.recompute_stats)
- ✅ **Beat 8 — Branch picker UI** (Outpost tier-grouped picker, locked
  branches dimmed, modifier strip per branch)
- ✅ **Beat 9 — Offline progress** (last_seen_timestamp on save,
  OfflineProgress.apply on launch, "While You Were Away" AcceptDialog)
- ⬜ **Beat 10 — Run report unlock prominence** — boss kill writes save
  + emits boss_killed signal, but the run report doesn't yet visually
  highlight first-clear unlocks above the loot list. The unlock IS
  surfaced via `[unlock]` print + the next Outpost visit shows new
  branches available; just no "BRANCH UNLOCKED" banner in the report.
  ~30m if/when desired.

Bonus beats shipped beyond the doc:
- **Smooth shader-driven fog of war** (replaces the cell-aligned Bresenham
  FoV). See HANDOVER.
- **Shared paperdoll renderer** — one rig builder used by in-game bot,
  HUD, Outpost, and main menu. Removes the "every weapon = battleaxe"
  test-mode hack and the hardcoded mummy armor.
- **Per-deploy run modifiers** (8 modifiers, Outpost picker shows the
  rolled set). User-requested addition to encourage backtracking.
- **Stricter unlock progression** — clearing every tier-N boss to open
  tier-(N+1), instead of the doc's "any 1 boss". User call.
- **Per-tier rarity baseline** in `_roll_rarity` so high-tier branches
  naturally drop better loot.
- **UI consistency pass** — palette/font unification, rarity outline
  → square border + inset halo, unified item tooltips everywhere.
- **Stuck-detection rewrite** — frame-counts → delta-time, carve-outs
  for combat / interaction / pathing. Bot no longer teleports mid-boss-
  fight on 120Hz displays.

Remaining gameplay-loop-shaped work:

- ⬜ **Run report unlock prominence** (Beat 10) — show "TIER N CLEARED —
  Tier (N+1) unlocked!" above the loot list when applicable.
- ⬜ **Sword item plan** (`docs/items-swords-plan.md`) — full re-roster of
  1H swords with `flavor_tags`, `drop_weights`, lore. Pending the same
  pass for axes/maces/staves/armor and a rebuild of the sprite-pack to
  match.
- ⬜ **Bespoke per-branch bosses** — currently boss = strongest pool
  member. Doc's Hydra/Lich/Vault Warden/etc would need 24+ new enemies
  in `enemies.json` (HP/ATK/sprite/etc). Add a `boss_id` field on the
  biome to override the pool-pick; ship the 7 endgame uniques first
  (per the items plan).

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

## Combat pass — partly shipped 2026-05-15

- ✅ **Affix expansion** — collapsed to 6 affixes, all 6 wired
  (Strength/Stamina/Agility/Regen/Crit/Haste). The old 30-affix system
  with 24 decorative stats is gone.
- ✅ **Real paper-doll** — `paperdoll_renderer.gd` builds layered Sprite2D
  rig from equipped weapon/armor/helm/shield/boots. Used in-game and
  on every UI surface.
- ⬜ **Enemy attack effects** — currently bot has weapon overlay + swing
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

This is the only Botter-unique creative work. Big chunks shipped 2026-05-15:

- ⬜ Configurable bot priorities (started — proximity-ranked behavior).
  Bot AI has aggro range cap (8 cells), current-room loot priority,
  low-HP retreat. Exposing these as Outpost sliders is still pending.
- ✅ Run-config: branch picker in Outpost. Per-deploy modifier rolls
  offer flavour variation. Behavioral preferences (greed vs caution,
  melee vs ranged) still pending.
- ✅ Idle reward curves — offline progress capped at 1h, "While You
  Were Away" summary on launch.
- ⬜ Meta-progression — `bot_upgrades` shipped (gold sink, permanent).
  Prestige (`shards`) field reserved in save state; no implementation
  yet.
- ✅ Visual presentation (smooth fog, paperdoll, rarity decor, segmented
  inventory).

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
- ✅ **Player paper-doll** — `scripts/paperdoll_renderer.gd` builds layered
  Sprite2D rig from `equipped`. Used in-game + every UI surface. Asset
  set added under `project/assets/tiles/player/` (body/, helm/, shield/,
  boots/, weapons/). 975+ sprites still available for variety expansion.
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
