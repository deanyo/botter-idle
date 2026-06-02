#!/usr/bin/env python3
"""analyze_cliff_t2t3.py — summarize the T2/T3 cliff fill-in.

Reads the cliff_t2t3_<branch> rows that run_cliff_t2t3.py appends to
logs/balance/index.jsonl, prints a one-page summary suitable for
pasting into docs/balance-findings-2026-06-02.md.

Usage:
    python3 tools/analyze_cliff_t2t3.py
"""

import json
from collections import defaultdict
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
INDEX = REPO / "logs" / "balance" / "index.jsonl"


def main() -> int:
    rows = []
    with open(INDEX) as f:
        for line in f:
            try:
                row = json.loads(line)
            except json.JSONDecodeError:
                continue
            if row.get("kind") == "cliff_partial" \
                    and row.get("label", "").startswith("cliff_t2t3_"):
                rows.append(row)

    if not rows:
        print("no cliff_t2t3_* rows found yet — experiment still running?")
        return 0

    # Take the latest row per branch (in case the experiment is re-run).
    latest = {}
    for row in rows:
        branch = row["params"]["branch"]
        if branch not in latest or row["ts"] > latest[branch]["ts"]:
            latest[branch] = row

    print("\n=== T2/T3 cliff fill-in ===\n")
    print(f"{'branch':10s} {'tier':>4s}  {'wins/n':>8s}  "
          f"{'win%':>5s}  {'avg_floor':>9s}  {'avg_kills':>9s}  {'avg_s':>5s}")
    print("-" * 72)
    branch_tier = {"lair": 2, "swamp": 3, "vaults": 4}
    for branch in ["lair", "swamp", "vaults"]:
        if branch not in latest:
            continue
        s = latest[branch]["summary"]
        n = s["n"]
        wins = s["wins"]
        rate = 100 * s["win_rate"]
        print(f"{branch:10s} T{branch_tier[branch]:<3d}  {wins:>3d}/{n:<3d}    "
              f"{rate:>4.0f}%  {s['avg_floor']:>9.2f}  "
              f"{s['avg_kills']:>9.1f}  {s['avg_elapsed_s']:>5.1f}")

    # Cross-tier shape: which tier shows the cliff?
    print("\n--- death-floor histograms (where the runs ended) ---")
    # We don't have per-run dump in the partial summary, so just show
    # the avg_floor as a proxy. For full histograms, parse the per-run
    # log files in logs/balance/cliff_t2t3_*_s<seed>.log.

    # Comparison vs the 2026-06-02 doc: T1 96% (dungeon), T4 0%, T5 0%.
    print("\n--- vs prior runs ---")
    print("T1 (dungeon):  96% wins  (from 2026-06-02 pinned re-run)")
    for branch in ["lair", "swamp", "vaults"]:
        if branch not in latest:
            continue
        s = latest[branch]["summary"]
        rate = 100 * s["win_rate"]
        tier = branch_tier[branch]
        print(f"T{tier} ({branch:8s}):{rate:>4.0f}% wins  (this run)")
    print("T5 (forge):     0% wins  (from 2026-06-02 pinned re-run)")
    return 0


if __name__ == "__main__":
    import sys
    sys.exit(main())
