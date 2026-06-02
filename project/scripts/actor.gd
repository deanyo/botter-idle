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

func take_damage(raw: int, attacker: Actor = null) -> int:
	# Defender-side flavor tag pre-checks. `reflective` rolls a 10% chance
	# to negate the entire incoming hit (true 0 damage). `harm` adds +25%
	# to incoming damage. Order: reflective first (a full negate beats a
	# multiplier), then harm.
	var def_tags: Array = combat_defense_tags()
	if not def_tags.is_empty():
		if "reflective" in def_tags and randf() < 0.10:
			# Hit fully reflected/parried — log a tiny squish and exit.
			if fx and is_alive:
				fx.hit_squish()
			return 0
		if "harm" in def_tags:
			raw = int(round(float(raw) * 1.25))
	var dmg: int = maxi(1, raw - defense)
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
func _find_adjacent_actor(near: Actor) -> Actor:
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
			var dx: int = absi(c.cell.x - near.cell.x)
			var dy: int = absi(c.cell.y - near.cell.y)
			if dx <= 1 and dy <= 1 and (dx + dy) > 0:
				return c
	return null

func attempt_attack(other: Actor, delta: float) -> int:
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

	# Crit roll: on success multiply raw damage before defense subtraction so
	# crit feels meaningful even against high-DEF targets.
	var raw: int = atk
	if dmg_mult != 1.0:
		raw = int(round(float(raw) * dmg_mult))
	var crit: bool = false
	var roll_chance: float = crit_chance + crit_bonus
	if roll_chance > 0.0 and randf() * 100.0 < roll_chance:
		raw = int(round(float(raw) * CRIT_MULTIPLIER))
		crit = true
	# Update precision streak — reset on crit, grow on miss-of-crit.
	if "precision" in tags:
		_precision_streak = 0 if crit else _precision_streak + 1
	var dealt: int = other.take_damage(raw, self)
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
	# Rage: each KILL by this attacker adds a stack (cap +30%, refresh
	# 6s window). Defender-worn so only the wearer accumulates stacks.
	if killed and "rage" in def_tags:
		_rage_stacks = mini(_rage_stacks + 1, 6)
		_rage_expires_at = float(Time.get_ticks_msec()) / 1000.0 + 6.0
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
	_apply_dot_status("burning", per_tick, ticks, interval)

func add_poison(per_tick: int, ticks: int, interval: float) -> void:
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
