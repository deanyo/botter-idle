# Botter — TODO

Roadmap and deferred items. The "what works today" lives in `HANDOVER.md`;
the durable rules in `CLAUDE.md`. Update this file when committing.

---

## Pre-pivot checkpoint (2026-06-04)

User is starting an experimental pivot. Repo is in a known-good
state at this commit:
- 309 items spanning 11 slots, all aligned to DCSS source-of-truth.
- 15 species + character creation + multi-character saves.
- All combat mechanics wired (vampiric/fire/cold/holy/poison/
  thunderous/dark/dragon_bane/brutal/precision/rage/thorns/
  reflective/harm/vitality/psychic/slaying/fortified/willpower/
  swiftness/regen/stealth/lordly/footwork/warding/elemental/wisdom/
  arcane/fire_res/cold_res/poison_res/vision/rampaging/flying/
  fortune/faith/acrobat/death/earth/guardian/demon/crystal/dual/
  sound/ponderous).
- Authoring portal live at https://dnyo.co.uk/botter-idle/ (atlas
  viewer + biome editor + item editor + affix editor).
- Smoke tests passing (1-run grind clean, 309/309 slot audit).

Open items below are roughly organized by lever: balance / item /
visual / system. Pick whichever dovetails with the pivot direction.

---

## Playtest issues (2026-06-02 — high priority, partially shipped)

User reported four issues from a real playtest. Status as of this beat:

- ✅ **Bot vertical squish over a long session.** Sprite progressively
  squashed to a few pixels after ~10 min of play. Root cause:
  `actor.gd::_set_facing` was reading `rig.scale` mid-tween (attack_lunge
  pinches Y to 0.85 for ~50ms) and snapshotting the transient value into
  `SpriteFX.base_scale` via `update_base_scale(rig.scale)`. Every
  facing flip that happened to overlap a tween permanently dropped
  base Y by a small amount; over thousands of attacks the bot
  collapsed. Fixed by rebuilding the resting scale from
  `visual_scale` + `_facing_x` instead of reading the live transform.

- ✅ **Ring slot UX — couldn't equip a third ring.** Fixed by
  collapsing two ring slots → one `ring` slot (amulet covers the
  trinket role). Save migration in `save_state.gd::_migrate` promotes
  ring1/ring2 cleanly: ring1 → ring, ring2 → inventory. Updated
  `bot.gd`, `outpost.gd`, `hud_chrome.gd`, `inject_save.py`. DCSS has
  two ring slots, but our equip-from-HUD UX is a single-tap interaction
  and the multi-slot routing was confusing. Simpler is better here.

- ✅ **Weapon rarity tint + glow.** Equipped legendary weapons now
  modulate by rarity (subtle wash — common neutral, legendary 50%
  toward rarity color) and epic+ weapons sport a soft pulsing halo
  behind the held sprite. Wired in `bot.gd::_apply_rarity_decor` for
  the live bot and `paperdoll_renderer.gd::_apply_rarity_modulate`
  for every UI surface. Fixes the "blue scimitar even though I just
  equipped a gold legendary" reported case.

- ✅ **Source-floor tier caps loot rarity.** Entering a wizlab/zig
  portal on Floor 2 used to pour T5 legendaries into a T1 run because
  `_pick_loot_id` keyed on the portal-overridden biome's tier
  (vaults T4 / zot T5) rather than the home branch tier (dungeon T1).
  Added `dungeon.gd::_source_tier()` (always returns the home branch
  tier, ignoring portal override) and `_clamp_rarity_to_tier()`
  (T1=uncommon cap, T2=rare, T3=epic, T4+=legendary). Wired through
  both `_roll_rarity` and `_roll_rarity_with_bias` so enemy drops,
  vault loot marks, and chest contents all respect it.

- ⬜ **PoE-style low-tier legendaries.** Followup to the rarity-cap
  fix: when source tier caps rarity at uncommon/rare, the player still
  has nothing aspirational to chase at low floors. Path of Exile
  solves this with low-level uniques that have weak base stats but
  signature unique stat lines / mechanics — they're build enablers,
  not stat upgrades. Author 5-10 low-tier legendaries with
  `drop_weights` heavily front-loaded (T1/T2 only) that carry a
  flavor_tag a base item couldn't have, but with stats below regular
  legendaries. Editor: `tools/item_editor.html`. ~1-2h.

- ✅ **Weapon-swing particle trails per flavor tag** (shipped 2026-06-02).
  `weapon_trails.gd` builds GPUParticles2D bursts per flavor (fire ember
  sparks, cold frost shards, vampiric blood drips, thunderous arcs,
  holy gold motes, poison wisps) and emits on every swing. Lazy node
  creation, one_shot particles. Slider-tunable amount + lifetime via
  FX Tuner.

- ✅ **Bot-side enchant glow on the wielding hand** (shipped 2026-06-02).
  `bot.gd::_apply_hand_enchant_ambience` parents a soft radial glow
  to the rig at -8x offset (anatomical weapon hand on DCSS sprite).
  Auto-mirrors when the bot flips facing because the offset rides on
  rig.scale.x. Slider-tunable alpha + scale.

- ✅ **Enemy variation: size jitter + magic/rare pack mods** (shipped
  2026-06-03). Per-spawn `visual_scale` jitter 0.85-1.15× on
  non-boss/non-miniboss/non-champion enemies. PoE-style pack tier
  system: 7%/1.2% magic/rare base rates at T1, scaling 1.5× per
  branch tier (T5 ≈ 35%/6%). 6 starter mods in `data/monster_mods.json`
  (hasted/tough/vicious/vampiric_pack/regenerating/stalwart) compose
  via random sampling without replacement. Magic = +20% HP/+10% ATK
  + 1 mod + blue tint + small aura; rare = +60% HP/+30% ATK + 2 mods
  + yellow tint + larger pulsing aura + named ("Hasted Vicious Goblin").
  Vampiric pack mod feeds through `combat_defense_tags()` so existing
  Bot tag mechanics apply automatically. Validated 2-run grind:
  61 pack spawns, every mod fired, no stutters.

  Followups (deferred):
  - ⬜ **Pack auras affect nearby allies.** Currently mods are self-
    only — a rare with "Hasted" speeds itself but doesn't grant
    haste to packmates. PoE-style aura wiring would need a per-
    frame proximity scan. Skip until needed.
  - ⬜ **Unique-tier monsters.** Hand-authored single-instance bosses
    with persistent ground effects, spawned once per floor (or per
    branch). Big design lift; defer.
  - ⬜ **Enemy regen tick.** `regenerating` mod is currently a no-op
    because `Actor.tick_statuses` doesn't tick `hp_regen_per_sec`
    on enemies (only Bot.process does). Add a generic actor-side
    regen tick path so the mod actually heals.
  - ⬜ **More mod variety.** Reflective/thorns/elemental_aura
    monster mods would cover more PoE archetypes. Wire as
    additional entries in `monster_mods.json`.

