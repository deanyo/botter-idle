#!/usr/bin/env python3
"""
Build project/data/tile_atlas.json from DCSS rltiles source.

Walks all dc-*.txt files in dcss-source/.../rltiles, parses the rltiles DSL
to extract category, ENUM, variant info per tile, then unions with a
filesystem walk of dcss/Dungeon Crawl Stone Soup Full/ + Supplemental/ to
emit a complete catalog of every PNG present in the tile packs.

The rltiles grammar (relevant subset):
    %name <category>            sets the parser's category context
    %sdir <subdir>              sets the source directory (relative)
    %weight <n>                 next tile's weight; %weight resets per-line
    %rim <0|1>                  cosmetic, ignored
    %lum/%hue/%desat/%resetcol  colour transforms, ignored for catalog
    %back <tile-name>...        defines fallback tiles, ignored for catalog
    %compose <tile-name>        composes onto another, ignored
    %variation <ENUM> <suffix>  next entry is a variation
    %enchant_variation <ENUM> <suffix>...   next tile is enchant variant
    %parts_ctg <NAME>           player paperdoll part category
    %end_ctg                    ends paperdoll category
    %include <file>             include another dc-*.txt
    %start <name>               named group
    %finish                     end named group

A tile line has the shape:
    <filename> [<ENUM_NAME> [<MORE_ENUMS>...]]

If ENUM is omitted, the tile is a variant of the previous ENUM in the same
group. Most weight/variant tiles look like:
    snake_0 FLOOR_SNAKE FLOOR_NORMAL
    snake_1
    snake_2
    ...

We collect:
  - filename (no extension)
  - directory (from %sdir)
  - enum (primary)
  - extra_enums (synonym ENUMs)
  - category (high-level: floor/wall/feat/item/monster/player/effect/...)
  - subcategory (parts_ctg or item-subdir or sdir tail)
  - is_variant (no ENUM on its own line; variant of preceding tile)
  - variation_of (parent ENUM, when this is a %variation)
  - variation_suffix (e.g. 'shiny','runed','glowing','randart','red','blue')
  - weight
  - directional (filename ends with _north/_south/_east/_west/_corner/_edge/_overlay)

Then we do filesystem-side enrichment: every PNG in dcss/.../Full/ and
Supplemental/ that wasn't matched by the rltiles parse gets a best-effort
classification from path + filename heuristics.

Finally we tag biome and class hints based on patterns.
"""

from __future__ import annotations

import json
import os
import re
import sys
from collections import defaultdict
from pathlib import Path
from typing import Optional, Tuple, Dict, List

DCSS_SOURCE = Path("/Users/dyo/claude/botter/dcss-source/crawl-ref/source/rltiles")
DCSS_FULL = Path("/Users/dyo/claude/botter/dcss/Dungeon Crawl Stone Soup Full")
DCSS_SUPP = Path("/Users/dyo/claude/botter/dcss/Dungeon Crawl Stone Soup Supplemental")
# Project-local sprite tree — surfaces our species portraits + spell
# tomes + slot icons in the atlas viewer so the authoring portal can
# browse them. Combat pivot 2026-06-04.
PROJECT_ASSETS = Path("/Users/dyo/claude/botter/project/assets/tiles")
OUTPUT = Path("/Users/dyo/claude/botter/project/data/tile_atlas.json")

# Top-level dc-*.txt files (each defines a category).
TOP_FILES = {
    "dc-floor.txt":      "floor",
    "dc-wall.txt":       "wall",
    "dc-feat.txt":       "feat",
    "dc-item.txt":       "item",
    "dc-mon.txt":        "monster",
    "dc-player.txt":     "player",
    "dc-main.txt":       "main",
    "dc-misc.txt":       "misc",
    "dc-gui.txt":        "gui",
    "dc-spells.txt":     "spell",
    "dc-skills.txt":     "skill",
    "dc-abilities.txt":  "ability",
    "dc-commands.txt":   "command",
    "dc-corpse.txt":     "corpse",
    "dc-demon.txt":      "demon",
    "dc-icons.txt":      "icon",
    "dc-invocations.txt":"invocation",
    "dc-mutations.txt":  "mutation",
    "dc-tentacles.txt":  "tentacle",
    "dc-zombie.txt":     "zombie",
}

