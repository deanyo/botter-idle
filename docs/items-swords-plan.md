# Botter — 1H Sword Item Plan

Written: 2026-05-15. For review before implementation. Tool: `tools/item_editor.html`.
Implementation: after user sign-off, merge the exported JSON into `project/data/items.json`.

---

## Scope

This document covers **1-handed swords only**. Other weapon slots (axes, maces, staves)
and armor slots (helm, boots, armor, shield) follow after review. 

Items in this pass are defined with current simple stats (ATK / DEF / HP) and **flavor
tags** that document the intended future mechanic. The tags are data-only — they cost
nothing now but prevent "fiery sword" from just being another +ATK sword forever.

---

## Base Types — DCSS-derived, 1H only

From DCSS `item-prop.cc` (damage, speed, skill group). Used to inform stat tuning.

| Base type     | DCSS dmg | DCSS spd | Skill         | Flavor                              |
|---------------|----------|----------|---------------|-------------------------------------|
| Dagger        | 4        | 10       | Short blades  | Fast, stabbing. Crit/Agility shine. |
| Knife         | 4        | 13       | Short blades  | Improvised. Low floor, low ceiling. |
| Quick Blade   | 4        | **15**   | Short blades  | Extreme speed, low raw dmg. Future: attack speed. |
| Short Sword   | 5        | 10       | Short blades  | Balanced entry. Crit-neutral.       |
| Rapier        | 7        | 12       | Short blades  | Thrusting. High crit multiplier flavor. |
| Falchion      | 8        | 13       | Long blades   | Single-edge curved. Mid-tier workhorse. |
| Long Sword    | 10       | 14       | Long blades   | Standard 1H. Reliable, slightly boring. |
| Scimitar      | **12**   | 14       | Long blades   | Highest base damage in 1H class.    |
| Sabre         | 10       | 14       | Long blades   | Cavalry sword. Balanced.            |
| Katana        | 10       | 13       | Long blades   | Precise. High crit flavor.          |
| Demon Blade   | **13**   | 13       | Long blades   | Infernal. Future: fire damage on hit. |

**Key insight from DCSS:** Short blades are fast/precise (Crit/Agility affixes), Long
blades have higher raw damage (Strength/Stamina affixes). Katana sits between them —
high damage *and* precision. This maps cleanly to our 5-stat system.

---

## Flavor Tags Reference

Tags are stored on items and documented for future mechanics. Current effect in brackets.

| Tag          | Color     | Current effect              | Future mechanic                                    |
|--------------|-----------|-----------------------------|----------------------------------------------------|
| `fire`       | #ff6633   | Strength affix bonus        | Fire damage on hit (light_spec already wired)      |
| `ice`        | #66ccff   | Agility affix bonus         | Freeze/slow chance on hit                          |
| `holy`       | #ffeebb   | Stamina affix bonus         | +bonus damage vs undead/demon enemies              |
| `dark`       | #9966cc   | Crit affix bonus            | Defense reduction debuff                           |
| `vampiric`   | #cc3366   | Regen affix bonus           | Lifesteal per hit                                  |
| `poison`     | #66cc44   | No current effect           | Damage over time ticks                             |
| `swift`      | #aaddff   | Agility affix bonus         | Attack speed increase                              |
| `precision`  | #ffdd88   | Crit affix bonus            | Higher crit multiplier (2.0× vs 1.5×)             |
| `magic`      | #cc88ff   | No current effect           | Penetrates magic resistance                        |
| `brutal`     | #ff8844   | Strength affix bonus        | Armor penetration (ignore % of DEF)                |
| `dragon_bane`| #ffaa22   | No current effect           | +50% damage vs dragon-type enemies                 |
| `arcane`     | #aa88ff   | No current effect           | Double-strike mechanic                             |
| `crystal`    | #88ddff   | No current effect           | Chance to shatter (AoE hit adjacent cells)         |
| `sound`      | #ffccaa   | No current effect           | ATK scales with kill count this run                |
| `death`      | #884466   | No current effect           | Death mark: target takes +25% damage for 3s        |

---

## Drop Weight System

Each item has `drop_weights: [T1, T2, T3, T4, T5]` — relative probability to appear
in the loot pool for each dungeon tier. Higher = more likely vs. other items in that
tier's pool. 0 = never drops there.

**Implementation note for dev agent:** When rolling item drops, first determine the
dungeon tier being run. Filter items where `drop_weights[dungeon_tier-1] > 0`. Weighted
random pick from the filtered pool. Items with weight 0 cannot appear.