- ✅ **Horde density via pack clusters** (shipped 2026-06-03).
  Floor 1 ~50 mobs / floor 6 ~150 (validated 535/436 kills/run in
  2-run grind). Replaced flat random N-spawn with `_spawn_packs`:
  groups of 6-12 same-id mobs around a leader who rolls magic/rare
  at elevated rates (30%→80% modified across T1→T5). Loot rebalanced
  for 10× kill counts: normal drop 15%→5%, magic 30%, rare 100%×2.
  Persistent outlines on boss/miniboss/rare/magic via extended
  `threat_outline.gdshader` (red/orange/gold/blue).

  Followups (deferred):
  - ⬜ **Per-pack difficulty preview.** Flag the leader's modifier
    visually (icon over head?) so the player can see "this pack is
    Hasted" before engaging.
  - ⬜ **Loot drop rebalance validation.** Loot-per-floor target
    was ~10-15. Confirm with longer-run statistics that this isn't
    too lean once the cap-driven salvage starts kicking in on
    deeper floors. Use `/playthrough` harness.

## Future balance beats (deferred per 2026-06-02 validation)

These are beyond tier-value tweaks — they require design work, not just
JSON edits. Surfaced from the validation experiment showing the 2026-06-02
patches were directionally right but insufficient.

- ⬜ **Regen mechanic redesign.** Capping regen tiers [10→3] reduced
  stacking but didn't dethrone single-affix dominance at vaults T4.
  Implication: vaults T4 chip damage is ~1 HP/sec, not 3-5 as assumed.
  Tier-value tweaks won't fix this. Two design options:
  - Path-of-Exile leech model — fast when wounded, slow when full HP
  - Disable regen during combat ticks (heals between fights only)
  Both bigger changes than this beat. Pair with the flavor-tag
  mechanic wiring (so vampiric/regen become competitive defensively).

- ⬜ **T4 boss difficulty separate scaling.** Pinned cliff showed 0%
  wins at vaults T4 even after softening enemy multiplier 3.2x → 2.7x.
  The boss floor is the bottleneck, not regular enemies. Add
  `BOSS_TIER_SCALE` separate from `TIER_SCALE` so we can soften bosses
  without nerfing minibosses. Or accept that gear is required for T4
  and surface that progression gate clearly.

- ⬜ **T3 multiplier softening (NEW priority — 2026-06-02 cliff fill-in).**
  The T2→T3 jump is the actual brick wall (86% → 8% wins, not the
  T3→T4 we previously assumed). Patch: `TIER_SCALE[2]` from 2.0 → 1.8
  in `constants.gd`. Validate with swamp N=30 — win rate should rise
  to ~25-40%. Pending human playtest confirmation. Full data in
  `docs/balance-findings-2026-06-02.md` "T2/T3 cliff fill-in" section.

## Critical bugs from playtest (2026-06-02 — HIGH PRIORITY)

⚠️ Reported by user — affects every run, breaks the visual contract.

- ⬜ **Mobs/chests stack on a single tile near top of floor.** On lots
  of floors the spawn distributor lumps everything into one cluster
  rather than spreading across rooms. Look at
  `dungeon.gd::_spawn_enemies` + `_place_interactables` — likely the
  spawn-cell selection is biased to a single bbox row when the
  generator's room list is empty/sparse, or the floor's accessibility
  graph from spawn is collapsing. Possibly related to dungeon-layout
  variants that produce 1 huge region instead of room rectangles.

- ⬜ **Bot descends stairs with no stair visible on the floor.** Tile
  exists in `grid` (T_DOWN_STAIRS) but `map_renderer` is failing to
  paint it, OR the stair texture is being occluded by a tile drawn
  on top of it. Check `map_renderer.gd` z-ordering of features vs
  floor decals. May share a root cause with #3 below.

- ⬜ **Floor tiles draw ON TOP of monster sprites.** Z-order regression
  in the renderer. Floor tile cells are at z=0 by convention; actor
  layer at z>0. Either an ambient_decor sprite or a feature overlay
  is leaking into the actor z-band. Check `map_renderer.gd::_paint_*`
  and `ambient_decor.gd` for any sprite that doesn't pin z to a
  background-only band.

These three may share a single underlying bug. Triage by reproducing
in `/screenshot dungeon` (the JSON sidecar will show enemy cells +
floor cell counts; if multiple enemies share a cell the JSON will
expose it directly). Pin the next session to fixing them before any
new mechanics ship.

## Up next (planned 2026-05-21)

After tier-pinned experiment data lands and a balance tuning beat is shipped:

0. **Paperdoll sprite alignment + scaling pass.** With 234 items shipped,
   the paperdoll bot looks silly — weapons/shields/armor are misplaced
   and miss-sized for the character base. Symptoms: shield floats off
   the bot's hand, sword is too small for the silhouette, armor doesn't
   align with the body, gear stacks weirdly when multiple slots are
   filled. Each new sprite was added with a single shared anchor offset
   per slot in `paperdoll_renderer.gd::ANCHOR_OFFSETS`, but real DCSS
   gear varies in canvas size + pivot point. Two fixes available:
   - **Per-item visual overrides**: optional `paperdoll_offset` and
     `paperdoll_scale` fields on items.json entries, with a tool/skill
     to author them (similar to how visual_scale works for big enemies).
     Most flexible but requires authoring per item.
   - **Per-base-type defaults**: `base_type` already exists on items
     (`dagger`, `long_sword`, `kite_shield`, etc). Author one offset+scale
     per base_type in a lookup table on PaperdollRenderer. Simpler and
     covers the family-of-similar-shape problem cleanly.
   Recommendation: start with the per-base-type approach (covers 80%
   of cases with ~30 entries), reserve per-item override for outliers.
   Verify visually with /showcase station for "all items in slot X".
