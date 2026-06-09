# Botter — Changelog

Dated archive of work that's already shipped. Moved here from `TODO.md`
during a backlog tidy — the engineering todo file should reflect what's
ahead, not what's behind. For point-in-time narrative ("what does
shipping look like RIGHT NOW") see `HANDOVER.md`. For commit-level
detail use `git log`.

This file is append-only — when a tier or beat ships, mirror the
corresponding TODO entry here as a one-paragraph summary, then delete
it from TODO.md.

---

## 2026-06-09

### Tier 2 save durability

Five-item audit cluster. Atomic `.tmp`+`.bak` rotate (`b231740`),
`SCHEMA_VERSION = 7` + versioned migration chain + downgrade refusal
(`3421610`), equipped/inventory orphan validation against items.json
(`cbd4ea1`), web `FS.syncfs` flush via `flush_to_disk(on_done)` + JS
pagehide listener + `_notification(WM_CLOSE_REQUEST)` + run-report
dismissal gated on flush callback (`b19d07f`). GUT 50→60 tests,
~941→~973 asserts.

### Tier 1 UI cleanup

7-item audit cluster, one commit per item. HUD `update_stats` hash
gate (~35% frame_ms drop in headless grind, `5c98387`); main-menu
dev-button gate (`fa18a5f`); delete-bot dialog disambiguator
(`acce5a7`); `lightning → thunderous` flavor canonicalization +
`tools/check_flavor_coverage.py` wired into pre-commit (`f93f633`,
closed 8 other coverage gaps); v1 schema residue stripped from
tooltips + ItemsDb format-version assert (`57bbc47`); duplicate
`_realize_implicit` deleted (`0a4e995`); `species_data.gd` doc
comments refreshed (`4a125f6`).

### Tier 2 test foundation

GUT 9.6.0 vendored at `project/addons/gut/`. Five test files at
`project/tests/test_*.gd` covering StatCalc, Actor combat, SaveState
migrations, AffixSystem rolling, DungeonGenerator connectivity. 47
tests, ~933 assertions, ~3s headless. Wired into
`tools/check_before_commit.sh` and CI via
`.github/workflows/test.yml`. Convention going forward: every Tier
1+ fix that touches a covered system adds at least one regression
test before commit.

---

## 2026-06-08

### Tier 0 legal hygiene

Three audit-flagged exposures closed before public release. Vault
bundle excluded from web `.pck` via `export_presets.cfg` filter (v15
build verified 0 occurrences of contributor-stamped vault filenames
or DES content fields). GitHub Pages allowlist —
`.github/workflows/pages.yml` no longer copies `project/data`
wholesale, just the 6 JSONs browser tools fetch. Tile dir manifest
scrubbed — `tools/build_tile_dir_manifest.py` no longer enumerates
`data/vaults/` (was leaking 1320 contributor-stamped filenames into
the web `.pck` even with the bundle excluded). README honesty pass —
stripped false "Offline progress" claim, replaced "TBD likely
permissive" license stub with explicit "all rights reserved, public
preview only", removed false "vault format is data, free to use"
claim.

### Tier 1 audit cluster (save / progression / StatCalc / combat)

All four tier-1 sessions shipped same-day:

- **Save/progression bug cluster** — `unspent_points` typo (`cd69e55`,
  outpost stats panel was pinned to "Unspent: 0" forever post
  level-up); octopode/naga ring2 wipe (`256ccc0`, ring-collapse
  migration was running on every load instead of once); chest-loot-
  loss on menu exit (`f80376b`, chests rolled loot at OPEN time and
  spawned LootDrop nodes; Esc → Main Menu mid-pickup discarded
  everything in `loot_drops`).

