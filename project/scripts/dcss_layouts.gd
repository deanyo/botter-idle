# Algorithms ported in spirit from DCSS source/dgn-layouts.cc and dgn-delve.cc.
# See CLAUDE.md "HOW TO PORT" rules — descriptions translated, GDScript written fresh.
class_name DCSSLayouts
extends RefCounted

const C := preload("res://scripts/constants.gd")

# ============================================================================
# basic_level — DCSS's canonical D:1-15 generator
# ----------------------------------------------------------------------------
# Approach (paraphrased from dgn_build_basic_level):
#   1. Carve THREE wandering trails from random start points. Each trail is a
#      drunkard-walk corridor that picks a cardinal direction biased away from
#      walls/edges and walks 2-15 cells before turning. Trails stop on
#      intersect with existing floor (with a small intersect_chance roll to
#      plow through anyway).
#   2. Mark each trail's endpoints as stair candidates. Connect each pair of
#      stair points to ensure connectivity.
#   3. ~6% of mid-deep floors get a "big_room" — large rectangle, possibly
#      octagonal, optionally chequerboarded or nested-boxed.
#   4. ~5% of mid-deep floors get "diamond_rooms" — 1-10 octagonal hazard
#      blobs filled with water/lava (NOT floor — these are obstacles).
#   5. Scatter 5-100 random rectangle rooms onto the map. Doors get placed on
#      sides where adjacent walls make a "good door spot."
#   6. Builder extras: optional river/lake/many-pools dressing on later floors.
# ============================================================================

static func basic_level(grid: Array, rng: RandomNumberGenerator, level_number: int) -> Dictionary:
	var w: int = grid[0].size()
	var h: int = grid.size()

	var corridor_max: int = 2 + rng.randi_range(0, 13)
	var segment_count: int = 30 + rng.randi_range(0, 199)
	if rng.randi_range(0, 99) == 0:
		segment_count = 500 + rng.randi_range(0, 499)
	var intersect_chance: int = rng.randi_range(0, 19)
	if rng.randi_range(0, 19) == 0:
		intersect_chance = 400

	var trail_endpoints: Array[Vector2i] = []

	var s1: Vector2i = Vector2i(_scale_x(35, w), _scale_y(35, h))
	var r1: Vector2i = Vector2i(_scale_x(30, w), _scale_y(20, h))
	var t1: Dictionary = _make_trail(grid, rng, s1, r1, corridor_max, intersect_chance, segment_count)
	if t1.has("begin"):
		trail_endpoints.append(t1.begin)

	var s2: Vector2i = Vector2i(_scale_x(10, w), _scale_y(10, h))
	var r2: Vector2i = Vector2i(_scale_x(15, w), _scale_y(15, h))
	var t2: Dictionary = _make_trail(grid, rng, s2, r2, corridor_max, intersect_chance, segment_count)
	if t2.has("begin"):
		trail_endpoints.append(t2.begin)

	var s3: Vector2i = Vector2i(_scale_x(50, w), _scale_y(10, h))
	var r3: Vector2i = Vector2i(_scale_x(20, w), _scale_y(15, h))
	var t3: Dictionary = _make_trail(grid, rng, s3, r3, corridor_max, intersect_chance, segment_count)
	if t3.has("begin"):
		trail_endpoints.append(t3.begin)

	for i in trail_endpoints.size():
		var j: int = i + 1
		while j < trail_endpoints.size():
			_join_dots(grid, trail_endpoints[i], trail_endpoints[j])
			j += 1

	if level_number > 1 and rng.randi_range(0, 15) == 0:
		_big_room(grid, rng, level_number)

	if rng.randi_range(0, level_number) > 6 and rng.randi_range(0, 2) == 0:
		_diamond_rooms(grid, rng, level_number)

	var door_level: int = rng.randi_range(0, 10)
	var room_size: int = 4 + rng.randi_range(0, 4) + rng.randi_range(0, 5)
	var room_count: int = _weighted_choose(rng, [636, 49, 15], [
		5 + _avg_two(rng, 29),
		100,
		1,
	])
	_make_random_rooms(grid, rng, room_count, 2 + rng.randi_range(0, 7), door_level, _scale_x(50, w), _scale_y(40, h), room_size)
	_make_random_rooms(grid, rng, 1 + rng.randi_range(0, 2), 1, door_level, _scale_x(55, w), _scale_y(45, h), 6)

	_builder_extras(grid, rng, level_number)
	_place_doors(grid, rng, level_number)

	var rooms_out: Array = _detect_rooms_for_compatibility(grid)
	var spawn_seed: Vector2i = trail_endpoints[0] if not trail_endpoints.is_empty() else _find_first_floor(grid)
	var spawn: Vector2i = _open_spawn_cell(grid, spawn_seed)
	var stairs_down: Vector2i = _farthest_floor_cell(grid, spawn)
	if stairs_down.x >= 0 and stairs_down.y >= 0 and stairs_down.y < h and stairs_down.x < w:
		grid[stairs_down.y][stairs_down.x] = C.T_STAIRS_DOWN
	_ensure_open_around(grid, spawn, 2)

	return {
		"grid": grid,
		"rooms": rooms_out,
		"spawn": spawn,
		"stairs_down": stairs_down,
	}