# Biome detection. Patterns are tested as filename-prefix or path-substring.
# Order matters: more specific first. A list of (pattern, biome, kind):
#   kind="dir"   substring match in full path
#   kind="prefix" filename starts with this
#   kind="contains" substring of filename anywhere
BIOME_HINTS = [
    # Directory-anchored
    ("dungeon/wall/abyss",   "abyss",        "dir"),
    ("dungeon/wall/orc",     "orc",          "dir"),
    ("dungeon/floor/grass",  "lair",         "dir"),
    ("dungeon/floor/sigils", "vaults",       "dir"),
    ("monster/abyss",        "abyss",        "dir"),
    ("monster/demonspawn",   "forge",        "dir"),
    ("monster/demons",       "forge",        "dir"),
    ("monster/draconic",     "zot",          "dir"),
    ("monster/dragons",      "zot",          "dir"),
    ("monster/holy",         "vaults",       "dir"),
    ("monster/aquatic",      "shoals",       "dir"),
    ("monster/spriggan",     "lair",         "dir"),
    ("monster/fungi_plants", "lair",         "dir"),
    # Filename-prefix (most reliable for biome floor/wall sets)
    ("lair",                 "lair",         "prefix"),
    ("swamp",                "swamp",        "prefix"),
    ("snake",                "snake",        "prefix"),
    ("shoals",               "shoals",       "prefix"),
    ("spider",               "spider",       "prefix"),
    ("forest",               "forest",       "prefix"),
    ("orc",                  "orc",          "prefix"),
    ("mines",                "mines",        "prefix"),
    ("vaults",               "vaults",       "prefix"),
    ("crypt",                "crypt",        "prefix"),
    ("tomb",                 "tomb",         "prefix"),
    ("elf",                  "elf",          "prefix"),
    ("zot",                  "zot",          "prefix"),
    ("depths",               "depths",       "prefix"),
    ("slime",                "slime",        "prefix"),
    ("hive",                 "hive",         "prefix"),
    ("abyss",                "abyss",        "prefix"),
    ("pan",                  "pandemonium",  "prefix"),
    ("labyrinth",            "labyrinth",    "prefix"),
    ("temple",               "temple",       "prefix"),
    ("forge",                "forge",        "prefix"),
    ("glacier",              "glacier",      "prefix"),
    ("infernal",             "forge",        "prefix"),
    ("volcanic",             "forge",        "prefix"),
    ("demonic",              "forge",        "prefix"),
    ("frozen",               "glacier",      "prefix"),
    ("ice",                  "glacier",      "prefix"),
    ("hell",                 "forge",        "prefix"),
    ("acidic",               "slime",        "prefix"),
    ("ooze",                 "slime",        "prefix"),
    ("mosaic",               "vaults",       "prefix"),
    ("sandstone",            "tomb",         "prefix"),
    ("bog",                  "swamp",        "prefix"),
    ("mud",                  "swamp",        "prefix"),
    ("moss",                 "lair",         "prefix"),
    ("vines",                "lair",         "prefix"),
    ("floor_vines",          "lair",         "prefix"),
    ("acidic_floor",         "slime",        "prefix"),
    ("crypt_domino",         "crypt",        "prefix"),
    ("green_bones",          "crypt",        "prefix"),
    ("dragon",               "zot",          "contains"),
    ("demon",                "forge",        "contains"),
    ("seraph",               "vaults",       "contains"),
    ("naga",                 "snake",        "contains"),
    ("merfolk",              "shoals",       "contains"),
    ("octopode",             "shoals",       "contains"),
    ("kraken",               "shoals",       "contains"),
    ("hydra",                "swamp",        "contains"),
    ("alligator",            "swamp",        "contains"),
    ("mummy",                "tomb",         "contains"),
    ("sphinx",               "tomb",         "contains"),
    ("vampire",              "crypt",        "contains"),
    ("lich",                 "crypt",        "contains"),
    ("revenant",             "crypt",        "contains"),
    ("skeleton",             "crypt",        "contains"),
    ("zombie",               "crypt",        "contains"),
    ("jelly",                "slime",        "contains"),
    ("slime_creature",       "slime",        "contains"),
    ("acid_blob",            "slime",        "contains"),
    ("killer_bee",           "hive",         "contains"),
    ("queen_bee",            "hive",         "contains"),
    ("spider",               "spider",       "contains"),
    ("tarantella",           "spider",       "contains"),
    ("redback",              "spider",       "contains"),
    ("mosquito",             "swamp",        "contains"),
    ("orc_",                 "orc",          "contains"),
    ("deep_elf",             "elf",          "contains"),
    ("vault_guard",          "vaults",       "contains"),
    ("vault_sentinel",       "vaults",       "contains"),
    ("ironbound",            "depths",       "contains"),
    ("imp",                  "forge",        "contains"),
    ("efreet",               "forge",        "contains"),
    ("salamander",           "forge",        "contains"),
    ("lava_",                "forge",        "prefix"),
    ("lava",                 "forge",        "contains"),
    ("ice_dragon",           "glacier",      "contains"),
    ("ice_devil",            "glacier",      "contains"),
    ("ice_beast",            "glacier",      "contains"),
    ("ice_giant",            "glacier",      "contains"),
    ("simulacrum",           "glacier",      "contains"),
    ("white_imp",            "glacier",      "contains"),
    ("blue_dragon",          "glacier",      "contains"),
    ("frost",                "glacier",      "contains"),
    ("yak",                  "lair",         "contains"),
    ("blink_frog",           "lair",         "contains"),
    ("toad",                 "lair",         "contains"),
    ("wolf",                 "lair",         "contains"),
    ("bear",                 "lair",         "contains"),
    ("elephant",             "lair",         "contains"),
    ("crocodile",            "swamp",        "contains"),
    ("worm",                 "lair",         "contains"),
    ("rat",                  "dungeon",      "prefix"),
    ("rat",                  "dungeon",      "contains"),
    ("kobold",               "dungeon",      "contains"),
    ("goblin",               "dungeon",      "contains"),
    ("hobgoblin",            "dungeon",      "contains"),
    ("gnoll",                "dungeon",      "contains"),
]

