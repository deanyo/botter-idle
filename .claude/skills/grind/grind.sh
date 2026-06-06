#!/bin/bash
# Botter grind helper. Drives auto-grind headlessly and tails the log until
# Godot prints "[run] auto-grind COMPLETE", then exits with a structured
# summary. No fixed sleep.
#
# Usage: grind.sh <runs> [speed] [--mortal] [--branch <id>]
#   --mortal       — disable bot invincibility (balance / death testing)
#   --branch <id>  — force every run to deploy to <id> (default: real
#                    progression — picks under-cleared branch in lowest
#                    unlocked tier, advances as bosses are killed)
#
# Logs land in logs/grind/<timestamp>_<speed>x_<runs>runs.log inside the
# repo (gitignored).

set -euo pipefail

RUNS=""
SPEED="16"
MORTAL=0
FORCE_BRANCH=""
PRESET=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --mortal) MORTAL=1; shift ;;
        --branch) FORCE_BRANCH="${2:-}"; shift 2 ;;
        --branch=*) FORCE_BRANCH="${1#--branch=}"; shift ;;
        --preset) PRESET="${2:-}"; shift 2 ;;
        --preset=*) PRESET="${1#--preset=}"; shift ;;
        *)
            if [[ -z "$RUNS" ]]; then RUNS="$1"
            else SPEED="$1"
            fi
            shift ;;
    esac
done

if [[ -z "$RUNS" ]]; then
    echo "Usage: $0 <runs> [speed] [--mortal] [--branch <id>] [--preset <name>]" >&2
    echo "  --preset <name>   Wipe debug save + inject a tier-appropriate loadout." >&2
    echo "                    Names: naked t1 t2 t3 t4 t5" >&2
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

# Optional debug-save purge. The debug save accumulates legacy items
# across sessions — when item schema changes (v2 stats, quality
# tier, etc) leftover items can show as blank until rolled fresh. Run
# with BOTTER_PURGE_SAVE=1 to wipe before grinding. Default keeps
# the save so inject_save.py-written specs survive.
DEBUG_SAVE="$USER_DIR/botter_save_debug.json"
if [[ "${BOTTER_PURGE_SAVE:-0}" == "1" ]] && [[ -f "$DEBUG_SAVE" ]]; then
    rm -f "$DEBUG_SAVE"
    echo "Purged debug save."
fi

# Preset application — wipe the debug save then inject a fresh
# tier-appropriate loadout. Lets balance experiments run against a
# clean baseline instead of the cumulative Lv 300 god the legacy
# debug save has become. New 2026-06-07.
if [[ -n "$PRESET" ]]; then
    PRESET_FILE="$REPO/.claude/skills/grind/presets/${PRESET}.json"
    if [[ ! -f "$PRESET_FILE" ]]; then
        echo "Unknown preset '$PRESET'. Available:" >&2
        ls "$REPO/.claude/skills/grind/presets/" 2>/dev/null | sed 's/\.json$//' | sed 's/^/  /' >&2
        exit 64
    fi
    rm -f "$DEBUG_SAVE"
    cd "$REPO" && python3 tools/inject_save.py "$PRESET_FILE" >/dev/null
    echo "Applied preset: $PRESET"
fi

# Write the marker.
echo "${SPEED},${RUNS}" > "$GRIND_MARKER"

# Launch envs:
#  --mortal               → BOTTER_NO_INVINCIBLE=1 disables grind invuln
#  --branch <id>          → BOTTER_GRIND_BRANCH=<id> forces every deploy
#                           (main.gd::_pick_grind_branch reads this env)
LAUNCH_ENV=()
if [[ "$MORTAL" == "1" ]]; then
    LAUNCH_ENV+=("BOTTER_NO_INVINCIBLE=1")
fi
if [[ -n "$FORCE_BRANCH" ]]; then
    LAUNCH_ENV+=("BOTTER_GRIND_BRANCH=$FORCE_BRANCH")
fi

# Launch Godot headless, log to file, run in background.
env "${LAUNCH_ENV[@]+"${LAUNCH_ENV[@]}"}" "$GODOT" --path "$PROJECT" --headless >"$LOG" 2>&1 &
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

# CRITICAL: clear AUTO_GRIND.txt so the user's next interactive launch
# doesn't silently boot into 16× speed mode. Also clear any parked
# DEBUG_FLOOR.txt — the user wants Godot launches to land in normal play
# mode, not screenshot capture mode.
rm -f "$GRIND_MARKER"
rm -f "$DEBUG_MARKER.parked"

if [[ $DONE -eq 0 ]]; then
    # Auto-recover from stale class_name cache.
    if grep -q 'Parse Error.*not declared' "$LOG" 2>/dev/null; then
        echo "grind: detected stale class cache, refreshing and retrying..." >&2
        bash "$REPO/tools/refresh_class_cache.sh" >/dev/null 2>&1 || true
        echo "${SPEED},${RUNS}" > "$GRIND_MARKER"
        env "${LAUNCH_ENV[@]+"${LAUNCH_ENV[@]}"}" "$GODOT" --path "$PROJECT" --headless >>"$LOG" 2>&1 &
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
