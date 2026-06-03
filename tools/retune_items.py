#!/usr/bin/env python3
"""
Stat retune pass for items.json.

Algorithm:
1. Group all items by (base_type, item_tier).
2. For each group, compute the median atk/def/hp from existing data.
3. For groups missing data, interpolate: take the parent base_type's
   trend across other tiers and fill the gap.
4. Apply to each item:
   - If unique=true → leave alone (preserves authored spikes).
   - Else if existing stat >= median → leave alone (don't churn).
   - Else snap to median (lifts items below the floor).

Run from repo root:
    python3 tools/retune_items.py
"""

import json
import math
import statistics
from collections import defaultdict
from pathlib import Path

ITEMS = Path("project/data/items.json")

# Per-slot ramp factor when interpolating missing tiers. Each tier
# multiplies the previous by ~1.4 (matches the existing data's natural
# growth — short_sword T1 16 atk → T5 ~83, ratio ≈ 5x = 1.4^4).
TIER_RAMP_ATK = 1.4
TIER_RAMP_DEF = 1.4
TIER_RAMP_HP  = 1.4

# Number ceiling — never push a stat above these even if interpolation
# would suggest it (matches CLAUDE.md "no idle-game number creep").
ATK_CEIL = 110
DEF_CEIL = 30
HP_CEIL  = 320


def med(arr):
    """Median, preferring the lowest non-zero value when most are 0."""
    if not arr:
        return 0
    nz = [a for a in arr if a > 0]
    if not nz:
        return 0
    return int(round(statistics.median(nz)))


def interpolate(known: dict[int, int], target_tier: int, ramp: float) -> int:
    """Given known values keyed by tier (e.g. {1: 16, 4: 38, 5: 70}),
    return an interpolated value for target_tier following the ramp."""
    if target_tier in known and known[target_tier] > 0:
        return known[target_tier]
    if not any(v > 0 for v in known.values()):
        return 0
    # Find nearest known tier on each side.
    sorted_known = sorted([(t, v) for t, v in known.items() if v > 0])
    if not sorted_known:
        return 0
    # Interpolate or extrapolate by ramp.
    closest = min(sorted_known, key=lambda kv: abs(kv[0] - target_tier))
    delta_tiers = target_tier - closest[0]
    val = closest[1] * (ramp ** delta_tiers)
    return int(round(val))


def main():
    data = json.loads(ITEMS.read_text())
    items = data["items"]

    # Group existing data.
    groups: dict[tuple, dict[str, list]] = defaultdict(lambda: {"atk": [], "def": [], "hp": []})
    for it in items:
        if it.get("unique"):
            continue  # uniques don't contribute to the median
        key = (it.get("base_type", "?"), int(it.get("item_tier", 0)))
        groups[key]["atk"].append(int(it.get("atk", 0) or 0))
        groups[key]["def"].append(int(it.get("def", 0) or 0))
        groups[key]["hp"].append(int(it.get("hp", 0) or 0))

    # Compute medians per group.
    medians: dict[tuple, dict[str, int]] = {}
    for key, vals in groups.items():
        medians[key] = {
            "atk": med(vals["atk"]),
            "def": med(vals["def"]),
            "hp": med(vals["hp"]),
        }

    # Build per-base_type tier maps for interpolation.
    by_bt: dict[str, dict[int, dict[str, int]]] = defaultdict(dict)
    for (bt, tier), m in medians.items():
        by_bt[bt][tier] = m

    # Apply: lift items below the median.
    fixed_atk = fixed_def = fixed_hp = 0
    skipped_unique = 0
    for it in items:
        if it.get("unique"):
            skipped_unique += 1
            continue
        bt = it.get("base_type", "?")
        tier = int(it.get("item_tier", 0))
        if bt not in by_bt:
            continue
        m = by_bt[bt].get(tier)
        if m is None:
            # Interpolate from neighboring tiers in the same base_type.
            atk_known = {t: v["atk"] for t, v in by_bt[bt].items()}
            def_known = {t: v["def"] for t, v in by_bt[bt].items()}
            hp_known  = {t: v["hp"]  for t, v in by_bt[bt].items()}
            m = {
                "atk": min(ATK_CEIL, interpolate(atk_known, tier, TIER_RAMP_ATK)),
                "def": min(DEF_CEIL, interpolate(def_known, tier, TIER_RAMP_DEF)),
                "hp":  min(HP_CEIL,  interpolate(hp_known,  tier, TIER_RAMP_HP)),
            }
        # Lift only — don't churn already-strong items down.
        cur_atk = int(it.get("atk", 0) or 0)
        cur_def = int(it.get("def", 0) or 0)
        cur_hp  = int(it.get("hp", 0) or 0)
        if m["atk"] > 0 and cur_atk < m["atk"]:
            it["atk"] = m["atk"]
            fixed_atk += 1
        if m["def"] > 0 and cur_def < m["def"]:
            it["def"] = m["def"]
            fixed_def += 1
        if m["hp"] > 0 and cur_hp < m["hp"]:
            it["hp"] = m["hp"]
            fixed_hp += 1

    ITEMS.write_text(json.dumps(data, indent=2) + "\n")
    print(f"lifted: atk {fixed_atk}, def {fixed_def}, hp {fixed_hp}")
    print(f"skipped uniques: {skipped_unique}")


if __name__ == "__main__":
    main()
