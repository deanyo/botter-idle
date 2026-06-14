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
# of_sundering (a02 P-11): defender carries a sunder amount + expiry.
# Each successful sunder hit refreshes the timer and stacks the armor
# reduction up to the cap (2 stacks per a10 P-11 rescope). Read by
# _apply_typed_damage when computing physical mitigation.
var _sunder_amount: int = 0
var _sunder_stacks: int = 0
var _sunder_expires_at: float = 0.0
const _SUNDER_DURATION := 3.0
const _SUNDER_MAX_STACKS := 2

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
	# S5 race-anchor: stamp the last-move time on Bot. Stoneflesh's
	# `petrify` tag reads it to grant DR while stationary; only Bot
	# carries the field, so guard the cast.
	if self is Bot:
		var bot_step: Bot = self as Bot
		bot_step._last_move_at_msec = Time.get_ticks_msec()
		# §1.H of_warden_step (a02 P-026, a10 cap 80). Increment cell-
		# traversal counter when the bot enters a new cell; fire a 2-tile
		# AoE pulse for X% of weapon damage on every 8th step. Visual
		# reuses SpellAoe.spawn_ring; damage walks sibling actors within
		# Chebyshev radius 2 of the bot.
		if bot_step.step_pulse_pct > 0.0 and cell != bot_step._warden_last_cell:
			bot_step._warden_last_cell = cell
			bot_step._warden_step_count += 1
			if bot_step._warden_step_count >= 8:
				bot_step._warden_step_count = 0
				_warden_step_pulse(bot_step)

# Resolve a swing: avoidance gates ONCE, each typed component goes through
# mitigation, returns (thorns/crystal) fire ONCE against the aggregated
# damage. The hybrid-weapon split (physical+fire+cold) used to call
# take_damage per type and gave each component its own evasion / footwork /
# reflective roll AND its own thorns/crystal return — a 3-element swing
# was multiplicatively easier to dodge and triggered three independent
# attacker-bound returns. Now: one roll, one return.
#
# Single-hit callers (spells, projectiles, splash, DoT-bypass paths) call
# take_damage instead, which builds a 1-entry typed dict and routes here
# so they pick up the same avoidance + return semantics for free.
func resolve_swing(typed: Dictionary, attacker: Actor = null) -> int:
	if not is_alive or typed.is_empty():
		return 0
	# Pull tag arrays once for the whole swing — used by every typed
	# component AND by the avoidance gates.
	var def_tags: Array = combat_defense_tags()
	var atk_tags: Array = []
	if attacker != null and is_instance_valid(attacker):
		atk_tags = attacker.combat_weapon_tags()
	# Avoidance gates — ONCE per swing. Order matches the legacy
	# take_damage gate order (evasion → footwork → reflective).
	if "evasion" in self:
		var eva: float = float(self.evasion)
		# §3.A spell_aura_grace — +10% evasion while "grace" status ticks.
		# Bot-only; aura applies via SpellTotem.spawn_aura → add_status.
		# Capped above the legacy 75% evasion ceiling; grace pushes it
		# to a hard 85%, keeping a 15% floor for hits to land.
		if has_status("grace"):
			eva = minf(85.0, eva + 10.0)
		if eva > 0.0 and randf() * 100.0 < eva:
			if fx and is_alive:
				fx.hit_squish()
			return 0
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
	# S9 block gate (a06 §2.2). Sits AFTER evasion/footwork/reflective so
	# block fires only on swings that aren't already evaded — keeps the
	# defensive layers from compounding on the same roll. On block proc:
	# subtract block_amount from each typed component pre-mitigation; if
	# block_amount ≥ every component, treat as full block (return 0). Else
	# partial block reduces each typed leg by block_amount, ≥1 floor, and
	# falls through to the normal mitigation pipeline.
	# Bot-only — mundane actors carry no block_chance/block_amount fields.
	if self is Bot and is_alive:
		var bot_block: Bot = self as Bot
		if bot_block.block_chance > 0.0 and randf() * 100.0 < bot_block.block_chance:
			var amt: int = bot_block.block_amount
			var full_block: bool = true
			for k in typed.keys():
				if int(typed[k]) > amt:
					full_block = false
					break
			# §1.H of_aegis_thorns (a02 P-025, a11 G4) — on either block path,
			# reflect block_thorns_flat back at the attacker through the same
			# rolling-emission cap as of_thorns. Fires on full AND partial block.
			if bot_block.block_thorns_flat > 0 and attacker != null \
					and is_instance_valid(attacker) and attacker.is_alive:
				var emitted_blk: int = _bot_emit_reflect(bot_block, bot_block.block_thorns_flat, attacker)
				if emitted_blk > 0:
					attacker.hp = maxi(0, attacker.hp - emitted_blk)
					attacker.damaged.emit(attacker, emitted_blk)
					attacker._update_hp_bar()
					if attacker.hp <= 0 and attacker.is_alive:
						attacker.is_alive = false
						attacker._play_death_then_emit()
			if full_block:
				if fx and is_alive:
					fx.hit_squish()
				return 0
			# Partial block — reduce each typed leg by amt with a ≥1 floor.
			for k in typed.keys():
				var part: int = int(typed[k])
				if part <= 0:
					continue
				typed[k] = maxi(1, part - amt)
	# Apply each typed component through mitigation + HP drop. Death
	# check is deferred until after the loop so a fatal first component
	# doesn't double-emit `died` from later components.
	var dealt_total: int = 0
	for k in typed.keys():
		var part: int = int(typed[k])
		if part <= 0:
			continue
		dealt_total += _apply_typed_damage(part, String(k), attacker, def_tags, atk_tags)
		if hp <= 0:
			break
	# Returns — ONCE per swing, against aggregated damage. Skip if the
	# attacker is gone (was dead before this swing landed, etc).
	if dealt_total > 0 and attacker != null and is_instance_valid(attacker) and attacker.is_alive and not def_tags.is_empty():
		# `thorns` returns 15% of total dealt damage to the attacker.
		if "thorns" in def_tags:
			var thorn_dmg: int = maxi(1, int(round(float(dealt_total) * 0.15)))
			attacker.hp = maxi(0, attacker.hp - thorn_dmg)
			attacker.damaged.emit(attacker, thorn_dmg)
			attacker._update_hp_bar()
			if attacker.hp <= 0 and attacker.is_alive:
				attacker.is_alive = false
				attacker._play_death_then_emit()
		# `crystal`: smaller always-on passive thorn — 5% of dealt to the
		# attacker. Stacks with thorns (lore: crystal armor splinters
		# inward AND outward).
		if "crystal" in def_tags and is_instance_valid(attacker) and attacker.is_alive:
			var c_dmg: int = maxi(1, int(round(float(dealt_total) * 0.05)))
			attacker.hp = maxi(0, attacker.hp - c_dmg)
			attacker.damaged.emit(attacker, c_dmg)
			attacker._update_hp_bar()
			if attacker.hp <= 0:
				attacker.is_alive = false
				attacker._play_death_then_emit()
	# §1.H of_thorns (a02 P-010, a11 G4) — flat reflect per-hit. Bot-side
	# only. Per-hit cap: 30% of dealt_total (so a 5-dmg trash mob can't
	# eat a 25-flat reflect for 500% effective). Rolling-window cap: ≤
	# max_hp×0.05/s emitted summed across thorns_flat + block_thorns_flat.
	if dealt_total > 0 and self is Bot and is_alive and attacker != null \
			and is_instance_valid(attacker) and attacker.is_alive:
		var bot_th: Bot = self as Bot
		if bot_th.thorns_flat > 0:
			var per_hit_cap: int = maxi(1, int(round(float(dealt_total) * 0.30)))
			var capped_thorn: int = mini(bot_th.thorns_flat, per_hit_cap)
			var emitted: int = _bot_emit_reflect(bot_th, capped_thorn, attacker)
			if emitted > 0:
				attacker.hp = maxi(0, attacker.hp - emitted)
				attacker.damaged.emit(attacker, emitted)
				attacker._update_hp_bar()
				if attacker.hp <= 0 and attacker.is_alive:
					attacker.is_alive = false
					attacker._play_death_then_emit()
	# §1.H of_avenger (a02 P-007). After taking damage, the bot enters a
	# 3-second "revenge" window where attempt_attack reads revenge_dmg_pct
	# into ephemeral_sum. Re-applying refreshes the 3s timer. Bot-only;
	# enemies have no revenge_dmg_pct field. Status_overlay registers the
	# rage.png icon so the buff bar reads "Revenge".
	if dealt_total > 0 and self is Bot and is_alive:
		var bot_av: Bot = self as Bot
		if bot_av.revenge_dmg_pct > 0.0:
			add_status("revenge", 3.0)
		# §1.H of_recoup (a02 P-011, a11 G1). Add a recoup bucket = pct × dealt
		# scheduled to drain over 4s in bot._process. Re-applying ADDs to the
		# pool and refreshes the window; pre-existing pool drains alongside the
		# new addition so heavy hits stack pacing rather than restart.
		if bot_av.recoup_pct > 0.0:
			var add_pool: float = float(dealt_total) * bot_av.recoup_pct / 100.0
			bot_av._recoup_bucket += add_pool
			bot_av._recoup_window_remaining = 4.0
			add_status("recouping", 4.0)
	if hp <= 0 and is_alive:
		# S11 of_phylactery (a07 §6.10 Boris's Phylactery). Once-per-floor
		# revive at phylactery_revive_pct% max HP on lethal damage. Gates
		# on the same revive_used_this_floor mutex S2 set up so stacking
		# of_phoenix + Last Heart + Phylactery still yields ONE revive
		# per floor (a11 §2.11 / a10 §5.2). Bot-only.
		if self is Bot:
			var bot_pl: Bot = self as Bot
			if bot_pl.phylactery_revive_pct > 0.0 and not bot_pl.revive_used_this_floor:
				bot_pl.revive_used_this_floor = true
				hp = maxi(1, int(round(float(max_hp) * bot_pl.phylactery_revive_pct / 100.0)))
				_update_hp_bar()
				return dealt_total
		is_alive = false
		_play_death_then_emit()
	return dealt_total

