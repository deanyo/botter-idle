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
# Per-slot cooldown bookkeeping for autocast spells. Keyed by slot id
# (spell1..spell5); value = seconds until next fire. Initialized by
# SpellSystem.init_run at floor build; ticked + reset by SpellSystem.
var spell_cooldowns: Dictionary = {}
# Gear-side spell augments folded out of equipped affixes during
# recompute_stats. Read by SpellSystem when computing effective spell
# stats (cooldown, projectile count, area, duration, damage). Phase 2
# wires the affix → field rollup; until then defaults are no-op.
var spell_cdr_pct: float = 0.0
var spell_proj_bonus: int = 0
var spell_proj_speed_pct: float = 0.0
var spell_area_pct: float = 0.0
var spell_duration_pct: float = 0.0
var spell_damage_pct: float = 0.0
# Per-element damage modifiers (multiplicative on element-tagged damage).
# Element keys: fire, cold, thunderous, holy, poison, dark.
var spell_element_pct: Dictionary = {
	"fire": 0.0, "cold": 0.0, "thunderous": 0.0,
	"holy": 0.0, "poison": 0.0, "dark": 0.0,
}
# Per-class spell-damage multipliers from of_str_mastery / of_dex_mastery /
# of_int_mastery. spell_data.compute_damage adds the matching one (keyed
# off the spell's primary_stat) into dmg_mult.
var str_spell_dmg_pct: float = 0.0
var dex_spell_dmg_pct: float = 0.0
var int_spell_dmg_pct: float = 0.0
# S4 Tier-1 affix accumulators (a02 P-8/9/10/11/12/13/15/16/19/27/28
# rescoped per a10 §3.2). Rolled up by StatCalc.compute; combat / spell /
# drop hot paths read these directly. Caps applied in stat_calc.gd:
#   sage_per_unspent_pct ≤ 24, berserker_peak_pct ≤ 20, hunter_pct ≤ 20,
#   str_dmg_per5_peak_pct ≤ 25, synergy_pct ≤ 12. Flat affixes
#   (echo_min_n / sundering_per_stack / bloodletting_per_stack) cap by
#   their per-stack count in attempt_attack.
var sage_per_unspent_pct: float = 0.0
var berserker_peak_pct: float = 0.0
var hunter_pct: float = 0.0
var echo_min_n: int = 0
var tempest_cd_penalty_pct: float = 0.0
var sundering_per_stack: int = 0
var bloodletting_per_stack: int = 0
var gold_drop_pct: float = 0.0
var spell_tome_drop_pct: float = 0.0
var str_dmg_per5_peak_pct: float = 0.0
var synergy_pct: float = 0.0
var synergy_active: bool = false
# Per-run berserker stack state (of_berserker). Each enemy kill bumps
# the counter (cap 5); 3-second window from the LAST kill. Refreshes
# on subsequent kills. attempt_attack reads + ages.
var _berserker_stacks: int = 0
var _berserker_expires_at: float = 0.0
# Per-run echo counter (of_echoes). Smaller N is better; combat ticks
# this and emits a 50% echo when it crosses the threshold.
var _echo_swing_count: int = 0
# Ephemeral conditional spell bonus accumulator (a10 §5.1). Future
# conditional/trigger-based spell affixes (Wrath Charge, Curse of
# Brittlebone, Tempest active windows, Sage unspent-points scaling)
# write a percentage into this lane. spell_data.compute_damage sums
# what's active on the cast and clamps total at +30% per cast — the
# same ceiling weapon swings respect. Permanent stat scalers
# (spell_damage_pct, spell_element_pct, class lanes) live in their
# own already-capped fields; this one is the conditional bucket.
var ephemeral_spell_dmg_pct: float = 0.0
# Revive mutex (a10 §5.2 / a11 §2.11, S2 cap rules). Future revive
# sources (of_phoenix amulet, Cloak of the Last Heart, boss-anchor
# Phylactery, etc.) gate on this flag — only ONE revive may fire per
# floor, regardless of how many revive items are equipped. Cleared on
# floor_started so the next floor restores the budget. Without the
# mutex, stacking 3+ revive sources turns boss fights into auto-clear.
var revive_used_this_floor: bool = false
# S11 boss-anchor unique state (a07 §6.1-6.12). One field per implicit
# affix, copied back from StatCalc.compute. Combat / dungeon hot paths
# read these directly. Per-floor counters (cast_count, kill_hp_grant,
# polymorph_used, dancing-blade reentry guard) are reset by the
# floor_started signal handler.
var bleed_on_miss: bool = false
var dancing_blade: bool = false
var polymorph_first_kill: bool = false
var wolf_kinship_pct: float = 0.0
var anchor_regen: float = 0.0
var hp_per_kill_cap: int = 0
var tidesong_water_pct: float = 0.0
var venom_on_hit: bool = false
var phylactery_revive_pct: float = 0.0
var extra_chests_per_floor: int = 0
var fifth_cast_pct: float = 0.0
# §1.H attempt_attack-shape conditional affixes (a02 P-001..005, a10).
# Each rides ephemeral_sum (offensive) or mit_sum (defensive). Mutex
# pair (low_hp_target_dmg ⊥ glass_cannon) resolved in stat_calc; one
# of the two will be 0 if both rolled.
var low_hp_target_dmg_pct: float = 0.0
var glass_cannon_dmg_pct: float = 0.0
var low_hp_dr_pct: float = 0.0
var boss_dmg_pct: float = 0.0
var pack_dmg_per_enemy_pct: float = 0.0
var full_hp_armor_pct: float = 0.0
var weapon_bleed_per_sec: int = 0
var holy_dot_per_sec: int = 0
var revenge_dmg_pct: float = 0.0
var first_hit_pct: float = 0.0
var hp_per_kill_flat: int = 0
var melee_armor_pen_pct: float = 0.0
var spell_resist_pen_pct: float = 0.0
var crit_mark_dmg_pct: float = 0.0
var recoup_pct: float = 0.0
var move_spell_dmg_pct: float = 0.0
var thorns_flat: int = 0
var block_thorns_flat: int = 0
var first_hit_mark_pct: float = 0.0
var doomstrike_dmg_pct: float = 0.0
# Per-bot every-5th-swing counter for of_doomstrike. Mirrors
# _arcane_swing_count and _echo_swing_count patterns. Never resets
# between floors — feel is "every 5 swings", not "every 5 swings of
# the current floor."
var _doomstrike_swing_count: int = 0
# §1.H a11 G4: rolling-window emission cap on reflect sources. Sum of
# of_thorns + of_aegis_thorns reflect emitted per second ≤ max_hp×0.05.
# resolve_swing accumulates _thorns_emitted in the active window; when
# the window expires (>1s since first emission) the bucket resets.
var _thorns_emitted_in_window: int = 0
var _thorns_window_started_msec: int = 0
# §1.H of_recoup heal-over-time bucket. take_damage adds the rolled
# heal pool here (recoup_pct/100 × dealt); _process drains it across
# the configured 4s window. Pre-existing hp_regen_per_sec ticker
# governs delivery; bucket unit is fractional HP.
var _recoup_bucket: float = 0.0
var _recoup_window_remaining: float = 0.0
# §1.H of_first_strike per-floor target tracker. Keys are Enemy
# instance_ids; presence means "this enemy has been hit at least once
# this floor." Reset on floor_started in dungeon._build_floor.
var _first_strike_hit_ids: Dictionary = {}
# Per-floor counters for the boss-anchor mechanics. Reset on floor_started
# via dungeon.gd alongside revive_used_this_floor.
var polymorph_used_this_floor: bool = false
var hp_per_kill_granted_this_floor: int = 0
var spell_cast_count: int = 0
# Reentry guard for of_dancing — without this the proc-fired strike
# could itself proc, recursing one or two more times when the dice land.
var _dancing_blade_active: bool = false
# S5 race-anchor state. `_last_move_at_msec` tracks the last frame the
# bot took a step — `petrify` flavor reads it to grant -25% phys DR
# while stationary (Gargoyle Stoneflesh Plate). `_last_kill_at_msec`
# anchors the new-encounter window so `first_blood` (Tengu Sky-Striker
# Helm) only fires once per pause-between-fights. `_feast_window_*`
# enforce the 50% MHP/s heal cap on the `feast` worn-tag (Troll Hide
# Armor) — without it, a 5-mob pack clear nets +490 HP at endgame.
var _last_move_at_msec: int = 0
var _last_kill_at_msec: int = 0
var _feast_window_start_msec: int = 0
var _feast_window_heal: int = 0
# Primary stats (DCSS-style). Base 5/5/5; species adds str_flat/dex_flat/
# int_flat on top. Each stat point = +2% damage on its scaling spells +
# small contributions to derived stats (str→hp, dex→crit/haste, int→spell
# area + DoT duration). Authored straight on the bot rather than rolled
# up so save schema stays simple.
var str_stat: int = 5
var dex_stat: int = 5
var int_stat: int = 5
# Item-overhaul v2 (2026-06-04). Weapon = source of damage range +
# speed + base damage type. Empty hand: 1-2 phys, 1.0s. Set in
# recompute_stats from the equipped weapon.
var damage_min: int = 1
var damage_max: int = 2
var weapon_speed: float = 1.0
var weapon_damage_type: String = "physical"
var weapon_class: String = "1H"
# Hybrid weapon / "of Embers"-style affix damage. Keyed by damage_type
# string → {min: int, max: int}. Combat rolls a fresh value per swing.
var extra_damage: Dictionary = {}
# PoE-style defenses. Armor = flat phys mitigation. Evasion = % chance
# to dodge any incoming hit (typed and physical alike). Resistances =
# per-element % mitigation, capped at 75.
var armor: int = 0
var evasion: float = 0.0
var resistances: Dictionary = {
	"fire": 0.0, "cold": 0.0, "lightning": 0.0,
	"holy": 0.0, "poison": 0.0, "dark": 0.0, "physical": 0.0,
}
var lifesteal_pct: float = 0.0
# S9 — crit_multiplier_pct (a06 §2.1). actor.gd::attempt_attack reads this
# and the const ×1.5 base crit-mult to compute (1.5 + cmp/100) × base for
# crits. Soft-capped at +35% in stat_calc.gd (peak crit ×1.85).
var crit_multiplier_pct: float = 0.0
# S9 — block_chance / block_amount (a06 §2.2). Shield slot gates after
# evasion / footwork / reflective in actor.gd::resolve_swing. On block
# proc, subtract block_amount from each typed component (≥1 floor); if
# all zero → full block. Soft-capped 30% chance / +20 amount.
var block_chance: float = 0.0
var block_amount: int = 0
# Haste accumulator after caps (0..200). Surfaced as a field so UI
# layers can show "Haste +24%" without recomputing the inverse-of-
# attack_interval formula. 2026-06-06 stat-calc unification.
var haste_pct: float = 0.0
var blessings: Array = []
# Legacy run-only altar blessings persisted on these fields pre-2026-06-08.
# atk_pct/atk_flat/def_flat/hp_pct now flow through StatCalc.compute()'s
# blessing rollup directly (see stat_calc.gd). lifesteal_per_hit and
# hp_regen_per_sec stay live on the bot — combat reads them in the melee
# tick path (lifesteal at actor.gd:839, regen in Bot._process).
var hp_regen_per_sec: float = 0.0
var lifesteal_per_hit: int = 0
var loot_rarity_bonus: float = 0.0
var xp_gain_pct: float = 0.0
var _regen_accum: float = 0.0
# Vision-tag flavor: read by dungeon AI as a bonus to AGGRO_DISTANCE
# so a vision-equipped bot engages from further away.
var aggro_bonus: int = 0
var weapon_sprite: Sprite2D = null
var _weapon_swing_tween: Tween

