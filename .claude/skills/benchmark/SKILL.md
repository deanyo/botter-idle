---
name: benchmark
description: Run a timed (default 5min) headless perf benchmark, then parse [perf] / [perf-floor] log lines to report avg frame timings, per-system µs, and outlier maps/vaults. Use to validate optimization commits.
user_invocable: true
---

# Botter benchmark

Wraps the auto-grind harness with a wall-clock budget instead of a run
count, then parses the `[perf]` and `[perf-floor]` log lines that
PerfMon emits.

## Usage

```bash
bash /Users/dyo/claude/botter/.claude/skills/benchmark/benchmark.sh [duration_s] [speed] [label]
```

Defaults: `duration_s=300` (5 min), `speed=16`, `label=baseline`,
`mode=headless`.

Examples:

```bash
bash .claude/skills/benchmark/benchmark.sh                            # 5min @ 16x baseline, headless
bash .claude/skills/benchmark/benchmark.sh 120 16 opt1-fog            # 2min after opt1, headless
bash .claude/skills/benchmark/benchmark.sh 300 8 fast-mode            # 5min @ 8x, headless
bash .claude/skills/benchmark/benchmark.sh 60 4 windowed-check windowed   # 60s windowed for full GPU stack
```

The label is for the log filename and the summary header; pass
something descriptive (`baseline`, `opt1-fog-gate`, `opt2-shader-buf`,
`opt3-flicker-cache`, `final`).

## Headless vs windowed

- `headless` (default) skips the GPU renderer entirely. CPU-side timers
  are honest (fog raycast, AI, flicker noise math, light array packing,
  modulate fade); GPU shader / shadow / particle costs are NOT exercised.
- `windowed` launches the actual game window so all rendering work runs.
  Use for absolute frame-time validation; deltas between two `headless`
  runs are still honest because they measure the same code paths.

## Hardware context

Baseline numbers are tagged with the machine (e.g. M3 Pro). Always
record which machine generated a benchmark log when comparing — a
200µs win on M3 Pro can be a 2ms win on a low-end Windows laptop.

## How it works

1. Park any active `DEBUG_FLOOR.txt` marker.
2. Write `AUTO_GRIND.txt` with `<speed>,99999` so the grind keeps
   producing runs until the script kills it.
3. Launch Godot `--headless`, redirect stdout to
   `logs/benchmark/<timestamp>_<label>.log`.
4. Sleep `duration_s` (this skill IS time-bounded).
5. Send TERM to Godot, wait for clean shutdown.
6. Parse `[perf]` lines (rolling per-240-frame snapshots):
   - frame_ms p50 / p95 / max
   - per-system avg µs (fog / lights / flicker / render / ai)
7. Parse `[perf-floor]` lines (per-floor totals):
   - top 10 worst-frame_ms floors with biome/vault attribution
   - top 10 worst per-system tags
8. Print a structured summary; print log path.

## Output format

```
=== benchmark <label>  <speed>x  <duration_s>s ===
runs: N  floors: M  perf samples: K
frame_ms: avg=X.XX p50=Y.YY p95=Z.ZZ max=W.WW
fog_us:    avg=A  p95=B
lights_us: avg=A  p95=B
flicker_us:avg=A  p95=B
render_us: avg=A  p95=B
ai_us:     avg=A  p95=B

worst floors by frame_ms:
  X.XXms  biome|vault|fN
  ...

worst floors by tag:
  fog: X us  biome|vault|fN
  lights: ...
  flicker: ...
  render: ...

biome avg frame_ms (top 10):
  biome  avg_ms  n_floors
```

## After running

`AUTO_GRIND.txt` is removed on exit (skill marker hygiene). To kill a
runaway benchmark manually:

```bash
pkill -f "Godot.*botter/project"
rm -f "$HOME/Library/Application Support/Godot/app_userdata/Botter/AUTO_GRIND.txt"
```

## Comparing runs

Each commit's benchmark log lives at `logs/benchmark/<ts>_<label>.log`.
To diff two:

```bash
bash .claude/skills/benchmark/compare.sh <baseline.log> <after.log>
```

`compare.sh` prints aligned avg/p95 deltas per tag.
