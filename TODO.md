# Botter — TODO

Roadmap and deferred items. The "what works today" lives in `HANDOVER.md`;
the durable rules in `CLAUDE.md`. Update this file when committing.

---

## Tier 0 legal hygiene (2026-06-08)

Shipped. Three audit-flagged exposures closed before public release:

- ✅ **Vault bundle excluded from web .pck.** `export_presets.cfg`
  exclude_filter now matches `data/vaults/*.json,data/vaults_bundle.json`.
  Re-exported v15 build verified: 0 occurrences of `des_minmay`,
  `des_hangedman`, `des_nicolae`, `vaults_bundle.json`, or DES content
  fields (`NAME`, `ORIENT`, `KFEAT`).
- ✅ **GitHub Pages allowlist.** `.github/workflows/pages.yml` no
  longer does `cp -R project/data`. Now copies only the 6 JSONs
  browser tools fetch (items, affixes, enchant_combos, biomes,
  tile_atlas, drop_tuning). On next push to `main`, the live
  `dnyo.co.uk/botter-idle/project/data/vaults/` paths will start
  returning 404.
- ✅ **Tile dir manifest scrubbed.** `tools/build_tile_dir_manifest.py`
  no longer enumerates `data/vaults/`. Without this, the manifest
  was leaking 1320 contributor-stamped vault filenames into the
  web .pck even with the bundle excluded.
- ✅ **README honesty.** Stripped false "Offline progress (capped 1h)"
  claim (offline progression is a no-op since 2026-06-06). Replaced
  "TBD likely permissive" license stub with explicit
  "all rights reserved, public preview only" pending Tier 2
  resolution. Removed false "vault format is data, free to use"
  claim.

### Still TBD (Tier 1 / Tier 2)

- Tier 1: ~~`unspent_points` typo~~, ~~ring-collapse migration gate~~,
  ~~chest loot persistence~~, ~~StatCalc unification residue cluster
  (blessings + species + elements + lifesteal + per-god buff icons)~~,
  ~~combat correctness passes (single avoidance roll per swing, spell
  `damage_type` piping, item `damage_min/max` reads, `spell_proj_bonus`
  clamp)~~ all shipped 2026-06-08. Tier 1 audit cluster complete.
- Tier 1 follow-up (noticed during chest-loot fix, out of scope for
  that audit task): `dungeon.gd::_end_run` has the same in-flight
  LootDrop vulnerability that `flush_to_save` had pre-`f80376b`. If
  the bot dies while drops are mid-air (chest opened the same tick
  combat ended in defeat), those drops are discarded with the
  dungeon scene. Fix is a one-liner — call
  `_fold_pending_loot_drops_into_inventory()` at the top of
  `_end_run`, same as `flush_to_save` now does. Low-priority
  because it requires precisely-timed death + open-chest, but
  trivial to ship.
- Tier 2: NOTICE.md / CREDITS surface enumerating CC0 tile attribution
  + Godot MIT — pre-req before final license grant.
- ~~Tier 2 (CRITICAL): clean-room rewrite of `dcss_layouts.gd`~~
  Shipped 2026-06-08. Fresh-session rewrite from
  `~/claude/game-audit/findings/dcss_layouts_descriptions.md` —
  rewriter session never opened `dcss-source/` or the prior
  `dcss_layouts.gd`. New names, new control-flow shape, new
  closed-form density divisor (replaces the 12-entry
  `denom_table`). 666 insertions / 798 deletions vs prior file.
  Top-of-file provenance comment in place. Validation: `/grind 5`
  produces playable runs (variable victory rate, within historical
  fresh-save variance).
- Tier 2 follow-up: NOTICE.md / CREDITS surface should call out that
  dungeon-layout algorithms are now original GDScript implementations
  inspired by standard dungeon-gen patterns (drunkard-walk, cellular
  excavation), not derived from DCSS source.

---

## HTML5 / itch.io shipping (2026-06-08)

**Status:** Shipped. Friend playtesting in Safari confirms smooth
gameplay (other than Safari's 60fps cap, which is browser policy
and not a build issue). Live at
https://deanyo-gh.itch.io/botter-idle, restricted visibility.

### Done

- HTML5 export working with single-threaded WASM + Compatibility
  renderer (no SharedArrayBuffer dependency, runs in any browser)
- itch.io project page set up + cover/description/credits, profile
  pad copy in `itch/profile.md`, devlog draft in `itch/devlog_001_first_build.md`
