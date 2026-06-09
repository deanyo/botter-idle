# Botter — Project Notes for Claude

**Reframe:** Botter is **DCSS Reimagined as an Idle Game.** Not "inspired by
DCSS" — actually *ported from* DCSS, with the player replaced by a
configurable autonomous bot.

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

**Why this matters**: stop reinventing dungeon generation. DCSS's source has
2000+ lines of polished, decades-tuned algorithms (trail+rooms, delve caves,
octa rooms, chequerboard, river/lake, Worley layouts) that we should port
directly. Same with monsters and items — the data is already balanced. **The
actual creative work is the bot + idle loop**, not yet another procgen.

**Rule of thumb — lean on DCSS for design decisions, don't reinvent the
wheel.** Whenever a question comes up about how something *should* feel or
work (loot rarity bands, branch progression, status-effect mechanics,
monster aggro shape, vault density, etc.), check what DCSS does first
(`dcss-source/crawl-ref/source/`) before designing from scratch. DCSS has
20+ years of playtest tuning baked in — its answers are usually right.
Then iterate and embellish for the idle-game frame: change number
ceilings, swap permadeath for retreats, add prestige curves, layer
modifiers. **Read for shape, not for code.** The GPLv2+ rule (never copy
code) still applies — read, write a plain-English description, rewrite
in GDScript. See "HOW TO PORT DCSS CODE" below.

Player fantasy: **being an MMO botter / following someone's autoplay run.**
Configure your bot, deploy it, watch it explore, gear it better, redeploy.
Background-friendly. Mobile-first.

## Where things live

- **`HANDOVER.md`** — point-in-time snapshot of what's actually shipping
  (gameplay loop, generation pipeline, biome roster, vault library, FX
  state, logging tags). Read on session start.
- **`TODO.md`** — roadmap, deferred items, asset gaps, open questions.
  This is the **engineering backlog** — entries are triaged, scoped, and
  often have file:line references.
- **`PLAYTEST.md`** — raw observation log from live playtests.
  Append-only, dated, untriaged. This is the **inbox**, not the
  backlog. The user dumps notes here verbatim post-playtest; the
  next session's job is to triage `Status: untriaged` items
  (re-verify against code, classify as bug / UX / design, promote
  to TODO.md or a new session brief, mark status). Same trust-but-
  verify rule as the audit findings — re-read the code before
  patching, since playtest evidence is unverified. Cross-link to
  audit findings in `~/claude/game-audit/findings/AUDIT_REPORT.md`
  where they overlap. Don't delete resolved items — the trail of
  what changed in response to play-feel feedback is durable memory.
- **`docs/`** — biome audit, branch research dossier, vault audit
  (long-form references).
- **`project/`** — the Godot project. Open this in the editor.
- **`tools/`** — atlas builder + viewer, biome editor, item editor +
  per-slot manifests, `sync_items.py` (manifest → items.json + sprites),
  `inject_save.py` (build-spec → debug save), `parse_grind.py` (grind
  log → dataclasses), `balance.py` (run_grind harness for /duel/sweep/
  playthrough), `analyze_*.py` (cross-branch / floor-deaths / affix-
  curve analyzers), `run_experiment.sh` (nohup wrapper for long jobs).
- **`logs/`** (gitignored) — `grind/`, `balance/`, `screenshots/`,
  `playthrough/` subdirs. `balance/index.jsonl` and
  `playthrough/index.jsonl` are JSONL ledgers — one entry per
  experiment, queryable with `jq`.

**Hard rule**: **when committing to git, update `HANDOVER.md` and `TODO.md`
to match what just shipped or got deferred.** They're the source of truth
for "what's done, what's next" and they rot fast if not maintained per beat.

## Audit artifacts (2026-06-08, multi-agent review)

A multi-agent audit produced 100 verified findings across architecture,
performance, idle integrity, content pipeline, technical debt, DCSS legal,
dual-platform, and pivot-residue. Every finding was confirmed by 2-of-3
adversarial skeptics (so when one cites a file:line, it existed at audit
time — but re-verify before acting; the code may have changed). Artifacts
live at `~/claude/game-audit/`, deliberately outside the repo:

- **`findings/AUDIT_REPORT.md`** — 628-line structured report. Executive
  summary, 78 individual findings grouped by category, Top-5 prioritization
  at the end. Each finding has file:line evidence, severity, recommendation,
  player impact.
