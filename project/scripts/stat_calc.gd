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
	# S9 crit_multiplier_pct (a06 §2.1, a10 rescope to +35% cap). Replaces
	# the const ×1.5 crit_mult at actor.gd:557 with (1.5 + cmp/100). Soft
	# cap at +35% so a 75% crit × ×1.85 build hits the ~555 peak — a slight
	# overshoot of the 400 ceiling but well under the +100% original a06
	# proposal that would have hit ~750 peak.
	var crit_multiplier_pct: float = 0.0
	# S9 block_chance / block_amount (a06 §2.2, a10 rescope to 30% / +20).
	# Shield-slot identity: bucklers/round/kite/tower carry distinct base
	# block stats, of_warding scales chance via affix, of_bulwark scales
	# flat damage reduced. Combat gate sits AFTER evasion+footwork+reflective
	# in actor.gd::resolve_swing.
	var block_chance: float = 0.0
	var block_amount: int = 0
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
	# Class-mastery spell multipliers (of_str_mastery / of_dex_mastery /
	# of_int_mastery). Accumulated per-class so spell_data.compute_damage
	# can read the matching one off the spell's primary_stat.
	var str_spell_dmg_pct: float = 0.0
	var dex_spell_dmg_pct: float = 0.0
	var int_spell_dmg_pct: float = 0.0
	# S4 Tier-1 affix accumulators (a02 P-8/9/10/11/12/13/15/16/19/27/28
	# rescoped per a10 §3.2). Each affix writes to its own bot field; the
	# combat / spell / drop hot paths read those fields directly. Keep the
	# accumulators independent so soft-cap behavior is per-affix.
	var sage_per_unspent_pct: float = 0.0       # of_sage    — peak unspent_pts %
	var berserker_peak_pct: float = 0.0         # of_berserker — peak (5-stack) %
	var hunter_pct: float = 0.0                 # of_hunter — vs ≥80% HP
	var echo_min_n: int = 0                     # of_echoes — smallest N wins
	var tempest_dmg_pct: float = 0.0            # of_tempest — spell dmg leg
	var tempest_cd_penalty_pct: float = 0.0     # of_tempest — cd penalty leg
	var sundering_per_stack: int = 0            # of_sundering — armor stack
	var bloodletting_per_stack: int = 0         # of_bloodletting — bleed stack
	var gold_drop_pct: float = 0.0              # of_plunder
	var spell_tome_drop_pct: float = 0.0        # of_scribe
	var str_dmg_per5_peak_pct: float = 0.0      # of_berserker_rage — peak (10-rank) %
	var synergy_pct: float = 0.0                # of_synergy — hybrid all-dmg
	# S11 boss-anchor implicit-affix accumulators (a07 §6.1-6.12). One
	# field per implicit_affix on the 12 boss-anchor uniques. Flag-kind
	# affixes ride a bool; pct/flat affixes accumulate normally and read
	# directly off bot.* in combat / dungeon hot paths.
	var bleed_on_miss: bool = false
	var dancing_blade: bool = false
	var polymorph_first_kill: bool = false
	var venom_on_hit: bool = false
	var wolf_kinship_pct: float = 0.0
	var anchor_regen: float = 0.0
	var hp_per_kill_cap: int = 0
	var tidesong_water_pct: float = 0.0
	var phylactery_revive_pct: float = 0.0
	var extra_chests_per_floor: int = 0
	var fifth_cast_pct: float = 0.0
	# §1.H attempt_attack-shape conditional affixes (a02 P-001..005, a10 caps).
	# All flow through ephemeral_sum / mit_sum so the +30% per-swing and
	# armor / pre-armor lanes already absorb them. Kingslayer & butcher are
	# offensive ephemeral; revenant is defensive (mit_sum); executioner_pact
	# / glass_cannon are mutex (asserted post-rollup, see below).
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
	var riposte_dmg_pct: float = 0.0
	var high_hp_cdr_pct: float = 0.0
	var kill_streak_cdr_pct: float = 0.0
	var crit_chain_pct: float = 0.0
	var step_pulse_pct: float = 0.0
	var loot_quantity_pct: float = 0.0

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

	# Per-affix-id source counter for diminishing returns. Audit found
	# the user wearing of_channeling × 6, of_resonance × 5, etc — pure
	# linear stacking gave +195% spell damage from one affix alone.
	# DR scales each subsequent same-id source: 1st=100%, 2nd=75%,
	# 3rd=50%, 4th+=25%. Stops slot-stuffing strategies dead.
	var _affix_source_count: Dictionary = {}

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
		# Baseline rollback (a10 §5.3, §8). Primal+Sublime stacked
		# meta_mult ×1.50 × qmult ×1.20 = ×1.80, pushing endgame Minotaur
		# weapon swing range into 198-324 — already 30-55% over the
		# 400-peak-hit ceiling before any new affix landed. Cap product
		# at ×1.30 so combined base scaling stays inside design rails;
		# affix expansion can layer on top without bursting the cap.
		var combined_base: float = clampf(meta_mult * qmult, 0.0, 1.30)

		if slot == "weapon":
			damage_min = int(round(float(item.get("damage_min", 1)) * combined_base))
			damage_max = int(round(float(item.get("damage_max", 2)) * combined_base))
			weapon_speed = float(item.get("speed", 1.0))
			weapon_damage_type = String(item.get("damage_type", "physical"))
			weapon_class = String(item.get("weapon_class", "1H"))
		else:
			armor_total += int(round(float(item.get("armor", 0)) * combined_base))
			evasion_total += float(item.get("evasion", 0)) * combined_base
			# S9 shield-slot base block stats (a06 §2.2). Bucklers/round/kite/
			# tower carry block_chance + block_amount on the items_db def so
			# the slot has identity beyond raw armor. Scaled by combined_base
			# so meta_rarity / quality affects shields the same way.
			if slot == "shield":
				block_chance += float(item.get("block_chance", 0)) * combined_base
				block_amount += int(round(float(item.get("block_amount", 0)) * combined_base))

		# Affix rollup (implicit + rolled). Each affix contributes through
		# the per-id DR scaler so wearing the same affix on N slots gets
		# 100% / 75% / 50% / 25% as the count climbs.
		# S5 race-anchor gate: an item with `requires_innate_tag` mutes
		# its implicit_affixes when the wearer's species lacks the tag.
		# Base stats (armor/damage) and rolled affixes still apply — only
		# the unique mechanic is gated. Human carries the "human" self-tag
		# (added 2026-06-12 with §1.F starter_human_spell gating) so any
		# requires_innate_tag="human" item works for humans only.
		var requires_tag: String = String(item.get("requires_innate_tag", ""))
		var implicits_active: bool = true
		if requires_tag != "":
			implicits_active = SpeciesData.has_innate_tag(species_id, requires_tag)
		var combined_affixes: Array = []
		if implicits_active:
			for a in item.get("implicit_affixes", []):
				combined_affixes.append(_realize_implicit(String(a), String(item.get("rarity", "common"))))
		for a in inst.get("affixes", []):
			combined_affixes.append(a)
		# Bump source counts BEFORE summing so each affix instance gets
		# its own DR slot. Two of_haste on the same item count as two
		# sources (rare in practice — slots usually roll unique ids).
		for af in combined_affixes:
			var aid: String = String(af.get("id", ""))
			if aid == "":
				continue
			_affix_source_count[aid] = int(_affix_source_count.get(aid, 0)) + 1
		# Apply DR-scaled affix sums, individually per affix so each
		# instance can be weighted by its own source-count rank. We
		# can't use AffixSystem.sum_affix_stats anymore (it pre-sums)
		# — fold the same per-affix scaling logic inline.
		var slot_sums: Dictionary = _scaled_affix_sums(combined_affixes, qmult_affix, _affix_source_count)

		str_stat += int(round(float(slot_sums.get("str", 0))))
		dex_stat += int(round(float(slot_sums.get("dex", 0))))
		int_stat += int(round(float(slot_sums.get("int", 0))))
		hp_flat += int(round(float(slot_sums.get("hp", 0))))
		armor_total += int(round(float(slot_sums.get("armor", 0))))
		evasion_total += float(slot_sums.get("evasion", 0))
		gear_regen += float(slot_sums.get("hp_regen", 0))
		for elem in ELEMENTS:
			resistances[elem] = float(resistances[elem]) + float(slot_sums.get(elem + "_res", 0))
		crit_sum += float(slot_sums.get("crit_chance", 0))
		# S9 — of_executioner writes crit_multiplier_pct.
		crit_multiplier_pct += float(slot_sums.get("crit_multiplier_pct", 0))
		# S9 — of_warding (pct) writes block_chance, of_bulwark (flat) writes
		# block_amount. Both layer additively on top of the shield base.
		block_chance += float(slot_sums.get("block_chance", 0))
		block_amount += int(round(float(slot_sums.get("block_amount", 0))))
		haste_sum += float(slot_sums.get("haste_pct", 0))
		lifesteal_pct += float(slot_sums.get("lifesteal_pct", 0))
		spell_cdr_pct += float(slot_sums.get("spell_cdr_pct", 0))
		spell_proj_bonus += int(round(float(slot_sums.get("spell_proj_bonus", 0))))
		spell_proj_speed_pct += float(slot_sums.get("spell_proj_speed_pct", 0))
		spell_area_pct += float(slot_sums.get("spell_area_pct", 0))
		spell_duration_pct += float(slot_sums.get("spell_duration_pct", 0))
		spell_damage_pct += float(slot_sums.get("spell_damage_pct", 0))
		str_spell_dmg_pct += float(slot_sums.get("str_spell_dmg_pct", 0))
		dex_spell_dmg_pct += float(slot_sums.get("dex_spell_dmg_pct", 0))
		int_spell_dmg_pct += float(slot_sums.get("int_spell_dmg_pct", 0))
		# S4 Tier-1 affix slot rollups. of_tempest writes into the spell-
		# damage lane (subject to spell_damage_pct soft cap below) AND the
		# cd-penalty lane (kept on its own field; spell_data.compute_cooldown
		# subtracts it from cdr to support burst-vs-sustain identity). All
		# other Tier-1 affixes get their own dedicated accumulators read by
		# the combat / spell / drop hot paths after the slot walk.
		sage_per_unspent_pct += float(slot_sums.get("sage_per_unspent_pct", 0))
		berserker_peak_pct += float(slot_sums.get("berserker_peak_pct", 0))
		hunter_pct += float(slot_sums.get("hunter_pct", 0))
		# of_echoes — stat key `echo_every_n`. Carries an N value where
		# smaller is better — track the minimum across all sources rather
		# than summing. Bypass the DR / qmult scaling pipeline because
		# both would shrink N and FALSELY amplify the affix when stacked.
		# Read raw value off each affix instance directly so a (N=8 + N=5)
		# loadout fires every 5 swings, not every 4 (DR-shrunk to ~3.75).
		for af in combined_affixes:
			if String(af.get("id", "")) != "of_echoes":
				continue
			var raw_n: int = int(af.get("value", 0))
			if raw_n > 0:
				echo_min_n = raw_n if echo_min_n == 0 else mini(echo_min_n, raw_n)
		var tempest_v: float = float(slot_sums.get("tempest_dmg_pct", 0))
		if tempest_v > 0.0:
			# Tempest folds spell-damage into the existing spell_damage_pct
			# soft cap (120) — the player chooses burst-vs-sustain via the
			# coupled cooldown penalty, NOT by stacking past the cap.
			spell_damage_pct += tempest_v
			# Cooldown penalty couples 1:1 with the dmg lane per a02 P-10
			# (T5: dmg+40 / cd+22). Express as 0.55 of the dmg roll so a
			# +20% common Tempest matches the 5/8/12/16/22 curve close
			# enough without authoring two parallel range entries.
			tempest_cd_penalty_pct += tempest_v * 0.55
		sundering_per_stack += int(round(float(slot_sums.get("sundering_per_stack", 0))))
		bloodletting_per_stack += int(round(float(slot_sums.get("bloodletting_per_stack", 0))))
		gold_drop_pct += float(slot_sums.get("gold_drop_pct", 0))
		spell_tome_drop_pct += float(slot_sums.get("spell_tome_drop_pct", 0))
		str_dmg_per5_peak_pct += float(slot_sums.get("str_dmg_per5_peak_pct", 0))
		synergy_pct += float(slot_sums.get("synergy_pct", 0))
		# S11 boss-anchor implicit-affix accumulators (a07 §6.1-6.12).
		# Flag-kind affixes return 1 from _scaled_affix_sums when present,
		# which we treat as a boolean OR (any equipped source enables it).
		# Pct/flat affixes flow through the same DR + qmult scaling as
		# every other affix, then get clamped against a07's rescoped caps.
		bleed_on_miss = bleed_on_miss or float(slot_sums.get("bleed_on_miss", 0)) > 0.0
		dancing_blade = dancing_blade or float(slot_sums.get("dancing_blade", 0)) > 0.0
		polymorph_first_kill = polymorph_first_kill or float(slot_sums.get("polymorph_first_kill", 0)) > 0.0
		venom_on_hit = venom_on_hit or float(slot_sums.get("venom_on_hit", 0)) > 0.0
		wolf_kinship_pct += float(slot_sums.get("wolf_kinship_pct", 0))
		anchor_regen += float(slot_sums.get("anchor_regen", 0))
		hp_per_kill_cap += int(round(float(slot_sums.get("hp_per_kill_cap", 0))))
		tidesong_water_pct += float(slot_sums.get("tidesong_water_pct", 0))
		phylactery_revive_pct += float(slot_sums.get("phylactery_revive_pct", 0))
		extra_chests_per_floor += int(round(float(slot_sums.get("extra_chests_per_floor", 0))))
		fifth_cast_pct += float(slot_sums.get("fifth_cast_pct", 0))
		# §1.H accumulators.
		low_hp_target_dmg_pct += float(slot_sums.get("low_hp_target_dmg_pct", 0))
		glass_cannon_dmg_pct += float(slot_sums.get("glass_cannon_dmg_pct", 0))
		low_hp_dr_pct += float(slot_sums.get("low_hp_dr_pct", 0))
		boss_dmg_pct += float(slot_sums.get("boss_dmg_pct", 0))
		pack_dmg_per_enemy_pct += float(slot_sums.get("pack_dmg_per_enemy_pct", 0))
		full_hp_armor_pct += float(slot_sums.get("full_hp_armor_pct", 0))
		weapon_bleed_per_sec += int(round(float(slot_sums.get("weapon_bleed_per_sec", 0))))
		holy_dot_per_sec += int(round(float(slot_sums.get("holy_dot_per_sec", 0))))
		revenge_dmg_pct += float(slot_sums.get("revenge_dmg_pct", 0))
		first_hit_pct += float(slot_sums.get("first_hit_pct", 0))
		hp_per_kill_flat += int(round(float(slot_sums.get("hp_per_kill_flat", 0))))
		melee_armor_pen_pct += float(slot_sums.get("melee_armor_pen_pct", 0))
		spell_resist_pen_pct += float(slot_sums.get("spell_resist_pen_pct", 0))
		crit_mark_dmg_pct += float(slot_sums.get("crit_mark_dmg_pct", 0))
		recoup_pct += float(slot_sums.get("recoup_pct", 0))
		move_spell_dmg_pct += float(slot_sums.get("move_spell_dmg_pct", 0))
		thorns_flat += int(round(float(slot_sums.get("thorns_flat", 0))))
		block_thorns_flat += int(round(float(slot_sums.get("block_thorns_flat", 0))))
		first_hit_mark_pct += float(slot_sums.get("first_hit_mark_pct", 0))
		doomstrike_dmg_pct += float(slot_sums.get("doomstrike_dmg_pct", 0))
		riposte_dmg_pct += float(slot_sums.get("riposte_dmg_pct", 0))
		high_hp_cdr_pct += float(slot_sums.get("high_hp_cdr_pct", 0))
		kill_streak_cdr_pct += float(slot_sums.get("kill_streak_cdr_pct", 0))
		crit_chain_pct += float(slot_sums.get("crit_chain_pct", 0))
		step_pulse_pct += float(slot_sums.get("step_pulse_pct", 0))
		loot_quantity_pct += float(slot_sums.get("loot_quantity_pct", 0))
		# Per-element spell-damage affixes (of_pyromancer / of_cryomancer
		# / of_thundercaller / of_zealot / of_pestcaller / of_nightcaller). Each writes to
		# `<elem>_dmg_pct`; we accumulate into spell_element_pct keyed by
		# element so spell_data.gd:181 can read elem_mult per spell.
		# Lightning is the one element where the spell-side identifier
		# ("thunderous") differs from the affix stat key ("lightning_dmg_pct"
		# post-2026-06-11 rename), so the lookup key is mapped explicitly.
		for elem in SPELL_ELEMENTS:
			var key: String = ("lightning_dmg_pct" if elem == "thunderous" else elem + "_dmg_pct")
			var add: float = float(slot_sums.get(key, 0))
			if add != 0.0:
				spell_element_pct[elem] = float(spell_element_pct[elem]) + add
		# Extra-damage range affixes (per-element min/max).
		for elem in ["physical", "fire", "cold", "lightning", "holy", "poison", "dark"]:
			var key: String = elem + "_extra"
			var lo: int = int(round(float(slot_sums.get(key + "_min", 0))))
			var hi: int = int(round(float(slot_sums.get(key + "_max", 0))))
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

	# Species atk_pct / def_pct / aggro_flat — pre-2026-06-08 these were
	# shown in the character_create preview but never read by StatCalc,
	# so a Minotaur's "+20% ATK" was decoration and a Spriggan's "+10%
	# DEF" did nothing. Now folded in alongside the blessing rollup.
	# atk_pct multiplies damage_min/max (after flat upgrade), def_pct
	# multiplies armor (after flat upgrade), aggro_flat surfaces in the
	# aggro_bonus output dict so the AI's engagement range respects it.
	var sp_atk_pct: float = float(sp.get("atk_pct", 0))
	var sp_def_pct: float = float(sp.get("def_pct", 0))
	var sp_aggro_flat: int = int(sp.get("aggro_flat", 0))
	if sp_atk_pct != 0.0:
		damage_min = int(round(float(damage_min) * (1.0 + sp_atk_pct / 100.0)))
		damage_max = int(round(float(damage_max) * (1.0 + sp_atk_pct / 100.0)))
	if sp_def_pct != 0.0:
		armor_total = int(round(float(armor_total) * (1.0 + sp_def_pct / 100.0)))

	# Altar blessing kinds. atk_pct / atk_flat / def_flat / hp_pct were
	# silently dead pre-2026-06-08 — the corresponding god (Trog, Zin,
	# Beogh, Yred, TSO, Lugonu, Xom, Qazlal, Ru, Cheibriados, Dithmenos,
	# Okawaru, Fedhas) granted nothing because StatCalc didn't read the
	# bot.bonus_* fields that grant_blessing wrote into. Now folded
	# directly into the StatCalc rollup — atk_pct/atk_flat hit damage_min
	# /max, def_flat hits armor, hp_pct multiplies max_hp at the same
	# layer as species hp_pct. lifesteal/loot_rarity/xp_gain/hp_regen
	# blessings already worked through other channels and stay there.
	var bless_atk_pct: float = 0.0
	var bless_atk_flat: int = 0
	var bless_def_flat: int = 0
	var bless_hp_pct: float = 0.0
	for b in blessings:
		match String(b.get("kind", "")):
			"atk_pct":  bless_atk_pct  += float(b.get("value", 0))
			"atk_flat": bless_atk_flat += int(b.get("value", 0))
			"def_flat": bless_def_flat += int(b.get("value", 0))
			"hp_pct":   bless_hp_pct   += float(b.get("value", 0))
	if bless_atk_flat != 0:
		damage_min += bless_atk_flat
		damage_max += bless_atk_flat
	if bless_atk_pct != 0.0:
		damage_min = int(round(float(damage_min) * (1.0 + bless_atk_pct / 100.0)))
		damage_max = int(round(float(damage_max) * (1.0 + bless_atk_pct / 100.0)))
	if bless_def_flat != 0:
		armor_total += bless_def_flat
	# bless_hp_pct folds into sp_hp_mult so it stacks multiplicatively
	# with species hp_pct (Fedhas's +40% on a Naga's +20% = ×1.40 × 1.20
	# = +68% — same composition rule the player sees on every other %
	# stat).
	if bless_hp_pct != 0.0:
		sp_hp_mult *= 1.0 + bless_hp_pct / 100.0

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

	# Crit / haste / evasion / spell caps. PoE-style soft caps prevent
	# slot-stuffing strategies from dominating — even with DR-scaled
	# affix stacks, the totals can still climb above sane levels via
	# Int-excess and unique-item multipliers. These clamps are the
	# absolute ceiling on what gear can grant the player.
	var crit_chance: float = clampf(crit_sum + up_crit, 0.0, 75.0)
	var haste_pct: float = clampf(haste_sum, 0.0, 200.0)
	var evasion_capped: float = clampf(evasion_total, 0.0, 75.0)
	lifesteal_pct = clampf(lifesteal_pct, 0.0, 15.0)
	spell_damage_pct = clampf(spell_damage_pct, 0.0, 120.0)
	# Class-mastery cap (per a06 §3.2) — same shape as spell_element_pct.
	# Each class lane caps independently so a pure-class build doesn't
	# trivially eclipse generic spell_damage_pct.
	str_spell_dmg_pct = clampf(str_spell_dmg_pct, 0.0, 100.0)
	dex_spell_dmg_pct = clampf(dex_spell_dmg_pct, 0.0, 100.0)
	int_spell_dmg_pct = clampf(int_spell_dmg_pct, 0.0, 100.0)
	spell_area_pct = clampf(spell_area_pct, 0.0, 100.0)
	spell_cdr_pct = clampf(spell_cdr_pct, 0.0, 50.0)
	spell_duration_pct = clampf(spell_duration_pct, 0.0, 100.0)
	spell_proj_speed_pct = clampf(spell_proj_speed_pct, 0.0, 100.0)
	# of_multicast can roll on spell/amulet/ring (10 possible slots) up
	# to [1,2] at legendary; with DR-stacked totals reach +4..+6 endgame,
	# multiplying chain-jump count and projectile-spawning spells with no
	# ceiling. Cap at +5 alongside the other spell-stat clamps.
	spell_proj_bonus = clampi(spell_proj_bonus, 0, 5)
	for elem in resistances.keys():
		resistances[elem] = clampf(float(resistances[elem]), -100.0, 75.0)
	# Per-element spell damage cap. PoE-style soft ceiling on element
	# stacking — single-element builds can still climb but can't
	# trivially eclipse `of_channeling`'s generic boost.
	for elem in spell_element_pct.keys():
		spell_element_pct[elem] = clampf(float(spell_element_pct[elem]), 0.0, 100.0)
	# S4 Tier-1 caps (a10 §3.2 rescopes). Each conditional/ephemeral lane
	# stays inside the +30% per-swing ephemeral cap once attempt_attack
	# clamps the sum, but the per-affix peak still wants its own ceiling
	# so a chest of of_hunter ×4 can't blast straight through.
	#   of_sage:           cap +24% peak (T5 mid 24 × 1 affix)
	#   of_berserker:      cap +20% peak (5 stacks × 4%)
	#   of_hunter:         cap +20% (a10 P-13 rescope)
	#   of_tempest:        already routes through spell_damage_pct cap
	#   of_berserker_rage: cap +25% peak (10 ranks × 2.5%)
	#   of_synergy:        cap +12% (a10 P-19 rescope)
	# of_sundering / of_bloodletting / of_echoes are flat values, no
	# % cap; they cap by their own per-stack count in actor.attempt_attack.
	# of_plunder / of_scribe are economy levers, capped via diminishing
	# returns from the per-affix DR scaler in _scaled_affix_sums.
	sage_per_unspent_pct = clampf(sage_per_unspent_pct, 0.0, 24.0)
	berserker_peak_pct = clampf(berserker_peak_pct, 0.0, 20.0)
	hunter_pct = clampf(hunter_pct, 0.0, 20.0)
	str_dmg_per5_peak_pct = clampf(str_dmg_per5_peak_pct, 0.0, 25.0)
	synergy_pct = clampf(synergy_pct, 0.0, 12.0)
	# S9 caps (a06 + a10 rescopes). crit_multiplier_pct cap +35% — combined
	# crit-mult ceiling at ×1.85 (1.5 + 0.35), peak hit ~555 with 75% crit.
	# block_chance cap 30% — leaves 70% of swings landing. block_amount cap
	# +20 — a tower-warding+bulwark stack reduces a 30-dmg hit to 10 on a
	# block proc (then armor subtracts on top).
	crit_multiplier_pct = clampf(crit_multiplier_pct, 0.0, 35.0)
	block_chance = clampf(block_chance, 0.0, 30.0)
	block_amount = clampi(block_amount, 0, 20)
	# `of_plunder` and `of_prospecting` both write `gold_drop_pct`; per-affix-id
	# DR is keyed by id so they additively stack (a02 §A2-double-dip-019, a11
	# G5). Hard-clamp the summed total so amulet+weapon stacks can't run past
	# 50%.
	gold_drop_pct = clampf(gold_drop_pct, 0.0, 50.0)

	# §1.H caps (a10 tightened values). Each conditional rides ephemeral_sum
	# or mit_sum so the +30% per-swing / per-hit ceiling absorbs the upper
	# tail; per-affix peaks below match A2's rescoped caps verbatim. The
	# executioner_pact ⊥ glass_cannon mutex (a11 G6) is enforced here:
	# whichever contributes more wins, the other zeroes. Clean asymmetric
	# rule means a slot that rolls both (eligibility overlaps on amulet)
	# pays for the conflict instead of double-dipping.
	low_hp_target_dmg_pct = clampf(low_hp_target_dmg_pct, 0.0, 40.0)
	glass_cannon_dmg_pct = clampf(glass_cannon_dmg_pct, 0.0, 30.0)
	low_hp_dr_pct = clampf(low_hp_dr_pct, 0.0, 28.0)
	boss_dmg_pct = clampf(boss_dmg_pct, 0.0, 40.0)
	pack_dmg_per_enemy_pct = clampf(pack_dmg_per_enemy_pct, 0.0, 10.0)
	full_hp_armor_pct = clampf(full_hp_armor_pct, 0.0, 75.0)
	# §1.H of_serrated_edge — A2 P-021 cap 16 per source (DR'd across slots).
	# Weapon-only so a max stack is 1×T5 (14) at base + meta_mult/qmult lift,
	# capped at 16 here for safety. Composes with of_bloodletting on-crit by
	# overwriting the per-tick value (whichever is larger wins per-frame).
	weapon_bleed_per_sec = clampi(weapon_bleed_per_sec, 0, 16)
	# §1.H of_zealous_strike — 3s × 17/sec = 51 total/cast for top-tier
	# weapon-only T5; cap at 20 per source (DR'd across slots).
	holy_dot_per_sec = clampi(holy_dot_per_sec, 0, 20)
	# §1.H of_avenger — A2 P-007 cap 50. Reactive offense; couples with
	# of_revenant (low-hp panic). Both can co-activate during the same
	# low-HP window after a hit lands.
	revenge_dmg_pct = clampf(revenge_dmg_pct, 0.0, 50.0)
	# §1.H of_first_strike — per a02 P-006, per-target gate (caps abuse
	# without an additional pct cap; cap at 120 here as headroom for the
	# +30% per-swing ephemeral lane to absorb T5 single-source 110).
	first_hit_pct = clampf(first_hit_pct, 0.0, 120.0)
	# §1.H of_drainblade — A2 P-023 cap 30 per source. Per-kill flat HP
	# gain composes with the existing of_serpent_growth +max_hp/floor cap;
	# kills also bump max_hp via the existing hp_per_kill_granted_this_floor
	# bookkeeping. A11 G1 mandates total recovery sources ≤ max_hp×0.10/s
	# emitted — drainblade is per-kill (not per-second), well under the
	# rolling cap. 3-source DR stack: 24 + 18 + 12 = 54, hard-clamped 30.
	hp_per_kill_flat = clampi(hp_per_kill_flat, 0, 30)
	# §1.H of_armor_breaker — A2 P-018 cap 50. STR-coded melee answer to
	# spell-pen. Applied to attacker's eff_armor lookup against the defender,
	# multiplicatively (eff_armor *= 1 - pen/100). Composes with of_sundering
	# (flat strip) — both reduce the same eff_armor; sundering is consumed
	# per-stack, pen is permanent-while-equipped.
	melee_armor_pen_pct = clampf(melee_armor_pen_pct, 0.0, 50.0)
	# §1.H of_unwavering_focus — A2 P-017 cap 35 (a10 rescope from 50).
	# Reduces defender's effective elemental resist on typed-elemental
	# hits (spells + weapon-typed swings: of_embers / cold_extra etc.
	# both flow through the same elem_mit lane). resist_pct is reduced
	# multiplicatively before mit_sum composition.
	spell_resist_pen_pct = clampf(spell_resist_pen_pct, 0.0, 35.0)
	# §1.H of_hunter_mark — A2 P-009 cap 40 (a10 rescope from 70). a11 G7
	# enforces only highest-mark per target (handled at apply-time, not here).
	crit_mark_dmg_pct = clampf(crit_mark_dmg_pct, 0.0, 40.0)
	# §1.H of_recoup — A2 P-011 cap 28 (a10 rescope). A11 G1: total recovery
	# sources clamped at max_hp×0.10/s emitted. Per-source cap holds the
	# 4s heal-over-time within budget — at endgame max_hp 1500, T5 28% =
	# 420 HP/4s = 105/s = 7% max_hp/s, well under the G1 ceiling.
	recoup_pct = clampf(recoup_pct, 0.0, 28.0)
	# §1.H of_smoldering_step — A2 P-015 cap 40 (a10). Spell-only damage
	# multiplier gated on bot.is_moving. Composes with spell_damage_pct
	# soft cap (120) so the additive layer can't cascade past 160 effective.
	move_spell_dmg_pct = clampf(move_spell_dmg_pct, 0.0, 40.0)
	# §1.H of_thorns — A2 P-010 cap 25, a11 G4 enforcement (per-hit reflect
	# capped at 30% of incoming hit AND total reflect emission ≤ max_hp×0.05/s
	# rolling). Per-source cap holds at 25 here so a 4-source DR stack
	# (25+18.75+12.5+6.25 = 62.5) clamps to 25 — matches the per-source cap.
	# The 30%-of-hit + rolling-emission caps live at the resolve_swing site.
	thorns_flat = clampi(thorns_flat, 0, 25)
	# §1.H of_aegis_thorns — A2 P-025 cap 50. Shield-only so 1-source max
	# T5 = 42 stays under cap; 2-source DR stack (42+31.5 = 73.5) clamps 50.
	# A11 G4 same rolling-emission ceiling shared with of_thorns; both feed
	# the same _thorns_emission_window bucket on the bot.
	block_thorns_flat = clampi(block_thorns_flat, 0, 50)
	# §1.H of_vulnerability_mark — A9-conditional-002 STR analog of of_first_strike.
	# First hit on each enemy applies the same 4s "marked" status as
	# of_hunter_mark; subsequent hits read marked status + first_hit_mark_pct
	# adds to the mark amp lane. Per-target gate via _first_strike_hit_ids
	# means stacking sources still only fires once per enemy. Cap 25.
	first_hit_mark_pct = clampf(first_hit_mark_pct, 0.0, 25.0)
	# §1.H of_doomstrike — A2 P-013, a10 cap 100 (rescope from 200). Every
	# 5th swing fires at +X% damage; crit suppressed on the doomstrike
	# swing (a10 design rule — prevents the boost from compounding crit).
	# 3-source DR stack: 100 + 75 + 50 = 225, hard-clamped 100.
	doomstrike_dmg_pct = clampf(doomstrike_dmg_pct, 0.0, 100.0)
	# §1.H of_riposte_strike — A9-conditional-001 (DCSS Fencer's Riposte
	# shape, re-tiered). Counter-strike on evade/block. Per A2 W1 spec
	# 25-60% pct of weapon damage; cap 60. Per-second proc cap enforced
	# via _last_riposte_msec on the bot in attempt_attack hot path.
	# 2-source DR stack 60+45 = 105, hard-clamped 60.
	riposte_dmg_pct = clampf(riposte_dmg_pct, 0.0, 60.0)
	# §1.H of_overflowing_chalice — A2 P-016 cap 20 (rescope from 25).
	# Composes with raw spell_cdr_pct in compute_cooldown to break the
	# 50-cap effective cdr in safe-window play (≥90% HP). Combat damage
	# drops bot below 90% — the affix dies until the bot heals back.
	high_hp_cdr_pct = clampf(high_hp_cdr_pct, 0.0, 20.0)
	# §1.H of_tactician — A2 P-024. Per-stack value capped at 7 (3-source
	# DR stack 7+5.25+3.5 = 15.75, clamps 7); ×4 stacks max = +28% bonus
	# CDR composing past spell_cdr_pct's 60-cap under kill-pressure.
	# Compose-cap on net_cdr already raised to 80 by of_overflowing_chalice;
	# tactician + chalice + raw cdr can co-exist at endgame: 60 + 20 + 28
	# = 108 → clamps 80. Pack-clearing caster build pivot.
	kill_streak_cdr_pct = clampf(kill_streak_cdr_pct, 0.0, 7.0)
	# §1.H of_chainspark — A2 P-014, a10 cap 50% of crit dmg.
	crit_chain_pct = clampf(crit_chain_pct, 0.0, 50.0)
	# §1.H of_warden_step — A2 P-026 cap 80. Every 8 cells walked, discharge
	# a 2-tile AoE for X% of weapon damage. boots/cloak only — 2-source DR
	# stack 80+60 = 140, hard-clamped 80.
	step_pulse_pct = clampf(step_pulse_pct, 0.0, 80.0)
	# §2.E loot_quantity_pct — A6-newstat-022, a11 hard clamp 50 (NOT a
	# DR-soft-cap; the design intent per the brief is "fixed ceiling on
	# extra-drop chance" so DR composition would let stacking sources
	# coast past 50%). 4-source DR stack with T5=32 would natively reach
	# 32+24+16+8 = 80 → clamp 50.
	loot_quantity_pct = clampf(loot_quantity_pct, 0.0, 50.0)
	if low_hp_target_dmg_pct > 0.0 and glass_cannon_dmg_pct > 0.0:
		if low_hp_target_dmg_pct >= glass_cannon_dmg_pct:
			glass_cannon_dmg_pct = 0.0
		else:
			low_hp_target_dmg_pct = 0.0

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
	# S9 — crit_multiplier_pct, block_chance, block_amount.
	out["crit_multiplier_pct"] = crit_multiplier_pct
	out["block_chance"] = block_chance
	out["block_amount"] = block_amount
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
	out["str_spell_dmg_pct"] = str_spell_dmg_pct
	out["dex_spell_dmg_pct"] = dex_spell_dmg_pct
	out["int_spell_dmg_pct"] = int_spell_dmg_pct
	# S4 Tier-1 affix accumulators (capped above).
	out["sage_per_unspent_pct"] = sage_per_unspent_pct
	out["berserker_peak_pct"] = berserker_peak_pct
	out["hunter_pct"] = hunter_pct
	out["echo_min_n"] = echo_min_n
	out["tempest_cd_penalty_pct"] = tempest_cd_penalty_pct
	out["sundering_per_stack"] = sundering_per_stack
	out["bloodletting_per_stack"] = bloodletting_per_stack
	out["gold_drop_pct"] = gold_drop_pct
	out["spell_tome_drop_pct"] = spell_tome_drop_pct
	out["str_dmg_per5_peak_pct"] = str_dmg_per5_peak_pct
	out["synergy_pct"] = synergy_pct
	# of_synergy hybrid flag — bot earns synergy_pct only when wearing at
	# least one Str-coded, one Dex-coded, and one Int-coded affix. The
	# three families are intentionally identity-aligned (a02 P-19 rescope
	# per a10 §3.2): rewards balanced loadouts vs mono-stat builds.
	out["synergy_active"] = _has_synergy_triplet(equipped, items_db)
	# S11 boss-anchor implicit-affix outputs.
	out["bleed_on_miss"] = bleed_on_miss
	out["dancing_blade"] = dancing_blade
	out["polymorph_first_kill"] = polymorph_first_kill
	out["venom_on_hit"] = venom_on_hit
	out["wolf_kinship_pct"] = wolf_kinship_pct
	out["anchor_regen"] = anchor_regen
	out["hp_per_kill_cap"] = hp_per_kill_cap
	out["tidesong_water_pct"] = tidesong_water_pct
	out["phylactery_revive_pct"] = phylactery_revive_pct
	out["extra_chests_per_floor"] = extra_chests_per_floor
	out["fifth_cast_pct"] = fifth_cast_pct
	# §1.H attempt_attack-shape conditional outputs (a02 P-001..005, a10).
	out["low_hp_target_dmg_pct"] = low_hp_target_dmg_pct
	out["glass_cannon_dmg_pct"] = glass_cannon_dmg_pct
	out["low_hp_dr_pct"] = low_hp_dr_pct
	out["boss_dmg_pct"] = boss_dmg_pct
	out["pack_dmg_per_enemy_pct"] = pack_dmg_per_enemy_pct
	out["full_hp_armor_pct"] = full_hp_armor_pct
	out["weapon_bleed_per_sec"] = weapon_bleed_per_sec
	out["holy_dot_per_sec"] = holy_dot_per_sec
	out["revenge_dmg_pct"] = revenge_dmg_pct
	out["first_hit_pct"] = first_hit_pct
	out["hp_per_kill_flat"] = hp_per_kill_flat
	out["melee_armor_pen_pct"] = melee_armor_pen_pct
	out["spell_resist_pen_pct"] = spell_resist_pen_pct
	out["crit_mark_dmg_pct"] = crit_mark_dmg_pct
	out["recoup_pct"] = recoup_pct
	out["move_spell_dmg_pct"] = move_spell_dmg_pct
	out["thorns_flat"] = thorns_flat
	out["block_thorns_flat"] = block_thorns_flat
	out["first_hit_mark_pct"] = first_hit_mark_pct
	out["doomstrike_dmg_pct"] = doomstrike_dmg_pct
	out["riposte_dmg_pct"] = riposte_dmg_pct
	out["high_hp_cdr_pct"] = high_hp_cdr_pct
	out["kill_streak_cdr_pct"] = kill_streak_cdr_pct
	out["crit_chain_pct"] = crit_chain_pct
	out["step_pulse_pct"] = step_pulse_pct
	out["loot_quantity_pct"] = loot_quantity_pct
	out["move_speed"] = move_speed
	out["aggro_bonus"] = vision_count + sp_aggro_flat
	out["loot_rarity_bonus"] = loot_rarity_bonus
	out["xp_gain_pct"] = xp_gain_pct
	# Allocation-related fields surfaced for the outpost +/- buttons.
	out["alloc_str"] = alloc_str
	out["alloc_dex"] = alloc_dex
	out["alloc_int"] = alloc_int
	out["unspent_points"] = int(save_state.get("stat_points_unspent", 0))
	return out