# Class hints for body / armor / weapons → archetypes.
CLASS_HINTS = {
    "robe":     ["mage", "wizard", "priest"],
    "wizard":   ["mage", "wizard"],
    "robe_red": ["fire_mage"],
    "robe_blue":["water_mage", "ice_mage"],
    "robe_white":["priest", "cleric"],
    "robe_black":["necromancer", "death_mage"],
    "robe_green":["druid", "earth_mage"],
    "leather":  ["rogue", "ranger", "hunter"],
    "studded":  ["rogue", "ranger"],
    "chainmail":["fighter", "warrior"],
    "scalemail":["fighter", "warrior"],
    "plate":    ["paladin", "knight", "warrior"],
    "platemail":["paladin", "knight", "warrior"],
    "crystal":  ["paladin", "lord"],
    "fire_dragon":  ["dragon_knight", "fire_warrior"],
    "ice_dragon":   ["dragon_knight", "ice_warrior"],
    "gold_dragon":  ["dragon_knight"],
    "shadow_dragon":["assassin", "shadow_knight"],
    "naga_barding": ["naga"],
    "centaur_barding": ["centaur"],
    "felid":    ["felid"],
    "bone":     ["necromancer", "death_knight"],
}

# Weapon subcategory inference from filename prefix.
WEAPON_SUBCAT = [
    ("club",         "mace_flail"),
    ("mace",         "mace_flail"),
    ("flail",        "mace_flail"),
    ("morningstar",  "mace_flail"),
    ("eveningstar",  "mace_flail"),
    ("hammer",       "mace_flail"),
    ("whip",         "mace_flail"),
    ("dagger",       "short_blade"),
    ("rapier",       "short_blade"),
    ("short_sword",  "short_blade"),
    ("short_blade",  "short_blade"),
    ("falchion",     "long_blade"),
    ("scimitar",     "long_blade"),
    ("long_sword",   "long_blade"),
    ("longsword",    "long_blade"),
    ("greatsword",   "long_blade"),
    ("double_sword", "long_blade"),
    ("triple_sword", "long_blade"),
    ("hand_axe",     "axe"),
    ("war_axe",      "axe"),
    ("battleaxe",    "axe"),
    ("broad_axe",    "axe"),
    ("executioners_axe","axe"),
    ("axe",          "axe"),
    ("spear",        "polearm"),
    ("trident",      "polearm"),
    ("halberd",      "polearm"),
    ("scythe",       "polearm"),
    ("glaive",       "polearm"),
    ("bardiche",     "polearm"),
    ("partisan",     "polearm"),
    ("staff",        "staff"),
    ("quarterstaff", "staff"),
    ("lajatang",     "staff"),
    ("bow",          "bow"),
    ("longbow",      "bow"),
    ("shortbow",     "bow"),
    ("crossbow",     "crossbow"),
    ("arbalest",     "crossbow"),
    ("triple_crossbow","crossbow"),
    ("sling",        "sling"),
    ("hand_crossbow","crossbow"),
    ("blowgun",      "ranged_misc"),
    ("javelin",      "thrown"),
    ("throwing_net", "thrown"),
    ("boomerang",    "thrown"),
    ("dart",         "thrown"),
]

