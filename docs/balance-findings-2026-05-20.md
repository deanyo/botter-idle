# Botter — Balance Findings (2026-05-20)

First production-scale balance experiments using the new pipeline
(`/equip`, `/duel`, `/sweep` skills + `tools/inject_save.py` +
`tools/parse_grind.py`). 210 grinds total across two experiments,
~165 minutes wall-clock.

This is a snapshot of insights, not a tuning patch. Each finding
points at concrete `data/affixes.json` or design changes worth
considering. None applied yet.

---

## Experiment 1: Crit tier curve (120 grinds)

**Setup.** Crit affix at tiers 1-5 across dungeon (T1) / vaults (T4) /
forge (T5), N=8 seeds per variant. Build: `steel_longsword level=30`
(no armor — keeps DEF low so combat actually matters). Same seed
sequence across all variants for paired comparison.

**Outcomes** (see `logs/balance/index.jsonl` for raw data):

```
                tier1  tier2  tier3  tier4  tier5
dungeon (T1):    25%    12%    12%     0%    12%
vaults  (T4):     0%     0%     0%    12%    12%
forge   (T5):    12%     0%    25%     0%    12%
```

Win rate is statistically flat — N=8 produced overlapping CIs. But the
secondary metrics (kills/run, elapsed) revealed real signal:

- **Forge kills: 77 → 78 → 107 → 107 → 125** as crit tier rises 1→5.
  ~30% kill-rate boost confirms crit *works*; just doesn't translate
  to survival.
- **Cross-branch curve is identical** — crit doesn't shine more at
  higher tiers. If the design intent was "crit becomes powerful at
  endgame", current numbers don't realize it.

**Key insight:** Crit is a kill-rate stat, not a survival stat. More
crit ⇒ more enemies dead, but the bot still dies on the same floor.

## Experiment 2: 6-affix head-to-head (90 grinds)

**Setup.** All 6 affixes (Strength/Stamina/Agility/Regen/Crit/Haste)
at tier 5 vs each other. Build: `steel_longsword + 1 tier-5 affix
level=30 branch=vaults`. N=15 seeds, same sequence for all variants.

**Win rate ranking** (CIs all overlap — categorical signal weak at
N=15):

```
rank  affix       wins  win_rate
1     regen5      2/15  13%
2     haste5      1/15   7%
3     stamina5    1/15   7%
4     agility5    1/15   7%
5     crit5       1/15   7%
6     strength5   0/15   0%
```

**HP loss** (the actual signal):

```
strength       median=122  avg=138   ← worst
crit           median=128  avg=140   ← worst (tied)
haste          median=42   avg=82
stamina        median=54   avg=87
agility        median=21   avg=58
regen          median=0    avg=7    ← outlier
```

Regen5 is **20× better than Strength5 on HP-lost.** Median 0 — half the
runs ended with full HP. Strength5 had 0 wins out of 15.

## Findings

### 🔴 Strength is undertuned at endgame

+18 ATK (legendary) doesn't matter when most enemies die in 1 hit
already. The "headline number" is misleading — it's a wasted slot vs.
basically any other affix. **0 wins out of 15.**

Possible fixes:
- Tier curve goes non-linear: legendary = +50 ATK + secondary effect
  (knockback / armor pen / on-kill bonus).
- Strength caps damage variance instead (always max-roll on common
  enemies, +X% to bosses).
- Accept Strength is the "early-game cornerstone" affix and rebrand —
  it's strictly the right pick for a level-1 bot, just irrelevant
  past mid-game.

### 🔴 Crit is also undertuned

Same root cause: more kill-power doesn't help when killing isn't the
bottleneck. Crit5 + Strength5 were tied for worst HP-lost.

Crit could use:
- A secondary effect on crit-success: heal % HP, refund attack cooldown,
  AoE splash, +shield charge.
- Higher crit multiplier at legendary tier (current 1.5×, all tiers).
- Or split into "crit chance" (low tiers) and "crit damage" (high tiers)
  so the affix changes character through progression.

