extends GutTest

# Golden-master tests for StatCalc.compute. Locks the post-2026-06-08
# unification residue cluster (blessing kinds, species atk_pct/def_pct/
# aggro_flat, lifesteal_pct clamp, spell_element_pct, unspent_points
# routing) so future touches catch silent regressions.
#
# Run via:
#   /Applications/Godot.app/Contents/MacOS/Godot --path project --headless \
#       -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit
#
# Surfaced through tools/check_before_commit.sh.

var items_db: Dictionary

func before_all() -> void:
	ItemsDb.preload_all()
	items_db = ItemsDb.items()

func test_items_db_loaded() -> void:
	assert_false(items_db.is_empty(), "ItemsDb.items() must not be empty")

func test_bare_human_stats() -> void:
	var save := _bare_save("human")
	var d: Dictionary = StatCalc.compute({}, items_db, save, "human", 1, 0, 0, [])
	# Human +1/+1/+1 on top of 5/5/5 base = 6/6/6.
	assert_eq(int(d.str), 6, "bare human str")
	assert_eq(int(d.dex), 6, "bare human dex")
	assert_eq(int(d.int), 6, "bare human int")
	# Bare-handed weapon = 1-2 phys.
	assert_eq(int(d.damage_min), 1, "bare human damage_min")
	assert_eq(int(d.damage_max), 2, "bare human damage_max")
	# str_excess=1 → max_hp = 80 × 1.015 = 81.2 → 81.
	assert_eq(int(d.max_hp), 81, "bare human max_hp")
	assert_eq(int(d.aggro_bonus), 0, "bare human aggro_bonus")

func test_minotaur_atk_pct_and_aggro() -> void:
	var save := _bare_save("minotaur")
	var d: Dictionary = StatCalc.compute({}, items_db, save, "minotaur", 10, 0, 0, [])
	# Minotaur +5 str_flat + 9 lvl_bonus + 5 base = 19 str.
	assert_eq(int(d.str), 19, "minotaur str")
	# Minotaur aggro_flat=1 surfaces as +1 aggro_bonus.
	assert_eq(int(d.aggro_bonus), 1, "minotaur aggro_bonus")

func test_naga_haste_pct_and_regen() -> void:
	# Naga -15 haste; bare-bot dex 3 (base 5 + species -2 + lvl 0).
	# Dex_excess = -2 → haste += -2 → -17 → clamps to 0. Regen 0.5.
	var save := _bare_save("naga")
	var d: Dictionary = StatCalc.compute({}, items_db, save, "naga", 1, 0, 0, [])
	assert_eq(int(d.dex), 3, "naga dex")
	assert_eq(int(round(float(d.haste_pct))), 0, "naga haste_pct (clamped)")
	assert_almost_eq(float(d.hp_regen), 0.5, 0.001, "naga hp_regen")

func test_octopode_loot_pct() -> void:
	var save := _bare_save("octopode")
	var d: Dictionary = StatCalc.compute({}, items_db, save, "octopode", 1, 0, 0, [])
	assert_almost_eq(float(d.loot_rarity_bonus), 20.0, 0.001, "octopode loot_rarity_bonus")
	assert_eq(int(d.aggro_bonus), 0, "octopode aggro_bonus")

func test_blessing_atk_pct_and_atk_flat_compose() -> void:
	# Trog (atk_pct=20) + Yred (atk_flat=25) on bare-hands Human.
	# Order: flat first (1+25=26, 2+25=27), then pct (×1.20) → 31, 32.
	var save := _bare_save("human")
	var blessings := [
		{"kind": "atk_pct",  "value": 20.0, "god": "trog"},
		{"kind": "atk_flat", "value": 25.0, "god": "yredelemnul"},
	]
	var d: Dictionary = StatCalc.compute({}, items_db, save, "human", 1, 0, 0, blessings)
	assert_eq(int(d.damage_min), 31, "trog+yred damage_min")
	assert_eq(int(d.damage_max), 32, "trog+yred damage_max")