func clear_blessings() -> void:
	blessings.clear()
	hp_regen_per_sec = 0.0
	lifesteal_per_hit = 0
	loot_rarity_bonus = 0.0
	xp_gain_pct = 0.0
	if _halo_sprite != null and is_instance_valid(_halo_sprite):
		_halo_sprite.queue_free()
	_halo_sprite = null
	# Drop every per-god status. Pre-2026-06-08 we only carried a single
	# generic "blessed" — now multiple gods stack one row each in the
	# buff bar, so we sweep all 22 + the legacy id for back-compat with
	# older save states / mid-flight transitions.
	for sid in StatusOverlay.STATUSES.keys():
		var sk: String = String(sid)
		if sk == "blessed" or sk.begins_with("blessed_"):
			remove_status(sk)

func grant_blessing(b: Dictionary) -> void:
	blessings.append(b)
	var k: String = String(b.get("kind", ""))
	var v: float = float(b.get("value", 0))
	match k:
		# atk_pct/atk_flat/def_flat/hp_pct/hp_regen are read directly out
		# of `blessings` by StatCalc.compute on the next recompute_stats —
		# no per-kind field write needed here. lifesteal_per_hit / loot /
		# xp_gain are still bot fields read by combat / drops / xp paths.
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
	# Per-god status: each altar contributes its own row to the buff
	# bar with its altar tile as the icon, so a player who blessed at
	# Trog + Zin + Sif Muna sees three deities stacked. Pre-2026-06-08
	# we collapsed every blessing to a single generic "blessed" icon.
	if god != "":
		var sid: String = "blessed_" + god
		if StatusOverlay.STATUSES.has(sid):
			add_status(sid, 0.0)
		else:
			add_status("blessed", 0.0)
	else:
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
# Species id (read from save_state). Set in apply_gear; consumed in
# recompute_stats to apply the species' stat modifiers. Defaults to
# "spriggan" so a fresh Bot before apply_gear still renders + computes
# stats reasonably.
var species_id: String = "spriggan"

