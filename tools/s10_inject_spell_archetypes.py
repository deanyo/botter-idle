#!/usr/bin/env python3
"""S10 — inject spell tomes for the 8 new spell archetypes into items.json.

Idempotent: re-running produces no change. Adds 6 tomes per archetype
(common / uncommon / rare / epic / legendary + a flavor variant), so the
loot pool covers each rarity slot. Affix pools mirror the existing
spell-tome shape (cooldown / multicast / damage scalers + the per-element
pcts from S1).

Skips an archetype if any of its tomes already exists by id (so a partial
re-run doesn't duplicate). Reports counts.

Usage: python3 tools/s10_inject_spell_archetypes.py
"""
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DB = ROOT / "project" / "data" / "items.json"

# Common affix-pool baseline that every spell tome shares (S1 normalized).
BASE_POOL: dict[str, int] = {
    "of_wisdom": 14,
    "of_quickcast": 22,
    "of_resonance": 20,
    "of_lingering": 18,
    "of_velocity": 12,
    "of_multicast": 10,
    "of_channeling": 22,
    "of_str_mastery": 8,
    "of_dex_mastery": 8,
    "of_int_mastery": 8,
    "of_crit": 12,
    "of_haste": 12,
    "of_lifesteal": 6,
    "of_pyromancer": 8,
    "of_cryomancer": 8,
    "of_storm": 8,
    "of_zealot": 8,
    "of_envenom": 8,
    "of_shadow": 8,
    "of_sage": 8,
    "of_hunter": 8,
    "of_tempest": 8,
    "of_synergy": 8,
}

# Per-rarity drop_weights — mirrors the existing canonical spread used
# by spell tomes (60/30/8/2/0 for common, etc).
RARITY_WEIGHTS = {
    "common":    [60, 30, 8, 2, 0],
    "uncommon":  [40, 50, 18, 4, 0],
    "rare":      [10, 30, 40, 15, 1],
    "epic":      [2, 8, 25, 50, 12],
    "legendary": [0, 0, 0, 1, 4],
}

RARITY_TIERS = {
    "common": 1, "uncommon": 2, "rare": 3, "epic": 4, "legendary": 5,
}


# Per-archetype config — base damage spread per tier, primary stat,
# damage_type (resolved on the spell side via element key), flavor tags,
# spell_cooldown spread (matches the archetype's cooldown × per-rarity
# clutch). Tier 1 / Tier 5 damage values bracket the range; per-tier
# spread interpolates linearly.
ARCHETYPES = {
    # bone_spear: STR phys bouncing. Base arch dmg = 22; tier curve 14-32.
    "spell_bone_spear": {
        "primary_stat": "str",
        "damage_type": "physical",
        "element": "",
        "flavor": ["earth"],
        "name": "Bone Spear",
        "lore": "A bouncing splinter of bone — once thrown, it finds the rest of the room.",
        "tile": "spells/scrolls/scroll.png",  # ITALIC: tiles validated against project/assets/tiles/items/
        # Tier-curve: T1 (14-18) → T5 (28-36)
        "tiers": {1: (14, 18), 2: (17, 21), 3: (20, 24), 4: (24, 30), 5: (28, 36)},
        "cooldown": {1: 6.0, 2: 5.2, 3: 4.5, 4: 3.8, 5: 3.2},
        "extra_pool": {"of_executioner": 8, "of_sundering": 8},
    },
    # venom_cloud: INT poison DoT. Per-tick dmg curve 1-3; cap 3 enemies.
    "spell_venom_cloud": {
        "primary_stat": "int",
        "damage_type": "poison",
        "element": "poison",
        "flavor": ["poison"],
        "name": "Venom Cloud",
        "lore": "A green miasma that lingers and reads each enemy's lungs.",
        "tile": "spells/books/dark_green.png",
        "tiers": {1: (1, 1), 2: (1, 2), 3: (2, 2), 4: (2, 3), 5: (3, 3)},
        "cooldown": {1: 7.0, 2: 6.2, 3: 5.5, 4: 4.8, 5: 4.2},
        "extra_pool": {"of_envenom": 30},
    },
    # stormcaller_totem: DEX lightning turret. 12 dmg/zap baseline; tier
    # ramps 8-18 dmg/zap.
    "spell_stormcaller_totem": {
        "primary_stat": "dex",
        "damage_type": "lightning",
        "element": "thunderous",
        "flavor": ["thunderous"],
        "name": "Stormcaller Totem",
        "lore": "Plant the totem; the lightning answers the rod.",
        "tile": "spells/books/metal_blue.png",
        "tiers": {1: (8, 10), 2: (10, 12), 3: (12, 14), 4: (14, 16), 5: (16, 18)},
        "cooldown": {1: 9.0, 2: 8.0, 3: 7.0, 4: 6.5, 5: 6.0},
        "extra_pool": {"of_storm": 30, "of_storms": 8},
    },
    # curse_brittlebone: DEX debuff (0 dmg). Tier scales duration via
    # spell_duration_pct on item — but for now just per-tier curve on
    # the base "damage" (kept at 1 to register kill log).
    "spell_curse_brittlebone": {
        "primary_stat": "dex",
        "damage_type": "dark",
        "element": "dark",
        "flavor": ["dark"],
        "name": "Curse of Brittlebone",
        "lore": "A whispered name; the cursed flinch from blows that haven't landed yet.",
        "tile": "spells/books/dark_blue.png",
        "tiers": {1: (1, 1), 2: (1, 1), 3: (1, 1), 4: (1, 1), 5: (1, 1)},
        "cooldown": {1: 12.0, 2: 11.0, 3: 10.0, 4: 9.0, 5: 8.0},
        "extra_pool": {"of_shadow": 22},
    },
    # wrath_charge: STR self-buff (0 dmg).
    "spell_wrath_charge": {
        "primary_stat": "str",
        "damage_type": "physical",
        "element": "",
        "flavor": ["brutal"],
        "name": "Wrath Charge",
        "lore": "A bellowed word. For four seconds, every blow remembers grudges.",
        "tile": "spells/books/red.png",
        "tiers": {1: (1, 1), 2: (1, 1), 3: (1, 1), 4: (1, 1), 5: (1, 1)},
        "cooldown": {1: 14.0, 2: 12.0, 3: 11.0, 4: 10.0, 5: 9.0},
        "extra_pool": {"of_str_mastery": 22},
    },
    # echo_lance: DEX bouncing-once. Base 11; tier 7-16.
    "spell_echo_lance": {
        "primary_stat": "dex",
        "damage_type": "lightning",
        "element": "thunderous",
        "flavor": ["thunderous"],
        "name": "Echo Lance",
        "lore": "A line of lightning that strikes twice — never thrice.",
        "tile": "spells/scrolls/scroll.png",
        "tiers": {1: (7, 9), 2: (8, 11), 3: (10, 13), 4: (12, 15), 5: (14, 17)},
        "cooldown": {1: 4.0, 2: 3.4, 3: 2.8, 4: 2.2, 5: 1.6},
        "extra_pool": {"of_storm": 22, "of_executioner": 8},
    },
    # wisp_servant: INT interim orbiter. Base 4 dmg/zap; tier 3-7.
    "spell_wisp_servant": {
        "primary_stat": "int",
        "damage_type": "physical",
        "element": "",
        "flavor": ["arcane"],
        "name": "Wisp Servant",
        "lore": "A bound spark. It does not wander; it waits beside you.",
        "tile": "spells/books/cyan.png",
        "tiers": {1: (3, 4), 2: (4, 5), 3: (5, 6), 4: (5, 7), 5: (6, 8)},
        "cooldown": {1: 12.0, 2: 10.0, 3: 8.5, 4: 7.5, 5: 7.0},
        "extra_pool": {"of_int_mastery": 22},
    },
    # ember_bloom: INT fire DoT patch. Per-tick 1-3.
    "spell_ember_bloom": {
        "primary_stat": "int",
        "damage_type": "fire",
        "element": "fire",
        "flavor": ["fire"],
        "name": "Ember Bloom",
        "lore": "Where the petals fall, the fire grows.",
        "tile": "spells/books/copper.png",
        "tiers": {1: (1, 2), 2: (1, 2), 3: (2, 3), 4: (2, 3), 5: (3, 3)},
        "cooldown": {1: 8.0, 2: 7.0, 3: 6.0, 4: 5.5, 5: 5.0},
        "extra_pool": {"of_pyromancer": 30},
    },
}


