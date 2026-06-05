#!/usr/bin/env python3
"""balance_generated_items.py — One-shot balance pass on flavor-suffixed item variants.

The Item Generator (in-game main-menu screen) emits paste-ready item bases
with stats copied from a parent + a thematic recolor. The output is
playable but doesn't account for how the *flavor* should steer the item's
gameplay identity. This script walks every flavor-suffixed item in
items.json and applies:

1. **Rarity correction** — prismatic = legendary, inverted/twisted/spectral
   ≥ epic, shimmer ≥ rare. The generator's randomized rarity rolls produced
   "Common Crimson Dagger" type oddities; we floor by visual cost.

2. **Flavor → affix-pool weighting** — each flavor leans into a thematic
   affix family. Crimson boosts fire/might/lifesteal; frostbound boosts
   cold/quickcast; voidwrought boosts dark/lifesteal/shadows; prismatic
   evens-out all elements + multicast/resonance to advertise its chaotic
   identity. Pool weights are *added* on top of the parent's pool so the
   parent's identity stays present.

3. **Drop-weight smoothing** — generator emitted [0,0,100,0,0] for tier
   3, etc. Smooth into [10,40,30,5,0] so a tier-3 item still appears at
   tier 2-4 floors with reduced frequency.

4. **Themed lore** — replace the auto "A jade-forged reflavor of the
   standard halberd" with a per-flavor one-liner that justifies the
   flavor. Falls back to a slot-aware template when no specific lore.

5. **Enchant chance bump** — legendary variants get enchant_chance lifted
   to 0.30 minimum so they roll a combat tag on top of their visual.

Idempotent in spirit: re-running re-applies the same rules with the same
results, so it's safe to call after each generator import.

Usage: python3 tools/balance_generated_items.py
"""

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DB = ROOT / 'project/data/items.json'

FLAVORS = {
    'crimson','bloodstained','verdant','mossy','azure','frostbound',
    'voidwrought','shadowed','gilded','sunsteel','stormtouched','embered',
    'inverse','twisted','prismatic','pale','bone','obsidian','ironclad',
    'coppersworn','jadeforged','rosegold','nightblue','umbral','spectral',
}

