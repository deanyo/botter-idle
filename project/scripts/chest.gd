class_name Chest
extends Interactable

const FEATURE_TILE_DIR := "res://assets/tiles/features/"
const CLOSED_TEX := preload("res://assets/tiles/features/chest_closed.png")
const OPEN_TEX := preload("res://assets/tiles/features/chest_open.png")

signal opened(chest: Chest, drop_count: int, rarity_bias: int)

var sprite: Sprite2D
var glow: Sprite2D
var pulse: Tween
var drop_count: int = 2
var rarity_bias: int = 0
var glow_color: Color = Color(1.0, 0.9, 0.3, 0.6)

func _init() -> void:
	interact_duration = 1.2

func setup(at_cell: Vector2i, drops: int = 2, bias: int = 0) -> void:
	place_at(at_cell)
	drop_count = drops
	rarity_bias = bias
	if bias >= 2:
		glow_color = Color(1.0, 0.5, 0.2, 0.8)
		interact_duration = 1.5
	elif bias >= 1:
		glow_color = Color(1.0, 0.9, 0.3, 0.7)

func _ready() -> void:
	sprite = Sprite2D.new()
	sprite.centered = true
	sprite.position = Vector2(C.TILE_SIZE * 0.5, C.TILE_SIZE * 0.5)
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.texture = CLOSED_TEX
	add_child(sprite)

	glow = Sprite2D.new()
	glow.centered = true
	glow.position = Vector2(C.TILE_SIZE * 0.5, C.TILE_SIZE * 0.5)
	glow.texture = LootDrop._make_glow_texture()
	glow.modulate = glow_color
	glow.scale = Vector2(2.2, 2.2)
	glow.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(glow)
	move_child(glow, 0)

	var spec_id: String = "chest_gold"
	if rarity_bias >= 2:
		spec_id = "chest_orange"
	LightSpec.attach(self, spec_id)

	_pulse_glow()

func _pulse_glow() -> void:
	if not is_instance_valid(glow):
		return
	var base: Color = glow.modulate
	var dim: Color = Color(base.r, base.g, base.b, base.a * 0.45)
	pulse = glow.create_tween().set_loops()
	pulse.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	pulse.tween_property(glow, "modulate", dim, 0.9)
	pulse.tween_property(glow, "modulate", base, 0.9)

func on_interact_complete(_bot: Bot) -> void:
	if consumed:
		return
	consumed = true
	if pulse and pulse.is_valid():
		pulse.kill()
	if is_instance_valid(sprite):
		sprite.texture = OPEN_TEX
		var jolt := sprite.create_tween()
		jolt.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		jolt.tween_property(sprite, "scale", Vector2(1.25, 0.85), 0.08)
		jolt.tween_property(sprite, "scale", Vector2.ONE, 0.18)
	if is_instance_valid(glow):
		var fade := glow.create_tween()
		fade.tween_property(glow, "modulate:a", 0.0, 0.4)
	opened.emit(self, drop_count, rarity_bias)
	interaction_complete.emit(self)
