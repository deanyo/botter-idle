class_name VaultStamper
extends RefCounted

const C := preload("res://scripts/constants.gd")

# Routes a vault to the right placement strategy based on its ORIENT field.
# Returns true on successful stamp. Encompass vaults stamp the whole grid;
# float vaults stamp inside detected open regions; n/s/e/w/centre stamp
# against the matching edge with safety checks.
static func try_stamp_oriented(grid: Array, rooms: Array, vault: Dictionary, rng: RandomNumberGenerator, results: Dictionary) -> bool:
	var orient: String = String(vault.get("orient", "float")).to_lower()
	match orient:
		"encompass":
			return _stamp_encompass(grid, vault, results)
		"north", "south", "east", "west", "centre", "center":
			return _stamp_oriented_edge(grid, vault, orient, rng, results)
		_:
			return try_stamp(grid, rooms, vault, rng, results)

static func _stamp_encompass(grid: Array, vault: Dictionary, results: Dictionary) -> bool:
	var grid_arr: Array = vault.get("grid", [])
	if grid_arr.is_empty():
		return false
	var gh: int = grid.size()
	var gw: int = grid[0].size() if gh > 0 else 0
	# Encompass vaults must match the level dimensions exactly. We center
	# smaller encompass-tagged vaults if they're a tile off due to map sizing.
	var size_arr: Array = vault.get("size", [0, 0])
	var vw: int = int(size_arr[0])
	var vh: int = int(size_arr[1])
	if vw <= 0 or vh <= 0 or vw > gw or vh > gh:
		return false
	var ox: int = (gw - vw) / 2
	var oy: int = (gh - vh) / 2
	_apply(grid, vault, ox, oy, results)
	results["placed_in_room"] = -1
	results["placement_orient"] = "encompass"
	return true

static func _stamp_oriented_edge(grid: Array, vault: Dictionary, orient: String, rng: RandomNumberGenerator, results: Dictionary) -> bool:
	var size_arr: Array = vault.get("size", [0, 0])
	var vw: int = int(size_arr[0])
	var vh: int = int(size_arr[1])
	if vw <= 0 or vh <= 0:
		return false
	var gh: int = grid.size()
	var gw: int = grid[0].size() if gh > 0 else 0
	if vw > gw - 4 or vh > gh - 4:
		return false
	# Edge-anchored origin for the orient.
	var ox: int = 2
	var oy: int = 2
	match orient:
		"north":
			ox = rng.randi_range(2, gw - vw - 2)
			oy = 2
		"south":
			ox = rng.randi_range(2, gw - vw - 2)
			oy = gh - vh - 2
		"east":
			ox = gw - vw - 2
			oy = rng.randi_range(2, gh - vh - 2)
		"west":
			ox = 2
			oy = rng.randi_range(2, gh - vh - 2)
		"centre", "center":
			ox = (gw - vw) / 2
			oy = (gh - vh) / 2
	if not _placement_safe(grid, vault, ox, oy):
		return false
	_apply(grid, vault, ox, oy, results)
	results["placement_orient"] = orient
	return true

static func try_stamp(grid: Array, rooms: Array, vault: Dictionary, rng: RandomNumberGenerator, results: Dictionary) -> bool:
	if vault.is_empty():
		return false
	var size_arr: Array = vault.get("size", [0, 0])
	var vw: int = int(size_arr[0])
	var vh: int = int(size_arr[1])
	if vw <= 0 or vh <= 0:
		return false
	var grid_arr: Array = vault.get("grid", [])
	if grid_arr.size() != vh:
		return false

	var room_indices: Array[int] = []
	var last_idx: int = rooms.size() - 1
	for i in rooms.size():
		if i == 0 or i == last_idx:
			continue
		room_indices.append(i)
	room_indices.shuffle()

	for room_idx in room_indices:
		var r: Rect2i = rooms[room_idx]
		if r.size.x < vw + 2 or r.size.y < vh + 2:
			continue
		var ox: int = r.position.x + 1 + rng.randi_range(0, r.size.x - vw - 2)
		var oy: int = r.position.y + 1 + rng.randi_range(0, r.size.y - vh - 2)
		if not _placement_safe(grid, vault, ox, oy):
			continue
		_apply(grid, vault, ox, oy, results)
		results["placed_in_room"] = room_idx
		results["placement_orient"] = "float"
		return true
	return false

static func _placement_safe(grid: Array, vault: Dictionary, ox: int, oy: int) -> bool:
	var grid_arr: Array = vault.get("grid", [])
	var gh: int = grid.size()
	var gw: int = grid[0].size() if gh > 0 else 0
	for y in grid_arr.size():
		var row: String = String(grid_arr[y])
		for x in row.length():
			var ch: String = row.substr(x, 1)
			if ch != "x" and ch != "X":
				continue
			var cy: int = oy + y
			var cx: int = ox + x
			if cy < 0 or cx < 0 or cy >= gh or cx >= gw:
				continue
			if grid[cy][cx] == C.T_FLOOR:
				return false
	return true