- **StatCalc residue cluster** (`81500b0`) — 15 dead gods now real
  (Trog/Zin/Beogh/Yred/TSO/Lugonu/Xom/Qazlal/Ru/Cheibriados/Dithmenos/
  Okawaru/Fedhas blessings did literally nothing pre-fix); species
  atk_pct / def_pct / aggro_flat now real (Minotaur, Naga, Demonspawn
  bonuses were shown in character_create but never read by StatCalc);
  6 element affixes (`of_pyromancer`, `of_cryomancer`, `of_storm`,
  `of_zealot`, `of_venom`, `of_shadow`) with 100% per-element soft
  cap; gear `of_lifesteal` now heals in melee; per-god buff icons (22
  `blessed_<god>` entries replacing the single generic `blessed`).
  22-test golden-master harness in `stat_calc_tests.gd`.

- **DCSS clean-room rewrite** of `dcss_layouts.gd` (`a2674e5`) — fresh
  session never opened `dcss-source/` or the prior `dcss_layouts.gd`,
  rewrote from the behavior-only description at
  `~/claude/game-audit/findings/dcss_layouts_descriptions.md`. New
  variable names, original control-flow shape, closed-form density
  divisor replaces the 12-entry `denom_table`. 666 insertions / 798
  deletions. Provenance comment in place.

- **Combat correctness cluster** (`2c8adba`, `2e66d8b`, `3825375`,
  `a0a0cf6`) — `spell_proj_bonus` clamp (was uncapped, `of_multicast`
  on 10 slots × DR-stacked totals could reach +6); spell-item
  `damage_min/max` + meta_rarity + quality (was reading
  `item.get("damage", arch.damage)` and falling through to archetype
  default 175/175 of the time); element + attacker piped into spell
  `take_damage` (8 sites in `spell_system.gd` + `projectile.gd` +
  `orbit_controller.gd` + `Projectile.caster` field — pre-fix every
  spell hit defaulted to "physical" damage_type so fireballs routed
  through armor not fire resistance); single avoidance roll per swing
  via new `Actor.resolve_swing` (was rolling evasion + thorns +
  crystal once per damage component, so a 3-element hybrid swing got
  3 dodge rolls and 3 attacker-bound thorn chunks). 17-test combat
  harness wired into pre-commit.

### HTML5 / itch.io public preview build

Shipped to `deanyo-gh/butter-idle:html5` (restricted visibility, password
gated). Single-threaded WASM + Compatibility renderer (no
SharedArrayBuffer dependency). `/deploy-web` skill +
`tools/deploy_web.sh` + butler push. Per-deploy version stamp
(`dist/.build_counter` → `data/build_version.json` → in-game HUD +
browser tab title). Web perf: vault bundle (`tools/build_vault_bundle.py`,
0.8 MB packed); tile dir manifest; multi-source TileSet (~50 sources
instead of 1 packed atlas); wave-spawn stagger (`_pending_wave_spawns`
drained one per frame); RenderingServer GPU prewarm
(`BiomeData.prewarm_biome` walks every floor/wall/overlay/sigil/enemy/
item texture); shared shader materials across map/particle/recolor
surfaces; web-specific shader skips (threat outline, item recolor,
light shadows, weapon-glow pulse); fog overlay halved march steps +
lights capped at 8 on web; `[perf-spike]` diagnostic with
browser-throttle filtering; manual zip upload fallback for itch CDN
propagation lag.

### Multi-character saves + character creation + species selector

15 species roster (DCSS-faithful). Each species has stat mods +
optional innate flavor tags (vampire→vampiric, demonspawn→demon).
Sprite swaps everywhere paperdolls render. Multi-character saves —
`botter_save.json` wraps `{characters:[…], active:int}`; existing
single-char saves auto-migrate. Slot conversion compensation —
octopode loses armor/boots/helm → gains 3 extra ring slots (4 total),
naga loses boots → 1 extra ring.

---

## 2026-06-07

### Balance validation snapshot (10-run)

After the floor-1-2 density softening + shop rarity gate. NB: grind
elapsed at 16× = real-time ÷ 16; multiply for player time.