ARMOR_SUBCAT = [
    ("robe",         "robe"),
    ("leather",      "light_armor"),
    ("studded",      "light_armor"),
    ("ring_mail",    "medium_armor"),
    ("scale",        "medium_armor"),
    ("scalemail",    "medium_armor"),
    ("chain",        "medium_armor"),
    ("chainmail",    "medium_armor"),
    ("banded",       "heavy_armor"),
    ("plate",        "heavy_armor"),
    ("plate_mail",   "heavy_armor"),
    ("platemail",    "heavy_armor"),
    ("crystal_plate","heavy_armor"),
    ("dragon",       "dragon_armor"),
    ("troll",        "hide_armor"),
    ("fur",          "hide_armor"),
    ("steam",        "dragon_armor"),
    ("buckler",      "shield"),
    ("shield",       "shield"),
    ("kite_shield",  "shield"),
    ("tower_shield", "shield"),
    ("helm",         "helm"),
    ("helmet",       "helm"),
    ("cap",          "helm"),
    ("hat",          "helm"),
    ("crown",        "helm"),
    ("turban",       "helm"),
    ("glove",        "gloves"),
    ("gauntlet",     "gloves"),
    ("boot",         "boots"),
    ("naga_barding", "barding"),
    ("centaur_barding","barding"),
    ("cloak",        "cloak"),
]

