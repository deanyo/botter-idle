class_name Actor
extends Node2D

const C := preload("res://scripts/constants.gd")

signal died(actor: Actor)
signal damaged(actor: Actor, amount: int)

@export var max_hp: int = 10
@export var atk: int = 2
@export var defense: int = 0
@export var move_speed: float = 4.0

var hp: int
var cell: Vector2i
var target_cell: Vector2i
var path: PackedVector2Array = PackedVector2Array()
var path_index: int = 0
var is_alive: bool = true
var attack_cooldown: float = 0.0
# Per-actor attack cadence (seconds between swings). Was a const 0.6 across
# all actors; now mutable so the bot can apply Haste affixes to shorten it.
# Enemies leave the default 0.6 for now.
var attack_interval: float = 0.6
# 0..100. Bot reads from Crit affixes; enemies stay at 0.
var crit_chance: float = 0.0
const CRIT_MULTIPLIER := 1.5
# Optional reference to the dungeon grid for per-cell terrain effects
# (e.g. water slow). Set externally; nil means no terrain modifiers.
var terrain_grid: Array = []

# rig parents the visual stack (base sprite + any overlays like armor / weapon)
# so SpriteFX can lunge / squish / flash the whole figure at once. HP bars stay
# direct children of Actor — they shouldn't bob with the lunge.
var rig: Node2D
var sprite: Sprite2D
var fx: SpriteFX
var hp_bar: ColorRect
var hp_bar_bg: ColorRect
# Visual scaling for "big" creatures. Logical layer (cell, hp, attack) is
# unaffected — these only modify how the sprite renders.
var visual_scale: float = 1.0
var visual_anchor: String = "centre"
# Facing direction: -1.0 (left) or +1.0 (right). DCSS player sprites
# are drawn right-facing, so +1 is the natural state. Updated from
# `step_movement` based on path direction; only changes on
# horizontal movement so vertical-only paths preserve the last
# horizontal facing rather than snapping to a default.
var _facing_x: float = 1.0

# DCSS-style ENCH layer — visible status icons above the rig. Drives no
# mechanics; mechanics drive it. Each status: {id, expires_at, sprite}.
# duration <= 0 = persistent until remove_status(id). Ticked from the
# scene's _process (Bot+Enemy both inherit Actor and tick).
var _status_layer: Node2D = null
var _statuses: Dictionary = {}  # id → {expires_at, sprite, dot, next_tick_at}
const _StatusOverlay := preload("res://scripts/status_overlay.gd")
const _ActorShadow := preload("res://scripts/actor_shadow.gd")
var _shadow: Node2D = null

# Anti-streak crit accumulator for the `precision` flavor tag. Resets
# on a successful crit; otherwise grows by +5%/swing toward a +50% cap
# above the base crit_chance. Bot reads this; mundane actors stay at 0.
var _precision_streak: int = 0

# `rage` flavor tag: each kill by this actor adds a stack (cap +30%
# atk, 6s refresh window). Stacks expire silently when window lapses
# — checked at attempt_attack time, no separate tick needed.
var _rage_stacks: int = 0
var _rage_expires_at: float = 0.0

# Combat-state buckets for the rest of the wired flavor tags. These
# all share the "expire silently when window lapses" pattern so we
# don't need a per-actor tick for any of them. Initialized lazy.
# `arcane`: every Nth swing fires a magic bonus. Counter, not timer.
var _arcane_swing_count: int = 0
# `stealth`: bot's NEXT attack lands a +25% bonus while bot has
# the `stealthy` status. Status is granted at floor-build time
# (or when the bot has gone N seconds without taking damage). Cleared
# on first hit landed. We just check has_status("stealthy") at hit
# time — no extra state needed here.
# `dual`: 15% chance to deal a second hit on the same target. We
# guard against infinite recursion via _dual_attacking.
var _dual_attacking: bool = false

func _ready() -> void:
	hp = max_hp
	# rig sits at the tile center so SpriteFX can rotate / scale around the
	# figure's pivot (death spin, attack lunge squish). All visual children —
	# base sprite, body armor, weapon overlay — attach to rig at offset (0, 0)
	# so they inherit lunge / flash / death tweens together.
	rig = Node2D.new()
	rig.position = Vector2(C.TILE_SIZE * 0.5, C.TILE_SIZE * 0.5)
	add_child(rig)
	# Shadow draws first so it's beneath everything else in the rig.
	# Offset to the figure's feet (~10px below pivot, since DCSS sprites
	# pivot at center but stand on the lower portion of the tile).
	if VideoSettings.is_effect_enabled("shadow"):
		_shadow = _ActorShadow.new()
		_shadow.position = Vector2(0, 10)
		_shadow.z_index = -1
		rig.add_child(_shadow)
	sprite = Sprite2D.new()
	sprite.centered = true
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	rig.add_child(sprite)
	fx = SpriteFX.new(rig, sprite)
	hp_bar_bg = ColorRect.new()
	hp_bar_bg.color = Color(0.1, 0.0, 0.0, 0.9)
	hp_bar_bg.size = Vector2(C.TILE_SIZE - 4, 3)
	hp_bar_bg.position = Vector2(2, -5)
	add_child(hp_bar_bg)
	hp_bar = ColorRect.new()
	hp_bar.color = Color(0.2, 0.9, 0.3, 0.95)
	hp_bar.size = Vector2(C.TILE_SIZE - 4, 3)
	hp_bar.position = Vector2(2, -5)
	add_child(hp_bar)

