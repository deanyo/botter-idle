class_name Showcase
extends RefCounted

# Hand-curated visual audit floor. One station per visual feature so we can
# eyeball flicker, glow, particles, terrain, vault decor, etc. all at once
# without waiting for procgen to roll the right combination.
#
# Activated by writing "showcase" to user://DEBUG_FLOOR.txt — see
# /showcase skill. main.gd sets DebugJump.showcase=true; dungeon.gd's
# _async_build_floor diverts here when set.
#
# Layout: 80×80 grid, outer wall ring, single open interior. Stations are
# placed in a 4×4 arrangement, each anchored to a labelled cell. Bot
# patrols a fixed loop that visits every station so its light reveals
# them one at a time.

const C := preload("res://scripts/constants.gd")

const MAP_W: int = 80
const MAP_H: int = 80

# Station anchor cells — each station occupies a small footprint around its
# anchor. Stations are spaced ~10 cells apart so each gets its own pool of
# "darkness around it" for flicker / glow assessment.
const STATIONS: Array = [
	# Fire light sources (decor tier — fog-only flicker test)
	{"anchor": Vector2i(15, 12), "kind": "fire_decor", "label": "fire decor"},
	{"anchor": Vector2i(28, 12), "kind": "magic_decor", "label": "magic decor"},
	{"anchor": Vector2i(41, 12), "kind": "crystal_decor", "label": "crystal decor"},
	{"anchor": Vector2i(54, 12), "kind": "mushroom_decor", "label": "mushroom"},
	{"anchor": Vector2i(67, 12), "kind": "campfire", "label": "campfire (actor tier)"},

	# Liquid terrain
	{"anchor": Vector2i(15, 25), "kind": "lava_pool", "label": "lava"},
	{"anchor": Vector2i(28, 25), "kind": "water_pool", "label": "water"},
	{"anchor": Vector2i(41, 25), "kind": "ice_patch", "label": "ice"},

	# Interactables
	{"anchor": Vector2i(54, 25), "kind": "fountain_blue", "label": "fountain blue"},
	{"anchor": Vector2i(67, 25), "kind": "fountain_blood", "label": "fountain blood"},

	# Altar zoo (5 representative gods)
	{"anchor": Vector2i(15, 38), "kind": "altar_trog", "label": "altar trog"},
	{"anchor": Vector2i(28, 38), "kind": "altar_zin", "label": "altar zin"},
	{"anchor": Vector2i(41, 38), "kind": "altar_vehumet", "label": "altar vehumet"},
	{"anchor": Vector2i(54, 38), "kind": "altar_kikubaaqudgha", "label": "altar kiku"},
	{"anchor": Vector2i(67, 38), "kind": "altar_xom", "label": "altar xom"},

	# Loot rarity ladder
	{"anchor": Vector2i(15, 51), "kind": "loot_common", "label": "loot common"},
	{"anchor": Vector2i(22, 51), "kind": "loot_uncommon", "label": "loot uncommon"},
	{"anchor": Vector2i(29, 51), "kind": "loot_rare", "label": "loot rare"},
	{"anchor": Vector2i(36, 51), "kind": "loot_epic", "label": "loot epic"},
	{"anchor": Vector2i(43, 51), "kind": "loot_legendary", "label": "loot legendary"},

	# Chests
	{"anchor": Vector2i(54, 51), "kind": "chest_normal", "label": "chest normal"},
	{"anchor": Vector2i(60, 51), "kind": "chest_rich", "label": "chest rich"},
	{"anchor": Vector2i(67, 51), "kind": "portal", "label": "portal"},

	# Enemies with light_spec attached (frozen — see Showcase.tick)
	{"anchor": Vector2i(15, 64), "kind": "enemy_fire_dragon", "label": "fire dragon"},
	{"anchor": Vector2i(28, 64), "kind": "enemy_ice_dragon", "label": "ice dragon"},
	{"anchor": Vector2i(41, 64), "kind": "enemy_salamander", "label": "salamander"},
	{"anchor": Vector2i(54, 64), "kind": "enemy_blizzard_demon", "label": "blizzard demon"},
	{"anchor": Vector2i(67, 64), "kind": "enemy_firefly", "label": "firefly"},
]

# Bot patrol path — one cell per station anchor (one row east of each so the
# bot doesn't stand ON the feature). The bot loops this list. Cell coords
# are picked to give each station a clean "lit up by the bot" beat.
static func patrol_path() -> Array:
	var out: Array = []
	for s in STATIONS:
		var a: Vector2i = s.anchor
		out.append(Vector2i(a.x, a.y + 2))
	return out

static func build_grid() -> Array:
	# 80×80 floor with outer wall ring. No interior walls — this keeps the
	# layout legible and lets the bot's light pool reveal whichever station
	# it's near without obstruction.
	var g: Array = []
	for y in MAP_H:
		var row: Array = []
		for x in MAP_W:
			if x == 0 or y == 0 or x == MAP_W - 1 or y == MAP_H - 1:
				row.append(C.T_WALL)
			else:
				row.append(C.T_FLOOR)
		g.append(row)
	# Stamp liquid terrain at the lava/water/ice stations. Done at grid-build
	# time so MapRenderer picks them up in the base pass.
	for s in STATIONS:
		var a: Vector2i = s.anchor
		match s.kind:
			"lava_pool":
				_stamp_pool(g, a, C.T_LAVA, 3)
			"water_pool":
				_stamp_pool(g, a, C.T_WATER, 3)
			"ice_patch":
				_stamp_pool(g, a, C.T_ICE, 3)
	return g

static func _stamp_pool(grid: Array, centre: Vector2i, terrain: int, radius: int) -> void:
	# Irregular blob — random per cell within radius — matches the look of
	# DCSS pool stamps without dragging in the full pool builder.
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var d2: int = dx * dx + dy * dy
			if d2 > radius * radius:
				continue
			var x: int = centre.x + dx
			var y: int = centre.y + dy
			if x <= 0 or y <= 0 or x >= MAP_W - 1 or y >= MAP_H - 1:
				continue
			grid[y][x] = terrain
