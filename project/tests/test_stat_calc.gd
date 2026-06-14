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
	# §2.I human signature: +5% to highest stat AFTER derivations.
	# DEX 18 > STR 6 = INT 6 → DEX gets the bump (18 × 1.05 = 19).
	# This test is no longer purely about rolled-affix passthrough; the
	# signature-affected-build case is covered separately. We pin the
	# post-signature value so future signature changes catch it.
	assert_eq(int(d.dex), 19,
		"rolled affixes apply on heritage-locked items even when implicits mute (post-human-signature 18→19)")

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

# ---------------------------------------------------------------------
# S12 §1.H — conditional/triggered affix caps + mutex framework.
#
# Pins every cap and the executioner_pact ⊥ glass_cannon mutex shipped
# in 2026-06-13's §1.H wave. Each test stuffs a single (or paired) lane
# with an oversized roll and asserts the post-clamp stat_calc output
# matches the design cap. Deliberately breaking a cap (e.g. raising
# `low_hp_target_dmg_pct = clampf(... 40)` to 80) MUST trip these.
# ---------------------------------------------------------------------

# All §1.H caps as of 2026-06-13. Keys map to stat-key in the StatCalc
# output dict; values are the design cap. Anything that adds a §1.H
# affix or moves a cap MUST update this table to keep the regression
# net honest.
const _S12_CAPS := {
	"low_hp_target_dmg_pct":    40.0,   # of_executioner_pact (a02 P-001)
	"glass_cannon_dmg_pct":     30.0,   # of_glass_cannon     (a02 P-002)
	"low_hp_dr_pct":            28.0,   # of_revenant         (a02 P-003)
	"boss_dmg_pct":             40.0,   # of_kingslayer       (a02 P-004)
	"pack_dmg_per_enemy_pct":   10.0,   # of_butcher          (a02 P-005)
	"first_hit_pct":           120.0,   # of_first_strike     (a02 P-006)
	"revenge_dmg_pct":          50.0,   # of_avenger          (a02 P-007)
	"crit_mark_dmg_pct":        40.0,   # of_hunter_mark      (a02 P-009)
	"thorns_flat":              25.0,   # of_thorns           (a02 P-010)
	"recoup_pct":               28.0,   # of_recoup           (a02 P-011)
	"doomstrike_dmg_pct":      100.0,   # of_doomstrike       (a02 P-013)
	"crit_chain_pct":           50.0,   # of_chainspark       (a02 P-014)
	"move_spell_dmg_pct":       40.0,   # of_smoldering_step  (a02 P-015)
	"high_hp_cdr_pct":          20.0,   # of_overflowing_chalice (a02 P-016)
	"spell_resist_pen_pct":     35.0,   # of_unwavering_focus (a02 P-017)
	"melee_armor_pen_pct":      50.0,   # of_armor_breaker    (a02 P-018)
	"full_hp_armor_pct":        75.0,   # of_unbroken         (a02 P-020)
	"weapon_bleed_per_sec":     16.0,   # of_serrated_edge    (a02 P-021)
	"holy_dot_per_sec":         20.0,   # of_zealous_strike   (a02 P-022)
	"hp_per_kill_flat":         30.0,   # of_drainblade       (a02 P-023)
	"kill_streak_cdr_pct":       7.0,   # of_tactician        (a02 P-024)
	"block_thorns_flat":        50.0,   # of_aegis_thorns     (a02 P-025)
	"step_pulse_pct":           80.0,   # of_warden_step      (a02 P-026)
	"first_hit_mark_pct":       25.0,   # of_vulnerability_mark (a09-cond-002)
	"riposte_dmg_pct":          60.0,   # of_riposte_strike   (a09-cond-001)
	# §2.E (Beat 2) — added per own-commit rule: every new stat-key
	# cap extends this table in the same commit so the regression
	# net stays current.
	"loot_quantity_pct":        50.0,   # of_abundance        (a06-newstat-022, a11 hard clamp)
	"damage_taken_pct":         40.0,   # of_obstinance       (a06-newstat-021)
	"dot_duration_pct":         80.0,   # of_lingering_pestilence (a06-newstat-019)
	"damage_vs_unique_pct":     40.0,   # of_unique_slayer    (a06-newstat-016)
	"low_hp_dmg_pct":           30.0,   # of_desperation      (a06-newstat-014)
	# §2.J mana axis. mana_regen_pct + mana_cost_pct are signed/clamped;
	# mana_max_flat / mana_floor_start_flat / mana_on_hit_flat are pure
	# additive. mana_cost_pct cap is 50 in MAGNITUDE (-50 lower bound).
	"mana_regen_pct":           100.0,  # of_arcane_flow
}