func set_texture(tex: Texture2D) -> void:
	if rig == null:
		rig = Node2D.new()
		rig.position = Vector2(C.TILE_SIZE * 0.5, C.TILE_SIZE * 0.5)
		add_child(rig)
	if sprite == null:
		sprite = Sprite2D.new()
		sprite.centered = true
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		rig.add_child(sprite)
		fx = SpriteFX.new(rig, sprite)
	sprite.texture = tex
	if fx == null:
		fx = SpriteFX.new(rig, sprite)

func apply_visual_scale(scale: float, anchor: String = "centre", z: int = 0) -> void:
	# Caller-provided scale already accounts for miniboss/champion compounding.
	# We cap here as a safety net.
	scale = clampf(scale, 0.5, 2.5)
	visual_scale = scale
	visual_anchor = anchor
	if rig == null or sprite == null:
		return
	# Scale the rig so any child overlays scale together. Sprite stays at (0,0)
	# inside the rig — the rig's own position handles tile centering.
	# Compose with `_facing_x` so a left-facing rig scaled to 2x stays
	# left-facing (otherwise apply_visual_scale would clobber the flip).
	rig.scale = Vector2(scale * _facing_x, scale)
	# Keep SpriteFX in sync so its base_scale snapshot stays current.
	if fx != null:
		fx.update_base_scale(rig.scale)
	if anchor == "ground":
		# For ground anchor, shift the rig up so the sprite's bottom edge stays
		# pinned to the cell's bottom — looks natural for upright creatures.
		var half_tile: float = C.TILE_SIZE * 0.5
		var overflow: float = (scale - 1.0) * half_tile
		rig.position = Vector2(half_tile, half_tile - overflow)
	else:
		rig.position = Vector2(C.TILE_SIZE * 0.5, C.TILE_SIZE * 0.5)
	# Sync the new rest position so attack_lunge returns to the right
	# offset for ground-anchored big creatures.
	if fx != null:
		fx.update_base_position(rig.position)
	sprite.position = Vector2.ZERO
	if z != 0:
		sprite.z_index = z

func _set_facing(facing: float) -> void:
	if facing == _facing_x:
		return
	_facing_x = facing
	if rig != null:
		# Build the authoritative resting scale from `visual_scale` rather
		# than reading rig.scale — if a tween is mid-flight (attack_lunge
		# squashes Y to 0.85 then back to 1.0 over ~0.18s), reading
		# rig.scale here would snapshot a transient stretched/squished
		# value into base_scale and the next tween would "rest" at that
		# corrupted scale. Over a long session the bot would gradually
		# shrink to a sliver — see HANDOVER for the bug report.
		var rest := Vector2(visual_scale * _facing_x, visual_scale)
		rig.scale = rest
		if fx != null:
			fx.update_base_scale(rest)

func place_at(c: Vector2i) -> void:
	cell = c
	target_cell = c
	position = Vector2(c.x * C.TILE_SIZE, c.y * C.TILE_SIZE)

func set_path(p: PackedVector2Array) -> void:
	path = p
	path_index = 0
	if path.size() > 0:
		target_cell = Vector2i(int(path[0].x / C.TILE_SIZE), int(path[0].y / C.TILE_SIZE))

func step_movement(delta: float) -> void:
	if not is_alive:
		return
	if path.size() == 0 or path_index >= path.size():
		return
	var goal: Vector2 = path[path_index]
	var dir: Vector2 = goal - position
	var dist: float = dir.length()
	var step: float = move_speed * C.TILE_SIZE * delta
	# Update facing on horizontal movement. Threshold avoids flicker
	# when the bot is walking straight up/down (tiny x jitter from
	# float math wouldn't otherwise flip it). Vertical-only paths keep
	# the last horizontal facing.
	#
	# DCSS spriggan_female draws the weapon hand on viewer-left, so the
	# "natural" rig appears to lead with shield on the right side. We
	# want the weapon hand to LEAD when moving — i.e. flip when going
	# right (so weapon ends up on viewer-right, leading) and stay
	# default when going left (weapon on viewer-left, leading).
	if absf(dir.x) > 0.5:
		_set_facing(-1.0 if dir.x > 0.0 else 1.0)
	# Water slows us down (50% speed). Lava is full-speed (we want to cross
	# quickly), ice is full-speed for v1.
	if not terrain_grid.is_empty() and cell.y >= 0 and cell.y < terrain_grid.size():
		var row_size: int = terrain_grid[0].size() if terrain_grid.size() > 0 else 0
		if cell.x >= 0 and cell.x < row_size:
			if terrain_grid[cell.y][cell.x] == C.T_WATER:
				# `flying` flavor on worn gear ignores water slow
				# (boots / wings of flight pattern from DCSS).
				if not ("flying" in combat_defense_tags()):
					step *= 0.5
	if dist <= step:
		position = goal
		cell = Vector2i(int(goal.x / C.TILE_SIZE), int(goal.y / C.TILE_SIZE))
		path_index += 1
		if path_index < path.size():
			var next: Vector2 = path[path_index]
			target_cell = Vector2i(int(next.x / C.TILE_SIZE), int(next.y / C.TILE_SIZE))
	else:
		position += dir.normalized() * step

