#!/usr/bin/env python3
"""
Item-overhaul v2 migration.

Rewrites project/data/items.json (and per-slot tools/items_*_manifest.json)
from the old schema (atk/def/hp baseline) to the new VS-shape schema:

    Weapons    → damage_min, damage_max, damage_type, speed, weapon_class
    Body slots → armor, evasion
    Jewelry    → no baseline
    Spells     → damage_min, damage_max, damage_type (already mostly shaped)
    Uniques    → preserved name+sprite+lore, regenerated stats per schema,
                 hand-curated implicit_affixes per known unique

Backups go to *.legacy alongside the originals so the migration is
non-destructive. Run once; commit the result.

Usage: python3 tools/migrate_items_v2.py
"""

import json
import pathlib
import shutil
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
ITEMS_PATH = ROOT / "project" / "data" / "items.json"
TOOLS = ROOT / "tools"

# Per-weapon-class baseline at common, T1, item_tier=1.
# (damage_min, damage_max, speed_seconds_per_swing).
WEAPON_BASE = {
    "dagger":          (4,  8,  0.5),
    "knife":           (4,  8,  0.5),
    "shiv":            (4,  8,  0.5),
    "short_sword":     (8,  15, 0.6),
    "long_sword":      (12, 22, 0.7),
    "broad_sword":     (12, 22, 0.7),
    "scimitar":        (10, 20, 0.6),
    "falchion":        (12, 22, 0.65),
    "rapier":          (8,  18, 0.55),
    "sabre":           (10, 20, 0.6),
    "greatsword":      (22, 40, 1.0),
    "claymore":        (24, 42, 1.05),
    "double_sword":    (28, 50, 1.05),
    "triple_sword":    (32, 56, 1.10),
    "hand_axe":        (10, 20, 0.65),
    "war_axe":         (14, 26, 0.75),
    "battle_axe":      (28, 50, 1.10),
    "broad_axe":       (30, 52, 1.15),
    "executioner_axe": (34, 58, 1.20),
    "club":            (10, 18, 0.7),
    "mace":            (14, 24, 0.8),
    "morningstar":     (16, 28, 0.85),
    "flail":           (14, 26, 0.8),
    "great_mace":      (30, 55, 1.15),
    "dire_flail":      (28, 50, 1.10),
    "giant_club":      (32, 56, 1.20),
    "eveningstar":     (24, 42, 1.0),
    "spear":           (12, 22, 0.7),
    "trident":         (16, 28, 0.85),
    "halberd":         (24, 44, 0.95),
    "bardiche":        (28, 50, 1.05),
    "scythe":          (26, 48, 1.0),
    "glaive":          (22, 40, 0.9),
    "bow":             (14, 28, 0.7),
    "longbow":         (16, 32, 0.75),
    "crossbow":        (20, 36, 0.95),
    "wand":            (8,  18, 0.5),
    "staff":           (18, 32, 0.85),
    "quarterstaff":    (16, 28, 0.8),
    "lajatang":        (24, 42, 0.95),
    "whip":            (10, 20, 0.65),
    "demon_whip":      (20, 36, 0.85),
    "demon_blade":     (24, 42, 0.9),
    "demon_trident":   (22, 38, 0.85),
}

# 2H weapon classes — used to set weapon_class field. Mirrors
# Bot.TWO_HANDED_BASE_TYPES.
TWO_HANDED = {
    "battle_axe", "broad_axe", "executioner_axe",
    "halberd", "bardiche", "scythe",
    "greatsword", "claymore", "double_sword", "triple_sword",
    "giant_club", "dire_flail",
    "quarterstaff", "lajatang",
}

# Body-slot baselines: (armor, evasion) at common rarity, T1.
# Cloaks favor evasion over armor (PoE pattern). Jewelry zero baseline.
BODY_BASE = {
    "armor":  (8,  2),
    "helm":   (4,  3),
    "boots":  (3,  4),
    "gloves": (2,  3),
    "cloak":  (1,  6),
    "shield": (6,  2),
}