| Preset | Branch | Floor mean | Notes |
|---|---|---|---|
| naked | dungeon | 1 | dies floor 1 in 1.5–14.6s grind |
| t1 | dungeon | 2.0 | real progression curve, varied outcomes |
| t2 | lair | ~1.3 | mostly floor-1 deaths — worth investigating |
| t3 | snake | ~4.9 | hits boss floor by run 3+, 0/10 victories |

Two findings flagged for follow-up: (1) floor-1 lethality in `naked`
preset, (2) t2 variance.

---

## 2026-06-04

### Combat pivot — autocast spells + 5 archetypes + density bump

Phase 1 — spell slot plumbing (5 new equipped slots `spell1..spell5`,
`SpellSystem` static class ticking each slot's cooldown). Phase 2-A —
Str/Dex/Int primary stats. Base 5/5/5 + species_flat + 1/level + gear
affixes (might/finesse/wisdom). New affix kinds: spell_cdr, spell_proj,
spell_proj_speed, spell_area, spell_duration, spell_damage, fire_dmg,
cold_dmg, lightning_dmg, holy_dmg, poison_dmg, dark_dmg. Phase 2-B —
Fireball end-to-end with `Projectile` node + `SpellData` archetype +
fire dispatcher. 20 spell items in items.json (5 base + 15 species
variants). Phase 3 — all 5 archetypes (Spinning Axes via
`OrbitController`, Frost Nova via `SpellAoe.spawn_ring`, Chain
Lightning via `spawn_chain`, Holy Beam via `spawn_cone`). Phase 4 —
density tripled (90 + floor*30, cap 350); wave spawns every 6-10s
top up to ~75% of target; burst events every 30-50s drop a 12-18
mob MAGIC pack; base-attack weapon procs (dagger=bleed, 1H sword=
cleave 1, 2H sword=cleave 2, 1H axe=cleave 1 full, 2H axe=cleave 3
full, mace=stun, polearm=behind hit, whip=line falloff). Phase 5 —
death survives the run (DEFEAT instead of "YOU DIED", redeploy/outpost
buttons, `run_active`/`run_branch`/`run_floor_reached` save fields).

### Spell archetype expansion (5 → 10)

5 new archetypes: `spell_magic_dart` (filler — int, CD 0.7s, low dmg,
range 9), `spell_iron_shot` (str, CD 3.5s, heavy 28-38 dmg, slow
piercing projectile), `spell_sandblast` (str, CD 2.6s, 3-cell cone),
`spell_drain` (int, CD 2.4s, dark homing projectile heals 35% of dmg
dealt), `spell_shatter` (str, CD 5s, radial physical AoE with brief
0.6s stun). 5 named uniques: Splinterfang (epic), Ironcrash (epic),
Veil of Grit (epic), Soulhunger (legendary), Earthsong (legendary).

### Item diversity pass — 309 items across 11 slots

Foundation: gloves + cloak slots added. 9 DCSS-mismatched items fixed
(parsed `dcss-source/.../art-data.txt` for ground truth — e.g.
`urand_fencer` is *Fencer's Gloves* (`ARM_GLOVES`), not boots). 17
starter items for new slots. `tools/check_item_slots.py` validates
sprite/slot/base_type alignment per DCSS source — 309/309 pass. Meta-
rarity (Ancient 1% gold +20%, Primal 0.1% red +50%) above legendary.
Per-instance recoloring + stat lean — `assets/item_recolor.gdshader`
with hue rotation + saturation + mode (normal/shimmer/inverted/
prismatic). 58 new weapons spanning 27 new base_types (axes / maces /
polearms / 2H / staves / exotics). Item secondary stats (`crit_chance`,
`atk_speed_pct`, `hp_regen` direct on items.json).

### Bespoke per-branch bosses (24)

24 hand-authored boss enemies — one per biome, sprites synced from
DCSS `monster/unique/` into `project/assets/tiles/enemies/boss_*.png`.
New `boss_id` field on each biome routes the boss-floor spawn to the
bespoke entry; pool-pick path retained as fallback. Bosses keep
authored names verbatim ("Boris the Lich"); pool-pick fallback still
wraps as "Greater X."

### Critical playtest bug triage

Three bugs from 2026-06-02 playtest, all root-caused and fixed in one
pass. Mobs/chests stack on a single tile (spawn pickers had no
occupancy tracking — new `_spawn_used_cells` Dictionary populated
incrementally + weighted-pair random-pick fallback). Invisible stairs
(`MapRenderer._stamp_decor_marks` allowed vault decor on
`T_STAIRS_DOWN` cells, overwriting stairs in the overlay layer — now
stamps on plain `T_FLOOR` only). Floor tiles drawing on top of
monsters (heat-haze z=50 + water-shimmer z=49 were ABOVE actor_layer
z=10 — dropped to z=3 and z=2).

### UI polish + duplication fix

OLED-pure-black palette (every panel BG alpha=1.0), responsive HUD +
outpost (`UILayout` helper, sidebar 320..480 viewport clamp), combat-
log overlay toggle, default Button focus + hover styleboxes. Drag
duplication root cause fixed (snapshot prev_instance_id, treat equip
as no-op only when displaced is empty AND slot's instance_id is
unchanged) + click duplication guard (HUD inv cells carry
`instance_id` meta, verify before equipping).

---

## 2026-06-03

### Authoring portal + items pipeline

`tools/index.html` portal links to atlas viewer + biome editor + item
editor + affix editor with badge states. GitHub Pages workflow stages
a clean `_site/`. Affix / Enchant Editor (`tools/affix_editor.html`)
with sidebar list, form fields, live preview card, auto-default color
per stat. Sanity-check pass via `tools/check_biome_assets.py` caught
18 broken references across 7 biomes.

### Horde density + pack-clustered spawns

Replaced uniform `4 + floor*2` random mob spawns with PoE-style pack
clustering. Floor 1 ~50 mobs, floor 6 ~150. `dungeon.gd::_spawn_packs`
target_total = 40 + floor*20, packs of 6-12 same-id mobs around a
leader. Pack leaders re-roll for modified-tier at elevated rates
(30% T1 → 80% T5). Loot rebalanced — normal drop 15% → 5%, magic
leaders 30%, rare leaders 100%×2. Persistent outlines on
boss/miniboss/rare/magic via extended `threat_outline.gdshader`.

### Enemy variation pass — pack tier system

PoE-style magic/rare on top of champion roll. Per-spawn `visual_scale`
jitter 0.85-1.15× on non-boss enemies (cluster of 6 worker ants no
longer reads as clones). Pack rates scale with branch tier: T1 1.2%
rare / 7% magic, T5 6% rare / 35% magic. Magic = +20% HP / +10% ATK
+ 1 mod + blue tint + small aura; rare = +60% HP / +30% ATK + 2 mods
+ yellow tint + larger pulsing aura + named ("Hasted Vicious
Goblin"). 6 starter mods in `data/monster_mods.json`.

### Shop screen

Reachable via "🏪 Shop" button on Outpost. Two-column layout: your
inventory left, today's stock right. 6 rotating stock items refresh
every 15 real-time minutes. 8 daily modifiers in
`data/shop_modifiers.json` (Weapon Day, Armor Day, Trinket Day, Rare
Collector, Legendary Seeker, Fire Sale, High Demand, Scarcity).
Sell price = 2× salvage × modifier; buy price = 10× salvage ×
modifier. "Sell all common/uncommon" bulk button skips favorites +
starter gear.

---

## 2026-06-02

### Playtest fix cluster

Bot vertical squish over long sessions (was reading `rig.scale`
mid-tween and snapshotting transient pinched Y into
`SpriteFX.base_scale` — fixed by rebuilding rest pose from
`visual_scale` + `_facing_x`). Ring slot UX collapsed to one `ring`
slot + amulet (was ring1 + ring2 + amulet, single-tap couldn't
disambiguate). Weapon rarity tint + glow (`bot.gd::_apply_rarity_decor`
modulates equipped sprite by rarity color, epic+ get pulsing halo).
Source-floor tier caps loot rarity (`_source_tier()` + `_clamp_rarity_to_tier()`
prevent T5 legendaries from pouring into a T1 run via portal entry).

### Tag → mechanic pipeline (13 flavor tags wired)

Attacker (weapon-side): vampiric (8% lifesteal), precision
(anti-streak crit), fire (3-tick burn DoT), holy (+50% vs HOLY_HATES),
dragon_bane (+50% vs DRAGON_HATES), cold (15% freeze chance + 20%
bonus vs frozen), poison (4-tick poison DoT), brutal (+25% vs ≤30%
HP), thunderous (50% chain to one adjacent target). Defender side:
harm (+25% damage dealt and taken), thorns (15% returned), reflective
(10% full negate), vitality (+1 HP regen/sec), rage (+5% atk/kill in
6s window). DoT generalized via `Actor._apply_dot_status()`.
`Actor.take_damage(raw, attacker)` now optionally takes the attacker
so thorns can return damage.

### DCSS-style overlay sprite layers (3)

SHADOW (`scripts/actor_shadow.gd` draws tinted oval beneath every
actor's rig at +10px, z=-1). ENCH (status-effect overlays via
`scripts/status_overlay.gd`, 9 sprite icons + WoW-style buff/debuff
bar at top of HUD with 36×36 square icons + countdown). HALO
(`bot._apply_halo(god)` per-god tinted radial glow at z=-2, soft
1.6s sin pulse, 22 god colors).

### Universal Pause menu

`scripts/pause_menu.gd` — Esc-key opens centered panel anytime during
live play. Resume / Video Settings / Back to Main Menu / Abandon Run
/ Quit Game. Pauses SceneTree while open. Mounted from
`main.gd::_install_pause_menu` after auto-grind/screenshot detection
so headless modes never paint a UI.

### Weapon-swing particle trails + bot-side enchant glow

`weapon_trails.gd` builds GPUParticles2D bursts per flavor (fire
ember sparks, cold frost shards, vampiric blood drips, thunderous
arcs, holy gold motes, poison wisps) and emits on every swing.
`bot.gd::_apply_hand_enchant_ambience` parents a soft radial glow to
the rig at -8x offset (DCSS sprite anatomical weapon hand). Both
slider-tunable via FX Tuner.

### Directional facing

Bot mirrors based on movement direction (`step_movement` flips when
`abs(dir.x) > 0.5`) AND attack target side (`attempt_attack` flips
before swing). DCSS sprites are right-facing default → `_facing_x =
-1.0` flips via `rig.scale.x`.

---

## 2026-05-21

### Visual-effect suite (5 shaders)

Color grading (`color_grade.gdshader` — full-screen LUT-style with
tint/saturation/contrast/brightness/vignette/mix; 8 of 24 biomes
curated initially, all 24 by end of day). Heat haze
(`heat_haze.gdshader` — per-cell sine-wave UV warp on T_LAVA tiles
with vertical falloff and slight chromatic refraction). Water
shimmer (`water_shimmer.gdshader` — per-cell horizontal flow + wobble
on T_WATER tiles, slight blue tint). Memory desaturation (extended
`tile_visibility.gdshader` reads `FogSystem.vis_texture`, tiles in
memory state render with reduced saturation). Threat outline
(`threat_outline.gdshader` — 4-direction neighbor sample around
enemy sprites, tier 0/1/2/3 from hits-to-kill heuristic). Light
cookies (optional `cookie` field on `light_spec.SPECS` overrides
default radial PointLight2D texture, 4 starter cookies authored
programmatically). All toggleable via Video Options menu.

### Playthrough harness

`/playthrough --equip POLICY --upgrade POLICY --advance POLICY`
simulates full game start-to-finish. 3 equip × 3 upgrade × 3 advance
= 27 policy combos. Currently 3 curated combos chained via
`tools/run_playthrough_trio.sh`.

### Experiment infrastructure hardening

`tools/run_experiment.sh` — nohup + double-fork wrapper, survives
parent SIGTERM, writes PID + exit-status files, streams unbuffered
output. Sweep durability — `sweep.py` persists `sweep_partial_variant`
to `index.jsonl` per variant. `balance.run_grind` timeout 60s/run →
90s/run (min 120s).

---

## 2026-05-20

### Items pipeline

234 items shipped across all 7 slots (47 swords / 32 helms / 47 armor
/ 27 shields / 20 boots / 35 rings / 26 amulets). Each item carries
`id`, `name`, `slot`, `rarity`, `tile`, `atk`/`def`/`hp`,
`item_tier`, `base_type` (DCSS-derived), `flavor_tags`, `lore`,
`drop_weights[T1..T5]`, `unique`. 39 uniques across all slots. Base
types sourced from DCSS `item-prop.cc` (armor AC) + `item-prop-enum.h`
(jewellery enum). `tools/item_editor.html` slot-tabbed browser
editor + `tools/sync_items.py` (full or partial sync) +
`tools/items_*_manifest.json` per slot. Drop-weight integration
(`dungeon.gd::_pick_loot_id(rarity)` respects
`drop_weights[branch_tier-1]`; uniques tracked per-run via
`run_dropped_uniques`).

### Balance pipeline

Seedable RNG (`BOTTER_SEED=<int>`); `tools/inject_save.py` (JSON
build spec → debug save, validates ids/tiers/branches);
`[combat]` log tag in `actor.gd`; `tools/parse_grind.py` (shared
dataclass parser). `tools/balance.py` harness. Skills: `/equip`
(shorthand build-spec parser writing to debug save), `/duel` (A/B
two builds across same N seeds, Wilson CI on win rate, paired
stats, damage attribution), `/sweep` (vary one parameter across N
runs, `@legendary`/`@epic_weapon` set tokens, `--affix --tiers`
for stat curve sweeps). 210 grinds across two production
experiments (~165 min wall-clock) producing the first data-driven
balance findings — full writeup in
`docs/balance-findings-2026-05-20.md`.

---

## 2026-05-15

### Gameplay loop overhaul

All 10 beats from `docs/gameplay-loop-plan.md` plus several extras:

- **Beat 1** — Affix simplification (collapsed to 6 affixes:
  Strength/Stamina/Agility/Regen/Crit/Haste; old 30-affix system gone)
- **Beat 2** — Branch tier data (`biomes.json` tagged tier 1-5 +
  `cr_recommended`; FLOORS_PER_RUN 10→6, MINIBOSS_FLOORS [3],
  TIER_SCALE [1.0, 1.4, 2.0, 3.2, 5.0])
- **Beat 3** — Save state expansion (unlocked_branches, bosses_killed,
  max_revives, loot_filter, inventory_cap, last_branch,
  branch_modifiers, bot_upgrades, shards, last_seen_timestamp)
- **Beat 4** — Branch-aware run plan (BiomeData.roll_run_plan accepts
  branch_id + floors; runtime tier scaling; branch boss = strongest
  pool member; boss_killed signal)
- **Beat 5** — Death retreat with revives stat (since-removed in the
  2026-06-05 balance pass; field kept for save-compat)
- **Beat 6** — Gear bloat (loot_filter + inventory_cap + auto-salvage,
  Outpost UI surfaced)
- **Beat 7** — Bot upgrades (`data/bot_upgrades.json` with 6
  upgrades, Outpost upgrades panel, stats fold into recompute_stats)
- **Beat 8** — Branch picker UI (Outpost tier-grouped picker, locked
  branches dimmed, modifier strip per branch)
- **Beat 9** — Offline progress (`OfflineProgress.apply` on launch,
  "While You Were Away" AcceptDialog) — later removed 2026-06-06 as
  the single biggest power-injection vector
- **Beat 10** — Run report unlock prominence (slow-pulsing gold
  banner under run-report title; shipped 2026-06-04)

Bonus beats: smooth shader-driven fog of war, shared paperdoll
renderer, per-deploy run modifiers (8 modifiers), stricter unlock
progression (clear every tier-N boss to open tier-(N+1)), per-tier
rarity baseline in `_roll_rarity`, UI consistency pass,
stuck-detection rewrite (frame-counts → delta-time).

### Combat pass

Affix collapse to 6 wired stats. Real paper-doll
(`paperdoll_renderer.gd` builds layered Sprite2D rig from equipped
weapon/armor/helm/shield/boots, used in-game and on every UI surface).

### HP scaling root-cause

`Bot.gain_xp` was setting `hp = max_hp` on every level-up, fully
healing the bot every level. Fix: level-up grants only the +8 max_hp
slice (`hp = mini(max_hp, hp + 8)`), no full heal. Combined with
save-state isolation (debug save for grind, untouched live save), the
dungeon now correctly tests as hard.

---

## 2026-05-13 → 2026-05-21

### Variety pass (1.5)

9 sub-stages mostly shipped: smart tile placement (uniform walls,
voronoi floor patches, strict prefix matching); edge overlays (grass
/ dirt / slime / shoreline directional autotile); fog + light (bot
lantern, world Light2Ds, per-cell visibility state machine,
WorldEnvironment with bloom); walls (`wall_alternates` system,
per-biome cluster themes); decor scatter (`AmbientDecor` system);
monster expansion (10 → ~177 unique monsters per atlas); artefact
items (legendaries pull from `item/weapon/artefact/`); sigils +
multi-tile decor; special features (`L`/`l` lava 5%/0.5s damage,
`W`/`w` water 50% move speed, `I` ice visual-only); floor pass
(per-cell hashed weighted variant pick, Lair dual-floor mix via
Perlin noise); door tiles (`+` glyph renders as closed/runed/sealed
per biome); combat effects (Effects helper class with biome-themed
kill flashes); DCSS-style UI (landscape 1280×720, right sidebar with
minimap+stats+log, bottom-left bag, top-left debug HUD).

### Perf pass (2 stages)

Pass 1 (2026-05-13) CPU-side at 1600×900 windowed. Pass 2
(2026-05-14) GPU + hitch at native Retina. Result: **fps min on
forge 19 → 119, gen p95 1290ms → 18ms**. See HANDOVER for full
breakdown.

---

## DCSS-port — phase status

### Phase A — algorithms ported

`dgn_build_basic_level` → `DCSSLayouts.basic_level` (trail + rooms).
`delve()` cave generator → `DCSSLayouts.delve` (with `caves`,
`caves_tight`, `caves_open` parameter presets).

### Phase B — data tables

`items.json` — 234 items across 7 slots with DCSS-derived base types
(2026-05-20).

### Phase C — bot AI + idle loop (the actual game)

Run-config with branch picker + per-deploy modifier rolls. Idle
reward curves with offline progress (since-removed 2026-06-06).
Visual presentation (smooth fog, paperdoll, rarity decor, segmented
inventory). Configurable bot priorities partly shipped (proximity-
ranked behavior, aggro range cap, current-room loot priority,
low-HP retreat).

---

## Tooling — infrastructure

### Permission allowlist

`.claude/settings.json` allows common patterns: read-only git,
python3, bash skills, find/grep/sed/awk/jq, file ops. Destructive
ops (rm, git push, git reset --hard, gh) stay behind `ask`.

### Save-state isolation

`SaveState.debug_mode = true` when AUTO_GRIND or DEBUG_FLOOR markers
are present, routing IO to `user://botter_save_debug.json`. Live
save untouched by benchmark/screenshot runs.

### class_name refresh wrapper

`tools/refresh_class_cache.sh` wraps `godot --headless --import` and
reports class count. Both `/screenshot` and `/grind` skills auto-detect
"Parse Error: ... not declared" and re-run with refresh.

### Skills

`/screenshot <biome> [vault] [floor]`, `/grind <runs> [speed]`,
`/benchmark <duration_s> [speed] [label] [headless|windowed]`,
`/showcase` (visual audit floor with one station per feature).