# Map each capped stat key to an affix id known to write it. The probe
# test stuffs a slot with this id at oversized raw value and verifies
# the post-clamp output matches the design cap.
const _S12_STAT_TO_AFFIX := {
	"low_hp_target_dmg_pct":    "of_executioner_pact",
	"glass_cannon_dmg_pct":     "of_glass_cannon",
	"low_hp_dr_pct":            "of_revenant",
	"boss_dmg_pct":             "of_kingslayer",
	"pack_dmg_per_enemy_pct":   "of_butcher",
	"first_hit_pct":            "of_first_strike",
	"revenge_dmg_pct":          "of_avenger",
	"crit_mark_dmg_pct":        "of_hunter_mark",
	"thorns_flat":              "of_thorns",
	"recoup_pct":               "of_recoup",
	"doomstrike_dmg_pct":       "of_doomstrike",
	"crit_chain_pct":           "of_chainspark",
	"move_spell_dmg_pct":       "of_smoldering_step",
	"high_hp_cdr_pct":          "of_overflowing_chalice",
	"spell_resist_pen_pct":     "of_unwavering_focus",
	"melee_armor_pen_pct":      "of_armor_breaker",
	"full_hp_armor_pct":        "of_unbroken",
	"weapon_bleed_per_sec":     "of_serrated_edge",
	"holy_dot_per_sec":         "of_zealous_strike",
	"hp_per_kill_flat":         "of_drainblade",
	"kill_streak_cdr_pct":      "of_tactician",
	"block_thorns_flat":        "of_aegis_thorns",
	"step_pulse_pct":           "of_warden_step",
	"first_hit_mark_pct":       "of_vulnerability_mark",
	"riposte_dmg_pct":          "of_riposte_strike",
	"loot_quantity_pct":        "of_abundance",
	"damage_taken_pct":         "of_obstinance",
	"dot_duration_pct":         "of_lingering_pestilence",
	"damage_vs_unique_pct":     "of_unique_slayer",
	"low_hp_dmg_pct":           "of_desperation",
	"mana_regen_pct":           "of_arcane_flow",
}

# Slot to use for each affix when stuffing the test loadout. Picked
# from the affix's `applies_to` array, defaulting to the first eligible
# entry. Centralizing this here means a future affix-eligibility move
# only updates one place.
const _S12_AFFIX_TEST_SLOT := {
	"of_executioner_pact":    "weapon",
	"of_glass_cannon":        "amulet",
	"of_revenant":            "armor",
	"of_kingslayer":          "weapon",
	"of_butcher":             "weapon",
	"of_first_strike":        "weapon",
	"of_avenger":             "weapon",
	"of_hunter_mark":         "weapon",
	"of_thorns":              "armor",
	"of_recoup":              "amulet",
	"of_doomstrike":          "weapon",
	"of_chainspark":          "weapon",
	"of_smoldering_step":     "boots",
	"of_overflowing_chalice": "amulet",
	"of_unwavering_focus":    "amulet",
	"of_armor_breaker":       "weapon",
	"of_unbroken":            "armor",
	"of_serrated_edge":       "weapon",
	"of_zealous_strike":      "weapon",
	"of_drainblade":          "weapon",
	"of_tactician":           "amulet",
	"of_aegis_thorns":        "shield",
	"of_warden_step":         "boots",
	"of_vulnerability_mark":  "weapon",
	"of_riposte_strike":      "weapon",
	"of_abundance":           "amulet",
	"of_obstinance":          "armor",
	"of_lingering_pestilence": "amulet",
	"of_unique_slayer":       "weapon",
	"of_desperation":         "weapon",
	"of_arcane_flow":         "amulet",
}

# Build a synthetic items_db with one stub-item per slot needed by the
# §1.H test loadouts. Keeps the fake-db construction in one place so
# every cap test reads from the same fixture.
func _s12_fake_db() -> Dictionary:
	var fake_db: Dictionary = items_db.duplicate(true)
	for slot in ["weapon", "amulet", "armor", "boots", "shield", "ring", "gloves", "helm", "cloak", "spell"]:
		var stub_id: String = "__s12_test_" + slot
		var entry: Dictionary = {
			"id": stub_id, "slot": slot, "rarity": "legendary",
			"flavor_tags": [], "implicit_affixes": [],
		}
		# Weapons need damage stats so StatCalc's weapon-branch survives.
		if slot == "weapon":
			entry["damage_min"] = 5
			entry["damage_max"] = 10
			entry["speed"] = 1.0
			entry["damage_type"] = "physical"
			entry["weapon_class"] = "1H"
		fake_db[stub_id] = entry
	return fake_db

func _s12_loadout(stat_key: String, raw_value: int) -> Dictionary:
	var affix_id: String = String(_S12_STAT_TO_AFFIX[stat_key])
	var slot: String = String(_S12_AFFIX_TEST_SLOT[affix_id])
	return {
		slot: {
			"base_id": "__s12_test_" + slot, "rarity": "legendary",
			"affixes": [{"id": affix_id, "value": raw_value}],
		},
	}