# Flavor identity → list of (affix_id, weight) bumps applied additively
# to the parent's pool. Negative bumps not used (keeps the parent's
# identity reachable). All these affixes apply to all gear slots — the
# AffixSystem filter does its own slot check before rolling.
FLAVOR_AFFIX_BUMPS = {
    # --- Fire family ---
    'crimson':     [('of_embers', 35), ('of_might', 18), ('of_lifesteal', 12), ('of_fire_resist', 18), ('of_haste', 12)],
    'bloodstained':[('of_lifesteal', 30), ('of_might', 15), ('of_shadows', 18), ('of_dark_resist', 15)],
    'embered':     [('of_embers', 30), ('of_quickcast', 14), ('of_fire_resist', 22), ('of_channeling', 10)],
    # --- Cold family ---
    'azure':       [('of_frost', 30), ('of_finesse', 15), ('of_quickcast', 14), ('of_cold_resist', 22)],
    'frostbound':  [('of_frost', 35), ('of_cold_resist', 22), ('of_quickcast', 18), ('of_crit', 15)],
    'spectral':    [('of_frost', 22), ('of_dark_resist', 18), ('of_finesse', 15), ('of_dex_mastery', 12)],
    # --- Holy / radiant family ---
    'sunsteel':    [('of_devotion', 30), ('of_holy_resist', 22), ('of_might', 18), ('of_regen', 12)],
    'gilded':      [('of_devotion', 28), ('of_holy_resist', 18), ('of_channeling', 15), ('of_quickcast', 12)],
    'rosegold':    [('of_devotion', 22), ('of_haste', 18), ('of_lifesteal', 12), ('of_quickcast', 15)],
    # --- Lightning family ---
    'stormtouched':[('of_storms', 32), ('of_lightning_resist', 20), ('of_haste', 18), ('of_velocity', 14)],
    # --- Nature family ---
    'verdant':     [('of_regen', 18), ('of_vitality', 22), ('of_the_bear', 15), ('of_poison_resist', 18)],
    'mossy':       [('of_venom', 28), ('of_poison_resist', 22), ('of_regen', 14), ('of_vitality', 15)],
    'jadeforged':  [('of_venom', 22), ('of_finesse', 18), ('of_dex_mastery', 14), ('of_crit', 15)],
    # --- Dark / void family ---
    'voidwrought': [('of_shadows', 32), ('of_dark_resist', 22), ('of_lifesteal', 18), ('of_might', 12)],
    'shadowed':    [('of_shadows', 26), ('of_dark_resist', 18), ('of_finesse', 14), ('of_quickcast', 12)],
    'umbral':      [('of_shadows', 30), ('of_dark_resist', 22), ('of_int_mastery', 14), ('of_channeling', 14)],
    'obsidian':    [('of_shadows', 22), ('of_the_bear', 22), ('of_dark_resist', 18), ('of_vitality', 18)],
    'twisted':     [('of_shadows', 26), ('of_finesse', 14), ('of_lifesteal', 14), ('of_dark_resist', 14)],
    'inverse':     [('of_finesse', 18), ('of_int_mastery', 18), ('of_quickcast', 14), ('of_resonance', 14)],
    # --- Earth / metal family ---
    'ironclad':    [('of_the_bear', 30), ('of_vitality', 22), ('of_might', 14), ('of_sharpness', 14)],
    'pale':        [('of_holy_resist', 18), ('of_devotion', 14), ('of_finesse', 14), ('of_wisdom', 12)],
    'bone':        [('of_shadows', 22), ('of_might', 14), ('of_finesse', 14), ('of_lifesteal', 12)],
    'coppersworn': [('of_storms', 22), ('of_lightning_resist', 18), ('of_might', 14), ('of_haste', 12)],
    'nightblue':   [('of_finesse', 18), ('of_int_mastery', 18), ('of_quickcast', 14), ('of_resonance', 14)],
    # --- Chaos / prismatic ---
    # 2026-06-05 retune: was 13 bumps totalling ~180 weight, which
    # bloated the affix_pool of legendary prismatic armor/shield to
    # +3σ in the iLvl audit. Trimmed to 7 element adders (the
    # chaotic identity) at 18 each — total ~126 weight, in band with
    # other legendary flavors.
    'prismatic':   [
        ('of_embers', 18), ('of_frost', 18), ('of_storms', 18),
        ('of_devotion', 18), ('of_venom', 18), ('of_shadows', 18),
        ('of_sharpness', 18),
    ],
}

# Floor-rarity per visual mode. Generator can roll a "common crimson"
# but the eye says crimson = significant. Floor by mode + flavor tier.
FLAVOR_RARITY_FLOOR = {
    'prismatic': 'legendary',  # always
    'inverse':   'epic',
    'twisted':   'epic',
    'spectral':  'epic',
    'shimmer_modes': 'rare',   # any flavor in shimmer mode → rare min
    'colorize_modes': 'uncommon',  # colorize → uncommon min
}

RARITY_INDEX = {'common': 0, 'uncommon': 1, 'rare': 2, 'epic': 3, 'legendary': 4}
RARITY_NAMES = ['common', 'uncommon', 'rare', 'epic', 'legendary']

