class_name Altar
extends Interactable

const ALTAR_DIR := "res://assets/tiles/features/"

const ALTAR_TEXTURES := {
	"trog":             preload("res://assets/tiles/features/altar_trog.png"),
	"okawaru":          preload("res://assets/tiles/features/altar_okawaru.png"),
	"zin":              preload("res://assets/tiles/features/altar_zin.png"),
	"elyvilon":         preload("res://assets/tiles/features/altar_elyvilon.png"),
	"vehumet":          preload("res://assets/tiles/features/altar_vehumet.png"),
	"kikubaaqudgha":    preload("res://assets/tiles/features/altar_kikubaaqudgha.png"),
	"sif_muna":         preload("res://assets/tiles/features/altar_sif_muna.png"),
	"beogh":            preload("res://assets/tiles/features/altar_beogh.png"),
	"makhleb":          preload("res://assets/tiles/features/altar_makhleb.png"),
	"yredelemnul":      preload("res://assets/tiles/features/altar_yredelemnul.png"),
	"the_shining_one":  preload("res://assets/tiles/features/altar_the_shining_one.png"),
	"lugonu":           preload("res://assets/tiles/features/altar_lugonu.png"),
	"jiyva":            preload("res://assets/tiles/features/altar_jiyva.png"),
	"fedhas":           preload("res://assets/tiles/features/altar_fedhas.png"),
	"cheibriados":      preload("res://assets/tiles/features/altar_cheibriados.png"),
	"xom":              preload("res://assets/tiles/features/altar_xom.png"),
	"ashenzari":        preload("res://assets/tiles/features/altar_ashenzari.png"),
	"dithmenos":        preload("res://assets/tiles/features/altar_dithmenos.png"),
	"gozag":            preload("res://assets/tiles/features/altar_gozag.png"),
	"qazlal":           preload("res://assets/tiles/features/altar_qazlal.png"),
	"nemelex":          preload("res://assets/tiles/features/altar_nemelex.png"),
	"ru":               preload("res://assets/tiles/features/altar_ru.png"),
}

# Each god offers a single run-ephemeral blessing tied to their lore. We
# keep blessings within the established 5 stat kinds (hp/atk/def/hp_pct/atk_pct)
# plus the extras already wired (hp_regen, lifesteal, loot_rarity, xp_gain) —
# adding new effect kinds is a separate beat. Some gods reuse a stat with a
# distinct theme/value so player feels the variety in flavour even where the
# mechanic overlaps.
const BLESSINGS := {
	"trog":             { "name": "Trog's Rage",          "kind": "atk_pct",     "value": 20.0, "desc": "+20% ATK" },
	"okawaru":          { "name": "Okawaru's Boon",       "kind": "atk_flat",    "value": 15.0, "desc": "+15 ATK +5 DEF", "extra": {"kind": "def_flat", "value": 5.0} },
	"zin":              { "name": "Zin's Light",          "kind": "hp_pct",      "value": 30.0, "desc": "+30% Max HP" },
	"elyvilon":         { "name": "Elyvilon's Mercy",     "kind": "hp_regen",    "value": 3.0,  "desc": "Regen 3 HP/sec" },
	"vehumet":          { "name": "Vehumet's Power",      "kind": "loot_rarity", "value": 25.0, "desc": "+25% loot rarity" },
	"kikubaaqudgha":    { "name": "Kiku's Hunger",        "kind": "lifesteal",   "value": 4.0,  "desc": "Lifesteal 4 HP/hit" },
	"sif_muna":         { "name": "Sif Muna's Wisdom",    "kind": "xp_gain",     "value": 50.0, "desc": "+50% XP gain" },
	"beogh":            { "name": "Beogh's Warband",      "kind": "atk_pct",     "value": 25.0, "desc": "+25% ATK (orc warlord)" },
	"makhleb":          { "name": "Makhleb's Frenzy",     "kind": "lifesteal",   "value": 6.0,  "desc": "Lifesteal 6 HP/hit (chaos)" },
	"yredelemnul":      { "name": "Yred's Reaping",       "kind": "atk_flat",    "value": 25.0, "desc": "+25 ATK (death)" },
	"the_shining_one":  { "name": "TSO's Halo",           "kind": "def_flat",    "value": 15.0, "desc": "+15 DEF +20% Max HP", "extra": {"kind": "hp_pct", "value": 20.0} },
	"lugonu":           { "name": "Lugonu's Corruption",  "kind": "atk_pct",     "value": 35.0, "desc": "+35% ATK (abyss)" },
	"jiyva":            { "name": "Jiyva's Slime",        "kind": "hp_regen",    "value": 5.0,  "desc": "Regen 5 HP/sec (ooze)" },
	"fedhas":           { "name": "Fedhas's Garden",      "kind": "hp_pct",      "value": 40.0, "desc": "+40% Max HP (verdant)" },
	"cheibriados":      { "name": "Cheibriados's Patience","kind": "def_flat",   "value": 30.0, "desc": "+30 DEF (slow & steady)" },
	"xom":              { "name": "Xom's Whim",           "kind": "atk_pct",     "value": 50.0, "desc": "+50% ATK (chaotic)" },
	"ashenzari":        { "name": "Ashenzari's Sight",    "kind": "loot_rarity", "value": 40.0, "desc": "+40% loot rarity (cursed sight)" },
	"dithmenos":        { "name": "Dithmenos's Shadow",   "kind": "atk_flat",    "value": 20.0, "desc": "+20 ATK +10 DEF (shadow)", "extra": {"kind": "def_flat", "value": 10.0} },
	"gozag":            { "name": "Gozag's Gold",         "kind": "loot_rarity", "value": 60.0, "desc": "+60% loot rarity (greed)" },
	"qazlal":           { "name": "Qazlal's Storm",       "kind": "atk_pct",     "value": 30.0, "desc": "+30% ATK (storm caller)" },
	"nemelex":          { "name": "Nemelex's Deck",       "kind": "loot_rarity", "value": 50.0, "desc": "+50% loot rarity (cards)" },
	"ru":               { "name": "Ru's Sacrifice",       "kind": "atk_pct",     "value": 75.0, "desc": "+75% ATK -25% Max HP", "extra": {"kind": "hp_pct", "value": -25.0} },
}