- butler push pipeline + `/deploy-web` skill + `tools/deploy_web.sh`
- Manual zip fallback path documented (itch CDN occasionally lags)
- Per-deploy version stamp visible in HUD + browser tab title
- Vault bundle, tile dir manifest, multi-source TileSet — see
  `HANDOVER.md` web-perf section
- Wave-spawn stagger + RenderingServer GPU prewarm
- Shared shader materials across map/particle/recolor surfaces
- Web-specific shader skips (threat outline, item recolor, light
  shadows, weapon-glow pulse)
- Fog overlay shader halved march steps + lights capped at 8 on web
- `[perf-spike]` diagnostic with browser-throttle filtering
- `[perf]` rolling stats line (frame_ms / fps / draws / per-system µs)
- Always-visible fullscreen button in HUD top-right
- Pause-menu fullscreen toggle (uses `JavaScriptBridge.eval` to
  call `canvas.requestFullscreen()` on web — Godot's
  `DisplayServer.window_set_mode` no-ops in browsers)

### Web-perf follow-ups (deferred — current state is good enough)

- **First-floor cold-load is still ~5-15s** on a never-loaded biome.
  RenderingServer prewarm helps subsequent floors but the first
  visible frame still pays a one-time pipeline-state compile per
  unique (texture × shader) combination. To drive it lower we'd
  need to render every prewarmed texture through the SAME shader
  the dungeon uses (visibility shader on TileMapLayer) — that's a
  bigger refactor.
- **Compatibility renderer** is the only one we ship to web. Forward+
  on web is supported in Godot 4.6 and might have totally different
  perf characteristics. Worth a one-day spike if web becomes a real
  target later, but Steam + mobile are the actual end-game so don't
  invest more here.
- **wasm size** is 36 MB (~12 MB gzipped). Stripping unused engine
  modules via a custom export template would shrink first-load,
  but it's a multi-hour build pipeline change for a target we're
  not committing to long-term.
- **itch.io CDN propagation lag.** butler push reports success but
  Chrome/Firefox can serve stale wasm/pck for several minutes.
  Workaround: manual zip upload via the itch edit page. No code
  fix possible — itch infrastructure issue.

---

## Balance validation 10-run snapshot (2026-06-07)

After the floor-1-2 density softening + shop rarity gate. NB: grind
elapsed at 16× = real-time ÷ 16; multiply for player time.

### `naked` × 10 (D:1, mortal)

10/10 die floor 1. Bot levels 1→2 by run 5+ from accumulated XP.
Elapsed 1.5-14.6s grind = 24s-234s real time. Bare hands vs 60 mobs
at Lv1. Pessimistic baseline working as designed.

### `t1` × 10 (D:1, mortal)

Floor reached: 1,1,1,3,2,2,2,3,3,2 (mean 2.0 — was f1 in 3-run).
Level: 7→27 (gained 20 across 10 runs, decent curve).
Gold: 275→5706 cumulative.
**Working as intended** — real progression curve, varied outcomes,
levels-up across runs feel real.

### `t2` × 10 (lair, mortal)

Floor reached: 1,3,1,1,1,1,1,2,1 + 1 (mean ~1.3, mostly floor-1
deaths). Level: 12→28, Gold: 307→3364.
**Worth investigating** — t2 lair specifically is harder than t1
dungeon for an equipped t2-preset bot. Possibly:
- Lair mob CR (wolves/cougars) outpaces uncommon-affix gear
- 90 mobs on floor 2 is still a war of attrition
- t2 preset gear is sized to T2 entry, not full clear

### `t3` × 10 (snake, mortal)

Floor reached: 3,2,6,6,2,6,6,6,6,6 (mean ~4.9, hits the boss
floor by run 3 onward). Level: 22→121 (huge growth). Gold:
3513→70734 (cumulative ~70k).

0/10 victories — bot reaches the boss floor but doesn't kill the
boss. Boss = real progression gate, working as intended. After
~5 runs the bot is comfortably reaching f6 and chipping at the
boss; would expect a victory in ~15-20 runs of mortal progression.

---

## Balance validation snapshot (2026-06-07, earlier)

After landing the affix DR, soft caps, XP doubling, slot-weighted
drops, spell gating, and longer spell CDs, ran mortal preset grinds
to actually test the curve. Results below.

