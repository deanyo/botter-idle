#!/usr/bin/env python3
# Per-floor rarity histogram from N headless grind runs.
#
# Wraps .claude/skills/grind/grind.sh; parses every "[loot] f=N rarity=X
# base=Y" line that dungeon.gd::_spawn_loot_drop emits; tabulates counts
# per (floor, rarity); prints an ASCII table and writes a CSV.
#
# Spec: ~/claude/game-audit/balance_pass_2026-06-11/synthesis/A12_tooling_roadmap.md §T1-4.

import argparse
import csv
import datetime
import os
import re
import subprocess
import sys
from collections import defaultdict

REPO = "/Users/dyo/claude/botter"
GRIND_SH = os.path.join(REPO, ".claude/skills/grind/grind.sh")
LOG_DIR = os.path.join(REPO, "logs/grind")
OUT_DIR = os.path.join(REPO, "logs/balance")

RARITIES = ["common", "uncommon", "rare", "epic", "legendary"]
LOOT_RE = re.compile(r"^\[loot\] f=(\d+) rarity=(\S+) base=(\S+)")

# Tier→floor mapping for --tier filter. Mirrors the in-game tier-band
# split used by tier_drop_band keys ("1-3" / "4-6"). T<n> covers floors
# 1..6 of the tier; absolute floor numbers reset per branch in our run
# model so the parser sees per-run f=1..6.
TIER_FLOOR_MAX = 6


def _newest_log():
    if not os.path.isdir(LOG_DIR):
        return None
    candidates = [os.path.join(LOG_DIR, f) for f in os.listdir(LOG_DIR) if f.endswith(".log")]
    if not candidates:
        return None
    return max(candidates, key=os.path.getmtime)


def run_grind(runs, branch, preset, mortal):
    cmd = ["bash", GRIND_SH, str(runs), "16"]
    if mortal:
        cmd.append("--mortal")
    if branch:
        cmd.extend(["--branch", branch])
    if preset:
        cmd.extend(["--preset", preset])
    print(f"==> grind: {' '.join(cmd[1:])}", file=sys.stderr)
    before = _newest_log()
    res = subprocess.run(cmd, capture_output=True, text=True)
    # grind.sh's summary section runs under `set -o pipefail`, so a `grep`
    # that finds zero matches in a downstream pipeline trips the script
    # and it exits non-zero before printing the trailing "log:" line.
    # Locate the log by mtime in `logs/grind/` instead — robust to that.
    log_path = None
    for line in res.stdout.splitlines():
        if line.startswith("log: "):
            log_path = line[5:].strip()
    if not log_path or not os.path.isfile(log_path):
        latest = _newest_log()
        if latest and latest != before:
            log_path = latest
    if not log_path or not os.path.isfile(log_path):
        print(res.stdout, file=sys.stderr)
        print(res.stderr, file=sys.stderr)
        raise SystemExit(f"could not locate grind log (exit {res.returncode})")
    return log_path


def parse_loot(log_path, tier_filter):
    counts = defaultdict(lambda: defaultdict(int))  # counts[floor][rarity]
    with open(log_path, encoding="utf-8", errors="replace") as f:
        for line in f:
            m = LOOT_RE.match(line)
            if not m:
                continue
            floor = int(m.group(1))
            rarity = m.group(2)
            if rarity not in RARITIES:
                continue
            if tier_filter is not None and floor > TIER_FLOOR_MAX:
                # --tier mode: only the per-run first 6 floors map cleanly
                # to a single tier band.
                continue
            counts[floor][rarity] += 1
    return counts


def render_ascii(counts):
    if not counts:
        return "no [loot] lines parsed — was the run too short?"
    header = f"{'floor':<7}" + "".join(f"{r:<10}" for r in RARITIES) + f"{'total':<8}{'  c%':<5}{' u%':<5}{' r%':<5}{' e%':<5}{' l%':<5}"
    rows = [header, "-" * len(header)]
    for floor in sorted(counts.keys()):
        per = counts[floor]
        total = sum(per.values())
        if total == 0:
            continue
        cells = [f"{floor:<7}"]
        for r in RARITIES:
            cells.append(f"{per[r]:<10}")
        cells.append(f"{total:<8}")
        for r in RARITIES:
            pct = (100.0 * per[r] / total) if total else 0.0
            cells.append(f"{pct:>3.0f}  ")
        rows.append("".join(cells))
    return "\n".join(rows)


def write_csv(counts, out_path):
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    with open(out_path, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["floor"] + RARITIES + ["total"])
        for floor in sorted(counts.keys()):
            per = counts[floor]
            total = sum(per.values())
            w.writerow([floor] + [per[r] for r in RARITIES] + [total])


def main():
    ap = argparse.ArgumentParser(description="Per-floor rarity histogram from N grinds.")
    ap.add_argument("runs", type=int, help="number of grind runs")
    ap.add_argument("--branch", default=None, help="pin every run to one biome")
    ap.add_argument("--preset", default=None, help="fresh-save loadout: naked|t1|t2|t3|t4|t5")
    ap.add_argument("--mortal", action="store_true", help="disable bot invincibility")
    ap.add_argument("--tier", type=int, default=None, help="filter to floors 1-6 (per-run) of one tier")
    args = ap.parse_args()

    if args.runs <= 0:
        raise SystemExit("runs must be > 0")

    log_path = run_grind(args.runs, args.branch, args.preset, args.mortal)
    counts = parse_loot(log_path, args.tier)

    ts = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    suffix_parts = [f"{args.runs}runs"]
    if args.preset: suffix_parts.append(args.preset)
    if args.branch: suffix_parts.append(args.branch)
    if args.tier is not None: suffix_parts.append(f"t{args.tier}")
    out_csv = os.path.join(OUT_DIR, f"rarity_hist_{ts}_{'_'.join(suffix_parts)}.csv")

    print()
    print(render_ascii(counts))
    print()

    write_csv(counts, out_csv)
    total_drops = sum(sum(per.values()) for per in counts.values())
    print(f"=== rarity histogram ===")
    print(f"runs:        {args.runs}")
    print(f"total drops: {total_drops}")
    print(f"floors hit:  {len(counts)}")
    print(f"grind log:   {log_path}")
    print(f"csv:         {out_csv}")


if __name__ == "__main__":
    main()