# Monster ENUMs that are clearly branch-specific (lair-side mostly).
MONSTER_BIOME_HINT = {
    "MONS_GIANT_NEWT": ["lair", "swamp"],
    "MONS_BLACK_BEAR": ["lair", "forest"],
    "MONS_SPIDER":     ["spider"],
    "MONS_TARANTELLA": ["spider"],
    "MONS_REDBACK":    ["spider"],
    "MONS_NAGA":       ["snake"],
    "MONS_BLACK_MAMBA":["snake"],
    "MONS_ANACONDA":   ["snake"],
    "MONS_MERFOLK":    ["shoals"],
    "MONS_OCTOPODE":   ["shoals"],
    "MONS_KRAKEN":     ["shoals"],
    "MONS_ALLIGATOR":  ["swamp"],
    "MONS_HYDRA":      ["swamp", "lair"],
    "MONS_BOG_BODY":   ["swamp"],
    "MONS_ORC":        ["orc", "mines"],
    "MONS_ORC_WARRIOR":["orc", "mines"],
    "MONS_ORC_KNIGHT": ["orc", "mines"],
    "MONS_ORC_WIZARD": ["orc", "mines"],
    "MONS_ORC_PRIEST": ["orc", "mines"],
    "MONS_ORC_HIGH_PRIEST":["orc", "mines"],
    "MONS_DEEP_ELF":   ["elf"],
    "MONS_DEEP_ELF_KNIGHT":["elf"],
    "MONS_DEEP_ELF_BLADEMASTER":["elf"],
    "MONS_DEEP_ELF_MASTER_ARCHER":["elf"],
    "MONS_VAULT_GUARD":["vaults"],
    "MONS_VAULT_SENTINEL":["vaults"],
    "MONS_IRONBOUND":  ["depths"],
    "MONS_VAMPIRE":    ["crypt"],
    "MONS_REVENANT":   ["crypt"],
    "MONS_LICH":       ["crypt", "tomb"],
    "MONS_DRACULA":    ["crypt"],
    "MONS_MUMMY":      ["tomb"],
    "MONS_GREATER_MUMMY":["tomb"],
    "MONS_SPHINX":     ["tomb"],
    "MONS_ANUBIS_GUARD":["tomb"],
    "MONS_JELLY":      ["slime"],
    "MONS_OOZE":       ["slime"],
    "MONS_SLIME_CREATURE":["slime"],
    "MONS_ACID_BLOB":  ["slime"],
    "MONS_DEATH_OOZE": ["slime"],
    "MONS_ROYAL_JELLY":["slime"],
    "MONS_KILLER_BEE": ["hive"],
    "MONS_QUEEN_BEE":  ["hive"],
    "MONS_VAMPIRE_MOSQUITO":["hive", "swamp"],
    "MONS_RED_DRAGON": ["zot", "forge"],
    "MONS_GOLDEN_DRAGON":["zot"],
    "MONS_QUICKSILVER_DRAGON":["zot"],
    "MONS_SHADOW_DRAGON":["zot", "abyss"],
    "MONS_FIRE_DRAGON":  ["forge", "zot"],
    "MONS_ICE_DRAGON":   ["glacier", "zot"],
    "MONS_DEMON":      ["forge", "abyss"],
    "MONS_HELL_KNIGHT":["forge"],
    "MONS_PANDEMONIUM_LORD":["pandemonium"],
    "MONS_ABYSSAL":    ["abyss"],
    "MONS_TENGU":      ["dungeon"],
    "MONS_RAT":        ["dungeon"],
    "MONS_GIANT_RAT":  ["dungeon"],
    "MONS_GOBLIN":     ["dungeon", "orc"],
    "MONS_KOBOLD":     ["dungeon"],
}

# DCSS source rltiles uses some abbreviations & British spellings that the
# shipped tile pack normalises to other names. Map source-side path → fs-side path.
PATH_REWRITES = [
    ("dngn/", "dungeon/"),
    ("mon/", "monster/"),
    ("item/armour/", "item/armor/"),
    ("item/armour", "item/armor"),
]

def normalise_rel_path(p: str) -> str:
    for src, dst in PATH_REWRITES:
        if p.startswith(src):
            return dst + p[len(src):]
        # Substring case (e.g. nested)
        p = p.replace(src, dst)
    return p

DIRECTIONAL_SUFFIXES = re.compile(
    r'_(north|south|east|west|northeast|northwest|southeast|southwest|nw|ne|sw|se|corner|edge|overlay|side|left|right|top|bottom)(?:_|$|\d)',
    re.IGNORECASE
)