### Distribution philosophy

```
Item Tier →   T1   T2   T3   T4   T5  (dungeon tier)
   1 items:  [80,  15,   0,   0,   0]  ← only in early game
   2 items:  [15,  65,  25,   3,   0]  ← mainly T1-T2, fade out
   3 items:  [ 0,  15,  60,  25,   5]  ← T2-T3 sweet spot
   4 items:  [ 0,   0,  10,  58,  32]  ← T3-T4 sweet spot
   5 items:  [ 0,   0,   0,  12,  72]  ← endgame only
   uniques:  [ 0,   0,   0,   5,  22]  ← rare even in endgame
```

Uniques use lower weights because they're `unique: true` — once dropped per run they
shouldn't appear again. The implementation should track which uniques have been dropped
this run and exclude them from subsequent rolls.

---

## The Sword List

### Tier 1 — Dungeon Swords

These drop in the Dungeon (T1) and occasionally surface in T2. Common to uncommon.
A freshly deployed bot should find something useful here within 3 floors.

| ID                 | Name               | Base Type   | ATK | HP | Rarity   | Flavor Tags    | Lore snippet                                      |
|--------------------|--------------------|-------------|-----|----|----------|----------------|---------------------------------------------------|
| rusty_dagger       | Rusty Dagger       | dagger      | 12  | 0  | common   |                | More rust than iron.                              |
| bone_knife         | Bone Knife         | knife       | 10  | 0  | common   |                | Fashioned from something that used to be alive.   |
| shiv               | Shiv               | dagger      | 13  | 0  | common   |                | Improvised. Effective. Ugly.                      |
| chipped_shortsword | Chipped Short Sword| short_sword | 16  | 0  | common   |                | Serviceable, if you ignore the nicks.             |
| iron_dagger        | Iron Dagger        | dagger      | 18  | 2  | uncommon |                | Standard issue for those who prefer not to be seen. |
| short_falchion     | Short Falchion     | falchion    | 20  | 2  | uncommon |                | A light curved blade. More than it looks.         |

**Tier 1 design note:** Starter bot has `rusty_dagger` (ATK 12). By end of first run
through Dungeon (T1 boss kill), bot should have found an uncommon (ATK 18-22). That's
the gear-up moment before entering T2.

### Tier 2 — Surface Swords

Drops in T1-T2. The "decent gear" zone before the player reaches the Wilds (T3).

| ID                | Name               | Base Type   | ATK | HP | Rarity  | Flavor Tags        | Lore snippet                                |
|-------------------|--------------------|-------------|-----|----|---------|--------------------|--------------------------------------------|
| steel_shortsword  | Steel Short Sword  | short_sword | 24  | 4  | uncommon|                    | Properly forged. An honest weapon.          |
| elven_dagger      | Elven Dagger       | dagger      | 22  | 3  | uncommon| swift              | Light enough to forget, until you aren't.  |
| iron_falchion     | Iron Falchion      | falchion    | 28  | 4  | uncommon|                    | A broad single-edge blade.                 |
| orcish_shortsword | Orcish Short Sword | short_sword | 30  | 5  | uncommon| brutal             | Crudely made. Hits like one anyway.        |
| rapier            | Rapier             | rapier      | 26  | 3  | rare    | precision          | Rewards patience.                           |
| quick_blade       | Quick Blade        | quick_blade | 20  | 4  | rare    | swift, precision   | The fastest blade in the Dungeon.           |

**Quick Blade note:** Lower ATK than a Rapier at same item_tier, but `swift` + `precision`
tags mean it should eventually attack faster with higher crit. For now it's a trade-off
(lower raw ATK). The bot's auto-equip logic should weigh this — current code equips
highest ATK, which will always skip Quick Blade. This is acceptable for MVP; future
combat rework will make it viable.

### Tier 3 — Wilds Swords

Drops in T2-T3. The player should be farming T3 to unlock T4. Rare tier.