func take_damage(raw: int, attacker: Actor = null, damage_type: String = "") -> int:
	# Item-overhaul v2 (2026-06-04). damage_type is the new typed-damage
	# hint — physical / fire / cold / lightning / holy / poison / dark.
	# Empty string falls through to the legacy flavor-tag-based path so
	# enemy attacks (which don't yet pass damage_type) still mitigate via
	# fire_res / cold_res / earth / etc.
	#
	# New PoE-style defenses:
	#   - evasion (% chance to fully dodge any incoming hit) → 0 damage
	#   - armor (flat) subtracts from PHYSICAL damage only
	#   - resistances[damage_type] subtract a percentage from typed damage
	# Old `defense` field is kept (mirrors armor for log compat).
	if damage_type == "":
		damage_type = "physical"  # default for legacy callers
	# Evasion roll first — applies to any damage type. Resolves the hit
	# entirely (no subsequent armor / resist math).
	if "evasion" in self:
		var eva: float = float(self.evasion)
		if eva > 0.0 and randf() * 100.0 < eva:
			if fx and is_alive:
				fx.hit_squish()
			return 0
	# Defender-side flavor tag pre-checks. Order matters: full-negate
	# rolls beat any multiplier; resistances apply before harm; element
	# resists (fire_res/cold_res/poison_res) check the attacker's
	# weapon tags so a fire dragon hitting a fire_res-armored bot does
	# half damage.
	var def_tags: Array = combat_defense_tags()
	# Atk-side tags (read so resists know what type of attack this is).
	var atk_tags: Array = []
	if attacker != null and is_instance_valid(attacker):
		atk_tags = attacker.combat_weapon_tags()
	if not def_tags.is_empty():
		# `footwork` — 8% chance to fully evade. Same shape as reflective
		# but more common and explicitly tied to dexterity / boots.
		if "footwork" in def_tags and randf() < 0.08:
			if fx and is_alive:
				fx.hit_squish()
			return 0
		if "reflective" in def_tags and randf() < 0.10:
			if fx and is_alive:
				fx.hit_squish()
			return 0
		# Element resists (defender-worn). 50% reduction matches DCSS
		# rF+ / rC+ pattern. Also grants immunity to the matching DoT
		# status (handled in _apply_dot_status).
		if "fire_res" in def_tags and "fire" in atk_tags:
			raw = int(round(float(raw) * 0.5))
		if "cold_res" in def_tags and "cold" in atk_tags:
			raw = int(round(float(raw) * 0.5))
		# `earth`: -15% from any non-elemental, non-magical attack.
		# "Physical" = anything without elemental/arcane/holy/dark tags.
		if "earth" in def_tags:
			var is_physical: bool = true
			for t in ["fire", "cold", "elemental", "arcane", "holy", "dark", "thunderous"]:
				if t in atk_tags:
					is_physical = false
					break
			if is_physical:
				raw = int(round(float(raw) * 0.85))
		# `willpower`: -25% from arcane / elemental / magical attackers.
		if "willpower" in def_tags:
			for t in ["arcane", "elemental", "fire", "cold"]:
				if t in atk_tags:
					raw = int(round(float(raw) * 0.75))
					break
		# `warding`: -20% from boss / miniboss attackers (anti-elite armor).
		if "warding" in def_tags and attacker is Enemy:
			var e: Enemy = attacker as Enemy
			if e.is_boss or e.is_miniboss:
				raw = int(round(float(raw) * 0.8))
		# `acrobat`: when below 30% HP, +20% def. Translates to ~17%
		# damage reduction at the take_damage layer.
		if "acrobat" in def_tags and max_hp > 0 and float(hp) / float(max_hp) <= 0.30:
			raw = int(round(float(raw) * 0.83))
		# `guardian`: flat -10% damage taken. Smaller than other resists
		# but always-on so it stacks well as a backup armor.
		if "guardian" in def_tags:
			raw = int(round(float(raw) * 0.9))
		if "harm" in def_tags:
			raw = int(round(float(raw) * 1.25))
	# Type-aware mitigation. Physical → flat armor subtraction. Elemental
	# → percent resistance from the defender's resistances dict (defaults
	# to 0 when the actor doesn't declare one — enemies with no resistances
	# field eat full damage). Floor of 1 so a 100%-resisted hit still pings
	# (gameplay-feel; nobody should ignore a hit completely except evasion).
	var dmg: int
	if damage_type == "physical":
		dmg = maxi(1, raw - defense)
	else:
		var resist_pct: float = 0.0
		if "resistances" in self:
			resist_pct = float(self.resistances.get(damage_type, 0))
		dmg = maxi(1, int(round(float(raw) * (1.0 - resist_pct / 100.0))))
	hp -= dmg
	damaged.emit(self, dmg)
	_update_hp_bar()
	if fx and is_alive:
		fx.hit_squish()
	# `thorns` returns 15% of (post-defense) damage to the attacker. Done
	# AFTER our HP update so the attacker can't kill us with their own
	# thorns response. Skip if thorns kills us — the attacker still takes
	# the return chunk regardless.
	if attacker != null and is_instance_valid(attacker) and attacker.is_alive and not def_tags.is_empty():
		if "thorns" in def_tags:
			var thorn_dmg: int = maxi(1, int(round(float(dmg) * 0.15)))
			attacker.hp = maxi(0, attacker.hp - thorn_dmg)
			attacker.damaged.emit(attacker, thorn_dmg)
			attacker._update_hp_bar()
			if attacker.hp <= 0:
				attacker.is_alive = false
				attacker._play_death_then_emit()
		# `crystal`: smaller passive thorn that fires regardless. 5% of
		# raw is a gentle constant bleed when an attacker keeps poking.
		if "crystal" in def_tags:
			var c_dmg: int = maxi(1, int(round(float(dmg) * 0.05)))
			attacker.hp = maxi(0, attacker.hp - c_dmg)
			attacker.damaged.emit(attacker, c_dmg)
			attacker._update_hp_bar()
			if attacker.hp <= 0 and attacker.is_alive:
				attacker.is_alive = false
				attacker._play_death_then_emit()
	if hp <= 0:
		is_alive = false
		_play_death_then_emit()
	return dmg

