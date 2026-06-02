class_name ActorShadow
extends Node2D

# Static darkened ellipse drawn beneath an actor so the figure reads as
# planted on the floor instead of floating. Drawn directly via _draw()
# (no texture allocation) — one polygon per actor, stable cost.
#
# DCSS reference: tilesdl.cc draws a similar fake shadow under tile
# figures via the doll layer's PSE_SHADOW slot. We don't need their
# bespoke art for an idle game — a tinted oval reads the same.

const C := preload("res://scripts/constants.gd")

# Default shadow shape — flat oval, slightly narrower than the tile.
const RADIUS_X := 11.0
const RADIUS_Y := 3.5
const SEGMENTS := 16
const COLOR := Color(0, 0, 0, 0.45)

var radius_x: float = RADIUS_X
var radius_y: float = RADIUS_Y
var color: Color = COLOR

func _draw() -> void:
	var pts := PackedVector2Array()
	for i in SEGMENTS:
		var a: float = TAU * float(i) / float(SEGMENTS)
		pts.append(Vector2(cos(a) * radius_x, sin(a) * radius_y))
	draw_colored_polygon(pts, color)
