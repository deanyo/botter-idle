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
**Status:** `untriaged`

When the bot attacks to the right, the mace swings *toward* the
enemy — looks correct. When the bot attacks to the left, the swing
animation is mirrored such that the weapon appears to swing *away*
from the enemy. Suggests the swing-tween anchor or pivot doesn't flip
in sync with `rig.scale.x` in `actor.gd::_set_facing` /
`_play_swing`.

### 2. STR/DEX/INT need to be the "core" stats — currently buried + opaque
**Status:** `untriaged`

The Stats panel doesn't lead with STR/DEX/INT, and there's no
indication of what each does. Player should see at a glance: "STR
governs A, B, C; DEX governs D, E; INT governs F, G." Move them to
the top of the stats section + add a one-line explanation per stat
(or a hover tooltip with the full breakdown).

### 3. Kill on-sprite buff icons; add hover tooltips on the buff bar
**Status:** `untriaged`

The buff/debuff stack rendered above the bot's head is redundant
with the top-of-screen buff bar + the HUD Buffs tab. Drop the
on-sprite layer (already gated by `gfx.ench` per HANDOVER, so it's
a video-options default change at minimum). Hovering a buff cell
on the top bar should show a tooltip explaining what it does — god
buffs especially, since they're the most build-defining and the
least self-explanatory.

### 4. Mystery green debuff icon on low-HP mobs
**Status:** `untriaged`

When attacking mobs, a green debuff icon appears once they reach low
HP. Player doesn't know what it is. Either it's a real mechanic with
no tooltip wiring (fix the tooltip), or it's an icon-leak from a
wrong status (fix the leak). Quick grep through `status_overlay.gd`
for status defs that turn on at low HP threshold should identify it.

### 5. Lava/water need an overhaul — break maps in many ways
**Status:** `untriaged`

Lava and water tiles cause structural problems: areas with no wall
tiles, "water edge" tiles used incorrectly in some biomes. Player
explicitly asks **how does DCSS handle this?** — applies the
CLAUDE.md "lean on DCSS for design decisions" rule directly. The
audit's content-pipeline findings touched terrain but didn't go
this deep. Likely needs its own session brief: read DCSS source for
the `L`/`W` glyph + adjacency-to-wall rules, port the shape to our
biome edge-overlay system, fix per-biome wall-tile coverage so
water/lava cells always have a sensible neighbour.

### 6. Portal opt-out + Football Manager–style bot behaviour config
**Status:** `untriaged`

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

### 7. Spell scaling stat (STR / DEX / INT) isn't legible
**Status:** `untriaged`

Player can't tell which spell scales off which primary stat. Per
HANDOVER.md the assignments exist (Spinning Axes / Holy Beam = Str,
Chain Lightning = Dex, Fireball / Frost Nova = Int) and there's a
class-color story (Red=Str, Green=Dex, Blue=Int) wired into species
preview + spell cell borders, but it's not landing in-game. Likely
needs: scaling stat shown on the spell tooltip + (probably) a
visible hint on the spell cell in the HUD spell row, not just on
character creation. Pairs with note #2 (STR/DEX/INT need to be the
"core" stats, currently buried).

### 8. Race selection feels low-stakes; slot limitations not visible
**Status:** `untriaged`

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

### 9. Items show `+0` stat lines (e.g. "+0 projectiles" on spells)
**Status:** `untriaged`

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

---

<!-- New playtest sessions append below. Keep this comment as the
     insertion marker so future-me drops new dated sections in the
     right place. -->
