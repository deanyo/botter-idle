class_name Bot
extends Actor

const BOT_TEX := preload("res://assets/tiles/player/spriggan_female.png")

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
	if _halo_sprite != null and is_instance_valid(_halo_sprite):
		_halo_sprite.queue_free()
	_halo_sprite = null
	remove_status("blessed")

func grant_blessing(b: Dictionary) -> void:
	blessings.append(b)
	var k: String = String(b.get("kind", ""))
	var v: float = float(b.get("value", 0))
	match k:
		"atk_pct": bonus_atk_pct += v
		"atk_flat": bonus_atk_flat += int(v)
		"def_flat": bonus_def_flat += int(v)
		"hp_pct": bonus_max_hp_pct += v
		# hp_regen is re-derived from blessings array inside recompute_stats
		# so we don't write it here directly (avoids double-counting).
		"lifesteal": lifesteal_per_hit += int(v)
		"loot_rarity": loot_rarity_bonus += v
		"xp_gain": xp_gain_pct += v
	var prev_max: int = max_hp
	recompute_stats()
	hp = mini(max_hp, hp + (max_hp - prev_max))
	_update_hp_bar()
	# DCSS-style HALO: a per-god tinted aura behind the rig (visible
	# while moving) plus a `blessed` status icon in the buff bar
	# (visible while reading the HUD). Reuses the soft radial glow
	# from LootDrop. Multiple blessings stack — newest tint wins on
	# the rig (the buff bar already shows all of them via _statuses).
	var god: String = String(b.get("god", ""))
	if god != "":
		_apply_halo(god)
	# Mark the bot as blessed for the duration of the run. duration<=0
	# = persistent until cleared (clear_blessings re-fires this path).
	add_status("blessed", 0.0)

const _HALO_COLORS := {
	"trog":            Color(1.0, 0.30, 0.20, 0.55),
	"okawaru":         Color(0.85, 0.75, 0.40, 0.50),
	"zin":             Color(1.0, 1.0, 0.70, 0.65),
	"elyvilon":        Color(0.60, 1.0, 0.70, 0.50),
	"vehumet":         Color(0.70, 0.40, 1.0, 0.60),
	"kikubaaqudgha":   Color(0.40, 0.20, 0.60, 0.60),
	"sif_muna":        Color(0.40, 0.70, 1.0, 0.55),
	"beogh":           Color(0.90, 0.50, 0.20, 0.55),
	"makhleb":         Color(1.0, 0.40, 0.10, 0.65),
	"yredelemnul":     Color(0.50, 0.10, 0.40, 0.60),
	"the_shining_one": Color(1.0, 0.95, 0.50, 0.80),
	"lugonu":          Color(0.30, 0.10, 0.30, 0.55),
	"jiyva":           Color(0.40, 0.85, 0.30, 0.55),
	"fedhas":          Color(0.30, 0.85, 0.40, 0.55),
	"cheibriados":     Color(0.50, 0.50, 0.40, 0.50),
	"xom":             Color(1.0, 0.40, 0.80, 0.65),
	"ashenzari":       Color(0.70, 0.65, 0.45, 0.55),
	"dithmenos":       Color(0.20, 0.20, 0.30, 0.65),
	"gozag":           Color(1.0, 0.85, 0.30, 0.60),
	"qazlal":          Color(0.60, 0.70, 0.95, 0.60),
	"nemelex":         Color(0.90, 0.40, 0.80, 0.60),
	"ru":              Color(0.90, 0.85, 0.70, 0.50),
}

var _halo_sprite: Sprite2D = null

func _apply_halo(god: String) -> void:
	if rig == null:
		return
	if _halo_sprite == null or not is_instance_valid(_halo_sprite):
		_halo_sprite = Sprite2D.new()
		_halo_sprite.texture = LootDrop._make_glow_texture()
		_halo_sprite.centered = true
		_halo_sprite.scale = Vector2(2.4, 2.4)
		_halo_sprite.z_index = -2  # below shadow (z=-1) and sprite (z=0)
		_halo_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		rig.add_child(_halo_sprite)
		# Slow alpha pulse for life. Adds .6s recovery feel without
		# being distracting like a tween-bounce.
		var pulse := _halo_sprite.create_tween().set_loops()
		pulse.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		var color: Color = _HALO_COLORS.get(god, Color(1, 1, 1, 0.5))
		_halo_sprite.modulate = color
		var dim: Color = Color(color.r, color.g, color.b, color.a * 0.55)
		pulse.tween_property(_halo_sprite, "modulate", dim, 1.6)
		pulse.tween_property(_halo_sprite, "modulate", color, 1.6)
	else:
		# Re-bless: update tint to the newest god (visible feedback).
		var c: Color = _HALO_COLORS.get(god, _halo_sprite.modulate)
		_halo_sprite.modulate = c

