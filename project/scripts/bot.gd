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
var base_max_hp: int = 80

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
# Vision-tag flavor: read by dungeon AI as a bonus to AGGRO_DISTANCE
# so a vision-equipped bot engages from further away.
var aggro_bonus: int = 0
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
	# Run-stable upgrade contributions to "blessing-style" stats. recompute
	# doesn't touch these (blessings can keep adding mid-run), so we apply
	# them once here at run start and let the rest of the run's flow stack
	# on top.
	if not upgrade_state.is_empty():
		loot_rarity_bonus = BotUpgrades.total_for_stat(upgrade_state, "loot_rarity_bonus")
	# Species loot_pct is a passive contribution — apply once at run
	# start so it stacks with bot upgrades / blessings instead of being
	# wiped each recompute.
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
	# 2H weapon ↔ shield exclusion. Equipping a 2H weapon clears the
	# shield slot back to inventory; equipping a shield clears a 2H
	# weapon back to inventory. PoE/Diablo pattern — kindest UX.
	if slot == "weapon" and is_two_handed_base_type(String(item.get("base_type", ""))):
		var current_shield: Variant = equipped.get("shield", null)
		if current_shield != null and typeof(current_shield) == TYPE_DICTIONARY:
			displaced.append(current_shield)
			equipped["shield"] = null
	elif slot == "shield":
		var current_weapon: Variant = equipped.get("weapon", null)
		if current_weapon != null and typeof(current_weapon) == TYPE_DICTIONARY:
			var w_id: String = String(current_weapon.get("base_id", ""))
			if w_id != "" and _items_db_cache.has(w_id):
				if is_two_handed_base_type(String(_items_db_cache[w_id].get("base_type", ""))):
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

# Realize an implicit affix into a rolled instance dict. Implicit
# affixes are stamped on uniques in items.json as just an id string;
# recompute_stats needs (id, value) shaped entries to feed
# AffixSystem.sum_affix_stats. We synthesize the value using the affix
# def's tier matching the item rarity. Range affixes get value_min /
# value_max bounds matching the tier range mid-point.
func _realize_implicit(affix_id: String, item_rarity: String) -> Dictionary:
	var def: Dictionary = AffixSystem.get_affix_def(affix_id)
	if def.is_empty():
		return {"id": affix_id, "value": 0}
	var tiers: Array = def.get("tiers", [])
	var idx: int = AffixSystem.tier_index_for_rarity(item_rarity)
	idx = clampi(idx, 0, tiers.size() - 1)
	if tiers.is_empty():
		return {"id": affix_id, "value": 0}
	var tier_entry = tiers[idx]
	var out: Dictionary = {"id": affix_id}
	if tier_entry is Array and tier_entry.size() >= 2:
		var lo: int = int(tier_entry[0])
		var hi: int = int(tier_entry[1])
		if String(def.get("kind", "flat")) == "range":
			out["value_min"] = lo
			out["value_max"] = hi
			out["value"] = int(round((lo + hi) / 2.0))
		else:
			# Implicits roll the AVG of the range so they're deterministic
			# (a Vampire's Tooth always gives the same lifesteal).
			out["value"] = int(round((lo + hi) / 2.0))
	else:
		out["value"] = int(tier_entry)
	return out

