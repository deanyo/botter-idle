#!/usr/bin/env python3
"""run_cliff_t2t3.py — fill the gap in the 2026-06-02 balance findings.

Prior data: T1 (dungeon) 96% wins, T4 (vaults) 0% wins, T5 (forge) 0%.
Missing: T2 (lair) and T3 (swamp). This script runs the same cliff
shape (N=50 per branch, build = steel_longsword level=30 no affixes)
across lair → swamp → vaults so the curve is continuous and the prior
T4 number is re-confirmed under the new (post-tag-wiring) build.

Output: appended to logs/balance/index.jsonl as cliff_partial rows.
"""

import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO / "tools"))

import balance  # type: ignore  # noqa: E402
from run_combo_and_cliff import run_grind_for_build, summarize  # type: ignore  # noqa: E402

SEEDS = list(range(7100, 7150))  # 50 fresh seeds, distinct from prior runs
BRANCHES = ["lair", "swamp", "vaults"]


def main() -> int:
    print("\n" + "=" * 90)
    print("CLIFF T2/T3 FILL-IN: N=50 per branch, steel_longsword level=30 (no affixes)")
    print(f"Branches: {BRANCHES}  Seeds: {SEEDS[0]}..{SEEDS[-1]}")
    print("=" * 90, flush=True)

    runs = {}
    for branch in BRANCHES:
        print(f"\n--- branch={branch} ---", flush=True)
        spec = {
            "level": 30, "gold": 5000,
            "unlocked_branches": ["dungeon", branch],
            "last_branch": branch,
            "equipped": {
                "weapon": {"base_id": "steel_longsword", "affixes": []},
            },
        }
        rs = []
        for i, s in enumerate(SEEDS):
            r = run_grind_for_build(f"cliff_t2t3_{branch}_s{s}", spec, s)
            if r is None:
                print(f"  WARN seed={s} no run", flush=True)
                continue
            if r.seed == 0:
                r.seed = s
            outcome = "WIN " if r.victory else "LOSS"
            print(f"  [{i+1}/{len(SEEDS)}] seed={s} {outcome} f={r.end_floor} "
                  f"kills={r.kills} elapsed={r.elapsed_s:.1f}s", flush=True)
            rs.append(r)
        runs[branch] = rs
        # Persist after each branch — partial visibility if the run is
        # interrupted, and a per-branch JSONL row for cross-branch greps.
        balance.append_index({
            "kind": "cliff_partial",
            "label": f"cliff_t2t3_{branch}",
            "params": {"branch": branch, "seeds": SEEDS,
                       "spec": "steel_longsword level=30 (no affixes)"},
            "summary": summarize(f"cliff_{branch}", rs),
        })

    # Death histograms across all 3 branches for the report.
    from collections import Counter
    print("\n\n=== T2/T3 cliff fill-in results ===", flush=True)
    for branch, rs in runs.items():
        deaths = Counter()
        wins = 0
        for r in rs:
            if r.victory:
                wins += 1
            else:
                deaths[r.end_floor] += 1
        hist = ", ".join(f"f{f}:{n}" for f, n in sorted(deaths.items()))
        print(f"\n  {branch}: wins={wins}/{len(rs)}  deaths_by_floor: {hist}",
              flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