def parse_rltiles_file(path: Path, category: str, ctx: dict) -> list:
    """Returns list of tile dicts. ctx carries shared state across recursive includes."""
    tiles = []
    if not path.exists():
        return tiles

    sdir_stack = ctx.setdefault("sdir", [None])
    parts_ctg = ctx.get("parts_ctg")
    next_weight = 1
    pending_variation = None  # (ENUM, suffix)
    pending_enchant = None    # (ENUM, [suffix])
    last_primary_enum = None

    for raw_line in path.read_text(errors="replace").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue

        if line.startswith("%"):
            parts = line.split()
            cmd = parts[0][1:]
            args = parts[1:]
            if cmd == "sdir":
                sdir_stack[-1] = args[0] if args else None
            elif cmd == "name":
                pass
            elif cmd == "include":
                inc = args[0]
                inc_path = path.parent / inc
                # Inherit category for nested includes.
                tiles.extend(parse_rltiles_file(inc_path, category, ctx))
            elif cmd == "weight":
                try:
                    next_weight = int(args[0])
                except (ValueError, IndexError):
                    next_weight = 1
            elif cmd == "variation":
                if len(args) >= 2:
                    pending_variation = (args[0], args[1])
            elif cmd == "enchant_variation":
                if len(args) >= 2:
                    pending_enchant = (args[0], args[1:])
            elif cmd == "parts_ctg":
                ctx["parts_ctg"] = args[0] if args else None
                parts_ctg = ctx.get("parts_ctg")
            elif cmd == "end_ctg":
                ctx["parts_ctg"] = None
                parts_ctg = None
            # Ignored: rim, lum, hue, desat, resetcol, repeat, syn, compose,
            # back, start, finish, prefix, startvalue, texture, domino,
            # shrink, pal, blank, abstract, back_sdir, reset_mirror,
            # repeat_ctg, mirror_horizontal, alpha
            continue

        # Tile line: <filename> [<ENUM> [<ENUM>...]]
        parts = line.split()
        filename = parts[0]
        enums = parts[1:]
        primary_enum = enums[0] if enums else None
        extra_enums = enums[1:] if len(enums) > 1 else []

        if primary_enum:
            last_primary_enum = primary_enum
            is_variant = False
        else:
            primary_enum = last_primary_enum
            is_variant = True

        sdir = sdir_stack[-1]
        raw_rel = (sdir + "/" if sdir else "") + filename + ".png"
        rel_path = normalise_rel_path(raw_rel)

        tile = {
            "filename": filename,
            "rel_path": rel_path,
            "category": category,
            "enum": primary_enum,
            "extra_enums": extra_enums,
            "weight": next_weight,
            "is_variant": is_variant,
        }
        if parts_ctg:
            tile["parts_ctg"] = parts_ctg
        if pending_variation and primary_enum and pending_variation[0] == primary_enum:
            # %variation applies to this entry only when the next entry has
            # a new ENUM that follows a %variation directive.
            tile["variation_of"] = pending_variation[0]
            tile["variation_suffix"] = pending_variation[1]
            pending_variation = None
        if pending_enchant and primary_enum and pending_enchant[0] == primary_enum:
            tile["enchant_variation_of"] = pending_enchant[0]
            tile["enchant_suffixes"] = pending_enchant[1]
            pending_enchant = None

        tiles.append(tile)
        next_weight = 1  # weight is per-line in DCSS rltiles

    return tiles


def detect_directional(filename: str) -> dict:
    m = DIRECTIONAL_SUFFIXES.search(filename)
    if m:
        return {"directional": True, "direction": m.group(1).lower()}
    return {}


def biome_tags_from_path(rel_path: str, enum: str = "") -> list:
    tags = set()
    fname = Path(rel_path).stem.lower()
    full = rel_path.lower()
    for needle, tag, kind in BIOME_HINTS:
        nl = needle.lower()
        if kind == "dir":
            if nl in full:
                tags.add(tag)
        elif kind == "prefix":
            if fname.startswith(nl):
                tags.add(tag)
        elif kind == "contains":
            if nl in fname:
                tags.add(tag)
    if enum and enum in MONSTER_BIOME_HINT:
        tags.update(MONSTER_BIOME_HINT[enum])
    return sorted(tags)


