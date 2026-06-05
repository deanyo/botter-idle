---
name: grind
description: Run a headless N-run benchmark grind on Botter. Use when the user wants to validate generation, measure variety, sanity-check changes, or just see runs play out at speed. Args - "<runs>" or "<runs> <speed>" (default speed 16x). Pass --mortal for balance testing (bot can die) and --branch <id> to pin every run to a specific biome.
user_invocable: true
---

# Botter grind

Drive the headless auto-grind loop and tail the log until it self-terminates.
No fixed sleep — exits the moment Godot prints `[run] auto-grind COMPLETE`.

## Usage

```bash
bash /Users/dyo/claude/botter/.claude/skills/grind/grind.sh <runs> [speed] [--mortal] [--branch <id>]
```

Examples:

```bash
# Default — invincible bot, branch picker simulates progression.
bash /Users/dyo/claude/botter/.claude/skills/grind/grind.sh 5 16

# Balance test — bot can die, runs end on first death (per the
# revives-removed change). Pair with BOTTER_PURGE_SAVE=1 for
# fresh-save baseline.
BOTTER_PURGE_SAVE=1 bash /Users/dyo/claude/botter/.claude/skills/grind/grind.sh 10 16 --mortal

# Pin every run to a specific biome (lair, crypt, vaults, forge, etc).
bash /Users/dyo/claude/botter/.claude/skills/grind/grind.sh 5 16 --branch crypt
```

`<runs>` is the number of complete runs. `<speed>` is `Engine.time_scale`
(default 16x). At 16x, a 5-run grind typically finishes in 30-90s.

### `--mortal` — disable invincibility

By default the grind bot is invincible so generation/perf audits can
reach floor 6 reliably. **For balance work pass `--mortal`** —
otherwise the bot can't die so deaths-vs-progression is unmeasurable.
Mortal mode also makes per-run length meaningful (a fresh-save run
that dies on floor 1 in 3s vs one that wins floor 6 in 90s).

### `--branch <id>` — pin every run to one biome

Forces every run to deploy to `<id>` regardless of progression.
Useful for "what does floor 1-6 look like in the lair" sweeps.
Branch ids: `dungeon`, `dungeon_dark`, `mines`, `lair`, `forest`,
`orc`, `temple`, `shoals`, `swamp`, `snake`, `spider`, `hive`,
`vaults`, `crypt`, `tomb`, `elf`, `depths`, `forge`, `glacier`,
`slime`, `labyrinth`, `abyss`, `pandemonium`, `zot`.

### Branch picker (default — no `--branch`)

Without `--branch`, the auto-grind picks deploys like a real
progression: walks tiers low → high, picks the under-cleared branch
in the lowest unlocked tier (fewest boss kills among siblings, so
kills spread evenly). Advances when each branch in the current tier
has been cleared `KILLS_PER_BRANCH_TO_UNLOCK_NEXT_TIER` times
(currently 2 — see `main.gd::_on_boss_killed`). Falls back to the
highest unlocked branch when every unlocked tier is fully cleared.

Pre-2026-06-05 the picker was missing — the dungeon got `branch_id=""`
and rolled random per-floor biomes, dropping a level-1 fresh-save bot
into tier-3 Crypt floors with rusty_dagger. That stalled grinds and
poisoned balance data. Fixed.

### Verifying compile-only changes

If you only need to confirm GDScript compiles cleanly (e.g. after a
small refactor), use the class-cache rebuild instead — it's a 5-second
parse-check that fails loudly if any script has a syntax error:

```bash
bash /Users/dyo/claude/botter/tools/refresh_class_cache.sh
```

A successful run prints `OK — cache regenerated with N classes.` Use
this for quick smoke; reserve the full grind for behavioral changes.

### Purging the debug save

The debug save persists across grind invocations so `inject_save.py`
loadouts can be tested run-after-run. When item schemas change (v2
stats, quality tiers, etc.), leftover instances may render as blank
until rolled fresh. Wipe before grinding with:

```bash
BOTTER_PURGE_SAVE=1 bash /Users/dyo/claude/botter/.claude/skills/grind/grind.sh 1
```

## How it works

1. Park any active `DEBUG_FLOOR.txt` marker so it doesn't fight the launch.
2. Write `AUTO_GRIND.txt` with `<speed>,<runs>` content.
3. Launch Godot with `--headless`, redirecting stdout to a timestamped log
   in `logs/grind/<timestamp>_<speed>x_<runs>runs.log`.
4. Tail the log; exit immediately when the `[run] auto-grind COMPLETE` line
   appears. Hard timeout = `runs × 60s` so a runaway grind doesn't hang
   forever.
5. Print a structured summary: per-run victory + level + gold + elapsed,
   total kills/loot/portals/stalls, unique biomes hit, unique vaults stamped,
   `[bad-floor]` count.

## Reading the result

The script prints both the human summary and the absolute path to the full
log on its last line. If you need details (specific stalls, exact per-floor
metrics, vault names, etc), Read the log file directly — every line is
structured and tagged (`[run]`, `[gen]`, `[floor]`, `[stall]`, `[portal]`,
`[bad-floor]`).

## Log format reminder (also in HANDOVER.md)

- `[run]` start/end with summary
- `[gen]` per-floor: `f=N biome=X layout=Y cells=Z largest=… regions=… rooms=…`
- `[floor]` per-floor outcome: `f=N biome=X ticks=… kills=… loot=… …`
- `[portal]` portal entries
- `[stall]` only on actual stalls
- `[bad-floor]` generator regression flags

## After running

The `AUTO_GRIND.txt` marker remains set. Running the skill again overwrites
it. To return to normal gameplay, rename the marker to `.parked`. (The
`/screenshot` skill does this automatically; this skill does too on next
invocation but leaves it in place between calls.)