func test_blessing_def_flat() -> void:
	# Cheibriados +30 DEF (def_flat=30): armor jumps 0 → 30.
	var save := _bare_save("human")
	var blessings := [{"kind": "def_flat", "value": 30.0, "god": "cheibriados"}]
	var d: Dictionary = StatCalc.compute({}, items_db, save, "human", 1, 0, 0, blessings)
	assert_eq(int(d.armor), 30, "cheibriados armor")

func test_blessing_hp_pct_stacks_multiplicatively_with_species() -> void:
	# Naga (+20% hp species) + Fedhas (+40% hp blessing) at lvl 1.
	# 1.20 × 1.40 = 1.68×, then × str_mult (1.045 from 8 str).
	# 80 × 1.68 × 1.045 = 140.45 → 140.
	var save := _bare_save("naga")
	var blessings := [{"kind": "hp_pct", "value": 40.0, "god": "fedhas"}]
	var d: Dictionary = StatCalc.compute({}, items_db, save, "naga", 1, 0, 0, blessings)
	assert_eq(int(d.max_hp), 140, "naga + fedhas max_hp")

func test_blessing_hp_regen() -> void:
	var save := _bare_save("human")
	var blessings := [{"kind": "hp_regen", "value": 3.0, "god": "elyvilon"}]
	var d: Dictionary = StatCalc.compute({}, items_db, save, "human", 1, 0, 0, blessings)
	assert_almost_eq(float(d.hp_regen), 3.0, 0.001, "elyvilon hp_regen")

func test_lifesteal_pct_clamps_at_15() -> void:
	# of_lifesteal 20% rolls higher than the 15 cap. Confirm clamp holds.
	var fake_db: Dictionary = items_db.duplicate(true)
	fake_db["__test_weapon"] = {
		"id": "__test_weapon", "slot": "weapon", "rarity": "legendary",
		"damage_min": 5, "damage_max": 10, "speed": 1.0,
		"damage_type": "physical", "weapon_class": "1H",
		"flavor_tags": [], "implicit_affixes": [],
	}
	var inst := {
		"base_id": "__test_weapon", "rarity": "legendary",
		"affixes": [{"id": "of_lifesteal", "value": 20}],
	}
	var save := _bare_save("human")
	var d: Dictionary = StatCalc.compute({"weapon": inst}, fake_db, save, "human", 1, 0, 0, [])
	assert_almost_eq(float(d.lifesteal_pct), 15.0, 0.001, "lifesteal_pct clamp")

func test_unspent_points_routes_from_stat_points_unspent() -> void:
	# Audit-flagged typo (cd69e55). Lock that StatCalc reads
	# stat_points_unspent, not legacy unspent_points key.
	var save := _bare_save("human")
	save["stat_points_unspent"] = 7
	var d: Dictionary = StatCalc.compute({}, items_db, save, "human", 5, 0, 0, [])
	assert_eq(int(d.unspent_points), 7, "stat_points_unspent → unspent_points")

func test_element_affix_populates_spell_element_pct() -> void:
	# of_pyromancer rolls fire_dmg_pct; StatCalc maps onto
	# spell_element_pct["fire"]. spell_data.gd:181 reads this.
	var fake_db: Dictionary = items_db.duplicate(true)
	fake_db["__test_amulet"] = {
		"id": "__test_amulet", "slot": "amulet", "rarity": "epic",
		"flavor_tags": [], "implicit_affixes": [],
	}
	var inst := {
		"base_id": "__test_amulet", "rarity": "epic",
		"affixes": [{"id": "of_pyromancer", "value": 24}],
	}
	var save := _bare_save("human")
	var d: Dictionary = StatCalc.compute({"amulet": inst}, fake_db, save, "human", 1, 0, 0, [])
	var elem: Dictionary = d.get("spell_element_pct", {})
	assert_almost_eq(float(elem.get("fire", 0)), 24.0, 0.001, "of_pyromancer → spell_element_pct.fire")

