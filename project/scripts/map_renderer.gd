class_name MapRenderer
extends Node2D

# TileMapLayer-backed renderer. Replaces the per-cell Sprite2D approach
# that was the dominant draw-call cost on the map (one canvas item per
# tile = thousands of draw calls per frame). Now: two TileMapLayers
# (base + overlay), each one canvas item; visibility fade via shader.
#
# Tile selection still respects:
#   - Per-cell hashed weighted variant pick (DCSS 6/3/1)
#   - Dual-floor Perlin noise mix
#   - Wall alternates with weighted patches
#   - Edge overlay directional autotile
#   - Vault decor marks + room sigils
# Each is a tile-set source picked by atlas_coords on set_cell.

const C := preload("res://scripts/constants.gd")

const STAIRS_DOWN_TEX := preload("res://assets/tiles/gateways/stairs_down.png")
const DOOR_PLAIN := preload("res://assets/tiles/features/closed_door.png")
const DOOR_RUNED := preload("res://assets/tiles/features/runed_door.png")
const DOOR_SEALED := preload("res://assets/tiles/features/sealed_door.png")
const TERRAIN_LAVA := preload("res://assets/tiles/terrain/lava.png")
const TERRAIN_WATER := preload("res://assets/tiles/terrain/water.png")
const TERRAIN_ICE := preload("res://assets/tiles/terrain/ice.png")
const VIS_SHADER := preload("res://assets/tile_visibility.gdshader")
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
# Public consumer-facing fields kept for screenshot JSON sidecar / signal
# parity with the old renderer.
var wall_cells: Dictionary = {}
var sigil_marks: Array = []
var decor_marks: Array = []

# TileSet + layers built per floor.
var _tileset: TileSet = null
var _base_layer: TileMapLayer = null
var _overlay_layer: TileMapLayer = null
var _vis_material: ShaderMaterial = null
# Heat-haze layer for lava cells. One small Sprite2D per lava cell
# covering the cell + the row above. Each carries a ShaderMaterial
# referencing assets/heat_haze.gdshader. Only created when lava cells
# exist; disabled via BOTTER_NO_HEAT_HAZE=1.
const HEAT_HAZE_SHADER := preload("res://assets/heat_haze.gdshader")
var _heat_haze_layer: Node2D = null
# Water shimmer: same pattern as heat haze but covers just the water cell
# (water doesn't rise/distort upward). One Sprite2D per T_WATER cell.
const WATER_SHIMMER_SHADER := preload("res://assets/water_shimmer.gdshader")
var _water_shimmer_layer: Node2D = null
# Single packed atlas: every unique tile texture this floor uses gets
# blitted into one big Image, then registered as one TileSetAtlasSource
# with per-tile atlas_coords. Result: TileMapLayer draws each layer in
# 1-2 batched calls instead of one per texture.
var _packed_atlas_source_id: int = 0
var _packed_atlas_cols: int = 1
# Texture2D -> Vector2i atlas_coords in the packed atlas.
var _atlas_coords_for: Dictionary = {}
# Pending texture queue, populated in pass 1; baked in _bake_atlas.
var _pending_textures: Array = []

