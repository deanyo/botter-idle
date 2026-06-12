#!/usr/bin/env python3
"""Strip 3 dead audit-residue metadata fields from project/data/items.json.

`_balance_bumps`, `_rebalance_v5`, `_rebalance_v6` are tombstones from
prior balance migrations (per A1-residue-020). They contribute ~50KB of
dead data and are never read by game code or tooling — confirmed via
`grep -rn '_balance_bumps' project/scripts/ tools/` returning hits only
inside items.json itself.

Run from repo root:
    python3 tools/strip_audit_residue.py --dry-run
    python3 tools/strip_audit_residue.py        # actually writes

Idempotent: re-running on a clean file is a no-op (reports 0 strips).
Keep the script around so future tombstone reintroductions can be
swept in one command.
"""
from __future__ import annotations
import argparse
import json
import os
import sys

REPO_ROOT = os.path.dirname(os.path.abspath(os.path.dirname(__file__)))
ITEMS_JSON = os.path.join(REPO_ROOT, 'project', 'data', 'items.json')
DEAD_FIELDS = ('_balance_bumps', '_rebalance_v5', '_rebalance_v6')


def strip(items: list[dict]) -> dict[str, int]:
    counts = {f: 0 for f in DEAD_FIELDS}
    for it in items:
        for f in DEAD_FIELDS:
            if f in it:
                counts[f] += 1
                del it[f]
    return counts


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument('--dry-run', action='store_true',
                    help='report counts without writing items.json')
    args = ap.parse_args()

    size_before = os.path.getsize(ITEMS_JSON)
    with open(ITEMS_JSON) as f:
        doc = json.load(f)

    counts = strip(doc['items'])
    total = sum(counts.values())

    print(f'items.json: {len(doc["items"])} items, {size_before:,} bytes before')
    for field, n in counts.items():
        print(f'  {field}: {n} stripped')
    print(f'total field strips: {total}')

    if args.dry_run:
        print('[dry-run] no file written.')
        return 0

    if total == 0:
        print('nothing to strip; items.json unchanged.')
        return 0

    with open(ITEMS_JSON, 'w') as f:
        json.dump(doc, f, indent=2)
    size_after = os.path.getsize(ITEMS_JSON)
    delta = size_before - size_after
    print(f'wrote items.json: {size_after:,} bytes after (delta {delta:+,})')
    return 0


if __name__ == '__main__':
    sys.exit(main())