# Apply ONE typed component after avoidance has already passed. Pure
# mitigation (resists / harm / armor / resistances) + HP drop. Does NOT
# trigger evasion, returns, or death — those are handled by resolve_swing.
# Returns the actually-dealt damage so resolve_swing can aggregate.
func _apply_typed_damage(raw: int, damage_type: String, attacker: Actor, def_tags: Array, atk_tags: Array) -> int:
	if damage_type == "":
		damage_type = "physical"
	# Mitigation cap (a10 §5.2, S2). Worn-tag conditional DR, element
	# resistance, and normalized armor additively SUM into mit_sum,
	# then clamp to [-0.50, +0.90] (10% always lands; harm can amplify
	# up to 1.5×). Pre-cap, layers multiplied: a Gargoyle stoneflesh +
	# tower-warding + fortified + 75% phys-resist + 75% evasion stack
	# could compound to 96%+ effective mitigation = ~30× EHP. Additive
	# composition keeps the defensive ceiling sane regardless of how
	# many DR sources land.
	var mit_sum: float = 0.0
	if not def_tags.is_empty():
		# Element resists (legacy: -50% off elemental hits whose attacker
		# tag matches the worn resist).
		if "fire_res" in def_tags and "fire" in atk_tags:
			mit_sum += 0.50
		if "cold_res" in def_tags and "cold" in atk_tags:
			mit_sum += 0.50
		# `earth`: -15% from any non-elemental, non-magical attack.
		if "earth" in def_tags:
			var is_physical: bool = true
			for t in ["fire", "cold", "elemental", "arcane", "holy", "dark", "thunderous"]:
				if t in atk_tags:
					is_physical = false
					break
			if is_physical:
				mit_sum += 0.15
		# `willpower`: -25% from arcane / elemental / magical attackers.
		if "willpower" in def_tags:
			for t in ["arcane", "elemental", "fire", "cold"]:
				if t in atk_tags:
					mit_sum += 0.25
					break
		# `warding`: -20% from boss / miniboss attackers.
		if "warding" in def_tags and attacker is Enemy:
			var e: Enemy = attacker as Enemy
			if e.is_boss or e.is_miniboss:
				mit_sum += 0.20
		# `acrobat`: -17% when below 30% HP.
		if "acrobat" in def_tags and max_hp > 0 and float(hp) / float(max_hp) <= 0.30:
			mit_sum += 0.17
		# §1.H of_revenant — low-hp damage reduction. <40% HP threshold per
		# a02 P-003, cap 28 in stat_calc. Same lane as acrobat so the
		# +30% mit ceiling absorbs the upper tail (acrobat 17 + revenant 28
		# would otherwise hit 45% pre-cap).
		if self is Bot and max_hp > 0 and float(hp) / float(max_hp) < 0.40:
			var bot_rv: Bot = self as Bot
			if bot_rv.low_hp_dr_pct > 0.0:
				mit_sum += bot_rv.low_hp_dr_pct / 100.0
		# §2.E damage_taken_pct — universal DR lane (a06-newstat-021, a10
		# cap 40). No conditional gate; reads bot field unconditionally.
		# Composes additively with worn-tag mit + resist_pct + revenant
		# in the final_mit clamp at +90% ceiling.
		if self is Bot:
			var bot_dt: Bot = self as Bot
			if bot_dt.damage_taken_pct > 0.0:
				mit_sum += bot_dt.damage_taken_pct / 100.0
		# `guardian`: flat -10% damage taken — backup armor.
		if "guardian" in def_tags:
			mit_sum += 0.10
		# `harm`: damage taken AMPLIFIED. Negative contribution.
		if "harm" in def_tags:
			mit_sum += -0.25
		# `petrify` (S5 Gargoyle Stoneflesh Plate, a10 5.13.B rescope):
		# -25% phys damage taken while stationary for ≥0.4s. Re-rolling
		# from a04 -50% would have given +100% EHP at 1953 base — broken.
		# 0.4s window is just-after-step so the bot has to actually pause
		# to claim the bonus (matches the visual "petrified" beat).
		if "petrify" in def_tags and damage_type == "physical" and self is Bot:
			var bot_p: Bot = self as Bot
			var since_move: int = Time.get_ticks_msec() - bot_p._last_move_at_msec
			if since_move >= 400:
				mit_sum += 0.25
	# Apply additive worn-tag/element mitigation FIRST, then route by
	# type. Physical keeps the legacy flat-armor subtraction so early-
	# game defenses still feel right (a 3-dmg rat vs 0-armor fresh-save
	# bot mitigates to 1 dmg via the floor, not via the additive cap
	# which would only knock 3 down to 2 — doubling time-to-die against
	# trash). Elemental damage routes resist_pct into mit_sum so it
	# stacks additively with worn-tag DR rather than multiplicatively.
	# This preserves the pre-cap early-game feel while still enforcing
	# the +90% additive ceiling on the late-game DR stack
	# (worn-tag + element-tag + resist_pct).
	var final_mit: float = clampf(mit_sum, -0.50, 0.90)
	var dmg: int
	# S10 — Curse of Brittlebone debuff (a05 prop-4 + a10 §3.2 rescope to
	# +15% damage taken). When the defender carries "cursed" status, raw
	# damage is amplified BEFORE mitigation. Folds in alongside `harm`
	# (which is attacker-side ephemeral); cursed is defender-side debuff.
	# Multiplicative on raw is fine here because a10 §3.2 capped this at
	# +15% — the post-cap stack with harm (-25% mit) is +43% effective
	# per cast, well within the +30% ephemeral envelope on the attacker.
	var raw_amped: float = float(raw)
	if has_status("cursed"):
		raw_amped *= 1.15
	# §1.H of_hunter_mark (a02 P-009, a11 G7) + of_vulnerability_mark
	# (a09-cond-002). Marked enemies take +X% damage from all sources for
	# 4s. of_hunter_mark applies on-crit; of_vulnerability_mark applies on
	# first-hit-per-target (see attempt_attack first-strike branch). Both
	# attacker-side accumulators sum into the marked-amp lane. Per-target
	# gate: only the LATEST refresh status sits active.
	if has_status("marked") and attacker != null and attacker is Bot:
		var bot_hm: Bot = attacker as Bot
		var amp: float = bot_hm.crit_mark_dmg_pct + bot_hm.first_hit_mark_pct
		if amp > 0.0:
			raw_amped *= 1.0 + amp / 100.0
	if damage_type == "physical":
		# Apply mit_sum first, then armor flat-subtract. Floor of 1 so
		# a fully mitigated hit still pings the HP bar.
		var post_mit: int = int(round(raw_amped * (1.0 - final_mit)))
		# of_sundering (a02 P-11 rescoped) — defender's armor temporarily
		# reduced by the active sunder amount. Stacks expire silently on
		# next read after _sunder_expires_at lapses; same shape as `rage`
		# stacks on attackers.
		var eff_armor: int = defense
		# §1.H of_unbroken — armor scales with full-HP gate (a02 P-020,
		# cap 75). Mirror of of_revenant shape but on the armor lane:
		# defender at hp == max_hp gets +full_hp_armor_pct% effective armor.
		# Lives BEFORE sunder so the sunder strip applies after the boost
		# (sunder strips a fixed amount; boost-then-strip preserves the
		# affix's purpose vs strip-then-boost).
		if self is Bot and hp >= max_hp and max_hp > 0:
			var bot_ub: Bot = self as Bot
			if bot_ub.full_hp_armor_pct > 0.0:
				eff_armor = int(round(float(eff_armor) * (1.0 + bot_ub.full_hp_armor_pct / 100.0)))
		if _sunder_amount > 0:
			var now_s: float = float(Time.get_ticks_msec()) / 1000.0
			if now_s > _sunder_expires_at:
				_sunder_amount = 0
				_sunder_stacks = 0
			else:
				eff_armor = maxi(0, defense - _sunder_amount)
		# Cursed targets ALSO take an extra -50% effective armor on physical
		# hits (a05 prop-4 second leg). Multiplicative with sunder so a 100-
		# armor target with both stacks reads as ~25 armor.
		if has_status("cursed"):
			eff_armor = int(float(eff_armor) * 0.5)
		# §1.H of_armor_breaker (a02 P-018) — attacker-side armor pen, cap 50.
		# Applied last so it lands on already-sundered/cursed armor; the
		# composed shape is "everything stacks multiplicatively from the
		# defender's nominal armor down." Bot-only attacker; enemies have no
		# melee_armor_pen_pct field.
		if attacker != null and attacker is Bot:
			var bot_atk: Bot = attacker as Bot
			if bot_atk.melee_armor_pen_pct > 0.0:
				eff_armor = int(round(float(eff_armor) * (1.0 - bot_atk.melee_armor_pen_pct / 100.0)))
		dmg = maxi(1, post_mit - eff_armor)
	else:
		var resist_pct: float = 0.0
		if "resistances" in self:
			resist_pct = float(self.resistances.get(damage_type, 0))
		# §1.H of_unwavering_focus (a02 P-017, a10 cap 35) — attacker-side
		# spell-pen reduces defender's positive resistance multiplicatively
		# before the elem_mit composition. Negative resistance (vulnerability)
		# left untouched — pen "drilling through" doesn't make a vulnerable
		# target less vulnerable. Bot-only attacker; weapon-typed-elemental
		# riders (of_embers / cold_extra etc.) also pass through this lane,
		# which is consistent with how of_armor_breaker applies to all
		# physical hits (not just spells).
		if attacker != null and attacker is Bot and resist_pct > 0.0:
			var bot_atk_s: Bot = attacker as Bot
			if bot_atk_s.spell_resist_pen_pct > 0.0:
				resist_pct = resist_pct * (1.0 - bot_atk_s.spell_resist_pen_pct / 100.0)
		# Resist pct joins the additive cap.
		var elem_mit: float = clampf(mit_sum + resist_pct / 100.0, -0.50, 0.90)
		dmg = maxi(1, int(round(raw_amped * (1.0 - elem_mit))))
	hp -= dmg
	damaged.emit(self, dmg)
	_update_hp_bar()
	if fx and is_alive:
		fx.hit_squish()
	return dmg

