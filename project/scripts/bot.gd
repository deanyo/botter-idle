class_name Bot
extends Actor

const BOT_TEX := preload("res://assets/tiles/player/spriggan_female.png")
const BODY_TEX := preload("res://assets/tiles/player/body/armor_mummy.png")
const WEAPON_DIR := "res://assets/tiles/player/weapons/"

# Map weapon item base_id -> overlay sprite filename. Test mode: any weapon
# uses battleaxe so we can verify the overlay+swing animation visually.
const WEAPON_OVERLAYS := {
	"rusty_dagger":   "battleaxe",
	"iron_dagger":    "battleaxe",
	"steel_dagger":   "battleaxe",
	"orcish_dagger":  "battleaxe",
	"elven_dagger":   "battleaxe",
	"short_sword":    "battleaxe",
	"iron_short_sword": "battleaxe",
	"long_sword":     "battleaxe",
	"iron_sword":     "battleaxe",
	"steel_sword":    "battleaxe",
	"falchion":       "battleaxe",
	"scimitar":       "battleaxe",
	"great_sword":    "battleaxe",
	"claymore":       "battleaxe",
}

# Weapon ids that should glow with a fire/magic light when equipped. Empty
# string = no light. Lights attach to the weapon_sprite child so they move
# with the bot and shimmer with the swing animation.
const WEAPON_LIGHTS := {
	"firestarter":    "firestarter",
	"hellfire":       "hellfire",
	"demon_blade":    "demon_blade",
	"flaming_sword":  "firestarter",
	"flaming_axe":    "firestarter",
}

var level: int = 1
var xp: int = 0
var gold: int = 0
var equipped: Dictionary = {}
var base_max_hp: int = 80
var base_atk: int = 6
var base_def: int = 2

var blessings: Array = []
var bonus_max_hp_pct: float = 0.0
var bonus_atk_pct: float = 0.0
var bonus_atk_flat: int = 0
var bonus_def_flat: int = 0
var hp_regen_per_sec: float = 0.0
var lifesteal_per_hit: int = 0
var loot_rarity_bonus: float = 0.0
var xp_gain_pct: float = 0.0
var _regen_accum: float = 0.0
var weapon_sprite: Sprite2D = null
var _weapon_swing_tween: Tween

func clear_blessings() -> void:
	blessings.clear()
	bonus_max_hp_pct = 0.0
	bonus_atk_pct = 0.0
	bonus_atk_flat = 0
	bonus_def_flat = 0
	hp_regen_per_sec = 0.0
	lifesteal_per_hit = 0
	loot_rarity_bonus = 0.0
	xp_gain_pct = 0.0

func grant_blessing(b: Dictionary) -> void:
	blessings.append(b)
	var k: String = String(b.get("kind", ""))
	var v: float = float(b.get("value", 0))
	match k:
		"atk_pct": bonus_atk_pct += v
		"atk_flat": bonus_atk_flat += int(v)
		"def_flat": bonus_def_flat += int(v)
		"hp_pct": bonus_max_hp_pct += v
		"hp_regen": hp_regen_per_sec += v
		"lifesteal": lifesteal_per_hit += int(v)
		"loot_rarity": loot_rarity_bonus += v
		"xp_gain": xp_gain_pct += v
	var prev_max: int = max_hp
	recompute_stats()
	hp = mini(max_hp, hp + (max_hp - prev_max))
	_update_hp_bar()

var _items_db_cache: Dictionary = {}

func apply_gear(items_db: Dictionary, equipped_instances: Dictionary) -> void:
	_items_db_cache = items_db
	equipped = equipped_instances.duplicate(true)
	recompute_stats()
	hp = max_hp
	_update_hp_bar()
	_refresh_weapon_overlay()

func recompute_stats() -> void:
	max_hp = base_max_hp + (level - 1) * 8
	atk = base_atk + (level - 1)
	defense = base_def + int(level / 3.0)

	var pct_hp: float = 0.0
	var pct_atk: float = 0.0
	for slot in equipped.keys():
		var inst: Variant = equipped[slot]
		if inst == null or typeof(inst) != TYPE_DICTIONARY:
			continue
		var base_id: String = String(inst.get("base_id", ""))
		if base_id == "" or not _items_db_cache.has(base_id):
			continue
		var item: Dictionary = _items_db_cache[base_id]
		max_hp += int(item.get("hp", 0))
		atk += int(item.get("atk", 0))
		defense += int(item.get("def", 0))

		var sums: Dictionary = AffixSystem.sum_affix_stats(inst.get("affixes", []))
		max_hp += int(sums.get("hp", 0))
		atk += int(sums.get("atk", 0))
		defense += int(sums.get("def", 0))
		pct_hp += float(sums.get("hp_pct", 0))
		pct_atk += float(sums.get("atk_pct", 0))

	atk += bonus_atk_flat
	defense += bonus_def_flat
	pct_hp += bonus_max_hp_pct
	pct_atk += bonus_atk_pct

	max_hp = int(round(max_hp * (1.0 + pct_hp / 100.0)))
	atk = int(round(atk * (1.0 + pct_atk / 100.0)))

