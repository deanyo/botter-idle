# Botter

DCSS Reimagined as an Idle Game. Configure a bot, deploy it into a multi-floor
DCSS-style dungeon, watch it explore, fight, and loot. Swap gear between runs.

Mobile-first portrait, Godot 4.6.2-stable, GDScript only.

## Running

1. Install Godot 4.6.2-stable.
2. Open `project/` in the editor.
3. Press F5.

## Project layout

```
botter/
├── CLAUDE.md            project notes (architecture, conventions, scope)
├── project/             the Godot project — open this in the editor
│   ├── scenes/          main, dungeon, garage, run_report
│   ├── scripts/         GDScript source
│   ├── data/            biomes.json, enemies.json, items.json, tile_atlas.json,
│   │                    vaults/*.json (1320 ported DCSS vaults)
│   └── assets/tiles/    curated CC0 sprite subset shipped with the game
├── docs/                biome audit, branch research dossier
├── tools/               atlas builder + viewer (offline tooling)
└── reference/           visual reference shots
```

## Tile atlas

Every PNG used by the game (and many we haven't wired up yet) is catalogued in
`project/data/tile_atlas.json` with category, subcategory, biome tags, class
hints, variant set, directional flags, etc.

Rebuild from DCSS source: `python3 tools/build_atlas.py`. Requires both DCSS
tile packs and the DCSS source tree — neither shipped here (see Asset note).

Browse interactively: open a local web server in the repo root
(`python3 -m http.server 8080`) and visit `tools/atlas_viewer.html`.

## Asset note

The full DCSS tile packs (`dcss/`) and DCSS source (`dcss-source/`) are
gitignored. The tile pack is CC0 and 35 MB; the source is GPLv2+ and 132 MB.
The game ships only the curated tile subset under `project/assets/tiles/`.

The DCSS source is read-only research only — algorithms and data are paraphrased
and rewritten in GDScript per the rules in CLAUDE.md, never line-translated.

## Status

Core gameplay loop works end-to-end: 10 floors with biome variety, ported DCSS
vaults stamped per biome, DCSS-style portal mini-floors, fog of war, dynamic
lights, sprite FX, run journal, gear slots and affixes.