func take_damage(raw: int, attacker: Actor = null, damage_type: String = "") -> int:
	# Single-hit entry point — every non-attempt_attack call site (spells,
	# projectiles, splash, DoT-bypass paths) routes through here. Builds a
	# 1-entry typed dict and feeds resolve_swing so single-hit callers get
	# the same evasion / footwork / reflective / thorns / crystal semantics
	# as a regular weapon swing.
	if damage_type == "":
		damage_type = "physical"
	return resolve_swing({damage_type: raw}, attacker)

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
# Dungeon-grid lookup helper for actor positional queries (e.g. of_tidesong
# wants "is the defender standing on water"). Actor's parent is ActorLayer
# whose parent is Dungeon. Returns false if the chain doesn't resolve or
# the cell is out of bounds.
func _is_cell_water(cell: Vector2i) -> bool:
	var parent: Node = get_parent()
	if parent == null:
		return false
	var d: Node = parent.get_parent()
	if d == null or not "grid" in d:
		return false
	var g: Variant = d.grid
	if not (g is Array) or (g as Array).is_empty():
		return false
	var rows: Array = g
	if cell.y < 0 or cell.y >= rows.size():
		return false
	var row: Array = rows[cell.y]
	if cell.x < 0 or cell.x >= row.size():
		return false
	return int(row[cell.x]) == C.T_WATER

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

