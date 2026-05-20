# Botter — Item Plan

Originally written 2026-05-15 as the 1H sword plan. Expanded the same day to
cover **all gear slots**: weapons, helms, armor, shields, boots, rings, and
amulets. Tool: `tools/item_editor.html` (slot tabs at the top).

Implementation status: **manifests are mockups for review**. Nothing has been
merged into `project/data/items.json` yet. Do a balance pass on these tables
in the editor, then merge per-slot exports into items.json in a follow-up beat.

---

## Scope

This pass mocks up **drafts only**:

- Stat values are within tier bands but **not finely tuned**.
- Items reference DCSS tiles already shipped under `dcss/Dungeon Crawl Stone Soup Full/`.
- Flavor tags document **future** mechanic intent. They cost nothing now —
  most route to one of the 6 affixes as a stat bonus today.
- Drop-weight integration is **not** yet wired to `dungeon.gd` loot rolls.
- Rings/amulets schema slots exist in `save_state.gd` but are NOT yet wired
  to combat, paperdoll, or the Outpost UI.

What this pass **does** ship:

- 7 manifest JSONs (one per slot) under `tools/`, ~189 items total.
- Slot-tabbed editor that loads each manifest, lets you tune stats / pick
  sprites / toggle flavor tags / drag drop weights.
- Per-slot export — each tab downloads `items_<slot>.json` for merge.
- This doc as a single-page reference of the gear system.

---

## What lives where

| File                                    | Purpose                                     |
|-----------------------------------------|---------------------------------------------|
| `tools/items_manifest.json`             | 1H swords (36)                              |
| `tools/items_helms_manifest.json`       | Helms (26)                                  |
| `tools/items_armor_manifest.json`       | Body armor (30)                             |
| `tools/items_shields_manifest.json`     | Shields (22)                                |
| `tools/items_boots_manifest.json`       | Boots (20)                                  |
| `tools/items_rings_manifest.json`       | Rings (29)                                  |
| `tools/items_amulets_manifest.json`     | Amulets (26)                                |
| `tools/item_editor.html`                | Browser editor (serve via `python3 -m http.server`) |
| `project/data/items.json`               | Live, in-game item data — merge target.    |

To run the editor:
```
cd /Users/dyo/claude/botter
python3 -m http.server 8080
# open http://localhost:8080/tools/item_editor.html
```

---

## Stat ceiling (project-wide, see CLAUDE.md)

End-game bot caps: **~1500 HP / ~300 ATK / ~100 DEF**, peak hits 300–400.
Affix tiers (`data/affixes.json`):
- Strength legendary = +18 ATK
- Stamina legendary = +90 HP
- Agility legendary = +11 DEF
- Regen, Crit, Haste — see file

Items in this plan respect those limits — even fully-stacked T5 gear with
4 legendary affixes won't bust the ceiling.

---

## Drop weight system

Each item has `drop_weights: [T1, T2, T3, T4, T5]` — relative probability to
appear in each dungeon-tier loot pool. 0 = never drops there.

**Distribution philosophy** (item-tier on the left, drop tier across the top):

```
Item Tier →   T1   T2   T3   T4   T5  (dungeon tier)
   1 items:  [80,  15,   0,   0,   0]  ← only in early game
   2 items:  [15,  65,  25,   3,   0]  ← mainly T1-T2, fade out
   3 items:  [ 0,  15,  60,  25,   5]  ← T2-T3 sweet spot
   4 items:  [ 0,   0,  10,  58,  32]  ← T3-T4 sweet spot
   5 items:  [ 0,   0,   0,  12,  72]  ← endgame only
   uniques:  [ 0,   0,   0,   5,  22]  ← rare even in endgame
```

Uniques use lower weights because they're `unique: true` — once dropped per
run they shouldn't appear again. Implementation should track which uniques
have been dropped this run and exclude them from subsequent rolls.

---

## Flavor tag system

Tags are stored on items, document **future** mechanic intent, and most
currently route to the matching affix-bonus stat.

