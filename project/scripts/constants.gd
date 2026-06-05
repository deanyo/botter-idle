class_name Constants
extends RefCounted

const TILE_SIZE := 32

const T_WALL  := 0
const T_FLOOR := 1
const T_DOOR  := 2
const T_STAIRS_DOWN := 3
const T_STAIRS_UP   := 4
# Special-feature walkable terrain:
#   T_LAVA  damages bot on contact (5% max-hp per 0.5s tick)
#   T_WATER halves move speed
#   T_ICE   visual-only for v1 (slip mechanic deferred)
const T_LAVA  := 5
const T_WATER := 6
const T_ICE   := 7

# Cells the bot can walk through. Used by pathfinding and walkable checks.
const WALKABLE_TERRAIN := [T_FLOOR, T_STAIRS_DOWN, T_STAIRS_UP, T_DOOR, T_LAVA, T_WATER, T_ICE]

const MAP_W := 80
const MAP_H := 80

const FLOORS_PER_RUN := 6
const BOSS_FLOOR := 6
const MINIBOSS_FLOORS := [3]

# Per-tier enemy stat multiplier. Indexed by branch tier - 1. Tier 1
# (Dungeon/Mines) is the base; Tier 5 hits ~4.5× baseline.
#
# 2026-06-02 tuning: was [1.0, 1.4, 2.0, 3.2, 5.0]. Pinned-experiment
# data showed level-30 unequipped bots at 96% wins on T1 and 0% wins on
# T4-T5 — the 2.0→3.2 jump (T3→T4, +60%) was the brick wall. Softened
# to [1.0, 1.4, 2.0, 2.7, 4.5] (T3→T4 now +35%, T4→T5 now +67%). Goal:
# T4 winnable with affixes, T5 still requires gear.
# See docs/balance-findings-2026-06-02.md for the full rationale.
# 2026-06-05 retune: per-tier balance grind showed T3-T5 bosses dying
# in <1s losing <1% HP from a tier-appropriate bot. T3 jumped 2.0 → 2.5
# (+25%), T4 2.7 → 3.6 (+33%), T5 4.5 → 6.5 (+44%) so high-tier enemies
# actually threaten well-equipped builds. T1+T2 unchanged — those still
# hit the 5-8min run-length target.
const TIER_SCALE := [1.0, 1.4, 2.5, 3.6, 6.5]