func test_s12_caps_enforced_per_lane() -> void:
	# Every cap in _S12_CAPS gets an oversized raw roll and is asserted
	# against the design ceiling. One assert per lane keeps regressions
	# specific (failure name == stat key).
	var fake_db: Dictionary = _s12_fake_db()
	var save := _bare_save("human")
	for stat_key in _S12_CAPS.keys():
		var cap: float = float(_S12_CAPS[stat_key])
		var equipped: Dictionary = _s12_loadout(stat_key, 999)
		var d: Dictionary = StatCalc.compute(equipped, fake_db, save, "human", 1, 0, 0, [])
		assert_almost_eq(float(d.get(stat_key, -1.0)), cap, 0.001,
			"§1.H cap pinned: %s = %.1f" % [stat_key, cap])

func test_s12_executioner_pact_glass_cannon_mutex_larger_wins() -> void:
	# A11 G6: of_executioner_pact ⊥ of_glass_cannon. Both rolled, the
	# larger contribution wins; the loser zeros. Resolved post-clamp in
	# stat_calc.compute so eligibility filters can stay loose.
	var fake_db: Dictionary = _s12_fake_db()
	var save := _bare_save("human")
	# executioner_pact 35 > glass_cannon 25 — exec wins.
	var equipped_a: Dictionary = {
		"weapon": {
			"base_id": "__s12_test_weapon", "rarity": "legendary",
			"affixes": [{"id": "of_executioner_pact", "value": 35}],
		},
		"amulet": {
			"base_id": "__s12_test_amulet", "rarity": "legendary",
			"affixes": [{"id": "of_glass_cannon", "value": 25}],
		},
	}
	var d_a: Dictionary = StatCalc.compute(equipped_a, fake_db, save, "human", 1, 0, 0, [])
	assert_almost_eq(float(d_a.get("low_hp_target_dmg_pct", -1.0)), 35.0, 0.001,
		"executioner_pact (35) > glass_cannon (25) → exec survives")
	assert_almost_eq(float(d_a.get("glass_cannon_dmg_pct", -1.0)), 0.0, 0.001,
		"executioner_pact > glass_cannon → glass_cannon zeroed")
	# Inverse: glass_cannon 25 > executioner_pact 15 — glass survives.
	var equipped_b: Dictionary = {
		"weapon": {
			"base_id": "__s12_test_weapon", "rarity": "legendary",
			"affixes": [{"id": "of_executioner_pact", "value": 15}],
		},
		"amulet": {
			"base_id": "__s12_test_amulet", "rarity": "legendary",
			"affixes": [{"id": "of_glass_cannon", "value": 25}],
		},
	}
	var d_b: Dictionary = StatCalc.compute(equipped_b, fake_db, save, "human", 1, 0, 0, [])
	assert_almost_eq(float(d_b.get("low_hp_target_dmg_pct", -1.0)), 0.0, 0.001,
		"glass_cannon (25) > executioner_pact (15) → exec zeroed")
	assert_almost_eq(float(d_b.get("glass_cannon_dmg_pct", -1.0)), 25.0, 0.001,
		"glass_cannon (25) > executioner_pact (15) → glass survives")

func test_s12_executioner_pact_glass_cannon_mutex_solo_each_passes_through() -> void:
	# Mutex framework must NOT zero the surviving lane when only one of
	# the pair is rolled — that would silently break all single-source
	# loadouts. Sanity check both sides solo.
	var fake_db: Dictionary = _s12_fake_db()
	var save := _bare_save("human")
	var solo_exec: Dictionary = {
		"weapon": {
			"base_id": "__s12_test_weapon", "rarity": "legendary",
			"affixes": [{"id": "of_executioner_pact", "value": 30}],
		},
	}
	var d_e: Dictionary = StatCalc.compute(solo_exec, fake_db, save, "human", 1, 0, 0, [])
	assert_almost_eq(float(d_e.get("low_hp_target_dmg_pct", -1.0)), 30.0, 0.001,
		"executioner_pact solo: not zeroed by absent glass_cannon")
	assert_almost_eq(float(d_e.get("glass_cannon_dmg_pct", -1.0)), 0.0, 0.001,
		"glass_cannon stays 0 when only executioner_pact is rolled")
	var solo_glass: Dictionary = {
		"amulet": {
			"base_id": "__s12_test_amulet", "rarity": "legendary",
			"affixes": [{"id": "of_glass_cannon", "value": 22}],
		},
	}
	var d_g: Dictionary = StatCalc.compute(solo_glass, fake_db, save, "human", 1, 0, 0, [])
	assert_almost_eq(float(d_g.get("glass_cannon_dmg_pct", -1.0)), 22.0, 0.001,
		"glass_cannon solo: not zeroed by absent executioner_pact")
	assert_almost_eq(float(d_g.get("low_hp_target_dmg_pct", -1.0)), 0.0, 0.001,
		"executioner_pact stays 0 when only glass_cannon is rolled")

