#!/bin/bash
# Wait for the regen5 backfill to finish, then run combo + cliff back-to-back.
set -e
cd /Users/dyo/claude/botter

STATUS=logs/balance/.pids/regen5_backfill.status

echo "=== Waiting for regen5 backfill to finish ==="
while [ ! -f "$STATUS" ]; do
    sleep 30
done
echo "regen5 backfill exited with status: $(cat $STATUS)"

echo ""
echo "=== Starting Experiment A + B ==="
python3 -u tools/run_combo_and_cliff.py
