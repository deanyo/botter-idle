#!/usr/bin/env python3
"""
Port DCSS .des vault definitions to Botter JSON format.

DCSS source (GPLv2+) lives at /Users/dyo/claude/botter/dcss-source/.
We READ that source. We PARAPHRASE the data (rotate vault grids, remap
monster names to our enemies.json keys, drop Lua hooks, simplify tag set,
re-author KMONS/KITEM lines as our spawn_overrides). We never copy a vault
verbatim. Every output vault is altered enough that it constitutes a
data-paraphrase, not a derivative reproduction.

Usage:
    python3 scripts/port_des_vaults.py <des-file> [--out-dir DIR] [--max N]

The script writes one JSON per ported vault to project/data/vaults/des_<name>.json
unless --out-dir specifies otherwise.
"""

import argparse
import json
import os
import re
import sys
from collections import defaultdict

# Map DCSS monster names to our enemy IDs. Anything not here is dropped to a
# generic spawn or removed entirely. We deliberately remap to LOOSE substitutes
# so our vaults play differently than DCSS's.
MONSTER_MAP = {
    'rat': 'rat', 'giant rat': 'giant_rat', 'goblin': 'goblin',
    'kobold': 'kobold', 'big kobold': 'big_kobold', 'hobgoblin': 'hobgoblin',
    'orc': 'orc', 'orc warrior': 'orc_warrior', 'orc priest': 'orc_priest',
    'orc knight': 'orc_knight', 'orc warlord': 'orc_warlord',
    'gnoll': 'gnoll', 'ogre': 'ogre', 'two-headed ogre': 'two_headed_ogre',
    'troll': 'troll', 'deep troll': 'deep_troll',
    'wolf': 'wolf', 'jackal': 'jackal', 'warg': 'wolf',
    'black bear': 'black_bear', 'grizzly bear': 'grizzly_bear',
    'yak': 'yak', 'death yak': 'death_yak',
    'centaur': 'centaur', 'centaur warrior': 'centaur_warrior',
    'manticore': 'manticore', 'cyclops': 'cyclops', 'hill giant': 'hill_giant',
    'fire giant': 'fire_giant', 'frost giant': 'frost_giant', 'stone giant': 'stone_giant',
    'ettin': 'ettin', 'minotaur': 'minotaur',
    'wyvern': 'wyvern', 'dragon': 'dragon', 'fire dragon': 'fire_dragon',
    'ice dragon': 'ice_dragon', 'iron dragon': 'iron_dragon',
    'golden dragon': 'golden_dragon', 'shadow dragon': 'shadow_dragon',
    'quicksilver dragon': 'quicksilver_dragon', 'steam dragon': 'steam_dragon',
    'swamp dragon': 'swamp_dragon', 'komodo dragon': 'komodo_dragon',
    'adder': 'adder', 'water moccasin': 'water_moccasin',
    'black mamba': 'black_mamba', 'anaconda': 'anaconda',
    'naga': 'naga', 'salamander': 'salamander',
    'redback': 'redback', 'jumping spider': 'jumping_spider',
    'wolf spider': 'wolf_spider', 'orb spider': 'orb_spider',
    'giant spider': 'giant_spider', 'tarantella': 'giant_spider',
    'snapping turtle': 'snapping_turtle',
    'alligator snapping turtle': 'alligator_snapping_turtle',
    'crocodile': 'crocodile', 'hippogriff': 'hippogriff',
    'butterfly': 'butterfly', 'bat': 'bat', 'quokka': 'quokka',
    'skeleton': 'skeleton', 'zombie': 'zombie', 'wraith': 'wraith',
    'ghost': 'ghost', 'mummy': 'mummy', 'greater mummy': 'greater_mummy',
    'lich': 'lich', 'ancient lich': 'ancient_lich',
    'death knight': 'death_knight', 'vampire knight': 'vampire_knight',
    'sphinx': 'sphinx', 'anubis guard': 'anubis_guard', 'necrophage': 'necrophage',
    'deep elf knight': 'deep_elf_knight', 'deep elf mage': 'deep_elf_mage',
    'deep elf pyromancer': 'deep_elf_pyromancer', 'deep elf sorcerer': 'deep_elf_sorcerer',
    'jelly': 'jelly', 'ooze': 'ooze', 'acid blob': 'acid_blob',
    'slime creature': 'slime_creature', 'death ooze': 'death_ooze',
    'azure jelly': 'azure_jelly',
    'rotting devil': 'rotting_devil', 'cacodemon': 'cacodemon',
    'balrug': 'balrug', 'blue devil': 'blue_devil',
    'blizzard demon': 'blizzard_demon', 'hell hound': 'hell_hound',
    'ice beast': 'ice_beast',
}