# Rarity stat multipliers — applied to weapon damage range, weapon speed,
# armor + evasion. Mild because we don't want pre-affix legendaries
# trivially better than common-with-affixes (PoE pattern).
RARITY_MULT = {
    "common":    1.00,
    "uncommon":  1.10,
    "rare":      1.22,
    "epic":      1.36,
    "legendary": 1.55,
}
# item_tier 1..5 multiplier. Stacks on top of rarity. Keeps the number
# ceiling smooth — a legendary T5 weapon = 1.55 × 1.40^4 ≈ 5.95× a
# common T1.
TIER_MULT = lambda t: 1.0 if t <= 1 else (1.40 ** (t - 1))

# Element keywords in item names → damage_type override on weapons.
# Stays minimal and explicit so misnamed items don't get auto-themed.
ELEMENT_NAME_HINTS = {
    "lightning": "lightning",
    "thunder":   "lightning",
    "storm":     "lightning",
    "fire":      "fire",
    "flame":     "fire",
    "ember":     "fire",
    "blaze":     "fire",
    "ash":       "fire",
    "frost":     "cold",
    "ice":       "cold",
    "freezing":  "cold",
    "cold":      "cold",
    "winter":    "cold",
    "holy":      "holy",
    "sacred":    "holy",
    "blessed":   "holy",
    "divine":    "holy",
    "venom":     "poison",
    "poison":    "poison",
    "toxic":     "poison",
    "shadow":    "dark",
    "dark":      "dark",
    "void":      "dark",
    "demon":     "dark",  # demon_blade / demon_whip default to dark — overridable
    "hellfire":  "fire",
}

# Hand-curated implicit_affixes for known uniques. The migration looks up
# the unique by id; entries listed here get their implicits stamped on.
# Keep flag-style affixes only — these are item-defining bonuses, not
# rolled values.
UNIQUE_IMPLICITS = {
    "vampires_tooth":          ["of_lifesteal"],
    "demonic_blade":           ["of_embers"],
    "demon_blade":             ["of_embers"],
    "spwpn_singing_sword":     ["of_storms"],
    "spwpn_majin":             ["of_shadows"],
    "spwpn_sword_of_power":    ["of_might"],
    "spwpn_sword_of_zonguldrok":["of_shadows"],
    "spwpn_sword_of_power_new":["of_might"],
    "spwpn_sword_of_zonguldrok_new":["of_shadows"],
    "elven_short_sword":       ["of_finesse"],
    "elven_broadsword":        ["of_finesse"],
    "ancient_sword":           ["of_might"],
    "icy_blade":               ["of_frost"],
}

# 5 NEW unique spell tomes (one per archetype) — each carries the
# corresponding archetype affix. The IDs are appended to items.json.
ARCHETYPE_UNIQUE_SPELLS = [
    {
        "id": "spell_axes_bleeding", "name": "Reaver's Edge",
        "base_type": "spell_axes", "primary_stat": "str",
        "tile": "spells/spell_axes.png",
        "damage_min": 14, "damage_max": 22,
        "damage_type": "physical",
        "spell_cooldown": 5.0,
        "implicit_affixes": ["bleeding_edge"],
        "lore": "Each axe weeps a thin, crimson line through the air.",
    },
    {
        "id": "spell_fireball_comet", "name": "Comet Tome",
        "base_type": "spell_fireball", "primary_stat": "int",
        "tile": "spells/spell_fireball.png",
        "damage_min": 16, "damage_max": 26,
        "damage_type": "fire",
        "spell_cooldown": 1.6,
        "implicit_affixes": ["comet_trail"],
        "lore": "Where it lands, the ground keeps burning.",
    },
    {
        "id": "spell_frost_nova_root", "name": "Frostbite Tome",
        "base_type": "spell_frost_nova", "primary_stat": "int",
        "tile": "spells/spell_frost_nova.png",
        "damage_min": 14, "damage_max": 22,
        "damage_type": "cold",
        "spell_cooldown": 4.0,
        "implicit_affixes": ["frostbite"],
        "lore": "Their feet freeze to the floor before they can flee.",
    },
    {
        "id": "spell_chain_lightning_brand", "name": "Storm Brand Tome",
        "base_type": "spell_chain_lightning", "primary_stat": "dex",
        "tile": "spells/spell_chain_lightning.png",
        "damage_min": 14, "damage_max": 22,
        "damage_type": "lightning",
        "spell_cooldown": 2.4,
        "implicit_affixes": ["storm_brand"],
        "lore": "The arc forks again and again, hungry for ground.",
    },
    {
        "id": "spell_holy_beam_radiance", "name": "Radiance Tome",
        "base_type": "spell_holy_beam", "primary_stat": "str",
        "tile": "spells/spell_holy_beam.png",
        "damage_min": 26, "damage_max": 38,
        "damage_type": "holy",
        "spell_cooldown": 4.2,
        "implicit_affixes": ["radiance"],
        "lore": "Slower to draw, but it cleanses everything in its path.",
    },
]

