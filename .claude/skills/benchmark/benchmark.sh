#!/bin/bash
# Botter benchmark — time-bounded headless grind with perf telemetry.
# Sister to /grind, but bounded by wall-clock duration, not run count, and
# parses [perf]/[perf-floor] lines into a structured summary.
#
# Usage: benchmark.sh [duration_s] [speed] [label]

set -euo pipefail

DURATION_S="${1:-300}"
SPEED="${2:-16}"
LABEL="${3:-baseline}"
MODE="${4:-headless}"   # headless | windowed

if ! [[ "$DURATION_S" =~ ^[0-9]+$ ]]; then
    echo "duration must be a positive integer (seconds)" >&2; exit 64
fi

GODOT="/Applications/Godot.app/Contents/MacOS/Godot"
REPO="/Users/dyo/claude/botter"
PROJECT="$REPO/project"
USER_DIR="$HOME/Library/Application Support/Godot/app_userdata/Botter"
GRIND_MARKER="$USER_DIR/AUTO_GRIND.txt"
DEBUG_MARKER="$USER_DIR/DEBUG_FLOOR.txt"
LOG_DIR="$REPO/logs/benchmark"
PARSER="$REPO/.claude/skills/benchmark/parse_perf.py"

mkdir -p "$USER_DIR" "$LOG_DIR"
TS=$(date +%Y%m%d-%H%M%S)
LOG="$LOG_DIR/${TS}_${LABEL}.log"

# Park DEBUG_FLOOR if present.
if [[ -f "$DEBUG_MARKER" ]]; then
    mv "$DEBUG_MARKER" "$DEBUG_MARKER.parked"
fi

# AUTO_GRIND with effectively unbounded run count — we time it ourselves.
echo "${SPEED},99999" > "$GRIND_MARKER"

if [[ "$MODE" == "windowed" ]]; then
    GODOT_ARGS=("")
    LAUNCH_NOTE="windowed (full GPU stack)"
else
    GODOT_ARGS=(--headless)
    LAUNCH_NOTE="headless (CPU-only timings; GPU shaders/particles/shadows not exercised)"
fi

echo "benchmark: ${LAUNCH_NOTE} at ${SPEED}x for ${DURATION_S}s, label=${LABEL}"
echo "log: $LOG"
# Pass through perf A/B env vars (BOTTER_NO_SHADOWS, BOTTER_SHADOW_FILTER,
# BOTTER_NO_EMBERS) for hypothesis testing.
[[ -n "${BOTTER_NO_SHADOWS:-}" ]]    && echo "  BOTTER_NO_SHADOWS=$BOTTER_NO_SHADOWS"
[[ -n "${BOTTER_SHADOW_FILTER:-}" ]] && echo "  BOTTER_SHADOW_FILTER=$BOTTER_SHADOW_FILTER"
[[ -n "${BOTTER_NO_EMBERS:-}" ]]     && echo "  BOTTER_NO_EMBERS=$BOTTER_NO_EMBERS"

# Launch.
if [[ "$MODE" == "windowed" ]]; then
    "$GODOT" --path "$PROJECT" >"$LOG" 2>&1 &
else
    "$GODOT" --path "$PROJECT" --headless >"$LOG" 2>&1 &
fi
PID=$!

# Sleep the budget. Watch for early death.
DEADLINE=$(( $(date +%s) + DURATION_S ))
while [[ $(date +%s) -lt $DEADLINE ]]; do
    if ! kill -0 $PID 2>/dev/null; then
        echo "benchmark: Godot exited early — see $LOG" >&2
        break
    fi
    sleep 1
done

# Stop Godot. SIGTERM first; escalate after 3s.
if kill -0 $PID 2>/dev/null; then
    kill $PID 2>/dev/null || true
    for _ in $(seq 1 15); do
        if ! kill -0 $PID 2>/dev/null; then break; fi
        sleep 0.2
    done
    kill -9 $PID 2>/dev/null || true
fi
wait $PID 2>/dev/null || true

# Marker hygiene — never leak into the user's next interactive launch.
rm -f "$GRIND_MARKER"
rm -f "$DEBUG_MARKER.parked"

# Auto-recover from stale class_name cache (same protocol as /grind).
if grep -q 'Parse Error.*not declared' "$LOG" 2>/dev/null; then
    echo "benchmark: detected stale class cache, refreshing and re-running..." >&2
    bash "$REPO/tools/refresh_class_cache.sh" >/dev/null 2>&1 || true
    echo "${SPEED},99999" > "$GRIND_MARKER"
    if [[ "$MODE" == "windowed" ]]; then
        "$GODOT" --path "$PROJECT" >>"$LOG" 2>&1 &
    else
        "$GODOT" --path "$PROJECT" --headless >>"$LOG" 2>&1 &
    fi
    PID=$!
    DEADLINE=$(( $(date +%s) + DURATION_S ))
    while [[ $(date +%s) -lt $DEADLINE ]]; do
        if ! kill -0 $PID 2>/dev/null; then break; fi
        sleep 1
    done
    if kill -0 $PID 2>/dev/null; then
        kill $PID 2>/dev/null || true
        sleep 0.4
        kill -9 $PID 2>/dev/null || true
    fi
    wait $PID 2>/dev/null || true
    rm -f "$GRIND_MARKER"
fi

echo
echo "=== benchmark ${LABEL}  ${SPEED}x  ${DURATION_S}s ==="
python3 "$PARSER" "$LOG"
echo
echo "log: $LOG"