# Find the nearest enemy (Chebyshev distance) within `radius` tiles of
# `near`, excluding `near` and self. Returns null if none. Used by
# §1.H of_chainspark and any future on-target chain primitives.
func _find_nearest_within(near: Actor, radius: int, skip: Dictionary = {}) -> Actor:
	if not is_instance_valid(near):
		return null
	var parent: Node = get_parent()
	if parent == null:
		return null
	var best: Actor = null
	var best_d: int = radius + 1
	for child in parent.get_children():
		if not (child is Actor) or child == near or child == self:
			continue
		var c: Actor = child as Actor
		if not c.is_alive:
			continue
		if skip.has(c.get_instance_id()):
			continue
		var dx: int = absi(c.cell.x - near.cell.x)
		var dy: int = absi(c.cell.y - near.cell.y)
		var cheb: int = maxi(dx, dy)
		if cheb > 0 and cheb <= radius and cheb < best_d:
			best = c
			best_d = cheb
	return best

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
	# `blinded`: 30% chance to fan-out the swing entirely. Sandblast's
	# Blinding Grit affix applies it. Eats the cooldown either way so
	# the blind ticks down on missed swings too. Spell expansion 2026-06-04.
	if has_status("blinded") and randf() < 0.30:
		return 0
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
	# Ephemeral conditional damage bonuses additively sum, then cap at
	# +30% per swing (a10 §5.1, S2 cap rules). Pre-cap, holy+brutal+cold+
	# arcane+demon+harm+rage+stealthy could compound to ~7.96× peak
	# (a10 §4.1). Each conditional contributes a flat fraction; total is
	# clamped before applying alongside str_mult (a permanent stat scaler
	# — NOT ephemeral). The cap is the floor for all future conditional
	# affixes (Berserker, Hunter, Sundering, Tempest …) so adding more
	# can't burst the ceiling.
	var ephemeral_sum: float = 0.0
	if not tags.is_empty():
		if "precision" in tags:
			crit_bonus = clampf(float(_precision_streak) * 5.0, 0.0, 50.0)
		var target_id: String = other.combat_label() if is_instance_valid(other) else ""
		if "holy" in tags and _StatusOverlay.enemy_matches_any(target_id, _StatusOverlay.HOLY_HATES):
			ephemeral_sum += 0.50
		if "dragon_bane" in tags and _StatusOverlay.enemy_matches_any(target_id, _StatusOverlay.DRAGON_HATES):
			ephemeral_sum += 0.50
		# `brutal`: +25% damage against targets below 30% HP (executioner).
		if "brutal" in tags and is_instance_valid(other) and other.max_hp > 0:
			if float(other.hp) / float(other.max_hp) <= 0.3:
				ephemeral_sum += 0.25
		# `cold`: +20% damage to already-frozen targets (the chance to
		# freeze itself is post-attack so the freeze applies for the
		# NEXT swing's bonus, not this one).
		if "cold" in tags and is_instance_valid(other) and other.has_status("frozen"):
			ephemeral_sum += 0.20
		# `elemental`: bonus damage scales with character level. Weapon
		# grows with the wielder. Bot's level via cast; enemies skip
		# (no level concept beyond the floor multiplier).
		if "elemental" in tags and self is Bot:
			var lvl: int = (self as Bot).level
			ephemeral_sum += 0.01 * float(lvl)
		# `arcane`: every 4th swing fires a +50% magic burst.
		if "arcane" in tags:
			_arcane_swing_count += 1
			if _arcane_swing_count >= 4:
				_arcane_swing_count = 0
				ephemeral_sum += 0.50
		# `demon`: inverse of holy — +25% damage vs HOLY_HATES targets
		# (undead/demon already favored by holy; demon stacks with it
		# rather than gating). Lore: a demonic weapon hates the same
		# things holy ones do, but for different reasons.
		var target_id_d: String = other.combat_label() if is_instance_valid(other) else ""
		if "demon" in tags and _StatusOverlay.enemy_matches_any(target_id_d, _StatusOverlay.HOLY_HATES):
			ephemeral_sum += 0.25
		# `ponderous`: heavy weapon — +10% damage but slower swing
		# (swing-rate handled in recompute_stats; here just the dmg).
		if "ponderous" in tags:
			ephemeral_sum += 0.10
		# `stealth` / first-strike: bot under "stealthy" status lands
		# +25% damage. Status is a one-shot — clear after the hit
		# below. Granted at floor build via the stealthy flavor on gear
		# (see Bot._refresh_stealthy_status).
		if has_status("stealthy"):
			ephemeral_sum += 0.25
		# `first_blood` (S5 Tengu Sky-Striker Helm, a10 5.5.B rescope):
		# +20% on the FIRST swing of a new encounter. "New encounter" =
		# ≥3s since the last kill landed by this bot, so chained pack
		# clears don't repeatedly fire it. Flat additive (vs guaranteed
		# crit in a04) — guaranteed crit composed catastrophically with
		# crit_multiplier_pct.
		if "first_blood" in tags and self is Bot:
			var bot_fb: Bot = self as Bot
			var since_kill: int = Time.get_ticks_msec() - bot_fb._last_kill_at_msec
			if since_kill >= 3000:
				ephemeral_sum += 0.20
	# `harm` (defender-worn): +25% damage dealt and +25% damage taken
	# (the receive side is in take_damage). Applies regardless of weapon.
	if "harm" in def_tags:
		ephemeral_sum += 0.25
	# `rage` (defender-worn): stacking +5% atk per kill in last 6s, max
	# +30%. State maintained on attacker; cleared on expiry in
	# attempt_attack so we don't need a separate tick.
	if not def_tags.is_empty() and "rage" in def_tags:
		var now_r: float = float(Time.get_ticks_msec()) / 1000.0
		if now_r > _rage_expires_at:
			_rage_stacks = 0
		ephemeral_sum += 0.05 * float(_rage_stacks)
	# S4 Tier-1 affix conditional damage. Each contributes a flat fraction
	# into ephemeral_sum so the +30% per-swing cap absorbs them alongside
	# pre-existing flavor-tag contributions. Combat-math change confined
	# to the same lane S2 already governs.
	if self is Bot:
		var bot_self: Bot = self as Bot
		# of_hunter — full-HP-bracket damage. ≥80% HP threshold per a02
		# P-13 (rescoped peak +20% at T5).
		if bot_self.hunter_pct > 0.0 and is_instance_valid(other) and other.max_hp > 0:
			if float(other.hp) / float(other.max_hp) >= 0.8:
				ephemeral_sum += bot_self.hunter_pct / 100.0
		# §1.H of_executioner_pact — low-hp target damage. <30% HP threshold
		# per a02 P-001, capped 40 in stat_calc. Mirror of of_hunter shape.
		if bot_self.low_hp_target_dmg_pct > 0.0 and is_instance_valid(other) and other.max_hp > 0:
			if float(other.hp) / float(other.max_hp) < 0.30:
				ephemeral_sum += bot_self.low_hp_target_dmg_pct / 100.0
		# §1.H of_glass_cannon — self-high-hp damage. >80% HP threshold
		# per a02 P-002, capped 30. Mutex with low_hp_target_dmg_pct
		# resolved in stat_calc (whichever is larger wins; the other is 0).
		if bot_self.glass_cannon_dmg_pct > 0.0 and bot_self.max_hp > 0:
			if float(bot_self.hp) / float(bot_self.max_hp) > 0.80:
				ephemeral_sum += bot_self.glass_cannon_dmg_pct / 100.0
		# §2.E of_desperation — self-low-hp damage. <40% HP threshold per
		# a06-newstat-014, capped 30. Mutex pair with glass_cannon_dmg_pct
		# resolved in stat_calc. Couples with §1.H of_revenant (low-hp DR)
		# for the panic-mode build pivot — bot below 40% HP is now both
		# tougher AND deadlier.
		if bot_self.low_hp_dmg_pct > 0.0 and bot_self.max_hp > 0:
			if float(bot_self.hp) / float(bot_self.max_hp) < 0.40:
				ephemeral_sum += bot_self.low_hp_dmg_pct / 100.0
		# §1.H of_kingslayer — boss/elite/miniboss damage. Per a02 P-004,
		# capped 40. Reads the target's is_boss / is_miniboss flag (Enemy).
		if bot_self.boss_dmg_pct > 0.0 and is_instance_valid(other) and other is Enemy:
			var oe: Enemy = other as Enemy
			if oe.is_boss or oe.is_miniboss:
				ephemeral_sum += bot_self.boss_dmg_pct / 100.0
		# §2.E damage_vs_unique_pct — sibling to kingslayer; fires vs
		# pack_tier == PACK_RARE (named elite mobs). a06-newstat-016,
		# a10 cap 40. Boss/miniboss already have boss_dmg_pct cover —
		# this lane targets the elite-density middle ground.
		if bot_self.damage_vs_unique_pct > 0.0 and is_instance_valid(other) and other is Enemy:
			var oe2: Enemy = other as Enemy
			if oe2.pack_tier == Enemy.PACK_RARE:
				ephemeral_sum += bot_self.damage_vs_unique_pct / 100.0
		# §1.H of_avenger — recently-hurt damage. 3s window after last
		# hit; revenge status set on take_damage. revenge_dmg_pct already
		# capped 50 in stat_calc.
		if bot_self.revenge_dmg_pct > 0.0 and has_status("revenge"):
			ephemeral_sum += bot_self.revenge_dmg_pct / 100.0
		# §1.H of_first_strike — per-target one-time amp on the first hit
		# this floor. Caps abuse via the per-target gate alone (a02 P-006);
		# stat_calc clamps the source at 120 so a 5×T5 stack (DR'd 220)
		# can't blast a single hit past 4× weapon damage. Mark target as
		# hit AFTER the swing so the same swing's ephemeral lane gets the
		# bonus. Per-floor reset cleared via dungeon._build_floor.
		# §1.H of_vulnerability_mark (a09-cond-002) shares the same
		# per-target gate but applies the "marked" status to the target
		# instead of an attacker-side ephemeral amp — durable across
		# multi-hit follow-up (DoTs, allies, spells all read marked).
		if (bot_self.first_hit_pct > 0.0 or bot_self.first_hit_mark_pct > 0.0) \
				and is_instance_valid(other):
			var oid: int = other.get_instance_id()
			if not bot_self._first_strike_hit_ids.has(oid):
				if bot_self.first_hit_pct > 0.0:
					ephemeral_sum += bot_self.first_hit_pct / 100.0
				if bot_self.first_hit_mark_pct > 0.0:
					other.add_status("marked", 4.0)
				bot_self._first_strike_hit_ids[oid] = true
		# §1.H of_butcher — pack-density damage. Per a02 P-005, +X% per
		# enemy within 3 tiles, cap 5 enemies (so cap-tier T5×5=+50%).
		# Walks sibling actors — parent owns bot + enemies, identical to
		# _find_adjacent_actor's traversal. Linear scan over ~5-15 enemies
		# is cheap; keeps the affix free of dungeon back-references.
		if bot_self.pack_dmg_per_enemy_pct > 0.0:
			var p: Node = get_parent()
			if p != null:
				var nearby: int = 0
				for child in p.get_children():
					if not (child is Enemy):
						continue
					var ce: Enemy = child as Enemy
					if not ce.is_alive:
						continue
					var dx: int = absi(ce.cell.x - bot_self.cell.x)
					var dy: int = absi(ce.cell.y - bot_self.cell.y)
					if dx <= 3 and dy <= 3 and (dx + dy) > 0:
						nearby += 1
						if nearby >= 5:
							break
				if nearby > 0:
					ephemeral_sum += (bot_self.pack_dmg_per_enemy_pct / 100.0) * float(nearby)
		# of_berserker — on-kill stacks. _berserker_stacks ages out via
		# 3s window; each stack contributes berserker_peak_pct/5 (peak
		# pct is the 5-stack total). Mirrors `rage` shape.
		if bot_self.berserker_peak_pct > 0.0:
			var now_b: float = float(Time.get_ticks_msec()) / 1000.0
			if now_b > bot_self._berserker_expires_at:
				bot_self._berserker_stacks = 0
			if bot_self._berserker_stacks > 0:
				var per_stack: float = bot_self.berserker_peak_pct / 5.0 / 100.0
				ephemeral_sum += per_stack * float(bot_self._berserker_stacks)
		# of_berserker_rage — STR-scaling per 5-rank, peak at 10 ranks.
		# str_excess clamped to 50 so the 10-rank cap holds at every
		# alloc level (Minotaur stat dump can hit ~109 excess; the cap
		# keeps bursts inside the +25% rescope).
		if bot_self.str_dmg_per5_peak_pct > 0.0 and "str_stat" in bot_self:
			var str_excess_b: int = int(bot_self.str_stat) - 5
			var ranks_b: int = clampi(str_excess_b / 5, 0, 10)
			var per_rank_b: float = bot_self.str_dmg_per5_peak_pct / 10.0 / 100.0
			ephemeral_sum += per_rank_b * float(ranks_b)
		# of_synergy — additive flat to all damage WHEN hybrid triplet
		# active (Str-coded + Dex-coded + Int-coded affix in the loadout).
		# synergy_pct already capped 12 in stat_calc.
		if bot_self.synergy_active and bot_self.synergy_pct > 0.0:
			ephemeral_sum += bot_self.synergy_pct / 100.0
		# S10 — Wrath Charge self-buff. While "wrath" status is ticking,
		# +20% weapon damage. Fixed 4s window (a10 §3.2 prop-5 rescope);
		# of_lingering must NOT extend the timer — Wrath Charge fires with
		# duration baked in at the cast site, not via spell_duration_pct.
		if has_status("wrath"):
			ephemeral_sum += 0.20
		# of_sundering — apply target armor-stack debuff BEFORE clamping
		# ephemeral_sum, so the next-swing reduction shows as the same
		# arch shape as armor on the defender's side. Stack count caps
		# at 2 per a10 P-11 rescope. Status-overlay backed for HUD legibility.
		if bot_self.sundering_per_stack > 0 and is_instance_valid(other):
			other.add_sunder_stack(bot_self.sundering_per_stack)
		# S11 of_wolf_kinship (a07 §6.5 Grum). +15% damage vs wolf-family
		# enemies (wolf, hound, hell hound, wolf spider). Reads the
		# defender's enemy_id; matches DCSS's wolf-family roster.
		if bot_self.wolf_kinship_pct > 0.0 and is_instance_valid(other) and other is Enemy:
			var oid: String = String((other as Enemy).enemy_id)
			if oid in ["wolf", "hound", "hell_hound", "wolf_spider"]:
				ephemeral_sum += bot_self.wolf_kinship_pct / 100.0
		# S11 of_tidesong (a07 §6.8 Ilsuiw). +25% damage vs targets standing
		# on a water tile. Cell-to-tile lookup via the dungeon grid.
		if bot_self.tidesong_water_pct > 0.0 and is_instance_valid(other) and other is Enemy:
			if _is_cell_water((other as Enemy).cell):
				ephemeral_sum += bot_self.tidesong_water_pct / 100.0
	var dmg_mult: float = 1.0 + minf(0.30, maxf(0.0, ephemeral_sum))

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
	# Strength build buffs hybrid weapons evenly. Capped at ×1.30 to
	# match the meta×qmult and ephemeral ceilings (S2 / a10 §10). Pre-
	# cap, lvl-30 alloc=50 STR Minotaur reached str_mult ×2.68, which
	# layered on top of the post-baseline damage_max pushed peak swings
	# to ~900 — V4 reference-build failure. STR still scales linearly
	# below ~20 excess (1.0+0.02×x clears 1.30 at x=15), so early-game
	# STR identity stays intact; only endgame stat dumps are clamped.
	var str_excess: int = 0
	if "str_stat" in self:
		str_excess = int(self.str_stat) - 5
	var str_mult: float = clampf(1.0 + float(str_excess) * 0.02, 1.0, 1.30)
	# Enchant-combo damage modifier — fires per damage type so combos
	# like Brittle Storm (+50% lightning vs frozen) and Quench (+100%
	# fire vs frozen) interact correctly with hybrid weapons.
	var combo_id: String = combat_weapon_combo_id()
	if combo_id != "":
		for k in typed.keys():
			var combo_mult: float = EnchantCombos.apply_damage_mod(combo_id, self, other, int(typed[k]), String(k))
			typed[k] = int(round(float(typed[k]) * combo_mult))
	if dmg_mult != 1.0 or str_mult != 1.0:
		var combo_mult_full: float = dmg_mult * str_mult
		for k in typed.keys():
			typed[k] = int(round(float(typed[k]) * combo_mult_full))
	# §1.H of_doomstrike (a02 P-013, a10 cap 100): every 5th swing fires
	# at +X% damage AND has crit suppressed (a10 design rule prevents the
	# boost from compounding crit). Counter increments per swing; resets
	# at 5 ≤ count. Bot-only.
	var is_doomstrike: bool = false
	if self is Bot:
		var bot_ds: Bot = self as Bot
		if bot_ds.doomstrike_dmg_pct > 0.0:
			bot_ds._doomstrike_swing_count += 1
			if bot_ds._doomstrike_swing_count >= 5:
				bot_ds._doomstrike_swing_count = 0
				is_doomstrike = true
				var ds_mult: float = 1.0 + bot_ds.doomstrike_dmg_pct / 100.0
				for k in typed.keys():
					typed[k] = int(round(float(typed[k]) * ds_mult))
	var crit: bool = false
	# Combo crit bonus (e.g. Judgement +10%).
	var roll_chance: float = crit_chance + crit_bonus + EnchantCombos.crit_bonus_for(combo_id)
	if is_doomstrike:
		roll_chance = 0.0
	if roll_chance > 0.0 and randf() * 100.0 < roll_chance:
		# S9 crit_multiplier_pct (a06 §2.1). Bot reads its own field; mundane
		# actors fall back to the const 1.5×. Cap is enforced in stat_calc
		# (+35%) so peak hit at 75% crit × ×1.85 stays inside the ceiling.
		var crit_mult: float = CRIT_MULTIPLIER
		if self is Bot:
			crit_mult = CRIT_MULTIPLIER + float((self as Bot).crit_multiplier_pct) / 100.0
		for k in typed.keys():
			typed[k] = int(round(float(typed[k]) * crit_mult))
		crit = true
	# Stash crit state on a meta flag so combo on-hit handlers (e.g.
	# Judgement: crits chain to adjacent foe) can read it.
	set_meta("just_crit", crit)
	# Update precision streak — reset on crit, grow on miss-of-crit.
	if "precision" in tags:
		_precision_streak = 0 if crit else _precision_streak + 1
	# Resolve the whole swing in one call so avoidance gates (evasion,
	# footwork, reflective) and post-mitigation returns (thorns, crystal)
	# fire ONCE per swing, not once per typed component. Pre-fix: a
	# 3-element hybrid swing got 3 independent dodge rolls and sent 3
	# independent thorns/crystal returns to the attacker, which could
	# multi-emit `died` if the first return chunk killed.
	# `raw` retained as the top-line aggregate for downstream tag procs
	# that need a single number (thunderous chain splash, death splash,
	# etc).
	var raw: int = 0
	for k in typed.keys():
		raw += int(typed[k])
	var dealt: int = other.resolve_swing(typed, self)
	var killed: bool = is_instance_valid(other) and not other.is_alive
	# Post-attack tag mechanics. `vampiric` heals 8% of damage dealt
	# back to the attacker — capped at max_hp. Defended/dodged hits
	# (dealt<=0) don't heal. `fire` applies a 3-tick burn DoT to the
	# target dealing 4% of their max_hp per tick (0.5s interval).
	if dealt > 0 and not tags.is_empty():
		# §2.I mummy: defender (other) is a Mummy bot → no lifesteal,
		# regardless of attacker tag. Dry bone yields no blood.
		var defender_is_mummy: bool = is_instance_valid(other) and other is Bot \
				and (other as Bot).species_id == "mummy"
		if "vampiric" in tags and is_alive and not defender_is_mummy:
			var heal: int = int(round(float(dealt) * 0.08))
			if heal > 0:
				hp = clampi(hp + heal, 0, max_hp)
				_update_hp_bar()
		if "fire" in tags and is_instance_valid(other) and other.is_alive:
			# 3 ticks × 4% max_hp = 12% max_hp total over 1.5s. Refreshes
			# duration on re-application; doesn't stack damage.
			var per_tick: int = maxi(1, int(round(float(other.max_hp) * 0.04)))
			other.add_burn(per_tick, 3, 0.5, self)
		if "cold" in tags and is_instance_valid(other) and other.is_alive and randf() < 0.15:
			# 0.5s freeze — short window so the +20% on next swing only
			# usually lands once, not the whole fight. Doesn't apply
			# slow on enemy speed (would need a movement-tick hook).
			other.add_status("frozen", 0.5)
		if "poison" in tags and is_instance_valid(other) and other.is_alive:
			# 4-tick poison DoT (similar shape to fire but slightly less
			# per tick). Uses the existing `poisoned` ENCH overlay.
			var poison_per_tick: int = maxi(1, int(round(float(other.max_hp) * 0.03)))
			other.add_poison(poison_per_tick, 4, 0.5, self)
	# Stealth single-strike consumed.
	if has_status("stealthy"):
		remove_status("stealthy")
	# `sound`: 10% chance to stun the target for 1s on a successful hit.
	if dealt > 0 and "sound" in tags and is_instance_valid(other) and other.is_alive and randf() < 0.10:
		other.add_status("stunned", 1.0)
	# `dual`: every successful hit fires an immediate off-hand swing at
	# 50% damage. DCSS gyre-and-gimble pattern — the off-hand IS the
	# weapon's second blade, which is why dual items also lock the
	# shield slot (Bot.is_two_handed). Guarded against recursion via
	# _dual_attacking so the off-hand swing can't itself trigger
	# another. Skips animation tween + crit roll — feels like one
	# fluid two-strike sequence instead of two distinct swings.
	# 2026-06-05 — was a 15% chance proc; now deterministic at half damage
	# so the shield trade-off actually pays off.
	if dealt > 0 and "dual" in tags and is_instance_valid(other) and other.is_alive and not _dual_attacking:
		_dual_attacking = true
		var raw2: int = int(round(float(atk) * 0.50))
		other.take_damage(maxi(1, raw2), self)
		_dual_attacking = false
	# Rage: each KILL by this attacker adds a stack (cap +30%, refresh
	# 6s window). Defender-worn so only the wearer accumulates stacks.
	if killed and "rage" in def_tags:
		_rage_stacks = mini(_rage_stacks + 1, 6)
		_rage_expires_at = float(Time.get_ticks_msec()) / 1000.0 + 6.0
	# of_berserker (a02 P-12): on-kill stack +N% per kill (cap 5 stacks,
	# 3s window). Bot-only so only the bot accumulates Berserker stacks.
	if killed and self is Bot:
		var bot_kk: Bot = self as Bot
		if bot_kk.berserker_peak_pct > 0.0:
			bot_kk._berserker_stacks = mini(bot_kk._berserker_stacks + 1, 5)
			bot_kk._berserker_expires_at = float(Time.get_ticks_msec()) / 1000.0 + 3.0
		# §1.H of_tactician — same shape, cap 4, 3s window. Independent
		# stacks/timer from of_berserker so the two affixes layer cleanly
		# (one feeds melee ephemeral, the other feeds spell CDR).
		if bot_kk.kill_streak_cdr_pct > 0.0:
			bot_kk._tactician_stacks = mini(bot_kk._tactician_stacks + 1, 4)
			bot_kk._tactician_expires_at = float(Time.get_ticks_msec()) / 1000.0 + 3.0
		# S5 race-anchor: stamp last-kill time for first_blood encounter
		# gating, and feed `feast` worn-tag (Troll Hide) the on-kill heal
		# subject to a 50% MHP/s rolling-window cap so a 5-mob pack clear
		# can't insta-fill (a10 5.6.A rescope).
		bot_kk._last_kill_at_msec = Time.get_ticks_msec()
		if "feast" in def_tags:
			var heal: int = int(round(float(bot_kk.max_hp) * 0.02))
			if heal > 0:
				var now_ms: int = Time.get_ticks_msec()
				if now_ms - bot_kk._feast_window_start_msec >= 1000:
					bot_kk._feast_window_start_msec = now_ms
					bot_kk._feast_window_heal = 0
				var window_cap: int = int(round(float(bot_kk.max_hp) * 0.50))
				var allowed: int = maxi(0, window_cap - bot_kk._feast_window_heal)
				var applied: int = mini(heal, allowed)
				if applied > 0:
					bot_kk.hp = clampi(bot_kk.hp + applied, 0, bot_kk.max_hp)
					bot_kk._feast_window_heal += applied
					bot_kk._update_hp_bar()
		# S11 of_serpent_growth (a07 §6.7 Hydra-Scale Cloak). +1 max HP per
		# kill on this floor up to hp_per_kill_cap. Both max_hp and hp grow
		# so the bot benefits immediately — refunds the kill's combat
		# state. Counter resets each floor (dungeon._floor_started reset).
		if bot_kk.hp_per_kill_cap > 0 and bot_kk.hp_per_kill_granted_this_floor < bot_kk.hp_per_kill_cap:
			bot_kk.hp_per_kill_granted_this_floor += 1
			bot_kk.max_hp += 1
			bot_kk.hp = mini(bot_kk.hp + 1, bot_kk.max_hp)
			bot_kk._update_hp_bar()
		# §1.H of_drainblade (a02 P-023): flat HP heal per kill. Caps via
		# stat_calc clamp (30) + the existing serpent_growth cap on max_hp
		# growth. A11 G1 recovery cap respected because per-kill !=
		# per-second; sustained pack-clear at 1 kill/s = ≤30 hp/s ≤
		# max_hp×0.10/s for any max_hp ≥ 300.
		if bot_kk.hp_per_kill_flat > 0 and bot_kk.hp < bot_kk.max_hp:
			bot_kk.hp = mini(bot_kk.hp + bot_kk.hp_per_kill_flat, bot_kk.max_hp)
			bot_kk._update_hp_bar()
		# S11 of_polymorph (a07 §6.4 Kirke's Pendant). First kill each
		# floor splits the kill into a "friendly slime" that strikes the
		# nearest adjacent live enemy for a flat-50-ATK splash (a10 6.4
		# rescope from "60% bot ATK" → 50 absolute cap so the splash
		# can't scale with endgame Minotaur ATK and break ceiling).
		if bot_kk.polymorph_first_kill and not bot_kk.polymorph_used_this_floor:
			bot_kk.polymorph_used_this_floor = true
			var nearby: Actor = _find_adjacent_actor(other)
			if nearby != null and nearby.is_alive:
				nearby.take_damage(50, self)
	# of_bloodletting (a02 P-9 rescoped to flat values): on-crit, apply
	# a flat-DPS bleed for 4 seconds. Stack count caps at 4 per a02 spec;
	# refreshes duration on re-crit. Uses the existing bleeding status
	# hook + dot/per-tick scheduler (same shape as `fire` enchant).
	if crit and dealt > 0 and is_instance_valid(other) and other.is_alive and self is Bot:
		var bot_bl: Bot = self as Bot
		if bot_bl.bloodletting_per_stack > 0:
			# 4 ticks × 1s = 4s total. Per-tick = bloodletting_per_stack.
			# Stacks cap implicit via add_bloodletting helper.
			other.add_bloodletting(bot_bl.bloodletting_per_stack, self)
		# §1.H of_hunter_mark (a02 P-009, a11 G7) — on-crit, apply 4s
		# "marked" status to target. Read at typed-damage-application time
		# so all subsequent hits (melee, spells, DoTs) read the amp.
		# 4s window per a02 spec. Per-target gate via add_status overwrite.
		if bot_bl.crit_mark_dmg_pct > 0.0:
			other.add_status("marked", 4.0)
		# §1.H of_chainspark (a02 P-014, a10 cap 50% of crit dmg). On-crit,
		# find nearest enemy within 4 tiles of the primary target and zap
		# them for crit_chain_pct% of the crit's damage. The chain hit
		# routes through take_damage → resolve_swing so armor/mit/resists
		# apply normally. Uses the bot's weapon_damage_type so element-
		# flagged weapons chain in their own element.
		if bot_bl.crit_chain_pct > 0.0:
			var spark: Actor = _find_nearest_within(other, 4)
			if spark != null and spark.is_alive:
				var spark_dmg: int = maxi(1, int(round(float(dealt) * bot_bl.crit_chain_pct / 100.0)))
				spark.take_damage(spark_dmg, self, bot_bl.weapon_damage_type)
	# §1.H of_serrated_edge (a02 P-021): every landed hit applies a 4s
	# bleed at flat dmg/sec. Non-stacking; re-applies refresh duration +
	# per-tick (whichever is larger of bloodletting on-crit OR serrated
	# on-hit wins the per-tick value via _apply_dot_status overwrite).
	# Bot-only and weapon-only by affix slot eligibility.
	if dealt > 0 and self is Bot and is_instance_valid(other) and other.is_alive:
		var bot_se: Bot = self as Bot
		if bot_se.weapon_bleed_per_sec > 0:
			other.add_bloodletting(bot_se.weapon_bleed_per_sec, self)
		# §1.H of_zealous_strike (a02 P-022): every landed hit applies a 3s
		# holy DoT. Same true-damage tick path as bleeding via a distinct
		# "smite" status. Composes with bleeding on the same target — they
		# tick independently and read separately in the HUD overlay.
		if bot_se.holy_dot_per_sec > 0:
			other.add_smite(bot_se.holy_dot_per_sec, self)
	# S11 of_bleed_on_miss (a07 §6.1 Sigmund's Sickle). On a missed swing
	# (dealt == 0 — defender evaded/blocked), apply a 3s bleed (4 dmg/s).
	# Compensates daggers/scythes for swings that whiff against high-evasion
	# enemies. Bot-only so monster swings don't bleed the bot.
	if dealt == 0 and self is Bot and is_instance_valid(other) and other.is_alive:
		if (self as Bot).bleed_on_miss:
			other.add_bloodletting(4, self)
		# §1.H of_riposte_strike (a09-conditional-001). On evade/block,
		# counter-strike for riposte_dmg_pct% of weapon damage. Per-second
		# proc cap via _last_riposte_msec; re-entry guard via _riposte_active
		# so the counter-swing's own resolve_swing can't fire another riposte
		# if the target ALSO dodges it. Routes through take_damage so existing
		# armor / mit / DoT pipes apply.
		var bot_rs: Bot = self as Bot
		if bot_rs.riposte_dmg_pct > 0.0 and not bot_rs._riposte_active:
			var now_rs: int = Time.get_ticks_msec()
			if now_rs - bot_rs._last_riposte_msec >= 1000:
				bot_rs._last_riposte_msec = now_rs
				bot_rs._riposte_active = true
				var weap_avg: int = int(round(float(bot_rs.damage_min + bot_rs.damage_max) * 0.5))
				var rip_dmg: int = maxi(1, int(round(float(weap_avg) * bot_rs.riposte_dmg_pct / 100.0)))
				other.take_damage(rip_dmg, self, bot_rs.weapon_damage_type)
				bot_rs._riposte_active = false
	# S11 of_serpent_venom (a07 §6.9 Aizul's Snake-Fang Knife). Each landed
	# melee hit applies a stack of poison via the existing add_poison helper
	# (3 ticks × 0.5s, max 5 stacks via the cap inside add_poison). Mirrors
	# how the `poison` flavor tag composes — but venom_on_hit is unconditional
	# (no +pct damage chain), purely the DoT layer.
	if dealt > 0 and self is Bot and is_instance_valid(other) and other.is_alive:
		if (self as Bot).venom_on_hit:
			var per_tick: int = maxi(1, int(round(float(other.max_hp) * 0.02)))
			other.add_poison(per_tick, 3, 0.5, self)
	# S11 of_dancing (a07 §6.3 Eustachio's Dancing Sword). 25% chance on a
	# successful hit to fire an extra weapon-damage strike at the same
	# target. Reentry-guarded via _dancing_blade_active so the proc'd strike
	# can't itself proc. Bot-only.
	if dealt > 0 and self is Bot and is_instance_valid(other) and other.is_alive:
		var bot_db: Bot = self as Bot
		if bot_db.dancing_blade and not bot_db._dancing_blade_active and randf() < 0.25:
			bot_db._dancing_blade_active = true
			# Extra strike at half raw damage (avoids double-cresting the
			# +30% ephemeral cap; same shape as `dual` flavor's off-hand).
			var dance_dmg: int = maxi(1, int(round(float(raw) * 0.5)))
			other.take_damage(dance_dmg, self)
			bot_db._dancing_blade_active = false
	# of_echoes (a02 P-8): every Nth swing echoes 50% damage to the same
	# target. echo_min_n is the smallest N rolled across gear (smaller =
	# more frequent). Echo skips crit + ephemeral re-resolve to avoid
	# infinite recursion; just deals raw/2 routed through take_damage.
	if dealt > 0 and is_instance_valid(other) and other.is_alive and self is Bot:
		var bot_eh: Bot = self as Bot
		if bot_eh.echo_min_n > 0:
			bot_eh._echo_swing_count += 1
			if bot_eh._echo_swing_count >= bot_eh.echo_min_n:
				bot_eh._echo_swing_count = 0
				var echo: int = maxi(1, int(round(float(raw) * 0.5)))
				other.take_damage(echo, self)
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
	# Enchant-combo on-hit + on-kill handlers (Combustion, Plasma,
	# Pyre, etc). Component flavor procs already fired above via the
	# tag loop; combos add the layered effect on top.
	if combo_id != "" and dealt > 0 and is_instance_valid(other):
		EnchantCombos.apply_on_hit(combo_id, self, other, dealt, raw)
	if combo_id != "" and killed:
		EnchantCombos.apply_on_kill(combo_id, self, other)
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

