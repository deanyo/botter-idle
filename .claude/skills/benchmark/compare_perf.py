#!/usr/bin/env python3
"""Compare two Botter benchmark logs side by side."""
from __future__ import annotations

import re
import statistics
import sys
from typing import Dict, List

PERF_TAGS = ["fog", "lights", "flicker", "render", "ai"]
PERF_RE = re.compile(
    r"\[perf\] frame_ms=(?P<frame_ms>[\d.]+) "
    r"fog_us=(?P<fog>\d+) lights_us=(?P<lights>\d+) flicker_us=(?P<flicker>\d+) "
    r"render_us=(?P<render>\d+) ai_us=(?P<ai>\d+)"
)


def percentile(values: List[float], p: float) -> float:
    if not values:
        return 0.0
    s = sorted(values)
    k = max(0, min(len(s) - 1, int(round((p / 100.0) * (len(s) - 1)))))
    return s[k]


def parse(path: str) -> Dict[str, List[float]]:
    out = {"frame_ms": [], **{t: [] for t in PERF_TAGS}}
    with open(path, "r", errors="replace") as f:
        for line in f:
            m = PERF_RE.search(line)
            if not m:
                continue
            out["frame_ms"].append(float(m["frame_ms"]))
            for t in PERF_TAGS:
                out[t].append(float(m[t]))
    return out


def fmt_pct(a: float, b: float) -> str:
    if a == 0:
        return "  n/a"
    delta = (b - a) / a * 100.0
    sign = "+" if delta >= 0 else ""
    return f"{sign}{delta:5.1f}%"


def row(label: str, av: List[float], bv: List[float], unit: str) -> str:
    a_avg = statistics.fmean(av) if av else 0
    b_avg = statistics.fmean(bv) if bv else 0
    a_p95 = percentile(av, 95)
    b_p95 = percentile(bv, 95)
    if unit == "ms":
        a_avg_s, b_avg_s = f"{a_avg:6.2f}", f"{b_avg:6.2f}"
        a_p95_s, b_p95_s = f"{a_p95:6.2f}", f"{b_p95:6.2f}"
    else:
        a_avg_s, b_avg_s = f"{int(a_avg):6d}", f"{int(b_avg):6d}"
        a_p95_s, b_p95_s = f"{int(a_p95):6d}", f"{int(b_p95):6d}"
    return (
        f"{label:<11} avg {a_avg_s} -> {b_avg_s} ({fmt_pct(a_avg, b_avg)})  "
        f"p95 {a_p95_s} -> {b_p95_s} ({fmt_pct(a_p95, b_p95)})"
    )


def main(a_path: str, b_path: str) -> int:
    a = parse(a_path)
    b = parse(b_path)
    print(f"baseline: {a_path}  ({len(a['frame_ms'])} samples)")
    print(f"after:    {b_path}  ({len(b['frame_ms'])} samples)")
    if not a["frame_ms"] or not b["frame_ms"]:
        print("not enough perf samples to compare", file=sys.stderr)
        return 1
    print()
    print(row("frame_ms", a["frame_ms"], b["frame_ms"], "ms"))
    for tag in PERF_TAGS:
        print(row(tag + "_us", a[tag], b[tag], "us"))
    return 0


if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("usage: compare_perf.py <baseline.log> <after.log>", file=sys.stderr)
        sys.exit(2)
    sys.exit(main(sys.argv[1], sys.argv[2]))