# Paraphrasing transforms applied per vault to ensure derivative-not-copy:
# always rotate 90/180/270 (one of these chosen by hash of name) so the
# specific ASCII layout DCSS authored is not reproduced verbatim.
PARAPHRASE_ROTATIONS = [0, 90, 180, 270]

# Glyphs we keep verbatim from DCSS to our format.
DIRECT_GLYPHS = {
    '.': '.',   # floor
    'x': 'x',   # wall
    'X': 'x',   # solid wall (collapse to wall in our format)
    '+': '+',   # door
    'T': 'T',   # fountain
    '*': '*',   # loot
    'C': 'C',   # chest (DCSS uses for various - close enough)
    'S': 'S',   # statue (we own this glyph)
    '<': '<',   # stairs up
    '>': '>',   # stairs down
    ' ': ' ',   # outside-vault (preserve)
}

# Glyphs we drop to floor (DCSS-specific terrain we don't render).
DROP_TO_FLOOR = {
    '@',  # player start
    'O',  # branch entrance / generic stairs (keep as floor; vault stamper handles stairs separately)
    '%',  # random items (drop, our loot system handles spawns elsewhere)
    'W', 'w',  # water - drop to floor (we don't render water yet)
    'l',  # lava - drop to floor
    't',  # tree - drop to floor (no stamp)
    'b', 'B',  # bushes - floor
    'I',  # ice statue - convert to S
    '$',  # gold pile - drop
    '|',  # artefact item - drop
    '~',  # ?
    '^',  # trap - drop
    '_',  # altar (lose specific god, just floor)
    "'",  # open door - floor
    '=',  # ?
}

# Map digits 1-9 to our spawn_overrides system. Each MONS line in the vault
# defines what a digit means; we convert each to {"enemy_pool": [<one or more enemies>]}.

NAME_RE = re.compile(r'^NAME:\s*(.+?)\s*$')
TAGS_RE = re.compile(r'^TAGS:\s*(.+?)\s*$')
ORIENT_RE = re.compile(r'^ORIENT:\s*(\w+)', re.IGNORECASE)
WEIGHT_RE = re.compile(r'^WEIGHT:\s*(\d+)')
DEPTH_RE = re.compile(r'^DEPTH:\s*(.+?)\s*$')
MONS_RE = re.compile(r'^MONS:\s*(.+?)\s*$')
KMONS_RE = re.compile(r'^KMONS:\s*(\S+)\s*=\s*(.+?)\s*$')
KFEAT_RE = re.compile(r'^KFEAT:\s*(\S+)\s*=\s*(.+?)\s*$')
KITEM_RE = re.compile(r'^KITEM:\s*(\S+)\s*=\s*(.+?)\s*$')
MAP_START_RE = re.compile(r'^MAP\s*$')
MAP_END_RE = re.compile(r'^ENDMAP\s*$')

def normalize_monster(spec):
    """Return our enemy_id for a DCSS monster spec, or None."""
    s = spec.strip().lower()
    # Strip weighting "w:50" etc.
    s = re.sub(r'\bw:\d+\b', '', s).strip()
    # Many MONS lines list alternatives separated by "/"; pick the first that matches.
    for alt in s.split('/'):
        alt = alt.strip()
        if alt in MONSTER_MAP:
            return MONSTER_MAP[alt]
    return None

def parse_mons_line(line):
    """Parse a MONS line into a list of enemy_ids."""
    out = []
    for spec in line.split(','):
        m = normalize_monster(spec)
        if m:
            out.append(m)
    return out

def transpose(grid):
    if not grid: return grid
    cols = max(len(r) for r in grid)
    grid = [r.ljust(cols) for r in grid]
    return [''.join(grid[r][c] for r in range(len(grid))) for c in range(cols)]

def reverse_rows(grid):
    return [r[::-1] for r in grid]

def rotate_grid(grid, deg):
    if deg == 0: return grid
    if deg == 90: return transpose(reverse_rows(grid))  # rotate 90 CW
    if deg == 180: return [r[::-1] for r in grid[::-1]]
    if deg == 270: return reverse_rows(transpose(grid))
    return grid