- **`findings/AUDIT_TODO.md`** — 47-item triaged backlog with effort
  estimates (L/M/H) and tier sequencing. Tier 0 = legal/credibility fires;
  Tier 1 = cheap visible fixes; Tier 2 = legal hygiene + tests + save
  durability; Tier 3 = architectural splits guarded by the test foundation.
- **`prompts/`** — ready-to-paste session openers. `_session_template.md`
  is the reusable context preamble; `tier0_*.md` / `tier1_*.md` /
  `tier2_*.md` / `tier3_*.md` are tier-specific task briefs that drop in
  where the template ends. `prompts/README.md` explains how to use them
  and the sequencing constraints.

**Sessions touching audit-flagged systems should:** (1) skim
`AUDIT_REPORT.md`'s relevant category section before editing; (2) re-verify
the cited file:line still matches reality; (3) cross-reference `AUDIT_TODO.md`
for tier ordering — do NOT start a Tier 3 architectural extraction without
the Tier 2 test foundation in place. The full sequencing rule lives in
`prompts/README.md`.

**Sessions NOT touching audit-flagged systems** can ignore these files —
they're orientation, not background reading for every change.

## Skills (project-scoped — already wired)

The project ships with skills under `.claude/skills/`. Use them — don't
reinvent these rituals each session.

- **`/screenshot <biome> [vault] [floor]`** — see
  `.claude/skills/screenshot/SKILL.md`. Captures one PNG + JSON sidecar at
  1024×1024. **The JSON is authoritative.** Trust it for HUD strings,
  biome id, every entity's cell+kind, all loaded floor/wall/overlay
  textures (resource paths). The PNG is for shape and silhouette only —
  color hallucinations and text misreads are common at compressed
  thumbnail size. Logs in `logs/screenshots/`.
- **`/grind <runs> [speed]`** — see `.claude/skills/grind/SKILL.md`.
  Headless N-run benchmark. No fixed sleep — exits the moment Godot prints
  `[run] auto-grind COMPLETE`. Returns a structured summary: per-run
  victory/level/gold, totals (floors, bad-floors, stalls, portals),
  uniqueness (biomes, vaults). Logs in `logs/grind/`.
- **`/equip "<spec>"`** — write a build to the debug save (no Godot
  launch). Shorthand: `weapon=demon_blade,Strength5,Crit4 level=30
  branch=forge`. Validates against items.json/affixes.json/biomes.json.
  Wraps `tools/inject_save.py`.
- **`/duel "<a>" -- "<b>" [-N 20]`** — A/B test two builds across the
  same N seeds. Wilson 95% CI win rate, paired stats, damage by weapon.
  Logs to `logs/balance/`.
- **`/sweep --slot W --values @legendary [-N 10]`** — vary one parameter
  across many runs. `@legendary`/`@epic_weapon` set sugar.
  `--affix crit --tiers 1,2,3,4,5` for affix curves. Ranked output.
- **`/playthrough [--equip POLICY] [--upgrade POLICY] [--advance POLICY]`**
  — simulate full game start-to-end. Three configurable policies decide
  what the simulated player does between runs. Outputs per-tier playtime
  + win-rate table. Use to calibrate the difficulty curve.
- **`/deploy-web`** — build the HTML5 export and push it to itch.io
  (`deanyo-gh/botter-idle:html5`) via butler. Wraps
  `tools/deploy_web.sh`. First push uploads ~12MB; subsequent pushes
  diff (typically <1MB). Prereq: `~/bin/butler` installed +
  `butler login` once.

**Long experiments** — when running anything that takes >5 min, wrap with
`tools/run_experiment.sh <name> <command>`. Detaches from parent shell
(survives Bash tool SIGTERMs), streams unbuffered to
`logs/balance/<name>.log`, writes exit code to
`logs/balance/.pids/<name>.status` on completion. Use python3 -u for
line-buffered Python output inside.

**Marker hygiene** (CRITICAL): both skills drive Godot via marker files
(`AUTO_GRIND.txt` for grind, `DEBUG_FLOOR.txt` for screenshot) under
`~/Library/Application Support/Godot/app_userdata/Botter/`. `main.gd`
reads these on every launch and switches the game into 16× speed-grind
mode or screenshot-and-quit mode accordingly. Both `grind.sh` and
`screenshot.sh` `rm -f` their markers (and parked `.parked` variants)
on exit. **If you ever launch Godot directly with these markers or
otherwise leak them, manually delete them before reporting the task
done** — the user playtests in normal mode and a stray marker breaks
their next launch silently. The user has been bitten by this.

