# Botter — Balance Pipeline

The bot plays itself, so balance experiments are unusually tractable: I can
run hundreds of headless A/B comparisons in parallel with the same seeds and
get statistical signal on item/affix/branch tuning questions in minutes.

This doc captures the toolchain. The skills compose:

```
/equip <build>           — write loadout to debug save
/grind <runs>            — play N runs with current debug save
/duel <a> -- <b> -N 20   — A/B two builds, N seeds each
/sweep --slot W ...      — vary one knob, rank results
```

## Foundation pieces

### Seedable RNG (`BOTTER_SEED=<int>`)

`dungeon.gd` seeds both its `RandomNumberGenerator` and Godot's global rng
(`seed()`) at boot. Each floor build re-seeds the global stream from world
rng so combat doesn't consume world entropy between floors. Same seed
+ same save = byte-identical floor sequence + byte-identical combat
outcomes.

The `[run] start ... seed=N` log line stamps the seed for traceability.

Combat IS deterministic under seeding — see "Determinism caveats" below
for the duel implications.

### Save state injection (`tools/inject_save.py`)

JSON-in, debug save out. Validates against `items.json`, `affixes.json`,
`biomes.json`. Affix shorthand: `["strength", 5]` reads tier-5 value (18)
from affixes.json automatically. Item shorthand: `"demon_blade"` =
`{"base_id":"demon_blade"}`.

Routes everything through `botter_save_debug.json` so playtest saves
are untouched.

### `[combat]` log tag

Per-attack structured line in `actor.gd`:

```
[combat] atk=<id> def=<id> wpn=<weapon_id> raw=N crit=0|1 dealt=N
         def_hp=N boss=0|1 mb=0|1
```

Gated on `GrindLog._enabled` so playtests don't spam.

### Grind log parser (`tools/parse_grind.py`)

Returns dataclasses (`GrindResult`, `RunResult`, `FloorResult`,
`CombatEvent`). Used by every skill. CLI mode for ad-hoc inspection:

```bash
python3 tools/parse_grind.py logs/grind/<latest>.log --combat
```

### Balance harness (`tools/balance.py`)

Helper module for `/duel` and `/sweep`:
  - `run_grind(seed, runs, speed, label, invincible)` — drives Godot
    headless, returns when COMPLETE line appears (or timeout).
  - `inject(spec)` — wrapper over inject_save.py.
  - `append_index(entry)` — append one JSON line to
    `logs/balance/index.jsonl`.

Sets `BOTTER_NO_INVINCIBLE=1` by default so wins/losses have signal.

## Determinism caveats

- **Bot invincibility**: auto-grind sets `bot.invincible = true` by default
  to reach floor 10 reliably for procgen audit. The balance skills set
  `BOTTER_NO_INVINCIBLE=1` so the bot can actually die. Pass `--invincible`
  to opt back in (useful when you only care about clear time / damage
  output, not survival).
- **Combat is NOT a separate axis** — under `BOTTER_SEED`, combat outcomes
  are reproducible too. Same seed + same build = identical kills, identical
  damage rolls, identical floor outcomes. This is a feature for
  reproducibility but means seed sensitivity matters: a 20-run duel covers
  20 different floor sequences, not 20 random combat samples on the same
  floor.
- **Different builds on the same seed will diverge floor-by-floor** because
  combat speed differences propagate (build A clears faster, lands on
  floor 2 with different HP, faces same vault but different aggro state,
  etc). The pairing is "same world, different gear" not "same fight,
  different gear" — but that's what we want for build comparison.

## Where data lives

```
logs/balance/
├── index.jsonl                                    # one line per experiment
├── 20260520-180312_grind_duel_demon_s1.log        # per-run log
├── 20260520-180345_grind_duel_demon_s2.log
├── ...
└── 20260520-180712_grind_sweep_arc_blade_s1.log
```

**`logs/balance/index.jsonl`** schema (one JSON object per line):

```json
{
  "ts": 1779290000.0,
  "kind": "duel" | "sweep",
  "label": "demon_vs_rusty",
  "params": {...},
  "a": {"label": "...", "wins": N, "win_rate": 0.6, ...},  // duel
  "b": {...},                                              // duel
  "ranked": [{"label": "...", ...}, ...]                   // sweep
}
```

To query historically:

```bash
# All duels involving demon_blade
jq 'select(.kind=="duel") | select(.params.spec_a // "" | contains("demon_blade") or
                                   .params.spec_b // "" | contains("demon_blade"))' \
    logs/balance/index.jsonl
```

## Workflow examples

### "Is Demon Blade overtuned?"

```bash
duel.py "weapon=demon_blade,Strength5,Crit4 level=30 branch=forge" -- \
        "weapon=runed_warsword,Strength5,Crit4 level=30 branch=forge" \
        -N 50 --label-a "demon" --label-b "warsword"
```

Output: paired comparison across 50 seeds. Look at the win rate Δ — if
demon is +20% over warsword with non-overlapping CIs, that's overtuned.

### "Find underpowered legendary swords"

```bash
sweep.py --slot weapon --values @legendary \
    --base "armor=crystal_plate,Stamina5 level=30 branch=forge" -N 10
```

Output: ranked table. Bottom-3 by win rate are candidates for buffing.

### "Sweep crit cap from 1 to 5 tier"

```bash
sweep.py --affix crit --tiers 1,2,3,4,5 \
    --base "weapon=demon_blade,Strength5 armor=crystal_plate,Stamina5 \
            level=30 branch=forge" -N 10
```

Output: 5 variants, see at what tier crit becomes dominant. Inflection
point informs whether the legendary tier (15%) is too weak/strong.

### "Does a hostile modifier flip the matchup?"

```bash
duel.py "weapon=demon_blade level=30 branch=forge" -- \
        "weapon=demon_blade level=30 branch=forge mods=bloodlust+crowded" \
        -N 30
```

Output: same build, only modifier differs. Win rate delta = how much
those modifiers actually punish you.

## What's not yet built

- **Parallel runner** — sweeps are currently sequential. ~30s/grind ×
  10 variants × 10 seeds = 50 minutes. Multiple Godot instances would
  cut to wall-clock divided by core count.
- **HP-loss telemetry** — currently `[combat] dealt=` is bot's perspective
  only. For "did the bot survive narrowly?" we want HP-loss curves over
  time within a run.
- **Per-affix sweep on multiple slots** — `--apply-to-slot` only varies
  one slot's affix. Can't currently do "weapon Crit4 + armor Stamina5"
  combinatorial.
- **Cross-branch sweeps** — `--branches dungeon,lair,forge` to compare
  the same build's win rate across tiers. Build it when needed.