def class_hints_from_path(rel_path: str) -> list:
    tags = set()
    blob = rel_path.lower()
    for needle, classes in CLASS_HINTS.items():
        if needle in blob:
            tags.update(classes)
    return sorted(tags)


def item_subcat(rel_path: str) -> str | None:
    if "/weapon/" in rel_path:
        for needle, sub in WEAPON_SUBCAT:
            if needle in rel_path.lower():
                return sub
        return "weapon_misc"
    if "/armor/" in rel_path or "/armour/" in rel_path:
        for needle, sub in ARMOR_SUBCAT:
            if needle in rel_path.lower():
                return sub
        return "armor_misc"
    if "/wand/" in rel_path:
        return "wand"
    if "/potion/" in rel_path:
        return "potion"
    if "/scroll/" in rel_path:
        return "scroll"
    if "/ring/" in rel_path:
        return "ring"
    if "/amulet/" in rel_path:
        return "amulet"
    if "/book/" in rel_path:
        return "book"
    if "/staff/" in rel_path:
        return "staff"
    if "/rod/" in rel_path:
        return "rod"
    if "/food/" in rel_path:
        return "food"
    if "/gold/" in rel_path:
        return "gold"
    if "/misc/" in rel_path:
        return "misc"
    return None


def variant_set_of(filename: str) -> tuple[str, int | None]:
    """For names like 'snake_0', 'snake_1' → returns ('snake', 0)."""
    m = re.match(r'^(.*?)_(\d+)$', filename)
    if m:
        return m.group(1), int(m.group(2))
    return filename, None


def main():
    print("Parsing rltiles dc-*.txt files…", flush=True)
    all_tiles_by_path: dict[str, dict] = {}

    for fname, top_category in TOP_FILES.items():
        path = DCSS_SOURCE / fname
        ctx = {}
        tiles = parse_rltiles_file(path, top_category, ctx)
        print(f"  {fname:25s} {len(tiles):>5} entries", flush=True)
        for t in tiles:
            # Some entries don't actually correspond to a PNG (e.g. ENUM-only
            # markers from %include). Index by rel_path; if seen twice, prefer
            # primary (non-variant) entry.
            key = t["rel_path"]
            existing = all_tiles_by_path.get(key)
            if existing and existing.get("enum") and not t.get("is_variant"):
                continue
            all_tiles_by_path[key] = t

    print(f"\nrltiles parsed: {len(all_tiles_by_path)} unique paths\n", flush=True)

    # Walk filesystem and union with parser output.
    print("Walking filesystem…", flush=True)
    fs_paths = {}  # rel_path -> abs_path
    for root in [DCSS_FULL, DCSS_SUPP]:
        if not root.exists(): continue
        for abs_path in root.rglob("*.png"):
            rel = abs_path.relative_to(root)
            rel_s = str(rel).replace("\\", "/")
            if rel_s not in fs_paths:
                fs_paths[rel_s] = str(abs_path)

    # Project-local sprites — species portraits, spell tomes, slot
    # icons, biome icons. Prefixed with "project/" so the authoring
    # portal can filter them and they don't collide with DCSS rltiles
    # paths. Combat pivot 2026-06-04.
    if PROJECT_ASSETS.exists():
        for abs_path in PROJECT_ASSETS.rglob("*.png"):
            rel = abs_path.relative_to(PROJECT_ASSETS)
            rel_s = "project/" + str(rel).replace("\\", "/")
            if rel_s not in fs_paths:
                fs_paths[rel_s] = str(abs_path)

    print(f"Filesystem PNGs: {len(fs_paths)}", flush=True)

    # Build final atlas keyed by relative path.
    atlas = {}
    matched = 0
    fs_only = 0

    for rel_path, abs_path in fs_paths.items():
        tile = dict(all_tiles_by_path.get(rel_path, {}))

        if tile:
            matched += 1
        else:
            # FS-only — derive everything from path
            fs_only += 1
            tile["rel_path"] = rel_path
            tile["category"] = path_to_category(rel_path)
            tile["filename"] = Path(rel_path).stem
            tile["is_variant"] = False
            tile["weight"] = 1

        # Enrich with directional, biome tags, class hints, subcat, variant set.
        tile.update(detect_directional(tile["filename"]))
        bts = biome_tags_from_path(rel_path, tile.get("enum") or "")
        if bts:
            tile["biome_tags"] = bts
        ch = class_hints_from_path(rel_path)
        if ch:
            tile["class_hints"] = ch
        sub = item_subcat(rel_path)
        if sub and tile.get("category") in ("item", "main"):
            tile["subcategory"] = sub
        # Variant set membership (e.g. lair_0..lair_15)
        vroot, vidx = variant_set_of(tile["filename"])
        if vidx is not None:
            tile["variant_set"] = vroot
            tile["variant_index"] = vidx

        atlas[rel_path] = tile

    print(f"\nMatched parser entries: {matched}", flush=True)
    print(f"FS-only entries:        {fs_only}", flush=True)
    print(f"Total atlas entries:    {len(atlas)}", flush=True)

    # Stats by category.
    cats = defaultdict(int)
    for t in atlas.values():
        cats[t.get("category", "?")] += 1
    print("\n=== Atlas counts by top category ===")
    for c, n in sorted(cats.items(), key=lambda x: -x[1]):
        print(f"  {c:15s} {n:>5}")

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    with OUTPUT.open("w") as f:
        json.dump(atlas, f, indent=1, sort_keys=True)
    size_mb = OUTPUT.stat().st_size / 1024 / 1024
    print(f"\nWrote {OUTPUT}  ({size_mb:.2f} MB)")