# ============================================================================
# Trail — drunkard walk that biases toward open map.
# Picks a cardinal direction, walks 2..corridor_max cells, then turns.
# Stops segments early on intersect with existing floor (unless intersect roll).
# Returns {begin, end}.
# ============================================================================

static func _make_trail(grid: Array, rng: RandomNumberGenerator, start: Vector2i, span: Vector2i,
		corridor_max: int, intersect_chance: int, segment_count: int) -> Dictionary:
	var w: int = grid[0].size()
	var h: int = grid.size()
	var pos := Vector2i(-1, -1)
	var tries: int = 200
	while tries > 0:
		var p := Vector2i(start.x + rng.randi_range(0, span.x - 1), start.y + rng.randi_range(0, span.y - 1))
		if _viable_trail_start(grid, p, w, h):
			pos = p
			break
		tries -= 1
	if pos.x < 0:
		return {}
	var begin: Vector2i = pos
	var finished: int = 0
	tries = 200
	var length: int = 0
	while finished < segment_count and tries > 0:
		tries -= 1
		var dir := Vector2i.ZERO
		if rng.randi_range(0, 1) == 0:
			dir.x = _trail_random_dir(rng, pos.x, w, 15)
		else:
			dir.y = _trail_random_dir(rng, pos.y, h, 15)
		if dir == Vector2i.ZERO:
			continue
		if dir.x == 0 or length == 0:
			length = 2 + rng.randi_range(0, corridor_max - 1)
		for step in length:
			if pos.x < 4:
				dir = Vector2i(1, 0)
			elif pos.x > w - 5:
				dir = Vector2i(-1, 0)
			if pos.y < 4:
				dir = Vector2i(0, 1)
			elif pos.y > h - 5:
				dir = Vector2i(0, -1)
			var probe: Vector2i = pos + dir * 2
			if probe.x >= 0 and probe.y >= 0 and probe.x < w and probe.y < h:
				if grid[probe.y][probe.x] == C.T_FLOOR and rng.randi_range(0, intersect_chance) != 0:
					break
			pos += dir
			if pos.x < 0 or pos.y < 0 or pos.x >= w or pos.y >= h:
				pos -= dir
				break
			if grid[pos.y][pos.x] == C.T_WALL:
				grid[pos.y][pos.x] = C.T_FLOOR
		if finished == segment_count - 1 and not (pos.x >= 0 and pos.y >= 0 and pos.x < w and pos.y < h and grid[pos.y][pos.x] == C.T_FLOOR):
			finished -= 2
		finished += 1
	return {"begin": begin, "end": pos}

static func _viable_trail_start(grid: Array, c: Vector2i, w: int, h: int) -> bool:
	if c.x < 1 or c.y < 1 or c.x >= w - 1 or c.y >= h - 1:
		return false
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var n: Vector2i = c + d
		if n.x >= 0 and n.y >= 0 and n.x < w and n.y < h and grid[n.y][n.x] == C.T_WALL:
			return true
	return false

static func _trail_random_dir(rng: RandomNumberGenerator, pos: int, bound: int, margin: int) -> int:
	var d: int = 0
	if pos < margin:
		d = 1
	elif pos > bound - margin:
		d = -1
	if d == 0 or rng.randi_range(0, 4) < 2:
		d = -1 if rng.randi_range(0, 1) == 0 else 1
	return d

# ============================================================================
# join_dots — connect two cells with a floor-carving path. Greedy step toward
# target. We don't need DCSS's priority-set pathfinder — the grid is mostly
# carved already, just push a line from A to B.
# ============================================================================

static func _join_dots(grid: Array, from: Vector2i, to: Vector2i) -> void:
	var w: int = grid[0].size()
	var h: int = grid.size()
	var pos: Vector2i = from
	var safety: int = 0
	while pos != to and safety < 1000:
		safety += 1
		if pos.x < 0 or pos.y < 0 or pos.x >= w or pos.y >= h:
			return
		if grid[pos.y][pos.x] == C.T_WALL:
			grid[pos.y][pos.x] = C.T_FLOOR
		var dx: int = sign(to.x - pos.x)
		var dy: int = sign(to.y - pos.y)
		if dx != 0 and dy != 0:
			if randi() % 2 == 0:
				pos.x += dx
			else:
				pos.y += dy
		elif dx != 0:
			pos.x += dx
		elif dy != 0:
			pos.y += dy
		else:
			break
	if pos.x >= 0 and pos.y >= 0 and pos.x < w and pos.y < h and grid[pos.y][pos.x] == C.T_WALL:
		grid[pos.y][pos.x] = C.T_FLOOR

