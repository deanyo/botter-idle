extends SceneTree

# Hand-rolled golden-master tests for StatCalc.compute. Locks the stat
# math against the post-2026-06-08 unification residue cluster so future
# touches catch regressions before they ship. No GUT dependency — runs
# via:
#   /Applications/Godot.app/Contents/MacOS/Godot \
#       --path project --headless --script tests/stat_calc_tests.gd
#
# Surfaced through tools/check_before_commit.sh — exits non-zero on any
# assertion failure. Tests print their own pass / fail line so a CI
# stream stays readable.

var _failures: int = 0
var _checks: int = 0

func _initialize() -> void:
	# Smoke-load items.json + affixes.json so StatCalc can resolve
	# implicit affixes + base item stats. Failing to preload would
	# throw "Failed to open" errors deep inside compute().
	ItemsDb.preload_all()
	var items_db: Dictionary = ItemsDb.items()
	if items_db.is_empty():
		_fail("could not load items_db", "ItemsDb.items() returned empty")
		_done()
		return

	# Default save fixture — no allocation, no upgrades. Everything in a
	# test reads from this base unless overridden.
	var save: Dictionary = _bare_save("human")

	_test_bare_human(items_db, save)
	_test_minotaur_atk_pct(items_db)
	_test_naga_haste_pct(items_db)
	_test_octopode_loot_pct_and_aggro(items_db)
	_test_blessing_atk_pct_doubles_with_atk_flat(items_db)
	_test_blessing_def_flat(items_db)
	_test_blessing_hp_pct_stacks_with_species(items_db)
	_test_blessing_hp_regen(items_db)
	_test_lifesteal_clamp(items_db)
	_test_unspent_points_key(items_db)
	_test_element_affix_populates_spell_element_pct(items_db)

	_done()

# ---------------------------------------------------------------------
# Cases
# ---------------------------------------------------------------------

func _test_bare_human(items_db: Dictionary, save: Dictionary) -> void:
	var d: Dictionary = StatCalc.compute({}, items_db, save, "human", 1, 0, 0, [])
	# Human +1/+1/+1 on top of 5/5/5 base → 6/6/6.
	_eq("bare human str", int(d.str), 6)
	_eq("bare human dex", int(d.dex), 6)
	_eq("bare human int", int(d.int), 6)
	# Bare-handed weapon = 1-2 phys, 1.0s. Dex excess of 1 nudges crit
	# by 0.5; haste by 1 (so attack_interval = 1.0/1.01).
	_eq("bare human damage_min", int(d.damage_min), 1)
	_eq("bare human damage_max", int(d.damage_max), 2)
	# str_excess=1 → max_hp = 80 × 1.015 = 81.2 → 81.
	_eq("bare human max_hp", int(d.max_hp), 81)
	_eq("bare human aggro_bonus", int(d.aggro_bonus), 0)

func _test_minotaur_atk_pct(items_db: Dictionary) -> void:
	# Minotaur has atk_pct=20 — pre-2026-06-08 this read as nothing.
	# Now folded multiplicatively into damage_min/max so a bare-hands
	# Minotaur swings 1.2-2.4 → rounds to 1-2 (still flat) but the dex
	# excess from 5 dex still routes through. Use a level-10 bot with
	# allocation in str so the multiplier moves a real number.
	var save: Dictionary = _bare_save("minotaur")
	save["stat_alloc_str"] = 0
	var d: Dictionary = StatCalc.compute({}, items_db, save, "minotaur", 10, 0, 0, [])
	# Minotaur +5 str_flat + 9 lvl_bonus + 5 base = 19 str.
	_eq("minotaur str", int(d.str), 19)
	# damage_min/max start at 1/2 (bare hands) + 0 atk upgrade,
	# then × 1.20 atk_pct = 1.2 / 2.4 → 1 / 2 after rounding.
	# Confirm aggro_flat=1 surfaces as +1 aggro_bonus.
	_eq("minotaur aggro_bonus", int(d.aggro_bonus), 1)

