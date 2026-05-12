class_name LightSpec
extends RefCounted

const C := preload("res://scripts/constants.gd")

const SPECS := {
	"torch": {
		"color": Color(1.0, 0.7, 0.35),
		"energy": 0.9, "range": 4.0,
		"flicker": "fast", "flicker_amp": 0.25
	},
	"flame_yellow": {
		"color": Color(1.0, 0.85, 0.4),
		"energy": 0.95, "range": 4.0,
		"flicker": "fast", "flicker_amp": 0.3
	},
	"flame_orange": {
		"color": Color(1.0, 0.55, 0.2),
		"energy": 1.0, "range": 4.5,
		"flicker": "fast", "flicker_amp": 0.32
	},
	"flame_red": {
		"color": Color(1.0, 0.35, 0.15),
		"energy": 1.05, "range": 4.5,
		"flicker": "fast", "flicker_amp": 0.35
	},
	"campfire": {
		"color": Color(1.0, 0.6, 0.25),
		"energy": 1.1, "range": 5.0,
		"flicker": "fast", "flicker_amp": 0.3
	},
	"lantern": {
		"color": Color(1.0, 0.9, 0.55),
		"energy": 0.85, "range": 4.5,
		"flicker": "slow", "flicker_amp": 0.1
	},
	"lantern_gold": {
		"color": Color(1.0, 0.85, 0.35),
		"energy": 0.95, "range": 5.0,
		"flicker": "slow", "flicker_amp": 0.12
	},
	"lava": {
		"color": Color(1.0, 0.4, 0.1),
		"energy": 1.2, "range": 4.5,
		"flicker": "fast", "flicker_amp": 0.35
	},
	"ice": {
		"color": Color(0.55, 0.8, 1.0),
		"energy": 0.45, "range": 3.0,
		"flicker": "slow", "flicker_amp": 0.15
	},
	"crystal_blue": {
		"color": Color(0.55, 0.8, 1.0),
		"energy": 0.6, "range": 3.5,
		"flicker": "slow", "flicker_amp": 0.2
	},
	"crystal_purple": {
		"color": Color(0.85, 0.55, 1.0),
		"energy": 0.6, "range": 3.5,
		"flicker": "pulse", "flicker_amp": 0.25
	},
	"crystal_green": {
		"color": Color(0.55, 1.0, 0.7),
		"energy": 0.6, "range": 3.5,
		"flicker": "slow", "flicker_amp": 0.2
	},
	"crystal": {
		"color": Color(0.7, 0.9, 1.0),
		"energy": 0.6, "range": 3.5,
		"flicker": "slow", "flicker_amp": 0.2
	},
	"sigil": {
		"color": Color(0.6, 0.4, 1.0),
		"energy": 0.55, "range": 2.5,
		"flicker": "pulse", "flicker_amp": 0.3
	},
	"mushroom_glow": {
		"color": Color(0.65, 1.0, 0.5),
		"energy": 0.45, "range": 2.8,
		"flicker": "slow", "flicker_amp": 0.18
	},
	"slime_glow": {
		"color": Color(0.7, 1.0, 0.4),
		"energy": 0.4, "range": 2.5,
		"flicker": "pulse", "flicker_amp": 0.25
	},
	"altar_trog":          { "color": Color(1.0, 0.3, 0.2), "energy": 0.7, "range": 3.5, "flicker": "slow", "flicker_amp": 0.2 },
	"altar_okawaru":       { "color": Color(0.95, 0.85, 0.4), "energy": 0.7, "range": 3.5, "flicker": "slow", "flicker_amp": 0.2 },
	"altar_zin":           { "color": Color(1.0, 1.0, 0.85), "energy": 0.85, "range": 4.0, "flicker": "slow", "flicker_amp": 0.15 },
	"altar_elyvilon":      { "color": Color(0.7, 1.0, 0.75), "energy": 0.7, "range": 3.5, "flicker": "slow", "flicker_amp": 0.2 },
	"altar_vehumet":       { "color": Color(0.8, 0.4, 1.0), "energy": 0.8, "range": 4.0, "flicker": "pulse", "flicker_amp": 0.3 },
	"altar_kikubaaqudgha": { "color": Color(0.5, 0.25, 0.7), "energy": 0.65, "range": 3.5, "flicker": "pulse", "flicker_amp": 0.25 },
	"altar_sif_muna":      { "color": Color(0.5, 0.75, 1.0), "energy": 0.7, "range": 3.5, "flicker": "slow", "flicker_amp": 0.2 },
	"fountain_sparkling":  { "color": Color(0.7, 0.95, 1.0), "energy": 0.65, "range": 3.0, "flicker": "slow", "flicker_amp": 0.2 },
	"fountain_blue":       { "color": Color(0.4, 0.7, 1.0), "energy": 0.5, "range": 2.8, "flicker": "slow", "flicker_amp": 0.2 },
	"fountain_blood":      { "color": Color(1.0, 0.3, 0.3), "energy": 0.55, "range": 2.8, "flicker": "slow", "flicker_amp": 0.2 },
	"chest_gold":          { "color": Color(1.0, 0.85, 0.4), "energy": 0.6, "range": 3.0, "flicker": "slow", "flicker_amp": 0.15 },
	"chest_orange":        { "color": Color(1.0, 0.55, 0.2), "energy": 0.7, "range": 3.2, "flicker": "slow", "flicker_amp": 0.2 },
	"loot_uncommon":       { "color": Color(0.4, 0.7, 1.0), "energy": 0.45, "range": 2.0, "flicker": "slow", "flicker_amp": 0.15 },
	"loot_rare":           { "color": Color(1.0, 0.9, 0.3), "energy": 0.6, "range": 2.5, "flicker": "slow", "flicker_amp": 0.2 },
	"loot_epic":           { "color": Color(1.0, 0.55, 0.2), "energy": 0.75, "range": 3.0, "flicker": "pulse", "flicker_amp": 0.25 },
	"loot_legendary":      { "color": Color(1.0, 0.3, 0.3), "energy": 0.95, "range": 3.5, "flicker": "pulse", "flicker_amp": 0.3 },
}