| Preset | Branch  | Run 1 | Run 2 | Run 3 | Trend |
|--------|---------|-------|-------|-------|-------|
| naked  | dungeon | f1 0k | f1 0k | f1 0k | dies in 1-3s |
| t1     | dungeon | f1 0k | f2 115k | f2 175k | f2-2-2 |
| t2     | lair    | f1 0k | f1 0k | f4 879k 2 portals | spike up |
| t3     | snake   | f4 1081k | f3 493k | f6 2070k 95 loot | f4-3-6 |

Reads:

- **`naked` is too brutal.** Lv 1 with no gear dies in 1-3 seconds
  before getting a single kill. A fresh-save first run should at
  least clear a few rats. Either the starting hp/atk needs a buff
  or the early floor-1 spawn density needs to scale to bot CR.
  ⬜ TODO: investigate _spawn_enemies for floor-1 density and the
     base bot HP/atk at level 1.
- **`t1` is good.** First run is hard (dies floor 1) but levels 5→8
  by run 2, makes floor 2 with 115 kills. Run 3 → floor 2 with 175
  kills. Roughly the "leveling-up curve in tier-1" feel.
- **`t2` is bumpy.** Two floor-1 deaths then a huge run with 879
  kills + 2 portals + reaching floor 4. The variance is real but
  could mean lair RNG is swingy. Worth a 10-run grind for stats.
- **`t3` works as intended.** Bot reaches floor 6 in two of three
  runs but doesn't clear the boss. Boss floors gating progression
  is the design — to advance you need rare+ gear with strong affixes,
  which the t3 preset has but only just enough.

Net: balance changes are directionally right. Curve is real, gear
matters, deaths happen at sensible rates. Two findings flagged for
follow-up:
- ⬜ **Floor-1 lethality in `naked` preset** — a Lv 1 player should
  not die in 1-3s on dungeon. May be a bug in encounter scaling
  vs CR=20 (cr_recommended).
- ⬜ **t2 variance** — 10-run sample needed to know if it's RNG
  or a real curve gap.

---

## Balance pass (HIGHEST priority — surfaced 2026-06-06 after stat audit)

The stat-system unification (StatCalc.compute) now correctly applies
meta_mult + Quality + worn-tag passives + bot upgrades — which made
visible just how overpowered the existing affix stacking is. Audit on
a real save (Lv 57 / 4 runs / floor 6 / spriggan / 16 inventory
items) found the bot doing **1500+ damage per swing on tier-1 mobs**.
Root causes:

- ⬜ **XP curve too flat** — `bot.gd::xp_to_next() = 20 + (level-1) * 15`
  Level 57 cumulative cost ≈ 24,220 XP = ~6,055 XP/run on 4 runs =
  ~1,009 XP per floor. Floor mobs avg 6 XP × 100 mobs × 1.5–3.0×
  pack mult = 600–1500 XP/floor, exactly the level-flooding rate.
  Suggested: `30 + (level-1) * 30` (2× cost at every level).

- ⬜ **Affix stacking is purely linear, no soft caps.** Save's stack:
  `of_channeling × 6 = +195% spell dmg`, `of_resonance × 5 = +162%
  area`, `of_quickcast × 3 = +43% CDR`, `of_str_mastery × 3 = +73%`,
  `of_might × 3 = +24 str (= +38% atk + ~28% HP)`, `of_vitality × 2 =
  +245 flat HP (4× base!)`, `of_haste × 2 = +39%`. Tier-5 single-roll
  caps in `affixes.json`: channeling=65, vitality=160, haste=32, str=12.
  **Stacked totals exceed legendary single rolls by 3-5× because every
  slot carries the same affix.** Add diminishing returns in
  `stat_calc.gd::compute` after the per-slot loop:
  - Spell damage / area / CDR / duration: clamp 0..120 / 0..100 / 0..50
    / 0..100 (PoE-style soft caps)
  - Lifesteal: clamp 0..15
  - Track per-affix-id source count, scale 1.0 / 0.75 / 0.50 / 0.25
    for 1st / 2nd / 3rd / 4th+ source

- ⬜ **Pack-tier loot thresholds too generous** — `dungeon.gd:1985`:
  rare-pack 100% drop, miniboss 100%, magic 30%. Suggested: rare 60%,
  miniboss 70%.

- ⬜ **Shop scales high-rarity at level 30 cap** — `shop.gd:384`
  `eff_lvl = mini(lvl, 30)` already clamps but at Lv 30+ a 4-run player
  has access to fairly common epic/legendary stock. Audit if cap should
  drop to 20 or rarity weights should scale per-run instead of per-level.