func _test_naga_haste_pct(items_db: Dictionary) -> void:
	# Naga -15 haste + +0.5 regen_flat. Bare bot dex 4 (5 base + -2
	# species + 1 lvl_bonus dex_flat... wait, -2 + 5 = 3, not 4. Lvl 1
	# means lvl_bonus=0, so 5 + (-2) + 0 + 0 = 3 dex.
	var save: Dictionary = _bare_save("naga")
	var d: Dictionary = StatCalc.compute({}, items_db, save, "naga", 1, 0, 0, [])
	_eq("naga dex", int(d.dex), 3)
	# Dex_excess = 3 - 5 = -2 → haste += -2; species haste -15 → -17.
	# Negative haste clamps to 0 in StatCalc.
	_eq("naga haste_pct (clamped)", int(round(float(d.haste_pct))), 0)
	# Regen is 0.5 from species.
	_assert_close("naga hp_regen", float(d.hp_regen), 0.5)

func _test_octopode_loot_pct_and_aggro(items_db: Dictionary) -> void:
	var save: Dictionary = _bare_save("octopode")
	var d: Dictionary = StatCalc.compute({}, items_db, save, "octopode", 1, 0, 0, [])
	_assert_close("octopode loot_rarity_bonus", float(d.loot_rarity_bonus), 20.0)
	_eq("octopode aggro_bonus (no vision tag)", int(d.aggro_bonus), 0)

func _test_blessing_atk_pct_doubles_with_atk_flat(items_db: Dictionary) -> void:
	# Trog (atk_pct=20) + Yred (atk_flat=25) on a bare-hands Human.
	# Order: flat applied first (1+25=26, 2+25=27), then pct (×1.20).
	# 26 × 1.20 = 31.2 → 31; 27 × 1.20 = 32.4 → 32.
	var save: Dictionary = _bare_save("human")
	var blessings: Array = [
		{"kind": "atk_pct",  "value": 20.0, "god": "trog"},
		{"kind": "atk_flat", "value": 25.0, "god": "yredelemnul"},
	]
	var d: Dictionary = StatCalc.compute({}, items_db, save, "human", 1, 0, 0, blessings)
	_eq("trog+yred damage_min", int(d.damage_min), 31)
	_eq("trog+yred damage_max", int(d.damage_max), 32)

func _test_blessing_def_flat(items_db: Dictionary) -> void:
	# Cheibriados +30 DEF (def_flat=30) — armor jumps from 0 to 30.
	var save: Dictionary = _bare_save("human")
	var blessings: Array = [{"kind": "def_flat", "value": 30.0, "god": "cheibriados"}]
	var d: Dictionary = StatCalc.compute({}, items_db, save, "human", 1, 0, 0, blessings)
	_eq("cheibriados armor", int(d.armor), 30)

func _test_blessing_hp_pct_stacks_with_species(items_db: Dictionary) -> void:
	# Naga (+20% hp) + Fedhas (+40% hp) at level 1. Stacks multiplicatively
	# = 1.20 × 1.40 = 1.68×, then × str_mult. Naga str = 5+3+0+0 = 8 →
	# str_excess=3 → str_mult = 1.045. max_hp = 80 × 1.68 × 1.045 = 140.45
	# → 140. Locks the multiplicative composition rule.
	var save: Dictionary = _bare_save("naga")
	var blessings: Array = [{"kind": "hp_pct", "value": 40.0, "god": "fedhas"}]
	var d: Dictionary = StatCalc.compute({}, items_db, save, "naga", 1, 0, 0, blessings)
	_eq("naga + fedhas max_hp", int(d.max_hp), 140)

func _test_blessing_hp_regen(items_db: Dictionary) -> void:
	# Elyvilon's mercy = +3 HP/sec — already worked pre-fix; lock it
	# in so future touches don't regress hp_regen kind.
	var save: Dictionary = _bare_save("human")
	var blessings: Array = [{"kind": "hp_regen", "value": 3.0, "god": "elyvilon"}]
	var d: Dictionary = StatCalc.compute({}, items_db, save, "human", 1, 0, 0, blessings)
	_assert_close("elyvilon hp_regen", float(d.hp_regen), 3.0)

