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

    # Build id-indexed views for in-place updates (so edits to items.json
    # propagate even when ids already exist in the manifest — e.g. after
    # balance_generated_items.py rewrites lore/rarity/affix_pool).
    manifest_index = {
        key: {i['id']: i for i in mf['items']} for key, (_, mf) in manifests.items()
    }

    additions = {key: 0 for key in manifests}
    updates = {key: 0 for key in manifests}
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
        path, mf = manifests[target]
        existing = manifest_index[target].get(it['id'])
        if existing is None:
            mf['items'].append(it)
            manifest_index[target][it['id']] = it
            additions[target] += 1
        elif existing != it:
            # Replace in-place to preserve item ordering inside the
            # manifest. Same id, content drift detected.
            for i, m_it in enumerate(mf['items']):
                if m_it['id'] == it['id']:
                    mf['items'][i] = it
                    break
            manifest_index[target][it['id']] = it
            updates[target] += 1

    total_added = 0
    total_updated = 0
    for key, (path, mf) in manifests.items():
        if additions[key] or updates[key]:
            with open(ROOT / path, 'w') as f:
                json.dump(mf, f, indent=2)
                f.write('\n')
            bits = []
            if additions[key]:
                bits.append(f'+{additions[key]} new')
            if updates[key]:
                bits.append(f'~{updates[key]} updated')
            print(f'  {", ".join(bits):20} → {path} (now {len(mf["items"])} items)')
            total_added += additions[key]
            total_updated += updates[key]

    if total_added == 0 and total_updated == 0:
        print('All manifests already in sync with items.json.')
    else:
        print(f'\nAdded {total_added}, updated {total_updated} across all manifests. Reload the item editor.')


if __name__ == '__main__':
    main()