func test_class_mastery_affixes_route_to_class_pct_keys() -> void:
	# S1 (2026-06-09): of_str_mastery / of_dex_mastery / of_int_mastery
	# write to str_spell_dmg_pct / dex_spell_dmg_pct / int_spell_dmg_pct
	# accumulators. Pre-fix StatCalc never read those keys; post-fix
	# spell_data.compute_damage multiplies by the matching class lane.
	var fake_db: Dictionary = items_db.duplicate(true)
	fake_db["__test_helm"] = {
		"id": "__test_helm", "slot": "helm", "rarity": "epic",
		"flavor_tags": [], "implicit_affixes": [],
	}
	var inst := {
		"base_id": "__test_helm", "rarity": "epic",
		"affixes": [
			{"id": "of_str_mastery", "value": 20},
			{"id": "of_dex_mastery", "value": 15},
			{"id": "of_int_mastery", "value": 30},
		],
	}
	var save := _bare_save("human")
	var d: Dictionary = StatCalc.compute({"helm": inst}, fake_db, save, "human", 1, 0, 0, [])
	assert_almost_eq(float(d.get("str_spell_dmg_pct", 0)), 20.0, 0.001,
		"of_str_mastery → str_spell_dmg_pct accumulator")
	assert_almost_eq(float(d.get("dex_spell_dmg_pct", 0)), 15.0, 0.001,
		"of_dex_mastery → dex_spell_dmg_pct accumulator")
	assert_almost_eq(float(d.get("int_spell_dmg_pct", 0)), 30.0, 0.001,
		"of_int_mastery → int_spell_dmg_pct accumulator")

func test_meta_qmult_caps_at_1_30() -> void:
	# S2 cap rules (a10 §5.3): meta_mult × qmult product is clamped to
	# ×1.30 in stat_calc.gd:128 so endgame Primal+Sublime weapons can't
	# multiply baseline by ×1.80 (Primal 1.50 × Sublime 1.20 = 1.80).
	# Authoring a fake weapon at base 100/100 with meta_rarity=primal
	# and quality=sublime; expected post-cap damage_min/max = 130, not
	# 180.
	var fake_db: Dictionary = items_db.duplicate(true)
	fake_db["__test_weapon"] = {
		"id": "__test_weapon", "slot": "weapon", "rarity": "legendary",
		"damage_min": 100, "damage_max": 100, "speed": 1.0,
		"damage_type": "physical", "weapon_class": "1H",
		"flavor_tags": [], "implicit_affixes": [],
	}
	var inst := {
		"base_id": "__test_weapon", "rarity": "legendary",
		"meta_rarity": "primal",  # ×1.50
		"quality": "sublime",     # ×1.20
		"affixes": [],
	}
	var save := _bare_save("human")
	var d: Dictionary = StatCalc.compute({"weapon": inst}, fake_db, save, "human", 1, 0, 0, [])
	# Pre-cap: 100 × 1.80 = 180. Post-cap: 100 × 1.30 = 130.
	# Human's atk_pct/def_pct are 0; bare-bot upgrades 0. Damage_min
	# is computed as round(100 × min(1.50×1.20, 1.30)) = 130.
	assert_eq(int(d.damage_min), 130,
		"meta×qmult clamp: Primal(×1.50) × Sublime(×1.20) caps at ×1.30")
	assert_eq(int(d.damage_max), 130,
		"meta×qmult clamp: damage_max also clamped")

func test_class_mastery_caps_at_100_pct() -> void:
	# Soft cap per a06 §3.2 — each class lane caps at 100%.
	# Use a single oversized roll (value=150) to verify the clamp fires
	# without depending on the per-affix-DR composition rules.
	var fake_db: Dictionary = items_db.duplicate(true)
	fake_db["__test_helm"] = {
		"id": "__test_helm", "slot": "helm", "rarity": "epic",
		"flavor_tags": [], "implicit_affixes": [],
	}
	var inst := {
		"base_id": "__test_helm", "rarity": "epic",
		"affixes": [{"id": "of_int_mastery", "value": 150}],
	}
	var save := _bare_save("human")
	var d: Dictionary = StatCalc.compute({"helm": inst}, fake_db, save, "human", 1, 0, 0, [])
	assert_almost_eq(float(d.get("int_spell_dmg_pct", 0)), 100.0, 0.001,
		"int_spell_dmg_pct soft-caps at 100 — raw=150 should clamp")

