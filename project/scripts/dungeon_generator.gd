class_name DungeonGenerator
extends RefCounted

const C := preload("res://scripts/constants.gd")

const MIN_LEAF := 8
const MIN_ROOM := 4
const MAX_ROOM_PADDING := 2

var rng: RandomNumberGenerator
var grid: Array
var rooms: Array[Rect2i] = []

class Leaf:
	var rect: Rect2i
	var left: Leaf
	var right: Leaf
	var room: Rect2i

	func _init(r: Rect2i) -> void:
		rect = r

	func is_leaf() -> bool:
		return left == null and right == null

func _init(rng_seed: int = 0) -> void:
	rng = RandomNumberGenerator.new()
	if rng_seed != 0:
		rng.seed = rng_seed
	else:
		rng.randomize()

func generate_themed(w: int, h: int, themes: Array, floor_num: int, layout_id: String, biome_id: String = "") -> Dictionary:
	# Pick the "best-fit" theme for this build pass: shuffle and try each, so
	# vault candidates from any matching theme can be selected. We pass the
	# whole list to filtering. For the legacy single-theme path, generate()
	# wraps a single-element array.
	_active_themes = themes.duplicate()
	_active_biome_id = biome_id
	return generate(w, h, "" if themes.is_empty() else String(themes[0]), floor_num, layout_id)

var _active_themes: Array = []
var _active_biome_id: String = ""

func _themes_or(fallback: String) -> Array:
	if not _active_themes.is_empty():
		return _active_themes
	return [fallback]

func generate(w: int = C.MAP_W, h: int = C.MAP_H, theme: String = "dungeon", floor_num: int = 1, layout_id: String = "basic") -> Dictionary:
	const MIN_FLOOR_CELLS := 200
	const MAX_REGEN_ATTEMPTS := 8
	var spawn_cell := Vector2i(1, 1)
	var stairs_cell := Vector2i(1, 1)
	var vault_results: Dictionary = {}
	var dist_to_stairs: Array = []
	for attempt in MAX_REGEN_ATTEMPTS:
		grid = []
		rooms.clear()
		for y in h:
			var row := []
			row.resize(w)
			for x in w:
				row[x] = C.T_WALL
			grid.append(row)

		vault_results = _new_vault_results()

		# DCSS step 1: encompass-vault short-circuit. If the library has an
		# encompass-orient vault matching this biome+depth, stamp it as the
		# entire level and skip layout generation.
		var encompass_handled: bool = _try_stamp_encompass(theme, floor_num, vault_results)
		if encompass_handled:
			# Encompass vault dictates spawn/stairs via stair_marks if present;
			# otherwise we synthesize. We then verify the largest connected
			# region, derive spawn from inside it, and orphan-rescue any
			# disconnected pockets so a single ASCII typo in the vault doesn't
			# kill the run.
			var stair_info: Dictionary = _resolve_stairs_from_marks(vault_results)
			spawn_cell = stair_info.spawn
			stairs_cell = stair_info.stairs
			# Pick spawn from the largest connected region instead of trusting
			# the vault's < glyph (the vault may carry stairs in disconnected
			# sub-regions). Stairs cell stays as authored, then orphan-rescue.
			var fallback: Vector2i = _spawn_in_largest_region(w, h)
			if fallback.x >= 0:
				spawn_cell = fallback
			_connect_orphans_to_main(spawn_cell)
			# Re-place stairs on a walkable cell if the rescue carve covered them.
			if stairs_cell.x >= 0 and stairs_cell.y >= 0 and stairs_cell.y < h and stairs_cell.x < w:
				grid[stairs_cell.y][stairs_cell.x] = C.T_STAIRS_DOWN
		else:
			var spawn_stairs: Dictionary = _carve_layout(layout_id, w, h, floor_num)
			spawn_cell = spawn_stairs.spawn
			stairs_cell = spawn_stairs.stairs

			var floor_count: int = _count_floor_cells(w, h)
			if floor_count < MIN_FLOOR_CELLS:
				continue
			# Largest reachable region must also be big — otherwise we have a
			# fragmented map even if the total cell count is high.
			var largest_region: int = _largest_floor_region_size(w, h)
			if largest_region < MIN_FLOOR_CELLS:
				continue

			# DCSS step 2: detect open regions and stamp orient + float vaults.
			rooms = _detect_open_regions(w, h, 5, 5, 30)
			_stamp_oriented_vaults(theme, floor_num, vault_results)
			_stamp_float_vaults(theme, floor_num, vault_results)

			# DCSS step 3: ensure spawn and stairs are still floor.
			if grid[spawn_cell.y][spawn_cell.x] != C.T_FLOOR:
				grid[spawn_cell.y][spawn_cell.x] = C.T_FLOOR
			grid[stairs_cell.y][stairs_cell.x] = C.T_STAIRS_DOWN

			# DCSS step 3.5: connect orphan regions to the main reachable area.
			# Vault stamping can occasionally seal a vault interior off from the
			# rest of the map; carve a corridor from each orphan to the nearest
			# main-region floor cell.
			_connect_orphans_to_main(spawn_cell)

		# DCSS step 4: connectivity verification.
		dist_to_stairs = _build_distance_map(stairs_cell, w, h)
		if dist_to_stairs[spawn_cell.y][spawn_cell.x] < 0:
			continue
		break

	var log_biome: String = _active_biome_id if _active_biome_id != "" else theme
	_log_floor_metrics(layout_id, log_biome, floor_num, w, h, spawn_cell, stairs_cell, vault_results)

	return {
		"grid": grid,
		"rooms": rooms,
		"width": w,
		"height": h,
		"spawn": spawn_cell,
		"stairs_down": stairs_cell,
		"vault_results": vault_results,
		"dist_to_stairs": dist_to_stairs,
	}

