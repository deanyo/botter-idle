# Generation algorithms are original GDScript implementations of
# standard dungeon-layout patterns (drunkard-walk corridors,
# cellular cave excavation). Written from
# ~/claude/game-audit/findings/dcss_layouts_descriptions.md
# in a clean-room session that did not have access to GPLv2+ DCSS
# source. See CLAUDE.md "HOW TO PORT DCSS CODE" rules.
class_name DCSSLayouts
extends RefCounted

const C := preload("res://scripts/constants.gd")

const CORRIDOR_FILL_TARGET := 0.32
const CORRIDOR_MAX_STRAIGHT_LEN := 12
const CORRIDOR_INTERSECT_PERSIST_CHANCE := 0.45
const WALKER_COUNT := 3
const WALKER_MIN_SEPARATION_FRACTION := 0.22
const EDGE_AVOID_FRACTION := 0.18
const EDGE_BIAS_OVERRIDE_CHANCE := 0.40
const BORDER_CLAMP_MARGIN := 4
const PROBE_DISTANCE := 2
const MAX_VIABLE_START_RETRIES := 200
const SEGMENT_BUDGET_PER_WALKER := 200

const ROOM_MIN_SIZE := 4
const ROOM_MAX_SIZE := 9
const ROOM_COUNT_PER_AREA := 0.0035
const ROOM_PLACEMENT_FAILURE_BUDGET_MULT := 4

const DOMINANT_FEATURE_CHANCE_PER_FLOOR := 0.06
const DOMINANT_FEATURE_MIN_EXTENT_FRACTION := 0.25
const DOMINANT_FEATURE_PILLARED_PERIOD := 3

const HAZARD_BLOB_CHANCE := 0.05
const HAZARD_BLOB_DEPTH_GATE := 1
const HAZARD_BLOB_COUNT_MIN := 1
const HAZARD_BLOB_COUNT_MAX := 3
const HAZARD_BLOB_SIZE_MIN := 3
const HAZARD_BLOB_SIZE_MAX := 6

const DOOR_PLACEMENT_FRACTION := 0.34
const DOOR_TOTAL_CAP := 24

const LIQUID_RIVER_CHANCE := 0.50
const LIQUID_LAKE_CHANCE := 0.40
const LIQUID_POOL_CHANCE := 0.40
const LIQUID_SKIP_CHANCE := 0.005
const RIVER_WIDTH_MIN := 2
const RIVER_WIDTH_MAX := 5
const LAKE_RADIUS_MIN := 4
const LAKE_RADIUS_MAX := 8
const POOL_COUNT_MIN := 2
const POOL_COUNT_MAX := 5
const POOL_RADIUS_MIN := 2
const POOL_RADIUS_MAX := 4
const POOL_MIN_FLOOR_AREA := 6

const MIN_STAIRS_FROM_SPAWN := 8
const SPAWN_RADIUS_CARVE := 2
const SPAWN_SCORE_RADIUS := 2

const SEED_RADIUS := 1
const CANDIDATE_RECENCY_WINDOW := 96
const SAFETY_ITERATION_CAP := 250000


static func basic_level(grid: Array, rng: RandomNumberGenerator, level_number: int, liquid_type: String) -> Dictionary:
	var h: int = grid.size()
	var w: int = grid[0].size() if h > 0 else 0

	_carve_walker_corridors(grid, rng, w, h)
	_place_scattered_rooms(grid, rng, w, h)
	_drop_dominant_feature(grid, rng, w, h, level_number)
	_scatter_hazard_blobs(grid, rng, w, h, level_number)
	_bridge_floor_components(grid, w, h)
	_place_pinch_doors(grid, rng, w, h)
	if liquid_type != "":
		_apply_liquid(grid, rng, w, h, liquid_type)

	var spawn: Vector2i = _select_spawn_open_global(grid, w, h)
	if spawn.x < 0:
		spawn = Vector2i(w / 2, h / 2)
	_carve_clearing(grid, spawn, w, h, SPAWN_RADIUS_CARVE)
	var stairs: Vector2i = _select_far_stairs(grid, spawn, w, h)
	if stairs.x >= 0:
		grid[stairs.y][stairs.x] = C.T_STAIRS_DOWN

	return {
		"grid": grid,
		"rooms": [] as Array[Rect2i],
		"spawn": spawn,
		"stairs_down": stairs,
	}


