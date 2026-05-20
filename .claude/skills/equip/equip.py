#!/usr/bin/env python3
"""equip.py — Shorthand build-spec parser → debug save.

Args: a single string with space-separated `slot=value[,affix1,affix2,...]`
tokens, plus optional level=N gold=N branch=branch_id mods=mod1+mod2.

Examples:

    weapon=demon_blade,Strength5,Crit4 armor=crystal_plate,Stamina5
    weapon=rusty_dagger level=1 gold=0
    weapon=singing_sword,Strength5,Haste5 helm=cornuthaum boots=fencer_slippers
    branch=forge mods=bloodlust+crowded level=30 gold=5000

Affix shorthand: <Name><Tier> where Name is title-case (Strength, Stamina,
Agility, Regen, Crit, Haste) and Tier is 1..5 (1=common, 5=legendary). Reads
the value from data/affixes.json — no need to hardcode legendary=18.

If you pass a single arg starting with '{' it's parsed as a JSON spec
(passed straight to inject_save.py).
"""

from __future__ import annotations
import json
import re
import shlex
import subprocess
import sys
from pathlib import Path
from typing import Optional

REPO_ROOT = Path(__file__).resolve().parent.parent.parent.parent
INJECT = REPO_ROOT / "tools" / "inject_save.py"

VALID_SLOTS = {"weapon", "armor", "helm", "boots", "shield", "ring1", "ring2", "amulet"}
SCALAR_KEYS = {"level", "gold", "xp", "max_revives", "loot_filter",
               "inventory_cap", "branch", "mods"}

AFFIX_NAMES = {
    "strength", "stamina", "agility", "regen", "crit", "haste",
    "str", "sta", "agi", "reg", "cri", "has",
}
_AFFIX_ALIASES = {"str": "strength", "sta": "stamina", "agi": "agility",
                  "reg": "regen", "cri": "crit", "has": "haste"}


def parse_affix_token(tok: str) -> list[str | int] | None:
    """Parse 'Strength5' or 'crit-4' or 'Sta3' → [affix_id, tier_int]."""
    m = re.match(r"^([A-Za-z]+)[-_]?(\d)$", tok)
    if not m:
        return None
    name = m.group(1).lower()
    name = _AFFIX_ALIASES.get(name, name)
    if name not in AFFIX_NAMES:
        return None
    tier = int(m.group(2))
    if not (1 <= tier <= 5):
        return None
    return [name, tier]


def parse_args(argv: list[str]) -> dict:
    """Returns inject_save.py-shaped JSON spec."""
    spec: dict = {"equipped": {}}

    for tok in argv:
        if "=" not in tok:
            raise SystemExit(f"unrecognized token (no '='): {tok!r}")
        key, _, val = tok.partition("=")
        key = key.strip()
        val = val.strip()

        if key in VALID_SLOTS:
            # value: <base_id>[,<affix>...]
            parts = [p.strip() for p in val.split(",") if p.strip()]
            if not parts:
                spec["equipped"][key] = None
                continue
            base_id = parts[0]
            affixes = []
            for af in parts[1:]:
                p = parse_affix_token(af)
                if p is None:
                    raise SystemExit(
                        f"affix token {af!r} not recognized (try Strength5, "
                        f"Crit4, Stamina3 etc; affix=strength|stamina|agility|"
                        f"regen|crit|haste; tier=1..5)"
                    )
                affixes.append(p)
            spec["equipped"][key] = {"base_id": base_id, "affixes": affixes}
            continue

        if key == "level":
            spec["level"] = int(val)
        elif key == "gold":
            spec["gold"] = int(val)
        elif key == "xp":
            spec["xp"] = int(val)
        elif key == "max_revives":
            spec["max_revives"] = int(val)
        elif key == "loot_filter":
            spec["loot_filter"] = val
        elif key == "inventory_cap":
            spec["inventory_cap"] = int(val)
        elif key == "branch":
            # branch=forge → unlock forge + dungeon (always unlocked).
            unlocked = ["dungeon"]
            if val and val != "dungeon":
                unlocked.append(val)
            spec["unlocked_branches"] = unlocked
            spec["last_branch"] = val
        elif key == "mods":
            # mods=a+b → branch_modifiers[<branch>] = [a, b]
            mod_list = [m.strip() for m in val.split("+") if m.strip()]
            branch = spec.get("last_branch", "dungeon")
            spec.setdefault("branch_modifiers", {})[branch] = mod_list
        else:
            raise SystemExit(
                f"unknown key: {key!r} (slots: {sorted(VALID_SLOTS)}, "
                f"scalars: {sorted(SCALAR_KEYS)})"
            )

    return spec


def main():
    argv = sys.argv[1:]
    if not argv:
        print(__doc__)
        return 1

    # JSON passthrough mode: single arg starting with '{'.
    raw = " ".join(argv).strip()
    if raw.startswith("{"):
        spec_str = raw
    else:
        spec = parse_args(shlex.split(raw))
        spec_str = json.dumps(spec)

    res = subprocess.run([sys.executable, str(INJECT), "--reset", "-"],
                         input=spec_str.encode())
    return res.returncode


if __name__ == "__main__":
    sys.exit(main())
