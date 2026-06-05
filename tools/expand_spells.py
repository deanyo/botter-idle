#!/usr/bin/env python3
"""expand_spells.py — Quadruple the spell pool (35 → ~140) with sprite variance.

Walks the 10 archetypes in scripts/spell_data.gd::ARCHETYPES and emits
~14 variants per archetype, balanced across str/dex/int and across
rarities. Uses the full DCSS scroll + book sprite trees so every spell
has a distinct tile (no duplicates within the same rarity tier).

Naming follows a "<flavor-prefix> <archetype-noun>" pattern; lore is
one-line per (archetype × element × tier). Affix pools steer toward the
spell's element + primary_stat. Drop weights match item_tier.

Reads existing spells in items.json so it doesn't overwrite hand-tuned
ones (uniques like Soulhunger, Splinterfang, the starter spells).
Appends new ones; reports counts.

Usage: python3 tools/expand_spells.py
"""

import json
import random
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DB = ROOT / 'project/data/items.json'

# RNG seeded so re-runs produce identical output.
rng = random.Random(20260605)

# --- Archetype catalog ---
# id, archetype default stat, element, primary spell-noun, themed roots.
# Each archetype gets ~14 variants spread across str/dex/int.
ARCHETYPES = [
    # id,                      def_stat, element,    noun,          element_label
    ('spell_fireball',         'int',    'fire',     'Fireball',    'fire'),
    ('spell_axes',             'str',    '',         'Spinning Axes','brutal'),
    ('spell_holy_beam',        'str',    'holy',     'Holy Beam',   'holy'),
    ('spell_chain_lightning',  'dex',    'thunderous','Chain Lightning','storm'),
    ('spell_frost_nova',       'int',    'cold',     'Frost Nova',  'cold'),
    ('spell_magic_dart',       'int',    '',         'Magic Dart',  'arcane'),
    ('spell_iron_shot',        'str',    '',         'Iron Shot',   'earth'),
    ('spell_sandblast',        'str',    '',         'Sandblast',   'earth'),
    ('spell_drain',            'int',    'dark',     'Drain',       'dark'),
    ('spell_shatter',          'str',    '',         'Shatter',     'earth'),
]

# Per-element naming prefixes for visual + theme variety. Pulled from
# fantasy / DCSS adjacent vocab — no need to be subtle, the player
# wants to read "Cinderbolt" and know it's fire.
# Each pool ≥ 14 unique prefixes so 14 variants per archetype never hits
# the fallback dedupe. Tone: short evocative single words; no "Common".
ELEMENT_PREFIXES = {
    'fire':       ['Cinder', 'Searing', 'Pyroclastic', 'Ashen', 'Sunfire', 'Hellforged', 'Smouldering', 'Magma', 'Solar', 'Ember', 'Volcanic', 'Phoenix', 'Wildfire', 'Kindling', 'Bonfire', 'Pyrelit'],
    'cold':       ['Glacial', 'Hoarfrost', 'Permafrost', 'Wintertide', 'Riming', 'Freezing', 'Crystalline', 'Polar', 'Cryogenic', 'Frozen', 'Snowbound', 'Icefall', 'Numbing', 'Bitterwind', 'Whitefrost', 'Blizzardborn'],
    'thunderous': ['Storm', 'Crackling', 'Tempest', 'Thunderhead', 'Skyward', 'Galvanic', 'Voltaic', 'Charged', 'Static', 'Lightning', 'Stormwrought', 'Skyrending', 'Forking', 'Cloudbreak', 'Gale', 'Sparkbound'],
    'holy':       ['Radiant', 'Sanctified', 'Cathedral', 'Pilgrim', 'Hallowed', 'Sunblessed', 'Seraphic', 'Choir', 'Vigil', 'Heavenly', 'Goldleaf', 'Lambent', 'Sanguine', 'Reliquary', 'Beacon', 'Mantled'],
    'dark':       ['Umbral', 'Wraith', 'Hollow', 'Pall', 'Murk', 'Voidbound', 'Shade', 'Famine', 'Withering', 'Eclipse', 'Nightfall', 'Gravekeeper', 'Shroud', 'Cinderash', 'Dirge', 'Sunless'],
    'arcane':     ['Echo', 'Resonant', 'Sigil', 'Glyph', 'Ward', 'Mana', 'Cipher', 'Spectral', 'Phantasmal', 'Veil', 'Runebound', 'Whispering', 'Inkwell', 'Verbatim', 'Lexicon', 'Cantrip'],
    'earth':      ['Granite', 'Quarry', 'Basalt', 'Stoneborn', 'Ironvein', 'Bedrock', 'Cragblade', 'Tectonic', 'Mountain', 'Pebble', 'Slate', 'Quartz', 'Riverstone', 'Gravelstrike', 'Earthworn', 'Ridge'],
    'brutal':     ['Whirling', 'Rending', 'Carving', 'Brutal', 'Cleaving', 'Hewn', 'Vortex', 'Cyclone', 'Furious', 'Pinwheel', 'Reaper', 'Threshing', 'Whetted', 'Hacking', 'Sundering', 'Spinning'],
    '':           ['Wandering', 'Apprentice', 'Drifter', 'Vagabond', 'Journey', 'Marching', 'Pilgrim', 'Errant', 'Roving', 'Untaught', 'Acolyte', 'Novice', 'Master', 'Adept', 'Sage', 'Initiate'],
}

