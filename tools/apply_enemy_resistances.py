#!/usr/bin/env python3
"""S8 Pass 1: populate `resistances` on ~45 enemies.

Idempotent — running again with the same lookup table overwrites the
same keys to the same values. Subsequent passes can hand-edit
enemies.json freely; this script only touches enemies it knows about.

Lookup table is built from a08 §A1 (forge fire-creatures, glacier
ice-creatures, Crypt/Tomb undead, demons, slimes, trolls, spiders,
snakes, plus forge biome co-residents picking up +fire). Numeric
values follow the synthesis brief — the upper bound +75 matches the
player-side resistance clamp ceiling at stat_calc.gd:311.

Damage-type keys = the keys passed into Actor.take_damage /
SpellData.damage_type_for_element output. Reminder:
  spell element 'thunderous' -> damage_type 'lightning'

Run:  python3 tools/apply_enemy_resistances.py
"""
from __future__ import annotations

import json
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
ENEMIES_JSON = REPO / "project" / "data" / "enemies.json"

# Profile -> resistances dict. Empty values trimmed so the JSON stays
# compact and "no entry" is read as 0% by actor.gd::_apply_typed_damage.
PROFILES: dict[str, dict[str, int]] = {
    # +75 fire signature, soft to cold. Forge flagships.
    "fire_creature":      {"fire": 75, "cold": -40},
    # +75 cold signature, soft to fire. Glacier flagships.
    "ice_creature":       {"cold": 75, "fire": -40},
    # Demon-fire hybrid. Holy is the canonical anti-demon lane.
    "demon_fire":         {"fire": 75, "cold": -40, "holy": -40, "dark": 25},
    "demon_ice":          {"cold": 75, "fire": -40, "holy": -40, "dark": 25},
    # Pure demon (no element body). Resists fire well, hates holy.
    "demon":              {"fire": 50, "dark": 25, "holy": -40},
    # Demon variant with lightning flavor.
    "demon_lightning":    {"fire": 25, "lightning": 50, "dark": 25, "holy": -40},
    # Demon-canine. Spits fire, weak to cold and holy.
    "demon_hound":        {"fire": 50, "cold": -25, "dark": 25, "holy": -40},
    # Necro-flavored demon — also poison-resists since it drips rot.
    "demon_rot":          {"fire": 25, "dark": 50, "poison": 50, "holy": -40},
    # Crypt / Tomb undead. Cold-tolerant, dark-aligned, hates holy,
    # poison-immune-ish (DCSS pattern). Standard variant.
    "undead":             {"cold": 25, "dark": 50, "holy": -40, "poison": 50},
    # Heavier undead (wraiths, ghosts, liches): more dark, more cold,
    # extra physical resist if incorporeal.
    "undead_high":        {"cold": 50, "dark": 75, "holy": -50, "poison": 75},
    # Incorporeal — wraith / ghost. Phys resist on top of high undead.
    "undead_incorporeal": {"cold": 50, "dark": 50, "holy": -50, "poison": 75, "physical": 50},
    # Mummy — desiccated, fire-soft.
    "undead_mummy":       {"cold": 25, "dark": 50, "holy": -50, "poison": 75, "fire": -25},
    # Slimes — DCSS slime profile. Poison + physical resist, fire-soft.
    "slime":              {"poison": 75, "physical": 25, "fire": -25},
    # Slime + extra dark for death-ooze.
    "slime_dark":         {"poison": 75, "physical": 25, "fire": -25, "dark": 25},
    # Slime + cold for azure-jelly.
    "slime_cold":         {"poison": 75, "physical": 25, "fire": -25, "cold": 50},
    # Trolls — DCSS regen-stops-on-fire. Mild poison resist.
    "troll":              {"poison": 25, "fire": -50},
    # Spider — poison body, weak to holy.
    "spider":             {"poison": 50, "holy": -10},
    # Snake / cold-blooded — modest poison resist, soft to cold.
    "snake":              {"poison": 25, "cold": -25},
    # Forge co-resident (non-fire-creature giants/cyclopes who live
    # in lava biomes). +25 fire is the broken-combo signal: a fire
    # spec underperforms here, but isn't zeroed out.
    "forge_native":       {"fire": 25},
}

# Enemy id -> profile.
ASSIGNMENTS: dict[str, str] = {
    # Fire creatures
    "fire_giant":     "fire_creature",
    "fire_dragon":    "fire_creature",
    "salamander":     "fire_creature",
    # Ice creatures
    "ice_beast":      "ice_creature",
    "ice_dragon":     "ice_creature",
    "frost_giant":    "ice_creature",
    # Demons (hybrid + pure)
    "cacodemon":         "demon_fire",
    "blizzard_demon":    "demon_ice",
    "balrug":            "demon",
    "blue_devil":        "demon_lightning",
    "hell_hound":        "demon_hound",
    "rotting_devil":     "demon_rot",
    # Crypt / Tomb undead
    "skeleton":         "undead",
    "zombie":           "undead",
    "death_knight":     "undead",
    "vampire_knight":   "undead",
    "necrophage":       "undead",
    "anubis_guard":     "undead",
    "wraith":           "undead_incorporeal",
    "ghost":            "undead_incorporeal",
    "lich":             "undead_high",
    "ancient_lich":     "undead_high",
    "mummy":            "undead_mummy",
    "greater_mummy":    "undead_mummy",
    # Slimes
    "jelly":            "slime",
    "ooze":             "slime",
    "acid_blob":        "slime",
    "slime_creature":   "slime",
    "death_ooze":       "slime_dark",
    "azure_jelly":      "slime_cold",
    # Trolls / two-headed ogre (DCSS regen-stop family)
    "troll":             "troll",
    "deep_troll":        "troll",
    "two_headed_ogre":   "troll",
    # Spiders
    "redback":           "spider",
    "jumping_spider":    "spider",
    "wolf_spider":       "spider",
    "orb_spider":        "spider",
    "giant_spider":      "spider",
    # Snakes / serpentine
    "adder":             "snake",
    "water_moccasin":    "snake",
    "black_mamba":       "snake",
    "anaconda":          "snake",
    "ball_python":       "snake",
    "naga":              "snake",
    # Forge co-residents (broken-combo signal: fire spec underperforms here)
    "manticore":         "forge_native",
    "cyclops":           "forge_native",
    "ogre":              "forge_native",
}


def main() -> int:
    raw = ENEMIES_JSON.read_text()
    data = json.loads(raw)

    unknown = sorted(set(ASSIGNMENTS) - set(data.keys()))
    if unknown:
        print(f"WARN: {len(unknown)} unknown enemy ids (skipping):")
        for u in unknown:
            print(f"  - {u}")

    touched = 0
    for eid, profile_name in ASSIGNMENTS.items():
        if eid not in data:
            continue
        profile = PROFILES[profile_name]
        # Sort keys for stable output ordering.
        data[eid]["resistances"] = {k: profile[k] for k in sorted(profile)}
        touched += 1

    # Write back with stable formatting matching the existing file.
    # Existing file: 2-space indent, no trailing newline.
    out = json.dumps(data, indent=2)
    ENEMIES_JSON.write_text(out)
    print(f"Wrote {touched} resistance entries to enemies.json")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