# Bot overrides to expose flavor_tags from worn ARMOR/SHIELD/AMULET (as
# opposed to weapon, which is `combat_weapon_tags`). Rationale:
# attacker tags (vampiric, fire, holy) live on the weapon; defender
# tags (thorns, reflective, harm, vitality, rage, psychic) live on
# armor/shield/amulet. Mundane actors return [].
func combat_defense_tags() -> Array:
	return []

# Find one cell-adjacent (8-direction) live actor to `near`, excluding
# `near` itself and `self`. Used by the `thunderous` chain mechanic.
# Returns null if nothing adjacent. Cheap O(siblings) — actor_layer has
# the bot + ~5-15 enemies, so the linear scan is fine.
func _find_adjacent_actor(near: Actor, skip: Dictionary = {}) -> Actor:
	if not is_instance_valid(near):
		return null
	var parent: Node = get_parent()
	if parent == null:
		return null
	for child in parent.get_children():
		if child is Actor and child != near and child != self:
			var c: Actor = child as Actor
			if not c.is_alive:
				continue
			if skip.has(c.get_instance_id()):
				continue
			var dx: int = absi(c.cell.x - near.cell.x)
			var dy: int = absi(c.cell.y - near.cell.y)
			if dx <= 1 and dy <= 1 and (dx + dy) > 0:
				return c
	return null