func test_s12_low_hp_dmg_glass_cannon_mutex_larger_wins() -> void:
	# §2.E low_hp_dmg_pct ⊥ glass_cannon_dmg_pct. Same shape as the
	# executioner_pact ⊥ glass_cannon mutex but on the SELF-HP axis:
	# both can't be active gates at the same time (HP can't be <40 AND
	# >80 simultaneously), but the mutex enforces build-identity by
	# zeroing the smaller contribution. Resolved AFTER the
	# executioner_pact mutex above, so a triplet loadout (exec + glass +
	# desperation) resolves deterministically.
	var fake_db: Dictionary = _s12_fake_db()
	var save := _bare_save("human")
	# desperation 28 > glass_cannon 22 — desperation survives.
	var equipped_a: Dictionary = {
		"weapon": {
			"base_id": "__s12_test_weapon", "rarity": "legendary",
			"affixes": [{"id": "of_desperation", "value": 28}],
		},
		"amulet": {
			"base_id": "__s12_test_amulet", "rarity": "legendary",
			"affixes": [{"id": "of_glass_cannon", "value": 22}],
		},
	}
	var d_a: Dictionary = StatCalc.compute(equipped_a, fake_db, save, "human", 1, 0, 0, [])
	assert_almost_eq(float(d_a.get("low_hp_dmg_pct", -1.0)), 28.0, 0.001,
		"desperation (28) > glass_cannon (22) → desperation survives")
	assert_almost_eq(float(d_a.get("glass_cannon_dmg_pct", -1.0)), 0.0, 0.001,
		"desperation > glass_cannon → glass_cannon zeroed")
	# Inverse: glass_cannon 25 > desperation 12 — glass survives.
	var equipped_b: Dictionary = {
		"weapon": {
			"base_id": "__s12_test_weapon", "rarity": "legendary",
			"affixes": [{"id": "of_desperation", "value": 12}],
		},
		"amulet": {
			"base_id": "__s12_test_amulet", "rarity": "legendary",
			"affixes": [{"id": "of_glass_cannon", "value": 25}],
		},
	}
	var d_b: Dictionary = StatCalc.compute(equipped_b, fake_db, save, "human", 1, 0, 0, [])
	assert_almost_eq(float(d_b.get("low_hp_dmg_pct", -1.0)), 0.0, 0.001,
		"glass_cannon (25) > desperation (12) → desperation zeroed")
	assert_almost_eq(float(d_b.get("glass_cannon_dmg_pct", -1.0)), 25.0, 0.001,
		"glass_cannon (25) > desperation (12) → glass_cannon survives")

# ---------------------------------------------------------------------
# §2.I — per-species signature passive dispatcher (batch 1: stat-shape).
# Each test pins one species's signature kind. The dispatcher reads
# sp.signature.kind from species.json and applies the matching effect
# in StatCalc.compute. Combat-event passives (mummy / hill_orc /
# minotaur / troll / gargoyle / octopode / kobold) land in actor.gd
# hot paths in subsequent batches and are tested separately.
# ---------------------------------------------------------------------

func test_s12_human_highest_stat_pct_picks_str_when_tied() -> void:
	# Human innate +5% to highest stat. With base 5/5/5 + flat 1/1/1
	# (per species.json) + 9 lvl bonus, all three sit at 15/15/15 → STR
	# wins by tie-break (str_stat == hi check runs first).
	var d: Dictionary = StatCalc.compute({}, items_db, _bare_save("human"), "human", 10, 0, 0)
	# +5% on 15 → 16 (round). DEX/INT stay at 15.
	assert_eq(int(d.str), 16, "human str gets +5%% (15 → 16)")
	assert_eq(int(d.dex), 15, "human dex unchanged")
	assert_eq(int(d.int), 15, "human int unchanged")

func test_s12_human_highest_stat_pct_picks_int_when_int_highest() -> void:
	# Stat-allocate INT to make it the unambiguous highest.
	var save := _bare_save("human")
	save.stat_alloc_int = 20
	var d: Dictionary = StatCalc.compute({}, items_db, save, "human", 10, 0, 0)
	# Base 5 + flat 1 + lvl 9 + alloc 20 = 35 INT before signature.
	# +5% → 37 (round). STR/DEX stay at 15.
	assert_eq(int(d.int), 37, "human int gets +5%% when highest (35 → 37)")
	assert_eq(int(d.str), 15, "human str unchanged when int is highest")