# Affix-pool template per slot. Migration assigns these wholesale —
# fine-tuning goes through the affix editor portal.
AFFIX_POOL_BY_SLOT = {
    "weapon": {
        "of_might": 25, "of_finesse": 15, "of_wisdom": 10,
        "of_sharpness": 30, "of_embers": 8, "of_frost": 8,
        "of_storms": 8, "of_devotion": 6, "of_venom": 6, "of_shadows": 6,
        "of_crit": 25, "of_haste": 20, "of_lifesteal": 15,
        "of_channeling": 8, "of_quickcast": 8,
    },
    "armor": {
        "of_might": 15, "of_finesse": 12, "of_wisdom": 12,
        "of_vitality": 30, "of_the_bear": 30,
        "of_fire_resist": 12, "of_cold_resist": 12,
        "of_lightning_resist": 12, "of_holy_resist": 8,
        "of_poison_resist": 10, "of_dark_resist": 8,
        "of_regen": 15,
    },
    "helm": {
        "of_might": 14, "of_finesse": 14, "of_wisdom": 18,
        "of_vitality": 18, "of_the_bear": 22, "of_the_cat": 14,
        "of_str_mastery": 8, "of_dex_mastery": 8, "of_int_mastery": 8,
        "of_quickcast": 12, "of_resonance": 12, "of_channeling": 12,
        "of_crit": 12,
    },
    "boots": {
        "of_finesse": 22, "of_might": 12, "of_wisdom": 10,
        "of_vitality": 14, "of_the_bear": 16, "of_the_cat": 26,
        "of_haste": 26, "of_regen": 10,
    },
    "gloves": {
        "of_might": 16, "of_finesse": 18, "of_wisdom": 10,
        "of_the_bear": 14, "of_the_cat": 16,
        "of_sharpness": 14, "of_embers": 10, "of_frost": 10,
        "of_storms": 10, "of_devotion": 8, "of_venom": 8, "of_shadows": 8,
        "of_crit": 18, "of_haste": 18, "of_lifesteal": 10,
        "of_channeling": 10, "of_velocity": 12,
    },
    "cloak": {
        "of_might": 10, "of_finesse": 12, "of_wisdom": 14,
        "of_vitality": 18, "of_the_bear": 12, "of_the_cat": 22,
        "of_fire_resist": 14, "of_cold_resist": 14,
        "of_lightning_resist": 14, "of_holy_resist": 8,
        "of_poison_resist": 10, "of_dark_resist": 8,
        "of_resonance": 12, "of_lingering": 14, "of_haste": 10,
        "of_regen": 8,
    },
    "shield": {
        "of_might": 16, "of_finesse": 8, "of_wisdom": 10,
        "of_vitality": 22, "of_the_bear": 30,
        "of_fire_resist": 14, "of_cold_resist": 14,
        "of_lightning_resist": 14, "of_holy_resist": 8,
        "of_poison_resist": 10, "of_dark_resist": 8,
    },
    "ring": {
        "of_might": 16, "of_finesse": 16, "of_wisdom": 16,
        "of_vitality": 14, "of_quickcast": 14, "of_resonance": 12,
        "of_lingering": 12, "of_velocity": 10, "of_multicast": 8,
        "of_channeling": 14, "of_embers": 10, "of_frost": 10,
        "of_storms": 10, "of_devotion": 8, "of_venom": 8, "of_shadows": 8,
        "of_fire_resist": 8, "of_cold_resist": 8, "of_lightning_resist": 8,
        "of_crit": 16, "of_haste": 16, "of_lifesteal": 10, "of_regen": 10,
    },
    "amulet": {
        "of_might": 16, "of_finesse": 16, "of_wisdom": 18,
        "of_vitality": 14, "of_str_mastery": 12, "of_dex_mastery": 12,
        "of_int_mastery": 14, "of_channeling": 16, "of_resonance": 14,
        "of_lingering": 12, "of_velocity": 10, "of_multicast": 8,
        "of_quickcast": 14, "of_crit": 14, "of_haste": 14,
        "of_lifesteal": 10, "of_regen": 10,
    },
    "spell": {
        "of_wisdom": 14, "of_quickcast": 22, "of_resonance": 20,
        "of_lingering": 18, "of_velocity": 12, "of_multicast": 10,
        "of_channeling": 22, "of_str_mastery": 8, "of_dex_mastery": 8,
        "of_int_mastery": 8, "of_crit": 12, "of_haste": 12,
        "of_lifesteal": 6,
    },
}