# Per-flavor lore one-liners. Slot-agnostic where possible; combine with
# parent name at format time. Tone matches existing items.json — flavor
# text, not stat description.
FLAVOR_LORE = {
    'crimson':      "Forged in dragonfire, the metal still glows when blood spills near it.",
    'bloodstained': "Old blood, deep in the grain. It never dries.",
    'verdant':      "Vines crawl over the haft, seeking soil that is not there.",
    'mossy':        "Damp green spores drift from every notch — they twitch toward warm flesh.",
    'azure':        "Cold to the touch. The air around it always tastes of winter.",
    'frostbound':   "A rime of ice will not melt, no matter how warm the room.",
    'voidwrought':  "Smithed somewhere between worlds. The shadow it casts is wrong.",
    'shadowed':     "Hard to see in dim light, even when held directly before you.",
    'gilded':       "Cathedral-gold leaf, beaten thin and prayed over for a hundred years.",
    'sunsteel':     "The metal is warm even at midnight. Undead dare not touch it.",
    'stormtouched': "Static raises the hairs on your arm. A faint hum, always present.",
    'embered':      "Carries its own slow heat. Embers drift from it when struck.",
    'inverse':      "Looking at it too long inverts what you saw before.",
    'twisted':      "It is not the same shape twice. Bending occurs when you look away.",
    'prismatic':    "Every glance reveals a new color, each one a real one — somewhere.",
    'pale':         "Bleached past white into a color the eye cannot name.",
    'bone':         "Shaped from the long bones of something old. It still aches in the cold.",
    'obsidian':     "Volcanic glass, edge-flaked razor-sharp by patient hands.",
    'ironclad':     "Plain forged iron, but heavier than the metal alone explains.",
    'coppersworn':  "Verdigris-greened copper that crackles when storms approach.",
    'jadeforged':   "Carved from one piece of imperial jade. Fault-lines make patterns.",
    'rosegold':     "An alloy out of fashion in this century. The shine is unmistakable.",
    'nightblue':    "Indigo so dark it reads as black until light hits the right angle.",
    'umbral':       "The dark that settles on it cannot be polished off.",
    'spectral':     "It is somehow always slightly cooler than its surroundings.",
}


def parse_flavor(item_id):
    parts = item_id.rsplit('_', 1)
    if len(parts) != 2:
        return None
    return parts[1] if parts[1] in FLAVORS else None


def floor_rarity(item, flavor):
    """Bump rarity up to a floor based on flavor + tint mode."""
    current = item.get('rarity', 'common')
    cur_idx = RARITY_INDEX.get(current, 0)
    # Any flavor-suffixed variant is at minimum uncommon — the name
    # ('Shadowed Leather Cloak', 'Mossy Bone Knife') promises a theme
    # that a 0-affix common can't deliver. 2026-06-05 user catch.
    floor_idx = max(cur_idx, RARITY_INDEX['uncommon'])
    # Flavor-specific floors.
    if flavor in FLAVOR_RARITY_FLOOR:
        floor_idx = max(floor_idx, RARITY_INDEX[FLAVOR_RARITY_FLOOR[flavor]])
    # Tint-mode floors.
    mode = item.get('default_tint', {}).get('mode', '')
    if mode == 'prismatic':
        floor_idx = max(floor_idx, RARITY_INDEX['legendary'])
    elif mode == 'inverted':
        floor_idx = max(floor_idx, RARITY_INDEX['epic'])
    elif mode == 'shimmer':
        floor_idx = max(floor_idx, RARITY_INDEX['rare'])
    elif mode == 'colorize':
        floor_idx = max(floor_idx, RARITY_INDEX['uncommon'])
    return RARITY_NAMES[floor_idx]


def smooth_drop_weights(item_tier):
    """Spread drop_weights across +/- 1 tier neighbors instead of [0,0,100,0,0]."""
    weights = [0] * 5
    t = max(1, min(5, item_tier))
    weights[t - 1] = 60
    if t >= 2:
        weights[t - 2] = 25
    if t <= 4:
        weights[t] = 12
    if t >= 3:
        weights[t - 3] = 3
    if t <= 3:
        weights[t + 1] = 0  # keep zero — current rule
    # Ensure non-zero in current tier.
    return weights


def merge_affix_pool(item, bumps, items_by_id):
    """Apply flavor bumps to the item's pool, idempotently.

    Pre-2026-06-05 this function ADDED bumps to whatever was already in
    pool — re-running the balance pass compounded the bumps, so an
    item that had been balanced 3 times had 3× the flavor weight.

    Fix: when `_balance_bumps` is present, reverse those exact bumps
    before re-applying. When ABSENT (first run after the fix on items
    that compounded across earlier runs), reset the pool to the
    parent base's authored pool so we rebuild cleanly. Tracks the
    fresh bumps in `_balance_bumps` for the next pass.
    """
    if '_balance_bumps' in item:
        # Reverse prior bumps so the pool returns to its parent-derived state.
        pool = dict(item.get('affix_pool') or {})
        prior = item['_balance_bumps']
        for affix_id, w in prior.items():
            if affix_id in pool:
                pool[affix_id] = pool[affix_id] - int(w)
                if pool[affix_id] <= 0:
                    del pool[affix_id]
    else:
        # No marker = recovery. The pool may have compounded multiple
        # bumps from past balance runs; the safe reset is to rebuild
        # from the parent base's authored affix_pool.
        flavor = parse_flavor(item['id'])
        parent_id = item['id'].rsplit('_' + flavor, 1)[0] if flavor else None
        parent = items_by_id.get(parent_id) if parent_id else None
        if parent and parent.get('affix_pool'):
            pool = dict(parent['affix_pool'])
        else:
            pool = dict(item.get('affix_pool') or {})
    # Apply current bumps and remember them.
    new_bumps = {}
    for affix_id, w in bumps:
        pool[affix_id] = pool.get(affix_id, 0) + int(w)
        new_bumps[affix_id] = new_bumps.get(affix_id, 0) + int(w)
    item['_balance_bumps'] = new_bumps
    return pool