static func _apply(grid: Array, vault: Dictionary, ox: int, oy: int, results: Dictionary) -> void:
	var grid_arr: Array = vault.get("grid", [])
	var fountains: Array = results.get("fountains", [])
	var statues: Array = results.get("statues", [])
	var loot_marks: Array = results.get("loot_marks", [])
	var chest_marks: Array = results.get("chest_marks", [])
	var altar_marks: Array = results.get("altar_marks", [])
	var stair_marks: Array = results.get("stair_marks", [])
	var spawn_overrides: Dictionary = results.get("spawn_overrides", {})
	var protected: Dictionary = results.get("protected_cells", {})
	var spawns_def: Dictionary = vault.get("spawns", {})
	var kfeat: Dictionary = vault.get("kfeat", {})
	var kmons: Dictionary = vault.get("kmons", {})
	var kitem: Dictionary = vault.get("kitem", {})
	var tags: Array = vault.get("tags", [])

	for y in grid_arr.size():
		var row: String = String(grid_arr[y])
		for x in row.length():
			var ch: String = row.substr(x, 1)
			var cell := Vector2i(ox + x, oy + y)
			if ch == " ":
				continue
			# KFEAT override always wins for terrain glyphs.
			if kfeat.has(ch):
				_apply_kfeat_full(grid, cell, String(kfeat[ch]), results)
				protected[cell] = true
				continue
			match ch:
				"x", "X":
					_set_cell(grid, cell, C.T_WALL)
				".", "+":
					_set_cell(grid, cell, C.T_FLOOR)
				"T":
					_set_cell(grid, cell, C.T_FLOOR)
					fountains.append(cell)
				"S":
					_set_cell(grid, cell, C.T_FLOOR)
					statues.append(cell)
				"*":
					_set_cell(grid, cell, C.T_FLOOR)
					if kitem.has(ch):
						loot_marks.append({"cell": cell, "kitem": kitem[ch]})
					else:
						loot_marks.append(cell)
				"C":
					_set_cell(grid, cell, C.T_FLOOR)
					chest_marks.append(cell)
				"A":
					_set_cell(grid, cell, C.T_FLOOR)
					altar_marks.append(cell)
				">":
					_set_cell(grid, cell, C.T_STAIRS_DOWN)
					stair_marks.append({"cell": cell, "kind": "down"})
				"<":
					_set_cell(grid, cell, C.T_FLOOR)
					stair_marks.append({"cell": cell, "kind": "up"})
				"m":
					_set_cell(grid, cell, C.T_FLOOR)
					if kmons.has(ch):
						spawn_overrides[cell] = {"enemy_pool": [String(kmons[ch])]}
				_:
					_set_cell(grid, cell, C.T_FLOOR)
					if ch >= "0" and ch <= "9":
						if kmons.has(ch):
							spawn_overrides[cell] = {"enemy_pool": [String(kmons[ch])]}
						elif spawns_def.has(ch):
							spawn_overrides[cell] = spawns_def[ch]
			protected[cell] = true

	results["fountains"] = fountains
	results["statues"] = statues
	results["loot_marks"] = loot_marks
	results["chest_marks"] = chest_marks
	results["altar_marks"] = altar_marks
	results["stair_marks"] = stair_marks
	results["spawn_overrides"] = spawn_overrides
	results["protected_cells"] = protected
	if tags.has("no_monster_gen") or tags.has("no_item_gen"):
		var bbox := Rect2i(ox, oy, vault.get("size", [0, 0])[0], vault.get("size", [0, 0])[1])
		var no_spawn_zones: Array = results.get("no_spawn_zones", [])
		no_spawn_zones.append({"rect": bbox, "monsters": tags.has("no_monster_gen"), "items": tags.has("no_item_gen")})
		results["no_spawn_zones"] = no_spawn_zones

static func _apply_kfeat_full(grid: Array, cell: Vector2i, feat: String, results: Dictionary) -> void:
	var f: String = feat.to_lower()
	if f == "wall":
		_set_cell(grid, cell, C.T_WALL)
		return
	_set_cell(grid, cell, C.T_FLOOR)
	if f.begins_with("altar_"):
		var altar_marks: Array = results.get("altar_marks", [])
		altar_marks.append({"cell": cell, "god": f.substr(6)})
		results["altar_marks"] = altar_marks
	elif f.begins_with("fountain_"):
		var fountains: Array = results.get("fountains", [])
		fountains.append({"cell": cell, "kind": f.substr(9)})
		results["fountains"] = fountains
	elif f == "stairs_down":
		_set_cell(grid, cell, C.T_STAIRS_DOWN)

static func _set_cell(grid: Array, cell: Vector2i, val: int) -> void:
	if cell.y >= 0 and cell.y < grid.size() and cell.x >= 0 and cell.x < grid[0].size():
		grid[cell.y][cell.x] = val
