#!/usr/bin/env python3
"""analyze_floor_deaths.py — Histogram which floor kills the bot.

Reads grind logs (default: logs/balance/*.log) and counts the floor that
the bot died on. Useful for diagnosing "where does the bot die most" —
a floor-4 spike means the difficulty curve has a hidden cliff there.

Usage:

    python3 tools/analyze_floor_deaths.py                     # all balance logs
    python3 tools/analyze_floor_deaths.py logs/grind/*.log    # specific dir
    python3 tools/analyze_floor_deaths.py --branch forge      # filter
"""

from __future__ import annotations
import argparse
import glob
import re
from collections import Counter, defaultdict
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_GLOB = str(REPO_ROOT / "logs" / "balance" / "*.log")


_RUN_END_RE = re.compile(
    r"\[run\] end .*?victory=(\w+).*?floor=(\d+).*?kills=(\d+).*?loot=(\d+)")


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("paths", nargs="*", default=None,
                        help="Log paths or globs (default: logs/balance/*.log).")
    parser.add_argument("--branch", help="Only consider runs containing this branch.")
    args = parser.parse_args()

    paths = []
    for p in (args.paths or [DEFAULT_GLOB]):
        paths.extend(glob.glob(p))

    death_floor: Counter = Counter()
    win_floor: Counter = Counter()
    branch_filter = args.branch
    n_runs = 0

    for path in paths:
        # If branch filter is set, peek at the log to confirm presence.
        with open(path) as f:
            content = f.read()
        if branch_filter and f"branch_id={branch_filter}" not in content \
                and f"biome={branch_filter}" not in content:
            continue
        for m in _RUN_END_RE.finditer(content):
            victory = m.group(1) == "true"
            floor = int(m.group(2))
            n_runs += 1
            if victory:
                win_floor[floor] += 1
            else:
                death_floor[floor] += 1

    if n_runs == 0:
        print("no [run] end events found.")
        return 1

    print()
    print(f"Analyzed {n_runs} runs across {len(paths)} log files")
    if branch_filter:
        print(f"(branch filter: {branch_filter})")
    print()
    print(f"{'floor':<8}{'deaths':<10}{'wins':<10}{'total':<10}{'death rate':<14}{'bar'}")
    print("-" * 80)
    max_floor = max(list(death_floor.keys()) + list(win_floor.keys()) + [6])
    total_deaths = sum(death_floor.values())
    total_wins = sum(win_floor.values())
    grand_total = total_deaths + total_wins
    for f in range(0, max_floor + 1):
        d = death_floor.get(f, 0)
        w = win_floor.get(f, 0)
        t = d + w
        rate = (d / t) if t else 0
        bar_pct = d / total_deaths if total_deaths else 0
        bar = "█" * int(bar_pct * 50)
        print(f"{f:<8}{d:<10}{w:<10}{t:<10}{rate:<14.0%}{bar}")
    print("-" * 80)
    print(f"{'total':<8}{total_deaths:<10}{total_wins:<10}{grand_total:<10}"
          f"{(total_deaths/grand_total) if grand_total else 0:<14.0%}")

    print()
    print("interpretation:")
    if total_deaths > 0:
        # Mode of death distribution
        most_deadly_floor, most_deadly_n = death_floor.most_common(1)[0]
        print(f"  most deaths: floor {most_deadly_floor} ({most_deadly_n} of "
              f"{total_deaths} = {most_deadly_n/total_deaths:.0%})")
        # Death cliff: largest jump
        jumps = []
        for f in range(0, max_floor):
            jumps.append((f + 1, death_floor.get(f + 1, 0) - death_floor.get(f, 0)))
        jumps.sort(key=lambda x: -x[1])
        if jumps and jumps[0][1] > 0:
            print(f"  biggest deaths-up jump: floor {jumps[0][0]-1} → {jumps[0][0]}: "
                  f"+{jumps[0][1]} deaths")
    if total_wins > 0:
        print(f"  win rate: {total_wins/grand_total:.0%}")
    return 0


if __name__ == "__main__":
    import sys
    sys.exit(main())