- ⬜ **Per-mob gold rates** — `dungeon.gd:1932`: `1-3 + floor/2` per
  mob = ~450g/floor at floor 6 with 100 mobs. With shop gold sinks
  starting at 30g (common) up to 3000g (legendary), this is roughly
  in proportion. Watch this once the affix caps land and items become
  rarer.

- ✅ **Offline item generation REMOVED 2026-06-06** — was generating
  ~16 fully-affixed items per session boot, the single biggest power
  injection. `offline_progress.gd::apply` now returns empty summary;
  legacy body preserved for reference.

The diminishing-returns + XP-curve fix is the highest-leverage pair —
together they take a 4-run player from L57 with 14 stuffed slots to
roughly L25-30 with 6 affixed slots, which is the intended pace.

---

## UI follow-ups (HIGH priority — ongoing)

Landed 2026-06-06 (HUD sidebar tabs):
- HUD right sidebar → always-visible name+Lv+HP header + TabContainer
  with Stats / Weapon / Buffs tabs (`hud_chrome.gd::_build_stats_pane`).
  Mirrors outpost Character pane structure.
- Per-section clipping panels: every sidebar widget now lives inside
  a `Control` with `clip_contents = true`. Long item / weapon / affix
  names can no longer bleed past the panel rect.
- `_add_label_to(parent, ...)` helper added so labels can land
  inside any panel, not just the HUD root.

Landed 2026-06-06 (second beat — HUD spatial overhaul):
- Minimap relocated out of sidebar to a 160×160 top-left overlay
  (`hud_chrome.gd::_build_minimap_overlay`). Sidebar gains the freed
  height for paperdoll + tabs.
- Bag panel wrapped in `_bag_panel: Control` (`clip_contents = true`).
- HUD inventory: flat single grid, newest-at-bottom, drops the
  per-floor segment headers. Data model in `dungeon.gd` (`_loot_segments`)
  unchanged.
- HUD inventory rarity filter chips ported from outpost (Common /
  Uncommon+ / Rare+ / Epic+ / Legendary). Shares `state.loot_filter`
  with auto-pickup so chip selection ALSO governs what the bot picks up.
- Debug HUD relocated below the minimap so the minimap doesn't paint
  over the debug text.
- Outpost run-in-progress banner top_y bump (60 → 80) so the banner
  doesn't clip under deploy panels.

Landed 2026-06-06 (third beat — UI consistency):
- ItemTooltip is the canonical "describe an item" widget; both outpost
  Weapon tab and HUD Weapon tab embed it. Drops ~120 lines of bespoke
  rendering.
- UITheme font tiers (FS_TITLE/HEADER/STAT/BODY/SMALL/SECTION/TINY)
  used across HUD/outpost/main_menu. UITheme.label() helper.
- Outpost: Stats tab wrapped in ScrollContainer, Str/Dex/Int alloc
  buttons in HBox grid (no more overlap), Dmg readout dropped,
  Bot Instructions promoted to its own tab.
- HUD Stats tab matches outpost layout (sections + colored rows).
- Paperdoll fits all slots: BAG_H 340→240, stats_h tab area 320→240,
  slot floor 36→30. Spell row no longer clipped off-bottom.
- Bag dead-space at bottom killed (scroll uses full bag height).
- Main menu vignette simplified — drops HP/ATK/DEF combat line.

Still deferred from this UI beat:
- ⬜ **AI perf cost** — separate from the HUD perf hotfix landed
  2026-06-06. Latest grind logs show `ai_us=47484` (47ms/frame at
  16x speed) on f=2 and similar on f=1. Per-tick AI is ~3ms which
  is fine at 1x but worth keeping an eye on. Not regressed by today's
  UI work — long-standing. Run `/benchmark` against an older commit
  if it ever feels worse than baseline.
