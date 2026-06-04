class_name EnchantCombos
extends RefCounted

# Compound enchant registry + combat effect dispatch. Loads
# project/data/enchant_combos.json once and indexes by sorted-pair
# AND by id so dungeon roll path + actor combat path can both reach
# the same data. Effects are dispatched by `effect_id` string into
# the static apply_*_on_hit / apply_*_on_kill / apply_*_modifier
# functions below — adding a new combo = data file + one function.
#
# Item-overhaul follow-up 2026-06-04.

const PATH := "res://data/enchant_combos.json"

static var _combos: Array = []
static var _by_id: Dictionary = {}
static var _by_pair: Dictionary = {}  # "cold|fire" → combo dict
static var _loaded: bool = false

static func _ensure_loaded() -> void:
	if _loaded:
		return
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		push_error("Failed to open enchant_combos.json")
		_loaded = true
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("enchant_combos.json: parse failed")
		_loaded = true
		return
	for combo in parsed.get("combos", []):
		var c: Dictionary = combo
		_combos.append(c)
		_by_id[String(c.id)] = c
		var key: String = _pair_key(c.components)
		_by_pair[key] = c
	_loaded = true

# Sort components alphabetically + join with '|'. Used as the lookup
# key so component order in the data file doesn't matter at roll time.
static func _pair_key(components: Array) -> String:
	var sorted: Array = []
	for c in components:
		sorted.append(String(c))
	sorted.sort()
	return "|".join(sorted)

# Public: look up a combo by component pair. Returns the combo dict
# or {} if no combo for this pair. Components passed in any order.
static func combo_for_pair(a: String, b: String) -> Dictionary:
	_ensure_loaded()
	if a == b or a == "" or b == "":
		return {}
	return _by_pair.get(_pair_key([a, b]), {})

# Public: lookup by combo id (e.g. "combustion"). Used by tooltip +
# combat effect dispatch.
static func get_combo(id: String) -> Dictionary:
	_ensure_loaded()
	return _by_id.get(id, {})

# Resolve the per-attacker combo id, if any. Reads inst.enchant_combo
# from the equipped weapon. Bot weapons fold this into combat tags so
# proc dispatch sees both component flavors AND the combo id.
static func combo_id_on_weapon(weapon_inst: Variant) -> String:
	if typeof(weapon_inst) != TYPE_DICTIONARY:
		return ""
	return String(weapon_inst.get("enchant_combo", ""))

# Returns the two component flavors for a combo, useful for combat
# code that needs to fire the underlying procs (e.g. Combustion still
# burns + still poisons).
static func components_for(id: String) -> Array:
	_ensure_loaded()
	var c: Dictionary = _by_id.get(id, {})
	return c.get("components", [])

# ============================================================
# Combat effect dispatch
# ============================================================
# Each effect_id maps to one of three on_hit / on_kill / on_damage
# hooks. apply_on_hit fires when an attacker lands a blow with this
# combo on their weapon; apply_on_kill fires when that hit kills the
# target; apply_modifiers tweaks pre-roll damage / defense values.
#
# Signature contracts:
#   apply_on_hit(attacker, defender, dealt, raw_dmg) → optional bonus dmg int
#   apply_on_kill(attacker, defender) → no return
#   apply_damage_mod(combo_id, attacker, defender, raw, dmg_type) → mult
#
# Functions stay terse — most effects reuse existing actor.gd hooks
# (add_burn / add_poison / add_status / hp += heal). Combat already
# fires the component flavor procs via combat_weapon_tags() so the
# combo ONLY needs to add the layered effect on top.

# Damage multiplier hook — fires before the swing's roll. Returns
# the multiplier to apply to the raw damage (default 1.0). Reads
# defender state to apply combos like Brittle Storm (frozen → +50%
# lightning) and Stormcurse (in fog cells → +100%).
static func apply_damage_mod(combo_id: String, _attacker: Node, defender: Node, raw: int, dmg_type: String) -> float:
	if combo_id == "":
		return 1.0
	match combo_id:
		"plasma":
			# +25% on every swing. Simple flat boost in exchange for
			# the combat-tag procs being doubled (fire AND lightning).
			return 1.25
		"brittle_storm":
			if dmg_type == "lightning" and defender != null and defender.has_method("has_status"):
				if defender.has_status("frozen"):
					return 1.50
			return 1.0
		"quench":
			# On a frozen target, fire damage doubles.
			if dmg_type == "fire" and defender != null and defender.has_method("has_status"):
				if defender.has_status("frozen"):
					return 2.0
			return 1.0
		"stormcurse":
			# Doubled damage in fog. Defender's `in_fog` flag is set by
			# the dungeon's fog system if reachable — fall back to false.
			if defender != null and "in_fog" in defender and defender.in_fog:
				return 2.0
			return 1.0
		"twilight":
			# Damage scaled by attacker's missing HP%. Up to +50% at
			# 1 HP. Reads attacker state.
			if _attacker != null and _attacker.has_method("get") and _attacker.max_hp > 0:
				var miss: float = 1.0 - clampf(float(_attacker.hp) / float(_attacker.max_hp), 0.0, 1.0)
				return 1.0 + miss * 0.5
			return 1.0
		"pyre":
			# Burn DoT damages undead/demons +50% — handled in the burn
			# tick, not the raw hit. Hit damage unchanged.
			return 1.0
	return 1.0