func render(g: Array, rs: Array, biome: Dictionary, rng: RandomNumberGenerator, vault_results: Dictionary = {}) -> void:
	# Tear down any previous floor's tile data.
	for child in get_children():
		child.queue_free()
	wall_cells.clear()
	sigil_marks.clear()
	decor_marks.clear()
	_atlas_coords_for.clear()
	_pending_textures.clear()
	grid = g
	rooms = rs
	if OS.has_environment("BOTTER_NO_TILES"):
		return
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

	var h := grid.size()
	var w: int = grid[0].size() if h > 0 else 0

	# Dual-floor noise + wall patch seeds (same algorithm as the old renderer).
	var floor_noise: FastNoiseLite = null
	if not floor_secondary.is_empty():
		floor_noise = FastNoiseLite.new()
		floor_noise.noise_type = FastNoiseLite.TYPE_PERLIN
		floor_noise.frequency = 0.045
		floor_noise.seed = int(rng.seed)
	var floor_patches: Array = _generate_floor_patches(w, h, floor_primary.size(), rng)
	var wall_patches: Array = _generate_wall_patches(w, h, wall_primary, wall_alternates, rng)

	# Pass 1: pre-register every texture that could possibly be used so we
	# can bake them into one packed atlas. Cheap (only Texture2D refs;
	# arrays already loaded by BiomeData).
	for tex in floor_primary: _register_texture(tex)
	for tex in floor_secondary: _register_texture(tex)
	for tex in floor_accent: _register_texture(tex)
	for tex in wall_primary: _register_texture(tex)
	for tex in wall_accent: _register_texture(tex)
	for alt in wall_alternates:
		for tex in alt.get("textures", []):
			_register_texture(tex)
	for k in edge_overlay.keys():
		var v: Variant = edge_overlay[k]
		if v is Texture2D: _register_texture(v)
		elif v is Array:
			for t in v:
				if t is Texture2D: _register_texture(t)
	_register_texture(STAIRS_DOWN_TEX)
	_register_texture(_door_texture_for(biome))
	_register_texture(TERRAIN_LAVA)
	_register_texture(TERRAIN_WATER)
	_register_texture(TERRAIN_ICE)
	for tex in BiomeData.load_sigil_set(biome): _register_texture(tex)
	# Vault decor textures load by name from disk — preload them here so
	# the atlas bake catches them.
	for entry in vault_results.get("decor_marks", []):
		var tex_name: String = String(entry.get("texture", ""))
		if tex_name == "":
			continue
		var path_a: String = "res://assets/tiles/sigils/" + tex_name + ".png"
		var path_b: String = "res://assets/tiles/decor_impassable/" + tex_name + ".png"
		var t: Texture2D = null
		if ResourceLoader.exists(path_a):
			t = load(path_a)
		elif ResourceLoader.exists(path_b):
			t = load(path_b)
		if t != null:
			_register_texture(t)
	# Bake the atlas now that we know every texture this floor needs.
	_build_tileset_and_layers(w, h)

	var overlay_label: String = "(none)"
	if not edge_overlay.is_empty():
		overlay_label = "n=%d cardinals" % int(edge_overlay.size() - 1)
	GrindLog.log_line("[render] biome=%s floor_tiles=%d wall_tiles=%d overlay=%s" % [
		String(biome.get("id","?")), floor_primary.size(), wall_primary.size(), overlay_label,
	])

	# Collect lava + water cells along the way to attach effects later.
	var lava_cells: Array[Vector2i] = []
	var water_cells: Array[Vector2i] = []
	# First pass — base layer (floor / wall / terrain / door / stairs).
	for y in h:
		for x in w:
			var cell: int = grid[y][x]
			var tex: Texture2D = null
			if cell == C.T_WALL:
				if not _wall_borders_floor(x, y, w, h):
					continue
				tex = _pick_wall_tile(x, y, wall_patches, wall_primary, wall_accent, rng)
				wall_cells[Vector2i(x, y)] = true
			elif cell == C.T_FLOOR or cell == C.T_STAIRS_DOWN or cell == C.T_DOOR:
				var pool: Array = floor_primary
				if floor_noise != null and floor_noise.get_noise_2d(float(x), float(y)) > 0.18:
					pool = floor_secondary
				tex = _pick_floor_tile(x, y, floor_patches, pool, floor_accent, rng)
			elif cell == C.T_LAVA:
				tex = TERRAIN_LAVA
				lava_cells.append(Vector2i(x, y))
			elif cell == C.T_WATER:
				tex = TERRAIN_WATER
				water_cells.append(Vector2i(x, y))
			elif cell == C.T_ICE:
				tex = TERRAIN_ICE
			if tex:
				_set_base(x, y, tex)
			# Stairs draw on top of the floor tile they overwrite.
			if cell == C.T_STAIRS_DOWN:
				_set_overlay(x, y, STAIRS_DOWN_TEX)
			if cell == C.T_DOOR:
				_set_overlay(x, y, _door_texture_for(biome))
			# Edge overlay on floor cells bordering walls.
			if not edge_overlay.is_empty() and (cell == C.T_FLOOR or cell == C.T_DOOR or cell == C.T_STAIRS_DOWN):
				var edge_tex: Texture2D = _pick_edge_overlay(x, y, w, h, edge_overlay, rng)
				if edge_tex:
					_set_overlay(x, y, edge_tex)
			# Per-wall light occluder (for shadow casting). One LightOccluder2D
			# per wall is unavoidable in Godot 4 — TileSet's occlusion layer
			# would need a custom TileSetSource pipeline; this is fine.
			if cell == C.T_WALL:
				_place_occluder(x, y)

	# Vault decor overlays (multi-tile sigil compositions etc.).
	_stamp_decor_marks(vault_results)
	# Per-room sigils.
	var sigil_set: Array = BiomeData.load_sigil_set(biome)
	var density: Vector2i = BiomeData.sigil_density(biome)
	if not sigil_set.is_empty() and density.y > 0 and not rooms.is_empty():
		_stamp_room_sigils(sigil_set, density, protected_cells, rng)
	# Heat haze on lava cells. Each lava cell + 2 rows above gets a sprite
	# with the heat_haze shader. Sub-microsecond per fragment, only paints
	# behind visible lava — total cost scales with lava cell count.
	# Toggleable from video options (gfx.heat_haze); env override
	# BOTTER_NO_HEAT_HAZE / BOTTER_FORCE_HEAT_HAZE.
	if not lava_cells.is_empty() and VideoSettings.is_effect_enabled("heat_haze"):
		_attach_heat_haze(lava_cells)
	# Water shimmer on water cells. Single-cell sprite per cell (no
	# vertical extension — water doesn't rise). Cheaper than heat haze.
	if not water_cells.is_empty() and VideoSettings.is_effect_enabled("water_shimmer"):
		_attach_water_shimmer(water_cells)