func apply_gear(items_db: Dictionary, equipped_instances: Dictionary, save_state: Dictionary = {}) -> void:
	_items_db_cache = items_db
	equipped = equipped_instances.duplicate(true)
	upgrade_state = save_state
	species_id = String(save_state.get("species", "spriggan")) if not save_state.is_empty() else "spriggan"
	# Reset loot_rarity_bonus + xp_gain_pct before stacking — pre-2026-06-06
	# they were added on top of whatever was already there, so a double-
	# apply (from a buggy caller) would double-count species bonuses.
	# StatCalc.compute now folds species + bot-upgrade values in directly;
	# blessings still accumulate via grant_blessing.
	loot_rarity_bonus = 0.0
	xp_gain_pct = 0.0
	if not upgrade_state.is_empty():
		loot_rarity_bonus = BotUpgrades.total_for_stat(upgrade_state, "loot_rarity_bonus")
	var sp: Dictionary = SpeciesData.get_def(species_id)
	if not sp.is_empty():
		loot_rarity_bonus += float(sp.get("loot_pct", 0))
		xp_gain_pct += float(sp.get("xp_pct", 0))
	# Apply species sprite swap. set_texture is idempotent — safe to
	# call repeatedly.
	var sp_path: String = SpeciesData.sprite_path_for(species_id)
	if sp_path != "" and ResourceLoader.exists(sp_path):
		set_texture(load(sp_path))
	recompute_stats()
	hp = max_hp
	_update_hp_bar()
	_refresh_gear_overlays()

# Two-handed weapon base_types — equipping a 2H weapon auto-unequips
# the shield, and vice versa. Per-base_type list (consistent with
# DCSS — every claymore/halberd/battle_axe is 2H regardless of
# specific item). Worth keeping centralized so paperdoll/UI/tooltip
# can all reference the same source of truth.
const TWO_HANDED_BASE_TYPES := [
	# 2H axes
	"battle_axe", "broad_axe", "executioner_axe",
	# 2H polearms (everything but spear is 2H)
	"halberd", "bardiche", "scythe",
	# 2H swords
	"greatsword", "claymore", "double_sword", "triple_sword",
	# Big bludgeons
	"giant_club", "dire_flail",
	# Staves (always 2H)
	"quarterstaff", "lajatang",
]

static func is_two_handed_base_type(base_type: String) -> bool:
	return base_type in TWO_HANDED_BASE_TYPES

# Item-level "occupies both hands" check — true for canonical 2H base
# types or items explicitly flagged `weapon_class: "2H"` / `two_handed`.
# Dual-wield (`weapon_class: "dual"`) deferred — S6 deleted the only
# dual base (gyre); re-add this branch only if 10+ dual bases ship at once.
static func is_two_handed(item: Dictionary) -> bool:
	if item == null or item.is_empty():
		return false
	if is_two_handed_base_type(String(item.get("base_type", ""))):
		return true
	var wc: String = String(item.get("weapon_class", ""))
	if wc == "2H":
		return true
	return bool(item.get("two_handed", false))

