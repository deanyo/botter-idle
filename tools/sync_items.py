#!/usr/bin/env python3
"""sync_items.py — Merge item manifests into project/data/items.json + copy sprites.

Two modes:

    python3 tools/sync_items.py
        Full sync. Reads all 7 tools/items_*_manifest.json files, merges them
        into project/data/items.json, copies referenced sprites from the DCSS
        tile pack into project/assets/tiles/items/ and (for slots with a
        paperdoll layer) project/assets/tiles/player/<slot>/.

    python3 tools/sync_items.py path/to/items_<slot>.json
        Partial sync. Same as full, but only the items in the given file
        (typically an editor export). Other slots are left untouched.

Item IDs are the merge key. If an item with the same id already exists in
items.json, it's replaced. Non-manifest items (legacy, manually-added) are
preserved.

Tile path rewriting:
    DCSS-shaped tile path  →  flat stem
    "item/weapon/dagger_3.png"  →  "dagger_3.png"

Sprite copying:
    For each item, the source PNG is copied to:
      1. project/assets/tiles/items/<stem>.png        (inventory + loot icon)
      2. project/assets/tiles/player/<slot-dir>/<stem>.png  (paperdoll overlay)
    Skipped if the destination already exists with the same content.

Run from the repo root.
"""

import argparse
import hashlib
import json
import os
import shutil
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
TOOLS = REPO_ROOT / "tools"
DCSS_FULL = REPO_ROOT / "dcss" / "Dungeon Crawl Stone Soup Full"
DCSS_SUP  = REPO_ROOT / "dcss" / "Dungeon Crawl Stone Soup Supplemental"
ITEMS_JSON = REPO_ROOT / "project" / "data" / "items.json"
ASSETS_ITEMS = REPO_ROOT / "project" / "assets" / "tiles" / "items"
ASSETS_PLAYER = REPO_ROOT / "project" / "assets" / "tiles" / "player"

# Maps slot id → paperdoll subdir (mirrors paperdoll_renderer.gd SLOT_DIRS).
# Slots not in this map (ring, amulet) skip the paperdoll copy.
PAPERDOLL_DIRS = {
    "weapon": "weapons",
    "armor":  "body",
    "helm":   "helm",
    "shield": "shield",
    "boots":  "boots",
}

ALL_MANIFESTS = [
    "items_manifest.json",          # 1H swords
    "items_helms_manifest.json",
    "items_armor_manifest.json",
    "items_shields_manifest.json",
    "items_boots_manifest.json",
    "items_rings_manifest.json",
    "items_amulets_manifest.json",
]


def stem_for(tile_path):
    """Flatten a DCSS-shaped tile path to a project-relative stem.

    >>> stem_for("item/weapon/dagger_3.png")
    'dagger_3.png'
    >>> stem_for("item/armor/artefact/urand_pondering_new.png")
    'urand_pondering_new.png'
    """
    return tile_path.split("/")[-1]


def find_source(tile_path):
    """Resolve a manifest tile path to an absolute source PNG.

    Tries 'Dungeon Crawl Stone Soup Full' first, then 'Supplemental'.
    Returns None if neither exists.
    """
    for root in (DCSS_FULL, DCSS_SUP):
        p = root / tile_path
        if p.exists() and p.stat().st_size > 200:
            return p
    return None


def md5(path):
    h = hashlib.md5()
    with open(path, "rb") as f:
        h.update(f.read())
    return h.hexdigest()


def copy_if_changed(src, dst):
    """Copy src → dst unless dst already has identical content. Returns True on copy."""
    dst.parent.mkdir(parents=True, exist_ok=True)
    if dst.exists() and md5(src) == md5(dst):
        return False
    shutil.copyfile(src, dst)
    return True


def normalize_item(it, slot_default):
    """Strip manifest-only fields, rewrite tile to flat stem."""
    out = {
        "id":           it["id"],
        "name":         it["name"],
        "slot":         it.get("slot", slot_default),
        "rarity":       it["rarity"],
        "tile":         stem_for(it["tile"]),
        "atk":          int(it.get("atk", 0)),
        "def":          int(it.get("def", 0)),
        "hp":           int(it.get("hp", 0)),
        # New fields — runtime ignores unknown keys via .get() defaults.
        "item_tier":    int(it.get("item_tier", 1)),
        "base_type":    it.get("base_type", ""),
        "flavor_tags":  list(it.get("flavor_tags", [])),
        "lore":         it.get("lore", ""),
        "drop_weights": list(it.get("drop_weights", [0, 0, 0, 0, 0])),
        "unique":       bool(it.get("unique", False)),
    }
    if "future_mechanic" in it:
        out["future_mechanic"] = it["future_mechanic"]
    return out