# ---------------------------------------------------------------------
# S4 Tier-1 affix accumulators (a02 P-8/9/10/11/12/13/15/16/19/27/28
# rescoped per a10 §3.2). Confirm each new affix routes to its
# dedicated accumulator + soft cap fires.
# ---------------------------------------------------------------------

func test_s4_of_sage_routes_to_sage_per_unspent_pct() -> void:
	var fake_db: Dictionary = items_db.duplicate(true)
	fake_db["__test_amulet"] = {
		"id": "__test_amulet", "slot": "amulet", "rarity": "legendary",
		"flavor_tags": [], "implicit_affixes": [],
	}
	var inst := {
		"base_id": "__test_amulet", "rarity": "legendary",
		"affixes": [{"id": "of_sage", "value": 24}],
	}
	var save := _bare_save("human")
	var d: Dictionary = StatCalc.compute({"amulet": inst}, fake_db, save, "human", 1, 0, 0, [])
	assert_almost_eq(float(d.get("sage_per_unspent_pct", 0)), 24.0, 0.001,
		"of_sage value flows into sage_per_unspent_pct accumulator")

func test_s4_caps_enforced_per_lane() -> void:
	# Each S4 cap (a10 §3.2 rescopes) gets its own clamp in StatCalc.
	# Stuff each lane with an oversized single roll; verify the clamp fires.
	var fake_db: Dictionary = items_db.duplicate(true)
	fake_db["__test_amulet"] = {
		"id": "__test_amulet", "slot": "amulet", "rarity": "legendary",
		"flavor_tags": [], "implicit_affixes": [],
	}
	# of_sage cap = 24. Use raw=200 to force the clamp.
	var inst := {
		"base_id": "__test_amulet", "rarity": "legendary",
		"affixes": [
			{"id": "of_sage", "value": 200},
			{"id": "of_synergy", "value": 200},
			{"id": "of_hunter", "value": 200},
		],
	}
	var save := _bare_save("human")
	var d: Dictionary = StatCalc.compute({"amulet": inst}, fake_db, save, "human", 1, 0, 0, [])
	assert_almost_eq(float(d.get("sage_per_unspent_pct", 0)), 24.0, 0.001,
		"sage_per_unspent_pct soft-caps at 24")
	assert_almost_eq(float(d.get("synergy_pct", 0)), 12.0, 0.001,
		"synergy_pct soft-caps at 12")
	assert_almost_eq(float(d.get("hunter_pct", 0)), 20.0, 0.001,
		"hunter_pct soft-caps at 20")

func test_s4_of_echoes_picks_smallest_n() -> void:
	# Multi-source of_echoes: smaller N wins (more frequent echoes).
	# Two rolls (8, 5) → echo_min_n = 5.
	var fake_db: Dictionary = items_db.duplicate(true)
	fake_db["__test_weapon"] = {
		"id": "__test_weapon", "slot": "weapon", "rarity": "legendary",
		"damage_min": 5, "damage_max": 10, "speed": 1.0,
		"damage_type": "physical", "weapon_class": "1H",
		"flavor_tags": [], "implicit_affixes": [],
	}
	fake_db["__test_gloves"] = {
		"id": "__test_gloves", "slot": "gloves", "rarity": "legendary",
		"flavor_tags": [], "implicit_affixes": [],
	}
	var weapon := {
		"base_id": "__test_weapon", "rarity": "legendary",
		"affixes": [{"id": "of_echoes", "value": 8}],
	}
	var gloves := {
		"base_id": "__test_gloves", "rarity": "legendary",
		"affixes": [{"id": "of_echoes", "value": 5}],
	}
	var save := _bare_save("human")
	var d: Dictionary = StatCalc.compute({"weapon": weapon, "gloves": gloves}, fake_db, save, "human", 1, 0, 0, [])
	assert_eq(int(d.get("echo_min_n", 0)), 5,
		"of_echoes picks the smaller N across sources")

