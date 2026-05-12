class_name Portal
extends Interactable

const GATEWAY_DIR := "res://assets/tiles/gateways/"

# DCSS-style portals. Stepping on a portal instantly swaps the current floor
# to a themed mini-floor with a richer loot table. Floor counter does NOT
# advance — the portal floor *replaces* the current floor; descending its
# stairs continues the run normally.
const PORTAL_KINDS := {
	"sewer":   { "tile": "sewer_portal_rusted.png", "biome": "swamp",     "name": "Sewer",    "loot_bias": 1, "color": Color(0.45, 0.7, 0.3, 0.7) },
	"bailey":  { "tile": "bailey_portal.png",       "biome": "orc",       "name": "Bailey",   "loot_bias": 1, "color": Color(0.9, 0.6, 0.3, 0.7) },
	"bazaar":  { "tile": "bazaar_portal.png",       "biome": "vaults",    "name": "Bazaar",   "loot_bias": 2, "color": Color(0.9, 0.85, 0.4, 0.85) },
	"ossuary": { "tile": "ossuary_portal.png",      "biome": "crypt",     "name": "Ossuary",  "loot_bias": 1, "color": Color(0.9, 0.85, 0.7, 0.65) },
	"wizlab":  { "tile": "lab_portal.png",          "biome": "elf",       "name": "Wizlab",   "loot_bias": 2, "color": Color(0.6, 0.4, 1.0, 0.8) },
	"trove":   { "tile": "trove_portal.png",        "biome": "vaults",    "name": "Trove",    "loot_bias": 2, "color": Color(1.0, 0.7, 0.3, 0.85) },
	"zig":     { "tile": "zig_portal.png",          "biome": "zot",       "name": "Ziggurat", "loot_bias": 2, "color": Color(1.0, 0.5, 0.7, 0.85) },
	"hive":    { "tile": "hive_portal.png",         "biome": "hive",      "name": "Hive",     "loot_bias": 1, "color": Color(1.0, 0.85, 0.3, 0.7) },
}

signal entered(portal: Portal, kind: String, biome_id: String, loot_bias: int)

var sprite: Sprite2D
var glow: Sprite2D
var pulse: Tween
var kind: String = "sewer"

func _init() -> void:
	interact_duration = 1.0

func setup(at_cell: Vector2i, kind_id: String = "") -> void:
	place_at(at_cell)
	if kind_id == "" or not PORTAL_KINDS.has(kind_id):
		var keys: Array = PORTAL_KINDS.keys()
		kind_id = keys[randi_range(0, keys.size() - 1)]
	kind = kind_id

func _ready() -> void:
	var def: Dictionary = PORTAL_KINDS.get(kind, {})
	sprite = Sprite2D.new()
	sprite.centered = true
	sprite.position = Vector2(C.TILE_SIZE * 0.5, C.TILE_SIZE * 0.5)
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var tex_path: String = GATEWAY_DIR + String(def.get("tile", "portal.png"))
	if ResourceLoader.exists(tex_path):
		sprite.texture = load(tex_path)
	add_child(sprite)

	glow = Sprite2D.new()
	glow.centered = true
	glow.position = Vector2(C.TILE_SIZE * 0.5, C.TILE_SIZE * 0.5)
	glow.texture = LootDrop._make_glow_texture()
	glow.modulate = def.get("color", Color(0.7, 0.7, 1.0, 0.8))
	glow.scale = Vector2(3.0, 3.0)
	glow.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(glow)
	move_child(glow, 0)
	_pulse_glow()

func _pulse_glow() -> void:
	if not is_instance_valid(glow):
		return
	var base: Color = glow.modulate
	var dim: Color = Color(base.r, base.g, base.b, base.a * 0.5)
	pulse = glow.create_tween().set_loops()
	pulse.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	pulse.tween_property(glow, "modulate", dim, 0.7)
	pulse.tween_property(glow, "modulate", base, 0.7)

func on_interact_complete(_bot: Bot) -> void:
	if consumed:
		return
	consumed = true
	if pulse and pulse.is_valid():
		pulse.kill()
	var def: Dictionary = PORTAL_KINDS.get(kind, {})
	if is_instance_valid(sprite):
		var spin := sprite.create_tween()
		spin.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		spin.tween_property(sprite, "scale", Vector2(0.1, 0.1), 0.25)
	if is_instance_valid(glow):
		var fade := glow.create_tween()
		fade.tween_property(glow, "scale", Vector2(8.0, 8.0), 0.4)
		fade.parallel().tween_property(glow, "modulate:a", 0.0, 0.5)
	entered.emit(self, kind, String(def.get("biome", "dungeon")), int(def.get("loot_bias", 1)))
	interaction_complete.emit(self)

static func random_kind(rng: RandomNumberGenerator) -> String:
	var keys: Array = PORTAL_KINDS.keys()
	return String(keys[rng.randi() % keys.size()])
