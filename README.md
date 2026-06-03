# Botter

**DCSS reimagined as an idle game.** Configure a bot, deploy it into a
DCSS-style dungeon, watch it explore, fight, and loot. Swap gear and tune
upgrades between runs.

Desktop landscape (1600×900), Godot 4.6.2-stable, GDScript only.
Mobile port deferred.

![status](https://img.shields.io/badge/status-active%20development-ffb84d)

---

## What's in here

- **DCSS-faithful generation.** Trail+rooms, delve caves, river/lake,
  Worley layouts, all ported in spirit from DCSS source (read, described,
  rewritten in GDScript — never line-translated; DCSS is GPLv2+).
- **1320 ported DCSS vaults.** 25-83% of floors land a stamped vault.
- **24 biomes across 5 tiers** — Dungeon, Lair, Vaults, Crypt, Tomb,
  Forge, Glacier, Slime, Hive, Pandemonium, Zot, etc.
- **234 items across 7 slots** with rarity, flavor tags, drop-weights.
  13 flavor mechanics wired (vampiric, fire DoT, holy bonus, thorns,
  reflective, …).
- **PoE-style monsters.** Magic / rare pack mobs with random modifiers
  (hasted / tough / vicious / vampiric / regenerating / stalwart),
  size jitter, persistent tier outlines (red boss / orange miniboss /
  gold rare / blue magic). Pack-clustered spawns yield 50–150 mobs/floor.
- **Bot AI.** Sticky-target priority engine: adjacent-attack →
  current-room loot → low-HP retreat → aggro within 8 cells →
  unvisited rooms → stairs.
- **Per-deploy modifiers.** 8 run modifiers (Crowded, Treasure Hoard,
  Endless, Bloodlust, Boss Hunt, etc.) re-rolled each Outpost visit.
- **Death retreat.** HP=0 spends a revive (3/run by default) and
  respawns at floor 1 of the same branch.
- **Idle loop.** Offline progress (capped 1h), auto-salvage, loot
  filters, gold-sink upgrades, "While You Were Away" summary.
- **Shop.** Real-time-rotating stock with daily modifiers (Weapon Day,
  Fire Sale, Legendary Seeker…) refreshing every 15 minutes.
- **Visual systems.** Sprite-localised glow shader, flavor-tinted
  weapon overlays, swing trails (fire / cold / vampiric / holy /
  poison / thunderous), hand-side enchant ambience, threat outlines,
  smooth shader fog of war, per-biome color grading.
- **FX Tuner.** Live paperdoll preview + 8 sliders for visual knobs
  (glow strength, pulse, thickness, hand alpha/scale, trail amount/
  lifetime, item tint). Reachable from main menu and pause menu.

## Running the game

1. Install Godot 4.6.2-stable.
2. Open `project/` in the editor.
3. Press F5 (or run from main scene).

## Authoring tools

Browser-based editors, hosted at:

> **https://dnyo.co.uk/botter-idle/**

Built and deployed automatically on push to main via the workflow at
`.github/workflows/pages.yml`.

- **Atlas Viewer** — browse 6,945 catalogued tiles by category, biome,
  class, subdir.
- **Biome Editor** — visual per-biome tile editor with picker UI.
- **Item Editor** — slot-tabbed (1H sword / helm / armor / shield /
  boots / ring / amulet) with stats, drop weights, flavor tags, lore.
- **Affix / Enchant Editor** — color picker, stat dropdown, tier
  values, live rarity-colored preview card.

Want to author content locally:

```bash
git clone https://github.com/deanyo/botter-idle.git
cd botter-idle
python3 -m http.server 8080
# open http://localhost:8080/tools/
```

Each editor has an **⬇ Export** button. Drop the JSON into a GitHub
issue — if accepted, it lands in `project/data/` next release.

## Project layout

```
botter/
├── CLAUDE.md            project notes (architecture, conventions, scope)
├── HANDOVER.md          point-in-time snapshot of what's shipping today
├── TODO.md              roadmap, deferred items, asset gaps
├── docs/                biome audit, branch dossier, balance findings
├── project/             the Godot project — open this in the editor
│   ├── scenes/          main, dungeon, outpost, run_report, shop,
│   │                    fx_tuner, video_options
│   ├── scripts/         GDScript source — bot, dungeon, enemy,
│   │                    pathfinding, paperdoll_renderer,
│   │                    biome_data, vault_library, dcss_layouts, …
│   ├── data/            biomes.json, enemies.json, items.json,
│   │                    affixes.json, monster_mods.json,
│   │                    shop_modifiers.json, modifiers.json,
│   │                    bot_upgrades.json, tile_atlas.json,
│   │                    vaults/*.json (1320 ported DCSS vaults)
│   └── assets/tiles/    curated CC0 sprite subset shipped with the game
├── tools/               atlas + biome + item + affix editors,
│                        atlas builder, sync_items, balance pipeline
├── reference/           visual reference shots
├── dcss/                gitignored — full DCSS tile pack (CC0)
└── dcss-source/         gitignored — DCSS source (GPLv2+, research only)
```

## Skills (Claude Code)

The repo ships with project-scoped skills under `.claude/skills/`:

- `/screenshot <biome> [vault] [floor]` — captures a labeled PNG +
  authoritative JSON sidecar for visual review.
- `/grind <runs> [speed]` — headless N-run benchmark. Returns a
  structured summary (per-run win/loot/floors, totals, uniqueness).
- `/equip "<spec>"` — write a build to the debug save without
  launching Godot.
- `/duel "<a>" -- "<b>"` — A/B two builds across the same N seeds
  with paired Wilson-CI win-rate stats.
- `/sweep --slot W --values @legendary` — vary one parameter across
  many runs, ranked output.
- `/playthrough` — simulate a full game start-to-end with
  configurable equip / upgrade / advance policies.

## Tile atlas

Every PNG in the curated subset (and many in the DCSS pack we haven't
wired yet) is catalogued in `project/data/tile_atlas.json` with
category, subcategory, biome tags, class hints, variant set,
directional flags. Rebuild via `python3 tools/build_atlas.py`.

## Sanity check

`python3 tools/check_biome_assets.py` walks every biome's tile
references and verifies they resolve to actual files. Run before
committing biome edits — exits non-zero on broken references for CI
integration.

## Asset note

The full DCSS tile pack (`dcss/`, ~35 MB CC0) and DCSS source tree
(`dcss-source/`, ~132 MB GPLv2+) are gitignored. The game ships only
the curated subset under `project/assets/tiles/`.

DCSS source is read-only research. Per `CLAUDE.md`, algorithms are
paraphrased and rewritten in GDScript — never line-translated — so
the project stays free of GPLv2+ obligations on its game logic.

## License

Game logic: TBD (likely a permissive license for the GDScript code).
Tile sprites: CC0 (RLTiles / DCSS contributors). Vault `.des` data
ports: format is data, not code (free to use).

## Status & roadmap

See `HANDOVER.md` for the point-in-time snapshot of what's shipping.
See `TODO.md` for active roadmap, deferred items, and balance beats.
