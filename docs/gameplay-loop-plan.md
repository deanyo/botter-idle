# Botter — Gameplay Loop Plan

Written: 2026-05-15. This is a design document for the dev agent to follow.
It does not supersede CLAUDE.md rules — those remain binding.

---

## The Problem Statement

The current game has everything it needs to be great but lacks the scaffolding
that gives idle players a reason to come back. Runs are random, there's no
progression ladder, the inventory fills up with hundreds of identical items,
and nothing explains what to do next. This plan fixes all of that.

Research anchor: Melvor Idle is the closest reference point — a RuneScape-
inspired idle game with dungeons gated behind gear checks, where every
dungeon clears grants the gear you need for the next one. That loop works
because clearing a dungeon feels like unlocking a door, not just adding a
number. We want exactly that feeling.

---

## Part 1 — The Three Loops

Every lasting idle game has three nested loops. Design every feature against
this model first.

### Loop 1 — Core (2–8 minutes per cycle)

Deploy bot → bot clears a branch (5 dungeon floors + 1 boss floor) → return
to Garage with loot → equip anything better → redeploy.

This loop must feel fast, legible, and rewarding on every cycle. The first
cycle should take under 5 minutes for a new player.

### Loop 2 — Session (30–90 minutes)

Unlock a new branch by defeating a boss → push into a harder tier where
current gear isn't enough → farm the previous tier until the loot upgrades
are sufficient → defeat the new boss → unlock the next branch.

This loop is the "hook" — the player has a clear next target and knows
exactly what they need. Every session should end with either a new branch
unlocked or a clear upgrade path identified.

### Loop 3 — Meta (days to weeks, deferred to post-MVP)

Prestige / Rebirth: reset run progress and level, keep permanent upgrades
bought with Shard currency earned from boss kills. Shard upgrades include
base stat boosts, bot AI config unlocks, and cosmetic options. Prestige is
NOT in scope for the current build — but the save schema should leave a
`shards` field placeholder so the migration isn't painful.

---

## Part 2 — The Branch Tier System

### Structure

Each branch is a 5-floor dungeon + 1 boss floor (6 floors total). This
replaces the current random 10-floor run. The boss floor is always floor 6;
the mini-boss rule (currently on floors 5/10/15/20/25) moves to boss floor
only.

The player picks their target branch in the Garage before deploying. Branches
they haven't unlocked are visible but locked with a tooltip explaining the
unlock condition. This creates aspiration without confusion.

### Combat Rating (CR) Gate

A single number that summarises the bot's current power, shown prominently
in the Garage UI:

```
CR = (level × 10) + (total_atk × 1.2) + (total_def × 2) + (total_hp × 0.1)
```

Each branch has a `cr_min` (can enter) and `cr_recommended` (can safely idle).
If the bot's CR is below `cr_recommended`, the HUD shows a warning:
"Your bot may struggle here — recommended CR is X." The bot can still enter;
it may die and return early with partial loot. That's fine — it creates a
"one more upgrade" moment.

### The Five Tiers

All 24 existing biomes map onto five tiers. Unlock conditions are cumulative:
clearing a boss in a tier unlocks that tier's siblings and gates to the next.

#### Tier 1 — The Dungeon (starter)

```
dungeon → dungeon_dark → mines
```

- **CR gate:** 0 (always available)
- **Run plan:** 5 floors of dungeon/dungeon_dark/mines mix + 1 boss floor
- **Boss:** Minotaur (current)
- **Boss loot:** Guaranteed uncommon weapon. First clear also grants
  `unlock: tier2` flag saved to state.
- **Enemy HP/ATK scale:** current values (base)
- **Gold dropped:** 5–15 per floor

Tier 1 is the tutorial tier. It should take a new player 3–5 minutes to clear
once. A fully geared player should clear it in under 1 minute (so farming it
is a trivially fast gold loop if they ever need to grind gold).

#### Tier 2 — The Surface (unlocked: defeat Minotaur)

```
lair, forest, orc, temple
```

