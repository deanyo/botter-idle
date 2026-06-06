class_name StatCalc
extends RefCounted

# Single source of truth for stat math. Both bot.recompute_stats and the
# outpost / main-menu stat panels feed inputs through here so all surfaces
# show the same numbers for the same equip. Pre-2026-06-06 the outpost
# rendered raw item.armor / item.damage_min etc. and ignored meta_mult,
# Quality, BotUpgrades, species hp_pct/crit_flat/regen_flat, and worn-tag
# passives — so a Pristine Ancient Iron Dagger read as different stats on
# the deploy screen vs in-run. Single canonical formula = no divergence.

# Element list shared between resistances + spell_element_pct + extra_damage.
# `physical` is a real resistance even though it doesn't appear on most gear
# (used by combat math), kept here so the dict has a stable shape.
const ELEMENTS := ["fire", "cold", "lightning", "holy", "poison", "dark"]
const SPELL_ELEMENTS := ["fire", "cold", "thunderous", "holy", "poison", "dark"]
const RESISTANCE_ELEMENTS := ["fire", "cold", "lightning", "holy", "poison", "dark", "physical"]

const _DEF_SLOTS := ["armor", "shield", "helm", "amulet", "ring", "ring2", "ring3", "ring4", "boots", "gloves", "cloak"]
const _BASE_HP := 80
const _BASE_MOVE_SPEED := 4.0