# Override on Bot — returns the equipped weapon's enchant_combo id or
# "" if none. Used by EnchantCombos.apply_* dispatch in attempt_attack.
func combat_weapon_combo_id() -> String:
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
			target.add_poison(bleed_per_tick, 3, 0.6, self)  # reuse poison DoT shape
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
	# §2.I (S12) Naga signature — slow-immune. Short-circuit any
	# add_status call for "slowed" on a Naga bot. The signature also
	# routes through stat_calc to push poison_res to 100, but `slowed`
	# is a status not a damage type so it needs the dispatch here.
	if id == "slowed" and self is Bot and (self as Bot).species_id == "naga":
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
	# When the "ench" visual toggle is off, register the status logically
	# (so DoT scheduling, has_status checks, and mechanic reads still work)
	# but skip the sprite/overlay layer. DoTs are gameplay, not visual flair.
	if not VideoSettings.is_effect_enabled("ench"):
		var now_no_vis: float = float(Time.get_ticks_msec()) / 1000.0
		_statuses[id] = {
			"expires_at": now_no_vis + duration if duration > 0.0 else 0.0,
			"sprite": null,
		}
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
# of_sundering (a02 P-11 rescoped): apply a sunder stack to this actor,
# reducing physical armor for the next ~3s. Each call refreshes the
# duration and stacks per-stack reduction up to the rescoped cap (2).
# Called by attempt_attack when the attacker has of_sundering equipped.
func add_sunder_stack(per_stack_amount: int) -> void:
	var now: float = float(Time.get_ticks_msec()) / 1000.0
	if now > _sunder_expires_at:
		_sunder_amount = 0
		_sunder_stacks = 0
	if _sunder_stacks < _SUNDER_MAX_STACKS:
		_sunder_stacks += 1
		_sunder_amount += per_stack_amount
	_sunder_expires_at = now + _SUNDER_DURATION