# On-hit hook — called from actor.attempt_attack after dealt resolves.
# Most combos add a status / heal / extra DoT on top of the swing.
static func apply_on_hit(combo_id: String, attacker: Node, defender: Node, dealt: int, _raw: int) -> void:
	if combo_id == "" or dealt <= 0:
		return
	if defender == null or not is_instance_valid(defender) or not defender.is_alive:
		return
	match combo_id:
		"combustion":
			# Poison ticks detonate on expiry — handled at tick-cleanup
			# side. On hit we just guarantee a poison stack lands so the
			# detonation has something to consume.
			if defender.has_method("add_poison"):
				var per_tick: int = maxi(1, int(round(float(defender.max_hp) * 0.03)))
				defender.add_poison(per_tick, 4, 0.5)
				defender.set_meta("combustion_active", true)
		"hellfire":
			# Burn DoT cannot be cleansed; lifesteal 5% on burning targets.
			if defender.has_method("add_burn"):
				var per_tick_h: int = maxi(1, int(round(float(defender.max_hp) * 0.04)))
				defender.add_burn(per_tick_h, 4, 0.5)
				defender.set_meta("hellfire_active", true)
			if attacker != null and defender.has_method("has_status") and defender.has_status("burning") and "max_hp" in attacker:
				var heal: int = maxi(1, int(round(float(dealt) * 0.05)))
				attacker.hp = clampi(attacker.hp + heal, 0, attacker.max_hp)
				if attacker.has_method("_update_hp_bar"):
					attacker._update_hp_bar()
		"bloodfire":
			# On lifesteal hit, target also takes burn DoT. Component
			# vampiric handles the lifesteal; we add the burn.
			if defender.has_method("add_burn"):
				var per_tick_b: int = maxi(1, int(round(float(defender.max_hp) * 0.03)))
				defender.add_burn(per_tick_b, 3, 0.5)
		"cleansing_frost":
			# Freeze duration +50% AND ignores Holy resistance. The
			# freeze proc itself fires from the cold flavor; here we
			# extend its duration if it landed.
			if defender.has_method("has_status") and defender.has_status("frozen") and defender.has_method("add_status"):
				defender.add_status("frozen", 1.0)  # extra 1.0s on top
		"cryo_toxin":
			# Each poison tick slows by 5% (cap 30%). Mark for the
			# tick handler to read.
			defender.set_meta("cryo_toxin_active", true)
			if defender.has_method("add_status"):
				defender.add_status("slowed", 1.0)
		"hollow_frost":
			# Freeze duration +100% on enemies below 50% HP.
			if defender.max_hp > 0 and float(defender.hp) / float(defender.max_hp) < 0.50:
				if defender.has_method("has_status") and defender.has_status("frozen"):
					if defender.has_method("add_status"):
						defender.add_status("frozen", 0.5)
		"heartrime":
			# Freezing a target restores 5% max HP. Fires when the
			# component cold flavor procs the freeze on this hit.
			if defender.has_method("has_status") and defender.has_status("frozen"):
				if attacker != null and "max_hp" in attacker:
					var heal_h: int = maxi(1, int(round(float(attacker.max_hp) * 0.05)))
					attacker.hp = clampi(attacker.hp + heal_h, 0, attacker.max_hp)
					if attacker.has_method("_update_hp_bar"):
						attacker._update_hp_bar()
		"acid_storm":
			# Lightning chains apply mini-poison stacks. Lower per-tick
			# than vanilla poison; cheap stacking proc.
			if defender.has_method("add_poison"):
				var per_tick_a: int = maxi(1, int(round(float(defender.max_hp) * 0.015)))
				defender.add_poison(per_tick_a, 3, 0.5)
		"blood_arc":
			# On hit, restore 1% max HP (cheap sustain). Component
			# lightning provides the chain damage.
			if attacker != null and "max_hp" in attacker:
				var heal_a: int = maxi(1, int(round(float(attacker.max_hp) * 0.01)))
				attacker.hp = clampi(attacker.hp + heal_a, 0, attacker.max_hp)
				if attacker.has_method("_update_hp_bar"):
					attacker._update_hp_bar()
		"sanctified_venom":
			# Poison ticks strip enemy buffs. Fires when poison lands;
			# the tick handler clears all status overlays except the
			# poison itself.
			defender.set_meta("sanctified_venom_active", true)
			if defender.has_method("add_poison"):
				var per_tick_s: int = maxi(1, int(round(float(defender.max_hp) * 0.03)))
				defender.add_poison(per_tick_s, 4, 0.5)
		"sanctified_drain":
			# Lifesteal heals 2× when target is undead/demon. Component
			# vampiric provides the lifesteal; we double the heal here.
			# Match against StatusOverlay.HOLY_HATES if available.
			if attacker != null and "max_hp" in attacker:
				var dlabel: String = defender.combat_label() if defender.has_method("combat_label") else ""
				var is_holy_hated: bool = false
				if Engine.has_singleton("_StatusOverlay"):
					pass  # keep simple — assume false unless overlay says yes
				if dlabel.find("undead") >= 0 or dlabel.find("demon") >= 0 or dlabel.find("zombie") >= 0:
					is_holy_hated = true
				if is_holy_hated:
					var bonus: int = maxi(1, int(round(float(dealt) * 0.08)))
					attacker.hp = clampi(attacker.hp + bonus, 0, attacker.max_hp)
					if attacker.has_method("_update_hp_bar"):
						attacker._update_hp_bar()
		"necrosis":
			# Poison DoT bypasses armor — flag the poison stack so the
			# tick handler skips armor mitigation. Apply a stack here.
			if defender.has_method("add_poison"):
				var per_tick_n: int = maxi(1, int(round(float(defender.max_hp) * 0.04)))
				defender.add_poison(per_tick_n, 4, 0.5)
				defender.set_meta("necrosis_active", true)
		"bloodbloom":
			# Lifesteal hits apply poison. Component vampiric does the
			# steal; we add the poison stack.
			if defender.has_method("add_poison"):
				var per_tick_bb: int = maxi(1, int(round(float(defender.max_hp) * 0.025)))
				defender.add_poison(per_tick_bb, 3, 0.5)
		"judgement":
			# Crits chain to one adjacent foe. Crit_chance bonus is
			# applied via apply_modifiers below; here we splash on crit.
			# We don't know if THIS hit crit'd — actor.attempt_attack
			# sets a meta flag we read.
			if attacker != null and attacker.has_meta("just_crit") and attacker.get_meta("just_crit"):
				if attacker.has_method("_find_adjacent_actor"):
					var nearby = attacker._find_adjacent_actor(defender)
					if nearby != null and nearby.has_method("take_damage"):
						nearby.take_damage(maxi(1, int(round(float(dealt) * 0.5))), attacker, "holy")

