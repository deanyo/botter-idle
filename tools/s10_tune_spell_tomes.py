#!/usr/bin/env python3
"""S10 — tune the new spell tomes after first injection.

The first pass at s10_inject_spell_archetypes.py landed cooldowns that
let venom_cloud / stormcaller_totem / wisp_servant break the +400 pack-
DPS ceiling at f30. This script overwrites their cooldowns + per-tick
damage so analyze_spell_dps_curve.py reports within ceiling.

Adjustments per a05 §D + a10 §3.2 rescope (item-tier cooldown spread):
  bone_spear:    arch 1.8s   items 6.0 → 3.2  T1→T5
  venom_cloud:   arch 4.5s   items 18 → 8     (tick base lowered)
  stormcaller:   arch 6.0s   items 25 → 12
  curse_brittle: arch 8.0s   items 32 → 18
  wrath_charge:  arch 9.0s   items 30 → 18
  echo_lance:    arch 1.4s   items 12 → 4
  wisp_servant:  arch 7.0s   items 25 → 14
  ember_bloom:   arch 5.0s   items 22 → 14

Idempotent. Reports counts.
"""
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DB = ROOT / "project" / "data" / "items.json"

# Per-archetype tier cooldown table. T1 is the slow common, T5 is the
# fast legendary. These match a05's per-archetype "items 12-25s" notation.
CD_BY_TIER = {
    "spell_bone_spear":         {1: 6.0, 2: 5.0, 3: 4.0, 4: 3.5, 5: 3.2},
    "spell_venom_cloud":        {1: 18.0, 2: 14.0, 3: 11.0, 4: 9.0, 5: 8.0},
    "spell_stormcaller_totem":  {1: 25.0, 2: 20.0, 3: 16.0, 4: 14.0, 5: 12.0},
    "spell_curse_brittlebone":  {1: 32.0, 2: 28.0, 3: 24.0, 4: 21.0, 5: 18.0},
    "spell_wrath_charge":       {1: 30.0, 2: 26.0, 3: 22.0, 4: 20.0, 5: 18.0},
    "spell_echo_lance":         {1: 12.0, 2: 9.0, 3: 7.0, 4: 5.0, 5: 4.0},
    "spell_wisp_servant":       {1: 25.0, 2: 21.0, 3: 18.0, 4: 16.0, 5: 14.0},
    "spell_ember_bloom":        {1: 22.0, 2: 19.0, 3: 17.0, 4: 15.0, 5: 14.0},
}

# Per-tick base damage for cloud archetypes — a10 §3.2 rescope is
# 1.5/tick venom, 2.0/tick ember at the archetype baseline. Items
# scale these via tier; keep peak modest so 2/s tick × 8s × 3 enemies
# stays under 400 pack DPS at f30 with full stat scaling.
DMG_BY_TIER = {
    "spell_venom_cloud":  {1: (1, 1), 2: (1, 1), 3: (1, 2), 4: (1, 2), 5: (2, 2)},
    "spell_ember_bloom":  {1: (1, 2), 2: (2, 2), 3: (2, 2), 4: (2, 2), 5: (2, 3)},
    # Stormcaller — keep 8-18 spread to balance with the long CD.
    "spell_stormcaller_totem":  {1: (8, 10), 2: (10, 12), 3: (12, 14), 4: (13, 16), 5: (14, 18)},
    # Wisp_servant — match a10 base 4 + tier scaling. Drop ceiling.
    "spell_wisp_servant":  {1: (3, 4), 2: (3, 4), 3: (4, 5), 4: (5, 6), 5: (6, 7)},
}


def main() -> int:
    doc = json.loads(DB.read_text())
    changed = 0
    for it in doc["items"]:
        bt = it.get("base_type", "")
        if bt not in CD_BY_TIER:
            continue
        tier = it.get("item_tier", 1)
        new_cd = CD_BY_TIER[bt][tier]
        if it.get("spell_cooldown") != new_cd:
            it["spell_cooldown"] = new_cd
            changed += 1
        if bt in DMG_BY_TIER:
            dmin, dmax = DMG_BY_TIER[bt][tier]
            if it.get("damage_min") != dmin or it.get("damage_max") != dmax:
                it["damage_min"] = dmin
                it["damage_max"] = dmax
                changed += 1
    if changed == 0:
        print("No tomes to tune.")
        return 0
    DB.write_text(json.dumps(doc, indent=2) + "\n")
    print(f"Tuned {changed} fields across S10 spell tomes.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
