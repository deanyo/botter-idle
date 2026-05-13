#!/usr/bin/env python3
"""Parse [perf] and [perf-floor] lines from a Botter benchmark log.

Emits a structured summary: aggregate frame_ms + per-system µs (avg / p95
/ max), worst floors by frame_ms, worst floors per tag, biome avg
frame_ms ranking.

Input log lines look like:
  [perf] frame_ms=4.21 fog_us=1840 lights_us=320 flicker_us=210 render_us=140 ai_us=600
  [perf-floor] label=lair|des_lair_x|f3 frames=420 frame_us=4180 fog_us=1810 lights_us=305 flicker_us=205 render_us=130 ai_us=590
"""
from __future__ import annotations

import re
import statistics
import sys
from collections import defaultdict
from typing import Dict, List, Tuple

PERF_TAGS = ["fog", "lights", "flicker", "render", "ai"]

PERF_RE = re.compile(
    r"\[perf\] frame_ms=(?P<frame_ms>[\d.]+)(?: fps=(?P<fps>[\d.]+))? "
    r"fog_us=(?P<fog>\d+) lights_us=(?P<lights>\d+) flicker_us=(?P<flicker>\d+) "
    r"render_us=(?P<render>\d+) ai_us=(?P<ai>\d+)"
)

PERF_FLOOR_RE = re.compile(
    r"\[perf-floor\] label=(?P<label>\S+) frames=(?P<frames>\d+) "
    r"frame_us=(?P<frame>\d+) fog_us=(?P<fog>\d+) lights_us=(?P<lights>\d+) "
    r"flicker_us=(?P<flicker>\d+) render_us=(?P<render>\d+) ai_us=(?P<ai>\d+)"
)

RUN_END_RE = re.compile(r"^\[run\] end #")
FLOOR_RE = re.compile(r"^\[floor\] f=")


def percentile(values: List[float], p: float) -> float:
    if not values:
        return 0.0
    s = sorted(values)
    k = max(0, min(len(s) - 1, int(round((p / 100.0) * (len(s) - 1)))))
    return s[k]


def fmt_us(v: float) -> str:
    return f"{int(round(v))}"


def main(path: str) -> int:
    samples = {"frame_ms": [], "fps": [], **{tag: [] for tag in PERF_TAGS}}
    floor_rows: List[Dict] = []
    runs = 0
    floors = 0

    with open(path, "r", errors="replace") as f:
        for line in f:
            if RUN_END_RE.search(line):
                runs += 1
                continue
            if FLOOR_RE.search(line):
                floors += 1
                continue
            m = PERF_RE.search(line)
            if m:
                samples["frame_ms"].append(float(m["frame_ms"]))
                if m.group("fps"):
                    samples["fps"].append(float(m["fps"]))
                for tag in PERF_TAGS:
                    samples[tag].append(float(m[tag]))
                continue
            m2 = PERF_FLOOR_RE.search(line)
            if m2:
                floor_rows.append({
                    "label": m2["label"],
                    "frames": int(m2["frames"]),
                    "frame_us": int(m2["frame"]),
                    "fog": int(m2["fog"]),
                    "lights": int(m2["lights"]),
                    "flicker": int(m2["flicker"]),
                    "render": int(m2["render"]),
                    "ai": int(m2["ai"]),
                })

    print(f"runs: {runs}  floors: {floors}  perf samples: {len(samples['frame_ms'])}")
    if not samples["frame_ms"]:
        print("(no [perf] lines found — was PerfMon enabled in this build?)")
        return 0

    # Aggregates.
    fr = samples["frame_ms"]
    print(f"frame_ms: avg={statistics.fmean(fr):.2f} p50={percentile(fr,50):.2f} "
          f"p95={percentile(fr,95):.2f} max={max(fr):.2f}")
    if samples["fps"]:
        fps = samples["fps"]
        print(f"fps:      avg={statistics.fmean(fps):.0f} p50={percentile(fps,50):.0f} "
              f"p05={percentile(fps,5):.0f} min={min(fps):.0f}")
    for tag in PERF_TAGS:
        v = samples[tag]
        print(f"{tag+'_us':<11} avg={fmt_us(statistics.fmean(v)):>6}  "
              f"p95={fmt_us(percentile(v,95)):>6}  max={fmt_us(max(v)):>6}")

    if floor_rows:
        # Worst floors by frame_us.
        worst = sorted(floor_rows, key=lambda r: r["frame_us"], reverse=True)[:10]
        print("\nworst floors by frame_us (avg per frame, biome|vault|fN):")
        for r in worst:
            ms = r["frame_us"] / 1000.0
            print(f"  {ms:6.2f}ms  frames={r['frames']:<5} {r['label']}")

        print("\nworst per tag (single floor max):")
        for tag in PERF_TAGS:
            wt = max(floor_rows, key=lambda r: r[tag])
            print(f"  {tag:<8} {wt[tag]:>6}us  {wt['label']} (frames={wt['frames']})")

        # Biome ranking — strip vault and floor parts.
        biome_groups: Dict[str, List[int]] = defaultdict(list)
        for r in floor_rows:
            biome = r["label"].split("|", 1)[0]
            biome_groups[biome].append(r["frame_us"])
        biome_ranked: List[Tuple[str, float, int]] = [
            (b, statistics.fmean(v) / 1000.0, len(v))
            for b, v in biome_groups.items()
        ]
        biome_ranked.sort(key=lambda t: t[1], reverse=True)
        print("\nbiome avg frame_ms (top 10):")
        for biome, ms, n in biome_ranked[:10]:
            print(f"  {biome:<14} {ms:6.2f}ms  n={n}")

        # Vault outliers — group floors that share at least one vault.
        vault_us: Dict[str, List[int]] = defaultdict(list)
        for r in floor_rows:
            parts = r["label"].split("|")
            vaults_part = parts[1] if len(parts) > 1 else ""
            if not vaults_part or vaults_part == "_":
                continue
            for v in vaults_part.split(","):
                if v:
                    vault_us[v].append(r["frame_us"])
        vault_ranked = [(v, statistics.fmean(s) / 1000.0, len(s))
                        for v, s in vault_us.items() if len(s) >= 1]
        vault_ranked.sort(key=lambda t: t[1], reverse=True)
        print("\nvault avg frame_ms (top 10 — possible outliers):")
        for v, ms, n in vault_ranked[:10]:
            print(f"  {ms:6.2f}ms  n={n}  {v}")

        # Floor-number ranking — tests "more enemies on late floors = slower"
        # hypothesis. Groups by the fN suffix of the perf-floor label.
        floor_num_us: Dict[int, List[int]] = defaultdict(list)
        for r in floor_rows:
            parts = r["label"].rsplit("|f", 1)
            if len(parts) == 2 and parts[1].isdigit():
                floor_num_us[int(parts[1])].append(r["frame_us"])
        if floor_num_us:
            print("\nfloor-number avg frame_ms (1=spawn, 10=boss):")
            for fn in sorted(floor_num_us.keys()):
                v = floor_num_us[fn]
                ms = statistics.fmean(v) / 1000.0
                print(f"  f{fn:<2} {ms:6.2f}ms  n={len(v)}")

    return 0


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("usage: parse_perf.py <log_path>", file=sys.stderr)
        sys.exit(2)
    sys.exit(main(sys.argv[1]))