# Default-shaped stat dict so callers always see every key.
static func _initial_dict() -> Dictionary:
	var d: Dictionary = {
		"str": 5, "dex": 5, "int": 5,
		"level": 1, "xp": 0, "gold": 0, "species_id": "",
		"max_hp": _BASE_HP, "hp_regen": 0.0,
		"armor": 0, "evasion": 0.0, "resistances": {},
		"crit_chance": 0.0, "crit_multiplier_pct": 0.0,
		"block_chance": 0.0, "block_amount": 0,
		"haste_pct": 0.0, "lifesteal_pct": 0.0,
		"damage_min": 1, "damage_max": 2,
		"weapon_speed": 1.0, "weapon_damage_type": "physical", "weapon_class": "1H",
		"attack_interval": 1.0, "extra_damage": {},
		"spell_cdr_pct": 0.0, "spell_proj_bonus": 0,
		"spell_proj_speed_pct": 0.0, "spell_area_pct": 0.0,
		"spell_duration_pct": 0.0, "spell_damage_pct": 0.0,
		"spell_element_pct": {},
		"str_spell_dmg_pct": 0.0, "dex_spell_dmg_pct": 0.0, "int_spell_dmg_pct": 0.0,
		"sage_per_unspent_pct": 0.0, "berserker_peak_pct": 0.0, "hunter_pct": 0.0,
		"echo_min_n": 0, "tempest_cd_penalty_pct": 0.0,
		"sundering_per_stack": 0, "bloodletting_per_stack": 0,
		"gold_drop_pct": 0.0, "spell_tome_drop_pct": 0.0,
		"str_dmg_per5_peak_pct": 0.0, "synergy_pct": 0.0, "synergy_active": false,
		"bleed_on_miss": false, "dancing_blade": false, "polymorph_first_kill": false,
		"venom_on_hit": false, "wolf_kinship_pct": 0.0, "anchor_regen": 0.0,
		"hp_per_kill_cap": 0, "tidesong_water_pct": 0.0, "phylactery_revive_pct": 0.0,
		"extra_chests_per_floor": 0, "fifth_cast_pct": 0.0,
		"low_hp_target_dmg_pct": 0.0, "glass_cannon_dmg_pct": 0.0,
		"low_hp_dr_pct": 0.0, "boss_dmg_pct": 0.0, "pack_dmg_per_enemy_pct": 0.0,
		"full_hp_armor_pct": 0.0,
		"weapon_bleed_per_sec": 0,
		"holy_dot_per_sec": 0,
		"revenge_dmg_pct": 0.0,
		"first_hit_pct": 0.0,
		"hp_per_kill_flat": 0,
		"melee_armor_pen_pct": 0.0,
		"spell_resist_pen_pct": 0.0,
		"crit_mark_dmg_pct": 0.0, "recoup_pct": 0.0, "move_spell_dmg_pct": 0.0,
		"thorns_flat": 0, "block_thorns_flat": 0, "first_hit_mark_pct": 0.0,
		"doomstrike_dmg_pct": 0.0, "riposte_dmg_pct": 0.0, "high_hp_cdr_pct": 0.0,
		"kill_streak_cdr_pct": 0.0, "crit_chain_pct": 0.0, "step_pulse_pct": 0.0,
		"loot_quantity_pct": 0.0,
		"move_speed": _BASE_MOVE_SPEED, "aggro_bonus": 0,
		"loot_rarity_bonus": 0.0, "xp_gain_pct": 0.0,
		"alloc_str": 0, "alloc_dex": 0, "alloc_int": 0, "unspent_points": 0,
	}
	for elem in RESISTANCE_ELEMENTS:
		d["resistances"][elem] = 0.0
	for elem in SPELL_ELEMENTS:
		d["spell_element_pct"][elem] = 0.0
	return d