When tooling-shaped work comes up (driving Godot from scripts, parsing
logs, watching for events) — **check whether a skill already exists**
before building one. If it doesn't, consider whether a new skill would
save time on the second use.

## Stack

- **Engine:** Godot 4.6.2-stable. User's binary at `/Applications/Godot.app/Contents/MacOS/Godot`.
- **Language:** GDScript only. No C# / GDExtension.
- **Target:** **Desktop landscape (1600×900 viewport)**, `keep` aspect
  stretch. DCSS-style chrome via `scripts/hud_chrome.gd`: right sidebar
  (minimap + stats + log feed), bottom-left bag (equipped + inventory),
  tiny top-left debug HUD. Mobile port is deferred — was originally
  mobile-first 540×960 portrait, pivoted 2026-05-13.
- **Tiles:** 32×32 DCSS sprites, CC0. Two source trees (both gitignored —
  bulky, refetchable, never shipped):
  - `dcss/` — full DCSS tilesheets (CC0 art only). Curated subset already
    copied into `project/assets/tiles/`.
  - `dcss-source/` — shallow clone of github.com/crawl/crawl (132 MB).
    **Research only — GPLv2+, never copy code.**
  - **Never reference `dcss/` or `dcss-source/` paths from project code** —
    only `project/assets/tiles/`.
- **Save/load:** Godot `FileAccess` + JSON, single slot. Save lives at
  `user://botter_save.json`.
- **Pathfinding:** `AStarGrid2D` (engine-native, fast). Set
  `diagonal_mode = DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES`. Don't mark every
  enemy solid every frame — agents oscillate in 1-tile corridors. See
  `scripts/pathfinding.gd`.
- **MCP:** `@coding-solo/godot-mcp` (project-scoped, `.mcp.json`). Lets
  Claude headlessly boot the project, capture errors, create scenes.
  **Project-scoped MCPs only prompt for trust at session START — restart
  the session if it doesn't appear.**

## Project layout

```
botter/
├── CLAUDE.md                  # rules of the road (this file)
├── HANDOVER.md                # what works today
├── TODO.md                    # what's next
├── README.md                  # outward-facing repo summary
├── .mcp.json                  # project-scoped MCP config
├── .claude/
│   ├── settings.json          # project permissions (committed)
│   └── skills/                # /screenshot, /grind (committed)
├── docs/                      # long-form references (biome audit, branch dossier)
├── tools/                     # atlas builder + viewer + biome editor
├── logs/                      # gitignored: screenshot + grind run logs
├── reference/                 # visual reference shots
├── dcss/                      # gitignored: raw DCSS tile pack (CC0)
├── dcss-source/               # gitignored: DCSS source (GPLv2+ — research only)
└── project/                   # the Godot project — open this in the editor
    ├── project.godot
    ├── scenes/                # main, dungeon, garage, run_report
    ├── scripts/               # constants, dungeon_generator, dungeon, bot, enemy,
    │                          # actor, pathfinding, map_renderer, biome_data,
    │                          # vault_library, vault_stamper, dcss_layouts,
    │                          # portal, altar, chest, fountain, fog_*, light_spec,
    │                          # affix_system, save_state, debug_jump, grind_log,
    │                          # hud_chrome, main, garage, run_report
    ├── data/                  # biomes.json, enemies.json, items.json,
    │                          # tile_atlas.json, vaults/des_*.json (1320 ported)
    └── assets/tiles/          # floor/, wall/, overlays/, features/, gateways/,
                               # enemies/, items/, player/, gui/
```

## HOW TO PORT DCSS CODE — process rules

These rules are non-negotiable. Bake them into every port session.

### Legal / licence

- DCSS source is **GPLv2+**. We can NOT distribute it or include any of its
  code.
- **Read the algorithm in C++. Describe it in plain English. Rewrite from
  the description in GDScript.** Don't even keep the C++ open while typing
  GDScript — there's a temptation to translate line-by-line, which is a
  derivative work. Translate *concepts*, not lines.
- Variable names: DON'T mirror DCSS's. Their `_make_trail` is fine to reuse
  as a function name (function names are utilitarian, not creative
  authorship), but `xs xr ys yr corrlength intersect_chance no_corr` should
  become readable GDScript like `start_x_min start_x_range
  corridor_max_length intersect_chance segment_count`.