static func make_trail(grid: Array, rng: RandomNumberGenerator, start_region_origin: Vector2i, start_region_size: Vector2i, corridor_max_length: int, intersect_persist_chance: float, segment_budget: int) -> Dictionary:
	var h: int = grid.size()
	var w: int = grid[0].size() if h > 0 else 0

	var begin: Vector2i = _find_viable_trail_start(grid, rng, start_region_origin, start_region_size, w, h)
	if begin.x < 0:
		return {}

	var pos: Vector2i = begin
	if grid[pos.y][pos.x] == C.T_WALL:
		grid[pos.y][pos.x] = C.T_FLOOR

	var segments_attempted: int = 0
	var dead_end_retry_grace: int = 0
	while segments_attempted < segment_budget + dead_end_retry_grace:
		segments_attempted += 1
		var direction: Vector2i = _pick_segment_direction(pos, w, h, rng)
		var seg_len: int = rng.randi_range(2, corridor_max_length)
		var joined_floor: bool = false
		for step in seg_len:
			var nxt: Vector2i = pos + direction
			if nxt.x <= BORDER_CLAMP_MARGIN or nxt.y <= BORDER_CLAMP_MARGIN or nxt.x >= w - BORDER_CLAMP_MARGIN - 1 or nxt.y >= h - BORDER_CLAMP_MARGIN - 1:
				break
			var probe: Vector2i = pos + direction * PROBE_DISTANCE
			if probe.x >= 0 and probe.y >= 0 and probe.x < w and probe.y < h:
				if grid[probe.y][probe.x] == C.T_FLOOR:
					if rng.randf() >= intersect_persist_chance:
						joined_floor = true
						break
			pos = nxt
			if grid[pos.y][pos.x] == C.T_WALL:
				grid[pos.y][pos.x] = C.T_FLOOR
			else:
				joined_floor = true
		if not joined_floor and segments_attempted == segment_budget and dead_end_retry_grace == 0:
			dead_end_retry_grace = 2

	return {"begin": begin, "end": pos}


static func delve(grid: Array, rng: RandomNumberGenerator, level_number: int, min_neighbors: int, max_neighbors: int, merge_chance_pct: int, target_floor_count: int, liquid_type: String) -> Dictionary:
	var h: int = grid.size()
	var w: int = grid[0].size() if h > 0 else 0

	var seed_center := Vector2i(w / 2, h / 2)
	for dy in range(-SEED_RADIUS, SEED_RADIUS + 1):
		for dx in range(-SEED_RADIUS, SEED_RADIUS + 1):
			grid[seed_center.y + dy][seed_center.x + dx] = C.T_FLOOR
	var carved_count: int = (SEED_RADIUS * 2 + 1) * (SEED_RADIUS * 2 + 1)

	if target_floor_count <= 0:
		target_floor_count = _density_target(w, h, min_neighbors + max_neighbors)

	var candidates: Array[Vector2i] = []
	for dy in range(-(SEED_RADIUS + 1), SEED_RADIUS + 2):
		for dx in range(-(SEED_RADIUS + 1), SEED_RADIUS + 2):
			var c := Vector2i(seed_center.x + dx, seed_center.y + dy)
			if c.x <= 1 or c.y <= 1 or c.x >= w - 2 or c.y >= h - 2:
				continue
			if grid[c.y][c.x] != C.T_WALL:
				continue
			candidates.append(c)

	var iter_safety: int = SAFETY_ITERATION_CAP
	while carved_count < target_floor_count and not candidates.is_empty() and iter_safety > 0:
		iter_safety -= 1
		var window_size: int = mini(CANDIDATE_RECENCY_WINDOW, candidates.size())
		var pop_idx: int = candidates.size() - 1 - rng.randi_range(0, window_size - 1)
		var c: Vector2i = candidates[pop_idx]
		candidates.remove_at(pop_idx)

		if c.x <= 1 or c.y <= 1 or c.x >= w - 2 or c.y >= h - 2:
			continue
		if grid[c.y][c.x] != C.T_WALL:
			continue

		var floor_neighbors: int = _count_floor_8(grid, c, w, h)
		if floor_neighbors < min_neighbors or floor_neighbors > max_neighbors:
			continue

		var groups: int = _count_neighbor_components(grid, c, w, h)
		if groups > 1:
			if rng.randi_range(0, 99) >= merge_chance_pct:
				continue

		grid[c.y][c.x] = C.T_FLOOR
		carved_count += 1

		var dirs: Array[Vector2i] = [
			Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
			Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
		]
		for i in range(dirs.size() - 1, 0, -1):
			var j: int = rng.randi_range(0, i)
			var t: Vector2i = dirs[i]
			dirs[i] = dirs[j]
			dirs[j] = t
		for d in dirs:
			var n: Vector2i = c + d
			if n.x <= 1 or n.y <= 1 or n.x >= w - 2 or n.y >= h - 2:
				continue
			if grid[n.y][n.x] != C.T_WALL:
				continue
			candidates.append(n)

	var spawn: Vector2i = _select_spawn_in_cave(grid, w, h, seed_center)
	_carve_clearing(grid, spawn, w, h, SPAWN_RADIUS_CARVE)
	var stairs: Vector2i = _select_far_stairs(grid, spawn, w, h)
	if stairs.x >= 0:
		grid[stairs.y][stairs.x] = C.T_STAIRS_DOWN

	if liquid_type != "":
		_apply_liquid(grid, rng, w, h, liquid_type)

	return {
		"grid": grid,
		"rooms": [] as Array[Rect2i],
		"spawn": spawn,
		"stairs_down": stairs,
	}


