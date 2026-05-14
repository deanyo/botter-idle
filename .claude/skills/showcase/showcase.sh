#!/bin/bash
# Botter visual showcase — launches Godot windowed on a hand-curated audit
# floor. Bot patrols a fixed loop so its light reveals each station in turn.
# No screenshot / auto-quit — exits when the user closes the window.
#
# Usage: showcase.sh
#
# Stations include: fire/magic/crystal/mushroom decor (decor-tier flicker),
# campfire (actor-tier flicker, comparison reference), lava/water/ice
# terrain, fountains, altars, loot rarity ladder, chests, portal, fire/ice
# creatures with attached lights.

set -euo pipefail

GODOT="/Applications/Godot.app/Contents/MacOS/Godot"
REPO="/Users/dyo/claude/botter"
PROJECT="$REPO/project"
USER_DIR="$HOME/Library/Application Support/Godot/app_userdata/Botter"
MARKER="$USER_DIR/DEBUG_FLOOR.txt"
GRIND_MARKER="$USER_DIR/AUTO_GRIND.txt"
LOG_DIR="$REPO/logs/showcase"

mkdir -p "$USER_DIR" "$LOG_DIR"
TS=$(date +%Y%m%d-%H%M%S)
LOG="$LOG_DIR/${TS}_showcase.log"

# Park AUTO_GRIND if present so it doesn't fight the launch.
if [[ -f "$GRIND_MARKER" ]]; then
    mv "$GRIND_MARKER" "$GRIND_MARKER.parked"
fi

# Marker: "showcase" tells main.gd to set DebugJump.showcase=true. No biome
# arg needed — the showcase floor is biome-agnostic (uses "dungeon" biome
# tile theme as a neutral baseline).
echo "showcase" > "$MARKER"

cleanup() {
    # Marker hygiene — the user's next interactive launch must land in
    # normal play, not the showcase floor.
    rm -f "$MARKER"
    rm -f "$GRIND_MARKER.parked"
}
trap cleanup EXIT INT TERM

echo "showcase: launching Botter windowed at the visual audit floor"
echo "log: $LOG"
echo "(close the Godot window to exit)"

# Foreground launch. Skill returns when the user closes the window or
# hits Cmd-Q. stdout/err captured for diagnostics.
"$GODOT" --path "$PROJECT" 2>&1 | tee "$LOG"