# Per-archetype lore variants. Two-three options per archetype × element.
# Falls back to a generic "Inscribed scroll of <noun>" line.
LORE_BY_ARCHETYPE_ELEMENT = {
    ('spell_fireball', 'fire'): [
        'The page is hot. The ink has burned slightly into it.',
        'A scroll the temperature of a banked oven.',
        'Pages have been singed by their own contents.',
    ],
    ('spell_fireball', 'cold'): [
        'Ice forms on the air around it before the casting.',
        'A frozen mote that bursts on impact.',
    ],
    ('spell_axes', ''): [
        'The diagrams revolve around the reader on their own.',
        'Iron filings on the page form an axe-shape, then disperse.',
    ],
    ('spell_holy_beam', 'holy'): [
        'A pilgrim\'s tract. Light reads off the page even in the dark.',
        'Ink set in gold. Reading aloud is dangerous to the unworthy.',
    ],
    ('spell_chain_lightning', 'thunderous'): [
        'Static raises the hairs on the reader\'s arm.',
        'Faint crackle when held, like distant thunder.',
    ],
    ('spell_frost_nova', 'cold'): [
        'A ring of frost expands from where the page is held.',
        'The pages are bound with a strip of glacier-ice.',
    ],
    ('spell_magic_dart', 'arcane'): [
        'The simplest cantrip. A dart of focused will.',
        'Apprentices learn this first; masters never stop using it.',
    ],
    ('spell_iron_shot', 'earth'): [
        'The page sags slightly under its own implied weight.',
        'A round of inscribed iron, fired through the ranks.',
    ],
    ('spell_sandblast', 'earth'): [
        'A pinch of grit pours from the pages whenever opened.',
        'Reading aloud kicks up a fine dust at one\'s feet.',
    ],
    ('spell_drain', 'dark'): [
        'A famished bolt — every kill stokes a quickening hunger.',
        'The ink looks suspiciously like dried blood.',
    ],
    ('spell_shatter', 'earth'): [
        'Hold the page wrong and the cover cracks down the middle.',
        'A radial shockwave that bypasses armour and strikes bone.',
    ],
}

# Which scroll sprites are "elemental-leaning" — picked first when the
# spell has a matching element. Falls through to the full pool when
# no thematic match. Path is relative to project/assets/tiles/.
# Only the full-tile scroll sprites — DCSS i-*.png files are tiny
# overlay pictograms (skull/eye/orb) intended to layer on top of a base
# scroll, not used standalone. Used alone they read as "tiny icon in
# empty space." User caught this 2026-06-05.
SCROLL_SPRITES = [
    'spells/scrolls/scroll-blue.png',
    'spells/scrolls/scroll-brown.png',
    'spells/scrolls/scroll-cyan.png',
    'spells/scrolls/scroll-green.png',
    'spells/scrolls/scroll-grey.png',
    'spells/scrolls/scroll-purple.png',
    'spells/scrolls/scroll-red.png',
    'spells/scrolls/scroll-yellow.png',
    'spells/scrolls/scroll.png',
]

