class_name MapRenderer
extends Node2D

const C := preload("res://scripts/constants.gd")

const STAIRS_DOWN_TEX := preload("res://assets/tiles/gateways/stairs_down.png")
const DOOR_PLAIN := preload("res://assets/tiles/features/closed_door.png")
const DOOR_RUNED := preload("res://assets/tiles/features/runed_door.png")
const DOOR_SEALED := preload("res://assets/tiles/features/sealed_door.png")
const TERRAIN_LAVA := preload("res://assets/tiles/terrain/lava.png")
const TERRAIN_WATER := preload("res://assets/tiles/terrain/water.png")
const TERRAIN_ICE := preload("res://assets/tiles/terrain/ice.png")
# Biome → door texture preference. Falls back to DOOR_PLAIN for unlisted biomes.
const DOOR_BY_BIOME := {
	"crypt":     "runed",
	"tomb":      "runed",
	"vaults":    "sealed",
	"depths":    "sealed",
	"elf":       "runed",
	"zot":       "runed",
	"pandemonium": "runed",
	"abyss":     "runed",
}

const FLOOR_PATCH_COUNT := 14
const WALL_PATCH_COUNT := 10
const ACCENT_PROB := 0.12
const WALL_ACCENT_PROB := 0.06

var grid: Array
var rooms: Array
var cell_sprites: Dictionary = {}
var wall_cells: Dictionary = {}
var cell_target_alpha: Dictionary = {}
var cell_current_alpha: Dictionary = {}
# Sigil placements — each entry is {cell: Vector2i, texture_path: String}.
# Populated by _stamp_room_sigils, exposed in the screenshot JSON sidecar.
var sigil_marks: Array = []
# Vault decor overlays applied via decor_overlays JSON field. Each entry is
# {cell: Vector2i, texture_path: String}.
var decor_marks: Array = []
# 0.4s full fade. Needs to be > the bot's per-cell move time so consecutive
# cell-flip reveal waves overlap into one continuous-looking emanation. With
# < cell-time, tiles complete fading then "hold" until the next cell crossing
# triggers another wave — that's the visible tick.
const FADE_RATE := 2.5

