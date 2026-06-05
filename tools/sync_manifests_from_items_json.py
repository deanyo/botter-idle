#!/usr/bin/env python3
"""sync_manifests_from_items_json.py — Backfill per-slot manifests from items.json.

The Item Generator (in-game main-menu screen) writes new variants directly to
project/data/items.json, but the editor + sync_items.py flow reads from
tools/items_*_manifest.json. After merging generated variants into items.json,
run this script so the editor sees them.

Idempotent. Reads items.json, walks every item, finds the right manifest for
its slot (weapons split by base_type), and appends any items missing from
that manifest.

Run from the repo root:
    python3 tools/sync_manifests_from_items_json.py

Reports counts per manifest.
"""

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

SLOT_TO_MANIFEST = {
    'helm':    'tools/items_helms_manifest.json',
    'armor':   'tools/items_armor_manifest.json',
    'shield':  'tools/items_shields_manifest.json',
    'boots':   'tools/items_boots_manifest.json',
    'ring':    'tools/items_rings_manifest.json',
    'amulet':  'tools/items_amulets_manifest.json',
    'gloves':  'tools/items_gloves_manifest.json',
    'cloak':   'tools/items_cloaks_manifest.json',
}

WEAPON_1H_MANIFEST = 'tools/items_manifest.json'
WEAPON_EXT_MANIFEST = 'tools/items_weapons_extended_manifest.json'


def main():
    db = json.load(open(ROOT / 'project/data/items.json'))

    # Load every manifest + build a base_type → manifest routing for weapons.
    manifests = {}
    for slot, path in SLOT_TO_MANIFEST.items():
        manifests[slot] = (path, json.load(open(ROOT / path)))
    m1 = json.load(open(ROOT / WEAPON_1H_MANIFEST))
    m2 = json.load(open(ROOT / WEAPON_EXT_MANIFEST))
    manifests['weapon_1h'] = (WEAPON_1H_MANIFEST, m1)
    manifests['weapon_ext'] = (WEAPON_EXT_MANIFEST, m2)
    m1_base_types = set(m1.get('base_types', {}).keys())

    # Existing items per manifest (id index for collision check).
    existing_ids = {key: {i['id'] for i in mf['items']} for key, (_, mf) in manifests.items()}

    missing = {key: [] for key in manifests}
    for it in db['items']:
        slot = it.get('slot')
        if slot == 'spell':
            continue
        if slot == 'weapon':
            bt = it.get('base_type', '')
            target = 'weapon_1h' if bt in m1_base_types else 'weapon_ext'
        elif slot in SLOT_TO_MANIFEST:
            target = slot
        else:
            continue
        if it['id'] not in existing_ids[target]:
            missing[target].append(it)

    total_added = 0
    for key, items_to_add in missing.items():
        if not items_to_add:
            continue
        path, mf = manifests[key]
        mf['items'].extend(items_to_add)
        with open(ROOT / path, 'w') as f:
            json.dump(mf, f, indent=2)
            f.write('\n')
        total_added += len(items_to_add)
        print(f'  + {len(items_to_add):3} → {path} (now {len(mf["items"])} items)')

    if total_added == 0:
        print('All manifests already in sync with items.json.')
    else:
        print(f'\nAdded {total_added} items across all manifests. Reload the item editor.')


if __name__ == '__main__':
    main()
