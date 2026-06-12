---
name: grind-rarity-histogram
description: Run N headless grinds and produce a per-floor rarity histogram (ASCII table to stdout + CSV). Use to validate the T1 rarity curve after `loot_factory.gd::roll_rarity` rewrites or `drop_tuning.json` weight tweaks. Args - "<runs> [--branch <id>] [--preset <name>] [--mortal] [--tier <n>]".
user_invocable: true
---

# Botter grind-rarity-histogram

Drives N headless `/grind`-style runs, parses every `[loot] f=N rarity=X
base=Y` line that `dungeon.gd::_spawn_loot_drop` emits, and produces a
per-floor rarity histogram so loot-curve changes can be validated
empirically instead of by visual diff.

## Usage

```bash
python3 /Users/dyo/claude/botter/.claude/skills/grind-rarity-histogram/grind_rarity_histogram.py <runs> [options]
```

Options (all optional):
- `--branch <id>` — pin every run to one biome (forwarded to grind).
- `--preset <name>` — fresh-save tier-appropriate loadout (naked, t1-t5).
- `--mortal` — disable bot invincibility (recommended for balance work).
- `--tier <n>` — filter the histogram to floors 1-6 of T<n> only (per-tier
  validation; matches A12 spec). Without `--tier`, all floors are tabulated.

Examples:

```bash
# 50-run T1 baseline — what the rarity curve actually produces on D:1-3.
python3 .claude/skills/grind-rarity-histogram/grind_rarity_histogram.py 50 --preset t1 --mortal --tier 1

# Branch-specific check after authoring biome-targeted drops.
python3 .claude/skills/grind-rarity-histogram/grind_rarity_histogram.py 30 --branch lair --mortal

# Quick smoke (default tier filter off).
python3 .claude/skills/grind-rarity-histogram/grind_rarity_histogram.py 10
```

## Output

ASCII table to stdout:

```
floor   common  uncommon  rare    epic    legendary  total
1       28      52        18      2       0          100
2       30      50        17      3       0          100
...
```

Plus a CSV at `logs/balance/rarity_hist_<timestamp>.csv` for the
`tools/drop_tuning.html` rarity-histogram view (T1-5, Beat 2 §2.G).

## How it works

Wraps the existing `/grind` skill (`grind.sh`). Each run emits
`[loot] f=N rarity=X base=Y` lines into the timestamped grind log; the
script parses them, accumulates `(floor, rarity)` counts, and prints both
the raw counts and per-floor row-percentages.

## Validation

Per CHECKLIST §1.J: "runs to completion; CSV has 30+ floor rows" —
satisfied once a 50-run grind crosses floor 30 in any single run.
With `--preset t1 --mortal` most runs die before floor 6 so the row
count is naturally bounded by the tier band — that's intentional.
