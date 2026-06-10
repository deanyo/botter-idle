#!/usr/bin/env python3
"""Build the directory manifest read by biome_data, vault_library,
and artefact_pool when they need to enumerate res:// directories.

HTML5 / web exports can't enumerate res:// directories via DirAccess
because the FS is virtualized inside the .pck. We pre-build a listing
at design time and load it via FileAccess (which IS supported in web).

Run from the repo root:
    python3 tools/build_tile_dir_manifest.py

Run after adding/removing files in any of the listed dirs. The
output is checked in (project/data/tile_dir_manifest.json) so the
HTML5 export ships with the right list.
"""
import json
import os
import sys

REPO_ROOT = os.path.dirname(os.path.abspath(os.path.dirname(__file__)))
PROJECT_ROOT = os.path.join(REPO_ROOT, 'project')

# (path, extension) — directories to enumerate + the file extension to
# include. Add new entries when scripts add new enumerate-at-runtime
# code.
#
# data/vaults/ is intentionally NOT listed: the 1320 ported DCSS vault
# filenames carry contributor handles (des_<author>_*.json) and the
# vault contents are GPLv2+. The web .pck excludes both vaults/*.json
# and vaults_bundle.json (export_presets.cfg), so web has no vaults
# regardless of this manifest. Desktop loads vaults via the DirAccess
# fallback in vault_library.gd::_list_vault_files. Re-add only if the
# vault corpus is replaced with original content.
DIRS = [
    ('assets/tiles/floor',           '.png'),
    ('assets/tiles/wall',            '.png'),
    ('assets/tiles/overlays',        '.png'),
    ('assets/tiles/sigils',          '.png'),
    # Full items + paperdoll trees so the item editor picker can
    # filter to actually-shipped sprites. The picker previously
    # listed every DCSS atlas entry, which let authors pick a tile
    # that wasn't copied into project/assets/tiles/items/ — runtime
    # resolved to a missing file → blank icon.
    ('assets/tiles/items',           '.png'),
    ('assets/tiles/items/artefacts', '.png'),
    ('assets/tiles/items/spells',    '.png'),
    ('assets/tiles/player/weapons',  '.png'),
    ('assets/tiles/player/body',     '.png'),
    ('assets/tiles/player/helm',     '.png'),
    ('assets/tiles/player/shield',   '.png'),
    ('assets/tiles/player/boots',    '.png'),
    ('assets/tiles/player/gloves',   '.png'),
    ('assets/tiles/player/cloak',    '.png'),
]

manifest = {}
for d, ext in DIRS:
    full = os.path.join(PROJECT_ROOT, d)
    files = []
    if os.path.isdir(full):
        for f in sorted(os.listdir(full)):
            if f.endswith(ext):
                files.append(f)
    manifest[f"res://{d}/"] = files
    print(f"  {d}: {len(files)} files")

out_path = os.path.join(PROJECT_ROOT, 'data', 'tile_dir_manifest.json')
os.makedirs(os.path.dirname(out_path), exist_ok=True)
with open(out_path, 'w') as f:
    json.dump(manifest, f, indent=2)
print(f"\nWrote {out_path}")
