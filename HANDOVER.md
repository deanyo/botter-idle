# Botter — Handover

Point-in-time snapshot of what's actually shipping. Updated as we go. The
durable rules and process live in `CLAUDE.md`; the roadmap and open work
items live in `TODO.md`.

Last refresh: 2026-06-09 (Tier 2 attribution shipped — final session
of the Botter audit. Vault filenames stripped of DCSS contributor
handles, LICENSE / NOTICE.md / CREDITS.md added at repo root, in-game
Credits screen wired into main menu, README + .gitignore refreshed,
export_presets.cfg tracked + vault exclude_filter asserted at
deploy time. **The Botter multi-agent audit is CLOSED** — no NEXT
tier; future work is open-ended).

`project/data/vaults/` now uses opaque per-theme IDs
(`vault_<theme>_NNNN.json`) instead of `des_<author>_*.json`. The
1320 ported vaults bucket across 14 themes (lair 166 / swamp 133 /
zot 127 / shoals 117 / snake 116 / elf 113 / crypt 106 / abyss 99 /
mines 89 / spider 88 / vaults 83 / slime 39 / tomb 35 / depths 9).
Each vault's `_original_dcss_id` field preserves the source
filename, and `project/data/vault_id_map.json` records the full
mapping (old_filename → new_filename / new_name / original_name /
primary_theme) for traceability. `tools/strip_vault_handles.py` is
the one-shot rename script; idempotent, --dry-run flag, deterministic
sort key, never re-runs against already-renamed files.

`LICENSE` declares "All Rights Reserved" mirroring the README's
existing public-preview framing — durable posture pre-launch, not a
transitional stub. `NOTICE.md` enumerates third-party attribution:
the full DCSS / RLTiles tile-pack contributor list (~50 names) with
the original RLTiles attribution language, 49 verified DCSS .des
vault contributor handles cross-referenced from the audit trail
(covering 1219 of 1320 ported vaults; ~100 unattributed credited
collectively to the DCSS community), Godot Engine MIT, and GUT MIT.
`CREDITS.md` carries dev credit + Claude Code AI-assist
acknowledgment + inspiration list + bundled-content roster.

In-game **Credits** screen (`project/scripts/credits.gd`) follows
the existing script-only screen pattern — paints itself in `_ready`,
two RichTextLabel panels rendering CREDITS.md / NOTICE.md side-by-
side, header back-button. Reachable from main menu →
"Credits" between "Item Generator" and "Reset Save".
`project/data/credits.txt` and `project/data/notice.txt` are the
shipped copies the screen reads via `res://data/`; repo-root .md
remains authoritative. `tools/sync_credits.py --check` is wired into
`tools/check_before_commit.sh` step 2/5 so attribution edits that
miss the project copy fail pre-commit instead of silently lagging.

`project/export_presets.cfg` now tracked (was gitignored). Carries
the load-bearing
`exclude_filter="data/vaults/*.json,data/vaults_bundle.json"` line
that keeps GPL-derived vault content out of the web .pck.
`tools/deploy_web.sh` adds a pre-export grep gate that aborts the
deploy with a NOTICE.md / CLAUDE.md pointer if either filter goes
missing — defense in depth against fresh-checkout / regenerated-
preset regressions.

`README.md` License section now points at `LICENSE`, `NOTICE.md`,
`CREDITS.md`, and the in-game Credits screen — the dcss_layouts.gd
clean-room "pending" sentence removed (that work shipped 2026-06-08
in commit `a2674e5`). `.gitignore:5-8` refreshed to point at
NOTICE.md as the canonical attribution record.

Validation: GUT 132/132 pass. `tools/check_before_commit.sh` 5/5
pass with the new credits-sync gate. Mortal T1 3-run grind
post-rename: 0 errors / 0 stalls, vault stamps confirmed in
`[gen]` log lines (`vaults=["vault_crypt_0093"]` etc).

**Botter audit retrospective.** Started 2026-06-08 with 100 verified
findings across 8 categories from a multi-agent audit. Ten Tier 0–3
sessions shipped sequentially over two days:
  - Tier 0 — legal hygiene fires (vault bundle out of .pck, Pages
    allowlist, README honesty, manifest scrub).
  - Tier 1 — save/progression bugs (chest-loot-loss, octopode/naga
    ring2 wipe, unspent_points key); StatCalc residue (15 dead
    altars + species stats); combat correctness (avoidance roll,
    spell element piping, spell-item damage scaling); UI cleanup.
  - Tier 2 — clean-room dcss_layouts.gd rewrite, GUT test
    foundation, save durability (atomic write, schema migrations,
    orphan validation, web pagehide flush).
  - Tier 3 — dungeon.gd god-class split: LootFactory,
    HUDInventoryController, DebugDump, RunState, WaveSpawner,
    ShowcaseRunner. dungeon.gd 4492 → 3064 LOC (-32%); the
    remainder is the irreducible orchestrator.
  - Tier 2 attribution (this session) — pre-public-launch hygiene
    cap: vault handle strip, LICENSE/NOTICE/CREDITS, in-game
    Credits screen, export-preset tracking + deploy guard.
GUT 0 → 132 tests, ~933 → ~2745 asserts. The audit is closed;
remaining open work in TODO.md is balance / UI / dev-tool follow-
ups, not audit findings.

---

2026-06-12 (balance pass beat 1.F — 73 recolor_of items triaged:
20 promoted, 42 culled, cluster 1.F closed). A1-recolor-016 root-
caused: 73 recolor_of items inflated the loot pool by ~11% without
adding mechanical depth — only 7 (vampires_tooth + folly + cloud
recolors) carried `implicit_affixes`. The other 66 were pure
cosmetic variants inheriting the parent's `affix_pool`. Shipped a
two-track triage: (1) **20 legendary recolors promoted** with 2
name-driven implicits each, keyed off the flavor suffix from
`item_generator.gd` flavor table — frostbound/azure→cold (of_frost,
of_finesse / of_cryomancer + of_cold_resist), ironclad→armor or
lightning (of_might + of_executioner / of_wisdom +
of_lightning_resist), jadeforged→poison (of_envenom +
of_poison_resist), sunsteel/rosegold→holy (of_zealot +
of_holy_resist), mossy→poison (of_venom + of_finesse),
obsidian/shadowed/spectral→dark (of_shadow + of_dark_resist /
of_dark_resist + of_phylactery), prismatic→multi-stat. All
slot-eligible per `affixes.json::applies_to`. (2) **42
epic/rare/uncommon recolors culled** by setting
`drop_weights=[0,0,0,0,0]` — out of loot pool, schema preserved so
existing save references don't crash. Final recolor pool: 73 total
= 42 culled + 31 in-pool (27 with implicits including 7 pre-
existing + 4 prior 1.F demoted prismatics). /duel verified
implicits compose: `runed_scimitar_frostbound` vs parent in glacier
+12.3% from of_frost+of_finesse; `firestarter_ironclad` vs parent
in lair +28.5% from of_might+of_executioner. **1.F cluster fully
closed (5 of 5 sub-items shipped over 4 sessions today and
yesterday — `requires_innate_tag` on starters,
`strip_audit_residue.py`, T1 legendary recolor demote, 2H
epic→legendary promotes, this recolor promote/cull).**

---

2026-06-12 (balance pass beat 1.F — 5 2H epic weapons promoted to
legendary + manifest backlog catch-up). A1-2H-collapse-021 root-
caused: pre-pass, 2H legendary count was 3 (warlord_battle_axe,
doomed_executioner, sigmunds_sickle T1 anchor) vs 28 1H legendaries.
With cluster 1.D differentiating the 1H legendaries, the 2H slot was
the visibly thinnest legendary lane in the pool — players running 2H
builds hit the same 2-3 legendaries every endgame run. Shipped 5
promotions: `triple_sword` (physical, of_sharpness + of_executioner),
`executioner_axe` (physical, of_executioner + of_bloodletting),
`reapers_scythe` (dark, of_shadows + of_bloodletting),
`blessed_claymore` (holy, of_devotion + of_might), `glacial_bardiche`
(cold, of_frost + of_finesse — was the 1.E new T4 epic). Element
coverage in the 2H legendary slot now spans physical / dark / holy /
cold (was 100% physical). 2H legendary count 3 → 8. No statline
changes — all 5 already sat under A10 R1's `damage_max ≤ 220` cap, so
promotion is rarity epic→legendary + item_tier 4→5 + drop_weights
normalized to `[0,0,0,15,40]` + 2 implicit_affixes per item for
identity. /duel sidegrade verified across multiple biomes:
triple_sword vs warlord_battle_axe in forge (both physical) +6.7%;
reapers_scythe vs warlord in lair (dark flexes vs beasts) +25.8%, in
crypt (undead dark-resist) -29%; blessed_claymore vs warlord in crypt
+21.8%. First reapers iteration with `of_lifesteal` ran away in lair
(+520% — survival multiplier was the issue, not flat damage); swap to
`of_bloodletting` keeps dark/death flavor in budget. Same session
flushed pre-existing manifest backlog: `_balance_bumps` etc residue
from earlier 1.F strip + 1.D body-armor implicits propagated via
`sync_manifests_from_items_json.py`; bundled into the same commit
since both are 1.F cluster cleanup.

---

2026-06-11 (balance pass beat 1.E cold/poison element coverage — 8
new weapons + chilly_death flagship rebalance). A1-coverage-005 root-
caused: pre-pass the 150-weapon pool had exactly 1 cold weapon
(`chilly_death` T5 legendary) and 1 poison weapon (`serpent_scourge` T5
legendary). Bots committing to a cold/poison physical-weapon archetype
had nothing at any earlier tier and a single legendary at endgame.
Shipped 4 cold weapons across the tier ladder (`frost_dagger` T2 unc,
`frostgrim` T3 rare battle_axe, `glacial_bardiche` T4 epic bardiche
with `of_frost` implicit, `rime_spear` T5 epic spear with `of_frost`
implicit) and 4 poison weapons (`viper_fang` T2 unc dagger,
`venomtongue` T3 rare dagger, `viper_lance` T4 epic spear with
`of_venom` implicit, `scourgevine` T5 epic whip with `of_venom`
implicit). Statlines anchored on existing tier templates (frostgrim
mirrors steel_battle_axe T3 rare 60-103/spd 1.1; viper_lance mirrors
steel-spear T3 → mithril_longsword T4 epic shape 45-82/spd 0.7).
Affix pools strictly slot-eligible per affixes.json applies_to —
`of_frost`/`of_venom` (flat-extra) carry the elemental flavor on
weapons; `of_envenom`/`of_zealot` (pct, amulet/ring/helm/etc only)
deliberately kept off weapons. Plus deferred-from-1.D `chilly_death`
rebalance: damage 48-107 → 60-119, mirroring serpent_scourge/wyrmbane
single-element-flagship template per A1 finding 4. Items pool
697 → 705. Validation: check_damage_ceiling clean (158/158 weapons
within 220/245 cap), audit_data_integrity 6 pre-existing thin-cell
warnings only, check_before_commit 5/5 PASS, /grind 5 zero errors,
runtime probe confirms all 9 items load through ItemsDb and roll
affixes via AffixSystem, /duel chilly_death vs wyrmbane (both now
60-119) shows asymmetric biome matchup correctly (cold neutral vs
holy-resistant lair fauna).

---

2026-06-11 (balance pass beat 1.E partial — 5 thin-cell fills + 5
race-anchor uniques, 10 new items.json entries). A4 §A thin-cell
proposals shipped to fill the 5-cell skinny-pool gap (gloves common,
gloves uncommon, cloak common, shield common, amulet common): `iron_token`
(STR-flagged common amulet), `student_mantle` (INT-flagged common cloak),
`padded_targe` (mixed-stat common buckler with block_chance/amount),
`silk_handwraps` (DEX-coded common gloves), `acolyte_handwraps` (INT-coded
uncommon gloves). Items pool 687 → 697. A4 §B race-anchor proposals
shipped for the 5 species under-anchored after S5: `demonspawn_pyre_mantle`
(legendary cloak, fire+demon, biome_pool=["forge","pandemonium"]),
`gargoyle_basalt_visor` (epic helm, stone — fills the gargoyle head-slot
gap), `elf_archmagi_focus` (legendary amulet, scholar, biome_pool=["elf"]),
`tengu_galewing_pendant` (epic amulet, windborn — non-cloak speed delivery),
`halfling_lucky_treads` (rare boots, lucky — fills boots-rare cell + delivers
loot identity via `of_plunder` implicit). Per-affix slot eligibility
strictly respected in pools; off-slot implicits used where existing precedent
exists (e.g. `vampire_nightshade_cloak` carries cloak-illegal `of_lifesteal`
as implicit). Race-anchors 24 species → 5 species gain a second anchor.
Validation: items.json parses, 697 items, all 10 load through ItemsDb
preload + roll affixes correctly via AffixSystem, check_damage_ceiling
clean (150 weapons within 220/245 cap), audit_data_integrity 6 pre-existing
THIN_DESIGNS warnings only (all in cells A4 left for follow-up batches),
check_before_commit 5/5 PASS, /grind 5 zero ERROR / push_error / parse
warnings.

---

