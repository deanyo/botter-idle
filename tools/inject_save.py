#!/usr/bin/env python3
"""inject_save.py — Write a build spec to the debug save state.

Used by the /equip skill (and ad-hoc balance experiments) to deterministically
set up a bot loadout before launching a /grind. Writes to
botter_save_debug.json so live playtest saves are untouched.

Usage:

    python3 tools/inject_save.py spec.json
    python3 tools/inject_save.py - <<EOF              # stdin JSON
    {"equipped":{"weapon":{"base_id":"demon_blade","affixes":[["strength",5],["crit",4]]}}}
    EOF

Spec fields (all optional — unspecified fields keep their current value or
the schema default for fresh saves):

    level, gold, xp           — bot stats
    max_revives               — death-retreat budget
    loot_filter               — "common".."legendary"
    inventory_cap             — auto-salvage threshold
    unlocked_branches         — array of branch ids
    bosses_killed             — {branch_id: count}
    bot_upgrades              — {upgrade_id: rank}
    branch_modifiers          — {branch_id: [mod_id, ...]}
    equipped                  — {slot: item_spec | null} (see below)
    inventory                 — array of item_specs

item_spec shapes (anything missing fills with sensible defaults):

    "demon_blade"                       # bare id, no affixes
    {"base_id":"demon_blade"}           # explicit, no affixes
    {"base_id":"demon_blade",
     "affixes":[["strength",5],         # affixes by tier-index (1..5)
                ["crit",4]]}            # tier 5 = legendary, 4 = epic, ...
    {"base_id":"demon_blade",
     "affixes":[{"id":"strength","value":18}]}  # explicit value override

The tier-index form ([affix_id, tier]) reads the actual `value` from
data/affixes.json so spec authors don't have to hardcode legendary=18 etc.

Validation:

  - Every base_id must exist in project/data/items.json.
  - Every affix id must exist in project/data/affixes.json.
  - Every tier must be 1..5.
  - Every branch must exist in project/data/biomes.json.
  - Slots must be one of weapon/armor/helm/boots/shield/ring/amulet.

Run from the repo root.
"""

import argparse
import json
import sys
from pathlib import Path
from time import time

REPO_ROOT = Path(__file__).resolve().parent.parent
ITEMS_JSON = REPO_ROOT / "project" / "data" / "items.json"
AFFIXES_JSON = REPO_ROOT / "project" / "data" / "affixes.json"
BIOMES_JSON = REPO_ROOT / "project" / "data" / "biomes.json"

USER_DATA = Path.home() / "Library" / "Application Support" / "Godot" / "app_userdata" / "Botter"
DEBUG_SAVE = USER_DATA / "botter_save_debug.json"

VALID_SLOTS = {"weapon", "armor", "helm", "boots", "shield", "gloves", "cloak", "ring", "amulet",
               "spell1", "spell2", "spell3", "spell4", "spell5"}
VALID_RARITIES = ("common", "uncommon", "rare", "epic", "legendary")


def load_dbs():
    items = {it["id"]: it for it in json.load(ITEMS_JSON.open())["items"]}
    affixes_doc = json.load(AFFIXES_JSON.open())
    affixes = {a["id"]: a for a in affixes_doc["affixes"]}
    # biomes.json shape: {"biomes": {<id>: {...}, ...}, "run_plans": ...}
    biomes = json.load(BIOMES_JSON.open())["biomes"]
    return items, affixes, biomes


def normalize_affix(spec, affixes):
    """Accept ["strength", 5] OR {"id":"strength","value":18} OR {"id":"strength","tier":5}."""
    if isinstance(spec, list):
        if len(spec) != 2:
            raise ValueError(f"affix list form must be [id, tier]: {spec!r}")
        afx_id, tier = spec[0], int(spec[1])
        return _affix_from_tier(afx_id, tier, affixes)
    if isinstance(spec, dict):
        if "value" in spec:
            return {"id": spec["id"], "value": int(spec["value"])}
        if "tier" in spec:
            return _affix_from_tier(spec["id"], int(spec["tier"]), affixes)
    raise ValueError(f"unrecognized affix spec: {spec!r}")


def _affix_from_tier(afx_id, tier, affixes):
    if afx_id not in affixes:
        raise ValueError(f"unknown affix id: {afx_id!r} (valid: {sorted(affixes)})")
    if not (1 <= tier <= 5):
        raise ValueError(f"affix tier must be 1..5, got {tier}")
    tiers = affixes[afx_id]["tiers"]
    return {"id": afx_id, "value": int(tiers[tier - 1])}


def normalize_item(spec, items, affixes):
    """Accept "id_string" OR {"base_id": ..., "affixes": [...]}."""
    if spec is None:
        return None
    if isinstance(spec, str):
        spec = {"base_id": spec}
    base_id = spec["base_id"]
    if base_id not in items:
        raise ValueError(f"unknown item id: {base_id!r}")
    inst = {
        "base_id": base_id,
        "instance_id": spec.get("instance_id", f"injected_{int(time()*1000)}_{base_id}"),
        "affixes": [normalize_affix(a, affixes) for a in spec.get("affixes", [])],
    }
    if "tile_override" in spec:
        inst["tile_override"] = spec["tile_override"]
    return inst