func attempt_attack(other: Actor, delta: float) -> int:
	# `stunned`: attacker skips this swing entirely. Sound enchant
	# triggers it on a defender, so when that defender becomes the
	# attacker on its next tick, it loses one swing. The status
	# auto-expires on its tick — we just bail here.
	if has_status("stunned"):
		attack_cooldown -= delta
		return 0
	attack_cooldown -= delta
	if attack_cooldown > 0.0:
		return 0
	attack_cooldown = attack_interval
	if fx:
		var toward: Vector2 = (other.position - position) if is_instance_valid(other) else Vector2.RIGHT
		# Face the target before swinging so the held weapon appears on the
		# correct side (vs reaching across the body to hit a left-side foe).
		# Threshold matches step_movement so vertical-only adjacency keeps
		# the prior horizontal facing. Inverted vs intuition because the
		# DCSS player sprite holds the weapon on viewer-left — flipping
		# when target is right puts the weapon on viewer-right toward target.
		if absf(toward.x) > 0.5:
			_set_facing(-1.0 if toward.x > 0.0 else 1.0)
		fx.attack_lunge(toward)
	# Flavor-tag pre-attack adjustments. Read both weapon (attacker) and
	# defense (worn-armor) tags once for the whole hit.
	var tags: Array = combat_weapon_tags()
	var def_tags: Array = combat_defense_tags()
	var crit_bonus: float = 0.0
	var dmg_mult: float = 1.0
	if not tags.is_empty():
		if "precision" in tags:
			crit_bonus = clampf(float(_precision_streak) * 5.0, 0.0, 50.0)
		var target_id: String = other.combat_label() if is_instance_valid(other) else ""
		if "holy" in tags and _StatusOverlay.enemy_matches_any(target_id, _StatusOverlay.HOLY_HATES):
			dmg_mult *= 1.5
		if "dragon_bane" in tags and _StatusOverlay.enemy_matches_any(target_id, _StatusOverlay.DRAGON_HATES):
			dmg_mult *= 1.5
		# `brutal`: +25% damage against targets below 30% HP (executioner).
		if "brutal" in tags and is_instance_valid(other) and other.max_hp > 0:
			if float(other.hp) / float(other.max_hp) <= 0.3:
				dmg_mult *= 1.25
		# `cold`: +20% damage to already-frozen targets (the chance to
		# freeze itself is post-attack so the freeze applies for the
		# NEXT swing's bonus, not this one).
		if "cold" in tags and is_instance_valid(other) and other.has_status("frozen"):
			dmg_mult *= 1.20
		# `elemental`: bonus damage scales with character level. Weapon
		# grows with the wielder. Bot's level via cast; enemies skip
		# (no level concept beyond the floor multiplier).
		if "elemental" in tags and self is Bot:
			var lvl: int = (self as Bot).level
			dmg_mult *= 1.0 + 0.01 * float(lvl)
		# `arcane`: every 4th swing fires a +50% magic burst.
		if "arcane" in tags:
			_arcane_swing_count += 1
			if _arcane_swing_count >= 4:
				_arcane_swing_count = 0
				dmg_mult *= 1.5
		# `demon`: inverse of holy — +25% damage vs HOLY_HATES targets
		# (undead/demon already favored by holy; demon stacks with it
		# rather than gating). Lore: a demonic weapon hates the same
		# things holy ones do, but for different reasons.
		var target_id_d: String = other.combat_label() if is_instance_valid(other) else ""
		if "demon" in tags and _StatusOverlay.enemy_matches_any(target_id_d, _StatusOverlay.HOLY_HATES):
			dmg_mult *= 1.25
		# `ponderous`: heavy weapon — +10% damage but slower swing
		# (swing-rate handled in recompute_stats; here just the dmg).
		if "ponderous" in tags:
			dmg_mult *= 1.10
		# `stealth` / first-strike: bot under "stealthy" status lands
		# +25% damage. Status is a one-shot — clear after the hit
		# below. Granted at floor build via the stealthy flavor on gear
		# (see Bot._refresh_stealthy_status).
		if has_status("stealthy"):
			dmg_mult *= 1.25
	# `harm` (defender-worn): +25% damage dealt and +25% damage taken
	# (the receive side is in take_damage). Applies regardless of weapon.
	if "harm" in def_tags:
		dmg_mult *= 1.25
	# `rage` (defender-worn): stacking +5% atk per kill in last 6s, max
	# +30%. State maintained on attacker; cleared on expiry in
	# attempt_attack so we don't need a separate tick.
	if not def_tags.is_empty() and "rage" in def_tags:
		var now_r: float = float(Time.get_ticks_msec()) / 1000.0
		if now_r > _rage_expires_at:
			_rage_stacks = 0
		dmg_mult *= 1.0 + 0.05 * float(_rage_stacks)

	# Item-overhaul v2: weapon damage is a roll over [damage_min,
	# damage_max] of weapon_damage_type. extra_damage adds typed bonus
	# rolls (one per element a +X-Y affix has loaded). The base swing's
	# Str scaling (+2% per stat point above baseline) lives here so it
	# multiplies the final pre-crit total.
	var dmin: int = int(self.get("damage_min")) if "damage_min" in self else atk
	var dmax: int = int(self.get("damage_max")) if "damage_max" in self else atk
	var base_type: String = String(self.get("weapon_damage_type")) if "weapon_damage_type" in self else "physical"
	# Per-type accumulators: one int per element key the swing actually
	# touches. Keyed by damage_type so the take_damage loop below routes
	# armor vs resistance properly.
	var typed: Dictionary = {}
	typed[base_type] = randi_range(dmin, max(dmin, dmax))
	# Extra damage from "of Embers"-style affixes — kept on the bot via
	# recompute_stats. Each element's {min, max} bounds get rolled here
	# so a single weapon can hit three types in one swing.
	var extra: Variant = self.get("extra_damage") if "extra_damage" in self else null
	if extra is Dictionary:
		for elem in extra.keys():
			var rng_dict: Dictionary = extra[elem]
			var lo: int = int(rng_dict.get("min", 0))
			var hi: int = int(rng_dict.get("max", 0))
			if hi <= 0:
				continue
			typed[elem] = int(typed.get(elem, 0)) + randi_range(lo, max(lo, hi))
	# Str scaling on the whole swing — affects all damage types so a
	# Strength build buffs hybrid weapons evenly.
	var str_excess: int = 0
	if "str_stat" in self:
		str_excess = int(self.str_stat) - 5
	var str_mult: float = 1.0 + float(str_excess) * 0.02
	if dmg_mult != 1.0 or str_mult != 1.0:
		var combo: float = dmg_mult * str_mult
		for k in typed.keys():
			typed[k] = int(round(float(typed[k]) * combo))
	var crit: bool = false
	var roll_chance: float = crit_chance + crit_bonus
	if roll_chance > 0.0 and randf() * 100.0 < roll_chance:
		for k in typed.keys():
			typed[k] = int(round(float(typed[k]) * CRIT_MULTIPLIER))
		crit = true
	# Update precision streak — reset on crit, grow on miss-of-crit.
	if "precision" in tags:
		_precision_streak = 0 if crit else _precision_streak + 1
	# Apply each typed component as a separate take_damage call. The
	# defender's evasion fires once on the first call (full miss); the
	# subsequent components also evasion-roll fresh — that's fine because
	# defender state mutates between calls (HP drops, evasion stays).
	# `raw` retained as the top-line value for downstream tag procs that
	# need a single number (thunderous chain splash, etc).
	var raw: int = 0
	for k in typed.keys():
		raw += int(typed[k])
	var dealt: int = 0
	for k in typed.keys():
		var part: int = int(typed[k])
		if part <= 0:
			continue
		dealt += other.take_damage(part, self, k)
	var killed: bool = is_instance_valid(other) and not other.is_alive
	# Post-attack tag mechanics. `vampiric` heals 8% of damage dealt
	# back to the attacker — capped at max_hp. Defended/dodged hits
	# (dealt<=0) don't heal. `fire` applies a 3-tick burn DoT to the
	# target dealing 4% of their max_hp per tick (0.5s interval).
	if dealt > 0 and not tags.is_empty():
		if "vampiric" in tags and is_alive:
			var heal: int = int(round(float(dealt) * 0.08))
			if heal > 0:
				hp = clampi(hp + heal, 0, max_hp)
				_update_hp_bar()
		if "fire" in tags and is_instance_valid(other) and other.is_alive:
			# 3 ticks × 4% max_hp = 12% max_hp total over 1.5s. Refreshes
			# duration on re-application; doesn't stack damage.
			var per_tick: int = maxi(1, int(round(float(other.max_hp) * 0.04)))
			other.add_burn(per_tick, 3, 0.5)
		if "cold" in tags and is_instance_valid(other) and other.is_alive and randf() < 0.15:
			# 0.5s freeze — short window so the +20% on next swing only
			# usually lands once, not the whole fight. Doesn't apply
			# slow on enemy speed (would need a movement-tick hook).
			other.add_status("frozen", 0.5)
		if "poison" in tags and is_instance_valid(other) and other.is_alive:
			# 4-tick poison DoT (similar shape to fire but slightly less
			# per tick). Uses the existing `poisoned` ENCH overlay.
			var poison_per_tick: int = maxi(1, int(round(float(other.max_hp) * 0.03)))
			other.add_poison(poison_per_tick, 4, 0.5)
	# Stealth single-strike consumed.
	if has_status("stealthy"):
		remove_status("stealthy")
	# `sound`: 10% chance to stun the target for 1s on a successful hit.
	if dealt > 0 and "sound" in tags and is_instance_valid(other) and other.is_alive and randf() < 0.10:
		other.add_status("stunned", 1.0)
	# `dual`: 15% chance to fire a second swing immediately. Guarded
	# against recursion via _dual_attacking flag — the second swing
	# CAN'T trigger another double or the player gets infinite swings
	# off a lucky chain. Skips the cooldown, doesn't refresh other tag
	# state to keep it simple.
	if dealt > 0 and "dual" in tags and is_instance_valid(other) and other.is_alive and not _dual_attacking:
		if randf() < 0.15:
			_dual_attacking = true
			# Reuse the same atk roll for the second hit; no animation
			# tween (would feel laggy if fired every time).
			var raw2: int = atk
			other.take_damage(raw2, self)
			_dual_attacking = false
	# Rage: each KILL by this attacker adds a stack (cap +30%, refresh
	# 6s window). Defender-worn so only the wearer accumulates stacks.
	if killed and "rage" in def_tags:
		_rage_stacks = mini(_rage_stacks + 1, 6)
		_rage_expires_at = float(Time.get_ticks_msec()) / 1000.0 + 6.0
	# `rampaging`: on a kill, refund the next attack's cooldown so
	# the bot can move/attack again immediately. PoE-Headhunter shape.
	if killed and ("rampaging" in tags or "rampaging" in def_tags):
		attack_cooldown = 0.0
	# `death`: on a kill, 25% chance to splash 5% atk to one adjacent
	# enemy. Tagged on a weapon — defender-worn `death` doesn't fire
	# (defender doesn't kill anyone here). Doesn't recurse.
	if killed and "death" in tags and is_instance_valid(other):
		if randf() < 0.25:
			var nearby: Actor = _find_adjacent_actor(other)
			if nearby != null:
				var blast: int = maxi(1, int(round(float(atk) * 0.05)))
				nearby.take_damage(blast, self)
	# `thunderous` (boots): chain 50% damage to one enemy adjacent to
	# the primary target. Defender-worn (boots are a defense slot).
	# Skipped if dealt<=0 (the chain is meant to read as "hit splashes
	# from the impact"). The chain hit doesn't itself trigger thunderous
	# again — would create infinite chains.
	if dealt > 0 and "thunderous" in def_tags and is_instance_valid(other):
		var chain: Actor = _find_adjacent_actor(other)
		if chain != null:
			var splash: int = maxi(1, int(round(float(raw) * 0.5)))
			chain.take_damage(splash, self)
	# Base-type weapon procs — combat pivot 2026-06-04. Each weapon
	# base_type carries an inherent style (dagger=bleed, axe=cleave,
	# mace=stun, etc.) on top of any flavor enchants. Reuses existing
	# status hooks (bleeding/stunned/frozen) and _find_adjacent_actor
	# for cleaves so the visual + logged feedback stay consistent.
	if dealt > 0 and is_instance_valid(other):
		_apply_base_type_proc(other, raw)
	# [combat] emitted only during instrumented runs (GrindLog enabled = grind/
	# benchmark mode). Per-attack volume is fine in batches but spams playtests.
	if GrindLog._enabled:
		GrindLog.log_line("[combat] atk=%s def=%s wpn=%s raw=%d crit=%s dealt=%d def_hp=%d boss=%s mb=%s" % [
			combat_label(),
			other.combat_label() if is_instance_valid(other) else "?",
			combat_weapon_id(),
			raw,
			"1" if crit else "0",
			dealt,
			other.hp if is_instance_valid(other) else 0,
			"1" if other is Enemy and (other as Enemy).is_boss else "0",
			"1" if other is Enemy and (other as Enemy).is_miniboss else "0",
		])
	return dealt

