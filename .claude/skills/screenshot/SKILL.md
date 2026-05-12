---
name: screenshot
description: Capture a Botter biome/vault screenshot for visual verification. Use when the user wants to see a biome rendered (e.g. "screenshot the lair", "show me crypt", "capture vaults floor 5"). Args - "<biome>" or "<biome> <vault_name>" or "<biome> _ <floor_num>".
user_invocable: true
---

# Botter screenshot

Capture a single-frame screenshot of a Botter biome (and optionally a forced vault) for visual sanity checking.

## Usage

The user provides a biome id (and optionally a vault name and/or floor number). Run the script:

```bash
bash /Users/dyo/claude/botter/.claude/skills/screenshot/screenshot.sh <biome> [vault_name|_] [floor_num]
```

Examples:

```bash
bash /Users/dyo/claude/botter/.claude/skills/screenshot/screenshot.sh lair
bash /Users/dyo/claude/botter/.claude/skills/screenshot/screenshot.sh tomb _ 7
bash /Users/dyo/claude/botter/.claude/skills/screenshot/screenshot.sh vaults des_vaults_vault
```

## CRITICAL: Read the JSON FIRST, then the PNG

Each capture writes BOTH files:
- **`<name>_<ts>.json`** — render manifest (biome id, HUD strings, every enemy/interactable/loot with cell+hp+kind, all loaded floor/wall/overlay textures, room rects, stairs, ambient settings). **Authoritative.**
- **`<name>_<ts>.png`** — 1024×1024 viewport snapshot. Pixel-art at 32px-per-tile, downscaled aggressively before Claude sees it.

**Always Read the JSON before the PNG.** The PNG is for shape/layout/color silhouettes ONLY:
- Color hallucinations are common (you may "see" magenta or red where the actual palette is brown/yellow)
- Small text on busy backdrops is unreadable — the HUD label, HP value, ATK number, gold count all need to come from the JSON, never guessed from the image
- Tile-detail comparisons (e.g. "is this floor a marble or a sandstone variant") need the JSON's `render_textures.floor_primary_samples` paths

The script prints the JSON and PNG paths on its last two lines:
```
JSON: /Users/dyo/Library/Application Support/Godot/app_userdata/Botter/debug_screenshots/lair_3303.json
PNG:  /Users/dyo/Library/Application Support/Godot/app_userdata/Botter/debug_screenshots/lair_3303.png
```

Read the JSON first, summarize biome + HUD facts to the user, then Read the PNG to comment on shape/density/atmosphere only.

## How it works

1. Park any active `AUTO_GRIND.txt` marker so it doesn't fight the launch.
2. Write `DEBUG_FLOOR.txt` with the screenshot flag (4th field).
3. Launch Godot with the project; Godot reads the marker, sets the window to 1024×1024, builds the requested floor, captures the viewport, writes both `.png` and `.json`, updates the manifest, and quits.
4. Poll the manifest for the new entry (no fixed sleep — exits as soon as the PNG is on disk).
5. Print both absolute paths.

Logs land in `/Users/dyo/claude/botter/logs/screenshots/<timestamp>_<biome>_<vault>_<floor>.log` (gitignored).

## Available biomes

`dungeon, dungeon_dark, mines, lair, forest, swamp, snake, shoals, orc, vaults, crypt, tomb, forge, glacier, slime, hive, labyrinth, abyss, pandemonium, zot, elf, spider, temple, depths`

## Vault names

If the user mentions a specific vault, pass it as arg 2 (e.g. `des_vaults_vault`). If no vault, pass `_` as a placeholder so floor_num still parses correctly.

## After running

The marker file `DEBUG_FLOOR.txt` remains set. Running the skill again with a new biome overwrites it. To return to normal gameplay, the user can rename `DEBUG_FLOOR.txt` to `DEBUG_FLOOR.txt.parked`.