# of_bloodletting (a02 P-9 rescoped): apply a flat-DPS bleed for 4s on
# crit. Bleed amount per tick = `per_tick`; ticks 1/sec for 4s. Re-applies
# refresh duration. Routes through the existing DoT scheduler so HUD
# overlay + tick math stays consistent. Bypasses immunity tags (bleed is
# physical, not poison/fire, so poison_res / fire_res don't gate it).
# §2.I (S12): true when self is a Mummy bot. Used to short-circuit
# bleed / poison / lifesteal-against effects per the mummy signature
# (undead-immune to status that fights regen). Cheap inline check.
func _is_mummy_defender() -> bool:
	return self is Bot and (self as Bot).species_id == "mummy"

func add_bloodletting(per_tick: int, attacker: Actor = null) -> void:
	if _is_mummy_defender():
		return  # §2.I mummy: bleed-immune
	_apply_dot_status("bleeding", per_tick, _scaled_dot_ticks(4, attacker), 1.0)

# §1.H of_zealous_strike (a02 P-022): apply a 3s holy DoT on landed hits.
# Same true-damage tick path as bleeding (DoTs bypass armor + resists by
# design). Distinct status_id "smite" so the HUD overlay reads correctly
# and a single defender can carry both bleeding + smite simultaneously.
func add_smite(per_tick: int, attacker: Actor = null) -> void:
	_apply_dot_status("smite", per_tick, _scaled_dot_ticks(3, attacker), 1.0)