# Subclasses override (Bot returns "bot", Enemy returns enemy_id).
func combat_label() -> String:
	return "actor"

# Bot overrides to return its equipped weapon's base_id; Enemy returns "".
func combat_weapon_id() -> String:
	return ""

# Bot overrides to return the equipped weapon's flavor_tags array
# (e.g. ["vampiric", "bloodlust"]). Tag-driven mechanics in
# attempt_attack read this. Enemy returns []; mundane bot returns [].
func combat_weapon_tags() -> Array:
	return []

# Override on Bot — returns the equipped weapon's base_type ("dagger",
# "battle_axe", etc.) so per-base-type procs can fire in attempt_attack.
# Default empty for enemies.
func combat_weapon_base_type() -> String:
	return ""

# Per-base-type combat procs. Daggers bleed, axes cleave, maces stun,
# polearms reach, etc. Each weapon style gets a signature feel layered
# on top of the existing flavor-tag procs. Combat pivot 2026-06-04.
#
# Args: `target` is the primary defender; `raw` is the pre-mitigation
# attack roll, used as the base for cleave splash math.
func _apply_base_type_proc(target: Actor, raw: int) -> void:
	var bt: String = combat_weapon_base_type()
	if bt == "":
		return
	# Daggers + knives — short bleed DoT. Quick low-damage weapons get a
	# chip-damage proc to compete with bigger weapons' raw output.
	if bt == "dagger" or bt == "knife" or bt == "shiv":
		if randf() < 0.40:
			var bleed_per_tick: int = maxi(1, int(round(float(raw) * 0.08)))
			target.add_poison(bleed_per_tick, 3, 0.6)  # reuse poison DoT shape
		return
	# 1H swords + sabres — modest cleave: 60% damage to one adjacent foe.
	if bt in ["short_sword", "long_sword", "scimitar", "falchion", "rapier", "sabre", "broad_sword"]:
		var adj_a: Actor = _find_adjacent_actor(target)
		if adj_a != null:
			adj_a.take_damage(maxi(1, int(round(float(raw) * 0.60))), self)
		return
	# 2H swords — full 360 cleave: full damage to up to 2 adjacent foes.
	if bt in ["greatsword", "claymore", "double_sword", "triple_sword"]:
		var seen: Dictionary = {target.get_instance_id(): true}
		var hits: int = 0
		for _i in 4:
			var adj_b: Actor = _find_adjacent_actor(target, seen)
			if adj_b == null:
				break
			adj_b.take_damage(raw, self)
			seen[adj_b.get_instance_id()] = true
			hits += 1
			if hits >= 2:
				break
		return
	# 1H axes — cleave: full damage to one adjacent. Hand axe / war axe.
	if bt in ["hand_axe", "war_axe"]:
		var adj_c: Actor = _find_adjacent_actor(target)
		if adj_c != null:
			adj_c.take_damage(raw, self)
		return
	# 2H axes — wide cleave: full damage to up to 3 adjacent.
	if bt in ["battle_axe", "broad_axe", "executioner_axe"]:
		var seen2: Dictionary = {target.get_instance_id(): true}
		var hits2: int = 0
		for _i in 6:
			var adj_d: Actor = _find_adjacent_actor(target, seen2)
			if adj_d == null:
				break
			adj_d.take_damage(raw, self)
			seen2[adj_d.get_instance_id()] = true
			hits2 += 1
			if hits2 >= 3:
				break
		return
	# Maces / clubs / flails — stun chance on hit.
	if bt in ["club", "mace", "flail", "morningstar", "great_mace", "dire_flail", "giant_club", "eveningstar"]:
		if randf() < 0.18:
			target.add_status("stunned", 0.6)
		return
	# Polearms (1H+2H) — reach: bonus +20% damage on first hit (already
	# applied via raw); hit a foe BEHIND the target as well.
	if bt in ["spear", "trident", "halberd", "bardiche", "scythe", "glaive"]:
		# Behind-target finder — closest cell beyond `target` from the
		# attacker's perspective. Approximated by taking another adjacent
		# actor.
		var adj_e: Actor = _find_adjacent_actor(target)
		if adj_e != null:
			adj_e.take_damage(maxi(1, int(round(float(raw) * 0.50))), self)
		return
	# Whips — line-hit. Damage falloff to up to 2 enemies in a line.
	if bt in ["whip", "demon_whip"]:
		var seen3: Dictionary = {target.get_instance_id(): true}
		var dmg: float = float(raw) * 0.6
		for _i in 2:
			var adj_f: Actor = _find_adjacent_actor(target, seen3)
			if adj_f == null:
				break
			adj_f.take_damage(maxi(1, int(round(dmg))), self)
			seen3[adj_f.get_instance_id()] = true
			dmg *= 0.7