- ⬜ **Outpost clipping audit** — outpost.gd panels not yet wrapped
  in `clip_contents` Controls (Stats tab page now clips, but other
  panes don't). Long item names in equipped-slot tooltips, paperdoll
  picker rows, upgrades desc text can still bleed past panel rects.
- ⬜ **Camera-offset reconsider** — `dungeon.gd::_center_camera_on_bot`
  shifts the camera by half-sidebar-width and half-bag-height to
  keep the bot centred in the visible-dungeon rectangle. The minimap
  overlay (top-left, 160×160) introduces a third occluded zone but
  is small + translucent enough to not justify another shift today.
  Revisit if the bot frequently runs into the minimap zone unseen.
- ⬜ **Inventory cell highlight on filter** — when a filter chip
  hides cells, the surviving cells reflow but there's no visual
  callout that "11 of 47 hidden". A subtle row counter under the
  chips would help.

---

## UI follow-ups (HIGH priority — 2026-06-04)

The Phase A+B+C-min UI pass landed: OLED-pure-black panels (was
0.85 alpha bleed), LoadingCurtain autoload wrapping every scene
swap, `UILayout` helper class, HUD sidebar width scales with
viewport (320..480 clamp instead of fixed 356), outpost rebuilds
on debounced resize, minimap backplate transparent.

Landed in this beat (UI polish + duplication fix, 2026-06-04):
- Outpost + HUD spell-row shrink-to-fit + wrap when pane too narrow.
- HUD log feed → translucent overlay over the play area with top→
  bottom alpha gradient. Bag panel reclaims full inventory width.
- Loading curtain paints BEFORE heavy dungeon instantiate (was:
  ~1s lag before transition).
- Default Button focus + hover styleboxes via UITheme.style_button
  / style_all_buttons across main menu, outpost, run report,
  pause menu, video options, fx tuner, character create, shop.
- Drag duplication bug fixed (deep-duplicate vs prev-equipped
  identity check) + click duplication guard (instance_id verify
  before try_equip_from_segment fires).

Phase D polish work still deferred:

- **Run report defeat header** — center, larger font, full-width
  rarity-color-tinted underline.
- **Character create grid alignment** — species cards align to a
  proper grid; current species highlighted with its class color
  border.
- **Main menu bot picker tile theme** — match the new pure-black
  + amber accent palette.
- **Min font size 11px audit** — sweep every script for font sizes
  below 11 and bump.
- **Min touch target 44×44px audit** — same sweep for Button +
  ItemCell hit regions.
- **Tall / portrait layout branch** — UILayout.Shape.TALL is
  defined but no screen actually picks it yet. When Phase D ships,
  each screen needs a TALL branch with stacked + scroll layout.
- **Custom in-game cursor sprite** — replace the OS arrow with a
  themed cursor. Loading curtain already overrides the spinner;
  this is the next step.
- **Animated scene transitions** beyond LoadingCurtain — slide-in /
  slide-out effects between screens.

---

## Enchant combos (HIGH priority — 2026-06-04)

Today an item rolls AT MOST one enchant from `enchant_pool` at drop
time. Idea: rarely (~1-2% of enchant rolls), the item rolls TWO
enchants that **combine into a named compound** with a unique effect
and a distinct color.

Examples to seed the system:
- `poison + fire` → **Combustion** (poison DoT triggers a
  delayed fire flash on expiry)
- `cold + lightning` → **Brittle Storm** (frozen targets take +50%
  lightning damage)
- `holy + fire` → **Pyre** (burns harder on undead/demon enemies)
- `dark + cold` → **Hollow Frost** (freeze duration +50% on enemies
  below 50% HP)
- `vampiric + holy` → **Sanctified Drain** (lifesteal heals 2× when
  target is holy-hated)

Implementation shape:
- New `enchant_combos.json` data file mapping `[a, b]` (sorted) →
  `{ name, color, effect_id }`. Effect ids resolve to handler
  functions in actor.gd (similar to how flavor tags fire procs today).
- `dungeon._create_item_instance` enchant roll path: when rolling an
  enchant, ~5% of rolls get a SECOND independent enchant pick. If the
  pair has a combo entry, write `inst.enchant = combo.name` and
  `inst.enchant_combo = true`. The combat path looks up combo effects
  from inst.enchant_combo + the constituent flavors.
- Some uniques carry a combo INNATELY via `implicit_enchant_combo:
  "Combustion"` field — adds the combined behavior + color glow
  without rolling.
- Tooltip shows the combo name in a special unique-style line with
  the combo's blended color (gradient between the two component
  flavor colors).

Worth pairing with a "compound flavor" expansion of the tooltip glow
shader so the panel halo shifts between the two component element
colors.

---

## Combat-pivot follow-ups (2026-06-04, HIGH priority — deferred from
##  the autocast spells beat)

The autocast spells pivot landed with 5 archetypes + species variants +
density bump + base-attack weapon procs. These are the next-pass items
explicitly identified during planning — pick whichever fits the next
session's energy.

- **Spell evolutions** (VS-style: 2 spells + 1 condition → upgraded
  form). E.g. Fireball + Spinning Axes at level 5 → Comet Strike. Adds
  a long-tail build goal once base spells are tuned.
