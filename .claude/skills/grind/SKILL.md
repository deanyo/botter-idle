---
name: grind
description: Run a headless N-run benchmark grind on Botter. Use when the user wants to validate generation, measure variety, sanity-check changes, or just see runs play out at speed. Args - "<runs>" or "<runs> <speed>" (default speed 16x).
user_invocable: true
---

# Botter grind

Drive the headless auto-grind loop and tail the log until it self-terminates.
No fixed sleep — exits the moment Godot prints `[run] auto-grind COMPLETE`.

## Usage

```bash
bash /Users/dyo/claude/botter/.claude/skills/grind/grind.sh <runs> [speed]
```

Examples:

```bash
bash /Users/dyo/claude/botter/.claude/skills/grind/grind.sh 3
bash /Users/dyo/claude/botter/.claude/skills/grind/grind.sh 5 16
bash /Users/dyo/claude/botter/.claude/skills/grind/grind.sh 10 8
```

`<runs>` is the number of complete 10-floor runs. `<speed>` is the
`Engine.time_scale` multiplier (default 16). At 16x, a 5-run grind typically
finishes in 30-90 seconds.

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
