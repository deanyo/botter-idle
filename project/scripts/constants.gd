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

const FLOORS_PER_RUN := 10
const BOSS_FLOOR := 10
const MINIBOSS_FLOORS := [5, 10, 15, 20, 25]

