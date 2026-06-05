class_name LootDrop
extends Interactable

const ITEM_TILE_DIR := "res://assets/tiles/items/"

const RARITY_GLOW := {
	"common": Color(0.85, 0.85, 0.85, 0.0),
	"uncommon": Color(0.4, 0.7, 1.0, 0.55),
	"rare": Color(1.0, 0.9, 0.3, 0.7),
	"epic": Color(1.0, 0.5, 0.2, 0.85),
	"legendary": Color(1.0, 0.3, 0.3, 1.0),
}

const RARITY_DURATIONS := {
	"common": 0.35,
	"uncommon": 0.4,
	"rare": 0.5,
	"epic": 0.6,
	"legendary": 0.8,
}

const RARITY_RANK := {
	"common": 0, "uncommon": 1, "rare": 2, "epic": 3, "legendary": 4,
}

var item_id: String = ""
var item: Dictionary = {}
var instance: Dictionary = {}

var sprite: Sprite2D
var glow: Sprite2D
var wobble: Tween
var fx: SpriteFX

func setup(id: String, def: Dictionary, at_cell: Vector2i) -> void:
	item_id = id
	item = def
	instance = {"base_id": id, "instance_id": "legacy", "affixes": []}
	place_at(at_cell)
	interact_duration = RARITY_DURATIONS.get(String(def.get("rarity", "common")), 0.4)

func setup_instance(inst: Dictionary, def: Dictionary, at_cell: Vector2i) -> void:
	instance = inst
	item_id = String(inst.get("base_id", ""))
	item = def
	place_at(at_cell)
	interact_duration = RARITY_DURATIONS.get(String(def.get("rarity", "common")), 0.4)

func _ready() -> void:
	if item.is_empty():
		return

	var rarity: String = String(item.get("rarity", "common"))
	var glow_color: Color = RARITY_GLOW.get(rarity, Color(1, 1, 1, 0))
	if glow_color.a > 0.01:
		glow = Sprite2D.new()
		glow.centered = true
		glow.position = Vector2(C.TILE_SIZE * 0.5, C.TILE_SIZE * 0.5)
		glow.texture = _make_glow_texture()
		glow.modulate = glow_color
		glow.scale = Vector2(2.0, 2.0)
		glow.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		add_child(glow)

	sprite = Sprite2D.new()
	sprite.centered = true
	sprite.position = Vector2(C.TILE_SIZE * 0.5, C.TILE_SIZE * 0.5)
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var tex: Texture2D = null
	var override: String = String(instance.get("tile_override", ""))
	if override != "":
		tex = load(ITEM_TILE_DIR + override)
	if tex == null:
		tex = load(ITEM_TILE_DIR + String(item.tile))
	if tex:
		sprite.texture = tex
	# Per-instance recolor — same shader the inventory cell + paperdoll
	# use. Items with `default_tint` authored in the item editor (or a
	# random tint rolled at drop time) display correctly on the floor
	# pickup. 2026-06-05.
	var recolor: ShaderMaterial = UITheme.recolor_material_for(instance)
	if recolor != null:
		sprite.material = recolor
	add_child(sprite)
	# Loot has no overlay stack — pass the sprite itself as both rig and sprite
	# so loot_pop tweens the sprite directly.
	fx = SpriteFX.new(sprite, sprite)

	_start_wobble()
	_pulse_glow()
	if rarity != "common":
		LightSpec.attach(self, "loot_" + rarity)

func _start_wobble() -> void:
	if not is_instance_valid(sprite):
		return
	wobble = sprite.create_tween().set_loops()
	wobble.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	var base_pos: Vector2 = sprite.position
	wobble.tween_property(sprite, "position", base_pos + Vector2(0, -3), 0.6)
	wobble.tween_property(sprite, "position", base_pos, 0.6)

func _pulse_glow() -> void:
	if not is_instance_valid(glow):
		return
	var base: Color = glow.modulate
	var dim: Color = Color(base.r, base.g, base.b, base.a * 0.4)
	var t := glow.create_tween().set_loops()
	t.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.tween_property(glow, "modulate", dim, 0.7)
	t.tween_property(glow, "modulate", base, 0.7)

func arc_from(start_world_center: Vector2, duration: float = 0.45) -> void:
	if not is_instance_valid(self):
		return
	var rest: Vector2 = position
	var start: Vector2 = start_world_center - Vector2(C.TILE_SIZE * 0.5, C.TILE_SIZE * 0.5)
	var apex: Vector2 = (start + rest) * 0.5 + Vector2(0, -22)
	position = start
	var t := create_tween()
	t.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(self, "position", apex, duration * 0.5)
	t.set_ease(Tween.EASE_IN)
	t.tween_property(self, "position", rest, duration * 0.5)

func play_pickup_then_free() -> void:
	if wobble and wobble.is_valid():
		wobble.kill()
	if fx:
		fx.loot_pop()
	var t := create_tween()
	t.tween_interval(0.18)
	t.tween_property(self, "modulate:a", 0.0, 0.12)
	t.tween_callback(queue_free)

# Bot loot filter — set per-run by the dungeon from the save state.
# Filter is the minimum rarity to pick up; below it the bot walks past.
# Static (one filter for all loot drops on the floor) so we don't reload
# save state in the AI hot path.
static var loot_filter_min_rank: int = 0

func should_skip(_bot: Bot) -> bool:
	var item_rarity: String = String(item.get("rarity", "common"))
	return RARITY_RANK.get(item_rarity, 0) < loot_filter_min_rank

static func _make_glow_texture() -> Texture2D:
	var img := Image.create(C.TILE_SIZE, C.TILE_SIZE, false, Image.FORMAT_RGBA8)
	var center := Vector2(C.TILE_SIZE * 0.5, C.TILE_SIZE * 0.5)
	var max_dist: float = C.TILE_SIZE * 0.5
	for y in C.TILE_SIZE:
		for x in C.TILE_SIZE:
			var d: float = Vector2(x, y).distance_to(center)
			var t: float = clampf(1.0 - d / max_dist, 0.0, 1.0)
			var alpha: float = t * t
			img.set_pixel(x, y, Color(1, 1, 1, alpha))
	return ImageTexture.create_from_image(img)
