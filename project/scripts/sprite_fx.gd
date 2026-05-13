class_name SpriteFX
extends RefCounted

const HIT_DURATION := 0.15
const ATTACK_DURATION := 0.18
const DEATH_DURATION := 0.40
const LOOT_DURATION := 0.20
const CAST_DURATION := 0.30

var sprite: Sprite2D
var base_scale: Vector2
var base_position: Vector2
var base_rotation: float
var base_modulate: Color
var transient: Tween

func _init(s: Sprite2D) -> void:
	sprite = s
	base_scale = s.scale
	base_position = s.position
	base_rotation = s.rotation
	base_modulate = s.modulate

func _reset() -> void:
	if transient and transient.is_valid():
		transient.kill()
	if not is_instance_valid(sprite):
		return
	sprite.scale = base_scale
	sprite.position = base_position
	sprite.rotation = base_rotation
	sprite.modulate = base_modulate

func attack_lunge(toward: Vector2) -> void:
	if not is_instance_valid(sprite):
		return
	_reset()
	var dir: Vector2 = toward.normalized() if toward.length() > 0.01 else Vector2.RIGHT
	var lunge_offset: Vector2 = base_position + dir * 12.0
	# Bright flash on the windup, fade back during the recovery. Punches up
	# the combat feel — without it the lunge is a position+scale bump only.
	var flash_color: Color = Color(
		minf(base_modulate.r * 1.6, 1.0),
		minf(base_modulate.g * 1.6, 1.0),
		minf(base_modulate.b * 1.4, 1.0),
		base_modulate.a,
	)
	transient = sprite.create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	transient.tween_property(sprite, "scale", base_scale * Vector2(1.15, 0.85), 0.05)
	transient.parallel().tween_property(sprite, "modulate", flash_color, 0.04)
	transient.tween_property(sprite, "scale", base_scale * Vector2(0.85, 1.15), 0.05)
	transient.parallel().tween_property(sprite, "position", lunge_offset, 0.05)
	transient.tween_property(sprite, "scale", base_scale, 0.08)
	transient.parallel().tween_property(sprite, "position", base_position, 0.08)
	transient.parallel().tween_property(sprite, "modulate", base_modulate, 0.10)

func hit_squish() -> void:
	if not is_instance_valid(sprite):
		return
	_reset()
	transient = sprite.create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	transient.tween_property(sprite, "scale", base_scale * Vector2(1.3, 0.7), 0.04)
	transient.parallel().tween_property(sprite, "modulate", Color(2.0, 2.0, 2.0, 1.0), 0.03)
	transient.tween_property(sprite, "scale", base_scale, 0.11)
	transient.parallel().tween_property(sprite, "modulate", base_modulate, 0.11)

func death_spin() -> Tween:
	if not is_instance_valid(sprite):
		return null
	_reset()
	transient = sprite.create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	var faded := Color(base_modulate.r, base_modulate.g, base_modulate.b, 0.0)
	transient.tween_property(sprite, "rotation", base_rotation + TAU, DEATH_DURATION)
	transient.parallel().tween_property(sprite, "scale", Vector2.ZERO, DEATH_DURATION)
	transient.parallel().tween_property(sprite, "modulate", faded, DEATH_DURATION)
	return transient

func loot_pop() -> void:
	if not is_instance_valid(sprite):
		return
	_reset()
	transient = sprite.create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	transient.tween_property(sprite, "position", base_position + Vector2(0, -6), 0.08)
	transient.tween_property(sprite, "position", base_position, 0.12)

func kneel(duration: float) -> void:
	if not is_instance_valid(sprite):
		return
	_reset()
	transient = sprite.create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	transient.tween_property(sprite, "scale", base_scale * Vector2(1.1, 0.85), 0.12)
	transient.parallel().tween_property(sprite, "position", base_position + Vector2(0, 2), 0.12)
	transient.tween_interval(maxf(0.0, duration - 0.24))
	transient.tween_property(sprite, "scale", base_scale, 0.12)
	transient.parallel().tween_property(sprite, "position", base_position, 0.12)

func cast_charge() -> void:
	if not is_instance_valid(sprite):
		return
	_reset()
	transient = sprite.create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	var glow := Color(1.5, 1.5, 2.2, 1.0)
	transient.tween_property(sprite, "scale", base_scale * Vector2(0.85, 1.25), 0.15)
	transient.parallel().tween_property(sprite, "modulate", glow, 0.15)
	transient.tween_property(sprite, "scale", base_scale, 0.15)
	transient.parallel().tween_property(sprite, "modulate", base_modulate, 0.15)