def collect_manifest_items(paths):
    """Load each manifest file, return list of (item, slot, source_tile_path)."""
    out = []
    for path in paths:
        with open(path) as f:
            data = json.load(f)
        # Manifest format: items[]. Editor export format: items_<slot>[] (single key).
        items_key = "items"
        if items_key not in data:
            for k in data:
                if k.startswith("items_") and isinstance(data[k], list):
                    items_key = k
                    break
        slot_default = data.get("slot", "")
        if not slot_default and "_slot" in data:
            slot_default = data["_slot"]
        for it in data.get(items_key, []):
            out.append((it, it.get("slot", slot_default), it["tile"]))
    return out


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("file", nargs="?", default=None,
                        help="Optional single manifest/export file. If omitted, all 7 manifests are synced.")
    parser.add_argument("--dry-run", action="store_true",
                        help="Report intended changes without writing.")
    parser.add_argument("--prune-legacy", action="store_true",
                        help="Remove items.json entries that lack base_type (legacy pre-manifest items). "
                             "Use with caution — only when running a full sync of all 7 manifests.")
    args = parser.parse_args()

    if args.file:
        paths = [Path(args.file).resolve()]
        if not paths[0].exists():
            print(f"file not found: {paths[0]}", file=sys.stderr)
            return 1
    else:
        paths = [TOOLS / name for name in ALL_MANIFESTS]
        missing = [p for p in paths if not p.exists()]
        if missing:
            print("missing manifests:", *missing, file=sys.stderr)
            return 1

    raw = collect_manifest_items(paths)
    print(f"loaded {len(raw)} items from {len(paths)} file(s)")

    # Detect stem collisions ACROSS slots — same flat filename but different
    # source paths. Within a slot it's fine (sprite is shared by design).
    stem_owners = {}  # stem → (slot, source_path)
    collisions = []
    for it, slot, tile in raw:
        stem = stem_for(tile)
        key = (stem, slot)
        existing = stem_owners.get(stem)
        if existing and existing != (slot, tile):
            collisions.append((stem, existing, (slot, tile)))
        else:
            stem_owners[stem] = (slot, tile)
    if collisions:
        print("\nWARN: stem collisions (same filename, different source path or slot):")
        for stem, a, b in collisions:
            print(f"  {stem}: {a}  vs  {b}")

    # Plan sprite copies.
    copy_plan = []  # [(src, dst, reason)]
    for it, slot, tile in raw:
        stem = stem_for(tile)
        src = find_source(tile)
        if src is None:
            print(f"  MISSING SPRITE: {it['id']} <- {tile}", file=sys.stderr)
            continue
        # Inventory/loot icon copy.
        copy_plan.append((src, ASSETS_ITEMS / stem, "items"))
        # Paperdoll overlay copy (only for slots with a body layer).
        sub = PAPERDOLL_DIRS.get(slot)
        if sub:
            copy_plan.append((src, ASSETS_PLAYER / sub / stem, f"player/{sub}"))

    # Dedup by destination (multiple items can reference the same sprite).
    seen = set()
    deduped = []
    for src, dst, reason in copy_plan:
        if dst in seen:
            continue
        seen.add(dst)
        deduped.append((src, dst, reason))
    copy_plan = deduped

    # Execute sprite copies.
    copied = 0
    skipped = 0
    for src, dst, reason in copy_plan:
        if args.dry_run:
            print(f"  [dry] copy {src.name} → {dst.relative_to(REPO_ROOT)}")
            continue
        if copy_if_changed(src, dst):
            copied += 1
        else:
            skipped += 1
    print(f"sprites: {copied} copied, {skipped} unchanged ({len(copy_plan)} total destinations)")

    # Merge into items.json.
    if not ITEMS_JSON.exists():
        existing = {"items": []}
    else:
        with open(ITEMS_JSON) as f:
            existing = json.load(f)
    by_id = {it["id"]: it for it in existing.get("items", [])}
    inserted = 0
    updated = 0
    for it, slot, tile in raw:
        norm = normalize_item(it, slot)
        if norm["id"] in by_id:
            updated += 1
        else:
            inserted += 1
        by_id[norm["id"]] = norm

    pruned_ids = []
    if args.prune_legacy and not args.file:
        # Drop items that lack base_type — those are pre-manifest entries.
        # Refuse pruning during a partial sync (--file) to avoid blowing away
        # untouched slots whose manifests weren't loaded.
        for k in list(by_id.keys()):
            if not by_id[k].get("base_type"):
                pruned_ids.append(k)
                del by_id[k]
    elif args.prune_legacy:
        print("--prune-legacy ignored: only allowed during full sync (no FILE arg)")

    # Re-emit. Sort by slot then item_tier then id to keep diffs small as you iterate.
    SLOT_ORDER = ["weapon", "armor", "helm", "shield", "boots", "ring", "amulet"]
    def sort_key(it):
        try:
            si = SLOT_ORDER.index(it.get("slot", ""))
        except ValueError:
            si = 99
        return (si, int(it.get("item_tier", 0)), it["id"])
    merged_items = sorted(by_id.values(), key=sort_key)
    new_doc = dict(existing)
    new_doc["items"] = merged_items

    if args.dry_run:
        print(f"[dry] would write {len(merged_items)} items to {ITEMS_JSON.relative_to(REPO_ROOT)}")
        print(f"[dry] inserted={inserted} updated={updated}", end="")
        if pruned_ids:
            print(f" pruned={len(pruned_ids)}", end="")
        print()
    else:
        with open(ITEMS_JSON, "w") as f:
            json.dump(new_doc, f, indent=2)
            f.write("\n")
        msg = f"items.json: wrote {len(merged_items)} items ({inserted} new, {updated} updated"
        if pruned_ids:
            msg += f", {len(pruned_ids)} legacy pruned"
        print(msg + ")")
        if pruned_ids:
            print("  pruned:", ", ".join(pruned_ids[:8]) + (" ..." if len(pruned_ids) > 8 else ""))

    # Orphan check: items.json entries whose tile sprite isn't on disk.
    orphans = []
    for it in merged_items:
        stem = it.get("tile", "")
        if not stem:
            continue
        if not (ASSETS_ITEMS / stem).exists():
            orphans.append(it["id"])
    if orphans:
        print(f"\nWARN: {len(orphans)} items reference sprites missing from "
              f"project/assets/tiles/items/:")
        for oid in orphans[:10]:
            print(f"  {oid}")
        if len(orphans) > 10:
            print(f"  ... and {len(orphans) - 10} more")

    return 0


if __name__ == "__main__":
    sys.exit(main())
