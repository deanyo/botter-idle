#!/usr/bin/env python3
"""Tier-pinned re-run of cliff + affix matrix experiments.

The branch-pinning fix (commit 481c006) means BOTTER_FORCE_BIOME now
flows through to dungeon.gd, so every floor of every grind will be the
specified biome — not the random per-floor mix that contaminated prior
runs.

Three experiments, chained:

  1. Cliff investigation N=50 at dungeon T1 — validates the floor-4
     cliff finding now that we're actually all-dungeon (was mixed-tier).
  2. Cliff investigation N=50 at forge T5 — same shape, different tier.
     Confirms whether forge-T5 difficulty is genuinely harder or if the
     prior 8% win rate was random-tier noise.
  3. 6-affix matrix N=20 at vaults T4 — re-run the head-to-head with
     actual T4 floors. Larger N than the prior N=15 since we have time.

Total: 50 + 50 + 6×20 = 220 grinds. ~3.5 hours wall-clock.
"""
import sys, time, json
from pathlib import Path
from collections import Counter

REPO_ROOT = Path("/Users/dyo/claude/botter")
sys.path.insert(0, str(REPO_ROOT / "tools"))
sys.path.insert(0, str(REPO_ROOT / ".claude" / "skills" / "duel"))
sys.path.insert(0, str(REPO_ROOT / ".claude" / "skills" / "equip"))

import balance
from parse_grind import parse, RunResult
from duel import summarize


def cliff_grind(branch: str, seed: int):
    spec = {
        "level": 30, "gold": 5000,
        "unlocked_branches": ["dungeon", branch],
        "last_branch": branch,
        "equipped": {
            "weapon": {"base_id": "steel_longsword", "affixes": []},
        },
    }
    balance.inject(spec, reset=True)
    balance.clean_markers()
    spawn = balance.run_grind(
        seed=seed, runs=1, speed=16,
        label=f"pinned_cliff_{branch}_s{seed}",
        invincible=False,
        env_extra={"BOTTER_FORCE_BIOME": branch},
    )
    g = parse(spawn.log_path)
    return g.runs[0] if g.runs else None


def matrix_grind(affix: str, seed: int, branch: str = "vaults"):
    spec = {
        "level": 30, "gold": 5000,
        "unlocked_branches": ["dungeon", branch],
        "last_branch": branch,
        "equipped": {
            "weapon": {
                "base_id": "steel_longsword",
                "affixes": [[affix, 5]],
            },
        },
    }
    balance.inject(spec, reset=True)
    balance.clean_markers()
    spawn = balance.run_grind(
        seed=seed, runs=1, speed=16,
        label=f"pinned_matrix_{affix}5_s{seed}",
        invincible=False,
        env_extra={"BOTTER_FORCE_BIOME": branch},
    )
    g = parse(spawn.log_path)
    return g.runs[0] if g.runs else None


def cliff_experiment(branch: str, n: int, seed_base: int):
    print(f"\n{'='*80}")
    print(f"CLIFF (PINNED): branch={branch}, N={n}, seeds {seed_base}..{seed_base+n-1}")
    print(f"{'='*80}", flush=True)
    seeds = list(range(seed_base, seed_base + n))
    runs = []
    for i, s in enumerate(seeds):
        r = cliff_grind(branch, s)
        if r is None:
            print(f"  WARN seed={s} no run", flush=True)
            continue
        if r.seed == 0:
            r.seed = s
        runs.append(r)
        outcome = "WIN " if r.victory else "LOSS"
        print(f"  [{i+1}/{n}] seed={s} {outcome} f={r.end_floor} kills={r.kills} elapsed={r.elapsed_s:.1f}s", flush=True)
    # Histogram
    deaths = Counter()
    wins = 0
    for r in runs:
        if r.victory:
            wins += 1
        else:
            deaths[r.end_floor] += 1
    print(f"\n  cliff result: {wins}/{len(runs)} wins ({wins/max(1,len(runs)):.0%})", flush=True)
    print(f"  death floor histogram:", flush=True)
    max_floor = max([6] + list(deaths.keys()))
    for f in range(0, max_floor + 1):
        d = deaths.get(f, 0)
        bar = "█" * d
        tag = " ← BOSS" if f == 6 else ""
        print(f"    f={f}: {d:>2} {bar}{tag}", flush=True)
    balance.append_index({
        "kind": "cliff_pinned",
        "label": f"cliff_pinned_{branch}_N{n}",
        "params": {"branch": branch, "n": n, "seed_base": seed_base,
                   "spec": "steel_longsword level=30 (no affixes), branch-pinned"},
        "summary": summarize(f"cliff_pinned_{branch}", runs),
    })
    return runs