var _items_db_cache: Dictionary = {}
# Snapshot of save.bot_upgrades at run start. Used by recompute_stats to
# stack upgrade ranks on top of base + gear stats. Set by apply_gear.
var upgrade_state: Dictionary = {}

func apply_gear(items_db: Dictionary, equipped_instances: Dictionary, save_state: Dictionary = {}) -> void:
	_items_db_cache = items_db
	equipped = equipped_instances.duplicate(true)
	upgrade_state = save_state
	# Run-stable upgrade contributions to "blessing-style" stats. recompute
	# doesn't touch these (blessings can keep adding mid-run), so we apply
	# them once here at run start and let the rest of the run's flow stack
	# on top.
	if not upgrade_state.is_empty():
		loot_rarity_bonus = BotUpgrades.total_for_stat(upgrade_state, "loot_rarity_bonus")
	recompute_stats()
	hp = max_hp
	_update_hp_bar()
	_refresh_gear_overlays()

# Swap an inventory item into its slot. Returns the displaced instance
# (or null if the slot was empty), so the caller can re-insert it into the
# inventory at whichever segment makes sense. Stat recompute preserves
# current HP delta (no cheesing full-heal by re-equipping).
func equip_from_inventory(inst: Dictionary) -> Variant:
	if typeof(inst) != TYPE_DICTIONARY:
		return null
	var base_id: String = String(inst.get("base_id", ""))
	if base_id == "" or not _items_db_cache.has(base_id):
		return null
	var slot: String = String(_items_db_cache[base_id].get("slot", ""))
	if slot == "":
		return null
	# items.json declares slot=="ring"; the equipped dict uses one `ring`
	# slot (collapsed from ring1/ring2 — see save_state._migrate).
	if slot == "ring":
		slot = "ring"
	var displaced: Variant = equipped.get(slot, null)
	equipped[slot] = inst.duplicate(true)
	var prev_max: int = max_hp
	recompute_stats()
	# Preserve the player's HP delta — equip does not heal or hurt.
	hp = clampi(hp + (max_hp - prev_max), 0, max_hp)
	_update_hp_bar()
	_refresh_gear_overlays()
	return displaced

func recompute_stats() -> void:
	# Permanent gold-sink upgrades stack on top of base level-scaled stats
	# (and stay on top of gear). Cached snapshot so we don't reload save
	# every recompute. Apply BEFORE gear so % multipliers (none yet, but
	# planned for later affixes) compound correctly.
	var up_hp: float = BotUpgrades.total_for_stat(upgrade_state, "max_hp") if not upgrade_state.is_empty() else 0.0
	var up_atk: float = BotUpgrades.total_for_stat(upgrade_state, "atk") if not upgrade_state.is_empty() else 0.0
	var up_def: float = BotUpgrades.total_for_stat(upgrade_state, "def") if not upgrade_state.is_empty() else 0.0
	max_hp = base_max_hp + (level - 1) * 8 + int(up_hp)
	atk = base_atk + (level - 1) + int(up_atk)
	defense = base_def + int(level / 3.0) + int(up_def)

	var pct_hp: float = 0.0
	var pct_atk: float = 0.0
	# Affix stats from the simplified 6-affix system. Crit/Haste are summed
	# across all gear slots; gear-regen stacks with altar blessings.
	var crit_sum: float = 0.0
	var haste_sum: float = 0.0
	var gear_regen: float = 0.0
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
		# Legacy %-affixes (from pre-migration saves that somehow slip through).
		pct_hp += float(sums.get("hp_pct", 0))
		pct_atk += float(sums.get("atk_pct", 0))
		crit_sum += float(sums.get("crit_chance", 0))
		haste_sum += float(sums.get("atk_speed_pct", 0))
		gear_regen += float(sums.get("hp_regen", 0))

	atk += bonus_atk_flat
	defense += bonus_def_flat
	pct_hp += bonus_max_hp_pct
	pct_atk += bonus_atk_pct

	max_hp = int(round(max_hp * (1.0 + pct_hp / 100.0)))
	atk = int(round(atk * (1.0 + pct_atk / 100.0)))

	# Crit chance is a flat percentage (sum across gear + Quick Reflexes
	# upgrade), capped at 75 so fights still feel like fights. Haste is
	# capped at 200 so attack interval can't drop below 0.2s (degenerate-
	# flicker territory).
	var up_crit: float = BotUpgrades.total_for_stat(upgrade_state, "crit_chance") if not upgrade_state.is_empty() else 0.0
	crit_chance = clampf(crit_sum + up_crit, 0.0, 75.0)
	var haste_pct: float = clampf(haste_sum, 0.0, 200.0)
	attack_interval = 0.6 / (1.0 + haste_pct / 100.0)
	# Gear regen + blessing regen + flavor-tag regen. Blessings already
	# added to hp_regen_per_sec via grant_blessing, so we re-derive from
	# scratch: count gear here + blessing array + tag stacks.
	hp_regen_per_sec = gear_regen
	for b in blessings:
		if String(b.get("kind", "")) == "hp_regen":
			hp_regen_per_sec += float(b.get("value", 0))
	# `vitality` flavor tag grants +1 HP/sec per source (amulet, etc).
	# Stacks across all worn slots, same as other defender-side tags.
	for slot in _DEF_SLOTS:
		var inst: Variant = equipped.get(slot, null)
		if inst == null or typeof(inst) != TYPE_DICTIONARY:
			continue
		var bid: String = String(inst.get("base_id", ""))
		if bid == "" or not _items_db_cache.has(bid):
			continue
		if "vitality" in _items_db_cache[bid].get("flavor_tags", []):
			hp_regen_per_sec += 1.0