def detect_damage_type(item: dict) -> str:
    """Resolve damage_type for a weapon. Default physical; element keyword
    in id or name pulls into the matching element."""
    name_l = (item.get("name", "") + " " + item.get("id", "")).lower()
    flavor_tags = [t.lower() for t in item.get("flavor_tags", [])]
    # Flavor tag hints first (more authoritative than name keyword).
    for tag, elem in (("fire","fire"), ("cold","cold"), ("thunderous","lightning"),
                      ("holy","holy"), ("poison","poison"), ("dark","dark")):
        if tag in flavor_tags:
            return elem
    # Name keyword fallback.
    for kw, elem in ELEMENT_NAME_HINTS.items():
        if kw in name_l:
            return elem
    return "physical"


def migrate_weapon(item: dict) -> dict:
    base_type = item.get("base_type", "")
    base = WEAPON_BASE.get(base_type, (8, 14, 0.6))
    mult = RARITY_MULT.get(item.get("rarity", "common"), 1.0) * TIER_MULT(int(item.get("item_tier", 1)))
    dmg_min = int(round(base[0] * mult))
    dmg_max = int(round(base[1] * mult))
    speed   = round(base[2], 2)
    weapon_class = "2H" if base_type in TWO_HANDED else "1H"
    new_item = {
        "id": item["id"],
        "name": item.get("name", item["id"]),
        "slot": "weapon",
        "rarity": item.get("rarity", "common"),
        "tile": item.get("tile", ""),
        "base_type": base_type,
        "weapon_class": weapon_class,
        "damage_min": dmg_min,
        "damage_max": dmg_max,
        "damage_type": detect_damage_type(item),
        "speed": speed,
        "item_tier": int(item.get("item_tier", 1)),
        "flavor_tags": item.get("flavor_tags", []),
        "lore": item.get("lore", ""),
        "drop_weights": item.get("drop_weights", [80, 15, 4, 1, 0]),
        "unique": bool(item.get("unique", False)),
        "enchant_chance": float(item.get("enchant_chance", 0.05)),
        "implicit_affixes": item.get("implicit_affixes", []),
        "affix_pool": AFFIX_POOL_BY_SLOT["weapon"],
    }
    # Hand-curated unique implicits.
    if new_item["unique"] and item["id"] in UNIQUE_IMPLICITS:
        new_item["implicit_affixes"] = UNIQUE_IMPLICITS[item["id"]]
    return new_item