func recompute_stats() -> void:
	# Item-overhaul v2 (2026-06-04). New stat shape:
	#   damage_min/max + weapon_speed + weapon_damage_type   ← from weapon
	#   armor + evasion + resistances                        ← from gear+affixes
	#   str_stat / dex_stat / int_stat                       ← species + level + alloc + affixes
	#   spell_*_pct accumulators                             ← from gear affixes
	#   max_hp + crit_chance + haste                         ← derived from above
	#
	# Old atk/defense/base_atk/base_def fields are gone. The Actor base
	# class still has `atk` + `defense` for compatibility with combat
	# logging — set them at the end from damage_max + armor as
	# representative values.

	# --- Primary stats (str/dex/int) ---------------------------------
	var sp: Dictionary = SpeciesData.get_def(species_id)
	var lvl_bonus: int = max(0, level - 1)
	# Allocated stat points (Phase B). Default 0 if not yet set.
	var alloc_str: int = int(upgrade_state.get("stat_alloc_str", 0)) if not upgrade_state.is_empty() else 0
	var alloc_dex: int = int(upgrade_state.get("stat_alloc_dex", 0)) if not upgrade_state.is_empty() else 0
	var alloc_int: int = int(upgrade_state.get("stat_alloc_int", 0)) if not upgrade_state.is_empty() else 0
	str_stat = 5 + int(sp.get("str_flat", 0)) + lvl_bonus + alloc_str
	dex_stat = 5 + int(sp.get("dex_flat", 0)) + lvl_bonus + alloc_dex
	int_stat = 5 + int(sp.get("int_flat", 0)) + lvl_bonus + alloc_int
	aggro_bonus = int(sp.get("aggro_flat", 0))

	# --- Defenses + accumulators reset --------------------------------
	# Empty-hand baseline. Filled by weapon below.
	damage_min = 1
	damage_max = 2
	weapon_speed = 1.0
	weapon_damage_type = "physical"
	weapon_class = "1H"
	extra_damage = {}
	armor = 0
	evasion = 0.0
	for elem in resistances.keys():
		resistances[elem] = 0.0
	lifesteal_pct = 0.0
	spell_cdr_pct = 0.0
	spell_proj_bonus = 0
	spell_proj_speed_pct = 0.0
	spell_area_pct = 0.0
	spell_duration_pct = 0.0
	spell_damage_pct = 0.0
	for elem in spell_element_pct.keys():
		spell_element_pct[elem] = 0.0

	# Crit/Haste/Regen accumulators (start with species seeds).
	var crit_sum: float = float(sp.get("crit_flat", 0))
	var haste_sum: float = float(sp.get("haste_pct", 0))
	var gear_regen: float = float(sp.get("regen_flat", 0))
	var hp_flat: int = 0
	var sp_hp_mult: float = 1.0 + float(sp.get("hp_pct", 0)) / 100.0
	# Permanent gold-sink upgrades. We map old "max_hp" / "crit_chance"
	# upgrade hooks onto the new model verbatim.
	var up_hp: float = BotUpgrades.total_for_stat(upgrade_state, "max_hp") if not upgrade_state.is_empty() else 0.0
	var up_crit: float = BotUpgrades.total_for_stat(upgrade_state, "crit_chance") if not upgrade_state.is_empty() else 0.0

	# --- Walk equipped ------------------------------------------------
	for slot in equipped.keys():
		var inst: Variant = equipped[slot]
		if inst == null or typeof(inst) != TYPE_DICTIONARY:
			continue
		var base_id: String = String(inst.get("base_id", ""))
		if base_id == "" or not _items_db_cache.has(base_id):
			continue
		var item: Dictionary = _items_db_cache[base_id]
		# Meta-rarity multiplier scales BASE stats (damage range / armor /
		# evasion). Affixes unaffected — they have their own tiers.
		var meta: String = String(inst.get("meta_rarity", ""))
		var meta_mult: float = 1.0
		if meta == "ancient":
			meta_mult = 1.20
		elif meta == "primal":
			meta_mult = 1.50
		# Slot-shape branching:
		#   weapon → set damage range + speed + damage_type
		#   body slots → add to armor / evasion
		#   spell tomes → handled by SpellSystem; recompute only reads
		#                 affixes for spell-modifier rollup
		#   jewelry → no baseline, just affixes
		if slot == "weapon":
			damage_min = int(round(float(item.get("damage_min", 1)) * meta_mult))
			damage_max = int(round(float(item.get("damage_max", 2)) * meta_mult))
			weapon_speed = float(item.get("speed", 1.0))
			weapon_damage_type = String(item.get("damage_type", "physical"))
			weapon_class = String(item.get("weapon_class", "1H"))
		else:
			armor += int(round(float(item.get("armor", 0)) * meta_mult))
			evasion += float(item.get("evasion", 0)) * meta_mult

		# Combine implicit + rolled affixes — both go through the same
		# rollup. Implicit affixes are stamped on uniques at item-roll
		# time and never displaced.
		var combined_affixes: Array = []
		for a in item.get("implicit_affixes", []):
			# Implicit entries are just affix ids; roll mid-tier values
			# at the item's rarity for display purposes (combat reads the
			# rolled values, not the implicit defs directly).
			combined_affixes.append(_realize_implicit(String(a), String(item.get("rarity", "common"))))
		for a in inst.get("affixes", []):
			combined_affixes.append(a)
		var sums: Dictionary = AffixSystem.sum_affix_stats(combined_affixes)
		# Primary stats from affixes.
		str_stat += int(sums.get("str", 0))
		dex_stat += int(sums.get("dex", 0))
		int_stat += int(sums.get("int", 0))
		# Defensive affixes.
		hp_flat += int(sums.get("hp", 0))
		armor += int(sums.get("armor", 0))
		evasion += float(sums.get("evasion", 0))
		gear_regen += float(sums.get("hp_regen", 0))
		# Resistances (cap applied after the loop).
		for elem in ["fire", "cold", "lightning", "holy", "poison", "dark"]:
			resistances[elem] += float(sums.get(elem + "_res", 0))
		# Crit / Haste / Lifesteal (universal).
		crit_sum += float(sums.get("crit_chance", 0))
		haste_sum += float(sums.get("haste_pct", 0))
		lifesteal_pct += float(sums.get("lifesteal_pct", 0))
		# Spell-modifier affixes.
		spell_cdr_pct += float(sums.get("spell_cdr_pct", 0))
		spell_proj_bonus += int(sums.get("spell_proj_bonus", 0))
		spell_proj_speed_pct += float(sums.get("spell_proj_speed_pct", 0))
		spell_area_pct += float(sums.get("spell_area_pct", 0))
		spell_duration_pct += float(sums.get("spell_duration_pct", 0))
		spell_damage_pct += float(sums.get("spell_damage_pct", 0))
		# Range affixes contribute extra_damage to autoattacks. The
		# value_min / value_max bounds are summed under "<stat>_min" /
		# "<stat>_max" keys by sum_affix_stats. Each elemental "of
		# <element>" affix lands as <element>_extra → extra_damage[<element>].
		for elem in ["physical", "fire", "cold", "lightning", "holy", "poison", "dark"]:
			var key: String = elem + "_extra"
			var lo: int = int(sums.get(key + "_min", 0))
			var hi: int = int(sums.get(key + "_max", 0))
			if lo > 0 or hi > 0:
				var prev: Dictionary = extra_damage.get(elem, {"min": 0, "max": 0})
				extra_damage[elem] = {"min": int(prev.min) + lo, "max": int(prev.max) + hi}

	# --- Final derived contributions ----------------------------------
	var str_excess: int = str_stat - 5
	var dex_excess: int = dex_stat - 5
	var int_excess: int = int_stat - 5
	# Str feeds melee damage post-roll (in actor.gd). Here we just feed
	# HP. Each Str above baseline = +1.5% HP.
	# Dex feeds crit + haste universally (used for spells AND melee).
	# Int feeds spell damage / area / duration.
	crit_sum += float(dex_excess) * 0.5
	haste_sum += float(dex_excess) * 1.0
	spell_damage_pct += float(int_excess) * 1.0
	spell_area_pct += float(int_excess) * 0.5
	spell_duration_pct += float(int_excess) * 0.5
	# HP rollup.
	max_hp = int(round(float(base_max_hp + (level - 1) * 8 + int(up_hp) + hp_flat) * sp_hp_mult * (1.0 + float(str_excess) * 0.015)))
	# Caps: crit ≤ 75, haste ≤ 200 (interval floor 0.2s), evasion ≤ 75.
	crit_chance = clampf(crit_sum + up_crit, 0.0, 75.0)
	var haste_pct: float = clampf(haste_sum, 0.0, 200.0)
	# Attack interval = weapon_speed / haste-mult. Empty hand falls back
	# to 1.0s. Floor 0.15s for degenerate-flicker safety.
	attack_interval = max(0.15, weapon_speed / (1.0 + haste_pct / 100.0))
	evasion = clampf(evasion, 0.0, 75.0)
	for elem in resistances.keys():
		resistances[elem] = clampf(float(resistances[elem]), -100.0, 75.0)
	# Legacy fields for combat-log paths that read bot.atk / bot.defense.
	# atk = average swing damage; defense = armor (rough surrogate).
	atk = int(round(float(damage_min + damage_max) * 0.5 * (1.0 + float(str_excess) * 0.02)))
	defense = armor
	# Gear regen + blessing regen + flavor-tag regen. Blessings already
	# added to hp_regen_per_sec via grant_blessing, so we re-derive from
	# scratch: count gear here + blessing array + tag stacks.
	hp_regen_per_sec = gear_regen
	for b in blessings:
		if String(b.get("kind", "")) == "hp_regen":
			hp_regen_per_sec += float(b.get("value", 0))
	# Per-tag passive bonuses applied here so they're visible in the
	# stats UI right after an equip change. All defender-side; iterate
	# the worn slots once to collect the bag of tags, then apply each.
	var worn_tags: Array = []
	for slot in _DEF_SLOTS:
		var inst: Variant = equipped.get(slot, null)
		if inst == null or typeof(inst) != TYPE_DICTIONARY:
			continue
		var bid: String = String(inst.get("base_id", ""))
		if bid == "" or not _items_db_cache.has(bid):
			continue
		# Combined static + per-instance enchant. Enchants count too —
		# a vitality-enchanted helm grants +1 regen the same as a
		# vitality-static amulet does.
		var combined: Array = UITheme.combined_flavor_tags(_items_db_cache[bid], inst)
		for t in combined:
			worn_tags.append(t)
	# `vitality`: +1 HP/sec per source. Stacks linearly.
	for t in worn_tags:
		if t == "vitality":
			hp_regen_per_sec += 1.0
		elif t == "regen":
			# Defender-worn `regen` flavor = +0.5 HP/sec (cheaper than
			# vitality so it can show up on more items without bloating).
			hp_regen_per_sec += 0.5
		elif t == "faith":
			# Faith = +0.5 HP/sec like regen. We also boost fountain
			# heal by 50% in dungeon._on_fountain_drank reading the
			# same tag.
			hp_regen_per_sec += 0.5
	# `swiftness`: +10% move speed per source, capped at +30% so a
	# 3-source bot doesn't walk through walls.
	var swift_count: int = 0
	for t in worn_tags:
		if t == "swiftness":
			swift_count += 1
	if swift_count > 0:
		var bonus: float = clampf(float(swift_count) * 0.10, 0.0, 0.30)
		# Bot's base move_speed is 4.0; multiply.
		move_speed = 4.0 * (1.0 + bonus)
	else:
		move_speed = 4.0
	# `fortified`: +20% defense per source, additive cap +50%.
	var fortified_count: int = 0
	for t in worn_tags:
		if t == "fortified":
			fortified_count += 1
	if fortified_count > 0:
		var fbonus: float = clampf(float(fortified_count) * 0.20, 0.0, 0.50)
		defense = int(round(float(defense) * (1.0 + fbonus)))
	# `ponderous`: -10% attack speed per source. Trade-off — ponderous
	# weapons hit harder (the +10% damage is in actor.gd) but slower.
	var ponderous_count: int = 0
	for t in combat_weapon_tags():
		if t == "ponderous":
			ponderous_count += 1
	if ponderous_count > 0:
		# attack_interval is "seconds between swings"; bigger = slower.
		attack_interval = attack_interval * (1.0 + 0.10 * float(ponderous_count))
	# `vision`: +1 aggro range per source so the bot engages enemies
	# from further away. Read by dungeon AI via bot.aggro_bonus.
	var vision_count: int = 0
	for t in worn_tags:
		if t == "vision":
			vision_count += 1
	aggro_bonus = vision_count

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
	# Species innate tags — vampire/demonspawn carry their flavor
	# even on a vanilla weapon. Read from the same SpeciesData lookup
	# combat_defense_tags uses.
	var sp: Dictionary = SpeciesData.get_def(species_id)
	for t in sp.get("innate_tags", []):
		if not (String(t) in tags):
			tags.append(String(t))
	return tags

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
		if lifesteal_per_hit > 0:
			hp = mini(max_hp, hp + lifesteal_per_hit)
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
