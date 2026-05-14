---
name: showcase
description: Launch a hand-curated visual audit floor in Botter. One station per visual feature (fire/magic/crystal decor, campfire reference, lava/water/ice, altars, fountains, loot rarities, chests, portal, fire/ice creatures). Bot patrols a fixed loop so its light reveals each station in turn. Use when the user wants to visually verify flicker, glow, particles, terrain, or any other look-and-feel concern without waiting for procgen to roll the right combination.
user_invocable: true
---

# Botter showcase

Hand-curated visual audit floor. Boots Godot windowed; bot patrols a fixed
path so each station enters its light radius in sequence.

## Usage

```bash
bash /Users/dyo/claude/botter/.claude/skills/showcase/showcase.sh
```

No arguments. The skill returns when the Godot window is closed.

## What's on the floor

80×80 single open room, outer wall ring. Stations laid out in rows:

- **Row 1 (y=12):** decor-tier light sources — fire (flame_0/1/2), magic
  (lantern + magic_lamp + orb), crystal (orb_glow + crystal_orb),
  mushroom (mold + zot_pillar), and an actor-tier **campfire** as the
  comparison reference. Use this row to verify decor-tier flicker
  matches campfire flicker visually (the campfire has a real
  PointLight2D + embers; the rest are fog-shader-only).
- **Row 2 (y=25):** liquid terrain — lava pool, water pool, ice patch,
  blue fountain, blood fountain.
- **Row 3 (y=38):** altar zoo — Trog (red), Zin (white), Vehumet
  (purple), Kiku (dark purple), Xom (chaos colours).
- **Row 4 (y=51):** loot rarity ladder (common → legendary) + normal
  chest + rich chest + portal.
- **Row 5 (y=64):** creatures with `light_spec` — fire dragon, ice
  dragon, salamander, blizzard demon, firefly. Frozen in place (no AI).

Bot patrols the row of cells one south of each station, looping. It
walks slowly enough that you can watch each station "light up" as the
bot arrives.

## When to use

- "I can't see the flicker on fire decor" → run /showcase, watch the
  fire decor row vs the campfire (actor tier).
- "Lava terrain looks washed out" → run /showcase, walk to the lava
  pool, observe.
- "Loot drops aren't distinguishable by rarity" → see Row 4 in one shot.
- Pre-flight before any visual change ("does this still look right?").

## Marker hygiene

Skill writes `DEBUG_FLOOR.txt` containing literally `showcase`, then
removes it on exit (including SIGINT / window close). If you ever
launch Godot interactively and it lands on the showcase floor, the
marker leaked — delete `~/Library/Application Support/Godot/app_userdata/Botter/DEBUG_FLOOR.txt`
and relaunch.

## Editing the showcase

Stations are declared in `project/scripts/showcase.gd::STATIONS`. Add a
new entry, give it an anchor cell, then handle the `kind` in
`dungeon.gd::_spawn_showcase_stations`. The patrol path auto-includes
every station (one cell south of each anchor).
