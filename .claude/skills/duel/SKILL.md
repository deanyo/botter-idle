---
name: duel
description: A/B test two bot builds across the same seeds. Use to settle "is X stronger than Y" questions deterministically. Args - "<build A>" -- "<build B>" [-N 20]. Build specs use /equip shorthand.
user_invocable: true
---

# Botter duel

Run two builds against the same N seeds, return a paired comparison
(win rate ± 95% CI, avg floor, avg ttk, damage by weapon). The same
floor sequence + same enemy spawns means the two builds fight the
identical world; only their gear/affixes/stats differ.

## Usage

```bash
python3 /Users/dyo/claude/botter/.claude/skills/duel/duel.py \
    "<build A spec>" -- "<build B spec>" [-N 20] [--seed-base 1] [--speed 16]
```

Build specs use `/equip` shorthand (see equip/SKILL.md).

## Examples

```bash
# Default: 20 runs each, BOTTER_SEED 1..20, default 16x speed
duel.py "weapon=demon_blade,Strength5,Crit4 level=30 branch=forge" -- \
        "weapon=runed_warsword level=30 branch=forge"

# 50 runs for tighter CI
duel.py "weapon=rusty_dagger" -- "weapon=iron_dagger" -N 50

# Specific seed range — useful if a particular seed exposes the question
duel.py "weapon=A" -- "weapon=B" -N 30 --seed-base 100

# Keep invincibility on — answers "how fast does each build clear" rather
# than "which build survives"
duel.py "weapon=A" -- "weapon=B" --invincible
```

## What it measures

Per build:
  - **win rate (95% CI)** — Wilson interval. Tighter as N grows.
  - **avg floor reached** — for non-victory runs, how deep did they get
  - **avg kills, loot, elapsed**
  - **damage by weapon** — total damage dealt by attacker.weapon across all runs

The diff column shows B−A. Negative means A was better at that metric.

## How runs are paired

For seed S in [seed-base, seed-base+N):
  1. Equip build A, run 1 grind with `BOTTER_SEED=S`
  2. Equip build B, run 1 grind with `BOTTER_SEED=S`

Same seed = same floor layout, same vault picks, same loot rolls, same
enemy spawn placements. Combat RNG is reseeded from world rng each
floor, so attack-by-attack outcomes are also deterministic per seed.
The only thing that varies between A and B is the gear/affixes you
specified.

## Where results go

Per-run logs: `logs/balance/<ts>_grind_duel_<label>_s<seed>.log`
Summary line: `logs/balance/index.jsonl` (one JSON object per duel)

Read `index.jsonl` to compare experiments over time, or grep specific
build labels.

## Caveats

- Bot invincibility is OFF by default. Without it, build differences
  affect HP loss → death → run failure → win-rate signal. Pass
  `--invincible` if you only care about clear time / damage output and
  not survival.
- Each grind launches a fresh Godot process, so wall-clock cost is
  ~30-90s per run × 2N runs. A 20-run duel ≈ 15-30 minutes.
- Currently runs sequentially. Parallel mode is on the TODO.