func render(g: Array, rs: Array, biome: Dictionary, rng: RandomNumberGenerator, vault_results: Dictionary = {}) -> void:
	for child in get_children():
		child.queue_free()
	cell_sprites.clear()
	wall_cells.clear()
	cell_target_alpha.clear()
	cell_current_alpha.clear()
	sigil_marks.clear()
	decor_marks.clear()
	grid = g
	rooms = rs
	set_process(true)
	var protected_cells: Dictionary = vault_results.get("protected_cells", {})

	var floor_primary: Array = BiomeData.load_floor_primary(biome)
	var floor_secondary: Array = BiomeData.load_floor_secondary(biome)
	var floor_accent: Array = BiomeData.load_floor_accent(biome)
	var wall_primary: Array = BiomeData.load_wall_primary(biome)
	var wall_accent: Array = BiomeData.load_wall_accent(biome)
	var wall_alternates: Array = BiomeData.load_wall_alternates(biome)
	var edge_overlay: Dictionary = BiomeData.load_edge_overlay(biome)
	if floor_primary.is_empty() or wall_primary.is_empty():
		push_error("Biome %s missing primary tiles" % biome.get("id", "?"))
		return
	# Dual-floor noise: when biome has a secondary pool, sample one octave of
	# Perlin per cell. Cells where noise > threshold use secondary, others
	# use primary. Smooth zonal transition without per-cell confetti.
	var floor_noise: FastNoiseLite = null
	if not floor_secondary.is_empty():
		floor_noise = FastNoiseLite.new()
		floor_noise.noise_type = FastNoiseLite.TYPE_PERLIN
		floor_noise.frequency = 0.045
		floor_noise.seed = int(rng.seed)
	var overlay_label: String = "(none)"
	if not edge_overlay.is_empty():
		overlay_label = "n=%d cardinals" % int(edge_overlay.size() - 1)
	GrindLog.log_line("[render] biome=%s floor_tiles=%d wall_tiles=%d overlay=%s" % [
		String(biome.get("id","?")), floor_primary.size(), wall_primary.size(), overlay_label,
	])

	var h := grid.size()
	var w: int = grid[0].size() if h > 0 else 0

	var floor_patches: Array = _generate_floor_patches(w, h, floor_primary.size(), rng)
	var wall_patches: Array = _generate_wall_patches(w, h, wall_primary, wall_alternates, rng)

	for y in h:
		for x in w:
			var cell: int = grid[y][x]
			var tex: Texture2D = null
			if cell == C.T_WALL:
				if not _wall_borders_floor(x, y, w, h):
					continue
				tex = _pick_wall_tile(x, y, wall_patches, wall_primary, wall_accent, rng)
			elif cell == C.T_FLOOR or cell == C.T_STAIRS_DOWN or cell == C.T_DOOR:
				# Dual-floor mix: pick from secondary pool when noise crosses
				# the threshold; otherwise primary. Threshold 0.18 keeps primary
				# dominant but gives meaningful patches of secondary.
				var pool: Array = floor_primary
				if floor_noise != null and floor_noise.get_noise_2d(float(x), float(y)) > 0.18:
					pool = floor_secondary
				tex = _pick_floor_tile(x, y, floor_patches, pool, floor_accent, rng)
			elif cell == C.T_LAVA:
				tex = TERRAIN_LAVA
			elif cell == C.T_WATER:
				tex = TERRAIN_WATER
			elif cell == C.T_ICE:
				tex = TERRAIN_ICE
			if tex:
				_place(tex, x, y)
				if cell == C.T_WALL:
					wall_cells[Vector2i(x, y)] = true
			if cell == C.T_WALL:
				_place_occluder(x, y)
			if cell == C.T_STAIRS_DOWN:
				_place(STAIRS_DOWN_TEX, x, y)
			if cell == C.T_DOOR:
				_place(_door_texture_for(biome), x, y)
			# Edge overlay: stamped on floor cells that border walls. Picked
			# directionally so e.g. grass tufts spill in from the wall side.
			if not edge_overlay.is_empty() and (cell == C.T_FLOOR or cell == C.T_DOOR or cell == C.T_STAIRS_DOWN):
				_apply_edge_overlay(x, y, w, h, edge_overlay, rng)

	# Vault decor overlays: per-cell texture stamps from vault decor_overlays
	# fields (e.g. multi-tile sigil compositions). These stamp on top of floor
	# cells without changing terrain.
	_stamp_decor_marks(vault_results, rng)

	# Room sigils: 1-2 random rune marks stamped per BSP room, biome-specific.
	# Skipped for caves layouts (rooms is empty) and biomes without a sigil_set.
	var sigil_set: Array = BiomeData.load_sigil_set(biome)
	var density: Vector2i = BiomeData.sigil_density(biome)
	if not sigil_set.is_empty() and density.y > 0 and not rooms.is_empty():
		_stamp_room_sigils(sigil_set, density, protected_cells, rng)

func _door_texture_for(biome: Dictionary) -> Texture2D:
	var biome_id: String = String(biome.get("id", ""))
	match DOOR_BY_BIOME.get(biome_id, "plain"):
		"runed":  return DOOR_RUNED
		"sealed": return DOOR_SEALED
		_:        return DOOR_PLAIN

func _stamp_decor_marks(vault_results: Dictionary, _rng: RandomNumberGenerator) -> void:
	var decor: Array = vault_results.get("decor_marks", [])
	for entry in decor:
		var cell: Vector2i = entry.cell
		if cell.y < 0 or cell.y >= grid.size() or cell.x < 0 or cell.x >= grid[0].size():
			continue
		var is_wall_decor: bool = bool(entry.get("is_wall", false))
		# Skip type mismatch — bones on a floor cell, tree on a wall cell.
		if is_wall_decor:
			if grid[cell.y][cell.x] != C.T_WALL:
				continue
		else:
			if grid[cell.y][cell.x] != C.T_FLOOR and grid[cell.y][cell.x] != C.T_STAIRS_DOWN:
				continue
		var tex_name: String = String(entry.get("texture", ""))
		if tex_name == "":
			continue
		# Try both decor dirs: sigils/ for floor sigils, decor_impassable/
		# for trees / mushrooms / bones / sarcophagus / etc.
		var tex: Texture2D = null
		var path_a: String = "res://assets/tiles/sigils/" + tex_name + ".png"
		var path_b: String = "res://assets/tiles/decor_impassable/" + tex_name + ".png"
		if ResourceLoader.exists(path_a):
			tex = load(path_a)
		elif ResourceLoader.exists(path_b):
			tex = load(path_b)
		if tex == null:
			continue
		_place(tex, cell.x, cell.y)
		decor_marks.append({"cell": cell, "texture": tex_name})