# Swap an inventory item into its slot. Returns an array of DISPLACED
# instances (0..2) so the caller can re-insert them into inventory.
# Most equips displace 0 or 1 items. The 2H↔shield exclusion can
# displace TWO at once: equipping a 2H weapon when both weapon AND
# shield are filled returns [old_weapon, old_shield].
# Stat recompute preserves current HP delta (no full-heal cheese).
func equip_from_inventory(inst: Dictionary) -> Array:
	if typeof(inst) != TYPE_DICTIONARY:
		return []
	var base_id: String = String(inst.get("base_id", ""))
	if base_id == "" or not _items_db_cache.has(base_id):
		return []
	var item: Dictionary = _items_db_cache[base_id]
	var slot: String = String(item.get("slot", ""))
	if slot == "":
		return []
	# Species body-shape restriction. Octopodes can't wear body
	# armor / boots / helms; nagas can't wear boots. Returning [] = no
	# items displaced + no equip happened. Caller treats it as "blocked"
	# (the inventory item stays in inventory, no swap occurs).
	if not SpeciesData.can_wear(species_id, slot):
		return []
	# Ring slot resolution: items.json declares slot=="ring"; the
	# equipped dict has one `ring` slot for most species, but species
	# with slot_conversions (octopode/naga) get extra ring slots
	# (ring2/ring3/ring4). Pick the FIRST EMPTY ring slot so the
	# player gets multi-ring stacking organically. Only when all are
	# full do we displace ring (the original slot).
	if slot == "ring":
		var ring_ids: Array = SpeciesData.ring_slot_ids(species_id)
		var picked_ring: String = ""
		for r in ring_ids:
			if equipped.get(r, null) == null:
				picked_ring = r
				break
		if picked_ring == "":
			picked_ring = "ring"  # all full — displace ring1
		slot = picked_ring
	# Spell slot resolution (same pattern as rings). Spell items declare
	# slot="spell" in items.json; the equipped dict has 5 numbered slots.
	# Pick the first empty spell1..spell5; if all full, displace spell1.
	# Without this, equipping a spell would write to a key called "spell"
	# that no UI surface reads, which is the "equipped item disappears"
	# bug we hit pre-fix.
	if slot == "spell":
		var spell_ids: Array = ["spell1", "spell2", "spell3", "spell4", "spell5"]
		var picked_spell: String = ""
		for s in spell_ids:
			if equipped.get(s, null) == null:
				picked_spell = s
				break
		if picked_spell == "":
			picked_spell = "spell1"
		slot = picked_spell
	var displaced: Array = []
	# 2H/dual weapon ↔ shield exclusion. Equipping a 2H or dual-wield
	# weapon clears the shield slot back to inventory; equipping a
	# shield clears a 2H/dual weapon back to inventory. PoE/Diablo
	# pattern. Routes through is_two_handed(item) so dual-wield items
	# (e.g. Gyre) get the same treatment as canonical 2H — they occupy
	# the off-hand in lieu of a second blade. 2026-06-05.
	if slot == "weapon" and is_two_handed(item):
		var current_shield: Variant = equipped.get("shield", null)
		if current_shield != null and typeof(current_shield) == TYPE_DICTIONARY:
			displaced.append(current_shield)
			equipped["shield"] = null
	elif slot == "shield":
		var current_weapon: Variant = equipped.get("weapon", null)
		if current_weapon != null and typeof(current_weapon) == TYPE_DICTIONARY:
			var w_id: String = String(current_weapon.get("base_id", ""))
			if w_id != "" and _items_db_cache.has(w_id):
				if is_two_handed(_items_db_cache[w_id]):
					displaced.append(current_weapon)
					equipped["weapon"] = null
	# Direct displace of the slot we're filling.
	var direct: Variant = equipped.get(slot, null)
	if direct != null and typeof(direct) == TYPE_DICTIONARY:
		displaced.append(direct)
	equipped[slot] = inst.duplicate(true)
	var prev_max: int = max_hp
	recompute_stats()
	hp = clampi(hp + (max_hp - prev_max), 0, max_hp)
	_update_hp_bar()
	_refresh_gear_overlays()
	return displaced

