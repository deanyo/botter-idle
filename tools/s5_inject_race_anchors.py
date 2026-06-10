#!/usr/bin/env python3
"""S5 — race-anchor uniques injection.

Reads project/data/items.json, appends 30 race-anchor uniques (2-3 per
species, mix of T1-T5), and writes the file back. Idempotent — uniques
keyed by id; re-running replaces in-place.

Per a04 §5 + a10 §3.2 rescopes. Every numeric value comes from a10.
Anchors gate via `requires_innate_tag` — humans get the muted version
(stat_calc.gd skips implicit_affixes when species lacks the tag).

Run from repo root: python3 tools/s5_inject_race_anchors.py
"""

import json
import sys
from pathlib import Path

ITEMS = Path(__file__).resolve().parent.parent / "project/data/items.json"

# Each anchor: a unique items.json entry. Tier-spread per a04 §5 priority
# (mix of T1-T5 to seed the chase ladder). drop_weights peak at the named
# tier. Implicit affixes use existing affix ids unless flagged.
#
# Keep `flavor_tags` lean — tags are read by combat to drive on-hit/proc
# behavior, so duplicating the implicit_affixes' effect via flavor_tags
# would double-fire. Tags here are the conditional/passive flavors that
# don't have an affix (`feast`, `petrify`, `first_blood`, `flying`,
# `swiftness`, `stealth`, etc.).

DROP_WEIGHTS = {
    1: [12, 30, 8, 0, 0],
    2: [0, 12, 30, 8, 0],
    3: [0, 0, 12, 30, 8],
    4: [0, 0, 0, 12, 30],
    5: [0, 0, 0, 5, 25],
}

