#!/usr/bin/env python3
"""rebalance_v6.py — Second iteration of outlier fixes.

After v5 + the prismatic-bumps trim + weapon_class bucketing, the
audit surfaced new outliers in narrower buckets. This pass handles:

A. 1H weapons over-rolling (eveningstar, demon_whip, runed_eveningstar).
B. Under-rolled 1H rares (mithril_shortsword, braided_whip).
C. Doom_knight_blade / sword_of_cerebov / demon_blade_umbral (1H
   legendary T5) — same demon_blade family, identical dmg, top of bucket.
   v5 already trimmed demon_blade. Now the same trim for the variants.
"""

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DB = ROOT / 'project/data/items.json'
db = json.loads(DB.read_text())

MARKER = '_rebalance_v6'

WEAPON_FIXES = {
    # Trim over-rolled 1H weapons
    'eveningstar':       {'damage_min': 44, 'damage_max': 78},   # 57-100 → 44-78
    'demon_whip':        {'damage_min': 60, 'damage_max': 108},  # 75-134 → 60-108
    'runed_eveningstar': {'damage_min': 70, 'damage_max': 124},  # 90-157 → 70-124
    # Bump under-rolled 1H rares
    'mithril_shortsword':{'damage_min': 27, 'damage_max': 48},   # 19-36 → 27-48
    'braided_whip':      {'damage_min': 27, 'damage_max': 47},   # 19-33 → 27-47
    'iron_katana':       {'damage_min': 38, 'damage_max': 65},   # 30-52 → 38-65
    'iron_katana_coppersworn': {'damage_min': 38, 'damage_max': 65},
    # Variants of demon_blade family — match v5 trim
    'doom_knight_blade': {'damage_min': 122, 'damage_max': 215},
    'sword_of_cerebov':  {'damage_min': 122, 'damage_max': 215},
    # Trim doomed_executioner
    'doomed_executioner':{'damage_min': 175, 'damage_max': 305},  # 202-345 → 175-305
}

count = 0
for it in db['items']:
    if it.get(MARKER):
        continue
    if it['id'] not in WEAPON_FIXES:
        continue
    fix = WEAPON_FIXES[it['id']]
    for k, v in fix.items():
        it[k] = v
    it[MARKER] = True
    count += 1
print(f'v6 weapon fixes: {count}')

with open(DB, 'w') as f:
    json.dump(db, f, indent=2)
    f.write('\n')