def migrate_body(item: dict) -> dict:
    slot = item["slot"]
    armor_b, evasion_b = BODY_BASE.get(slot, (0, 0))
    mult = RARITY_MULT.get(item.get("rarity", "common"), 1.0) * TIER_MULT(int(item.get("item_tier", 1)))
    new_item = {
        "id": item["id"],
        "name": item.get("name", item["id"]),
        "slot": slot,
        "rarity": item.get("rarity", "common"),
        "tile": item.get("tile", ""),
        "base_type": item.get("base_type", slot),
        "armor": int(round(armor_b * mult)),
        "evasion": int(round(evasion_b * mult)),
        "item_tier": int(item.get("item_tier", 1)),
        "flavor_tags": item.get("flavor_tags", []),
        "lore": item.get("lore", ""),
        "drop_weights": item.get("drop_weights", [80, 15, 4, 1, 0]),
        "unique": bool(item.get("unique", False)),
        "enchant_chance": float(item.get("enchant_chance", 0.05)),
        "implicit_affixes": item.get("implicit_affixes", []),
        "affix_pool": AFFIX_POOL_BY_SLOT.get(slot, AFFIX_POOL_BY_SLOT["armor"]),
    }
    if new_item["unique"] and item["id"] in UNIQUE_IMPLICITS:
        new_item["implicit_affixes"] = UNIQUE_IMPLICITS[item["id"]]
    return new_item


def migrate_jewelry(item: dict) -> dict:
    slot = item["slot"]
    new_item = {
        "id": item["id"],
        "name": item.get("name", item["id"]),
        "slot": slot,
        "rarity": item.get("rarity", "common"),
        "tile": item.get("tile", ""),
        "base_type": item.get("base_type", slot),
        "item_tier": int(item.get("item_tier", 1)),
        "flavor_tags": item.get("flavor_tags", []),
        "lore": item.get("lore", ""),
        "drop_weights": item.get("drop_weights", [70, 20, 7, 2, 1]),
        "unique": bool(item.get("unique", False)),
        "enchant_chance": float(item.get("enchant_chance", 0.10)),
        "implicit_affixes": item.get("implicit_affixes", []),
        "affix_pool": AFFIX_POOL_BY_SLOT.get(slot, AFFIX_POOL_BY_SLOT["ring"]),
    }
    if new_item["unique"] and item["id"] in UNIQUE_IMPLICITS:
        new_item["implicit_affixes"] = UNIQUE_IMPLICITS[item["id"]]
    return new_item


def migrate_spell(item: dict) -> dict:
    base_dmg = float(item.get("damage", 16))
    flavor_tags = [t.lower() for t in item.get("flavor_tags", [])]
    elem_map = {"fire":"fire", "cold":"cold", "thunderous":"lightning",
                "holy":"holy", "poison":"poison", "dark":"dark", "vampiric":"dark"}
    dtype = "physical"
    for tag, elem in elem_map.items():
        if tag in flavor_tags:
            dtype = elem
            break
    new_item = {
        "id": item["id"],
        "name": item.get("name", item["id"]),
        "slot": "spell",
        "rarity": item.get("rarity", "common"),
        "tile": item.get("tile", ""),
        "base_type": item.get("base_type", "spell_fireball"),
        "primary_stat": item.get("primary_stat", "int"),
        "damage_min": int(round(base_dmg * 0.85)),
        "damage_max": int(round(base_dmg * 1.15)),
        "damage_type": dtype,
        "spell_cooldown": float(item.get("spell_cooldown", 3.0)),
        "item_tier": int(item.get("item_tier", 1)),
        "flavor_tags": item.get("flavor_tags", []),
        "lore": item.get("lore", ""),
        "drop_weights": item.get("drop_weights", [60, 30, 8, 2, 0]),
        "unique": bool(item.get("unique", False)),
        "enchant_chance": float(item.get("enchant_chance", 0.10)),
        "implicit_affixes": item.get("implicit_affixes", []),
        "affix_pool": AFFIX_POOL_BY_SLOT["spell"],
    }
    if new_item["unique"] and item["id"] in UNIQUE_IMPLICITS:
        new_item["implicit_affixes"] = UNIQUE_IMPLICITS[item["id"]]
    return new_item


