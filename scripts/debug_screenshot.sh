#!/bin/bash
# debug_screenshot.sh — capture a biome/vault screenshot and print its path.
# Usage:
#   ./debug_screenshot.sh <biome>                  # screenshot of biome
#   ./debug_screenshot.sh <biome> <vault>          # screenshot with forced vault
#   ./debug_screenshot.sh <biome> <vault> <floor>  # screenshot at specific floor
#
# Output: prints the full path of the resulting PNG to stdout. Pipe or capture
# to feed straight into a Read tool call.
#
# Returns 1 if Godot fails to launch or screenshot fails to write.

set -e

BIOME="${1:?usage: $0 <biome> [vault] [floor]}"
VAULT="${2:-_}"
FLOOR="${3:-1}"
USERDIR="$HOME/Library/Application Support/Godot/app_userdata/Botter"
PROJECT_DIR="/Users/dyo/claude/botter/project"
GODOT="/Applications/Godot.app/Contents/MacOS/Godot"

# Compose marker. Use _ for unset slots.
echo "${BIOME},${VAULT},${FLOOR},1" > "$USERDIR/DEBUG_FLOOR.txt"

# Brief settle so any inotify on the file fires before Godot starts.
sleep 0.2

# Run silently. Use --path to be explicit about project dir so Godot doesn't
# fall back to current dir and emit "no main scene" errors.
"$GODOT" --path "$PROJECT_DIR" > /tmp/debug_screenshot_${BIOME}.log 2>&1

# Read manifest to find the saved path. Manifest format: name=path per line.
MANIFEST="$USERDIR/debug_screenshots/_manifest.txt"
if [ ! -f "$MANIFEST" ]; then
    echo "ERROR: manifest not written; check /tmp/debug_screenshot_${BIOME}.log" >&2
    exit 1
fi

# Resolve key: biome_vault if vault given, else just biome.
KEY="$BIOME"
if [ "$VAULT" != "_" ] && [ -n "$VAULT" ]; then
    KEY="${BIOME}_${VAULT}"
fi

LINE=$(grep "^${KEY}=" "$MANIFEST" | tail -1)
if [ -z "$LINE" ]; then
    echo "ERROR: no manifest entry for '${KEY}'; check log /tmp/debug_screenshot_${BIOME}.log" >&2
    cat "$MANIFEST" >&2
    exit 1
fi

# Extract the user:// path and convert to absolute.
USERPATH="${LINE#*=}"
ABSPATH="${USERPATH/user:\/\//$USERDIR/}"

if [ ! -f "$ABSPATH" ]; then
    echo "ERROR: screenshot file missing at $ABSPATH" >&2
    exit 1
fi

# Print only the absolute path so it can be piped.
echo "$ABSPATH"