func recompute_stats() -> void:
	# Single source of truth lives in StatCalc.compute. The bot's job
	# here is to feed inputs in and copy the result dict back onto its
	# own fields so combat code that reads `bot.damage_max`,
	# `bot.armor`, etc. keeps working unchanged. 2026-06-06 unification.
	var d: Dictionary = StatCalc.compute(
		equipped, _items_db_cache, upgrade_state, species_id,
		level, xp, gold, blessings,
	)
	str_stat = int(d.str)
	dex_stat = int(d.dex)
	int_stat = int(d.int)
	max_hp = int(d.max_hp)
	hp_regen_per_sec = float(d.hp_regen)
	armor = int(d.armor)
	evasion = float(d.evasion)
	resistances = d.resistances
	crit_chance = float(d.crit_chance)
	crit_multiplier_pct = float(d.get("crit_multiplier_pct", 0.0))
	block_chance = float(d.get("block_chance", 0.0))
	block_amount = int(d.get("block_amount", 0))
	haste_pct = float(d.haste_pct)
	lifesteal_pct = float(d.lifesteal_pct)
	damage_min = int(d.damage_min)
	damage_max = int(d.damage_max)
	weapon_speed = float(d.weapon_speed)
	weapon_damage_type = String(d.weapon_damage_type)
	weapon_class = String(d.weapon_class)
	attack_interval = float(d.attack_interval)
	extra_damage = d.extra_damage
	spell_cdr_pct = float(d.spell_cdr_pct)
	spell_proj_bonus = int(d.spell_proj_bonus)
	spell_proj_speed_pct = float(d.spell_proj_speed_pct)
	spell_area_pct = float(d.spell_area_pct)
	spell_duration_pct = float(d.spell_duration_pct)
	spell_damage_pct = float(d.spell_damage_pct)
	spell_element_pct = d.spell_element_pct
	str_spell_dmg_pct = float(d.get("str_spell_dmg_pct", 0.0))
	dex_spell_dmg_pct = float(d.get("dex_spell_dmg_pct", 0.0))
	int_spell_dmg_pct = float(d.get("int_spell_dmg_pct", 0.0))
	sage_per_unspent_pct = float(d.get("sage_per_unspent_pct", 0.0))
	berserker_peak_pct = float(d.get("berserker_peak_pct", 0.0))
	hunter_pct = float(d.get("hunter_pct", 0.0))
	echo_min_n = int(d.get("echo_min_n", 0))
	tempest_cd_penalty_pct = float(d.get("tempest_cd_penalty_pct", 0.0))
	sundering_per_stack = int(d.get("sundering_per_stack", 0))
	bloodletting_per_stack = int(d.get("bloodletting_per_stack", 0))
	gold_drop_pct = float(d.get("gold_drop_pct", 0.0))
	spell_tome_drop_pct = float(d.get("spell_tome_drop_pct", 0.0))
	str_dmg_per5_peak_pct = float(d.get("str_dmg_per5_peak_pct", 0.0))
	synergy_pct = float(d.get("synergy_pct", 0.0))
	synergy_active = bool(d.get("synergy_active", false))
	# S11 boss-anchor implicits.
	bleed_on_miss = bool(d.get("bleed_on_miss", false))
	dancing_blade = bool(d.get("dancing_blade", false))
	polymorph_first_kill = bool(d.get("polymorph_first_kill", false))
	wolf_kinship_pct = float(d.get("wolf_kinship_pct", 0.0))
	anchor_regen = float(d.get("anchor_regen", 0.0))
	hp_per_kill_cap = int(d.get("hp_per_kill_cap", 0))
	tidesong_water_pct = float(d.get("tidesong_water_pct", 0.0))
	venom_on_hit = bool(d.get("venom_on_hit", false))
	phylactery_revive_pct = float(d.get("phylactery_revive_pct", 0.0))
	extra_chests_per_floor = int(d.get("extra_chests_per_floor", 0))
	fifth_cast_pct = float(d.get("fifth_cast_pct", 0.0))
	# §1.H attempt_attack-shape conditional affixes.
	low_hp_target_dmg_pct = float(d.get("low_hp_target_dmg_pct", 0.0))
	glass_cannon_dmg_pct = float(d.get("glass_cannon_dmg_pct", 0.0))
	low_hp_dr_pct = float(d.get("low_hp_dr_pct", 0.0))
	boss_dmg_pct = float(d.get("boss_dmg_pct", 0.0))
	pack_dmg_per_enemy_pct = float(d.get("pack_dmg_per_enemy_pct", 0.0))
	full_hp_armor_pct = float(d.get("full_hp_armor_pct", 0.0))
	weapon_bleed_per_sec = int(d.get("weapon_bleed_per_sec", 0))
	holy_dot_per_sec = int(d.get("holy_dot_per_sec", 0))
	revenge_dmg_pct = float(d.get("revenge_dmg_pct", 0.0))
	first_hit_pct = float(d.get("first_hit_pct", 0.0))
	hp_per_kill_flat = int(d.get("hp_per_kill_flat", 0))
	melee_armor_pen_pct = float(d.get("melee_armor_pen_pct", 0.0))
	spell_resist_pen_pct = float(d.get("spell_resist_pen_pct", 0.0))
	crit_mark_dmg_pct = float(d.get("crit_mark_dmg_pct", 0.0))
	recoup_pct = float(d.get("recoup_pct", 0.0))
	move_spell_dmg_pct = float(d.get("move_spell_dmg_pct", 0.0))
	thorns_flat = int(d.get("thorns_flat", 0))
	block_thorns_flat = int(d.get("block_thorns_flat", 0))
	first_hit_mark_pct = float(d.get("first_hit_mark_pct", 0.0))
	doomstrike_dmg_pct = float(d.get("doomstrike_dmg_pct", 0.0))
	# anchor_regen folds into hp_regen so the regen tick already in actor.gd
	# picks it up alongside species + worn-tag regen.
	hp_regen_per_sec = float(d.hp_regen) + anchor_regen
	move_speed = float(d.move_speed)
	aggro_bonus = int(d.aggro_bonus)
	# Legacy Actor fields combat-log paths read.
	var str_excess: int = str_stat - 5
	atk = int(round(float(damage_min + damage_max) * 0.5 * (1.0 + float(str_excess) * 0.02)))
	defense = armor

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
		# Per-instance hue/sat recolor — `inst.tint` is rolled at drop
		# time and drives item_recolor.gdshader. Was previously only
		# applied to the paperdoll path, so a green-tinted item read as
		# the base red on the in-game bot but green on the paperdoll.
		# Mirrors paperdoll_renderer._apply_recolor 2026-06-06.
		_apply_overlay_recolor(sprite, equipped.get(slot_id, null))
	weapon_sprite = _gear_sprites.get("weapon", null)
	# Fire-tagged weapons emit their own light from the held sprite.
	if weapon_sprite != null:
		var wpn: Variant = equipped.get("weapon", null)
		var base_id: String = "" if wpn == null or typeof(wpn) != TYPE_DICTIONARY else String(wpn.get("base_id", ""))
		var weapon_light_id: String = String(WEAPON_LIGHTS.get(base_id, ""))
		if weapon_light_id != "":
			LightSpec.attach(weapon_sprite, weapon_light_id, Vector2.ZERO)
		# Hand-side enchant ambience — soft radial glow under the weapon
		# pivot tinted by the weapon's flavor tag color. Ties bot+weapon
		# visually so the enchant doesn't read as "weapon glows but the
		# wielder has nothing to do with it". Skipped when no flavor
		# match (a vanilla weapon shouldn't haze).
		_apply_hand_enchant_ambience(wpn)

# Sprite-localised glow shader. Hugs the actual silhouette of the
# weapon/gear sprite via 8-direction alpha sampling instead of drawing
# a fat circular blob behind it — see assets/item_glow.gdshader.
const _ITEM_GLOW_SHADER := preload("res://assets/item_glow.gdshader")