# §2.E dot_duration_pct (a06-newstat-019, a10 cap 80). Scales tick count
# by the attacker's dot_duration_pct — same DPS, longer total damage.
# Mundane attackers / null attacker pass through unchanged.
func _scaled_dot_ticks(base_ticks: int, attacker: Actor) -> int:
	if attacker == null or not (attacker is Bot):
		return base_ticks
	var pct: float = float((attacker as Bot).dot_duration_pct)
	if pct <= 0.0:
		return base_ticks
	# Round to nearest int, floor of base_ticks so a 70% bonus on a
	# 4-tick base reads as 7 ticks (4 × 1.7 = 6.8 → 7).
	return maxi(base_ticks, int(round(float(base_ticks) * (1.0 + pct / 100.0))))

# §1.H of_warden_step (a02 P-026). Discharge a 2-tile AoE around the bot:
# damage every sibling actor within Chebyshev radius 2 for step_pulse_pct
# of weapon damage average. Visual ring via SpellAoe.spawn_ring at the
# bot's pixel position. Damage routes through take_damage so armor / mit
# / DoT pipes all apply.
func _warden_step_pulse(bot: Bot) -> void:
	var parent: Node = get_parent()
	if parent == null:
		return
	var weap_avg: int = int(round(float(bot.damage_min + bot.damage_max) * 0.5))
	var pulse_dmg: int = maxi(1, int(round(float(weap_avg) * bot.step_pulse_pct / 100.0)))
	for child in parent.get_children():
		if not (child is Enemy):
			continue
		var ce: Enemy = child as Enemy
		if not ce.is_alive:
			continue
		var dx: int = absi(ce.cell.x - bot.cell.x)
		var dy: int = absi(ce.cell.y - bot.cell.y)
		if maxi(dx, dy) <= 2 and (dx + dy) > 0:
			ce.take_damage(pulse_dmg, bot, bot.weapon_damage_type)
	# Visual ring — radius 2 cells in pixels.
	var origin: Vector2 = bot.position + Vector2(C.TILE_SIZE * 0.5, C.TILE_SIZE * 0.5)
	SpellAoe.spawn_ring(parent, origin, float(C.TILE_SIZE) * 2.0, Color(1.0, 0.85, 0.40, 0.85))