static func _density_target(w: int, h: int, neighbor_sum: int) -> int:
	# Flatter divisor than a steep linear ramp: bot AI is tuned to navigate
	# caves of ~1500-1800 cells regardless of neighbor-rule profile. The
	# description's "denser for skinny tunnels" principle is preserved by
	# the +(sum-7)*0.25 slope, but the clamp compresses the spread so
	# every config lands in a navigable size band.
	var divisor: float = clampf(3.4 + (neighbor_sum - 7) * 0.25, 3.4, 4.5)
	return int(float(w * h) / divisor)


static func _carve_walker_corridors(grid: Array, rng: RandomNumberGenerator, w: int, h: int) -> void:
	var area: int = w * h
	var target_carved: int = int(area * CORRIDOR_FILL_TARGET)
	var starts: Array[Vector2i] = _scatter_walker_starts(rng, w, h, WALKER_COUNT)
	for s in starts:
		if _count_floor_cells(grid, w, h) >= target_carved:
			break
		make_trail(grid, rng, s, Vector2i(1, 1), CORRIDOR_MAX_STRAIGHT_LEN, CORRIDOR_INTERSECT_PERSIST_CHANCE, SEGMENT_BUDGET_PER_WALKER)


static func _scatter_walker_starts(rng: RandomNumberGenerator, w: int, h: int, count: int) -> Array[Vector2i]:
	var starts: Array[Vector2i] = []
	var min_sep: int = int(mini(w, h) * WALKER_MIN_SEPARATION_FRACTION)
	var attempts: int = 200
	while starts.size() < count and attempts > 0:
		attempts -= 1
		var p := Vector2i(
			rng.randi_range(BORDER_CLAMP_MARGIN + 1, w - BORDER_CLAMP_MARGIN - 2),
			rng.randi_range(BORDER_CLAMP_MARGIN + 1, h - BORDER_CLAMP_MARGIN - 2)
		)
		var ok: bool = true
		for s in starts:
			if absi(p.x - s.x) + absi(p.y - s.y) < min_sep:
				ok = false
				break
		if ok:
			starts.append(p)
	while starts.size() < count:
		starts.append(Vector2i(
			rng.randi_range(BORDER_CLAMP_MARGIN + 1, w - BORDER_CLAMP_MARGIN - 2),
			rng.randi_range(BORDER_CLAMP_MARGIN + 1, h - BORDER_CLAMP_MARGIN - 2)
		))
	return starts


