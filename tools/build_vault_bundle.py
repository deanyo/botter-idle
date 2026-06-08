#!/usr/bin/env python3
"""Bundle all vault JSONs into a single file.

VaultLibrary previously opened 1335 individual JSON files on first load.
On HTML5 each FileAccess.open is significantly slower than desktop, so
the cumulative dungeon-entry hitch was multiple seconds. Reading one
bundle file is ~1000x faster.

The bundle is shaped as:

    {"name1": {...vault...}, "name2": {...vault...}, ...}

VaultLibrary reads the bundle on first call and falls back to the
old per-file path if the bundle is missing.

Run from repo root:
    python3 tools/build_vault_bundle.py

Re-run any time vaults are added / regenerated.
"""
import json
import os
import sys

REPO_ROOT = os.path.dirname(os.path.abspath(os.path.dirname(__file__)))
VAULT_DIR = os.path.join(REPO_ROOT, 'project', 'data', 'vaults')
OUT_PATH = os.path.join(REPO_ROOT, 'project', 'data', 'vaults_bundle.json')

bundle = {}
file_count = 0
for fname in sorted(os.listdir(VAULT_DIR)):
    if not fname.endswith('.json'):
        continue
    full = os.path.join(VAULT_DIR, fname)
    with open(full) as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError as e:
            print(f"  SKIP malformed: {fname}: {e}", file=sys.stderr)
            continue
    # Use the filename (sans .json) as the key — preserves uniqueness
    # even if vault names collide (they shouldn't, but defensive).
    key = fname[:-5]
    bundle[key] = data
    file_count += 1

with open(OUT_PATH, 'w') as f:
    json.dump(bundle, f, separators=(',', ':'))

size_mb = os.path.getsize(OUT_PATH) / (1024 * 1024)
print(f"Bundled {file_count} vaults into {OUT_PATH} ({size_mb:.1f} MB)")