def matrix_experiment(branch: str, n: int, seed_base: int):
    print(f"\n{'='*80}")
    print(f"MATRIX (PINNED): branch={branch} N={n} per affix, seeds {seed_base}..{seed_base+n-1}")
    print(f"{'='*80}", flush=True)
    affixes = ["strength", "stamina", "agility", "regen", "crit", "haste"]
    seeds = list(range(seed_base, seed_base + n))
    summaries = []
    for affix in affixes:
        print(f"\n--- {affix}5 ---", flush=True)
        runs = []
        for i, s in enumerate(seeds):
            r = matrix_grind(affix, s, branch=branch)
            if r is None:
                continue
            if r.seed == 0:
                r.seed = s
            runs.append(r)
            outcome = "WIN " if r.victory else "LOSS"
            print(f"  [{i+1}/{n}] seed={s} {outcome} f={r.end_floor} kills={r.kills} elapsed={r.elapsed_s:.1f}s", flush=True)
        # HP-lost summary (was the high-resolution metric in prior run)
        hp_lost = []
        for r in runs:
            tot = sum(fr.hp_lost for fr in r.floors)
            hp_lost.append(tot)
        if hp_lost:
            import statistics
            print(f"  hp_lost: median={statistics.median(hp_lost):.0f} avg={sum(hp_lost)/len(hp_lost):.0f}", flush=True)
        s_summary = summarize(f"{affix}5", runs)
        summaries.append(s_summary)
        # Persist per variant
        balance.append_index({
            "kind": "affix_matrix_partial",
            "label": f"matrix_pinned_{affix}5_{branch}",
            "params": {"affix": affix, "branch": branch, "n": n, "seed_base": seed_base,
                       "spec": "steel_longsword + 1 tier-5 affix, branch-pinned"},
            "summary": s_summary,
        })
    # Final ranked table
    summaries.sort(key=lambda d: (-d.get("win_rate", 0), -d.get("avg_floor", 0)))
    print(f"\n=== matrix ranked at {branch} (PINNED) ===", flush=True)
    for i, s in enumerate(summaries):
        wr = s.get("win_rate", 0)
        ci = s.get("win_rate_ci95", [0, 0])
        wr_str = f"{wr:.0%} [{ci[0]:.0%},{ci[1]:.0%}]"
        print(f"  #{i+1}: {s.get('label','?'):<14} wins={s.get('wins',0)}/{s.get('n',0)}  {wr_str}  floor={s.get('avg_floor',0):.2f}  kills={s.get('avg_kills',0):.1f}", flush=True)
    balance.append_index({
        "kind": "affix_matrix",
        "label": f"matrix_pinned_{branch}_N{n}",
        "params": {"branch": branch, "n_per_variant": n, "seed_base": seed_base,
                   "spec": "steel_longsword + 1 tier-5 affix, branch-pinned"},
        "ranked": summaries,
    })


def main():
    t0 = time.time()
    cliff_experiment("dungeon", 50, 9000)
    cliff_experiment("forge", 50, 9100)
    matrix_experiment("vaults", 20, 9200)
    print(f"\n=== ALL PINNED EXPERIMENTS COMPLETE ({(time.time()-t0)/60:.1f} min) ===", flush=True)


if __name__ == "__main__":
    main()