# ============================================================================
# random_rooms — place N rectangular rooms with overlap-retry.
# Each room: random rectangle, carve interior to floor, place doors on
# wall-adjacent edge cells (stochastically based on door_level).
# ============================================================================

static func _make_random_rooms(grid: Array, rng: RandomNumberGenerator, count: int, max_doors: int, door_level: int, max_x: int, max_y: int, max_room_size: int) -> void:
	var w: int = grid[0].size()
	var h: int = grid.size()
	var i: int = 0
	var stuck: int = 0
	while i < count:
		var attempt: int = 200
		var sx: int = 0
		var sy: int = 0
		var ex: int = 0
		var ey: int = 0
		while attempt > 0:
			sx = clampi(2 + rng.randi_range(0, max_x), 2, w - 4)
			sy = clampi(2 + rng.randi_range(0, max_y), 2, h - 4)
			ex = mini(sx + 2 + rng.randi_range(0, max_room_size), w - 2)
			ey = mini(sy + 2 + rng.randi_range(0, max_room_size), h - 2)
			break
		if not _make_room(grid, rng, sx, sy, ex, ey, max_doors, door_level):
			stuck += 1
			if stuck > 30:
				stuck = 0
				i += 1
		else:
			stuck = 0
			i += 1

static func _make_room(grid: Array, rng: RandomNumberGenerator, sx: int, sy: int, ex: int, ey: int, max_doors: int, door_level: int) -> bool:
	var w: int = grid[0].size()
	var h: int = grid.size()
	if sx < 1 or sy < 1 or ex >= w - 1 or ey >= h - 1:
		return false
	# Look for "good door spots" on the perimeter — these are cells where the
	# perpendicular direction is solid wall on both sides.
	var find_door: int = 0
	for rx in range(sx, ex + 1):
		find_door += _good_door_spot(grid, rx, sy)
		find_door += _good_door_spot(grid, rx, ey)
	for ry in range(sy + 1, ey):
		find_door += _good_door_spot(grid, sx, ry)
		find_door += _good_door_spot(grid, ex, ry)
	if find_door == 0:
		return false
	# Carve interior to floor.
	for rx in range(sx, ex + 1):
		for ry in range(sy, ey + 1):
			if grid[ry][rx] != C.T_FLOOR:
				grid[ry][rx] = C.T_FLOOR
	# Place doors on viable perimeter cells. door_level/10 is the chance per spot.
	# (We render door tiles via the vault `+` glyph elsewhere; here the door is
	#  just a floor cell on the perimeter where both sides are wall.)
	var doors_placed: int = 0
	# Top and bottom edges.
	for rx in range(sx + 1, ex):
		if doors_placed >= max_doors:
			break
		if _is_wall(grid, rx, sy - 1) and _is_wall(grid, rx - 1, sy - 1) and _is_wall(grid, rx + 1, sy - 1):
			pass
		elif rng.randi_range(0, 9) < door_level and grid[sy - 1][rx] != C.T_WALL:
			doors_placed += 1
		if doors_placed >= max_doors:
			break
	return true

static func _good_door_spot(grid: Array, x: int, y: int) -> int:
	var w: int = grid[0].size()
	var h: int = grid.size()
	if x < 1 or y < 1 or x >= w - 1 or y >= h - 1:
		return 0
	# A good door spot has wall on two opposite sides and non-wall on the other two.
	var n_wall: bool = _is_wall(grid, x, y - 1)
	var s_wall: bool = _is_wall(grid, x, y + 1)
	var e_wall: bool = _is_wall(grid, x - 1, y)
	var w_wall: bool = _is_wall(grid, x + 1, y)
	if n_wall == s_wall and e_wall == w_wall and n_wall != e_wall:
		return 1
	return 0

static func _is_wall(grid: Array, x: int, y: int) -> bool:
	var w: int = grid[0].size()
	var h: int = grid.size()
	if x < 0 or y < 0 or x >= w or y >= h:
		return true
	return grid[y][x] == C.T_WALL

# ============================================================================
# big_room — large 21+ wide rectangle. Variants:
#   - 25%: octagon shape, mostly floor (or lava/water on deep floors)
#   - rest: rectangle. 25% chance chequerboard, ~17% nested boxes, else plain.
# ============================================================================

