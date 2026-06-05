---
name: sync-items
description: Backfill per-slot item manifests from project/data/items.json. Run after merging generator-exported items, hand-editing items.json, or any time the editor (tools/item_editor.html) is missing items that exist in-game. Idempotent.
user_invocable: true
---

# Botter sync-items

The editor (`tools/item_editor.html`) and `tools/sync_items.py` both treat
`tools/items_<slot>_manifest.json` as the source of truth. The game treats
`project/data/items.json` as source of truth. The sync flow is normally
manifest → items.json (one-way), but the in-game **Item Generator** writes
fresh variants straight to items.json, bypassing the manifests.

Symptom: a new variant exists in-game / drops in dungeons but the editor
doesn't show it. Example: 2026-06-05 — `amulet_finger` had a `rosegold`
variant in items.json that didn't appear in the editor's Amulet tab.

This skill backfills the manifests so the editor catches up.

## Usage

```bash
python3 /Users/dyo/claude/botter/tools/sync_manifests_from_items_json.py
```

Reports `+ N → tools/items_<slot>_manifest.json (now M items)` per
manifest, or `All manifests already in sync with items.json.` when there's
nothing to do.

## When to run

- **After merging a generator export** into items.json (the most common
  case — happens any time the user cherry-picks variants from the in-game
  Item Generator and asks to add them to the database).
- **After hand-editing items.json** to add an item directly.
- **When the user reports an item missing from the editor** but the item
  exists in items.json.

After running, the editor (next reload) shows every item that exists in
items.json.

## What it does

For each item in `project/data/items.json`:

1. Determine target manifest by `slot` field. Weapons split by
   `base_type`: 1H-sword family → `items_manifest.json`, everything else →
   `items_weapons_extended_manifest.json`.
2. Check if the item's `id` is already in that manifest's `items[]` array.
3. If not, append the entire item dict (untouched) to the manifest.
4. Spell-slot items are skipped — they live in a separate authoring path.

## What it does NOT do

- Does NOT modify `items.json`. Source-of-truth flow stays manifest → json
  for hand-authored items.
- Does NOT copy sprite PNGs (those are already in `project/assets/tiles/`
  if the generator produced a working variant).
- Does NOT validate stats / drop_weights — items are appended verbatim.
- Does NOT run `tools/sync_items.py`. That script merges manifest →
  items.json, which is the opposite direction. Run this skill first if
  needed, but they don't need to chain.

## Idempotency

Safe to re-run any time. Only appends items missing from their manifest;
existing items are untouched.
