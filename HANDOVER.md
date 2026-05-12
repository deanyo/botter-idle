# Botter — Handover

Point-in-time snapshot of what's actually shipping. Updated as we go. The
durable rules and process live in `CLAUDE.md`; the roadmap and open work
items live in `TODO.md`.

Last refresh: 2026-05-12 (end of evening session).

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
4. Pick goal in priority order: nearest enemy → nearest interactable → stairs.
5. Mark room visited as bot passes through (incidental, no separate room navigation).

Room navigation was REMOVED — caused oscillation between rival room targets.
Bot relies on incidental room visits during enemy/interactable/stairs traversal.

The bot reads the full grid for pathing (autoexplore-style); the player
watches through fog. That's intentional and matches DCSS's autoexplore.

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
- **Sprite FX**: per-actor Tween-driven squash/stretch — attack lunge, hit
  squish + flash, death spin/shrink, kneel-on-interact, loot pop.
- **Run journal**: per-floor narrative log (DCSS-morgue style) shown on run
  report alongside loot recovered/lost.

## Fog of war + dynamic lighting

Radius-based reveal (FogSystem `REVEAL_RADIUS=7`) plus `PointLight2D`-driven
lighting from world sources (altars, fountains, lava, legendary loot, lit
chests). Tile sprites have a 3-state visibility system (UNSEEN/EXPLORED/VISIBLE)
applied as per-cell modulate.

**Walls don't yet block vision** — that's the line-of-sight upgrade in TODO.

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

- **HP scaling looks buggy** — user flagged. The `[floor] hp_lost=` field in
  the new logging was added to help diagnose. Most floors show `hp_lost=0`
  even with 20+ enemies, which doesn't match expectation.
- Common gear may be too strong vs floor-1 enemies (Rusty Dagger +16 ATK).
- Vault frequency may need re-tuning — currently ~25% chance of zero float
  vaults, ~40% chance of two on floors 4+.
- 24 affix stats not yet wired into combat (crit, lifesteal, gold find,
  dodge, regen, thorns, etc).