| ID                | Name                | Base Type   | ATK | HP  | Rarity | Flavor Tags       | Lore snippet                                   |
|-------------------|---------------------|-------------|-----|-----|--------|-------------------|------------------------------------------------|
| steel_falchion    | Steel Falchion      | falchion    | 36  | 6   | rare   |                   | A proper blade, properly made.                 |
| mithril_shortsword| Mithril Short Sword | short_sword | 34  | 7   | rare   |                   | Light. Strong. Expensive to replace.           |
| iron_longsword    | Iron Long Sword     | long_sword  | 38  | 6   | rare   |                   | A proper weapon for a proper fight.            |
| silver_rapier     | Silver Rapier       | rapier      | 32  | 5   | rare   | precision, holy   | Undead hate it.                                |
| scimitar          | Scimitar            | scimitar    | 42  | 6   | rare   |                   | A curve that finds every gap in armor.         |
| silver_sabre      | Silver Sabre        | sabre       | 40  | 5   | rare   | holy              | Silver-edged. Blessed. Smells of incense.      |

**Silver Rapier note:** Holy + precision makes this the go-to weapon for Crypt (T4 branch
full of undead). Even though it's item tier 3, smart players will keep it for Crypt runs
specifically. This is intentional — flavor creates attachment.

### Tier 4 — Vault Swords

Drops in T3-T4. Epic tier. The player should feel like they've earned these.

| ID                | Name                | Base Type   | ATK | HP  | Rarity | Flavor Tags       | Lore snippet                                          |
|-------------------|---------------------|-------------|-----|-----|--------|-------------------|-------------------------------------------------------|
| steel_longsword   | Steel Long Sword    | long_sword  | 48  | 8   | rare   |                   | Dependable. Exactly as good as it needs to be.        |
| elven_shortsword  | Elven Short Sword   | short_sword | 38  | 8   | epic   | swift, precision  | Almost too light to feel. Very sharp.                 |
| runed_falchion    | Runed Falchion      | falchion    | 52  | 10  | epic   | magic             | Sigils run down the blade, each one a name.           |
| mithril_longsword | Mithril Long Sword  | long_sword  | 56  | 10  | epic   |                   | Light enough to carry all day, heavy enough to end it.|
| iron_katana       | Katana              | katana      | 50  | 9   | epic   | precision, swift  | Simple. Exact. Deadly.                                |
| runed_scimitar    | Runed Scimitar      | scimitar    | 58  | 11  | epic   | magic             | The runes pulse when it cuts. Nobody knows why.       |
| elven_broadsword  | Elven Broadsword    | long_sword  | 54  | 10  | epic   | swift, magic      | Longer than it looks. Lighter than possible.          |

**Katana note:** ATK (50) is lower than Runed Scimitar (58) but `precision + swift` tags
mean it should eventually be competitive or better for Crit-heavy builds. For now it's
the "feels cool, plays slightly behind curve" option.

### Tier 5 — Planes Swords (Standard)

Drops only in T4-T5. Epic to legendary. End-game baseline.

| ID                | Name                | Base Type   | ATK | HP  | Rarity    | Flavor Tags        | Lore snippet                                      |
|-------------------|---------------------|-------------|-----|-----|-----------|--------------------|---------------------------------------------------|
| crystal_longsword | Crystal Long Sword  | long_sword  | 68  | 14  | epic      | magic, crystal     | Hums when hungry.                                 |
| mithril_katana    | Mithril Katana      | katana      | 64  | 13  | epic      | precision, swift   | Forged over seven years. Used for the rest.       |
| ancient_sword     | Ancient Sword       | long_sword  | 72  | 16  | epic      | dark, death        | Nobody remembers who made it. Nobody dares ask.   |
| demon_blade       | Demon Blade         | demon_blade | 80  | 16  | legendary | fire, demon        | Forged in a plane that shouldn't exist.           |

### Tier 5 — Unique Swords

One per run maximum. Guaranteed legendary. Only from T4 bosses (rarely) and T5 floors.
The DCSS artefact sprite library has these exact tiles.

| ID                 | Name                     | ATK | Flavor Tags           | Flavor / Future mechanic                                   |
|--------------------|--------------------------|-----|-----------------------|------------------------------------------------------------|
| singing_sword      | The Singing Sword        | 88  | magic, sound          | ATK scales with kills this run (+1/10 kills)               |
| chilly_death       | Chilly Death             | 78  | ice, cold             | 15% freeze on hit. Frozen enemies take +20% damage.        |
| firestarter        | Firestarter              | 85  | fire                  | Burn DoT on hit (3 ticks at 5% max HP). Light spec wired.  |
| bloodbane          | Bloodbane                | 80  | vampiric, dark        | Lifesteal: heal 8% of damage dealt on every hit.           |
| wyrmbane           | Wyrmbane                 | 92  | holy, dragon_bane     | +50% vs dragon-type enemies.                               |
| gyre               | Gyre                     | 90  | arcane, dual          | Hits twice per attack at 70% damage each.                  |
| doom_knight_blade  | The Doom Knight's Blade  | 100 | dark, death           | Death mark: target takes +25% damage for 3s.               |