2026-06-11 (balance pass beat 1.K — lightning resistance spread,
1→9 enemies). Synthesis Top-5 finding 1.5 root-caused: pre-pass,
1 of 125 enemies (`blue_devil`) had any lightning resistance and
zero were lightning-vulnerable, leaving lightning the only
structurally pure-positive element with no biome leverage. Now 9
of 125 (7.2%, lower bound of A5's 10% target) carry a `lightning`
key in their `resistances` dict: 5 T4-T5 construct/armored/warded
entries at +50 (`iron_dragon`, `stone_giant`, `quicksilver_dragon`,
`vampire_knight`, `ancient_lich`) which cluster in
zot/depths/vaults/abyss/labyrinth, and 3 swamp/snake aquatic
entries at -25 (`water_moccasin`, `hydra`, `swamp_dragon`).
Composition path is unchanged — `actor.gd:474-477` already reads
`resistances[damage_type]` element-agnostically and folds it into
`elem_mit` exactly like fire/cold/holy/poison/dark; runtime probe
confirmed +50 halves a 100-dmg lightning hit and -25 amps it to
125. The result: chain_lightning / spell_static_field / echo_lance
/ stormcaller_totem / `of_storm` and `of_storms_pct` lightning
builds now have biome shape — neutral in lair/forest, walled in
zot endgame, vulnerable in swamp. Symmetric to fire-vulnerable
slime jellies and holy-vulnerable crypt undead.

---

2026-06-11 (balance pass beat 1.G curve fixes — 5 affix tier
flatlines + gold_drop_pct hard clamp). Five affix curves
re-tuned per A2 audit: `of_berserker` `[[3,5],[5,8],[8,12],[12,16],[16,20]]`
(was T4=T5=20 flatline), `of_sundering`
`[[2,3],[4,5],[5,7],[7,9],[9,12]]` (was T4=T5=10 flatline),
`of_multicast` `[[1,1],[1,2],[2,2],[2,3],[2,4]]` (was T1=T2=T3=1
identical; preserves the PLAYTEST 2026-06-09 #9 +0-rule by flooring
every tier at 1), `of_regen` `[[1,1],[1,2],[2,3],[3,5],[5,7]]` (was
T4-T5 capped at 4-6), `of_vitality` T5 max 160→130 per A10 cap (a
6-slot legendary stack now resolves to ~390 HP from rolls instead
of ~480, restoring ceiling headroom against `of_might`-driven STR
HP-mults). Plus a hard clamp of `gold_drop_pct` at 50 in
`stat_calc.gd::compute` post-summation — `of_plunder` and
`of_prospecting` both write the same stat key but per-affix-id DR
keys by id, so a plunder T5 amulet + prospecting amulet + prospecting
weapon stack would otherwise reach 65%+ with no ceiling. Clamp
verified at runtime via direct probe. /sweep loaded all 5 of_berserker
tiers cleanly on the new curve. Cluster 1.G items 5-10 ship; items
1-3 (id-collision renames) remain open pending a v9→v10 save
migration scaffold.

---

2026-06-11 (balance pass beat 1.D — 31 legendary clones gain
identity via `implicit_affixes`). The audit's A1 stat-clone
findings (5 demon_blade variants at dmg=122-215/spd=0.9, 9 long_sword
variants at dmg=71-131/spd=0.7, 13 body armors at armor=48/ev=12,
4 vampires_tooth/dagger variants at dmg=48-107/spd=0.55) — all
sharing affix_pool keys before this beat — now carry per-name
`implicit_affixes` arrays. Implicits flow through
`stat_calc.gd::_realize_implicit` and the per-affix-id DR pipeline,
so the differentiation registers as real combat numbers. Spot-check:
`/duel demon_blade -- demon_blade_umbral` shows +8% damage-output
gap purely from implicit choice. `/duel eos -- jihad` (lair) shows
-17% damage gap from element + implicit interaction. Picks favored
weapon/armor-applies_to affixes by flavor (e.g. `arc_blade` got
`of_storms` since it's the only lightning long_sword; `armor_of_zhor`
got `of_regen + of_vitality` matching its lore; `chilly_death` got
`of_frost + of_finesse` as cold-rapier identity). Every legendary
in these 4 clusters now has a distinct on-equip mechanical signature
that the outpost search field (1.A) can isolate by typing the
implicit affix name.

---

2026-06-11 (balance pass beat 1.C remainder — `elf_spire_tome`
schema repair + `green_dragon_inverse` re-tier + 3 quarterstaff
1H retags shipped). `elf_spire_tome` (the only one of 224 spell
items missing damage fields — would null-deref on cast) gained
`primary_stat=int / damage_min=20 / damage_max=35 / damage_type=
dark / spell_cooldown=14.0` per A1 finding 11. `green_dragon_inverse`
demoted from `legendary` → `epic` to match its armor=30/ev=7
statline (legendary median is 48/12) per A1 finding 9. The three
quarterstaff-base items (`quarterstaff` common, `metal_staff`
uncommon, `metal_staff_nightblue` uncommon) were all at speed=0.8
but tagged `weapon_class=2H`, which made them 8-12 std devs faster
than the 2H median — retagged to `1H` per A1 finding 6.
`sigmunds_sickle` (T1 boss anchor, 2H spd=0.7) intentionally
preserved. Beat 1.C is now complete. Validation: items.json parses
clean (687 items), `tools/check_damage_ceiling.py` exits 0 (150/150
weapons), `tools/audit_data_integrity.py` no new warnings, /grind 5
zero ERROR / push_error / parse warnings on the affected items.

---

2026-06-11 (balance pass beat 1.B + first 1.C ceiling fixes —
weapon damage-ceiling tripwire + 2H legendary nerfs shipped).
`tools/check_damage_ceiling.py` walks `project/data/items.json`
and asserts `damage_max <= 220` and raw DPS (`damage_max / speed`)
`<= 245` across every weapon. Caps come from balance-pass
2026-06-11 §A10 R1 — the 220 figure is the explicit "cap to ship"
for 2H legendaries; the 245 DPS guard mirrors the existing 1H
legendary ceiling (demon_blade at 239 raw DPS). Wired into
`tools/check_before_commit.sh` after `audit_data_integrity.py` so
a future content pass that re-introduces the doomed_executioner /
warlord_battle_axe shape (305 / 298 dmax → ~3× the 400-peak hit
target after blessing+crit stacks) fails pre-commit.
`doomed_executioner.damage_max` 305→220 (damage_min 175→126);
`warlord_battle_axe.damage_max` 298→220 (damage_min 167→123) —
both 2H legendaries now sidegrade `triple_sword` (epic 2H, dmax
209). Validation: the tripwire trips on a throwaway dmax=250
edit, restores green after revert. /duel doomed_executioner vs
triple_sword (10 seeds, level=30 forge): total damage dealt
10724 vs 10091 — 6.3% delta, sidegrade as A10 specified. Pre-
nerf the gap was ~50%.

---

2026-06-11 (balance pass beat 1.A — outpost filter-by-affix +
sort-by-ilvl shipped). The outpost inventory chip row gained a
`Search affix or name` LineEdit and an `Item level (high → low)`
sort entry. Substring search (case-insensitive) matches against
the item base name, every implicit affix id and display name, and
every rolled affix id and display name on the instance — so typing
`crit` filters to anything carrying a crit affix, and typing the
name of a boss-anchor implicit (e.g. `phylactery`) finds the one
unique that rolls it without scrolling 30+ epics. The ilvl sort
uses `ItemLevel.compute(item, inst).level` with rarity then name
as tiebreakers. Both ride on top of the existing slot/rarity/
favorites filters; empty query short-circuits so default behavior
is unchanged. Implementation in `project/scripts/outpost.gd:1095`
(state field), `:1113-1119` (sort options), `:1172-1183` (LineEdit
chip), `:1200-1230` (`_passes_filter` + new
`_matches_affix_query`), `:1318-1330` (ilvl branch in
`_render_inventory` sort match). Gating tool for the rest of the
balance pass — every Beat-1 affix add and unique-differentiation
batch becomes searchable in-hand.

---

Earlier 2026-06-09 (Tier 3 dungeon.gd split — sixth and final
extraction shipped: ShowcaseRunner pulled out of the 3179-LOC
dungeon. **The dungeon.gd Tier 3 split is COMPLETE** — what remains
is the irreducible orchestrator).

`project/scripts/showcase_runner.gd` is a RefCounted helper the
dungeon owns as the `show` field. It carries the showcase-mode
integration glue: the `patrol` + `patrol_idx` runtime bookkeeping,
plus `is_active()` (wraps `DebugJump.showcase`), `build_floor_data()`
(curated 80×80 floor + patrol seed + spawn cell), `spawn_stations()`
(walks `Showcase.STATIONS` and dispatches into the dungeon's spawn
helpers — actor_layer / interactables / ambient_decor_nodes / loot
factory / chest / fountain / portal / specific-enemy), and
`tick_patrol(delta)` (advances the bot one cell along the loop,
wraps at the end). The static visual-audit content (STATIONS roster,
patrol_path, build_grid, lava/water/ice stamping) stays in
`scripts/showcase.gd` where it lives as data — only the runtime
bookkeeping + integration callbacks moved.

`dungeon.gd` shrank 3179 → 3064 (-115 lines). The seven `if
DebugJump.showcase: ...` integration branches in `_async_build_floor`
(3 sites — floor data, station spawn, enemy-spawn skip), `_tick_bot`
(descend gate + patrol tick), `_check_stuck`, and `_tick_enemies`
collapse to `if show.is_active(): ...` calls with one-liner forwarders.
The five showcase functions on the dungeon (~125 lines) and the two
patrol fields are gone. Run-init constructs the runner lazily next
to the WaveSpawner so the bound dungeon ref is stable for the run.

Test foundation extended: `test_showcase_runner.gd` 6 tests / 21
asserts covering `is_active()` reading through to `DebugJump.showcase`,
`build_floor_data()` resetting `patrol_idx` + returning the dict
shape downstream code reads by name (`grid` / `rooms` / `spawn` /
`stairs_down` / `dist_to_stairs` / `vault_results`) + the spawn cell
matching `patrol[0]`, `tick_patrol` empty-patrol no-op, mid-path
step (no idx advance), arrival advancing idx + requesting a path +
setting `bot_target_kind`, and loop-end wrap. Visual-audit content
(STATIONS roster, patrol_path) intentionally NOT pinned — locking
it would discourage adding new stations. New
`_stub_showcase_dungeon.gd` records spawn-helper calls + stubs
`bot.path` / `bot.set_path` / `pathing.path` so the runner's patrol
math is testable without a real grid. GUT 126 → 132 tests,
2724 → 2745 asserts. Suite still ~3.4s headless.

Validation: GUT 132/132 pass post-extraction.
`tools/check_before_commit.sh` all 5 steps pass. Manual mortal T1
3-run grind: floors 2/1/2, 85+0+136 kills, 0 errors / 0 stalls /
0 script errors, no `[showcase]` log lines (confirms the showcase
glue doesn't fire in normal play). Headless `/showcase` smoke
before AND after the extraction shows identical shape — same
`[debug-jump] showcase mode` boot, same `[render] biome=dungeon
floor_tiles=12 wall_tiles=8`, same `[build-floor] enemies=4` (4 of
5 enemy stations spawn — `firefly` is missing from
`data/enemies.json`, a pre-existing data gap unrelated to this
extraction). The pre-existing `floor_started callable unbinds 8
arguments` chrome-signal error reproduces on both baseline and
post-extraction smokes — also not from this change.

**Tier 3 dungeon.gd split: COMPLETE.** The remaining 3064 LOC is
the irreducible orchestrator — node graph build/teardown,
`_process` driver, signal emit/connect glue, thin forwarders into
the helpers (`LootFactory`, `HUDInventoryController`, `DebugDump`,
`RunState`, `WaveSpawner`, `ShowcaseRunner`). Future Tier 3
candidates (drop_tuning.json, biome data, etc) should be triaged
before the next session opens.

---

Earlier 2026-06-09 (Tier 3 dungeon.gd split — fifth extraction
shipped: WaveSpawner pulled out of the 3314-LOC dungeon).

`project/scripts/wave_spawner.gd` is a RefCounted helper the dungeon
owns as the `wave` field. It carries the VS-style density layer:
`wave_accum`, `wave_interval`, `burst_accum`, `burst_interval`, and
the `pending_wave_spawns` queue, plus the WAVE_MIN/MAX_MOBS,
BURST_MIN/MAX_MOBS, DENSITY_HARD_CAP constants. Methods that mutate
it: `begin_floor(rng)` (reset accumulators + jitter the next-fire
intervals into 6-10s / 30-50s bands), `tick_wave(delta)` (top-up
spawns when alive < ~70% of target density), `tick_burst(delta)`
(every 30-50s, spawn a 12-18 mob MAGIC pack with leader spawned
immediately and packmates queued), `drain_one()` (pop one ID per
frame and call back into dungeon to spawn it), and `warp_in_last_spawn()`
(the alpha+scale tween on the most-recently-spawned enemy). Behavior
is a strict copy — no tuning rides the extraction. Callbacks into
the dungeon: `_floor_ready` / `bot` / `rng` / `current_floor` /
`current_biome` / `enemies` reads, `_random_walkable_cell_far_from_bot`
and `_spawn_specific` calls.

`dungeon.gd` shrank 3314 → 3179 (-135 lines). The per-frame `_process`
driver replaces the three bare calls (`_tick_wave_spawns(delta)`,
`_tick_burst_events(delta)`, `_drain_pending_spawns()`) with three
forwarders into `wave`. The accumulator-reset block at the bottom of
`_async_build_floor` collapsed to a single `wave.begin_floor(rng)`.
`_warp_in_last_spawn` and `_build_enemy_pool` moved with WaveSpawner
since the wave/burst/drain paths were their only callers.

Test foundation extended: `test_wave_spawner.gd` 13 tests / 50
asserts covering begin_floor reset + interval jitter into the
expected bands, tick_wave gating (sub-interval no-op, fire +
re-jitter, target-density gate, DENSITY_HARD_CAP gate, _floor_ready
gate, bot-dead gate, queue-cap-at-remaining-target), tick_burst
gating + leader spawn at PACK_MAGIC tier + packmate-queue id parity,
and drain_one FIFO + empty-queue no-op. New `_stub_dungeon.gd`
records `_spawn_specific` calls without instantiating a real grid /
node graph, so the spawner's accumulator + queue math is testable
in isolation. GUT 113 → 126 tests, 2674 → 2724 asserts. Suite still
~3.4s headless.

Validation: GUT 126/126 pass post-extraction.
`tools/check_before_commit.sh` all 5 steps pass. Manual mortal T1
3-run grind: floors 3/2/2, 179+58+152 kills, 1 hive portal entered,
0 errors / 0 stalls / 0 script errors. 4 `[burst]` log lines fired
across the 3 runs (matching the pre-extraction baseline of 4 in the
same configuration). drain_spawn perf-context stamps still arriving
as expected.

Next dungeon.gd extraction: Showcase (dead-code move — the curated
visual-audit floor builder). After that the dungeon split per
`AUDIT_TODO.md` Tier 3 is complete.

---

Earlier 2026-06-09 (Tier 3 dungeon.gd split — fourth extraction
shipped: RunState pulled out of the 3413-LOC dungeon).

`project/scripts/run_state.gd` is a RefCounted helper the dungeon owns
as the `run` field. It carries the run + floor lifecycle state:
`current_floor`, `branch_id`, `run_plan`, every `floor_*` per-floor
counter, every `run_*` per-run accumulator, the four `portal_*` overlay
fields, the boss-floor lethality snapshot (`boss_floor_entry_hp/_ms/
_branch`, `boss_initial_hp`), the `kills` tally, `dropped_items`,
`loot_log`, `journal`, `active_modifiers`, `floors_per_run`,
`boss_floor`, `revives_remaining`, `retreats_this_run`, `run_turn` +
the per-frame `_turn_accum`, `run_vaults_stamped`, `run_biomes_visited`,
`run_dropped_uniques`, `floor_placed_vaults`, `floor_starting_hp`,
`floor_start_tick`. The methods that mutate it: `init_run`,
`_resolve_active_modifiers` (private), `begin_floor`,
`record_floor_vaults`, every `note_*` per-event helper, `enter_portal`/
`exit_portal`, `record_descend_summary`, `advance_to_next_floor`,
`is_final_boss_floor`/`is_miniboss_floor`, `capture_boss_floor_entry`,
`tick_run_turn`, `journal_floor_entry`/`journal_event`,
`note_dropped_unique`/`is_unique_dropped`, `try_death_retreat`,
`flush_to_save(bot, inv)`, `end_run(victory, bot, inv, items_db)`.
Behavior is a strict copy — no tuning rides the extraction.

`dungeon.gd` shrank 3413 → 3314 (-99 lines). Smaller drop than the
prior extractions because the external API surface is wide:
`current_floor`, `run_plan`, all `floor_*` and `run_*` counters,
`portal_active`, `journal`, `kills`, `dropped_items`, `active_modifiers`,
etc. are read by name from main.gd / chrome / debug_dump / outpost,
so the dungeon keeps property forwarders (~150 lines) that get/set
through the helper. The win is that the LOC moved out is more
load-bearing than the count suggests: every state mutation now goes
through a method on RunState, not a scatter of `+= 1` writes across
3700 lines.

External API preserved by name:
* `dungeon.flush_to_save()` — main.gd's pause-to-main-menu, web pagehide
  hook, and `_notification(WM_CLOSE_REQUEST)` all call this. Body is
  now `run.flush_to_save(bot, inv)`.
* `dungeon._end_run(victory)` — pause-menu Abandon-Run + every internal
  victory/defeat path. Body is `run.end_run(victory, bot, inv, items_db)`,
  spell-system summary log, `run_ended.emit(victory, report)`.
* `dungeon._try_death_retreat(reason)` — bookkeeping (counter decrements,
  log line, current_floor reset to 1) lives on RunState; the bot revive
  (HP reset, tween kill, rig transform, bot.is_alive flip) stays on
  dungeon because it touches the bot's tween + rig.
* `dungeon.run_kills` etc — main.gd's `_on_run_ended` reads the per-run
  accumulators by name through the dungeon node. Property forwarders
  preserve those reads.

Test foundation extended: `test_run_state.gd` 22 tests / 75 asserts.
Covers init_run resetting every per-run counter + rolling the run
plan + consuming the branch_modifiers entry, every `note_*` per-event
helper, begin_floor isolating per-floor vs run-wide state,
record_floor_vaults dedup against the run set, portal enter/exit
state lifecycle, is_final_boss_floor probe, capture_boss_floor_entry
stamping all three fields, record_descend_summary aggregating into
run-wide totals + biome list + run_done flip at floor cap,
try_death_retreat returning false at zero revives + decrementing +
floor reset when allowed, tick_run_turn 0.25s cadence, journal entry
+ event-append guard, unique-drop tracking. GUT 91 → 113 tests,
2599 → 2674 asserts. Suite still ~3.3s headless.

Validation: GUT 113/113 pass post-extraction.
`tools/check_before_commit.sh` all 5 steps pass. Manual mortal T1
3-run grind: 248 kills, 24 loot pickups, 0 errors, 0 stalls, 0 script
errors. Run report fields (kills, loot, gold, level, floor) match
pre-extraction shape. Save-state shape unchanged across both
flush_to_save (mid-run menu exit) and end_run (victory + defeat)
paths.

Next dungeon.gd extraction: WaveSpawner (combat-shaped — pull the
wave/burst tick, _pending_wave_spawns queue, _drain_pending_spawns,
_warp_in_last_spawn). After that: Showcase (dead-code move). Each
session shrinks dungeon.gd and doesn't touch anything else.

---

Earlier 2026-06-09 (Tier 3 dungeon.gd split — third extraction
shipped: DebugDump pulled out of the 3735-LOC dungeon).

`project/scripts/debug_dump.gd` is a pure static utility class
(`class_name DebugDump`, extends RefCounted) that owns the entire
floor-dump dev-tool surface: `serialize_marks(marks)`,
`analyze_floor_regions(grid, w, h)`, `build_floor_report(dungeon)`,
and `dump_and_save(dungeon)`. Caller passes the dungeon node;
methods read its fields directly. No per-instance state, no node
graph. Behavior is a strict copy of the dungeon.gd functions it
replaces — no JSON shape changes, no tuning.

`dungeon.gd` shrank 3735 → 3413 (-322 lines). The chrome signal
connect in `_ensure_hud` (`chrome.debug_dump_requested.connect`)
still targets `_on_debug_dump_requested` on the dungeon — that
function is now a one-liner forwarder calling
`DebugDump.dump_and_save(self)`. The screenshot manifest's two
`_serialize_marks` calls (`_collect_render_manifest` lines 840-841)
route through `DebugDump.serialize_marks` so the helper has a
single source of truth across both dev-tool dumps.

The dump itself is unchanged: triggered from the in-game debug HUD
"Dump floor" button, builds the full JSON report, writes
`user://floor_dump_<unix>.json`, copies the JSON to the clipboard,
prints `[floor-dump] saved=...`, logs `[floor-dump]` via
`GrindLog.log_line`, and flashes the chrome status with
`flash_debug_dump_status`. No GUT regression test was added — the
dev-tool is too prone to false-positive failures on shape drift,
and locking field-by-field equality would discourage adding new
fields.

---

Earlier 2026-06-09 (Tier 3 dungeon.gd split — second extraction
shipped: HUDInventoryController pulled out of the 4167-LOC dungeon).

`project/scripts/hud_inventory_controller.gd` is a RefCounted helper
the dungeon owns. It carries the live HUD inventory state (`loot_segments`,
`current_floor_segment_index`, `hud_inv_cache`, `hud_inventory_seeded`,
`inventory_cap`, `run_salvaged_count`, `run_salvaged_gold`,
`pending_salvage_check`, `slot_cooldowns`) and the methods that mutate
it: `init_run`, `complete_loot_pickup`, `flush_pending_drops`,
`maybe_auto_salvage`, `maybe_auto_salvage_if_pending`,
`try_equip_from_segment`, `instance_at_segment_idx`, `handle_drag_drop`,
`handle_unequip_request`, `append_to_active_segment`,
`tick_cooldowns`, `push_inventory_to_hud`. The drag-equip surface
(`_hud_drag_equip_by_instance_id`, `_hud_drag_equip_at`,
`_hud_drag_equip_from_inv`, `_hud_drag_swap_slots`,
`_equip_to_explicit_slot`, `_resolve_equip_slot_for`) is private to the
controller. The `STARTER_IDS` const and `EQUIP_COOLDOWN_SECONDS` move
with it. Behavior is a strict copy — no tuning or balance changes ride
the extraction.

Two load-bearing fixes survive the move verbatim:
* **Chest-loot-loss** (commit `f80376b`) — `flush_pending_drops` folds
  in-flight LootDrops into the active segment via a Callable provider
  the dungeon hands the controller. The `_on_inv_drop_folded` callback
  keeps `floor_loot_picked` + `dropped_items` in sync on the dungeon
  side (those counters live there, not on the controller).
* **Click-duplication guard** — `instance_at_segment_idx` + the
  `prev_inst_id` / `now_inst_id` snapshots in every equip path.
  HUD chrome still calls `equip_request_target.try_equip_from_segment`
  + `instance_at_segment_idx` by name; dungeon keeps thin forwarders
  so chrome doesn't need to learn about the controller.

`dungeon.gd` shrank 4167 → 3727 (-440 lines). Signal connect
(`chrome.hud_drag_drop` / `chrome.hud_unequip_requested`) still
targets the dungeon, which forwards into the controller. Per-frame
`_tick_equip_cooldowns(delta)` calls `inv.tick_cooldowns(delta)`.
`flush_to_save` and `_end_run` read `inv.hud_inv_cache` and
`inv.run_salvaged_*` for serialization. Run-init creates the
controller once and re-binds it on subsequent runs (Bot is fresh
each run) via `bind(bot, items_db, chrome)`.

Test foundation extended: `test_hud_inventory_controller.gd` 18 tests
covering segment shape (init_run seeds Base + cap, complete_loot_pickup
lazy-creates the floor segment, reuses on subsequent picks),
flush_pending_drops happy path + chest-loss edge case (no walk-pickup
yet → segment lazy-created), auto-salvage walking oldest-first,
skipping favorites + STARTER_IDS + above-filter rarity, and
maybe_auto_salvage_if_pending clearing the deferred-flag. The
click-duplication guard is locked down via three
`instance_at_segment_idx` cases including the post-shift stale read.
Cooldown tick decay + eviction. `_stub_bot.gd` provides the minimal
Bot surface the salvage path needs without dragging in Actor's rig.
GUT 73 → 91 tests, ~2544 → ~2599 asserts. Suite still ~3s headless.

Validation: GUT 91/91 pass post-extraction.
`tools/check_before_commit.sh` all 5 steps pass. Manual mortal T1
3-run grind (preset t1, --mortal): 215 loot pickups, 1 sewer portal
entered (chest-open path exercised), 1949+137+979 kills, 0 errors,
0 stalls. Auto-salvage exercised inline (run 1 cap=50 with 133
loot rolls, run 3 with 71 + base inventory). Inventory pipeline
behaves identically to pre-extraction within run-to-run RNG
variance.

Next dungeon.gd extraction: DebugDump (pure dev-tool, no shipping
surface — moves the floor-dump JSON serializer + clipboard helpers
out). Each session shrinks dungeon.gd by ~400-600 lines and doesn't
touch anything else.

---

Earlier 2026-06-09 (Tier 3 dungeon.gd split — first extraction
shipped: LootFactory pulled out of the 4492-LOC god-class).

`project/scripts/loot_factory.gd` is a pure static utility class
owning the loot pipeline: `roll_rarity`, `roll_rarity_with_bias`,
`pick_loot_id`, `clamp_rarity_to_tier`, `create_item_instance`,
`salvage_value`, `hue_to_stat_lean`, plus the `TIER_RARITY_CAP`,
`RARITY_RANK`, `SLOT_DROP_WEIGHTS`, `SALVAGE_VALUES` constant tables.
Caller passes rng + items_db + derived state; LootFactory holds no
node graph and no per-instance state. Behavior is a strict copy of
the prior dungeon.gd functions — no tuning or balance changes ride
the extraction.

`dungeon.gd` shrank 4492 → 4167 (-325 lines). All five call sites
now route through LootFactory: enemy drops, vault loot_marks, chest
opens, auto-salvage gold totals, and the showcase floor's spawn
helper. Kept a thin `_roll_drop_rarity` wrapper that pulls the bot's
blessing bonus + active run-modifier rarity_bonus into the call so
LootFactory's `roll_rarity` stays pure. `shop.gd`'s duplicate
`SALVAGE_VALUES` const replaced with `LootFactory.salvage_value()`
(buy_price + sell_price). `offline_progress.gd` had its dead
`_legacy_apply` body and helpers (including the audit-flagged third
`_roll_rarity` duplicate) deleted; public `apply()` no-op stub
preserved for main.gd / main_menu.gd callers.

Test foundation extended: `test_loot_factory.gd` 13 tests / ~26
asserts covering same-seed determinism (roll_rarity,
roll_rarity_with_bias, pick_loot_id, create_item_instance), rarity
distribution within ±5% of expected thresholds at T5/floor 1,
T1-clamp behavior, boss-roll skew toward legendary, salvage values,
hue→stat-lean color wheel, allow_spell gating, and unique-item
single-roll guarantee. GUT 60 → 73 tests, ~973 → ~2544 asserts
(distribution test alone runs N=2000 rolls). Suite still ~3.3s
headless.

Validation: GUT 73/73 pass post-extraction. `tools/check_before_commit.sh`
all 5 steps pass. Manual mortal T1 3-run grind: 174 loot drops, 1
trove portal entered (chest-open path exercised), 1046+119+1302
kills, 0 errors, 0 stalls. Loot pipeline behaves identically to
pre-extraction within run-to-run RNG variance.

---

Earlier 2026-06-09 (Tier 2 save durability shipped — atomic
.tmp+.bak rotate, schema_version + versioned migration chain with
downgrade refusal, equipped/inventory orphan validation against
items.json, web tab-close FS.syncfs flush, run-report dismissal
gated on flush completion).

Five-item audit cluster, four commits:

- `b231740` — `_save_wrapper` rewrites via `<path>.tmp` + rotate-old-
  to-`.bak` + atomic rename. `_load_wrapper` falls back to `.bak` when
  the primary fails to parse, quarantines corrupted files as
  `.corrupted-<unix_ts>` for forensic recovery, and surfaces
  `save_recovered_from_backup` / `save_could_not_be_loaded` via
  `SaveState.last_load_warnings` + a runtime-only
  `state.last_load_warnings` field. Switched the parse path to
  `JSON.new().parse()` so corrupted-file recovery doesn't emit
  engine-level errors.
- `3421610` — `SCHEMA_VERSION = 7` field added; `_migrate` is now a
  versioned chain (`_migrate_to_v7` subsumes the 6+ historic
  probe-based bumps from gloves/cloak through ring-collapse). Loader
  refuses to overwrite saves with `schema_version > SCHEMA_VERSION` —
  preserves the future-version save as `.future-v<n>-<ts>` and
  surfaces `save_from_future_build` so an older build can't silently
  downgrade a newer build's save. `_finalize_loaded_wrapper` now runs
  `_migrate` BEFORE the `_default()`-key fill so a pre-v7 save's
  missing `schema_version` isn't masked into a no-op migrate.
- `cbd4ea1` — `_validate_loaded_state` walks equipped + inventory,
  evicts orphaned `base_id` entries (missing from items.json) into a
  new `state.orphaned_items` array. Player isn't silently robbed of
  build-defining gear when a base_id is renamed/deleted between
  builds; once it's restored the orphan is recoverable. Surfaces
  `orphan_items_count_<n>` warning. `orphaned_items` added to
  `_default()`.
- `b19d07f` — Web tab-close save flush. New `SaveState.flush_to_disk
  (on_done: Callable)` — no-op on Steam/desktop (`FileAccess` is
  already synchronous), `FS.syncfs(false, ...)` on web with optional
  callback. `main.gd` installs a JS pagehide / beforeunload /
  visibilitychange listener that fires syncfs unconditionally on tab
  close, plus a belt-and-braces `NOTIFICATION_WM_CLOSE_REQUEST`
  handler. Explicit flush calls after `_on_boss_killed` (the audit's
  headline web failure mode), `_on_run_ended`, shop `_buy_one` /
  `_sell_all_junk`. Run-report buttons start disabled with a "Saving…"
  hint and become clickable when the syncfs callback fires — Steam
  fires it synchronously, web round-trip is <100ms, but a fast clicker
  could otherwise drop the unlock to a tab close in the moments after
  the report appears.

Test foundation extended: `test_save_state.gd` 8 → 18 tests covering
atomic-write happy path, `.bak` torn-write recovery, both-files-
corrupted defaults, warnings-not-baked-to-disk, schema_version stamps
and short-circuits, future-version quarantine, orphan eviction in
both equipped and inventory, real-item not-evicted false-positive
guard. GUT 50 → 60 tests, ~941 → ~973 asserts, suite still ~3s
headless.

Manual /grind 3 t1 mortal smoke: 3 cycles of save / load / migrate /
re-save, atomic rotation working (`<path>` + `<path>.bak`, no `.tmp`
residue), `schema_version: 7` stamped, no orphans on the live debug
save. No itch redeploy this session — durability changes need
broader playtest validation before pushing to the playtester.

---

Earlier 2026-06-09 (Tier 1 UI cleanup cluster shipped — 7
small commits closing the last of the audit's UI / cleanup
backlog).

The 7 fixes, in commit order:

- `5c98387` — HUD `update_stats` now hashes its inputs and skips
  `SaveState.load_state()` + `StatCalc.compute()` when nothing
  changed. Reads `bot.upgrade_state` directly. Headless 16× grind
  frame_ms dropped 3.0-3.4 → 1.7-2.5 (~35%).
- `fa18a5f` — main menu hides FX Tuner / Paperdoll Audit / Spell
  Showcase / Item Generator unless `OS.is_debug_build()` or
  `BOTTER_DEV=1`. Pause-menu FX Tuner still works in release.
- `acce5a7` — delete-bot confirm dialog now identifies the
  character (species / level / runs / gold) instead of saying
  "this character".
- `f93f633` — `lightning` flavor canonicalized to `thunderous`
  across items.json (3 fixes) + enchant_combos.json (6 combos
  whose pair lookup was silently dead). Closed 8 other coverage
  gaps; wired `tools/check_flavor_coverage.py` into pre-commit
  step 2/5 to catch future drift.
- `57bbc47` — v1-schema residue stripped from `format_item_tooltip`
  (was reading `atk/def/hp` keys that v2 items don't carry; now
  reads `damage_min/max + armor + evasion`). `_format_stat_line`
  drops the dead `atk`/`def` cases. ItemsDb asserts
  `_format_version == 2` on load. 3 new tests in
  `test_affix_system.gd`.
- `0a4e995` — `bot._realize_implicit` deleted (verbatim duplicate
  of `stat_calc._realize_implicit` with zero callers).
- `4a125f6` — `species_data.gd` doc comments refreshed to describe
  StatCalc reality (the `base_max_hp` / `base_atk` / `base_def`
  fields the comments referenced were already removed in `81500b0`).

GUT 47 → 50 tests, ~933 → ~941 asserts, full suite still ~3s
headless. Pre-commit umbrella now 5 steps (was 4) — added a
flavor-coverage gate.

---

Earlier 2026-06-09 (Tier 2 test-foundation shipped — GUT
addon vendored, three new test files added, full suite wired into
both pre-commit and CI).

The 2026-06-08 hand-rolled SceneTree harness (`stat_calc_tests.gd` +
`actor_combat_tests.gd`) migrated to GUT 9.6.0, vendored at
`project/addons/gut/`. Five test files now live at
`project/tests/test_*.gd`:

| File | Tests | Locks in |
|---|---|---|
| `test_stat_calc.gd` | 12 | StatCalc unification (blessing kinds, species mods, lifesteal clamp, spell_element_pct, unspent_points routing) |
| `test_actor_combat.gd` | 11 | Combat-correctness fixes (single avoidance roll per swing, thorns/crystal aggregation, multi-emit `died` regression, spell element piping) |
| `test_save_state.gd` | 8 | Migration idempotence + historic shapes (octopode ring2 regression, ring1/ring2 collapse, spell-slot/gloves/cloak forward-compat init, stat-point retroactive grant) |
| `test_affix_system.gd` | 9 | `roll_affixes_for` reproducibility, rarity_affix_count contract, applies_to filter, common/uncommon spell flag-affix gating, no duplicate affixes |
| `test_dungeon_generator.gd` | 7 | `generate` connectivity (spawn reaches stairs across biome × layout × seed cross-section), seeded determinism |

47 tests, ~933 assertions, full suite runs in ~3s headless.

Run locally:

```
/Applications/Godot.app/Contents/MacOS/Godot --path project --headless \
    -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit
```

Or via the umbrella (also runs the per-biome smoke-build):

```
bash tools/check_before_commit.sh
```

Pre-commit step 2/4 invokes GUT; CI runs the same `gut_cmdln.gd`
invocation via `.github/workflows/test.yml` on every push/PR (caches
the Godot 4.6.2 Linux binary across runs).

**Convention going forward.** Every Tier 1+ fix that touches a
covered system must add at least one regression test to its
relevant `test_*.gd` file before the fix is committed. Tests are
cheap (3s) — there's no excuse to skip them. New systems get a new
`test_<system>.gd` file; co-locate stubs as `_stub_<role>.gd` (see
`tests/_stub_attacker.gd` / `tests/_stub_defender.gd`).

GUT's `assert_*` helpers — `assert_eq`, `assert_almost_eq`,
`assert_true`, `assert_false`, `assert_not_null`, `assert_lt` /
`assert_gte` — replace the hand-rolled `_eq` / `_assert_close`. One
gotcha: `assert_ne(x, null, msg)` chokes on null comparisons; use
`assert_not_null(x, msg)` instead.

---

Earlier 2026-06-08 (clean-room rewrite of `dcss_layouts.gd`).
Tier 2 audit item shipped: the dungeon-layout algorithms (`basic_level`,
`make_trail`, `delve`) were a structural line-translation of GPLv2+
DCSS C++ — same magic constants, same `denom_table`, same control
flow. Replaced via a clean-room workflow: a behavior-only description
(`~/claude/game-audit/findings/dcss_layouts_descriptions.md`) drove
a fresh session that never opened `dcss-source/` or the prior
`dcss_layouts.gd`. New file uses original variable names, an original
flat-loop control structure, and a closed-form density divisor in
place of the 12-entry table. Top-of-file provenance comment in place.
666 insertions / 798 deletions vs prior. Caves and basic levels
generate playably; bot completes runs at the historical fresh-save
variance band. Diff vs prior is a structural rewrite, not a rename pass.

NOTICE.md / CREDITS still need a one-line update calling out that the
layout algorithms are original GDScript implementations of standard
dungeon-gen patterns, not ported from DCSS source — that's the
Tier 2 follow-up item in TODO.md.

---

Prior refresh: 2026-06-08 (Tier 1 combat-correctness cluster).
Four audit-flagged combat path bugs in the spell + hybrid-weapon
damage pipeline:

- **Single avoidance roll per swing.** `actor.gd::attempt_attack`
  splits hybrid weapons (physical+fire+cold) into per-damage-type
  components and called `take_damage` once per type. Each call
  independently rolled evasion, footwork, reflective full-negate AND
  fired thorns/crystal returns to the attacker. A 3-element hybrid
  swing got 3 dodge rolls (P(land) = 1 - 0.5³ = 87.5% at 50% evasion
  vs 50% post-fix) and 3 attacker-bound thorn chunks — which could
  multi-emit `died` if the first chunk killed. New
  `Actor.resolve_swing(typed: Dictionary, attacker)` rolls avoidance
  once for the whole swing, walks each component through pure
  mitigation, aggregates dealt damage, fires thorns/crystal once at
  the end. Single-hit `take_damage` callers (spells, projectiles,
  splash, DoT-bypass) wrap a 1-entry typed dict and route through
  resolve_swing for the same semantics.
- **Element + attacker piped into spell `take_damage`.** Every spell
  hit pre-fix called `take_damage(amount)` with no attacker, no
  damage_type. Default damage_type was "physical", so a fireball
  routed through armor not fire resistance, and defender flavor tags
  that depend on attacker tags (fire_res, cold_res, willpower, earth,
  harm) evaluated against an empty `atk_tags` array. Wired through 8
  call sites in `spell_system.gd` + `projectile.gd` + `orbit_controller.gd`
  via `SpellData.damage_type_for_element` (fire/cold/holy/poison/dark
  pass through, `thunderous` → `lightning` for the resistance lookup).
  `Projectile` gained a `caster` field carrying the bot reference;
  spawn_fireball plumbs it through; pierce hits + lifesteal-Drain
  share the same caster.
- **Spell-item `damage_min`/`damage_max` rolled per cast.**
  `spell_data.gd::compute_damage` read `item.get("damage", arch.damage)`.
  No spell item declares `damage` (175/175 declare damage_min/max);
  every cast fell through to the archetype default. Per-tome rarity
  / quality / meta-rarity scaling was purely cosmetic. Now rolls
  `randi_range(damage_min, damage_max)` when present, applies
  `meta_mult × Quality.multiplier_for(inst)` mirroring the StatCalc
  weapon path. Inst is plumbed through via a `_inst` stash on the
  dispatch view dict.
- **`spell_proj_bonus` clamped at +5.** `stat_calc.gd:286-289` clamps
  every spell stat except spell_proj_bonus. `of_multicast` on 10
  possible slots × DR-stacked totals could reach +6 endgame,
  multiplying chain-jump count and projectile-spawning spells with
  no ceiling. One-line `clampi(0, 5)` alongside the others.

**Test harness expanded.** New `project/tests/actor_combat_tests.gd`
SceneTree script — 17 assertions covering typed mitigation (armor,
fire_res, harm), avoidance gates (single-roll evasion), thorns +
crystal aggregation, the multi-emit `died` regression, spell element
piping (fire vs fire_res tag + resistance dict, lightning resistance
halving thunderous spells), and the SpellData element→damage_type
mapping. Two stub helpers (`_stub_attacker.gd` / `_stub_defender.gd`)
override Actor.combat_weapon_tags / combat_defense_tags / evasion so
tests don't need a Bot instance. Wired into
`tools/check_before_commit.sh` as step 3/5 alongside the existing
StatCalc harness. 39/39 tests passing.

**Mortal grind smoke.** T3 2-run mortal (no save baseline): runs
floor=5/floor=6 reaching the boss in run 2 (1 victory), 1143+1221
kills, 0 errors, 0 stalls. T1 3-run mortal: floors 1/2/1, mean
1.3 — within the pre-fix variance band documented for t1. Hybrid
weapons are now squishier vs evasive enemies (single roll); spells
genuinely scale through resists. Further tuning likely needed once
players actually run resist-heavy builds.

---

Earlier 2026-06-08 (Tier 1 StatCalc residue cluster).
StatCalc-unification residue swept — 4 audit-flagged "advertised
mechanic does not work" issues + 1 user-reported buff-bar bug:

- **15 of 22 god altars now real.** `bot.grant_blessing` was writing
  `atk_pct/atk_flat/def_flat/hp_pct` blessings into private `bot.bonus_*`
  fields, but `StatCalc.compute()` overwrote `damage_min/max/armor/max_hp`
  from its own dict-based rollup and never read those fields. Effect:
  Trog/Zin/Beogh/Yred/TSO/Lugonu/Xom/Qazlal/Ru/Cheibriados/Dithmenos/
  Okawaru/Fedhas blessings did literally nothing (only Elyvilon, Vehumet,
  Sif Muna, Ashenzari, Gozag, Kiku, Makhleb, Jiyva, Nemelex worked
  through other channels). StatCalc now reads `blessings[].kind` directly
  for atk_pct (×damage_min/max), atk_flat (+damage_min/max), def_flat
  (+armor), hp_pct (×sp_hp_mult — stacks multiplicatively with species).
  Dead `bot.bonus_atk_pct/atk_flat/def_flat/max_hp_pct/base_max_hp`
  fields removed.
- **Species atk_pct / def_pct / aggro_flat now real.** Minotaur's "+20%
  ATK", Naga's "+10% DEF", Demonspawn's "+10% ATK" etc. were shown in
  the character_create preview but never read by StatCalc. Now folded
  in alongside the blessing rollup. atk_pct multiplies damage_min/max
  after flat upgrade, def_pct multiplies armor after flat upgrade,
  aggro_flat surfaces in the aggro_bonus output.
- **Element-damage builds buildable.** Six new affix entries —
  `of_pyromancer` (fire), `of_cryomancer` (cold), `of_storm`
  (thunderous), `of_zealot` (holy), `of_venom` (poison), `of_shadow`
  (dark) — each rolling 4-45% on amulet/ring/helm/gloves/cloak/spell.
  StatCalc folds the per-element sums into `spell_element_pct[<elem>]`
  with a 100% per-element soft cap. `spell_data.gd:181-182` was
  already reading `bot.spell_element_pct[arch.element]` to scale
  element-tagged spells — the dict was just never populated.
- **Gear `of_lifesteal` heals.** `bot.lifesteal_pct` was clamped at
  15% in StatCalc and assigned to the bot field, but melee never
  read it — only `lifesteal_per_hit` (flat blessings) and the 8%
  `vampiric` flavor tag fired. `Bot.attempt_attack` now adds a
  `dealt × lifesteal_pct / 100` heal alongside the existing flat
  channel. vampiric still fires from `actor.gd::attempt_attack` so
  vampiric weapons don't double-dip.
- **Per-god buff icons.** Pre-fix every blessing collapsed to a
  single generic "blessed" status row, so a player who'd visited
  Trog + Zin + Sif Muna saw one icon. `StatusOverlay.STATUSES` now
  has 22 `blessed_<god>` entries (Trog, Okawaru, Zin, Elyvilon,
  Vehumet, Kikubaaqudgha, Sif Muna, Beogh, Makhleb, Yredelemnul,
  TSO, Lugonu, Jiyva, Fedhas, Cheibriados, Xom, Ashenzari, Dithmenos,
  Gozag, Qazlal, Nemelex, Ru) each using the existing
  `assets/tiles/features/altar_<god>.png` as its buff-bar icon
  with the per-god halo tint. `bot.grant_blessing` adds
  `blessed_<god>` instead of generic `blessed`. `clear_blessings`
  sweeps every `blessed_*` status. Run-scoped (cleared at run
  start, not floor descent — preserves prior mental model).

**StatCalc.compute test harness.** New `project/tests/stat_calc_tests.gd`
SceneTree script — 22 golden-master assertions covering bare bot,
species mods (Minotaur/Naga/Octopode), each blessing kind,
multiplicative HP stacking, lifesteal clamp, the audit-flagged
`stat_points_unspent` key, and `of_pyromancer → spell_element_pct.fire`.
Runs in <2s via
`Godot --path project --headless --script tests/stat_calc_tests.gd`,
exits non-zero on any failure. Wired into
`tools/check_before_commit.sh` as step 2/4. First unit test in the
project — Tier 2 audit task "Zero unit tests across 27,808 LOC"
starts to recede.

**Balance smoke** (3-run t1 mortal): floors 2/1/2, level 6→10, no
errors / stalls / bad-floors. Within run-to-run variance vs the
pre-fix 10-run snapshot mean of 2.0. The newly-real altar power
swing isn't dominating tier-1; further tuning probably needed at
T3+ once players actually stack 3-4 god blessings deep into a run.

Earlier 2026-06-08 (Tier 1 save/progression bug cluster):
- `cd69e55` `stat_calc.gd` was reading `save["unspent_points"]` while
  every writer used `stat_points_unspent`. Outpost stats panel was
  pinned to "Unspent: 0" forever post level-up.
- `256ccc0` Octopode (4 rings) + naga (2 rings) lost ring2 every save
  load: legacy ring1/ring2 → ring collapse migration ran on every load
  instead of once, and species init recreated ring2 just before the
  legacy block treated it as a stale legacy key. Now gated on a
  one-time `migration_v_ring_collapse` flag and skipped entirely for
  species whose ring_slot_ids include ring2.
- `f80376b` Chests rolled their loot at OPEN time + spawned LootDrop
  nodes; items only entered `_hud_inv_cache` when `_complete_loot_pickup`
  ran (after the bot stood on each drop ~0.4-0.8s). Esc → Main Menu
  mid-pickup discarded everything in `loot_drops`. `flush_to_save` now
  folds live unconsumed drops into the current floor segment before
  serializing.

Earlier 2026-06-08: HTML5 web build + itch.io playtest. Botter
is now publicly playable in a browser at
**https://deanyo-gh.itch.io/botter-idle**. itch project is set to
"restricted" visibility — link-only sharing for friends-feedback. Build
shipped in **Compatibility renderer + single-threaded WASM** so it runs
on every browser without needing the SharedArrayBuffer header dance.

**Deploy pipeline.** `tools/deploy_web.sh` runs Godot's HTML5 export →
zips for archive → pushes via butler to `deanyo-gh/botter-idle:html5`.
Wrapped as the `/deploy-web` skill so future sessions invoke it
naturally. Each deploy auto-bumps a counter in `dist/.build_counter`,
stamps `project/data/build_version.json`, and the game prints
`[build] version=vN ts=...` on boot + bakes "Botter — build vN" into
the browser tab title + shows it in the in-game debug HUD. Triple
redundancy because itch's CDN occasionally serves stale wasm/pck for
several minutes after a butler push — manual zip upload via the itch
edit page is the reliable fallback when butler's CDN is lagging.

**Web perf optimizations shipped today** (in priority order of
real-world impact):

1. **`MapRenderer` atlas-bake → multi-source TileSet.** Pre-fix,
   every floor build called `tex.get_image()` per tile (forces
   GPU→CPU readback) and uploaded a packed atlas — that's the
   single biggest cost in Godot Web GL Compatibility. New path
   builds a TileSet with one source per texture; ~50 sources
   instead of 1, but no `get_image()` calls. Cut dungeon-load
   from 60s → 15s.
2. **Vault bundle (desktop only).** `tools/build_vault_bundle.py`
   packs all 1335 `.json` vault files into one `vaults_bundle.json`
   (0.8 MB). `VaultLibrary._ensure_loaded` reads the bundle first,
   falls back to per-file enumeration on desktop dev. Web load
   dropped another ~10s on desktop. **The bundle and per-file
   vaults are both excluded from the web pck** via `exclude_filter`
   in `export_presets.cfg` (`data/vaults/*.json,data/vaults_bundle.json`).
   Web builds therefore ship with no vault content — a deliberate
   legal-hygiene choice (vaults are ports of GPLv2+ DCSS source).
   Re-add to web only after the corpus is replaced with original
   content. 2026-06-08.
3. **Tile dir manifest.** `tools/build_tile_dir_manifest.py`
   pre-bakes directory listings for `floor/`, `wall/`, `overlays/`,
   `sigils/`, `items/artefacts/`. HTML5 can't enumerate `res://`
   directories via DirAccess (virtualized FS in the .pck), so
   `BiomeData._list_dir` and `ArtefactPool` read from
   `data/tile_dir_manifest.json` first. **`data/vaults/` is
   intentionally NOT in the manifest** (was previously, removed
   2026-06-08): the 1320 ported vault filenames carry contributor
   handles (`des_<author>_*.json`), and shipping them in the manifest
   would leak attribution into the web .pck even when the vaults
   themselves are excluded. `VaultLibrary` only ever runs the
   DirAccess fallback on desktop and shouldn't be called on web
   anyway (no vaults to load).
4. **Wave-spawn stagger.** `dungeon.gd::_tick_wave_spawns` queues
   spawn IDs into `_pending_wave_spawns` instead of spawning
   N enemies in a single frame. `_drain_pending_spawns` pulls
   one per frame from `_process`. Pre-fix: 4-8 enemies materializing
   on the same frame triggered a synchronous GPU pipeline compile
   stall (6+ second hang). Now spread across 4-8 frames so each
   frame's pipeline cost is invisible.
5. **GPU upload pre-warm via RenderingServer.** `BiomeData.prewarm_biome`
   walks every floor / wall / overlay / sigil / enemy / item
   texture for the chosen biome and forces an actual GPU upload
   by drawing 1×1 rects via `RenderingServer.canvas_item_add_texture_rect`
   on the root canvas. Earlier attempts using off-screen
   `TextureRect`s got frustum-culled by the browser; going through
   RS bypasses scene-tree culling entirely. Throttled to 8
   textures per frame so the pre-warm itself doesn't stall outpost
   startup. Outpost calls `prewarm_biome` for every unlocked branch
   on `_ready`.
6. **Shared shader materials.** `ShaderMaterial.new()` per sprite
   was producing pipeline-state thrash on Web GL. Now shared:
   - `MapRenderer._shared_heat_haze_mat` / `_shared_water_shimmer_mat`
     — one material across all lava/water sprites in a floor.
   - `LightSpec._ember_mat_cache` — `ParticleProcessMaterial`
     cached by particle color (was a fresh shader compile per
     fire-tagged enemy spawn).
   - `UITheme._recolor_mat_cache` — recolor materials cached by
     `(hue, sat, mode, colorize_strength)` tuple. Filter chips
     used to alloc N fresh `ShaderMaterial`s per inventory rebuild.
   - `ItemCell._desaturate_mat` — singleton across every blocked
     cell.
7. **Web-specific renderer toggles.** Threat-outline shader
   skipped on web (`enemy.gd::_ensure_outline_material` early-out).
   Item recolor shader skipped on web (`UITheme.recolor_material_for`
   returns null). PointLight2D shadows force-disabled on web
   (`light_spec.gd`). Bot weapon-glow pulse tween skipped on web
   (`bot.gd::_apply_rarity_decor`). Each one was a real spike
   source on Compatibility renderer; visual fidelity loss is
   minimal (modulate tints still carry rarity / flavor).
8. **Fog-overlay shader cost cut.** `MARCH_STEPS` 24 → 12, web
   light cap 24 → 8 in `fog_overlay.gd::update_lights`. Full-screen
   fragment shader was running 24 lights × 24 march steps × every
   pixel; halved both for web.

**Diagnostic tooling.** `PerfMon.spike_tick()` measures wall-time
between `_process` calls and logs `[perf-spike] <ms>ms ctx=<context>`
when a frame exceeds 50ms. Filters:
- `> 15s` discarded (browser RAF-throttle on backgrounded tab,
  scene-transition pauses)
- `not DisplayServer.window_is_focused()` discarded (skipped
  when the tab is inactive — RAF backoff on inactive tabs
  produced ~6s "phantom" spikes that turned out to be browser
  throttling, not real stutters)

Stamping context: `dungeon.gd` calls
`PerfMon.note_spike_context(<event>)` at chest-open, wave-spawn,
loot-pickup, descend, drain-spawn, floor-built. The most-recent
context is the label on the next spike line, so a 6s spike with
`ctx="loot_pickup base=wooden_buckler"` tells us a never-before-seen
item texture caused the stall — directly traceable to a fix path.

**Manual zip upload.** Path of last resort when butler's CDN doesn't
propagate: `dist/botter_web.zip` (~12 MB) gets dropped on
https://deanyo-gh.itch.io/botter-idle/edit → Replace file. Worked
when butler-pushed builds were stuck serving v3 to Chrome despite
the dashboard showing v13.

**Earlier today: 2026-06-07 (HUD overhaul follow-up + clip_text
audit + outpost tabs).** [unchanged below]

---

Earlier: 2026-06-06 (stat system unification). Single source of
truth for stat math: new `StatCalc.compute()` static function takes
`(equipped, items_db, save_state, species_id, level, xp, gold,
blessings)` and returns a flat dict with every stat (vitals / combat /
spell modifiers / primary / misc). `bot.gd::recompute_stats` is a thin
wrapper that calls it and copies fields back. Outpost calls it
identically. **No more outpost-vs-HUD divergence** — pre-fix outpost
ignored meta_mult / Quality / bot upgrades / species seeds / worn-tag
passives, so a Pristine Ancient Iron Dagger read different numbers on
the deploy screen vs in-run. Two previously-dead bot upgrades wired
(`combat_training` → atk on damage_min/max, `toughening` → armor).
`fortified` flavor now applies to `armor` (was `defense`, never
showed in UI). `loot_rarity_bonus` and `xp_gain_pct` reset before
species/upgrade stacking in apply_gear (no double-count on
re-apply). New shared `StatPanel` widget renders every stat row
(including 0 values) at uniform font sizes in a ScrollContainer;
both HUD Stats tab and Outpost Stats tab use it. Haste shown as
"+24%" (the affix-sum value, capped 0..200, always non-negative)
instead of the inverse-formula "-50%" that confused players.
**Offline item generation REMOVED** per user direction — was
dumping ~16 fully-rolled items per session boot.

Earlier: 2026-06-06 (perf hotfix). HUD's per-frame work
(`update_buffs` + buffs-tab mirror) was rebuilding labels every
frame, and a freshly-added `subscribe_resize` on the HUD was
rebuilding 100+ Controls on any viewport size_changed signal —
together those caused 1-second freezes during play (120fps→3fps).
Both diffed/cached now. HUD resize subscription dropped (outpost
keeps it). Layout flipped: paperdoll now anchors to the bottom
(just above the bag), stats panel fills everything above. No
black dead-space below paperdoll on tall sidebars (M3 MBP 1.539
aspect).

Earlier today: 2026-06-06 (UI consistency beat). Big follow-up to
the spatial overhaul — Weapon-tab shows the same widget the hover
tooltip uses (`ItemTooltip`), HUD Stats tab matches outpost layout
(sections + UITheme.affix_stat_color rows), outpost stats fits in
a ScrollContainer + str/dex/int alloc buttons in proper HBox grid,
Bot Instructions promoted to its own outpost tab, font sizes pulled
from `UITheme.FS_*` tiers everywhere, paperdoll slot floor lowered
30px and BAG_H trimmed 340 → 240 so all paperdoll slots actually
fit, bag dead-space at bottom eliminated, main-menu vignette no
longer shows nonsense pre-deploy combat numbers (just Lv / Floor /
runs / gold).

Earlier today: 2026-06-06 (HUD spatial overhaul). Minimap relocated
out of the sidebar to a top-left WoW-style 160×160 overlay. Sidebar
gains the freed real estate for a roomier paperdoll + bigger Stats/
Weapon/Buffs tab pane. In-game inventory flattened — single grid,
newest-at-bottom, with rarity filter chips (Common/Uncommon+/Rare+/
Epic+/Legendary) sharing `state.loot_filter` with the auto-pickup
filter so chip changes also affect what the bot picks up next.
Outpost run-in-progress banner no longer clips under deploy panels.

Earlier: 2026-06-04 (perf + spell visuals + portal theme beat).
Autocast spells + Str/Dex/Int + density bump + base-attack weapon
procs + run-survives-death. Bot is now a VS-style autobattler with 5
autocast spell slots on top of the existing melee + gear loop.

## Capsule — UI consistency beat (2026-06-06, third beat)

Fixes from playtest of the spatial overhaul (capsule below): outpost
stats column was clipping its bottom rows + str/dex/int alloc buttons
overlapped the labels, HUD stats looked nothing like outpost stats,
paperdoll slot floor was bottoming out (spell row clipped off-bottom),
bag had ~36px black dead-space, main menu showed pre-deploy combat
stats that were always wrong.

* **`ItemTooltip` is the canonical "describe an item" widget.** Both
  the outpost Weapon tab and the HUD Weapon tab now embed an
  `ItemTooltip` and call `render_for(item, inst, db)` on the equipped
  weapon. Same widget the inventory hover tooltip uses, so the tab
  reads identical to the hover popup. Drops ~120 lines of bespoke
  weapon-tab rendering across `outpost.gd` + `hud_chrome.gd`.
* **`UITheme.FS_*` font tiers used everywhere.** New `FS_SECTION = 11`
  + `FS_TINY = 10` added to round out TITLE/HEADER/STAT/BODY/SMALL.
  New helpers `UITheme.label(text, size, color)` and
  `UITheme.section_label(text)` cut the boilerplate-per-Label from
  ~5 lines to one call. Audits HUD/outpost/main_menu — replaces
  literal 11/12/13/14/16/22 throughout.
* **Outpost Character pane reflowed.**
  * Stats tab wrapped in a ScrollContainer (no more bottom clip).
  * Str/Dex/Int rows now use real `HBoxContainer`s — label
    EXPAND_FILL on the left, − value + on the right, no overlap.
  * Dropped Dmg/Atk readout (Weapon tab covers it now — was double-
    displayed).
  * Bot Instructions promoted to its own tab (was a section at the
    bottom of Stats). Pickup filter dropdown + inventory cap readout
    + a hint about Pouch upgrade.
* **HUD Stats tab matches outpost layout** — section headers
  (Vitals / Combat / Resources / Location), section underline
  rule, UITheme.affix_stat_color() per row, drops Dmg readout
  (Weapon tab covers it).
* **Paperdoll size fix.** `paperdoll_h` budget recomputed: BAG_H
  trimmed 340 → 240 (frees 100px upward), stats_h tab area trimmed
  320 → 240 (frees 80px), slot floor lowered 36 → 30. All 5 right-
  column slots + bottom row + spell row now fit on the panel; spell
  row no longer clips off-bottom on a 1600×900 viewport.
* **Bag dead-space killed.** `_build_bag` used to floor `visible_rows`
  to a whole-row multiple, leaving up to ~42px black at the bottom.
  Scroll now uses the full available bag height; the last visible row
  partial-renders into the panel as a "more below" cue.
* **Main menu vignette simplified.** Drops the HP/ATK/DEF/Crit/
  Haste/Regen line — those numbers were derived from save-state
  before recompute_stats, so they were always slightly wrong relative
  to the deploy bot. Keeps Lv / Floor reached / runs / gold (durable
  progression numbers). `_derive_stats` deleted.

Validated: 2× headless grind at 16× (~470s total, 12 floors,
1.95k kills, 178 loot, 1 portal entered). Zero errors. Filter chip
persistence still works.

## Capsule — HUD spatial overhaul (2026-06-06, second beat)

After the morning's tab refactor (capsule below), the sidebar still
felt cramped: minimap ate ~380px which pinched the paperdoll, and
inventory segmentation by floor produced a noisy header-grid-header-
grid wall.

Three changes ship together:

* **Minimap → top-left overlay** (`_build_minimap_overlay`).
  Fixed 160×160, pinned to (6, 6), translucent dark backdrop +
  amber border. Out of the sidebar entirely. The freed sidebar
  height goes to the Stats panel (header + tabs ~ 376px now,
  was 286) and the paperdoll (now ~140px+ minimum, slot-shrink
  math handles the variance). Debug HUD shifts down to clear the
  minimap (`_build_debug` parks `debug_lbl` at y = minimap-bottom + 4).
* **Sidebar reflow** — drops the minimap panel; stats panel
  starts at y=0; paperdoll panel sits below tabs and above the
  bag. Both panels still wrap their children in clipping
  Controls (the no-element-escapes rule from earlier today).
* **Flat inventory** — one `GridContainer` for every loot item
  ever picked up, newest at the bottom of the scroll. Per-floor
  segment headers gone. Data model in `dungeon.gd` is unchanged
  (`_loot_segments` still keys by floor); only the render is
  flat. Filter chip row at the top of the bag (Common / Uncommon+
  / Rare+ / Epic+ / Legendary) drives both `cell.visible` AND
  the auto-pickup filter via shared `state.loot_filter`.
* **Bag panel clipped** — `_build_bag` now wraps everything in
  a `_bag_panel: Control` with `clip_contents = true`, finishing
  off the per-section clipping rule for the in-game HUD.
* **Outpost banner fix** — the "Run in progress: <branch> — Floor
  N" banner sat at y=48..72 but panels started at y=60. Bumped
  `top_y` to 80 when the banner is showing so it reads cleanly.

Validated: 2 grind runs at 16× (~250s each, 12 floors, 2.4k kills,
236 loot pickups). No errors. Filter chip clicks persist to save
state and round-trip cleanly.

## Capsule — HUD sidebar tabs + section clipping (2026-06-06)

Lost-session deferred work — applies the outpost.gd Character-pane
TabContainer pattern to `hud_chrome.gd`'s in-game sidebar.

Layout (top→bottom, `_build_sidebar`):

* **Minimap panel** (clipped Control)
* **Stats panel** (clipped Control) — always-visible header
  (`lbl_name` "Adventurer Lv X" + `lbl_hp` text + HP bar) +
  TabContainer with three pages:
  * **Stats**: Place / Dmg / Armor / Crit / Haste / Regen / Gold,
    two-column with per-Label `clip_text = true` so a "Dmg: 999-9999
    Lightning · 9.99s" line can't escape its column.
  * **Weapon**: equipped-weapon detail (rarity-colored name, dmg
    range, swing, DPS, traits, implicits, rolled affixes, iLvl).
    Rebuilt by `_rebuild_weapon_tab` whenever `update_equipped`
    fires. Wrapped in a `ScrollContainer` so >panel-height affix
    lists scroll instead of bleeding.
  * **Buffs**: pooled list of `BUFF_TAB_MAX` rows (icon + name +
    countdown). Driven by `_update_buffs_tab` from the same data
    that feeds the existing top-of-screen buff bar.
* **Paperdoll panel** (clipped Control) — equipment header +
  paperdoll rig + L-shape slot grid + spell row. Slot-shrink math
  preserved.
* **Bag panel** (still raw HUD root for now — clipping audit in
  TODO follow-up).

Every panel is built via `_make_clip_panel(x, y, w, h, parent)`
which sets `clip_contents = true` and `MOUSE_FILTER_PASS`. Labels
that take dynamic strings get `clip_text = true` and a fixed
`size`. Outline contract: **no text or element ever escapes its
section** (saved as a feedback memory; durable rule for future UI
work).

## Capsule — bespoke per-branch bosses (2026-06-04)

24 hand-authored boss enemies — one bespoke fight per biome. Replaces
the prior "strongest pool member, prefixed Greater" finale that made
every branch climax feel similar.

* New `boss_id` field on each biome in `data/biomes.json`. When set,
  `dungeon._spawn_enemies` uses it directly on the boss floor instead
  of running the legacy pool-pick. Pool-pick path retained as a
  fallback for biomes without a `boss_id` (or future mods).
* 24 new boss entries in `data/enemies.json` (tier 1 → 5), one per
  biome:
  - **T1** Sigmund (dungeon), Eustachio (dungeon_dark), Blork the Orc (mines)
  - **T2** Kirke (lair), Erolcha (forest), Grum (orc), Psyche the Witch (temple)
  - **T3** Aizul (snake), Ilsuiw the Tideborn (shoals), the Lernaean Hydra (swamp), Jorgrun the Spider (spider), Gastronok (hive)
  - **T4** Frederick (vaults), Boris the Lich (crypt), Menkaure the Pharaoh (tomb), the Enchantress (elf), Polyphemus (depths)
  - **T5** Azrael the Inferno (forge), Antaeus the Cold (glacier), Dissolution (slime), Killer Klown (labyrinth), Mnoleg (abyss), Cerebov (pandemonium), Tiamat the Many (zot)
* 24 sprites synced from DCSS `monster/unique/` into
  `project/assets/tiles/enemies/boss_*.png`.
* `_spawn_branch_boss` now keeps the authored name verbatim for
  bespoke bosses (id prefix `boss_`). The legacy pool-pick path still
  wraps as "Greater X" so the player reads "this is a boss-tier
  version of a normal mob."

## Capsule — critical playtest bug triage (2026-06-04)

Three reported bugs from the 2026-06-02 playtest, all root-caused
and fixed in one pass:

* **Mobs/chests stack on a single tile.** Spawn pickers had no
  occupancy tracking, so chests/altars/fountains/portals/packmates
  rolled the same cells. New `_spawn_used_cells` set on dungeon.gd
  populated incrementally; `_random_walkable_cell_far_from_bot` +
  `_walkable_cell_near` now skip used cells and mark picks. Fallback
  also rewritten: was top-25%-farthest sorted (deterministic clumping
  in one corner), now random pair with farther-of-two pick.
* **Invisible stairs.** `MapRenderer._stamp_decor_marks` allowed
  vault decor on `T_STAIRS_DOWN` cells, overwriting the stair
  sprite in the overlay layer. Now decor stamps onto plain `T_FLOOR`
  only.
* **Floor tiles drawing on top of monsters.** Heat-haze layer
  (z=50) + water-shimmer layer (z=49) were ABOVE actor_layer (z=10),
  painting over any monster on a lava/water cell. Dropped to z=3 and
  z=2 — between tile-overlay z=1 and actor_layer z=10.

## Capsule — spell archetype expansion (2026-06-04)

5 new autocast spell archetypes + 5 unique-tier named items + 6 new
archetype affixes. The spell roster goes from 5 archetypes → 10.

* **`spell_magic_dart`** — int, very short CD (0.7s), low damage (8-11),
  range 9. The "filler" spell that pops constantly. **Splintering
  Volley** affix splits each dart into 3 weaker side-darts on cast.
  Unique: **Splinterfang** (epic).
* **`spell_iron_shot`** — str, CD 3.5s, heavy 28-38 dmg, slow projectile
  (220 px/s) that pierces every body in its path with 25%-per-hit
  damage falloff. **Earthbreaker** affix slows pierced enemies for
  1.5s. Unique: **Ironcrash** (epic).
* **`spell_sandblast`** — str, CD 2.6s, short 3-cell cone (45° half-
  angle) at 26-34 dmg. **Blinding Grit** affix applies a 30% miss-
  chance debuff to all hit enemies for 2s. Unique: **Veil of Grit**
  (epic).
* **`spell_drain`** — int, CD 2.4s, dark-element homing projectile
  18-26 dmg that heals the bot for 35% of damage dealt regardless
  of gear lifesteal. **Ravenous** affix additionally adds a 4s
  hasted buff on each hit so chains snowball. Unique: **Soulhunger**
  (legendary).
* **`spell_shatter`** — str, CD 5s, radial physical AoE 24-34 dmg
  with brief 0.6s stun on hit. **Aftershock** affix fires a second
  smaller pulse 0.4s after the first at half damage / 70% radius.
  Unique: **Earthsong** (legendary).

Wiring:
* `SpellSystem._dispatch_fire` extended with 5 new branches.
* `SpellSystem._fold_inst_affixes_into` merges per-instance archetype
  flag affixes (implicit + rolled) into the dispatch-side item view
  so fire functions read flags off `item.get("spell_<flag>", false)`
  uniformly. Fixes the prior gap where existing archetype affixes
  (Bleeding Edge, Comet Trail, etc.) were declared but never read.
* `Projectile` extended: `piercing` + `pierce_falloff` + `pierce_apply_status`
  for Iron Shot; `lifesteal_pct` + `lifesteal_target` + `lifesteal_buff_bot`
  for Drain.
* `Actor.attempt_attack` reads new `blinded` status (30% miss chance)
  for Sandblast's Blinding Grit affix.
* `StatusOverlay.STATUS_DEFS` adds `blinded` entry.
* 5 new entries in `data/affixes.json`: splintering_volley,
  earthbreaker, blinding_grit, ravenous, aftershock.
* 10 new `data/items.json` entries (5 commons + 5 named uniques).
* Sprites synced from DCSS source (`gui/spells/conjuration/`,
  `gui/spells/earth/`, `gui/spells/necromancy/`) into
  `project/assets/tiles/items/spells/` + `projectiles/`.
* **Sprite variety pass.** Previously all 25 spell items reused the
  same 5 spell-tab icons (one per archetype). Now each spell item's
  tile is picked from a flavor + rarity matrix:
  - **Commons** = scrolls (`item/scroll/i-*.png`) — 35 unique scroll
    sprites available; flavor → scroll mapping (fire→immolation,
    cold→fog, holy→holy_word, dark→torment, poison→poison, etc.).
  - **Uncommon/rare** = colored books (`item/book/<color>.png`) —
    fire→red, cold→light_blue, holy→gold, poison→dark_green,
    dark→dark_blue, arcane→purple, earth→copper, etc.
  - **Epic/legendary** = distinctive specials (`book_of_the_dead`,
    `manual1`, `manual2`, `metal_*`, `parchment`) so uniques stand
    out at-a-glance in inventory.
  All 35 spell items now have unique-or-themed visuals; ~14 distinct
  sprites in active use vs 5 before.

## Capsule — perf + spell visuals + portal theme (2026-06-04)

Late-Phase-D + perf-pass + spell visual refinements:

* **Dungeon load latency.** First-time deploy ~50-100ms faster, repeat
  deploys ~30-60ms faster. New `ItemsDb` class caches items.json /
  enemies.json / monster_mods.json once per Godot session; `main._ready`
  warms the cache during offline-progress so the first deploy is hot.
  `dungeon._ready` defers heavy work via `call_deferred` so the loading
  curtain has a chance to paint before blocking. New
  `LoadingCurtain.hold_until_signal(obj, signal_name)` keeps the curtain
  up exactly as long as `floor_started` takes to fire — no
  fixed-duration over/undershoot.
* **Spell cooldown ring overlay.** Each of the 5 HUD spell cells now
  shows a radial sweep ring driven by `bot.spell_cooldowns` +
  `SpellSystem.cooldown_fraction`. Ring goes full → empty as cooldown
  ticks down. Driven from `dungeon._update_biome_hud` each frame; only
  redraws when fraction changes by ≥0.005.
* **Spinning Axes look like real spinning axes.** Bigger sprite scale
  (0.7 → 1.15), per-axe self-spin (rotates about its own center at
  14 rad/s), trailing glow sprite ~0.18 rad behind each axe so the
  motion arc is visible. User feedback: "axes don't look great" → axes
  now read as whirling weapons instead of icons tracking a circle.
* **AoE spell sprite-driven impact.** Frost Nova scatters 12
  ice_shatter sprites along the expanding ring perimeter. Chain
  Lightning drops a magic_shimmer sprite at every chain node. Holy
  Beam scatters 6 gold_sparkle sprites along the cone. All ride the
  same lifetime tween as the abstract shape, so the visual feels
  unified.
* **Run report unlock banner.** Beat 10 from the gameplay-loop overhaul
  — when a run unlocks new branches, the run report shows a slow-
  pulsing gold "BRANCHES UNLOCKED: X, Y" banner under the title.
  `main._on_deploy` snapshots `unlocked_branches` at run start and
  diffs at end; `run_report._install_unlock_banner` lazily creates the
  Label. Plus title polish: bigger font (32→56), centered, with a
  victory/defeat-colored underline strip.
* **Character-create stat telegraphing.** Species preview pane now
  leads with a STR / DEX / INT row in the spell-class colors, plus a
  starter-spell line showing which spell the species ships with and
  its primary stat color. Players see the build identity at pick time.
* **Portal-wide theme unification.** All 5 editors (atlas viewer,
  biome editor, item editor, affix editor, drop tuning) + index page
  now share a single `tools/portal.css` with the warm amber / OLED
  palette + button/tooltip widgets. Atlas viewer also got races /
  portals / gods quick-filter chips, slide-in detail panel with copy
  buttons, multi-root tile path resolver, keyboard shortcuts.



## Capsule — UI polish + duplication fix (2026-06-04)

Layout, theme, and one nasty equip bug:

* **Loading curtain on scene swaps.** `LoadingCurtain` autoload paints
  an amber-pulse + arc-spinner over the full viewport during every
  scene transition. Synchronous swap is preceded by a two-frame await
  for the heavy `DUNGEON_SCENE.instantiate()` path so the curtain
  visibly paints BEFORE the freeze (was: 1s freeze, then curtain
  flash). `show_for_swap` is no-op-aware when the curtain is already
  up so callers can paint it manually for heavy loads.
* **OLED-pure-black palette.** Every panel BG is alpha=1.0 (was
  0.85). UITheme owns BG_DEEP / BG_PANEL / BG_OVERLAY / BORDER_DIM /
  BORDER_ACCENT. Minimap mm_bg is fully transparent — backplate
  blends with sidebar.
* **Responsive HUD + outpost.** `UILayout` helper class (sidebar
  width clamped 320..480 of viewport, paperdoll pane 280..520).
  Outpost subscribes to `subscribe_resize` (250ms debounced) and
  rebuilds on every viewport size change. Spell row + paperdoll
  bottom row reserved space prevents overflow under the bag panel.
* **Combat-log overlay toggle.** Loot/combat log now renders as a
  translucent bottom-left overlay over the play area (top→bottom
  alpha gradient — old messages fade, newest reads cleanly). Bag
  panel uses the full bottom strip for inventory. Toggle in Video
  Options → "Loot/combat log overlay."
* **Inventory row clipping fix.** Scroll height rounds down to a
  whole-row multiple so the last visible row is never half-cut.
* **Default button focus + hover styleboxes.** `UITheme.style_button`
  + `style_all_buttons(root)` apply a consistent amber-accent normal /
  hover-wash / pressed / 2px-gold focus / dim-disabled style across
  every screen (main menu, outpost, run report, pause, video
  options, fx tuner, char create, shop). Replaces default Godot
  flat-grey hover.
* **Mac modifier-key tracking.** `UILayout.shift_held()` /
  `alt_held()` poll a static flag fed by InputEventKey.shift_pressed
  + keycode-on-keydown — works around Mac `Input.is_key_pressed`
  unreliability for pure-modifier presses. Cmd ⌘ counts as
  alt-equivalent for the alt-extended tooltip.
* **Drag duplication root cause.** `dungeon._hud_drag_equip_from_inv`
  no-op detection was `bot.equipped[dst_slot] != inst` but
  `_equip_to_explicit_slot` deep-duplicates the inst into the slot
  — so the comparison was ALWAYS true on a successful equip into an
  empty slot, leaving the original in inventory. Visible as "I
  dropped a flail and it's still in my bag." Now snapshots
  prev_instance_id and treats the equip as a no-op only when
  displaced is empty AND the slot's instance_id is unchanged.
* **Click duplication.** HUD inv cells now carry an `instance_id`
  meta. `_on_hud_inv_left_click` calls `instance_at_segment_idx` on
  the dungeon to verify the (seg_idx, item_idx) still resolves to
  the same item before equipping. Stale-cell rapid-clicks no-op
  cleanly instead of equipping whatever slid into that slot.



## Capsule — combat pivot (2026-06-04)

Combat went from "dull autoattack" to "1 base attack + 5 autocast
spell slots." Phase-by-phase:

* **Phase 1 — Spell slot plumbing.** 5 new equipped slots (spell1..
  spell5). Save schema migration for legacy chars. Empty slot icon.
  `SpellSystem` static class ticking each slot's cooldown each frame.
  Paperdoll cells in outpost + HUD chrome.

* **Phase 2-A — Stat overhaul.** Added Str/Dex/Int primary stats.
  Base 5/5/5 + species_flat + 1/level + gear affixes (might/finesse/
  wisdom). Each point = +2% damage on its scaling spells, plus
  derived contributions: Str→HP/atk, Dex→crit/haste, Int→spell
  damage/area/duration. New affix kinds: spell_cdr, spell_proj,
  spell_proj_speed, spell_area, spell_duration, spell_damage,
  fire_dmg, cold_dmg, lightning_dmg, holy_dmg, poison_dmg, dark_dmg.

* **Phase 2-B — Fireball end-to-end.** Homing projectile spell with
  `Projectile` node, `SpellData` archetype config, fire dispatcher in
  SpellSystem. Each species starts with a species-flavored starter
  spell pre-equipped to spell1 (Human=Fireball, Naga=Frost Nova,
  Vampire=Blood Arc, etc.). 20 spell items total in items.json (5
  base + 15 species variants). Visuals: per-item flavor color via
  `flavor_tags` — Vampire's Blood Arc reads RED, Demonspawn's
  Hellfire reads ORANGE, Spriggan's Forest Spinners read GREEN.

* **Phase 3 — All 5 archetypes.** Spinning Axes (`OrbitController`),
  Frost Nova (`SpellAoe.spawn_ring`), Chain Lightning (`SpellAoe.
  spawn_chain`), Holy Beam (`SpellAoe.spawn_cone`). Each scales off
  its primary stat: Spinning Axes/Holy Beam = Str, Chain Lightning =
  Dex, Fireball/Frost Nova = Int.

* **Phase 4 — Density + weapon procs.** Mob density tripled
  (90 + floor*30, cap 350). Wave spawns every 6-10s top up to ~75%
  of target (gated to prevent endless spawns on invincible bots).
  Burst events every 30-50s drop a 12-18 mob MAGIC pack. Base-attack
  weapon procs: dagger=bleed, 1H sword=cleave 1, 2H sword=cleave 2,
  1H axe=cleave 1 full, 2H axe=cleave 3 full, mace=stun chance,
  polearm=behind hit, whip=line falloff.

* **Phase 5 — Death survives the run.** "DEFEAT" instead of "YOU
  DIED" on the run report. "Redeploy" / "Outpost" buttons. New save
  fields `run_active`, `run_branch`, `run_floor_reached` track an
  in-progress run across deaths. Outpost shows "Run in progress: X —
  Floor N" banner + "End Run" button when active.

* **Color-coded spell classification.** Red = Str, Green = Dex,
  Blue = Int. Drives spell cell border color in paperdolls + Str/
  Dex/Int labels on the stats panel. Phase 2-A.

* **Atlas categorization.** `tools/build_atlas.py` now walks
  `project/assets/tiles/` as a third source root and emits
  first-class categories: species (15), spell (5), projectile (2),
  biome_icon (24), slot_icon (19). Authoring portal can browse them.

Smoke verification (legendary loadout, all 5 spells, single floor 6
victory): 1344 kills, ~900 spell fires across 3 archetypes, 0
errors, 65s elapsed.

## Capsule — what shipped before the pivot

Anything below is tracked in `TODO.md` for "what's next." See `git
log` for the per-commit timeline.

* **Item diversity** — gloves + cloak slots, 9 DCSS slot
  mismatches fixed, 17 starter items authored, 58 new weapons (axes/
  maces/polearms/2H/staves/exotics, 27 new base_types). Meta-rarity
  Ancient (1%) / Primal (0.1%) above legendary. Per-instance sprite
  recolor (hue/sat/inverted/shimmer/prismatic) with stat lean by hue
  family. Item secondary stats (crit/atk_speed/regen direct on
  items.json). 309 items total, all pass slot audit.
* **2H weapon mutual exclusion** — equipping a 2H weapon clears the
  shield slot back to inventory and vice versa. Tooltip shows "2H"
  badge on the rarity chunk.
* **Species selector + character creation** — 15 species roster
  (DCSS-faithful), each with stat mods + optional innate flavor tags
  (vampire→vampiric, demonspawn→demon). Sprite swaps everywhere
  paperdolls render. Reachable from main menu.
* **Multi-character saves** — `botter_save.json` wraps
  `{characters:[…], active:int}`. Existing single-char saves
  auto-migrate. New API: list_characters / create_character /
  set_active / delete_character. Main menu shows a horizontal
  scrollable Bots picker with switch/delete.
* **Slot conversion compensation** — DCSS-style restricted-slot
  payoff. Octopode loses armor/boots/helm → gains 3 extra ring slots
  (4 total). Naga loses boots → 1 extra. Equip flow routes ring
  items into the first empty ring slot. Paperdoll renders converted
  slots as ring cells labeled Ring II/III/IV. Bug fix: starter
  tattered_hide stripped on character creation for species that
  can't wear it.
* **Empty paperdoll slot icons** — greyscale silhouettes
  (long-sword/chain-mail/helmet/kite-shield/boots/glove/cloak/ring/
  amulet) baked under `project/assets/tiles/slot_icons/`. Fade to
  35% alpha, hidden when item equipped or species-blocked.
* **Biome icons on Outpost branch cards** — DCSS `enter_<branch>.png`
  where available, thematic substitutes (lava cell, ice tile,
  mangrove) for the rest. 96×96 watermark behind text labels.

## Item diversity pass — 2026-06-03

## Item diversity pass — 2026-06-03

Massive single-push beat covering slot schema, weapon family
expansion, meta-rarity above legendary, per-instance sprite
recoloring with stat lean, and item secondary stats. 309 items
total (was 251). Slot audit tool ensures sprite/slot/base_type
alignment matches DCSS source-of-truth (`art-data.txt`).

### Foundation

* **Gloves + cloak slots added** to save schema, paperdoll renderer,
  HUD chrome, Outpost, Bot._DEF_SLOTS, inject_save.py. Forward-compat
  migration in `save_state._migrate`. `paperdoll_renderer.SLOT_Z`
  layered: cloak (back) → boots → armor → gloves → helm → shield →
  weapon. Asset dirs `project/assets/tiles/player/{gloves,cloak}/`
  created.

* **9 DCSS-mismatched items fixed** by parsing
  `dcss-source/.../art-data.txt`. e.g. `urand_fencer` is
  *Fencer's Gloves* (`ARM_GLOVES`), `urand_flash` is *Cloak of
  Flash* (`ARM_CLOAK`). Items renamed where the lore was wrong:
  `fencer_slippers` → `fencer_gauntlets`, `flashboots` →
  `cloak_of_flash`, `thiefs_boots` → `cloak_of_the_thief`,
  `shield_of_war` → `gauntlets_of_war`. Plus reslotting
  `etheric_cage` → helm, `lightning_scales` → boots,
  `robe_of_resistance` → shield (it's a kite_shield in DCSS),
  `ratskin_cloak` + `starlight_cloak` → cloak.

* **17 starter items** for the new slots authored: 10 gloves + 8
  cloaks spanning common→epic. With the existing 6 unique
  gauntlets/cloaks → 23 items in the new slots.

* **`tools/check_item_slots.py`** validates every item's
  sprite/slot/base_type alignment per DCSS source. Exits non-zero
  on mismatch; CI gate. Currently 309/309 pass.

### Meta-rarity (Ancient / Primal) — D3 pattern

* `dungeon._create_item_instance` rolls `inst.meta_rarity` per drop:
  1.0% Ancient (gold tint, +20% base stats, "Ancient" prefix),
  0.1% Primal (red tint, +50% base stats, "Primal" prefix).
* `bot.recompute_stats` reads it and multiplies item.atk/def/hp.
* `UITheme.item_modulate` honors meta_rarity and tints OVER flavor
  + rarity (gold/red dominates so you can't miss the drop).
* `AffixSystem.format_item_name` prepends "Ancient" / "Primal".
* Tooltip line announces the meta-rarity tier.

### Per-instance recoloring + stat lean

New `assets/item_recolor.gdshader` — hue rotation + saturation +
mode (normal / shimmer / inverted / prismatic). 8-instruction
fragment shader, runs cheap per inv-cell sprite.

Roll rates per drop:
* Plain hue shift: ~25%
* Shimmer (animated highlight): ~3%
* Inverted (palette flipped): ~1%
* Prismatic (animated rainbow): ~0.5%
* Vanilla: ~70.5% (no shader cost)

`inst.tint = {hue, sat, mode, lean, lean_pct}`. Hue determines the
stat lean per `dungeon._hue_to_stat_lean()`: red→atk, orange→hp,
yellow/green→haste, cyan→def, blue→regen, purple→crit. lean_pct
varies by mode (7% normal → 15% prismatic). Stat lean applied in
`bot.recompute_stats` and shown in tooltip.

Materials applied in HUD inventory cells, Outpost inv, Shop inv.
Paperdoll bot rig stays clean (existing glow shader takes priority
on weapon slot).

### Weapon family expansion

58 new weapon items spanning 27 new base_types: hand_axe / war_axe /
battle_axe / broad_axe / executioner_axe / club / mace / morningstar
/ eveningstar / flail / dire_flail / hammer / giant_club / spear /
halberd / bardiche / scythe / greatsword / claymore / double_sword /
triple_sword / quarterstaff / lajatang / bullwhip / demon_whip /
ankus / cutlass. New manifest:
`tools/items_weapons_extended_manifest.json`. Item editor gets a
new "Weapons (extended)" tab. base_type_affixes entries authored
for every new family (axes lean strength+crit, polearms lean
crit+haste, 2H lean strength+stamina, lajatang/double_sword lean
haste+crit for dual-wield-style speed).

### Item secondary stats

items.json now carries optional `crit_chance`, `atk_speed_pct`,
`hp_regen` as DIRECT contributions (separate from rolled affixes).
Bot.recompute_stats reads them. 24 uniques retroactively get
secondary stats matching their lore (quick_blade +25% atk_speed,
spriggans_knife +15% crit / +15% atk_speed, salamander_hide
+1.5 HP/sec, etc). Item editor exposes sliders. sync_items.py
carries the fields through.

### Validation

`/grind 5 16` → 5/5 victories, ~50 loot/run, no script errors. Slot
audit 309/309 pass. Meta-rarity probability matches authored rates
(~2.5 ancient, ~0.25 primal, ~75 tinted across ~250 drops).

## Authoring portal + sanity pass — 2026-06-03

**Sanity-check pass.** Wrote `tools/check_biome_assets.py` to expand
every biome's `floor_*` / `wall_*` / `edge_overlay` / `sigil_set`
prefix references against actual files in `project/assets/tiles/`.
Caught **18 broken references across 7 biomes** — bare-stem entries
like `tree_1_yellow`, `boulder`, `crumbled_column`, `lava_0`,
`mangrove_1..3`, `mold_1/2`, `deep_water_*` that were used as
prefixes (which expand `entry + "_"`) but pointed at literal files
without the trailing underscore. Fixed by patching them to `@stem`
literal-tile syntax (the system already supported it). After patch:
all 24 biomes resolve cleanly. This is what the user reported as
biomes "drifting from their atlas."

**Authoring portal** (`tools/index.html`). Landing page that links
to atlas viewer + biome editor + item editor + new affix editor,
with badge states (live / soon) and a "sharing what you build"
section explaining the no-backend export-to-issue flow.

**GitHub Pages workflow** (`.github/workflows/pages.yml`). Stages a
clean `_site/` containing `tools/`, `project/data/`, and
`project/assets/tiles/`, plus a root `index.html` that redirects
into `tools/`. Publishes on push to main. Browser editors fetch
from `../project/data/...` so the relative paths just work in
both local-server and GitHub-Pages contexts.

**Affix / Enchant Editor** (`tools/affix_editor.html`). New
browser-based editor with:
- Sidebar list of all affixes
- Form fields: id, display name, stat dropdown (8 wired stats),
  color picker, applies_to list, tier values (5 columns colored
  by rarity), lore textarea
- Live preview card showing tier values as rarity-colored pills
- Auto-default color per stat (Strength→red, Crit→yellow,
  Haste→cyan, etc — matches the in-game flavor color story)
- Add/delete affix buttons
- Export downloads complete `affixes.json` for review/merge

## UI overhaul — 2026-06-03

Big chrome + inventory pass driven by a playtest report.

**OLED chrome.** Replaced the faint blue-tint backgrounds
(`Color(0.05, 0.05, 0.07)`, `Color(0.04, 0.04, 0.06)`) with pure
black across `ui_theme.gd`, `outpost.gd`, `main_menu.gd`,
`hud_chrome.gd`, `pause_menu.gd`, `video_options.tscn`,
`run_report.tscn`. Minimap backdrop is now fully transparent — its
containing panel's pure-black bg gives the visual frame.

**Branch picker as item-style cards.** Old picker was 96px tall
with cramped horizontal buttons. New layout: 220px tall, each
branch is a 168×168 vertical card with biome name (rarity-colored),
tier label, modifier list visible without hover, CR footer, and a
rarity-tinted halo (T1 white → T5 red). Tier rarity mapping:
T1 common, T2 uncommon, T3 rare, T4 epic, T5 legendary. Halo
strength scales with tier so high-tier branches feel "loaded."
Locked branches dim to 55% modulate. See
`outpost.gd::_make_branch_card`.

**Inventory filter chips** (`outpost.gd::_build_filter_chips`).
Slot dropdown (All / Weapon / Armor / Helm / Shield / Boots / Ring /
Amulet) + rarity dropdown (All / Uncommon+ / Rare+ / Epic+ /
Legendary) + "★ Favorites only" toggle. Re-renders the inventory
grid on change.

**Favorite/lock items.** Right-click an inventory cell to toggle
the favorite flag (`inst.favorite = true`). A gold star icon
overlays favorited cells. Favorited items skip auto-salvage
(`dungeon.gd::_maybe_auto_salvage`) and the shop's "sell all junk"
button. WoW lock-bag pattern.

**Shop screen** (`scenes/shop.tscn` + `scripts/shop.gd`).
Reachable via "🏪 Shop" button on Outpost. Two-column layout:
your inventory left, today's stock right. 6 rotating stock items
refresh every 15 real-time minutes (`SHOP_REFRESH_SECS = 900`).
Each refresh rolls a daily modifier from
`data/shop_modifiers.json` (8 modifiers: Weapon Day, Armor Day,
Trinket Day, Rare Collector, Legendary Seeker, Fire Sale, High
Demand, Scarcity). Modifier biases buy/sell prices and sometimes
stock quality. Sell price = 2× salvage × today's modifier.
Buy price = 10× salvage × modifier. Countdown label ticks each
second; auto-refreshes when the timer expires while the screen
is open. "Sell all common/uncommon" bulk button skips favorites
+ starter gear (rusty_dagger, tattered_hide).

**Save schema additions.** `state.shop = {last_refresh_ts,
stock, modifier_id}`. Forward-compat init in `_default()`.

## Horde density + pack-clustered spawns — 2026-06-03

## Horde density + pack-clustered spawns — 2026-06-03

Replaced uniform `4 + floor*2` random mob spawns with PoE-style
pack clustering. Floor 1 ~50 mobs, floor 6 ~150 — validated with a
2-run grind logging 535 / 436 kills.

**Spawn shape** (`dungeon.gd::_spawn_packs`). target_total = 40 +
floor*20. Spawned in packs of 6-12 same-id mobs around a leader.
Pack count = total / avg_pack_size, so floor 6 produces ~15-20
packs of ~10 mobs each. Same-id-per-pack is what makes a cluster
read as a "pack" visually; different packs roll different ids so
the floor still has variety.

**Pack leaders** (`_roll_leader_pack_tier`). Leaders re-roll for
modified-tier at elevated rates: 30% (T1) → 80% (T5) chance of
being magic/rare; within the modified pool ~85% magic / 15% rare.
Packmates are forced to PACK_NORMAL via the new `force_pack_tier`
arg on `_spawn_specific` so the leader is always the visual
centerpiece.

**Loot rebalance** (`_maybe_drop_item`). Normal drop chance
15% → 5% so 100+ kills don't flood the inventory. Magic leaders
drop at 30%, rare leaders at 100% with bonus drop count (×2),
bosses + minibosses unchanged at 100%. Total floor loot stays
~10-15 items despite 10× the kills — validated 12/11 loot on 94/125
kill floors.

**Persistent outlines** (`enemy.gd::apply_persistent_outline` +
extended `threat_outline.gdshader`). The shader now takes an
optional `pack_color` uniform that overrides the threat color
table. Boss = red, miniboss = orange, rare = gold, magic = blue.
Threat tier still drives outline thickness so a deadly rare reads
brighter than a trivial rare.

**Perf**. Headless 16× grind shows ai_us 300-1100µs (well under
budget — was hitting 12700µs during the original thundering-herd
bug). Pack clustering helps: aggro range cap (8 cells), staggered
repath, 3-paths-per-frame cap, and sticky-target combat all stay
within their existing ceilings. Mob render cost scales linearly
with count — 100-150 enemy sprites at 32×32 is still trivial on
the M3 Pro baseline.

## Enemy variation pass — 2026-06-03

PoE-style pack-tier system on top of the existing champion roll.
Cheap visual variety knob — same enemy IDs, dramatically different
read on screen.

**Per-spawn visual jitter** (`dungeon.gd::_spawn_specific`). Every
non-boss/non-miniboss/non-champion enemy multiplies its `visual_scale`
by `randf_range(0.85, 1.15)` at spawn. A cluster of 6 worker ants no
longer reads as "clones."

**Pack tier roll**. After the champion roll, non-boss enemies roll
for magic/rare. Rates scale with branch tier:
- T1: 1.2% rare / 7% magic
- T5: 6% rare / 35% magic

Magic = +20% HP / +10% ATK / 1 random mod / blue tint + small aura /
"Hasted Goblin"-style display name.
Rare = +60% HP / +30% ATK / 2 random mods / yellow tint + larger
pulsing aura / "Hasted Vicious Goblin" prefix.

**Mods** (`data/monster_mods.json`):
- hasted (+35% atk speed, +30% move speed)
- tough (+50% HP, +25% DEF)
- vicious (+35% ATK)
- vampiric_pack (vampiric flavor tag → Bot's existing tag pipe)
- regenerating (stub — needs enemy-side regen tick, not yet wired)
- stalwart (+60% DEF, +15% HP)

Mod payload merges into stat init *before* the pack HP/ATK
multipliers so the percentages compose cleanly. Flavor tags route
through `Enemy.combat_defense_tags()` so existing Bot-side mechanics
(vampiric leech back from bot when it hits a vampiric pack mob)
fire automatically.

**Visual signature** (`enemy.gd::apply_pack_visuals`). Multiplicative
modulate on the rig (preserves champion's existing pinkish wash) +
LootDrop glow texture as an aura sprite at z=-2 with a per-tier
pulse rate. Magic pulses every 1.6s, rare every 1.0s.

**Logging**. `[pack]` log line per spawn during instrumented runs
(`grind`, `benchmark`) so we can audit roll rates and mod
distribution. Two-run grind validation: 61 pack spawns, every mod
fired at least once, no errors.

Deferred followups in TODO.md: pack auras affecting nearby allies,
unique-tier hand-authored monsters, enemy regen tick path,
reflective/thorns mods.

## Playtest fixes — 2026-06-02

## Playtest fixes — 2026-06-02

Four reported issues from a long live playtest, all shipped this beat.

**Bot squish over time.** After ~10 min of play the bot's sprite
gradually compressed to a few pixels vertically. Root cause was in
`actor.gd::_set_facing` — when an attack_lunge tween was in flight
(rig scale animating from 1.0 → 1.15/0.85 → 1.0 over ~0.18s), a facing
flip happening mid-tween would read `rig.scale` and snapshot the
transient pinched Y value into `SpriteFX.base_scale` via
`fx.update_base_scale(rig.scale)`. The next tween then "rested" at
the corrupted base, and the rot accumulated over thousands of
flip-during-attack events. Fixed by rebuilding the rest pose from
`visual_scale` + `_facing_x` instead of reading the live transform:

    var rest := Vector2(visual_scale * _facing_x, visual_scale)
    rig.scale = rest
    fx.update_base_scale(rest)

Lesson: never snapshot a Node2D transform into a "base" variable
while a tween targeting that transform is running. Always build the
authoritative resting state from canonical inputs.

**Rings collapsed to ring + amulet.** Old layout had `ring1` + `ring2`
+ `amulet`. The HUD's single-tap equip flow couldn't surface "which
ring slot do I fill" cleanly — once both were full, equipping a third
ring silently replaced ring1, looking broken. Collapsed to one `ring`
slot (amulet still fills the trinket role). Save migration in
`save_state.gd::_migrate` promotes ring1 → ring and pushes ring2's
item to inventory if both were full. Touches: `save_state.gd`,
`bot.gd`, `outpost.gd`, `hud_chrome.gd`, `tools/inject_save.py`.

**Rarity-tinted weapon overlays.** Equipped weapons all rendered with
their stock sprite color regardless of rarity, so a gold legendary
sword looked indistinguishable from a common blue scimitar once on
the bot. Added `bot.gd::_apply_rarity_decor` — modulates the overlay
sprite by `lerp(white, rarity_color, strength)` (common 0% → legendary
50%) and attaches a soft pulsing radial halo behind epic+ weapons.
Mirrored on every UI surface via
`paperdoll_renderer.gd::_apply_rarity_modulate` so inventory /
outpost / main-menu paperdolls all match. Cheap (<10 nodes per rig),
reads at dungeon zoom, doesn't blow out the silhouette.

**Source-floor tier caps loot rarity.** A floor-2 wizlab portal was
showering the bot with T5 legendaries because
`dungeon.gd::_pick_loot_id` keyed on the portal biome's tier (elf=T2,
vaults=T4, zot=T5) rather than the home branch's. Added
`_source_tier()` (always returns the home branch tier, ignoring portal
overrides) and `_clamp_rarity_to_tier()` (T1=uncommon cap, T2=rare,
T3=epic, T4+=legendary). Both `_roll_rarity` and `_roll_rarity_with_bias`
clamp through it now, so enemy drops, chest contents, and vault loot
marks all respect the home branch's progression. Followup TODO: PoE-
style low-tier legendaries with capped stats but unique mechanics, so
the rarity cap doesn't kill aspirational drops at low floors.

## Tuning beat — 2026-06-02

First data-driven tuning pass. The pinned-experiment re-run (220 grinds,
3.5h wall-clock) produced unambiguous numbers across 7 affix-vs-affix
permutations and 3 tier cliff investigations. Two changes shipped:

### 1. Regen affix capped at 3 HP/sec

`data/affixes.json` regen tiers `[1, 2, 4, 6, 10]` → `[1, 2, 3, 3, 3]`.

Pinned-vaults-T4 matrix showed regen5 median HP-lost = 0 (next-best
affix at 84-114). The +10 HP/sec at legendary exceeded the chip-damage
rate of T4 encounters, making it a one-affix free pass on attrition.
Cap at 3 HP/sec keeps regen as a real defensive option (heals between
fights, supplements fountains) without trivializing combat.

### 2. TIER_SCALE softened at T4-T5

`scripts/constants.gd::TIER_SCALE` `[1.0, 1.4, 2.0, 3.2, 5.0]` →
`[1.0, 1.4, 2.0, 2.7, 4.5]`.

Pinned cliff investigations showed 96% wins at T1 vs 0% at both T4 and
T5. The 2.0→3.2 jump at T3→T4 (+60%) was the brick wall — no in-between
difficulty. Softened to T3→T4 +35%, T4→T5 +67%. Goal: T4 should be
winnable with affixes (~10-20% win rate on un-armored bots), T5 still
requires gear progression.

**Update 2026-06-02 (T2/T3 cliff fill-in)**: ran the deferred T2/T3
N=50 cliff and the data corrects this hypothesis. The actual cliff
is **T2→T3 (86% → 8%)**, not T3→T4. T4/T5 are correctly gear-gated;
softening them was tweaking the wrong tiers. Next patch should target
`TIER_SCALE[2]` (T3) — proposed 2.0 → 1.8. Full analysis in
`docs/balance-findings-2026-06-02.md` "T2/T3 cliff fill-in" section.
Pending human playtest confirmation.

### Validation outcome

40-grind smoke test ran post-patch. Mixed result:
- ✅ **TIER_SCALE softening worked partially.** Avg floor reached ticked
  up across affixes (regen 4.60→5.10, stamina 4.50→4.90), runs are
  ~30% longer (60s→80s), strength5 HP-lost dropped 148→92.
- ❌ **Regen5 median HP-lost still 0.** The 10→3 HP/sec cap reduced
  stacking but didn't dethrone single-affix dominance. Implication:
  vaults T4 chip damage is ~1 HP/sec, not 3-5 as assumed.
- ❌ **No wins at T4 for any affix.** Predicted 1-3 wins didn't happen.
  T4 boss difficulty is the real bottleneck, not just enemy scaling.

Per "don't tune-spike now, iterate later" guidance, both patches stay
shipped — they're directionally correct improvements over the original
values. Carrying forward:

- **Regen mechanic redesign** as a future beat (scale with missing HP,
  or disable during combat ticks). Tier-value tweaks alone won't fix
  single-affix dominance.
- **T4 boss difficulty** is the real wall. Either gear is required
  (likely intended) or boss-tier multiplier needs separate scaling
  from regular enemy multiplier.

See `docs/balance-findings-2026-06-02.md` for the full analysis.

## Playthrough harness — 2026-05-21

The balance pipeline tests fixed builds against fixed challenges. A
**playthrough** simulates the full game loop: starter gear → dungeon →
loot → equip → upgrade → advance → repeat, until tier 5 boss is killed
or run cap is hit. Lets us calibrate per-tier playtime + difficulty
curve from data.

### Skill: `/playthrough [--equip POLICY] [--upgrade POLICY] [--advance POLICY]`

Three configurable policies decide what the simulated player does
between runs:

**Equip policies** (`.claude/skills/playthrough/policies.py`):
- `score_weighted` — `ATK*3 + DEF*5 + HP*0.5 + Σ(affix_value)`. Mirrors
  what `bot.recompute_stats` actually values. Default.
- `pure_dps` — Max ATK on weapon, max DEF on every other slot.
- `rarity_first` — Highest rarity wins, tiebreak ATK+DEF+HP.

**Upgrade policies**:
- `round_robin` — Buy cheapest affordable upgrade. Default.
- `combat_first` — Prioritize combat_training + toughening + conditioning.
- `hp_first` — Prioritize conditioning + toughening for survival.

**Advancement policies**:
- `strict` — Try highest-tier unlocked branch. Default (matches game's
  unlock rule).
- `cautious` — Need 3 wins in a row at current branch before advancing.
- `greedy` — Try next tier immediately; retreat one tier if win rate
  < 30% over last 5 attempts.

### Implementation

`playthrough.py` reads/writes `botter_save_debug.json` directly between
runs. Each iteration:
1. Apply advance policy → pick next branch
2. Apply upgrade policy → spend gold (mutates save)
3. Apply equip policy → swap gear (mutates save)
4. Call `balance.run_grind` for one run with `BOTTER_SEED` and
   `BOTTER_NO_INVINCIBLE=1` (so death is real)
5. Re-read save (Godot mutated inventory/level/gold during the run)
6. Record per-tier metrics

Stops when `bosses_killed[<any T5 branch>] > 0` or `--max-runs` hit.

### Output

Per-run line + per-tier summary table:
```
tier  runs  wins  win%   sim_s     last_floor  bosses_killed
1     5     5     100%   142.3     6           1
2     8     6     75%    268.4     6           1
3     14    8     57%    498.1     6           1
4     22    11    50%    827.5     6           1
5     31    9     29%    1284.6    6           1
```

`sim_s` is grind seconds at 16x. Real-time playtime ≈ `sim_s × 16`.

Logs to `logs/playthrough/<ts>_<equip>_<upgrade>_<advance>.log` plus
one summary line in `logs/playthrough/index.jsonl`.

## Visual-effect suite — 2026-05-21

Five shaders shipped, all wired through the new `VideoSettings.gfx`
toggle store + UI. Each effect can be toggled per-effect from the
Video Options menu. Env-var overrides (`BOTTER_NO_<EFFECT>=1` /
`BOTTER_FORCE_<EFFECT>=1`) take precedence so dev A/B testing still
works.

### Settings architecture

`VideoSettings` (`scripts/video_settings.gd`):
- New `gfx` sub-dict with per-effect bools (color_grade, heat_haze,
  water_shimmer, memory_desat, threat_outlines, light_cookies, ench,
  shadow, bloom)
- Quality presets: `GFX_PRESET_HIGH/MEDIUM/LOW` (currently unused as
  presets but in place for future quick-set buttons)
- `is_effect_enabled(effect)` reads env override → settings, with
  forward-compat merge for existing saves

`scripts/video_options.gd`:
- Programmatically appends "Graphics effects" header + one CheckBox
  per effect to the existing options form. Toggles save+apply
  instantly. New effects auto-show without .tscn edits.

### The five effects

**Color grading** (`color_grade.gdshader`) — full-screen LUT-style
post-process. Tint, saturation, contrast, brightness, vignette + tint,
mix amount. CanvasLayer 60. **All 24 biomes now have curated grades.**

**Heat haze** (`heat_haze.gdshader`) — per-cell sine-wave UV warp on
T_LAVA tiles, covers cell + 2 rows above. Vertical falloff. Slight
chromatic refraction.

**Water shimmer** (`water_shimmer.gdshader`) — per-cell horizontal flow
+ wobble on T_WATER tiles. Subtle blue tint fakes water absorption.
Cheaper than heat haze (single sample).

**Memory desaturation** (`tile_visibility.gdshader` extended) — tiles in
fog memory render with reduced saturation. Reads `FogSystem.vis_texture`
which encodes 0/0.5/1.0 for unseen/memory/visible. Saturation shifts
are far less perceptually jarring than the alpha shifts that caused the
abandoned per-cell "ticking" artifact.

**Threat outline** (`threat_outline.gdshader`) — 4-direction neighbor
sample around enemy sprites. Tier 0 (trivial) = no outline, 1 = faint
white, 2 = orange, 3 = red. Pulse rate uniform. `dungeon._apply_threat_auras()`
classifies each enemy by hits-to-kill + enemy-damage-as-fraction-of-bot-HP.

**Light cookies** (extended `light_spec.gd`) — optional `cookie` field on
spec dicts overrides the default radial PointLight2D texture. Four
starter cookies authored programmatically:
`assets/lights/cookie_{stained_glass,prison_bars,web,stardust}.png`.
Currently wired: `sigil` → stained glass, `firefly` → stardust.

**Actor shadow** (`scripts/actor_shadow.gd`, shipped 2026-06-02) —
draw_colored_polygon ellipse at +10px under every actor's rig (z=-1).
Plants the bot + enemies on the floor visually instead of letting them
float on the tile. Toggleable via `gfx.shadow`; `BOTTER_NO_SHADOW=1`
disables. Mirrors DCSS `tilesdl.cc`'s PSE_SHADOW slot but uses a flat
oval (cheaper than per-figure shadow art for an idle game).

**HALO** (shipped 2026-06-02). Per-god tinted radial glow at rig
z=-2 (below shadow). 22 god colors in `bot.gd::_HALO_COLORS`. Soft
1.6s sin-pulse alpha. Spawned from `_apply_halo(god)` inside
`grant_blessing`; cleared by `clear_blessings`. Also adds `blessed`
status so it shows up in the WoW-style buff bar.

**Directional facing** (Actor `_facing_x`, shipped 2026-06-02).
Bot mirrors based on movement direction (`step_movement` flips when
`abs(dir.x) > 0.5`) AND on attack target side (`attempt_attack`
flips before the weapon swing). DCSS sprites are right-facing
default → `_facing_x = -1.0` flips via `rig.scale.x`. Composes with
`visual_scale` so big-creature scale and facing don't clobber each
other. Side benefit: solves the "weapon swings across body when
target is on the wrong side" cosmetic — bot now always faces the
target before swinging, so the held weapon appears on the swing side.

**Universal Pause menu** (`scripts/pause_menu.gd`, shipped 2026-06-02).
Esc-key opens a centered panel at any time during live play. Options:
Resume / Video Settings / Back to Main Menu / Abandon Run (dungeon
only) / Quit Game. Pauses the SceneTree while open. Mounted at
`main.gd::_install_pause_menu` after auto-grind/screenshot detection
so headless modes never paint a UI. `set_context(screen_name)` is
called from `_swap` so context-dependent buttons (Abandon, Back to
Main Menu) hide where they don't apply. Re-uses the existing
`scenes/video_options.tscn` for the settings sub-screen.

**WoW-style buff/debuff bar** (`hud_chrome.gd::_build_buff_bar` +
`update_buffs`, shipped 2026-06-02). Top-of-screen row of 36×36
square icons + countdown text, centered above the dungeon canvas
(excluding sidebar). Pool of 12 cells, hidden until populated. Fed
from `bot.active_statuses()` each frame; sorted by status `z`
(important effects leftmost). Persistent buffs (blessed, etc.)
show no countdown. Per user pref, this runs ALONGSIDE the on-sprite
ENCH layer for the bot — both layers visible.

### Godot 4.6 SCREEN_TEXTURE deprecation

Both `color_grade.gdshader` and `heat_haze.gdshader` initially used the
deprecated `SCREEN_TEXTURE` builtin and threw `SHADER ERROR` when first
exercised. Fixed by declaring `uniform sampler2D screen_tex :
hint_screen_texture, repeat_disable, filter_linear` and reading from
`screen_tex` instead. `water_shimmer.gdshader` was authored correctly
from the start.

## Heat haze shader — 2026-05-21

Per-cell vertex-distortion shader on T_LAVA tiles. Sine-wave UV warp
with vertical falloff (strongest at lava, fades upward). Slight
chromatic offset fakes refraction. Makes lava feel hot — currently
it's a static red sprite.

`assets/heat_haze.gdshader` + `map_renderer.gd::_attach_heat_haze`.
Each lava cell gets one Sprite2D covering itself + 2 rows above on
`_heat_haze_layer` (z_index 50). Skipped entirely when no lava cells
exist. Gated by `BOTTER_NO_HEAT_HAZE=1`.

**Important**: Both this shader and `color_grade.gdshader` use Godot
4.6's required `hint_screen_texture` uniform pattern, NOT the legacy
`SCREEN_TEXTURE` builtin. Initial implementation hit a `SHADER ERROR`
when the experiment chain ran into a forge lava-bridge vault — fixed
by declaring `uniform sampler2D screen_tex : hint_screen_texture`.

## Color grading shader — 2026-05-21

Per-biome post-process to elevate the visual language without changing
gameplay. Existing `CanvasModulate` (flat per-channel tint) was barely
perceptible; the new `ColorGrade` is a full-screen LUT-style shader.

### Pipeline

`assets/color_grade.gdshader` — 6 uniforms:
- `tint` (vec3, multiplied with base color)
- `saturation` (around Rec.709 luma)
- `contrast` (around mid-grey 0.5)
- `brightness` (additive)
- `vignette` + `vignette_tint` (corner falloff to a custom color)
- `mix_amount` (cross-fade for biome transitions)

`scripts/color_grade.gd` — `ColorGrade` CanvasLayer (layer 60, between
fog and HUD). Reads `current_biome.color_grade` dict, pushes uniforms.
`transition_to(grade, 0.4)` cross-fades via mix-amount tween — no
hard pop on biome change.

`dungeon.gd` instantiates next to `ambient_modulate`. Gated by
`BOTTER_NO_GRADE=1` env var (matches existing `BOTTER_NO_*` perf
A/B knob pattern).

### Curated biomes (8/24)

`biomes.json` extended with `color_grade` field for:

| Biome   | Mood                       | Tint            | Sat  | Vignette       |
|---------|----------------------------|-----------------|------|----------------|
| dungeon | Cool stone-vault           | 0.95/0.97/1.05  | 0.85 | 25% blue-black |
| lair    | Warm lush green            | 1.0/1.08/0.95   | 1.15 | 20% green      |
| swamp   | Murky desaturated          | 0.95/1.0/0.78   | 0.75 | 30% olive      |
| crypt   | Cold washed-out blue-grey  | 0.85/0.92/1.05  | 0.65 | 40% deep blue  |
| tomb    | Sandy sun-bleached         | 1.10/1.05/0.85  | 0.80 | 25% sand       |
| forge   | Hot saturated red-orange   | 1.20/0.95/0.75  | 1.20 | 30% blood-red  |
| glacier | Cold blue-cyan, frosted    | 0.82/0.95/1.15  | 0.75 | 22% deep blue  |
| slime   | Sickly green murky         | 0.90/1.10/0.80  | 1.05 | 25% green      |

The remaining 16 biomes fall through to identity (no-op). Extend on
review.

### Perf

One full-screen sample per pixel, ~6 instructions, no expensive math.
Sub-microsecond impact. Far cheaper than the existing 24-light fog
ray-march.

## Experiment infrastructure hardening — 2026-05-21

After a sweep died mid-experiment when polling commands SIGTERM'd
the parent shell, the chain was hardened:

- **`tools/run_experiment.sh`** — wraps any command in nohup + double-fork
  subshell (macOS lacks setsid). Survives parent SIGTERM. Writes the
  experiment's PID to `logs/balance/.pids/<name>.pid` and exit code to
  `<name>.status` on completion. Output streams unbuffered to
  `logs/balance/<name>.log`.
- **Sweep durability** — `sweep.py` now persists a `sweep_partial_variant`
  entry to `index.jsonl` after each variant completes, so a kill mid-
  experiment loses at most one variant of data.
- **`balance.run_grind` timeout** — bumped from 60s/run to 90s/run (min
  120s) after seeing 60s clip live grinds mid-floor-4 on tanky builds.

### Standard pattern for long experiments

```bash
# Stage script (always use python3 -u for line-buffered output)
cat > /tmp/myexp.sh <<'EOF'
python3 -u tools/my_experiment.py
EOF

# Detach + survive parent shell
tools/run_experiment.sh my_experiment bash /tmp/myexp.sh

# Monitor without polling
tail -f logs/balance/my_experiment.log
cat logs/balance/.pids/my_experiment.status   # exists when done
```

### Currently in flight (2026-05-21 17:00)

Job chain queued for ~6 hours unattended:
- `regen5_backfill` — DONE (15/15 grinds, regen5 final win rate 40%)
- `full_suite` — running, mid Experiment B (cliff investigation
  N=50 × 3 branches; ~115 min remaining)
- `playthrough_trio` — queued, waits on full_suite. Three policy combos:
  score+round_robin+strict, pure_dps+combat_first+strict,
  score+hp_first+cautious. ~2-3 hr.
- `color_grade_showcase` — queued, waits on playthrough_trio. Captures
  16 screenshots (8 biomes × with/without grade) for visual A/B.

## Balance pipeline — 2026-05-20

The bot plays itself, so balance experiments are unusually tractable. New
toolchain enables headless A/B comparisons across deterministic seed
sequences — settle "is X stronger than Y" questions in minutes instead
of hours of human playtest.

### Skills

- **`/equip <build>`** (`.claude/skills/equip/`) — write a loadout to
  the debug save without launching Godot. Shorthand syntax:
  `weapon=demon_blade,Strength5,Crit4 armor=crystal_plate,Stamina5
   level=30 branch=forge`. Validates against items.json / affixes.json
  / biomes.json. Affix shorthand `<Name><Tier>` looks up the actual
  value from affixes.json (Strength5 → 18 ATK).
- **`/duel <a> -- <b> [-N 20]`** (`.claude/skills/duel/`) — A/B test two
  builds across the same N seeds. Same world, different gear. Returns
  paired comparison: win rate ± 95% Wilson CI, avg floor, avg kills,
  avg elapsed, damage by weapon. Writes per-run logs + summary line to
  `logs/balance/index.jsonl`.
- **`/sweep --slot W --values @legendary [-N 10]`** (`.claude/skills/sweep/`)
  — vary one parameter across many runs. Two flavors:
  - Item sweep: `--slot weapon --values demon_blade,runed_warsword,...`
    or `--values @legendary` / `@epic_armor` / `@helm`.
  - Affix sweep: `--affix crit --tiers 1,2,3,4,5`.
  Returns ranked table. Uses same seed sequence per variant for paired
  comparison.

### Foundation

- **Seedable RNG** (`BOTTER_SEED=<int>`). `dungeon.gd` seeds both its
  `RandomNumberGenerator` and Godot's global rng (`seed()`). Each floor
  build re-seeds the global stream from world rng so combat doesn't
  consume world entropy between floors. **Same seed + same save = byte-
  identical floor sequence + byte-identical combat.** `[run] start ...
  seed=N` stamps the seed for traceability.
- **`tools/inject_save.py`** — JSON build spec → `botter_save_debug.json`.
  Validates item ids / affix ids / branch ids. Affix shorthand
  `["strength", 5]` reads tier-5 value from affixes.json automatically.
  Item shorthand `"demon_blade"` = `{"base_id": "demon_blade"}`.
  Flags: `--reset`, `--dry-run`, `-` for stdin. Routes everything
  through the debug save so playtests are untouched.
- **`[combat]` log tag** in `actor.gd::attempt_attack`. Per-attack
  structured line: `atk=<id> def=<id> wpn=<weapon_id> raw=N crit=0|1
  dealt=N def_hp=N boss=0|1 mb=0|1`. Gated on `GrindLog._enabled` so
  playtests don't spam. Bot/Enemy override `combat_label()` and
  `combat_weapon_id()` for clean attribution. ~250 events/run at 16x.
- **`tools/parse_grind.py`** — shared parser, returns dataclasses
  (`GrindResult`, `RunResult`, `FloorResult`, `CombatEvent`). Used by
  every balance skill. CLI mode for ad-hoc inspection:
  `python3 tools/parse_grind.py logs/grind/<latest>.log --combat`.
- **`tools/balance.py`** — harness for skill scripts.
  `run_grind(seed, runs, speed, label, invincible)` drives Godot
  headless, returns when COMPLETE line appears. `inject(spec)` wraps
  inject_save. `append_index(entry)` appends one JSON line to
  `logs/balance/index.jsonl`. Sets `BOTTER_NO_INVINCIBLE=1` by default
  so balance experiments produce real win/loss signal.

### `BOTTER_NO_INVINCIBLE=1`

`main.gd` sets `DebugJump.bot_invincible = true` for grind mode by
default (so /grind reaches floor 10 reliably for procgen audit).
Balance skills set `BOTTER_NO_INVINCIBLE=1` to opt out, so build
differences actually translate to win/loss outcomes. Pass
`--invincible` on duel/sweep to override (useful when you only care
about clear time / damage output, not survival).

### Determinism caveats

Combat IS deterministic under `BOTTER_SEED` — same seed + same build
= identical kills, identical damage rolls. This is reproducibility,
not a bug. It means seed sensitivity matters: a 20-run duel covers 20
different floor sequences, not 20 random combat samples. If you need
combat variance, set seeds to a wider range (e.g. `--seed-base 100
-N 50`).

Different builds on the same seed will diverge floor-by-floor as
combat speed differences propagate (build A clears faster, lands on
floor 2 with different HP, fights the same vault but with different
aggro state, etc). The pairing is "same world, different gear" — not
"same fight, different gear" — but that's what we want for build
comparison.

### Where data lives

```
logs/balance/
├── index.jsonl                                     # one line per experiment
├── 20260520-180312_grind_duel_demon_s1.log         # per-run log
├── 20260520-180345_grind_duel_demon_s2.log
└── 20260520-180712_grind_sweep_arc_blade_s1.log
```

`index.jsonl` schema: `{ts, kind, label, params, a, b}` for duels,
`{ts, kind, label, params, ranked: [...]}` for sweeps. Query with `jq`.

### Findings from first production runs (2026-05-20)

210 grinds across two experiments, ~165 min wall-clock. Full writeup
in `docs/balance-findings-2026-05-20.md`. Headlines:

- **Strength is undertuned at endgame.** +18 ATK (legendary) is a
  wasted slot — 0 wins out of 15 in the 6-affix matrix. Killing isn't
  the bottleneck; chip damage is.
- **Crit has the same problem.** More crits = more kills, same death
  floor. Crit5 + Strength5 tied for worst HP-lost.
- **Regen is overtuned.** +10 HP/sec (legendary) had median HP-lost = 0
  — the bot heals faster than enemies damage it at vaults T4. Cap or
  rate-limit needed.
- **Floor 4-5 cliff is real.** 34-37% of all deaths happen on these
  floors across both experiments. Likely floor-3 miniboss damage with
  no fountain pre-floor-3.
- **Stamina/Agility balanced about right.** Haste competitive with
  Strength.

Methodology lessons: HP-lost is 20× higher-resolution than win-rate
at small N. Use N=30+ for categorical signal. Same-seed paired
comparison works correctly.

See `docs/balance-pipeline.md` for the toolchain, `docs/balance-
findings-2026-05-20.md` for the analysis writeup.

## Items pipeline — 2026-05-20

The full gear catalogue moved from a 75-item hand-rolled list to a manifest-
driven 234-item pool spread across all 7 equip slots. Workflow is editor →
export → sync script → live data.

### What shipped

**7 manifest files under `tools/`:**

| File | Slot | Items | Coverage |
|---|---|---|---|
| `items_manifest.json` | weapon (1H sword) | 47 | 55% of available DCSS sword sprites |
| `items_helms_manifest.json` | helm | 32 | 46% |
| `items_armor_manifest.json` | armor | 47 | 39% (rest is `_new`/`_old` art-revamp dupes) |
| `items_shields_manifest.json` | shield | 27 | 38% |
| `items_boots_manifest.json` | boots | 20 | 100% of base feet sprites (DCSS itself sparse) |
| `items_rings_manifest.json` | ring | 35 | 71% |
| `items_amulets_manifest.json` | amulet | 26 | 63% |

Each item carries `id`, `name`, `slot`, `rarity`, `tile`, `atk`/`def`/`hp`,
plus new fields: `item_tier` (1-5), `base_type` (DCSS-derived), `flavor_tags`
(future-mechanic intent), `lore`, `drop_weights[T1..T5]`, `unique`.

Base types are sourced from DCSS `item-prop.cc` (armor AC values, weapon
damage/speed) and `item-prop-enum.h` (jewellery enum). Stat bands respect
the project number ceiling (~1500 HP / ~300 ATK / ~100 DEF endgame).

Total uniques: 39 across all slots, each with a documented
`future_mechanic` payload (lifesteal, freeze chance, set bonuses, etc.).

### `tools/item_editor.html` — slot-tabbed editor

Browser tool. Tabs: 1H Swords / Helms / Armor / Shields / Boots / Rings /
Amulets. Each tab loads the matching manifest, shows tier-grouped item
cards with sprite previews, drop-weight bars, and rarity pills. Click a
card to edit: name / base type / item tier / rarity / atk-def-hp /
flavor-tag toggles / drop-weight sliders / lore. Sprite picker offers
slot-aware filters (e.g. helms tab: All / Hats-Caps / Helmets / Artefacts).
**⬇ Export** downloads `items_<slot>.json` for sync.

Serve via `python3 -m http.server` from repo root, visit
`http://localhost:8080/tools/item_editor.html`.

### `tools/sync_items.py` — manifest → items.json + sprite copy

CLI:
```
python3 tools/sync_items.py                    # full sync (all 7 manifests)
python3 tools/sync_items.py items_armor.json   # partial sync from editor export
python3 tools/sync_items.py --dry-run          # preview, no writes
python3 tools/sync_items.py --prune-legacy     # drop items.json entries lacking base_type
```

What it does:
1. Walks each manifest, finds the source PNG under `dcss/Dungeon Crawl Stone Soup Full/` or `Supplemental/`.
2. Copies into `project/assets/tiles/items/<stem>.png` (inventory icon).
3. For `weapon/armor/helm/shield/boots`, also copies into
   `project/assets/tiles/player/<slot-dir>/<stem>.png` (paperdoll overlay).
4. Skips copies if destination has identical content (md5 dedup).
5. Merges into `project/data/items.json` by `id` — replaces matching IDs,
   preserves non-manifest items unless `--prune-legacy`.
6. Sorts items by slot → item_tier → id for stable diffs.
7. Reports inserts / updates / prunes / orphans.

Item IDs are the merge key. New schema fields are added on update;
non-manifest items keep their original shape.

### Drop-weight integration in `dungeon.gd`

New `_pick_loot_id(rarity)` helper at `dungeon.gd:1269`:
- Filters items by `drop_weights[branch_tier-1] > 0` for the current
  biome's tier (tier read from `current_biome.tier`).
- Weight-picks within the rarity tier.
- Excludes items already in `run_dropped_uniques` if they're flagged
  `unique: true`. Tracker resets on run start.
- Falls back to flat weight 1 for legacy items without `drop_weights`,
  so any non-manifest items still drop at all tiers until covered.

Wired into 3 loot paths:
- `_maybe_drop_item` (enemy kill drops)
- `_apply_vault_results` (vault loot marks)
- `_on_chest_opened` (chest contents)

`offline_progress.gd::_roll_loot` got the same `drop_weights[tier-1] > 0`
filter so the "While You Were Away" pool respects branch tier too.

### Save state schema

`save_state.gd::_default()` reserves `ring1`, `ring2`, `amulet` slots in
the `equipped` dict (null defaults). Equip routing (added 2026-06-02):
items have `slot=="ring"` but the equipped dict uses `ring1`/`ring2`.
`outpost.gd::_resolve_equip_slot` and `bot.gd::equip_from_inventory`
both pick `ring1` if empty, else `ring2`, else replace `ring1`. Stats
are summed by the existing `equipped.keys()` defensive iteration in
`bot.gd::recompute_stats` — no per-slot wiring needed. No paperdoll
work — DCSS `tiledoll.cc` confirms jewellery is never rendered on the
doll (categories: BODY/HAND1/HAND2/BOOTS/LEG/HELM/ARM/CLOAK/HAIR/BEARD).

### Migration outcome

Before: 75 items, hand-rolled, all using flat-rarity drop logic.
After:  234 items in `project/data/items.json` (387 sprite assets copied),
        14 legacy axe/claymore entries pruned (their slots have no manifest yet),
        drop_weights live in 3 loot paths + offline simulation,
        starter gear (rusty_dagger, tattered_hide) preserved with new
        sprites and added schema fields.

Validated: 3-run grind (16× speed), all victorious, 56 loot pickups
across 15 floors, zero stalls, zero errors. Loot rolls drew from items.json
across T1 (dungeon, lair) through T5 (pandemonium, tomb) biomes.

### Iteration workflow now

1. Open `tools/item_editor.html` (any slot tab)
2. Edit stats, drop weights, sprites, lore — hit ⬇ Export
3. Drop the export into the chat / pass to `python3 tools/sync_items.py <export.json>`
4. Reload Godot — items.json + sprite assets are in sync

`tools/items_manifest.json` (and its 6 siblings) are the source of truth
for the editor. Direct edits to those manifest files also flow through
`sync_items.py` on full-sync.

### What's not yet wired

- **Most per-tag mechanics** — 13 tags wired 2026-06-02. Two pipes:
  weapon tags via `combat_weapon_tags()` (attacker side) and worn
  tags via `combat_defense_tags()` (defender side; iterates armor/
  shield/helm/amulet/ring1/ring2/boots).
  Attacker-side: `vampiric` (8% lifesteal), `precision` (anti-streak
    +5%/swing crit, cap +50%), `fire` (3-tick burn DoT 4%/tick),
    `holy` (+50% vs HOLY_HATES undead/demon), `dragon_bane` (+50%
    vs DRAGON_HATES dragon/wyrm/drake), `cold` (15% freeze + 20%
    bonus vs frozen), `poison` (4-tick DoT 3%/tick), `brutal`
    (+25% vs ≤30% HP).
  Defender-side: `harm` (+25% damage dealt and taken), `thorns`
    (15% post-defense damage returned to attacker), `reflective`
    (10% chance to fully negate hit), `vitality` (+1 HP regen/sec),
    `rage` (+5% atk/kill, 6s window, cap +30%),
    `thunderous` (boots; on hit, 50% raw to one adjacent live actor
    via `_find_adjacent_actor`).
  `take_damage(raw, attacker)` now optionally takes the attacker so
  thorns can return damage. DoT generalized via `_apply_dot_status()`
  — `add_burn`/`add_poison` ride on it.
  Validated 2026-06-02: vampires_tooth +0.38 floors at vaults T4;
  eos vs bloodbane at crypt confirms holy 1.504× via combat log
  (raw=182 vs lich, raw=121 vs rat). Other tags currently route to
  affix-bonus stats
  (documented in `docs/items-plan.md`). Real mechanics (lifesteal, fire DoT,
  freeze chance, dragon-bane, set bonuses) need per-tag wiring in
  `actor.gd`. None implemented yet.
- **2H weapons / axes / maces / staves manifests** — the 14 legacy weapons
  pruned in this pass (claymores, war swords, axes, cleavers) deserve
  their own manifests. DCSS has plenty of sprites for these
  (`spwpn_glaive_of_prune`, `urand_wrath_of_trog`, `spwpn_scepter_of_torment`,
  etc.). Same workflow as 1H swords.

## Gameplay loop overhaul — 2026-05-15 (whole loop rebuilt)

Marathon session. Implemented all 10 beats of `docs/gameplay-loop-plan.md`
plus a smooth-fog rewrite, paperdoll renderer, three new commit-worthy
visual reworks. The play loop is now Melvor-idle-shaped: pick branch →
clear bosses → unlock the next tier → repeat with random per-deploy
modifiers spicing each run.

### What's new

**Affix system (was 30 → now 6, all combat-wired):**
- Strength (+ATK), Stamina (+HP), Agility (+DEF), Regen (+HP/sec), Crit
  (+%), Haste (+%atk speed). No prefix/suffix split. `applies_to: ["any"]`
  on all 6.
- `actor.gd` rolls crit on every attack (1.5× multiplier on success).
- `attack_interval` is per-actor mutable; bot's = `0.6 / (1 + haste/100)`.
  Capped at 200% haste so interval doesn't drop below 0.2s.
- Crit cap 75%. Regen flows from gear via `bot.recompute_stats`.
- Item names simplified: `Iron Sword [+Strength, +Crit]` instead of
  `Sharp Iron Sword of Butchery`.

**Branch tier system (5 tiers, doc Appendix B):**
- 24 biomes mapped to 5 tiers with `tier` + `cr_recommended` in
  `biomes.json`. Tier 1 base, Tier 5 `5×` enemy stats via
  `C.TIER_SCALE[tier-1]` folded into `_branch_tier_mult`.
- `FLOORS_PER_RUN: 10 → 6` (5 regular + 1 boss). `BOSS_FLOOR=6`.
  `MINIBOSS_FLOORS=[3]`.
- Branch boss = strongest enemy in the branch's pool, ×3 hp / ×1.7 atk
  / ×1.5 def on top of tier+floor mults. No bespoke per-branch enemy
  data needed; future `boss_id` field on biomes can override.
- Per-tier rarity baseline: T1 +0% .. T5 +20% in `_roll_rarity` so
  higher tiers naturally drop better loot.

**Stricter unlock progression:**
- Clearing one tier-N boss unlocks tier-N siblings only.
- Tier-(N+1) only opens when EVERY tier-N branch's boss is cleared at
  least once. Tracked in `save.bosses_killed: {branch_id: count}`.
- `boss_killed` signal in `dungeon.gd`; `main.gd::_on_boss_killed`
  applies the rule and writes save. Prints `[unlock]` lines so progress
  is visible in the editor stdout.
- Fallback path: `_on_run_ended(victory=true)` re-runs `_on_boss_killed`
  on the selected branch in case the signal silently failed.

**Per-deploy run modifiers (`data/modifiers.json`):**
- 8 modifiers gated by `min_tier`: Treasure Hoard, Crowded, Endless,
  Glittering, Bloodlust, Fortified, Hunted, Boss Hunt.
- Outpost rolls 1-2 per unlocked branch on every visit (60% one /
  40% two), persists in `save.branch_modifiers`. Cleared after deploy
  so the next visit re-rolls fresh.
- Effects fold throughout: `enemy_count_mult`, `enemy_stat_mult`,
  `extra_floors`, `rarity_bonus`, `extra_chests_per_floor`,
  `chest_contents_mult`, `extra_miniboss_on_floor`, `boss_loot_mult`,
  `gold_mult`. See `RunModifiers.sum_effect`.
- Branch picker buttons show the rolled modifier strip ("+Crowded ·
  +Glittering") with full descriptions in the hover tooltip.

**Death retreat with revives stat:**
- `save.max_revives` (default 3) → `revives_remaining` per run.
- HP=0 → `_try_death_retreat`: kills the death-spin tween, resets the
  rig transform, revives bot at full HP, respawns at floor 1 of the
  same branch. Loot stays in `_loot_segments` and `_hud_inv_cache`.
- When revives hit 0, real `_end_run(false)`. Run report shows
  `Retreats: N` in red.
- Lava death routes through retreat too (was a missing path).
- `max_revives` is the scaling hook — bot upgrades / gear affixes can
  bump it later.

**Idle-friendly inventory loop:**
- No more death loss — loot is loot, banked on victory or death.
- `_loot_segments`: per-floor inventory sections. Base stash on top,
  Floor-N segments append as floors complete. HUD renders newest-first
  so latest pickups stay in view without scrolling.
- Live equip from HUD: click an inventory cell → bot swaps in-place.
  Per-slot 30s cooldown (countdown overlays the paperdoll equipped
  slot, NOT every same-slot inventory item — visual was misleading).
  Refusing-during-cooldown logs to combat log.

**Gear bloat controls:**
- `save.loot_filter` (default `"common"`) — bot walks past loot below
  this rarity. `LootDrop.should_skip` checks a static rank cached at
  run start (no disk hit in AI hot path).
- `save.inventory_cap` (default 50). On pickup, `_maybe_auto_salvage`
  walks segments oldest-first and converts items at-or-below the
  filter rarity to gold until under cap. Starter gear excluded.
- Salvage values: common 2g / uncommon 6 / rare 18 / epic 60 /
  legendary 200. Tunable in `_SALVAGE_VALUES`.
- Outpost "Bot Instructions" panel: filter dropdown + `Inventory: X / N`
  readout (folds in Pouch upgrade contribution).

**Bot upgrades (`data/bot_upgrades.json` + `scripts/bot_upgrades.gd`):**
- 6 upgrades: Conditioning (+5 HP/rank), Combat Training (+1 ATK/rank),
  Toughening (+1 DEF/rank), Quick Reflexes (+2% crit/rank), Loot Sense
  (+10% rarity bias/rank), Pouch (+10 inventory cap/rank).
- Cost curves per the doc (×2.5/rank).
- Stats fold into `bot.recompute_stats` via
  `BotUpgrades.total_for_stat(state, stat)`. Loot Sense is set once at
  `apply_gear` (blessing-style stat).
- Outpost upgrades section: scrollable list with rank N/M, "Buy — Xg"
  button (greyed unaffordable, "MAXED" when full).

**Offline progress (`scripts/offline_progress.gd`):**
- `save_state.save_state` stamps `last_seen_timestamp` on every save.
- `last_branch` written on deploy.
- On launch (skipped in grind/debug-jump): `OfflineProgress.apply`
  computes `elapsed = min(now - last_seen, 3600s)`. Below 60s = no
  progress.
- Estimated floors/sec scales with bot CR vs branch `cr_recommended`
  (clamped 22..360s/floor). ~4 loot drops per floor on average; loot
  honors the player's filter. Per-tier gold: T1 ~10g/floor → T5
  ~1150g/floor.
- "While You Were Away" `AcceptDialog` on the main menu reports
  branch / minutes / floors / loot / gold. One-shot, cleared after.

### Stuck-detection rewrite

Old code counted frames (`STUCK_RECOVERY_THRESHOLD = 360`). On 120Hz
ProMotion that was 3s — well under the 6s the original comment intended.
Plus zero carve-outs for legitimate idle states. Result: bot teleporting
to stairs mid-boss-fight or while opening a chest.

New behavior (`_check_stuck` + `_try_death_retreat`):
- Delta-time accumulator, refresh-rate independent.
- Carve-outs reset the timer to zero every frame: `bot_interacting`,
  `bot.path.size() > 0`, `_has_combat_engaged_enemy()` (any live enemy
  within `AGGRO_ENGAGE_RANGE = 5` cells, Chebyshev). Boss fights
  no longer count as idle.
- 4-tier escalation: warn at 6s, soft repath at 10s, hard reset at 18s,
  last-resort teleport-to-stairs at 30s. Each tier logs.

### UI rework — Outpost (was Garage), shared paperdoll, smoother chrome

`scripts/garage.{gd,uid,tscn}` removed; replaced by
`scripts/outpost.{gd,uid,tscn}`. Three-pane DCSS chrome: paperdoll left,
stats center, inventory right. Branch picker at the bottom.

**Shared paperdoll renderer (`scripts/paperdoll_renderer.gd`):**
Builds a layered Sprite2D rig (base bot + boots/armor/helm/shield/weapon
overlays at anatomical anchors). Used by:
- In-game bot via `bot.gd::_refresh_gear_overlays`. Removed the
  hardcoded `armor_mummy.png` body and the "every weapon = battleaxe"
  test-mode hack. Equipped weapon/armor/helm/shield/boots all show
  their actual sprites now.
- HUD sidebar paperdoll panel (rebuilt on `update_equipped`).
- Outpost paperdoll pane.
- Main menu vignette.
Same `Node2D` rig + `scale` knob — what's in inventory matches what
fights in the dungeon.

**New gear overlay assets** under `assets/tiles/player/`:
- `body/` — `armor_chain.png`, `armor_leather.png`, `armor_plate.png`,
  `armor_robe.png` (plus existing `armor_mummy.png`)
- `helm/` — `helm_cap.png`, `helm_crested.png`
- `shield/` — `shield_buckler.png`
- `boots/` — `boots_brown.png`
- `weapons/` — `weapon_dagger.png`, `weapon_sword.png`, `weapon_axe.png`,
  `weapon_claymore.png` (plus existing battleaxe/dagger/long_sword/etc)
- `bot_lantern.png` removed (was a mistakenly-equipped-as-overlay icon
  from a previous test).

**Rarity decoration on item cells** (`UITheme.add_rarity_cell_decor`):
1px square border in rarity color + inset halo (rarity-tinted edge ring
fading to dark center). Halo strength scales with rarity (common 0% ..
legendary 55%). Replaces the old silhouette outline shader for
inventory + equipped slots. Floor loot drops keep the silhouette glow
(`loot_drop.gd::_make_glow_texture` — different system).

**HUD sidebar reshape:**
- Dropped XL/Turn (mystery values).
- Added Crit / Haste / Regen so all 6 stats are visible at a glance.
- Loot log moved to bottom strip; segmented inventory grid renders
  newest-first.
- Tooltips unified via `AffixSystem.format_item_tooltip` —
  `Iron Brigandine [+Strength] [Common]\n+7 DEF +80 HP\n+4 ATK`.
- Fixed mouse-filter regressions: bag/sidebar/minimap `ColorRect`s set
  to `MOUSE_FILTER_IGNORE` so tooltips reach the underlying buttons.

**Main menu refresh** — two-column splash, bot vignette pulls saved bot's
gear/stats. "Reset Save" dialog requires typing `reset`. "Create Character
(soon)" placeholder for later.

**Theme constants** (`scripts/ui_theme.gd`) — single source of truth for
colors, font sizes, rarity tints. GDScript const-expression rules force
inline duplicates in each consumer; UITheme is the documentation reference.

### Smooth shader-driven fog of war

Replaced cell-aligned Bresenham FoV with shader-side ray-march.
`fog_overlay.gdshader` does per-fragment LoS to the bot's continuous
world position against a wall-mask texture (`R8`: 1=wall, 0=walkable),
24 march steps with linear filtering for soft occlusion.

Fixes:
- The "tick" every tile (cell-aligned visibility texture only refreshed
  when `bot.cell` changed).
- Christmas-cracker corridor stripes (Bresenham rays to grid-aligned
  perimeter cells).
- Hard occlusion edges (now soft via per-step density accumulation).
- Grey halo bleed past map edges (OOB samples treated as wall;
  `oob_factor` clamps OOB fragments to opaque black).
- Grey ticking trails behind the bot (`tile_visibility.gdshader` was
  independently fading each tile based on the old per-cell texture —
  bypassed; tiles now render full alpha and the overlay is the only
  fog source).

CPU `FogSystem` still runs for AI gating, journal, minimap dimming, and
actor visibility. Just no longer drives the visual.

`FogOverlay.set_wall_mask_from_grid(grid)` builds the mask once per
floor. `FogOverlay.update_lights(..., bot_world, bot_radius_px)` pushes
bot world position every frame (diff-checked).

---

## Perf pass 2 — 2026-05-14 (native Retina + 1×)

User reported 10-23 fps on most maps and 10 fps in lava/forge vaults
despite the previous pass logging 19 → 112 fps. Root cause: the previous
pass measured at 1600×900 windowed, which is ~5× fewer pixels than M3 Pro
native Retina. CPU side was fine; everything was GPU- and floor-build-
hitch-bound at native res. Six surgical wins:

1. **PointLight2D node count was the GPU killer.** Forge spawns ~50
   ambient-decor lights per floor; each is a separate full-coverage screen
   pass on Godot's GL Compatibility renderer, dropping fps from 120 to
   19 at native res. Added `LightSpec.TIER_DECOR` — for decor lights,
   skip the PointLight2D node entirely. The fog-overlay shader's
   24-source `light_intensities[]` uniform handles the broad warmth, and
   a per-decor additive glow Sprite2D + GPUParticles2D embers handle the
   "this is a flame" visual.
2. **Decor flicker animation moved CPU-side.** When PointLight2D went
   away, FlickerDriver lost its lights to animate. Per-decor `_process`
   now runs the same noise math (FastNoiseLite, scoped at 35% spec
   amplitude), driving glow alpha + scale + sub-pixel jitter. Visually
   equivalent to actor-tier flicker, zero GPU cost.
3. **FlickerDriver tree-signal churn.** Was subscribed to global
   `tree.node_added`/`node_removed`; every blood splat / hit flash /
   tween-spawned sprite forced a full tree walk to refresh the cache.
   Replaced with a 0.25s coarse refresh tick. **CPU avg 515µs → 254µs.**
4. **HUD inventory pool.** `update_inventory` was queue_freeing every
   `TextureRect` and re-creating; now grows a pool once and toggles
   visibility + texture. No more per-build node churn.
5. **Forward+ renderer.** Flipped `rendering_method` from
   `gl_compatibility` to `forward_plus`. Boots cleanly on Apple Metal.
   **fps min 58 → 100** (much smoother frametimes); CPU per-system tags
   ~doubled but well within budget. Caveat: requires Vulkan, will fall
   back to gl_compatibility on hardware without it (mobile profile keeps
   compat anyway).
6. **Orphan-connect O(N×W×H) → O(W×H).** `_connect_orphans_to_main` was
   doing per-orphan-cell expanding-spiral nearest-cell searches. p95
   1290ms, max 2016ms — that's the 2-second hitch users actually saw.
   Rewrote as a single multi-source BFS from main_region walking through
   walls + parent backtrace. **p95 18ms, max 26ms (-98.7%).**
   `[gen-phases]` log line stays in for future regressions.

### Final M3 Pro numbers (1× windowed, native Retina, forge)

| Metric | Pre-pass | Final | Δ |
|---|---|---|---|
| fps median | 73 | **120** (vsync cap) | +64% |
| fps min | **19** | **119** | **+526%** |
| frame_ms max | (variable, 0.80+) | 0.55 | smooth |
| gen p95 | 1290ms hitch | 18ms | -98.7% |
| build_floor avg | 1500+ms tail | 432ms | -71% |

### New tooling

- **`/showcase` skill** — hand-curated visual audit floor with one
  station per visual feature (fire/magic/crystal decor, campfire actor-
  tier reference, lava/water/ice, altars, fountains, loot rarities,
  chests, portal, fire/ice creatures with light_spec). Bot patrols a
  fixed loop so its light reveals each station. Use for any visual
  iteration without waiting for procgen to roll the right combination.
  See `.claude/skills/showcase/`.
- **`BOTTER_FORCE_BIOME=<id>`** env var — pins every floor of an
  auto-grind to a single biome. Used for biome-specific A/B sweeps.
- **`[gen-phases]`** log line — per-floor `carve_us / vault_us /
  connect_us / dist_us` profile. Stays in to flag any future generator
  hot spot.

### Hardware caveat (unchanged)

Baseline is M3 Pro Retina. The remaining sub-vsync floors (gen 30-75ms,
vault 10-40ms) are not yet split across frames; on a low-end Windows
laptop these may need further work. Forward+ requires Vulkan — older
hardware will hit the gl_compatibility fallback and lose the smoother-
min benefit.

---

## Perf pass 1 — 2026-05-13 (full session arc)

The session opened with a "fairly simplistic game running at variable
30-120fps" complaint. By end, **avg fps 19 → 112, p50 → 120 (vsync
cap), min 17 → 49** on M3 Pro 1× windowed.

### What turned out to actually be slow (in order of impact)

1. **HUD update was the dominant cost** — `_update_biome_hud` ran every
   frame and (a) called `SaveState.load_state()` (file open + JSON parse
   + migrate) every frame, (b) queue_freed and recreated up to 1745
   `TextureRect` nodes for the inventory grid, (c) repainted a 6400-pixel
   minimap image, (d) wrote 7 Label.text values triggering Godot
   layout/relayout. Throttling these to "data-changed" / 0.25s ticks
   alone took fps from 19 → ~80. **This single class of fix dwarfed
   everything else.**

2. **Tile rendering as per-cell Sprite2D** — 6400 individual canvas
   items × 2 layers = thousands of draw calls per frame. Migrated to
   `TileMapLayer` with a runtime-baked packed atlas (one
   `TileSetAtlasSource` per floor, every biome texture blitted into
   one `Image`). Draws fell from ~6400 to ~150. Per-cell modulate
   visibility fade replaced with a canvas shader sampling the fog
   visibility texture.

3. **Async floor build** — `_build_floor` is now split across 4 frames
   via `await get_tree().process_frame` between gen / atlas-bake / decor
   / spawn phases. The single-frame 70-600ms freeze on stairs descent
   is gone. Build-generation counter cancels stale awaits when a new
   build preempts (fixes the race when runs end mid-build).

4. **AI repath thundering herd** — every enemy initialised
   `repath_timer = 0` so they all fired A* on the same frame; with
   24 enemies that was 24 × ~1ms paths per repath cycle. Fixes:
   stagger `repath_timer = randf_range(0, REPATH_INTERVAL)` at spawn,
   cap `MAX_REPATHS_PER_FRAME = 3` in `_tick_enemies`. ai_us max
   went 12741 → 276µs (46×).

5. **Three CPU opts (already shipped earlier in the session)** —
   - **Fog refresh gate** (`bot.cell` change + invalidate_fog events;
     dedupes `_world_light_sources` to once per refresh). avg -29%,
     p95 -44%.
   - **Shader buffer reuse** in `FogOverlay` — preallocated MAX_LIGHTS
     packed arrays, per-slot diffing skips redundant
     `set_shader_parameter` calls. avg -49%.
   - **FlickerDriver group cache + visibility gating** — replaced
     scene-tree walk with `flicker_lights` group; lights not visible
     in tree skip animation AND pause ember `GPUParticles2D.emitting`.
     avg -96%.

### What I expected to be slow but wasn't

- **PointLight2D shadow filter (PCF5) against ~1500 wall occluders.**
  Disabling shadows entirely gained zero fps. Counterintuitive.
- **WorldEnvironment glow.** Disabling gave ~+1% fps.
- **GPUParticles2D embers.** Disabling gave 0%.
- **Floor enemy count.** ai_us was flat across f1 (6 enemies) → f8
  (24 enemies); the spike was paths firing simultaneously, not the
  scale of work.

### Telemetry that landed

- **`scripts/perf_mon.gd`** — static µs accumulator. Tags
  `frame/fog/lights/flicker/render/ai`. 240-frame rolling window.
  HUD line, `[perf]` log every snapshot, `[perf-floor]` per-floor
  with `label=biome|vault[,vault]|fN`. The `[perf]` line also
  reports `draws=` (RenderingServer draw calls) + `objs=` + `nodes=`.
- **`scripts/dungeon.gd`** — `[build-floor]` line per floor with
  total/gen/render/decor/spawn ms. Pinpoints which phase is slow.
- **`/benchmark` skill** — `.claude/skills/benchmark/`.
  `benchmark.sh [duration_s] [speed] [label] [headless|windowed]`,
  `parse_perf.py` ranks worst floors/vaults/floor-numbers,
  `compare.sh` diffs two logs.

### Hardware A/B knobs (kept for future hardware testing)

Env vars that disable individual systems at scene start, for
hypothesis-testing perf on lower hardware:

`BOTTER_NO_TILES`, `BOTTER_NO_LIGHTS`, `BOTTER_NO_FOG`,
`BOTTER_NO_GLOW`, `BOTTER_NO_EMBERS`, `BOTTER_NO_SHADOWS`,
`BOTTER_NO_OCCLUDERS`, `BOTTER_NO_VSYNC`,
`BOTTER_SHADOW_FILTER=none|pcf5|pcf13`.

`BOTTER_NO_TILES=1 BOTTER_NO_LIGHTS=1 bash benchmark.sh 30 1
all-off windowed` is a useful "what's the platform's ceiling".

### Headless vs windowed

- `--headless` skips the GPU renderer entirely. CPU timers (fog, ai,
  flicker, render-fade, light pack) are honest; **GPU shader / shadow
  / particle costs are NOT exercised**. Useful for fast CPU-only A/B.
- `windowed` launches the actual game window so the full renderer
  runs. Required for any GPU-related measurement.
- Important: at 16× speed_scale the bot ticks 16× per real second,
  so CPU work scales but GPU per-frame cost stays constant.
  GPU-cost measurements need 1× speed.

### Final M3 Pro numbers (2min windowed 1×)

| Metric | Pre-pass | Final | Δ |
|---|---|---|---|
| fps avg | 19 | **112** | 5.9× |
| fps p50 | 18 | **120** (vsync cap) | 6.7× |
| fps p05 | 19 | **56** | 2.9× |
| fps min | 17 | **49** | 2.9× |
| ai_us max | 12,741 | **276** | 46× |
| draws | ~6400 (per-cell sprites) | ~150 (packed atlas) | 40× |

### Hardware caveats

Baseline is **MacBook M3 Pro**. Re-run `/benchmark` on the high-end PC,
mid PC, low-end Windows laptop when those become available — a 200µs
win on M3 Pro can be 2ms on the laptop.

### Outlier maps/vaults — perf hot floors

From baseline 5min, 16×, M3 Pro:

- `crypt|des_grunt_crypt_end_deaths_head` and
  `crypt|des_quadcrypt_mu` — top frame_ms floors.
- `pandemonium|des_hellmonk_crystal_mountain`,
  `pandemonium|des_infiniplex_zot_generator`.
- `lair|des_grunt_forest_small_clearing_treed` — small sample but high
  ms; likely big-tree decor.

These are candidates for inspection if perf still hurts on lower-tier
hardware after these opts.



## Marathon session summary — what just shipped

16+ commits in one session. Highlights:

- **Vault stamping rate 14% → 75-83%** (the fundamental fix to the user's
  "maps look like random messes, no notable loot rooms" complaint)
- **Map size 60×60 → 80×80** for breathing room
- **Bot AI tuning**: aggro range cap, current-room loot priority, low-HP
  retreat. Loot pickup rate jumped from 20 to 125 per run.
- **Starter gear** (rusty_dagger + tattered_hide) so a fresh bot can
  actually progress
- **Weapon overlay sprite** + swing animation on attacks
- **Bot light + z-order fixes** (no more white-out, bot draws over chests)
- **Special-feature terrain** (lava damages, water slows, ice visual)
- **Sigil floor decorations** (single + multi-tile compositions via
  decor_overlays vault format extension)
- **Multi-tile decor glyphs** (t/B/M for trees/bones/mushrooms)
- **Big-creature visual scaling** (32 enemies render 1.3-1.6× scale)
- **22 god altars** (was 7) with thematic blessings
- **Combat effects** (blood/fire/ice on kill, magic shimmer on legendary)
- **Doors** (per-biome variants — wooden/runed/sealed)
- **Save-state isolation** (debug runs don't pollute live save)
- **Bot invincibility** in grind mode
- **Permission allowlist** expanded (saves session clicks)
- **Pre-commit validation** (`tools/check_before_commit.sh`)
- **class_name refresh wrapper** (`tools/refresh_class_cache.sh`) +
  auto-recovery in skill scripts
- **Richer /grind summary** (per-biome breakdown, portal kinds, terrain
  counts)
- **HP scaling bug fix** (level-up no longer fully heals)
- **Run-end-on-boss-kill** gated to actual boss floor
- **Bot visual swap** — spriggan_female base + mummy body armor +
  battleaxe weapon overlay (testing the layered sprite system)
- **Desktop pivot + DCSS chrome**:
  - Viewport 540×960 → **1600×900** landscape. `keep` aspect stretch.
  - New `HudChrome` CanvasLayer (`scripts/hud_chrome.gd`):
    right sidebar (minimap top, stats panel, recent-events log feed),
    bottom-left bag panel (5 equipped slots + scrollable inventory
    grid), tiny top-left debug HUD (biome/floor/layout/recent vault
    names/grid dims/enemy + interactable counts/fps).
  - Subtle translucency on chrome (panel α 0.62, slot bg α 0.40) so
    the dungeon shows under the chrome in the cracks.
  - Camera `offset` shifts world view so the bot stays in the centre
    of the dungeon-visible region (not under the sidebar/bag).
    Screenshot mode bypasses the offset.
  - Old top-left HUD (`hud_name_label`, `hud_hp_bar`, etc.) removed —
    chrome owns all stats.
  - DCSS GUI tile assets copied to `project/assets/tiles/gui/`
    (tab labels, checkboxes, prompt yes/no).
- **Biome editor (per-tile review tool)** — `tools/biome_editor.html`:
  - Visual editor showing every tile that could render per biome
    (floor primary/secondary/accent, wall primary/accent/alternates,
    edge overlay with 3×3 directional grid + N/S/E/W/NE/NW/SE/SW/FULL
    labels, sigil set), per-tile **Replace** dropdown via picker modal,
    Duplicate / New blank / Delete buttons, raw-JSON textarea for
    advanced fields, `⬇ Export biomes.json` downloads modified file.
  - Biome JSON schema extended: `@stem` literal-tile syntax alongside
    prefixes (`biome_data.gd._expand_prefixes`); `wall_primary` now
    accepts arrays as well as strings; `wall_alternates` supports
    `prefixes:` list as well as legacy `prefix:`.
  - `tools/build_biome_manifest.py` bakes asset directory listings →
    `tools/biome_manifest.json` for the static editor.
- **Vault chest cap** — `vault_stamper` enforces
  `CHEST_MAX_PER_VAULT = 8` and `LOOT_MAX_PER_VAULT = 12` with stride
  sampling; `vault_library` precomputes `_chest_count` at load and
  `_effective_weight` divides by 8 (4-7 chests) or 20 (8+) before
  `pick_weighted` rolls. `des_vaults_vault` (28×22 = 608 chest glyphs)
  used to spawn 613 chests and tank perf — now picks ~1/600th as often
  AND caps at 8 chests when it does.
- **Skill marker hygiene** — `grind.sh` and `screenshot.sh` now
  unconditionally `rm -f` their markers (`AUTO_GRIND.txt`,
  `DEBUG_FLOOR.txt`, parked variants) on exit so the user's next
  interactive Godot launch always lands in normal-speed play.
- **Floor pass** (DCSS-faithful):
  - Per-cell hashed weighted variant pick replaces Voronoi patches —
    floors read as "textured" instead of chunky-patches. Weights match
    DCSS's 6/3/1 distribution.
  - Real liquid terrain: river/lake/pools convert FLOOR cells to
    T_WATER / T_LAVA (was: T_WALL stub). Biome-gated via
    `liquid_type: "water"|"lava"|""` in biomes.json (forge / pandemonium
    / abyss → lava; shoals / swamp / lair / snake / forest / slime →
    water). Wired through both `basic_level` and `delve` paths so
    caves layouts also get rivers.
  - Sigil set audit: directional sigils stripped from per-room sigil
    placement (they were designed to layer, not scatter). Defaulted to
    safe single-tile [sigil_circle, sigil_cross, sigil_rhombus].
  - Lair pilot dual-floor mix: Perlin noise (one octave, freq 0.045)
    selects between `floor_primary` (lair) and `floor_secondary` (moss)
    so cells transition organically across the map.

---

## Core gameplay loop — fully working

Main menu → Outpost (pick branch) → Deploy → 6-floor dungeon → Run report
→ Outpost with new loot → equip / spend gold on upgrades → redeploy.

- **Boss floor = 6** (5 regular + 1 boss), single miniboss floor at 3.
- **Branch boss** = strongest enemy in the branch's pool, scaled to boss
  tier. Each tier multiplies enemy stats by `TIER_SCALE[tier-1]`
  (1.0/1.4/2.0/3.2/5.0).
- **Stricter unlock**: clearing one tier-N boss opens tier-N siblings;
  clearing every tier-N boss opens tier-(N+1).
- **Death retreat**: HP=0 spends a revive (default 3/run). When revives
  run out the run actually ends.
- **Per-deploy modifiers**: each branch button shows 1-2 rolled
  modifiers (Crowded, Endless, etc) refreshed on every Outpost visit.

## Bot AI

Sticky-target priority engine in `dungeon.gd`:

1. Adjacent live enemy → attack (lock, don't switch).
2. Has unfinished path? → keep walking, don't repick target.
3. Target invalid (enemy died, interactable consumed) → drop path, repick.
4. **Low-HP retreat**: HP < 30% max → head to nearest unconsumed fountain.
5. **Current-room loot priority**: if bot is inside a BSP room and that
   room contains an unconsumed interactable, target it before chasing
   distant enemies.
6. **Aggro range cap (8 cells)**: nearest-enemy chase only if within 8
   cells. Beyond that, bot keeps exploring; combat happens when paths
   cross.
7. Nearest interactable globally → walk toward.
8. Nearest unvisited room → walk toward.
9. Stairs → descend.

The bot reads the full grid for pathing (autoexplore-style); the player
watches through fog. That's intentional and matches DCSS's autoexplore.

**Enemy soft-collision**: enemies hold their tick if their next path-cell
is occupied by another live enemy (excluding the bot's cell). Prevents
the visual stacking when a horde converges on the bot.

## Map size

80×80 cells (was 60×60). Bigger maps mean more breathing room for both
caves and procedural rooms, more space for vaults to land, less cramped
combat. Each tile is 32 px so maps render at 2560×2560 internal coords.

## Vault stamping reliability — FIXED

Earlier sessions saw most floors with `vaults=[]` (vaults rare). Root
causes diagnosed and fixed:

1. **Float stamper picked one random vault, tried once.** If the picked
   vault was 30×20 and no detected room was 32×22, the floor got zero
   vaults — even though plenty of 8×8 vaults would have fit. Fixed:
   stamper now retries up to 16 candidate picks per slot with a size
   filter that pre-screens for fitting candidates.
2. **First and last rooms were always skipped** in the room-shuffle
   loop (legacy attempt to keep spawn/stairs vault-free). On caves
   layouts where room order is arbitrary this discarded ~20% of valid
   placements. Fixed: try every room.
3. **Vault-stamped boss enemies ended the run prematurely.** Vaults
   like `des_shoals_end_hellmonk_lost_city` have `spawns: [..., minotaur]`
   and minotaur is boss-flagged, so killing it on floor 5 ended the run
   "victorious". Fixed: run-end-on-boss-kill only triggers on the actual
   final-boss floor (`current_floor >= BOSS_FLOOR`).

Result: vault stamp rate jumped from 14% to 75-83% per floor. A typical
3-run grind now stamps 14-17 unique vaults across 30 floors.

## Bot invincibility (grind only)

When auto-grind is active, `DebugJump.bot_invincible = true` and
`Bot.take_damage` no-ops. Lets benchmark runs reach floor 10 reliably so
late-floor generation is audited even if the bot's combat balance is off.
Live playtest is unaffected.

## Generation pipeline (DCSS-faithful)

Order in `dungeon_generator.gd`:

1. **Encompass-vault short-circuit.** ~25% gate; if hit, the vault IS the level. Stairs come from vault `<`/`>` glyphs.
2. **Procedural layout.** Picked from `BiomeData.roll_layout()` weighted pool — `basic_level` / `caves` / `caves_tight` / `caves_open`. Each biome ships 2-3 layouts so the same biome can look different across runs.
3. **Oriented vault stamp.** N/S/E/W/centre vaults attached to the matching map edge.
4. **Float vaults.** ~1-2 per floor (2 on floor 7+), filtered by biome `vault_themes` array.
5. **Connectivity verification.** BFS from spawn; orphans get carved corridors, full regen if needed.

Generator regenerates if a layout produces < 200 floor cells (up to 5 attempts).

## Biome roster — 24 biomes, all wired

`dungeon, dungeon_dark, mines, lair, forest, swamp, snake, shoals, orc,
vaults, crypt, tomb, forge, glacier, slime, hive, labyrinth, abyss,
pandemonium, zot, elf, spider, temple, depths`

Each declares `vault_themes` (which vault tags it pulls), `layouts` (weighted
pool), `floor_primary`/`wall_primary`/`wall_alternates` tile prefixes,
`enemy_pool`, `ambient_decor`, `darkness`, `modulate`, and an optional
`edge_overlay`.

`BiomeData.roll_run_plan()` currently builds a fully-random 10-floor plan
(every floor independently rolled). Locked-in chain mode (D:1-3 → Lair:1-2 →
…) is in TODO.

## Vault library — 1320 ported DCSS vaults

All in `project/data/vaults/des_*.json`. **No hand-typed ASCII vaults remain**
— they were redundant with the ported pool and were deleted.

Filter rules in `vault_library.gd` `_theme_match_any`:

- A vault matches a biome if they share at least one non-`dungeon` tag, OR
- The vault has only `dungeon` (universal), OR
- The biome's only request is `dungeon` (then dungeon-tagged vaults match).

This stops Lair-tagged vaults from leaking into Crypt biomes etc.

Lair sub-branch tags (`swamp`, `snake`, `shoals`, `spider`, `forest`, `hive`)
are mutually exclusive with `lair` on ported vaults — i.e. a swamp-tagged
vault no longer also has `lair`. So Swamp pulls 293 vaults, Snake 272, Shoals
275, Spider 243, Hive 164, Forest 173 — each distinct rather than all sharing
the 620-strong Lair pool.

## Portals — DCSS-style mini-floors

8 portal kinds (`sewer, bailey, bazaar, ossuary, wizlab, trove, ziggurat,
hive`) live in `Portal.PORTAL_KINDS`. 15% spawn rate per eligible floor
(2-9). Stepping on a portal interactable swaps the current floor in-place to
the portal's biome with bonus chests (+1 to +2 count, rarity bias).
Descending the portal floor's stairs continues the run normally; the floor
counter does not advance during the side-trip.

## Visible loot, interactables, FX

- **Loot drops**: Items physically drop on floor with rarity-coded glow + idle
  wobble. Bot kneels (squish + lean) to pick up. Rarity-scaled pickup
  duration (common 0.35s → legendary 0.8s).
- **Affix system**: 6 affixes (Strength, Stamina, Agility, Regen, Crit,
  Haste). Roll 0-4 per item by rarity. Items get
  "Iron Sword [+Strength, +Crit]"-style names. ALL 6 are combat-wired.
  Cap: 75% crit, 200% haste.
- **Interactables**: chests (burst items in arcs on open), fountains (heal
  40-60% HP, bot only stops if injured), altars (22 god-themed
  run-ephemeral blessings — Trog/Okawaru/Zin/Elyvilon/Vehumet/Kiku/Sif Muna
  + Beogh/Makhleb/Yred/TSO/Lugonu/Jiyva/Fedhas/Cheibriados/Xom/Ashenzari/
  Dithmenos/Gozag/Qazlal/Nemelex/Ru), portals (above).
- **Sprite FX**: per-actor Tween-driven squash/stretch — attack lunge
  (with bright color flash on swing), hit squish + flash, death spin/
  shrink, kneel-on-interact, loot pop.
- **Run journal**: per-floor narrative log (DCSS-morgue style) shown on run
  report alongside loot recovered/lost.

## Fog of war + dynamic lighting

**Shader-driven ray-march** (`assets/fog_overlay.gdshader`). Per-fragment
LoS from screen pixel to bot's continuous world position against a
wall-mask texture. 24 march steps, linear-filtered mask, soft occlusion
via per-step density accumulation. Smooth as the bot moves, walls block
lights cleanly, no tile-aligned ticks.

External lights (torches, sconces, fire dragons) ray-march against the
same mask so they don't leak through walls. Out-of-bounds fragments are
forced to opaque black so light halos don't bleed past the map edge.

CPU `FogSystem` still runs for AI gating + journal + minimap dimming +
actor visibility (per-cell binary "can the bot see this enemy"). Just
doesn't drive the visual anymore.

`PointLight2D`-driven additive lighting from world sources (altars,
fountains, lava, legendary loot, lit chests, fire/ice creatures) layers
on top of the fog overlay.

### Organic flicker + ember particles

`LightSpec.attach()` stamps a "flicker" meta dict on each PointLight2D
instead of running a tween. A single `FlickerDriver` node walks the
scene each frame and animates every light via a shared FastNoiseLite,
sampled at unique seeds per-light so flames desync naturally. Three
flicker categories:

- **fire** — broadband noise, sub-pixel position jitter, ember particles
  (GPUParticles2D with per-spec colour gradient)
- **magic** — noise + slow sine pulse, no jitter, no particles
- **crystal** — slow noise wobble, no jitter, no particles

Light specs added: `firestarter`, `hellfire`, `demon_blade`, `firefly`,
`fire_creature`, `lava_creature`, `ice_creature`, `magic_lamp`.

### Per-creature emitter lights

`enemies.json` entries can declare a `light_spec` field. The spawner
calls `LightSpec.attach(enemy, spec)` so fire dragons / ice giants /
fireflies emit their own light. 8 creatures tagged: fire_giant,
fire_dragon, salamander, cacodemon, ice_dragon, ice_beast, frost_giant,
blizzard_demon.

### Fire weapons emit light

`Bot.WEAPON_LIGHTS` maps weapon `base_id` -> light spec. Fire-tagged
weapons (firestarter, hellfire, demon_blade, flaming_sword/axe) attach
their light to the weapon overlay sprite, so the glow follows the bot's
held hand.

## Edge-overlay autotile system

In `MapRenderer._apply_edge_overlay`. Floor cells that border walls get a
second sprite layer with directional pieces (north/south/east/west + 4
corners). 57 directional tiles in `project/assets/tiles/overlays/` — 5 sets:
`grass, dirt, slime_overlay, shallow_water_wave, deep_water_wave`.

Wired to biomes:
- **lair / forest** → `grass` (high density)
- **swamp / snake / spider / hive** → `dirt`
- **slime** → `slime_overlay`
- **shoals** → `shallow_water_wave`

The renderer reads `biome.edge_overlay = {"prefix": "grass", "density": 0.85,
"patch_density": 0.06}`.

## Special-feature terrain (lava / water / ice)

Three new walkable-with-effect cell types:
- `T_LAVA` — walkable but damages bot 5% max-hp every 0.5s on the cell.
  Pathfinder weight 4.0 (avoid if any safe path exists).
- `T_WATER` — walkable, halves move_speed while bot is on the cell.
  Pathfinder weight 2.0. Affects enemies symmetrically.
- `T_ICE` — visual-only for v1 (slip mechanic deferred).

Wired via VaultStamper glyphs `L`/`l` (lava), `W`/`w` (water), `I` (ice).
Six mini-vaults in `project/data/vaults/`:
`forge_lava_pit_5x5`, `forge_lava_bridge_7x3`, `shoals_tide_pool_5x5`,
`swamp_bog_5x5`, `glacier_ice_shrine_5x5`, `crypt_blood_pool_3x3`.
All authored as **irregular organic shapes** — no rectangular blobs.

Sprites in `project/assets/tiles/terrain/{lava, water, ice}.png`.

The vault-stamping system has a debug-only fallback: if `DebugJump.vault_name`
matches the vault being stamped AND no rooms are available (caves layout),
the stamper does a bounded random-region scan to place it for screenshot
verification. Outside debug mode, vaults strictly require BSP rooms.

JSON sidecar exposes `floor.terrain_cells: {lava: N, water: N, ice: N}`.

## Doors

Vault `+` glyph renders as `closed_door`/`runed_door`/`sealed_door` based
on biome. Stone-tier biomes (vaults/depths) get sealed iron; ritual
biomes (crypt/tomb/elf/zot/pandemonium/abyss) get runed; everywhere else
gets the plain wooden closed door. Three sprites in
`project/assets/tiles/features/`. Mapping in `MapRenderer.DOOR_BY_BIOME`.

## Combat effects

Lightweight `Effects` helper (`scripts/effects.gd`) — one-shot Sprite2D
fades. Hooks:

- Enemy died → biome-themed kill flash. Forge/Pandemonium → fire,
  Glacier → ice, everywhere else → blood splat.
- Legendary loot picked up → magic shimmer.
- Rare loot picked up → gold sparkle.
- Altar grant → magic shimmer at the altar.

7 effect tiles in `project/assets/tiles/effects/`. Each spawn tweens
scale + alpha and queue_frees itself; no persistent state.

## Big-creature visual scaling

In `Actor.apply_visual_scale(scale, anchor, z)`. 32 creatures in
`enemies.json` carry optional `visual_scale` / `visual_anchor` /
`visual_z` fields. Dragons, giants, sphinxes, mummies render at 1.5x
ground-anchored (sprite bottom pinned to cell bottom, body extends up).
Jellies/oozes/spiders render at 1.4x centre-anchored (sprawls outward).
Champion variants stack on top (1.5 × 1.25 = 1.875). Miniboss variants
stack to 1.5 × 1.4 = 2.1, capped at 2.5.

Logical layer (cell, hp, attack adjacency, pathfinding) untouched —
every creature still occupies one cell. The visual scale is purely
sprite-render. Z-ordering means big creatures draw over decor and
adjacent smaller enemies. Screenshot JSON sidecar exposes
`entities.enemies[].visual_scale` and `visual_anchor`.

True multi-cell creatures and tentacle-segment chains are deferred —
the shipped CC0 DCSS pack only contains 32×32 sprites; multi-cell
mechanics need 32×64 art we don't have plus pathfinding/collision
rewrites.

## Sigil floor decorations

Two systems, both shipping in `project/assets/tiles/sigils/` (70 PNGs).

**Single-tile room sigils** (`MapRenderer._stamp_room_sigils`): each BSP
room in stone-tier biomes gets 1-2 random sigil rune marks (`sigil_circle`,
`sigil_cross`, `sigil_algiz_*`, `sigil_y_*`, etc). Per-biome `sigil_set`
array + `sigil_density: [min, max]` field in biomes.json. Wired biomes:
vaults, crypt, tomb, elf, temple, depths, zot, labyrinth, pandemonium.
Skips cells in `vault_results.protected_cells` so vault-stamped features
aren't covered. Caves layouts (rooms == []) skip the pass.

**Multi-tile sigil compositions** via vault `decor_overlays` field. Six
mini-vaults in `data/vaults/sigil_*.json` (3×3 cross, 3×3 pinwheel, 5×1
straight line, 3×3 compass, 5×5 runed circle, 5×3 paired-Y) compose
several pieces into pre-arranged shapes. Stamper writes `decor_marks` to
results, renderer stamps the named texture over the floor cell. Pure
cosmetic, no terrain impact, system reusable for future multi-tile decor
beyond sigils.

Both systems expose their placements in the screenshot JSON sidecar's
`entities.sigils_stamped` and `entities.decor_marks` arrays.

## Logging — structured per-floor + per-run

In `GrindLog.log_line`. Tags:

- `[run]` — `start hp/level/gold`, `end #N victory=… kills=… loot=… …`,
  `auto-grind ENABLED/COMPLETE`
- `[gen]` — per-floor generation: `f=1 biome=lair layout=caves_open
  cells=900 largest=900 regions=1 bbox=… rooms=18 vaults=[…]`
- `[floor]` — per-floor outcome: `f=1 biome=lair ticks=338 kills=6 loot=2
  chests=1 altars=0 fountains=0 portals=0 stalls=0 hp_lost=14`
- `[portal]` — `entered=wizlab -> biome=elf bias=2 on_floor=3`
- `[stall]` — only on actual stalls (bot 120t without movement)
- `[bad-floor]` — generator regression flags
- `[render]` — debugging only: confirms which biome/textures the renderer
  loaded for a build

`[grind-debug]` ticker (every 240 frames in `_tick_bot`) was REMOVED — it
emitted nothing useful and drowned the log.

## Asset atlas — 6945 PNGs catalogued

`project/data/tile_atlas.json` (1.5 MB) is built from DCSS source
`rltiles/dc-*.txt` plus filesystem walk. Per-tile fields: `category`,
`subcategory` (item subcat), `enum`, `biome_tags`, `class_hints`,
`variant_set`, `variant_index`, `directional`, `direction`, `weight`.

Browse interactively: open a local web server in the repo root
(`python3 -m http.server 8080`) and visit `tools/atlas_viewer.html`. Filter
by category / biome / class / subcategory, group by subdir / variant_set.

Rebuild: `python3 tools/build_atlas.py`.

## Test harnesses

### `/screenshot` skill — biome / vault visual verification

```
bash .claude/skills/screenshot/screenshot.sh <biome> [vault|_] [floor]
```

Drives the `DEBUG_FLOOR.txt` marker, launches Godot at 1024×1024, captures
viewport, writes BOTH a PNG and a JSON sidecar, prints both absolute paths.
**The JSON is authoritative.** Use the PNG for shape/silhouette only — color
hallucinations and small-text misreads are common at compressed thumbnail
size. The JSON contains: HUD strings, biome id + display name, layout id,
all loaded floor/wall/overlay textures (resource paths), every
enemy/interactable/loot with cell+kind, room rects, stairs/spawn cells,
ambient settings, modulate values.

Logs land in `logs/screenshots/<timestamp>_<biome>_<vault>_<floor>.log`.
Screenshots in `~/Library/Application Support/Godot/app_userdata/Botter/debug_screenshots/`.

### Save-state isolation

When `AUTO_GRIND.txt` or `DEBUG_FLOOR.txt` markers are present, `main.gd`
sets `SaveState.debug_mode = true`. SaveState then reads/writes
`user://botter_save_debug.json` instead of `user://botter_save.json`.
Live playtest save is untouched by benchmark or screenshot runs.

To reset the debug save: delete `botter_save_debug.json` from the user
data dir. To reset live: delete `botter_save.json`.

### Auto-grind — headless N-run benchmark

```
echo "16,5" > "$HOME/Library/Application Support/Godot/app_userdata/Botter/AUTO_GRIND.txt"
/Applications/Godot.app/Contents/MacOS/Godot --path /Users/dyo/claude/botter/project --headless
```

`<speed>,<max_runs>` in the marker. Bot auto-deploys at N× speed, plays
through `max_runs` complete runs, prints structured logs, exits.
Implementation in `main.gd` `_ready()`.

### Debug-jump — same as `/screenshot` skill but without the screenshot

Marker `<biome>[,<vault>][,<floor>]` in `DEBUG_FLOOR.txt`. Skips garage,
spawns directly into that biome+floor with optional forced vault stamp.
The 4-field form `biome,vault,floor,1` enables screenshot mode (the
`/screenshot` skill drives this).

## Decisions on record

- **Stack**: Godot 4.6.2-stable + GDScript. No C# / GDExtension.
- **Pathfinding**: `AStarGrid2D` over NavigationAgent2D / custom A* —
  engine-native C++, grid-aligned, `set_point_solid` maps 1:1 to wall tiles.
- **Number ceiling**: ~1500 HP / ~300 ATK / ~100 DEF endgame; ~300-400 peak
  damage. User explicitly rejected idle-game number creep.
- **DCSS source**: shallow-cloned (132 MB) into `dcss-source/`. **Research
  only — GPLv2+, never copy code.** Gitignored.
- **DCSS tile pack**: gitignored (35 MB CC0 art); only the curated subset
  under `project/assets/tiles/` ships.
- **Run plan**: currently fully-random per floor. Locked-in DCSS-style chain
  (D:1-3 → Lair:1-2 → …) is the planned default once branches feel
  content-complete.

## Open balance knobs (next time we touch combat)

- **Vault frequency** — ~75-83% per floor. Feels right; may need to dial
  back for atmosphere.
- **Affix tier values** — `data/affixes.json` is conservative right now
  (Strength tier-3 = +7 ATK, Crit legendary = +22%). Tune as playtesting
  reveals what feels good. Crit/haste caps in `bot.recompute_stats`
  (75/200) are also tunable.
- **Modifier difficulty** — Bloodlust ×1.3 enemy stats might be too
  punishing in tier 1; min_tier 2 was the band-aid. Tune `data/modifiers.json`
  effects.
- **Bot upgrade costs** — `data/bot_upgrades.json` matches the doc's
  ×2.5/rank curve. Re-evaluate once gold-per-tier feels real.
- **Salvage gold values** — common 2g .. legendary 200g in
  `_SALVAGE_VALUES`. Currently doesn't feel exciting for low rarities.
- **Aggro range cap (8 cells)** is conservative; may be too restrictive
  on 80×80 maps.

## Save state schema (current)

`save_state.gd::_default()` returns:
- `gold, level, xp` — bot stats
- `inventory: Array[item_instance]` — loose stash
- `equipped: {weapon, armor, helm, boots, shield}` — slots
- `runs_completed, highest_floor` — meta progress
- `unlocked_branches: Array[branch_id]` — starts `["dungeon"]`
- `bosses_killed: {branch_id: count}` — drives stricter unlock rule
- `max_revives: int` — death retreat budget per run (default 3)
- `loot_filter: String` — bot's pickup threshold ("common".."legendary")
- `inventory_cap: int` — auto-salvage threshold (default 50)
- `last_branch: String` — for offline progress
- `branch_modifiers: {branch_id: [modifier_id, ...]}` — current Outpost rolls
- `bot_upgrades: {upgrade_id: rank}` — gold-sink purchases
- `shards: int` — prestige currency stub
- `last_seen_timestamp: int` — Unix time, drives offline calc