- **CR gate:** 50 (clear Tier 1 boss once)
- **Each branch:** 5 floors of its biome pool + 1 boss floor
- **Bosses:** Lair → Hydra, Forest → Forest Drake, Orc → Orc Warlord, Temple → High Priest
- **Boss loot:** Guaranteed rare item on first clear. Subsequent clears: rare-weighted drop.
- **Unlock condition for Tier 3:** Clear any 2 Tier 2 bosses.
- **Enemy scale:** ×1.4 HP and ATK vs Tier 1
- **Gold dropped:** 20–50 per floor

Players can choose which Tier 2 branches to run based on what loot they need.
Forest drops agility-heavy gear; Orc drops strength-heavy gear; this gives
early meaningful choice.

#### Tier 3 — The Lair Sub-Branches (unlocked: 2× Tier 2 bosses)

```
shoals, swamp, snake, spider, hive
```

These are DCSS's Lair sub-branches — thematically they feel like going deeper
into the wilderness, which is exactly where they sit.

- **CR gate:** 150
- **Bosses:** Shoals → Kraken, Swamp → Swamp Dragon, Snake → Guardian Serpent,
  Spider → Arachne, Hive → Killer Bee Queen
- **Boss loot:** Guaranteed epic item on first clear.
- **Unlock condition for Tier 4:** Clear any 2 Tier 3 bosses.
- **Enemy scale:** ×2.0 HP and ATK vs Tier 1
- **Gold dropped:** 80–180 per floor

Special mechanic per branch (to make each feel distinct):
- **Shoals:** Water terrain covers 30% of floors — bot move speed penalty applies.
- **Swamp:** High enemy count, lower individual HP. Tests AOE-adjacent builds.
- **Snake:** Enemies have faster attack speed.
- **Spider:** Enemies can web the bot (0.5s movement pause, once per encounter).
  Visual only for MVP — no new mechanic needed, just a hit-stun on specific enemies.
- **Hive:** Dense swarms — up to 30 enemies per floor instead of the usual 16–24.

#### Tier 4 — The Vaults (unlocked: 2× Tier 3 bosses)

```
vaults, crypt, tomb, elf, depths
```

- **CR gate:** 350
- **Bosses:** Vaults → Vault Warden, Crypt → Lich, Tomb → Tomb Guardian,
  Elf → Elven Archmage, Depths → Ancient Wyrm
- **Boss loot:** Guaranteed epic or legendary (70%/30%) on first clear.
- **Unlock condition for Tier 5:** Clear any 3 Tier 4 bosses.
- **Enemy scale:** ×3.2 HP and ATK vs Tier 1
- **Gold dropped:** 250–500 per floor

Tier 4 is intended to represent 4–8 hours of total play time for a new player
to reach. This is where gear starts mattering significantly — a player with
all-common gear will not survive here.

#### Tier 5 — The Planes (unlocked: 3× Tier 4 bosses)

```
forge, glacier, slime, labyrinth, abyss, pandemonium, zot
```

- **CR gate:** 700
- **Bosses:** Forge → Brimstone Titan, Glacier → Frost Colossus, Slime → Royal Jelly,
  Labyrinth → The Minotaur King, Abyss → Abyss Lord, Pandemonium → Demon Prince,
  Zot → Orb Guardian
- **Boss loot:** Legendary-weighted (50% legendary, 50% epic). Unique artifacts on
  first clear (one per branch — predefine 7 named uniques in items.json).
- **Enemy scale:** ×5.0 HP and ATK vs Tier 1
- **Gold dropped:** 800–1500 per floor

Tier 5 is the endgame. Reaching it should feel like an achievement. Zot is
the final branch — clearing its boss is the current "win" condition until
prestige is implemented.

### Enemy Stat Scaling

Rather than hard-coding per-tier multipliers in enemies.json, apply a
runtime multiplier in dungeon.gd based on the branch's tier:

```gdscript
const TIER_SCALE := [1.0, 1.4, 2.0, 3.2, 5.0]  # indexed by tier 1–5
```

Multiply enemy `hp` and `atk` by `TIER_SCALE[branch_tier - 1]` at spawn
time, the same way mini-bosses are already scaled. This means enemies.json
stays clean (current base values) and tuning is done in one place.