def _build_tome(arch: str, cfg: dict, rarity: str, suffix: str = "") -> dict:
    tier = RARITY_TIERS[rarity]
    dmin, dmax = cfg["tiers"][tier]
    cd = cfg["cooldown"][tier]
    pool = dict(BASE_POOL)
    pool.update(cfg.get("extra_pool", {}))
    item_id = arch if rarity == "common" and suffix == "" else f"{arch}_{suffix or rarity}"
    return {
        "id": item_id,
        "name": f"{cfg['name']} Tome" + (f" ({suffix.title()})" if suffix and suffix not in {rarity} else ""),
        "slot": "spell",
        "rarity": rarity,
        "tile": cfg["tile"],
        "base_type": arch,
        "primary_stat": cfg["primary_stat"],
        "damage_min": dmin,
        "damage_max": dmax,
        "damage_type": cfg["damage_type"],
        "spell_cooldown": cd,
        "item_tier": tier,
        "flavor_tags": list(cfg["flavor"]),
        "lore": cfg["lore"],
        "drop_weights": list(RARITY_WEIGHTS[rarity]),
        "unique": False,
        "enchant_chance": 0.1,
        "implicit_affixes": [],
        "affix_pool": pool,
    }


def main() -> int:
    doc = json.loads(DB.read_text())
    existing_ids = {it["id"] for it in doc["items"]}
    added: list[dict] = []
    for arch, cfg in ARCHETYPES.items():
        # 5 base rarities — common (= bare archetype id), then each
        # subsequent rarity gets a "_uncommon"/"_rare" id suffix to keep
        # the catalog browsable.
        plan = [
            ("common",    ""),
            ("uncommon",  "uncommon"),
            ("rare",      "rare"),
            ("epic",      "epic"),
            ("legendary", "legendary"),
            # 6th: one flavor variant at rare so DPS-curve picker has
            # something at f12-15. Same archetype, slightly hotter base.
            ("rare",      "honed"),
        ]
        for rarity, suffix in plan:
            tome = _build_tome(arch, cfg, rarity, suffix)
            if tome["id"] in existing_ids:
                continue
            doc["items"].append(tome)
            existing_ids.add(tome["id"])
            added.append(tome)
    if not added:
        print("No new tomes to add (all 8 archetypes already populated).")
        return 0
    DB.write_text(json.dumps(doc, indent=2) + "\n")
    print(f"Added {len(added)} spell tomes across {len(ARCHETYPES)} archetypes.")
    by_arch: dict[str, int] = {}
    for it in added:
        by_arch[it["base_type"]] = by_arch.get(it["base_type"], 0) + 1
    for arch, n in sorted(by_arch.items()):
        print(f"  {arch:30s} +{n} tomes")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