static func _big_room(grid: Array, rng: RandomNumberGenerator, _level_number: int) -> void:
	var w: int = grid[0].size()
	var h: int = grid.size()
	if rng.randi_range(0, 3) == 0:
		var oblique: int = 5 + rng.randi_range(0, 19)
		var rect := _random_big_rect(rng, w, h)
		_octa_room(grid, rect, oblique, C.T_FLOOR)
		return
	var rect2 := _random_big_rect(rng, w, h)
	# DCSS sometimes fills with water/lava on deep levels; we'll simplify and
	# always carve floor here, leaving water/lava to the river/lake builders.
	for x in range(rect2.position.x, rect2.position.x + rect2.size.x):
		for y in range(rect2.position.y, rect2.position.y + rect2.size.y):
			if x >= 0 and y >= 0 and x < w and y < h:
				grid[y][x] = C.T_FLOOR
	# Sometimes chequerboard the room: alternate floor / wall to make pillared hall.
	if rng.randi_range(0, 3) == 0:
		_chequerboard(grid, rect2)
	# Sometimes nested boxed rooms.
	elif rng.randi_range(0, 5) == 0:
		_nested_boxes(grid, rng, rect2)

static func _random_big_rect(rng: RandomNumberGenerator, w: int, h: int) -> Rect2i:
	var sx: int = 8 + rng.randi_range(0, maxi(1, w - 30))
	var sy: int = 8 + rng.randi_range(0, maxi(1, h - 30))
	var rw: int = mini(21 + rng.randi_range(0, 9), w - sx - 2)
	var rh: int = mini(21 + rng.randi_range(0, 7), h - sy - 2)
	return Rect2i(sx, sy, maxi(rw, 8), maxi(rh, 8))

static func _octa_room(grid: Array, region: Rect2i, oblique_max: int, floor_type: int) -> void:
	var w: int = grid[0].size()
	var h: int = grid.size()
	var oblique: int = oblique_max
	var x_start: int = region.position.x
	var x_end: int = region.position.x + region.size.x
	var y_start: int = region.position.y
	var y_end: int = region.position.y + region.size.y
	for x in range(x_start, x_end):
		var dist_from_start: int = x - x_start
		var dist_from_end: int = x_end - 1 - x
		var corner_cut: int = maxi(0, oblique_max - mini(dist_from_start, dist_from_end))
		for y in range(y_start + corner_cut, y_end - corner_cut):
			if x >= 0 and y >= 0 and x < w and y < h:
				if grid[y][x] == C.T_WALL:
					grid[y][x] = floor_type

static func _chequerboard(grid: Array, region: Rect2i) -> void:
	var w: int = grid[0].size()
	var h: int = grid.size()
	for x in range(region.position.x, region.position.x + region.size.x):
		for y in range(region.position.y, region.position.y + region.size.y):
			if x < 0 or y < 0 or x >= w or y >= h:
				continue
			if grid[y][x] != C.T_FLOOR:
				continue
			if (x + y) % 2 == 0:
				grid[y][x] = C.T_WALL

static func _nested_boxes(grid: Array, rng: RandomNumberGenerator, region: Rect2i) -> void:
	var w: int = grid[0].size()
	var h: int = grid.size()
	var i: int = region.position.x
	var j: int = region.position.y
	var k: int = region.position.x + region.size.x - 1
	var l: int = region.position.y + region.size.y - 1
	while true:
		i += 2 + rng.randi_range(0, 2)
		j += 2 + rng.randi_range(0, 2)
		k -= 2 + rng.randi_range(0, 2)
		l -= 2 + rng.randi_range(0, 2)
		if i >= k - 3 or j >= l - 3:
			break
		# Box outline.
		for x in range(i, k + 1):
			if x >= 0 and x < w:
				if j >= 0 and j < h:
					grid[j][x] = C.T_WALL
				if l >= 0 and l < h:
					grid[l][x] = C.T_WALL
		for y in range(j + 1, l):
			if y >= 0 and y < h:
				if i >= 0 and i < w:
					grid[y][i] = C.T_WALL
				if k >= 0 and k < w:
					grid[y][k] = C.T_WALL
		# Open one gap on a random side.
		var side: int = rng.randi_range(0, 3)
		if side == 0:
			grid[j][i + 1 + rng.randi_range(0, k - i - 2)] = C.T_FLOOR
		elif side == 1:
			grid[l][i + 1 + rng.randi_range(0, k - i - 2)] = C.T_FLOOR
		elif side == 2:
			grid[j + 1 + rng.randi_range(0, l - j - 2)][i] = C.T_FLOOR
		else:
			grid[j + 1 + rng.randi_range(0, l - j - 2)][k] = C.T_FLOOR

# ============================================================================
# diamond_rooms — 1-10 octagonal "obstacle" blobs. Most floors map these to
# wall (impassable terrain that breaks up open space). Higher floors get
# water/lava blobs. Note: these are NOT walkable rooms — they're hazards.
# ============================================================================