func _log_floor_metrics(layout_id: String, theme: String, floor_num: int, w: int, h: int, spawn: Vector2i, stairs: Vector2i, vault_results: Dictionary) -> void:
	var floor_count: int = _count_floor_cells(w, h)
	# Largest connected floor region.
	var visited: Dictionary = {}
	var largest: int = 0
	var region_count: int = 0
	for y in h:
		for x in w:
			var cell := Vector2i(x, y)
			if visited.has(cell):
				continue
			var v: int = grid[y][x]
			if v != C.T_FLOOR and v != C.T_STAIRS_DOWN and v != C.T_DOOR:
				continue
			region_count += 1
			var size: int = 0
			var stack: Array[Vector2i] = [cell]
			while not stack.is_empty():
				var c: Vector2i = stack.pop_back()
				if visited.has(c):
					continue
				visited[c] = true
				if c.y < 0 or c.x < 0 or c.y >= h or c.x >= w:
					continue
				var cv: int = grid[c.y][c.x]
				if cv != C.T_FLOOR and cv != C.T_STAIRS_DOWN and cv != C.T_DOOR:
					continue
				size += 1
				stack.append(Vector2i(c.x + 1, c.y))
				stack.append(Vector2i(c.x - 1, c.y))
				stack.append(Vector2i(c.x, c.y + 1))
				stack.append(Vector2i(c.x, c.y - 1))
			largest = maxi(largest, size)
	var bbox_min := Vector2i(w, h)
	var bbox_max := Vector2i(0, 0)
	for y in h:
		for x in w:
			var cv: int = grid[y][x]
			if cv == C.T_FLOOR or cv == C.T_STAIRS_DOWN or cv == C.T_DOOR:
				bbox_min.x = mini(bbox_min.x, x)
				bbox_min.y = mini(bbox_min.y, y)
				bbox_max.x = maxi(bbox_max.x, x)
				bbox_max.y = maxi(bbox_max.y, y)
	var bbox_w: int = bbox_max.x - bbox_min.x + 1
	var bbox_h: int = bbox_max.y - bbox_min.y + 1
	var bad: Array = []
	if floor_count < 250:
		bad.append("floor_count<250")
	if largest < 400:
		bad.append("largest_region<400")
	# Small disconnected pockets are fine in caves; only flag if they're big
	# enough to look like content the bot should have reached.
	var orphan: int = floor_count - largest
	if orphan > 60:
		bad.append("orphan_cells=%d" % orphan)
	if bbox_w * bbox_h < 400:
		bad.append("bbox<400")
	var msg: String = "[gen] f=%d biome=%s layout=%s cells=%d largest=%d regions=%d bbox=%dx%d rooms=%d vaults=%s" % [
		floor_num, theme, layout_id, floor_count, largest, region_count,
		bbox_w, bbox_h, rooms.size(), str(vault_results.get("placed_vaults", [])),
	]
	if not bad.is_empty():
		msg = "[bad-floor] " + " ".join(bad) + " | " + msg
	GrindLog.log_line(msg)