func test_s4_of_synergy_active_requires_triplet() -> void:
	# Bot must wear at least one Str-coded, one Dex-coded, AND one Int-
	# coded affix to activate synergy_pct. Single-axis loadouts do not.
	var fake_db: Dictionary = items_db.duplicate(true)
	fake_db["__test_amulet"] = {
		"id": "__test_amulet", "slot": "amulet", "rarity": "legendary",
		"flavor_tags": [], "implicit_affixes": [],
	}
	# Only str-coded affix: synergy NOT active.
	var inst_str := {
		"base_id": "__test_amulet", "rarity": "legendary",
		"affixes": [{"id": "of_might", "value": 12}],
	}
	var save := _bare_save("human")
	var d_str: Dictionary = StatCalc.compute({"amulet": inst_str}, fake_db, save, "human", 1, 0, 0, [])
	assert_false(bool(d_str.get("synergy_active", true)),
		"of_might alone does NOT activate synergy_active")
	# str+dex+int: synergy ACTIVE.
	var inst_triplet := {
		"base_id": "__test_amulet", "rarity": "legendary",
		"affixes": [
			{"id": "of_might", "value": 12},
			{"id": "of_finesse", "value": 12},
			{"id": "of_wisdom", "value": 12},
		],
	}
	var d_t: Dictionary = StatCalc.compute({"amulet": inst_triplet}, fake_db, save, "human", 1, 0, 0, [])
	assert_true(bool(d_t.get("synergy_active", false)),
		"of_might + of_finesse + of_wisdom triplet activates synergy_active")

# ---------------------------------------------------------------------
# S5 — race-anchor implicit gating (requires_innate_tag)
# ---------------------------------------------------------------------

func test_s5_requires_innate_tag_skipped_on_mismatch() -> void:
	# An item that requires a tag the species doesn't carry must skip its
	# implicit_affixes in the StatCalc rollup. Base stats still apply.
	var fake_db: Dictionary = items_db.duplicate(true)
	fake_db["__s5_amulet"] = {
		"id": "__s5_amulet", "slot": "amulet", "rarity": "legendary",
		"flavor_tags": [],
		"requires_innate_tag": "vampiric",
		"implicit_affixes": ["of_might"],
	}
	var inst := {"base_id": "__s5_amulet", "rarity": "legendary", "affixes": []}
	# Human (no innate_tags) — implicit muted, str unchanged from base.
	var d_human: Dictionary = StatCalc.compute(
		{"amulet": inst}, fake_db, _bare_save("human"), "human", 1, 0, 0, []
	)
	# Vampire — implicit fires, str gains the of_might tier-mid roll.
	var d_vamp: Dictionary = StatCalc.compute(
		{"amulet": inst}, fake_db, _bare_save("vampire"), "vampire", 1, 0, 0, []
	)
	assert_gt(int(d_vamp.str), int(d_human.str),
		"vampire (innate_tag=vampiric) sees of_might implicit; human (muted) does not")

func test_s5_requires_innate_tag_only_mutes_implicits_not_rolled() -> void:
	# Rolled affixes (inst.affixes) should still apply even when the item
	# is heritage-locked and the bot doesn't satisfy it. Only the
	# implicit_affixes lane mutes.
	var fake_db: Dictionary = items_db.duplicate(true)
	fake_db["__s5_amulet2"] = {
		"id": "__s5_amulet2", "slot": "amulet", "rarity": "legendary",
		"flavor_tags": [],
		"requires_innate_tag": "fae",
		"implicit_affixes": ["of_might"],
	}
	var inst := {
		"base_id": "__s5_amulet2", "rarity": "legendary",
		"affixes": [{"id": "of_finesse", "value": 12}],
	}
	# Human — implicit muted, but rolled of_finesse still adds to dex.
	var d: Dictionary = StatCalc.compute(
		{"amulet": inst}, fake_db, _bare_save("human"), "human", 1, 0, 0, []
	)
	# Bare human dex = 6 (5 + species 1). With of_finesse +12 → 18.
	assert_eq(int(d.dex), 18,
		"rolled affixes apply on heritage-locked items even when implicits mute")

