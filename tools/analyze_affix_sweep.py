#!/usr/bin/env python3
"""analyze_affix_sweep.py — Cross-branch comparison for affix-tier sweeps.

Reads logs/balance/index.jsonl, finds the most recent N affix sweeps (default
3, one per branch), and prints a tier × branch grid showing win rate, avg
floor, avg kills, and avg elapsed.

Usage:

    python3 tools/analyze_affix_sweep.py                  # last 3 entries
    python3 tools/analyze_affix_sweep.py --affix crit     # last 3 crit sweeps
    python3 tools/analyze_affix_sweep.py --last 5         # last 5 sweeps
"""

from __future__ import annotations
import argparse
import json
import sys
from pathlib import Path

INDEX = Path(__file__).resolve().parent.parent / "logs" / "balance" / "index.jsonl"


def load_sweeps(filter_affix: str | None = None) -> list[dict]:
    if not INDEX.exists():
        print(f"no index at {INDEX}", file=sys.stderr)
        return []
    sweeps = []
    for line in INDEX.open():
        try:
            e = json.loads(line)
        except json.JSONDecodeError:
            continue
        if e.get("kind") != "sweep":
            continue
        if filter_affix and e.get("params", {}).get("affix") != filter_affix:
            continue
        sweeps.append(e)
    return sweeps


def branch_of(sweep: dict) -> str:
    base = sweep.get("params", {}).get("base", "")
    for tok in base.split():
        if tok.startswith("branch="):
            return tok.split("=", 1)[1]
    return "?"


def affix_of(sweep: dict) -> str:
    return sweep.get("params", {}).get("affix", "?")


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--affix", help="Only consider sweeps of this affix.")
    parser.add_argument("--last", type=int, default=3,
                        help="How many recent sweeps to include (default 3 = one per branch).")
    args = parser.parse_args()

    sweeps = load_sweeps(args.affix)
    if not sweeps:
        print("no matching sweeps in index.", file=sys.stderr)
        return 1
    target = sweeps[-args.last:]

    by_branch: dict[str, dict] = {}
    affix_label = ""
    for sw in target:
        b = branch_of(sw)
        by_branch[b] = sw
        affix_label = affix_of(sw)

    print()
    print("=" * 100)
    title = f"AFFIX TIER CURVE: {affix_label}" if affix_label else "AFFIX TIER CURVE"
    print(f"{title} — win rate × avg floor × avg kills × elapsed, by branch")
    print("=" * 100)
    print()

    branches = list(by_branch)
    # Stable ordering: dungeon → vaults → forge first if present, then alpha
    canonical = ["dungeon", "lair", "orc", "vaults", "crypt", "tomb", "forge",
                 "glacier", "elf", "snake", "spider", "shoals", "swamp",
                 "slime", "hive", "labyrinth", "abyss", "pandemonium", "zot"]
    branches.sort(key=lambda b: (canonical.index(b) if b in canonical else 999, b))

    hdr = "tier".ljust(8) + "metric".ljust(20)
    for b in branches:
        hdr += f"{b:<26}"
    print(hdr)
    print("-" * 100)

    # Discover the tier set across all branches
    all_tiers: set[int] = set()
    for sw in target:
        for v in sw["ranked"]:
            label = v["label"]
            if label.startswith(affix_label) and label[len(affix_label):].isdigit():
                all_tiers.add(int(label[len(affix_label):]))
    tiers = sorted(all_tiers)

    # Build {tier: {branch: variant_dict}}
    data: dict[int, dict[str, dict]] = {t: {} for t in tiers}
    for branch, sw in by_branch.items():
        for v in sw["ranked"]:
            label = v["label"]
            if label.startswith(affix_label):
                rest = label[len(affix_label):]
                if rest.isdigit():
                    data[int(rest)][branch] = v

    metrics = [
        ("wins/n", lambda v: f"{v.get('wins',0)}/{v.get('n',0)}"),
        ("win_rate (CI)", lambda v: (
            f"{v.get('win_rate',0):.0%} "
            f"[{v.get('win_rate_ci95',[0,0])[0]:.0%},{v.get('win_rate_ci95',[0,0])[1]:.0%}]"
        )),
        ("avg_floor", lambda v: f"{v.get('avg_floor',0):.2f}"),
        ("avg_kills", lambda v: f"{v.get('avg_kills',0):.1f}"),
        ("avg_elapsed_s", lambda v: f"{v.get('avg_elapsed_s',0):.1f}"),
    ]
    for tier in tiers:
        for i, (mname, mfn) in enumerate(metrics):
            line = (f"{affix_label}{tier}".ljust(8) if i == 0 else "".ljust(8)) + mname.ljust(20)
            for b in branches:
                v = data[tier].get(b, {})
                line += f"{mfn(v):<26}"
            print(line)
        print()

    print()
    print("=" * 100)
    print(f"SLOPE: tier {tiers[0]} → tier {tiers[-1]}, per branch")
    print("=" * 100)
    for b in branches:
        wr = [data[t].get(b, {}).get("win_rate", 0) for t in tiers]
        fl = [data[t].get(b, {}).get("avg_floor", 0) for t in tiers]
        kl = [data[t].get(b, {}).get("avg_kills", 0) for t in tiers]
        print()
        print(f"  {b}:")
        print(f"    win_rate    by tier:  {' → '.join(f'{w:.0%}' for w in wr)}")
        print(f"    avg_floor   by tier:  {' → '.join(f'{f:.2f}' for f in fl)}")
        print(f"    avg_kills   by tier:  {' → '.join(f'{k:.0f}' for k in kl)}")
        print(f"    Δ tier{tiers[0]}→tier{tiers[-1]}: "
              f"win_rate {wr[-1]-wr[0]:+.0%}, "
              f"floor {fl[-1]-fl[0]:+.2f}, "
              f"kills {kl[-1]-kl[0]:+.0f}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