# Compute the full stat dict from the given inputs. `equipped` is the
# slot → instance dict (same shape as bot.equipped / save.equipped).
# `save_state` is the SaveState dict (used for stat_alloc_str/dex/int +
# bot_upgrades). `blessings` is the Bot.blessings array (empty in outpost
# context — blessings only exist mid-run).
static func compute(
	equipped: Dictionary,
	items_db: Dictionary,
	save_state: Dictionary,
	species_id: String,
	level: int,
	xp: int,
	gold: int,
	blessings: Array = []
) -> Dictionary:
	var sp: Dictionary = SpeciesData.get_def(species_id)
	var lvl_bonus: int = max(0, level - 1)
	var alloc_str: int = int(save_state.get("stat_alloc_str", 0))
	var alloc_dex: int = int(save_state.get("stat_alloc_dex", 0))
	var alloc_int: int = int(save_state.get("stat_alloc_int", 0))

	var out: Dictionary = _initial_dict()
	out["level"] = level
	out["xp"] = xp
	out["gold"] = gold
	out["species_id"] = species_id

	# Primary stats — base + species + level + alloc.
	var str_stat: int = 5 + int(sp.get("str_flat", 0)) + lvl_bonus + alloc_str
	var dex_stat: int = 5 + int(sp.get("dex_flat", 0)) + lvl_bonus + alloc_dex
	var int_stat: int = 5 + int(sp.get("int_flat", 0)) + lvl_bonus + alloc_int

	# Defensive accumulators.
	var armor_total: int = 0
	var evasion_total: float = 0.0
	var hp_flat: int = 0
	var lifesteal_pct: float = 0.0
	var crit_sum: float = float(sp.get("crit_flat", 0))
	var haste_sum: float = float(sp.get("haste_pct", 0))
	var gear_regen: float = float(sp.get("regen_flat", 0))
	var sp_hp_mult: float = 1.0 + float(sp.get("hp_pct", 0)) / 100.0

	# Resistances + spell element + extra damage start at 0.
	var resistances: Dictionary = {}
	for elem in RESISTANCE_ELEMENTS:
		resistances[elem] = 0.0
	var spell_element_pct: Dictionary = {}
	for elem in SPELL_ELEMENTS:
		spell_element_pct[elem] = 0.0
	var extra_damage: Dictionary = {}

	# Spell modifier accumulators.
	var spell_cdr_pct: float = 0.0
	var spell_proj_bonus: int = 0
	var spell_proj_speed_pct: float = 0.0
	var spell_area_pct: float = 0.0
	var spell_duration_pct: float = 0.0
	var spell_damage_pct: float = 0.0

	# Bot upgrades — gold-sink purchases. Pre-2026-06-06 combat_training
	# (atk) and toughening (def) were never read here; players spent gold
	# for nothing. Now wired into damage_min/max and armor.
	var up_hp: float = 0.0
	var up_atk: float = 0.0
	var up_def: float = 0.0
	var up_crit: float = 0.0
	var up_loot: float = 0.0
	if not save_state.is_empty():
		up_hp = BotUpgrades.total_for_stat(save_state, "max_hp")
		up_atk = BotUpgrades.total_for_stat(save_state, "atk")
		up_def = BotUpgrades.total_for_stat(save_state, "def")
		up_crit = BotUpgrades.total_for_stat(save_state, "crit_chance")
		up_loot = BotUpgrades.total_for_stat(save_state, "loot_rarity_bonus")

	# Weapon defaults — empty hand 1-2 phys, 1.0s.
	var damage_min: int = 1
	var damage_max: int = 2
	var weapon_speed: float = 1.0
	var weapon_damage_type: String = "physical"
	var weapon_class: String = "1H"

	# Walk equipped slots.
	for slot in equipped.keys():
		var inst: Variant = equipped[slot]
		if inst == null or typeof(inst) != TYPE_DICTIONARY:
			continue
		var base_id: String = String(inst.get("base_id", ""))
		if base_id == "" or not items_db.has(base_id):
			continue
		var item: Dictionary = items_db[base_id]
		var meta: String = String(inst.get("meta_rarity", ""))
		var meta_mult: float = 1.0
		if meta == "ancient":
			meta_mult = 1.20
		elif meta == "primal":
			meta_mult = 1.50
		var qmult: float = Quality.multiplier_for(inst)
		var qmult_affix: float = Quality.affix_multiplier_for(inst)
		var combined_base: float = meta_mult * qmult

		if slot == "weapon":
			damage_min = int(round(float(item.get("damage_min", 1)) * combined_base))
			damage_max = int(round(float(item.get("damage_max", 2)) * combined_base))
			weapon_speed = float(item.get("speed", 1.0))
			weapon_damage_type = String(item.get("damage_type", "physical"))
			weapon_class = String(item.get("weapon_class", "1H"))
		else:
			armor_total += int(round(float(item.get("armor", 0)) * combined_base))
			evasion_total += float(item.get("evasion", 0)) * combined_base

		# Affix rollup (implicit + rolled).
		var combined_affixes: Array = []
		for a in item.get("implicit_affixes", []):
			combined_affixes.append(_realize_implicit(String(a), String(item.get("rarity", "common"))))
		for a in inst.get("affixes", []):
			combined_affixes.append(a)
		var sums: Dictionary = AffixSystem.sum_affix_stats(combined_affixes)

		str_stat += int(round(float(sums.get("str", 0)) * qmult_affix))
		dex_stat += int(round(float(sums.get("dex", 0)) * qmult_affix))
		int_stat += int(round(float(sums.get("int", 0)) * qmult_affix))
		hp_flat += int(round(float(sums.get("hp", 0)) * qmult_affix))
		armor_total += int(round(float(sums.get("armor", 0)) * qmult_affix))
		evasion_total += float(sums.get("evasion", 0)) * qmult_affix
		gear_regen += float(sums.get("hp_regen", 0)) * qmult_affix
		for elem in ELEMENTS:
			resistances[elem] = float(resistances[elem]) + float(sums.get(elem + "_res", 0)) * qmult_affix
		crit_sum += float(sums.get("crit_chance", 0)) * qmult_affix
		haste_sum += float(sums.get("haste_pct", 0)) * qmult_affix
		lifesteal_pct += float(sums.get("lifesteal_pct", 0)) * qmult_affix
		spell_cdr_pct += float(sums.get("spell_cdr_pct", 0)) * qmult_affix
		spell_proj_bonus += int(round(float(sums.get("spell_proj_bonus", 0)) * qmult_affix))
		spell_proj_speed_pct += float(sums.get("spell_proj_speed_pct", 0)) * qmult_affix
		spell_area_pct += float(sums.get("spell_area_pct", 0)) * qmult_affix
		spell_duration_pct += float(sums.get("spell_duration_pct", 0)) * qmult_affix
		spell_damage_pct += float(sums.get("spell_damage_pct", 0)) * qmult_affix
		# Extra-damage range affixes (per-element min/max).
		for elem in ["physical", "fire", "cold", "lightning", "holy", "poison", "dark"]:
			var key: String = elem + "_extra"
			var lo: int = int(round(float(sums.get(key + "_min", 0)) * qmult_affix))
			var hi: int = int(round(float(sums.get(key + "_max", 0)) * qmult_affix))
			if lo > 0 or hi > 0:
				var prev: Dictionary = extra_damage.get(elem, {"min": 0, "max": 0})
				extra_damage[elem] = {"min": int(prev.min) + lo, "max": int(prev.max) + hi}

	# Wire the previously-dead upgrades into damage + armor. atk → flat
	# bonus on both damage_min and damage_max (so a "1-2 dagger + 5 atk
	# upgrade" reads 6-7). def → armor.
	if up_atk > 0.0:
		damage_min += int(round(up_atk))
		damage_max += int(round(up_atk))
	if up_def > 0.0:
		armor_total += int(round(up_def))

	# Primary excess feeds derived stats.
	var str_excess: int = str_stat - 5
	var dex_excess: int = dex_stat - 5
	var int_excess: int = int_stat - 5
	crit_sum += float(dex_excess) * 0.5
	haste_sum += float(dex_excess) * 1.0
	spell_damage_pct += float(int_excess) * 1.0
	spell_area_pct += float(int_excess) * 0.5
	spell_duration_pct += float(int_excess) * 0.5

	# HP rollup with str-mult + species hp_pct + bot upgrade.
	var max_hp: int = int(round(float(_BASE_HP + (level - 1) * 8 + int(up_hp) + hp_flat) * sp_hp_mult * (1.0 + float(str_excess) * 0.015)))

	# Crit / haste / evasion caps.
	var crit_chance: float = clampf(crit_sum + up_crit, 0.0, 75.0)
	var haste_pct: float = clampf(haste_sum, 0.0, 200.0)
	var evasion_capped: float = clampf(evasion_total, 0.0, 75.0)
	for elem in resistances.keys():
		resistances[elem] = clampf(float(resistances[elem]), -100.0, 75.0)

	var attack_interval: float = max(0.15, weapon_speed / (1.0 + haste_pct / 100.0))

	# Worn-tag passive bonuses — vitality / regen / faith on regen,
	# fortified on armor (was applied to `defense` pre-fix, never showed
	# in stats UI), swiftness on move_speed, vision on aggro.
	# `ponderous` (weapon-only) slows attack_interval.
	var hp_regen: float = gear_regen
	for b in blessings:
		if String(b.get("kind", "")) == "hp_regen":
			hp_regen += float(b.get("value", 0))
	var worn_tags: Array = []
	for slot in _DEF_SLOTS:
		var inst: Variant = equipped.get(slot, null)
		if inst == null or typeof(inst) != TYPE_DICTIONARY:
			continue
		var bid: String = String(inst.get("base_id", ""))
		if bid == "" or not items_db.has(bid):
			continue
		var combined: Array = UITheme.combined_flavor_tags(items_db[bid], inst)
		for t in combined:
			worn_tags.append(t)
	var swift_count: int = 0
	var fortified_count: int = 0
	var vision_count: int = 0
	for t in worn_tags:
		match String(t):
			"vitality": hp_regen += 1.0
			"regen": hp_regen += 0.5
			"faith": hp_regen += 0.5
			"swiftness": swift_count += 1
			"fortified": fortified_count += 1
			"vision": vision_count += 1
	var move_speed: float = _BASE_MOVE_SPEED
	if swift_count > 0:
		var bonus: float = clampf(float(swift_count) * 0.10, 0.0, 0.30)
		move_speed = _BASE_MOVE_SPEED * (1.0 + bonus)
	if fortified_count > 0:
		var fbonus: float = clampf(float(fortified_count) * 0.20, 0.0, 0.50)
		armor_total = int(round(float(armor_total) * (1.0 + fbonus)))
	# Ponderous — applied AFTER the haste floor. Slows attack_interval.
	# Re-clamp the floor to keep the 0.15s invariant.
	var weapon_inst: Variant = equipped.get("weapon", null)
	var ponderous_count: int = 0
	if weapon_inst != null and typeof(weapon_inst) == TYPE_DICTIONARY:
		var w_bid: String = String(weapon_inst.get("base_id", ""))
		if w_bid != "" and items_db.has(w_bid):
			var combined: Array = UITheme.combined_flavor_tags(items_db[w_bid], weapon_inst)
			for t in combined:
				if String(t) == "ponderous":
					ponderous_count += 1
	if ponderous_count > 0:
		attack_interval = max(0.15, attack_interval * (1.0 + 0.10 * float(ponderous_count)))

	# Loot rarity + xp gain — folded into the stat dict so callers can
	# display them. Species + bot-upgrade contributions stack.
	var loot_rarity_bonus: float = up_loot + float(sp.get("loot_pct", 0))
	var xp_gain_pct: float = float(sp.get("xp_pct", 0))
	# Blessings can add to either; surface both via the dict.
	for b in blessings:
		match String(b.get("kind", "")):
			"loot_rarity": loot_rarity_bonus += float(b.get("value", 0))
			"xp_gain": xp_gain_pct += float(b.get("value", 0))

	# Pack the final dict.
	out["str"] = str_stat
	out["dex"] = dex_stat
	out["int"] = int_stat
	out["max_hp"] = max_hp
	out["hp_regen"] = hp_regen
	out["armor"] = armor_total
	out["evasion"] = evasion_capped
	out["resistances"] = resistances
	out["crit_chance"] = crit_chance
	out["haste_pct"] = haste_pct
	out["lifesteal_pct"] = lifesteal_pct
	out["damage_min"] = damage_min
	out["damage_max"] = damage_max
	out["weapon_speed"] = weapon_speed
	out["weapon_damage_type"] = weapon_damage_type
	out["weapon_class"] = weapon_class
	out["attack_interval"] = attack_interval
	out["extra_damage"] = extra_damage
	out["spell_cdr_pct"] = spell_cdr_pct
	out["spell_proj_bonus"] = spell_proj_bonus
	out["spell_proj_speed_pct"] = spell_proj_speed_pct
	out["spell_area_pct"] = spell_area_pct
	out["spell_duration_pct"] = spell_duration_pct
	out["spell_damage_pct"] = spell_damage_pct
	out["spell_element_pct"] = spell_element_pct
	out["move_speed"] = move_speed
	out["aggro_bonus"] = vision_count
	out["loot_rarity_bonus"] = loot_rarity_bonus
	out["xp_gain_pct"] = xp_gain_pct
	# Allocation-related fields surfaced for the outpost +/- buttons.
	out["alloc_str"] = alloc_str
	out["alloc_dex"] = alloc_dex
	out["alloc_int"] = alloc_int
	out["unspent_points"] = int(save_state.get("unspent_points", 0))
	return out