func _apply_rarity_decor(sprite: Sprite2D, inst: Variant, slot_id: String) -> void:
	if inst == null or typeof(inst) != TYPE_DICTIONARY:
		return
	var base_id: String = String(inst.get("base_id", ""))
	if base_id == "" or not _items_db_cache.has(base_id):
		return
	var item: Dictionary = _items_db_cache[base_id]
	var rarity: String = String(item.get("rarity", "common"))
	# Combined static + per-instance enchant tags. Shared helper on
	# UITheme so HUD/Outpost/floor-loot all see the same union.
	var flavor_tags: Array = UITheme.combined_flavor_tags(item, inst)
	# Modulate folds in flavor color (vampiric=red, fire=orange, etc).
	# Falls back to rarity tint when no priority tag is present.
	sprite.modulate = UITheme.item_modulate(rarity, flavor_tags, String(inst.get("meta_rarity", "")))
	# Glow: sprite-localised via shader. Tags drive color first, rarity
	# second. Returns alpha=0 when no glow should draw — short-circuit.
	var glow_color: Color = UITheme.item_glow_color(rarity, flavor_tags)
	if glow_color.a <= 0.0:
		return
	# Only the weapon slot gets the glow on the live bot. ATK is the
	# primary "what's the bot wielding" read, and 5 simultaneous shader
	# materials on the rig would be visual noise.
	if slot_id != "weapon":
		return
	var mat := ShaderMaterial.new()
	mat.shader = _ITEM_GLOW_SHADER
	mat.set_shader_parameter("glow_color", glow_color)
	# Strength + thickness driven by the video-options sliders so the
	# user can dial these live from the paperdoll preview.
	var base_strength: float = VideoSettings.tunable("glow_strength", 1.2)
	mat.set_shader_parameter("glow_strength", base_strength)
	var slider_thickness: float = VideoSettings.tunable("glow_thickness", 0.12)
	# Boost thickness slightly for legendary/flavor items so they pop.
	var thickness: float = slider_thickness * (1.20 if rarity == "legendary" or _has_priority_flavor(flavor_tags) else 1.0)
	mat.set_shader_parameter("thickness", thickness)
	sprite.material = mat
	# Skip the pulse tween on web — every equip swap was building a new
	# Tween + binding 2 method callbacks, contributing to the equip lag
	# spike on Firefox HTML5. The pulse is barely perceptible on the
	# small in-game bot sprite anyway.
	if OS.has_feature("web"):
		return
	var pulse_amt: float = VideoSettings.tunable("glow_pulse_amount", 0.30)
	# Soft pulse via glow_strength uniform — shader-side, so we don't
	# replace the modulate (which already carries flavor tint).
	# Tween is owned by the sprite so it auto-dies when the gear is
	# unequipped (queue_freed by _refresh_gear_overlays).
	var pulse := sprite.create_tween().set_loops()
	pulse.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	pulse.tween_method(_set_glow_strength.bind(mat), base_strength - pulse_amt * 0.5, base_strength + pulse_amt * 0.5, 1.4)
	pulse.tween_method(_set_glow_strength.bind(mat), base_strength + pulse_amt * 0.5, base_strength - pulse_amt * 0.5, 1.4)

func _set_glow_strength(value: float, mat: ShaderMaterial) -> void:
	if mat == null:
		return
	mat.set_shader_parameter("glow_strength", value)

func _has_priority_flavor(flavor_tags: Array) -> bool:
	for tag in UITheme.FLAVOR_COLORS.keys():
		if tag in flavor_tags:
			return true
	return false

# Hand-side enchant glow. Soft radial Sprite2D parented to the RIG
# (not the weapon sprite) at an anatomical hand offset, tinted by
# weapon flavor. Living on the rig means:
#   1. it sits over the actual hand, not the torso (weapon sprite
#      pivot is at rig center which reads as "torso" on DCSS art);
#   2. it doesn't rotate/scale with the swing tween (which targets
#      weapon_sprite directly);
#   3. it auto-mirrors when the bot flips facing (`rig.scale.x = -1`
#      cascades, so +X offset becomes -X without extra code).
# Removed/replaced on every gear refresh so old enchants don't leak.
var _hand_enchant_sprite: Sprite2D = null
# DCSS spriggan_female draws the WEAPON hand on viewer-left, so the
# enchant offset is -8 (lands on the sword side). The rig auto-flips
# this when the bot turns around — see paperdoll_renderer comment.
const _HAND_OFFSET_X := -8.0
const _HAND_OFFSET_Y := 1.0

func _apply_overlay_recolor(sprite: Sprite2D, inst: Variant) -> void:
	# Mirror PaperdollRenderer._apply_recolor on the live-bot rig path.
	# If a glow shader is already attached (rarity glow on weapons), we
	# don't overwrite — the glow takes priority and the recolor would
	# conflict. Same rule the paperdoll renderer uses.
	if sprite == null or not is_instance_valid(sprite):
		return
	if sprite.material != null:
		return
	# Use the overlay-specific tint when the item authored a separate
	# default_tint_overlay; falls back to default_tint otherwise.
	var mat: ShaderMaterial = UITheme.recolor_material_for_overlay(inst)
	if mat != null:
		sprite.material = mat

func _apply_hand_enchant_ambience(weapon_inst: Variant) -> void:
	if _hand_enchant_sprite != null and is_instance_valid(_hand_enchant_sprite):
		_hand_enchant_sprite.queue_free()
	_hand_enchant_sprite = null
	if rig == null:
		return
	if weapon_inst == null or typeof(weapon_inst) != TYPE_DICTIONARY:
		return
	var base_id: String = String(weapon_inst.get("base_id", ""))
	if base_id == "" or not _items_db_cache.has(base_id):
		return
	var flavor_tags: Array = UITheme.combined_flavor_tags(_items_db_cache[base_id], weapon_inst)
	var fc: Color = UITheme.flavor_color_for(flavor_tags)
	if fc.a <= 0.0:
		return
	var glow := Sprite2D.new()
	glow.texture = LootDrop._make_glow_texture()
	glow.centered = true
	# z=4 = above body/helm/shield, below the weapon sprite (z=5) so
	# the blade silhouette stays the foreground read.
	glow.z_index = 4
	var hand_scale: float = VideoSettings.tunable("hand_enchant_scale", 0.95)
	glow.scale = Vector2(hand_scale, hand_scale)
	glow.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	glow.position = Vector2(_HAND_OFFSET_X, _HAND_OFFSET_Y)
	var base_alpha: float = VideoSettings.tunable("hand_enchant_alpha", 0.30)
	glow.modulate = Color(fc.r, fc.g, fc.b, base_alpha)
	rig.add_child(glow)
	_hand_enchant_sprite = glow
	var dim := Color(fc.r, fc.g, fc.b, base_alpha * 0.45)
	var bright := Color(fc.r, fc.g, fc.b, base_alpha)
	var pulse := glow.create_tween().set_loops()
	pulse.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	pulse.tween_property(glow, "modulate", dim, 1.6)
	pulse.tween_property(glow, "modulate", bright, 1.6)