def path_to_category(rel_path: str) -> str:
    p = rel_path.lower()
    # Project-local sprites — first-class categories so the authoring
    # portal lists them ahead of raw DCSS rltiles. Combat pivot 2026-06-04.
    if p.startswith("project/player/species"):     return "species"
    if p.startswith("project/items/spells"):       return "spell"
    if p.startswith("project/projectiles"):        return "projectile"
    if p.startswith("project/biome_icons"):        return "biome_icon"
    if p.startswith("project/slot_icons"):         return "slot_icon"
    if p.startswith("project/player/"):            return "player_part"
    if p.startswith("project/items/"):             return "item"
    if p.startswith("project/enemies/"):           return "monster"
    if p.startswith("project/floor"):              return "floor"
    if p.startswith("project/walls"):              return "wall"
    if p.startswith("project/overlays"):           return "overlay"
    if p.startswith("project/features"):           return "feat"
    if p.startswith("project/gateways"):           return "gateway"
    if p.startswith("project/gui"):                return "gui"
    if p.startswith("project/"):                   return "project_misc"
    # DCSS raw — original mapping.
    if p.startswith("dungeon/floor"): return "floor"
    if p.startswith("dungeon/wall"):  return "wall"
    if p.startswith("dungeon/water"): return "water"
    if p.startswith("dungeon/trees"): return "tree"
    if p.startswith("dungeon/altars"):return "altar"
    if p.startswith("dungeon/traps"): return "trap"
    if p.startswith("dungeon/shops"): return "shop"
    if p.startswith("dungeon/statues"):return "statue"
    if p.startswith("dungeon/doors"): return "door"
    if p.startswith("dungeon/vaults"):return "vault_decor"
    if p.startswith("dungeon/gateways"):return "gateway"
    if p.startswith("dungeon/"):      return "feat"
    if p.startswith("item/"):         return "item"
    if p.startswith("monster/"):      return "monster"
    if p.startswith("player/"):       return "player"
    if p.startswith("effect/"):       return "effect"
    if p.startswith("misc/"):         return "misc"
    if p.startswith("emissaries/"):   return "emissary"
    if p.startswith("gui/"):          return "gui"
    return "unknown"


if __name__ == "__main__":
    main()