signal blessed(altar: Altar, blessing: Dictionary)

var sprite: Sprite2D
var glow: Sprite2D
var pulse: Tween
var god: String = "trog"

func _init() -> void:
	interact_duration = 1.8

func setup(at_cell: Vector2i, god_id: String = "") -> void:
	place_at(at_cell)
	if god_id == "" or not ALTAR_TEXTURES.has(god_id):
		var keys: Array = ALTAR_TEXTURES.keys()
		god_id = keys[randi_range(0, keys.size() - 1)]
	god = god_id

func _ready() -> void:
	sprite = Sprite2D.new()
	sprite.centered = true
	sprite.position = Vector2(C.TILE_SIZE * 0.5, C.TILE_SIZE * 0.5)
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.texture = ALTAR_TEXTURES.get(god)
	add_child(sprite)

	glow = Sprite2D.new()
	glow.centered = true
	glow.position = Vector2(C.TILE_SIZE * 0.5, C.TILE_SIZE * 0.5)
	glow.texture = LootDrop._make_glow_texture()
	glow.modulate = _glow_color_for_god()
	glow.scale = Vector2(2.6, 2.6)
	glow.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(glow)
	move_child(glow, 0)
	LightSpec.attach(self, "altar_" + god)
	_pulse_glow()

func _glow_color_for_god() -> Color:
	match god:
		"trog":             return Color(1.0, 0.3, 0.2, 0.6)
		"okawaru":          return Color(0.8, 0.7, 0.4, 0.55)
		"zin":              return Color(1.0, 1.0, 0.7, 0.7)
		"elyvilon":         return Color(0.6, 1.0, 0.7, 0.55)
		"vehumet":          return Color(0.7, 0.4, 1.0, 0.65)
		"kikubaaqudgha":    return Color(0.4, 0.2, 0.6, 0.65)
		"sif_muna":         return Color(0.4, 0.7, 1.0, 0.6)
		"beogh":            return Color(0.9, 0.5, 0.2, 0.6)
		"makhleb":          return Color(1.0, 0.4, 0.1, 0.7)
		"yredelemnul":      return Color(0.5, 0.1, 0.4, 0.65)
		"the_shining_one":  return Color(1.0, 0.95, 0.5, 0.85)
		"lugonu":           return Color(0.6, 0.3, 0.7, 0.7)
		"jiyva":            return Color(0.7, 1.0, 0.4, 0.6)
		"fedhas":           return Color(0.5, 0.9, 0.4, 0.55)
		"cheibriados":      return Color(0.5, 0.6, 0.7, 0.55)
		"xom":              return Color(1.0, 0.5, 1.0, 0.7)
		"ashenzari":        return Color(0.7, 0.7, 1.0, 0.55)
		"dithmenos":        return Color(0.2, 0.2, 0.4, 0.6)
		"gozag":            return Color(1.0, 0.85, 0.2, 0.8)
		"qazlal":           return Color(0.6, 0.7, 0.95, 0.65)
		"nemelex":          return Color(0.9, 0.4, 0.8, 0.65)
		"ru":               return Color(0.9, 0.85, 0.7, 0.55)
	return Color(1, 1, 1, 0.5)

func _pulse_glow() -> void:
	if not is_instance_valid(glow):
		return
	var base: Color = glow.modulate
	var dim: Color = Color(base.r, base.g, base.b, base.a * 0.4)
	pulse = glow.create_tween().set_loops()
	pulse.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	pulse.tween_property(glow, "modulate", dim, 1.2)
	pulse.tween_property(glow, "modulate", base, 1.2)

func should_skip(bot: Bot) -> bool:
	for b in bot.blessings:
		if String(b.get("god", "")) == god:
			return true
	return false

func on_interact_complete(bot: Bot) -> void:
	if consumed:
		return
	consumed = true
	if pulse and pulse.is_valid():
		pulse.kill()
	var blessing: Dictionary = BLESSINGS.get(god, {}).duplicate(true)
	blessing["god"] = god
	bot.grant_blessing(blessing)
	if blessing.has("extra"):
		var extra: Dictionary = blessing.extra
		extra["god"] = god
		bot.grant_blessing(extra)
	if is_instance_valid(sprite):
		var burst := sprite.create_tween()
		burst.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		burst.tween_property(sprite, "scale", Vector2(1.5, 1.5), 0.18)
		burst.tween_property(sprite, "scale", Vector2.ONE, 0.32)
	if is_instance_valid(glow):
		var fade := glow.create_tween()
		fade.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		fade.tween_property(glow, "scale", Vector2(5.0, 5.0), 0.3)
		fade.parallel().tween_property(glow, "modulate:a", 0.0, 0.6)
	blessed.emit(self, blessing)
	interaction_complete.emit(self)
