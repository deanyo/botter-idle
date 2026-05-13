class_name Effects
extends RefCounted

# One-shot Sprite2D fade effects for combat/loot/altar feedback. Each spawn
# creates a transient Sprite2D, tweens its scale + alpha, and queue_frees
# itself. No persistent state. Caller passes a parent node (typically the
# Dungeon's actor_layer) and a world position.

const C := preload("res://scripts/constants.gd")

const FX_BLOOD_RED := preload("res://assets/tiles/effects/blood_splat_red.png")
const FX_BLOOD_GREEN := preload("res://assets/tiles/effects/blood_splat_green.png")
const FX_BLOOD_PUDDLE := preload("res://assets/tiles/effects/blood_puddle.png")
const FX_FIRE := preload("res://assets/tiles/effects/fire_flash.png")
const FX_ICE := preload("res://assets/tiles/effects/ice_shatter.png")
const FX_MAGIC := preload("res://assets/tiles/effects/magic_shimmer.png")
const FX_GOLD := preload("res://assets/tiles/effects/gold_sparkle.png")

# Spawn a one-shot fade effect at world position. Tweens scale up and alpha
# to zero over `duration`, then queue_frees.
static func spawn(parent: Node, tex: Texture2D, world_pos: Vector2, duration: float = 0.5, end_scale: float = 1.4) -> void:
	if parent == null or tex == null:
		return
	var s := Sprite2D.new()
	s.texture = tex
	s.centered = true
	s.position = world_pos
	s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	s.modulate = Color(1, 1, 1, 1)
	s.scale = Vector2(0.8, 0.8)
	s.z_index = 6
	parent.add_child(s)
	var tw := s.create_tween()
	tw.set_parallel(true)
	tw.tween_property(s, "scale", Vector2(end_scale, end_scale), duration)
	tw.tween_property(s, "modulate:a", 0.0, duration)
	tw.chain().tween_callback(s.queue_free)

# Convenience wrappers — pick the texture per effect type.
static func blood_splat(parent: Node, world_pos: Vector2) -> void:
	spawn(parent, FX_BLOOD_RED, world_pos, 0.45, 1.2)

static func fire_flash(parent: Node, world_pos: Vector2) -> void:
	spawn(parent, FX_FIRE, world_pos, 0.6, 1.6)

static func ice_shatter(parent: Node, world_pos: Vector2) -> void:
	spawn(parent, FX_ICE, world_pos, 0.5, 1.5)

static func magic_shimmer(parent: Node, world_pos: Vector2) -> void:
	spawn(parent, FX_MAGIC, world_pos, 0.7, 1.8)

static func gold_burst(parent: Node, world_pos: Vector2) -> void:
	spawn(parent, FX_GOLD, world_pos, 0.6, 1.4)