func _stamp_room_sigils(sigil_set: Array, density: Vector2i, protected: Dictionary, rng: RandomNumberGenerator) -> void:
	for r in rooms:
		var rect: Rect2i = r as Rect2i
		# Tiny rooms (<= 4 cells interior) skip — sigils need breathing room.
		if rect.size.x < 3 or rect.size.y < 3:
			continue
		var lo: int = max(0, density.x)
		var hi: int = max(lo, density.y)
		var n: int = lo if lo == hi else rng.randi_range(lo, hi)
		var attempts: int = 0
		var placed: int = 0
		# Cap attempts to avoid infinite loops on tiny / dense rooms.
		while placed < n and attempts < n * 6:
			attempts += 1
			var cx: int = rect.position.x + rng.randi_range(1, max(1, rect.size.x - 2))
			var cy: int = rect.position.y + rng.randi_range(1, max(1, rect.size.y - 2))
			var cell := Vector2i(cx, cy)
			if protected.has(cell):
				continue
			if cy < 0 or cy >= grid.size() or cx < 0 or cx >= grid[0].size():
				continue
			if grid[cy][cx] != C.T_FLOOR:
				continue
			var idx: int = _hash_idx(cx, cy, 41, rng.seed) % sigil_set.size()
			var tex: Texture2D = sigil_set[idx]
			_place(tex, cx, cy)
			var path: String = String(tex.resource_path) if tex and tex.resource_path else ""
			sigil_marks.append({"cell": cell, "texture_path": path})
			placed += 1

func _apply_edge_overlay(x: int, y: int, w: int, h: int, overlay: Dictionary, rng: RandomNumberGenerator) -> void:
	# Determine which cardinals are walls (treat out-of-bounds as wall too —
	# the map perimeter should overlay correctly even at the very edge).
	var n_wall: bool = _is_wall_or_out(x, y - 1, w, h)
	var s_wall: bool = _is_wall_or_out(x, y + 1, w, h)
	var e_wall: bool = _is_wall_or_out(x + 1, y, w, h)
	var w_wall: bool = _is_wall_or_out(x - 1, y, w, h)
	var wall_count: int = int(n_wall) + int(s_wall) + int(e_wall) + int(w_wall)

	var density: float = float(overlay.get("density", 0.7))
	var patch_density: float = float(overlay.get("patch_density", 0.04))

	if wall_count == 0:
		# No bordering walls — optional random patch from the patches array.
		var patches: Array = overlay.get("patches", [])
		if patches.is_empty():
			return
		if _hash_chance(x, y, 17, rng.seed) >= patch_density:
			return
		var idx: int = _hash_idx(x, y, 19, rng.seed) % patches.size()
		_place(patches[idx], x, y)
		return

	# Roll density gate so the overlay isn't on every wall-adjacent cell —
	# gives a more organic look (some bare cells, some grass-spilling cells).
	if _hash_chance(x, y, 23, rng.seed) >= density:
		return

	# All four cardinals are walls — use 'full' if we have one, else nothing.
	if wall_count == 4:
		if overlay.has("full"):
			_place(overlay["full"], x, y)
		return

	# Two adjacent walls form a corner — pick the diagonal piece.
	if n_wall and e_wall and overlay.has("northeast"):
		_place(overlay["northeast"], x, y); return
	if n_wall and w_wall and overlay.has("northwest"):
		_place(overlay["northwest"], x, y); return
	if s_wall and e_wall and overlay.has("southeast"):
		_place(overlay["southeast"], x, y); return
	if s_wall and w_wall and overlay.has("southwest"):
		_place(overlay["southwest"], x, y); return

	# Single-cardinal: use that direction. If two opposite walls (e.g. N+S),
	# pick one randomly so we don't double-stamp.
	var picks: Array = []
	if n_wall and overlay.has("north"): picks.append("north")
	if s_wall and overlay.has("south"): picks.append("south")
	if e_wall and overlay.has("east"):  picks.append("east")
	if w_wall and overlay.has("west"):  picks.append("west")
	if picks.is_empty():
		return
	var dir: String = picks[_hash_idx(x, y, 29, rng.seed) % picks.size()]
	_place(overlay[dir], x, y)