ANCHORS = [
    # ─── Spriggan (forest, fae) ─────────────────────────────────────
    {
        "id": "spriggan_leaf_boots",
        "name": "Leaf-Light Slippers",
        "slot": "boots",
        "rarity": "rare",
        "tile": "wormwood_boots.png",
        "base_type": "sandals",
        "armor": 2, "evasion": 12,
        "item_tier": 3,
        "flavor_tags": ["swiftness", "footwork"],
        "lore": "Stitched from dryad-blessed leaves. The wearer steps on tomorrow's grass.",
        "drop_weights": DROP_WEIGHTS[3],
        "unique": True,
        "enchant_chance": 0.0,
        "requires_innate_tag": "fae",
        "implicit_affixes": ["of_haste"],
        "affix_pool": {"of_finesse": 14, "of_evasion_pct_dummy": 0},
    },
    {
        "id": "spriggan_fae_cloak",
        "name": "Fey-Sap Cloak",
        "slot": "cloak",
        "rarity": "epic",
        "tile": "fae_cloak.png",
        "base_type": "cloak",
        "armor": 4, "evasion": 24,
        "item_tier": 4,
        "flavor_tags": ["stealth", "willpower"],
        "lore": "It dries the wood of every forest it walks through.",
        "drop_weights": DROP_WEIGHTS[4],
        "unique": True,
        "enchant_chance": 0.0,
        "requires_innate_tag": "forest",
        "implicit_affixes": ["of_haste", "of_resonance"],
        "affix_pool": {"of_finesse": 16, "of_wisdom": 12},
    },

    # ─── Minotaur (bovine, champion) ────────────────────────────────
    {
        "id": "minotaur_horn_helm",
        "name": "Horn-Bound Helm",
        "slot": "helm",
        "rarity": "epic",
        "tile": "horned_helm.png",
        "base_type": "great_helm",
        "armor": 14, "evasion": 4,
        "item_tier": 3,
        "flavor_tags": ["lordly", "rampaging"],
        "lore": "The skull beneath remembers older wars. Charging is a virtue.",
        "drop_weights": DROP_WEIGHTS[3],
        "unique": True,
        "enchant_chance": 0.0,
        "requires_innate_tag": "bovine",
        "implicit_affixes": ["of_might", "of_hunter"],
        "affix_pool": {"of_might": 20, "of_vitality": 14},
    },
    {
        "id": "minotaur_champion_blade",
        "name": "Blade of the Champion",
        "slot": "weapon",
        "rarity": "epic",
        "tile": "spwpn_axes_arena.png",
        "base_type": "executioner_axe",
        "weapon_class": "2H",
        "damage_min": 58, "damage_max": 102,
        "damage_type": "physical", "speed": 0.85,
        "item_tier": 4,
        "flavor_tags": ["brutal", "lordly"],
        "lore": "Wielded only by the champion. Loaned only to the next.",
        "drop_weights": DROP_WEIGHTS[4],
        "unique": True,
        "enchant_chance": 0.0,
        "requires_innate_tag": "champion",
        "implicit_affixes": ["of_sharpness", "of_berserker"],
        "affix_pool": {"of_might": 24, "of_crit": 16, "of_sharpness": 18},
    },

    # ─── Naga (serpentine, coldblooded) ─────────────────────────────
    {
        "id": "naga_coiled_ring",
        "name": "Coiled Ring",
        "slot": "ring",
        "rarity": "rare",
        "tile": "ring_coral.png",
        "base_type": "ring_regen",
        "item_tier": 3,
        "flavor_tags": ["regen"],
        "lore": "Tightens with each strike upon a single quarry.",
        "drop_weights": DROP_WEIGHTS[3],
        "unique": True,
        "enchant_chance": 0.0,
        "requires_innate_tag": "serpentine",
        "implicit_affixes": ["of_regen", "of_hunter"],
        "affix_pool": {"of_might": 12, "of_finesse": 10},
    },
    {
        "id": "naga_frostfang_ring",
        "name": "Frostfang Ring",
        "slot": "ring",
        "rarity": "epic",
        "tile": "ring_octopus.png",
        "base_type": "ring_cold",
        "item_tier": 4,
        "flavor_tags": ["cold_res", "cold"],
        "lore": "Coldblood fangs forged into a coil. Bites the hand it wraps.",
        "drop_weights": DROP_WEIGHTS[4],
        "unique": True,
        "enchant_chance": 0.0,
        "requires_innate_tag": "coldblooded",
        "implicit_affixes": ["of_cold_resist", "of_frost"],
        "affix_pool": {"of_cryomancer": 16, "of_finesse": 12},
    },

    # ─── Tengu (avian, windborn) ────────────────────────────────────
    {
        "id": "tengu_wind_cloak",
        "name": "Windborn Cloak",
        "slot": "cloak",
        "rarity": "rare",
        "tile": "tengu_cloak.png",
        "base_type": "cloak",
        "armor": 1, "evasion": 16,
        "item_tier": 3,
        "flavor_tags": ["swiftness", "flying"],
        "lore": "Catches the air the wearer's wings would have, were they still there.",
        "drop_weights": DROP_WEIGHTS[3],
        "unique": True,
        "enchant_chance": 0.0,
        "requires_innate_tag": "windborn",
        "implicit_affixes": ["of_haste"],
        "affix_pool": {"of_finesse": 14, "of_evasion_pct_dummy": 0},
    },
    {
        "id": "tengu_skystriker_helm",
        "name": "Sky-Striker Beak Helm",
        "slot": "helm",
        "rarity": "epic",
        "tile": "tengu_helm.png",
        "base_type": "helmet",
        "armor": 9, "evasion": 11,
        "item_tier": 4,
        "flavor_tags": ["first_blood", "precision"],
        "lore": "The first stroke is the one that breaks the sky.",
        "drop_weights": DROP_WEIGHTS[4],
        "unique": True,
        "enchant_chance": 0.0,
        "requires_innate_tag": "avian",
        "implicit_affixes": ["of_crit"],
        "affix_pool": {"of_finesse": 18, "of_crit": 12},
    },

    # ─── Troll (regen, primal) ──────────────────────────────────────
    {
        "id": "troll_hide_armor",
        "name": "Troll-Hide Armor",
        "slot": "armor",
        "rarity": "rare",
        "tile": "troll_leather_unique.png",
        "base_type": "troll_leather",
        "armor": 18, "evasion": 4,
        "item_tier": 3,
        "flavor_tags": ["feast", "regen"],
        "lore": "Sloughs and re-knits with each meal. Smells worse than its previous owner.",
        "drop_weights": DROP_WEIGHTS[3],
        "unique": True,
        "enchant_chance": 0.0,
        "requires_innate_tag": "regen",
        "implicit_affixes": ["of_vitality", "of_regen"],
        "affix_pool": {"of_might": 12, "of_the_bear": 10},
    },
    {
        "id": "troll_crusher",
        "name": "Crusher",
        "slot": "weapon",
        "rarity": "epic",
        "tile": "spwpn_giant_club_unique.png",
        "base_type": "giant_club",
        "weapon_class": "2H",
        "damage_min": 65, "damage_max": 110,
        "damage_type": "physical", "speed": 1.0,
        "item_tier": 4,
        "flavor_tags": ["brutal", "ponderous"],
        "lore": "It will outlast you, and the troll, and the troll's grandchildren.",
        "drop_weights": DROP_WEIGHTS[4],
        "unique": True,
        "enchant_chance": 0.0,
        "requires_innate_tag": "primal",
        "implicit_affixes": ["of_might", "of_hunter"],
        "affix_pool": {"of_might": 25, "of_sharpness": 18},
    },

    # ─── Octopode (aquatic, many-armed) ─────────────────────────────
    {
        "id": "octopode_coral_ring",
        "name": "Octopode's Coral",
        "slot": "ring",
        "rarity": "rare",
        "tile": "ring_octopus.png",
        "base_type": "ring_magic",
        "item_tier": 3,
        "flavor_tags": ["regen", "fortune"],
        "lore": "Polished smooth in eight grips at once.",
        "drop_weights": DROP_WEIGHTS[3],
        "unique": True,
        "enchant_chance": 0.0,
        "requires_innate_tag": "aquatic",
        "implicit_affixes": ["of_wisdom"],
        "affix_pool": {"of_wisdom": 14, "of_resonance": 10},
    },
    {
        "id": "octopode_eight_amulet",
        "name": "Mantle of the Eight",
        "slot": "amulet",
        "rarity": "epic",
        "tile": "amulet_octopode.png",
        "base_type": "amulet_acrobat",
        "item_tier": 4,
        "flavor_tags": ["vision", "psychic"],
        "lore": "Each tentacle reads a different sky.",
        "drop_weights": DROP_WEIGHTS[4],
        "unique": True,
        "enchant_chance": 0.0,
        "requires_innate_tag": "many-armed",
        "implicit_affixes": ["of_int_mastery", "of_resonance"],
        "affix_pool": {"of_wisdom": 14, "of_channeling": 12},
    },

    # ─── Demonspawn (demon) ─────────────────────────────────────────
    {
        "id": "demonspawn_hellsigil_brand",
        "name": "Hellsigil Brand",
        "slot": "weapon",
        "rarity": "rare",
        "tile": "spwpn_demon_blade.png",
        "base_type": "scimitar",
        "weapon_class": "1H",
        "damage_min": 32, "damage_max": 58,
        "damage_type": "fire", "speed": 0.6,
        "item_tier": 3,
        "flavor_tags": ["fire", "demon"],
        "lore": "Brands the air it cuts. Old promise re-renewed.",
        "drop_weights": DROP_WEIGHTS[3],
        "unique": True,
        "enchant_chance": 0.0,
        "requires_innate_tag": "demon",
        "implicit_affixes": ["of_embers", "of_pyromancer"],
        "affix_pool": {"of_might": 16, "of_pyromancer": 14},
    },
    {
        "id": "demonspawn_ashen_crown",
        "name": "Ashen Crown",
        "slot": "helm",
        "rarity": "epic",
        "tile": "ashen_crown.png",
        "base_type": "crown",
        "armor": 8, "evasion": 8,
        "item_tier": 4,
        "flavor_tags": ["fire", "harm"],
        "lore": "Worn by every demonspawn who outlived their patron.",
        "drop_weights": DROP_WEIGHTS[4],
        "unique": True,
        "enchant_chance": 0.0,
        "requires_innate_tag": "demon",
        "implicit_affixes": ["of_pyromancer", "of_resonance"],
        "affix_pool": {"of_pyromancer": 18, "of_int_mastery": 14},
    },

    # ─── Vampire (vampiric, undead) ─────────────────────────────────
    {
        "id": "vampire_sangromancer_locket",
        "name": "Sangromancer's Locket",
        "slot": "amulet",
        "rarity": "epic",
        "tile": "amulet_blood.png",
        "base_type": "amulet_rage",
        "item_tier": 3,
        "flavor_tags": ["vampiric", "harm"],
        "lore": "A fingerbone in red glass. The bone is yours.",
        "drop_weights": DROP_WEIGHTS[3],
        "unique": True,
        "enchant_chance": 0.0,
        "requires_innate_tag": "vampiric",
        "implicit_affixes": ["of_lifesteal", "of_might"],
        "affix_pool": {"of_lifesteal": 20, "of_might": 14},
    },
    {
        "id": "vampire_nightshade_cloak",
        "name": "Nightshade Cloak",
        "slot": "cloak",
        "rarity": "rare",
        "tile": "cloak_nightshade.png",
        "base_type": "cloak",
        "armor": 2, "evasion": 14,
        "item_tier": 3,
        "flavor_tags": ["stealth", "vampiric"],
        "lore": "Folded shadow with a salt taste. Closes around the neck like a kiss.",
        "drop_weights": DROP_WEIGHTS[3],
        "unique": True,
        "enchant_chance": 0.0,
        "requires_innate_tag": "vampiric",
        "implicit_affixes": ["of_lifesteal", "of_haste"],
        "affix_pool": {"of_lifesteal": 14, "of_finesse": 10},
    },

    # ─── Mummy (undead, ancient) ────────────────────────────────────
    {
        "id": "mummy_tomb_wrappings",
        "name": "Sigil-Wrappings of the Tomb",
        "slot": "armor",
        "rarity": "epic",
        "tile": "tomb_wrappings.png",
        "base_type": "robe",
        "armor": 6, "evasion": 18,
        "item_tier": 3,
        "flavor_tags": ["dark", "willpower"],
        "lore": "Three sigils per wrap. The sigils outlast the linen.",
        "drop_weights": DROP_WEIGHTS[3],
        "unique": True,
        "enchant_chance": 0.0,
        "requires_innate_tag": "ancient",
        "implicit_affixes": ["of_dark_resist", "of_int_mastery"],
        "affix_pool": {"of_wisdom": 16, "of_channeling": 12},
    },
    {
        "id": "mummy_relic_amulet",
        "name": "Pharaoh's Relic Amulet",
        "slot": "amulet",
        "rarity": "rare",
        "tile": "relic_amulet.png",
        "base_type": "amulet_faith",
        "item_tier": 3,
        "flavor_tags": ["faith", "psychic"],
        "lore": "Older than the curse. Older than the mummy who carried it.",
        "drop_weights": DROP_WEIGHTS[3],
        "unique": True,
        "enchant_chance": 0.0,
        "requires_innate_tag": "ancient",
        "implicit_affixes": ["of_lingering", "of_wisdom"],
        "affix_pool": {"of_wisdom": 14, "of_lingering": 10},
    },

    # ─── Hill Orc (orcish, raider) ──────────────────────────────────
    {
        "id": "orc_beoghs_banner",
        "name": "Beogh's Banner",
        "slot": "cloak",
        "rarity": "epic",
        "tile": "orcish_banner.png",
        "base_type": "cloak",
        "armor": 4, "evasion": 18,
        "item_tier": 3,
        "flavor_tags": ["rage", "lordly"],
        "lore": "Pinned to the back of every orc warlord. Most are too proud to drop it.",
        "drop_weights": DROP_WEIGHTS[3],
        "unique": True,
        "enchant_chance": 0.0,
        "requires_innate_tag": "orcish",
        "implicit_affixes": ["of_might", "of_berserker"],
        "affix_pool": {"of_might": 18, "of_berserker": 14},
    },
    {
        "id": "orc_raider_axe",
        "name": "Raider's Hand-Axe",
        "slot": "weapon",
        "rarity": "rare",
        "tile": "spwpn_orc_handaxe.png",
        "base_type": "hand_axe",
        "weapon_class": "1H",
        "damage_min": 26, "damage_max": 48,
        "damage_type": "physical", "speed": 0.7,
        "item_tier": 2,
        "flavor_tags": ["rampaging"],
        "lore": "Notched once for every farmstead. The notches go around twice.",
        "drop_weights": DROP_WEIGHTS[2],
        "unique": True,
        "enchant_chance": 0.0,
        "requires_innate_tag": "raider",
        "implicit_affixes": ["of_might", "of_plunder"],
        "affix_pool": {"of_might": 14, "of_plunder": 10},
    },

    # ─── Deep Elf (elf, scholar) ────────────────────────────────────
    {
        "id": "elf_grimoire_gloves",
        "name": "Grimoire-Bound Gloves",
        "slot": "gloves",
        "rarity": "epic",
        "tile": "elf_gloves.png",
        "base_type": "gloves",
        "armor": 3, "evasion": 8,
        "item_tier": 3,
        "flavor_tags": ["wisdom", "arcane"],
        "lore": "Each finger underwritten with a verse the wearer half-remembers.",
        "drop_weights": DROP_WEIGHTS[3],
        "unique": True,
        "enchant_chance": 0.0,
        "requires_innate_tag": "scholar",
        "implicit_affixes": ["of_wisdom", "of_quickcast"],
        "affix_pool": {"of_wisdom": 16, "of_channeling": 12},
    },
    {
        "id": "elf_spire_tome",
        "name": "Elven Spire Tome",
        "slot": "spell",
        "rarity": "epic",
        "tile": "elf_tome.png",
        "base_type": "spell_iron_shot",
        "primary_stat": "int",
        "item_tier": 4,
        "flavor_tags": ["arcane"],
        "lore": "An iron-shot manual transcribed by a deep-elf hand. The shot leaves a glow.",
        "drop_weights": DROP_WEIGHTS[4],
        "unique": True,
        "enchant_chance": 0.0,
        "requires_innate_tag": "elf",
        "implicit_affixes": ["of_int_mastery", "of_resonance"],
        "affix_pool": {"of_int_mastery": 18, "of_channeling": 14},
    },

    # ─── Gargoyle (construct, stone) ────────────────────────────────
    {
        "id": "gargoyle_stoneflesh_plate",
        "name": "Stoneflesh Plate",
        "slot": "armor",
        "rarity": "epic",
        "tile": "stoneflesh_plate.png",
        "base_type": "plate",
        "armor": 30, "evasion": 0,
        "item_tier": 4,
        "flavor_tags": ["petrify", "fortified"],
        "lore": "Becomes the wearer's skin where it touches it. Take it off carefully.",
        "drop_weights": DROP_WEIGHTS[4],
        "unique": True,
        "enchant_chance": 0.0,
        "requires_innate_tag": "stone",
        "implicit_affixes": ["of_the_bear", "of_vitality"],
        "affix_pool": {"of_the_bear": 18, "of_might": 12},
    },
    {
        "id": "gargoyle_granite_amulet",
        "name": "Granite Mantle",
        "slot": "amulet",
        "rarity": "rare",
        "tile": "amulet_granite.png",
        "base_type": "amulet_guardian",
        "item_tier": 3,
        "flavor_tags": ["guardian"],
        "lore": "Heavy enough that the wearer never quite straightens.",
        "drop_weights": DROP_WEIGHTS[3],
        "unique": True,
        "enchant_chance": 0.0,
        "requires_innate_tag": "construct",
        "implicit_affixes": ["of_the_bear", "of_holy_resist"],
        "affix_pool": {"of_the_bear": 14, "of_might": 10},
    },

    # ─── Halfling (small, lucky) ────────────────────────────────────
    {
        "id": "halfling_luck_charm",
        "name": "Luck-Bound Sling Bag",
        "slot": "amulet",
        "rarity": "rare",
        "tile": "lucky_pouch.png",
        "base_type": "amulet_acrobat",
        "item_tier": 2,
        "flavor_tags": ["fortune", "footwork"],
        "lore": "Always one coin heavier than you remember leaving it.",
        "drop_weights": DROP_WEIGHTS[2],
        "unique": True,
        "enchant_chance": 0.0,
        "requires_innate_tag": "lucky",
        "implicit_affixes": ["of_plunder", "of_scribe"],
        "affix_pool": {"of_plunder": 14, "of_scribe": 12},
    },
    {
        "id": "halfling_quiet_knife",
        "name": "Knife of the Quiet Road",
        "slot": "weapon",
        "rarity": "rare",
        "tile": "spwpn_halfling_knife.png",
        "base_type": "knife",
        "weapon_class": "1H",
        "damage_min": 24, "damage_max": 42,
        "damage_type": "physical", "speed": 0.45,
        "item_tier": 3,
        "flavor_tags": ["stealth", "first_blood"],
        "lore": "Soft on the road. Loud on the kidney.",
        "drop_weights": DROP_WEIGHTS[3],
        "unique": True,
        "enchant_chance": 0.0,
        "requires_innate_tag": "small",
        "implicit_affixes": ["of_finesse", "of_crit"],
        "affix_pool": {"of_crit": 16, "of_haste": 12},
    },

    # ─── Kobold (small, scavenger) ──────────────────────────────────
    {
        "id": "kobold_scavenger_coat",
        "name": "Scavenger's Coat",
        "slot": "armor",
        "rarity": "rare",
        "tile": "scavenger_coat.png",
        "base_type": "leather",
        "armor": 8, "evasion": 8,
        "item_tier": 2,
        "flavor_tags": ["fortune", "regen"],
        "lore": "Patched with whatever the previous owner had no further use for.",
        "drop_weights": DROP_WEIGHTS[2],
        "unique": True,
        "enchant_chance": 0.0,
        "requires_innate_tag": "scavenger",
        "implicit_affixes": ["of_plunder", "of_regen"],
        "affix_pool": {"of_plunder": 12, "of_finesse": 10},
    },
    {
        "id": "kobold_throwing_hand",
        "name": "Throwing Hand",
        "slot": "gloves",
        "rarity": "rare",
        "tile": "kobold_gloves.png",
        "base_type": "gloves",
        "armor": 2, "evasion": 8,
        "item_tier": 3,
        "flavor_tags": ["agility"],
        "lore": "Wraps two fingers and a thumb. The other digits do their own work.",
        "drop_weights": DROP_WEIGHTS[3],
        "unique": True,
        "enchant_chance": 0.0,
        "requires_innate_tag": "scavenger",
        "implicit_affixes": ["of_velocity", "of_multicast"],
        "affix_pool": {"of_finesse": 14, "of_velocity": 10},
    },

    # ─── Vampire low-tier weapon (gives Vampire a chase target below T5) ─
    {
        "id": "vampire_splintered_tooth",
        "name": "Splintered Tooth",
        "slot": "weapon",
        "rarity": "uncommon",
        "tile": "spwpn_splintered_tooth.png",
        "base_type": "dagger",
        "weapon_class": "1H",
        "damage_min": 6, "damage_max": 12,
        "damage_type": "physical", "speed": 0.45,
        "item_tier": 1,
        "flavor_tags": ["vampiric"],
        "lore": "Yours, once. Returned to you sharper.",
        "drop_weights": DROP_WEIGHTS[1],
        "unique": True,
        "enchant_chance": 0.0,
        "requires_innate_tag": "vampiric",
        "implicit_affixes": ["of_lifesteal"],
        "affix_pool": {"of_lifesteal": 12, "of_might": 8},
    },

    # ─── Spriggan low-tier (T1 chase target) ────────────────────────
    {
        "id": "spriggan_wisp_lance",
        "name": "Wisp-Lance",
        "slot": "weapon",
        "rarity": "uncommon",
        "tile": "spwpn_wisp_lance.png",
        "base_type": "dagger",
        "weapon_class": "1H",
        "damage_min": 8, "damage_max": 14,
        "damage_type": "lightning", "speed": 0.4,
        "item_tier": 1,
        "flavor_tags": ["arcane"],
        "lore": "Light as a thought. Cuts faster than one.",
        "drop_weights": DROP_WEIGHTS[1],
        "unique": True,
        "enchant_chance": 0.0,
        "requires_innate_tag": "fae",
        "implicit_affixes": ["of_haste"],
        "affix_pool": {"of_finesse": 10, "of_storms": 8},
    },
]


def main() -> int:
    if not ITEMS.exists():
        print(f"items.json not found at {ITEMS}", file=sys.stderr)
        return 1
    with ITEMS.open() as f:
        data = json.load(f)
    items = data["items"]
    # Build id → index map.
    by_id = {it.get("id"): idx for idx, it in enumerate(items)}
    added = 0
    replaced = 0
    for anchor in ANCHORS:
        # Strip the dummy affix-pool entry — used as a placeholder when
        # the slot has few good affix options.
        if "of_evasion_pct_dummy" in anchor.get("affix_pool", {}):
            anchor["affix_pool"].pop("of_evasion_pct_dummy")
            if not anchor["affix_pool"]:
                anchor["affix_pool"] = {"of_finesse": 10}
        anchor_id = anchor["id"]
        if anchor_id in by_id:
            items[by_id[anchor_id]] = anchor
            replaced += 1
        else:
            items.append(anchor)
            added += 1
    with ITEMS.open("w") as f:
        json.dump(data, f, indent=2)
        f.write("\n")
    print(f"S5 race anchors: {added} added, {replaced} replaced — total uniques now: " +
          str(sum(1 for it in items if it.get('unique'))))
    return 0


if __name__ == "__main__":
    sys.exit(main())