func _new_vault_results() -> Dictionary:
	return {
		"fountains": [], "statues": [], "loot_marks": [], "chest_marks": [],
		"altar_marks": [], "stair_marks": [], "spawn_overrides": {},
		"placed_vaults": [], "no_spawn_zones": [], "protected_cells": {},
		"decor_marks": [],
	}

func _carve_layout(layout_id: String, w: int, h: int, floor_num: int) -> Dictionary:
	var spawn := Vector2i(1, 1)
	var stairs := Vector2i(1, 1)
	# Pull liquid_type from biome so river/lake builders can stamp T_WATER /
	# T_LAVA in the right biomes (forge → lava, shoals → water, etc).
	var liquid_type: String = ""
	if _active_biome_id != "":
		liquid_type = BiomeData.liquid_type_for(BiomeData.get_biome(_active_biome_id))
	match layout_id:
		"caves":
			var result: Dictionary = DCSSLayouts.delve(grid, rng, floor_num, 2, 5, 35, -1, liquid_type)
			grid = result.grid
			spawn = result.spawn
			stairs = result.stairs_down
		"caves_tight":
			var result: Dictionary = DCSSLayouts.delve(grid, rng, floor_num, 2, 4, 50, -1, liquid_type)
			grid = result.grid
			spawn = result.spawn
			stairs = result.stairs_down
		"caves_open":
			var result: Dictionary = DCSSLayouts.delve(grid, rng, floor_num, 3, 6, 60, -1, liquid_type)
			grid = result.grid
			spawn = result.spawn
			stairs = result.stairs_down
		_:
			var result: Dictionary = DCSSLayouts.basic_level(grid, rng, floor_num, liquid_type)
			grid = result.grid
			spawn = result.spawn
			stairs = result.stairs_down
	return {"spawn": spawn, "stairs": stairs}

func _try_stamp_encompass(theme: String, floor_num: int, results: Dictionary) -> bool:
	var encompass: Array = VaultLibrary.encompass_candidates_multi(_themes_or(theme), floor_num)
	if encompass.is_empty():
		return false
	# Debug-jump always stamps the forced vault. Otherwise rare gate.
	if not DebugJump.active or DebugJump.vault_name == "":
		if rng.randf() > 0.25:
			return false
	var picked: Dictionary = VaultLibrary.pick_weighted(encompass, rng)
	if picked.is_empty():
		return false
	if not VaultLibrary.passes_chance(picked, floor_num, rng):
		return false
	var ok: bool = VaultStamper.try_stamp_oriented(grid, [], picked, rng, results)
	if ok:
		results["placed_vaults"].append(String(picked.get("name", "")))
		# Encompass vault may define its own rooms via tagged regions later;
		# for now, detect open regions post-stamp.
		rooms = _detect_open_regions(grid[0].size(), grid.size(), 5, 5, 30)
	return ok

