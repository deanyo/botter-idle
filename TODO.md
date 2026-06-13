# Botter — TODO

Active engineering backlog. Open items only — shipped work lives in
`docs/CHANGELOG.md`. Point-in-time narrative ("what does shipping look
like RIGHT NOW") in `HANDOVER.md`. Raw playtest observations
(pre-triage) in `PLAYTEST.md`.

**Hard rule:** when committing, update `HANDOVER.md` to match what
shipped, and either (a) move the entry from here to `docs/CHANGELOG.md`
if it's done, or (b) edit it in place if it changed. They rot fast if
not maintained per beat.

---

## Active priorities (NEXT)

**The Botter multi-agent audit is CLOSED (2026-06-09).** All Tier 0–3
sessions shipped + Tier 2 attribution as the final cap. Future work is
open-ended (balance / UI / dev-tools / new features), not audit
follow-ups. The orchestrator file at
`~/claude/game-audit/prompts/SESSION.md` is archived; future sessions
don't need it.

**Balance pass 2026-06-11 — Beat 1 DONE (2026-06-13).** All ungated
Beat-1 clusters shipped (§1.A through §1.M). of_predator is
deferred-with-blocker to §2.E (needs A6 combat_move_speed_pct
primitive). Active state file lives at
`~/claude/game-audit/balance_pass_2026-06-11/CHECKLIST.md` — the
recommended next move is **Beat 2 §2.D stat_calc.gd unit tests**
(`project/tests/test_stat_calc.gd`), which is the gating dependency
for the §2.E stat-plumbing wave (crit_multiplier_pct affixes,
block_chance/amount uniques, spell_pierce_pct, pack_density_pct,
low_hp_dmg_pct/high_hp_dmg_pct mutex pair, dot_duration_pct,
damage_taken_pct, aura_radius_pct, damage_vs_boss/unique, and the
loot_quantity_pct hard clamp — none of which can land without §2.D's
caps-and-output assertions in place). §2.J mana-economy is its own
independent plan-mode workstream that can also run.

The active backlog below is the live agenda — pick the highest-leverage
item or anything from PLAYTEST.md that the playtester surfaced.

---

## Tier 2 save durability follow-ups (deferred 2026-06-09)

- ⬜ **UI surfacing for `last_load_warnings`.** Loader stamps warnings
  into `state.last_load_warnings` (e.g. `save_recovered_from_backup`,
  `orphan_items_count_3`) but no UI reads them yet. Add a banner in
  `main_menu.gd` + `run_report.gd`: "Save recovered from backup" amber
  banner / "3 items hidden — saved separately" amber banner. Cleared
  after first display via `state.last_load_warnings = []` + save.
  ~30m. Touching the save format was the load-bearing fix; the banner
  can land in any UI session.
- ⬜ **`orphaned_items` recovery UI.** Once `last_load_warnings` is
  surfaced, also add a "Recovered Items" tab in the outpost / shop
  that lets the player move orphaned items back to inventory if
  they've reappeared in items.json. Today the items are preserved
  but invisible until manual JSON inspection. ~1-2h.
- ⬜ **Stale `.tmp` / `.corrupted` / `.future` cleanup.** Atomic-write
  may leave `.tmp` from a torn write; `.corrupted-<ts>` and
  `.future-v<n>-<ts>` accumulate over time. One-time sweep on
  startup: scan `user://`, drop any `*.corrupted-*` /
  `*.future-v*-*` older than 30 days, drop any `botter_save*.tmp`
  older than 1 day. ~15m. Cosmetic — no actual disk-pressure
  problem yet.
- ⬜ **`DirAccess.rename` error handling.** `_save_wrapper` ignores
  the rotate-to-`.bak` rename error (only the final `.tmp → final`
  rename's error is logged). On Windows / sandboxed FS the rotate
  could fail and we'd silently overwrite the prior generation.
  Defensive: log the rotate error too, fall through to the
  rename-tmp path so the new save still lands. ~10m.
- ⬜ **Mid-session corruption recovery test.** Today's
  `test_load_falls_back_to_bak_when_primary_corrupted` simulates the
  corrupted-on-load scenario but doesn't simulate "save survived N
  writes, then write N+1 truncates the primary mid-write." A test
  that writes, mutates, kills the process mid-store, reopens — end-
  to-end torn-write recovery. Requires GUT-level subprocess spawning
  we don't have today. Defer until needed.

---

## Tier 1+ follow-ups noticed during recent sessions

- ⬜ **`dungeon.gd::_end_run` in-flight LootDrop drop.** Same
  vulnerability `flush_to_save` had pre-`f80376b`. If the bot dies
  while drops are mid-air (chest opened the same tick combat ended in
  defeat), those drops are discarded with the dungeon scene. Fix:
  call `_fold_pending_loot_drops_into_inventory()` at the top of
  `_end_run`, same as `flush_to_save` now does. Low-priority because
  it requires precisely-timed death + open-chest, but trivial.
- ⬜ **`dungeon.gd:2613` lava/water terrain damage missing damage_type.**
  Calls `bot.take_damage(dmg)` with no attacker and no damage_type.
  Now that the spell path pipes element + attacker into
  `resolve_swing`, lava is the last hold-out routing through armor
  instead of fire resistance. One-line fix: pass `damage_type="fire"`
  for lava cells (and `"physical"` for water if/when water deals
  damage — currently it only slows). Low-priority because lava chip
  damage is small.
- ⬜ **itch redeploy after attribution session.** Vault-handle strip
  + clean-room dcss_layouts.gd + new credits screen all want a fresh
  web build before the password is removed. Run `/deploy-web` once
  the playtester confirms current build is stable. tools/deploy_web.sh
  now asserts the vault exclude_filter at deploy time so the rename
  can't accidentally re-ship handle-bearing filenames to web.

---

## Balance pass (HIGH priority — surfaced 2026-06-06 after stat audit)

The stat-system unification (StatCalc.compute) made visible just how
overpowered the existing affix stacking is. Audit on a real save (Lv
57 / 4 runs / floor 6 / spriggan / 16 inventory items) found the bot
doing **1500+ damage per swing on tier-1 mobs**. Root causes:

- ⬜ **XP curve too flat.** `bot.gd::xp_to_next() = 20 + (level-1) * 15`.
  Level 57 cumulative cost ≈ 24,220 XP = ~6,055 XP/run on 4 runs =
  ~1,009 XP per floor. Floor mobs avg 6 XP × 100 mobs × 1.5–3.0× pack
  mult = 600–1500 XP/floor, exactly the level-flooding rate.
  Suggested: `30 + (level-1) * 30` (2× cost at every level).

- ⬜ **Affix stacking is purely linear, no soft caps.** Save's stack:
  `of_channeling × 6 = +195% spell dmg`, `of_resonance × 5 = +162%
  area`, `of_quickcast × 3 = +43% CDR`, `of_str_mastery × 3 = +73%`,
  `of_might × 3 = +24 str (= +38% atk + ~28% HP)`, `of_vitality × 2 =
  +245 flat HP (4× base!)`, `of_haste × 2 = +39%`. Tier-5 single-roll
  caps in `affixes.json`: channeling=65, vitality=160, haste=32,
  str=12. **Stacked totals exceed legendary single rolls by 3-5×
  because every slot carries the same affix.** Add diminishing
  returns in `stat_calc.gd::compute` after the per-slot loop:
  - Spell damage / area / CDR / duration: clamp 0..120 / 0..100 /
    0..50 / 0..100 (PoE-style soft caps)
  - Lifesteal: clamp 0..15
  - Track per-affix-id source count, scale 1.0 / 0.75 / 0.50 / 0.25
    for 1st / 2nd / 3rd / 4th+ source

- ⬜ **Pack-tier loot thresholds too generous.** `dungeon.gd:1985`:
  rare-pack 100% drop, miniboss 100%, magic 30%. Suggested: rare 60%,
  miniboss 70%.

- ⬜ **Shop scales high-rarity at level 30 cap.** `shop.gd:384`
  `eff_lvl = mini(lvl, 30)` already clamps but at Lv 30+ a 4-run
  player has access to fairly common epic/legendary stock. Audit if
  cap should drop to 20 or rarity weights should scale per-run
  instead of per-level.

- ⬜ **Per-mob gold rates.** `dungeon.gd:1932`: `1-3 + floor/2` per
  mob = ~450g/floor at floor 6 with 100 mobs. Roughly proportional to
  shop sinks (30g common → 3000g legendary). Watch this once affix
  caps land and items become rarer.

The diminishing-returns + XP-curve fix is the highest-leverage pair —
together they take a 4-run player from L57 with 14 stuffed slots to
roughly L25-30 with 6 affixed slots, the intended pace.

### Future balance beats (deferred per 2026-06-02 validation)

Beyond tier-value tweaks — design work, not just JSON edits.

- ⬜ **Regen mechanic redesign.** Capping regen tiers [10→3] reduced
  stacking but didn't dethrone single-affix dominance at vaults T4.
  Implication: vaults T4 chip damage is ~1 HP/sec, not 3-5 as
  assumed. Tier-value tweaks won't fix this. Two design options: PoE
  leech model (fast when wounded, slow when full HP) or disable
  regen during combat ticks (heals between fights only). Pair with
  flavor-tag mechanic wiring so vampiric/regen become competitive
  defensively.

- ⬜ **T4 boss difficulty separate scaling.** Pinned cliff showed 0%
  wins at vaults T4 even after softening enemy multiplier 3.2× →
  2.7×. The boss floor is the bottleneck, not regular enemies. Add
  `BOSS_TIER_SCALE` separate from `TIER_SCALE` so we can soften
  bosses without nerfing minibosses. Or accept gear is required for
  T4 and surface that progression gate clearly.

- ⬜ **T3 multiplier softening (NEW priority — 2026-06-02 cliff
  fill-in).** The T2→T3 jump is the actual brick wall (86% → 8%
  wins, not the T3→T4 we previously assumed). Patch:
  `TIER_SCALE[2]` 2.0 → 1.8 in `constants.gd`. Validate with swamp
  N=30 — win rate should rise to ~25-40%. Pending human playtest
  confirmation. Full data in `docs/balance-findings-2026-06-02.md`
  "T2/T3 cliff fill-in" section.

- ⬜ **Floor-1 lethality in `naked` preset.** Lv 1 with no gear dies
  in 1-3 seconds before getting a single kill. A fresh-save first
  run should at least clear a few rats. Either starting hp/atk
  needs a buff or floor-1 spawn density needs to scale to bot CR.
  Investigate `_spawn_enemies` for floor-1 density and base bot
  HP/atk at level 1.

- ⬜ **t2 variance at lair.** 10-run sample showed mean ~1.3 floor
  reached (mostly floor-1 deaths). Possibly: lair mob CR
  (wolves/cougars) outpaces uncommon-affix gear, OR 90 mobs on
  floor 2 is still attrition, OR t2 preset gear is sized to T2
  entry not full clear. Worth a focused N=30 grind.

---

## UI follow-ups

- ⬜ **AI perf cost.** Latest grind logs show `ai_us=47484` (47ms/
  frame at 16× speed) on f=2 and similar on f=1. Per-tick AI is
  ~3ms which is fine at 1× but worth keeping an eye on. Run
  `/benchmark` against an older commit if it ever feels worse than
  baseline.
- ⬜ **Outpost clipping audit.** `outpost.gd` panels not yet wrapped
  in `clip_contents` Controls (Stats tab page now clips, but other
  panes don't). Long item names in equipped-slot tooltips,
  paperdoll picker rows, upgrades desc text can still bleed past
  panel rects.
- ⬜ **Camera-offset reconsider.** `dungeon.gd::_center_camera_on_bot`
  shifts camera by half-sidebar-width and half-bag-height. The
  minimap overlay (top-left, 160×160) introduces a third occluded
  zone but is small + translucent enough to not justify another
  shift today. Revisit if the bot frequently runs into the minimap
  zone unseen.
- ⬜ **Inventory cell highlight on filter.** When a filter chip
  hides cells, surviving cells reflow but no visual callout that
  "11 of 47 hidden". A subtle row counter under the chips would
  help.

### Phase D polish (deferred from 2026-06-04)

- **Run report defeat header** — center, larger font, full-width
  rarity-color-tinted underline.
- **Character create grid alignment** — species cards align to a
  proper grid; current species highlighted with its class color
  border.
- **Main menu bot picker tile theme** — match the new pure-black
  + amber accent palette.
- **Min font size 11px audit** — sweep every script for font
  sizes below 11 and bump.
- **Min touch target 44×44px audit** — same sweep for Button +
  ItemCell hit regions.
- **Tall / portrait layout branch** — `UILayout.Shape.TALL` is
  defined but no screen actually picks it yet. Each screen needs
  a TALL branch with stacked + scroll layout when Phase D ships.
- **Custom in-game cursor sprite** — replace the OS arrow with a
  themed cursor.
- **Animated scene transitions** beyond LoadingCurtain — slide-in
  / slide-out effects between screens.

---

## Combat-pivot follow-ups (deferred from autocast-spells beat)

- ⬜ **Spell evolutions** (VS-style: 2 spells + 1 condition →
  upgraded form). E.g. Fireball + Spinning Axes at level 5 → Comet
  Strike. Long-tail build goal once base spells are tuned.
- ⬜ **Spell merges / fusion** — combine two same-spell items into
  a higher rarity / level. Half-implemented for gear via
  meta-rarity; spells should follow the same pattern.
- ⬜ **Spell socketing / supports** — PoE-style: link a "support
  gem" spell-item to another spell to add behavior (chain
  support, cold support, AoE support). 2nd build axis on top of
  equip.
- ⬜ **Enemy spell variety** — elite/boss/rare-pack leaders cast
  their own spells. Adds tactical defense interest. Strong
  experimental candidate.
- ⬜ **Spell drag-and-drop UI** — equip-from-inventory currently
  picks "first empty spell slot." Player feedback wants slot
  choice. Build a drag-and-drop swap UI.
- ⬜ **Atlas / authoring portal** — races + spells need to appear
  in the atlas viewer + a "spell editor" akin to the biome
  editor so the user can author new spells without manual JSON
  editing.
- ⬜ **Wave spawn animation** — current wave/burst mobs just
  appear at walkable cells. Add a brief warp-in or warning
  indicator.

---

## Enchant combos (HIGH priority — design beat)

Today an item rolls AT MOST one enchant from `enchant_pool` at drop
time. Idea: rarely (~1-2% of enchant rolls), the item rolls TWO
enchants that **combine into a named compound** with a unique
effect and a distinct color.

Examples to seed:
- `poison + fire` → **Combustion** (poison DoT triggers a delayed
  fire flash on expiry)
- `cold + lightning` → **Brittle Storm** (frozen targets take +50%
  lightning damage)
- `holy + fire` → **Pyre** (burns harder on undead/demon enemies)
- `dark + cold` → **Hollow Frost** (freeze duration +50% on
  enemies below 50% HP)
- `vampiric + holy` → **Sanctified Drain** (lifesteal heals 2×
  when target is holy-hated)

Implementation shape: new `enchant_combos.json` mapping `[a, b]`
(sorted) → `{ name, color, effect_id }`. `dungeon._create_item_instance`
enchant roll path: ~5% of rolls get a SECOND independent enchant
pick; if the pair has a combo entry, write `inst.enchant = combo.name`
and `inst.enchant_combo = true`. Some uniques carry combos INNATELY
via `implicit_enchant_combo: "Combustion"`. Tooltip shows the combo
name in a special unique-style line with the combo's blended color.

Worth pairing with a "compound flavor" expansion of the tooltip
glow shader so the panel halo shifts between the two component
element colors.

---

## Pack mod follow-ups (deferred 2026-06-03)

- ⬜ **Pack auras affect nearby allies.** Mods are currently
  self-only — a rare with "Hasted" speeds itself but doesn't
  grant haste to packmates. PoE-style aura wiring needs a
  per-frame proximity scan. Skip until needed.
- ⬜ **Unique-tier monsters.** Hand-authored single-instance
  bosses with persistent ground effects, spawned once per floor
  (or per branch). Big design lift; defer.
- ⬜ **Enemy regen tick.** `regenerating` mod is a no-op because
  `Actor.tick_statuses` doesn't tick `hp_regen_per_sec` on
  enemies (only Bot.process does). Add a generic actor-side
  regen tick path so the mod actually heals.
- ⬜ **More mod variety.** Reflective/thorns/elemental_aura would
  cover more PoE archetypes. Wire as additional entries in
  `monster_mods.json`.
- ⬜ **Per-pack difficulty preview.** Flag the leader's modifier
  visually (icon over head?) so the player can see "this pack is
  Hasted" before engaging.
- ⬜ **Loot drop rebalance validation.** Loot-per-floor target
  was ~10-15. Confirm with longer-run statistics this isn't too
  lean once cap-driven salvage kicks in on deeper floors. Use
  `/playthrough` harness.

---

## Items / paperdoll follow-ups

- ⬜ **Paperdoll sprite alignment + scaling pass.** With 234+
  items shipped, the paperdoll bot looks silly — weapons/shields/
  armor are misplaced and miss-sized for the character base.
  Symptoms: shield floats off the bot's hand, sword too small for
  silhouette, armor doesn't align with body, gear stacks weirdly
  when multiple slots filled. Each new sprite was added with a
  single shared anchor offset per slot in
  `paperdoll_renderer.gd::ANCHOR_OFFSETS`, but real DCSS gear
  varies in canvas size + pivot point. Two fixes:
  - **Per-base-type defaults** (recommended): `base_type` already
    exists on items (`dagger`, `long_sword`, `kite_shield`, etc).
    Author one offset+scale per base_type in a lookup table on
    PaperdollRenderer. Covers 80% of cases with ~30 entries.
  - **Per-item visual overrides**: optional `paperdoll_offset` and
    `paperdoll_scale` fields on items.json entries, with a tool/
    skill to author them. Most flexible but requires authoring
    per item; reserve for outliers.
  Verify visually with `/showcase` station for "all items in slot X".
- ⬜ **PoE-style low-tier legendaries.** Followup to the rarity-cap
  fix: when source tier caps rarity at uncommon/rare, the player
  has nothing aspirational to chase at low floors. PoE solves this
  with low-level uniques that have weak base stats but signature
  unique stat lines / mechanics — build enablers, not stat
  upgrades. Author 5-10 low-tier legendaries with `drop_weights`
  heavily front-loaded (T1/T2 only) carrying a flavor_tag a base
  item couldn't have, but stats below regular legendaries.
  ~1-2h via `tools/item_editor.html`.
- ⬜ **Rings/amulets full UI wiring.** Items + schema slots in
  save_state ready, but `paperdoll_renderer.gd::SLOT_DIRS` has no
  jewellery entries (DCSS confirms jewellery never renders on the
  doll, so SLOT_DIRS skip is correct), `outpost.gd::SLOTS` const
  doesn't include ring1/ring2/amulet, HUD tooltips don't render
  jewellery. ~1.5h.
- ⬜ **2H weapons / axes / maces / staves manifests.** 14 legacy
  entries pruned during 1H-only items migration (bearded_axe,
  chipped_claymore, dawnbreaker, fanged_dirk, highland_claymore,
  honed_dagger, iron_shortsword, mithril_blade, runed_warsword,
  shadowfang, steel_sword, thunder_cleaver, voidpiercer,
  worldsplitter). DCSS has sprites for all. Same manifest +
  editor + sync workflow as 1H swords. ~1h per slot.
- ⬜ **Tags not yet wired** (need design decisions):
  - `dark` (7 weapons) — possibly +damage in low-light tiles?
  - `psychic` (3 helms) — TBD; mind shield + reflect spell?
  - `slaying` (5 rings) — currently effectively wired via base
    atk; no extra mechanic beyond the stat itself.

---

## Combat polish (deferred)

- ⬜ **Enemy attack effects** — bot has weapon overlay + swing
  animation; enemies just have hit_squish on hit. Add per-enemy
  attack animations: dragon breath, mage cast, archer shoot.

---

## Generation pipeline — DCSS-faithful gaps

- ⬜ **Doors aren't placed by the layout.** `_place_doors_in_corridors()`
  in `basic_level` is a stub. DCSS does it inside `_make_room`.
- ⬜ **Branch-entry vault stamping** — slot 4 in the pipeline is
  reserved but unused. Becomes meaningful once we have branch
  transitions.
- ⬜ **Chance vault gating** — DCSS has per-vault probability
  tables (e.g. "20% on D:2, fallback 0"). We use a flat `chance`
  field. Port the per-branch table.
- ⬜ **DEPTH algebra** — DCSS supports `D:2-7`, `Lair:1-3`,
  `!Zot`. We use simple `[min, max]` integer ranges.
- ⬜ **`SUBVAULT` glyph** — vaults can reference other vaults by
  name. Skipped intentionally; revisit if vault authoring needs
  nesting.

### DCSS algorithm port — Phase A still TODO

- ⬜ `dgn-shoals.cc` — branch-specific Shoals generator (tide
  pools, sand islands)
- ⬜ `dgn-swamp.cc` — branch-specific Swamp generator (boggy
  paths, water expanses)
- ⬜ `dgn-proclayouts.cc` — Worley/Perlin layouts (`RiverLayout`,
  `ColumnLayout`, `DiamondLayout`, `WastesLayout`)
- ⬜ `dgn-irregular-box.cc` — non-rectangular rooms

### Phase B — data table ports

- ⬜ `enemies.json` — replace stats with DCSS `mon-data.h` values
  (decades-tuned). Currently a mix of hand-rolled and partial
  ports.
- ⬜ `biomes.json` → eventually rename to `branches.json`. One
  entry per real DCSS branch with its actual generator id, enemy
  pool, vault tags, ambient features.

### DCSS branches — Phase 3 (heavier lift, deferred)

- ⬜ Hell tier (Vestibule, Dis, Geh, Coc, Tar) — endgame branches
  with custom procgen and signature monster waves.
- ⬜ Pan / Abyss morphing geometry — DCSS regenerates these every
  step. Current biomes use static layouts as a stand-in.
- ⬜ Dedicated branch generators — Shoals tide pools, Swamp bogs
  (currently using `caves_open` / `caves` approximations).

### Phase C — bot AI + idle loop (the actual game)

- ⬜ Configurable bot priorities. Bot AI has aggro range cap (8
  cells), current-room loot priority, low-HP retreat. Exposing
  these as Outpost sliders is pending. **See PLAYTEST.md note 6
  for the Football Manager-style instruction-panel framing.**
- ⬜ Behavioral preferences (greed vs caution, melee vs ranged)
  pending.
- ⬜ Meta-progression — `bot_upgrades` shipped (gold sink,
  permanent). Prestige (`shards`) field reserved in save state;
  no implementation yet.

### Multi-tile creatures (deferred)

Visual scaling shipped — 32 creatures (dragons, giants, sphinx,
mummies, jellies, etc) render at 1.3-1.6× scale with proper anchor
+ z-ordering. Logical layer still 1 cell per creature. True
multi-cell mechanics (vine_segment chains, kraken with 4 tentacle
cells, serpent_of_hell) deferred because:
- Shipped CC0 DCSS pack is 32×32 only; the 32×64 unique-monster
  sprites DCSS uses for big creatures aren't in our pack.
- Pathfinding (AStarGrid2D) doesn't natively support multi-cell
  shape obstacles. Enemy class would need a `multi_tile_layout`
  of relative cell offsets; pathfinder must mark all occupied
  cells solid; bot attack-target picker needs nearest-cell math.
- Tentacle chain solver is its own beat.

Architectural sketch: Enemy gets optional `multi_tile_layout:
Array[Vector2i]` (offsets from head). Pathfinder treats all
occupied cells as solid against other enemies. Bot adjacency =
`min(chebyshev to any creature cell)`. Render: parent sprite at
head, child sprites at offsets. Spawn validates an N-cell open
"footprint".

### Variety pass — `1.5h` still pending

- ⬜ **Negative space** — partially done via fog; could be
  tighter (smaller playable area, tighter camera).
- ⬜ **`t` (tree), `B` (bones), `M` (mushroom)** impassable decor
  glyphs not yet wired. Plus ice-slip mechanic for `I` cells.

---

## Visual effects — deferred

- ⬜ **Light cookies — author themed cookies for biomes.** Current
  4 cookies are programmatically generated test patterns.
  Hand-authored cookies for elf (stained glass arches), tomb
  (prison bars), spider (web with center hub), forge (forge-flame
  plume) would feel more intentional.
- ⬜ **Quality presets in video options.** `VideoSettings.GFX_PRESET_*`
  exist but no UI buttons to apply them. Add 3 buttons (Low /
  Med / High) that batch-set all toggles.
- ⬜ **Dithered fog transitions** (bayer) — option for hard-edged
  pixel-art-authentic fog instead of the current smooth gradient.
  Subjective.
- ⬜ **Scanlines / CRT shader** — opt-in graphics option.
  Polarizing, default off.
- ⬜ **Heat haze on torches** — same shader could apply to fire-
  tier light specs (campfire, lava actor) for a more dramatic
  forge feel. Currently only T_LAVA terrain cells.

---

## Perf — validate on lower-tier hardware

Two passes complete (CHANGELOG 2026-05-13/14). Remaining items are
all "nice to have" / "validate elsewhere":

- ⬜ **Validate on lower-tier hardware** — high-end PC, mid PC,
  low-end Windows laptop. Env-var A/B knobs (`BOTTER_NO_*`,
  `BOTTER_FORCE_BIOME`) wired. Forward+ requires Vulkan — track
  which hardware falls back to gl_compatibility.
- ⬜ **Stretch mode `viewport`** — currently `canvas_items`.
  `viewport` mode renders at design size + GPU upscales —
  universal pixel-art-game perf trick on high-DPI. Changes pixel
  snap, needs visual review under `/showcase`.
- ⬜ **Glow / bloom video options toggle.** `WorldEnvironment.glow_*`
  is on unconditionally for ~+1% cost. Add a graphics-options
  toggle for low-end targets. Low priority.
- ⬜ **Outlier vaults** — `des_grunt_crypt_end_deaths_head`,
  `des_quadcrypt_mu`, `des_hellmonk_crystal_mountain` consistently
  top the perf-floor ranking. Cosmetic — inspect for excess decor,
  light count, or pathological room shapes only if a low-end
  target struggles.
- ⬜ **Shadow filter for ambient decor** — drop PCF5 to NONE/PCF13
  only if a low-end target shows shadows as the cost. Currently
  zero impact on M3 Pro. `BOTTER_SHADOW_FILTER` env var is the
  test harness.
- ⬜ **MapRenderer fade dirty-set** — minor (~410µs); skip if not
  seen in the wild.
- ⬜ **`_carve_layout` p95 53ms** — biggest remaining gen hitch on
  forge. Already async-split at build-floor level. Could split
  internally if a weaker target shows it as a problem.

### Web-perf follow-ups (deferred — current state is good enough)

- **First-floor cold-load** ~5-15s on a never-loaded biome.
  RenderingServer prewarm helps subsequent floors but the first
  visible frame still pays a one-time pipeline-state compile per
  unique (texture × shader) combination. To drive lower would need
  to render every prewarmed texture through the SAME shader the
  dungeon uses — bigger refactor.
- **Compatibility renderer** is the only one we ship to web.
  Forward+ on web is supported in Godot 4.6 and might have totally
  different perf characteristics. Worth a one-day spike if web
  becomes a real target later.
- **wasm size** is 36 MB (~12 MB gzipped). Stripping unused engine
  modules via a custom export template would shrink first-load,
  but it's a multi-hour build pipeline change.
- **itch.io CDN propagation lag.** No code fix possible. Manual
  zip upload via itch edit page is the workaround.

---

## Tooling — deferred

- ⬜ **Aggregate end-of-grind report**: "5 runs, 50 floors, X%
  bad-floor rate". Currently you'd grep yourself.
- ⬜ **Generator unit-style harness**: headless script that calls
  `DungeonGenerator.generate()` 200× per layout, prints bad-floor
  rate per layout. Run before merging generator changes.
- ⬜ **Batch screenshot mode** — single Godot process with TCP
  eval to capture N biomes at the cost of one cold start. Worth
  porting if we ever need a 24-biome audit in one shot.
- ⬜ **Parallel runner** — sweeps are sequential. Multiple Godot
  instances would cut wall-clock by core count (~50-min sweep →
  ~10min). Needs save-state isolation per worker (each writes to
  its own user_data dir or uses `--user-data-dir` override).
- ⬜ **HP-loss telemetry** — `[combat] dealt` is bot-attacker only
  meaningfully populated. For "did bot survive narrowly" we need
  HP curves over time. Add `[hp] f=N t=N hp=N max=N` line per
  second-ish.
- ⬜ **Cross-branch sweeps** — `--branches dungeon,lair,forge` to
  compare a build's win rate across tiers. Build when needed.
- ⬜ **Loot-pickup policy** for `/playthrough` — currently
  `loot_filter` is "common" so the bot grabs everything. A policy
  that filters (e.g. "epic+ only past tier 3") would simulate
  gear-pruning gameplay.
- ⬜ **Build re-spec mid-playthrough** — playthroughs commit to
  one equip/upgrade policy throughout. A real player might pivot
  (start combat-first, switch to hp-first when reaching crypt).
- ⬜ **Per-tier playtime calibration findings** — once the trio
  completes, write up tier-by-tier wall-clock estimates and
  identify any soft walls.

---

## Asset utilization — gaps

- ⬜ **Doors** — 30 door sprites available; vault `+` glyph
  renders 3 styles (closed/runed/sealed) but we have many more.
- ⬜ **Traps** — 24 trap sprites, none used.
- ⬜ **Effects** — 238 effect frames (blood, fire, ice, magic),
  none used outside the curated kill-flash set.

---

## Open questions — defer until needed

- PvP (async — your bot vs. another player's dungeon config)
- Prestige / rebirth for endgame
- Clan / guild social features
- Steam Deck support alongside mobile
- Monetization model

---

## Out of scope (decided no)

- DCSS *source code* in the project (GPLv2+ would force the whole
  game open-source). Tiles only (CC0).
- Lua hooks in vaults — code-in-data is bad.
- Original HTML prototype's structure — was a visual mockup, not
  a target architecture.
- Auto-running the editor or auto-screenshotting in normal
  sessions — the user opens Godot themselves. Screenshot mode is
  opt-in via `DEBUG_FLOOR.txt` marker, captured by `/screenshot`.