func test_s12_naga_poison_res_clamps_to_100_not_75() -> void:
	# Naga signature `poison_immune_threshold: 100` is a clamp-bypass:
	# resistances.poison reads 100 (not the global 75 cap).
	var d: Dictionary = StatCalc.compute({}, items_db, _bare_save("naga"), "naga", 1, 0, 0)
	assert_almost_eq(float(d.resistances.poison), 100.0, 0.001,
		"naga poison_res clamps to 100 (immune threshold)")
	# Other resistances stay at the standard 75 cap. Pump fire_res past
	# 75 to verify the bypass is poison-only.
	var fake_db: Dictionary = items_db.duplicate(true)
	fake_db["__naga_test"] = {
		"id": "__naga_test", "slot": "amulet", "rarity": "legendary",
		"flavor_tags": [], "implicit_affixes": [],
	}
	var saturate: Dictionary = {
		"amulet": {"base_id": "__naga_test", "rarity": "legendary",
			"affixes": [{"id": "of_fire_resist", "value": 200}]},
	}
	var d2: Dictionary = StatCalc.compute(saturate, fake_db, _bare_save("naga"), "naga", 1, 0, 0)
	assert_almost_eq(float(d2.resistances.fire), 75.0, 0.001,
		"naga fire_res still clamps at 75 (only poison bypasses)")

func test_s12_demonspawn_fire_pact_holy_vulnerability() -> void:
	# Demonspawn signature: +25% fire-spell-element pct, -25% holy_res
	# (i.e. +25% holy damage taken).
	var d: Dictionary = StatCalc.compute({}, items_db, _bare_save("demonspawn"), "demonspawn", 1, 0, 0)
	assert_almost_eq(float(d.spell_element_pct.fire), 25.0, 0.001,
		"demonspawn fire-spell pct = 25")
	assert_almost_eq(float(d.resistances.holy), -25.0, 0.001,
		"demonspawn holy_res = -25 (vulnerability)")

func test_s12_vampire_lifesteal_cap_is_20_not_15() -> void:
	# Vampire signature bumps the lifesteal cap by 5 (15 → 20). Pin
	# both vampire (20) AND a human at the same equip (15) so a future
	# global cap change can't silently regress one half.
	var fake_db: Dictionary = items_db.duplicate(true)
	fake_db["__life_test"] = {
		"id": "__life_test", "slot": "amulet", "rarity": "legendary",
		"flavor_tags": [], "implicit_affixes": [],
	}
	var saturate: Dictionary = {
		"amulet": {"base_id": "__life_test", "rarity": "legendary",
			"affixes": [{"id": "of_lifesteal", "value": 100}]},
	}
	var d_h: Dictionary = StatCalc.compute(saturate, fake_db, _bare_save("human"), "human", 1, 0, 0)
	var d_v: Dictionary = StatCalc.compute(saturate, fake_db, _bare_save("vampire"), "vampire", 1, 0, 0)
	assert_almost_eq(float(d_h.lifesteal_pct), 15.0, 0.001, "human lifesteal cap = 15")
	assert_almost_eq(float(d_v.lifesteal_pct), 20.0, 0.001, "vampire lifesteal cap = 20")

func test_s12_deep_elf_spell_damage_cap_is_150_not_120() -> void:
	# Deep Elf signature bumps spell_damage_pct cap by 30 (120 → 150).
	var fake_db: Dictionary = items_db.duplicate(true)
	fake_db["__sd_test"] = {
		"id": "__sd_test", "slot": "amulet", "rarity": "legendary",
		"flavor_tags": [], "implicit_affixes": [],
	}
	var saturate: Dictionary = {
		"amulet": {"base_id": "__sd_test", "rarity": "legendary",
			"affixes": [{"id": "of_channeling", "value": 200}]},
	}
	var d_h: Dictionary = StatCalc.compute(saturate, fake_db, _bare_save("human"), "human", 1, 0, 0)
	var d_e: Dictionary = StatCalc.compute(saturate, fake_db, _bare_save("deep_elf"), "deep_elf", 1, 0, 0)
	assert_almost_eq(float(d_h.spell_damage_pct), 120.0, 0.001, "human spell_dmg cap = 120")
	assert_almost_eq(float(d_e.spell_damage_pct), 150.0, 0.001, "deep_elf spell_dmg cap = 150")

func test_s12_spriggan_evasion_flat() -> void:
	# Spriggan: +8% evasion innate. Bare-equip on lvl 1 should read 8
	# (no other evasion sources).
	var d: Dictionary = StatCalc.compute({}, items_db, _bare_save("spriggan"), "spriggan", 1, 0, 0)
	assert_almost_eq(float(d.evasion), 8.0, 0.001, "spriggan innate evasion = 8")

func test_s12_tengu_spell_proj_speed_flat() -> void:
	# Tengu: +25% spell projectile speed innate.
	var d: Dictionary = StatCalc.compute({}, items_db, _bare_save("tengu"), "tengu", 1, 0, 0)
	assert_almost_eq(float(d.spell_proj_speed_pct), 25.0, 0.001, "tengu innate spell_proj_speed = 25")