func _resolve_stairs_from_marks(results: Dictionary) -> Dictionary:
	var stair_marks: Array = results.get("stair_marks", [])
	var down: Vector2i = Vector2i(-1, -1)
	var up: Vector2i = Vector2i(-1, -1)
	for m in stair_marks:
		var c: Vector2i = m.cell
		if String(m.kind) == "down":
			down = c
		elif String(m.kind) == "up":
			up = c
	if down.x < 0:
		down = _find_walkable_cell()
	if up.x < 0:
		up = _find_walkable_cell_far_from(down)
	# Encompass vaults embed their stairs; mark the down cell as such.
	if down.x >= 0 and down.y >= 0:
		grid[down.y][down.x] = C.T_STAIRS_DOWN
	return {"spawn": up, "stairs": down}

func _find_walkable_cell() -> Vector2i:
	var h: int = grid.size()
	var w: int = grid[0].size() if h > 0 else 0
	for y in h:
		for x in w:
			if grid[y][x] == C.T_FLOOR:
				return Vector2i(x, y)
	return Vector2i(1, 1)

func _find_walkable_cell_far_from(other: Vector2i) -> Vector2i:
	var h: int = grid.size()
	var w: int = grid[0].size() if h > 0 else 0
	var best := Vector2i(1, 1)
	var best_d: int = -1
	for y in h:
		for x in w:
			if grid[y][x] != C.T_FLOOR:
				continue
			var d: int = absi(x - other.x) + absi(y - other.y)
			if d > best_d:
				best_d = d
				best = Vector2i(x, y)
	return best

func _stamp_oriented_vaults(theme: String, floor_num: int, results: Dictionary) -> void:
	var placed_names: Dictionary = {}
	for name in results.get("placed_vaults", []):
		placed_names[name] = true
	var attempts: int = 1 if floor_num >= 3 else 0
	if floor_num >= 7 and rng.randf() < 0.4:
		attempts = 2
	for i in attempts:
		var candidates: Array = VaultLibrary.oriented_candidates_multi(_themes_or(theme), floor_num, placed_names)
		if candidates.is_empty():
			return
		var picked: Dictionary = VaultLibrary.pick_weighted(candidates, rng)
		if picked.is_empty():
			continue
		if not VaultLibrary.passes_chance(picked, floor_num, rng):
			continue
		var ok: bool = VaultStamper.try_stamp_oriented(grid, rooms, picked, rng, results)
		if ok:
			var name: String = String(picked.get("name", ""))
			results["placed_vaults"].append(name)
			placed_names[name] = true

func _count_floor_cells(w: int, h: int) -> int:
	var n: int = 0
	for y in h:
		for x in w:
			if grid[y][x] == C.T_FLOOR or grid[y][x] == C.T_STAIRS_DOWN or grid[y][x] == C.T_DOOR:
				n += 1
	return n

func _spawn_in_largest_region(w: int, h: int) -> Vector2i:
	# Find the largest connected floor region, then return a cell near its
	# centroid. Used by encompass-vault path so we always spawn somewhere
	# reachable, even if the vault's < glyph landed in a sub-region.
	var visited: Dictionary = {}
	var best_region: Array[Vector2i] = []
	for y in h:
		for x in w:
			var cell := Vector2i(x, y)
			if visited.has(cell):
				continue
			var v: int = grid[y][x]
			if v != C.T_FLOOR and v != C.T_STAIRS_DOWN and v != C.T_DOOR:
				continue
			var region: Array[Vector2i] = []
			var queue: Array[Vector2i] = [cell]
			visited[cell] = true
			while not queue.is_empty():
				var c: Vector2i = queue.pop_back()
				region.append(c)
				for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var n: Vector2i = c + d
					if n.x < 0 or n.y < 0 or n.x >= w or n.y >= h:
						continue
					if visited.has(n):
						continue
					var nv: int = grid[n.y][n.x]
					if nv != C.T_FLOOR and nv != C.T_STAIRS_DOWN and nv != C.T_DOOR:
						continue
					visited[n] = true
					queue.append(n)
			if region.size() > best_region.size():
				best_region = region
	if best_region.is_empty():
		return Vector2i(-1, -1)
	# Centroid (average) — gives us something near the middle of the open area.
	var sx: int = 0
	var sy: int = 0
	for c in best_region:
		sx += c.x
		sy += c.y
	var cx: int = sx / best_region.size()
	var cy: int = sy / best_region.size()
	# Snap centroid to the nearest actual region cell.
	var best := best_region[0]
	var best_d: int = 999999
	for c in best_region:
		var dx: int = c.x - cx
		var dy: int = c.y - cy
		var d: int = dx * dx + dy * dy
		if d < best_d:
			best_d = d
			best = c
	return best