# On-kill hook — fired from actor.attempt_attack when a hit kills.
static func apply_on_kill(combo_id: String, attacker: Node, _defender: Node) -> void:
	if combo_id == "":
		return
	match combo_id:
		"soulfeed":
			# Killing under Soulfeed restores 10% max HP.
			if attacker != null and "max_hp" in attacker:
				var heal: int = maxi(1, int(round(float(attacker.max_hp) * 0.10)))
				attacker.hp = clampi(attacker.hp + heal, 0, attacker.max_hp)
				if attacker.has_method("_update_hp_bar"):
					attacker._update_hp_bar()

# Crit-bonus hook — fires during attempt_attack's crit roll. Returns
# bonus crit chance % to add to the base crit_chance for this swing.
static func crit_bonus_for(combo_id: String) -> float:
	match combo_id:
		"judgement":
			return 10.0
	return 0.0

# Tooltip color — return a single Color that's the average of the
# combo's two component colors. Used by the tooltip combo line and
# the sprite-tint pipeline.
static func combo_color(combo_id: String) -> Color:
	_ensure_loaded()
	var c: Dictionary = _by_id.get(combo_id, {})
	if c.is_empty():
		return Color(1, 1, 1, 1)
	var a: Array = c.get("color_a", [1.0, 1.0, 1.0])
	var b: Array = c.get("color_b", [1.0, 1.0, 1.0])
	return Color(
		(float(a[0]) + float(b[0])) * 0.5,
		(float(a[1]) + float(b[1])) * 0.5,
		(float(a[2]) + float(b[2])) * 0.5,
		1.0,
	)