- Tile sprites are **CC0** — different licence — fine to ship freely, with
  the attribution we already include.
- **Vault `.des` files**: format is data, not code. We port the format
  (glyph DSL → JSON) and populate from DCSS's actual `.des` library —
  that's how we got 1320 vaults.

### Per-port workflow

When porting a DCSS algorithm:

1. **Read the function and 1-2 layers of helpers it calls.** Don't go
   deeper unless needed.
2. **Write a 2-paragraph plain-English description** of what it does to
   the grid. Example: "Trail picks a random start cell, then iteratively
   picks a cardinal direction biased away from map edges, walks 2-15 cells
   in that direction, and either stops or carves another segment, repeating
   up to 30-200 times. Carved cells become floor."
3. **Rewrite from that description in GDScript**, using our coordinate
   system (Vector2i), our tile constants (`C.T_FLOOR`, `C.T_WALL`), our
   RNG (passed in), and our map dimensions. Don't open the .cc file again
   until you hit a question.
4. **Translate constants**: DCSS uses 80×70 maps. We use 80×80. Scale
   absolute-coordinate constants proportionally. Bounds checks use our
   `MAP_W`/`MAP_H`.
5. **Drop branch-specific edge cases.** DCSS has
   `if (player_in_branch(BRANCH_GEHENNA))` etc — we move those to
   biome.json toggles, not C++ branches.