func _connect_orphans_to_main(spawn: Vector2i) -> void:
	var h: int = grid.size()
	var w: int = grid[0].size() if h > 0 else 0
	# BFS from spawn over walkable cells.
	var main_region: Dictionary = {}
	if spawn.x < 0 or spawn.y < 0 or spawn.x >= w or spawn.y >= h:
		return
	var queue: Array[Vector2i] = [spawn]
	main_region[spawn] = true
	var head: int = 0
	while head < queue.size():
		var c: Vector2i = queue[head]
		head += 1
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			if n.x < 0 or n.y < 0 or n.x >= w or n.y >= h:
				continue
			if main_region.has(n):
				continue
			var cv: int = grid[n.y][n.x]
			if cv != C.T_FLOOR and cv != C.T_STAIRS_DOWN and cv != C.T_DOOR:
				continue
			main_region[n] = true
			queue.append(n)
	# Find all orphan floor cells; group by region.
	var visited: Dictionary = main_region.duplicate()
	var orphan_groups: Array = []
	for y in h:
		for x in w:
			var cell := Vector2i(x, y)
			if visited.has(cell):
				continue
			var v: int = grid[y][x]
			if v != C.T_FLOOR and v != C.T_STAIRS_DOWN and v != C.T_DOOR:
				continue
			# New orphan region — flood it.
			var group: Array[Vector2i] = []
			var sub_queue: Array[Vector2i] = [cell]
			visited[cell] = true
			var sub_head: int = 0
			while sub_head < sub_queue.size():
				var oc: Vector2i = sub_queue[sub_head]
				sub_head += 1
				group.append(oc)
				for d2 in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var on: Vector2i = oc + d2
					if on.x < 0 or on.y < 0 or on.x >= w or on.y >= h:
						continue
					if visited.has(on):
						continue
					var ov: int = grid[on.y][on.x]
					if ov != C.T_FLOOR and ov != C.T_STAIRS_DOWN and ov != C.T_DOOR:
						continue
					visited[on] = true
					sub_queue.append(on)
			orphan_groups.append(group)
	# For each orphan group, carve a corridor to the nearest main-region cell.
	for group in orphan_groups:
		_carve_corridor_to_main(group, main_region, w, h)

func _carve_corridor_to_main(orphan: Array, main_region: Dictionary, w: int, h: int) -> void:
	# Pick the orphan cell closest to any main-region cell (Manhattan).
	var best_orphan := Vector2i(-1, -1)
	var best_main := Vector2i(-1, -1)
	var best_d: int = 999999
	for oc in orphan:
		# Spiral outward looking for nearest main-region cell. Capped by
		# the map bounds to keep runtime reasonable.
		for radius in range(1, maxi(w, h)):
			var found: bool = false
			for dy in range(-radius, radius + 1):
				for dx in range(-radius, radius + 1):
					if absi(dx) != radius and absi(dy) != radius:
						continue
					var probe := Vector2i(oc.x + dx, oc.y + dy)
					if not main_region.has(probe):
						continue
					var d: int = absi(dx) + absi(dy)
					if d < best_d:
						best_d = d
						best_orphan = oc
						best_main = probe
					found = true
			if found:
				break
		if best_d <= 2:
			break
	if best_orphan.x < 0 or best_main.x < 0:
		return
	# Carve a Manhattan corridor from best_orphan toward best_main, ignoring
	# walls and doors (replace with floor). This is brute-force connectivity.
	var cur: Vector2i = best_orphan
	var safety: int = 200
	while cur != best_main and safety > 0:
		safety -= 1
		if grid[cur.y][cur.x] == C.T_WALL:
			grid[cur.y][cur.x] = C.T_FLOOR
		var dx: int = best_main.x - cur.x
		var dy: int = best_main.y - cur.y
		if absi(dx) >= absi(dy) and dx != 0:
			cur.x += signi(dx)
		elif dy != 0:
			cur.y += signi(dy)
		else:
			cur.x += signi(dx)
	if grid[best_main.y][best_main.x] == C.T_WALL:
		grid[best_main.y][best_main.x] = C.T_FLOOR

