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
# Helpers
# ---------------------------------------------------------------------

func _bare_save(species: String) -> Dictionary:
	return {
		"species": species,
		"stat_alloc_str": 0, "stat_alloc_dex": 0, "stat_alloc_int": 0,
		"stat_points_unspent": 0,
		"bot_upgrades": {},
	}
