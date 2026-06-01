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

# DCSS-style ENCH layer — visible status icons above the rig. Drives no
# mechanics; mechanics drive it. Each status: {id, expires_at, sprite}.
# duration <= 0 = persistent until remove_status(id). Ticked from the
# scene's _process (Bot+Enemy both inherit Actor and tick).
var _status_layer: Node2D = null
var _statuses: Dictionary = {}  # id → {expires_at: float, sprite: Sprite2D}
const _StatusOverlay := preload("res://scripts/status_overlay.gd")

func _ready() -> void:
	hp = max_hp
	# rig sits at the tile center so SpriteFX can rotate / scale around the
	# figure's pivot (death spin, attack lunge squish). All visual children —
	# base sprite, body armor, weapon overlay — attach to rig at offset (0, 0)
	# so they inherit lunge / flash / death tweens together.
	rig = Node2D.new()
	rig.position = Vector2(C.TILE_SIZE * 0.5, C.TILE_SIZE * 0.5)
	add_child(rig)
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
	rig.scale = Vector2(scale, scale)
	if anchor == "ground":
		# For ground anchor, shift the rig up so the sprite's bottom edge stays
		# pinned to the cell's bottom — looks natural for upright creatures.
		var half_tile: float = C.TILE_SIZE * 0.5
		var overflow: float = (scale - 1.0) * half_tile
		rig.position = Vector2(half_tile, half_tile - overflow)
	else:
		rig.position = Vector2(C.TILE_SIZE * 0.5, C.TILE_SIZE * 0.5)
	sprite.position = Vector2.ZERO
	if z != 0:
		sprite.z_index = z

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

func take_damage(raw: int) -> int:
	var dmg: int = maxi(1, raw - defense)
	hp -= dmg
	damaged.emit(self, dmg)
	_update_hp_bar()
	if fx and is_alive:
		fx.hit_squish()
	if hp <= 0:
		is_alive = false
		_play_death_then_emit()
	return dmg

func attempt_attack(other: Actor, delta: float) -> int:
	attack_cooldown -= delta
	if attack_cooldown > 0.0:
		return 0
	attack_cooldown = attack_interval
	if fx:
		var toward: Vector2 = (other.position - position) if is_instance_valid(other) else Vector2.RIGHT
		fx.attack_lunge(toward)
	# Crit roll: on success multiply raw damage before defense subtraction so
	# crit feels meaningful even against high-DEF targets.
	var raw: int = atk
	var crit: bool = false
	if crit_chance > 0.0 and randf() * 100.0 < crit_chance:
		raw = int(round(float(raw) * CRIT_MULTIPLIER))
		crit = true
	var dealt: int = other.take_damage(raw)
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