func test_s5_humans_get_no_implicits_on_anchor() -> void:
	# Sanity-check the new ANCHORS dataset: a human equipping a vampire
	# anchor (vampire_splintered_tooth) does NOT get its implicit_affixes
	# pumped through StatCalc. The damage_min / damage_max base stats
	# still apply.
	if not items_db.has("vampire_splintered_tooth"):
		# Items.json drift — skip rather than fail (pre-S5 trees lack it).
		pending("vampire_splintered_tooth not present in items_db")
		return
	var inst := {"base_id": "vampire_splintered_tooth", "rarity": "uncommon", "affixes": []}
	var d_human: Dictionary = StatCalc.compute(
		{"weapon": inst}, items_db, _bare_save("human"), "human", 1, 0, 0, []
	)
	var d_vamp: Dictionary = StatCalc.compute(
		{"weapon": inst}, items_db, _bare_save("vampire"), "vampire", 1, 0, 0, []
	)
	# Both load the weapon's damage_min/max, so the swing range is the
	# same. But of_lifesteal is implicit on the splintered tooth — only
	# the vampire bot sees lifesteal_pct climb.
	assert_eq(int(d_human.damage_min), int(d_vamp.damage_min),
		"base damage_min identical regardless of heritage")
	assert_gt(float(d_vamp.lifesteal_pct), float(d_human.lifesteal_pct),
		"vampire gets implicit of_lifesteal; human does not")

func test_s5_species_data_has_innate_tag_lookup() -> void:
	# SpeciesData.has_innate_tag is the gate every other surface reads.
	# Verify it answers correctly on both populated and empty species.
	assert_true(SpeciesData.has_innate_tag("vampire", "vampiric"),
		"vampire carries vampiric tag")
	assert_true(SpeciesData.has_innate_tag("vampire", "undead"),
		"vampire also carries undead tag (shared with mummy)")
	assert_false(SpeciesData.has_innate_tag("human", "vampiric"),
		"human does not carry vampiric tag")
	assert_true(SpeciesData.has_innate_tag("human", "human"),
		"human carries 'human' self-tag (gates starter_human_spell per §1.F)")
	assert_false(SpeciesData.has_innate_tag("vampire", ""),
		"empty tag query returns false")
	assert_false(SpeciesData.has_innate_tag("", "vampiric"),
		"empty species query returns false")
	# Sanity-check every species got tagged.
	for sp in SpeciesData.all():
		var sid: String = String(sp.id)
		var has_any: bool = false
		for t in sp.get("innate_tags", []):
			has_any = SpeciesData.has_innate_tag(sid, String(t))
			if has_any:
				break
		assert_true(has_any, "species %s has at least one innate_tag" % sid)

# ---------------------------------------------------------------------
# S9 — spell crit (a06 §3.1, a10 ×1.25 rescope).
# ---------------------------------------------------------------------
# spell_data.compute_damage rolls crit_chance gated by bot.crit_chance.
# On crit, damage scales by (1.25 + crit_multiplier_pct/100/2). Pre-S9
# the spell branch never crit; Dex-spec on chain_lightning was a no-op
# for spell DPS.

func test_s9_spell_crit_at_zero_crit_chance_never_fires() -> void:
	# Stub bot dict; compute_damage reads crit_chance + crit_multiplier_pct
	# off the Node-shaped argument. With crit_chance=0, no crit ever fires
	# — damage stays deterministic across many rolls.
	var stub_bot: _SpellCritStubBot = _SpellCritStubBot.new()
	stub_bot.crit_chance = 0.0
	stub_bot.crit_multiplier_pct = 30.0  # huge cmp; should not matter
	var item: Dictionary = {
		"base_type": "spell_holy_beam",
		"damage_min": 100, "damage_max": 100,
		"primary_stat": "str",
	}
	# Set str_stat=5 (no excess), spell_damage_pct=0, no element bonuses.
	# Expected dmg = round(100 × 1.0 × 1.0 × 1.0 × 1.0 × 1.0) = 100.
	var saw_higher: bool = false
	for _i in 30:
		var dmg: int = SpellData.compute_damage(stub_bot, item, null)
		if dmg > 100:
			saw_higher = true
			break
	assert_false(saw_higher, "crit_chance=0 → spell never crits regardless of crit_multiplier_pct")
	stub_bot.free()