func combat_label() -> String:
	return "bot"

func combat_weapon_id() -> String:
	var wpn: Variant = equipped.get("weapon", null)
	if wpn == null or typeof(wpn) != TYPE_DICTIONARY:
		return ""
	return String(wpn.get("base_id", ""))

# Returns the equipped weapon's base_type ("dagger", "battle_axe", etc.)
# or "" when bare-handed. Used by actor.gd to apply per-base-type
# combat procs (cleave, bleed, pierce, etc.) on the base autoattack.
# Combat pivot 2026-06-04.
func combat_weapon_base_type() -> String:
	var wpn: Variant = equipped.get("weapon", null)
	if wpn == null or typeof(wpn) != TYPE_DICTIONARY:
		return ""
	var base_id: String = String(wpn.get("base_id", ""))
	if base_id == "" or not _items_db_cache.has(base_id):
		return ""
	return String(_items_db_cache[base_id].get("base_type", ""))

func combat_weapon_tags() -> Array:
	var wpn: Variant = equipped.get("weapon", null)
	if wpn == null or typeof(wpn) != TYPE_DICTIONARY:
		return []
	var base_id: String = String(wpn.get("base_id", ""))
	if base_id == "" or not _items_db_cache.has(base_id):
		return []
	# Combine static base tags with the per-instance enchant roll
	# (dungeon._create_item_instance writes inst.enchant). The
	# enchant adds ONE additional flavor on top of whatever the
	# base item already carries — e.g. an Iron Dagger rolled with
	# fire enchant returns ["fire"]; a vampires_tooth rolled with
	# cold enchant returns ["vampiric", "cold"].
	var tags: Array = (_items_db_cache[base_id].get("flavor_tags", []) as Array).duplicate()
	var enchant: String = String(wpn.get("enchant", ""))
	if enchant != "" and not (enchant in tags):
		tags.append(enchant)
	# Enchant combo — when an item rolled a compound, expand it into
	# the two component flavors so the existing per-tag procs (burn,
	# freeze, lifesteal, etc) all fire on combo hits. The combo's
	# layered effect fires separately via EnchantCombos.apply_on_hit
	# in actor.attempt_attack.
	var combo_id: String = String(wpn.get("enchant_combo", ""))
	if combo_id != "":
		for ct in EnchantCombos.components_for(combo_id):
			if not (String(ct) in tags):
				tags.append(String(ct))
	# Species innate tags — vampire/demonspawn carry their flavor
	# even on a vanilla weapon. Read from the same SpeciesData lookup
	# combat_defense_tags uses.
	var sp: Dictionary = SpeciesData.get_def(species_id)
	for t in sp.get("innate_tags", []):
		if not (String(t) in tags):
			tags.append(String(t))
	return tags

# Returns the equipped weapon's enchant_combo id (or "") so combat
# can dispatch combo-specific layered effects. Item-overhaul follow-up
# 2026-06-04.
func combat_weapon_combo_id() -> String:
	var wpn: Variant = equipped.get("weapon", null)
	if wpn == null or typeof(wpn) != TYPE_DICTIONARY:
		return ""
	return String(wpn.get("enchant_combo", ""))

# Defender-worn tags — armor / shield / amulet / rings provide the
# defensive flavor tags (thorns, reflective, harm, rage). Helms also
# count for completeness. Multiple sources stack — a thorns shield +
# thorns armor will return damage twice per hit, by design.
# Slots whose equipped items contribute defender-side flavor tags +
# regen/vitality bonuses. Includes the extra ring slots
# (ring2/ring3/ring4) so octopode's ring stacking flows through —
# absent keys on a non-octopode bot just skip cleanly.
const _DEF_SLOTS := ["armor", "shield", "helm", "amulet", "ring", "ring2", "ring3", "ring4", "boots", "gloves", "cloak"]

func combat_defense_tags() -> Array:
	var out: Array = []
	# Species innate tags. A vampire always carries "vampiric" so its
	# weapon hits gain lifesteal even with no vampiric gear; a
	# demonspawn always carries "demon" so it gets +25% vs holy_hates.
	# Read first so they show up on tooltips alongside gear tags.
	var sp: Dictionary = SpeciesData.get_def(species_id)
	for t in sp.get("innate_tags", []):
		if not (String(t) in out):
			out.append(String(t))
	for slot in _DEF_SLOTS:
		var inst: Variant = equipped.get(slot, null)
		if inst == null or typeof(inst) != TYPE_DICTIONARY:
			continue
		var base_id: String = String(inst.get("base_id", ""))
		if base_id == "" or not _items_db_cache.has(base_id):
			continue
		# Static tags + per-instance enchant (defender-worn slots
		# also read enchant; thorns enchant on a chest plate works
		# the same as a static thorns armor).
		for t in _items_db_cache[base_id].get("flavor_tags", []):
			if not (t in out):
				out.append(t)
		var enchant: String = String(inst.get("enchant", ""))
		if enchant != "" and not (enchant in out):
			out.append(enchant)
	return out