- **Spell merges / fusion** — combine two same-spell items into a
  higher rarity / level. Half-implemented for gear via meta-rarity;
  spells should follow the same pattern.
- **Spell socketing / supports** — PoE-style: link a "support gem"
  spell-item to another spell to add behavior (chain support, cold
  support, AoE support). Adds a 2nd build axis on top of equip.
- **Enemy spell variety** — elite/boss/rare-pack leaders cast their
  own spells. Adds tactical defense interest: player has to balance
  offensive + defensive spells. Strong experimental candidate.
- **Spell drag-and-drop UI** — equip-from-inventory currently picks
  "first empty spell slot." Player feedback: they want to choose
  which slot. Build a drag-and-drop swap UI (drag inventory spell →
  spell cell, drag cell → cell, etc).
- ✅ **HUD spell cooldown overlay** (shipped 2026-06-04) — radial
  ring sweep on each of the 5 HUD spell cells, driven by
  `bot.spell_cooldowns` + `SpellSystem.cooldown_fraction`.
  `chrome.update_spell_cooldowns(bot, items_db)` runs each frame.
- **Atlas / authoring portal** — races and spells need to appear in
  the atlas viewer + a "spell editor" akin to the biome editor so
  the user can author new spells without manual JSON editing. Also
  add per-species sprites to the atlas categorization.
- ✅ **Stat overhaul telegraphing** (shipped 2026-06-04) — species
  preview pane now leads with the species' STR / DEX / INT in the
  spell-class colors plus the starter spell + its class color.
- **Wave spawn animation** — current wave/burst mobs just appear at
  walkable cells. Add a brief warp-in or warning indicator so the
  player sees them coming.

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

## Critical bugs from playtest (2026-06-02 — fixed 2026-06-04)

All three reported issues fixed in the same beat.

- ✅ **Mobs/chests stack on a single tile near top of floor.** Root
  cause: `_random_walkable_cell_far_from_bot` and `_walkable_cell_near`
  had no occupancy tracking, so multiple chests/altars/fountains/
  packmates rolled the same cells. The fallback path also sampled
  the top-25%-farthest sorted, deterministically piling into one
  corner when the strict path failed. Fix: new `_spawn_used_cells`
  Dictionary populated incrementally + a weighted-pair random-pick
  fallback. Seeded with bot/stairs cells so neither hosts an
  interactable.
- ✅ **Bot descends stairs with no stair visible on the floor.**
  Root cause: `MapRenderer._stamp_decor_marks` allowed vault decor
  on `T_STAIRS_DOWN` cells, overwriting the stair sprite in the
  overlay layer. Fix: stamp on plain `T_FLOOR` only.
- ✅ **Floor tiles draw ON TOP of monster sprites.** Root cause:
  heat-haze (`z=50`) and water-shimmer (`z=49`) layers in
  `MapRenderer._attach_heat_haze` / `_attach_water_shimmer` were
  ABOVE the actor_layer (`z=10`), so monsters standing on lava/
  water cells were painted over by the shader sprite. Fix: drop
  haze to z=3, shimmer to z=2 (between tile-overlay z=1 and
  actor_layer z=10).

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
- ✅ **Beat 10 — Run report unlock prominence** (shipped 2026-06-04).
  Slow-pulsing gold "BRANCHES UNLOCKED: X, Y" banner under the run-
  report title when the run unlocked new branches. Plus title polish
  (32→56px, centered, victory/defeat-colored underline).

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

- ✅ **Run report unlock prominence** (Beat 10, shipped 2026-06-04).
  When a run unlocks new branches, the run report shows a
  slow-pulsing gold "BRANCHES UNLOCKED: X, Y" banner under the
  title. `main._on_deploy` snapshots unlocked_branches at run start;
  `_on_run_ended` diffs and injects `newly_unlocked` into the report.
  Plus title polish: bigger centered font + victory/defeat-colored
  underline strip.
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
- ✅ **Bespoke per-branch bosses** (shipped 2026-06-04). 24 hand-
  authored boss enemies in enemies.json, one per biome, sprites
  synced from DCSS monster/unique/. New `boss_id` field on each biome
  routes the boss-floor spawn to the bespoke entry; pool-pick path
  retained as fallback. Bespoke bosses keep their authored display
  name verbatim ("Boris the Lich"); pool-pick fallback still wraps
  as "Greater X."

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