func _largest_floor_region_size(w: int, h: int) -> int:
	var visited: Dictionary = {}
	var largest: int = 0
	for y in h:
		for x in w:
			var cell := Vector2i(x, y)
			if visited.has(cell):
				continue
			var v: int = grid[y][x]
			if v != C.T_FLOOR and v != C.T_STAIRS_DOWN and v != C.T_DOOR:
				continue
			var size: int = 0
			var stack: Array[Vector2i] = [cell]
			while not stack.is_empty():
				var c: Vector2i = stack.pop_back()
				if visited.has(c):
					continue
				visited[c] = true
				if c.y < 0 or c.x < 0 or c.y >= h or c.x >= w:
					continue
				var cv: int = grid[c.y][c.x]
				if cv != C.T_FLOOR and cv != C.T_STAIRS_DOWN and cv != C.T_DOOR:
					continue
				size += 1
				stack.append(Vector2i(c.x + 1, c.y))
				stack.append(Vector2i(c.x - 1, c.y))
				stack.append(Vector2i(c.x, c.y + 1))
				stack.append(Vector2i(c.x, c.y - 1))
			largest = maxi(largest, size)
	return largest

func _build_distance_map(from: Vector2i, w: int, h: int) -> Array:
	# BFS from `from` cell over all walkable cells. Returns 2D array of distances
	# (-1 for unreachable / wall).
	var dist: Array = []
	for y in h:
		var row := []
		row.resize(w)
		for x in w:
			row[x] = -1
		dist.append(row)
	if from.x < 0 or from.y < 0 or from.x >= w or from.y >= h:
		return dist
	dist[from.y][from.x] = 0
	var queue: Array[Vector2i] = [from]
	var head: int = 0
	while head < queue.size():
		var c: Vector2i = queue[head]
		head += 1
		var d: int = dist[c.y][c.x]
		for nd in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + nd
			if n.x < 0 or n.y < 0 or n.x >= w or n.y >= h:
				continue
			if dist[n.y][n.x] != -1:
				continue
			var cell: int = grid[n.y][n.x]
			if cell != C.T_FLOOR and cell != C.T_STAIRS_DOWN and cell != C.T_DOOR:
				continue
			dist[n.y][n.x] = d + 1
			queue.append(n)
	return dist

func _detect_open_regions(w: int, h: int, min_w: int, min_h: int, max_count: int) -> Array[Rect2i]:
	# Greedy: scan grid, find each cell that anchors a min_w x min_h floor block,
	# claim it as a Rect2i, expand outward as long as still mostly floor, mark
	# claimed cells. Simple, not optimal — sufficient for vault placement and
	# AI room-targeting fallback.
	var claimed: Dictionary = {}
	var out: Array[Rect2i] = []
	for y in range(1, h - min_h):
		for x in range(1, w - min_w):
			if claimed.has(Vector2i(x, y)):
				continue
			if not _all_floor(x, y, min_w, min_h):
				continue
			var rw: int = min_w
			var rh: int = min_h
			while x + rw + 1 < w and _all_floor(x, y, rw + 1, rh):
				rw += 1
			while y + rh + 1 < h and _all_floor(x, y, rw, rh + 1):
				rh += 1
			out.append(Rect2i(x, y, rw, rh))
			for cy in range(y, y + rh):
				for cx in range(x, x + rw):
					claimed[Vector2i(cx, cy)] = true
			if out.size() >= max_count:
				return out
	return out