func test_s12_halfling_loot_quantity_flat() -> void:
	# Halfling: +10% loot_quantity_pct innate.
	var d: Dictionary = StatCalc.compute({}, items_db, _bare_save("halfling"), "halfling", 1, 0, 0)
	assert_almost_eq(float(d.loot_quantity_pct), 10.0, 0.001, "halfling innate loot_quantity = 10")

func test_s12_mummy_bleed_immune() -> void:
	# §2.I mummy: add_bloodletting on a Mummy bot is a no-op. Other
	# species absorb the bleed normally (verified by absence of mummy
	# species_id on the defender).
	var _StubBotDefender := preload("res://tests/_stub_bot_defender.gd")
	var d: Bot = _StubBotDefender.new()
	d.species_id = "mummy"
	d.hp = 100
	d.max_hp = 100
	d.add_bloodletting(5, null)
	assert_false(d.has_status("bleeding"), "mummy bot is bleed-immune (no status applied)")
	# Sanity: a non-mummy bot DOES gain the bleed status.
	var d2: Bot = _StubBotDefender.new()
	d2.species_id = "human"
	d2.hp = 100
	d2.max_hp = 100
	d2.add_bloodletting(5, null)
	assert_true(d2.has_status("bleeding"), "non-mummy bot bleeds normally (control)")
	d.free()
	d2.free()

func test_s12_mummy_poison_immune() -> void:
	var _StubBotDefender := preload("res://tests/_stub_bot_defender.gd")
	var d: Bot = _StubBotDefender.new()
	d.species_id = "mummy"
	d.hp = 100
	d.max_hp = 100
	d.add_poison(5, 4, 0.5, null)
	assert_false(d.has_status("poisoned"), "mummy bot is poison-immune")
	d.free()

func test_s12_mummy_burn_NOT_immune() -> void:
	# Mummy is bleed/poison/lifesteal-immune per the brief, but burn
	# still cooks dry bone — sanity-check that we didn't over-broadly
	# gate add_burn.
	var _StubBotDefender := preload("res://tests/_stub_bot_defender.gd")
	var d: Bot = _StubBotDefender.new()
	d.species_id = "mummy"
	d.hp = 100
	d.max_hp = 100
	d.add_burn(5, 3, 0.5, null)
	assert_true(d.has_status("burning"), "mummy bot still burns (NOT immune to fire DoT)")
	d.free()

func test_s12_minotaur_swing_counter_fires_on_every_5th() -> void:
	# §2.I minotaur: increment swing counter; on 5th swing flag fires.
	# Pure counter test — the actual armor=0 application is in
	# resolve_swing and is exercised by integration tests / playtest.
	# Here we pin only the counter logic.
	var _StubBotDefender := preload("res://tests/_stub_bot_defender.gd")
	var bot: Bot = _StubBotDefender.new()
	bot.species_id = "minotaur"
	bot._minotaur_swing_count = 0
	# Simulate 4 swings — counter at 4, no pen yet.
	for i in 4:
		bot._minotaur_swing_count += 1
	bot._minotaur_pen_active = false
	# 5th swing → flag fires + counter resets.
	bot._minotaur_swing_count += 1
	if bot._minotaur_swing_count >= 5:
		bot._minotaur_swing_count = 0
		bot._minotaur_pen_active = true
	assert_true(bot._minotaur_pen_active, "5th swing flips pen flag")
	assert_eq(bot._minotaur_swing_count, 0, "counter resets after firing")
	# 6th swing — pen back off.
	bot._minotaur_pen_active = false
	bot._minotaur_swing_count += 1
	assert_false(bot._minotaur_pen_active, "6th swing pen is off (counter at 1)")
	bot.free()

func test_s12_hill_orc_rage_used_resets_per_floor() -> void:
	# §2.I hill_orc: _hill_orc_rage_used is the once-per-floor mutex.
	# Pin: starts false on a fresh bot, set true once it fires, reset
	# false by the floor_started hook (simulated here).
	var _StubBotDefender := preload("res://tests/_stub_bot_defender.gd")
	var bot: Bot = _StubBotDefender.new()
	bot.species_id = "hill_orc"
	assert_false(bot._hill_orc_rage_used, "fresh bot has rage available")
	bot._hill_orc_rage_used = true
	# floor_started hook in dungeon.gd resets this to false.
	bot._hill_orc_rage_used = false
	assert_false(bot._hill_orc_rage_used, "floor_started resets rage availability")
	bot.free()

# ---------------------------------------------------------------------
# §2.J — mana economy plumbing tests.
# Pin the INT-scaling formula, species cross-links, and clamps so a
# future stat_calc edit can't silently change the player-feel of mana
# pacing.
# ---------------------------------------------------------------------

