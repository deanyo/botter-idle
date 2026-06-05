#!/usr/bin/env python3
"""rebalance_v5.py — Targeted outlier fixes from the 1.5σ audit.

Categorized fixes:

A. SPELL-ARCHETYPE TUNING — systemic, applied to every variant of an
   archetype:
   - spell_axes:     under-tuned (5.0s CD × 14 dmg = 2.8 DPS). Bump
                     base damage 14 → 22 so the 5s commitment pays.
   - spell_frost_nova: also under-tuned at uncommon/rare. Bump 16 → 20.
   - spell_sandblast: over-tuned. Trim 30 → 24.

B. WEAPON UNIQUES — hand-rolled outliers in items.json. Bump the weak
   knives + the under-tuned T3 rares; trim the over-rolled giant club.

C. PRISMATIC FLAVOR — narrow the bump list so prismatic armor/shields
   don't always blow past +3σ.

Idempotent: re-running detects already-applied changes via a marker
key on each adjusted item.
"""

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DB = ROOT / 'project/data/items.json'
db = json.loads(DB.read_text())

MARKER = '_rebalance_v5'

# --- A. Spell archetype damage tuning ---
ARCH_DMG_DELTA = {
    # archetype: (mult_for_damage_min, mult_for_damage_max)
    'spell_axes':       (1.55, 1.55),  # 14 → 22, 22 → 34 etc
    'spell_frost_nova': (1.25, 1.25),  # 16 → 20
    'spell_sandblast':  (0.80, 0.80),  # 30 → 24
}

a_count = 0
for it in db['items']:
    if it.get(MARKER):
        continue
    if it.get('slot') != 'spell':
        continue
    arch = it.get('base_type', '')
    if arch not in ARCH_DMG_DELTA:
        continue
    mn_mult, mx_mult = ARCH_DMG_DELTA[arch]
    new_min = int(round(float(it.get('damage_min', 0)) * mn_mult))
    new_max = int(round(float(it.get('damage_max', 0)) * mx_mult))
    if new_min != it.get('damage_min') or new_max != it.get('damage_max'):
        it['damage_min'] = new_min
        it['damage_max'] = new_max
        it[MARKER] = True
        a_count += 1
print(f'A. Spell archetype damage retuned: {a_count} variants')

# --- B. Weapon unique fixes ---
# Bumps for under-tuned uniques + trims for over-rolled.
WEAPON_FIXES = {
    # id: {damage_min, damage_max, ...}
    # Under-tuned — bump damage:
    'spriggans_knife':   {'damage_min': 38, 'damage_max': 70, 'speed': 0.45},
    'knife_of_accuracy': {'damage_min': 24, 'damage_max': 46, 'speed': 0.45},
    'naval_cutlass':     {'damage_min': 28, 'damage_max': 48},
    'steel_warhammer':   {'damage_min': 28, 'damage_max': 48},
    'ankus':             {'damage_min': 28, 'damage_max': 48},
    'elven_dagger':      {'damage_min': 9,  'damage_max': 16},
    # Over-tuned — gentle trim:
    'demon_blade':         {'damage_min': 122, 'damage_max': 215},  # 143-250 → 122-215
    'demon_blade_umbral':  {'damage_min': 122, 'damage_max': 215},
    'demon_blade_embered': {'damage_min': 122, 'damage_max': 215},
    'scythe':            {'damage_min': 32, 'damage_max': 60},  # 40-74 → 32-60
    'giant_club':        {'damage_min': 64, 'damage_max': 112},  # 77-134 → 64-112
    'giant_club_crimson':{'damage_min': 64, 'damage_max': 112},
    'bardiche':          {'damage_min': 56, 'damage_max': 100},  # 67-120 → 56-100
}
b_count = 0
for it in db['items']:
    if it.get(MARKER):
        continue
    if it['id'] not in WEAPON_FIXES:
        continue
    fix = WEAPON_FIXES[it['id']]
    for k, v in fix.items():
        it[k] = v
    it[MARKER] = True
    b_count += 1
print(f'B. Weapon uniques retuned: {b_count}')

# --- C. Prismatic flavor trim ---
# Prismatic items have an outsized affix_pool because the FLAVOR_AFFIX_BUMPS
# table adds weight to all 7 elements + 3 masteries simultaneously
# (~180 weight bump). For armor/shield bases that already have decent
# pools this pushes them past +3σ. Cap each prismatic bump at 12 so the
# total prismatic contribution is ~120 not ~180.
prismatic_count = 0
for it in db['items']:
    if it.get(MARKER):
        continue
    if not it.get('id', '').endswith('_prismatic'):
        continue
    pool = it.get('affix_pool', {})
    bumps = it.get('_balance_bumps', {})
    if not bumps:
        continue
    # For each bump > 12, reduce both the bump record and the pool weight.
    new_bumps = {}
    for k, v in bumps.items():
        capped = min(int(v), 12)
        delta = int(v) - capped
        if delta > 0 and k in pool:
            pool[k] = max(0, int(pool[k]) - delta)
            if pool[k] <= 0:
                del pool[k]
        new_bumps[k] = capped
    it['_balance_bumps'] = new_bumps
    it[MARKER] = True
    prismatic_count += 1
print(f'C. Prismatic flavor trim: {prismatic_count} items')

# Save
with open(DB, 'w') as f:
    json.dump(db, f, indent=2)
    f.write('\n')
print(f'\nTotal: {a_count + b_count + prismatic_count} items adjusted.')
print('Re-run python3 tools/audit_item_levels.py to verify.')