# Books split by tier — uncommon/rare = simple bound books,
# epic = colored metal, legendary = unique authored covers.
BOOKS_RARE = [  # parchment/cloth/leather and basic colors
    'spells/books/parchment.png',
    'spells/books/cloth.png',
    'spells/books/leather.png',
    'spells/books/dark_brown.png',
    'spells/books/light_brown.png',
    'spells/books/dark_gray.png',
    'spells/books/light_gray.png',
    'spells/books/tan.png',
    'spells/books/light_blue.png',
    'spells/books/light_green.png',
    'spells/books/cyan.png',
    'spells/books/dark_blue.png',
    'spells/books/dark_green.png',
    'spells/books/turquoise.png',
    'spells/books/yellow.png',
    'spells/books/pink.png',
]
BOOKS_EPIC = [  # metal-bound + bronze/copper, ornate
    'spells/books/bronze.png',
    'spells/books/copper.png',
    'spells/books/metal_blue.png',
    'spells/books/metal_cyan.png',
    'spells/books/metal_green.png',
    'spells/books/red.png',
    'spells/books/magenta.png',
    'spells/books/purple.png',
    'spells/books/plaid.png',
    'spells/books/white.png',
]
BOOKS_LEGENDARY = [  # signature
    'spells/books/manual1.png',
    'spells/books/manual2.png',
    'spells/books/book_of_the_dead.png',
    'spells/books/gold.png',
    'spells/books/silver.png',
]

# Per-element scroll picks — when an element matches, prefer this
# subset so a fire spell looks fiery.
# Element → preferred scroll color. Overlay icons (i-*.png) are NOT in
# this list — they're tiny overlay pictograms, not main tile art.
SCROLL_ELEMENT_HINTS = {
    'fire':       ['scroll-red.png', 'scroll-yellow.png'],
    'cold':       ['scroll-blue.png', 'scroll-cyan.png'],
    'thunderous': ['scroll-purple.png', 'scroll-blue.png'],
    'holy':       ['scroll-yellow.png', 'scroll-grey.png'],
    'dark':       ['scroll-grey.png', 'scroll-purple.png'],
    'arcane':     ['scroll-purple.png', 'scroll-cyan.png'],
    'earth':      ['scroll-brown.png', 'scroll-green.png'],
    'brutal':     ['scroll.png', 'scroll-grey.png', 'scroll-red.png'],
}

# Each archetype's variant plan — N variants per rarity tier, balanced
# across str/dex/int. Same plan used for every archetype so the total
# spell count = 10 archetypes × 14 = 140 variants (plus the existing
# starter/handcrafted ones we leave untouched).
VARIANTS_PER_ARCHETYPE = [
    # (rarity, count, allow_stats)
    ('common',    5, ['str', 'dex', 'int']),
    ('uncommon',  4, ['str', 'dex', 'int']),
    ('rare',      3, ['str', 'dex', 'int']),
    ('epic',      1, ['str', 'dex', 'int']),
    ('legendary', 1, ['str', 'dex', 'int']),
]

# Rarity → drop_weights template (matches existing common spells).
RARITY_DROPS = {
    'common':    [60, 30, 8, 2, 0],
    'uncommon':  [40, 50, 20, 5, 0],
    'rare':      [10, 25, 50, 18, 5],
    'epic':      [0, 5, 25, 45, 20],
    'legendary': [0, 0, 5, 20, 30],
}
RARITY_TIER = {  # item_tier
    'common': 1, 'uncommon': 2, 'rare': 3, 'epic': 4, 'legendary': 5,
}
RARITY_DAMAGE_MULT = {
    'common': 1.00, 'uncommon': 1.10, 'rare': 1.22, 'epic': 1.38, 'legendary': 1.55,
}
RARITY_ENCHANT_CHANCE = {
    'common': 0.05, 'uncommon': 0.08, 'rare': 0.12, 'epic': 0.20, 'legendary': 0.32,
}