# Default-shaped stat dict so callers always see every key.
static func _initial_dict() -> Dictionary:
	var d: Dictionary = {
		"str": 5, "dex": 5, "int": 5,
		"level": 1, "xp": 0, "gold": 0, "species_id": "",
		"max_hp": _BASE_HP, "hp_regen": 0.0,
		"armor": 0, "evasion": 0.0, "resistances": {},
		"crit_chance": 0.0, "haste_pct": 0.0, "lifesteal_pct": 0.0,
		"damage_min": 1, "damage_max": 2,
		"weapon_speed": 1.0, "weapon_damage_type": "physical", "weapon_class": "1H",
		"attack_interval": 1.0, "extra_damage": {},
		"spell_cdr_pct": 0.0, "spell_proj_bonus": 0,
		"spell_proj_speed_pct": 0.0, "spell_area_pct": 0.0,
		"spell_duration_pct": 0.0, "spell_damage_pct": 0.0,
		"spell_element_pct": {},
		"move_speed": _BASE_MOVE_SPEED, "aggro_bonus": 0,
		"loot_rarity_bonus": 0.0, "xp_gain_pct": 0.0,
		"alloc_str": 0, "alloc_dex": 0, "alloc_int": 0, "unspent_points": 0,
	}
	for elem in RESISTANCE_ELEMENTS:
		d["resistances"][elem] = 0.0
	for elem in SPELL_ELEMENTS:
		d["spell_element_pct"][elem] = 0.0
	return d

# Implicit affix realizer — same as bot.gd::_realize_implicit. Lifted here
# because StatCalc must be self-contained for outpost / main-menu callers
# that don't have a Bot instance.
static func _realize_implicit(affix_id: String, item_rarity: String) -> Dictionary:
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
			out["value"] = int(round((lo + hi) / 2.0))
	else:
		out["value"] = int(tier_entry)
	return out