**Firestarter note:** This already exists in the game as a `weapon_light` reference in
`bot.gd`. The item stats need to be updated to match this tier-5 spec (current entry has
ATK 72, which undersells a legendary). The `light_spec` stays as-is.

---

## Stat Progression Summary

This table shows ATK values across item tiers. The band should feel like each tier is
~30-40% stronger than the previous, roughly matching the `TIER_SCALE` dungeon enemy
scaling from `gameplay-loop-plan.md`.

```
Item Tier   ATK range     Rarity range
   1        10–20         common / uncommon
   2        20–30         uncommon / rare
   3        32–42         rare
   4        38–58         rare / epic
   5        64–100        epic / legendary
```

The Quick Blade (T2, ATK 20) intentionally sits at the bottom of its tier — the speed
and crit tags are its value proposition, not raw ATK.

---

## Implementation Notes for Dev Agent

1. **items.json merge:** The editor exports `items_1h_swords.json`. Merge its
   `items_1h_swords` array into `project/data/items.json`'s `"items"` array.
   Old weapon entries (rusty_dagger, iron_shortsword, chipped_claymore, etc.) should
   be replaced with this new list. Keep armor/helm/boots/shield entries untouched.

2. **New fields in items.json:** Each item gains `item_tier`, `base_type`,
   `flavor_tags`, `lore`, and `drop_weights` fields. `garage.gd` and `dungeon.gd`
   should ignore unknown fields gracefully — GDScript Dictionary access with `.get()`
   defaults will handle this.

3. **Drop weight implementation:** In `dungeon.gd`, the current loot drop logic
   picks items by rarity from a flat pool. Replace with: filter items where
   `drop_weights[current_biome_tier - 1] > 0`, then weighted random pick. The biome
   tier comes from the `tier` field we're adding to `biomes.json` (Beat 2 in
   gameplay-loop-plan.md).

4. **Unique items:** Add `run_dropped_uniques: []` to the dungeon run state. Before
   rolling a unique, check it's not already in the list. On drop, add to list.
   Reset at run start.

5. **Firestarter stats update:** Change current `firestarter` entry from ATK 72 to
   ATK 85, add `item_tier: 5`, add `flavor_tags: ["fire"]`, add `lore`. The
   `weapon_light` mapping in `bot.gd` stays untouched.

6. **Auto-equip logic:** Currently auto-equips highest ATK. This will always skip
   Quick Blade for anything with higher ATK. Acceptable for MVP. Future: weight by
   effective DPS estimate including flavor tags.

7. **Sprite tiles:** The items in this plan use DCSS tile pack paths. For the game
   to render them, the referenced PNGs need to be copied to `project/assets/tiles/items/weapons/`.
   After confirming the list, run a copy pass from `dcss/Dungeon Crawl Stone Soup Full/`
   to the project assets. The DCSS tile pack is gitignored — this copy step is manual.

8. **rusty_dagger as starter:** Keep `rusty_dagger` in `save_state.gd`'s `_default()`.
   Its ATK drops from 16 to 12 in this plan (more appropriate for "rusty"). The starter
   bot is correspondingly weaker — this is intentional (see gameplay-loop-plan.md
   Early Hook section: first run should find an upgrade).

---

## Open Questions for User Review

1. **ATK values:** The tier 1-2 numbers are softer than current items.json (rusty_dagger
   was ATK 16, now 12). Does this feel right given the bot starts combat with base_atk 6?
   Total ATK at T1 start: 6 (base) + 12 (rusty) = 18. At T2: ~30-36. At T3: ~50-60.

2. **Quick Blade positioning:** It sits at T2 with ATK 20 — deliberately below its tier
   peers. Is that the right trade-off for the speed/crit flavor, or should it have higher
   ATK for now (since those mechanics aren't wired yet)?

3. **Unique count:** 7 uniques feels right for an initial pass, but if you want denser
   endgame loot hunting, more can be added. The artefact tile library has many more
   sword tiles (vampires_tooth, arc_blade, serpent_scourge, eos, jihad, etc).

4. **Sabre (curved sabre):** Currently `sabre_2.png` isn't assigned to any item in this
   draft. There's room for a T3-T4 sabre if you want more cavalry-sword options.
   Alternatively, the sabre slot could be filled by an uncommon T2 curved sabre.