static func _find_viable_trail_start(grid: Array, rng: RandomNumberGenerator, origin: Vector2i, size: Vector2i, w: int, h: int) -> Vector2i:
	var rsx_max: int = origin.x + maxi(1, size.x) - 1
	var rsy_max: int = origin.y + maxi(1, size.y) - 1
	for tries in MAX_VIABLE_START_RETRIES:
		var x: int = rng.randi_range(origin.x, rsx_max)
		var y: int = rng.randi_range(origin.y, rsy_max)
		if x <= BORDER_CLAMP_MARGIN or y <= BORDER_CLAMP_MARGIN or x >= w - BORDER_CLAMP_MARGIN - 1 or y >= h - BORDER_CLAMP_MARGIN - 1:
			continue
		var has_wall_neighbor: bool = false
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n := Vector2i(x + d.x, y + d.y)
			if grid[n.y][n.x] == C.T_WALL:
				has_wall_neighbor = true
				break
		if has_wall_neighbor:
			return Vector2i(x, y)
	return Vector2i(-1, -1)


static func _pick_segment_direction(pos: Vector2i, w: int, h: int, rng: RandomNumberGenerator) -> Vector2i:
	var dirs: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	if rng.randf() < EDGE_BIAS_OVERRIDE_CHANCE:
		return dirs[rng.randi() % dirs.size()]
	var margin_x: int = int(w * EDGE_AVOID_FRACTION)
	var margin_y: int = int(h * EDGE_AVOID_FRACTION)
	var viable: Array[Vector2i] = []
	for d in dirs:
		if d.x > 0 and pos.x > w - margin_x:
			continue
		if d.x < 0 and pos.x < margin_x:
			continue
		if d.y > 0 and pos.y > h - margin_y:
			continue
		if d.y < 0 and pos.y < margin_y:
			continue
		viable.append(d)
	if viable.is_empty():
		return dirs[rng.randi() % dirs.size()]
	return viable[rng.randi() % viable.size()]


static func _bridge_floor_components(grid: Array, w: int, h: int) -> void:
	var components: Array = _find_floor_components(grid, w, h)
	if components.size() <= 1:
		return
	var primary_idx: int = 0
	for i in range(components.size()):
		if components[i].size() > components[primary_idx].size():
			primary_idx = i
	var anchor: Vector2i = components[primary_idx][components[primary_idx].size() / 2]
	for i in range(components.size()):
		if i == primary_idx:
			continue
		var comp: Array = components[i]
		var target: Vector2i = comp[comp.size() / 2]
		_carve_greedy_line(grid, w, h, target, anchor)


static func _find_floor_components(grid: Array, w: int, h: int) -> Array:
	var visited: Dictionary = {}
	var out: Array = []
	for y in h:
		for x in w:
			var key := Vector2i(x, y)
			if visited.has(key):
				continue
			if grid[y][x] != C.T_FLOOR:
				continue
			var comp: Array[Vector2i] = []
			var queue: Array[Vector2i] = [key]
			visited[key] = true
			var head: int = 0
			while head < queue.size():
				var c: Vector2i = queue[head]
				head += 1
				comp.append(c)
				for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var n: Vector2i = c + d
					if n.x < 0 or n.y < 0 or n.x >= w or n.y >= h:
						continue
					if visited.has(n):
						continue
					if grid[n.y][n.x] != C.T_FLOOR:
						continue
					visited[n] = true
					queue.append(n)
			out.append(comp)
	return out


static func _carve_greedy_line(grid: Array, w: int, h: int, from: Vector2i, to: Vector2i) -> void:
	var p: Vector2i = from
	var safety: int = w + h + 10
	while p != to and safety > 0:
		safety -= 1
		var dx: int = to.x - p.x
		var dy: int = to.y - p.y
		if absi(dx) > absi(dy):
			p.x += signi(dx)
		elif absi(dy) > 0:
			p.y += signi(dy)
		else:
			p.x += signi(dx)
		if p.x <= 0 or p.y <= 0 or p.x >= w - 1 or p.y >= h - 1:
			return
		if grid[p.y][p.x] == C.T_WALL:
			grid[p.y][p.x] = C.T_FLOOR