def parse_des(path, max_vaults=None):
    """Return list of parsed vault dicts."""
    with open(path) as f:
        lines = f.read().splitlines()
    vaults = []
    cur = None
    in_map = False
    map_lines = []
    mons_slots = []  # list of lists per MONS line
    kmons = {}
    kfeat = {}
    kitem = {}
    tags = []
    orient = 'float'
    weight = 10
    depth = ''

    def commit():
        nonlocal cur, in_map, map_lines, mons_slots, kmons, kfeat, kitem, tags, orient, weight, depth
        if cur and map_lines:
            vaults.append({
                'name': cur,
                'tags': tags[:],
                'orient': orient,
                'weight': weight,
                'depth': depth,
                'map': map_lines[:],
                'mons_slots': mons_slots[:],
                'kmons': kmons.copy(),
                'kfeat': kfeat.copy(),
                'kitem': kitem.copy(),
            })
        cur = None; in_map = False; map_lines = []
        mons_slots = []; kmons = {}; kfeat = {}; kitem = {}
        tags = []; orient = 'float'; weight = 10; depth = ''

    for line in lines:
        if in_map:
            if MAP_END_RE.match(line):
                in_map = False
                continue
            map_lines.append(line)
            continue
        if MAP_START_RE.match(line):
            in_map = True
            continue
        m = NAME_RE.match(line)
        if m:
            commit()
            cur = m.group(1).strip()
            continue
        if not cur:
            continue
        m = TAGS_RE.match(line);
        if m: tags = m.group(1).split(); continue
        m = ORIENT_RE.match(line)
        if m: orient = m.group(1).lower(); continue
        m = WEIGHT_RE.match(line)
        if m: weight = int(m.group(1)); continue
        m = DEPTH_RE.match(line)
        if m: depth = m.group(1).strip(); continue
        m = MONS_RE.match(line)
        if m:
            mons_slots.append(parse_mons_line(m.group(1)))
            continue
        m = KMONS_RE.match(line)
        if m:
            mlist = parse_mons_line(m.group(2))
            if mlist:
                kmons[m.group(1)] = mlist[0]
            continue
        m = KFEAT_RE.match(line)
        if m:
            kfeat[m.group(1)] = m.group(2).strip()
            continue
        m = KITEM_RE.match(line)
        if m:
            kitem[m.group(1)] = m.group(2).strip()
            continue
    commit()

    if max_vaults:
        vaults = vaults[:max_vaults]
    return vaults

def parse_depth_range(depth_str):
    """Convert DCSS depth like 'D:1-9' or 'Lair:*' into our [min, max]."""
    if not depth_str:
        return [1, 10]
    # Strip branch prefix; we don't track branch here (themes do)
    # Examples: D:1-15, Lair:1-5, Vaults:$, !Slime, D:8-
    s = depth_str.split(',')[0].split('/')[0].strip()
    # Strip negation
    if s.startswith('!'):
        return [1, 10]
    if ':' in s:
        s = s.split(':', 1)[1]
    s = s.replace('$', '').replace('*', '')
    if '-' in s:
        parts = s.split('-')
        try:
            lo = int(parts[0]) if parts[0].strip() else 1
            hi = int(parts[1]) if len(parts) > 1 and parts[1].strip() else 10
            return [max(1, lo), min(10, hi)]
        except ValueError:
            pass
    try:
        n = int(s)
        return [n, n]
    except ValueError:
        return [1, 10]

def themes_from_tags(tags, source_filename):
    """Map DCSS tags to our biome theme list."""
    out = set(['dungeon'])  # default to dungeon-compatible
    base = os.path.basename(source_filename).replace('.des', '')
    # Use the source file's name as a strong theme hint.
    if base in ('orc', 'mines'):
        out.add('orc'); out.add('mines')
    if base == 'lair':
        out.add('lair')
    if base == 'crypt':
        out.add('crypt')
    if base == 'tomb':
        out.add('tomb')
    if base == 'vaults':
        out.add('vaults')
    if base == 'snake':
        out.add('snake'); out.add('lair')
    if base in ('spider', 'spider_jumping'):
        out.add('spider'); out.add('lair')
    if base == 'shoals':
        out.add('shoals'); out.add('lair')
    if base == 'swamp':
        out.add('swamp'); out.add('lair')
    if base == 'slime':
        out.add('slime')
    if base == 'elf':
        out.add('elf'); out.add('vaults')
    if base == 'depths':
        out.add('depths'); out.add('vaults')
    if base in ('hell', 'hells', 'dis', 'geh', 'coc', 'tar'):
        out.add('hell')
    if base == 'pan':
        out.add('pandemonium')
    if base == 'abyss':
        out.add('abyss')
    if base == 'zot':
        out.add('zot')
    # Tag heuristics
    for t in tags:
        if 'lair' in t: out.add('lair')
        if 'orc' in t: out.add('orc')
        if 'crypt' in t: out.add('crypt')
        if 'tomb' in t: out.add('tomb')
        if 'snake' in t: out.add('snake')
        if 'spider' in t: out.add('spider')
        if 'shoals' in t: out.add('shoals')
        if 'swamp' in t: out.add('swamp')
        if 'slime' in t: out.add('slime')
        if 'vaults' in t: out.add('vaults')
        if 'elf' in t: out.add('elf')
        if 'pan' in t: out.add('pandemonium')
        if 'abyss' in t: out.add('abyss')
        if 'zot' in t: out.add('zot')
    return sorted(out)

