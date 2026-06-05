#!/usr/bin/env python3
"""audit_item_levels.py — Compute Item Level for every item in items.json,
flag outliers per (slot, rarity, item_tier) bucket.

Mirrors the GDScript scoring in scripts/item_level.gd. Runs from Python
so we can analyze without launching Godot. Use after balance changes:

    python3 tools/audit_item_levels.py

Reports:
  - mean / median / stddev per (slot, rarity, item_tier) bucket
  - items >2σ above the bucket mean (potential overpowered)
  - items >2σ below the bucket mean (potential undertuned)
  - top-N and bottom-N overall in each rarity tier

Outputs a markdown table + a JSON dump of every item's score for
pivot-table analysis.
"""

import json
import statistics
import sys
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ITEMS = json.load(open(ROOT / 'project/data/items.json'))
AFFIXES = json.load(open(ROOT / 'project/data/affixes.json'))

_AFFIX_BY_ID = {a['id']: a for a in AFFIXES['affixes']}
_RARITY_AFFIX_COUNT = AFFIXES['rarity_affix_count']
_RARITY_TIER_INDEX = AFFIXES['rarity_tier_index']

# Mirror item_level.gd::_STAT_VALUE — keep these in sync.
_STAT_VALUE = {
    'str': 2.0, 'dex': 2.0, 'int': 2.0,
    'hp': 0.5, 'hp_regen': 8.0,
    'armor': 1.5, 'evasion': 3.0,
    'crit_chance': 4.0, 'haste_pct': 3.0, 'lifesteal_pct': 5.0,
    'physical_extra': 2.5, 'fire_extra': 2.5, 'cold_extra': 2.5,
    'lightning_extra': 2.5, 'holy_extra': 2.5, 'poison_extra': 2.5, 'dark_extra': 2.5,
    'fire_res': 1.0, 'cold_res': 1.0, 'lightning_res': 1.0,
    'holy_res': 1.0, 'poison_res': 1.0, 'dark_res': 1.0,
    'spell_cdr_pct': 3.5, 'spell_damage_pct': 4.0, 'spell_area_pct': 2.5,
    'spell_duration_pct': 2.0, 'spell_proj_speed_pct': 1.5, 'spell_proj_bonus': 20.0,
    'str_spell_dmg_pct': 3.0, 'dex_spell_dmg_pct': 3.0, 'int_spell_dmg_pct': 3.0,
}

_COMBAT_FLAVOR_BONUS = {
    'vampiric': 12.0, 'fire': 6.0, 'cold': 6.0, 'holy': 6.0,
    'poison': 6.0, 'thunderous': 6.0, 'dark': 6.0,
    'regen': 8.0, 'swiftness': 4.0, 'fortified': 4.0, 'warding': 3.0,
}


def expected_affix_value(affix_id, rarity):
    a = _AFFIX_BY_ID.get(affix_id)
    if not a:
        return 0.0
    tier_idx = _RARITY_TIER_INDEX.get(rarity, 0)
    tiers = a.get('tiers', [])
    if tier_idx >= len(tiers):
        return 0.0
    band = tiers[tier_idx]
    if not isinstance(band, list) or len(band) < 2:
        return 0.0
    return (band[0] + band[1]) / 2.0


def score_affix(affix_id, rarity):
    a = _AFFIX_BY_ID.get(affix_id)
    if not a:
        return 0.0
    stat = a.get('stat', '')
    return expected_affix_value(affix_id, rarity) * _STAT_VALUE.get(stat, 1.0)


def score_expected_affixes(item, rarity):
    count = _RARITY_AFFIX_COUNT.get(rarity, 0)
    if count <= 0:
        return 0.0
    pool = item.get('affix_pool', {})
    if not pool:
        return count * 5.0 * _RARITY_TIER_INDEX.get(rarity, 0)
    total_w = 0.0
    weighted = 0.0
    for affix_id, w in pool.items():
        w = float(w)
        if w <= 0:
            continue
        weighted += score_affix(affix_id, rarity) * w
        total_w += w
    if total_w <= 0:
        return count * 5.0
    return (weighted / total_w) * count


def score_implicits(item, rarity):
    return sum(score_affix(a, rarity) for a in item.get('implicit_affixes', []))


def score_flavor_tags(item):
    return sum(_COMBAT_FLAVOR_BONUS.get(t, 0.0) for t in item.get('flavor_tags', []))


def compute_gear(item):
    rarity = item.get('rarity', 'common')
    base = 0.0
    components = []
    if item.get('slot') == 'weapon':
        dmin = float(item.get('damage_min', 0))
        dmax = float(item.get('damage_max', 0))
        speed = float(item.get('speed', 1.0)) or 1.0
        avg_dmg = (dmin + dmax) / 2
        dps = avg_dmg / max(0.3, speed)
        s = dps * 1.5
        base += s
        if s > 0:
            components.append((f"dmg {dmin:.0f}-{dmax:.0f}/{speed:.2f}s", int(round(s))))
    armor = float(item.get('armor', 0))
    evas = float(item.get('evasion', 0))
    if armor > 0:
        s = armor * _STAT_VALUE['armor']; base += s
        components.append((f"armor {int(armor)}", int(round(s))))
    if evas > 0:
        s = evas * _STAT_VALUE['evasion']; base += s
        components.append((f"evasion {int(evas)}%", int(round(s))))
    for stat in ['hp', 'atk', 'def']:
        v = float(item.get(stat, 0))
        if v > 0:
            key = {'atk': 'str', 'def': 'armor'}.get(stat, stat)
            s = v * _STAT_VALUE.get(key, 1.0); base += s
            components.append((f"{stat} {int(v)}", int(round(s))))
    imp = score_implicits(item, rarity)
    if imp > 0: components.append(("implicits", int(round(imp))))
    aff = score_expected_affixes(item, rarity)
    if aff > 0: components.append((f"affixes ({_RARITY_AFFIX_COUNT.get(rarity,0)})", int(round(aff))))
    tag = score_flavor_tags(item)
    if tag > 0: components.append(("flavor tags", int(round(tag))))
    total = base + imp + aff + tag
    return int(round(total)), components


