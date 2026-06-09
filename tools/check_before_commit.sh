#!/bin/bash
# Pre-commit validation. Catches generator regressions and GDScript parse
# errors before they land. Run before any commit that touches .gd files
# or generator-relevant data (biomes.json, vaults/).
#
# Usage: bash tools/check_before_commit.sh
#
# Exits 0 on pass, non-zero on fail. Fast — should complete in < 30s.

set -uo pipefail

GODOT="/Applications/Godot.app/Contents/MacOS/Godot"
REPO="/Users/dyo/claude/botter"
PROJECT="$REPO/project"
LOG_DIR="$REPO/logs/precommit"
mkdir -p "$LOG_DIR"
TS=$(date +%Y%m%d-%H%M%S)
LOG="$LOG_DIR/${TS}.log"

# Sample biomes — one per architectural family for breadth without
# blowing the runtime. Includes biomes that exercise every layout id.
SAMPLE_BIOMES=(dungeon lair vaults crypt forge glacier slime spider zot)

FAIL=0

# 1. Refresh class cache (catches "class not declared" for any new class_name)
echo "1/5  Refreshing class cache..."
if ! "$GODOT" --path "$PROJECT" --headless --import >"$LOG" 2>&1; then
    echo "FAIL: --import failed (see $LOG)" >&2
    tail -10 "$LOG" >&2
    exit 1
fi

# 2. Flavor coverage gate. Every flavor tag used in items.json or
# enchant_combos.json must exist in BOTH UITheme.FLAVOR_COLORS and
# AffixSystem.ENCHANT_BLURBS — without that, the UI shows un-colored
# tooltips and missing blurbs. Audit 2026-06-09 found "lightning" in 3
# items + 6 combos clashing with "thunderous" everywhere else; this
# step catches that drift the day it lands.
echo "2/5  Checking flavor-tag coverage + credits sync..."
COV_LOG="$LOG_DIR/${TS}_flavor_coverage.log"
if ! python3 "$REPO/tools/check_flavor_coverage.py" >"$COV_LOG" 2>&1; then
    echo "FAIL: flavor coverage gap (see $COV_LOG)" >&2
    cat "$COV_LOG" >&2
    FAIL=1
fi
# Credits / notice sync — repo-root .md is authoritative; project/data/
# *.txt is the shipped copy the in-game credits screen reads. Drift
# would silently let the in-game attribution lag the canonical one.
SYNC_LOG="$LOG_DIR/${TS}_credits_sync.log"
if ! python3 "$REPO/tools/sync_credits.py" --check >"$SYNC_LOG" 2>&1; then
    echo "FAIL: credits/notice drift (see $SYNC_LOG)" >&2
    cat "$SYNC_LOG" >&2
    FAIL=1
fi

# 3. GUT test suite. Discovers project/tests/test_*.gd and runs every
# test_* function. Locks: StatCalc unification (blessing kinds,
# species mods, lifesteal clamp, spell_element_pct), Actor combat
# correctness (single avoidance roll per swing, thorns/crystal
# aggregation, spell element piping), SaveState migrations
# (idempotence, octopode ring2 regression, ring1/ring2 collapse),
# AffixSystem rolling (reproducibility, applies_to filter, spell
# flag-affix gating), DungeonGenerator connectivity (spawn reaches
# stairs across biome × layout × seed cross-section).
#
# CONVENTION: every Tier 1+ fix should add at least one regression
# test to the relevant test_*.gd file before the fix is committed.
# Tests are cheap (~3s for the full suite as of 2026-06-09) — there's
# no excuse to skip them.
echo "3/5  Running GUT test suite..."
TEST_LOG="$LOG_DIR/${TS}_gut.log"
if ! "$GODOT" --path "$PROJECT" --headless \
        -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit \
        >"$TEST_LOG" 2>&1; then
    echo "FAIL: GUT tests failed (see $TEST_LOG)" >&2
    grep -E '\[Failed\]|^- test_|Failing Tests|Asserts' "$TEST_LOG" | tail -25 >&2
    FAIL=1
fi

# 4. Per-biome 1-floor smoke build via debug-jump (no screenshot — just gen)
USER_DIR="$HOME/Library/Application Support/Godot/app_userdata/Botter"
mkdir -p "$USER_DIR"
DEBUG_MARKER="$USER_DIR/DEBUG_FLOOR.txt"
GRIND_MARKER="$USER_DIR/AUTO_GRIND.txt"

# Park any active markers
[[ -f "$DEBUG_MARKER" ]] && mv "$DEBUG_MARKER" "$DEBUG_MARKER.precommit_parked"
[[ -f "$GRIND_MARKER" ]] && mv "$GRIND_MARKER" "$GRIND_MARKER.precommit_parked"

echo "4/5  Smoke-building 1 floor each across ${#SAMPLE_BIOMES[@]} biomes..."
for biome in "${SAMPLE_BIOMES[@]}"; do
    # Floor 1, no vault, no screenshot mode (4th field unset)
    echo "${biome},_,1" > "$DEBUG_MARKER"
    SUB_LOG="$LOG_DIR/${TS}_${biome}.log"
    "$GODOT" --path "$PROJECT" --headless >"$SUB_LOG" 2>&1 &
    PID=$!
    # Wait for floor build to complete, then kill. Generator builds in
    # well under a second; we add headroom.
    sleep 4
    {
        kill $PID 2>/dev/null
        sleep 0.3
        kill -9 $PID 2>/dev/null
        wait $PID 2>/dev/null
    } &>/dev/null || true

    # Check for parse errors / SCRIPT errors / bad-floor flags
    if grep -qE 'Parse Error|SCRIPT ERROR' "$SUB_LOG"; then
        echo "FAIL: $biome - parse/script error" >&2
        grep -E 'Parse Error|SCRIPT ERROR' "$SUB_LOG" | head -3 >&2
        FAIL=1
    fi
    if grep -q '\[bad-floor\]' "$SUB_LOG"; then
        echo "WARN: $biome - bad-floor flagged" >&2
        grep '\[bad-floor\]' "$SUB_LOG" | head -1 >&2
        # bad-floor is a warning not a failure (some randomness allowed)
    fi
    if ! grep -q '\[gen\] f=1' "$SUB_LOG"; then
        echo "FAIL: $biome - no [gen] f=1 line found (build never started?)" >&2
        tail -5 "$SUB_LOG" >&2
        FAIL=1
    fi
done

# Restore parked markers
[[ -f "$DEBUG_MARKER.precommit_parked" ]] && mv "$DEBUG_MARKER.precommit_parked" "$DEBUG_MARKER"
[[ -f "$GRIND_MARKER.precommit_parked" ]] && mv "$GRIND_MARKER.precommit_parked" "$GRIND_MARKER"
[[ -f "$DEBUG_MARKER" && ! -f "$DEBUG_MARKER.precommit_parked" ]] || rm -f "$DEBUG_MARKER" 2>/dev/null

# Clear the precommit-set marker if no original was parked
if [[ ! -f "$USER_DIR/DEBUG_FLOOR.txt.precommit_parked" ]]; then
    rm -f "$USER_DIR/DEBUG_FLOOR.txt"
fi

# 5. Summary
echo "5/5  Summary"
if [[ $FAIL -eq 0 ]]; then
    echo "PASS — ${#SAMPLE_BIOMES[@]} biomes built without errors."
    echo "logs: $LOG_DIR/${TS}_*.log"
    exit 0
else
    echo "FAIL — see logs in $LOG_DIR/${TS}_*.log" >&2
    exit 1
fi
