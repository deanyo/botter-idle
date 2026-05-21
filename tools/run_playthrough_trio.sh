#!/bin/bash
# Wait for full_suite to finish, then run 3 playthrough policy combos.
set -e
cd /Users/dyo/claude/botter

STATUS=logs/balance/.pids/full_suite.status

echo "=== Waiting for full_suite to finish ==="
while [ ! -f "$STATUS" ]; do
    sleep 60
done
echo "full_suite exited with status: $(cat $STATUS)"

# Sanity: ensure no leftover Godot process before kicking off (otherwise
# the playthrough's auto-grind marker would race).
sleep 5

echo ""
echo "=== Playthrough 1/3: score_weighted + round_robin + strict ==="
python3 -u .claude/skills/playthrough/playthrough.py \
    --equip score_weighted --upgrade round_robin --advance strict \
    --seed-base 6000 --max-runs 200

# Reset save between policies so each run starts fresh from the same baseline.
rm -f "$HOME/Library/Application Support/Godot/app_userdata/Botter/botter_save_debug.json"

echo ""
echo "=== Playthrough 2/3: pure_dps + combat_first + strict ==="
python3 -u .claude/skills/playthrough/playthrough.py \
    --equip pure_dps --upgrade combat_first --advance strict \
    --seed-base 7000 --max-runs 200

rm -f "$HOME/Library/Application Support/Godot/app_userdata/Botter/botter_save_debug.json"

echo ""
echo "=== Playthrough 3/3: score_weighted + hp_first + cautious ==="
python3 -u .claude/skills/playthrough/playthrough.py \
    --equip score_weighted --upgrade hp_first --advance cautious \
    --seed-base 8000 --max-runs 200

echo ""
echo "=== ALL THREE PLAYTHROUGHS COMPLETE ==="