func _play_death_then_emit() -> void:
	if fx == null:
		died.emit(self)
		return
	var tween := fx.death_spin()
	died.emit(self)
	if tween:
		tween.finished.connect(_on_death_tween_done)
	else:
		_on_death_tween_done()

func _on_death_tween_done() -> void:
	if is_inside_tree():
		queue_free()

func _update_hp_bar() -> void:
	if hp_bar == null:
		return
	var pct: float = clampf(float(hp) / float(max_hp), 0.0, 1.0)
	hp_bar.size = Vector2((C.TILE_SIZE - 4) * pct, 3)
	hp_bar.color = Color(1.0 - pct, 0.4 + 0.5 * pct, 0.3, 0.95)

# ============================================================================
# ENCH — status overlay framework. See status_overlay.gd for the registry.
# ============================================================================

# Add or refresh a status. duration > 0 = expires after that many seconds;
# duration <= 0 = persistent until remove_status(id) is called.
# Refreshing a status (called again before expiry) extends the timer.
# Gated by VideoSettings.gfx.ench — when off, every call no-ops so
# the framework stays cheap on low-end hardware.
func add_status(id: String, duration: float = 1.0) -> void:
	if not _StatusOverlay.has_status(id):
		return
	if not VideoSettings.is_effect_enabled("ench"):
		return
	# Refresh existing status — bump timer, leave sprite alone.
	if _statuses.has(id):
		var existing: Dictionary = _statuses[id]
		var now: float = float(Time.get_ticks_msec()) / 1000.0
		var new_expiry: float = now + duration if duration > 0.0 else 0.0
		# Persistent (duration<=0) overrides any previous timer; otherwise
		# only extend (don't shorten on a shorter duration call).
		if duration <= 0.0:
			existing["expires_at"] = 0.0
		else:
			existing["expires_at"] = max(float(existing.get("expires_at", 0.0)), new_expiry)
		return
	# New status — instantiate overlay sprite + register.
	var def: Dictionary = _StatusOverlay.get_def(id)
	var tex: Texture2D = _StatusOverlay.texture_for(id)
	if tex == null:
		# Sprite missing — register the status anyway so mechanics can
		# read is_status(id), but skip the visual.
		var now2: float = float(Time.get_ticks_msec()) / 1000.0
		_statuses[id] = {
			"expires_at": now2 + duration if duration > 0.0 else 0.0,
			"sprite": null,
		}
		return
	if _status_layer == null:
		_status_layer = Node2D.new()
		# Sit slightly above the rig but below HP bars (which are at y=-5).
		# Position = (tile_center, y just above figure top).
		_status_layer.position = Vector2(C.TILE_SIZE * 0.5, -2)
		add_child(_status_layer)
	var spr := Sprite2D.new()
	spr.texture = tex
	spr.centered = true
	spr.modulate = def.get("tint", Color(1, 1, 1, 1))
	spr.z_index = int(def.get("z", 0))
	# Stack horizontally — each status icon offset 12px apart.
	var slot: int = _statuses.size()
	spr.position = Vector2(slot * 12 - 6, 0)
	spr.scale = Vector2(0.5, 0.5)  # 32px source → 16px on-screen
	_status_layer.add_child(spr)
	var now3: float = float(Time.get_ticks_msec()) / 1000.0
	_statuses[id] = {
		"expires_at": now3 + duration if duration > 0.0 else 0.0,
		"sprite": spr,
	}

