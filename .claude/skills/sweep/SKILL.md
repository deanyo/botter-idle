---
name: sweep
description: Vary one parameter across many runs and rank the results. Use when comparing 3+ items in a slot, finding underpowered uniques, or tuning an affix tier curve. Args - --slot weapon --values @legendary -N 10, OR --affix crit --tiers 1,2,3,4,5.
user_invocable: true
---

# Botter sweep

Run N grinds for each variant of a single parameter, return a ranked
table by win rate. The same seed sequence is used for every variant
so the comparison is paired (variant-A and variant-B fight the same
floors).

## Usage

```bash
python3 /Users/dyo/claude/botter/.claude/skills/sweep/sweep.py \
    [--slot S --values V] OR [--affix A --tiers T] \
    [--base "<other gear>"] -N 10
```

## Examples

```bash
# Compare 4 specific weapons
sweep.py --slot weapon \
    --values demon_blade,runed_warsword,thunder_cleaver,dawnbreaker \
    --base "armor=crystal_plate,Stamina5 level=30 branch=forge" -N 10

# Find underpowered legendaries — uses @set sugar
sweep.py --slot weapon --values @legendary \
    --base "armor=crystal_plate,Stamina5 level=30 branch=forge" -N 5

# Find underpowered armor uniques across all branches
sweep.py --slot armor --values @legendary_armor \
    --base "weapon=demon_blade,Strength5 level=30" -N 5

# Sweep crit tiers — answers "is tier-5 crit too strong?"
sweep.py --affix crit --tiers 1,2,3,4,5 \
    --base "weapon=demon_blade,Strength5 armor=crystal_plate,Stamina5 \
            level=30 branch=forge" -N 10
```

## @set tokens (item sweep only)

Resolve to lists of items from `project/data/items.json`:
  - `@legendary` — all legendaries in the matching slot
  - `@epic_weapon`, `@rare_armor`, etc.
  - `@helm`, `@shield`, etc. — all items in the slot regardless of rarity

The matching slot defaults to whatever `--slot` you passed; use the
qualified form (`@legendary_armor`) to override.

## Output

Ranked table by win rate (then avg floor, then avg kills as tiebreakers):

```
rank variant                     wins   win_rate              floor   kills   elapsed
1    demon_blade                 9      90% [56%,100%]        5.80    72.1    35.2
2    runed_warsword              7      70% [40%,89%]         5.10    61.5    38.4
3    thunder_cleaver             5      50% [24%,76%]         4.50    52.3    41.0
...
```

Summary line appended to `logs/balance/index.jsonl`.

## Caveats

- N runs per variant — total grinds = variants × N. A 10-variant sweep
  with N=10 is 100 grinds (≈ 50-90 minutes).
- Default `--invincible` is OFF (so wins/losses matter). Pass
  `--invincible` when you only care about clear time / damage output.
- `--affix` mode requires `--base` to already equip the slot you're
  attaching the affix to (default `--apply-to-slot weapon`).
