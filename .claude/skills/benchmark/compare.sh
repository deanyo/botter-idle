#!/bin/bash
# Compare two benchmark logs. Prints per-tag avg/p95 deltas.
# Usage: compare.sh <baseline.log> <after.log>
set -euo pipefail
A="${1:-}"
B="${2:-}"
if [[ -z "$A" || -z "$B" ]]; then
    echo "usage: $0 <baseline.log> <after.log>" >&2; exit 64
fi
exec python3 "$(dirname "$0")/compare_perf.py" "$A" "$B"
