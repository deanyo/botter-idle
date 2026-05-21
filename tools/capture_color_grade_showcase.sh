#!/bin/bash
# Capture per-biome color-grade screenshots after the experiment chain
# finishes. Uses the existing /screenshot skill on a curated list of
# biomes that have color_grade entries.
set -e
cd /Users/dyo/claude/botter

# Wait for playthrough_trio to finish (the last in the chain)
STATUS=logs/balance/.pids/playthrough_trio.status
echo "=== Waiting for playthrough_trio to finish ==="
while [ ! -f "$STATUS" ]; do sleep 60; done
echo "playthrough_trio status: $(cat $STATUS)"

mkdir -p logs/screenshots/color_grade_showcase
sleep 3   # let any lingering Godot processes settle

# 8 biomes, one screenshot each on floor 2 (skips floor 1 which often
# has no decor / is starter-room). Two passes: with grade, without.

echo ""
echo "=== Pass 1: WITH color grade (default) ==="
for biome in dungeon lair swamp crypt tomb forge glacier slime; do
    echo "  $biome..."
    bash .claude/skills/screenshot/screenshot.sh "$biome" _ 2 || true
    sleep 1
done

# Move to a 'with' subdir (the skill writes to a fixed dir, easier to
# move than retag).
USER_SS_DIR="$HOME/Library/Application Support/Godot/app_userdata/Botter/debug_screenshots"
DEST=logs/screenshots/color_grade_showcase/with_grade
mkdir -p "$DEST"
cp "$USER_SS_DIR"/*.png "$DEST/" 2>/dev/null || true
cp "$USER_SS_DIR"/*.json "$DEST/" 2>/dev/null || true

echo ""
echo "=== Pass 2: WITHOUT color grade (BOTTER_NO_GRADE=1) ==="
export BOTTER_NO_GRADE=1
for biome in dungeon lair swamp crypt tomb forge glacier slime; do
    echo "  $biome..."
    bash .claude/skills/screenshot/screenshot.sh "$biome" _ 2 || true
    sleep 1
done

DEST=logs/screenshots/color_grade_showcase/without_grade
mkdir -p "$DEST"
cp "$USER_SS_DIR"/*.png "$DEST/" 2>/dev/null || true
cp "$USER_SS_DIR"/*.json "$DEST/" 2>/dev/null || true

echo ""
echo "=== ALL SCREENSHOTS CAPTURED ==="
echo "with grade:    logs/screenshots/color_grade_showcase/with_grade/"
echo "without grade: logs/screenshots/color_grade_showcase/without_grade/"