static func _place_scattered_rooms(grid: Array, rng: RandomNumberGenerator, w: int, h: int) -> void:
	var area: int = w * h
	var target_count: int = int(area * ROOM_COUNT_PER_AREA)
	var attempt_budget: int = target_count * ROOM_PLACEMENT_FAILURE_BUDGET_MULT
	var placed: int = 0
	var attempts: int = 0
	while placed < target_count and attempts < attempt_budget:
		attempts += 1
		var rw: int = rng.randi_range(ROOM_MIN_SIZE, ROOM_MAX_SIZE)
		var rh: int = rng.randi_range(ROOM_MIN_SIZE, ROOM_MAX_SIZE)
		var rx: int = rng.randi_range(2, w - rw - 2)
		var ry: int = rng.randi_range(2, h - rh - 2)
		var rect := Rect2i(rx, ry, rw, rh)
		if not _room_has_viable_door(grid, rect, w, h):
			continue
		for y in range(ry, ry + rh):
			for x in range(rx, rx + rw):
				if grid[y][x] == C.T_WALL:
					grid[y][x] = C.T_FLOOR
		placed += 1


static func _room_has_viable_door(grid: Array, rect: Rect2i, w: int, h: int) -> bool:
	for x in range(rect.position.x, rect.position.x + rect.size.x):
		var top_y: int = rect.position.y - 1
		if top_y > 0 and x > 0 and x < w - 1:
			if grid[top_y][x - 1] == C.T_WALL and grid[top_y][x + 1] == C.T_WALL:
				return true
		var bot_y: int = rect.position.y + rect.size.y
		if bot_y < h - 1 and x > 0 and x < w - 1:
			if grid[bot_y][x - 1] == C.T_WALL and grid[bot_y][x + 1] == C.T_WALL:
				return true
	for y in range(rect.position.y, rect.position.y + rect.size.y):
		var left_x: int = rect.position.x - 1
		if left_x > 0 and y > 0 and y < h - 1:
			if grid[y - 1][left_x] == C.T_WALL and grid[y + 1][left_x] == C.T_WALL:
				return true
		var right_x: int = rect.position.x + rect.size.x
		if right_x < w - 1 and y > 0 and y < h - 1:
			if grid[y - 1][right_x] == C.T_WALL and grid[y + 1][right_x] == C.T_WALL:
				return true
	return false


static func _drop_dominant_feature(grid: Array, rng: RandomNumberGenerator, w: int, h: int, level_number: int) -> void:
	if level_number < 1:
		return
	if rng.randf() > DOMINANT_FEATURE_CHANCE_PER_FLOOR:
		return
	var min_extent: int = int(mini(w, h) * DOMINANT_FEATURE_MIN_EXTENT_FRACTION)
	var fw: int = rng.randi_range(min_extent, min_extent + 8)
	var fh: int = rng.randi_range(min_extent, min_extent + 8)
	var fx: int = rng.randi_range(3, w - fw - 3)
	var fy: int = rng.randi_range(3, h - fh - 3)
	var center := Vector2i(fx + fw / 2, fy + fh / 2)
	if rng.randf() < 0.5:
		var rx: float = fw * 0.5
		var ry: float = fh * 0.5
		for y in range(fy, fy + fh):
			for x in range(fx, fx + fw):
				var ndx: float = (x - center.x) / rx
				var ndy: float = (y - center.y) / ry
				if ndx * ndx + ndy * ndy <= 1.0:
					if grid[y][x] == C.T_WALL:
						grid[y][x] = C.T_FLOOR
	else:
		for y in range(fy, fy + fh):
			for x in range(fx, fx + fw):
				if grid[y][x] == C.T_WALL:
					grid[y][x] = C.T_FLOOR
		var period: int = DOMINANT_FEATURE_PILLARED_PERIOD
		for y in range(fy + period - 1, fy + fh - 1, period):
			for x in range(fx + period - 1, fx + fw - 1, period):
				grid[y][x] = C.T_WALL


