class_name Bot
extends Actor

const BOT_TEX := preload("res://assets/tiles/player/bot_base.png")
const LANTERN_TEX := preload("res://assets/tiles/player/bot_lantern.png")

var level: int = 1
var xp: int = 0
var gold: int = 0
var equipped: Dictionary = {}
var base_max_hp: int = 50
var base_atk: int = 5
var base_def: int = 1

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
	set_texture(BOT_TEX)
	# Layer the lantern over the player base. Sprite is centered=false in Actor,
	# matching tile origin, so the overlay aligns 1:1 by default.
	var lantern := Sprite2D.new()
	lantern.texture = LANTERN_TEX
	lantern.centered = false
	lantern.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	lantern.z_index = 1
	add_child(lantern)

func _process(delta: float) -> void:
	if not is_alive or hp_regen_per_sec <= 0.0:
		return
	_regen_accum += delta * hp_regen_per_sec
	if _regen_accum >= 1.0:
		var ticks: int = int(_regen_accum)
		_regen_accum -= float(ticks)
		hp = mini(max_hp, hp + ticks)
		_update_hp_bar()

func attempt_attack(other: Actor, delta: float) -> int:
	var dealt := super.attempt_attack(other, delta)
	if dealt > 0 and lifesteal_per_hit > 0:
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