var _gear_sprites: Dictionary = {}  # slot_id → Sprite2D, for swing/light hooks

func _ready() -> void:
	super._ready()
	# Render bot above all interactables (chests/altars/loot/portals which
	# default to z_index = 0). FX particles draw at z=6 so they still overlay.
	z_index = 5
	set_texture(BOT_TEX)
	_refresh_gear_overlays()

func _refresh_gear_overlays() -> void:
	# Drop any existing overlay sprites (preserve the base bot texture which
	# lives on `self`, not in `_gear_sprites`).
	for slot in _gear_sprites.keys():
		var s: Variant = _gear_sprites[slot]
		if s is Sprite2D and is_instance_valid(s):
			s.queue_free()
	_gear_sprites.clear()
	weapon_sprite = null
	# Build the rig overlays directly under `rig` so they inherit the bot's
	# lunge / squish / death tweens. We don't reuse the renderer's Node2D
	# wrapper because the bot's base sprite is `self`, not a child.
	for slot_id in PaperdollRenderer.SLOT_Z.keys():
		var path: String = PaperdollRenderer._resolve_overlay(slot_id, equipped, _items_db_cache)
		if path == "":
			continue
		var sprite := Sprite2D.new()
		sprite.texture = load(path)
		sprite.centered = true
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		sprite.position = PaperdollRenderer.SLOT_OFFSETS.get(slot_id, Vector2.ZERO)
		sprite.z_index = int(PaperdollRenderer.SLOT_Z[slot_id])
		rig.add_child(sprite)
		_gear_sprites[slot_id] = sprite
		# Rarity tint + glow: a gold-rendered legendary scimitar previously
		# read identical to a common blue scimitar once equipped. Tint the
		# overlay's modulate by rarity (subtle — keeps the art legible) and
		# attach a soft pulsing halo behind epic+ items so they read as
		# "obviously a special weapon" at a glance.
		_apply_rarity_decor(sprite, equipped.get(slot_id, null), slot_id)
	weapon_sprite = _gear_sprites.get("weapon", null)
	# Fire-tagged weapons emit their own light from the held sprite.
	if weapon_sprite != null:
		var wpn: Variant = equipped.get("weapon", null)
		var base_id: String = "" if wpn == null or typeof(wpn) != TYPE_DICTIONARY else String(wpn.get("base_id", ""))
		var weapon_light_id: String = String(WEAPON_LIGHTS.get(base_id, ""))
		if weapon_light_id != "":
			LightSpec.attach(weapon_sprite, weapon_light_id, Vector2.ZERO)

# Subtle modulate per rarity. Common stays neutral so the art reads as-is;
# higher rarities pick up a light wash in the rarity color. Strengths
# tuned by eye — too strong washes out the silhouette, too weak doesn't
# read at the dungeon zoom level.
const _RARITY_TINT_STRENGTH := {
	"common": 0.0, "uncommon": 0.18, "rare": 0.28, "epic": 0.38, "legendary": 0.50,
}
const _RARITY_GLOW_RARITIES := { "epic": true, "legendary": true }

