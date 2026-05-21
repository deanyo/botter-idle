---
name: playthrough
description: Simulate a full game playthrough start-to-end, applying configurable equip/upgrade/advance policies between runs. Use to estimate per-tier playtime and find difficulty-curve issues. Args - --equip POLICY --upgrade POLICY --advance POLICY [--max-runs 200].
user_invocable: true
---

# Botter playthrough

A playthrough = a chain of grinds where save state evolves between runs.
Inventory grows from loot. Gold accumulates. The bot levels up. Between
runs, three configurable policies decide:

- **equip policy** — which gear to wear (the bot.recompute_stats inputs)
- **upgrade policy** — which bot_upgrades to buy with available gold
- **advance policy** — when to attempt the next tier

This produces a per-tier breakdown of how many runs and how much
wall-clock time progression takes — letting us calibrate difficulty
from data instead of guessing.

## Usage

```bash
python3 /Users/dyo/claude/botter/.claude/skills/playthrough/playthrough.py \
    [--equip POLICY] [--upgrade POLICY] [--advance POLICY] \
    [--max-runs 200] [--seed-base 6000]
```

## Policies

### Equip (--equip)

| Policy            | Logic                                                   |
|-------------------|---------------------------------------------------------|
| score_weighted    | ATK*3 + DEF*5 + HP*0.5 + sum(affix_value). Default.     |
| pure_dps          | Max ATK on weapon, max DEF on every other slot.         |
| rarity_first      | Highest rarity wins, tiebreak ATK+DEF+HP.               |

### Upgrade (--upgrade)

| Policy        | Logic                                                       |
|---------------|-------------------------------------------------------------|
| round_robin   | Buy cheapest affordable upgrade (cycles through slots).     |
| combat_first  | Prioritize combat_training + toughening + conditioning.     |
| hp_first      | Prioritize conditioning + toughening for survival.          |

### Advance (--advance)

| Policy    | Logic                                                          |
|-----------|----------------------------------------------------------------|
| strict    | Try highest-tier unlocked branch immediately. (Default.)       |
| cautious  | Need 3 wins in a row at current branch before advancing.       |
| greedy    | Try next tier; retreat one tier if win rate < 30% over last 5. |

## Examples

```bash
# Default: a "neutral baseline player"
python3 .claude/skills/playthrough/playthrough.py

# Min-max DPS player
python3 .claude/skills/playthrough/playthrough.py \
    --equip pure_dps --upgrade combat_first --advance strict

# Cautious survival player
python3 .claude/skills/playthrough/playthrough.py \
    --equip score_weighted --upgrade hp_first --advance cautious

# Custom run cap (default 200 — use 50 for a quick smoke test)
python3 .claude/skills/playthrough/playthrough.py --max-runs 50
```

## Output

Per-run line during execution:
```
--- run 12 | tier 2 | branch=lair | seed=6011 ---
  pre-run: lvl=8 gold=240 hp_gear=140 atk_gear=33 def_gear=8
  upgrades: bought ['conditioning'] for 156g
  gear: weapon: rusty_dagger → iron_dagger
  equipped: wpn:iron_dagger arm:tattered_hide
  result: WIN f=6 kills=42 loot=3 elapsed=27.4s → post-run lvl=9 gold=387
```

Per-tier summary at end:
```
tier  runs  wins  win%   sim_s     last_floor  bosses_killed
1     5     5     100%   142.3     6           1
2     8     6     75%    268.4     6           1
3     14    8     57%    498.1     6           1
4     22    11    50%    827.5     6           1
5     31    9     29%    1284.6    6           1
```

`sim_s` is in-game grind seconds at 16x speed. Real-time playtime at
default 1x speed = sim_s × 16.

Logs:
- `logs/playthrough/<ts>_<equip>_<upgrade>_<advance>.log` — per-run
- `logs/playthrough/index.jsonl` — one summary line per playthrough

## Caveats

- BOTTER_NO_INVINCIBLE is set automatically (the bot must be killable
  for the simulation to mean anything).
- Runs against vaults/forge/etc may take 1-2 min each at 16x; a full
  playthrough is 30-90 min wall-clock.
- The advance policy can deadlock at unwinnable tiers if max-runs is
  hit before tier 5 boss is killed. The summary still reports up to
  whatever was reached.
- Gear inventory accumulates. To reset between policies, delete
  `botter_save_debug.json` between runs (`balance.clear_save()` works).