func _register_texture(tex: Texture2D) -> void:
	if tex == null:
		return
	if _atlas_coords_for.has(tex):
		return
	# Coords assigned in registration order; computed in _build_tileset.
	_pending_textures.append(tex)

func _build_tileset_and_layers(w: int, h: int) -> void:
	# Compose every registered texture into one packed Image so the
	# TileSet has exactly ONE source — TileMapLayer can then batch the
	# whole layer into ~1 draw call instead of one per source.
	var n: int = _pending_textures.size()
	if n == 0:
		return
	var ts: int = C.TILE_SIZE
	# Square-ish layout: ceil(sqrt(n)) columns.
	var cols: int = int(ceil(sqrt(float(n))))
	var rows: int = int(ceil(float(n) / float(cols)))
	_packed_atlas_cols = cols
	var atlas_img := Image.create(cols * ts, rows * ts, false, Image.FORMAT_RGBA8)
	atlas_img.fill(Color(0, 0, 0, 0))
	for i in n:
		var tex: Texture2D = _pending_textures[i]
		var src_img: Image = tex.get_image()
		if src_img == null:
			continue
		# Some imported textures arrive in non-RGBA8; convert in place.
		if src_img.get_format() != Image.FORMAT_RGBA8:
			src_img = src_img.duplicate()
			src_img.convert(Image.FORMAT_RGBA8)
		var ax: int = i % cols
		var ay: int = i / cols
		atlas_img.blit_rect(
			src_img,
			Rect2i(0, 0, src_img.get_width(), src_img.get_height()),
			Vector2i(ax * ts, ay * ts),
		)
		_atlas_coords_for[tex] = Vector2i(ax, ay)
	var atlas_tex := ImageTexture.create_from_image(atlas_img)
	var src := TileSetAtlasSource.new()
	src.texture = atlas_tex
	src.texture_region_size = Vector2i(ts, ts)
	for i in n:
		var ax: int = i % cols
		var ay: int = i / cols
		src.create_tile(Vector2i(ax, ay))
	_tileset = TileSet.new()
	_tileset.tile_size = Vector2i(ts, ts)
	_packed_atlas_source_id = 0
	_tileset.add_source(src, _packed_atlas_source_id)
	# Visibility material shared by both layers.
	_vis_material = ShaderMaterial.new()
	_vis_material.shader = VIS_SHADER
	_vis_material.set_shader_parameter("grid_size", Vector2(float(w), float(h)))
	_vis_material.set_shader_parameter("tile_size_px", float(ts))
	_vis_material.set_shader_parameter("reveal_strength", 1.0)
	# Memory desaturation strength (0.0 = off, 1.0 = full grayscale in
	# memory cells). Toggleable from video options (gfx.memory_desat).
	var memory_strength: float = 0.6 if VideoSettings.is_effect_enabled("memory_desat") else 0.0
	_vis_material.set_shader_parameter("memory_strength", memory_strength)
	_base_layer = TileMapLayer.new()
	_base_layer.tile_set = _tileset
	_base_layer.material = _vis_material
	_base_layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_base_layer)
	_overlay_layer = TileMapLayer.new()
	_overlay_layer.tile_set = _tileset
	_overlay_layer.material = _vis_material
	_overlay_layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_overlay_layer.z_index = 1
	add_child(_overlay_layer)

func _set_base(x: int, y: int, tex: Texture2D) -> void:
	if tex == null:
		return
	var coords: Variant = _atlas_coords_for.get(tex, null)
	if coords == null:
		# Texture wasn't pre-registered — fall back: register, but the
		# atlas is already baked, so this tile won't render. Log so
		# we can fix the registration list.
		push_warning("MapRenderer: tile texture not pre-registered: %s" % str(tex.resource_path))
		return
	_base_layer.set_cell(Vector2i(x, y), _packed_atlas_source_id, coords)

