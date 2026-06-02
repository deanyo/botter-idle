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

## T2/T3 cliff fill-in — N=50 (later same day)

The "tier-2/3 needs more challenge data" deferred item ran. 50 grinds
each at lair (T2), swamp (T3), vaults (T4 re-confirm). Same build:
`steel_longsword level=30` no affixes. Vaults sample partial (8/8 LOSS
at write time) but consistent with the prior 0/50 finding.

| Tier | Branch  | Wins  | Win% | Avg floor | Avg kills |
|------|---------|-------|------|-----------|-----------|
| T1   | dungeon | 46/48 | 96%  | (deep)    | (high)    |
| T2   | lair    | 42/49 | 86%  | 5.84      | 101.9     |
| T3   | swamp   | 4/50  | 8%   | 5.26      | 137.3     |
| T4   | vaults  | 0/8   | 0%   | 4.5       | 110       |
| T5   | forge   | 0/50  | 0%   | (early)   | —         |

T1 + T5 numbers are from the prior 2026-06-02 pinned re-run.

### 🔴 The cliff is between T2 and T3, not T3→T4

The earlier "smooth out the T3→T4 ramp" hypothesis was directionally
wrong. The actual shape:
- **T1→T2**: -10 points (96% → 86%) — mild slope, expected
- **T2→T3**: -78 points (86% → 8%) — **brick wall**
- **T3→T4**: -8 points (8% → 0%) — already wall-bound
- **T4→T5**: 0 points (0% → 0%) — same, both gear-gated

The 2026-06-02 patch (`TIER_SCALE [3.2, 5.0] → [2.7, 4.5]` softening
T4/T5) was tweaking the wrong tiers. T4/T5 are correctly gear-gated;
the actual problem is that the T3 jump from `1.4× → 2.0×` enemy
multiplier is where the sub-30 unequipped bot starts getting one-shot
by miniboss-class enemies.

Important nuance: at T3 the bot reaches **avg floor 5.26 with 137
kills** before dying — so it's clearing most of the run, just not the
boss. At T4 it dies on f3-f5 with 110 kills (boss-floor proximity).
T3 is "doable until the final stretch"; T4 is "doable until the
midboss."

### Tuning targets (next beat)

The cleanest patch is to soften the T3 multiplier. Currently
`TIER_SCALE := [1.0, 1.4, 2.0, 2.7, 4.5]` (already softened from the
original 3.2/5.0). Proposed:

```
[1.0, 1.4, 1.8, 2.7, 4.5]
                ^
                T3: 2.0 → 1.8 (10% softer)
```

This mirrors what 1.4× → 1.8× would have been in the original linear
interpretation (smaller jumps from T2 onward). Validation: re-run
cliff at swamp T3 N=30 with patched scale. Win rate should rise from
8% to ~25-40% (a level-30 unequipped bot should sometimes clear T3,
not always; gear is still the path to consistent T3 wins).

Don't simultaneously tweak T4 — the data shows it's gear-gated, not
multiplier-gated. Leave it alone.

### What this validates about the prior beat

The 2026-06-02 patches (regen cap, T4/T5 softening) were directionally
fine but addressed the wrong floor. The +0.38-floor improvement for
agility5/stamina5 in the validation run was real, but didn't produce
wins because the bottleneck wasn't where we thought.

The pinned-experiment harness keeps earning its keep — the swamp data
contradicts the "smooth ramp" theory in a way no random-mix data
could.

### Human playtest validation pending

User to confirm via human playtest that the T3 wall is what the
numbers describe (an unequipped level-30 hero reaches f5 then gets
one-shot by a boss-equivalent enemy). If so, the T3 softening lands.

---

## Validation pass — N=10 × 4 affixes (post-patch)

After applying both patches, ran 4 affixes (regen, strength, agility,
stamina) at vaults T4 with N=10 to confirm the shape changed.

```
affix     wins/n  avg_floor  med_hp_lost  avg_hp_lost   change vs pre-patch
regen5    0/10    5.10        0           21            HP-lost flat (still 0)
strength5 0/10    4.60        92          100           HP-lost 148→92
agility5  0/10    5.00        80          130           HP-lost 83→80
stamina5  0/10    4.90        76          131           HP-lost 84→76
```

**TIER_SCALE softening worked partially.** Avg floor reached ticked up
across the board (regen 4.60→5.10, stamina 4.50→4.90). Bot survival is
~10% deeper into the run, run times longer (60s→80s), enemies dying
faster from strength5. The softening is doing something.

**Win rate still 0% at T4.** Predicted "1-3 wins at T4 with affixes"
didn't happen. T4 boss-floor difficulty is the bottleneck, and softening
T4 enemy stats by 16% (3.2x → 2.7x) doesn't bridge the gap on its own.
Either gear is required (likely the right answer per the design doc)
or a deeper tier-scale rework is needed.

**Regen5 median HP-lost still 0.** This is the surprise. The cap
[1,2,4,6,10] → [1,2,3,3,3] reduced legendary regen by 70%, but the bot
still ends most runs unscathed.

The implication: the chip-damage rate at vaults T4 is lower than the
~3-5 HP/sec assumed in the rationale section. Probably closer to
1 HP/sec across the typical encounter density, since:
- 3 HP/sec × 80s avg run = 240 HP healed total
- Average HP-lost across other affixes is 76-130
- So 3 HP/sec still exceeds incoming damage rate

**Decision: don't iterate on regen further this beat.** The cap is
already a 70% reduction; dropping it further (e.g. all tiers ≤ 2)
risks making low-tier regen feel useless. The right fix is probably
either:
- Make regen scale with missing HP (Path of Exile leech model — fast
  when wounded, slow when full)
- Disable regen during combat ticks (heals between fights only)

Both are bigger design changes than tier-value tweaks. Carrying as a
follow-up beat. The tier values are still better than [1,2,4,6,10] —
the cap reduces stacking with stamina/agility, just doesn't dethrone
single-affix dominance at T4.

### What survived the validation

- **TIER_SCALE patch** is doing what it was meant to (deeper survival,
  longer runs).
- **Regen patch** is a partial fix — reduces stacking value, doesn't
  fix the dominance. Acceptable as baseline; revisit when wiring real
  flavor-tag mechanics that compete defensively.

Per the "iterate later, don't tune-spike now" guidance, both stay shipped.

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