def pick_scroll_or_book(element, rarity, used):
    """Pick a base tile. Hue rotation (default_tint) handles the rest.

    We use a small pool of clean base sprites and apply per-spell hue
    shifts via the recolor shader (same system as the item generator)
    so 50 commons can each look distinct without needing 50 unique
    PNGs. 2026-06-05.
    """
    # Common/uncommon → use scroll.png as the unified base. The hue
    # shift in default_tint colors it per element+variant.
    if rarity in ('common', 'uncommon'):
        # Use a single neutral scroll as the canonical base — hue
        # rotation does the rest. Fall through to scroll-grey if the
        # blank one isn't available.
        return 'spells/scrolls/scroll.png'
    pool = {
        'rare': BOOKS_RARE,
        'epic': BOOKS_EPIC,
        'legendary': BOOKS_LEGENDARY,
    }[rarity]
    avail = [p for p in pool if p not in used]
    return avail[0] if avail else pool[rng.randrange(len(pool))]


# Element → base hue (degrees). Variants step ±20° around this so a
# fire spell can read as red, orange, or amber — all clearly fire, none
# identical. 2026-06-05.
ELEMENT_BASE_HUE = {
    'fire':       10.0,    # red-orange
    'cold':       210.0,   # cyan-blue
    'thunderous': 270.0,   # violet-purple
    'lightning':  270.0,
    'holy':       50.0,    # warm gold
    'dark':       290.0,   # purple-magenta
    'arcane':     280.0,   # purple
    'earth':      30.0,    # brown-amber
    'brutal':     0.0,     # red
    'poison':     130.0,   # green
    'vampiric':   355.0,   # blood-red
    '':           200.0,   # default arcane-ish blue
}

def make_tint(element, variant_idx):
    """Build a default_tint dict that hue-shifts the base scroll/book
    sprite into the right element band, with a per-variant offset so
    spells of the same element don't all look identical."""
    base = ELEMENT_BASE_HUE.get(element, ELEMENT_BASE_HUE[''])
    offset = ((variant_idx * 17) % 41) - 20  # ±20° spread
    h = (base + offset) % 360.0
    # Mode 'colorize' overrides the underlying color — works on the
    # parchment-yellow scroll.png. Saturation 0.85 keeps some texture
    # variation through the recolor.
    return {
        'hue': round(float(h), 1),
        'sat': 0.85,
        'mode': 'colorize',
    }


def build_affix_pool(element, primary_stat, rarity):
    """Steer affix weights toward the spell's element + primary stat."""
    pool = {
        # generic spell-relevant affixes (always present)
        'of_wisdom': 14,
        'of_quickcast': 22,
        'of_resonance': 18,
        'of_lingering': 16,
        'of_velocity': 12,
        'of_multicast': 10,
        'of_channeling': 22,
        'of_crit': 10,
        'of_haste': 12,
    }
    # Mastery for the spell's primary stat — heavier weight.
    mastery_key = {'str': 'of_str_mastery', 'dex': 'of_dex_mastery', 'int': 'of_int_mastery'}[primary_stat]
    pool[mastery_key] = 26
    # Lower weight for the other two masteries (still in pool).
    for s in ('str', 'dex', 'int'):
        if s == primary_stat:
            continue
        pool[{'str': 'of_str_mastery', 'dex': 'of_dex_mastery', 'int': 'of_int_mastery'}[s]] = 6
    # Element-specific bumps. "thunderous" → of_storms; "" → no bump.
    elem_affix_map = {
        'fire': 'of_embers',
        'cold': 'of_frost',
        'thunderous': 'of_storms',
        'holy': 'of_devotion',
        'poison': 'of_venom',
        'dark': 'of_shadows',
    }
    if element in elem_affix_map:
        pool[elem_affix_map[element]] = 24
    # Higher rarities also boost spell_damage_pct (channeling).
    if rarity in ('epic', 'legendary'):
        pool['of_channeling'] = 30
        pool['of_resonance'] = 24
    if rarity == 'legendary':
        # Legendary — multicast + lingering matter more (spec'd casters).
        pool['of_multicast'] = 16
        pool['of_lingering'] = 22
    return pool