func _is_wall_or_out(x: int, y: int, w: int, h: int) -> bool:
	if x < 0 or y < 0 or x >= w or y >= h:
		return true
	return grid[y][x] == C.T_WALL

func _wall_borders_floor(x: int, y: int, w: int, h: int) -> bool:
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			var nx: int = x + dx
			var ny: int = y + dy
			if nx < 0 or ny < 0 or nx >= w or ny >= h:
				continue
			var n: int = grid[ny][nx]
			if n == C.T_FLOOR or n == C.T_STAIRS_DOWN:
				return true
	return false

func _generate_floor_patches(w: int, h: int, primary_count: int, rng: RandomNumberGenerator) -> Array:
	var seeds: Array = []
	for i in FLOOR_PATCH_COUNT:
		var sx: int = rng.randi_range(0, w - 1)
		var sy: int = rng.randi_range(0, h - 1)
		var primary_idx: int = rng.randi_range(0, maxi(0, primary_count - 1))
		seeds.append({"x": sx, "y": sy, "primary": primary_idx})
	return seeds

func _generate_wall_patches(w: int, h: int, wall_primary: Array, wall_alternates: Array, rng: RandomNumberGenerator) -> Array:
	var seeds: Array = []
	var total_alt_weight: float = 0.0
	for a in wall_alternates:
		total_alt_weight += float(a.get("weight", 0))
	for i in WALL_PATCH_COUNT:
		var sx: int = rng.randi_range(0, w - 1)
		var sy: int = rng.randi_range(0, h - 1)
		var theme: Dictionary = {}
		var roll: float = rng.randf_range(0.0, 100.0)
		if roll < total_alt_weight and not wall_alternates.is_empty():
			var pick: float = rng.randf_range(0.0, total_alt_weight)
			var cum: float = 0.0
			for a in wall_alternates:
				cum += float(a.get("weight", 0))
				if pick <= cum:
					theme = {"textures": a["textures"], "is_alt": true}
					break
		if theme.is_empty():
			theme = {"textures": wall_primary, "is_alt": false}
		seeds.append({"x": sx, "y": sy, "theme": theme})
	return seeds

func _pick_floor_tile(x: int, y: int, _patches: Array, primary: Array, accent: Array, rng: RandomNumberGenerator) -> Texture2D:
	# DCSS-style per-cell hashed weighted variant pick. Each cell is a stable
	# hash of (rng.seed, x, y) into the primary array, with an accent sprinkle
	# at low probability. No Voronoi patching — variants are subtly different
	# and per-cell randomness reads as "textured floor" rather than "chunky
	# patch boundaries". (Patches arg kept for signature compat; ignored.)
	if not accent.is_empty() and _hash_chance(x, y, 73, rng.seed) < ACCENT_PROB:
		return accent[_hash_idx(x, y, 31, rng.seed) % accent.size()]
	if primary.is_empty():
		return null
	# Weighted pick: variants earlier in the array are slightly more common
	# (matches DCSS's `%weight 6 / 3 / 1` distribution where common variants
	# dominate). Shape: [6, 6, 6, 6, 3, 3, 1, 1] gives the first variants
	# ~25% each and tail variants ~3% each.
	var weights: Array = []
	var total: int = 0
	for i in primary.size():
		var w: int = 6
		if i >= primary.size() / 2:
			w = 3
		if i >= primary.size() * 3 / 4:
			w = 1
		weights.append(w)
		total += w
	var roll: int = _hash_idx(x, y, 11, rng.seed) % max(1, total)
	var cum: int = 0
	for i in primary.size():
		cum += weights[i]
		if roll < cum:
			return primary[i]
	return primary[-1]