def build_lore(parent_name, flavor, slot):
    base = FLAVOR_LORE.get(flavor)
    if base:
        return base
    return f"A {flavor} variant of the {parent_name.lower()}."


def parent_name_from_id(items_by_id, item, flavor):
    # New-style id is "<parent_id>_<flavor>". Look up the parent in db.
    parent_id = item['id'].rsplit('_' + flavor, 1)[0]
    parent = items_by_id.get(parent_id)
    if parent:
        return parent.get('name', parent_id)
    return parent_id.replace('_', ' ').title()


def main():
    db = json.loads(DB.read_text())
    items_by_id = {it['id']: it for it in db['items']}

    changed = 0
    rarity_bumps = 0
    pool_bumps = 0
    lore_bumps = 0
    dw_bumps = 0
    enchant_bumps = 0

    for item in db['items']:
        flavor = parse_flavor(item['id'])
        if flavor is None:
            continue
        before = json.dumps(item, sort_keys=True)

        # 1. Rarity correction.
        new_rarity = floor_rarity(item, flavor)
        if new_rarity != item.get('rarity'):
            item['rarity'] = new_rarity
            rarity_bumps += 1

        # 2. Flavor-thematic affix pool bumps. Filter bumps to those
        #    whose affix actually applies to this slot (skips
        #    weapon-only "of_sharpness" on a helm, etc). merge_affix_pool
        #    is idempotent — it reverses prior bumps via the
        #    _balance_bumps tracker before applying the current ones.
        bumps = FLAVOR_AFFIX_BUMPS.get(flavor, [])
        if bumps:
            new_pool = merge_affix_pool(item, bumps, items_by_id)
            if new_pool != item.get('affix_pool'):
                item['affix_pool'] = new_pool
                pool_bumps += 1

        # 3. Drop-weight smoothing.
        item_tier = int(item.get('item_tier', 3))
        new_dw = smooth_drop_weights(item_tier)
        if item.get('drop_weights') != new_dw:
            item['drop_weights'] = new_dw
            dw_bumps += 1

        # 4. Lore.
        new_lore = build_lore(parent_name_from_id(items_by_id, item, flavor), flavor, item.get('slot', ''))
        if item.get('lore') != new_lore:
            item['lore'] = new_lore
            lore_bumps += 1

        # 5. Enchant chance bump for legendaries.
        if item.get('rarity') == 'legendary':
            cur_chance = float(item.get('enchant_chance', 0.0))
            if cur_chance < 0.30:
                item['enchant_chance'] = 0.30
                enchant_bumps += 1
        elif item.get('rarity') == 'epic':
            cur_chance = float(item.get('enchant_chance', 0.0))
            if cur_chance < 0.18:
                item['enchant_chance'] = 0.18
                enchant_bumps += 1

        if json.dumps(item, sort_keys=True) != before:
            changed += 1

    DB.write_text(json.dumps(db, indent=2) + '\n')
    print(f'Reviewed all flavor-suffixed items.')
    print(f'  changed:          {changed}')
    print(f'  rarity bumps:     {rarity_bumps}')
    print(f'  affix pool bumps: {pool_bumps}')
    print(f'  drop weights:     {dw_bumps}')
    print(f'  lore rewrites:    {lore_bumps}')
    print(f'  enchant bumps:    {enchant_bumps}')


if __name__ == '__main__':
    main()