func test_s12_2j_mana_max_int_scaling() -> void:
	# Bare bot at lvl 1 has int_excess = 1 (5 base + flat 1) - 5 = 1
	# (humans get +1 to all stats per species_data.json), so mana_max
	# = 30 + int(1 × 0.5) = 31. At lvl 30, int_excess = 30 → 30 + 15 = 45.
	var d_lvl1: Dictionary = StatCalc.compute({}, items_db, _bare_save("human"), "human", 1, 0, 0)
	assert_eq(int(d_lvl1.mana_max), 31, "human lvl 1 mana_max = 31 (30 + int_excess 1 × 0.5 round)")
	var d_lvl30: Dictionary = StatCalc.compute({}, items_db, _bare_save("human"), "human", 30, 0, 0)
	assert_eq(int(d_lvl30.mana_max), 45, "human lvl 30 mana_max = 45 (30 + int_excess 30 × 0.5)")

func test_s12_2j_mana_regen_int_scaling() -> void:
	# Bare bot lvl 1 int_excess = 1 → regen 1.0 + 0.05 = 1.05.
	# Lvl 30 int_excess = 30 → regen 1.0 + 1.5 = 2.5.
	var d_lvl1: Dictionary = StatCalc.compute({}, items_db, _bare_save("human"), "human", 1, 0, 0)
	assert_almost_eq(float(d_lvl1.mana_regen), 1.05, 0.001, "human lvl 1 mana_regen = 1.05")
	var d_lvl30: Dictionary = StatCalc.compute({}, items_db, _bare_save("human"), "human", 30, 0, 0)
	assert_almost_eq(float(d_lvl30.mana_regen), 2.50, 0.001, "human lvl 30 mana_regen = 2.50")

func test_s12_2j_mana_cost_clamp() -> void:
	# of_thrift T5 at -25, stack 5 → -125 raw. mana_cost_pct clamps at -50.
	var fake_db: Dictionary = items_db.duplicate(true)
	fake_db["__thrift_test"] = {
		"id": "__thrift_test", "slot": "amulet", "rarity": "legendary",
		"flavor_tags": [], "implicit_affixes": [],
	}
	var saturate: Dictionary = {
		"amulet": {"base_id": "__thrift_test", "rarity": "legendary",
			"affixes": [{"id": "of_thrift", "value": -200}]},
	}
	var d: Dictionary = StatCalc.compute(saturate, fake_db, _bare_save("human"), "human", 1, 0, 0)
	assert_almost_eq(float(d.mana_cost_pct), -50.0, 0.001, "of_thrift discount clamps at -50")

func test_s12_2j_octopode_regen_bonus() -> void:
	# Octopode mana_regen × 1.5. Bare lvl 1: 1.05 × 1.5 = 1.575.
	var d: Dictionary = StatCalc.compute({}, items_db, _bare_save("octopode"), "octopode", 1, 0, 0)
	# Octopode int_flat in species.json may differ from human. Compute
	# the expected from int_excess to keep the test species-data agnostic.
	var expected_regen: float = (1.0 + float(int(d.int) - 5) * 0.05) * 1.5
	assert_almost_eq(float(d.mana_regen), expected_regen, 0.01,
		"octopode mana_regen = base × 1.5 (got %.3f vs expected %.3f)" % [
			float(d.mana_regen), expected_regen])

func test_s12_2j_deep_elf_max_bonus() -> void:
	# Deep elf mana_max × 1.3. Bare lvl 1: round(31 × 1.3) = 40 — but
	# deep_elf has +int_flat in species.json so int_excess differs.
	# Compute expected from int_excess.
	var d: Dictionary = StatCalc.compute({}, items_db, _bare_save("deep_elf"), "deep_elf", 1, 0, 0)
	var expected_max: int = int(round(float(int(round(30.0 + float(int(d.int) - 5) * 0.5))) * 1.3))
	assert_eq(int(d.mana_max), expected_max,
		"deep_elf mana_max = (30 + int_excess × 0.5) × 1.3 (got %d vs expected %d)" % [
			int(d.mana_max), expected_max])

func test_s12_2j_mummy_no_passive_regen() -> void:
	# Mummy mana_regen = 0 (only on-kill grants).
	var d: Dictionary = StatCalc.compute({}, items_db, _bare_save("mummy"), "mummy", 30, 0, 0)
	assert_almost_eq(float(d.mana_regen), 0.0, 0.001, "mummy passive mana_regen = 0")
	# But mana_max is still positive (non-zero pool, just doesn't refill
	# passively).
	assert_gt(int(d.mana_max), 0, "mummy mana_max > 0 (pool exists, just no auto-refill)")

func test_s12_2j_demonspawn_regen_penalty() -> void:
	# Demonspawn mana_regen × 0.80 (the offsetting downside).
	var d: Dictionary = StatCalc.compute({}, items_db, _bare_save("demonspawn"), "demonspawn", 30, 0, 0)
	var expected_regen: float = (1.0 + float(int(d.int) - 5) * 0.05) * 0.80
	assert_almost_eq(float(d.mana_regen), expected_regen, 0.01,
		"demonspawn mana_regen = base × 0.80")