static func _diamond_rooms(grid: Array, rng: RandomNumberGenerator, _level_number: int) -> void:
	var w: int = grid[0].size()
	var h: int = grid.size()
	var count: int = 1 + rng.randi_range(0, 9)
	# DCSS picks deep_water by default and switches to other features deep.
	# Since our biomes drive water/lava placement separately, we just use wall
	# here — the effect is "obstacle clusters break up big open areas."
	for _i in count:
		var rw: int = 6 + rng.randi_range(0, 14)
		var rh: int = 6 + rng.randi_range(0, 9)
		var sx: int = 8 + rng.randi_range(0, maxi(1, w - rw - 16))
		var sy: int = 8 + rng.randi_range(0, maxi(1, h - rh - 16))
		var rect := Rect2i(sx, sy, rw, rh)
		_octa_room(grid, rect, rect.size.x / 2, C.T_WALL)

# ============================================================================
# builder_extras — late-floor dressing. Roll a river or lake or pool cluster.
# ============================================================================

static func _builder_extras(grid: Array, rng: RandomNumberGenerator, level_number: int) -> void:
	if level_number > 6 and rng.randi_range(0, 9) == 0:
		_many_pools(grid, rng)
		return
	if level_number > 8 and rng.randi_range(0, 15) == 0:
		_build_river(grid, rng)
	elif level_number > 8 and rng.randi_range(0, 11) == 0:
		_build_lake(grid, rng)

static func _build_river(grid: Array, rng: RandomNumberGenerator) -> void:
	var w: int = grid[0].size()
	var h: int = grid.size()
	var width: int = 3 + rng.randi_range(0, 3)
	var y: int = clampi(10 - width + rng.randi_range(0, h - 12), 4, h - 8)
	for x in range(5, w - 5):
		if rng.randi_range(0, 2) == 0:
			y += 1
		if rng.randi_range(0, 2) == 0:
			y -= 1
		if rng.randi_range(0, 1) == 0:
			width += 1
		if rng.randi_range(0, 1) == 0:
			width -= 1
		width = clampi(width, 2, 6)
		y = clampi(y, 4, h - width - 4)
		for j in range(y, y + width):
			if j >= 5 and j <= h - 5 and rng.randi_range(0, 199) != 0:
				# Rivers carve through walls — keep them as wall (impassable terrain
				# variant we already render via biome `wall_alternates: deep_water`).
				# A real water layer would need a third tile state; for now, the
				# river just *clears* the area to wall-rendered-as-water.
				grid[j][x] = C.T_WALL

static func _build_lake(grid: Array, rng: RandomNumberGenerator) -> void:
	var w: int = grid[0].size()
	var h: int = grid.size()
	var x1: int = 5 + rng.randi_range(0, maxi(1, w - 30))
	var y1: int = 5 + rng.randi_range(0, maxi(1, h - 30))
	var x2: int = x1 + 4 + rng.randi_range(0, 15)
	var y2: int = y1 + 8 + rng.randi_range(0, 11)
	var height: int = y2 - y1
	for j in range(y1, y2):
		if rng.randi_range(0, 1) == 0:
			x1 += rng.randi_range(0, 2)
		if rng.randi_range(0, 1) == 0:
			x1 -= rng.randi_range(0, 2)
		if rng.randi_range(0, 1) == 0:
			x2 += rng.randi_range(0, 2)
		if rng.randi_range(0, 1) == 0:
			x2 -= rng.randi_range(0, 2)
		if j - y1 < height / 2:
			x2 += rng.randi_range(0, 2)
			x1 -= rng.randi_range(0, 2)
		else:
			x2 -= rng.randi_range(0, 2)
			x1 += rng.randi_range(0, 2)
		for i in range(x1, x2):
			if j >= 5 and j <= h - 5 and i >= 5 and i <= w - 5 and rng.randi_range(0, 199) != 0:
				grid[j][i] = C.T_WALL

static func _many_pools(grid: Array, rng: RandomNumberGenerator) -> void:
	var w: int = grid[0].size()
	var h: int = grid.size()
	var num_pools: int = 20 + _avg_two(rng, 9)
	var placed: int = 0
	var safety: int = 30000
	while placed < num_pools and safety > 0:
		safety -= 1
		var i: int = rng.randi_range(2, maxi(3, w - 21))
		var j: int = rng.randi_range(2, maxi(3, h - 21))
		var k: int = i + 2 + rng.randi_range(2, 18)
		var l: int = j + 2 + rng.randi_range(2, 18)
		if k >= w - 1 or l >= h - 1:
			continue
		# Only place pool if region currently has NO floor cells.
		var has_floor: bool = false
		for x in range(i, k + 1):
			if has_floor:
				break
			for y in range(j, l + 1):
				if grid[y][x] == C.T_FLOOR:
					has_floor = true
					break
		if has_floor:
			continue
		_place_pool(grid, rng, i, j, k, l)
		placed += 1