1. ✅ **Rings/amulets stat + UI wiring** (shipped 2026-06-02). Items
   route through `_resolve_equip_slot` (slot=="ring" picks ring1 first,
   then ring2). `outpost.gd::SLOTS` and `hud_chrome.gd::EQUIPPED_SLOTS`
   extended; bot.gd recompute_stats picks them up via existing
   defensive iteration. No paperdoll work — DCSS confirms jewellery
   never renders on the doll.
2. **DCSS-style overlay sprite layers** — all 3 layers shipped:
   ENCH ✅, SHADOW ✅, HALO ✅ (all 2026-06-02).

   - ✅ **SHADOW**. `scripts/actor_shadow.gd` draws a tinted oval
     beneath every actor's rig at +10px, z=-1. Toggleable via
     `gfx.shadow` VideoSetting; `BOTTER_NO_SHADOW=1` disables.

   - ✅ **ENCH**. Status-effect overlays. `scripts/status_overlay.gd`
     registry, 9 sprite icons, driver hooks for lava/water/altar/
     low-HP/regen. Toggleable via `gfx.ench`. Plus the WoW-style
     buff/debuff bar at top of HUD (`hud_chrome._build_buff_bar` +
     `update_buffs`) — square icons + countdown timers, fed from
     `bot.active_statuses()` each frame.

   - ✅ **HALO**. `bot._apply_halo(god)` spawns a per-god tinted
     radial glow at z=-2 behind the rig (also behind shadow), with
     a soft 1.6s sin pulse. 22 god colors in `_HALO_COLORS`. Adds
     `blessed` status so the buff bar shows the halo icon too.
     `clear_blessings` queues the sprite free + removes status.