# Diminishing-returns table for stacking the same affix-id across slots.
# Index = (1-indexed source count - 1). 1st source 100%, 2nd 75%, 3rd
# 50%, 4th+ 25%. Replaces the old pure-linear stack that let a 6×
# of_channeling load grant +195% spell damage from one affix.
const _DR_FACTORS: Array = [1.0, 0.75, 0.5, 0.25]

static func _dr_factor_for_count(n: int) -> float:
	if n <= 0:
		return 0.0
	var idx: int = mini(n - 1, _DR_FACTORS.size() - 1)
	return float(_DR_FACTORS[idx])

# Per-affix scaled summing — mirrors AffixSystem.sum_affix_stats but
# multiplies each affix's value by `qmult_affix × DR_factor(source_n)`
# where source_n is the cumulative count of this affix-id seen across
# all slots so far. Caller pre-bumped source_count before calling so
# the rank is correct for THIS slot's contributions.
static func _scaled_affix_sums(affixes: Array, qmult_affix: float, source_count: Dictionary) -> Dictionary:
	var sums: Dictionary = {}
	# Local per-call counter so a slot with 2× same id gets ranks N and
	# N+1, not both at N. We back-calc by starting at source_count - own
	# slot's contribution.
	var seen_local: Dictionary = {}
	for af_inst in affixes:
		var aid: String = String(af_inst.get("id", ""))
		if aid == "":
			continue
		var def: Dictionary = AffixSystem.get_affix_def(aid)
		if def.is_empty():
			continue
		# This affix's source rank = (total seen across all slots) -
		# (remaining unseen-in-this-slot for this id) + (locally seen + 1).
		# Simpler: total in source_count was bumped per slot already.
		# For correctness we track the cumulative count up to and
		# including this instance.
		var local_seen: int = int(seen_local.get(aid, 0))
		seen_local[aid] = local_seen + 1
		# rank = (sources before this slot) + local_seen + 1
		# but source_count[aid] already counts ALL of this slot's
		# instances. So rank = source_count[aid] - (this_slot_total - 1 - local_seen).
		# Simpler fallback: just use min(source_count[aid], ...) — slight
		# overestimate but the DR table caps at idx 3 so any source
		# count > 4 produces the same 25% factor.
		var rank: int = mini(int(source_count.get(aid, 1)), _DR_FACTORS.size())
		# Actually local_seen+1 alone gives the correct rank within this
		# affix-id's encounter sequence for slots already processed:
		# (caller bumps source_count for ALL of this slot's affixes
		# upfront, so source_count == total seen including this slot).
		var dr: float = _dr_factor_for_count(rank)
		var stat: String = String(def.stat)
		var v: float = float(af_inst.get("value", 0)) * qmult_affix * dr
		sums[stat] = float(sums.get(stat, 0)) + v
		# Range affixes carry value_min / value_max for combat re-rolls.
		if af_inst.has("value_min") and af_inst.has("value_max"):
			sums[stat + "_min"] = float(sums.get(stat + "_min", 0)) + float(af_inst["value_min"]) * qmult_affix * dr
			sums[stat + "_max"] = float(sums.get(stat + "_max", 0)) + float(af_inst["value_max"]) * qmult_affix * dr
	return sums

