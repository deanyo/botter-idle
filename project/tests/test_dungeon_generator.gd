extends GutTest

# Tests for DungeonGenerator.generate. Connectivity is the load-bearing
# invariant — if the bot's spawn cell can't reach the stairs, the floor
# is unplayable. The generator's MIN_FLOOR_CELLS / largest-region /
# distance-map gates already retry on failure (MAX_REGEN_ATTEMPTS=8);
# these tests verify that the post-retry result really is reachable
# across a wide cross-section of seed/biome/layout/depth combinations.
#
# Run via:
#   /Applications/Godot.app/Contents/MacOS/Godot --path project --headless \
#       -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit
#
# ~30 generations; runs in a few seconds at most.

const C := preload("res://scripts/constants.gd")

# Cross-section of biomes (theme strings handed to generate()) and
# layouts. `basic` is the rectangular-rooms BSP layout; `caves*` are
# the cellular-automata variants. Picked one biome from each tier.
const BIOMES := ["dungeon", "lair", "vaults", "forge", "zot"]
const LAYOUTS := ["basic", "caves", "caves_open", "caves_tight"]

func test_generated_floor_has_required_keys() -> void:
	var gen := DungeonGenerator.new(12345)
	var result: Dictionary = gen.generate(C.MAP_W, C.MAP_H, "dungeon", 1, "basic")
	for key in ["grid", "rooms", "width", "height", "spawn", "stairs_down",
				"vault_results", "dist_to_stairs"]:
		assert_true(result.has(key), "result has %s key" % key)

func test_generated_grid_dimensions_match_input() -> void:
	var gen := DungeonGenerator.new(99)
	var w := 60
	var h := 40
	var result: Dictionary = gen.generate(w, h, "dungeon", 1, "basic")
	assert_eq(int(result.width), w, "width matches input")
	assert_eq(int(result.height), h, "height matches input")
	var grid: Array = result.grid
	assert_eq(grid.size(), h, "grid row count matches height")
	assert_eq(grid[0].size(), w, "grid column count matches width")

func test_spawn_and_stairs_are_distinct() -> void:
	# Across many seeds/biomes/layouts, spawn must never coincide with
	# stairs — otherwise the floor is "won" the moment the bot lands.
	var gen_seed := 1
	for biome in BIOMES:
		for layout in LAYOUTS:
			var gen := DungeonGenerator.new(gen_seed)
			var result: Dictionary = gen.generate(C.MAP_W, C.MAP_H, biome, 1, layout)
			gen_seed += 1
			var spawn: Vector2i = result.spawn
			var stairs: Vector2i = result.stairs_down
			assert_true(spawn != stairs,
				"spawn != stairs for %s/%s seed=%d (both at %s)" %
				[biome, layout, gen_seed, str(spawn)])

func test_spawn_cell_reaches_stairs_across_cross_section() -> void:
	# Connectivity invariant: dist_to_stairs[spawn] must be >= 0
	# (negative means BFS never reached spawn from stairs). The
	# generator's retry loop bails when this fails — these tests
	# confirm we don't ship a successful return that's actually
	# disconnected.
	var gen_seed := 100
	var checked: int = 0
	for biome in BIOMES:
		for layout in LAYOUTS:
			var gen := DungeonGenerator.new(gen_seed)
			var result: Dictionary = gen.generate(C.MAP_W, C.MAP_H, biome, 1, layout)
			gen_seed += 1
			var spawn: Vector2i = result.spawn
			var dist: Array = result.dist_to_stairs
			var d: int = int(dist[spawn.y][spawn.x])
			assert_gte(d, 0,
				"spawn unreachable for %s/%s seed=%d (dist=%d)" %
				[biome, layout, gen_seed, d])
			checked += 1
	assert_gt(checked, 15, "covered at least 15 biome×layout combos")

func test_floor_cell_count_above_minimum() -> void:
	# DungeonGenerator enforces MIN_FLOOR_CELLS=200 internally via its
	# retry loop. Confirm the returned grid actually clears that bar
	# rather than the loop having silently hit MAX_REGEN_ATTEMPTS and
	# returned a stub.
	var gen := DungeonGenerator.new(7777)
	var result: Dictionary = gen.generate(C.MAP_W, C.MAP_H, "dungeon", 1, "basic")
	var grid: Array = result.grid
	var floor_count: int = 0
	var walkables := [C.T_FLOOR, C.T_STAIRS_DOWN, C.T_STAIRS_UP, C.T_DOOR]
	for row in grid:
		for cell in row:
			if cell in walkables:
				floor_count += 1
	assert_gte(floor_count, 200,
		"floor cells >= MIN_FLOOR_CELLS (got %d)" % floor_count)

func test_spawn_and_stairs_are_walkable() -> void:
	# Whatever cells the generator hands back as spawn/stairs must
	# actually be walkable terrain — a floor/stairs/door/lava/water/ice
	# tile, not solid wall.
	var gen := DungeonGenerator.new(5555)
	for biome in ["dungeon", "lair", "forge"]:
		for layout in ["basic", "caves"]:
			var result: Dictionary = gen.generate(C.MAP_W, C.MAP_H, biome, 3, layout)
			var grid: Array = result.grid
			var spawn: Vector2i = result.spawn
			var stairs: Vector2i = result.stairs_down
			var spawn_cell: int = int(grid[spawn.y][spawn.x])
			var stairs_cell: int = int(grid[stairs.y][stairs.x])
			assert_true(spawn_cell in C.WALKABLE_TERRAIN,
				"%s/%s spawn cell walkable (was %d)" % [biome, layout, spawn_cell])
			# Stairs cell is specifically T_STAIRS_DOWN.
			assert_eq(stairs_cell, C.T_STAIRS_DOWN,
				"%s/%s stairs cell is T_STAIRS_DOWN (was %d)" %
				[biome, layout, stairs_cell])

func test_seeded_generation_is_deterministic() -> void:
	# Same RNG seed + same inputs must produce a byte-identical floor.
	# This is the foundation of /duel and /sweep paired comparisons —
	# without it, no balance experiment is meaningful.
	var gen_a := DungeonGenerator.new(424242)
	var gen_b := DungeonGenerator.new(424242)
	var a: Dictionary = gen_a.generate(C.MAP_W, C.MAP_H, "dungeon", 1, "basic")
	var b: Dictionary = gen_b.generate(C.MAP_W, C.MAP_H, "dungeon", 1, "basic")
	assert_eq(a.spawn, b.spawn, "same-seed spawn cell identical")
	assert_eq(a.stairs_down, b.stairs_down, "same-seed stairs cell identical")
	assert_eq(JSON.stringify(a.grid), JSON.stringify(b.grid),
		"same-seed grid byte-identical")