# §1.H a11 G4 reflect-emission window. Both of_thorns and of_aegis_thorns
# feed this bucket on the bot. Returns the actually-allowed emission
# (clamped to remaining budget for the active 1s window). Window resets
# when ≥1s has elapsed since it opened.
func _bot_emit_reflect(bot: Bot, requested: int, _attacker: Actor) -> int:
	if requested <= 0 or bot.max_hp <= 0:
		return 0
	var now_ms: int = Time.get_ticks_msec()
	if now_ms - bot._thorns_window_started_msec >= 1000:
		bot._thorns_window_started_msec = now_ms
		bot._thorns_emitted_in_window = 0
	var window_cap: int = maxi(1, int(round(float(bot.max_hp) * 0.05)))
	var allowed: int = maxi(0, window_cap - bot._thorns_emitted_in_window)
	var emitted: int = mini(requested, allowed)
	if emitted > 0:
		bot._thorns_emitted_in_window += emitted
	return emitted

func add_burn(per_tick: int, ticks: int, interval: float, attacker: Actor = null) -> void:
	# §2.I mummy: NOT immune to burn — fire still cooks dry bone. Only
	# bleed/poison/lifesteal-against gate per the brief. Burn falls
	# through normally.
	# fire_res grants immunity to burn DoT (matches DCSS rF+ stops
	# being on fire). Resists are wired on every actor; non-bot
	# actors return [] from combat_defense_tags so this is a no-op
	# for them.
	if "fire_res" in combat_defense_tags():
		return
	_apply_dot_status("burning", per_tick, _scaled_dot_ticks(ticks, attacker), interval)

func add_poison(per_tick: int, ticks: int, interval: float, attacker: Actor = null) -> void:
	if "poison_res" in combat_defense_tags():
		return
	if _is_mummy_defender():
		return  # §2.I mummy: poison-immune
	_apply_dot_status("poisoned", per_tick, _scaled_dot_ticks(ticks, attacker), interval)

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
