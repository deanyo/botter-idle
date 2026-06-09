#!/usr/bin/env python3
"""Cross-reference affixes.json × items.json × stat_calc.gd × spell_data.gd.

Reports the four classes of bugs that the audit (item-and-balance pass,
2026-06-09) found surface together:

  - duplicate affix ids in affixes.json
  - never-rolled affixes (defined in affixes.json, in 0 items' affix_pool)
  - orphan stat keys (affix.stat written but never read by stat_calc.gd
    or spell_data.gd)
  - near-zero tier ranges ([0,0] floors that produce "+0 Foo" tooltip
    noise per PLAYTEST #9)
  - base_type_affixes.json keys that don't resolve to a known affix-id
    (after category-alias expansion)
  - items.json affix_pool entries referencing unknown affix ids

Exit code 0 = clean, 1 = at least one issue (suitable for pre-commit).

Usage:
  python3 tools/audit_data_integrity.py            # report-only
  python3 tools/audit_data_integrity.py --strict   # fail-fast for CI
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
DATA = REPO / "project" / "data"
SCRIPTS = REPO / "project" / "scripts"

AFFIXES_JSON = DATA / "affixes.json"
ITEMS_JSON = DATA / "items.json"
BASE_TYPE_AFFIXES_JSON = DATA / "base_type_affixes.json"
STAT_CALC_GD = SCRIPTS / "stat_calc.gd"
SPELL_DATA_GD = SCRIPTS / "spell_data.gd"
AFFIX_SYSTEM_GD = SCRIPTS / "affix_system.gd"

# Categories accepted in base_type_affixes.json — must match the
# _CATEGORY_EXPANSION dict in scripts/affix_system.gd. Keep in sync.
KNOWN_CATEGORIES = {"crit", "haste", "strength", "agility", "stamina", "regen"}


def _load_json(p: Path):
    with p.open() as f:
        return json.load(f)


def main() -> int:
    issues: list[str] = []
    warnings: list[str] = []

    affixes_doc = _load_json(AFFIXES_JSON)
    items_doc = _load_json(ITEMS_JSON)
    base_type_doc = _load_json(BASE_TYPE_AFFIXES_JSON)

    stat_calc_text = STAT_CALC_GD.read_text()
    spell_data_text = SPELL_DATA_GD.read_text()
    combined_compute = stat_calc_text + "\n" + spell_data_text

    affixes = affixes_doc.get("affixes", [])

    # ── 1. Duplicate ids ────────────────────────────────────────────
    seen: dict[str, int] = {}
    for af in affixes:
        seen[af["id"]] = seen.get(af["id"], 0) + 1
    for af_id, count in seen.items():
        if count > 1:
            issues.append(
                f"DUP_AFFIX_ID  {af_id}  defined {count}× in affixes.json"
            )

    affix_ids = set(seen.keys())

    # ── 2. Near-zero tier ranges ────────────────────────────────────
    for af in affixes:
        af_id = af["id"]
        kind = af.get("kind", "flat")
        # Flag-kind affixes intentionally roll [1,1] — those aren't ranges.
        if kind == "flag":
            continue
        for i, t in enumerate(af.get("tiers", [])):
            if isinstance(t, list) and len(t) >= 2:
                lo, hi = int(t[0]), int(t[1])
                if lo == 0 and hi == 0:
                    rar = ["common", "uncommon", "rare", "epic", "legendary"][i]
                    issues.append(
                        f"NEAR_ZERO_TIER  {af_id}  {rar}=[0,0] — produces +0 "
                        f"tooltip noise (raise floor to [1,1] or denylist)"
                    )

    # ── 3. Never-rolled affixes ─────────────────────────────────────
    rolled_ids: set[str] = set()
    for it in items_doc.get("items", []):
        pool = it.get("affix_pool")
        if isinstance(pool, dict):
            for k in pool.keys():
                rolled_ids.add(k)
        for af_id in it.get("implicit_affixes", []):
            rolled_ids.add(af_id)
    # Archetype family is referenced by spell flag-implicits — its rolling
    # path is implicit_affixes only. Skip the per-id "never rolled" check
    # for archetype-family affixes since they're not pool-rolled by design.
    for af in affixes:
        af_id = af["id"]
        if af.get("family") == "archetype":
            continue
        if af_id not in rolled_ids:
            issues.append(
                f"NEVER_ROLLED   {af_id}  defined but absent from every "
                f"item's affix_pool / implicit_affixes"
            )

    # ── 4. Orphan stat keys ─────────────────────────────────────────
    # An affix.stat is "orphaned" if neither stat_calc.gd nor spell_data.gd
    # references it. Bonus_min/max keys derived from a `range` affix are
    # auto-created by _scaled_affix_sums; skip those.
    for af in affixes:
        af_id = af["id"]
        stat = af.get("stat", "")
        if not stat:
            continue
        # archetype flag stats are pure markers consumed by spell_system —
        # treat any reference to the literal stat key in scripts/ as a hit.
        # We grep across the entire scripts dir for a permissive read check.
        if af.get("family") == "archetype":
            hit = False
            for gd in SCRIPTS.glob("*.gd"):
                if stat in gd.read_text():
                    hit = True
                    break
            if not hit:
                issues.append(
                    f"ORPHAN_STAT    {af_id}  archetype flag stat '{stat}' "
                    f"never referenced under scripts/"
                )
            continue
        # Generic / class affixes are read in stat_calc + spell_data.
        if stat in combined_compute:
            continue
        # Range affixes synthesize sums[stat], sums[stat+'_min'], sums[stat+'_max'].
        # The base "physical_extra" key may not appear directly but the
        # element-loop iterates ELEMENTS and accumulates extra_damage[elem]
        # via "<elem>_extra". Accept that as a wired read.
        if af.get("kind") == "range":
            base = stat.replace("_extra", "")
            element_loop = '"physical", "fire", "cold", "lightning", "holy", "poison", "dark"'
            if (
                base in ("physical", "fire", "cold", "lightning", "holy", "poison", "dark")
                and element_loop in combined_compute
            ):
                continue
        # Element-pct + element-resist stats are read via element loops in
        # stat_calc.gd ("for elem in ELEMENTS" and similar), not by literal
        # key name. If the stat key matches "<element>_dmg_pct" or
        # "<element>_res" and the corresponding loop pattern is in
        # stat_calc.gd, count it as wired.
        if stat.endswith("_dmg_pct"):
            elem = stat[: -len("_dmg_pct")]
            if elem in ("fire", "cold", "thunderous", "holy", "poison", "dark"):
                # stat_calc.gd lines 184-188: per-element loop
                if 'elem + "_dmg_pct"' in combined_compute or "elem + '_dmg_pct'" in combined_compute:
                    continue
        if stat.endswith("_res"):
            elem = stat[: -len("_res")]
            if elem in ("fire", "cold", "lightning", "holy", "poison", "dark", "physical"):
                if 'elem + "_res"' in combined_compute or "elem + '_res'" in combined_compute:
                    continue
        issues.append(
            f"ORPHAN_STAT    {af_id}  writes '{stat}' but no compute path "
            f"reads it (stat_calc.gd / spell_data.gd)"
        )

    # ── 5. base_type_affixes references ─────────────────────────────
    base_types = base_type_doc.get("base_types", {})
    for bt, weights in base_types.items():
        for key in weights.keys():
            if key in KNOWN_CATEGORIES:
                continue
            if key in affix_ids:
                continue
            issues.append(
                f"UNKNOWN_BT_KEY base_type_affixes.json {bt!r} → key "
                f"{key!r} is neither a known category nor an affix id"
            )

    # ── 6. items.json affix_pool references ─────────────────────────
    for it in items_doc.get("items", []):
        pool = it.get("affix_pool")
        if not isinstance(pool, dict):
            continue
        item_id = it.get("id", "?")
        for af_id in pool.keys():
            if af_id not in affix_ids:
                issues.append(
                    f"UNKNOWN_POOL   item {item_id!r} references unknown "
                    f"affix id {af_id!r}"
                )

    # ── 6b. recolor_of references resolve ───────────────────────────
    items_by_id = {it.get("id"): it for it in items_doc.get("items", [])}
    for it in items_doc.get("items", []):
        root = it.get("recolor_of")
        if not root:
            continue
        item_id = it.get("id", "?")
        if root not in items_by_id:
            issues.append(
                f"UNKNOWN_RECOLOR item {item_id!r} recolor_of {root!r} "
                f"does not exist in items.json"
            )
            continue
        if items_by_id[root].get("slot") != it.get("slot"):
            issues.append(
                f"RECOLOR_SLOT   item {item_id!r} slot mismatch with "
                f"recolor_of {root!r}"
            )

    # ── 6c. Per slot×tier design diversity (recolor-aware) ──────────
    # Per a04 §9.4: collapse recolor twins to their root when counting
    # distinct designs. Warn (non-fatal) when a (slot, item_tier) cell
    # has < 3 distinct non-unique designs after recolor collapse —
    # the build matrix gets thin there.
    cells: dict[tuple[str, int], set[str]] = {}
    for it in items_doc.get("items", []):
        if it.get("unique"):
            continue
        slot = it.get("slot", "")
        tier = int(it.get("item_tier", 0) or 0)
        if not slot or tier == 0:
            continue
        canonical = it.get("recolor_of") or it.get("id")
        cells.setdefault((slot, tier), set()).add(canonical)
    for (slot, tier), designs in sorted(cells.items()):
        if len(designs) < 3:
            warnings.append(
                f"THIN_DESIGNS   slot={slot!r} tier={tier} has "
                f"{len(designs)} distinct non-unique design(s) post-recolor "
                f"collapse (target ≥3)"
            )

    # ── 7. Sanity: KNOWN_CATEGORIES match affix_system.gd ───────────
    # Read the GD source and pull the exact dict so the linter doesn't
    # drift behind code edits.
    gd_text = AFFIX_SYSTEM_GD.read_text()
    # Pull the block from `_CATEGORY_EXPANSION := {` to its matching close
    # brace. Naive brace counting is good enough for a static dict.
    block: str | None = None
    start = gd_text.find("_CATEGORY_EXPANSION")
    if start != -1:
        brace = gd_text.find("{", start)
        if brace != -1:
            depth = 0
            i = brace
            while i < len(gd_text):
                if gd_text[i] == "{":
                    depth += 1
                elif gd_text[i] == "}":
                    depth -= 1
                    if depth == 0:
                        block = gd_text[brace : i + 1]
                        break
                i += 1
    if block is not None:
        gd_categories = set(re.findall(r'"([a-z_]+)":\s*\{', block))
        if gd_categories and gd_categories != KNOWN_CATEGORIES:
            extra = gd_categories - KNOWN_CATEGORIES
            missing = KNOWN_CATEGORIES - gd_categories
            issues.append(
                "CATEGORY_DRIFT linter KNOWN_CATEGORIES disagrees with "
                f"affix_system.gd _CATEGORY_EXPANSION (gd has extra {extra}, "
                f"missing {missing}). Update one to match the other."
            )

    # ── Report ──────────────────────────────────────────────────────
    if warnings:
        print(f"audit_data_integrity: {len(warnings)} warning(s) (non-fatal).\n")
        for line in warnings:
            print(" ", line)
        print()
    if not issues:
        print("audit_data_integrity: OK — no issues found.")
        return 0

    print(f"audit_data_integrity: {len(issues)} issue(s) found.\n")
    for line in issues:
        print(" ", line)
    return 1


if __name__ == "__main__":
    sys.exit(main())
