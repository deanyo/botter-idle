#!/usr/bin/env python3
"""duel.py — A/B test two builds across the same seed sequence.

Usage:

    python3 duel.py "<build A spec>" -- "<build B spec>" [N=20] [seed_base=1] [speed=16]

Build specs use the same shorthand as /equip (see equip.py).

What it does:
  1. For each seed S in [seed_base, seed_base+N):
     a. /equip build A → /grind 1 with BOTTER_SEED=S
     b. /equip build B → /grind 1 with BOTTER_SEED=S
  2. Parse both logs, build paired comparison.
  3. Print summary table (win rates with 95% CI, avg floor, avg kills,
     avg ttk, damage by weapon, etc).
  4. Append one summary line to logs/balance/index.jsonl.

Each grind runs with BOTTER_NO_INVINCIBLE=1 by default (so failure is
possible and win-rate has signal). To opt back into invincibility for
"how fast can each build clear" (where survival is guaranteed and you
only care about elapsed/damage), pass --invincible.
"""

from __future__ import annotations
import argparse
import math
import re
import subprocess
import sys
from collections import Counter
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent.parent.parent
sys.path.insert(0, str(REPO_ROOT / "tools"))
sys.path.insert(0, str(REPO_ROOT / ".claude" / "skills" / "equip"))

import balance
from parse_grind import parse, GrindResult, RunResult
from equip import parse_args as parse_equip_args
import shlex


def equip_from_spec(spec_str: str) -> None:
    """Parse a /equip-style shorthand spec and write to debug save."""
    if spec_str.strip().startswith("{"):
        # Pass-through JSON.
        import json
        spec = json.loads(spec_str)
    else:
        spec = parse_equip_args(shlex.split(spec_str))
    balance.inject(spec, reset=True)


def branch_from_spec(spec_str: str) -> str:
    """Extract the branch= value (or last_branch from JSON spec). Returns
    '' if no branch specified — caller falls through to the random-roll
    path. The dungeon runtime only honors `branch_id` when a non-empty
    value is passed through BOTTER_FORCE_BIOME, so this is what pins the
    run plan to a single biome."""
    if spec_str.strip().startswith("{"):
        import json
        spec = json.loads(spec_str)
        return str(spec.get("last_branch", ""))
    for tok in shlex.split(spec_str):
        if tok.startswith("branch="):
            return tok.split("=", 1)[1]
    return ""


def wilson_ci(k: int, n: int, z: float = 1.96) -> tuple[float, float]:
    """Wilson 95% CI for a binomial proportion (k wins of n)."""
    if n == 0:
        return (0.0, 0.0)
    p = k / n
    denom = 1 + z * z / n
    center = (p + z * z / (2 * n)) / denom
    margin = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n)) / denom
    return (max(0.0, center - margin), min(1.0, center + margin))


def run_one(label: str, spec_str: str, seeds: list[int], speed: int,
            invincible: bool) -> list[RunResult]:
    """Run N grinds with the given build, one per seed. Returns flat list of RunResults."""
    runs: list[RunResult] = []
    branch = branch_from_spec(spec_str)
    env_extra = {"BOTTER_FORCE_BIOME": branch} if branch else None
    for i, s in enumerate(seeds):
        equip_from_spec(spec_str)
        balance.clean_markers()
        spawn = balance.run_grind(seed=s, runs=1, speed=speed,
                                  label=f"duel_{label}_s{s}",
                                  invincible=invincible,
                                  env_extra=env_extra)
        g = parse(spawn.log_path)
        if not g.runs:
            print(f"  WARN: build {label} seed={s} produced no [run] start — log={spawn.log_path}",
                  file=sys.stderr)
            continue
        # Stamp seed into the run record (parse picks it up from the log,
        # but if the run aborted before [run] start completed it's 0).
        if g.runs[0].seed == 0:
            g.runs[0].seed = s
        runs.extend(g.runs)
        outcome = "WIN " if g.runs[0].victory else "LOSS"
        print(f"  [{i+1}/{len(seeds)}] {label}: seed={s} {outcome} f={g.runs[0].end_floor} "
              f"kills={g.runs[0].kills} loot={g.runs[0].loot} elapsed={g.runs[0].elapsed_s:.1f}s")
    return runs


def summarize(label: str, runs: list[RunResult]) -> dict:
    if not runs:
        return {"label": label, "n": 0}
    wins = sum(1 for r in runs if r.victory)
    n = len(runs)
    wr_lo, wr_hi = wilson_ci(wins, n)
    weapon_damage = Counter()
    for r in runs:
        for ev in r.combat:
            if ev.attacker == "bot":
                weapon_damage[ev.weapon or "(unarmed)"] += ev.dealt
    return {
        "label": label, "n": n,
        "wins": wins,
        "win_rate": wins / n,
        "win_rate_ci95": [wr_lo, wr_hi],
        "avg_floor": sum(r.end_floor for r in runs) / n,
        "avg_kills": sum(r.kills for r in runs) / n,
        "avg_loot": sum(r.loot for r in runs) / n,
        "avg_elapsed_s": sum(r.elapsed_s for r in runs) / n,
        "total_dmg_by_weapon": dict(weapon_damage.most_common()),
    }