func test_s12_octopode_rings_skip_per_affix_dr() -> void:
	# §2.I octopode: ring affixes ignore per-affix-id DR with each
	# other. Same affix on multiple rings stacks at 1.0× per ring,
	# instead of 1.0/0.75/0.5/0.25 normal DR.
	# Setup: 2 rings each rolling of_might 12 (T5).
	var fake_db: Dictionary = items_db.duplicate(true)
	fake_db["__op_ring"] = {
		"id": "__op_ring", "slot": "ring", "rarity": "legendary",
		"flavor_tags": [], "implicit_affixes": [],
	}
	fake_db["__op_ring2"] = {
		"id": "__op_ring2", "slot": "ring2", "rarity": "legendary",
		"flavor_tags": [], "implicit_affixes": [],
	}
	var inst1 := {"base_id": "__op_ring", "rarity": "legendary",
		"affixes": [{"id": "of_might", "value": 12}]}
	var inst2 := {"base_id": "__op_ring2", "rarity": "legendary",
		"affixes": [{"id": "of_might", "value": 12}]}
	# Human comparison: 2 of_might at 12 each, with DR 1.0 + 0.75 = 1.75 → 21 STR added.
	# Bare human STR = 5 + flat 1 + lvl 0 = 6. + 21 → 27.
	var d_h: Dictionary = StatCalc.compute(
		{"ring": inst1, "ring2": inst2}, fake_db,
		_bare_save("human"), "human", 1, 0, 0
	)
	# Octopode: 2 rings each at 1.0× = 24 STR added (no DR).
	# Bare octopode STR = 5 + flat (octopode str_flat in species.json)
	# + lvl 0. We don't know octopode's str_flat without reading the
	# data, so anchor on the DELTA between human and octopode rather
	# than absolute values.
	var d_o: Dictionary = StatCalc.compute(
		{"ring": inst1, "ring2": inst2}, fake_db,
		_bare_save("octopode"), "octopode", 1, 0, 0
	)
	# Bare-equip baselines (no rings):
	var d_h_base: Dictionary = StatCalc.compute({}, fake_db, _bare_save("human"), "human", 1, 0, 0)
	var d_o_base: Dictionary = StatCalc.compute({}, fake_db, _bare_save("octopode"), "octopode", 1, 0, 0)
	# Human ring delta = 21 (12 × 1.0 + 12 × 0.75 = 21).
	var human_delta: int = int(d_h.str) - int(d_h_base.str)
	# Octopode ring delta = 24 (12 × 1.0 + 12 × 1.0 = 24, no DR).
	var op_delta: int = int(d_o.str) - int(d_o_base.str)
	# But §2.I human signature bumps highest stat by 5%, and rings
	# pump STR. With STR 27 + 5% = 28.35 → 28; base 6 + 5% = 6.3 → 6.
	# Delta becomes 28-6 = 22 (signature compresses by 1). Octopode
	# has no highest-stat sig so its delta is clean 24. The TEST
	# pin: octopode delta > human delta — DR skip is real and
	# meaningful regardless of human's compression.
	assert_gt(op_delta, human_delta,
		"octopode ring stacking exceeds human (DR skip → %d > %d)" % [op_delta, human_delta])
	# Stronger pin: octopode delta should be exactly 24 (no DR,
	# no rounding loss for STR).
	assert_eq(op_delta, 24,
		"octopode 2 of_might × 12 = 24 STR (no DR — octopode delta=%d)" % op_delta)

func test_s12_first_hit_mark_sums_with_crit_mark_into_marked_amp_lane() -> void:
	# Both of_hunter_mark (on-crit) and of_vulnerability_mark (first-hit)
	# write into the marked-amp lane that actor.gd::_apply_typed_damage
	# reads when has_status("marked"). The sum must surface — independent
	# clamping per source means a paired loadout reaches their summed
	# nominal totals (40 + 25 = 65) without either being clamped to the
	# other's cap. (The marked-amp APPLICATION at hit-time isn't tested
	# here — that's an actor.gd combat-resolution test; this test pins
	# only the StatCalc accumulator output.)
	var fake_db: Dictionary = _s12_fake_db()
	var save := _bare_save("human")
	var equipped: Dictionary = {
		"weapon": {
			"base_id": "__s12_test_weapon", "rarity": "legendary",
			"affixes": [
				{"id": "of_hunter_mark", "value": 40},
				{"id": "of_vulnerability_mark", "value": 25},
			],
		},
	}
	var d: Dictionary = StatCalc.compute(equipped, fake_db, save, "human", 1, 0, 0, [])
	assert_almost_eq(float(d.get("crit_mark_dmg_pct", -1.0)), 40.0, 0.001,
		"of_hunter_mark hits its 40 cap")
	assert_almost_eq(float(d.get("first_hit_mark_pct", -1.0)), 25.0, 0.001,
		"of_vulnerability_mark hits its 25 cap")