func _set_overlay(x: int, y: int, tex: Texture2D) -> void:
	if tex == null:
		return
	var coords: Variant = _atlas_coords_for.get(tex, null)
	if coords == null:
		push_warning("MapRenderer: overlay tex not pre-registered: %s" % str(tex.resource_path))
		return
	_overlay_layer.set_cell(Vector2i(x, y), _packed_atlas_source_id, coords)

func _door_texture_for(biome: Dictionary) -> Texture2D:
	var biome_id: String = String(biome.get("id", ""))
	match DOOR_BY_BIOME.get(biome_id, "plain"):
		"runed":  return DOOR_RUNED
		"sealed": return DOOR_SEALED
		_:        return DOOR_PLAIN

func _stamp_decor_marks(vault_results: Dictionary) -> void:
	var decor: Array = vault_results.get("decor_marks", [])
	for entry in decor:
		var cell: Vector2i = entry.cell
		if cell.y < 0 or cell.y >= grid.size() or cell.x < 0 or cell.x >= grid[0].size():
			continue
		var is_wall_decor: bool = bool(entry.get("is_wall", false))
		if is_wall_decor:
			if grid[cell.y][cell.x] != C.T_WALL:
				continue
		else:
			if grid[cell.y][cell.x] != C.T_FLOOR and grid[cell.y][cell.x] != C.T_STAIRS_DOWN:
				continue
		var tex_name: String = String(entry.get("texture", ""))
		if tex_name == "":
			continue
		var tex: Texture2D = null
		var path_a: String = "res://assets/tiles/sigils/" + tex_name + ".png"
		var path_b: String = "res://assets/tiles/decor_impassable/" + tex_name + ".png"
		if ResourceLoader.exists(path_a):
			tex = load(path_a)
		elif ResourceLoader.exists(path_b):
			tex = load(path_b)
		if tex == null:
			continue
		_set_overlay(cell.x, cell.y, tex)
		decor_marks.append({"cell": cell, "texture": tex_name})

func _stamp_room_sigils(sigil_set: Array, density: Vector2i, protected: Dictionary, rng: RandomNumberGenerator) -> void:
	for r in rooms:
		var rect: Rect2i = r as Rect2i
		if rect.size.x < 3 or rect.size.y < 3:
			continue
		var lo: int = max(0, density.x)
		var hi: int = max(lo, density.y)
		var n: int = lo if lo == hi else rng.randi_range(lo, hi)
		var attempts: int = 0
		var placed: int = 0
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
			_set_overlay(cx, cy, tex)
			var path: String = String(tex.resource_path) if tex and tex.resource_path else ""
			sigil_marks.append({"cell": cell, "texture_path": path})
			placed += 1

func _pick_edge_overlay(x: int, y: int, w: int, h: int, overlay: Dictionary, rng: RandomNumberGenerator) -> Texture2D:
	var n_wall: bool = _is_wall_or_out(x, y - 1, w, h)
	var s_wall: bool = _is_wall_or_out(x, y + 1, w, h)
	var e_wall: bool = _is_wall_or_out(x + 1, y, w, h)
	var w_wall: bool = _is_wall_or_out(x - 1, y, w, h)
	var wall_count: int = int(n_wall) + int(s_wall) + int(e_wall) + int(w_wall)

	var density: float = float(overlay.get("density", 0.7))
	var patch_density: float = float(overlay.get("patch_density", 0.04))

	if wall_count == 0:
		var patches: Array = overlay.get("patches", [])
		if patches.is_empty():
			return null
		if _hash_chance(x, y, 17, rng.seed) >= patch_density:
			return null
		var idx: int = _hash_idx(x, y, 19, rng.seed) % patches.size()
		return patches[idx]
	if _hash_chance(x, y, 23, rng.seed) >= density:
		return null
	if wall_count == 4:
		return overlay.get("full", null)
	if n_wall and e_wall and overlay.has("northeast"):
		return overlay["northeast"]
	if n_wall and w_wall and overlay.has("northwest"):
		return overlay["northwest"]
	if s_wall and e_wall and overlay.has("southeast"):
		return overlay["southeast"]
	if s_wall and w_wall and overlay.has("southwest"):
		return overlay["southwest"]
	var picks: Array = []
	if n_wall and overlay.has("north"): picks.append("north")
	if s_wall and overlay.has("south"): picks.append("south")
	if e_wall and overlay.has("east"):  picks.append("east")
	if w_wall and overlay.has("west"):  picks.append("west")
	if picks.is_empty():
		return null
	var dir: String = picks[_hash_idx(x, y, 29, rng.seed) % picks.size()]
	return overlay[dir]

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
	if not accent.is_empty() and _hash_chance(x, y, 73, rng.seed) < ACCENT_PROB:
		return accent[_hash_idx(x, y, 31, rng.seed) % accent.size()]
	if primary.is_empty():
		return null
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
	# BOTTER_NO_OCCLUDERS=1 — perf A/B for the per-wall occluder count.
	if OS.has_environment("BOTTER_NO_OCCLUDERS"):
		return
	var occ := LightOccluder2D.new()
	occ.occluder = _occluder_poly()
	occ.position = Vector2(x * C.TILE_SIZE, y * C.TILE_SIZE)
	add_child(occ)

