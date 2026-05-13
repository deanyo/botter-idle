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

	# Try every room (used to skip first+last; that was discarding valid
	# placements on caves layouts where room order is arbitrary).
	var room_indices: Array[int] = []
	for i in rooms.size():
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
	# Debug-jump force path: when we explicitly request a specific vault and
	# rooms are unavailable (caves layout), try one open-region scan fallback
	# so the screenshot skill can still verify the vault. Outside debug-jump,
	# we skip the fallback to avoid littering caves layouts with rectangular
	# patches.
	if DebugJump.active and DebugJump.vault_name != "" \
			and String(vault.get("name", "")) == DebugJump.vault_name:
		var gh: int = grid.size()
		var gw: int = grid[0].size() if gh > 0 else 0
		for attempt in 60:
			var ox2: int = rng.randi_range(2, gw - vw - 2)
			var oy2: int = rng.randi_range(2, gh - vh - 2)
			if ox2 < 0 or oy2 < 0:
				continue
			if _placement_safe(grid, vault, ox2, oy2):
				_apply(grid, vault, ox2, oy2, results)
				results["placement_orient"] = "float_debug_fallback"
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

const CHEST_MAX_PER_VAULT := 8
const LOOT_MAX_PER_VAULT := 12

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
	var decor_overlays: Dictionary = vault.get("decor_overlays", {})
	var decor_marks: Array = results.get("decor_marks", [])
	var tags: Array = vault.get("tags", [])

	# Collect chest/loot glyph cells separately so we can cap the spawn count
	# at vault-application time. Some ported DCSS vaults stamp huge "C" or "*"
	# blocks (treasure-vault tile-art) where each glyph nominally represents a
	# *chance* of treasure, not literal one-chest-per-cell. Without a cap, a
	# 28×22 chest block spawns 613 chest interactables — instant lag.
	var chest_candidates: Array[Vector2i] = []
	var loot_candidates: Array = []
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
			# Decor overlay glyphs are purely cosmetic — set the cell to floor
			# and queue the texture name for the renderer to stamp on top.
			# Used for multi-tile sigil compositions and similar pure-decor
			# vaults. Cell is protected so other passes (sigils, edge overlays)
			# don't double-stamp.
			if decor_overlays.has(ch):
				_set_cell(grid, cell, C.T_FLOOR)
				decor_marks.append({"cell": cell, "texture": String(decor_overlays[ch])})
				protected[cell] = true
				continue
			match ch:
				"x", "X":
					_set_cell(grid, cell, C.T_WALL)
				".", "+":
					_set_cell(grid, cell, C.T_FLOOR)
				"L", "l":
					_set_cell(grid, cell, C.T_LAVA)
				"W", "w":
					_set_cell(grid, cell, C.T_WATER)
				"I":
					_set_cell(grid, cell, C.T_ICE)
				"t":
					_set_cell(grid, cell, C.T_WALL)
					decor_marks.append({"cell": cell, "texture": "tree", "is_wall": true})
				"B":
					_set_cell(grid, cell, C.T_FLOOR)
					decor_marks.append({"cell": cell, "texture": "bones", "is_wall": false})
				"M":
					_set_cell(grid, cell, C.T_WALL)
					decor_marks.append({"cell": cell, "texture": "mushroom", "is_wall": true})
				"T":
					_set_cell(grid, cell, C.T_FLOOR)
					fountains.append(cell)
				"S":
					_set_cell(grid, cell, C.T_FLOOR)
					statues.append(cell)
				"*":
					_set_cell(grid, cell, C.T_FLOOR)
					if kitem.has(ch):
						loot_candidates.append({"cell": cell, "kitem": kitem[ch]})
					else:
						loot_candidates.append(cell)
				"C":
					_set_cell(grid, cell, C.T_FLOOR)
					chest_candidates.append(cell)
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

	# Cap chest / loot counts. Vaults that stamp wide "treasure block" rectangles
	# overflow gameplay and tank perf — pick a fair sample instead of one per
	# cell. Sampling stride keeps clusters spread out across the block.
	if chest_candidates.size() > CHEST_MAX_PER_VAULT:
		var stride: int = max(1, chest_candidates.size() / CHEST_MAX_PER_VAULT)
		for i in range(0, chest_candidates.size(), stride):
			chest_marks.append(chest_candidates[i])
			if chest_marks.size() >= CHEST_MAX_PER_VAULT:
				break
	else:
		for c in chest_candidates:
			chest_marks.append(c)
	if loot_candidates.size() > LOOT_MAX_PER_VAULT:
		var lstride: int = max(1, loot_candidates.size() / LOOT_MAX_PER_VAULT)
		for i in range(0, loot_candidates.size(), lstride):
			loot_marks.append(loot_candidates[i])
			if loot_marks.size() >= LOOT_MAX_PER_VAULT:
				break
	else:
		for l in loot_candidates:
			loot_marks.append(l)

	results["fountains"] = fountains
	results["statues"] = statues
	results["loot_marks"] = loot_marks
	results["chest_marks"] = chest_marks
	results["altar_marks"] = altar_marks
	results["stair_marks"] = stair_marks
	results["spawn_overrides"] = spawn_overrides
	results["protected_cells"] = protected
	results["decor_marks"] = decor_marks
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