def make_variant(arch, rarity, primary_stat, used_ids, used_tiles, used_names, variant_idx):
    arch_id, def_stat, element, noun, label = arch
    # Read base stats from spell_data.gd source — easier than re-reading
    # the GD file. Approximate the values we know.
    BASE_DAMAGE = {
        'spell_fireball': 18,
        'spell_axes': 14,
        'spell_holy_beam': 26,
        'spell_chain_lightning': 16,
        'spell_frost_nova': 16,
        'spell_magic_dart': 9,
        'spell_iron_shot': 32,
        'spell_sandblast': 30,
        'spell_drain': 22,
        'spell_shatter': 28,
    }
    BASE_CD = {
        'spell_fireball': 1.6,
        'spell_axes': 5.0,
        'spell_holy_beam': 3.2,
        'spell_chain_lightning': 2.4,
        'spell_frost_nova': 4.0,
        'spell_magic_dart': 0.7,
        'spell_iron_shot': 3.5,
        'spell_sandblast': 2.6,
        'spell_drain': 2.4,
        'spell_shatter': 5.0,
    }
    DAMAGE_TYPE = {
        'spell_fireball': 'fire',
        'spell_axes': 'physical',
        'spell_holy_beam': 'holy',
        'spell_chain_lightning': 'lightning',
        'spell_frost_nova': 'cold',
        'spell_magic_dart': 'physical',
        'spell_iron_shot': 'physical',
        'spell_sandblast': 'physical',
        'spell_drain': 'dark',
        'spell_shatter': 'physical',
    }
    base_dmg = BASE_DAMAGE[arch_id]
    rarity_mult = RARITY_DAMAGE_MULT[rarity]
    dmg_mid = base_dmg * rarity_mult
    dmg_min = int(round(dmg_mid * 0.85))
    dmg_max = int(round(dmg_mid * 1.20))
    # Pick prefix — element-driven if the spell has an element, else from
    # primary_stat. Dedupe across the WHOLE archetype (not just same
    # rarity) so different rarity tiers + stats all get unique names —
    # the player sees them all in inventory at once and "Cinder Fireball
    # Scroll" + "Cinder Fireball Tome" reads as a typo.
    prefix_pool = ELEMENT_PREFIXES.get(element or label) or ELEMENT_PREFIXES['']
    avail_prefixes = [p for p in prefix_pool if (arch_id, p) not in used_names]
    if not avail_prefixes:
        # Pool exhausted — disambiguate with stat + rarity, and check the
        # combined string against used_names to guarantee uniqueness.
        for _ in range(20):
            base_prefix = prefix_pool[rng.randrange(len(prefix_pool))]
            decorated = f'{base_prefix} {primary_stat.title()}{"" if rarity == "common" else " " + rarity.title()}'
            if (arch_id, decorated) not in used_names:
                prefix = decorated
                used_names.add((arch_id, prefix))
                break
        else:
            # Truly exhausted — fallback unique uses an index. Caller
            # enforces id uniqueness already so this just prevents name
            # collisions in inventory.
            prefix = f'{prefix_pool[0]} {primary_stat.title()} {rarity.title()} {rng.randrange(1000)}'
            used_names.add((arch_id, prefix))
    else:
        prefix = avail_prefixes[rng.randrange(len(avail_prefixes))]
        used_names.add((arch_id, prefix))
    # Stat suffix in id — e.g. spell_fireball_cinder_dex
    rarity_suffix = '' if rarity == 'common' else f'_{rarity}'
    new_id = f'{arch_id}_{prefix.lower()}_{primary_stat}'
    while new_id in used_ids:
        new_id = f'{arch_id}_{prefix.lower()}_{primary_stat}_{rng.randrange(1000)}'
    used_ids.add(new_id)
    # Pick tile
    tile_path = pick_scroll_or_book(element or label, rarity, used_tiles)
    used_tiles.add(tile_path)
    name_suffix = 'Tome' if tile_path.startswith('spells/books') else 'Scroll'
    name = f'{prefix} {noun} {name_suffix}'
    # Lore — pick from per-arch table or fallback.
    lore_pool = LORE_BY_ARCHETYPE_ELEMENT.get((arch_id, element), None)
    if lore_pool is None:
        # Try without element key
        for key in [(arch_id, ''), (arch_id, label)]:
            if key in LORE_BY_ARCHETYPE_ELEMENT:
                lore_pool = LORE_BY_ARCHETYPE_ELEMENT[key]
                break
    if lore_pool is None:
        lore_pool = [f'A {prefix.lower()}-bound spell, marked with the seal of {noun.lower()}.']
    lore = lore_pool[rng.randrange(len(lore_pool))]
    # Affix pool steered by stat + element.
    affix_pool = build_affix_pool(element, primary_stat, rarity)
    flavor_tags = []
    if element:
        flavor_tags.append(element)
    item = {
        'id': new_id,
        'name': name,
        'slot': 'spell',
        'rarity': rarity,
        'tile': tile_path,
        'default_tint': make_tint(element or label, variant_idx),
        'base_type': arch_id,
        'primary_stat': primary_stat,
        'damage_min': dmg_min,
        'damage_max': dmg_max,
        'damage_type': DAMAGE_TYPE[arch_id],
        'spell_cooldown': BASE_CD[arch_id],
        'item_tier': RARITY_TIER[rarity],
        'flavor_tags': flavor_tags,
        'lore': lore,
        'drop_weights': RARITY_DROPS[rarity][:],
        'unique': False,
        'enchant_chance': RARITY_ENCHANT_CHANCE[rarity],
        'implicit_affixes': [],
        'affix_pool': affix_pool,
    }
    return item