static func _scatter_hazard_blobs(grid: Array, rng: RandomNumberGenerator, w: int, h: int, level_number: int) -> void:
	if level_number < HAZARD_BLOB_DEPTH_GATE:
		return
	if rng.randf() > HAZARD_BLOB_CHANCE:
		return
	var count: int = rng.randi_range(HAZARD_BLOB_COUNT_MIN, HAZARD_BLOB_COUNT_MAX)
	for i in count:
		var r: int = rng.randi_range(HAZARD_BLOB_SIZE_MIN, HAZARD_BLOB_SIZE_MAX)
		var cx: int = rng.randi_range(r + 2, w - r - 3)
		var cy: int = rng.randi_range(r + 2, h - r - 3)
		var l1_cutoff: int = int(r * 1.5)
		for y in range(cy - r, cy + r + 1):
			for x in range(cx - r, cx + r + 1):
				if x <= 1 or y <= 1 or x >= w - 2 or y >= h - 2:
					continue
				var dx: int = absi(x - cx)
				var dy: int = absi(y - cy)
				if maxi(dx, dy) <= r and dx + dy <= l1_cutoff:
					grid[y][x] = C.T_WALL


static func _place_pinch_doors(grid: Array, rng: RandomNumberGenerator, w: int, h: int) -> void:
	var candidates: Array[Vector2i] = []
	for y in range(1, h - 1):
		for x in range(1, w - 1):
			if grid[y][x] != C.T_FLOOR:
				continue
			var n: int = grid[y - 1][x]
			var s: int = grid[y + 1][x]
			var e: int = grid[y][x + 1]
			var ww: int = grid[y][x - 1]
			var horiz_pinch: bool = (ww == C.T_WALL and e == C.T_WALL) and (n == C.T_FLOOR and s == C.T_FLOOR)
			var vert_pinch: bool = (n == C.T_WALL and s == C.T_WALL) and (ww == C.T_FLOOR and e == C.T_FLOOR)
			if horiz_pinch or vert_pinch:
				candidates.append(Vector2i(x, y))
	for i in range(candidates.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var t: Vector2i = candidates[i]
		candidates[i] = candidates[j]
		candidates[j] = t
	var placed: int = 0
	var placed_cells: Dictionary = {}
	for c in candidates:
		if placed >= DOOR_TOTAL_CAP:
			break
		if rng.randf() > DOOR_PLACEMENT_FRACTION:
			continue
		var skip: bool = false
		for dy in [-1, 0, 1]:
			for dx in [-1, 0, 1]:
				if placed_cells.has(Vector2i(c.x + dx, c.y + dy)):
					skip = true
					break
			if skip:
				break
		if skip:
			continue
		grid[c.y][c.x] = C.T_DOOR
		placed_cells[c] = true
		placed += 1


static func _apply_liquid(grid: Array, rng: RandomNumberGenerator, w: int, h: int, liquid_type: String) -> void:
	var tile: int = C.T_WATER if liquid_type == "water" else C.T_LAVA
	var fired: bool = false
	if rng.randf() < LIQUID_RIVER_CHANCE:
		_paint_river(grid, rng, w, h, tile)
		fired = true
	if rng.randf() < LIQUID_LAKE_CHANCE:
		_paint_lake(grid, rng, w, h, tile)
		fired = true
	if rng.randf() < LIQUID_POOL_CHANCE:
		_paint_pools(grid, rng, w, h, tile)
		fired = true
	if not fired:
		_paint_lake(grid, rng, w, h, tile)


static func _paint_river(grid: Array, rng: RandomNumberGenerator, w: int, h: int, tile: int) -> void:
	var y: int = rng.randi_range(h / 4, 3 * h / 4)
	var width: int = rng.randi_range(RIVER_WIDTH_MIN, RIVER_WIDTH_MAX)
	for x in w:
		var lo: int = y - width / 2
		var hi: int = y + (width - width / 2)
		for ty in range(lo, hi):
			if ty <= 0 or ty >= h - 1:
				continue
			if grid[ty][x] != C.T_FLOOR:
				continue
			if rng.randf() < LIQUID_SKIP_CHANCE:
				continue
			grid[ty][x] = tile
		if rng.randf() < 0.30:
			y += rng.randi_range(-1, 1)
			y = clampi(y, h / 6, 5 * h / 6)
		if rng.randf() < 0.15:
			width += rng.randi_range(-1, 1)
			width = clampi(width, RIVER_WIDTH_MIN, RIVER_WIDTH_MAX)


static func _paint_lake(grid: Array, rng: RandomNumberGenerator, w: int, h: int, tile: int) -> void:
	var radius: int = rng.randi_range(LAKE_RADIUS_MIN, LAKE_RADIUS_MAX)
	var cx: int = rng.randi_range(radius + 2, w - radius - 3)
	var cy: int = rng.randi_range(radius + 2, h - radius - 3)
	for dy in range(-radius, radius + 1):
		var ty: int = cy + dy
		if ty <= 0 or ty >= h - 1:
			continue
		var ratio: float = float(dy) / float(radius)
		var envelope: int = int(radius * sqrt(maxf(0.0, 1.0 - ratio * ratio)))
		var jitter: int = rng.randi_range(-1, 1)
		var w_row: int = maxi(0, envelope + jitter)
		for dx in range(-w_row, w_row + 1):
			var tx: int = cx + dx
			if tx <= 0 or tx >= w - 1:
				continue
			if grid[ty][tx] != C.T_FLOOR:
				continue
			if rng.randf() < LIQUID_SKIP_CHANCE:
				continue
			grid[ty][tx] = tile


static func _paint_pools(grid: Array, rng: RandomNumberGenerator, w: int, h: int, tile: int) -> void:
	var n: int = rng.randi_range(POOL_COUNT_MIN, POOL_COUNT_MAX)
	for i in n:
		var radius: int = rng.randi_range(POOL_RADIUS_MIN, POOL_RADIUS_MAX)
		var cx: int = rng.randi_range(radius + 2, w - radius - 3)
		var cy: int = rng.randi_range(radius + 2, h - radius - 3)
		var floor_count: int = 0
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if grid[cy + dy][cx + dx] == C.T_FLOOR:
					floor_count += 1
		if floor_count < POOL_MIN_FLOOR_AREA:
			continue
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if dx * dx + dy * dy > radius * radius:
					continue
				var ty: int = cy + dy
				var tx: int = cx + dx
				if grid[ty][tx] != C.T_FLOOR:
					continue
				if rng.randf() < LIQUID_SKIP_CHANCE:
					continue
				grid[ty][tx] = tile


static func _select_spawn_open_global(grid: Array, w: int, h: int) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_score: int = -1
	for y in range(SPAWN_SCORE_RADIUS, h - SPAWN_SCORE_RADIUS):
		for x in range(SPAWN_SCORE_RADIUS, w - SPAWN_SCORE_RADIUS):
			if grid[y][x] != C.T_FLOOR:
				continue
			var score: int = 0
			for dy in range(-SPAWN_SCORE_RADIUS, SPAWN_SCORE_RADIUS + 1):
				for dx in range(-SPAWN_SCORE_RADIUS, SPAWN_SCORE_RADIUS + 1):
					if grid[y + dy][x + dx] == C.T_FLOOR:
						score += 1
			if score > best_score:
				best_score = score
				best = Vector2i(x, y)
	return best


static func _select_spawn_in_cave(grid: Array, w: int, h: int, seed: Vector2i) -> Vector2i:
	var visited: Dictionary = {seed: true}
	var queue: Array[Vector2i] = [seed]
	var head: int = 0
	var best: Vector2i = seed
	var best_score: int = -1
	while head < queue.size():
		var c: Vector2i = queue[head]
		head += 1
		if c.x >= SPAWN_SCORE_RADIUS and c.y >= SPAWN_SCORE_RADIUS and c.x < w - SPAWN_SCORE_RADIUS and c.y < h - SPAWN_SCORE_RADIUS:
			var score: int = 0
			for dy in range(-SPAWN_SCORE_RADIUS, SPAWN_SCORE_RADIUS + 1):
				for dx in range(-SPAWN_SCORE_RADIUS, SPAWN_SCORE_RADIUS + 1):
					if grid[c.y + dy][c.x + dx] == C.T_FLOOR:
						score += 1
			if score > best_score:
				best_score = score
				best = c
		for nd in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + nd
			if n.x < 0 or n.y < 0 or n.x >= w or n.y >= h:
				continue
			if visited.has(n):
				continue
			if grid[n.y][n.x] != C.T_FLOOR:
				continue
			visited[n] = true
			queue.append(n)
	return best


static func _carve_clearing(grid: Array, center: Vector2i, w: int, h: int, radius: int) -> void:
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var x: int = center.x + dx
			var y: int = center.y + dy
			if x <= 0 or y <= 0 or x >= w - 1 or y >= h - 1:
				continue
			if grid[y][x] == C.T_WALL:
				grid[y][x] = C.T_FLOOR


static func _select_far_stairs(grid: Array, spawn: Vector2i, w: int, h: int) -> Vector2i:
	if spawn.x < 0:
		return spawn
	var dist: Array = []
	for y in h:
		var row: Array = []
		row.resize(w)
		for x in w:
			row[x] = -1
		dist.append(row)
	dist[spawn.y][spawn.x] = 0
	var queue: Array[Vector2i] = [spawn]
	var head: int = 0
	var farthest: Vector2i = spawn
	var farthest_d: int = 0
	while head < queue.size():
		var c: Vector2i = queue[head]
		head += 1
		var d: int = dist[c.y][c.x]
		if d > farthest_d:
			farthest_d = d
			farthest = c
		for nd in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + nd
			if n.x < 0 or n.y < 0 or n.x >= w or n.y >= h:
				continue
			if dist[n.y][n.x] != -1:
				continue
			if grid[n.y][n.x] != C.T_FLOOR:
				continue
			dist[n.y][n.x] = d + 1
			queue.append(n)
	if farthest_d >= MIN_STAIRS_FROM_SPAWN:
		return farthest
	for y in h:
		for x in w:
			if grid[y][x] != C.T_FLOOR:
				continue
			var dx: int = absi(x - spawn.x)
			var dy: int = absi(y - spawn.y)
			if maxi(dx, dy) >= MIN_STAIRS_FROM_SPAWN:
				return Vector2i(x, y)
	return farthest


static func _count_floor_8(grid: Array, c: Vector2i, w: int, h: int) -> int:
	var n: int = 0
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			var ty: int = c.y + dy
			var tx: int = c.x + dx
			if ty < 0 or tx < 0 or ty >= h or tx >= w:
				continue
			var v: int = grid[ty][tx]
			if v == C.T_FLOOR or v == C.T_STAIRS_DOWN or v == C.T_DOOR:
				n += 1
	return n


static func _count_neighbor_components(grid: Array, c: Vector2i, w: int, h: int) -> int:
	var offsets: Array[Vector2i] = [
		Vector2i(0, -1), Vector2i(1, -1), Vector2i(1, 0), Vector2i(1, 1),
		Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0), Vector2i(-1, -1),
	]
	var flags: Array[bool] = [false, false, false, false, false, false, false, false]
	var any_floor: bool = false
	for i in 8:
		var n: Vector2i = c + offsets[i]
		var is_floor: bool = false
		if n.x >= 0 and n.y >= 0 and n.x < w and n.y < h:
			var v: int = grid[n.y][n.x]
			is_floor = (v == C.T_FLOOR or v == C.T_STAIRS_DOWN or v == C.T_DOOR)
		flags[i] = is_floor
		if is_floor:
			any_floor = true
	var groups: int = 0
	for i in 8:
		var prev_idx: int = (i + 7) % 8
		if flags[i] and not flags[prev_idx]:
			groups += 1
	if any_floor and groups == 0:
		groups = 1
	return groups


static func _count_floor_cells(grid: Array, w: int, h: int) -> int:
	var n: int = 0
	for y in h:
		for x in w:
			if grid[y][x] == C.T_FLOOR:
				n += 1
	return n