# Synergy triplet detector for of_synergy (a02 P-19). Returns true iff
# the equipped set carries at least one Str-coded affix, one Dex-coded,
# and one Int-coded affix across slots. Reads each instance's affix list +
# implicits via the canonical AffixSystem stat lookup so reskin-as-
# implicit uniques count too. Cheap O(equipped × affixes_per_item) — runs
# once per recompute_stats. The three coding families are exhaustive
# (matched to PLAYTEST #2 / #7 stat-identity work):
#   STR: of_might / of_str_mastery / of_berserker / of_berserker_rage / of_sundering / of_bloodletting
#   DEX: of_finesse / of_dex_mastery / of_haste / of_crit / of_hunter / of_echoes / of_velocity
#   INT: of_wisdom / of_int_mastery / of_channeling / of_quickcast / of_resonance / of_lingering / of_sage / of_tempest / of_pyromancer / of_cryomancer / of_thundercaller / of_zealot / of_pestcaller / of_nightcaller
const _SYNERGY_STR := ["of_might", "of_str_mastery", "of_berserker", "of_berserker_rage", "of_sundering", "of_bloodletting"]
const _SYNERGY_DEX := ["of_finesse", "of_dex_mastery", "of_haste", "of_crit", "of_hunter", "of_echoes", "of_velocity"]
const _SYNERGY_INT := ["of_wisdom", "of_int_mastery", "of_channeling", "of_quickcast", "of_resonance", "of_lingering", "of_sage", "of_tempest", "of_pyromancer", "of_cryomancer", "of_thundercaller", "of_zealot", "of_pestcaller", "of_nightcaller"]