static func _place_pool(grid: Array, rng: RandomNumberGenerator, x1: int, y1: int, x2: int, y2: int) -> void:
	var w: int = grid[0].size()
	var h: int = grid.size()
	if x1 >= x2 - 4 or y1 >= y2 - 4:
		return
	var span: int = x2 - x1
	var left_edge: int = x1 + 2 + rng.randi_range(0, span - 1)
	var right_edge: int = x2 - 2 - rng.randi_range(0, span - 1)
	for j in range(y1 + 1, y2 - 1):
		for i in range(x1 + 1, x2 - 1):
			if i >= left_edge and i <= right_edge and grid[j][i] == C.T_FLOOR:
				grid[j][i] = C.T_WALL
		# Edge jitter — first half pulls outward, second half inward, with random kicks.
		if j - y1 < (y2 - y1) / 2 or rng.randi_range(0, 3) == 0:
			if left_edge > x1 + 1:
				left_edge -= rng.randi_range(0, 2)
			if right_edge < x2 - 1:
				right_edge += rng.randi_range(0, 2)
		if left_edge < x2 - 1 and (j - y1 >= (y2 - y1) / 2 or left_edge <= x1 + 2 or rng.randi_range(0, 3) == 0):
			left_edge += rng.randi_range(0, 2)
		if right_edge > x1 + 1 and (j - y1 >= (y2 - y1) / 2 or right_edge >= x2 - 2 or rng.randi_range(0, 3) == 0):
			right_edge -= rng.randi_range(0, 2)

# ============================================================================
# delve — the cave generator from dgn-delve.cc.
# Tunable cave width via ngb_min/ngb_max parameters:
#   - (1, 1): twisting 1-tile tunnels
#   - (2, 4): organic caves
#   - (3, 6): chunky open caverns
# connchance: 0-100, chance to allow new connections (loops)
# Returns same {grid, rooms, spawn, stairs_down} contract.
# ============================================================================

static func delve(grid: Array, rng: RandomNumberGenerator, _level_number: int, ngb_min: int = 2, ngb_max: int = 5, connchance: int = 35, target_floor_count: int = -1) -> Dictionary:
	var w: int = grid[0].size()
	var h: int = grid.size()
	# Initial seed: dig a small 3x3 cluster so the first candidates have enough
	# floor neighbors to clear the ngb_min threshold. With a single-cell seed,
	# every push-neighbor sees only 1 floor neighbor — anything ngb_min >= 2
	# stalls immediately and produces a degenerate 5x5 island.
	var seed_pos := Vector2i(w / 2, h / 2)
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var sx: int = seed_pos.x + dx
			var sy: int = seed_pos.y + dy
			if sx >= 1 and sy >= 1 and sx < w - 1 and sy < h - 1:
				grid[sy][sx] = C.T_FLOOR
	var store: Array[Vector2i] = []
	for dy2 in range(-2, 3):
		for dx2 in range(-2, 3):
			var n := Vector2i(seed_pos.x + dx2, seed_pos.y + dy2)
			if _diggable(grid, n.x, n.y):
				store.append(n)

	if target_floor_count < 0:
		# DCSS heuristic table — denser when ngb sum is low (skinny tunnels eat fewer cells).
		var denom_table := [0, 0, 8, 7, 6, 5, 5, 4, 4, 4, 3, 3]
		var sum: int = ngb_min + ngb_max
		var denom: int = 5
		if sum >= 2 and sum < denom_table.size():
			denom = denom_table[sum]
		target_floor_count = (w * h) / denom

	var delved: int = 9
	var safety: int = 0
	while delved < target_floor_count and not store.is_empty() and safety < 250000:
		safety += 1
		# Pull a candidate from the top of the store with some randomness.
		# DCSS pulls from "top 125" — we just pull a random recent entry.
		var top: int = mini(125, store.size())
		var idx: int = store.size() - 1 - rng.randi_range(0, top - 1)
		var c: Vector2i = store[idx]
		store.remove_at(idx)
		if not _diggable(grid, c.x, c.y):
			continue
		var ngb: int = _floor_neighbor_count(grid, c.x, c.y)
		if ngb < ngb_min or ngb > ngb_max:
			continue
		# If digging this cell would join two disconnected floor regions, only
		# do it with connchance% probability. This is what controls loop frequency.
		var groups: int = _floor_neighbor_groups(grid, c.x, c.y)
		if groups > 1 and rng.randi_range(0, 99) >= connchance:
			continue
		grid[c.y][c.x] = C.T_FLOOR
		delved += 1
		# Add neighbors in random order to prevent corner bias.
		var dirs: Array = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]
		dirs.shuffle()
		for d in dirs:
			var n: Vector2i = c + d
			if _diggable(grid, n.x, n.y):
				store.append(n)

	# Spawn at the cell with the most floor neighbors (open area centroid).
	var spawn: Vector2i = _open_spawn_cell(grid, seed_pos)
	# Ensure spawn area is open BEFORE picking stairs — so BFS has a wide start.
	_ensure_open_around(grid, spawn, 2)
	# Stairs at farthest reachable floor cell (BFS from spawn).
	var stairs: Vector2i = _farthest_floor_cell(grid, spawn)
	# Sanity: stairs must be different from spawn AND at least 8 cells away.
	if stairs == spawn or _chebyshev_v(stairs, spawn) < 8:
		# fallback: scan for any cell at least 8 away
		var alt: Vector2i = _find_cell_far_from(grid, spawn, 8)
		if alt.x >= 0:
			stairs = alt
	if stairs.x >= 0:
		grid[stairs.y][stairs.x] = C.T_STAIRS_DOWN
	return {
		"grid": grid,
		"rooms": [],
		"spawn": spawn,
		"stairs_down": stairs,
	}

