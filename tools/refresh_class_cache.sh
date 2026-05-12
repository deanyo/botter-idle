#!/bin/bash
# Refresh Godot's global script class cache. Run after adding a new
# class_name declaration to ensure headless launches don't fail with
# "class not declared" parse errors.
#
# Usage: bash tools/refresh_class_cache.sh
#
# Takes ~5-10s. Updates project/.godot/global_script_class_cache.cfg.

set -euo pipefail

GODOT="/Applications/Godot.app/Contents/MacOS/Godot"
PROJECT="/Users/dyo/claude/botter/project"

if [[ ! -x "$GODOT" ]]; then
    echo "Godot not found at $GODOT" >&2
    exit 1
fi

echo "Refreshing class cache..."
"$GODOT" --path "$PROJECT" --headless --import 2>&1 | tail -3

CACHE="$PROJECT/.godot/global_script_class_cache.cfg"
if [[ -f "$CACHE" ]]; then
    CLASSES=$(grep -c '^"class":' "$CACHE" || echo 0)
    echo "OK — cache regenerated with $CLASSES classes."
else
    echo "Warning: cache file $CACHE not found after import." >&2
    exit 1
fi
