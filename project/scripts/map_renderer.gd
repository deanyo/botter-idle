class_name MapRenderer
extends Node2D

const C := preload("res://scripts/constants.gd")

const STAIRS_DOWN_TEX := preload("res://assets/tiles/gateways/stairs_down.png")
const DOOR_TEX := preload("res://assets/tiles/features/closed_door.png")

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
# 0.4s full fade. Needs to be > the bot's per-cell move time so consecutive
# cell-flip reveal waves overlap into one continuous-looking emanation. With
# < cell-time, tiles complete fading then "hold" until the next cell crossing
# triggers another wave — that's the visible tick.
const FADE_RATE := 2.5

func render(g: Array, rs: Array, biome: Dictionary, rng: RandomNumberGenerator) -> void:
	for child in get_children():
		child.queue_free()
	cell_sprites.clear()
	wall_cells.clear()
	cell_target_alpha.clear()
	cell_current_alpha.clear()
	grid = g
	rooms = rs
	set_process(true)

	var floor_primary: Array = BiomeData.load_floor_primary(biome)
	var floor_accent: Array = BiomeData.load_floor_accent(biome)
	var wall_primary: Array = BiomeData.load_wall_primary(biome)
	var wall_accent: Array = BiomeData.load_wall_accent(biome)
	var wall_alternates: Array = BiomeData.load_wall_alternates(biome)
	if floor_primary.is_empty() or wall_primary.is_empty():
		push_error("Biome %s missing primary tiles" % biome.get("id", "?"))
		return

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
				tex = _pick_floor_tile(x, y, floor_patches, floor_primary, floor_accent, rng)
			if tex:
				_place(tex, x, y)
				if cell == C.T_WALL:
					wall_cells[Vector2i(x, y)] = true
			if cell == C.T_WALL:
				_place_occluder(x, y)
			if cell == C.T_STAIRS_DOWN:
				_place(STAIRS_DOWN_TEX, x, y)
			if cell == C.T_DOOR:
				_place(DOOR_TEX, x, y)

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

func _pick_floor_tile(x: int, y: int, patches: Array, primary: Array, accent: Array, rng: RandomNumberGenerator) -> Texture2D:
	if not accent.is_empty() and _hash_chance(x, y, 73, rng.seed) < ACCENT_PROB:
		return accent[_hash_idx(x, y, 31, rng.seed) % accent.size()]
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
	var primary_idx: int = int(patches[best].primary) % primary.size()
	return primary[primary_idx]

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