func test_s9_spell_crit_at_full_chance_applies_half_rate_multiplier() -> void:
	# crit_chance=100 forces every cast to crit. crit_multiplier_pct=30
	# → spell crit multiplier = 1.25 + 30/100/2 = 1.40. Base dmg 100 →
	# crit dmg 140. Tests ×1.25 base + half-rate cmp composition.
	var stub_bot: _SpellCritStubBot = _SpellCritStubBot.new()
	stub_bot.crit_chance = 100.0
	stub_bot.crit_multiplier_pct = 30.0
	var item: Dictionary = {
		"base_type": "spell_holy_beam",
		"damage_min": 100, "damage_max": 100,
		"primary_stat": "str",
	}
	var dmg: int = SpellData.compute_damage(stub_bot, item, null)
	assert_eq(dmg, 140,
		"crit @ 100% × cmp+30 → dmg = round(100 × (1.25 + 30/100/2)) = 140")
	stub_bot.free()

func test_s9_spell_crit_base_at_125_when_cmp_zero() -> void:
	# Base spell-crit multiplier alone is ×1.25 (vs melee ×1.5). Confirms
	# the rescope: spell_data uses 1.25, NOT the actor.gd const 1.5.
	var stub_bot: _SpellCritStubBot = _SpellCritStubBot.new()
	stub_bot.crit_chance = 100.0
	stub_bot.crit_multiplier_pct = 0.0
	var item: Dictionary = {
		"base_type": "spell_holy_beam",
		"damage_min": 100, "damage_max": 100,
		"primary_stat": "str",
	}
	var dmg: int = SpellData.compute_damage(stub_bot, item, null)
	assert_eq(dmg, 125, "spell crit base ×1.25 (rescoped from melee ×1.5)")
	stub_bot.free()

# ---------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------

# Spell-crit stub bot — minimal Node carrying the fields spell_data reads
# (str_stat, dex_stat, int_stat, spell_damage_pct, spell_element_pct,
# str/dex/int_spell_dmg_pct, ephemeral_spell_dmg_pct, crit_chance,
# crit_multiplier_pct, sage_per_unspent_pct, unspent_points,
# synergy_active, synergy_pct). Defaults to neutral values so a
# vanilla cast yields raw base damage; tests poke fields they care about.
class _SpellCritStubBot extends Node:
	var str_stat: int = 5
	var dex_stat: int = 5
	var int_stat: int = 5
	var spell_damage_pct: float = 0.0
	var spell_element_pct: Dictionary = {
		"fire": 0.0, "cold": 0.0, "thunderous": 0.0,
		"holy": 0.0, "poison": 0.0, "dark": 0.0,
	}
	var str_spell_dmg_pct: float = 0.0
	var dex_spell_dmg_pct: float = 0.0
	var int_spell_dmg_pct: float = 0.0
	var ephemeral_spell_dmg_pct: float = 0.0
	var sage_per_unspent_pct: float = 0.0
	var unspent_points: int = 0
	var synergy_active: bool = false
	var synergy_pct: float = 0.0
	var crit_chance: float = 0.0
	var crit_multiplier_pct: float = 0.0
	var spell_cdr_pct: float = 0.0
	var spell_proj_bonus: int = 0
	var tempest_cd_penalty_pct: float = 0.0

func _bare_save(species: String) -> Dictionary:
	return {
		"species": species,
		"stat_alloc_str": 0, "stat_alloc_dex": 0, "stat_alloc_int": 0,
		"stat_points_unspent": 0,
		"bot_upgrades": {},
	}