---

## Part 3 — Affix System Simplification

### The Problem

30 affixes exist but 25 of them don't affect combat. They produce item names
like "of Swiftness" and "of Seeking" that feel meaningful but aren't. A new
player reads "Iron Shortsword of Seeking" and has no idea if Seeking is good.
Worse, they pick it up because it has a suffix and then realise it does nothing
measurable.

### The Fix: Five Core Stats

Replace all 30 affixes with five stats tied directly to the warrior fantasy.
Any player who has played an ARPG will immediately understand all five.

```
Strength  → +ATK flat
Stamina   → +HP flat
Agility   → +DEF flat
Regen     → +HP per second (hp_regen stat)
Crit      → +crit chance %
```

#### New affixes.json

```json
{ "id": "strength", "name": "Strength", "stat": "atk",        "tiers": [3, 6, 10, 16, 24] }
{ "id": "stamina",  "name": "Stamina",  "stat": "hp",         "tiers": [18, 32, 52, 80, 115] }
{ "id": "agility",  "name": "Agility",  "stat": "def",        "tiers": [2, 4, 7, 11, 17] }
{ "id": "regen",    "name": "Regen",    "stat": "hp_regen",   "tiers": [1, 2, 3, 5, 8] }
{ "id": "crit",     "name": "Crit",     "stat": "crit_chance","tiers": [3, 6, 10, 15, 21] }
```

`rarity_affix_count` stays the same (common: 0, uncommon: 1, rare: 2,
epic: 3, legendary: 4). `rarity_tier_index` stays the same (higher rarity
= higher tier value from the tiers array).

All five affixes apply to any slot (`"applies_to": ["any"]`). No prefix/
suffix distinction is needed when there are only 5 — every affix is just
an "affix". Remove the prefix/suffix field entirely.

#### Crit mechanic

