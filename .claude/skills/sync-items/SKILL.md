---
name: sync-items
description: Run the full Item-Generator import pipeline — balance pass on all flavor-suffixed variants in items.json, then backfill per-slot item manifests so the editor sees the changes. Run after merging generator exports, hand-editing items.json, or whenever the editor is missing items that exist in-game. Both steps are idempotent.
user_invocable: true
---

# Botter sync-items

Two-step pipeline that closes the loop after Item Generator output reaches
`project/data/items.json`. Run both steps every time, in this order:

1. **Balance pass** — walk every flavor-suffixed variant in items.json
   and tighten its design (rarity floor, affix-pool weighting, drop-weight
   curve, themed lore, enchant-chance bumps).
2. **Manifest sync** — propagate items.json → tools/items_*_manifest.json
   so `tools/item_editor.html` sees the changes (both new items and
   content updates from step 1).

## Usage

Run both, in this order:

```bash
python3 /Users/dyo/claude/botter/tools/balance_generated_items.py
python3 /Users/dyo/claude/botter/tools/sync_manifests_from_items_json.py
```

The first prints stats per rule (`rarity bumps`, `affix pool bumps`, etc).
The second reports `+N new` / `~N updated` per manifest, or `All manifests
already in sync` when nothing changed.

## When to run

- **After merging a generator export** into items.json (the most common
  case — every time the user cherry-picks variants from the in-game Item
  Generator and asks you to add them to the database).
- **After hand-editing items.json** to add or modify an item directly.
- **When the user reports an item missing or outdated** in the editor.

## What balance_generated_items.py does

A flavor-suffixed item is one whose id ends in a flavor token (e.g.
`amulet_finger_rosegold`, `demon_blade_umbral`, `iron_falchion_twisted` —
25 flavors total: crimson, voidwrought, prismatic, ironclad, etc).

For each:

1. **Rarity floor** — prismatic → legendary always; inverted/twisted/
   spectral → ≥ epic; shimmer → ≥ rare; colorize → ≥ uncommon. Existing
   higher rarities are kept. Generator-rolled "common crimson sword"
   becomes uncommon at minimum.
2. **Affix-pool steering** — the flavor's thematic affixes are *added*
   on top of the parent's existing pool weights, never replacing. So a
   `crimson` weapon stays a member of its parent base's family but
   leans into fire/might/lifesteal/fire_resist. Prismatic spreads
   evenly across all 7 elemental adders + multicast/resonance/channeling
   to advertise its chaotic identity.
3. **Drop-weight smoothing** — generator emitted `[0,0,100,0,0]`. Now
   `[3,25,60,12,0]`-style curves with tier-N as the peak.
4. **Themed lore** — one-liner replaces the auto-generated "A jade-
   forged reflavor of the standard halberd". 25 hand-authored lore
   lines, one per flavor, slot-agnostic.
5. **Enchant-chance bumps** — legendary variants get `enchant_chance ≥
   0.30`, epic variants ≥ 0.18, so high-tier items roll a combat tag on
   top of their visual.

## What sync_manifests_from_items_json.py does

For each item in items.json:

1. Determine the target manifest by `slot`. Weapons split by `base_type`:
   1H-sword family → `items_manifest.json`, everything else →
   `items_weapons_extended_manifest.json`.
2. If the id is missing from that manifest, append the whole item dict.
3. If the id exists but the contents differ, replace in-place
   (preserves manifest ordering).
4. Spell-slot items are skipped — separate authoring path.

## What neither does

- Does NOT touch items.json directly (only the balance script does).
- Does NOT copy sprite PNGs — they were already placed at generator time.
- Does NOT run `tools/sync_items.py` (manifest → items.json direction —
  opposite of this pipeline; only used by the item editor's export flow).

## Idempotency

Both scripts are safe to re-run. The balance pass produces the same
output for the same input, and the manifest sync is a content-equality
check before each write.
