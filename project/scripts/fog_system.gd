class_name FogSystem
extends RefCounted

const C := preload("res://scripts/constants.gd")

const VIS_UNSEEN := 0
const VIS_EXPLORED := 1
const VIS_VISIBLE := 2

const BOT_LOS_RADIUS := 8

var grid_w: int = 0
var grid_h: int = 0
var grid: Array = []
var visibility: Array = []
var vis_image: Image = null
var vis_texture: ImageTexture = null

func setup(w: int, h: int, dungeon_grid: Array) -> void:
	grid_w = w
	grid_h = h
	grid = dungeon_grid
	visibility = []
	for y in h:
		var row := []
		row.resize(w)
		for x in w:
			row[x] = VIS_UNSEEN
		visibility.append(row)
	vis_image = Image.create(w, h, false, Image.FORMAT_R8)
	vis_image.fill(Color(0, 0, 0, 1))
	vis_texture = ImageTexture.create_from_image(vis_image)

func recompute(bot_cell: Vector2i, los_sources: Array) -> void:
	for y in grid_h:
		var row: Array = visibility[y]
		for x in grid_w:
			if row[x] == VIS_VISIBLE:
				row[x] = VIS_EXPLORED
	_cast(bot_cell, BOT_LOS_RADIUS)
	for src in los_sources:
		var cell: Vector2i = src.cell
		var radius: int = int(src.radius)
		_cast(cell, radius)
	_update_texture()

func _update_texture() -> void:
	if vis_image == null:
		return
	for y in grid_h:
		var row: Array = visibility[y]
		for x in grid_w:
			var v: int = row[x]
			var g: float = 0.0
			if v == VIS_VISIBLE:
				g = 1.0
			elif v == VIS_EXPLORED:
				g = 0.5
			vis_image.set_pixel(x, y, Color(g, g, g, 1.0))
	if vis_texture:
		vis_texture.update(vis_image)

func is_visible(cell: Vector2i) -> bool:
	if cell.x < 0 or cell.y < 0 or cell.x >= grid_w or cell.y >= grid_h:
		return false
	return visibility[cell.y][cell.x] == VIS_VISIBLE

func is_explored(cell: Vector2i) -> bool:
	if cell.x < 0 or cell.y < 0 or cell.x >= grid_w or cell.y >= grid_h:
		return false
	return visibility[cell.y][cell.x] != VIS_UNSEEN

func is_seen(cell: Vector2i) -> bool:
	return is_explored(cell)

func _cast(origin: Vector2i, radius: int) -> void:
	if origin.y < 0 or origin.x < 0 or origin.y >= grid_h or origin.x >= grid_w:
		return
	if radius <= 0:
		visibility[origin.y][origin.x] = VIS_VISIBLE
		return
	visibility[origin.y][origin.x] = VIS_VISIBLE
	var r2: int = radius * radius
	# Cast a ray to every cell on the bounding-box perimeter. Each ray walks
	# from the origin outward via Bresenham, marking floor cells visible and
	# stopping after the first wall (the wall itself is marked visible). This
	# is permissive raycast FOV — symmetric enough for our tile scale, and
	# cheap (4*(2r+1) rays * O(r) length per source).
	var rad: int = radius
	var perimeter: Array[Vector2i] = []
	for d in range(-rad, rad + 1):
		perimeter.append(Vector2i(origin.x + d, origin.y - rad))
		perimeter.append(Vector2i(origin.x + d, origin.y + rad))
		perimeter.append(Vector2i(origin.x - rad, origin.y + d))
		perimeter.append(Vector2i(origin.x + rad, origin.y + d))
	for target in perimeter:
		_ray(origin, target, r2)

func _ray(from: Vector2i, to: Vector2i, r2: int) -> void:
	var x0: int = from.x
	var y0: int = from.y
	var x1: int = to.x
	var y1: int = to.y
	var dx: int = absi(x1 - x0)
	var dy: int = -absi(y1 - y0)
	var sx: int = 1 if x0 < x1 else -1
	var sy: int = 1 if y0 < y1 else -1
	var err: int = dx + dy
	var first: bool = true
	while true:
		if not first:
			if x0 < 0 or y0 < 0 or x0 >= grid_w or y0 >= grid_h:
				return
			var rdx: int = x0 - from.x
			var rdy: int = y0 - from.y
			if rdx * rdx + rdy * rdy > r2:
				return
			visibility[y0][x0] = VIS_VISIBLE
			if grid[y0][x0] == C.T_WALL:
				return
		first = false
		if x0 == x1 and y0 == y1:
			return
		var e2: int = 2 * err
		if e2 >= dy:
			err += dy
			x0 += sx
		if e2 <= dx:
			err += dx
			y0 += sy
