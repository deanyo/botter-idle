class_name Pathfinding
extends RefCounted

const C := preload("res://scripts/constants.gd")

var astar: AStarGrid2D

func build(grid: Array) -> void:
	var h := grid.size()
	var w: int = grid[0].size() if h > 0 else 0
	astar = AStarGrid2D.new()
	astar.region = Rect2i(0, 0, w, h)
	astar.cell_size = Vector2(C.TILE_SIZE, C.TILE_SIZE)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.update()
	for y in h:
		for x in w:
			var cell: int = grid[y][x]
			var p := Vector2i(x, y)
			astar.set_point_solid(p, cell == C.T_WALL)
			# Discourage but don't block hazardous terrain. Lava costs 4× to
			# walk over (avoid if any safe path exists). Water costs 2× (slow
			# but acceptable). Ice is normal cost.
			if cell == C.T_LAVA:
				astar.set_point_weight_scale(p, 4.0)
			elif cell == C.T_WATER:
				astar.set_point_weight_scale(p, 2.0)

func path(from_cell: Vector2i, to_cell: Vector2i) -> PackedVector2Array:
	if astar == null:
		return PackedVector2Array()
	# If the FROM cell is marked solid (e.g., bot landed on a wall), unmark it
	# temporarily — bot is clearly there, pathfinding shouldn't reject the origin.
	var from_was_solid: bool = astar.is_point_solid(from_cell)
	if from_was_solid:
		astar.set_point_solid(from_cell, false)
	# If the destination is solid, try pathing to nearest walkable neighbor instead.
	var dest: Vector2i = to_cell
	if astar.is_point_solid(dest):
		var alt := _find_walkable_neighbor(dest)
		if alt.x >= 0:
			dest = alt
		else:
			if from_was_solid:
				astar.set_point_solid(from_cell, true)
			return PackedVector2Array()
	var result := astar.get_point_path(from_cell, dest)
	if from_was_solid:
		astar.set_point_solid(from_cell, true)
	return result

func _find_walkable_neighbor(c: Vector2i) -> Vector2i:
	if astar == null:
		return Vector2i(-1, -1)
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]:
		var n: Vector2i = c + d
		if not astar.region.has_point(n):
			continue
		if not astar.is_point_solid(n):
			return n
	return Vector2i(-1, -1)