def main():
    db = json.loads(DB.read_text())
    # Drop spells produced by previous runs of THIS script so re-runs are
    # idempotent. Detect by id pattern: spell_<archetype>_<prefix>_<stat>
    # — has a stat suffix, distinguishing it from hand-tuned ids like
    # "soulhunger" or "spell_fireball_comet" which are pre-existing
    # uniques.
    arch_ids = {a[0] for a in ARCHETYPES}
    keep = []
    drop_count = 0
    for it in db['items']:
        if it.get('slot') == 'spell':
            sid = it['id']
            if any(sid.startswith(a + '_') for a in arch_ids):
                # Looks like an expand_spells output. Distinguish from
                # hand-tuned legendaries by checking if the id ends with
                # _str / _dex / _int (or one of those + a numeric tag).
                tail = sid.rsplit('_', 1)[-1]
                if tail in ('str', 'dex', 'int') or tail.isdigit():
                    drop_count += 1
                    continue
        keep.append(it)
    if drop_count:
        print(f'Pruning {drop_count} previously-generated spells before re-run.')
        db['items'] = keep
    existing_ids = {it['id'] for it in db['items']}
    existing_tiles_per_rarity = {}
    # Track which tiles are used by existing spells per rarity so we don't
    # duplicate (preserve hand-tuned spell visual identity).
    for it in db['items']:
        if it.get('slot') != 'spell':
            continue
        existing_tiles_per_rarity.setdefault(it.get('rarity', 'common'), set()).add(it.get('tile', ''))
    # Build new variants. Plan: for each archetype × rarity tier, allocate
    # `count` variants distributed across `allow_stats`.
    new_items = []
    used_ids = set(existing_ids)
    used_names = set()
    # Per-rarity tile usage — start from existing.
    used_tiles_per_rarity = {r: set(s) for r, s in existing_tiles_per_rarity.items()}
    variant_counter = 0
    for arch in ARCHETYPES:
        for rarity, count, allow_stats in VARIANTS_PER_ARCHETYPE:
            # Distribute `count` variants across allow_stats roughly evenly.
            # Avoid duplicating archetype's default stat too heavily.
            stat_order = list(allow_stats)
            rng.shuffle(stat_order)
            for i in range(count):
                primary = stat_order[i % len(stat_order)]
                used_tiles = used_tiles_per_rarity.setdefault(rarity, set())
                item = make_variant(arch, rarity, primary, used_ids, used_tiles, used_names, variant_counter)
                variant_counter += 1
                new_items.append(item)
    # Append + save.
    db['items'].extend(new_items)
    DB.write_text(json.dumps(db, indent=2) + '\n')
    # Stats report.
    by_arch = {}
    by_rarity = {}
    by_stat = {}
    for it in new_items:
        by_arch[it['base_type']] = by_arch.get(it['base_type'], 0) + 1
        by_rarity[it['rarity']] = by_rarity.get(it['rarity'], 0) + 1
        by_stat[it['primary_stat']] = by_stat.get(it['primary_stat'], 0) + 1
    print(f'Generated {len(new_items)} new spells.')
    print('Per archetype:', by_arch)
    print('Per rarity:   ', by_rarity)
    print('Per stat:     ', by_stat)
    total_spells = sum(1 for i in db['items'] if i.get('slot') == 'spell')
    print(f'Total spells in items.json now: {total_spells}')


if __name__ == '__main__':
    main()