static func _open_spawn_cell(grid: Array, prefer: Vector2i) -> Vector2i:
	# Among floor cells reachable from `prefer`, pick the one with the most
	# floor neighbors in a 3x3 box around it.
	var w: int = grid[0].size()
	var h: int = grid.size()
	var best: Vector2i = prefer
	var best_score: int = -1
	# BFS visit + score
	var visited: Dictionary = {}
	var queue: Array[Vector2i] = [prefer]
	visited[prefer] = true
	while not queue.is_empty():
		var c: Vector2i = queue.pop_front()
		# Score: count floor in 3x3 around c
		var score: int = 0
		for dy in range(-2, 3):
			for dx in range(-2, 3):
				var nx: int = c.x + dx
				var ny: int = c.y + dy
				if ny >= 0 and ny < h and nx >= 0 and nx < w and grid[ny][nx] == C.T_FLOOR:
					score += 1
		if score > best_score:
			best_score = score
			best = c
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			if visited.has(n):
				continue
			if n.y < 0 or n.y >= h or n.x < 0 or n.x >= w:
				continue
			if grid[n.y][n.x] != C.T_FLOOR:
				continue
			visited[n] = true
			queue.append(n)
	return best

static func _ensure_open_around(grid: Array, center: Vector2i, radius: int) -> void:
	var w: int = grid[0].size()
	var h: int = grid.size()
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var nx: int = center.x + dx
			var ny: int = center.y + dy
			if ny < 1 or ny >= h - 1 or nx < 1 or nx >= w - 1:
				continue
			if grid[ny][nx] == C.T_WALL:
				grid[ny][nx] = C.T_FLOOR

static func _diggable(grid: Array, x: int, y: int) -> bool:
	var w: int = grid[0].size()
	var h: int = grid.size()
	if x < 1 or y < 1 or x >= w - 1 or y >= h - 1:
		return false
	return grid[y][x] == C.T_WALL

static func _floor_neighbor_count(grid: Array, x: int, y: int) -> int:
	var n: int = 0
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]:
		var c := Vector2i(x + d.x, y + d.y)
		if c.y >= 0 and c.y < grid.size() and c.x >= 0 and c.x < grid[0].size():
			if grid[c.y][c.x] == C.T_FLOOR:
				n += 1
	return n

static func _floor_neighbor_groups(grid: Array, x: int, y: int) -> int:
	# Walk the 8 neighbors clockwise, count transitions from non-floor to floor.
	# This counts disjoint groups of dug-out neighbors.
	var compass := [Vector2i(0, -1), Vector2i(1, -1), Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0), Vector2i(-1, -1)]
	var groups: int = 0
	var prev_floor: bool = _is_floor_at(grid, x + compass[7].x, y + compass[7].y)
	var any_floor: bool = false
	for d in compass:
		var f: bool = _is_floor_at(grid, x + d.x, y + d.y)
		if f and not prev_floor:
			groups += 1
		if f:
			any_floor = true
		prev_floor = f
	if any_floor and groups == 0:
		return 1
	return groups

static func _is_floor_at(grid: Array, x: int, y: int) -> bool:
	if y < 0 or y >= grid.size() or x < 0 or x >= grid[0].size():
		return false
	return grid[y][x] == C.T_FLOOR

static func _chebyshev_v(a: Vector2i, b: Vector2i) -> int:
	return maxi(abs(a.x - b.x), abs(a.y - b.y))

static func _find_cell_far_from(grid: Array, origin: Vector2i, min_dist: int) -> Vector2i:
	var w: int = grid[0].size()
	var h: int = grid.size()
	for y in h:
		for x in w:
			if grid[y][x] != C.T_FLOOR:
				continue
			if _chebyshev_v(Vector2i(x, y), origin) >= min_dist:
				return Vector2i(x, y)
	return Vector2i(-1, -1)

