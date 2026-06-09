#!/usr/bin/env python3
"""Export the SpellData.ARCHETYPES dict from spell_data.gd as JSON.

The build_matrix.html page and analyze_spell_dps_curve.py both need the
canonical archetype config (primary_stat, base damage, range, element,
cooldown). spell_data.gd is the source of truth — re-parsing it on every
tool launch invites drift. This script reads the GDScript constant and
writes the equivalent dict to project/data/spell_archetypes.json.

Run after editing spell_data.gd's ARCHETYPES const. Idempotent — same
input always produces same output.

Usage:
  python3 tools/dump_spell_archetypes.py
"""
from __future__ import annotations

import json
import re
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
SPELL_DATA_GD = REPO / "project" / "scripts" / "spell_data.gd"
OUT = REPO / "project" / "data" / "spell_archetypes.json"

# ARCHETYPES const block in spell_data.gd is a deterministic GDScript
# literal — no expressions, only string/int/float values. We can scrape
# each archetype's fields with simple regex.

_ARCH_BLOCK_RE = re.compile(
    r'"(spell_[a-z_]+)"\s*:\s*\{([^}]*)\}', re.DOTALL
)
_FIELD_RE = re.compile(r'"([a-z_]+)"\s*:\s*([^,#}]+?)\s*(?:,|\n|$)', re.DOTALL)


def _parse_value(raw: str):
    raw = raw.strip().rstrip(",").strip()
    # Strip trailing comments.
    if "#" in raw:
        raw = raw.split("#", 1)[0].strip()
    if raw.startswith('"') and raw.endswith('"'):
        return raw[1:-1]
    if raw in ("true", "false"):
        return raw == "true"
    try:
        if "." in raw:
            return float(raw)
        return int(raw)
    except ValueError:
        return raw


def main() -> int:
    text = SPELL_DATA_GD.read_text()
    # Slice out the const ARCHETYPES := { ... } body to limit regex scope.
    start = text.find("const ARCHETYPES := {")
    if start < 0:
        print("ARCHETYPES const not found in spell_data.gd")
        return 1
    end = text.find("\n}", start)
    body = text[start:end]

    archetypes: dict[str, dict] = {}
    for m in _ARCH_BLOCK_RE.finditer(body):
        arch_id = m.group(1)
        block = m.group(2)
        fields: dict = {}
        for fm in _FIELD_RE.finditer(block):
            key = fm.group(1)
            val = _parse_value(fm.group(2))
            fields[key] = val
        archetypes[arch_id] = fields

    OUT.write_text(json.dumps(archetypes, indent=2) + "\n")
    print(f"Wrote {len(archetypes)} archetypes → {OUT.relative_to(REPO)}")
    for aid, defn in archetypes.items():
        ps = defn.get("primary_stat", "?")
        dmg = defn.get("damage", "?")
        cd = defn.get("cooldown", "?")
        elem = defn.get("element", "")
        print(f"  {aid:30s} stat={ps} dmg={dmg} cd={cd}s element={elem!r}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