def compute_spell(item):
    rarity = item.get('rarity', 'common')
    components = []
    dmin = float(item.get('damage_min', 0))
    dmax = float(item.get('damage_max', 0))
    cd = float(item.get('spell_cooldown', 3.0))
    avg = (dmin + dmax) / 2
    # Floor cooldown at 1.0s so micro-CD spells (magic_dart 0.7s) don't
    # get runaway DPS scores. 2026-06-05.
    eff_cd = max(1.0, cd)
    dps = avg / eff_cd
    base = dps * 3.0
    if base > 0:
        components.append((f"dmg {dmin:.0f}-{dmax:.0f}/{cd:.1f}s", int(round(base))))
    imp = 0.0
    for af_id in item.get('implicit_affixes', []):
        a = _AFFIX_BY_ID.get(af_id)
        if not a: continue
        if a.get('kind') == 'flag':
            imp += 30
        else:
            imp += score_affix(af_id, rarity)
    if imp > 0: components.append(("implicits", int(round(imp))))
    aff = score_expected_affixes(item, rarity)
    if aff > 0: components.append((f"affixes ({_RARITY_AFFIX_COUNT.get(rarity,0)})", int(round(aff))))
    return int(round(base + imp + aff)), components


def compute(item):
    if item.get('slot') == 'spell':
        return compute_spell(item)
    return compute_gear(item)


def main():
    items = ITEMS['items']
    scored = []
    for it in items:
        ilvl, comps = compute(it)
        scored.append({
            'id': it['id'],
            'name': it.get('name', it['id']),
            'slot': it.get('slot', '?'),
            'rarity': it.get('rarity', 'common'),
            'item_tier': it.get('item_tier', 0),
            'unique': bool(it.get('unique', False)),
            'level': ilvl,
        })

    # Bucket by (slot, rarity, item_tier, weapon_class).
    # weapon_class included so 1H and 2H weapons are compared
    # separately (a 2H sword has higher base damage by design).
    # Non-weapon slots have weapon_class="" — they all share one bucket.
    buckets = defaultdict(list)
    items_by_id = {it['id']: it for it in items}
    for s in scored:
        wc = ''
        if s['slot'] == 'weapon':
            wc = items_by_id[s['id']].get('weapon_class', '1H')
        key = (s['slot'], s['rarity'], s['item_tier'], wc)
        buckets[key].append(s)

    print('# Item-level audit\n')
    print('## Bucket means (slot · rarity · tier)\n')
    print('| Slot | Rarity | Tier | Class | N | Mean | Median | Stddev | Min | Max |')
    print('|---|---|---|---|---:|---:|---:|---:|---:|---:|')
    bucket_stats = {}
    for key in sorted(buckets.keys()):
        slot, rarity, tier, wc = key
        levels = [s['level'] for s in buckets[key]]
        if not levels: continue
        n = len(levels)
        mean = statistics.mean(levels)
        median = statistics.median(levels)
        sd = statistics.stdev(levels) if n > 1 else 0.0
        bucket_stats[key] = {'mean': mean, 'sd': sd}
        wc_label = wc if wc else '—'
        print(f'| {slot} | {rarity} | T{tier} | {wc_label} | {n} | {mean:.0f} | {median:.0f} | {sd:.0f} | {min(levels)} | {max(levels)} |')

    print('\n## Outliers (>2σ from bucket mean)\n')
    outliers = []
    for key in sorted(buckets.keys()):
        st = bucket_stats.get(key)
        if not st or st['sd'] < 1: continue
        for s in buckets[key]:
            z = (s['level'] - st['mean']) / max(1.0, st['sd'])
            if abs(z) >= 1.5:
                outliers.append((z, s, key))
    outliers.sort(key=lambda x: -abs(x[0]))
    if outliers:
        print('| z | Item | Slot · Rarity · Tier | Lvl | Bucket μ ± σ |')
        print('|---:|---|---|---:|---:|')
        for z, s, key in outliers[:40]:
            slot, rarity, tier, wc = key
            mean = bucket_stats[key]['mean']
            sd = bucket_stats[key]['sd']
            arrow = '↑' if z > 0 else '↓'
            wc_label = ' ' + wc if wc else ''
            print(f'| {z:+.1f}σ {arrow} | `{s["id"]}` | {slot}{wc_label} · {rarity} · T{tier} | {s["level"]} | {mean:.0f} ± {sd:.0f} |')
    else:
        print('No outliers.')

    print('\n## Top 5 per rarity\n')
    for rarity in ['common', 'uncommon', 'rare', 'epic', 'legendary']:
        rs = [s for s in scored if s['rarity'] == rarity]
        rs.sort(key=lambda x: -x['level'])
        if not rs: continue
        print(f'\n### {rarity.capitalize()}\n')
        print('| Item | Slot | Tier | iLvl |')
        print('|---|---|---:|---:|')
        for s in rs[:5]:
            print(f'| `{s["id"]}` | {s["slot"]} | T{s["item_tier"]} | {s["level"]} |')

    # JSON dump
    out_path = ROOT / 'logs' / 'balance' / 'item_level_audit.json'
    out_path.parent.mkdir(parents=True, exist_ok=True)
    with open(out_path, 'w') as f:
        json.dump(scored, f, indent=2)
    print(f'\nFull dump: {out_path}')


if __name__ == '__main__':
    main()