static func _farthest_floor_cell(grid: Array, from: Vector2i) -> Vector2i:
	# BFS to find the farthest floor cell from a starting point.
	var w: int = grid[0].size()
	var h: int = grid.size()
	var dist: Array = []
	for y in h:
		var row := []
		row.resize(w)
		for x in w:
			row[x] = -1
		dist.append(row)
	dist[from.y][from.x] = 0
	var queue: Array[Vector2i] = [from]
	var farthest: Vector2i = from
	var max_d: int = 0
	while not queue.is_empty():
		var c: Vector2i = queue.pop_front()
		var d: int = dist[c.y][c.x]
		if d > max_d:
			max_d = d
			farthest = c
		for nd in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + nd
			if n.y < 0 or n.y >= h or n.x < 0 or n.x >= w:
				continue
			if dist[n.y][n.x] != -1:
				continue
			if grid[n.y][n.x] != C.T_FLOOR:
				continue
			dist[n.y][n.x] = d + 1
			queue.append(n)
	return farthest

# ============================================================================
# Helpers used by both layouts.
# ============================================================================

static func _scale_x(dcss_x: int, w: int) -> int:
	# DCSS uses 80-wide maps; scale to ours.
	return clampi(int(round(float(dcss_x) * w / 80.0)), 1, w - 2)

static func _scale_y(dcss_y: int, h: int) -> int:
	return clampi(int(round(float(dcss_y) * h / 70.0)), 1, h - 2)

static func _avg_two(rng: RandomNumberGenerator, n: int) -> int:
	# DCSS's random2avg(n, 2) — approximate normal distribution of [0, n).
	return (rng.randi_range(0, n - 1) + rng.randi_range(0, n - 1)) / 2

static func _weighted_choose(rng: RandomNumberGenerator, weights: Array, values: Array) -> int:
	var total: int = 0
	for w in weights:
		total += int(w)
	var roll: int = rng.randi_range(0, total - 1)
	var cum: int = 0
	for i in weights.size():
		cum += int(weights[i])
		if roll < cum:
			return int(values[i])
	return int(values[values.size() - 1])

static func _detect_rooms_for_compatibility(grid: Array) -> Array:
	# Our existing systems (vault stamper, "nearest unvisited room") rely on
	# rooms: Array[Rect2i]. The basic_level generator doesn't produce explicit
	# room records (rooms are emergent from carving). For compatibility, do a
	# rough flood-fill of dense floor regions and approximate them as Rects.
	# For now, return empty — vault stamper falls back gracefully (we'll teach
	# AI to fall back to "nearest unexplored floor cell").
	return []

static func _find_first_floor(grid: Array) -> Vector2i:
	for y in grid.size():
		for x in grid[0].size():
			if grid[y][x] == C.T_FLOOR:
				return Vector2i(x, y)
	return Vector2i(1, 1)

# ============================================================================
# Doors — convert a fraction of "doorway" floor cells into doors.
# A doorway is a floor cell with two opposing wall neighbors (forming a
# pinch point between rooms or between a room and a corridor). DCSS calls
# this a "good door spot." We sample these post-carve and convert ~30% of
# them to T_DOOR. Doors render as a sprite over floor; pathfinding/LoS
# treat them as walkable for v1 (no open/close gameplay).
# ============================================================================

static func _place_doors(grid: Array, rng: RandomNumberGenerator, _level_number: int) -> void:
	var w: int = grid[0].size()
	var h: int = grid.size()
	var placed: int = 0
	var probe := []
	for y in range(1, h - 1):
		for x in range(1, w - 1):
			if grid[y][x] != C.T_FLOOR:
				continue
			# Two opposing wall neighbors AND the perpendicular pair are open.
			var n_wall: bool = grid[y - 1][x] == C.T_WALL
			var s_wall: bool = grid[y + 1][x] == C.T_WALL
			var w_wall: bool = grid[y][x - 1] == C.T_WALL
			var e_wall: bool = grid[y][x + 1] == C.T_WALL
			var vertical_pinch: bool = w_wall and e_wall and not n_wall and not s_wall
			var horizontal_pinch: bool = n_wall and s_wall and not w_wall and not e_wall
			if not (vertical_pinch or horizontal_pinch):
				continue
			# Avoid placing two doors adjacent — single-cell choke is enough.
			if grid[y - 1][x] == C.T_DOOR or grid[y + 1][x] == C.T_DOOR:
				continue
			if grid[y][x - 1] == C.T_DOOR or grid[y][x + 1] == C.T_DOOR:
				continue
			probe.append(Vector2i(x, y))
	probe.shuffle()
	# Place ~30% of valid doorways as doors. Don't carpet — too many doors
	# turn dungeons into door warehouses.
	var target: int = mini(probe.size() / 3, 25)
	for i in target:
		var c: Vector2i = probe[i]
		grid[c.y][c.x] = C.T_DOOR
		placed += 1