Crit currently has the `stat` field but isn't wired to combat. Wire it:
in actor.gd's `attempt_attack`, before damage is applied, roll `randf() <
(crit_chance / 100.0)`. On success, multiply raw damage by 1.5. Expose
`crit_chance` on the Bot as a computed property from affix sums, just like
`atk` and `def` are today. Crit multiplier is fixed at 1.5 for now — it
becomes a separate affix when a second class is introduced.

#### Item name display

With only 5 affixes, the name format simplifies. Every affix just becomes
its stat name appended: "Iron Shortsword [+Strength, +Crit]" or rendered
as the current prefix/suffix format if desired: "Sharp Iron Shortsword of
Crit". Both are fine — the key is the player immediately understands the
stat.

#### Affix system migration

`affix_system.gd` already reads affixes from the JSON. Replacing affixes.json
is sufficient. Any saved items with old affix IDs (sharp, vicious, etc.)
should be migrated: `save_state.gd`'s `_migrate()` function strips unknown
affixes from saved items (or converts them: sharp/vicious/heavy → strength,
sturdy/stalwart → stamina, reinforced → agility, of_regen → regen,
balanced/savage/of_butchery → crit, everything else → dropped).

---

## Part 4 — Gear Bloat

### The Problem

Runs produce 20–40 loot drops per 10 floors. After a few runs the inventory
has hundreds of items. Players open the Garage, see a wall of grey text
buttons, and have no idea what to do. This is a known idle game killer.

### The Fix: Three Layers

#### Layer 1 — Loot filter (Garage UI, immediate)

A rarity threshold selector in the Garage: "Pick up: All / Uncommon+ / Rare+
/ Epic+ / Legendary only". Default: All for new players, but the UI should
visually highlight that they can change it once their inventory hits 20 items
("Tip: set a loot filter to reduce clutter").

In `dungeon.gd`, before calling `bot.pickup_loot()`, check the item's rarity
against `save_state.loot_filter` (new field, default `"common"`). If below
threshold, the item spawns and glows on the floor as normal but the bot
walks past it. This is intentional — the visual of the bot ignoring loot
is part of the "botting" fantasy.

The filter should feel configurable as a "bot instruction" in the Garage,
not as a UI option — frame it as "Tell your bot what to pick up."

#### Layer 2 — Auto-salvage (Garage UI, next priority)

A toggle: "Auto-salvage: items below [rarity] when inventory is full".

When inventory count exceeds the cap (see Layer 3), the oldest items below
the salvage threshold are converted to gold at 20% of their base sell value.
This happens silently during the run, reported in the run summary as:
"Salvaged 14 items for 38 gold."

The gold value of salvaging should always be meaningfully less than selling
manually would be, to reward active engagement. This is the idle game's
classic "offline tax" — if you're watching, you can squeeze more value;
if you're away, you still make progress.

#### Layer 3 — Inventory cap

Hard cap: 50 items. Above this, auto-salvage fires regardless of toggle
(the bot has to put things somewhere). Display the cap in the Garage:
"Inventory: 23/50". A future prestige upgrade can increase this cap.

Equipped items do not count toward the cap. Starter gear items (`rusty_dagger`,
`tattered_hide`) are excluded from salvage — the bot keeps its starter kit
even if everything else gets converted.

---

## Part 5 — Offline Progress

### Target: 1 hour unattended

The player should be comfortable leaving the game running for 1 hour and
returning to a meaningful loot haul. The bot should not get stuck or die
permanently — it retreats on death (drops to floor 1 of the current branch,
continues) and keeps running.

### Death handling

When the bot's HP reaches 0, instead of a hard run-end, the bot "retreats":
- The current floor's in-progress loot is dropped (forfeit)
- The run summary shows the partial floor as a retreat
- The bot respawns at floor 1 of the same branch with full HP
- This means the player can leave the game running and the bot will keep
  trying — getting further as its gear improves

Death-retreat is only for live/unattended play. Auto-grind still uses
`bot_invincible = true` for benchmarking.

### Offline delta-time calculation

When the player returns after closing the game:

1. On save: store `last_seen_timestamp` in the save state.
2. On load: compute `offline_seconds = now - last_seen_timestamp`.
3. Cap at `MAX_OFFLINE_SECONDS = 3600` (1 hour). This cap creates
   the "check in every hour" rhythm that idle games use for retention.
4. Compute offline loot: `floors_completed = floor(offline_seconds / seconds_per_floor)`.
   Use the bot's current branch's expected floor clear time.
5. Roll loot drops for each computed floor at the branch's loot table.
6. Show a "While You Were Away" summary screen before the Garage loads,
   listing the loot earned.

**Expected floor clear time:** This is derived from the bot's CR vs the
branch's cr_recommended. At CR == cr_recommended, assume ~90 seconds per
floor. At CR > 2× cr_recommended, assume ~45s per floor. This keeps offline
rewards proportional to the bot's actual power.

**Offline loot quality:** Offline loot uses the same rarity rolls as live
loot. No offline bonus or penalty — the reward for watching is the visual
experience, not better loot. This avoids the common idle game mistake of
making offline progress feel hollow because it's always worse quality.

---

## Part 6 — Early Hook (First 10 Minutes)

The first boss kill is the hook. Everything before it is setup. Design
backwards from that moment.

### Minute 0–1: First launch

The Garage loads with `rusty_dagger + tattered_hide` already equipped.
No tutorial text. One button: "Deploy". The HUD shows "Target: The Dungeon".
The player deploys.

Add a first-launch hint strip at the bottom of the Garage: "Your bot is
configured. Hit Deploy to watch it explore." Remove it after the first run.

### Minutes 1–4: First run

The bot enters Dungeon floor 1. Enemies are weak (rats, bats, goblins) and
die in 2–4 hits. The bot finds a chest on floor 2 and opens it — burst loot
animation. An uncommon item drops. The bot picks it up.

Floor 3 introduces the first mini-boss (at 1.8× scale, red tint). The bot
kills it. The combat log registers the kill with a satisfying description.

### Minute 4–5: First boss

Floor 6 — the Minotaur. It's visually larger (1.5× scale), has a boss health
bar. The bot fights it for 8–12 ticks. Minotaur dies. The boss death triggers
a large loot pop (3–5 items burst from the body, including one guaranteed
uncommon weapon).

**The unlock moment:** The run report appears. At the top, before the loot
list: "DUNGEON CLEARED — Lair branch unlocked." This is the first hook. The
player now has a new destination.

### Minutes 5–10: Second run, first upgrade

Back in Garage. The uncommon weapon from the boss is better than the rusty
dagger. The player equips it. The Lair branch is now visible in the branch
picker. The player deploys to Lair.

Lair looks different — grass, new enemies, harder. The bot may not clear
it cleanly on first attempt (it retreats if it dies, so the player doesn't
lose progress). Within 2–3 Lair attempts the bot gets a rare item and the
session loop is established: "I need better gear to clear Lair boss."

### What this requires (new for implementation)

1. A branch picker in the Garage (replaces the current "Deploy" button).
2. A "While You Were Away" / run report screen that shows branch unlocks
   prominently, above the loot list.
3. `save_state` gains `unlocked_branches: Array` (starts: `["dungeon"]`,
   grows on boss kills).
4. Boss kill must emit a distinct event that the run report can flag as
   "branch unlocked."

---

## Part 7 — Gold Economy

Gold currently has no sink. Without a sink, it accumulates to meaningless
numbers quickly. The idle genre's solution is a persistent upgrade layer
that gold buys — something that always exists and always feels worth buying.

### Bot Upgrades (permanent, not reset on prestige)

A "Bot Upgrades" tab in the Garage — a grid of permanent stat purchases.
These are NOT gear — they're persistent upgrades that represent the player's
investment in their bot configuration. They persist across prestige.

Initial upgrade tree (keep it small — 12 upgrades max for MVP):

| Upgrade | Effect | Cost (gold) | Max rank |
|---|---|---|---|
| Conditioning | +5 base HP per rank | 50 / 150 / 300 / 600 / 1200 | 5 |
| Combat Training | +1 base ATK per rank | 80 / 250 / 500 / 1000 / 2000 | 5 |
| Toughening | +1 base DEF per rank | 100 / 300 / 600 / 1200 / 2400 | 5 |
| Quick Reflexes | +2% crit chance | 200 / 500 | 2 |
| Loot Sense | +10% loot rarity bias | 300 / 800 | 2 |
| Pouch | +10 inventory cap | 500 / 1000 / 2000 | 3 |

Cost scales roughly ×2.5 per rank. By the time a player reaches Tier 3,
they should have maxed Conditioning rank 3 or 4 from gold naturally earned.
The upgrades should never feel optional — they should feel like "of course
I buy these."

These are the gold sink. Every run produces gold; every gold buys permanent
bot improvements. This is the idle loop's core progression flywheel.

### Gold scaling per tier

| Tier | Gold per floor (range) | Gold per 6-floor run (est.) |
|---|---|---|
| 1 (Dungeon) | 5–15 | ~60 |
| 2 (Lair/Forest/Orc) | 20–50 | ~210 |
| 3 (Shoals/Swamp etc.) | 80–180 | ~780 |
| 4 (Vaults/Crypt etc.) | 250–500 | ~2250 |
| 5 (Forge/Zot etc.) | 800–1500 | ~6900 |

Gold from boss kills: 5× the highest floor gold for that tier. So a Tier 1
boss kill = ~75 bonus gold, Tier 5 boss kill = ~10,000 gold.

---

## Part 8 — Save State Changes Required

The current `save_state.gd` `_default()` needs the following new fields:

```gdscript
"unlocked_branches": ["dungeon"],
"bot_upgrades": {},          # upgrade_id -> rank purchased
"loot_filter": "common",     # min rarity to pick up
"auto_salvage": false,       # auto-salvage toggle
"last_seen_timestamp": 0,    # Unix timestamp for offline calc
"shards": 0,                 # prestige currency (placeholder, not used yet)
```

And `_migrate()` should add all of these as defaults to old saves.

---

## Part 9 — Branch Picker UI (Garage)

Replace the single Deploy button with:

1. **Branch list panel** (left side of Garage or a new tab): shows all 5 tiers.
   Locked branches are greyed out with the unlock condition shown. Unlocked
   branches show their CR range and the best loot table available.

2. **Selected branch info panel** (right side): shows the selected branch's
   biome name, floor count (always 6), CR requirement vs. bot's current CR
   (green/yellow/red indicator), expected loot tier, and estimated clear time
   based on current CR.

3. **Deploy button** remains. Now deploys the bot to the selected branch.

4. **Random run option**: a "Surprise me" button that picks a random branch
   from unlocked ones. Preserves the existing random-floor experience for
   players who want it.

The run plan in `BiomeData.roll_run_plan()` needs to accept a branch
parameter and return a 5-floor plan of that branch's biome pool + 1 boss
floor of the same biome. Boss floors always use a boss-tier vault if one
is available.

`FLOORS_PER_RUN` changes from 10 to 6 (5 regular + 1 boss). `BOSS_FLOOR`
changes from 10 to 6. `MINIBOSS_FLOORS` should move to floor 3 (mid-branch
mini-boss for pacing).

---

## Part 10 — Implementation Order

This is the sequence the dev agent should follow. Each beat should be
independently testable with `/grind` before moving to the next.

### Beat 1 — Affix simplification (data + code, 1–2h)

1. Replace `affixes.json` with the 5-stat version above.
2. Update `affix_system.gd` `sum_affix_stats` to recognise `crit_chance` and
   `hp_regen` as valid stats (they probably already are — just confirm).
3. Wire `crit_chance` into `actor.gd`'s `attempt_attack`: roll crit on each
   hit, multiply by 1.5 on success. Expose `crit_chance` as a computed
   property on `Bot` summing affix values.
4. Remove prefix/suffix logic from `affix_system.gd` — all affixes are flat.
5. Add affix migration in `save_state.gd`'s `_migrate()`: map old affix IDs
   to new ones, drop unknowns.
6. Validate with `/grind 3` — item names should show simplified affixes.

### Beat 2 — Branch tier data (data only, 1h)

1. Add `tier` and `cr_min` and `cr_recommended` and `boss_name` fields to
   each biome entry in `biomes.json`.
2. Add the boss definitions to `enemies.json` (Hydra, Forest Drake, etc.):
   give each 8–12× the HP of a standard same-biome enemy, boss=true,
   visual_scale 1.5–2.0.
3. Change `FLOORS_PER_RUN` to 6, `BOSS_FLOOR` to 6, `MINIBOSS_FLOORS` to [3]
   in `constants.gd`.
4. Add `TIER_SCALE` array to `constants.gd`.
5. Validate with `/screenshot` on a few biomes.

### Beat 3 — Save state migration (code, 30m)

1. Add the new fields to `_default()` in `save_state.gd`.
2. Write migration logic in `_migrate()` for old saves.
3. Add `last_seen_timestamp` write to `save_state.save_state()`.

### Beat 4 — Branch-aware run plan (code, 1–2h)

1. Update `BiomeData.roll_run_plan()` to accept an optional `branch_id`
   parameter. When provided, return 5 floors of that branch's biome pool
   plus 1 boss floor.
2. Pass the selected branch from the Garage through `main.gd` into `dungeon.gd`
   `_start_run()`.
3. Apply tier enemy scaling (`TIER_SCALE[branch_tier - 1]`) in the enemy
   spawn step of `_async_build_floor()`.
4. Boss floor: spawn the branch's boss enemy instead of the Minotaur. Boss
   enemy should use the `boss: true` flag already in enemies.json.
5. On boss kill in `dungeon.gd`, emit a `boss_killed(branch_id)` signal.
   `main.gd` catches it, updates `unlocked_branches` in SaveState.
6. Validate with `/grind 5 --branch dungeon` (add this arg to grind.sh) —
   confirm 6-floor runs with boss on floor 6.

### Beat 5 — Death retreat (code, 1h)

1. Change `bot.take_damage()` death path in `dungeon.gd`: instead of
   emitting `run_ended(false, ...)`, emit `bot_retreated(current_floor)`.
2. `_on_bot_retreated`: save partial loot to state, reset `current_floor = 1`,
   call `_build_floor()`. Bot respawns at full HP at floor 1 of the same
   branch.
3. Keep a `retreats_this_run` counter; show it in the run report.
4. Auto-grind mode keeps `bot_invincible = true` (no change there).

### Beat 6 — Gear bloat: loot filter + inventory cap (code + UI, 1–2h)

1. Add `loot_filter` to SaveState (default `"common"` = pick up everything).
2. In `dungeon.gd` bot pickup logic: if item rarity is below `loot_filter`,
   bot ignores the loot drop (it stays on the floor, despawns with the floor).
3. Add inventory cap check: if `inventory.size() >= 50`, trigger auto-salvage
   before adding new item (convert oldest below-threshold items to gold).
4. Add "Loot Filter" selector to the Garage UI — 5 options matching rarities.
5. Show "Inventory: N/50" in Garage.

### Beat 7 — Bot upgrades (code + UI, 2–3h)

1. Add `bot_upgrades` dict to SaveState.
2. Define upgrade table in a new `data/bot_upgrades.json` (ids, effects,
   max_rank, costs per rank).
3. In `bot.gd`'s `recompute_stats()`, add bot upgrade bonuses on top of gear
   stats. Read from `SaveState` since upgrades are meta-persistent.
4. Add a "Upgrades" tab to the Garage scene.
5. Validate gold sink is working with `/grind 10`.

### Beat 8 — Branch picker UI (UI, 2–3h)

1. Replace the Deploy button with a branch picker panel in the Garage.
2. Show tier groupings, lock/unlock status, CR indicator.
3. "Surprise me" random branch option.
4. Wire selected branch through to `_start_run()`.

### Beat 9 — Offline progress (code, 1–2h)

1. Write `last_seen_timestamp` in `save_state.save_state()`.
2. On load in `main.gd`, compute `offline_seconds`, compute offline loot,
   add to state, show "While You Were Away" summary before Garage loads.
3. Cap at `MAX_OFFLINE_SECONDS = 3600`.
4. Validate: set the timestamp back 30 minutes in the save file manually,
   reload, confirm the summary screen appears.

### Beat 10 — Run report: branch unlock prominence (UI, 30m)

1. In `run_report.gd`, if the run's boss was killed for the first time,
   show "BRANCH UNLOCKED: [name]" as the first thing in the report, above
   the loot list, in a visually distinct style.
2. The hook moment needs to land visually — it's the most important screen
   in the game for new players.

---

## Appendix A — CR Targets by Tier

For the dev agent to use as reference when setting `cr_min` and
`cr_recommended` on each biome in biomes.json:

| Tier | cr_min | cr_recommended | Bot state at entry |
|---|---|---|---|
| 1 | 0 | 20 | Starter gear |
| 2 | 50 | 120 | Full common gear, level 5–8 |
| 3 | 150 | 280 | Mixed uncommon/rare, level 10–15 |
| 4 | 350 | 600 | Mostly rare/epic, level 20–30 |
| 5 | 700 | 1100 | Epic/legendary mix, level 35–50 |

---

## Appendix B — Biome → Tier Mapping (reference)

```
Tier 1: dungeon, dungeon_dark, mines
Tier 2: lair, forest, orc, temple
Tier 3: shoals, swamp, snake, spider, hive
Tier 4: vaults, crypt, tomb, elf, depths
Tier 5: forge, glacier, slime, labyrinth, abyss, pandemonium, zot
```

`slime` is Tier 5 because it is DCSS's deep Lair variant and enemy difficulty
is appropriately high. `labyrinth` is Tier 5 because DCSS treats it as a
special branch. If playtesting reveals either feels mismatched, move them
to Tier 4 — the tier system is a data change, not a code change.

---

## Appendix C — What NOT to Build Yet

- Prestige/Rebirth mechanic (scaffold save field `shards: 0`, don't implement)
- Multiple classes (Int/mage class deferred — affix simplification is designed
  to expand cleanly when it arrives)
- PvP / async bot battles
- Crafting or item combination
- Skill trees (the bot upgrade grid is intentionally simple for now)
- Sound effects / music (unblocking the loop matters more)
- Mobile layout (desktop landscape is the target; mobile deferred)
