class_name AmbientDecor
extends Node2D

const C := preload("res://scripts/constants.gd")
const FEATURE_DIR := "res://assets/tiles/features/"

const DECOR_SPECS := {
	"lantern":      { "tile": "lantern.png",      "light": "lantern_gold" },
	"lamp":         { "tile": "lamp.png",         "light": "lantern" },
	"magic_lamp":   { "tile": "magic_lamp.png",   "light": "lantern_gold" },
	"orb":          { "tile": "orb.png",          "light": "crystal_blue" },
	"orb_2":        { "tile": "orb_2.png",        "light": "crystal_purple" },
	"crystal_orb":  { "tile": "crystal_orb.png",  "light": "crystal_blue" },
	"zot_pillar":   { "tile": "zot_pillar.png",   "light": "crystal_purple" },
	"flame_0":      { "tile": "flame_0.png",      "light": "flame_yellow" },
	"flame_1":      { "tile": "flame_1.png",      "light": "flame_orange" },
	"flame_2":      { "tile": "flame_2.png",      "light": "flame_red" },
	"orb_glow_0":   { "tile": "orb_glow_0.png",   "light": "crystal_purple" },
	"orb_glow_1":   { "tile": "orb_glow_1.png",   "light": "crystal_blue" },
	"sparkles_1":   { "tile": "sparkles_1.png",   "light": "chest_gold" },
	"mold_1":       { "tile": "mold_1.png",       "light": "mushroom_glow" },
	"mold_2":       { "tile": "mold_2.png",       "light": "mushroom_glow" },
	"campfire":     { "tile": "flame_2.png",      "light": "campfire" },
}

var sprite: Sprite2D
var spec_id: String = ""
var light_spec_id: String = ""
var cell: Vector2i = Vector2i.ZERO

func setup(decor_id: String, at_cell: Vector2i) -> void:
	spec_id = decor_id
	cell = at_cell
	position = Vector2(at_cell.x * C.TILE_SIZE, at_cell.y * C.TILE_SIZE)
	var spec: Dictionary = DECOR_SPECS.get(decor_id, {})
	light_spec_id = String(spec.get("light", ""))

func _ready() -> void:
	var spec: Dictionary = DECOR_SPECS.get(spec_id, {})
	if spec.is_empty():
		return
	var tex: Texture2D = load(FEATURE_DIR + String(spec.tile))
	if tex == null:
		return
	sprite = Sprite2D.new()
	sprite.texture = tex
	sprite.centered = true
	sprite.position = Vector2(C.TILE_SIZE * 0.5, C.TILE_SIZE * 0.5)
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(sprite)
	if light_spec_id != "":
		LightSpec.attach(self, light_spec_id)

func light_emit() -> Dictionary:
	var spec: Dictionary = LightSpec.SPECS.get(light_spec_id, {})
	if spec.is_empty():
		return {}
	return {
		"position": position + Vector2(C.TILE_SIZE * 0.5, C.TILE_SIZE * 0.5),
		"radius": C.TILE_SIZE * float(spec.get("range", 3.0)),
		"intensity": float(spec.get("energy", 0.6)),
		"color": spec.get("color", Color(1, 1, 1)),
	}