func _ready() -> void:
	super._ready()
	# Render bot above all interactables (chests/altars/loot/portals which
	# default to z_index = 0). FX particles draw at z=6 so they still overlay.
	z_index = 5
	set_texture(BOT_TEX)
	# Layer the body armor sprite over the player base. Parented to rig so
	# it inherits attack_lunge / hit_squish / death_spin tweens. Lantern
	# removed — we want clean weapon + (eventually) shield slots only.
	var body := Sprite2D.new()
	body.texture = BODY_TEX
	body.centered = true
	body.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	body.z_index = 1
	rig.add_child(body)
	_refresh_weapon_overlay()

func _refresh_weapon_overlay() -> void:
	# Drop existing weapon sprite if any.
	if is_instance_valid(weapon_sprite):
		weapon_sprite.queue_free()
		weapon_sprite = null
	var wpn: Variant = equipped.get("weapon", null)
	if wpn == null or typeof(wpn) != TYPE_DICTIONARY:
		return
	var base_id: String = String(wpn.get("base_id", ""))
	var overlay_name: String = String(WEAPON_OVERLAYS.get(base_id, "long_sword"))
	var path: String = WEAPON_DIR + overlay_name + ".png"
	if not ResourceLoader.exists(path):
		return
	weapon_sprite = Sprite2D.new()
	weapon_sprite.texture = load(path)
	weapon_sprite.centered = true
	# Offset slightly down + right of rig origin — roughly where DCSS
	# hand_right paperdoll sits. Parented to rig so it inherits the bot's
	# lunge / squish / death tweens; weapon's own swing tween composes on top.
	weapon_sprite.position = Vector2(4, 2)
	weapon_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	weapon_sprite.z_index = 2
	rig.add_child(weapon_sprite)
	# Fire-tagged weapons emit their own light from the held sprite. Must
	# happen AFTER add_child so LightSpec.attach has a parent in the tree.
	var weapon_light_id: String = String(WEAPON_LIGHTS.get(base_id, ""))
	if weapon_light_id != "":
		LightSpec.attach(weapon_sprite, weapon_light_id, Vector2.ZERO)

func swing_weapon(toward: Vector2) -> void:
	if not is_instance_valid(weapon_sprite):
		return
	if _weapon_swing_tween and _weapon_swing_tween.is_valid():
		_weapon_swing_tween.kill()
	# Real swing: cock back, sweep through a wide arc, snap to rest.
	# Direction sign mirrors the arc for leftward attacks (weapon held in
	# right hand, so leftward swings go overhead the other way).
	var sign: float = 1.0 if toward.x >= 0 else -1.0
	var windup_rot: float = sign * deg_to_rad(35.0)   # cock back slightly
	var swing_rot: float = sign * -deg_to_rad(110.0)  # sweep across body
	weapon_sprite.rotation = 0.0
	weapon_sprite.scale = Vector2(1, 1)
	_weapon_swing_tween = weapon_sprite.create_tween()
	# Windup: slow ease-in.
	_weapon_swing_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_weapon_swing_tween.tween_property(weapon_sprite, "rotation", windup_rot, 0.07)
	# Swing-through: fast, exaggerated scale at peak for impact.
	_weapon_swing_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_weapon_swing_tween.tween_property(weapon_sprite, "rotation", swing_rot, 0.08)
	_weapon_swing_tween.parallel().tween_property(weapon_sprite, "scale", Vector2(1.35, 1.35), 0.08)
	# Recovery: ease back to neutral.
	_weapon_swing_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	_weapon_swing_tween.tween_property(weapon_sprite, "rotation", 0.0, 0.16)
	_weapon_swing_tween.parallel().tween_property(weapon_sprite, "scale", Vector2(1, 1), 0.16)

func _process(delta: float) -> void:
	if not is_alive or hp_regen_per_sec <= 0.0:
		return
	_regen_accum += delta * hp_regen_per_sec
	if _regen_accum >= 1.0:
		var ticks: int = int(_regen_accum)
		_regen_accum -= float(ticks)
		hp = mini(max_hp, hp + ticks)
		_update_hp_bar()

func take_damage(raw: int) -> int:
	# Grind/audit invincibility — set by main.gd when auto_grind is active.
	# Live playtest is unaffected.
	if DebugJump.bot_invincible:
		return 0
	return super.take_damage(raw)

func attempt_attack(other: Actor, delta: float) -> int:
	var dealt := super.attempt_attack(other, delta)
	if dealt > 0:
		# Swing the equipped weapon overlay toward the target.
		var toward: Vector2 = (other.position - position) if is_instance_valid(other) else Vector2.RIGHT
		swing_weapon(toward)
		if lifesteal_per_hit > 0:
			hp = mini(max_hp, hp + lifesteal_per_hit)
			_update_hp_bar()
	return dealt

func gain_xp(amount: int) -> void:
	var bonus: int = int(round(float(amount) * xp_gain_pct / 100.0))
	xp += amount + bonus
	while xp >= xp_to_next():
		xp -= xp_to_next()
		level += 1
		max_hp += 8
		atk += 1
		if level % 3 == 0:
			defense += 1
		# Level-up grants the new HP slice (the +8 from this level), but does
		# NOT fully heal — full-heal-on-level-up made HP feel infinite once
		# enemies were dropping fast enough to chain level-ups in combat.
		hp = mini(max_hp, hp + 8)
		_update_hp_bar()

func xp_to_next() -> int:
	return 20 + (level - 1) * 15
