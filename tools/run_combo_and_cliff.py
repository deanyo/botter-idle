#!/usr/bin/env python3
"""Run two experiments back-to-back:

Experiment A: Strength+Haste vs Strength alone (N=30, vaults).
  Tests whether stacking DPS affixes overcomes the floor-5 cliff.

Experiment B: Floor-cliff investigation at high N=50.
  Same neutral build (no affixes) at dungeon / vaults / forge.
  Goal: tight death-floor histogram per branch.

Total grinds: 60 (A) + 150 (B) = 210. Wall-clock ~3 hours.
"""
import sys, time, json
from pathlib import Path
sys.path.insert(0, '/Users/dyo/claude/botter/tools')
sys.path.insert(0, '/Users/dyo/claude/botter/.claude/skills/duel')
sys.path.insert(0, '/Users/dyo/claude/botter/.claude/skills/equip')

import balance
from parse_grind import parse
from duel import summarize


def run_grind_for_build(label, spec, seed, invincible=False):
    balance.inject(spec, reset=True)
    balance.clean_markers()
    # Pin run plan to the spec's branch via BOTTER_FORCE_BIOME — without
    # it, dungeon.gd falls through to random-biome rolls regardless of
    # last_branch, because branch_id is only set via Outpost UI flow.
    branch = str(spec.get("last_branch", ""))
    env_extra = {"BOTTER_FORCE_BIOME": branch} if branch else None
    spawn = balance.run_grind(seed=seed, runs=1, speed=16,
                              label=label, invincible=invincible,
                              env_extra=env_extra)
    g = parse(spawn.log_path)
    return g.runs[0] if g.runs else None


def variant_spec(weapon_affixes):
    return {
        "level": 30, "gold": 5000,
        "unlocked_branches": ["dungeon", "vaults"],
        "last_branch": "vaults",
        "equipped": {
            "weapon": {"base_id": "steel_longsword",
                       "affixes": weapon_affixes},
        }
    }


# =================== Experiment A: Strength+Haste duel ===================
def experiment_a():
    print("\n" + "=" * 90)
    print("EXPERIMENT A: Strength+Haste combo vs Strength alone")
    print("=" * 90)
    SEEDS = list(range(4000, 4030))  # 30 seeds, disjoint from priors

    variants = [
        ("strength5", variant_spec([["strength", 5]])),
        ("str5_haste5", variant_spec([["strength", 5], ["haste", 5]])),
    ]
    runs_a = {}
    for label, spec in variants:
        print(f"\n--- {label} ---", flush=True)
        rs = []
        for i, s in enumerate(SEEDS):
            r = run_grind_for_build(f"comboA_{label}_s{s}", spec, s)
            if r is None:
                print(f"  WARN seed={s} no run", flush=True)
                continue
            if r.seed == 0:
                r.seed = s
            outcome = "WIN " if r.victory else "LOSS"
            print(f"  [{i+1}/{len(SEEDS)}] seed={s} {outcome} f={r.end_floor} "
                  f"kills={r.kills} elapsed={r.elapsed_s:.1f}s", flush=True)
            rs.append(r)
        runs_a[label] = rs

    # Persist + summarize
    for label, rs in runs_a.items():
        balance.append_index({
            "kind": "duel_partial",
            "label": f"comboA_{label}",
            "params": {"seeds": SEEDS, "spec": str(variants)},
            "summary": summarize(label, rs),
        })

    print("\n=== Experiment A results ===")
    for label, rs in runs_a.items():
        s = summarize(label, rs)
        print(f"  {label:<20} wins={s['wins']}/{s['n']}  "
              f"win_rate={s['win_rate']:.0%}  avg_floor={s['avg_floor']:.2f}  "
              f"avg_kills={s['avg_kills']:.1f}")
    return runs_a


# =================== Experiment B: Floor-cliff investigation ===================
def experiment_b():
    print("\n" + "=" * 90)
    print("EXPERIMENT B: Floor-cliff investigation N=50 per branch (no affixes)")
    print("=" * 90)
    SEEDS = list(range(5000, 5050))  # 50 seeds
    BRANCHES = ["dungeon", "vaults", "forge"]

    runs_b = {}
    for branch in BRANCHES:
        print(f"\n--- branch={branch} ---", flush=True)
        spec = {
            "level": 30, "gold": 5000,
            "unlocked_branches": ["dungeon", branch],
            "last_branch": branch,
            "equipped": {
                "weapon": {"base_id": "steel_longsword", "affixes": []},
            }
        }
        rs = []
        for i, s in enumerate(SEEDS):
            r = run_grind_for_build(f"cliffB_{branch}_s{s}", spec, s)
            if r is None:
                print(f"  WARN seed={s} no run", flush=True)
                continue
            if r.seed == 0:
                r.seed = s
            outcome = "WIN " if r.victory else "LOSS"
            print(f"  [{i+1}/{len(SEEDS)}] seed={s} {outcome} f={r.end_floor} "
                  f"kills={r.kills} elapsed={r.elapsed_s:.1f}s", flush=True)
            rs.append(r)
        runs_b[branch] = rs
        # Persist after each branch.
        balance.append_index({
            "kind": "cliff_partial",
            "label": f"cliffB_{branch}",
            "params": {"branch": branch, "seeds": SEEDS,
                       "spec": "steel_longsword level=30 (no affixes)"},
            "summary": summarize(f"cliff_{branch}", rs),
        })

    print("\n=== Experiment B results ===")
    for branch, rs in runs_b.items():
        # Death histogram per branch
        from collections import Counter
        deaths = Counter()
        wins = 0
        for r in rs:
            if r.victory:
                wins += 1
            else:
                deaths[r.end_floor] += 1
        print(f"\n  {branch}: wins={wins}/{len(rs)}  "
              f"({wins/len(rs):.0%})")
        print(f"  death floor histogram:")
        max_floor = max([6] + list(deaths.keys()))
        for f in range(0, max_floor + 1):
            d = deaths.get(f, 0)
            bar = "█" * d
            tag = " ← BOSS FLOOR" if f == 6 else ""
            print(f"    f={f}: {d:>2} {bar}{tag}")
    return runs_b


def main():
    t0 = time.time()
    runs_a = experiment_a()
    runs_b = experiment_b()
    print(f"\n\n=== ALL EXPERIMENTS COMPLETE ===")
    print(f"Wall clock: {(time.time() - t0)/60:.1f} min")


if __name__ == "__main__":
    main()