# Apply a burn DoT on top of the burning visual status. Each tick deals
# `per_tick` true damage (skips defense — DoTs are intended to bypass
# armor) and the status auto-expires after `ticks * interval` seconds.
# Re-applying refreshes the timer and replaces tick params.
func add_burn(per_tick: int, ticks: int, interval: float) -> void:
	# fire_res grants immunity to burn DoT (matches DCSS rF+ stops
	# being on fire). Resists are wired on every actor; non-bot
	# actors return [] from combat_defense_tags so this is a no-op
	# for them.
	if "fire_res" in combat_defense_tags():
		return
	_apply_dot_status("burning", per_tick, ticks, interval)

func add_poison(per_tick: int, ticks: int, interval: float) -> void:
	if "poison_res" in combat_defense_tags():
		return
	_apply_dot_status("poisoned", per_tick, ticks, interval)

func _apply_dot_status(status_id: String, per_tick: int, ticks: int, interval: float) -> void:
	add_status(status_id, float(ticks) * interval)
	if not _statuses.has(status_id):
		return
	var now: float = float(Time.get_ticks_msec()) / 1000.0
	var entry: Dictionary = _statuses[status_id]
	entry["dot"] = {"amount": per_tick, "interval": interval}
	entry["next_tick_at"] = now + interval
	_statuses[status_id] = entry

func remove_status(id: String) -> void:
	if not _statuses.has(id):
		return
	var entry: Dictionary = _statuses[id]
	var spr: Variant = entry.get("sprite", null)
	if spr is Sprite2D and is_instance_valid(spr):
		(spr as Sprite2D).queue_free()
	_statuses.erase(id)
	_relayout_statuses()

func has_status(id: String) -> bool:
	return _statuses.has(id)

# Snapshot of active statuses, keyed by id. Used by HUD layers (the
# WoW-style buff bar) so they can iterate without touching the
# underscore field directly. Returned dict is the same backing store —
# do not mutate from the caller.
func active_statuses() -> Dictionary:
	return _statuses

# Called from scene _process via Bot/Enemy tick paths. Expires statuses
# whose timers have elapsed and pulses the active ones.
func tick_statuses(delta: float) -> void:
	if _statuses.is_empty():
		return
	var now: float = float(Time.get_ticks_msec()) / 1000.0
	var expired: Array[String] = []
	for id in _statuses.keys():
		var entry: Dictionary = _statuses[id]
		var expires: float = float(entry.get("expires_at", 0.0))
		if expires > 0.0 and now >= expires:
			expired.append(id)
			continue
		# DoT tick — applied if the status carries a `dot` payload
		# (set via add_burn / future add_poison etc.). True-damage
		# (no defense subtraction) so the DoT feels distinct from
		# direct attacks.
		var dot: Variant = entry.get("dot", null)
		if dot != null and typeof(dot) == TYPE_DICTIONARY:
			var next_tick: float = float(entry.get("next_tick_at", 0.0))
			if now >= next_tick:
				var amount: int = int(dot.get("amount", 0))
				var interval: float = float(dot.get("interval", 0.5))
				if amount > 0 and is_alive:
					hp = maxi(0, hp - amount)
					damaged.emit(self, amount)
					_update_hp_bar()
					if hp <= 0:
						is_alive = false
						_play_death_then_emit()
				entry["next_tick_at"] = now + interval
				_statuses[id] = entry
		var spr: Variant = entry.get("sprite", null)
		if spr is Sprite2D and is_instance_valid(spr):
			var def: Dictionary = _StatusOverlay.get_def(id)
			if bool(def.get("pulse", false)):
				# Subtle alpha pulse to draw the eye. Ranges 0.6..1.0.
				var t: float = sin(now * 4.0) * 0.5 + 0.5  # 0..1
				var base_a: float = 1.0
				var col: Color = (spr as Sprite2D).modulate
				col.a = 0.6 + 0.4 * t * base_a
				(spr as Sprite2D).modulate = col
	for id in expired:
		remove_status(id)

# Re-stack remaining icons after one is removed.
func _relayout_statuses() -> void:
	var i: int = 0
	for id in _statuses.keys():
		var entry: Dictionary = _statuses[id]
		var spr: Variant = entry.get("sprite", null)
		if spr is Sprite2D and is_instance_valid(spr):
			(spr as Sprite2D).position = Vector2(i * 12 - 6, 0)
		i += 1
