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

# DCSS source has SEPARATE pre-aligned paperdoll sprites under
# rltiles/player/{hand1, hand2, body, head, boots} — different files
# from the inventory tiles (rltiles/item/...). Each is hand-drawn with
# the grip/anchor at the figure's hand/head/etc position.
#
# Mirrors DCSS tilepick-p.cc:_tileidx_player_weapon — per-base-type
# lookup of inventory_subtype → paperdoll_tile_name. We map each of our
# base_types to the appropriate DCSS pre-aligned sprite. Same paperdoll
# tile is reused across all items of a base_type (every dagger looks
# the same when held); this matches DCSS's behavior.
#
# Entry: base_type → (dcss_subdir, dcss_filename). Subdirs are relative
# to dcss-source/crawl-ref/source/rltiles/player/.
PAPERDOLL_BY_BASE_TYPE = {
    # --- Weapons → player/hand1/ ---
    "dagger":      ("hand1", "dagger_slant.png"),
    "knife":       ("hand1", "knife.png"),
    "quick_blade": ("hand1", "dagger.png"),  # DCSS WPN_QUICK_BLADE → DAGGER tile
    "short_sword": ("hand1", "short_sword_slant.png"),
    "rapier":      ("hand1", "rapier.png"),
    "sabre":       ("hand1", "falchion.png"),  # similar curve, no dedicated DCSS tile
    "falchion":    ("hand1", "falchion.png"),
    "long_sword":  ("hand1", "long_sword_slant.png"),
    "scimitar":    ("hand1", "scimitar.png"),
    "katana":      ("hand1", "katana_slant.png"),
    "demon_blade": ("hand1", "demonblade.png"),  # DCSS canonical (per tilepick-p.cc)

    # --- Shields → player/hand2/ ---
    "buckler":      ("hand2", "buckler_round.png"),
    "round_shield": ("hand2", "buckler_round.png"),  # same fallback
    "kite_shield":  ("hand2", "kite_shield_kite2.png"),
    # tower_shield_gold is drawn sideways in DCSS (horizontal tear-drop). Use
    # the long_red variant which is properly upright.
    "tower_shield": ("hand2", "tower_shield_long_red.png"),

    # --- Body armor → player/body/ ---
    # We deviate from DCSS canonical (tilepick-p.cc) body mappings here
    # because DCSS uses many full-figure body sprites (leather_armour,
    # ringmail, troll_leather, dragonarm_*) — they expect the body to
    # REPLACE the base figure. We keep the spriggan base visible and
    # layer overlays, so we need TORSO-ONLY body sprites.
    #
    # Each entry below visually verified torso-only — no head, arms, or
    # legs in the sprite.
    "robe":          ("body", "robe_black_gold.png"),
    "leather":       ("body", "jacket2.png"),
    "studded":       ("body", "jacket_stud.png"),
    "ring_mail":     ("body", "chainmail.png"),
    "scale_mail":    ("body", "scalemail.png"),
    "chain_mail":    ("body", "chainmail.png"),
    "splint_mail":   ("body", "half_plate.png"),
    "banded_mail":   ("body", "half_plate.png"),
    "plate":         ("body", "bplate_metal1.png"),
    "crystal_plate": ("body", "half_plate2.png"),
    "troll_leather": ("body", "deep_troll_leather.png"),
    "dragon_scales": ("body", "shoulder_pad.png"),

    # --- Helms → player/head/ ---
    "skullcap":   ("head", "cap_black1.png"),
    "cap":        ("head", "cap_blue.png"),
    "hood":       ("head", "hood_assassin.png"),
    "wizard_hat": ("head", "cone_blue.png"),  # pointy mage hat
    "helmet":     ("head", "fhelm_gray3.png"),
    "great_helm": ("head", "fhelm_horn2.png"),
    "crown":      ("head", "crown_gold1.png"),

    # --- Boots → player/boots/ ---
    "sandals":       ("boots", "slippers.png"),
    "shoes":         ("boots", "short_brown.png"),
    "leather_boots": ("boots", "middle_brown.png"),
    "iron_boots":    ("boots", "long_white.png"),
    "greaves":       ("boots", "long_white.png"),
    "treads":        ("boots", "seven_league_boots.png"),
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

# Bespoke paperdoll art for named uniques. Mirrors DCSS's
# unrandart_to_doll_tile() (artefact-prop.cc) — each unrand has a
# hand-drawn sprite under rltiles/player/<slot>/artefact/. Path is
# relative to dcss-source/.../rltiles/player/.
#
# In DCSS only weapons (hand1/artefact/) ship with significant unrand
# art; non-weapon uniques mostly fall through to the magical-variant or
# base sprite. We only list items here where DCSS actually has a sprite.
UNIQUE_PAPERDOLL_OVERRIDES = {
    "singing_sword":       "hand1/artefact/singing_sword.png",
    "chilly_death":        "hand1/artefact/chilly_death.png",
    "firestarter":         "hand1/artefact/firestarter.png",
    "bloodbane":           "hand1/artefact/bloodbane.png",
    "wyrmbane":            "hand1/artefact/wyrmbane.png",
    "gyre":                "hand1/artefact/gyre.png",
    "doom_knight_blade":   "hand1/artefact/dread_knight.png",
    "knife_of_accuracy":   "hand1/artefact/knife_of_accuracy.png",
    "spriggans_knife":     "hand1/artefact/spriggans_knife.png",
    "vampires_tooth":      "hand1/artefact/vampires_tooth.png",
    "arc_blade":           "hand1/artefact/arc_blade.png",
    "eos":                 "hand1/artefact/eos.png",
    "sword_of_power":      "hand1/artefact/sword_of_power.png",
    "sword_of_zonguldrok": "hand1/artefact/zonguldrok.png",
    "majin_bo":            "hand1/artefact/majin.png",
}

# Rarities that get the DCSS "magical" variant sprite (filename2.png).
# Maps to DCSS enchant_to_int (tilepick.cc:4960): mundane=0 → base,
# shiny/runed/glowing=1 → ENCHANTED variant. We collapse all three
# enchant flavors to the single magical sprite (DCSS does too — only
# one ENCHANTED variant per weapon family).
MAGICAL_RARITIES = {"rare", "epic", "legendary"}


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


def _resolve_paperdoll_src(it, sub, inventory_src, dcss_player_root):
    """Pick the best DCSS paperdoll sprite for `it`.

    Priority (mirrors DCSS tilepick-p.cc):
      1. Per-id override in UNIQUE_PAPERDOLL_OVERRIDES (named unrand —
         e.g. bloodbane, wyrmbane). DCSS unrandart_to_doll_tile().
      2. Magical-variant sprite for rare/epic/legendary non-uniques —
         DCSS's enchanted weapon tile (filename2.png). Only triggers
         when both the base mapping AND a `<base>2.png` sibling exist.
      3. Base sprite from PAPERDOLL_BY_BASE_TYPE (mundane).
      4. Inventory sprite as last resort (visible but misaligned).

    Returns an absolute Path. Falls through to `inventory_src` if no
    DCSS hand-aligned art exists for this item.
    """
    item_id = it.get("id", "")
    base_type = it.get("base_type", "")
    rarity = it.get("rarity", "common")

    # 1. Bespoke unique override.
    override = UNIQUE_PAPERDOLL_OVERRIDES.get(item_id)
    if override:
        candidate = dcss_player_root / override
        if candidate.exists():
            return candidate

    # 2-3. Base-type mapping.
    base_entry = PAPERDOLL_BY_BASE_TYPE.get(base_type)
    if base_entry is None:
        return inventory_src
    dcss_subdir, dcss_filename = base_entry
    base_path = dcss_player_root / dcss_subdir / dcss_filename

    # 2. Magical variant (filename2.png) for rare+ non-uniques.
    if rarity in MAGICAL_RARITIES and not it.get("unique"):
        stem, _, ext = dcss_filename.rpartition(".")
        variant_path = dcss_player_root / dcss_subdir / f"{stem}2.{ext}"
        if variant_path.exists():
            return variant_path

    # 3. Mundane base.
    if base_path.exists():
        return base_path

    # 4. Last resort.
    return inventory_src


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
    # DCSS paperdoll source root for the per-base-type lookup.
    DCSS_RLTILES_PLAYER = REPO_ROOT / "dcss-source" / "crawl-ref" / "source" / "rltiles" / "player"
    for it, slot, tile in raw:
        stem = stem_for(tile)
        src = find_source(tile)
        if src is None:
            print(f"  MISSING SPRITE: {it['id']} <- {tile}", file=sys.stderr)
            continue
        # Inventory/loot icon copy — comes from the DCSS item/ tree
        # (where the standalone, non-figure-aligned art lives).
        copy_plan.append((src, ASSETS_ITEMS / stem, "items"))
        # Paperdoll overlay copy. Two paths:
        #   A. Item's base_type has a DCSS paperdoll-tree mapping
        #      (PAPERDOLL_BY_BASE_TYPE) — pull the pre-aligned sprite.
        #      Multiple items of same base_type share the paperdoll
        #      file (every dagger looks the same when held). Mirrors
        #      DCSS tilepick-p.cc behavior.
        #   B. Fallback: copy the inventory tile (ugly but at least
        #      visible — used to be the only path).
        sub = PAPERDOLL_DIRS.get(slot)
        if sub:
            paperdoll_src = _resolve_paperdoll_src(it, sub, src,
                                                    DCSS_RLTILES_PLAYER)
            copy_plan.append((paperdoll_src, ASSETS_PLAYER / sub / stem,
                              f"player/{sub}"))

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
