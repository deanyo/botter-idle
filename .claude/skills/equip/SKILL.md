---
name: equip
description: Set up a bot loadout in the debug save (no Godot launch). Use when the user wants to test a specific build, prepare a bot for /grind, or stage a state before /duel or /sweep. Args - shorthand `weapon=<id>,Strength5,Crit4` etc; or a single JSON string.
user_invocable: true
---

# Botter equip

Writes a build spec to `botter_save_debug.json` so the next /grind launches
that exact bot. Validates item ids against `project/data/items.json`, affix
ids/tiers against `data/affixes.json`, branches against `data/biomes.json`.

## Usage

```bash
python3 /Users/dyo/claude/botter/.claude/skills/equip/equip.py "<spec tokens>"
```

Tokens are space-separated. Each is either:

- `<slot>=<base_id>[,<affix>...]` — equip an item, optionally with affixes.
  Slots: weapon, armor, helm, boots, shield, ring1, ring2, amulet.
- `level=<int>`, `gold=<int>`, `xp=<int>`
- `max_revives=<int>` — death-retreat budget per run
- `loot_filter=<rarity>` — common|uncommon|rare|epic|legendary
- `inventory_cap=<int>`
- `branch=<branch_id>` — sets last_branch + adds it to unlocked_branches
- `mods=<mod1>+<mod2>` — applies to current `branch=` value

Affix shorthand: `<Name><Tier>` where Name is one of strength/stamina/agility/regen/crit/haste
(also accepts str/sta/agi/reg/cri/has) and Tier is 1..5.
Tier 5 = legendary value, tier 1 = common value, etc — the actual stat
value is read from `data/affixes.json`.

## Examples

```bash
# Bare minimum — give the bot a weapon, level 1 default
python3 .claude/skills/equip/equip.py "weapon=rusty_dagger"

# Tier-5 endgame demo bot for forge runs
python3 .claude/skills/equip/equip.py \
  "weapon=demon_blade,Strength5,Crit4 armor=crystal_plate,Stamina5 \
   helm=kings_diadem boots=treads_apocalypse shield=shield_of_war \
   level=30 gold=5000 branch=forge"

# Test a unique with a hostile modifier
python3 .claude/skills/equip/equip.py \
  "weapon=singing_sword,Strength5,Haste5 branch=forge mods=bloodlust+crowded"

# Pass full JSON (for complex specs the shorthand can't express)
python3 .claude/skills/equip/equip.py '{"level":1,"equipped":{"weapon":"rusty_dagger"}}'
```

## What it does NOT do

- Launch Godot (use `/grind` after, or chain into `/duel` / `/sweep`).
- Touch the live save (`botter_save.json`). The `--reset` flag inside
  inject_save.py routes everything to `botter_save_debug.json`.
- Persist between sessions in any meaningful way — once Godot starts in
  grind mode it'll happily mutate the debug save (gold accrues etc).
  Always re-run /equip before each independent experiment.

## Workflow

```
/equip "<build>"              # write build to debug save
/grind 5                      # play 5 runs with that build
                              # (or use /duel <a> -- <b>, /sweep ...)
```

The skill returns the resolved equipment summary on stdout so the chat
log shows exactly what got injected.
