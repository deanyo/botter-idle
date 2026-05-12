#!/bin/bash
# Botter screenshot helper. Drives DEBUG_FLOOR.txt + launches Godot, waits for
# the manifest to update, prints the resulting PNG path on stdout.
#
# Usage: screenshot.sh <biome> [vault_name|_] [floor_num]
#
# Logs land in logs/screenshots/<timestamp>.log inside the repo (gitignored).
# Screenshots themselves live in user://debug_screenshots/ — Godot writes them
# there and we just look up the absolute path via the manifest.

set -euo pipefail

BIOME="${1:-}"
VAULT="${2:-_}"
FLOOR="${3:-1}"

if [[ -z "$BIOME" ]]; then
    echo "Usage: $0 <biome> [vault_name|_] [floor_num]" >&2
    exit 64
fi

GODOT="/Applications/Godot.app/Contents/MacOS/Godot"
REPO="/Users/dyo/claude/botter"
PROJECT="$REPO/project"
USER_DIR="$HOME/Library/Application Support/Godot/app_userdata/Botter"
SHOTS_DIR="$USER_DIR/debug_screenshots"
MARKER="$USER_DIR/DEBUG_FLOOR.txt"
GRIND_MARKER="$USER_DIR/AUTO_GRIND.txt"
MANIFEST="$SHOTS_DIR/_manifest.txt"
LOG_DIR="$REPO/logs/screenshots"

mkdir -p "$SHOTS_DIR" "$LOG_DIR"
TS=$(date +%Y%m%d-%H%M%S)
LOG="$LOG_DIR/${TS}_${BIOME}_${VAULT}_${FLOOR}.log"

# Park AUTO_GRIND if present so it doesn't fight the screenshot launch.
if [[ -f "$GRIND_MARKER" ]]; then
    mv "$GRIND_MARKER" "$GRIND_MARKER.parked"
fi

# Capture previous LAST so we can detect when a new screenshot lands.
PREV_LAST=""
if [[ -f "$MANIFEST" ]]; then
    PREV_LAST=$(grep '^LAST=' "$MANIFEST" 2>/dev/null | tail -1 | sed 's/^LAST=//' || true)
fi

# Write the marker. 4th field = screenshot mode.
echo "$BIOME,$VAULT,$FLOOR,1" > "$MARKER"

# Launch Godot in the background; capture all output to the timestamped log.
"$GODOT" --path "$PROJECT" >"$LOG" 2>&1 &
PID=$!

# Poll the manifest for an updated LAST= line. Godot quits itself when the
# screenshot is saved, so this also handles "process exited cleanly" naturally.
NEW_PATH=""
TIMEOUT_S=30
DEADLINE=$(( $(date +%s) + TIMEOUT_S ))
while [[ $(date +%s) -lt $DEADLINE ]]; do
    if [[ -f "$MANIFEST" ]]; then
        CUR=$(grep '^LAST=' "$MANIFEST" 2>/dev/null | tail -1 | sed 's/^LAST=//' || true)
        if [[ -n "$CUR" && "$CUR" != "$PREV_LAST" ]]; then
            NEW_PATH="$CUR"
            break
        fi
    fi
    # If Godot exited (clean self-quit after save_png), one last manifest check
    # then bail.
    if ! kill -0 $PID 2>/dev/null; then
        sleep 0.1
        if [[ -f "$MANIFEST" ]]; then
            CUR=$(grep '^LAST=' "$MANIFEST" 2>/dev/null | tail -1 | sed 's/^LAST=//' || true)
            if [[ -n "$CUR" && "$CUR" != "$PREV_LAST" ]]; then
                NEW_PATH="$CUR"
            fi
        fi
        break
    fi
    sleep 0.25
done

# If Godot is still running (timeout fallback), kill it.
if kill -0 $PID 2>/dev/null; then
    kill $PID 2>/dev/null || true
    for i in $(seq 1 10); do
        if ! kill -0 $PID 2>/dev/null; then break; fi
        sleep 0.2
    done
    kill -9 $PID 2>/dev/null || true
fi
wait $PID 2>/dev/null || true

if [[ -z "$NEW_PATH" ]]; then
    # Auto-recover from a stale class_name cache. If the log shows a
    # "not declared" parse error, refresh and retry once before giving up.
    if grep -q 'Parse Error.*not declared' "$LOG" 2>/dev/null; then
        echo "screenshot: detected stale class cache, refreshing and retrying..." >&2
        bash "$REPO/tools/refresh_class_cache.sh" >/dev/null 2>&1 || true
        # Retry the launch once.
        "$GODOT" --path "$PROJECT" >>"$LOG" 2>&1 &
        PID=$!
        DEADLINE=$(( $(date +%s) + TIMEOUT_S ))
        while [[ $(date +%s) -lt $DEADLINE ]]; do
            if [[ -f "$MANIFEST" ]]; then
                CUR=$(grep '^LAST=' "$MANIFEST" 2>/dev/null | tail -1 | sed 's/^LAST=//' || true)
                if [[ -n "$CUR" && "$CUR" != "$PREV_LAST" ]]; then
                    NEW_PATH="$CUR"
                    break
                fi
            fi
            if ! kill -0 $PID 2>/dev/null; then break; fi
            sleep 0.25
        done
        if kill -0 $PID 2>/dev/null; then
            kill $PID 2>/dev/null || true
            sleep 0.4
            kill -9 $PID 2>/dev/null || true
        fi
        wait $PID 2>/dev/null || true
    fi
fi

if [[ -z "$NEW_PATH" ]]; then
    echo "screenshot: no new manifest entry detected after ${TIMEOUT_S}s" >&2
    echo "log: $LOG" >&2
    tail -20 "$LOG" >&2
    exit 1
fi

# Convert user:// to absolute path.
ABS_PATH="${NEW_PATH/user:\/\//$USER_DIR/}"

if [[ ! -f "$ABS_PATH" ]]; then
    echo "screenshot: manifest pointed to $ABS_PATH but file does not exist" >&2
    echo "log: $LOG" >&2
    exit 1
fi

# Print human summary + the absolute paths on the last lines so Claude can
# Read both the JSON manifest and the PNG.
JSON_ABS_PATH="${ABS_PATH%.png}.json"
echo "biome=$BIOME vault=$VAULT floor=$FLOOR  log=$LOG"
echo "JSON: $JSON_ABS_PATH"
echo "PNG:  $ABS_PATH"