### 🔴 Regen is overtuned at high tiers

+10 HP/sec (legendary tier) effectively neutralizes attrition at vaults
T4. Median HP-lost was 0 — the bot was healing faster than it took
damage. This is a fountain replacement.

Possible fixes:
- Cap regen rate (e.g. ≤ baseline regen × 2).
- Scale with missing HP (Path of Exile leech style — fast when low,
  slow when full).
- Disable regen during combat (heals between fights only, keeps idle-
  game flavor without trivializing combat).
- Shorten regen tick interval but reduce per-tick (still healing, but
  vulnerable to burst damage).

### 🟡 Strength and Crit are functionally equivalent

Both gave +kills but +HP-lost. They're the same archetype: "more DPS,
no defense." If both stay this way, they shouldn't both exist as
separate affixes — pick one and replace the other with something with
a different role (e.g. Lifesteal as its own affix vs. flavor tag,
Vigor as +max-HP-on-kill, etc).

### 🟡 Agility is balanced about right

+11 DEF (legendary) reduced incoming damage to ~1/hit since most
enemies hit raw=10-25. Avg HP-lost 58 vs Strength's 138. Underrated
but balanced.

### 🟢 Stamina is fine

+90 HP cushion buffers single big hits. Median HP-lost 54 — the affix
is doing exactly what it advertises. Perfectly mid-tier.

### 🟡 Haste competitive with Strength

+32% atk speed = effectively +32% Strength. Slightly better HP-lost
(82 vs 138) because faster swings → enemies die before second
attack lands. Could swap with Strength as the "DPS affix" without
changing balance much.

## Difficulty curve finding (separate from affixes)

Across both experiments, the **floor 4-5 cliff is real and large**:

```
Crit experiment (no armor, multiple branches): 34% deaths on floor 4
Matrix experiment (no armor, vaults only):     37% deaths on floor 5
```

Adding any affix bought ~1 floor of survival on average. The cliff
moved one floor with affix support — proving it's not random. Likely
cause: floor-3 miniboss damage + no fountain pre-floor-3 → bot enters
floor 4-5 already chip-damaged → boss-prep enemies finish them off.

Possible fixes:
- Guarantee at least one fountain on floors 1-3 (chest-bias system
  exists, can extend to fountain placement).
- Reduce floor-3 miniboss damage scaling.
- Buff baseline regen (without affixes) so the bot heals slowly
  between fights even unequipped.
- Compensate the floor-3 → floor-4 transition with an explicit
  "rest cell" guarantee.

## Methodology lessons

1. **N=8 is too small for win-rate comparisons.** CI widths are ~50
   percentage points — anything subtler than a 30pp delta is invisible.
   Use N=30+ when the question is "does this build win more."
2. **HP-lost is a 20× higher-resolution metric than win-rate.** Use it
   as primary for affix/build comparisons; only dial up to win-rate
   N=30+ when HP-lost is suggestive but not decisive.
3. **Same-seed paired comparison works.** Same seed across variants
   produced the expected pattern (seed=2007 won for haste/stamina/
   regen, lost for strength/crit — consistent with HP-lost ranking).
4. **`steel_longsword + level=30 + no armor` is a good test build.**
   Low DEF makes combat actually matter (raw - def > 0), level 30 has
   enough HP to differentiate, no armor variance keeps the affix
   variable isolated. Use this as the standard balance build.

## What's next (queued experiments)

- **Regen tier curve t1/t3/t5 N=20** — confirm regen-overtuned
  hypothesis with tighter sample. Should show flat curve at low tiers
  then dramatic jump at t5 if the hypothesis is right.
- **Strength+Haste vs Strength** — does stacking DPS affixes beat
  spreading? Tests whether the "two DPS slots" build is viable.
- **Floor-4-5 cliff investigation N=50** — same build, different
  branches, large N → tight floor-death histogram. Confirms cliff
  isn't random and pinpoints which floor specifically.