SLOT_DISPATCH = {
    "weapon": migrate_weapon,
    "armor":  migrate_body,
    "helm":   migrate_body,
    "boots":  migrate_body,
    "gloves": migrate_body,
    "cloak":  migrate_body,
    "shield": migrate_body,
    "ring":   migrate_jewelry,
    "amulet": migrate_jewelry,
    "spell":  migrate_spell,
}


def main():
    if not ITEMS_PATH.exists():
        print(f"items.json not found at {ITEMS_PATH}", file=sys.stderr)
        sys.exit(1)
    legacy = ITEMS_PATH.with_suffix(".json.legacy")
    shutil.copy(ITEMS_PATH, legacy)
    print(f"Backup → {legacy.name}")

    raw = json.loads(ITEMS_PATH.read_text())
    items = raw.get("items", [])
    print(f"Loaded {len(items)} items")

    migrated = []
    skipped = []
    for it in items:
        slot = it.get("slot", "")
        fn = SLOT_DISPATCH.get(slot)
        if fn is None:
            skipped.append(it.get("id", "?"))
            continue
        migrated.append(fn(it))

    # Append the 5 archetype-unique spell tomes if not already present.
    existing_ids = {it["id"] for it in migrated}
    for tome in ARCHETYPE_UNIQUE_SPELLS:
        if tome["id"] in existing_ids:
            continue
        migrated.append({
            "id": tome["id"],
            "name": tome["name"],
            "slot": "spell",
            "rarity": "legendary",
            "tile": tome["tile"],
            "base_type": tome["base_type"],
            "primary_stat": tome["primary_stat"],
            "damage_min": tome["damage_min"],
            "damage_max": tome["damage_max"],
            "damage_type": tome["damage_type"],
            "spell_cooldown": tome["spell_cooldown"],
            "item_tier": 5,
            "flavor_tags": [tome["damage_type"]] if tome["damage_type"] != "physical" else [],
            "lore": tome["lore"],
            "drop_weights": [0, 0, 0, 1, 4],
            "unique": True,
            "enchant_chance": 0.0,
            "implicit_affixes": tome["implicit_affixes"],
            "affix_pool": AFFIX_POOL_BY_SLOT["spell"],
        })

    out = {
        "_doc": "Item-overhaul v2 (2026-06-04). Schema: weapons have damage_min/max/speed/damage_type/weapon_class. Body slots have armor + evasion. Jewelry has zero baseline. All slots roll affixes from per-slot affix_pool. Uniques can carry implicit_affixes (item-defining bonuses, never roll). 5 archetype-unique spell tomes shipped with this migration.",
        "_format_version": 2,
        "items": migrated,
    }
    ITEMS_PATH.write_text(json.dumps(out, indent=2) + "\n")
    print(f"Wrote {len(migrated)} migrated items → {ITEMS_PATH.name}")
    if skipped:
        print(f"Skipped (unknown slot): {skipped}")

    # Migrate every per-slot manifest in the same shape so the editor
    # roundtrip stays consistent.
    for manifest in TOOLS.glob("items_*_manifest.json"):
        legacy_m = manifest.with_suffix(".json.legacy")
        shutil.copy(manifest, legacy_m)
        m_raw = json.loads(manifest.read_text())
        m_items = m_raw.get("items", []) if isinstance(m_raw, dict) else m_raw
        m_out = []
        for it in m_items:
            slot = it.get("slot", "")
            fn = SLOT_DISPATCH.get(slot)
            if fn is None:
                continue
            m_out.append(fn(it))
        if isinstance(m_raw, dict):
            m_raw["items"] = m_out
            payload = m_raw
        else:
            payload = m_out
        manifest.write_text(json.dumps(payload, indent=2) + "\n")
        print(f"  manifest → {manifest.name} ({len(m_out)} items)")


if __name__ == "__main__":
    main()