func swing_weapon(toward: Vector2) -> void:
	if not is_instance_valid(weapon_sprite):
		return
	if _weapon_swing_tween and _weapon_swing_tween.is_valid():
		_weapon_swing_tween.kill()
	# Flavor-tag swing trail (fire/cold/vampiric/holy/poison/thunderous).
	# Emit BEFORE the animation tween so the burst aligns with the
	# windup → strike beat. Cheap: GPUParticles2D is one_shot, lazily
	# created the first time per weapon, restarted on each swing.
	var wpn: Variant = equipped.get("weapon", null)
	if wpn != null and typeof(wpn) == TYPE_DICTIONARY:
		var base_id: String = String(wpn.get("base_id", ""))
		if base_id != "" and _items_db_cache.has(base_id):
			var tags: Array = _items_db_cache[base_id].get("flavor_tags", [])
			var trail_flavor: String = WeaponTrails.flavor_for_tags(tags)
			if trail_flavor != "":
				WeaponTrails.emit_burst(weapon_sprite, trail_flavor)
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

func _play_swing_horizontal(_toward: Vector2) -> void:
	# Rotations are in the rig's local frame. The rig flips horizontally
	# (rig.scale.x = -1) when facing left, which automatically mirrors the
	# arc into screen space — so the windup/swing values are facing-agnostic.
	var windup_rot: float = deg_to_rad(35.0)   # cock back slightly
	var swing_rot: float = -deg_to_rad(110.0)  # sweep across body
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
	if not is_alive:
		return
	if hp_regen_per_sec > 0.0:
		_regen_accum += delta * hp_regen_per_sec
		if _regen_accum >= 1.0:
			var ticks: int = int(_regen_accum)
			_regen_accum -= float(ticks)
			hp = mini(max_hp, hp + ticks)
			_update_hp_bar()
	# §1.H of_recoup bucket drain. _recoup_window_remaining > 0 means
	# the 4s heal window is active; drain bucket proportionally each
	# frame and apply integer HP gain whenever a whole point accumulates.
	# When the window expires, leftover fractional bucket dumps as 1 HP
	# (so a 3-HP bucket doesn't quietly evaporate at the tail).
	if _recoup_window_remaining > 0.0 and _recoup_bucket > 0.0:
		var drain: float = _recoup_bucket * (delta / _recoup_window_remaining)
		_recoup_window_remaining -= delta
		if _recoup_window_remaining <= 0.0:
			drain = _recoup_bucket
			_recoup_window_remaining = 0.0
		_recoup_bucket -= drain
		if drain >= 1.0 and hp < max_hp:
			var heal: int = int(drain)
			hp = mini(max_hp, hp + heal)
			_update_hp_bar()
			if not has_status("recouping") and _recoup_window_remaining > 0.0:
				add_status("recouping", _recoup_window_remaining)

func take_damage(raw: int, attacker: Actor = null, damage_type: String = "") -> int:
	# Grind/audit invincibility — set by main.gd when auto_grind is active.
	# Live playtest is unaffected.
	if DebugJump.bot_invincible:
		return 0
	return super.take_damage(raw, attacker, damage_type)

func attempt_attack(other: Actor, delta: float) -> int:
	var dealt := super.attempt_attack(other, delta)
	if dealt > 0:
		# Swing the equipped weapon overlay toward the target.
		var toward: Vector2 = (other.position - position) if is_instance_valid(other) else Vector2.RIGHT
		swing_weapon(toward)
		# Two lifesteal channels stack:
		#  - `lifesteal_per_hit` (flat HP from Kiku/Makhleb altar +
		#    legacy 4-6 HP/hit blessings). Adds even on a 1-damage swing.
		#  - `lifesteal_pct` (% from `of_lifesteal` gear, clamped to 15%
		#    in StatCalc). Was rolled but never read pre-2026-06-08.
		# vampiric flavor tag's fixed 8% fires separately from
		# actor.gd::attempt_attack so vampiric weapons don't double-dip.
		var heal: int = lifesteal_per_hit
		if lifesteal_pct > 0.0:
			heal += int(round(float(dealt) * lifesteal_pct / 100.0))
		if heal > 0:
			hp = mini(max_hp, hp + heal)
			_update_hp_bar()
	return dealt

func gain_xp(amount: int) -> void:
	# Flavor-tag XP boosts. lordly = +15%, wisdom = +15%. Stack
	# multiplicatively so a bot wearing both gets ~32%. Same hook as
	# the legacy Sif Muna xp_gain_pct blessing (kept additive there
	# for back-compat).
	var def_tags: Array = combat_defense_tags()
	var tag_mult: float = 1.0
	if "lordly" in def_tags: tag_mult *= 1.15
	if "wisdom" in def_tags: tag_mult *= 1.15
	if tag_mult != 1.0:
		amount = int(round(float(amount) * tag_mult))
	var bonus: int = int(round(float(amount) * xp_gain_pct / 100.0))
	xp += amount + bonus
	while xp >= xp_to_next():
		xp -= xp_to_next()
		level += 1
		# Item-overhaul v2: level-up grants 3 stat points. atk / defense /
		# max_hp are now derived in recompute_stats from the level + alloc
		# scheme, so no inline bumps here. Stat-points + recompute call
		# below handles all of it.
		var unspent: int = int(upgrade_state.get("stat_points_unspent", 0)) + 3
		upgrade_state["stat_points_unspent"] = unspent
		recompute_stats()
		# Level-up grants the new HP slice (the +8 from this level), but
		# does NOT fully heal — full-heal-on-level-up made HP feel
		# infinite once enemies were dropping fast enough to chain
		# level-ups in combat.
		hp = mini(max_hp, hp + 8)
		_update_hp_bar()

func xp_to_next() -> int:
	# Doubled 2026-06-06 (was `20 + (level-1) * 15`). Audit found a
	# 4-run save reaching Lv 57 — ~6,055 XP/run, ~1,009 XP/floor — so
	# floor mobs at avg 6 XP × 100 mobs × pack-multipliers were level-
	# flooding hard. Doubling the curve targets ~Lv 25-30 at the same
	# 4-run pace, which is what the gear curve is designed for.
	return 30 + (level - 1) * 30