func _apply_rarity_decor(sprite: Sprite2D, inst: Variant, slot_id: String) -> void:
	if inst == null or typeof(inst) != TYPE_DICTIONARY:
		return
	var base_id: String = String(inst.get("base_id", ""))
	if base_id == "" or not _items_db_cache.has(base_id):
		return
	var rarity: String = String(_items_db_cache[base_id].get("rarity", "common"))
	var strength: float = float(_RARITY_TINT_STRENGTH.get(rarity, 0.0))
	if strength > 0.0:
		var col: Color = UITheme.rarity_color(rarity)
		# Lerp from white → rarity color by `strength`. White preserves the
		# base sprite art; the lerp keeps brightness up rather than darkening.
		sprite.modulate = Color(
			lerp(1.0, col.r, strength),
			lerp(1.0, col.g, strength),
			lerp(1.0, col.b, strength),
			1.0,
		)
	# Glow halo: same texture LootDrop uses for floor sparkle. Behind the
	# weapon sprite (z=-1 within the overlay), softly pulses. Only for the
	# weapon slot for now — ATK is the primary "what is the bot wielding"
	# read, and 5 simultaneous halos on the rig would be visual noise.
	if slot_id == "weapon" and _RARITY_GLOW_RARITIES.has(rarity):
		var glow := Sprite2D.new()
		glow.texture = LootDrop._make_glow_texture()
		glow.centered = true
		glow.scale = Vector2(1.6, 1.6)
		glow.z_index = -1
		glow.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		var col_g: Color = UITheme.rarity_color(rarity)
		var base_alpha: float = 0.55 if rarity == "legendary" else 0.40
		glow.modulate = Color(col_g.r, col_g.g, col_g.b, base_alpha)
		sprite.add_child(glow)
		var dim: Color = Color(col_g.r, col_g.g, col_g.b, base_alpha * 0.55)
		var pulse := glow.create_tween().set_loops()
		pulse.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		pulse.tween_property(glow, "modulate", dim, 1.4)
		pulse.tween_property(glow, "modulate", Color(col_g.r, col_g.g, col_g.b, base_alpha), 1.4)

func combat_label() -> String:
	return "bot"

func combat_weapon_id() -> String:
	var wpn: Variant = equipped.get("weapon", null)
	if wpn == null or typeof(wpn) != TYPE_DICTIONARY:
		return ""
	return String(wpn.get("base_id", ""))

func combat_weapon_tags() -> Array:
	var wpn: Variant = equipped.get("weapon", null)
	if wpn == null or typeof(wpn) != TYPE_DICTIONARY:
		return []
	var base_id: String = String(wpn.get("base_id", ""))
	if base_id == "" or not _items_db_cache.has(base_id):
		return []
	return _items_db_cache[base_id].get("flavor_tags", [])

# Defender-worn tags — armor / shield / amulet / rings provide the
# defensive flavor tags (thorns, reflective, harm, rage). Helms also
# count for completeness. Multiple sources stack — a thorns shield +
# thorns armor will return damage twice per hit, by design.
const _DEF_SLOTS := ["armor", "shield", "helm", "amulet", "ring", "boots"]

func combat_defense_tags() -> Array:
	var out: Array = []
	for slot in _DEF_SLOTS:
		var inst: Variant = equipped.get(slot, null)
		if inst == null or typeof(inst) != TYPE_DICTIONARY:
			continue
		var base_id: String = String(inst.get("base_id", ""))
		if base_id == "" or not _items_db_cache.has(base_id):
			continue
		for t in _items_db_cache[base_id].get("flavor_tags", []):
			if not (t in out):
				out.append(t)
	return out

func swing_weapon(toward: Vector2) -> void:
	if not is_instance_valid(weapon_sprite):
		return
	if _weapon_swing_tween and _weapon_swing_tween.is_valid():
		_weapon_swing_tween.kill()
	# Three flavors based on target direction:
	#   - Mostly-horizontal: classic side sweep (cock back, swing across).
	#   - Mostly-vertical down: overhead chop (raise weapon, slam down).
	#   - Mostly-vertical up: upward thrust (pull back, jab up).
	# Threshold ~60° from horizontal — outside that we treat as vertical.
	var ax: float = absf(toward.x)
	var ay: float = absf(toward.y)
	if ay > ax * 1.7:
		if toward.y > 0:
			_play_swing_overhead_chop()
		else:
			_play_swing_upward_thrust()
	else:
		_play_swing_horizontal(toward)

