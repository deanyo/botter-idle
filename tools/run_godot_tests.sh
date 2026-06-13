#!/bin/bash
# Standalone GUT test runner. Invokes only the test phase that lives
# inside check_before_commit.sh step 3/5 — useful when iterating on
# tests themselves (no need to wait for the full pre-commit gauntlet)
# or when CI wants to gate on tests separately from biome builds /
# data integrity / ceiling checks.
#
# Usage:
#   ./tools/run_godot_tests.sh               # all tests
#   ./tools/run_godot_tests.sh test_stat     # only test_stat*.gd files
#
# Output: streams GUT's report to stdout; exits 0 on pass, non-zero
# on any failure. Cap commit hook reuses the same Godot invocation
# directly — duplication is intentional so editing one path doesn't
# silently break the other.

set -e -o pipefail

GODOT="${GODOT_BIN:-/Applications/Godot.app/Contents/MacOS/Godot}"
PROJECT="$(cd "$(dirname "$0")/.." && pwd)/project"

if [[ ! -x "$GODOT" ]]; then
    echo "ERROR: Godot binary not found at $GODOT" >&2
    echo "Set GODOT_BIN=/path/to/Godot to override." >&2
    exit 2
fi

if [[ ! -d "$PROJECT/tests" ]]; then
    echo "ERROR: $PROJECT/tests not found — wrong working directory?" >&2
    exit 2
fi

# GUT cmdln args:
#   -gdir=res://tests   discover tests under project/tests/
#   -gexit              exit Godot after the run (no editor pop-up)
#   -gprefix=test_      run files whose names begin with test_
#   -ginclude_subdirs   walk subdirs (we don't currently nest, but
#                       it's the safer default for future growth)
ARGS=(--path "$PROJECT" --headless
      -s addons/gut/gut_cmdln.gd
      -gdir=res://tests
      -gprefix=test_
      -ginclude_subdirs
      -gexit)

# Optional 1st arg = filename prefix filter (e.g. "test_stat" runs only
# tests under test_stat*.gd). GUT's cmdln supports -gselect to narrow.
if [[ -n "${1:-}" ]]; then
    ARGS+=("-gselect=$1")
fi

"$GODOT" "${ARGS[@]}"