func _all_floor(x: int, y: int, w: int, h: int) -> bool:
	for cy in range(y, y + h):
		for cx in range(x, x + w):
			if cy >= grid.size() or cx >= grid[0].size():
				return false
			if grid[cy][cx] != C.T_FLOOR and grid[cy][cx] != C.T_STAIRS_DOWN:
				return false
	return true

func _stamp_float_vaults(theme: String, floor_num: int, results: Dictionary) -> void:
	var placed_names: Dictionary = {}
	for name in results.get("placed_vaults", []):
		placed_names[name] = true
	# Target N successful stamps; up to MAX_TRIES candidate picks per slot.
	# The previous logic picked ONE random vault per slot; if that vault
	# was too large for any detected room, we got zero stamps. Retrying
	# with smaller candidates fixes the "vaults rare" problem.
	var target: int = 1
	if floor_num >= 4 and rng.randf() < 0.5:
		target = 2
	if floor_num == 10:
		target = 1
	if rng.randf() < 0.15 and floor_num < 10:
		target = 0
	# Debug-jump always attempts the forced vault.
	if DebugJump.active and DebugJump.vault_name != "":
		target = max(target, 1)
	# Find the largest detected room — caps the vault size we'll try.
	# Caves layouts produce small organic pockets; without this cap we'd
	# pick a 30x20 vault on every attempt and silently fail.
	var biggest_w: int = 0
	var biggest_h: int = 0
	for r in rooms:
		var rect: Rect2i = r as Rect2i
		biggest_w = max(biggest_w, rect.size.x)
		biggest_h = max(biggest_h, rect.size.y)
	const MAX_TRIES_PER_SLOT := 16
	var stamped: int = 0
	while stamped < target:
		var slot_succeeded: bool = false
		for try_n in MAX_TRIES_PER_SLOT:
			var candidates: Array = VaultLibrary.float_candidates_multi(_themes_or(theme), floor_num, placed_names)
			if candidates.is_empty():
				return
			# Filter to candidates that COULD fit in the largest available
			# room. Avoids wasting picks on huge vaults in caves layouts.
			if biggest_w > 0 and biggest_h > 0:
				var fitting: Array = []
				for c in candidates:
					var s: Array = c.get("size", [0, 0])
					if int(s[0]) + 2 <= biggest_w and int(s[1]) + 2 <= biggest_h:
						fitting.append(c)
				if not fitting.is_empty():
					candidates = fitting
			var picked: Dictionary = VaultLibrary.pick_weighted(candidates, rng)
			if picked.is_empty():
				continue
			if not VaultLibrary.passes_chance(picked, floor_num, rng):
				continue
			var ok: bool = VaultStamper.try_stamp_oriented(grid, rooms, picked, rng, results)
			if ok:
				var name: String = String(picked.get("name", ""))
				results["placed_vaults"].append(name)
				placed_names[name] = true
				slot_succeeded = true
				break
			# This vault didn't fit; mark it placed so we don't retry it.
			placed_names[String(picked.get("name", "_unnamed"))] = true
		if not slot_succeeded:
			break
		stamped += 1

var _stairs_down_pos: Vector2i