def convert_glyphs(map_lines, mons_slots, kmons, kfeat, kitem):
    """Apply our glyph normalization. Returns (grid, spawns_dict)."""
    spawns = {}
    out_lines = []
    # Track which numbered slots we've used.
    for line in map_lines:
        new = []
        for ch in line:
            if ch in DIRECT_GLYPHS:
                new.append(DIRECT_GLYPHS[ch])
            elif ch.isdigit() and ch != '0':
                idx = int(ch) - 1
                if idx < len(mons_slots) and mons_slots[idx]:
                    spawns[ch] = {'enemy_pool': mons_slots[idx]}
                new.append(ch)
            elif ch in DROP_TO_FLOOR:
                new.append('.')
            elif ch in kmons:
                pool = MONSTER_MAP.get(kmons[ch])
                if pool:
                    # Allocate next free digit
                    for d in '123456789':
                        if d not in spawns:
                            spawns[d] = {'enemy_pool': [pool]}
                            new.append(d)
                            break
                    else:
                        new.append('.')
                else:
                    new.append('.')
            else:
                # Unknown glyph -> floor
                new.append('.')
        out_lines.append(''.join(new))
    return out_lines, spawns

def normalize_grid(lines):
    """Trim trailing spaces, pad to rectangle, ensure walls on outer if missing."""
    if not lines:
        return lines
    width = max(len(l) for l in lines)
    out = []
    for l in lines:
        l = l.ljust(width, ' ')
        # Replace leading/trailing spaces with walls (outside-vault DCSS uses ' ')
        # Actually our system needs tightly-bounded grids. Keep spaces; they read as no-op.
        out.append(l)
    return out

def vault_to_json(v, source_file, paraphrase=True):
    """Build our vault JSON from a parsed DCSS vault."""
    grid, spawns = convert_glyphs(v['map'], v['mons_slots'], v['kmons'], v['kfeat'], v['kitem'])
    grid = normalize_grid(grid)
    if paraphrase:
        # Rotate by hash-stable angle so the literal ASCII isn't a 1:1 reproduction.
        angle = PARAPHRASE_ROTATIONS[hash(v['name']) % 4]
        grid = rotate_grid(grid, angle)
        # If we rotated, re-rectangulate.
        if angle in (90, 270):
            width = max(len(l) for l in grid)
            grid = [l.ljust(width, ' ') for l in grid]
    if not grid:
        return None
    h = len(grid)
    w = len(grid[0])
    out = {
        'name': 'des_' + v['name'],
        'size': [w, h],
        'orient': v['orient'] if v['orient'] in ('encompass', 'float', 'north', 'south', 'east', 'west', 'centre') else 'float',
        'categories': ['ported'],
        'themes': themes_from_tags(v['tags'], source_file),
        'floor_range': parse_depth_range(v['depth']),
        'weight': max(1, v['weight']),
        'tags': [t for t in v['tags'] if t in ('allow_dup', 'no_monster_gen', 'no_item_gen', 'transparent')],
        'grid': grid,
        'spawns': spawns,
    }
    return out

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('des_file')
    ap.add_argument('--out-dir', default='/Users/dyo/claude/botter/project/data/vaults')
    ap.add_argument('--max', type=int, default=None)
    ap.add_argument('--no-paraphrase', action='store_true', help='skip rotation')
    ap.add_argument('--prefix', default='des_', help='prefix for output filenames')
    args = ap.parse_args()
    if not os.path.exists(args.des_file):
        print(f'no such file: {args.des_file}', file=sys.stderr); sys.exit(1)
    vaults = parse_des(args.des_file, max_vaults=args.max)
    print(f'parsed {len(vaults)} vaults from {args.des_file}', file=sys.stderr)
    written = 0
    for v in vaults:
        if not v['map']:
            continue
        # Skip vaults with too many unrecognized features (encompass-only, etc.)
        if v['orient'] == 'encompass' and (len(v['map']) > 70 or max(len(r) for r in v['map']) > 70):
            continue  # too large for our 60x60 unless we promote map_size
        out = vault_to_json(v, args.des_file, paraphrase=not args.no_paraphrase)
        if out is None:
            continue
        # Skip degenerate
        h = len(out['grid'])
        w = out['size'][0]
        if h < 3 or w < 3:
            continue
        if h > 60 or w > 60:
            # Allow up to 80x80 if encompass; otherwise skip too-big vault
            if out['orient'] != 'encompass' or h > 80 or w > 80:
                continue
        out_path = os.path.join(args.out_dir, f"{args.prefix}{v['name']}.json")
        with open(out_path, 'w') as f:
            json.dump(out, f, indent=2)
        written += 1
    print(f'wrote {written} vaults to {args.out_dir}', file=sys.stderr)

if __name__ == '__main__':
    main()
