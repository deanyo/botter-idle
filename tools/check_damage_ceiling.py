#!/usr/bin/env python3
"""Weapon damage-ceiling tripwire.

Walks `project/data/items.json` and asserts every weapon stays within the
design ceiling:

  - `damage_max <= 220`         (single-swing peak before any affix roll)
  - `damage_max / speed <= 245` (raw-DPS guard — catches over-tuned spd
                                 values that hide behind a legal damage_max)

Both caps come from A10 §R1 (number-ceiling enforcer) of the
2026-06-11 balance pass. The 220 figure is the explicit "cap to ship"
for 2H legendaries; the 245 DPS guard mirrors the existing 1H legendary
ceiling (demon_blade at 239) so a slow weapon can't sneak past by
trading speed for raw damage_max.

Why this exists: A1-ceiling-001 found `doomed_executioner` (dmax=305)
and `warlord_battle_axe` (dmax=298) breaching the 300-400 peak-hit
target before any affix landed. Without an automated tripwire the
design ceiling is honor-system; once the next content pass adds
weapons we need the guard already wired.

Exit code 0 = clean, 1 = at least one violation (suitable for pre-commit).

Usage:
  python3 tools/check_damage_ceiling.py
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
ITEMS_JSON = REPO / "project" / "data" / "items.json"

DAMAGE_MAX_CAP = 220
DPS_CAP = 245.0


def main() -> int:
    with ITEMS_JSON.open() as f:
        items_doc = json.load(f)

    weapons = [it for it in items_doc.get("items", []) if it.get("slot") == "weapon"]
    issues: list[str] = []

    for w in weapons:
        wid = w.get("id", "?")
        dmax = int(w.get("damage_max", 0))
        speed = float(w.get("speed", 1.0))
        if dmax > DAMAGE_MAX_CAP:
            issues.append(
                f"DAMAGE_MAX_OVER  {wid}  damage_max={dmax} (cap={DAMAGE_MAX_CAP})"
            )
        if speed > 0.0:
            dps = dmax / speed
            if dps > DPS_CAP:
                issues.append(
                    f"DPS_OVER         {wid}  damage_max/speed={dps:.1f} "
                    f"(dmax={dmax} speed={speed:.2f}, cap={DPS_CAP:.0f})"
                )

    if not issues:
        print(
            f"check_damage_ceiling: OK — {len(weapons)}/{len(weapons)} "
            f"weapons within damage_max={DAMAGE_MAX_CAP} / dps={DPS_CAP:.0f} caps."
        )
        return 0

    print(f"check_damage_ceiling: {len(issues)} violation(s) found.\n")
    for line in issues:
        print(" ", line)
    return 1


if __name__ == "__main__":
    sys.exit(main())