# ----------------------------------------------------------------------
# Public API consumed by Dungeon
# ----------------------------------------------------------------------

func apply_visibility(fog: FogSystem) -> void:
	# The shader handles the fade in real-time from the fog visibility
	# texture, so this is now just a uniform push when the texture itself
	# is replaced (only happens on _build_floor).
	if _vis_material == null or fog == null or fog.vis_texture == null:
		return
	_vis_material.set_shader_parameter("visibility_tex", fog.vis_texture)

func reveal_all() -> void:
	# Used by the screenshot path to flatten visibility for capture.
	# The fog texture itself is filled to 1.0 by the caller; we just bump
	# reveal_strength so the smoothstep doesn't dim anything.
	if _vis_material:
		_vis_material.set_shader_parameter("reveal_strength", 1.0)

# Build per-lava-cell heat-haze rectangles. Each covers the lava cell +
# 2 rows above (where rising heat would visibly distort whatever is
# rendered behind). The shader's vertical_falloff fades the effect
# upward so only the bottom shimmers strongly.
#
# Uses Sprite2D (Node2D-native) with a 1×1 white texture scaled to the
# zone size, so coordinates match the tile grid. ColorRect would force
# us into Control hierarchy which complicates positioning.
static var _heat_haze_tex: Texture2D = null

func _attach_heat_haze(lava_cells: Array[Vector2i]) -> void:
	if _heat_haze_layer != null and _heat_haze_layer.is_inside_tree():
		_heat_haze_layer.queue_free()
	_heat_haze_layer = Node2D.new()
	_heat_haze_layer.z_index = 50  # above tiles, below FX/UI
	add_child(_heat_haze_layer)
	# Lazy-init the 1×1 white tex once; shared across every haze sprite.
	if _heat_haze_tex == null:
		var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
		img.fill(Color(1, 1, 1, 1))
		_heat_haze_tex = ImageTexture.create_from_image(img)
	var px := float(C.TILE_SIZE)
	for cell in lava_cells:
		var spr := Sprite2D.new()
		spr.texture = _heat_haze_tex
		spr.centered = false
		# Scale 1px → tile_size × tile_size*3 (cell + 2 rows above).
		spr.scale = Vector2(px, px * 3.0)
		# Top-left of the affected zone = 2 rows above the lava cell.
		spr.position = Vector2(cell.x * px, (cell.y - 2) * px)
		var mat := ShaderMaterial.new()
		mat.shader = HEAT_HAZE_SHADER
		spr.material = mat
		_heat_haze_layer.add_child(spr)

# Water shimmer per T_WATER cell. Mirrors _attach_heat_haze but the
# sprite covers a single cell — water doesn't visually distort tiles
# above it the way heat does.
func _attach_water_shimmer(water_cells: Array[Vector2i]) -> void:
	if _water_shimmer_layer != null and _water_shimmer_layer.is_inside_tree():
		_water_shimmer_layer.queue_free()
	_water_shimmer_layer = Node2D.new()
	_water_shimmer_layer.z_index = 49  # just below heat haze
	add_child(_water_shimmer_layer)
	if _heat_haze_tex == null:
		var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
		img.fill(Color(1, 1, 1, 1))
		_heat_haze_tex = ImageTexture.create_from_image(img)
	var px := float(C.TILE_SIZE)
	for cell in water_cells:
		var spr := Sprite2D.new()
		spr.texture = _heat_haze_tex
		spr.centered = false
		spr.scale = Vector2(px, px)
		spr.position = Vector2(cell.x * px, cell.y * px)
		var mat := ShaderMaterial.new()
		mat.shader = WATER_SHIMMER_SHADER
		spr.material = mat
		_water_shimmer_layer.add_child(spr)