def _default_character():
    return {
        "species": "spriggan",
        "gold": 0,
        "level": 1,
        "xp": 0,
        "inventory": [],
        "equipped": {
            "weapon": None, "armor": None, "helm": None,
            "boots": None, "shield": None,
            "gloves": None, "cloak": None,
            "ring": None, "amulet": None,
            "spell1": None, "spell2": None, "spell3": None,
            "spell4": None, "spell5": None,
        },
        "runs_completed": 0,
        "highest_floor": 0,
        "unlocked_branches": ["dungeon"],
        "bosses_killed": {},
        "max_revives": 3,
        "loot_filter": "common",
        "inventory_cap": 50,
        "last_branch": "",
        "branch_modifiers": {},
        "bot_upgrades": {},
        "shards": 0,
        "last_seen_timestamp": 0,
    }


def load_existing():
    """Returns the ACTIVE character dict from the save wrapper.
    Save schema (post-2026-06-04) is {characters:[...], active:int}; legacy
    pre-wrapper saves are auto-wrapped on load. Inject mutates the active
    character; save_existing() writes the wrapper back."""
    if not DEBUG_SAVE.exists():
        return _default_character()
    raw = json.load(DEBUG_SAVE.open())
    if isinstance(raw, dict) and "characters" in raw and isinstance(raw["characters"], list):
        chars = raw["characters"]
        active = int(raw.get("active", 0))
        if 0 <= active < len(chars):
            return chars[active]
        return chars[0] if chars else _default_character()
    # Legacy single-character save — operate on it directly. save_existing
    # below will wrap it for Godot.
    return raw


def save_existing(state):
    """Write `state` back as the active character inside the wrapper."""
    USER_DATA.mkdir(parents=True, exist_ok=True)
    if DEBUG_SAVE.exists():
        try:
            raw = json.load(DEBUG_SAVE.open())
        except Exception:
            raw = None
    else:
        raw = None
    if isinstance(raw, dict) and "characters" in raw and isinstance(raw["characters"], list):
        chars = raw["characters"]
        active = int(raw.get("active", 0))
        if 0 <= active < len(chars):
            chars[active] = state
        else:
            chars[0] = state
        wrapper = {"characters": chars, "active": active if 0 <= active < len(chars) else 0}
    else:
        wrapper = {"characters": [state], "active": 0}
    with DEBUG_SAVE.open("w") as f:
        json.dump(wrapper, f, indent=2)
        f.write("\n")


def apply_spec(state, spec, items, affixes, biomes):
    # Scalar fields — copy through if present.
    for k in ("level", "gold", "xp", "max_revives", "loot_filter",
              "inventory_cap", "last_branch", "species"):
        if k in spec:
            state[k] = spec[k]
    # Branch fields.
    if "unlocked_branches" in spec:
        for b in spec["unlocked_branches"]:
            if b not in biomes:
                raise ValueError(f"unknown branch id: {b!r}")
        state["unlocked_branches"] = list(spec["unlocked_branches"])
    if "bosses_killed" in spec:
        state["bosses_killed"] = dict(spec["bosses_killed"])
    if "bot_upgrades" in spec:
        state["bot_upgrades"] = dict(spec["bot_upgrades"])
    if "branch_modifiers" in spec:
        state["branch_modifiers"] = {k: list(v) for k, v in spec["branch_modifiers"].items()}
    # Equipped — apply caller's slots, then null any VALID_SLOTS the
    # caller didn't mention so a follow-up inject doesn't carry over
    # state from the previous spec. Without this, repeated injects
    # accumulate gear from the last run, which made smoke tests lie
    # about which spells were actually equipped.
    if "equipped" in spec:
        equipped = state.setdefault("equipped", {})
        for slot, item_spec in spec["equipped"].items():
            if slot not in VALID_SLOTS:
                raise ValueError(f"unknown slot: {slot!r} (valid: {sorted(VALID_SLOTS)})")
            equipped[slot] = normalize_item(item_spec, items, affixes)
        for slot in VALID_SLOTS:
            if slot not in spec["equipped"]:
                equipped[slot] = None
    # Inventory.
    if "inventory" in spec:
        state["inventory"] = [normalize_item(it, items, affixes) for it in spec["inventory"]]


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("spec", help="Path to JSON spec, or '-' for stdin.")
    parser.add_argument("--reset", action="store_true",
                        help="Start from a fresh default save instead of merging "
                             "into the existing botter_save_debug.json.")
    parser.add_argument("--dry-run", action="store_true",
                        help="Print resolved save without writing.")
    args = parser.parse_args()

    items, affixes, biomes = load_dbs()

    if args.spec == "-":
        spec = json.load(sys.stdin)
    else:
        spec = json.load(open(args.spec))

    if args.reset and DEBUG_SAVE.exists():
        DEBUG_SAVE.unlink()
    state = load_existing()
    apply_spec(state, spec, items, affixes, biomes)

    if args.dry_run:
        print(json.dumps(state, indent=2))
        return 0

    save_existing(state)
    # Compact summary so logs read clearly when chained from a skill.
    eq = state.get("equipped", {})
    eq_summary = ", ".join(
        f"{k}={(v or {}).get('base_id', '-')}"
        + (f"[{','.join(a['id'] for a in (v or {}).get('affixes', []))}]"
           if v and v.get("affixes") else "")
        for k, v in eq.items() if v is not None
    ) or "(none)"
    print(f"wrote {DEBUG_SAVE}")
    print(f"  level={state['level']} gold={state['gold']} branches={state['unlocked_branches']}")
    print(f"  equipped: {eq_summary}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
