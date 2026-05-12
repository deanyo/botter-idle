class_name Fountain
extends Interactable

const SPARKLING_TEX := preload("res://assets/tiles/features/fountain_sparkling.png")
const BLUE_TEX := preload("res://assets/tiles/features/fountain_blue.png")
const BLOOD_TEX := preload("res://assets/tiles/features/fountain_blood.png")
const DRY_TEX := preload("res://assets/tiles/features/fountain_dry.png")

signal drank(fountain: Fountain, heal_amount: int, kind: String)

var sprite: Sprite2D
var glow: Sprite2D
var pulse: Tween
var kind: String = "blue"
var heal_pct: float = 0.4

func _init() -> void:
	interact_duration = 1.0

func setup(at_cell: Vector2i, fountain_kind: String = "blue") -> void:
	place_at(at_cell)
	kind = fountain_kind
	match kind:
		"sparkling":
			heal_pct = 0.6
			interact_duration = 1.2
		"blue":
			heal_pct = 0.4
		"blood":
			heal_pct = 0.5
		_:
			heal_pct = 0.4

func _ready() -> void:
	sprite = Sprite2D.new()
	sprite.centered = true
	sprite.position = Vector2(C.TILE_SIZE * 0.5, C.TILE_SIZE * 0.5)
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.texture = _texture_for_kind()
	add_child(sprite)

	var glow_color: Color = _glow_color_for_kind()
	if glow_color.a > 0.01:
		glow = Sprite2D.new()
		glow.centered = true
		glow.position = Vector2(C.TILE_SIZE * 0.5, C.TILE_SIZE * 0.5)
		glow.texture = LootDrop._make_glow_texture()
		glow.modulate = glow_color
		glow.scale = Vector2(2.4, 2.4)
		glow.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		add_child(glow)
		move_child(glow, 0)
		_pulse_glow()
		LightSpec.attach(self, "fountain_" + kind)

func should_skip(bot: Bot) -> bool:
	return bot.hp >= bot.max_hp

func _texture_for_kind() -> Texture2D:
	match kind:
		"sparkling": return SPARKLING_TEX
		"blue": return BLUE_TEX
		"blood": return BLOOD_TEX
	return DRY_TEX

func _glow_color_for_kind() -> Color:
	match kind:
		"sparkling": return Color(0.7, 0.95, 1.0, 0.7)
		"blue": return Color(0.4, 0.7, 1.0, 0.5)
		"blood": return Color(1.0, 0.3, 0.3, 0.55)
	return Color(0, 0, 0, 0)

func _pulse_glow() -> void:
	if not is_instance_valid(glow):
		return
	var base: Color = glow.modulate
	var dim: Color = Color(base.r, base.g, base.b, base.a * 0.5)
	pulse = glow.create_tween().set_loops()
	pulse.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	pulse.tween_property(glow, "modulate", dim, 1.0)
	pulse.tween_property(glow, "modulate", base, 1.0)

func on_interact_complete(bot: Bot) -> void:
	if consumed:
		return
	consumed = true
	if pulse and pulse.is_valid():
		pulse.kill()
	var heal: int = int(round(float(bot.max_hp) * heal_pct))
	bot.hp = mini(bot.max_hp, bot.hp + heal)
	bot._update_hp_bar()

	if is_instance_valid(sprite):
		sprite.texture = DRY_TEX
		var t := sprite.create_tween()
		t.tween_property(sprite, "modulate", Color(0.6, 0.6, 0.6, 1.0), 0.4)
	if is_instance_valid(glow):
		var fade := glow.create_tween()
		fade.tween_property(glow, "modulate:a", 0.0, 0.5)

	drank.emit(self, heal, kind)
	interaction_complete.emit(self)
