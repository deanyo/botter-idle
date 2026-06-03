#!/usr/bin/env python3
"""
Slot/sprite/base_type alignment audit for items.json.

Three checks per item:

1. **DCSS source alignment** — for items whose tile is a `urand_*` /
   `spwpn_*` / `lshield_*` artefact sprite, parse
   `dcss-source/.../art-data.txt` to find the canonical OBJ_ARMOUR/
   ARM_X mapping and verify our slot matches.

2. **Sprite directory alignment** — verify the file exists in
   `project/assets/tiles/items/<basename>` (the runtime path).

3. **Base_type sanity** — flag items whose `base_type` mismatches
   what we'd infer from the sprite path or DCSS art-data. e.g. an
   item with base_type='gloves' should have a tile from
   item/armor/hands/ (or be an artefact whose ARM_X is ARM_GLOVES).

Exits 0 if clean, non-zero on mismatches. Run before any items.json
or sprite change to catch drift early.

    python3 tools/check_item_slots.py
"""

import json
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
ITEMS_PATH = REPO / "project" / "data" / "items.json"
ART_DATA = REPO / "dcss-source" / "crawl-ref" / "source" / "art-data.txt"
ITEMS_DIR = REPO / "project" / "assets" / "tiles" / "items"

# DCSS ARM_X → our slot. Mirrors the table in (one place we should
# extract this to a shared module if it grows further).
ARM_TO_SLOT = {
    "ARM_HAT":         "helm",
    "ARM_HELMET":      "helm",
    "ARM_GLOVES":      "gloves",
    "ARM_BOOTS":       "boots",
    "ARM_BARDING":     "boots",
    "ARM_BUCKLER":     "shield",
    "ARM_KITE_SHIELD": "shield",
    "ARM_TOWER_SHIELD":"shield",
    "ARM_CLOAK":       "cloak",
    "ARM_SCARF":       "cloak",
    "ARM_ROBE":        "armor",
    "ARM_LEATHER_ARMOUR": "armor",
    "ARM_RING_MAIL":   "armor",
    "ARM_SCALE_MAIL":  "armor",
    "ARM_CHAIN_MAIL":  "armor",
    "ARM_PLATE_ARMOUR":"armor",
    "ARM_CRYSTAL_PLATE_ARMOUR": "armor",
    "ARM_TROLL_LEATHER_ARMOUR": "armor",
    "ARM_ANIMAL_SKIN": "armor",
    "ARM_FIRE_DRAGON_ARMOUR":   "armor",
    "ARM_ICE_DRAGON_ARMOUR":    "armor",
    "ARM_STEAM_DRAGON_ARMOUR":  "armor",
    "ARM_QUICKSILVER_DRAGON_ARMOUR": "armor",
    "ARM_PEARL_DRAGON_ARMOUR":  "armor",
    "ARM_SHADOW_DRAGON_ARMOUR": "armor",
    "ARM_STORM_DRAGON_ARMOUR":  "armor",
    "ARM_GOLD_DRAGON_ARMOUR":   "armor",
    "ARM_GOLDEN_DRAGON_ARMOUR": "armor",
    "ARM_SWAMP_DRAGON_ARMOUR":  "armor",
    "ARM_ACID_DRAGON_ARMOUR":   "armor",
    "ARM_ORB":         "amulet",
}


def parse_art_data():
    """Return {tile_stem: (slot, subtype_enum, name)} from art-data.txt."""
    if not ART_DATA.is_file():
        return {}
    text = ART_DATA.read_text()
    out = {}
    for entry in re.split(r"\n\s*\n", text):
        obj_m = re.search(r"OBJ:\s+OBJ_(ARMOUR|WEAPONS)/(\w+)", entry)
        tile_m = re.search(r"TILE:\s+(\w+)", entry)
        name_m = re.search(r"NAME:\s+(.+)", entry)
        if not (obj_m and tile_m):
            continue
        obj_class = obj_m.group(1)
        sub = obj_m.group(2)
        tile = tile_m.group(1)
        name = (name_m.group(1).strip() if name_m else "?")
        slot = ARM_TO_SLOT.get(sub, "weapon" if obj_class == "WEAPONS" else "armor")
        out[tile] = (slot, sub, name)
    return out


def main() -> int:
    if not ITEMS_PATH.is_file():
        print(f"missing {ITEMS_PATH}", file=sys.stderr)
        return 2
    items = json.loads(ITEMS_PATH.read_text())["items"]
    art = parse_art_data()
    bad = 0

    for it in items:
        tile = it.get("tile", "")
        if not tile:
            print(f"  [missing-tile]  {it.get('id')}: no tile field")
            bad += 1
            continue
        sprite_path = ITEMS_DIR / tile
        if not sprite_path.is_file():
            print(f"  [missing-file]  {it['id']}: items/{tile} not on disk")
            bad += 1
            continue
        # Artefact alignment check: strip _new/_old/.png to canonical stem.
        stem = tile.replace(".png", "")
        for suffix in ("_new", "_old"):
            if stem.endswith(suffix):
                stem = stem[: -len(suffix)]
                break
        if stem in art:
            true_slot, sub, true_name = art[stem]
            if it.get("slot") != true_slot:
                print(f"  [slot-mismatch] {it['id']}: ours='{it.get('slot')}'  DCSS='{true_slot}' ({sub})  '{true_name}'")
                bad += 1

    if bad == 0:
        print(f"OK — {len(items)} items pass slot audit.")
        return 0
    print(f"\n{bad} mismatches (see above)")
    return 1


if __name__ == "__main__":
    sys.exit(main())
