#!/bin/bash
# Botter grind helper. Drives auto-grind headlessly and tails the log until
# Godot prints "[run] auto-grind COMPLETE", then exits with a structured
# summary. No fixed sleep.
#
# Usage: grind.sh <runs> [speed]
#
# Logs land in logs/grind/<timestamp>_<speed>x_<runs>runs.log inside the
# repo (gitignored).

set -euo pipefail

RUNS="${1:-}"
SPEED="${2:-16}"

if [[ -z "$RUNS" ]]; then
    echo "Usage: $0 <runs> [speed]" >&2
    exit 64
fi
if ! [[ "$RUNS" =~ ^[0-9]+$ ]]; then
    echo "<runs> must be a positive integer" >&2
    exit 64
fi

GODOT="/Applications/Godot.app/Contents/MacOS/Godot"
REPO="/Users/dyo/claude/botter"
PROJECT="$REPO/project"
USER_DIR="$HOME/Library/Application Support/Godot/app_userdata/Botter"
GRIND_MARKER="$USER_DIR/AUTO_GRIND.txt"
DEBUG_MARKER="$USER_DIR/DEBUG_FLOOR.txt"
LOG_DIR="$REPO/logs/grind"

mkdir -p "$USER_DIR" "$LOG_DIR"
TS=$(date +%Y%m%d-%H%M%S)
LOG="$LOG_DIR/${TS}_${SPEED}x_${RUNS}runs.log"

# Park DEBUG_FLOOR if present so it doesn't preempt auto-grind.
if [[ -f "$DEBUG_MARKER" ]]; then
    mv "$DEBUG_MARKER" "$DEBUG_MARKER.parked"
fi

# Write the marker.
echo "${SPEED},${RUNS}" > "$GRIND_MARKER"

# Launch Godot headless, log to file, run in background.
"$GODOT" --path "$PROJECT" --headless >"$LOG" 2>&1 &
PID=$!

# Tail the log waiting for the COMPLETE line. Hard timeout: 240s/run.
# A normal run at 16x is ~30-60s but invincible grind runs can hit huge
# encompass vaults (e.g. des_vaults_vault has 608 chests) that take many
# minutes to explore.
TIMEOUT_S=$((RUNS * 240))
DEADLINE=$(( $(date +%s) + TIMEOUT_S ))
DONE=0
while [[ $(date +%s) -lt $DEADLINE ]]; do
    if grep -q '\[run\] auto-grind COMPLETE' "$LOG" 2>/dev/null; then
        DONE=1
        break
    fi
    if ! kill -0 $PID 2>/dev/null; then
        # Godot exited (cleanly or otherwise) — one last grep
        if grep -q '\[run\] auto-grind COMPLETE' "$LOG" 2>/dev/null; then
            DONE=1
        fi
        break
    fi
    sleep 0.5
done

# Stop Godot if still running.
if kill -0 $PID 2>/dev/null; then
    kill $PID 2>/dev/null || true
    for i in $(seq 1 10); do
        if ! kill -0 $PID 2>/dev/null; then break; fi
        sleep 0.2
    done
    kill -9 $PID 2>/dev/null || true
fi
wait $PID 2>/dev/null || true

if [[ $DONE -eq 0 ]]; then
    # Auto-recover from stale class_name cache.
    if grep -q 'Parse Error.*not declared' "$LOG" 2>/dev/null; then
        echo "grind: detected stale class cache, refreshing and retrying..." >&2
        bash "$REPO/tools/refresh_class_cache.sh" >/dev/null 2>&1 || true
        echo "${SPEED},${RUNS}" > "$GRIND_MARKER"
        "$GODOT" --path "$PROJECT" --headless >>"$LOG" 2>&1 &
        PID=$!
        DEADLINE=$(( $(date +%s) + TIMEOUT_S ))
        while [[ $(date +%s) -lt $DEADLINE ]]; do
            if grep -q '\[run\] auto-grind COMPLETE' "$LOG" 2>/dev/null; then
                DONE=1
                break
            fi
            if ! kill -0 $PID 2>/dev/null; then
                if grep -q '\[run\] auto-grind COMPLETE' "$LOG" 2>/dev/null; then DONE=1; fi
                break
            fi
            sleep 0.5
        done
        if kill -0 $PID 2>/dev/null; then
            kill $PID 2>/dev/null || true
            sleep 0.4
            kill -9 $PID 2>/dev/null || true
        fi
        wait $PID 2>/dev/null || true
    fi
fi

if [[ $DONE -eq 0 ]]; then
    echo "grind: did not complete within ${TIMEOUT_S}s — last 30 log lines:" >&2
    tail -30 "$LOG" >&2
    echo "log: $LOG" >&2
    exit 1
fi

# Build the structured summary.
echo "=== grind summary  ${SPEED}x  ${RUNS} runs ==="
grep '\[run\] end' "$LOG" || true
echo
TOTAL_BAD=$(grep -c '\[bad-floor\]' "$LOG" || true)
TOTAL_STALLS=$(grep -c '^\[stall\] f=' "$LOG" || true)
TOTAL_PORTALS=$(grep -c '^\[portal\] entered=' "$LOG" || true)
TOTAL_FLOORS=$(grep -c '^\[floor\] f=' "$LOG" || true)
UNIQUE_BIOMES=$(grep -oE '^\[floor\] f=[0-9]+ biome=[a-z_.]+' "$LOG" | awk '{print $3}' | sort -u | wc -l | tr -d ' ')
UNIQUE_VAULTS=$(grep -oE 'vaults=\["des_[^"]+"' "$LOG" | sort -u | wc -l | tr -d ' ')
echo "totals: floors=${TOTAL_FLOORS} bad-floors=${TOTAL_BAD} stalls=${TOTAL_STALLS} portals=${TOTAL_PORTALS}"
echo "uniqueness: biomes=${UNIQUE_BIOMES} vaults=${UNIQUE_VAULTS}"
if [[ "$TOTAL_BAD" -gt 0 ]]; then
    echo
    echo "bad-floor patterns:"
    grep '\[bad-floor\]' "$LOG" | grep -oE 'bad-floor\] [^|]+' | sort | uniq -c | sort -rn
fi
# Per-biome breakdown if multi-run
if [[ "$TOTAL_FLOORS" -ge 5 ]]; then
    echo
    echo "biome distribution:"
    grep -oE '^\[floor\] f=[0-9]+ biome=[a-z_.]+' "$LOG" | awk '{print $3}' | sort | uniq -c | sort -rn | head -25
fi
# Portals fired
if [[ "$TOTAL_PORTALS" -gt 0 ]]; then
    echo
    echo "portals: $(grep -oE '\[portal\] entered=[a-z_]+' "$LOG" | sort | uniq -c | sort -rn | tr '\n' ' ')"
fi
# Terrain stamped
TERRAIN_HITS=$(grep -E "lava_pit|lava_bridge|tide_pool|swamp_bog|ice_shrine|blood_pool" "$LOG" | wc -l | tr -d ' ')
if [[ "$TERRAIN_HITS" -gt 0 ]]; then
    echo "terrain vaults: ${TERRAIN_HITS}"
fi
echo
echo "log: $LOG"