func _play_swing_horizontal(toward: Vector2) -> void:
	# Direction sign mirrors the arc for leftward attacks (weapon held in
	# right hand, so leftward swings go overhead the other way).
	var sign: float = 1.0 if toward.x >= 0 else -1.0
	var windup_rot: float = sign * deg_to_rad(35.0)   # cock back slightly
	var swing_rot: float = sign * -deg_to_rad(110.0)  # sweep across body
	weapon_sprite.rotation = 0.0
	weapon_sprite.scale = Vector2(1, 1)
	weapon_sprite.position = Vector2.ZERO
	_weapon_swing_tween = weapon_sprite.create_tween()
	_weapon_swing_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_weapon_swing_tween.tween_property(weapon_sprite, "rotation", windup_rot, 0.07)
	_weapon_swing_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_weapon_swing_tween.tween_property(weapon_sprite, "rotation", swing_rot, 0.08)
	_weapon_swing_tween.parallel().tween_property(weapon_sprite, "scale", Vector2(1.35, 1.35), 0.08)
	_weapon_swing_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	_weapon_swing_tween.tween_property(weapon_sprite, "rotation", 0.0, 0.16)
	_weapon_swing_tween.parallel().tween_property(weapon_sprite, "scale", Vector2(1, 1), 0.16)

func _play_swing_overhead_chop() -> void:
	# Raise weapon high (large negative-Y position offset, rotate to vertical),
	# slam down past neutral, recover. Reads as a chop targeting below.
	weapon_sprite.rotation = 0.0
	weapon_sprite.scale = Vector2(1, 1)
	weapon_sprite.position = Vector2.ZERO
	_weapon_swing_tween = weapon_sprite.create_tween()
	# Windup: pull up + tilt back.
	_weapon_swing_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_weapon_swing_tween.tween_property(weapon_sprite, "rotation", deg_to_rad(-90.0), 0.10)
	_weapon_swing_tween.parallel().tween_property(weapon_sprite, "position", Vector2(0, -8), 0.10)
	# Slam down: fast, scale impact.
	_weapon_swing_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_weapon_swing_tween.tween_property(weapon_sprite, "rotation", deg_to_rad(45.0), 0.07)
	_weapon_swing_tween.parallel().tween_property(weapon_sprite, "position", Vector2(0, 4), 0.07)
	_weapon_swing_tween.parallel().tween_property(weapon_sprite, "scale", Vector2(1.3, 1.3), 0.07)
	# Recover.
	_weapon_swing_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	_weapon_swing_tween.tween_property(weapon_sprite, "rotation", 0.0, 0.14)
	_weapon_swing_tween.parallel().tween_property(weapon_sprite, "position", Vector2.ZERO, 0.14)
	_weapon_swing_tween.parallel().tween_property(weapon_sprite, "scale", Vector2(1, 1), 0.14)

func _play_swing_upward_thrust() -> void:
	# Pull weapon back/down then jab upward. Reads as an upward stab.
	weapon_sprite.rotation = 0.0
	weapon_sprite.scale = Vector2(1, 1)
	weapon_sprite.position = Vector2.ZERO
	_weapon_swing_tween = weapon_sprite.create_tween()
	# Windup: pull down + tilt down.
	_weapon_swing_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_weapon_swing_tween.tween_property(weapon_sprite, "rotation", deg_to_rad(40.0), 0.08)
	_weapon_swing_tween.parallel().tween_property(weapon_sprite, "position", Vector2(0, 4), 0.08)
	# Thrust up: fast, exaggerated upward motion.
	_weapon_swing_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_weapon_swing_tween.tween_property(weapon_sprite, "rotation", deg_to_rad(-20.0), 0.07)
	_weapon_swing_tween.parallel().tween_property(weapon_sprite, "position", Vector2(0, -10), 0.07)
	_weapon_swing_tween.parallel().tween_property(weapon_sprite, "scale", Vector2(1.2, 1.4), 0.07)
	# Recover.
	_weapon_swing_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	_weapon_swing_tween.tween_property(weapon_sprite, "rotation", 0.0, 0.14)
	_weapon_swing_tween.parallel().tween_property(weapon_sprite, "position", Vector2.ZERO, 0.14)
	_weapon_swing_tween.parallel().tween_property(weapon_sprite, "scale", Vector2(1, 1), 0.14)

func _process(delta: float) -> void:
	if not is_alive or hp_regen_per_sec <= 0.0:
		return
	_regen_accum += delta * hp_regen_per_sec
	if _regen_accum >= 1.0:
		var ticks: int = int(_regen_accum)
		_regen_accum -= float(ticks)
		hp = mini(max_hp, hp + ticks)
		_update_hp_bar()

func take_damage(raw: int, attacker: Actor = null) -> int:
	# Grind/audit invincibility — set by main.gd when auto_grind is active.
	# Live playtest is unaffected.
	if DebugJump.bot_invincible:
		return 0
	return super.take_damage(raw, attacker)

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