static func attach(parent: Node2D, spec_id: String, offset_px: Vector2 = Vector2(C.TILE_SIZE * 0.5, C.TILE_SIZE * 0.5)) -> PointLight2D:
	var spec: Dictionary = SPECS.get(spec_id, {})
	if spec.is_empty():
		return null
	var light := PointLight2D.new()
	light.texture = _radial_texture()
	light.texture_scale = float(spec.get("range", 3.0))
	light.offset = offset_px
	light.energy = float(spec.get("energy", 0.7))
	light.color = spec.get("color", Color(1, 1, 1))
	light.range_z_min = -1024
	light.range_z_max = 1024
	light.shadow_enabled = true
	light.shadow_filter = Light2D.SHADOW_FILTER_PCF5
	light.shadow_filter_smooth = 1.5
	parent.add_child(light)
	_apply_flicker(light, String(spec.get("flicker", "none")), float(spec.get("flicker_amp", 0.0)))
	return light

static var _cached_radial: Texture2D = null

static func _radial_texture() -> Texture2D:
	if _cached_radial != null:
		return _cached_radial
	var size_px: int = 96
	var img := Image.create(size_px, size_px, false, Image.FORMAT_RGBA8)
	var center := Vector2(size_px * 0.5, size_px * 0.5)
	var max_d: float = size_px * 0.5
	for y in size_px:
		for x in size_px:
			var d: float = Vector2(x, y).distance_to(center)
			var t: float = clampf(1.0 - d / max_d, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, t * t))
	_cached_radial = ImageTexture.create_from_image(img)
	return _cached_radial

static func _apply_flicker(light: PointLight2D, mode: String, amp: float) -> void:
	if mode == "none" or amp <= 0.0:
		return
	var base: float = light.energy
	var lo: float = base * (1.0 - amp)
	var hi: float = base * (1.0 + amp)
	var t := light.create_tween().set_loops()
	t.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	match mode:
		"fast":
			t.tween_property(light, "energy", hi, 0.15)
			t.tween_property(light, "energy", lo, 0.18)
			t.tween_property(light, "energy", base, 0.12)
		"slow":
			t.tween_property(light, "energy", lo, 1.1)
			t.tween_property(light, "energy", hi, 1.1)
		"pulse":
			t.tween_property(light, "energy", hi, 0.6)
			t.tween_property(light, "energy", lo, 0.6)
