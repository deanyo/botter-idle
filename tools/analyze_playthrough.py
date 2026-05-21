#!/usr/bin/env python3
"""analyze_playthrough.py — Compare playthrough simulations.

Reads logs/playthrough/index.jsonl (each line = one playthrough summary)
and produces:
  - Per-tier table for each playthrough (runs, wins, sim_s, real-time)
  - Cross-policy comparison (which archetype clears fastest, hits walls)
  - Soft-wall detection (tier where progression stalls)

Usage:

    python3 tools/analyze_playthrough.py                    # last 3 entries
    python3 tools/analyze_playthrough.py --last 5
    python3 tools/analyze_playthrough.py --policy score_weighted_round_robin_strict
"""
from __future__ import annotations
import argparse
import json
import sys
from pathlib import Path

INDEX = Path(__file__).resolve().parent.parent / "logs" / "playthrough" / "index.jsonl"

# Grinds run at 16x speed_scale; multiply sim_s × 16 to get real-time playtime.
SPEED_MULT = 16


def load_runs(filter_policy: str | None = None) -> list[dict]:
    if not INDEX.exists():
        print(f"no index at {INDEX}", file=sys.stderr)
        return []
    runs = []
    for line in INDEX.open():
        try:
            e = json.loads(line)
        except json.JSONDecodeError:
            continue
        if e.get("kind") != "playthrough":
            continue
        if filter_policy:
            p = e.get("policies", {})
            label = f"{p.get('equip')}_{p.get('upgrade')}_{p.get('advance')}"
            if filter_policy not in label:
                continue
        runs.append(e)
    return runs


def policy_label(p: dict) -> str:
    pol = p.get("policies", {})
    return f"{pol.get('equip','?')}/{pol.get('upgrade','?')}/{pol.get('advance','?')}"


def fmt_time(sim_s: float) -> str:
    """Real-time playtime in friendly units."""
    real_s = sim_s * SPEED_MULT
    if real_s < 60:
        return f"{real_s:.0f}s"
    elif real_s < 3600:
        return f"{real_s/60:.1f}m"
    else:
        return f"{real_s/3600:.1f}h"


def print_per_run_table(p: dict):
    pol = policy_label(p)
    print()
    print(f"PLAYTHROUGH: {pol}")
    print(f"  total_runs={p.get('total_runs',0)}  "
          f"max_tier_reached={p.get('max_tier_reached',1)}  "
          f"final_lvl={p.get('final_level',1)}  "
          f"final_gold={p.get('final_gold',0)}  "
          f"wall_clock={p.get('wall_clock_min',0):.1f}min")
    fg = p.get("final_gear", {})
    print(f"  final gear bonuses: hp+{fg.get('hp',0)} atk+{fg.get('atk',0)} "
          f"def+{fg.get('def',0)}")

    per_tier = p.get("per_tier", {})
    print(f"  {'tier':<6}{'runs':<6}{'wins':<6}{'win%':<7}"
          f"{'sim_s':<10}{'real_time':<14}{'last_floor':<12}{'bosses_killed'}")
    print("  " + "-" * 76)
    for tier_str in ("1", "2", "3", "4", "5"):
        r = per_tier.get(tier_str, per_tier.get(int(tier_str), {}))
        if not r or r.get("runs", 0) == 0:
            continue
        wp = r["wins"] / r["runs"] * 100 if r["runs"] else 0
        sim_s = r.get("elapsed_s", 0)
        print(f"  {tier_str:<6}{r['runs']:<6}{r['wins']:<6}{wp:<7.0f}"
              f"{sim_s:<10.1f}{fmt_time(sim_s):<14}"
              f"{r.get('last_floor', 0):<12}{r.get('bosses_killed', 0)}")


def print_cross_policy_comparison(runs: list[dict]):
    print()
    print("=" * 88)
    print("CROSS-POLICY COMPARISON")
    print("=" * 88)
    if not runs:
        return

    # Header: per-policy summary in a row each
    print(f"{'policy':<48}{'runs':<8}{'max_tier':<10}{'wall_min':<10}{'final_lvl'}")
    print("-" * 88)
    for p in runs:
        pol = policy_label(p)
        print(f"{pol[:46]:<48}"
              f"{p.get('total_runs',0):<8}"
              f"{p.get('max_tier_reached',1):<10}"
              f"{p.get('wall_clock_min',0):<10.1f}"
              f"{p.get('final_level',1)}")

    # Real-time playtime per tier per policy
    print()
    print("REAL-TIME PLAYTIME PER TIER (sim_s × 16)")
    print("-" * 88)
    print(f"{'policy':<48}", end="")
    for t in (1, 2, 3, 4, 5):
        print(f"{'T'+str(t):<8}", end="")
    print()
    for p in runs:
        pol = policy_label(p)
        per_tier = p.get("per_tier", {})
        print(f"{pol[:46]:<48}", end="")
        for t in (1, 2, 3, 4, 5):
            r = per_tier.get(str(t), per_tier.get(t, {}))
            sim_s = r.get("elapsed_s", 0)
            cell = fmt_time(sim_s) if sim_s > 0 else "-"
            print(f"{cell:<8}", end="")
        print()

    # Win rate per tier per policy
    print()
    print("WIN RATE PER TIER")
    print("-" * 88)
    print(f"{'policy':<48}", end="")
    for t in (1, 2, 3, 4, 5):
        print(f"{'T'+str(t):<8}", end="")
    print()
    for p in runs:
        pol = policy_label(p)
        per_tier = p.get("per_tier", {})
        print(f"{pol[:46]:<48}", end="")
        for t in (1, 2, 3, 4, 5):
            r = per_tier.get(str(t), per_tier.get(t, {}))
            if r.get("runs", 0) == 0:
                cell = "-"
            else:
                wp = r["wins"] / r["runs"] * 100
                cell = f"{wp:.0f}%"
            print(f"{cell:<8}", end="")
        print()

    # Soft-wall detection: tier where most runs were spent
    print()
    print("SOFT-WALL DETECTION")
    print("-" * 88)
    for p in runs:
        pol = policy_label(p)
        per_tier = p.get("per_tier", {})
        max_tier = 1
        max_runs = 0
        for t_str in ("1", "2", "3", "4", "5"):
            r = per_tier.get(t_str, per_tier.get(int(t_str), {}))
            n = r.get("runs", 0)
            if n > max_runs:
                max_runs = n
                max_tier = int(t_str)
        # Wall = where the player spent the most attempts before progressing
        # (or stalled out entirely).
        max_reached = p.get("max_tier_reached", 1)
        if max_reached < 5:
            print(f"  {pol[:46]:<48} stalled at tier {max_reached} "
                  f"(spent {max_runs} runs at tier {max_tier})")
        else:
            print(f"  {pol[:46]:<48} cleared. Most attempts: tier {max_tier} "
                  f"({max_runs} runs)")


def main():
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--last", type=int, default=3,
                   help="How many recent playthroughs to include (default 3).")
    p.add_argument("--policy",
                   help="Substring filter on policy label "
                        "(e.g. 'score_weighted', 'cautious').")
    args = p.parse_args()

    runs = load_runs(args.policy)
    if not runs:
        print("no playthroughs in index.", file=sys.stderr)
        return 1
    target = runs[-args.last:]

    for run in target:
        print_per_run_table(run)
    if len(target) > 1:
        print_cross_policy_comparison(target)
    return 0


if __name__ == "__main__":
    sys.exit(main() or 0)
