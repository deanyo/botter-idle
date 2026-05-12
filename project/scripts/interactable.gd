class_name Interactable
extends Node2D

const C := preload("res://scripts/constants.gd")

signal interaction_complete(node: Interactable)

var cell: Vector2i = Vector2i.ZERO
var interact_duration: float = 0.4
var consumed: bool = false

func _init() -> void:
	pass

func place_at(at_cell: Vector2i) -> void:
	cell = at_cell
	position = Vector2(at_cell.x * C.TILE_SIZE, at_cell.y * C.TILE_SIZE)

func can_interact() -> bool:
	return not consumed

func should_skip(_bot: Bot) -> bool:
	return false

func on_interact_start(_bot: Bot) -> void:
	pass

func on_interact_complete(_bot: Bot) -> void:
	pass