3. ✅ **First flavor-tag mechanic wired** (shipped 2026-06-02).
   `actor.gd::attempt_attack` reads `combat_weapon_tags()` (Bot
   overrides with equipped weapon's flavor_tags). On `vampiric`,
   heals `dealt * 0.08` capped at max_hp. Validated via /duel:
   vampires_tooth vs chilly_death (legendary rapiers, ~equal atk),
   N=8 vaults T4 — vampiric reached +0.38 floors deeper / +7 kills
   off near-identical raw damage. Pattern proven; more tags follow
   the same `if "<tag>" in tags:` shape.

   Tags wired 2026-06-02 (13 total via the `combat_weapon_tags()` /
   `combat_defense_tags()` pipeline; vampiric was the first):
   - ✅ Attacker (weapon-side): `vampiric` (8% lifesteal),
     `precision` (anti-streak crit, +5%/swing cap +50%),
     `fire` (3-tick burn DoT), `holy` (+50% vs HOLY_HATES),
     `dragon_bane` (+50% vs DRAGON_HATES),
     `cold` (15% freeze chance + 20% bonus vs frozen),
     `poison` (4-tick poison DoT),
     `brutal` (+25% vs targets ≤30% HP).
   - ✅ Defender (armor/shield/amulet/ring/boots/helm-side):
     `harm` (+25% damage dealt and taken),
     `thorns` (15% returned to attacker, post-defense),
     `reflective` (10% chance to fully negate the hit),
     `vitality` (+1 HP regen/sec via recompute_stats),
     `rage` (+5% atk/kill in 6s window, cap +30%).
   - HOLY_HATES + DRAGON_HATES live in StatusOverlay constants.
   - `Actor.take_damage(raw, attacker)` now optionally takes the
     attacker so thorns can return damage.
   - DoT generalized via `Actor._apply_dot_status()` — `burning` and
     `poisoned` both ride on it.

   Also wired 2026-06-02:
   - ✅ `thunderous` (4 boots) — on a successful hit, finds one cell-
     adjacent live Actor to the target via `_find_adjacent_actor`
     (O(siblings), excludes self+target+dead) and deals 50% raw to it.
     Chain hit doesn't itself re-trigger thunderous (no infinite chain).

   Tags not yet wired (need design decisions):
   - `dark` (7 weapons) — possibly +damage in low-light tiles?
   - `psychic` (3 helms) — TBD; mind shield + reflect spell?
   - `slaying` (5 rings) — currently effectively wired via base atk;
     no extra mechanic beyond the stat itself.

## Gameplay loop overhaul — DONE 2026-05-15

All 10 beats from `docs/gameplay-loop-plan.md` implemented + several
extras. Latest snapshot lives in `HANDOVER.md` "Gameplay loop overhaul"
section. 5 commits ahead of `origin/main`:

```
52a9ab5 Stricter progression + per-deploy run modifiers
70aff1b Death retreat + gear bloat + bot upgrades + offline progress
5fad84a Smooth shader-driven fog of war
6ead4a6 UI rework — Outpost (was Garage), shared paperdoll, rarity decor
b88eb83 Gameplay loop overhaul — 6 affixes + branch tiers + idle-friendly inventory
```

Beat status:
- ✅ **Beat 1 — Affix simplification** (6 affixes — added Haste vs the
  doc's 5; crit + haste wired in `actor.gd`; no save migration, dev saves
  nuked instead)
- ✅ **Beat 2 — Branch tier data** (`biomes.json` tagged tier 1-5 +
  cr_recommended; `constants.gd` FLOORS_PER_RUN 10→6, MINIBOSS_FLOORS [3],
  TIER_SCALE [1.0, 1.4, 2.0, 3.2, 5.0])
- ✅ **Beat 3 — Save state expansion** (unlocked_branches, bosses_killed,
  max_revives, loot_filter, inventory_cap, last_branch, branch_modifiers,
  bot_upgrades, shards, last_seen_timestamp)
- ✅ **Beat 4 — Branch-aware run plan** (BiomeData.roll_run_plan accepts
  branch_id + floors; runtime tier scaling at spawn; branch boss = strongest
  pool member; boss_killed signal)
- ✅ **Beat 5 — Death retreat with revives stat** (max_revives default 3;
  HP=0 → revive at floor 1 of same branch; lava death routed through
  retreat too)
- ✅ **Beat 6 — Gear bloat** (loot_filter + inventory_cap + auto-salvage,
  Outpost UI surfaced)
- ✅ **Beat 7 — Bot upgrades** (data/bot_upgrades.json with 6 upgrades,
  Outpost upgrades panel, stats fold into bot.recompute_stats)
- ✅ **Beat 8 — Branch picker UI** (Outpost tier-grouped picker, locked
  branches dimmed, modifier strip per branch)
- ✅ **Beat 9 — Offline progress** (last_seen_timestamp on save,
  OfflineProgress.apply on launch, "While You Were Away" AcceptDialog)
- ⬜ **Beat 10 — Run report unlock prominence** — boss kill writes save
  + emits boss_killed signal, but the run report doesn't yet visually
  highlight first-clear unlocks above the loot list. The unlock IS
  surfaced via `[unlock]` print + the next Outpost visit shows new
  branches available; just no "BRANCH UNLOCKED" banner in the report.
  ~30m if/when desired.

Bonus beats shipped beyond the doc:
- **Smooth shader-driven fog of war** (replaces the cell-aligned Bresenham
  FoV). See HANDOVER.
- **Shared paperdoll renderer** — one rig builder used by in-game bot,
  HUD, Outpost, and main menu. Removes the "every weapon = battleaxe"
  test-mode hack and the hardcoded mummy armor.
- **Per-deploy run modifiers** (8 modifiers, Outpost picker shows the
  rolled set). User-requested addition to encourage backtracking.
- **Stricter unlock progression** — clearing every tier-N boss to open
  tier-(N+1), instead of the doc's "any 1 boss". User call.
- **Per-tier rarity baseline** in `_roll_rarity` so high-tier branches
  naturally drop better loot.
- **UI consistency pass** — palette/font unification, rarity outline
  → square border + inset halo, unified item tooltips everywhere.
- **Stuck-detection rewrite** — frame-counts → delta-time, carve-outs
  for combat / interaction / pathing. Bot no longer teleports mid-boss-
  fight on 120Hz displays.

Remaining gameplay-loop-shaped work:

- ⬜ **Run report unlock prominence** (Beat 10) — show "TIER N CLEARED —
  Tier (N+1) unlocked!" above the loot list when applicable.
- ✅ **Item plan** (`docs/items-plan.md`) — DONE 2026-05-20. 234 items
  shipped across all 7 slots (47 swords / 32 helms / 47 armor / 27 shields
  / 20 boots / 35 rings / 26 amulets), `flavor_tags` + `drop_weights` +
  lore on every item, manifest-driven editor + sync pipeline. See
  HANDOVER "Items pipeline" section.
- ⬜ **Rings/amulets full wiring** — items + schema slots in save_state
  ready, but `paperdoll_renderer.gd::SLOT_DIRS` has no jewellery entries,
  `outpost.gd::SLOTS` const doesn't include ring1/ring2/amulet, HUD
  tooltips don't render jewellery. ~1.5h of work. Natural follow-up
  to the items pipeline migration.
- ⬜ **2H weapons / axes / maces / staves manifests** — 14 legacy
  entries (bearded_axe, chipped_claymore, dawnbreaker, fanged_dirk,
  highland_claymore, honed_dagger, iron_shortsword, mithril_blade,
  runed_warsword, shadowfang, steel_sword, thunder_cleaver, voidpiercer,
  worldsplitter) were pruned during the 1H-only items migration.
  DCSS has sprites for all of these (`spwpn_glaive_of_prune`, `urand_wrath_of_trog`,
  `spwpn_scepter_of_torment`, `urand_arc_blade` etc). Same manifest +
  editor + sync workflow as 1H swords. ~1h per slot.
- ⬜ **First flavor-tag mechanic wired** — pick a simple one (vampiric
  lifesteal, fire DoT, precision crit-multiplier) and wire it
  end-to-end in `actor.gd`. Validates the tag → mechanic pipeline
  before all 30 tags accumulate. ~45m.
- ⬜ **Bespoke per-branch bosses** — currently boss = strongest pool
  member. Doc's Hydra/Lich/Vault Warden/etc would need 24+ new enemies
  in `enemies.json` (HP/ATK/sprite/etc). Add a `boss_id` field on the
  biome to override the pool-pick; ship the 7 endgame sword uniques
  first (per the items plan — they exist in items.json now).

## Perf — done for now

Two passes complete. Pass 1 (2026-05-13) was CPU-side at 1600×900
windowed. Pass 2 (2026-05-14) was GPU + hitch at native Retina:
**fps min on forge 19 → 119, gen p95 1290ms → 18ms**. See HANDOVER for
the full breakdown.

Remaining items are all "nice to have" / "validate on other hardware":

- ⬜ **Validate on lower-tier hardware** — high-end PC, mid PC, low-end
  Windows laptop. Env-var A/B knobs (`BOTTER_NO_*`, `BOTTER_FORCE_BIOME`)
  are wired, ready for hypothesis tests on each platform. Forward+
  requires Vulkan — track which hardware falls back to gl_compatibility.
- ⬜ **Stretch mode `viewport`** — currently `canvas_items` (renders at
  window resolution). `viewport` mode renders at design size + GPU
  upscales — universal pixel-art-game perf trick on high-DPI. Changes
  pixel snap, needs a visual review under `/showcase` before shipping.
- ⬜ **Glow / bloom video options toggle** — `WorldEnvironment.glow_*`
  is on unconditionally for ~+1% cost. Add a graphics-options toggle
  for low-end targets. Low priority.
- ⬜ **Outlier vaults** — `des_grunt_crypt_end_deaths_head`,
  `des_quadcrypt_mu`, `des_hellmonk_crystal_mountain` consistently top
  the perf-floor ranking. Cosmetic perf — inspect for excess decor,
  light count, or pathological room shapes only if a low-end target
  struggles on these floors.
- ⬜ **Shadow filter for ambient decor** — drop PCF5 to NONE/PCF13 only
  if a low-end target shows shadows as the cost. Currently zero impact
  on M3 Pro. The `BOTTER_SHADOW_FILTER` env var is the test harness.
- ⬜ **MapRenderer fade dirty-set** — minor (~410µs); skip if not seen
  in the wild.
- ⬜ **`_carve_layout` p95 53ms** — biggest remaining gen hitch on
  forge. Already async-split at the build-floor level so the user
  sees it as a stutter, not a freeze. Could split internally if a
  weaker target shows it as a problem.

## New skills shipped

- ✅ `/showcase` — visual audit floor with one station per feature.
  See `.claude/skills/showcase/`. Use for any flicker / glow / terrain /
  loot-rarity visual iteration. Bot patrols a fixed path so each
  station enters its light radius in turn.

## Combat pass — partly shipped 2026-05-15

- ✅ **Affix expansion** — collapsed to 6 affixes, all 6 wired
  (Strength/Stamina/Agility/Regen/Crit/Haste). The old 30-affix system
  with 24 decorative stats is gone.
- ✅ **Real paper-doll** — `paperdoll_renderer.gd` builds layered Sprite2D
  rig from equipped weapon/armor/helm/shield/boots. Used in-game and
  on every UI surface.
- ⬜ **Enemy attack effects** — currently bot has weapon overlay + swing
  animation. Enemies just have hit_squish on hit. Add per-enemy attack
  animations: dragon breath, mage cast, archer shoot.

## Active — directional tiles continuation

Edge overlays and sigils both shipped. Remaining: multi-tile creatures.

### Multi-tile creatures (deferred)

Visual scaling shipped — see HANDOVER.md "Big-creature visual scaling".
32 creatures (dragons, giants, sphinx, mummies, jellies, etc) render at
1.3-1.6× scale with proper anchor + z-ordering. Logical layer still 1
cell per creature.

True multi-cell mechanics (vine_segment chains, kraken with 4 tentacle
cells, serpent_of_hell) deferred because:

- Shipped CC0 DCSS pack is 32×32 only. The 32×64 unique-monster sprites
  DCSS uses for big creatures are not in our pack. Custom 32×64 art or
  bigger sprites would be needed.
- Pathfinding (AStarGrid2D) doesn't natively support multi-cell shape
  obstacles. Enemy class would need a `multi_tile_layout` of relative
  cell offsets; pathfinder must mark all occupied cells solid; bot
  attack-target picker needs nearest-cell-of-creature math; spawn
  validation needs N-cell open-region check.
- Tentacle chain solver (per-frame chain physics or grid-based tail
  follow) is its own beat.

Architectural sketch when we revisit: Enemy gets optional
`multi_tile_layout: Array[Vector2i]` (offsets from head). Pathfinder
treats all occupied cells as solid against other enemies. Bot adjacency
test = `min(chebyshev to any creature cell)`. Render: parent sprite at
head, child sprites at offsets. Spawn validates an N-cell open
"footprint" before placement.

## HP scaling — DONE (root cause identified + fixed)

Root cause: `Bot.gain_xp` was setting `hp = max_hp` on every level-up, fully
healing the bot every time it levelled. With 50% xp boost (Sif Muna) or
chained kills, level-ups happened mid-floor, so HP never appeared to drop.
Fix: level-up grants only the +8 max_hp slice (`hp = mini(max_hp, hp + 8)`),
no full heal.

Combined with save-state isolation (level-1 fresh start instead of grind-
inflated bot at lvl 247), the dungeon now correctly tests as hard. Bots
die at floor 2-3 unequipped; will need to playtest gear progression to
balance.

---

## Variety pass — partly shipped, rest pending

The "1.5 variety pass" originally listed as 9 sub-stages. Status:

- ✅ **1.5a Smart tile placement** — uniform walls (`wall_primary` + 5-10%
  `wall_accents`), Voronoi floor patches, strict prefix matching to avoid
  pulling directional overlays as primary.
- ✅ **Edge overlays** (was nominally part of 1.5e but shipped as its own
  beat) — grass / dirt / slime / shoreline directional autotile.
- ✅ **1.5-fog+light** — bot lantern, world Light2Ds (altars, fountains,
  legendaries, lava cells in Forge), per-cell visibility state machine,
  WorldEnvironment with bloom.
- ✅ **1.5-walls** (impassable terrain variety) — `wall_alternates` system,
  per-biome cluster themes (water in Shoals, trees in Forest, etc).
- ✅ **1.5b Decor scatter** — `AmbientDecor` system, per-biome decor pool
  with weighted ids and density.
- ✅ **1.5c Monster expansion** — went from 10 to ~177 unique monsters
  (per atlas). Many enemy pools now use 6-15 candidates per biome.
- ✅ **1.5d Artefact items** — legendaries pull from `item/weapon/artefact/`
  and `item/armor/artefact/` pools via `tile_override`.
- ✅ **Sigils + multi-tile decor** — single-tile room sigils on stone-tier
  biomes + multi-tile compositions via vault `decor_overlays` field. The
  `decor_overlays` system is general — reusable for future multi-tile
  decor (zot generators, abyss chaos rings, hive honeycomb patterns).
- ✅ **1.5e Special features (terrain)** — `L`/`l` (lava, 5%/0.5s damage),
  `W`/`w` (water, 50% move speed), `I` (ice visual-only). Six mini-vaults
  for forge/shoals/swamp/glacier/crypt with irregular organic shapes.
  Pathfinder weight 4.0 lava / 2.0 water. JSON sidecar exposes counts.
  Plus river/lake/pools builder converts FLOOR cells to T_WATER / T_LAVA
  procedurally on biomes with `liquid_type` set. Wired through both
  `basic_level` and `delve` paths. Still TODO: `t` (tree), `B` (bones),
  `M` (mushroom) impassable decor; ice-slip mechanic.
- ✅ **Floor pass** — per-cell hashed weighted variant pick (replaces
  Voronoi patches), directional sigils stripped from per-room placement,
  Lair dual-floor mix pilot via Perlin noise (lair-grass + moss),
  `liquid_type` field threaded through generators so caves layouts can
  also stamp rivers/lakes.
- ✅ **1.5f Door tiles** — vault `+` glyph renders as closed/runed/sealed
  door per biome (3 sprites, mapping in MapRenderer.DOOR_BY_BIOME).
- ✅ **1.5g Combat effects** — Effects helper class. Biome-themed kill
  flashes (fire/ice/blood), magic shimmer on legendary pickups + altar
  grants, gold sparkle on rares.
- ⬜ **1.5h Negative space** — partially done via fog; could be tighter
  (smaller playable area, tighter camera).
- ✅ **1.5i DCSS-style UI** — landscape 1280×720 viewport, right
  sidebar with minimap + stats + log feed, bottom-left bag panel
  (equipped slots + scrollable inventory), tiny top-left debug HUD
  (biome/vaults/cells/fps). Mobile port deferred — desktop is the
  primary target now.

## DCSS-port — phases

### Phase A — port DCSS algorithms (mostly done)

- ✅ `dgn_build_basic_level` → `DCSSLayouts.basic_level` (trail + rooms)
- ✅ `delve()` cave generator → `DCSSLayouts.delve` (with `caves`,
  `caves_tight`, `caves_open` parameter presets)
- ⬜ `dgn-shoals.cc` — branch-specific Shoals generator (tide pools, sand
  islands)
- ⬜ `dgn-swamp.cc` — branch-specific Swamp generator (boggy paths, water
  expanses)
- ⬜ `dgn-proclayouts.cc` — Worley/Perlin layouts (`RiverLayout`,
  `ColumnLayout`, `DiamondLayout`, `WastesLayout`)
- ⬜ `dgn-irregular-box.cc` — non-rectangular rooms

### Phase B — port DCSS data tables

- ⬜ `enemies.json` — replace stats with DCSS `mon-data.h` values (decades-
  tuned). Currently using a mix of hand-rolled and partial ports.
- ✅ `items.json` — DONE 2026-05-20. 234 items across 7 slots, base types
  derived from DCSS `item-prop.cc` and `item-prop-enum.h` jewellery enum.
  Manifest-driven via `tools/items_*_manifest.json` + `tools/item_editor.html`
  + `tools/sync_items.py`. **Affixes are still the simplified 6-stat system
  from the gameplay-loop overhaul** (Strength/Stamina/Agility/Regen/Crit/Haste);
  the DCSS `ego` enum is documented as `flavor_tags` for future-mechanic
  wiring but doesn't drop additional stats today.
- ⬜ `biomes.json` → eventually rename to `branches.json`. One entry per
  real DCSS branch with its actual generator id, enemy pool, vault tags,
  ambient features.

### Phase C — bot AI + idle loop (the actual game)

This is the only Botter-unique creative work. Big chunks shipped 2026-05-15:

- ⬜ Configurable bot priorities (started — proximity-ranked behavior).
  Bot AI has aggro range cap (8 cells), current-room loot priority,
  low-HP retreat. Exposing these as Outpost sliders is still pending.
- ✅ Run-config: branch picker in Outpost. Per-deploy modifier rolls
  offer flavour variation. Behavioral preferences (greed vs caution,
  melee vs ranged) still pending.
- ✅ Idle reward curves — offline progress capped at 1h, "While You
  Were Away" summary on launch.
- ⬜ Meta-progression — `bot_upgrades` shipped (gold sink, permanent).
  Prestige (`shards`) field reserved in save state; no implementation
  yet.
- ✅ Visual presentation (smooth fog, paperdoll, rarity decor, segmented
  inventory).

## Generation pipeline — DCSS-faithful gaps

Caught up substantially this session. Remaining gaps in the canonical
DCSS order:

- ⬜ **Doors aren't placed by the layout** — `_place_doors_in_corridors()`
  in `basic_level` is a stub. DCSS does it inside `_make_room`.
- ⬜ **Branch-entry vault stamping** — slot 4 in the pipeline is reserved
  but unused. Once we have branch transitions, this becomes meaningful.
- ⬜ **Chance vault gating** — DCSS has per-vault probability tables (e.g.
  "20% on D:2, fallback 0"). We use a flat `chance` field. Port the
  per-branch table.
- ⬜ **DEPTH algebra** — DCSS supports `D:2-7`, `Lair:1-3`, `!Zot`. We use
  simple `[min, max]` integer ranges.
- ⬜ **`SUBVAULT` glyph** — vaults can reference other vaults by name.
  Skipped intentionally per agent recommendation; revisit if vault authoring
  ever needs nesting.

## DCSS branch roster — port status

Phase 1 ship-ready (have biome + assets): D, Lair, Orc, Swamp, Vaults, Crypt,
Tomb, Zot — all in production.

Phase 2 (1-2 sprites needed): Elf ✅ shipped, Snake ✅, Spider ✅, Shoals ✅,
Depths ✅, Slime ✅, Forge ✅ (cross-pollinated with zot), Glacier ✅
(cross-pollinated with crypt). All in production.

Phase 3 (heavier lift, deferred):

- ⬜ Hell tier (Vestibule, Dis, Geh, Coc, Tar) — endgame branches with
  custom procgen and signature monster waves.
- ⬜ Pan / Abyss morphing geometry — DCSS regenerates these every step.
  Deferred; current biomes use static layouts as a stand-in.
- ⬜ Dedicated branch generators — Shoals tide pools, Swamp bogs (currently
  using `caves_open` / `caves` as approximations).

## Quality / regression telemetry

Already shipping:

- ✅ `[gen]` per-floor metrics (cells, largest region, regions, bbox, rooms)
- ✅ `[bad-floor]` flags (floor_count<250, largest_region<400, bbox<400,
  orphan_cells>60)
- ✅ Stall snapshots dumped on hard-recovery (`user://stall_snapshot_floor*.txt`)
- ✅ `[floor]` per-floor outcome (kills, loot, ticks, hp_lost)
- ✅ `[run]` per-run summary (kills, loot, portals, stalls, biomes,
  unique vaults)
- ✅ Auto-grind harness with N-run support

Still want:

- ⬜ **Aggregate end-of-grind report**: "5 runs, 50 floors, X% bad-floor rate".
  Currently you'd have to grep yourself.
- ⬜ **Generator unit-style harness**: headless script that calls
  `DungeonGenerator.generate()` 200× per layout, prints bad-floor rate per
  layout. Run before merging generator changes.

## Tooling — infrastructure

Quality-of-life upgrades to land before more feature work piles up.

### Permission allowlist — DONE

Shipped. .claude/settings.json now allows common patterns: read-only git
(status/log/diff/show), python3, bash skills, find/grep/sed/awk/jq, file
ops, etc. Destructive ops (rm, git push, git reset --hard, gh) stay
behind `ask`.

### Save-state isolation — DONE

Shipped: `SaveState.debug_mode = true` when AUTO_GRIND or DEBUG_FLOOR
markers are present, routing IO to `user://botter_save_debug.json`. Live
`botter_save.json` is untouched by benchmark/screenshot runs.

### class_name refresh wrapper — DONE

Shipped: `tools/refresh_class_cache.sh` wraps `godot --headless --import`
and reports class count. Both `/screenshot` and `/grind` skills auto-detect
"Parse Error: ... not declared" in their log output and re-run with
refresh.

### Pre-commit headless validation

Run a 1-floor-per-biome smoke build, grep for `[bad-floor]` or any `ERROR`/
`SCRIPT ERROR` in the output, exit non-zero if found. Wire as a pre-commit
hook OR as a `tools/check_before_commit.sh` script. Catches generator
regressions and parse errors before they land. Should take <30s with
debug-jump's per-biome 1-floor mode.

## Tooling — skills

- ✅ `/screenshot <biome> [vault] [floor]` — captures one PNG + JSON sidecar
  per call. See `.claude/skills/screenshot/`.
- ✅ `/grind <runs> [speed]` — N-run headless harness, structured summary.
- ✅ `/benchmark <duration_s> [speed] [label] [headless|windowed]` —
  time-bounded headless run with PerfMon telemetry; `parse_perf.py`
  ranks worst floors / vaults; `compare.sh` diffs two logs.
- ⬜ **Batch screenshot mode** — single Godot process with TCP eval to
  capture N biomes at the cost of one cold start. The fork
  `tugcantopaloglu/godot-mcp` (cloned to `/Users/dyo/claude/external/godot-mcp-fork`)
  shows the pattern: an autoload TCP server accepts JSON commands. Worth
  porting if we ever need a 24-biome audit in one shot.

## Visual effects — color grading shipped 2026-05-21, more queued

The bot plays itself, so visual polish is what makes biomes feel
distinct. Existing render stack: shader fog of war, WorldEnvironment
bloom, per-light flicker (FastNoiseLite), ember GPUParticles2D, sprite
FX, edge overlays. Per-biome `modulate` was barely perceptible. New
`color_grade` shader replaces that with a real LUT-style post-process.

- ✅ **Per-biome color grading** — `assets/color_grade.gdshader` +
  `scripts/color_grade.gd`. 8 of 24 biomes curated with tint/saturation/
  contrast/vignette. Layer 60 (between fog and HUD). Gated by
  `BOTTER_NO_GRADE=1`. See HANDOVER "Color grading shader" section.
- ✅ **Extend grades to remaining 16 biomes** — shipped 2026-05-21.
  All 24 biomes now have curated `color_grade` entries.
- ✅ **Heat haze on T_LAVA tiles** — shipped 2026-05-21.
- ✅ **Water shimmer on T_WATER** — shipped 2026-05-21. Per-cell
  horizontal flow + wobble shader, slight blue tint.
- ✅ **Memory desaturation** — shipped 2026-05-21. Modified
  `tile_visibility.gdshader` to read `FogSystem.vis_texture` and
  desaturate cells in memory state. Strength tunable via shader
  uniform, gated by `gfx.memory_desat`.
- ✅ **Threat-tier outline** — shipped 2026-05-21. 4-direction
  neighbor-sample shader on enemy sprites. Tier 0/1/2/3 from a
  hits-to-kill heuristic. Computed in `dungeon._apply_threat_auras()`
  per floor build.
- ✅ **Light cookies on PointLight2D** — shipped 2026-05-21. Optional
  `cookie` field in `light_spec.SPECS`. 4 starter cookies authored
  programmatically (stained_glass / prison_bars / web / stardust).
  `sigil` and `firefly` specs use them.
- ✅ **Video options graphics toggles** — shipped 2026-05-21. Each
  effect toggleable from in-game Video Options menu via dynamically-
  added CheckBoxes. Settings persist to `user://video_settings.json`.
- ⬜ **Light cookies — author themed cookies for biomes** — current 4
  cookies are programmatically generated test patterns. Hand-authored
  cookies for elf (stained glass arches), tomb (prison bars), spider
  (web with center hub), forge (forge-flame plume) would feel more
  intentional.
- ⬜ **Quality presets in video options** — `VideoSettings.GFX_PRESET_*`
  exist but no UI buttons to apply them. Add 3 buttons (Low/Med/High)
  that batch-set all toggles.
- ⬜ **Dithered fog transitions** (bayer) — option for hard-edged
  pixel-art-authentic fog instead of the current smooth gradient.
  Subjective.
- ⬜ **Scanlines / CRT shader** — opt-in graphics option. Polarizing,
  default off.
- ⬜ **Heat haze on torches** — same shader could apply to fire-tier
  light specs (campfire, lava actor, etc) for a more dramatic forge
  feel. Currently only T_LAVA terrain cells.

## Tooling — playthrough harness (shipped 2026-05-21)

- ✅ `/playthrough --equip POLICY --upgrade POLICY --advance POLICY` —
  simulates full game start-to-finish. Reads/writes save state directly
  between runs (Godot mutates inventory/level/gold during runs;
  policies mutate equipped/upgrades/last_branch between runs).
  3 equip × 3 upgrade × 3 advance = 27 policy combos, currently 3
  curated combos chained via `tools/run_playthrough_trio.sh`.
- ⬜ **Per-tier playtime calibration findings** — once the trio
  completes, write up tier-by-tier wall-clock estimates and identify
  any soft walls (tier where progression stalls). Compare across the
  3 policy archetypes (neutral / DPS / cautious).
- ⬜ **Loot-pickup policy** — currently `loot_filter` is "common" so
  the bot grabs everything. A policy that filters (e.g. "epic+ only
  past tier 3") would simulate gear-pruning gameplay.
- ⬜ **Build re-spec mid-playthrough** — playthroughs commit to one
  equip/upgrade policy throughout. A real player might pivot (start
  combat-first, switch to hp-first when reaching crypt). Worth modeling
  later.

## Tooling — experiment harness (shipped 2026-05-21)

After a sweep died mid-experiment when a polling Bash command SIGTERM'd
its parent shell, the chain was hardened:

- ✅ `tools/run_experiment.sh` — nohup + double-fork wrapper. Survives
  parent SIGTERM. Writes PID + exit-status files. Stream unbuffered
  output to log file. Standard pattern for any long-running detached job.
- ✅ Sweep durability — `sweep.py` persists `sweep_partial_variant` to
  `index.jsonl` after each variant. Kill mid-sweep loses ≤ one variant.
- ✅ `balance.run_grind` timeout 60s/run → 90s/run (min 120s). Tanky
  builds were getting clipped mid-floor-4.
- ⬜ **Parallel runner** (still unbuilt). Sweeps are sequential. Multiple
  Godot instances would cut wall-clock by core count. Needs save-state
  isolation per worker (each writes to its own user_data dir, e.g. via
  a `--user-data-dir` Godot flag — verify this exists or simulate).
  ~50-min sweep → ~10min on M3 Pro.

## Tooling — balance pipeline (shipped 2026-05-20)

- ✅ `BOTTER_SEED=<int>` — seeds dungeon rng + Godot global rng. Same
  seed + same save = byte-identical world. Per-floor reseed so combat
  doesn't consume world entropy.
- ✅ `BOTTER_NO_INVINCIBLE=1` — opt out of grind invincibility so duels
  produce real win-rate signal. Set automatically by /duel and /sweep.
- ✅ `tools/inject_save.py` — JSON build spec → debug save. Validates
  ids/tiers/branches. Affix shorthand reads tier values from affixes.json.
- ✅ `[combat]` log tag in actor.gd — per-attack structured event
  (attacker, defender, weapon, damage, crit, boss flag).
- ✅ `tools/parse_grind.py` — shared dataclass parser. CLI mode for
  ad-hoc inspection.
- ✅ `tools/balance.py` — harness for /duel and /sweep. Includes
  `run_grind`, `inject`, `append_index`, marker hygiene.
- ✅ `/equip` skill — shorthand build-spec parser. Validates and
  writes to debug save.
- ✅ `/duel` skill — A/B test two builds across same N seeds. Wilson
  CI on win rate, paired stats, damage attribution.
- ✅ `/sweep` skill — vary one parameter across N runs. @set tokens
  (@legendary, @epic_weapon, etc) for item sweeps. --affix --tiers
  for stat curve sweeps. Ranked output table.
- ⬜ **Parallel runner** — sweeps are sequential. Multiple Godot
  instances would cut wall-clock by core count (~50-min sweep → ~10min).
  Need to handle save state isolation per worker (each worker writes
  to its own user_data dir or uses --user-data-dir override).
- ⬜ **HP-loss telemetry** — `[combat] dealt` is bot-attacker only
  meaningfully populated. For "did bot survive narrowly" we need HP
  curves over time. Add `[hp] f=N t=N hp=N max=N` line per second-ish.
- ⬜ **Cross-branch sweeps** — `--branches dungeon,lair,forge` to
  compare a build's win rate across tiers. Build when needed.

See `docs/balance-pipeline.md`.

## Tooling — items pipeline (shipped 2026-05-20)

- ✅ `tools/item_editor.html` — slot-tabbed browser editor (1H Swords /
  Helms / Armor / Shields / Boots / Rings / Amulets). Per-slot manifests
  in `tools/items_*_manifest.json`. Drop-weight sliders, flavor-tag
  toggles, sprite picker with slot-aware filters. Serve via
  `python3 -m http.server` from repo root.
- ✅ `tools/sync_items.py` — full or partial sync. Copies sprites from
  `dcss/Dungeon Crawl Stone Soup Full/` → `project/assets/tiles/items/`
  (and `player/<slot>/` for paperdoll), merges into
  `project/data/items.json` by item id. Flags: `--dry-run`,
  `--prune-legacy`. Run from repo root.
- ✅ Drop-weight integration — `dungeon.gd::_pick_loot_id(rarity)` + 3
  loot-path call sites + `offline_progress.gd::_roll_loot` filter.
  Items respect `drop_weights[branch_tier-1]`; uniques tracked per-run
  via `run_dropped_uniques`.

## Asset utilization — gaps

- ⬜ **Doors** — 30 door sprites, none used (vault `+` renders as plain floor)
- ⬜ **Traps** — 24 trap sprites, none used
- ⬜ **Effects** — 238 effect frames (blood, fire, ice, magic), none used
- ✅ **Player paper-doll** — `scripts/paperdoll_renderer.gd` builds layered
  Sprite2D rig from `equipped`. Used in-game + every UI surface. Asset
  set added under `project/assets/tiles/player/` (body/, helm/, shield/,
  boots/, weapons/). 975+ sprites still available for variety expansion.
- ✅ **God altar variants** — expanded from 7 to 22. Beogh/Makhleb/Yred/
  TSO/Lugonu/Jiyva/Fedhas/Cheibriados/Xom/Ashenzari/Dithmenos/Gozag/
  Qazlal/Nemelex/Ru added with thematic blessings + glow colors.
- ✅ **Organic flame jitter** — done. FlickerDriver runs FastNoiseLite
  per-light with unique seeds so flames desync. Sub-pixel jitter on
  fire-category lights. Ember particles on flame sources.

## Open questions — defer until needed

- PvP (async — your bot vs. another player's dungeon config)
- Prestige / rebirth for endgame
- Clan / guild social features
- Steam Deck support alongside mobile
- Monetization model

## Out of scope (decided no)

- DCSS *source code* in the project (GPLv2+ would force the whole game
  open-source). Tiles only (CC0).
- Lua hooks in vaults — code-in-data is bad.
- Original HTML prototype's structure — was a visual mockup, not a target
  architecture.
- Auto-running the editor or auto-screenshotting in normal sessions — the
  user opens Godot themselves. Screenshot mode is opt-in via
  `DEBUG_FLOOR.txt` marker, captured by the `/screenshot` skill.