Common across all slots:

| Tag          | Color     | Future mechanic                                       |
|--------------|-----------|-------------------------------------------------------|
| `fortified`  | #aaccdd   | Flat damage reduction                                 |
| `stealth`    | #666688   | Lower aggro range                                     |
| `swiftness`  | #aaddff   | +Move speed                                           |
| `regen`      | #66cc88   | HP regen tick                                         |
| `willpower`  | #ffaa88   | Magic resistance                                      |
| `lordly`     | #ffdd44   | Aura buff (+ATK / +DEF)                               |
| `fortune`    | #ffdd44   | Bonus gold/loot                                       |
| `vision`     | #ffeebb   | See-invisible / extended fog reveal                   |
| `wisdom`     | #cc88ff   | +XP gain                                              |
| `elemental`  | #ff8866   | Multi-element resistance                              |
| `fire_res` / `cold_res` / `poison_res` | (color) | Per-element resistance |

Slot-specific tags (sword: `precision/dragon_bane/sound/death/...`,
shield: `reflective/thorns/mayhem/stardust`, boots: `flying/rampaging/earth/footwork`,
amulet: `harm/rage/guardian/acrobat/vitality/faith`,
ring: `slaying`).

The full list per slot lives in each manifest's `flavor_tags` block.

---

## 1H Swords (36)

Base types from DCSS `item-prop.cc`:

| Base type     | DCSS dmg | DCSS spd | Skill        | Flavor                                |
|---------------|----------|----------|--------------|---------------------------------------|
| Dagger        | 4        | 10       | Short blades | Fast, stabbing. Crit/Agility shine.  |
| Knife         | 4        | 13       | Short blades | Improvised. Low floor, low ceiling.  |
| Quick Blade   | 4        | **15**   | Short blades | Extreme speed, low raw dmg.          |
| Short Sword   | 5        | 10       | Short blades | Balanced entry. Crit-neutral.        |
| Rapier        | 7        | 12       | Short blades | Thrusting. High crit multiplier.     |
| Falchion      | 8        | 13       | Long blades  | Single-edge curved. Workhorse.       |
| Long Sword    | 10       | 14       | Long blades  | Standard 1H. Reliable.               |
| Scimitar      | **12**   | 14       | Long blades  | Highest base damage in 1H class.     |
| Sabre         | 10       | 14       | Long blades  | Cavalry sword. Balanced.             |
| Katana        | 10       | 13       | Long blades  | Precise. High crit flavor.           |
| Demon Blade   | **13**   | 13       | Long blades  | Infernal. Future: fire damage.       |

**Key insight from DCSS**: Short blades are fast/precise (Crit/Agility),
Long blades have higher raw damage (Strength/Stamina). Katana sits between —
high damage *and* precision.

ATK band per item-tier: T1 10–20, T2 20–30, T3 32–42, T4 38–58, T5 64–100.

T5 includes 7 unique/legendary swords (Singing Sword / Chilly Death /
Firestarter / Bloodbane / Wyrmbane / Gyre / Doom Knight's Blade) with fully
documented `future_mechanic` payloads.

**Sword sprite hotfix landed in this pass**: 7 of the original 36 swords
referenced files that didn't exist (e.g. `short_sword_1.png` — the actual
asset is `short_sword_1_new.png`). All 36 sword tiles now resolve.

## Helms (26)

DCSS base types: hat (AC 0, more ego variety), helmet (AC 1, heavier).

Botter base types in the manifest:

| Base type    | DCSS base | Flavor                                          |
|--------------|-----------|------------------------------------------------|
| Skullcap     | hat       | Improvised; small DEF, light HP                 |
| Cap          | hat       | Padded cloth/leather; tinkery                   |
| Hood         | hat       | Stealth-flavored                                |
| Wizard Hat   | hat       | Pointed mage hat; mana/regen synergy            |
| Helmet       | helmet    | Hardened steel; higher DEF                       |
| Great Helm   | helmet    | Full visored; heaviest 1H-class                  |
| Crown        | helmet    | Royal regalia; end-game flavor                   |

