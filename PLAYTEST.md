# Botter — Playtest log

Raw observations from live playtests. **Append-only, dated, untriaged.**
This file is the inbox; `TODO.md` is the engineering backlog.

## How this works

**Adding notes (you, post-playtest):** dump observations verbatim into
the latest dated section, or start a new dated section if the prior
one is closed. No editorializing required, no triage required, no
file:line references required. Raw is fine.

**Triaging notes (next session):** sweep `Status: untriaged` items.
For each:

1. **Re-verify against the code.** Player observations are unverified
   evidence — "stats panel is confusing" might already be wired and
   the player just didn't find it; "X is broken" might be a design
   choice. Read the relevant code before patching. Same trust-but-
   verify discipline as the audit findings.
2. **Classify the shape:**
   - **Bug** — code disagrees with intent. Goes into the next opportunistic
     session, or fixed inline if trivial.
   - **UX** — code matches intent but the player can't read it. Goes
     into a UI-cleanup cluster (Tier 1 shape).
   - **Design** — the player wants the game to work differently than
     it does. Becomes its own session brief at
     `~/claude/game-audit/prompts/playtest_<topic>.md` if non-trivial,
     or a TODO.md entry if it's a single decision.
3. **Update status:**
   - `triaged → fixed` (commit hash, terse reason)
   - `triaged → TODO` (link to the new TODO.md row)
   - `triaged → next-session-brief` (link to the new prompt file)
   - `triaged → deferred` (one-line why)
   - `triaged → not-a-bug` (one-line explanation; useful for future-me
     who'll otherwise re-investigate the same observation)

**Cross-linking:** when a note maps to an existing audit finding
(`~/claude/game-audit/findings/AUDIT_REPORT.md`), reference the finding
id in the status. The audit catches code-grounded issues; playtest
catches experience-grounded issues. Where they overlap, both should
know about it.

**Don't delete.** Even resolved items stay in the log — the trail of
what got changed in response to play-feel feedback is durable
project memory.

---

## 2026-06-09 — six notes from a live session

Status legend: `untriaged` | `triaged → fixed` | `triaged → TODO` |
`triaged → next-session-brief` | `triaged → deferred` | `triaged →
not-a-bug`.

### 1. Weapon swing direction wrong when attacking left
**Status:** `triaged → fixed` (Phase 1 sweep, 2026-06-10)

Fix: removed `sign` multiplier in `_play_swing_horizontal()`
(bot.gd:822). The rig's `scale.x = -1` already mirrors the swing into
screen space when facing left; multiplying rotations by `sign` was
mirroring it a *second* time, producing the away-from-enemy arc.

When the bot attacks to the right, the mace swings *toward* the
enemy — looks correct. When the bot attacks to the left, the swing
animation is mirrored such that the weapon appears to swing *away*
from the enemy. Suggests the swing-tween anchor or pivot doesn't flip
in sync with `rig.scale.x` in `actor.gd::_set_facing` /
`_play_swing`.

**Research notes (2026-06-10):**

**Root Cause (Shape: Bug)**

Weapon swing rotation is not direction-aware. When `rig.scale.x` flips
to `-1.0` for left-facing attacks (actor.gd:155, 188), the weapon
sprite's swing rotation tweens remain positive, causing the arc to
swing away from the target instead of toward it.

The weapon sprite is a child of `rig` (bot.gd:520) with `centered=true`,
so it rotates around its own center. When `rig.scale.x = -1.0` mirrors
the rig horizontally, the weapon's coordinate frame flips, but the
tween rotation angles (e.g., `swing_rot = sign * -deg_to_rad(110.0)`
at bot.gd:827) use `sign` to flip the initial arc direction. However,
the final rotation value is applied directly to `weapon_sprite.rotation`
without accounting for the rig's horizontal flip.

**Where to Fix**

1. bot.gd:822-839 `_play_swing_horizontal()` — the `sign` variable
   correctly inverts `windup_rot` and `swing_rot`, but this only
   affects the magnitude. When `rig.scale.x < 0`, the weapon sprite's
   rotation frame is already mirrored, so the rotation must also flip
   its sign.
2. bot.gd:841-882 `_play_swing_overhead_chop()` and
   `_play_swing_upward_thrust()` — these don't use `sign` at all, so
   vertical swings are unaffected, but they should also check
   `_facing_x` for consistency and forward-compatibility.

**Concrete Fix**

In `_play_swing_horizontal()`, `_play_swing_overhead_chop()`, and
`_play_swing_upward_thrust()`:
- Cache `_facing_x` and negate all rotation tweens if `_facing_x < 0`.
- Example: `var facing_mult = 1.0 if _facing_x > 0 else -1.0` at the
  start of each function.
- Apply: `_weapon_swing_tween.tween_property(weapon_sprite, "rotation",
  windup_rot * facing_mult, ...)` instead of raw `windup_rot`.

**Risk Areas**

- Rotation sign flip must apply consistently across all three swing
  types (horizontal, overhead, thrust).
- Test left-facing attacks in-game to confirm the arc now sweeps
  toward the target.
- Check edge cases: tall creatures with apply_visual_scale and negative
  facing; verify lunge + swing compose correctly (see sprite_fx.gd's
  base_scale sync at line 39–40).

### 2. STR/DEX/INT need to be the "core" stats — currently buried + opaque
**Status:** `triaged → fixed` (Phase 4 explainability, 2026-06-10) —
stat_panel.gd now renders an always-visible dim hint line under each
primary stat ("+HP, melee damage" / "+Crit, +Haste" / "+Spell dmg,
area, duration"). Hover still gives the full numeric breakdown via
the existing `_PRIMARY_TOOLTIPS` dict. The hint applies to both the
HUD stats panel and the outpost editable variant.

The Stats panel doesn't lead with STR/DEX/INT, and there's no
indication of what each does. Player should see at a glance: "STR
governs A, B, C; DEX governs D, E; INT governs F, G." Move them to
the top of the stats section + add a one-line explanation per stat
(or a hover tooltip with the full breakdown).

**Research notes (2026-06-10):**

**Problem Shape:** STR/DEX/INT stat descriptions exist
(stat_panel.gd:30-34) with clear one-liners, but are NOT visible to
players. The tooltips are only active when hovering; there's no
always-visible explanation. Players see stats in order (Primary →
Vitals → Combat → Spells → Misc), yet "what does each primary stat
do" is the most fundamental question for build-shaping.

**Current State (stat_panel.gd):**
- Lines 106-115: "Primary" section builds first (good — leading
  position).
- Lines 30-34: `_PRIMARY_TOOLTIPS` dict holds per-stat one-liners
  (STR: +1.5% HP + melee damage; DEX: +0.5% crit + 1% haste; INT: +1%
  spell dmg + 0.5% area/duration).
- Lines 193-196, 217-220: Tooltips attached to stat labels, but only
  on hover (Engine native `tooltip_text`).

**Stat Scaling (stat_calc.gd:362-373):**
- STR excess (lines 373): +1.5% HP per point via `sp_hp_mult`
  multiplier.
- DEX excess (lines 366-367): +0.5% crit + 1.0% haste.
- INT excess (lines 368-370): +1.0% spell damage + 0.5% area + 0.5%
  duration.
- Melee damage: wired to weapon rolls (lines 172-173), not directly
  scaled by STR in current code.

**Gap:** Tooltip reveals don't scale — "Melee weapon damage scales
here" for STR is vague. INT's three bonuses are listed but the
INT-melee path missing. No mention of how spell-class masteries
(of_*_mastery) interact.

**Proposed Fixes:**

1. **Add brief descriptions under each Primary stat label**
   (stat_panel.gd ~line 116):
   - After building the three stat rows (113-115 in read-only mode,
     108-110 in editable), insert inline small-print labels or expand
     tooltip coverage.
   - Option A: Add a 4th helper row per stat showing the tooltip text
     as a dim secondary line (e.g., "Str  [5]  +Crit, +Haste" → new
     row "        → +1.5% HP / Melee dmg").
   - Option B: Widen the label column to fit the one-liner inline
     (requires layout tweaks to avoid truncation).

2. **Verify stat→formula mapping** in stat_calc.gd against the
   tooltip claims:
   - Confirm "Melee weapon damage scales here" for STR — if weapon
     damage is purely gear-based, update tooltip to "Boosts HP +
     equipment carries damage" or add a STR→damage multiplier if
     design intent.
   - Confirm INT scaling of spells wires through spell_data.gd
     correctly.

3. **Consider hover UX improvement:**
   - Current: one-liner on hover only.
   - Better: add a persistent "?" icon next to each stat label that
     toggles a collapsible panel showing all three descriptions at
     once — gives players a "reference card" without per-stat
     hovering.
   - Minimal risk: use same `_PRIMARY_TOOLTIPS` dict, just surface it
     differently.

**Risk Areas:**
- Outpost vs HUD: both use StatPanel (hud_chrome.gd:622-631 embeds
  it). Changes must apply to both screens.
- Layout: adding text risks label wrapping or value truncation in
  narrow panels (low-end ultrawide or portrait fallback). Test all
  viewport sizes.
- Tooltip clipping: if overlapping other UI, native Godot tooltips
  may clamp off-screen.

**Files to Edit:**
- `project/scripts/stat_panel.gd` (lines 106-159 layout build; 30-34
  tooltip dict)
- Optionally: `project/scripts/stat_calc.gd` (lines 362-373 to
  confirm stat scaling vs. claims)

### 3. Kill on-sprite buff icons; add hover tooltips on the buff bar
**Status:** `triaged → partial` (Phase 1 sweep, 2026-06-10) — sprite
overlay defaulted off in HIGH and MEDIUM presets (video_settings.gd:38–47).
Hover-tooltip explanations on the top buff bar still TODO; rolls into
the explainability cluster (#2, #7, status tooltips, affixes).

The buff/debuff stack rendered above the bot's head is redundant
with the top-of-screen buff bar + the HUD Buffs tab. Drop the
on-sprite layer (already gated by `gfx.ench` per HANDOVER, so it's
a video-options default change at minimum). Hovering a buff cell
on the top bar should show a tooltip explaining what it does — god
buffs especially, since they're the most build-defining and the
least self-explanatory.

**Research notes (2026-06-10):**

**Current architecture:**
- **On-sprite buff overlay**: actor.gd:1057-1072 builds `_status_layer`
  (Node2D) above the bot's rig, stacking icon sprites horizontally.
  Gated by `VideoSettings.is_effect_enabled("ench")` at line 1031.
  Icons scale 0.5× and pulse on `pulse: true` statuses (line
  1184-1190).
- **Top-of-screen buff bar**: hud_chrome.gd:1242-1289
  (`_build_buff_bar`) pools 12 Control cells with TextureRect icons +
  Label timer. Line 1296-1372 (`update_buffs`) drives both the bar AND
  the Buffs tab via the same `statuses` dict (line 1371).
- **Tooltip infrastructure exists**: hud_chrome.gd:1349-1351 sets
  `ctrl.tooltip_text` from StatusOverlay.STATUSES[id]["label"/"desc"].
  Already wired, just missing descriptions for many buffs.
- **Status definitions**: status_overlay.gd:27-85 define all 38
  statuses with hardcoded "label" + "desc" fields. God blessings
  (lines 63-84) have descriptions like "+20% ATK (run)" but generic
  statuses (burning, poisoned, etc.) have basic descriptions. No
  descriptions exist for combat mechanics (stealthy, blinded,
  stun/dodge procs).

**Problem shape:**
UX gap — the redundancy is confirmed (HANDOVER line 1935-1936: "both
layers visible"). The task is twofold:
1. Kill the on-sprite overlay by defaulting `gfx.ench = false` in
   VideoSettings (line 40, currently `true`).
2. Ensure tooltips on the buff bar show actionable text for
   build-critical buffs (gods especially).

**Concrete next steps:**
- **Step 1**: video_settings.gd:40 — change `"ench": true` →
  `"ench": false` to default to off (opt-in via Video Settings if
  player wants old visuals).
- **Step 2**: status_overlay.gd:27-85 — audit and expand all "desc"
  fields. Priority: god blessings (already good) and combat mechanics
  (stealthy, blinded, stunned, wounded, shielded). Add mechanical
  clarity like "Stealthy: +25% first hit bonus" (line 51 partial) and
  "Blinded: 30% miss chance" (line 56 has it).
- **Step 3**: Optional: hud_chrome.gd:1351 — confirm tooltip_text
  assignment uses both label + desc. Already correct; no code changes
  needed if descs are populated.

**Risk areas:**
- Players expecting on-sprite visuals on load; mitigation: Video
  Settings → Effects menu clearly labels option as "On-sprite buff
  icons."
- Description field parity: Some god blessings show mechanical
  effects (+25% ATK) while others need the same granularity (e.g.,
  Jiyva regen rates are in code not desc).

### 4. Mystery green debuff icon on low-HP mobs
**Status:** `triaged → fixed` (incidentally, Phase 1 sweep)

Phase 1 disabled the on-sprite buff/debuff overlay by default in HIGH
and MEDIUM video presets (video_settings.gd:38–47). The mystery green
icon was likely the `regen` status (tint 0.55,1,0.6) leaking onto
enemies via projectile pierce-apply, with no on-sprite tooltip wiring
to identify it. With the on-sprite layer off by default, the icon
no longer appears. The top-of-screen buff bar already had tooltips
wired (hud_chrome.gd:1371) for buffs that affect the player; that's
where statuses belong.

Players who turn the on-sprite layer back on (LOW preset has it on by
default for legacy reasons) still don't get tooltips on those icons,
but that's an opt-in performance/visual choice. Native tooltips on
sprite-attached Node2D's would need a separate StatusTooltip class —
deferred until anyone actually requests it.

When attacking mobs, a green debuff icon appears once they reach low
HP. Player doesn't know what it is. Either it's a real mechanic with
no tooltip wiring (fix the tooltip), or it's an icon-leak from a
wrong status (fix the leak). Quick grep through `status_overlay.gd`
for status defs that turn on at low HP threshold should identify it.

**Research notes (2026-06-10):**

**Root Cause: Status icons lack tooltip UI infrastructure.** All
statuses in `status_overlay.gd` (lines 27-85) have label/desc fields
but are never displayed to the player. No mouse handlers exist for
status sprites (actor.gd, hud_chrome.gd).

**Primary Problem (UX Gap):**
- Status overlays render visually on bot & enemies (actor.gd:1028-1077
  add_status → sprite + modulate)
- Tooltip infrastructure exists only for items (ItemTooltip class,
  hud_chrome.gd)
- Green icon is likely "regen" (tint 0.55,1,0.6) or altar blessings
  like "blessed_jiyva"/"blessed_fedhas" (both lime-green tints
  0.4,0.85,0.3x)
- **Fix**: Wire mouse_entered/exited handlers on status sprites to
  show/hide popup label+desc tooltips matching ItemTooltip pattern

**Secondary Issue (Icon Leak Risk):**
- projectile.gd:173-174 allows ANY status on ANY actor (enemy/bot via
  `pierce_apply_status`)
- "Regen" status only applied to bot at dungeon.gd:1777, but if an
  enemy ever gets it, there's no "bot-only" guard
- Todo at dungeon.gd:2993-2996 flags missing enemy-regen ticker
  (skeleton code exists, non-functional)
- **Fix**: Add bot-only status check + clarify which statuses are for
  enemies vs. bot in StatusOverlay definition

**Concrete Next Steps:**
1. Create `StatusTooltip` class (mirror ItemTooltip) or extend
   hud_chrome._on_cell_tooltip to handle status mouse events
2. Wire status sprite mouse_entered/exited in actor.gd's add_status()
   to spawn tooltip at cursor
3. Extract label+desc from StatusOverlay.get_def(id) into tooltip
   (lines 108-109)
4. Optionally: mark bot-only statuses in StatusOverlay const (e.g.
   "bot_only": true) + validate in projectile.gd pierce logic

**Risk:** Tooltip spawning overhead if many statuses are visible;
keep tooltip pooled/cached like ItemTooltip does.

### 5. Lava/water need an overhaul — break maps in many ways
**Status:** `triaged → deferred` (Phase 1 sweep, 2026-06-10) —
research-agent's one-line fix (extend cell-type guard at
map_renderer.gd:197) is wrong: `_pick_edge_overlay` currently
fires when the cell borders WALLS, but wave-edge tiles want the
shoreline (water cell adjacent to FLOOR). Naive extension would
render overlays in the wrong direction. Needs its own session with
the inverted adjacency logic + per-biome edge_overlay configs for
all water/lava biomes (currently only Shoals declares one). Bumped
to its own beat.

Lava and water tiles cause structural problems: areas with no wall
tiles, "water edge" tiles used incorrectly in some biomes. Player
explicitly asks **how does DCSS handle this?** — applies the
CLAUDE.md "lean on DCSS for design decisions" rule directly. The
audit's content-pipeline findings touched terrain but didn't go
this deep. Likely needs its own session brief: read DCSS source for
the `L`/`W` glyph + adjacency-to-wall rules, port the shape to our
biome edge-overlay system, fix per-biome wall-tile coverage so
water/lava cells always have a sensible neighbour.

**Research notes (2026-06-10):**

**Problem Shape:** Design gap — water/lava cells never render
wall-adjacent edge tiles, despite having directional wave-edge assets
(shallow_water_wave_*, deep_water_wave_*). Edge-overlay system only
applies to FLOOR/DOOR/STAIRS_DOWN (map_renderer.gd:197), excluding
T_WATER and T_LAVA. Shoals biome already config'd
"shallow_water_wave" edge_overlay prefix but it's dead code.

**Root Cause:** map_renderer.gd:196-200 condition `(cell == T_FLOOR or
T_DOOR or T_STAIRS_DOWN)` prevents `_pick_edge_overlay` from firing on
water/lava. The `_is_wall_or_out` adjacency logic (line 428-431) works
for any cell type but never executes for liquid terrain.

**DCSS Parallel:** DCSS tilepick.cc:200-207 assigns TILE_DNGN_LAVA /
TILE_DNGN_DEEP_WATER / TILE_DNGN_SHALLOW_WATER as base tiles (no
autotile), but DCSS's tileset includes directional wave-edge variants
for shoreline polish — asset coverage exists in both codebases.

**Concrete Next Steps:**
1. **map_renderer.gd:197** — extend condition to include `cell ==
   C.T_WATER or C.T_LAVA`
2. **`_pick_edge_overlay()`** — handle liquid overlay selection (may
   need density/patch tuning; biomes.json already has it for Shoals)
3. **biomes.json** — audit all biomes with `"liquid_type": "water"` or
   `"lava"` to add/fix edge_overlay prefixes (dungeon_sewer, swamp,
   forge, etc.)
4. **Edge Case:** Ensure wall-count logic (full/cardinal/diagonal)
   handles lava/water identically to floor (no special rules needed)

**Risk Areas:** Visual regression if wave-edge tiles overlap badly;
performance (additional overlay lookups per liquid cell); biome
configs may need density tuning (patch_density=0 for Shoals suggests
wave-tiles replace patches entirely).

### 6. Portal opt-out + Football Manager–style bot behaviour config
**Status:** `triaged → next-session-brief` (Phase 4, 2026-06-10) —
this is a design-heavy beat (CLAUDE.md "Bot AI is the actual game"),
not a quick fix. The cheap part — `state["skip_portals"]` toggle in
the outpost instructions tab + `Portal.should_skip()` override — is
~30 lines, but that's just the seed. The full vision (FM-style
profile: skip portals / loot priority / engage HP threshold / etc)
needs a design pass on the full instruction surface before any code.
Bumped to its own session brief, candidate path:
`~/claude/game-audit/prompts/playtest_bot_behaviour.md`.

Player observation: **does getting sent into a portal screw your
run?** Portals can be harder than the home branch. If the player's
goal is to clear the floor, an unintended portal entry is
progression-negative.

Proposed direction: greatly expand the **character instructions**
panel in the outpost so the bot's behaviour is configurable like a
Football Manager player profile. Examples:
- Skip portals (yes / sometimes / always)
- Prioritise looting over fighting (or vice versa)
- Engage / retreat at HP threshold
- ...what else?

This is the actual-game work per CLAUDE.md ("Bot AI is Botter-original.
This is the actual game.") — the football-manager framing is a strong
design unlock and almost certainly wants its own multi-beat session
chain. Worth a dedicated prompt file (`playtest_bot_behaviour.md`)
that captures the full instruction surface before any code lands.

**Research notes (2026-06-10):**

**Current State:** Bot always targets portals when visible via
`_nearest_interactable()` (dungeon.gd:1965–1973). Portals inherit
`Interactable` base class (interactable.gd:22) with empty
`should_skip(_bot: Bot) -> bool`, so no opt-out mechanism exists.
Outpost already has a character instructions tab (outpost.gd:748–782)
with one working toggle: `loot_filter` (saved to
`state["loot_filter"]`, used by `LootDrop.should_skip()` at
loot_drop.gd:142–144). Instructions panel reads/writes save state;
bot skips loot below threshold per run-init
`LootDrop.loot_filter_min_rank`.

**Problem Shape:** Design gap + UX gap. Player perception: portals
often harder than home branch, entering one mid-run can lock you into
a risky floor. Current AI treats portals like any loot drop — finds
them, enters them unconditionally. DCSS precedent: explore-stop flags
let the player configure pause points (ES_PORTAL, ES_STAIR, ES_ITEM).
Botter needs similar behavior knobs.

**Concrete Proposal:**
1. **Portal opt-out flag** (core): Add `skip_portals: bool = false`
   to save state. Portal class overrides `should_skip(bot: Bot) ->
   bool` to read `dungeon.run.skip_portals_enabled` (via run state,
   mirroring loot_filter pattern).
2. **Add to instructions tab** (UI): CheckBox control in outpost.gd's
   `_build_instructions_tab()` (~line 748) labeled "Skip portals" →
   toggles `state["skip_portals"]`, saved immediately.
3. **Extend for FM-style config** (follow-up): Add knobs for retreat
   HP threshold (dungeon.gd:1930–1947 has retreat logic already), loot
   priority (greedy vs. conservative), and enemy avoidance
   aggressiveness. Each is a `should_skip()` call on Portal / Enemy /
   Loot or a priority reweight in the AI decision tree.

**Risk Areas:**
- Run-init must wire `skip_portals` into Portal.should_skip() via
  dungeon's run state (line 334 already caches
  `loot_filter_min_rank`).
- portal.gd has no `should_skip` override yet (line:1-91 — add
  override at ~line 70, after `on_interact_complete`).
- Save state migration needed if schema adds new boolean
  (save_state.gd §4 migration path).

**File:line references:**
- Portal decision: dungeon.gd:1965–1973
- Portal skip hook: portal.gd:1–91 (add override)
- Interactable base: interactable.gd:22
- Loot filter precedent: loot_drop.gd:142–144, dungeon.gd:334
- Instructions tab: outpost.gd:748–782
- Run state wiring: run_state.gd:37–44 (portal fields already live
  here; add `skip_portals_enabled`)

### 7. Spell scaling stat (STR / DEX / INT) isn't legible
**Status:** `triaged → fixed` (Phase 4 explainability, 2026-06-10) —
item_cell.gd now paints a corner letter glyph (S/D/I in red/green/blue)
on paperdoll spell cells, on top of the existing class-color border.
Border-only was too subtle at 32-56px; the letter resolves the scaling
stat unambiguously. Tooltip "Scales: …" line was already present
(item_tooltip.gd:421).

Player can't tell which spell scales off which primary stat. Per
HANDOVER.md the assignments exist (Spinning Axes / Holy Beam = Str,
Chain Lightning = Dex, Fireball / Frost Nova = Int) and there's a
class-color story (Red=Str, Green=Dex, Blue=Int) wired into species
preview + spell cell borders, but it's not landing in-game. Likely
needs: scaling stat shown on the spell tooltip + (probably) a
visible hint on the spell cell in the HUD spell row, not just on
character creation. Pairs with note #2 (STR/DEX/INT need to be the
"core" stats, currently buried).

**Research notes (2026-06-10):**

The spell scaling stat assignment IS partially implemented but
incomplete:

**Current state:**
- spell_archetypes.json: All spells have `primary_stat` field
  (str/dex/int) ✓
- Tooltip rendering: "Scales: Strength/Dexterity/Intelligence" with
  spell-class color already renders at item_tooltip.gd:416 ✓
- Spell cell border: Logic wired to show spell_class_color
  (red/green/blue) at item_cell.gd:182-189, active for role=
  "paperdoll" + slot_id begins_with("spell") ✓

**The gap:**
The visual cue (border color) is too subtle to read at a glance on
small HUD cells (32-56px). Player doesn't see the stat scaling
without hovering for the tooltip. Per task statement "it's not
landing in-game" — the border color likely works in code but doesn't
register as a legible UI signal.

**Concrete fixes needed:**
1. Make the spell-class border more visible: bump border_width from
   2.5 to 3.0-3.5 in item_cell.gd:189, or add an inner accent line
2. Add a stat icon/label on the spell cell itself (e.g. small
   "S"/"D"/"I" glyph bottom-left, or color tint overlay) so the
   scaling stat is obvious without tooltip
3. Consider: spell cell background tint (faint color wash) + thicker
   border as dual visual cues

**Risk areas:**
- item_cell.gd render() is called from hud_chrome.gd:1531 during
  update_equipped — confirm paperdoll cells update on equip
- UITheme.spell_class_color values are correct (red=0.95,0.30,0.30;
  green=0.50,0.95,0.40; blue=0.45,0.85,1.00) but may blend into cell
  background at small scales
- DCSS precedent: Crawl shows spell schools via color (but with
  larger UI, player experience differs)

### 8. Race selection feels low-stakes; slot limitations not visible
**Status:** `triaged → next-session-brief` (Phase 4, 2026-06-10) —
two-part. The surfacing fix (show octopode/naga slot conversions on
character_create) is a UI-cleanup beat using existing
`SpeciesData.disallowed_slots()` / `slot_conversions()` data. The
identity-mechanics half (per-race signature passives — felid forbids
weapons, deep dwarf can't regen, etc) is a design pass that needs
direction on which mechanics are worth porting and what the idle-
game frame does with them. Bumped to its own brief.

Player observation: **picking a race seems like a boring decision.**
The current shape is stat tweaks (atk_pct / def_pct / hp_pct), some
flavor tags (vampire→vampiric), and slot conversions
(octopode → 4 rings, naga → 2 rings) — but the slot limitations
aren't surfaced on the character-create UI, and the stat differences
read as numbers rather than identity.

Two sub-questions:
- **Surfacing**: the UI should make slot limitations explicit
  (octopode "no body armor / boots / helm — gains 3 extra ring
  slots", naga "no boots — gains 1 extra ring slot",
  felid/spriggan etc). Currently the player has to discover these
  by trying to equip and being silently blocked.
- **Design**: race choice needs more *identity* than stat tweaks.
  DCSS races each play distinctly (felid attacks unarmed and
  forbids weapons; deep dwarf can't regenerate naturally; vampire
  has hunger states). What's our equivalent? Per-race signature
  mechanics (passives that change combat shape, not just numbers)
  would make the choice feel like a build decision rather than a
  cosmetic one.

Worth pairing the surfacing fix with a design pass on
per-race mechanics — character_create currently shows a stats row
+ starter spell + class color; could also show a "Racial:
&lt;mechanic&gt;" line under the species name.

**Research notes (2026-06-10):**

**Problem shape:**
Slot limitations for races like octopode (4 rings, no armor/boots/
helm) and naga (3 rings, no boots) are NOT surfaced during character
creation. The character_create.gd renders a stat-mod table
(HP/ATK/DEF/etc) but never mentions slot conversions.
character_create.gd:128–312 shows only stat summary;
species_data.gd:87–90 defines `slot_conversions()` but it's read only
by save_state.gd and hud_inventory_controller.gd at runtime.

**Surface area:**
1. **Character create preview pane** (character_create.gd:152–220, fn
   `_render_stat_table`): Render an additional section below the stat
   table that lists disallowed and converted slots. Use
   `SpeciesData.disallowed_slots()` (species_data.gd:96–102) and
   `SpeciesData.extra_ring_slots()` (species_data.gd:115–121).
2. **Slot info in preview** (character_create.gd:276–311): Add a new
   row group e.g. "Equipment shape" showing "Armor: converted to extra
   ring (ring#2)" or "Boots: forbidden" using slot_conversions dict.
3. **Naga lore already hints** (species.json:66): "Cannot wear boots —
   no feet to put them on" is present but buried in lore text; UI
   should make it EXPLICIT as a slot affordance.
4. **Octopode lore mentions tentacles** (species.json:126): "no torso
   for armor, no feet for boots, no head for helms — but tentacles
   for trinkets" is flavor; needs mechanical translation.

**Implementation steps:**
- Extend `_render_stat_table()` to call
  `SpeciesData.slot_conversions(sp.id)` and render "Slots converted:
  armor→ring, boots→ring, helm→ring" below the innate_tags block.
- Or add a new section "Available slots" listing which are disallowed,
  which are converted, and how many ring slots total.
- Color conversions green (good for identity), disallowed red (loss).
- Consider adding `signature_mechanic` string field to species.json
  (e.g., octopode→"ring-stacking", naga→"no-boots serpent") for
  future race-identity UI work per DCSS spirit (DCSS source player.h
  has body_shape enum).

**Risk areas:**
- Reflow: adding a "slots" section to preview may require layout
  tweaks (preview_stats VBoxContainer growth).
- Copy coherence: verify lore + slot affordances align (some lore
  already hints at slots, some doesn't).
- Future: DCSS races have deeper mechanical identity (deep dwarf
  can't regen, felid forbids weapons, vampire drains). Botter
  currently only models slot restrictions; no deeper mechanics coded
  yet.

File references: character_create.gd:207–312, species_data.gd:87–130,
species.json:63–145 (naga/octopode entries), hud_chrome.gd:66
(EQUIPPED_SLOTS constant for reference).

### 9. Items show `+0` stat lines (e.g. "+0 projectiles" on spells)
**Status:** `triaged → fixed` (Phase 1 sweep, 2026-06-10)

Fix: simplified `format_affix_lines()` to skip any affix whose rolled
value is 0 (affix_system.gd:264). Removed the range-bounds dance that
was still letting `lo=0, hi=1, midpoint=0` cases through. Single
guard now: `if v == 0: continue`.

Some items render stat lines that read `+0` — visible example was a
spell item showing "+0 projectiles." Either the item genuinely rolled
a 0 on that stat (in which case the line should be hidden, not
rendered as +0 noise), or there's a tooltip-rendering bug where a
stat key exists with value 0 and the formatter doesn't filter it.
Quick search through `affix_system._format_stat_line` /
`format_item_tooltip` for unconditional renders should turn it up.

Cosmetic at first glance but it's the kind of polish gap that makes
the game feel unfinished — every "+0" line implies "we forgot to
filter this" to a player.

**Research notes (2026-06-10):**

**Problem Shape:** Rendering bug in `format_affix_lines()` — range
affixes with low=0 and hi≥1 bypass the zero-filter and produce "+0"
lines after midpoint rounding.

**Root Cause:** affix_system.gd:269–275.
- Current logic skips range affixes only if BOTH lo AND hi equal 0
- Range [0,1] has lo=0, hi=1 → condition fails → midpoint rounds to
  0 → renders "+0"
- Flat affixes filter correctly (v==0 case)

**Concrete Fix:**
1. Replace the range check (line 272) from `if lo == 0 and hi == 0:`
   to `if lo == 0 and hi <= 0:` (or equivalently, skip if
   `max(lo, hi) == 0`)
2. Consider also filtering if midpoint rounds to 0: `var mid =
   int(round((lo + hi) / 2.0)); if mid == 0: continue` — more explicit
   but matches the comment intent

**Risk:** Low. Only affects tooltip display; no combat/balance logic.
Existing affix tiers show min=1 for damage types, but range [0,1] is
theoretically possible in future data. Test spell items post-fix.

**File:Line:** affix_system.gd:269–275 (format_affix_lines function)

---

## 2026-06-10 — six notes from a live session

Status legend: `untriaged` | `triaged → fixed` | `triaged → TODO` |
`triaged → next-session-brief` | `triaged → deferred` | `triaged →
not-a-bug`.

### 1. Bot occasionally picks up two completely identical items
**Status:** `triaged → deferred` (Phase 1 sweep, 2026-06-10) —
research-agent's instance_id-collision diagnosis is wrong: instance_id
collision wouldn't make stats/affixes/quality identical, only the ID
string. Walked the spawn paths (dungeon.gd:1535–1541, 1600–1602,
2348–2353) and the affix roller (affix_system.gd:75–148) — each item
consumes RNG draws sequentially, so back-to-back items use distinct
state. One plausible visual-only false-positive: two common-rarity
items rolling 0 affixes + same base + no enchant + same quality look
identical even though they're different instances; this is data, not
a bug. Real repro needs instrumentation: log instance_id + affixes
hash on every pickup, watch for true duplicates next playtest. No
speculative fix — bumped to next playtest with logging.

Rare occurrence: bot picks up two items that are *fully identical* —
same base (e.g. blue boots), same affixes, same quality, same stats.
Either loot-roll RNG is collapsing onto the same seed when two drops
happen close together (same-frame RNG state? shared seed?), or the
inventory dedup/stack logic is letting truly identical instances
coexist when they should merge / re-roll. Worth grepping
`loot_table.gd` / wherever drops roll for any shared-rng-state
pattern, and checking whether equipment items should ever be
considered "stackable identical."

**Research notes (2026-06-10):**

**Root cause identified**: Instance ID collision in
LootFactory._gen_instance_id() at loot_factory.gd:274-275. The
function generates `"%d_%d" % [Time.get_unix_time_from_system(),
rng.randi()]`. When multiple items drop in rapid succession (same
frame/loop iteration), the timestamp component returns the same
millisecond value, making collisions possible if both the timestamp
AND rng.randi() happen to match.

**When the bug occurs**:
- Rare pack leaders drop 2 items (dungeon.gd:1521)
- Boss kills via drop_count loop (dungeon.gd:1535-1541) generate
  multiple instances in quick succession
- Chest picks generate 2-3 items at once (dungeon.gd:1593,
  loot_factory.gd referenced)
- All paths call `create_item_instance(rng, picked, items_db)`
  sequentially in a tight loop, immediately calling
  `_gen_instance_id(rng)` each time

**No inventory dedup layer**: hud_inventory_controller.gd:519 and
:548 unconditionally append instances. No check for duplicate
instance_id or matching (base_id + affixes + quality + tint +
meta_rarity).

**Concrete fixes**:
1. **Replace timestamp with counter**: Change loot_factory.gd:274-275
   to use a static atomic counter or UUID v4 instead of
   `Time.get_unix_time_from_system()`, eliminating collision risk
   entirely.
2. **Fallback dedup (defensive)**: Add a sanity check in
   hud_inventory_controller.gd:517-527 (complete_loot_pickup) to
   reject items where instance_id already exists in loot_segments,
   logging a warning.
3. **RNG sequencing**: Verify that each `create_item_instance` call
   consumes enough RNG state that sequential calls in a loop can't
   produce identical rolls (currently affixes + meta + tint + enchant
   rolls should differ, but verify).

**Risk areas**: The timestamp-based approach might have been chosen
for debugging/logging; ensure counter-based IDs don't break save
serialization or reproduction logs. Test rare pack drops and boss
multi-loot scenarios post-fix.

### 2. Affix names are opaque to the player — need stat explanations
**Status:** `triaged → fixed` (Phase 4 explainability, 2026-06-10) —
two changes:
- affix_system.gd: new `_STAT_DESCRIPTIONS` dict + `description_for_stat()`
  helper. Keyed by the affix's `stat` field (not the flavor name), so
  "of Bloodletting" with stat=lifesteal_pct gets "Heal for a portion
  of damage you deal." 41 stat keys covered.
- item_tooltip.gd: when Alt is held, each affix line gets a dim
  description sub-line above its existing debug-detail line. Existing
  hotkey hint "[Alt] affix detail" still surfaces the binding.
Self-explanatory stats (+5 HP) are skipped to keep tooltips compact.

Player sees an item "of bloodletting" and has no idea what that does.
Affix names are flavor-coded but the actual mechanical effect isn't
surfaced. Two proposed surfaces:
- **Hold Alt** on an item tooltip → expand the affix lines to include
  their stat effect ("of bloodletting: +X% lifesteal" or whatever the
  real implementation is).
- **Hover the stat panel** → show what each stat governs (pairs with
  PLAYTEST 2026-06-09 #2 — STR/DEX/INT explanation tooltips).

This is the same readability gap as note #2 from 2026-06-09 (stats
buried + opaque) and #7 (spell scaling stat illegible). Affix
mechanics need to live somewhere the player can actually read them.

**Research notes (2026-06-10):**

**Problem shape:** Affixes like "of bloodletting" have no visible
explanation — players see only the flavor name and can't infer the
stat effect. The tooltip currently renders affix names + rolled
values (affix_system.gd:256–277, item_tooltip.gd:423–458) but no
descriptions.

**Current architecture:**
- Affixes defined in `/project/data/affixes.json` carry `id`, `name`,
  `stat`, `kind` (flat/pct/range/flag), and `tiers`. No `description`
  field yet.
- Tooltips already detect Alt-hold via `UILayout.alt_held()`
  (ui_layout.gd:51–55) to show extended details (quality percentile,
  affix tier-band breakdown, iLvl component breakdown).
- Enchants already use a BLURB map (affix_system.gd:395–447) —
  demonstrates the pattern works.

**Next steps (concrete):**
1. **Add `description` field to affixes.json** per-affix (e.g.,
   `"description": "Converts 3% of damage dealt into healing"`).
   Format: one-liner that names the stat + explains the mechanical
   effect. ~40 affixes × ~30s each.
2. **Extend `AffixSystem._make_alt_line`** (item_tooltip.gd:465–502)
   or create a new `_make_affix_description_line()` helper to render
   the description when Alt is held, placed below the rolled-stat
   line. Dim + smaller font, same as current alt-detail pattern
   (color: 0.55,0.55,0.5).
3. **Update tooltips' affix rendering** (item_tooltip.gd:444, 457) to
   call the new description renderer when `alt_held` is true. Reuse
   the existing Alt conditional so "expanded affix detail" includes
   both tier-band AND mechanical explanation.

**Risk:** Affix names are flavor and descriptions must mechanically
accurate — if descriptions drift from actual combat code (actor.gd,
spell effects) they'll mislead. Validate by spot-checking 3–5 affixes
post-write: does "Converts 3% damage → heal" match `lifesteal_pct`
scaling in actor.gd::attempt_attack?

**No data migration needed** — adding a new optional JSON field is
backward-compatible. Affixes without `description` render cleanly
(description line just doesn't render). Already-shipped items
unchanged.

### 3. Bought 4 items in shop, only 3 in inventory back at outpost
**Status:** `triaged → fixed` (Phase 2 inventory cluster, 2026-06-10) —
shop.gd `_buy_one()` now checks inventory cap before append
(shop.gd:733). Buys at-or-over cap are rejected with a 1-second
red-flash on the new "Carrying N / cap" counter in the inventory pane.
Pre-fix the buy succeeded, gold was deducted, item appended, then
silently dropped on next save round-trip via salvage flush. Paired
with default cap raise to 200 (see #7).

Player purchased 4 items in the run shop, returned to outpost, only
3 of those items appeared in stash/inventory. Either:
- Save/load drops a purchased item between run-end and outpost-load
  (serialization gap — does shop-purchased loot route through the
  same persist path as drop loot?),
- Inventory cap silently drops the overflow (no warning to player),
- Shop UI is letting the player "buy" without actually granting the
  item (gold deducted, item never lands in inventory).

Concrete repro is hard without knowing which item was lost. Check
shop purchase flow → inventory append → end-of-run save serialization
for any silent-drop branches. This is exactly the kind of bug that
erodes player trust fastest.

**Research notes (2026-06-10):**

**BUG FOUND: shop.gd `_buy_one()` bypasses inventory cap enforcement.**

Shop purchases append directly to `state.inventory` (line 748) with
zero validation. During runs, items route through `hud_inv_cache` →
`complete_loot_pickup()` → `maybe_auto_salvage()` which silently
salvages overflow once inventory exceeds cap
(hud_inventory_controller.gd:562–604). Shop purchases skip this
entirely.

**Repro:** Player at cap=50 with 50/50 items. Buy 4 items → inventory
becomes 54/50, silently truncated on next save/load cycle.

**Root cause:** shop.gd:748 `state.inventory.append(inst.duplicate(true))`
→ SaveState.save_state() → Outpost._ready() reloads fresh state,
dropping overflow items silently (no warning, no salvage credit).

**Shape:** UX gap — shop doesn't enforce inventory contract. Silent
drop on reload erodes trust.

**Fix targets:**
1. shop.gd:733–756 `_buy_one()`: Check `inventory_cap` (from
   save_state:732, default 50) before append. If at cap:
   - Option A: Reject purchase ("Inventory full")
   - Option B: Auto-salvage oldest item (matches run-loot precedent)
   - Option C: Allow overflow + auto-salvage on outpost return
     (consistent with runs)

2. Add `inventory_cap` read to shop._ready() or compute per-purchase
   (account for BotUpgrades.total_for_stat as outpost.gd:773 does).

3. Risk: Run-end `inv.maybe_auto_salvage_if_pending()`
   (run_state.gd:400) already handles cap breach from normal loot.
   Shop auto-salvage must use same STARTER_IDS guard
   (hud_inventory_controller.gd:581) so rusty_dagger/tattered_hide
   aren't lost.

**DCSS:** Shops don't cap inventory — DCSS has no inventory system
(unlimited pickup). Port concept is "respect the game's cap" not
"copy DCSS behavior."

### 4. Tooltips render partially offscreen, especially with shift-compare
**Status:** `triaged → fixed` (Phase 3 tooltip layout, 2026-06-10)

Three changes:
- hud_chrome.gd `_hud_clamp_tooltip` now accepts a size param (defaults
  to TOOLTIP_W × 240 for the initial render, where the actual size
  hasn't resolved yet). Mirrors outpost.gd's existing signature.
- hud_chrome.gd `_process` re-clamps the primary tooltip every frame
  using the actual `_hud_tooltip.size`. Mirrors outpost.gd:185 — that
  path already worked, the HUD path was missing it.
- Both `_process` paths now re-flow stacked compare tooltips using
  each panel's *actual* height (was hardcoded 220 per panel, which let
  tall multi-affix ring tooltips overlap each other and the bottom
  margin clamp to 220 of slack ignored taller panels).

Tooltip positioning doesn't clamp to viewport edges. Worst when
shift-compare is active (two tooltips side-by-side). Need:
- Viewport-edge clamp on tooltip position (flip to other side of
  cursor / item slot when there's no room).
- Compare tooltip should pick the side opposite the primary tooltip,
  and both should respect the clamp.

**Research notes (2026-06-10):**

**Problem shape:** Two related positioning bugs in hud_chrome.gd and
outpost.gd.

1. **Primary tooltip uses hardcoded height (hud_chrome.gd:414, line
   322)** — `_hud_clamp_tooltip()` uses 240px height estimate, but
   ItemTooltip.TOOLTIP_W=280. Position is set BEFORE `render_for()`
   completes, so actual size (resolved async) is unknown. Compare:
   outpost.gd:193 uses Vector2(280, 200) as estimate to
   `_clamp_tooltip_position()`, which accepts size param. hud_chrome
   has no size param fallback.

2. **Compare tooltips clamp Y but ignore primary tooltip height for
   bottom margin** — hud_chrome.gd:400 clamps to `view.y - 220.0`
   (hardcoded 220px guess). When primary tooltip is tall + near
   screen bottom, compare panels stack into the clamp floor,
   rendering offscreen. outpost.gd:239 has identical issue, but
   outpost also lacks dynamic height awareness.

3. **Missing dynamic repositioning loop** — outpost.gd:185 updates
   tooltip.position every `_process` frame using `_tooltip.size`
   (actual rendered size). hud_chrome.gd:_process() does NOT update
   `_hud_tooltip.position` after render. This means if actual height
   differs from estimate, tooltip stays in wrong spot.

4. **Compare tooltip placement (left/right offset) doesn't adjust for
   primary's final position** — hud_chrome.gd:384–386 decides
   left/right based on primary's initial x, but primary may shift
   after clamping. Compare then anchors from clamped position with no
   secondary clamp on compare's x if it pushes left off-screen.

**Concrete fixes (priority order):**

- *hud_chrome.gd:322* — After render, call `_hud_clamp_tooltip()`
  again with actual size: `_hud_tooltip.position =
  _hud_clamp_tooltip(get_viewport().get_mouse_position() +
  Vector2(16, 16), _hud_tooltip.size)` (requires sig change to
  `_hud_clamp_tooltip`).
- *hud_chrome.gd:411–417* — Update `_hud_clamp_tooltip(anchor,
  sz=null)` to accept optional size param; default to hardcoded
  estimate if sz is null for backwards compat.
- *hud_chrome.gd:_process()* — Add loop to re-clamp
  `_hud_tooltip.position` every frame (like outpost:185), post-render.
- *hud_chrome.gd:398–403* — Use actual `_hud_tooltip.size.y` instead
  of 220 guess for y_offset and clamp. Also reconsider left/right
  logic if primary was clamped (use `_hud_tooltip.position`, not
  `_hud_tooltip.position` before clamping).
- *outpost.gd:239* — Same height clamp issue; recommend similar fixes
  for consistency.

**Risk:** Dynamic repositioning in `_process` could cause jitter if
tooltip height changes (unlikely once render is done). Height
estimate fallback (200–240px) handles typical single/dual-stat items
safely.

### 5. Items with long names overflow tooltip bounds
**Status:** `triaged → fixed` (Phase 3 tooltip layout, 2026-06-10)

Fix: item_tooltip.gd:193 sets the title label's
`custom_minimum_size = (TOOLTIP_W - PADDING * 2, 0)` and `autowrap_mode
= AUTOWRAP_WORD_SMART`. Long meta-prefixed names ("Primal Ancient
Celestial Boots of the Vanguard") now wrap inside the panel instead
of painting outside it. Other body labels (desc/blurb/flavor) were
already wrapped; title was the only outlier.

Tooltip width is fixed (or min-width-bounded) and long item names
exceed it, painting outside the tooltip frame. Either widen the
tooltip dynamically with the longest line, wrap the name across
multiple lines, or clip + ellipsize. Pairs with #4 (tooltip
positioning) — same surface, same pass.

UI clipping rule from memory: nothing should ever escape the bounds
of its UI section. Tooltips count.

**Research notes (2026-06-10):**

**Problem:** Item title label at item_tooltip.gd:193 renders with
fixed-width constraint `TOOLTIP_W = 280` (line 20), but
`_make_label()` (lines 605-614) creates Label nodes with NO autowrap
or `custom_minimum_size` set. Long item names (e.g. "Celestial Boots
of the Ancient Vanguard") paint outside the 280px frame, violating
the UI clipping rule.

**Root cause:** Label created at line 193 gets added to VBoxContainer
(line 194) but has no size constraint. The VBoxContainer itself has
no `clip_contents` set (line 72-76). Child labels in the tooltip are
wrapped (lines 314, 339, 367) EXCEPT the title — design
inconsistency. The constant-width design (TOOLTIP_W = 280) conflicts
with uncontrolled title width.

**Solutions (pick one):**

1. **Wrap title (preferred):** Add `custom_minimum_size =
   Vector2(TOOLTIP_W - PADDING*2, 0)` + `autowrap_mode =
   TextServer.AUTOWRAP_WORD_SMART` to title label (line 193). Matches
   pattern already used for desc/blurb/flavor labels. Title will
   split across multiple 16px lines.

2. **Dynamic width:** Compute title width after render, expand
   TOOLTIP_W. Breaks compact layout; less maintainable.

3. **Ellipsize:** Set `custom_minimum_size`, `clip_text = true`.
   Loses information, poor UX for long names.

**Concrete changes:**
- Line 193: modify `_make_label()` call to accept optional
  `custom_minimum_size` param, OR
- Line 193: post-create, set `title.custom_minimum_size =
  Vector2(TOOLTIP_W - PADDING*2, 0)` + `title.autowrap_mode =
  TextServer.AUTOWRAP_WORD_SMART`
- Optional: add `_vbox.clip_contents = true` (line 72) as
  defense-in-depth for all child overflow

**Risk:** Title wrapping increases tooltip height slightly
(especially for meta-prefixed names like "Primal Ancient Celestial
Boots"). Existing title-pulse tweens (lines 210-214) should still
work on wrapped text (Godot bug? — test before commit).

DCSS parallel: crawl doesn't have item name overflow — tile UI
constrains descriptions strictly. This is Botter-original UX
requiring Botter-specific solution.

### 6. Item tooltip effects (e.g. 20% quality) feel great
**Status:** `triaged → not-a-bug` (positive feedback)

Player called out the cool effects on item tooltips when rolling
notable stats (e.g. 20% quality). Logging this so the next person
who's tempted to "simplify" tooltip rendering knows the FX are
load-bearing for game feel. Don't strip them.

### 7. Inventory cap doesn't seem to work — and should be much higher anyway
**Status:** `triaged → fixed` (Phase 2 inventory cluster, 2026-06-10)

Fix landed across four files:
- save_state.gd: default `inventory_cap` 50 → 200. New saves start at
  200; existing saves migrate via new schema v9 (any save still on the
  legacy 50 gets bumped to 200; user-upgraded values >50 are
  preserved).
- shop.gd: enforce cap on `_buy_one()` (shop.gd:733). Pre-fix the
  shop bypassed cap entirely and items were silently dropped on save
  round-trip. Buys at full now reject with a red-flash counter.
- shop.gd: added "Carrying N / cap" counter to the inventory pane
  (shop.gd `_render`).
- outpost.gd + hud_inventory_controller.gd: matched fallback default
  to 200 so all read paths agree.

The "doesn't seem to work" perception was three things stacked: shop
bypass (real bug — fixed), soft-cap-only-flushes-at-floor-end (working
as designed; auto-salvage runs on floor-end + run-end + menu-exit),
and 50 being too low to feel like a cap (design — fixed).

Player observation: the inventory cap doesn't appear to enforce
during play (items keep stacking in past where the cap should kick
in). Pairs with #3 above (shop overflow) — research there confirms
shop bypasses cap enforcement entirely (shop.gd:748 appends without
validation), but if the run-loop auto-salvage path
(hud_inventory_controller.gd:562–604) is also misbehaving, the cap
is functionally absent.

Two-part ask:
- **Bug**: figure out why the cap isn't enforcing (auto-salvage
  threshold, maybe_auto_salvage_if_pending hook, cap value sourcing).
- **Design**: cap should probably be a lot higher than the current
  default (50). The player wants to hoard between runs more than
  the current value allows. Pick a new target — 100? 200? — and
  consider whether the cap exists primarily for perf (tooltip
  rendering, save size) or for game-economy reasons.

**Research notes (2026-06-10):**

**Root cause identified:** The inventory cap enforcement is a *soft
cap* that only triggers at specific points (run-end, floor-end,
menu-exit), not on every pickup. Three separate bypass vectors exist:

1. **shop.gd:748 bug** — `_buy_one()` appends directly to
   `state.inventory` with zero validation. No cap check, no link to
   the HUD inventory system's `pending_salvage_check`. Items bought
   from the shop skip `maybe_auto_salvage_if_pending()` entirely.
   (Same root as #3 above.)
2. **Loot pickup bypass** — `complete_loot_pickup()`
   (hud_inventory_controller.gd:517) appends to `loot_segments` and
   only sets `pending_salvage_check = true`. Salvage only runs on
   explicit `maybe_auto_salvage_if_pending()` calls
   (hud_inventory_controller.gd:617). Until floor/run-end flush,
   inventory can exceed cap.
3. **Missing validation at write time** — run_state.gd:373 & 411
   write `inv.hud_inv_cache` directly to `save.inventory` with no
   truncation. If overflow happened during a run (e.g., rapid loot
   pickup), the oversized inventory persists to disk.

**Key code paths:**
- Cap definition: save_state.gd:732 (default 50) + upgrades via
  BotUpgrades.total_for_stat (outpost.gd:773,
  hud_inventory_controller.gd:106)
- Soft-cap check: hud_inventory_controller.gd:562 (only in
  `maybe_auto_salvage()`)
- Pending flag: hud_inventory_controller.gd:526, 618 (set during
  pickup, consumed at flush)
- Enforcement gaps: shop.gd:748 (no check), run_state.gd:373/411 (no
  truncation)

**Design recommendation:** 200 cap balances perf (tooltip rendering
O(n), save size ~20KB at 50 items → ~80KB at 200) with game feel. At
200: player can comfortably hoard mid-run without constant salvage
prompts; forces meaningful trash/treasure decisions.

**Concrete fixes needed:**
1. Add cap validation in shop.gd:748: check `len(state.inventory) <
   inventory_cap_for_state(state)` before append, or reject purchase.
2. Add truncation in run_state.gd:373/411 post-write:
   `save.inventory = save.inventory[:inventory_cap_for_state(save)]`
3. Increase default in save_state.gd:732: `"inventory_cap": 200` (or
   150 if perf testing shows tooltip lag at 200).
4. Optionally defer shop purchase if at cap, or warn player in shop
   UI.

### 8. Firefox performance is still terrible; other browsers fine
**Status:** `triaged → partial` (Phase 4, 2026-06-10) — added a
dismissable Firefox-only banner via JavaScriptBridge in main.gd's
`_install_firefox_warning`. Detects Firefox via UA, shows a one-time
"recommend Chrome or Safari" notice at the top of the page,
remembers dismissal in localStorage. Doesn't fix the actual perf gap
(that's a deeper diagnostic + WebGL feature-gate beat — bumped to
its own session). At least players know now.

Web build performance is "completely shite" on Firefox but works
well in every other browser (Chrome, Safari, etc). Not a regression
from last session — long-standing.

Likely root cause is Firefox's WebGL Compatibility renderer being
slower than Chrome's, or Firefox's WASM JIT pipeline behaving
differently on our single-threaded build. The CLAUDE.md HTML5
playbook covers Compatibility-renderer perf rules but assumes
Chrome-class perf as the floor. May need a Firefox-specific
diagnostic pass: profile a Firefox session with `[perf]` log lines,
compare to Chrome, identify whether the bottleneck is shader
compile, texture upload, or per-frame draw cost.

Worst case: ship a "browser detected: Firefox" warning advising
Chrome for now. Better case: identify the specific WebGL extension
or shader pattern Firefox hates and replace with a fallback (we
already have desktop-vs-web feature gates via `OS.has_feature("web")`
— add a Firefox-specific gate if needed). Use
`navigator.userAgent` via `JavaScriptBridge.eval` to detect.

**Research notes (2026-06-10):**

**Problem Shape**: Firefox WebGL Compatibility renderer underperforms
Chrome on Godot 4.6 single-threaded WASM build. Existing web perf
gates (fog_overlay.gd:126 caps lights to 8, enemy.gd:102 disables
threat outlines, light_spec.gd:122 disables shadows) apply
uniformly — no Firefox-specific tuning yet.

**Existing Infrastructure**:
- `PerfMon.spike_tick()` (perf_mon.gd:129–164) detects multi-second
  stalls; already filters false positives (tab backgrounding >15s,
  unfocused window). Spike context stamping works.
- Web build exports single-threaded WASM (export_presets.cfg:
  `thread_support=false`, `variant/extensions_support=false`).
- Shader caching pattern in UITheme exists (ui_theme.gd); CLAUDE.md
  §330–421 documents material caching rules.

**No Firefox Detection Today**: Suggests `navigator.userAgent` via
`JavaScriptBridge.eval()`. Zero browser-sniff code currently exists.

**Diagnostic Path**:
1. **Add browser detection utility** (new file `browser_detection.gd`
   or extend PerfMon):
   - Cache result of `JavaScriptBridge.eval("navigator.userAgent")`
     at startup
   - Expose `is_firefox()` / `is_chrome()` / `detected_browser:
     String` properties
   - File:line: Would live at ~scripts/browser_detection.gd, called
     from main.gd `_ready` after build-version stamp
2. **Firefox-specific gates** (parallel to existing
   `OS.has_feature("web")`):
   - Reduce light count further (4 vs 8) on Firefox
     (fog_overlay.gd:126)
   - Consider disabling additional effects (bloom, heat_haze toggles
     already exist in VideoSettings)
   - Cap simultaneous shader compiles (no API for this; fallback is
     pre-warm at startup)
3. **Instrumentation**: Extend PerfMon tags to isolate WebGL-specific
   costs:
   - Add `TAG_SHADER_COMPILE`, `TAG_TEXTURE_UPLOAD`,
     `TAG_BATCH_SUBMIT` if possible via `RenderingServer` perf
     monitors
   - Compare Firefox `[perf]` logs vs Chrome to identify bottleneck
     (shader vs texture vs draw cost)

**Risk Areas**:
- `JavaScriptBridge.eval()` only runs on web; must guard with
  `OS.has_feature("web")` or will error on desktop.
- Godot 4.6 WebGL Compatibility has no built-in shader JIT control —
  vendor fallbacks (ANGLE, SwiftShader) may vary by browser.
- Worst-case scenario (unidentifiable perf cliff): Ship a
  browser-detect warning in HUD or on itch page recommending Chrome
  as primary.

**Concrete Next Step**: Add browser_detection.gd utility + one
Firefox-specific light cap (lights=4) in fog_overlay.gd. Validate
against grind perf logs before broader feature gates.

---

<!-- New playtest sessions append below. Keep this comment as the
     insertion marker so future-me drops new dated sections in the
     right place. -->