def print_table(a: dict, b: dict):
    print()
    print(f"{'metric':<24}{'A: '+a.get('label','A'):<28}{'B: '+b.get('label','B'):<28}{'Δ':<10}")
    print("-" * 90)
    rows = [
        ("n", "n", lambda d: d.get("n", 0), "{:d}"),
        ("wins", "wins", lambda d: d.get("wins", 0), "{:d}"),
        ("win_rate", "win_rate (95% CI)", lambda d:
            f"{d.get('win_rate',0):.0%} [{d.get('win_rate_ci95',[0,0])[0]:.0%}, "
            f"{d.get('win_rate_ci95',[0,0])[1]:.0%}]", "{}"),
        ("avg_floor", "avg floor reached", lambda d: d.get("avg_floor", 0), "{:.2f}"),
        ("avg_kills", "avg kills/run", lambda d: d.get("avg_kills", 0), "{:.1f}"),
        ("avg_loot", "avg loot/run", lambda d: d.get("avg_loot", 0), "{:.1f}"),
        ("avg_elapsed_s", "avg elapsed (s)", lambda d: d.get("avg_elapsed_s", 0), "{:.1f}"),
    ]
    for key, label, getter, fmt in rows:
        va, vb = getter(a), getter(b)
        if isinstance(va, (int, float)) and isinstance(vb, (int, float)):
            diff = vb - va
            diff_s = f"{diff:+.2f}" if isinstance(va, float) else f"{diff:+d}"
        else:
            diff_s = ""
        if fmt == "{}":
            sa, sb = va, vb
        else:
            sa = fmt.format(va)
            sb = fmt.format(vb)
        print(f"{label:<24}{str(sa):<28}{str(sb):<28}{diff_s:<10}")
    print()
    print("damage dealt by bot weapon (totals across all runs):")
    weapons = sorted(set(a.get("total_dmg_by_weapon", {}).keys()) |
                     set(b.get("total_dmg_by_weapon", {}).keys()))
    for w in weapons:
        wa = a.get("total_dmg_by_weapon", {}).get(w, 0)
        wb = b.get("total_dmg_by_weapon", {}).get(w, 0)
        print(f"  {w:<28}{wa:>10}{wb:>10}")


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("a", help="Build A spec (shorthand or JSON).")
    parser.add_argument("--", dest="sep", action="store_true", help="(separator)")
    parser.add_argument("b", help="Build B spec.")
    parser.add_argument("-N", "--runs", type=int, default=20, help="Runs per build (default 20).")
    parser.add_argument("--seed-base", type=int, default=1,
                        help="Seeds used: [seed-base, seed-base+N). Default 1.")
    parser.add_argument("--speed", type=int, default=16, help="Engine.time_scale (default 16).")
    parser.add_argument("--label-a", default="A", help="Label for build A in output.")
    parser.add_argument("--label-b", default="B", help="Label for build B in output.")
    parser.add_argument("--invincible", action="store_true",
                        help="Keep grind invincibility (default: off, so wins/losses are real).")
    args = parser.parse_args()

    seeds = list(range(args.seed_base, args.seed_base + args.runs))
    print(f"Duel: {args.runs} seeds (base {args.seed_base}), speed {args.speed}x, "
          f"invincible={args.invincible}")
    print(f"  A: {args.a}")
    print(f"  B: {args.b}")
    print()

    print("--- Build A ---")
    runs_a = run_one(args.label_a, args.a, seeds, args.speed, args.invincible)
    print()
    print("--- Build B ---")
    runs_b = run_one(args.label_b, args.b, seeds, args.speed, args.invincible)

    summary_a = summarize(args.label_a, runs_a)
    summary_b = summarize(args.label_b, runs_b)
    print_table(summary_a, summary_b)

    # Persist to ledger.
    balance.append_index({
        "kind": "duel",
        "label": f"{args.label_a}_vs_{args.label_b}",
        "params": {
            "spec_a": args.a, "spec_b": args.b,
            "runs": args.runs, "seed_base": args.seed_base,
            "speed": args.speed, "invincible": args.invincible,
        },
        "a": summary_a,
        "b": summary_b,
    })
    print(f"appended summary to {balance.INDEX_PATH}")
    return 0


if __name__ == "__main__":
    # Manual argv split because argparse can't natively handle a `--` separator
    # between two positional strings on its own. We do it ourselves so users
    # can write: duel.py "weapon=A" -- "weapon=B" -N 50.
    argv = sys.argv[1:]
    if "--" in argv:
        idx = argv.index("--")
        a_part, rest = argv[:idx], argv[idx + 1:]
        if not a_part or not rest:
            print("usage: duel.py \"<build A>\" -- \"<build B>\" [-N 20] [--seed-base N] [--speed S]",
                  file=sys.stderr)
            sys.exit(2)
        # First arg of rest is build B; the rest are flags.
        new_argv = [a_part[0], rest[0]] + a_part[1:] + rest[1:]
        sys.argv = [sys.argv[0]] + new_argv
    sys.exit(main())