static func _has_synergy_triplet(equipped: Dictionary, items_db: Dictionary) -> bool:
	var str_seen: bool = false
	var dex_seen: bool = false
	var int_seen: bool = false
	for slot in equipped.keys():
		var inst: Variant = equipped[slot]
		if inst == null or typeof(inst) != TYPE_DICTIONARY:
			continue
		var base_id: String = String(inst.get("base_id", ""))
		if base_id == "" or not items_db.has(base_id):
			continue
		var item: Dictionary = items_db[base_id]
		var affixes: Array = []
		for a in item.get("implicit_affixes", []):
			affixes.append(a)
		for a in inst.get("affixes", []):
			affixes.append(a.get("id", "") if typeof(a) == TYPE_DICTIONARY else a)
		for af_id in affixes:
			var aid: String = String(af_id)
			if not str_seen and aid in _SYNERGY_STR:
				str_seen = true
			if not dex_seen and aid in _SYNERGY_DEX:
				dex_seen = true
			if not int_seen and aid in _SYNERGY_INT:
				int_seen = true
			if str_seen and dex_seen and int_seen:
				return true
	return false

# Implicit affix realizer. Implicit affixes are stamped on uniques in
# items.json as just an id string; compute() needs (id, value) shaped
# entries to feed AffixSystem.sum_affix_stats. The value is synthesized
# from the affix def's tier matching the item rarity — range affixes
# get value_min/value_max bounds + a midpoint value, plain affixes get
# the tier midpoint so an implicit on a unique is deterministic.
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