DEF band per item-tier: T1 1–3, T2 3–5, T3 6–8, T4 9–10, T5 9–14.
HP band per item-tier: T1 18–42, T2 50–60, T3 75–95, T4 95–125, T5 130–185.

T5 uniques: Hat of Pondering (urand_pondering), Cornuthaum (the "Wizard's
Hat"), Helm of the Dragon (urand_dragonmask), Crown of Dyrovepreva,
Helm of the High Council. Each carries a documented `future_mechanic`.

## Body Armor (30)

DCSS base types from `item-prop.cc` (AC values):

| Base type      | DCSS AC | Flavor                                       |
|----------------|---------|---------------------------------------------|
| Robe           | 2       | Cloth, fast, casts well                      |
| Leather        | 3       | Light, mobile; stealth/agility flavor        |
| Studded leather| 3       | Reinforced leather; mid-light option         |
| Ring mail      | 5       | Riveted iron rings; common medium             |
| Scale mail     | 6       | Layered metal scales; solid mid-tier         |
| Splint mail    | 7       | Strips of metal over chain; heavy/flexible   |
| Banded mail    | 7       | Concentric bands; mid-heavy                  |
| Chain mail     | 8       | Interlinked rings; workhorse heavy           |
| Plate          | 10      | Forged plates; heaviest standard              |
| Crystal plate  | 14      | Living crystal lattice; end-game              |
| Troll leather  | 3+regen | Light hide; future regen mechanic            |
| Dragon scales  | 5–12+ego| Dragon hide; element-coded                    |

DEF band per item-tier: T1 2–7, T2 4–10, T3 10–14, T4 16–18, T5 19–28.
HP band per item-tier: T1 45–85, T2 75–115, T3 130–160, T4 165–200, T5 210–300.

Dragon armours occupy T4–T5: swamp (poison_res), ice (cold_res), fire
(fire_res), shimmering (willpower), shadow (stealth), gold (elemental
fortified), pearl (willpower regen).

T5 legendary uniques: Lear's Chainmail, Robe of Folly, Ratskin Cloak,
Starlight Cloak, Robe of Misfortune, Etheric Cage. Each balanced with a
risk/reward `future_mechanic` (Bloodbane-style heal-on-cost, regen-with-DEF-
penalty, etc).

## Shields (22)

DCSS base types from `item-prop.cc`:

| Base type     | DCSS SH | Flavor                                       |
|---------------|---------|---------------------------------------------|
| Buckler       | 3       | Small round shield; light, fast, parries    |
| Round shield  | 4       | Mid-size; balanced parry/block              |
| Kite shield   | 8       | Large body shield; heavy block              |
| Tower shield  | 13      | Wall on a strap; heaviest 1H-class          |
| Orb           | 0+ego   | Magical offhand; flavor over flat block     |

DEF band per item-tier: T1 4–9, T2 7–11, T3 9–14, T4 11–21, T5 14–26.

T5 legendary uniques: Louise's Shield (urand reflect-with-speed-penalty),
Shield of War (urand_war), Bullseye (urand_bullseye, ranged-block focus),
The Gong (urand_gong, AoE-stun-on-block tradeoff).

## Boots (20)

DCSS base type: boots (AC 1) with egos for flying / stealth / rampaging /
earth. Sparse tile library (8 base sprites in `item/armor/feet/`), so T4–T5
leans on artefact uniques (urand_fencer, urand_assassin, urand_thief,
urand_flash).

DEF band per item-tier: T1 1–3, T2 3–5, T3 4–7, T4 6–11, T5 7–14.

T5 legendary uniques: Fencer's Slippers, Assassin's Boots, Thief's Boots,
Boots of Flash, Treads of Apocalypse. Mostly `swiftness/stealth/footwork`-
flavored to differentiate from heavier T5 greaves.

## Rings (29)

DCSS base types from `item-prop-enum.h` jewellery_type. Mapped to Botter
base_types:

| Base type        | DCSS enum                       | Flavor                                |
|------------------|---------------------------------|---------------------------------------|
| Ring of Protection | RING_PROTECTION              | +DEF; defensive build cornerstone     |
| Ring of Strength | RING_STRENGTH                   | +ATK; direct damage scaler            |
| Ring of Slaying  | RING_SLAYING                    | +ATK and accuracy; hunter's classic   |
| Ring of Evasion  | RING_EVASION                    | +DEF via dodge                        |
| Ring of Dexterity| RING_DEXTERITY                  | +Crit/+Haste; speed-flavored          |
| Ring of Regen    | RING_REGENERATION               | +HP regen; sustained build            |
| Ring of Fire/Cold/Poison Res | RING_PROTECTION_FROM_*| Per-element resistance              |
| Ring of Stealth  | RING_STEALTH                    | Lower aggro range                     |
| Ring of Willpower| RING_WILLPOWER                  | Magic resistance                      |
| Ring of Magic Power | RING_MAGICAL_POWER           | End-game caster ring                  |
| Ring of Flight   | RING_FLIGHT                     | Ignore terrain hazards                |

Rings are **two equip slots** in the schema (ring1, ring2). Stats lean small
but stack — rings are the affix-spreader slot.

ATK band: T1 0–2, T2 0–3, T3 2–4, T4 4–6, T5 0–7 (uniques cap at 8).
DEF band: T1 0–2, T2 1–3, T3 1–4, T4 2–5, T5 3–7.
HP band: T1 5–18, T2 14–22, T3 22–30, T4 35–45, T5 50–90.

T5 legendary uniques: Octoring (counts as 2 slots), Ring of Robustness,
Ring of Shadows, Shaolin Ring, Ring of the Mage.

## Amulets (26)

DCSS base types from `item-prop-enum.h`:

| Base type             | DCSS enum                | Flavor                              |
|-----------------------|--------------------------|-------------------------------------|
| Amulet of Reflection  | AMU_REFLECTION           | Reflects ranged attacks             |
| Amulet of Regeneration| AMU_REGENERATION         | Steady HP regen                     |
| Amulet of Mana Regen  | AMU_MANA_REGENERATION    | Mana regen; future caster mechanic  |
| Amulet of Faith       | AMU_FAITH                | Stronger altar blessings            |
| Amulet of Rage        | AMU_RAGE                 | Berserker trigger                   |
| Amulet of Harm        | AMU_HARM                 | Trade defense for damage            |
| Amulet of Guardian    | AMU_GUARDIAN_SPIRIT      | Damage routes through HP and MP     |
| Amulet of Acrobat     | AMU_ACROBAT              | Bonus dodge while moving            |
| Amulet of Vitality    | (unique)                 | End-game HP boost                   |
| Amulet of Air         | (unique)                 | Wind-themed; lightning res          |

Amulets are **a single equip slot** and are the run-flavoring slot —
mostly utility over raw stats.

T5 legendary uniques: Amulet of Vitality, Amulet of Air (urand_air),
Amulet of Bloodlust (high ATK with DEF drawback), Brooch of Shielding,
Cekugob's Amulet (once-per-run prevent-fatal), The Four Winds, The Finger
(big-damage cost-trade).

---

## Implementation notes for dev agent

When wiring this into `project/data/items.json` and the runtime:

1. **Merge per-slot exports.** The editor downloads `items_<slot>.json`.
   Append each slot's array into the `items[]` array of
   `project/data/items.json`. Old weapon entries (rusty_dagger,
   iron_shortsword, chipped_claymore, etc.) and old armor/helm/boots/shield
   entries should be replaced with the new lists. Keep `rusty_dagger` and
   `tattered_hide` IDs alive — they're the starter gear referenced by
   `save_state.gd::_default()`.

2. **New fields per item.** Each item gains `item_tier`, `base_type`,
   `flavor_tags`, `lore`, `drop_weights` fields. GDScript Dictionary
   `.get()` defaults already handle unknown fields gracefully, so older
   loaders won't break.

3. **Drop weight implementation.** In `dungeon.gd` (loot drop logic),
   replace the current rarity-flat pool with: filter items where
   `drop_weights[current_biome_tier - 1] > 0`, then weighted random pick.
   The biome tier comes from the `tier` field in `biomes.json`.

4. **Unique items.** Add `run_dropped_uniques: []` to the dungeon run state.
   Before rolling a unique, check it's not already in the list. On drop,
   add to list. Reset at run start.

5. **Auto-equip logic.** Currently equips highest ATK. This will skip Quick
   Blade and skip lower-ATK swift/precision items. Acceptable for MVP.
   Future: weight by effective DPS estimate including flavor tags.

6. **Sprite tiles.** All manifests reference paths under `dcss/Dungeon Crawl
   Stone Soup Full/`. For runtime rendering, copy the referenced PNGs into
   `project/assets/tiles/items/`. The DCSS tile pack is gitignored — this
   copy step is manual. (See atlas viewer + `python3 tools/build_atlas.py`.)

7. **Jewellery wiring (deferred).** `save_state.gd::_default()` now has
   `ring1`, `ring2`, `amulet` slots, but they're NOT yet wired to:
   - `bot.recompute_stats` (it iterates `equipped.keys()` defensively, so
     null slots are skipped — but `items_db_cache` doesn't yet have ring/
     amulet base_ids).
   - `paperdoll_renderer.gd` (no anchors / overlay paths defined for jewellery).
   - `outpost.gd` SLOTS const (only the original 5 slots).
   - HUD bag / equip flow (`hud_chrome.gd::update_equipped` doesn't render
     ring/amulet tooltips).
   When wiring later: add anchors to `paperdoll_renderer.gd::ANCHOR_OFFSETS`,
   add `ring1`/`ring2`/`amulet` to outpost.gd SLOTS, hook tooltips in HUD.

8. **Affix system (already done).** All 6 affixes (Strength/Stamina/Agility/
   Regen/Crit/Haste) work on any slot. No per-slot affix restriction needed
   for this pass.

9. **Bot starter gear unchanged.** rusty_dagger + tattered_hide remain the
   defaults. Their stats don't change in this pass.

---

## Open questions for user review (post-balance pass)

1. **Stat ATK numbers** are softer than the current items.json
   (rusty_dagger was ATK 16, now ATK 12). Re-validate against the bot's
   base_atk 6 and a typical T1 boss.

2. **Quick Blade positioning** — at ATK 20 it sits below its tier peers.
   Right tradeoff for the speed/crit flavor, or boost ATK until those
   mechanics are wired?

3. **Jewellery balance**. Rings stack 2 slots; amulets only 1. Default
   stat budgets reflect that — verify it doesn't make 2x ring builds
   strictly dominant.

4. **Unique density.** Currently 7 sword uniques + 5 helm + 6 armor + 4
   shield + 5 boot + 5 ring + 7 amulet = **39 uniques** total. Feels right
   for an initial pass; can grow if endgame loot hunting feels thin.

5. **Drawback mechanics on uniques** (e.g. Bloodlust Amulet's +ATK/-DEF,
   Etheric Cage's -move speed) need a `drawback_*` field schema before
   wiring. For now they live in `future_mechanic` text only.

6. **Sabre coverage.** Only one sabre item (Silver Sabre, T3) — the manifest
   has Sabre as a base type but few base sprites match. Add a T2 cavalry
   sabre and a T4 unique sabre if you want more variety in the curved-
   blade space.

7. **Sprites we DIDN'T use.** The DCSS tile pack has many more artefact
   tiles than this pass uses. For example: `urand_resistance`,
   `urand_zhor`, `urand_clouds`, `urand_faerie` (armor); `urand_air` (used
   for amulet but armor has urand_air variants too); `urand_singing_sword`
   variants. Atlas viewer (`tools/atlas_viewer.html`) is the place to scout
   if you want to add more uniques later.