6. **Use Godot built-ins** where they exist: `AStarGrid2D` for pathfinding
   (replaces DCSS's `dgn_join_the_dots_pathfind`), `RandomNumberGenerator`
   (replaces `random2`/`coinflip`), `Rect2i` (replaces `dgn_region`).
7. **One file per source file.** `dgn-layouts.cc` →
   `scripts/dcss_layouts.gd`. Easy to grep, easy to update later.
8. **Add a comment at the top** of each ported file:
   `# Algorithms ported in spirit from DCSS source/dgn-layouts.cc — see
   CLAUDE.md "HOW TO PORT" rules`.

### What "data we can use" means

- Tile sprite paths: yes, ship them.
- Tile filenames in DCSS .des format: data, fine.
- Function names and broad algorithm shapes: utilitarian, fine to reuse
  names like `make_trail`, `delve`, `octa_room`.
- Random distributions like "1 in 16 chance, big_room kicks in if level >
  1": these are tuning numbers, fine to use directly.
- Their .yaml monster stat tables and item ego enum: data, fine to
  transcribe.
- C++ literal code, even small chunks: NO, rewrite from description.

## Conventions

- **Number ceiling (HARD design rule):** Stats stay in tight ranges to
  avoid idle-game number creep.
  - End-game bot: ~**1500 HP**, ~**300 ATK**, ~**100 DEF**. Hits should
    peak around **300–400 damage**.
  - End-game enemies sit in similar bands. No 50k-HP bosses, no 9999-damage
    crits.
  - Progression scales **gear quality** (white→red rarity adds ~+5% per
    tier) and **floor depth** (each floor multiplies enemy stats by
    ~1.10–1.12), NOT raw stat inflation.
  - When tempted to "make a number bigger," instead make the *encounter*
    harder: more enemies, smarter positioning, mechanics. Damage variance
    and timing matter more than peak numbers.
- **Tile size constant:** `const TILE_SIZE := 32` — define once, reference
  everywhere. Don't hardcode 32.
- **Coordinates:** dungeon grid coords are `Vector2i` (cell), world coords
  are `Vector2` (pixels). Convert at the boundary, never mix.
- **Data-driven:** enemies, items, gear stats live in JSON under `data/`.
  Code reads, doesn't hardcode stat tables.
- **No comments unless the WHY is non-obvious.** Don't narrate the code.
- **Inclusive language:** master/slave/whitelist/blacklist →
  primary/replica/allowlist/denylist (per global rules).
- **Attribution:** credits screen must read: *"Part of the graphic tiles
  used in this program are from the public domain roguelike tileset
  RLTiles. http://rltiles.sf.net"* and credit DCSS contributors (CC0).

## HTML5 / Web export — Compatibility-renderer perf playbook

Botter ships to itch.io via `/deploy-web` (see Skills section above).
The export uses **Compatibility renderer + single-threaded WASM** so
it runs without SharedArrayBuffer headers. That choice constrains
the visual stack — Web GL Compatibility on macOS browsers has
specific failure modes that Forward+ desktop doesn't.

When adding a visual feature that involves a `ShaderMaterial`,
`ParticleProcessMaterial`, `PointLight2D`, or per-instance shader
allocation, design with these rules baked in:

1. **Shared materials, not per-instance.** A fresh `ShaderMaterial.new()`
   per sprite triggers a synchronous shader pipeline compile/link
   on Web GL the first time the (texture × shader) combination
   draws — multi-second main-thread stall. **Cache by parameter
   tuple** the way `UITheme._recolor_mat_cache` does:
   ```gdscript
   static var _mat_cache: Dictionary = {}
   func material_for(spec: Dictionary) -> ShaderMaterial:
       var key: String = "%.4f|%.4f|%d" % [spec.a, spec.b, spec.mode]
       var cached: Variant = _mat_cache.get(key, null)
       if cached != null and is_instance_valid(cached):
           return cached
       var mat := ShaderMaterial.new()
       # ... configure ...
       _mat_cache[key] = mat
       return mat
   ```
   Per-instance Tweens that mutate shader uniforms are fine; the
   uniform writes are cheap, only the program compile is expensive.
2. **Skip on web when the visual is dispensable.** Use
   `if OS.has_feature("web"): return` early-out for shader effects
   that aren't load-bearing for gameplay readability — threat
   outlines, item-recolor tints, weapon-glow pulse tweens,
   `PointLight2D` shadow casting. Modulate-based fallbacks
   (`sprite.modulate = ...`) cost nothing extra. See
   `enemy.gd::_ensure_outline_material` and
   `light_spec.gd::attach` for examples.
3. **Pre-warm any texture that will appear mid-run.** A loot drop
   or wave-spawned enemy with a never-before-drawn texture stalls
   for 1-3s the first time it draws. `BiomeData.prewarm_biome`
   walks every floor / wall / overlay / sigil / enemy / item
   texture and forces an actual GPU upload via
   `RenderingServer.canvas_item_add_texture_rect` against the
   root canvas (1×1 rect, full alpha — alpha=0 gets culled). It's
   throttled at 8 textures per frame so the prewarm itself stays
   smooth. Outpost calls `prewarm_biome` for every unlocked branch
   on `_ready`.
4. **Stagger spawns across frames.** N enemies materializing on
   the same frame multiplies texture-upload + node-add cost into
   one synchronous stall. `dungeon.gd` queues spawns in
   `_pending_wave_spawns` and drains one per frame from `_process`.
   Same pattern any time you'd burst-spawn N visual nodes.
5. **Multi-source TileSet > packed atlas.** `MapRenderer` builds
   one `TileSetAtlasSource` per texture instead of compositing
   them into a packed image. The packed-atlas approach calls
   `tex.get_image()` per tile (forces GPU→CPU readback —
   catastrophic on Web GL). Multi-source costs more draw calls
   (~50 instead of 1) but those are GPU-side and trivial at our
   80×80 grid scale.
6. **Browser tab throttling produces phantom spikes.** When the
   tab is backgrounded or inactive, the browser pauses RAF and
   resumes it with exponential backoff (1s → 2s → 4s → 8s).
   Naively measuring `Time.get_ticks_usec()` between `_process`
   calls flags those pauses as "5-second freezes." `PerfMon.spike_tick`
   filters with `dt_ms > 15000` discard + `not DisplayServer.window_is_focused()`
   discard. When debugging real perf, **keep the browser tab
   focused**, or work around the false signal.

**Diagnostic stamps.** When investigating a real spike, add
`PerfMon.note_spike_context("<event-id> <key=val>")` calls at
suspect entry points. The next `[perf-spike]` printout carries
that context. We've stamped chest-open, wave-spawn, loot-pickup,
descend, drain-spawn, floor-built — extend as needed.

**Manual zip upload fallback.** itch.io's CDN occasionally serves
stale wasm/pck for several minutes after a butler push (verified
2026-06-08 — Chrome served v3 while butler dashboard reported
v13). When testing a deploy and the in-game build stamp doesn't
match what was pushed, drop `dist/botter_web.zip` on
https://deanyo-gh.itch.io/botter-idle/edit → Replace file. Bypasses
butler/CDN entirely.

**Build version visibility.** `tools/deploy_web.sh` writes
`project/data/build_version.json` with an auto-incrementing counter
(`dist/.build_counter`) + a deploy timestamp. The game prints
`[build] version=vN ts=...` on boot, sets the browser tab title
to "Botter — build vN" via `JavaScriptBridge.eval`, and shows it
as the first line of the in-game debug HUD (`dungeon.gd::_build_stamp`).
Triple redundancy because verifying which build the user is
actually running matters when CDN caching is unreliable.

## Visual-tuning UIs — the FX Tuner pattern

Whenever a visual subsystem ships a "how strong should this be" knob
(glow alpha, particle count, shader thickness, etc.), expose it via
the **FX Tuner pattern** rather than baking magic numbers into code:

1. **Persist as a tunable in `VideoSettings.GFX_TUNABLE_DEFAULTS`**
   (`scripts/video_settings.gd`). Add a key, default, and forward-
   compat merge logic. Read at the call site via
   `VideoSettings.tunable("key", fallback)`.
2. **Add a slider row to FX Tuner** in `fx_tuner.gd::_TUNABLE_ROWS`
   (`scripts/fx_tuner.gd`). The screen rebuilds the live preview
   on every slider change.
3. **Expose flavor / mode pickers** when the effect has variants
   the user might want to A/B (flavor tag colors, effect type,
   pack tier, etc.). The Effect picker lets the user isolate
   *just* the thing they're tuning so it doesn't get masked.
4. **Save the FX Tuner settings to the JSON store via the same
   `VideoSettings` save pipeline** — no parallel persistence layer.
5. **Export to clipboard** is mandatory — the user pastes their
   preferred setup back for review/merging into defaults. The
   button's already in `fx_tuner.gd::_export_settings`; new
   tunables ride on top automatically.

Entry points: Main Menu → "FX Tuner" button + Pause Menu → "FX
Tuner" button. **Both** must work — the user shouldn't have to be
in a run to tune visuals.

The FX Tuner panel uses pure-black background (`Color(0,0,0,1)`) so
faint alpha effects read against neutral, not the slightly-blue
chrome panels. **Visibility** of low-alpha glows / trails matters
more than UI palette consistency on this specific screen.

When in doubt: if a magic number controls a visual, it should be a
slider. If a visual has variants, it should be a picker. If the user
ever asks "can you tweak X", the answer should already be "go to FX
Tuner."

## Plan mode for multi-step work

When a request will touch **4+ files** or changes architecture (new
subsystem, generator rewrite, save-state schema migration, etc.), enter
Plan mode first via `ExitPlanMode`. Surface:

- Affected files (with line numbers when known)
- Step-by-step sequence
- Risk areas / what could break
- Validation plan (which skill/test confirms it works)

Get user approval before editing. Catches design mistakes earlier and
produces a doc trail. For small changes (1-3 files, isolated) just edit.

## What NOT to do

- **Don't pull in DCSS *source code*** — it's GPLv2+ and would force the
  whole game open-source. Tiles only (CC0). Game logic is fresh GDScript.
- **Don't render screenshots or run the editor automatically in normal
  sessions.** The user opens Godot themselves. Screenshot mode is opt-in
  via the `/screenshot` skill or the `DEBUG_FLOOR.txt` marker file.
- **Don't reinvent skill rituals.** If you're about to wrap "write marker,
  launch Godot, sleep, kill, parse" — that's already a skill. See
  `.claude/skills/`.
- **Don't trust the PNG of a screenshot for facts.** Color hallucinations
  and small-text misreads are common at the resolution Claude's image
  pipeline downsamples to. Read the JSON sidecar first.

## Reading screenshots — the explicit rule

The `/screenshot` skill produces a 1024×1024 PNG and a sibling JSON. **Read
the JSON first.** Authoritative fields:

- `hud.*` — exact HUD strings on the screen
- `resolved.biome_id` / `display_name` / `layout_id` — what's really
  rendered
- `resolved.enemy_pool` / `vault_themes` / `ambient_decor` / `modulate` —
  biome config
- `entities.enemies[]` — every enemy with cell, hp, name, boss flags
- `entities.interactables[]` — every chest/altar/fountain/portal/loot with
  cell + kind + extras
- `render_textures.*` — all loaded floor/wall/overlay PNG paths (so you
  can verify a specific biome is using the right tile set)
- `floor.*` — width, height, floor cell count, wall cell count, room
  rectangles, stairs/spawn cells, branch label

**Then look at the PNG** for:

- Overall floor shape (cave-like vs rectangular rooms)
- Density of decor / ambient lights
- Wall vs floor color silhouettes
- Whether a vault stands out from the surrounding procedural carve

Do NOT use the PNG to:

- Read HUD numbers (HP/ATK/Gold/Level)
- Identify specific tiles by colour (dungeon stone vs sandstone vs marble
  is unreliable at thumbnail size)
- Count enemies / interactables (use the JSON arrays)

## Tile catalog and atlas

`project/data/tile_atlas.json` (1.5 MB) catalogs all 6945 PNGs in the DCSS
tile pack with category, subcategory, biome tags, class hints, variant set,
directional flags. Built from DCSS source `rltiles/dc-*.txt` plus
filesystem walk. Rebuild via `python3 tools/build_atlas.py`.

Browse interactively: `python3 -m http.server 8080` from repo root, then
visit `http://localhost:8080/tools/atlas_viewer.html`. Filter by category /
biome / class / subcategory.

**Before bulk-copying any assets**: consult the atlas. **Never hardcode
caps** like "copy 3 variants" — pull all available, or read the count
from the catalog. The atlas exists exactly for this reason.

## Biome editor

`tools/biome_editor.html` (also at `http://localhost:8080/tools/biome_editor.html`)
is a per-biome visual editor. For each biome it shows every tile that
could render (floor primary/secondary/accent, wall primary/accent/
alternates, edge overlay as a 3×3 directional grid with N/S/E/W/NE/NW/
SE/SW/FULL labels, sigil set). Each tile has a **Replace** button that
opens a picker; the schema supports `@stem` literal-tile syntax
alongside prefixes so picks are surgical. Duplicate / New blank /
Delete buttons. **Export biomes.json** downloads the modified file —
drop it into `project/data/biomes.json`. Backed by
`tools/biome_manifest.json` (rebuild via
`python3 tools/build_biome_manifest.py` whenever new tile assets land).

Use this for any "spider feels off" / "hive walls clash with floor"
review pass — visual review needs a human eye, the editor gives the
user a single page to make decisions.

## Tile-prefix gotchas (LESSONS LEARNED)

DCSS tiles aren't all "primary floor" — some prefixes are *directional
overlays* meant to be placed at specific floor cells (typically those
bordering walls). Tiling them randomly across a floor produces a "messy" /
"random" look.

**Confirmed offenders:**

- **slime**: DCSS has `slime_overlay_north/south/east/west/ne/nw/se/sw` —
  these are meant to render at floor cells *adjacent* to walls in the
  matching direction, simulating slime dripping off walls. Slime biome's
  `floor_primary` uses plain `dungeon` stone; slime walls + the edge-overlay
  system carry the biome identity.

**General rule:**

1. **Primary floor tiles must be square-symmetric and tileable in all
   directions.** No directional cracks, no edge highlights, no "drip" /
   "pool" features.
2. **Decorative / feature tiles** (runes, sigils, blood splatter, slime
   drips, moss patches with directional bias) belong in `floor_accent` at
   ~12% sprinkle density, OR in the edge-overlay autotile system (see
   HANDOVER.md).
3. **When in doubt, use the parent's plain stone floor.** A slime-themed
   wall + stone floor reads as "stone room with slime walls" — a
   slime-themed floor that's actually edge-overlays reads as "what is this
   mess." Walls carry biome identity more reliably than floors.

## Decisions on record

- **Stack:** Godot 4.6 + GDScript (user picked over the React prototype
  handoff).
- **Pathfinding:** AStarGrid2D over NavigationAgent2D / custom A* —
  engine-native C++, grid-aligned, `set_point_solid` maps 1:1 to wall tiles.
- **Number ceiling:** ~1500 HP / ~300 ATK / ~100 DEF endgame; ~300-400
  peak damage. User explicitly rejected idle-game number creep ("dont want
  to creep into players having 50000 hp").
- **DCSS source:** shallow-cloned (132 MB) into `dcss-source/`. **Research
  only — GPLv2.** Gitignored.
- **No hand-typed ASCII vaults.** All 42 hand-made vaults were deleted in
  favor of the 1320 ported DCSS vaults. The portal mechanic replaces what
  the hand-made `portal_*` encompass vaults were doing.
