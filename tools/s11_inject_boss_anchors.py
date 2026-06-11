#!/usr/bin/env python3
"""S11 — Inject 12 boss-anchor uniques into project/data/items.json.

Each unique declares:
  * boss_drop: <boss_id>      — only drops from the named boss kill
  * biome_pool: [<biome>]     — only rolls in the matching biome
  * implicit_affixes: [...]   — the unique mechanic + thematic stats

Idempotent: re-running upserts by item id (replaces an existing entry
with the same id).

Numbers are per a07 §6 with a10 §3.2 rescopes already baked into the
implicit_affix tiers (Kirke 50 ATK abs cap, Ilsuiw +25%, Tiamat +15%).
"""
from __future__ import annotations
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ITEMS = ROOT / "project" / "data" / "items.json"


# fmt: off
ANCHORS = [
    # T1 — first-branch bosses, dungeon/dungeon_dark/mines
    {
        "id": "sigmunds_sickle", "name": "Sigmund's Sickle",
        "slot": "weapon", "rarity": "legendary",
        "tile": "scythe_3.png",
        "base_type": "scythe", "weapon_class": "2H",
        "damage_min": 6, "damage_max": 12, "damage_type": "physical", "speed": 0.7,
        "item_tier": 1,
        "flavor_tags": ["bloody", "precision"],
        "lore": "Sigmund swung this in his prime. The prime was brief.",
        "drop_weights": [40, 0, 0, 0, 0],
        "unique": True, "enchant_chance": 0.0,
        "implicit_affixes": ["of_bleed_on_miss", "of_sharpness"],
        "affix_pool": {"of_might": 25, "of_sharpness": 20, "of_crit": 15, "of_bloodletting": 12},
        "boss_drop": "boss_sigmund",
        "biome_pool": ["dungeon"],
    },
    {
        "id": "blorks_pickaxe", "name": "Blork's Pickaxe",
        "slot": "weapon", "rarity": "rare",
        "tile": "ankus.png",
        "base_type": "mace", "weapon_class": "1H",
        "damage_min": 7, "damage_max": 11, "damage_type": "physical", "speed": 0.7,
        "item_tier": 1,
        "flavor_tags": ["fortune"],
        "lore": "Smells of mineshaft. Strikes earth like it was promised something.",
        "drop_weights": [40, 0, 0, 0, 0],
        "unique": True, "enchant_chance": 0.0,
        "implicit_affixes": ["of_prospecting", "of_sharpness"],
        "affix_pool": {"of_might": 20, "of_plunder": 22, "of_sharpness": 16, "of_crit": 12},
        "boss_drop": "boss_blork",
        "biome_pool": ["mines"],
    },
    {
        "id": "eustachio_dancing_sword", "name": "Eustachio's Dancing Sword",
        "slot": "weapon", "rarity": "epic",
        "tile": "long_sword_1_new.png",
        "base_type": "long_sword", "weapon_class": "1H",
        "damage_min": 6, "damage_max": 10, "damage_type": "physical", "speed": 0.5,
        "item_tier": 1,
        "flavor_tags": ["arcane", "precision"],
        "lore": "The blade leads. Eustachio was, quite literally, just along for the ride.",
        "drop_weights": [35, 0, 0, 0, 0],
        "unique": True, "enchant_chance": 0.0,
        "implicit_affixes": ["of_dancing", "of_finesse"],
        "affix_pool": {"of_finesse": 22, "of_haste": 18, "of_crit": 16, "of_sharpness": 14},
        "boss_drop": "boss_eustachio",
        "biome_pool": ["dungeon_dark"],
    },

    # T2 — second-branch bosses, lair/orc/temple
    {
        "id": "kirkes_pendant", "name": "Kirke's Pendant",
        "slot": "amulet", "rarity": "legendary",
        "tile": "stone_1_cyan.png",
        "base_type": "amulet_polymorph",
        "item_tier": 2,
        "flavor_tags": ["arcane"],
        "lore": "Its setting is shaped like a pig. The wearer notices things that weren't always pigs.",
        "drop_weights": [0, 30, 0, 0, 0],
        "unique": True, "enchant_chance": 0.0,
        "implicit_affixes": ["of_polymorph", "of_wisdom"],
        "affix_pool": {"of_wisdom": 20, "of_channeling": 18, "of_int_mastery": 14, "of_quickcast": 12},
        "boss_drop": "boss_kirke",
        "biome_pool": ["lair"],
    },
    {
        "id": "grums_wolfclaw_gauntlets", "name": "Grum's Wolfclaw Gauntlets",
        "slot": "gloves", "rarity": "rare",
        "tile": "glove_4_gauntlets.png",
        "base_type": "gauntlets",
        "armor": 4, "evasion": 2,
        "item_tier": 2,
        "flavor_tags": ["bloodlust"],
        "lore": "The wolves recognized them. Grum did not survive that recognition.",
        "drop_weights": [0, 30, 0, 0, 0],
        "unique": True, "enchant_chance": 0.0,
        "implicit_affixes": ["of_wolf_kinship", "of_might"],
        "affix_pool": {"of_might": 22, "of_finesse": 14, "of_sharpness": 16, "of_haste": 10},
        "boss_drop": "boss_grum",
        "biome_pool": ["orc"],
    },
    {
        "id": "psyche_holy_censer", "name": "Psyche's Holy Censer",
        "slot": "helm", "rarity": "epic",
        "tile": "helm_cap.png",
        "base_type": "helm",
        "armor": 4, "evasion": 1,
        "item_tier": 2,
        "flavor_tags": ["faith", "regen"],
        "lore": "Smolders eternally. Psyche believed the smoke kept her sane. It did not.",
        "drop_weights": [0, 25, 5, 0, 0],
        "unique": True, "enchant_chance": 0.0,
        "implicit_affixes": ["of_holy_anchor", "of_holy_resist"],
        "affix_pool": {"of_wisdom": 16, "of_vitality": 18, "of_holy_resist": 18, "of_regen": 16},
        "boss_drop": "boss_psyche",
        "biome_pool": ["temple"],
    },

    # T3 — mid bosses, swamp/shoals/snake
    {
        "id": "lernaean_hydra_cloak", "name": "Lernaean Hydra-Scale Cloak",
        "slot": "cloak", "rarity": "legendary",
        "tile": "cloak_3.png",
        "base_type": "cloak",
        "armor": 6, "evasion": 12,
        "item_tier": 3,
        "flavor_tags": ["regen"],
        "lore": "Each scale grew back twice. The wearer feels the same.",
        "drop_weights": [0, 0, 30, 0, 0],
        "unique": True, "enchant_chance": 0.0,
        "implicit_affixes": ["of_serpent_growth", "of_vitality"],
        "affix_pool": {"of_vitality": 24, "of_the_bear": 18, "of_regen": 16, "of_poison_resist": 14},
        "boss_drop": "boss_lernaean",
        "biome_pool": ["swamp"],
    },
    {
        "id": "ilsuiw_trident", "name": "Ilsuiw's Mermaid Trident",
        "slot": "weapon", "rarity": "legendary",
        "tile": "spear_3.png",
        "base_type": "spear", "weapon_class": "1H",
        "damage_min": 12, "damage_max": 18, "damage_type": "physical", "speed": 0.7,
        "item_tier": 3,
        "flavor_tags": ["cold", "tide"],
        "lore": "Bites cold. Salt. Hums when the wielder steps on wet stone.",
        "drop_weights": [0, 0, 30, 0, 0],
        "unique": True, "enchant_chance": 0.0,
        "implicit_affixes": ["of_tidesong", "of_frost"],
        "affix_pool": {"of_might": 20, "of_finesse": 16, "of_frost": 18, "of_sharpness": 14},
        "boss_drop": "boss_ilsuiw",
        "biome_pool": ["shoals"],
    },
    {
        "id": "aizul_serpent_knife", "name": "Aizul's Snake-Fang Knife",
        "slot": "weapon", "rarity": "rare",
        "tile": "dagger_3.png",
        "base_type": "dagger", "weapon_class": "1H",
        "damage_min": 5, "damage_max": 9, "damage_type": "physical", "speed": 0.4,
        "item_tier": 3,
        "flavor_tags": ["poison", "precision"],
        "lore": "Carved from a single tooth. Still drips, faintly, in dry air.",
        "drop_weights": [0, 0, 30, 0, 0],
        "unique": True, "enchant_chance": 0.0,
        "implicit_affixes": ["of_serpent_venom", "of_finesse"],
        "affix_pool": {"of_finesse": 22, "of_crit": 16, "of_venom": 18, "of_poison_resist": 12},
        "boss_drop": "boss_aizul",
        "biome_pool": ["snake"],
    },

    # T4 — late bosses, crypt/vaults
    {
        "id": "boris_phylactery", "name": "Boris's Necromantic Phylactery",
        "slot": "amulet", "rarity": "legendary",
        "tile": "bone_gray.png",
        "base_type": "amulet_phylactery",
        "item_tier": 4,
        "flavor_tags": ["dark", "willpower"],
        "lore": "Boris's piece of himself, neatly preserved. Now yours, if you find a way.",
        "drop_weights": [0, 0, 0, 40, 0],
        "unique": True, "enchant_chance": 0.0,
        "implicit_affixes": ["of_phylactery", "of_dark_resist"],
        "affix_pool": {"of_vitality": 22, "of_wisdom": 16, "of_dark_resist": 18, "of_regen": 12},
        "boss_drop": "boss_boris",
        "biome_pool": ["crypt"],
    },
    {
        "id": "frederick_vault_key_ring", "name": "Frederick's Vault-Key Ring",
        "slot": "ring", "rarity": "legendary",
        "tile": "ring_gold_white.png",
        "base_type": "ring_keys",
        "item_tier": 4,
        "flavor_tags": ["fortune"],
        "lore": "Heavy with keys. Frederick collected them. Frederick was, eventually, collected.",
        "drop_weights": [0, 0, 0, 40, 0],
        "unique": True, "enchant_chance": 0.0,
        "implicit_affixes": ["of_vault_key", "of_plunder"],
        "affix_pool": {"of_might": 14, "of_finesse": 14, "of_wisdom": 14, "of_plunder": 18, "of_scribe": 12},
        "boss_drop": "boss_frederick",
        "biome_pool": ["vaults"],
    },

    # T5 — final boss, zot
    {
        "id": "tiamat_five_heads", "name": "Tiamat's Five Heads",
        "slot": "helm", "rarity": "legendary",
        "tile": "crested_helmet.png",
        "base_type": "helm",
        "armor": 12, "evasion": 4,
        "item_tier": 5,
        "flavor_tags": ["fire_res", "cold_res", "willpower"],
        "lore": "Five heads. Five jaws. Five voices, none quieting.",
        "drop_weights": [0, 0, 0, 0, 30],
        "unique": True, "enchant_chance": 0.0,
        "implicit_affixes": [
            "of_five_heads", "of_fire_resist", "of_cold_resist", "of_poison_resist",
        ],
        "affix_pool": {"of_wisdom": 20, "of_vitality": 22, "of_channeling": 16, "of_quickcast": 14},
        "boss_drop": "boss_tiamat",
        "biome_pool": ["zot"],
    },
]
# fmt: on


def main() -> int:
    doc = json.loads(ITEMS.read_text())
    items = doc.get("items", [])
    by_id = {it.get("id"): i for i, it in enumerate(items)}
    inserted, replaced = 0, 0
    for entry in ANCHORS:
        eid = entry["id"]
        if eid in by_id:
            items[by_id[eid]] = entry
            replaced += 1
        else:
            items.append(entry)
            inserted += 1
    doc["items"] = items
    ITEMS.write_text(json.dumps(doc, indent=2) + "\n")
    print(f"s11_inject_boss_anchors: inserted={inserted} replaced={replaced} total_anchors={len(ANCHORS)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