func _pick_wall_tile(x: int, y: int, patches: Array, _wall_primary: Array, wall_accent: Array, rng: RandomNumberGenerator) -> Texture2D:
	var best: int = 0
	var best_d: int = 999999
	for i in patches.size():
		var p: Dictionary = patches[i]
		var dx: int = x - int(p.x)
		var dy: int = y - int(p.y)
		var d: int = dx * dx + dy * dy
		if d < best_d:
			best_d = d
			best = i
	var theme: Dictionary = patches[best].theme
	var textures: Array = theme.textures
	var is_alt: bool = bool(theme.get("is_alt", false))
	if is_alt:
		return textures[_hash_idx(x, y, 53, rng.seed) % textures.size()]
	if not wall_accent.is_empty() and _hash_chance(x, y, 91, rng.seed) < WALL_ACCENT_PROB:
		return wall_accent[_hash_idx(x, y, 47, rng.seed) % wall_accent.size()]
	return textures[0]

func _hash_chance(x: int, y: int, salt: int, sd: int) -> float:
	var v: int = ((x * 73856093) ^ (y * 19349663) ^ (salt * 83492791) ^ sd) & 0x7fffffff
	return float(v % 1000) / 1000.0

func _hash_idx(x: int, y: int, salt: int, sd: int) -> int:
	var v: int = ((x * 73856093) ^ (y * 19349663) ^ (salt * 83492791) ^ sd) & 0x7fffffff
	return v

func _place(tex: Texture2D, x: int, y: int) -> void:
	var s := Sprite2D.new()
	s.texture = tex
	s.centered = false
	s.position = Vector2(x * C.TILE_SIZE, y * C.TILE_SIZE)
	s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	s.modulate = Color(0, 0, 0, 1)
	add_child(s)
	var key := Vector2i(x, y)
	if not cell_sprites.has(key):
		cell_sprites[key] = []
	cell_sprites[key].append(s)

static var _shared_occluder: OccluderPolygon2D = null

static func _occluder_poly() -> OccluderPolygon2D:
	if _shared_occluder != null:
		return _shared_occluder
	var poly := OccluderPolygon2D.new()
	var t: float = float(C.TILE_SIZE)
	poly.polygon = PackedVector2Array([
		Vector2(0, 0), Vector2(t, 0), Vector2(t, t), Vector2(0, t)
	])
	poly.closed = true
	_shared_occluder = poly
	return _shared_occluder

func _place_occluder(x: int, y: int) -> void:
	var occ := LightOccluder2D.new()
	occ.occluder = _occluder_poly()
	occ.position = Vector2(x * C.TILE_SIZE, y * C.TILE_SIZE)
	add_child(occ)

const VIS_MOD_VISIBLE := Color(1, 1, 1, 1)
const VIS_MOD_EXPLORED := Color(0.45, 0.5, 0.6, 1.0)
const VIS_MOD_UNSEEN := Color(0, 0, 0, 0)

func apply_visibility(fog: FogSystem) -> void:
	if fog == null or cell_sprites.is_empty():
		return
	for key in cell_sprites.keys():
		cell_target_alpha[key] = 1.0 if fog.is_visible(key) else 0.0

func _process(delta: float) -> void:
	if cell_target_alpha.is_empty():
		return
	PerfMon.begin(PerfMon.TAG_RENDER_FADE)
	var step: float = FADE_RATE * delta
	for key in cell_target_alpha.keys():
		var target: float = cell_target_alpha[key]
		var current: float = cell_current_alpha.get(key, 0.0)
		if is_equal_approx(current, target):
			continue
		if current < target:
			current = minf(current + step, target)
		else:
			current = maxf(current - step, target)
		cell_current_alpha[key] = current
		var sprites: Array = cell_sprites[key]
		for s in sprites:
			if is_instance_valid(s):
				s.modulate = Color(current, current, current, 1.0)
	PerfMon.end(PerfMon.TAG_RENDER_FADE)
