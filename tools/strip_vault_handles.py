#!/usr/bin/env python3
"""Rename DCSS-derived vault files to opaque per-theme sequential IDs.

The 1320 files under project/data/vaults/des_*.json carry contributor
handles in both the filename (des_<author>_*.json) and the JSON `name`
field. Original DCSS contributors are credited in NOTICE.md; per-file
identity in our repo doesn't need to expose them.

This script:
  1. Walks project/data/vaults/, finds every des_*.json
  2. Computes a stable per-theme sequential ID
       vault_<primary_theme>_<NNNN>.json
     primary_theme is themes[0] unless that's "dungeon" and themes[1]
     exists (most ported vaults have themes=["dungeon"] which would
     all collide into one bucket); the NNNN sort key is the original
     filename, so reruns are deterministic.
  3. Reads each JSON, moves `name` → `_original_dcss_id` (preserved
     for attribution), sets `name` to the new opaque ID.
  4. Renames the file.
  5. Writes vault_id_map.json: {old_filename: {new_filename, new_name,
     original_name, primary_theme}} — durable audit trail.

Hand-authored vaults (sigil_*, crypt_*, swamp_*, etc.) are passed
through untouched; they don't carry DCSS contributor handles.

Run from repo root:
    python3 tools/strip_vault_handles.py --dry-run
    python3 tools/strip_vault_handles.py        # actually renames

After running, re-run tools/build_vault_bundle.py so the bundle
reflects the new IDs.
"""
from __future__ import annotations
import argparse
import json
import os
import sys
from collections import defaultdict

REPO_ROOT = os.path.dirname(os.path.abspath(os.path.dirname(__file__)))
VAULT_DIR = os.path.join(REPO_ROOT, 'project', 'data', 'vaults')
MAP_OUT = os.path.join(REPO_ROOT, 'project', 'data', 'vault_id_map.json')


def primary_theme(themes: list[str]) -> str:
    if not themes:
        return 'misc'
    head = themes[0]
    if head == 'dungeon' and len(themes) > 1:
        return themes[1]
    return head


def plan_renames(vault_dir: str) -> tuple[dict, list[str]]:
    """Return (rename_map, warnings).

    rename_map[old_filename] = {
        'new_filename': str, 'new_name': str,
        'original_name': str, 'primary_theme': str,
    }
    """
    warnings: list[str] = []
    by_theme: dict[str, list[tuple[str, dict]]] = defaultdict(list)
    for fname in sorted(os.listdir(vault_dir)):
        if not fname.endswith('.json'):
            continue
        if not fname.startswith('des_'):
            # Hand-authored — passthrough.
            continue
        full = os.path.join(vault_dir, fname)
        try:
            with open(full) as f:
                v = json.load(f)
        except json.JSONDecodeError as e:
            warnings.append(f'malformed JSON: {fname}: {e}')
            continue
        theme = primary_theme(v.get('themes', []))
        by_theme[theme].append((fname, v))

    rename_map: dict[str, dict] = {}
    for theme, files in by_theme.items():
        for idx, (fname, v) in enumerate(files):
            new_name = f'vault_{theme}_{idx:04d}'
            new_filename = new_name + '.json'
            rename_map[fname] = {
                'new_filename': new_filename,
                'new_name': new_name,
                'original_name': v.get('name', fname[:-5]),
                'primary_theme': theme,
            }
    return rename_map, warnings


def detect_collisions(vault_dir: str, rename_map: dict) -> list[str]:
    existing = set(os.listdir(vault_dir))
    new_filenames = [info['new_filename'] for info in rename_map.values()]
    collisions: list[str] = []
    seen: set[str] = set()
    for nf in new_filenames:
        if nf in seen:
            collisions.append(f'duplicate new filename in plan: {nf}')
        seen.add(nf)
    # Collisions vs hand-authored (non-des) vaults
    for nf in seen:
        if nf in existing and nf not in rename_map:
            collisions.append(f'new filename {nf} collides with existing non-des file')
    return collisions


def apply_renames(vault_dir: str, rename_map: dict) -> int:
    n = 0
    for old_fname, info in rename_map.items():
        old_path = os.path.join(vault_dir, old_fname)
        new_path = os.path.join(vault_dir, info['new_filename'])
        with open(old_path) as f:
            v = json.load(f)
        v['_original_dcss_id'] = info['original_name']
        v['name'] = info['new_name']
        with open(new_path, 'w') as f:
            json.dump(v, f, indent=2)
        if os.path.abspath(old_path) != os.path.abspath(new_path):
            os.remove(old_path)
        n += 1
    return n


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument('--dry-run', action='store_true',
                    help='print the rename plan without touching files')
    args = ap.parse_args()

    rename_map, warnings = plan_renames(VAULT_DIR)
    for w in warnings:
        print(f'WARN: {w}', file=sys.stderr)

    collisions = detect_collisions(VAULT_DIR, rename_map)
    if collisions:
        print('FATAL: collisions detected, aborting:', file=sys.stderr)
        for c in collisions:
            print(f'  {c}', file=sys.stderr)
        return 2

    by_theme: dict[str, int] = defaultdict(int)
    for info in rename_map.values():
        by_theme[info['primary_theme']] += 1

    print(f'plan: rename {len(rename_map)} des_*.json files')
    print('per-theme:')
    for theme, count in sorted(by_theme.items(), key=lambda kv: -kv[1]):
        print(f'  {theme:12s}  {count:5d}')

    sample = list(rename_map.items())[:5]
    print('\nfirst 5 mappings (sample):')
    for old, info in sample:
        print(f'  {old}')
        print(f'    → {info["new_filename"]}  (was name={info["original_name"]!r})')

    if args.dry_run:
        print('\n[dry-run] no files written.')
        return 0

    print('\napplying...')
    n = apply_renames(VAULT_DIR, rename_map)

    map_payload = {
        old: info for old, info in sorted(rename_map.items())
    }
    with open(MAP_OUT, 'w') as f:
        json.dump(map_payload, f, indent=2)
    print(f'renamed {n} files; wrote audit trail to {MAP_OUT}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
