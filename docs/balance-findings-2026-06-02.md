# Botter — Balance Findings (Pinned Re-run, 2026-06-02)

The earlier balance-findings doc (`balance-findings-2026-05-20.md`) was
collected while the harness had a bug: every grind ran with random-mix
biomes regardless of the labeled tier. The branch-pinning fix
(commit 481c006) plumbed `BOTTER_FORCE_BIOME` through, and these
findings are from the first full re-run with actually-tier-locked
floors.

220 grinds, ~3.5 hours wall-clock. Build = `steel_longsword level=30`
(no armor, no other gear) so the affix variable is isolated.

---

## Headline numbers

### Cliff investigation (N=50 each, no affixes)

| Branch | Wins | Death floor mode |
|---|---|---|
| Dungeon T1 | 96% (46/48 valid) | Trivial. 1 death on f1, 1 on f2 |
| Forge T5 | 0% (0/50) | 46% die on f3 (miniboss), 34% on f4 |

### 6-affix matrix at vaults T4 (N=20 each, +1 tier-5 affix)

```
affix       wins/n  avg_floor  avg_kills  med_hp_lost  avg_hp_lost
strength5   0/20    4.65       100.6       148          140
stamina5    0/20    4.50        90.0        84          118
agility5    0/20    5.00       109.8        83          114
regen5      0/20    4.60       103.0         0           10
crit5       0/20    4.50        96.2       153          182
haste5      0/20    4.60        95.7       114          164
```

---

## Findings (sharpened from prior random-tier data)

### 🔴 Tier curve is brutally non-linear

The same level-30 bot with steel_longsword + 1 tier-5 affix:
- **T1: 96% wins** (cakewalk, won 46 of 48)
- **T4: 0% wins** (reaches f4-f5, dies short of boss)
- **T5: 0% wins** (dies on f3 miniboss)

There's no in-between. The jump from T1 cake to T4 wall is the issue —
not a single biome's tuning. Either T2-T3 needs to actually challenge,
or T4-T5 needs gear gates.

This contradicts the earlier "floor-4 cliff at 34% across all branches"
finding, which was a mixed-tier averaging artifact. Each tier has its
own bottleneck:
- T1: no cliff
- T4: dies approaching the boss (f6)
- T5: dies on f3 miniboss

### 🔴 Regen5 is wildly overtuned (confirmed, sharper)

Median HP-lost = 0 across 20 vaults runs. Average HP-lost = 10. Next-best
affix (Agility5) is at 83/114 — **8-14× more damage taken** than regen5.

At +10 HP/sec (legendary tier), the regen rate exceeds the chip-damage
rate from most enemy interactions. The bot heals between fights faster
than it gets hurt during them. That's a one-affix free pass on attrition.

The earlier matrix at random-mix biomes showed median 0 HP-lost too —
this finding is robust across seed sets.

### 🔴 Strength5 + Crit5 actively hurt survival

Both at 140-182 avg HP-lost — *worse* than no affix (which we don't have
direct data for, but Agility5 at 114 with same gear is a proxy for
"defensive baseline"). The reasoning:

- More damage per hit = enemies die ~5-10% faster
- But the bot still spends N seconds in combat range
- More attack cycles = more enemy attack windows = more damage taken
- Net effect: kills slightly more, takes meaningfully more

Both are pure-DPS affixes with no defensive secondary. At endgame
numbers they're competing with Stamina/Agility/Regen and losing.

### 🟡 Agility5 quietly best on the kill+survive axis

5.00 avg floor reached (highest). 109.8 avg kills (highest). 114 avg
HP-lost (third lowest). +11 DEF reduces most enemy hits to 1 damage
floor.

If Regen5 gets capped, Agility5 likely emerges as the new best survival
affix.

### 🟡 Stamina5 / Haste5 are sensible mid-tier

Stamina5 at 84/118 HP-lost is doing what it advertises — passive HP
buffer. Haste5 at 114/164 outperforms Strength5 (140/140) which makes
sense: faster swings = enemies die faster than equivalent-damage
slow swings.

---

## Tuning targets

These are concrete numbers the data supports. Each one is a single
JSON edit + a /duel validation.

### 1. Cap regen at 3 HP/sec at legendary

`data/affixes.json` regen tiers: `[1, 2, 4, 6, 10]` → `[1, 2, 3, 3, 3]`

Rationale: The chip-damage rate at vaults T4 is ~3-5 HP/sec depending
on encounter density. Capping regen below that rate means **regen still
helps** (heals between fights, supplements fountain heals) but doesn't
trivialize attrition. Drops the legendary tier from "always pick this"
to "good defensive option among several."

Validation: re-run regen5 at vaults T4 N=20 with patched values. Median
HP-lost should rise from 0 to ~30-50 (similar to Stamina5/Agility5).
If still dominant, drop further to [1, 1, 2, 2, 3].

### 2. Soften T4 enemy stats by ~15%

`data/biomes.json` doesn't directly hold enemy stats — they're in
`enemies.json` with per-tier scaling in `constants.gd::TIER_SCALE`.
Current: `[1.0, 1.4, 2.0, 3.2, 5.0]`. The 2.0→3.2 jump (T3→T4) is
2.4×, vs the 1.4→2.0 jump (T2→T3) at 1.43×.

Soften: `[1.0, 1.4, 2.0, 2.7, 4.5]` (T4 from 3.2× to 2.7×, T5 from
5.0× to 4.5×). Smoother ramp, T4 becomes possible without min-maxed
gear.

Validation: cliff investigation N=50 at vaults T4 with patched scale.
Win rate should rise from 0% to ~10-20% (a level-30 unequipped bot
should sometimes succeed at T4, not always succeed).

### 3. Strength + Crit need secondary effects (deferred)

Pure DPS affixes don't compete with defensive ones in this game's
attrition model. Two paths:

- **Wire flavor-tag mechanics** (already on roadmap as "First flavor-
  tag mechanic wired"). E.g. `vampiric` heals % of damage on hit;
  applied to Strength tier-4+ items, gives Strength a defensive
  secondary. Or `precision` boosts crit damage and adds 5% crit chance
  per attack since last crit (anti-streak comp).
- **Tweak crit multiplier**: currently 1.5× at all tiers. Bump to
  1.5×/1.7×/2.0×/2.3×/2.5× per tier. Makes high-tier crit feel
  qualitatively different.

Both are bigger beats than this tuning pass. Defer.

### 4. Tier-2/3 needs more challenge data (deferred)

We have data for T1 (96%) and T4 (0%) but no direct measurement of T2
or T3. Before tuning T4 down, run cliff N=50 at lair T2 + at swamp T3
to confirm the gap is what we think.

Defer — small experiment, ~1 hour, but not blocking the regen fix.

---

## What this run validated about the pipeline

- Branch pinning works correctly. Cliff-dungeon at 96% (was 4% under
  random-mix) and cliff-forge at 0% (was 8%) — completely different
  pictures. The data is now actionable.
- HP-lost remains the high-resolution metric. With wins all at 0% in
  the matrix, HP-lost still resolved a 14× difference between regen5
  and crit5.
- The 220-grind, 3.5-hour batch finished cleanly (no timeouts, all
  parsed). The hardened harness (run_experiment.sh + sweep partial
  persistence) earned its keep.
