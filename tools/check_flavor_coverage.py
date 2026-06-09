#!/usr/bin/env python3
# Flavor-coverage gate. Every flavor tag that appears in items.json or in
# enchant_combos.json's component pairs must also exist in:
#   - UITheme.FLAVOR_COLORS  (so the UI can color it)
#   - AffixSystem.ENCHANT_BLURBS  (so tooltips can describe it)
#
# Without this check it's easy to author a new flavor tag in items.json
# (or a combo component) and ship a black-on-black tooltip / un-described
# enchant. Audit 2026-06-09 found "lightning" in 3 items + 6 combo
# components clashing with "thunderous" everywhere else; this check
# would have surfaced that drift the day it landed.
#
# Exits 0 on pass, 1 on missing flavor coverage.

import json
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
PROJECT = REPO / "project"


def _parse_gd_dict_keys(path: Path, const_name: str) -> set[str]:
    text = path.read_text()
    m = re.search(rf"const\s+{re.escape(const_name)}\s*:=\s*\{{(.*?)^\}}",
                  text, re.DOTALL | re.MULTILINE)
    if not m:
        sys.exit(f"failed to find const {const_name} in {path}")
    body = m.group(1)
    # Strip line comments before key extraction.
    body = re.sub(r"#.*", "", body)
    keys = set(re.findall(r'"([^"]+)"\s*:', body))
    if not keys:
        sys.exit(f"const {const_name} parsed to zero keys — extractor regex out of date")
    return keys


def main() -> int:
    flavor_colors = _parse_gd_dict_keys(PROJECT / "scripts" / "ui_theme.gd", "FLAVOR_COLORS")
    enchant_blurbs = _parse_gd_dict_keys(PROJECT / "scripts" / "affix_system.gd", "ENCHANT_BLURBS")
    canonical = flavor_colors & enchant_blurbs

    items = json.loads((PROJECT / "data" / "items.json").read_text()).get("items", [])
    combos = json.loads((PROJECT / "data" / "enchant_combos.json").read_text()).get("combos", [])

    item_flavors: set[str] = set()
    for it in items:
        for tag in it.get("flavor_tags", []):
            item_flavors.add(str(tag))
    combo_components: set[str] = set()
    for c in combos:
        for cmp in c.get("components", []):
            combo_components.add(str(cmp))

    used = item_flavors | combo_components
    missing = sorted(used - canonical)

    if missing:
        print("FAIL: flavor coverage gap — these tags are used in items.json /", file=sys.stderr)
        print("enchant_combos.json but not in BOTH UITheme.FLAVOR_COLORS and", file=sys.stderr)
        print("AffixSystem.ENCHANT_BLURBS:", file=sys.stderr)
        for tag in missing:
            in_colors = "✓" if tag in flavor_colors else "✗"
            in_blurbs = "✓" if tag in enchant_blurbs else "✗"
            sources = []
            if tag in item_flavors:
                sources.append("items.json")
            if tag in combo_components:
                sources.append("enchant_combos.json")
            print(f"  {tag}  FLAVOR_COLORS={in_colors}  ENCHANT_BLURBS={in_blurbs}  used in: {', '.join(sources)}",
                  file=sys.stderr)
        return 1

    print(f"PASS — {len(used)} flavor tags used; {len(canonical)} canonical tags available.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
