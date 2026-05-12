# Botter — Project Notes for Claude

**Reframe (locked in mid-development):** Botter is **DCSS Reimagined as an Idle Game.** Not "inspired by DCSS" — actually *ported from* DCSS, with the player replaced by a configurable autonomous bot.

Mental model:

| Layer | Source |
|---|---|
| Dungeon generation algorithms | **Port from DCSS source** (GPL: read & rewrite in GDScript, never copy code) |
| Branch structure & depth | **DCSS's 15+ branches** (D:1-15 main, Lair, Vaults, Snake, Spider, Swamp, Shoals, Slime, Crypt, Tomb, Forge, Glacier, Forest, Hive, Pandemonium, Abyss, Zot, etc.) |
| Enemy data (HP/ATK/DEF/speed) | **DCSS's data files** — decades-balanced, already respect number ceilings |
| Item data + affixes (egos) | **DCSS's data files** — `unrand`/`artefact`/`ego` systems |
| Tile rendering | DCSS sprites (CC0 — already use, fine to ship) |
| Vault library | **DCSS .des files** — port format, populate from DCSS examples |
| **Bot AI** | **Botter-original. This is the actual game.** |
| Run loop / progression / rewards | Botter-original — idle reward curves, prestige, etc. |
| UI | Botter-original |

**Why this matters**: stop reinventing dungeon generation. DCSS's source has 2000+ lines of polished, decades-tuned algorithms (trail+rooms, delve caves, octa rooms, chequerboard, river/lake, Worley layouts) that we should port directly. Same with monsters and items — the data is already balanced. **The actual creative work is the bot + idle loop**, not yet another procgen.

## HOW TO PORT DCSS CODE — process rules

These rules are non-negotiable. Bake them into every port session.

### Legal / licence
- DCSS source is **GPLv2+**. We can NOT distribute it or include any of its code.
- **Read the algorithm in C++. Describe it in plain English. Rewrite from the description in GDScript.** Don't even keep the C++ open while typing GDScript — there's a temptation to translate line-by-line, which is a derivative work. Translate *concepts*, not lines.
- Variable names: DON'T mirror DCSS's. Their `_make_trail` is fine to reuse as a function name (function names are utilitarian, not creative authorship), but `xs xr ys yr corrlength intersect_chance no_corr` should become readable GDScript like `start_x_min start_x_range corridor_max_length intersect_chance segment_count`.
- Tile sprites are **CC0** — different licence — fine to ship freely, with the attribution we already include.
- **Vault `.des` files**: format is data, not code. We port the format (glyph DSL → JSON) and can write our OWN vaults using DCSS's data structures. Whether to populate from DCSS's actual `.des` library is murkier — for now we hand-author.

### Per-port workflow

When porting a DCSS algorithm:

1. **Read the function and 1-2 layers of helpers it calls.** Don't go deeper unless needed.
2. **Write a 2-paragraph plain-English description** of what it does to the grid. Example: "Trail picks a random start cell, then iteratively picks a cardinal direction biased away from map edges, walks 2-15 cells in that direction, and either stops or carves another segment, repeating up to 30-200 times. Carved cells become floor."
3. **Rewrite from that description in GDScript**, using our coordinate system (Vector2i), our tile constants (`C.T_FLOOR`, `C.T_WALL`), our RNG (passed in), and our map dimensions. Don't open the .cc file again until you hit a question.
4. **Translate constants**: DCSS uses 80×70 maps. We use 60×60. Scale absolute-coordinate constants proportionally. Bounds checks use our `MAP_W`/`MAP_H`.
5. **Drop branch-specific edge cases.** DCSS has `if (player_in_branch(BRANCH_GEHENNA))` etc — we move those to biome.json toggles, not C++ branches.
6. **Use Godot built-ins** where they exist: `AStarGrid2D` for pathfinding (replaces DCSS's `dgn_join_the_dots_pathfind`), `RandomNumberGenerator` (replaces `random2`/`coinflip`), `Rect2i` (replaces `dgn_region`).
7. **One file per source file.** `dgn-layouts.cc` → `scripts/dcss_layouts.gd`. Easy to grep, easy to update later.
8. **Add a comment at the top** of each ported file: `# Algorithms ported in spirit from DCSS source/dgn-layouts.cc — see CLAUDE.md "HOW TO PORT" rules`.

### What "data we can use" means

- Tile sprite paths: yes, ship them.
- Tile filenames in DCSS .des format: data, fine.
- Function names and broad algorithm shapes: utilitarian, fine to reuse names like `make_trail`, `delve`, `octa_room`.
- Random distributions like "1 in 16 chance, big_room kicks in if level > 1": these are tuning numbers, fine to use directly.
- Their .yaml monster stat tables and item ego enum: data, fine to transcribe.
- C++ literal code, even small chunks: NO, rewrite from description.

Player fantasy: **being an MMO botter / following someone's autoplay run.** Configure your bot, deploy it, watch it explore, gear it better, redeploy. Background-friendly. Mobile-first.

The full game-design doc lives in conversation history (GDD v0.1). This file captures the things you can't re-derive by reading code: stack, conventions, scope, and what NOT to do.

## Stack

- **Engine:** Godot 4.6.2-stable. User's binary at `/Applications/Godot.app/Contents/MacOS/Godot`.
- **Language:** GDScript only. No C# / GDExtension.
- **Target:** Mobile-first portrait orientation (540×960 viewport), but desktop is the dev target right now.
- **Tiles:** 32×32 DCSS sprites, CC0. Two source trees:
  - `dcss/` — full DCSS tilesheets (CC0 art only). Curated subset already copied into `project/assets/tiles/`.
  - `dcss-source/` — shallow clone of github.com/crawl/crawl (132 MB). **For research only — GPLv2+, never copy code.** Used by background agents to study DCSS procgen.
  - **Never reference `dcss/` or `dcss-source/` paths from project code** — only `project/assets/tiles/`.
- **Save/load:** Godot `FileAccess` + JSON, single slot. Save lives at `user://botter_save.json`.
- **Pathfinding:** `AStarGrid2D` (engine-native, fast). Set `diagonal_mode = DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES`. Don't mark every enemy solid every frame — agents oscillate in 1-tile corridors. See `scripts/pathfinding.gd`.
- **MCP:** `godot-mcp` (Coding-Solo, free) installed at project scope (`.mcp.json`). Lets Claude headlessly boot the project, capture errors, create scenes. **Project-scoped MCPs only prompt for trust at session START — restart the session if it doesn't appear.**

## Project layout

```
botter/
├── CLAUDE.md                  # this file
├── .mcp.json                  # project-scoped MCP config (godot-mcp)
├── .claude/settings.json      # project permissions
├── dcss/                      # raw DCSS tilesets (CC0 art). Source for asset curation, not shipped.
├── dcss-source/               # shallow clone of crawl/crawl (GPLv2+ — RESEARCH ONLY, never copy)
└── project/                   # the Godot project — open this dir in the Godot editor
    ├── project.godot
    ├── scenes/                # main.tscn, dungeon.tscn, garage.tscn, run_report.tscn
    ├── scripts/
    │   ├── constants.gd       # TILE_SIZE, tile enums, MAP_W/H, FLOORS_PER_RUN, BOSS_FLOOR
    │   ├── dungeon_generator.gd  # BSP rooms + L-corridors → grid + rooms + spawn + stairs
    │   ├── pathfinding.gd     # AStarGrid2D wrapper
    │   ├── map_renderer.gd    # places floor/wall/stair sprites from grid
    │   ├── actor.gd           # base for bot+enemy: HP, movement, attack, hp bar
    │   ├── bot.gd             # extends actor — XP/level, gold, gear stat application
    │   ├── enemy.gd           # extends actor — repath timer, aggro range
    │   ├── dungeon.gd         # the run loop: spawn enemies, tick AI, descend floors, end run
    │   ├── garage.gd          # gear swap UI, deploy button
    │   ├── run_report.gd      # post-run summary
    │   ├── main.gd            # screen router (garage ↔ dungeon ↔ report)
    │   └── save_state.gd      # JSON save/load helpers
    ├── data/                  # enemies.json (10 enemies, Minotaur boss on floor 10)
    │                          # items.json (75 items: 5 slots × 5 rarities × 3 variants)
    └── assets/tiles/{floor,wall,player,enemies,items,gateways,gui}/
```

## MVP scope (what we're building now)

Watch a bot traverse a multi-floor DCSS-style dungeon, plunder loot, fight enemies, eventually die OR clear a final boss. Then swap gear and redeploy. That's the loop.

Concretely:
1. BSP dungeon generator → multi-floor descent with stairs.
2. Bot AI: pathfind to nearest enemy → attack → loot → next room → next floor.
3. Combat: HP/ATK/DEF, melee only for v1.
4. Loot drops, auto-pickup, gear slots (weapon, armor, helm, boots, shield).
5. Death/victory → run report → gear-swap UI → redeploy button.

Out of scope for MVP: skills/rotations, action-priority configuration, offline progress, push notifications, multiple dungeon tiers (one tier with N floors is enough), monetization, cosmetics.

## Conventions

- **Number ceiling (HARD design rule):** Stats stay in tight ranges to avoid idle-game number creep.
  - End-game bot: ~**1500 HP**, ~**300 ATK**, ~**100 DEF**. Hits should peak around **300–400 damage**.
  - End-game enemies sit in similar bands. No 50k-HP bosses, no 9999-damage crits.
  - Progression scales **gear quality** (white→red rarity adds ~+5% per tier) and **floor depth** (each floor multiplies enemy stats by ~1.10–1.12), NOT raw stat inflation.
  - When tempted to "make a number bigger," instead make the *encounter* harder: more enemies, smarter positioning, mechanics. Damage variance and timing matter more than peak numbers.
- **Tile size constant:** `const TILE_SIZE := 32` — define once, reference everywhere. Don't hardcode 32.
- **Coordinates:** dungeon grid coords are `Vector2i` (cell), world coords are `Vector2` (pixels). Convert at the boundary, never mix.
- **Data-driven:** enemies, items, gear stats live in JSON under `data/`. Code reads, doesn't hardcode stat tables.
- **No comments unless the WHY is non-obvious.** Don't narrate the code.
- **Inclusive language:** master/slave/whitelist/blacklist → primary/replica/allowlist/denylist (per global rules).
- **Attribution:** credits screen must read: *"Part of the graphic tiles used in this program are from the public domain roguelike tileset RLTiles. http://rltiles.sf.net"* and credit DCSS contributors (CC0).

## What NOT to do

- Don't pull in DCSS *source code* — it's GPLv2+ and would force the whole game open-source. Tiles only (CC0). Game logic is fresh GDScript.
- Don't add features beyond MVP (skills system, action priorities, offline progress, etc.) until the core loop is fun.
- Don't reference the original HTML prototype's structure — it was a visual mockup, not a target architecture. The user explicitly said they're not married to it.
- Don't render screenshots or run the editor automatically. The user opens Godot themselves.

## Status as of last session

**Core gameplay loop is fully working** end-to-end:

- Garage → Deploy → 10-floor dungeon → Run report → back to Garage with new loot → equip → redeploy
- Boss on floor 10 (Minotaur), mini-bosses on floors 5/10/15/20/25 (1.8× HP, 1.4× ATK, larger sprite, red tint, "Greater [Enemy]" name)
- Bot AI: proximity-ranked behavior. Adjacent enemy → attack; enemy within 5 tiles → engage; otherwise nearest of {enemy, interactable, unvisited room} wins; stairs are last fallback. Picks up interactables when standing on them.
- **Visible loot system**: Items physically drop on floor with rarity-coded glow + idle wobble. Bot kneels (squish + lean) to pick up. Rarity-scaled pickup duration (common 0.35s → legendary 0.8s).
- **Affix system**: 30 affixes (Sharp, Vicious, of Vigor, of Fortune, etc.) Roll 0-4 per item by rarity. Items get "Sharp Iron Sword of Vigor"-style names. 5 stats wired to combat (hp/atk/def/hp_pct/atk_pct); 24 others parse but don't affect gameplay yet.
- **Interactables**: chests (burst items in arcs on open), fountains (heal 40-60% HP, bot only stops if injured), altars (7 god-themed run-ephemeral blessings — Trog/Okawaru/Zin/Elyvilon/Vehumet/Kikubaaqudgha/Sif Muna)
- **Vault stamping**: 4 starter vaults (`fountain_alcove`, `statue_alley`, `goblin_warband`, `treasure_cache`) loaded from `data/vaults/*.json`, stamped onto BSP rooms with 1-cell padding. Statues block pathfinding. ~75% of floors get 1 vault, ~10% get 2, ~25% get 0.
- **Sprite FX**: per-actor Tween-driven squash/stretch — attack lunge, hit squish + flash, death spin/shrink, kneel-on-interact, loot pop
- **Run journal**: per-floor narrative log (DCSS-morgue style) shown on run report alongside loot recovered/lost

## Open balance knobs (review during playtest)

- Common gear is too strong vs floor-1 enemies (Rusty Dagger +16 ATK). Either trim common-tier item stats or buff enemy floor scaling.
- Vault frequency may need further tuning — currently ~75% of floors have 1 vault. User flagged "a bit too common" before the dial-back; check.
- The 24 affix stats not yet wired into combat (crit, lifesteal-on-non-altar, gold find, dodge, regen, thorns, etc.). Easy retrofits when needed.
- **`basic_level` floors render as one giant square room far too often.** User flag (2026-05-11): "the square rooms as an entire floor of the dungeon are way too common." Suspected cause is some combination of `_big_room`, the trail-then-rooms approach merging into a single open area, or `_make_random_rooms` placing one dominant rectangle. We need data — not a guess — before fixing. Step one is automated detection (see "Quality / regression telemetry" below); step two is comparing against DCSS's actual `dgn-layouts.cc` parameters to see what we drifted from.

## Quality / regression telemetry — NEXT INFRASTRUCTURE PRIORITY

We have auto-grind running headless and emitting `[grind]` logs. That's the loop foundation. Next step is making it **catch bad floors automatically** so visual / structural regressions don't slip through manual playtests.

What "automated logging, debug, testing" should add (in order):

1. **Floor structure metrics** — at the end of `dungeon_generator.generate()`, compute and log per-floor:
   - `floor_count` (already tracked internally), `room_count`, `largest_room_area`, `largest_room_pct` (largest room ÷ total floor cells), `corridor_cells` (floor cells not in any room), `open_ratio` (max single open rectangle ÷ map area).
   - Emit one `[floor-metrics]` log line per build. Cheap, structured, greppable.
2. **Bad-floor flagging** — alongside metrics, flag patterns we *know* look bad:
   - `largest_room_pct > 0.6` → "single-dominant-room" floor (this is the current complaint).
   - `room_count == 1` on `basic` layout → degenerate.
   - `corridor_cells / floor_count < 0.05` on `basic` → no real corridors, just one big space.
   - Each flag emits `[bad-floor]` with the layout, biome, seed, and which rule fired.
3. **Snapshot on flag** — when a `[bad-floor]` rule fires during auto-grind, dump the ASCII grid to `user://bad_floor_<seed>.txt` (same format as the existing `_dump_stall_snapshot`). We can then visually audit a batch of bad floors offline.
4. **Aggregate report at run end** — `main.gd`'s auto-grind exit path should print a summary: "5 runs, 50 floors built, 12 flagged bad (24%)." Threshold for acceptable is something like <5%; anything above means generator regression.
5. **Generator unit-style harness** — a headless script that calls `DungeonGenerator.generate()` 200× per layout, runs the metrics + flags, and prints the bad-floor rate per layout. Run before merging generator changes. No Godot UI needed.
6. **Bot-behavior metrics** — alongside floor metrics, log per-floor: `ticks_to_clear`, `rooms_visited / room_count`, `loot_picked_up`, `stalls_recovered`. Surfaces "bot beelined to stairs and skipped 80% of the floor" without needing eyes on it.

The point is to stop relying on screenshots + "it looks weird" feedback. Bake the regression check into the auto-grind loop so the next time floor shapes drift, the log calls it out.

## DCSS branches — full roster planned

User decision (2026-05-12): port the full DCSS branch family, not just D:1-15. Each branch is a biome+layout+enemy pool+vault library with its own identity. http://crawl.chaosforge.org/Dungeon_branches lists 17+ branches; we'll port them in clusters.

**Run shape** = "Both" — default to a *linear branch chain* now (10-floor run hops between branches DCSS-style), and later add a Garage *branch picker* for meta-progression once a branch is content-complete.

**Linear chain example (placeholder, to be tuned):**
```
D:1-3  →  Lair:1-2  →  D:4-5  →  Vaults:1  →  Crypt:1  →  Forge:1  →  Glacier:1  →  D:9-10 (Zot final)
```
Each hop swaps the biome, enemy pool, layout id, vault tag, and ambient palette. Implemented in `BiomeData.roll_run_plan` (already exists; needs a richer table).

**Cluster priorities (in order):**
1. **Stone — Vaults / Crypt / Tomb** (FIRST). Reason: best showcase for the new orient-bound vault pipeline we're building right now. Vaults' identity *is* heavy vault stamping; Crypt and Tomb both use vault-driven layouts. Lets us prove the pipeline rewrite delivers visual variety without inventing new generators.
2. **Nature — Lair / Swamp / Snake / Shoals**. Has its own DCSS generators (`dgn-shoals.cc`, `dgn-swamp.cc`) to port. Big visual variety win once stone cluster is in.
3. **Elemental — Forge / Glacier**. Adds lava and ice as gameplay terrain (slow, damage-on-step). Smaller cluster, fast to ship after Nature lands.
4. **Weird — Slime / Hive / Spider / Pan / Abyss**. Most mechanically unusual; tackle last. Pan/Abyss may need entirely separate generators (procedurally morphing geometry).

**Per-branch checklist** (apply to each branch as we ship):
- Add a biome entry in `data/biomes.json` with floor/wall palette, enemy_pool, vault_themes, layout id, ambient_decor, darkness, run-plan position weight.
- Author 4-8 vaults specifically tagged for that branch's `themes`. Mix orients (1-2 encompass for branch finales, several float, a couple north/south oriented).
- Verify enemy pool — DCSS branches have signature monsters (Lair: jackals/blink frogs, Crypt: skeletons/wraiths, Forge: imps/red dragons, etc.). May need to add 5-10 monsters per branch from `monster/*` art library.
- Smoke-grind 50 floors of that branch via the auto-grind harness; check the floor-metrics log for any new `[bad-floor]` patterns.

**Where this changes existing files:**
- `BiomeData` / `data/biomes.json` — biome roster grows from 18 → ~25.
- `data/enemies.json` — likely doubles (10 enemies per new branch theme × ~10 themes that don't have full pools).
- `data/vaults/` — vault count grows from 4 → 30+ over the cluster ports.
- `dcss_layouts.gd` — port `dgn-shoals.cc`, `dgn-swamp.cc` as new layouts (`shoals`, `swamp`); Pan/Abyss get their own. Slime gets a "pools" layout.
- `dungeon_generator.gd` — add layout dispatch for the new ids.

## DCSS-faithful generation pipeline — IN PROGRESS

User asked for "do it how DCSS does it." Research pass complete (see git log / agent output 2026-05-12). The canonical DCSS order, ported to our terms:

1. **Encompass-vault short-circuit.** Before anything else, ask the vault library for an `ORIENT: encompass` vault matching the current biome+depth. If found, stamp it at (0,0) and skip everything below — the level IS the vault.
2. **Layout.** No encompass? Pick a layout vault (tagged `"layout"`) OR run a procedural layout (`basic_level`, `delve`, etc). Procedural layouts carve floor/wall AND **place doors during room creation** (we currently don't — fix).
3. **Connectivity flag on.** From here forward every stamp must preserve connectivity; verify after.
4. **Branch-entry vaults.** Stamp branch-entrance vaults (we don't have branches yet but the slot is reserved).
5. **Chance vaults.** Stamp `tags: chance` vaults gated by per-vault probability tables.
6. **Orient-bound minivaults.** Stamp `ORIENT: north/south/east/west/centre` vaults at the corresponding edges — these need an *edge picker* in the stamper, which we lack.
7. **Float vaults.** Stamp `ORIENT: float` vaults inside detected open regions (this is what our current stamper does — but only this).
8. **Post-vault fixup.** Slime stair-spacing, ruination, etc.
9. **Stairs / monsters / items.** Vault-placed stairs (`>`/`<` glyphs marked MMT_VAULT) win; random stairs avoid vault cells. Monsters respect `KMONS` per-glyph; items respect `KITEM`. Vaults tagged `no_monster_gen` don't get random spawns inside them.
10. **Connectivity verification.** BFS from stairs; if any region disconnected, regen the whole level.

**.des concepts we're missing in our JSON vault format** (port these into our parser):

- `ORIENT` (encompass / north / south / east / west / centre / float — defaults to float).
- `TAGS` array: `allow_dup`, `no_monster_gen`, `no_item_gen`, `transparent`, `decor`, `chance`, `extra`, `no_pool_fixup`, plus biome tags.
- `DEPTH` ranges (`D:2-7`, `Lair:1-3`, `!Zot`).
- `CHANCE` table per branch (`20% (D:2)`, fallback `0`).
- `WEIGHT` for selection precedence.
- `KFEAT` per-glyph terrain override (`KFEAT: C = altar_vehumet`).
- `KMONS` per-glyph monster override.
- `KITEM` per-glyph item override.
- `SUBVAULT` glyph that expands to a referenced vault by name.
- Glyphs we should support beyond our current set: `X` (solid decor wall, doesn't merge with corridors), `m` (default monster spawn), `>`/`<` (vault-placed stairs).

**What our generator gets wrong today** (in priority order — fix these in this order):

1. **No encompass-vault short-circuit.** We always run a layout. Fix: add the early-return path.
2. **Doors aren't placed by the layout.** We carve corridors but never put doors in them. DCSS does it inside `_make_room`. Fix: add `_place_doors_in_corridors()` step into our basic-level carve.
3. **Vault stamper has no orient support.** Every vault is treated as float. Fix: add edge-picking for n/s/e/w and full-grid stamp for encompass.
4. **Minivault placement is too greedy.** No `allow_dup` enforcement, no DEPTH/CHANCE gating. Fix: parse those fields, enforce them in `VaultLibrary.candidates_for`.
5. **No KFEAT/KMONS/KITEM.** Vaults can't override terrain or per-glyph monster type. Fix: extend JSON schema, honor in stamper.
6. **Stairs placed after all vaults regardless.** Vault-placed stairs aren't honored. Fix: stamper writes T_STAIRS when it sees `>`/`<`, and the stair-finalize step skips floors that already have stairs.

**Sequencing**: do steps 1, 2, 3 first — they reorder the pipeline. Then 4, 5, 6 to enrich the data. Then expand the vault library substantially. The "one giant square room" complaint should disappear after step 1+3 because encompass vaults will start carrying interesting full-floor designs (DCSS Vaults:5, Lair-end, etc.) instead of every floor being a generic procedural carve.

## Line-of-sight fog of war — VISIBILITY UPGRADE

Current fog system is **radius-only**: bot has a circle of vision (FogSystem REVEAL_RADIUS=7, plus the shader-driven `fog_overlay.gd` painting darkness around point-light positions). Walls do NOT block vision. Standing in a corridor, the bot sees through walls into adjacent rooms as long as they're inside the circle. That's the bug to fix.

**Target behavior** (Project Zomboid / Monaco style):
- Vision is **cast**, not stamped. Rays from the bot stop at walls.
- Long corridors should reveal far down their length (a 20-tile corridor lit fully because nothing blocks LoS), but the rooms on either side of the corridor stay dark until the bot enters them.
- Light sources in the world cast their own LoS the same way: an altar in a room illuminates that room AND any visible corridor segments leading to it, but not through the room's far wall.
- "Seen but not currently visible" cells stay dimly rendered (already partially in place via FogSystem.ever_seen) — the new system layers *currently visible* on top of *ever seen*.

**Architecture (proposed):**

1. **Per-tile visibility state machine** with three values:
   - `UNSEEN` — fully black, never rendered.
   - `EXPLORED` — previously visible, currently out of LoS. Dim grey, no entities drawn.
   - `VISIBLE` — currently in LoS of bot OR a world light source. Full brightness, entities rendered.
   Stored as `Array[Array[int]]` indexed by cell, recomputed when bot moves to a new cell or a light source changes state.

2. **Visibility computation per source**:
   - Each "viewer" (bot + every active world light) runs a shadowcasting pass.
   - **Recursive shadowcasting** is the standard roguelike algorithm — symmetric, cheap (~O(visible cells)), produces the corridor-reveal effect we want. Implementation: 8 octants, scan rows outward, narrow the angle range when a wall is hit. Plenty of public-domain GDScript references exist (we read, describe, rewrite — same DCSS porting rules).
   - Source's max range = its light radius in tiles. Bot's range = REVEAL_RADIUS (7).
   - Output: a Set of cells visible from that source.
   - Union all sets → the per-tile VISIBLE map.

3. **Performance budget**:
   - Recompute only when bot's `cell` changes, OR a world light is added/removed/extinguished. Not every frame.
   - 30 light sources × ~150 cells/source ≈ 4500 raycasts on movement. Easily <1ms in GDScript with a tight loop. Cache the previous bot cell and skip work if unchanged.
   - If we ever push it harder: precompute a static "wall blocks LoS" grid once per floor (already have `grid` — walls = T_WALL), keep the visible-set recomputation per light.

4. **Renderer integration** (`map_renderer.gd`):
   - Tile sprites get a per-cell modulate based on visibility state. UNSEEN → modulate.a = 0. EXPLORED → modulate (0.4, 0.4, 0.5, 0.6) (cool desaturated dim). VISIBLE → modulate (1, 1, 1, 1) full color.
   - Entities (enemies, loot drops, interactables) ONLY render when their cell is VISIBLE. Currently they render on EXPLORED too — that's wrong (you'd see enemies through walls in remembered rooms).

5. **Shader adaptation** (`fog_overlay.gdshader`):
   - The shader currently paints darkness over the world based on light positions/radii ignoring walls. We keep it for the warm light-color tinting effect, but the **authoritative visibility** comes from the per-tile mask, not the shader.
   - Option A: shader reads a `visibility_mask` texture (a 60×60 sampler updated each move). Octant-correct.
   - Option B: keep the shader as-is for color/glow, and add a *separate* darkening overlay driven by the per-tile mask (additive black sprite layer on EXPLORED/UNSEEN tiles). Simpler, no shader rewrite, slightly less polished.
   - **Pick B for v1** — ship correctness now, swap to A later if performance allows shader-driven gradients.

6. **Edge cases that always bite shadowcasting implementations**:
   - **Diagonal walls** — without a tweak, the bot can see through a corner formed by two walls meeting at a point. Standard fix: when both adjacent cardinals are walls, the diagonal is also blocked. Code that in or accept the bleed.
   - **Symmetry** — if A sees B, B should see A. Recursive shadowcasting is symmetric by construction; some other approaches aren't.
   - **Off-by-one at the source cell** — source's own cell is always visible, regardless of whether it's a wall (shouldn't happen but guard for it).
   - **Diagonal moves through doorways** — Godot's AStarGrid2D is set to `DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES` so the pathing won't squeeze through a corner — match the LoS rule to that for consistency.

**Gameplay impact** (why this matters beyond visuals):
- Corridors become tactically interesting — bot turning a corner reveals a room, briefly. We can use this for ambush mechanics later.
- Lit altars / fountains glimmer through doorways before bot enters — rewards exploration, gives the corridor "see something cool ahead" feel that DCSS does so well.
- Cave layouts (delve) gain enormous variety — the curving tunnels reveal piecewise instead of in big circles.

**Sequencing**: implement after the regression-telemetry pass — we want metrics in place to confirm we're not making the bot dumber (e.g., bot's pathing assumes it knows the full floor, but if visibility is now LoS-gated, do we want bot AI to respect fog or cheat? **Decision: bot AI still knows the full grid for pathing, only the rendering is fogged.** That's how DCSS works — autoexplore knows the map; you the player only see what your character sees. Same applies here: the bot reads the truth, the player watches through the fog.)

## Debug-jump (fast biome/vault validation)

To launch the game directly into a specific biome with optional forced vault:

1. Write `<biome_id>[,<vault_name>][,<floor_num>]` (e.g. `lair`, `vaults,twin_chambers`, `crypt,,7`) to `/Users/dyo/Library/Application Support/Godot/app_userdata/Botter/DEBUG_FLOOR.txt`
2. Launch project. Skips garage; spawns floor 1 (or given floor_num) directly in that biome. If `vault_name` is set, that vault is force-stamped (encompass roll bypassed).
3. After validation: `rm "$HOME/Library/Application Support/Godot/app_userdata/Botter/DEBUG_FLOOR.txt"` to return to normal flow.

Implementation in `scripts/debug_jump.gd` (static singleton). Used to validate biomes/vaults in ~8 seconds instead of 5-min auto-grind cycles.

## Auto-grind telemetry (working as of last session)

Headless self-iteration loop is operational. To trigger:

1. Write `<speed>,<max_runs>` (e.g. `8,2`) to `/Users/dyo/Library/Application Support/Godot/app_userdata/Botter/AUTO_GRIND.txt`
2. Launch project (via godot-mcp `run_project` or normal godot launcher)
3. Bot auto-deploys at N× speed, plays through `max_runs` complete runs, prints structured logs (`[grind]` lines) to stdout
4. After all runs, calls `get_tree().quit()` and exits the process

Logs cover: per-floor (biome, layout, room count, enemy count), per-run (victory/floor/level/gold/elapsed), and tick-level diagnostics when bot is stuck. Use this to debug AI/generator issues without needing manual playtest.

To delete the marker (back to normal mode): `rm "$HOME/Library/Application Support/Godot/app_userdata/Botter/AUTO_GRIND.txt"`

Implementation in `scripts/main.gd` (looks for marker on `_ready`).

## Bot AI (working as of last session)

Sticky-target priority engine:
1. Adjacent live enemy → attack (lock, don't switch)
2. Has unfinished path? → keep walking, don't repick target
3. Target invalid (enemy died, interactable consumed) → drop path, repick
4. Pick goal in priority order: nearest enemy → nearest interactable → stairs
5. Mark room visited as bot passes through (incidental, no separate room navigation)

Room navigation was REMOVED — caused oscillation between rival room targets. Bot relies on incidental room visits during enemy/interactable/stairs traversal.

Generator regeneration: if a layout produces < 200 floor cells, regenerate (up to 5 attempts). Prevents tiny degenerate dungeons.

## PIVOT (latest session): "DCSS Reimagined" approach

Stop hand-rolling generators/data. Port DCSS's. The work now is:

### Phase A — Port DCSS algorithms
Read each DCSS source file in `dcss-source/crawl-ref/source/`, rewrite in GDScript. Files in priority order:

1. **dgn-layouts.cc** — `dgn_build_basic_level` (the canonical D:1-15 generator). Trail-then-rooms approach: 3 random-walk corridors connected, then random rectangle rooms scattered, then door placement, then `_builder_extras`.
   - Subroutines: `_make_trail`, `_make_random_rooms`, `_make_room`, `_octa_room` (diamond-shaped rooms), `_big_room`, `_diamond_rooms` (places water/lava blob obstacles), `_chequerboard`, `_box_room` (nested wall frames), `_build_river`, `_build_lake`.

2. **dgn-delve.cc** — the `delve()` cave generator. Far better than vanilla cellular automata. Tunable `(ngb_min, ngb_max, connchance, cellnum)` produces winding tunnels, organic caverns, or dense networks.

3. **dgn-proclayouts.cc** — Worley/Perlin-based layouts. `RiverLayout` (curving rivers via Worley boundaries), `ColumnLayout` (regular pillar grids), `DiamondLayout` (tile-grid of diamond cells), `WastesLayout`. These are stateless `(x,y) → tile` functions.

4. **dgn-irregular-box.cc** — irregular non-rectangular rooms.

5. **dgn-shoals.cc** / **dgn-swamp.cc** — branch-specific generators (we want these for actual Shoals/Swamp biome experience).

6. **mapdef.cc** + `dat/des/*.des` — vault library. Port DSL (already partially done) and load real DCSS vault definitions.

### Phase B — Port DCSS data tables
- **enemies.json** (already exists, partial). Replace with DCSS-derived stats from their `mon-data.h`. Their values are decades-tuned and respect number ceilings.
- **items.json** + affixes — port from DCSS item definitions, ego system. We currently have ~30 hand-rolled affixes; their `ego` enum has more, balanced.
- **biomes.json** → become **branches.json**. One entry per real DCSS branch with its actual generator id, enemy pool, vault tags, ambient features.

### Phase C — Bot AI + idle loop (the actual game)
This is the only Botter-unique creative work:
- Configurable bot priorities (already started)
- Run-config: which branches to attempt, gear loadout, behavioral preferences (greed vs caution, melee vs ranged)
- Idle reward curves (offline progress, time-gated rewards)
- Meta-progression (prestige, permanent unlocks, gear stash)
- Visual presentation (we've done a lot here — fog, lighting, sprite FX)

### Process rule (locked from this session forward)

**When implementing a generator/data system, FIRST read the corresponding DCSS source file or .des/.yaml in dcss-source/. Don't invent. Port.**

DCSS code is GPLv2. We *describe* algorithms in plain English, then *rewrite* in GDScript. Never copy a line of C++. Tile sprites are CC0 (different licence); fine to ship.

## DEPRECATED — old "Dungeon Pass" plan

The 5-stage pass below was authored before the reframe. Kept for context but most of it is moot now — DCSS-port supersedes it. Anything still relevant (lighting, decor scatter, room types) can live as polish on top of ported generators.

## DUNGEON PASS — the next major project

**Goal**: transform "ugly brown soup, every floor identical" into "varied, beautiful, interesting" dungeons. The brown-on-brown look is the #1 visual problem. Currently we use 1 floor texture and 1 wall texture across all 10 floors despite the catalog containing 1000+ floor/wall tiles.

**Why this matters**: per the user — "for this game to work, it needs to be visually appealing. The dungeons and watching your guy move around and explore is the main draw other than making a build." Visual quality is core to the value proposition, not polish. Treat it accordingly.

The plan is **6 stages**, sequenced to ship visual transformation early then deepen. Each stage is intended to be playtested before the next. **Order is locked**: tile pass first (Stage 1), then layouts/vaults/rooms (Stages 2-4) for spatial variety, then decorative + lighting passes (Stages 5-6) for the high-polish reveal.

### Stage 1: Biome palette system (~6h) — START HERE NEXT

Build `data/biomes.json` with all **18 biomes** from `tile_catalog.json` palette recipes:
`dungeon, dungeon_dark, mines, lair, forest, swamp, snake, shoals, orc, vaults, crypt, tomb, forge, glacier, slime, hive, labyrinth, abyss, zot, pandemonium`

Per biome, define:
- `floor_tiles: [paths]` (3-6 variants for weighted random)
- `wall_tiles: [paths]` (3-5 variants)
- `modulate: Color` for ambient `CanvasModulate`
- `enemy_pool: [enemy_ids]` filter from `enemies.json`
- `vault_themes: [...]` for vault filter
- `display_name` for run journal
- `floor_range: [min, max]` for biome eligibility per run-floor

Tasks:
1. Copy ~80 new tiles from `dcss/Dungeon Crawl Stone Soup Full/dungeon/floor/` and `wall/` per biome's recipe into `assets/tiles/floor/biome_X/` and `assets/tiles/wall/biome_X/` subdirs. Reimport.
2. Write `biomes.json` with all 18 biomes.
3. Update `MapRenderer.render()` to take a biome dict, pick floor/wall tile per cell with weighted random (uniform for v1, can add Perlin-coherent later).
4. Add `Dungeon` node-level `CanvasModulate` for ambient tinting.
5. Generate per-run "biome plan" at deploy time: 10-floor list of biome assignments. v1 uses fixed mapping (`1-2 Dungeon, 3 Mines, 4-5 Lair, 6 Swamp, 7-8 Crypt, 9 Vaults, 10 Zot`); make it data-driven so we can reshuffle.
6. Filter `_spawn_enemies()` by biome's `enemy_pool`.
7. Pass biome to `VaultLibrary.candidates_for(theme, floor)` so vault selection respects biome.
8. Run journal entries display biome name (`Floor 4 — Lair`).

**Validation**: 1 deploy should visually progress through 4-6 distinct environments. Brown soup is gone.

### Stage 2: Layout variety (~6h)

Add 3 layout algorithms beyond BSP. Promote `DungeonGenerator` to a thin dispatcher.

Layouts to ship:
- `bsp` — current rooms+L-corridors
- `cave` — cellular automaton (B5678/S45678, 4 iterations, flood-fill keep largest region). Returns empty `rooms: []`. Pair with Lair, Mines, Slime.
- `corridor` — drunkard's walk biased to straight runs (~80% same-direction continuation), rare 3-wide widenings every N tiles, 3-6 small chambers. Pair with Crypt, Forge.
- `arena` — single big rectangle (~70% map area) + scatter Voronoi-seeded clumps of impassable decor. Pair with Vaults (pillar hall), Lair (tree clumps), boss floor 10.

Each biome opts in via `layouts: [...]`. Generator picks layout from biome's list. **Caves return `rooms: []`** — thread fallbacks through `_random_walkable_cell_far_from_bot()`, vault stamper, and AI's "nearest unvisited room" so it falls back to "nearest unexplored walkable cell" when rooms is empty.

### Stage 3: Vault expansion (~8h)

Grow library 4 → ~30 vaults. Categories per biome:
- 4-6 generic decor (fountain alcoves, statue alleys, columned halls, pillar rings, mushroom patches, water pools)
- 2-3 monster set-pieces per biome (orc warband for Mines, jelly vat for Slime, skeleton crypt-room for Crypt, fire imp pit for Forge, etc.)
- 4-6 treasure rooms (single big chest guarded by walls, gold pile + 2-3 enemies, locked vault, moat-around-loot)
- 2-3 boss arenas — fancy floor-10 set pieces themed to whichever biome led there
- 3-4 sub-vaults / decor dressings (single sarcophagus, single statue-of-altar combo, single trap-room)

New glyphs to support:
- `L` lava (impassable + damages on contact, future Stage 5)
- `W` water (slow movement, future Stage 5)
- `t` tree (impassable like statue)
- `>` stairs override (rare, lets vault dictate stairs placement)
- `A` altar slot (uses existing Altar interactable)

Each vault tagged `themes: [biomes that allow it]`. `VaultLibrary.candidates_for(biome, floor)` already filters by themes.

### Stage 4: Room types within layouts (~5h)

When `DungeonGenerator` carves BSP rooms, tag each with a type: `empty`, `monster`, `horde`, `loot`, `altar`, `boss`. Per-biome weights for how often each appears (Vaults = more loot rooms, Crypt = more altar rooms, Mines = more horde rooms).

Then:
- `_spawn_enemies()` reads room types: `horde` = 6-10 weak enemies in cluster, `monster` = single normal spawn, `loot` = 1-2 enemies + guaranteed chest, `empty` = no spawn
- Altar rooms always have an altar
- Boss rooms reserved for floor 10 / mini-boss floors

Vault stamping prefers rooms tagged compatibly (decor vault → empty room, monster vault → monster/horde room, treasure vault → loot room).

### Stage 5: Decorative pass (~4h)

- Per-biome lighting effects: forge orange flicker, glacier blue tint, crypt dim purple, swamp green murk
- Edge tiles for natural transitions: deep_water tiles around water cells, lava cracks at lava edges, rough rock around cave walls
- Wall variant rolling: 3-4 wall variants per biome rolled at 70/15/10/5% weights so walls aren't perfectly uniform — fights the "every wall identical" look
- Add lava / water / pit gameplay: lava damages when bot stands on it, water slows movement, pits drop bot to next floor (free descent but skips loot)

### Stage 1.5: VARIETY PASS — the next major push after current work

**Trigger reference**: see `botter/dcss-reference-elvenhalls.png` style note in this doc. User wants Botter to feel like DCSS:
- Distinct, regionalized tile placement (NOT per-cell pepper-noise random)
- Room-scale visual identity — each room/zone reads as a place
- Sparse, intentional-feeling decor (not scattered randomly)
- Way more enemy variety — "discovering new monsters as I play"
- Way more item variety — legendary items use unique artefact sprites
- Eventually DCSS-style UI (side panel HP/MP bars, minimap)

**Current asset utilization is shameful** (snapshot at end of last session):

| Asset | Using | Available | %  |
|---|---|---|---|
| Enemies | 10 types | **177 unique sprites** | 5% |
| Weapons | 4 sprites | 351 (incl. 84 artefacts) | 1% |
| Armor pieces | ~6 | 222 | 3% |
| Consumables | 1 sprite | 261 | <1% |
| Altars | 7 gods | 23 gods | 30% |
| Statues/decor | 1 | 41+ | 2% |
| Doors | 0 | 30 | 0% |
| Traps | 0 | 24 | 0% |
| Trees, boulders, water, lava | 0 | many | 0% |
| Effect frames (blood/fire/ice/etc) | 0 | 238 | 0% |
| Floor/wall | 553 | 1035 | 53% |

**Goal**: get to ~50% utilization across the board. The whole point of choosing DCSS as our tile source was this art library — using 5% of it is malpractice.

#### Sub-stage 1.5a: Smart tile placement — refined plan after seeing DCSS reference shots

User shared 4 DCSS screenshots (Necromancer corridor, Elven Halls 2, classic dungeon, RLTiles reference sheet). Key observations now informing the plan:

**1. Walls are near-uniform.** DCSS picks ONE dominant wall sprite per biome and sticks with it across the entire floor. Maybe 1 secondary wall (cracked / mossed / damaged) at 5-10% frequency. Our current approach of 14 wall variants per biome is the single biggest noise source. Walls frame action — they shouldn't compete with floors.

**2. Floor variants cluster in PATCHES.** Voronoi-style 6-15 cell zones, not per-cell randomness. Each patch picks ONE primary tile from a 2-3-tile "primary set." Within the patch ~85% primary, ~10% same-family secondary tiles, ~5% destruction accents (cracks, blood, wear). The "blue tile patch / green tile patch / plain patch" pattern in Elven Halls is patches, not noise.

**3. Edge/transition tiles between patches.** When a destroyed/special patch meets a clean patch, one row of transition cells uses an intermediate tile. This is the visible gradient effect.

**4. Linear decor along walls/corridors.** DCSS Necromancer shot shows plants arranged in linear hedge formations along corridor edges, every 2-3 cells. Not random scatter. New `LinearDecor` rule: corridor-edge decor places at regular intervals along the wall line, not random.

**5. One "feature" per room rule.** Each room/zone gets at most ONE high-contrast feature: a blue rune-tile, fountain, pile of bones, sigil-floor accent. Currently we sprinkle. DCSS punctuates — single point of visual interest per region.

**6. NEGATIVE SPACE matters most.** Elven Halls shot is ~70% black void with the playable region rendered as a small island. We render full 60×60 grid edge-to-edge. This is THE biggest perceptual difference. Solution = fog of war (see below — combined with lighting).

**Implementation order within 1.5a (revised after lighting insight):**

1. **Walls go uniform first** — biggest immediate cleanup. `biomes.json`: rename to `wall_dominant` (single tile) + `wall_accents` (array of 1-3 tiles used at total 5-10%). Update renderer.
2. **Floor patch system** — Voronoi-seeded 10-15 patches per floor. Each patch primary + 2 secondaries + rare destruction accent. New `floor_primary_tiles`, `floor_accent_tiles`, `floor_destruction_tiles` arrays in biome data.
3. **Linear decor rule** for corridor walls — when placing wall-adjacent decor (vines, mushrooms), bias to regular intervals along long wall runs.
4. **One-feature-per-room rule** — when assigning room feature (rune tile, fountain, etc), enforce max 1 per BSP room.

#### Sub-stage 1.5-FOG+LIGHT — combined fog of war + lighting (replaces old separate Stage 6)

**Insight**: in DCSS-style games, fog of war and lighting are the SAME system. The bot's "field of view" radius IS the bot's carried light. Discovered cells become "remembered" (rendered dim) when out of light. Light sources in the world (torches, altars, lava cells) partially reveal rooms before the bot enters.

This is the single highest-impact visual change of the entire variety pass. Putting it RIGHT AFTER 1.5a (smart tiles) and BEFORE everything else.

**Implementation:**

1. **Bot light**: `PointLight2D` child of bot, energy 1.0, range ~7 tiles, soft falloff, white. Slight flicker via tween (energy 0.95–1.05 on 0.6s loop).
2. **Tile sprite alpha state machine**:
   - Cell in bot's light radius → `modulate.a = 1.0`, full color
   - Cell previously seen but currently out of radius → `modulate.a = 0.35`, slightly desaturated (`modulate.r/g/b *= 0.6`)
   - Cell never seen → `modulate.a = 0` (effectively black void)
   - All transitions tweened over 0.25s for smooth reveal
3. **Per-cell `explored: bool`** dict on `Dungeon`. Updated each `_tick_bot` based on Chebyshev distance ≤ light radius from bot.cell.
4. **World light sources** — emit their own `PointLight2D`:
   - Lit altars: god-themed color (Trog red, Sif Muna blue, Zin white) range ~3, energy 0.8, slow pulse
   - Lit fountains: matching their fountain kind (sparkling cyan, blood red, blue blue) range ~3, energy 0.6
   - Lava cells (Forge): orange-red, range ~4, energy 1.0, fast flicker
   - Ice crystals (Glacier): cool blue, range ~3, energy 0.5, slow pulse
   - Legendary loot drops: rarity-color, range ~3, energy 0.7
   - Lit chests (high-bias): warm gold, range ~3, energy 0.6
   - Torches (decor, future): warm orange, range ~5, fast flicker
5. **Biome ambient light tuning** — biomes.json gets a `darkness` field. Bright biomes (Vaults, Tomb) = 0.0 darkness (full ambient). Dim biomes (Crypt, Forge, Abyss) = 0.4-0.6 darkness (the void state matters more, light matters more).
6. **`WorldEnvironment` with bloom** — added at the dungeon scene root. Glow strength tuned moderate. This makes legendary glows + altar pulses + lava emit visible bloom around them. Already-built glows on chests/altars/fountains automatically benefit.
7. **Performance check**: 30-50 dynamic Light2Ds is fine on Godot 4 GL Compatibility renderer at 60fps mobile-equivalent. If we later go heavier, switch to "static lights baked into a darkness mask" instead of per-source.

**Effort estimate: ~5h.** This was originally 4h for "Stage 6 lighting" + 0h "fog separate" — combining them is more efficient.

**Validation**: a single deploy after this stage should feel transformed. Walking the bot should reveal new rooms cell-by-cell. Walking past an altar before reaching it should glimmer. Lava biomes should feel hot. Crypt should feel claustrophobic. The brown-soup look will be IMPOSSIBLE because most of what we see at any moment is bot-illuminated, not flat tile dump.

#### Sub-stage 1.5-WALLS: Impassable terrain variety (CRITICAL — biggest single visual fix left)

User insight: **walls don't have to be walls.** Anywhere a wall would render, it could be water, trees, lava, mushroom clusters, fallen pillars, ice columns, tall grass — anything visually distinct that's still impassable. This is NOT decor — it's terrain replacement at the wall layer.

DCSS Lair shot shows this: most "walls" surrounding the room are actually trees, water, mushroom patches. Visual chaos = lush feel. Pure-stone walls = sterile dungeon.

**Implementation:**

- New biome field `wall_alternates`: list of `{prefix, weight}` impassable tiles that substitute for some % of wall cells.
- Renderer's wall-pick rolls: 60-70% dominant wall, then weighted-pick across alternates.
- Critical: for water and lava, **cluster** them — pick certain wall patches to be entirely water/lava/etc, not individual cells. Otherwise confetti effect. Use Voronoi extension: patches assigned a "wall theme" (stone/water/tree/lava), all wall cells in that patch use that theme.
- Pathfinding still treats them as walls (T_WALL); only the visual changes.
- Per biome:
  - Lair: tree clusters (60% of walls become trees in some patches), shallow water, tall grass
  - Forest: 80% trees, occasional rock outcrop, mushroom clusters
  - Swamp: deep water, mangroves, mud cracks
  - Shoals: deep water, sand mounds, palms
  - Forge: lava cracks (some wall patches become lava), boulders, charred rock
  - Glacier: ice columns, frozen water, snowdrifts
  - Crypt: collapsed pillars, bone piles, rubble
  - Vaults: fallen marble columns, statue rubble, sigil pillars
  - Tomb: sandstone slabs, sand drifts
  - Slime: acid pools, slime puddles
  - Hive: honeycomb structures, beehive clusters

DCSS has the assets:
- `dungeon/water/` — 121 water tiles (deep, shallow, with directional wave variants for shoreline)
- `dungeon/trees/` — 9 tree tiles (red/yellow/lightred autumn, mangroves)
- Tree color variants for biome theming (forest = green, autumn = red/yellow)
- Lava tiles in `dungeon/floor/lava_*` and similar
- `dungeon/floor/moss_*` for soft ground patches
- Mushroom monsters can be reused as decor: `monster/fungi_plants/wandering_mushroom`

Effort: ~4h. Highest single visual impact left in the variety pass.

#### Sub-stage 1.5b: Decor scatter — biome-themed, sparse

NEW pass after vault stamping. For each room, roll 0-3 decorative items from the biome's decor pool:
- Crypt → bones, skulls, sarcophagus
- Forge → embers, scorch marks, anvil
- Lair → mushroom clusters, vines, bones
- Vaults → broken statues, runed plaques, incense braziers
- Glacier → ice shards, frost crystals
- Swamp → mud puddles, mushrooms, rotted logs

These are non-blocking aesthetic Sprite2D nodes overlaid on floor cells. New `DecorScatter.gd` system, biome-driven config in `biomes.json`.

#### Sub-stage 1.5c: MONSTER EXPANSION — 10 → ~60 enemies

Pull 50 unique sprites from `monster/animals/`, `monster/undead/`, `monster/dragons/`, `monster/aberration/`, etc. Tier 1-5 by intuited threat. Add to `enemies.json` with stats following the number ceiling.

Each biome's `enemy_pool` grows from 4 to 10-15 candidates. Per-floor random subset (3-5 chosen at floor build time) means **runs feel fresh** — this run's Lair is jackals + adders + bats, next run's is wolves + spiders + slugs. That's the "discovering new monsters" feel.

Add **champion** variants: ~1% spawn chance for an "elite" version of any enemy with 1.4× stats, larger sprite, unique color tint. Distinct from miniboss (which is room-locked); champions appear anywhere.

#### Sub-stage 1.5d: ARTEFACT items for legendaries

Legendary items currently look identical to commons. Use the **84 artefact weapon sprites + 38 artefact armor sprites** from `item/weapon/artefact/`, `item/armor/artefact/`. Each legendary instance picks one at drop time and stores `tile_override` in the item instance dict. Two legendaries from the same base look meaningfully different.

Update `items.json` legendaries to flag them, update `LootDrop` and `Garage` to prefer `tile_override` over base tile when present.

#### Sub-stage 1.5e: Special features per biome

Add new vault glyphs and biome-specific autonomous spawners:
- `t` tree (impassable, Lair/Forest)
- `L` lava (impassable + future damage tile, Forge)
- `W` water (slow movement, Shoals/Swamp)
- `I` ice (Glacier, slippery future hook)
- `B` bones / skull / sarcophagus (Crypt, decor)
- `M` mushroom cluster (Swamp/Lair)
- New chest variants: small wooden / ornate / sarcophagus (each with different drop bias)

#### Sub-stage 1.5f: Door tiles

Make vault `+` glyph render as actual door sprite. Per-biome door variant: wooden in Dungeon, iron-barred in Vaults, runed in Crypt. Open/closed state cosmetic for now.

#### Sub-stage 1.5g: Combat effects

One-shot Sprite2D fades using `effect/*` frames:
- Blood splatter on hit
- Fire flash on Forge kills  
- Ice shatter on Glacier kills
- Magic shimmer on legendary drops + altar grants
- Smoke poof when chest opens

#### Sub-stage 1.5h: Negative space + smaller dungeons

Current 60×60 map fully filled with floor/wall. DCSS surrounds the playable region with **black void**. Two changes:
- Reduce playable area to ~40×30 (DCSS Elven Halls visible region)
- Outside walkable space = no rendering (transparent / black)
- Camera centers tighter; map feels intimate, not overwhelming

#### Sub-stage 1.5i: DCSS-style UI (deferred — its own beat)

Side panel: HP green bar + MP blue bar (when MP exists), XL/level + xp%, AC/EV/SH placeholders, gold count, current biome name, inventory shortcut row. Minimap top-right showing explored area only. Pixel font (`silkscreen` from existing prototype, or `Press Start 2P`). Dark BG. Don't tackle until 1.5a-h are in.

### Sequencing for the variety pass — recommended order (REVISED)

1. **1.5a** Smart tile placement — uniform walls + floor patches + linear decor + 1-feature-per-room. Foundation everything else builds on.
2. **1.5-fog+light** — combined fog of war + Light2D lighting system. THE headliner. Single biggest visual transformation. Negative space comes for free via fog.
3. **1.5c** Monster expansion — biggest "discovery" feel for player
4. **1.5d** Artefact items for legendaries — biggest visual win for already-found content
5. **1.5b** Decor scatter — texture without changing geometry; lights from torches/braziers added here
6. **1.5e** Special features — depth per biome (lava cells emit light, ice crystals emit light, etc — composes with fog+light system)
7. **1.5f** Doors — small polish; doors emit slight torchlight when adjacent
8. **1.5g** Combat effects — blood, fire, ice, magic shimmer
9. **1.5i** DCSS-style UI — separate beat (HP bar, minimap, side panel)

**Total ~28-32h.** Note: old "Stage 6 lighting" is now folded into 1.5-fog+light, so original Stages 2-5 (layouts, vault expansion, room types, decorative pass) still pending after the variety pass. Original Stage 6 deleted.

### Process rules added after asset-utilization audit

**Before bulk-copying any assets**: consult `data/tile_catalog.json` for actual variant counts per category. **Never hardcode caps** like "copy 3 variants" — pull all available, or read the count from the catalog. The catalog exists exactly for this reason; ignoring it wasted weeks of variety we already had.

**When implementing a new system**: do a `find` or `ls | wc -l` on the relevant DCSS folder first, eyeball the actual tile count, write the import to use what's there.

**Never assume "small variety is fine for v1"** — variety is the product. Underutilization is a bug, not a stage.

### Stage 6: Lighting + effects pass (~3-4h) — Godot-native polish

Modern Godot 4 has cheap, high-impact 2D lighting that pixel art *needs* to not look flat. Order of cost-vs-impact:

**Quick wins (~2h):**
- `CanvasModulate` per biome already in Stage 1 — ambient tinting baseline.
- `PointLight2D` on torches, fountains, altars, lava tiles, lit chests. Each light has its own color matching the source (torches warm, altars god-themed, lava red-orange, legendary items rarity-colored).
- `WorldEnvironment` with bloom enabled — legendary item glows become *radiant*. Current alpha-glow looks dim by comparison.
- Light flicker — torches/braziers tween energy 0.85 ↔ 1.0 on a 0.6s loop.
- Screen shake on damage taken / boss hit / chest open. One-line Camera2D tween.

**Medium (+1h):**
- `LightOccluder2D` on wall tiles so torch light casts proper shadows; pillars / statues / boulders become visible silhouettes.
- `GPUParticles2D` for lava embers, dust motes in dim corridors, blood spurts on hit, sparkles around legendary drops, altar grant burst.

**Defer to later:**
- Animated water shimmer / lava heat shaders (cool but each is a custom shader file)
- Normal-mapped tiles for proper light-wrap on pixel art (auto-generation possible but ~1-2 day project)
- Volumetric fog / god rays (overkill at tile size)

**Validation**: comparison run before/after Stage 6 should be obvious — pixel art that "feels lit" vs "feels flat."

## Out of scope for this dungeon pass (defer)

- Subvaults / nested vaults (DCSS does this; we explicitly skipped per agent's recommendation)
- Lua hooks in vaults (skipped — code in data files = bad)
- DCSS's full DEPTH algebra (`!Depths:$`, `Lair:1-3` etc) — we use simple `[min, max]` integer ranges
- Branch-discovery minigame, secret doors, line-of-sight (idle game has no perception layer)
- Shoals tide system / Abyss morphing geometry — too expensive for 30-sec mobile session
- Player paper-doll layered sprites for custom bot appearance — defer to post-MVP cosmetics. **PLANNED:** when we revisit, build it as DCSS does — base body + per-slot overlay sprites for mainhand, offhand, body armor, helmet, boots, cloak, gloves. Each slot in `equipped` dict picks a `tile_override` (already exists for legendaries) that loads the corresponding `player/{slot}/{name}.png` layer onto the bot. Asset library has 975 paper-doll sprites; same 32×32 origin so layers compose without offsets. Should be straightforward once we want gear visually distinct on the bot.
- **Organic-light flame jitter — TODO.** Torches, braziers, campfires, lava, candles should have subtle non-uniform twinkle: small pseudo-random offsets to position (sub-pixel) and energy (±10-15%) per-light, so each one looks like an independent flame instead of synchronized pulsing. The current `flicker: fast/slow/pulse` modes are tween-driven and too uniform. Real flames jitter at ~5-12Hz with broadband noise. Implementation: in `LightSpec._apply_flicker`, replace the linear tween with a per-frame `_process` callback that drives `light.energy = base * (1 + noise(t * freq) * amp)` plus a tiny `light.position += rand_v2 * 0.5px`. Apply only to "fire" / "lava" / "candle" categories — crystals and altars stay smooth. Bot lantern is included since it's a flame.
- 23 god-altar variants (we already use 7 — adding more is just a JSON edit when we want it)

## How to inspect tiles (READ-TOOL TRICKS)

The Read tool downscales images aggressively when previewing — a single 32×32 PNG renders as a tiny smudge that's useless for judging tile content. Lessons learned for future inspection passes:

1. **Build composite tile sheets at ~180px per tile** in 4-col grids and save to `/tmp/tile_audit/sheet_<biome>.png`. The Read tool will downscale the *sheet* but at sheet sizes ~720×600, individual 180px tiles end up at ~50px in the preview — enough to read shapes.

2. **A composer script lives at `/tmp/tile_audit/`**. Pattern:
   ```python
   from PIL import Image, ImageDraw
   imgs = [Image.open(p).resize((180, 180), Image.NEAREST) for p in tile_paths]
   sheet = Image.new("RGB", (180*4 + 20, 200*rows + 30), (40,40,40))
   # paste each + label below
   ```
   This is the ONLY reliable way to audit tiles I've found. Don't bother trying to Read individual 32×32 PNGs.

3. **Directional-tile detection is a pattern recognition task on the sheet.** Look for these signs:
   - **Octagonal cell frames** (vaults — corner pieces of a stamped shape)
   - **Diagonal slabs / arches** (parts of a multi-tile architecture)
   - **One-side darker than the rest** (edge highlights, e.g. moss along south)
   - **Visible "drip" / "pool" / "shoreline"** running off one edge (slime, water, lava)
   - **Repeating motif clearly intended to span 2+ tiles** (the visible 2x2 `octa_room` pattern in vaults — corners + sides)

   If the sheet looks like a coherent architectural pattern across tiles rather than 12 independent square swatches, **the prefix is directional and should NOT be in `floor_primary`**. Demote to accent at most, ideally substitute with a plain stone/marble primary from another biome.

4. **The Read tool can mis-cache** — calling Read on `sheet_abyss.png` may return the previously-cached `sheet_vaults.png` content under some conditions. Verify by checking the file modification time AND the labels visible in the sheet. If wrong, regenerate the sheet with a unique filename suffix.

5. **DCSS source filenames hint at directionality.** Anything with `_overlay_*`, `_north`/`_south`/`_east`/`_west`, `_corner`, `_shore`, `_edge`, or that's part of an `_alt2`/`_alt3` set in DCSS's tilesheet recipe is suspect. Cross-reference `tile_catalog.json` and `dcss/` source pack before using a prefix as primary.

6. **Walls have similar issues.** Wall tilesets often include `_torch_left/right` variants meant for specific edges. Same audit logic applies — if the sheet shows directional ornamentation, treat as accent.

**Where this lesson came from:**
- **slime** prefix is literally `slime_overlay_north/south/etc` — directional drips, NEVER primary. Fix shipped: slime now uses `dungeon` as primary floor, slime walls + ambient decor carry biome identity.
- **vaults** prefix is the DCSS vault-frame autotile (octagonal arch pieces). Fix in progress.
- Likely affected: abyss, hive, depths, elf — full sheet audit pending.

## Tile-prefix gotchas (LESSONS LEARNED)

DCSS tiles aren't all "primary floor" — some prefixes are *directional overlays* meant to be placed at specific floor cells (typically those bordering walls). Tiling them randomly across a floor produces a "messy" / "random" look the user has flagged repeatedly.

**Confirmed offenders:**
- **slime**: DCSS has `slime_overlay_north/south/east/west/ne/nw/se/sw` — these are meant to render at floor cells *adjacent* to walls in the matching direction, simulating slime dripping off walls. Our pack has these as `slime_*.png` and `slime_alt_*.png`. Treating them as primary patches is wrong. **Fix applied**: slime biome's `floor_primary` is now plain `dungeon` stone; wall stays slime-themed. Future: implement directional autotile (task #66).

**Likely affected (audit pending):**
- Any biome where the floor tiles include "edge", "shore", "transition" naming — flag these and treat as wall-adjacent overlays, not primary patches.
- The `_alt`, `_alt2`, `_alt3` suffixes in vaults/, etc. — *some* alt-numbered variants are decorative features (rune-floors, magic circles) that look bad as a patch face. Audit when reported.

**General rule from this lesson — apply across all biomes:**
1. **Primary floor tiles must be square-symmetric and tileable in all directions.** No directional cracks, no edge highlights, no "drip" / "pool" features.
2. **Decorative / feature tiles** (runes, sigils, blood splatter, slime drips, moss patches with directional bias) belong in `floor_accent` at ~12% sprinkle density, OR in a future directional-autotile system.
3. **When in doubt, use the parent's plain stone floor.** A slime-themed wall + stone floor reads as "stone room with slime walls" — a slime-themed floor that's actually edge-overlays reads as "what is this mess." Walls carry biome identity more reliably than floors.
4. **Authentic atmosphere comes from walls + ambient decor + lighting palette, NOT busy floor tiles.** Pandemonium and Zot look great because their primary floor tiles ARE square-symmetric textures. Slime looked bad because we put directional overlays at primary.
5. **When auditing a biome that "looks bad" or "looks random,"** check the DCSS source filenames in `dcss/Dungeon Crawl Stone Soup Full/dungeon/floor/` — anything named `*_overlay_*`, `*_north.png`, `*_edge*` is directional and should NOT be in `floor_primary`.

This is also why our `_expand_prefixes` fix earlier (require `prefix_<digit>` exact suffix) helped — it stopped `slime` from accidentally pulling `slime_alt_*` directional pieces into primary. Keep that strict.

## Biome audit (2026-05-12)

`/Users/dyo/claude/botter/docs/biome-audit.md` — full visual audit of all 24 biomes done via debug-jump screenshot self-verification. Lists ship-ready biomes, ones needing tweaks, and broad insights about DCSS tile conventions, modulate values, and decor density. Produced after the user pointed out that vaults/slime/dungeon_dark looked broken; fixes shipped + lessons documented.

Key insights baked into the audit:
- Walls carry biome identity more reliably than floors
- Modulate <0.7 risks crushing detail; reserve for atmospheric biomes only
- Some DCSS prefixes are directional overlays (slime), NOT primary tiles — inspect raw pixels before assuming numbered variants are equivalent
- Two biomes can share floor tiles if walls are distinct enough
- Every biome should have at least one ambient light source

## Branch research dossier

`/Users/dyo/claude/botter/docs/branch-research.md` is the canonical reference for every DCSS dungeon branch — visual identity, layout style, signature monsters, signature features, vault library notes, run-loop role for Botter, and asset gaps. ~9000 words across ~25 branches. Read it before authoring any new biome / branch / vault. Sourced offline from `dcss-source/crawl-ref/source/branch-data.h`, the per-branch `.des` files, and our own asset directory. All paraphrased — no GPL violations.

When implementing a new branch:
1. Read its section in `branch-research.md`.
2. Check the asset-status note: SHIP NOW (assets ready), SHIP WITH GAPS (1-2 sprites needed), DEFER (heavy art lift).
3. Cross-reference our `data/biomes.json` entry — do tile prefixes match what the dossier says we have?
4. Use the dossier's vault concepts to seed encompass / float vault authoring.

Phase-1 ship-ready branches per the dossier: D, Lair, Orc, Swamp, Vaults, Crypt, Tomb, Zot.
Phase-2 (1-2 sprites needed): Elf, Snake, Spider, Shoals, Depths, Slime.
Phase-3 (endgame, heavier lift): Hell tier (Vestibule, Dis, Geh, Coc, Tar), Pan, Abyss.

## Tile catalog

`project/data/tile_catalog.json` is the inventory of all available DCSS tiles, indexed by category (floor/wall/monster/item/feature/effect/player). It includes biome palette recipes — explicit floor/wall prefix lists per biome — for 18 biomes (dungeon, lair, swamp, snake, shoals, orc, vaults, crypt, tomb, forge, glacier, slime, hive, labyrinth, abyss, zot, pandemonium, dungeon_dark). Use this as the shopping list when adding biomes.

Notable assets we haven't tapped yet:
- 23 god altars (80 sprites, some animated) → blessing system if desired
- 84 artefact weapon + 38 artefact armor sprites → unique legendary art (currently legendaries reuse common-tier art)
- 121 directional water tiles → real shoreline autotiling for shoals/swamp
- 177 unique-monster sprites → way more variety than `enemies.json` currently uses
- 11 themed branch-entrance gateways → biome-select hub if we build one
- 975 player paper-doll layered sprites → custom bot appearance if we want it

When picking tiles for new code, **read tile_catalog.json first** — don't go spelunking through `dcss/` directly.

## Open questions (from the GDD, decide later)

- PvP (async — your bot vs. another player's dungeon config)
- Prestige/rebirth for endgame
- Clan/guild social features
- Steam Deck support alongside mobile

## Decisions on record

- **Stack:** Godot 4.6 + GDScript (user picked over the React prototype handoff).
- **Pathfinding:** AStarGrid2D over NavigationAgent2D / custom A* (research agent recommendation — engine-native C++, grid-aligned, set_point_solid maps 1:1 to wall tiles).
- **Number ceiling:** ~1500 HP / ~300 ATK / ~100 DEF endgame; ~300-400 peak damage. User explicitly rejected idle-game number creep ("dont want to creep into players having 50000 hp").
- **DCSS prototype handoff:** acknowledged but not followed. User said "we dont need to absolutely follow the claude design file" — it was just for visual direction.
- **DCSS source:** shallow-cloned (132 MB) into `dcss-source/`. **Research only — GPLv2.**