func _split(leaf: Leaf, depth: int) -> void:
	if depth <= 0:
		return
	var r := leaf.rect
	if r.size.x < MIN_LEAF * 2 and r.size.y < MIN_LEAF * 2:
		return

	var split_h: bool
	if r.size.x > r.size.y * 1.25:
		split_h = false
	elif r.size.y > r.size.x * 1.25:
		split_h = true
	else:
		split_h = rng.randf() < 0.5

	if split_h:
		if r.size.y < MIN_LEAF * 2:
			return
		var cut := rng.randi_range(MIN_LEAF, r.size.y - MIN_LEAF)
		leaf.left = Leaf.new(Rect2i(r.position, Vector2i(r.size.x, cut)))
		leaf.right = Leaf.new(Rect2i(Vector2i(r.position.x, r.position.y + cut), Vector2i(r.size.x, r.size.y - cut)))
	else:
		if r.size.x < MIN_LEAF * 2:
			return
		var cut := rng.randi_range(MIN_LEAF, r.size.x - MIN_LEAF)
		leaf.left = Leaf.new(Rect2i(r.position, Vector2i(cut, r.size.y)))
		leaf.right = Leaf.new(Rect2i(Vector2i(r.position.x + cut, r.position.y), Vector2i(r.size.x - cut, r.size.y)))

	_split(leaf.left, depth - 1)
	_split(leaf.right, depth - 1)

func _carve_rooms(leaf: Leaf) -> void:
	if leaf.is_leaf():
		var r := leaf.rect
		var pad := MAX_ROOM_PADDING
		var rw := rng.randi_range(MIN_ROOM, max(MIN_ROOM, r.size.x - pad))
		var rh := rng.randi_range(MIN_ROOM, max(MIN_ROOM, r.size.y - pad))
		var rx := r.position.x + rng.randi_range(0, max(0, r.size.x - rw))
		var ry := r.position.y + rng.randi_range(0, max(0, r.size.y - rh))
		var room := Rect2i(rx, ry, rw, rh)
		leaf.room = room
		rooms.append(room)
		_fill_rect(room, C.T_FLOOR)
		return
	if leaf.left:
		_carve_rooms(leaf.left)
	if leaf.right:
		_carve_rooms(leaf.right)

func _carve_corridors(leaf: Leaf) -> void:
	if leaf.is_leaf():
		return
	if leaf.left and leaf.right:
		var a := _any_room_center(leaf.left)
		var b := _any_room_center(leaf.right)
		_carve_l_corridor(a, b)
	if leaf.left:
		_carve_corridors(leaf.left)
	if leaf.right:
		_carve_corridors(leaf.right)

func _any_room_center(leaf: Leaf) -> Vector2i:
	if leaf.is_leaf():
		return _room_center(leaf.room)
	if leaf.left:
		return _any_room_center(leaf.left)
	return _any_room_center(leaf.right)

func _room_center(r: Rect2i) -> Vector2i:
	return Vector2i(r.position.x + int(r.size.x / 2.0), r.position.y + int(r.size.y / 2.0))

func _carve_l_corridor(a: Vector2i, b: Vector2i) -> void:
	if rng.randf() < 0.5:
		_carve_h(a.x, b.x, a.y)
		_carve_v(a.y, b.y, b.x)
	else:
		_carve_v(a.y, b.y, a.x)
		_carve_h(a.x, b.x, b.y)

func _carve_h(x1: int, x2: int, y: int) -> void:
	var lo := mini(x1, x2)
	var hi := maxi(x1, x2)
	for x in range(lo, hi + 1):
		_set_cell(x, y, C.T_FLOOR)

func _carve_v(y1: int, y2: int, x: int) -> void:
	var lo := mini(y1, y2)
	var hi := maxi(y1, y2)
	for y in range(lo, hi + 1):
		_set_cell(x, y, C.T_FLOOR)

func _fill_rect(r: Rect2i, val: int) -> void:
	for y in range(r.position.y, r.position.y + r.size.y):
		for x in range(r.position.x, r.position.x + r.size.x):
			_set_cell(x, y, val)

func _set_cell(x: int, y: int, val: int) -> void:
	if y >= 0 and y < grid.size() and x >= 0 and x < grid[0].size():
		grid[y][x] = val

func _place_stairs() -> void:
	if rooms.size() < 2:
		_stairs_down_pos = _room_center(rooms[0])
		return
	var last := rooms[rooms.size() - 1]
	_stairs_down_pos = _room_center(last)
	_set_cell(_stairs_down_pos.x, _stairs_down_pos.y, C.T_STAIRS_DOWN)