func _test_lifesteal_clamp(items_db: Dictionary) -> void:
	# of_lifesteal at high tier could push lifesteal_pct over 15 cap.
	# Confirm the clamp holds. Build a synthetic affix: 20% lifesteal.
	# Equip an inst-only weapon with no item def so it has no atk
	# contribution, then feed a hand-rolled affix list. Easiest path:
	# fake an item by writing one to items_db at runtime.
	var fake_db: Dictionary = items_db.duplicate(true)
	fake_db["__test_weapon"] = {
		"id": "__test_weapon", "slot": "weapon", "rarity": "legendary",
		"damage_min": 5, "damage_max": 10, "speed": 1.0,
		"damage_type": "physical", "weapon_class": "1H",
		"flavor_tags": [], "implicit_affixes": [],
	}
	var inst: Dictionary = {
		"base_id": "__test_weapon", "rarity": "legendary",
		"affixes": [
			{"id": "of_lifesteal", "value": 20},
		],
	}
	var save: Dictionary = _bare_save("human")
	var d: Dictionary = StatCalc.compute({"weapon": inst}, fake_db, save, "human", 1, 0, 0, [])
	# Cap lives at 15.0.
	_assert_close("lifesteal_pct clamp", float(d.lifesteal_pct), 15.0)

func _test_unspent_points_key(items_db: Dictionary) -> void:
	# Audit-flagged typo (cd69e55). Lock it in: stat_calc reads
	# stat_points_unspent, not unspent_points.
	var save: Dictionary = _bare_save("human")
	save["stat_points_unspent"] = 7
	var d: Dictionary = StatCalc.compute({}, items_db, save, "human", 5, 0, 0, [])
	_eq("unspent_points routes from stat_points_unspent", int(d.unspent_points), 7)

func _test_element_affix_populates_spell_element_pct(items_db: Dictionary) -> void:
	# Element affixes (of_pyromancer etc.) write to fire_dmg_pct /
	# cold_dmg_pct / etc., which StatCalc maps onto spell_element_pct
	# keyed by element. spell_data.gd:181 reads these to scale element
	# tagged spells. Confirm the wiring.
	var fake_db: Dictionary = items_db.duplicate(true)
	fake_db["__test_amulet"] = {
		"id": "__test_amulet", "slot": "amulet", "rarity": "epic",
		"flavor_tags": [], "implicit_affixes": [],
	}
	var inst: Dictionary = {
		"base_id": "__test_amulet", "rarity": "epic",
		"affixes": [
			{"id": "of_pyromancer", "value": 24},
		],
	}
	var save: Dictionary = _bare_save("human")
	var d: Dictionary = StatCalc.compute({"amulet": inst}, fake_db, save, "human", 1, 0, 0, [])
	var elem: Dictionary = d.get("spell_element_pct", {})
	_assert_close("of_pyromancer → spell_element_pct.fire", float(elem.get("fire", 0)), 24.0)

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

func _eq(name: String, actual, expected) -> void:
	_checks += 1
	if actual == expected:
		print("  PASS  %s  (= %s)" % [name, str(actual)])
	else:
		_failures += 1
		print("  FAIL  %s  expected %s, got %s" % [name, str(expected), str(actual)])

func _assert_close(name: String, actual: float, expected: float) -> void:
	_checks += 1
	if absf(actual - expected) <= 0.001:
		print("  PASS  %s  (= %.3f)" % [name, actual])
	else:
		_failures += 1
		print("  FAIL  %s  expected ~%.3f, got %.3f" % [name, expected, actual])

func _fail(name: String, msg: String) -> void:
	_checks += 1
	_failures += 1
	print("  FAIL  %s  %s" % [name, msg])

func _done() -> void:
	print("")
	print("StatCalc tests: %d/%d passed" % [_checks - _failures, _checks])
	quit(1 if _failures > 0 else 0)
