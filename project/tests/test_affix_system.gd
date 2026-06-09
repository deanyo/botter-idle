extends GutTest

# Tests for AffixSystem.roll_affixes_for. Locks the content-pipeline-
# critical contracts:
#   - Reproducibility: same RNG seed → same affix roll
#   - Count matches data/affixes.json::rarity_affix_count
#   - applies_to filter holds (no armor affix on a weapon)
#   - affix_pool override beats applies_to fallback
#   - Common/uncommon spell rolls strip flag-kind affixes
#   - No duplicate affix in a single roll
#
# Run via:
#   /Applications/Godot.app/Contents/MacOS/Godot --path project --headless \
#       -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit

# ---------------------------------------------------------------------
# Reproducibility — same seed + same item → same roll
# ---------------------------------------------------------------------

func test_same_seed_produces_identical_rolls() -> void:
	var item := {"slot": "ring", "rarity": "epic", "base_type": "ring"}
	var rng_a := RandomNumberGenerator.new()
	rng_a.seed = 1234
	var rng_b := RandomNumberGenerator.new()
	rng_b.seed = 1234
	var roll_a: Array = AffixSystem.roll_affixes_for(item, rng_a)
	var roll_b: Array = AffixSystem.roll_affixes_for(item, rng_b)
	assert_eq(JSON.stringify(roll_a), JSON.stringify(roll_b),
		"epic ring roll deterministic under fixed seed")

func test_different_seed_likely_diverges() -> void:
	# Statistical: with 5 affixes drawn from a wide pool, two rolls
	# from different seeds should differ in at least one slot. Not
	# strict equality — just diverge across N seeds.
	var item := {"slot": "ring", "rarity": "legendary", "base_type": "ring"}
	var diverged: bool = false
	for s in range(1, 5):
		var rng_a := RandomNumberGenerator.new()
		rng_a.seed = 1000
		var rng_b := RandomNumberGenerator.new()
		rng_b.seed = 1000 + s
		if JSON.stringify(AffixSystem.roll_affixes_for(item, rng_a)) \
				!= JSON.stringify(AffixSystem.roll_affixes_for(item, rng_b)):
			diverged = true
			break
	assert_true(diverged, "different seeds produce different rolls within 4 attempts")

# ---------------------------------------------------------------------
# Count matches rarity_affix_count
# ---------------------------------------------------------------------

func test_rarity_affix_count_matches_data() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var expected := {"common": 1, "uncommon": 2, "rare": 3, "epic": 4, "legendary": 5}
	for rarity in expected.keys():
		var item := {"slot": "ring", "rarity": rarity, "base_type": "ring"}
		var roll: Array = AffixSystem.roll_affixes_for(item, rng)
		assert_eq(roll.size(), expected[rarity],
			"%s ring rolls %d affixes" % [rarity, expected[rarity]])

# ---------------------------------------------------------------------
# applies_to filter holds — no armor-restricted affix on a weapon
# ---------------------------------------------------------------------

func test_no_affix_violates_applies_to_for_weapon() -> void:
	# Hammer 50 random rolls of a legendary weapon: every rolled affix
	# must list "weapon" in its applies_to (or "any").
	var rng := RandomNumberGenerator.new()
	for s in 50:
		rng.seed = s
		var item := {"slot": "weapon", "rarity": "legendary", "base_type": "long_sword"}
		var roll: Array = AffixSystem.roll_affixes_for(item, rng)
		for af_inst in roll:
			var def: Dictionary = AffixSystem.get_affix_def(String(af_inst.id))
			var applies: Array = def.get("applies_to", [])
			var ok: bool = "weapon" in applies or "any" in applies
			assert_true(ok,
				"weapon roll seed=%d included %s (applies_to=%s)" %
				[s, af_inst.id, str(applies)])

func test_no_affix_violates_applies_to_for_armor() -> void:
	var rng := RandomNumberGenerator.new()
	for s in 50:
		rng.seed = s
		var item := {"slot": "armor", "rarity": "legendary", "base_type": "plate_armor"}
		var roll: Array = AffixSystem.roll_affixes_for(item, rng)
		for af_inst in roll:
			var def: Dictionary = AffixSystem.get_affix_def(String(af_inst.id))
			var applies: Array = def.get("applies_to", [])
			var ok: bool = "armor" in applies or "any" in applies
			assert_true(ok,
				"armor roll seed=%d included %s (applies_to=%s)" %
				[s, af_inst.id, str(applies)])

# ---------------------------------------------------------------------
# affix_pool override beats applies_to fallback
# ---------------------------------------------------------------------

func test_affix_pool_override_constrains_picks() -> void:
	# Item-authored allowlist: only of_might + of_finesse may roll.
	# Even at legendary (5 affixes wanted), pool is exhausted at 2;
	# the "no duplicates" guard should cap the roll at 2.
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var item := {
		"slot": "ring", "rarity": "legendary", "base_type": "ring",
		"affix_pool": {"of_might": 100, "of_finesse": 100},
	}
	var roll: Array = AffixSystem.roll_affixes_for(item, rng)
	assert_lte(roll.size(), 2,
		"affix_pool capped at 2 unique entries should never exceed 2 rolls")
	for af_inst in roll:
		var id: String = String(af_inst.id)
		assert_true(id == "of_might" or id == "of_finesse",
			"rolled %s outside the affix_pool allowlist" % id)

# ---------------------------------------------------------------------
# Common/uncommon spell strips flag-kind affixes
# ---------------------------------------------------------------------

func test_common_spell_strips_flag_affixes() -> void:
	# Pre-2026-06-07 a common Magic Dart could roll Forked + Rending
	# (flag-kind, archetype-defining). Filter must remove flag-kind
	# entries from the spell pool at common/uncommon rarity.
	var rng := RandomNumberGenerator.new()
	for s in 30:
		rng.seed = s
		var item := {"slot": "spell", "rarity": "common", "base_type": "spell"}
		var roll: Array = AffixSystem.roll_affixes_for(item, rng)
		for af_inst in roll:
			var def: Dictionary = AffixSystem.get_affix_def(String(af_inst.id))
			assert_ne(String(def.get("kind", "")), "flag",
				"common spell rolled flag-kind %s at seed=%d" % [af_inst.id, s])

func test_epic_spell_allows_flag_affixes() -> void:
	# Inverse of the above: at epic+ rarity, flag-kind entries are
	# allowed back into the pool. Statistical: across 30 epic rolls
	# (4 affixes each = 120 picks), at least one flag should land.
	var rng := RandomNumberGenerator.new()
	var saw_flag: bool = false
	for s in 30:
		rng.seed = s
		var item := {"slot": "spell", "rarity": "epic", "base_type": "spell"}
		var roll: Array = AffixSystem.roll_affixes_for(item, rng)
		for af_inst in roll:
			var def: Dictionary = AffixSystem.get_affix_def(String(af_inst.id))
			if String(def.get("kind", "")) == "flag":
				saw_flag = true
				break
		if saw_flag:
			break
	assert_true(saw_flag, "epic spell pool re-includes flag-kind affixes")

# ---------------------------------------------------------------------
# No duplicate affix in a single roll
# ---------------------------------------------------------------------

func test_no_duplicate_affix_in_single_roll() -> void:
	var rng := RandomNumberGenerator.new()
	for s in 50:
		rng.seed = s
		var item := {"slot": "ring", "rarity": "legendary", "base_type": "ring"}
		var roll: Array = AffixSystem.roll_affixes_for(item, rng)
		var ids: Dictionary = {}
		for af_inst in roll:
			var id: String = String(af_inst.id)
			assert_false(ids.has(id),
				"duplicate %s in single roll at seed=%d" % [id, s])
			ids[id] = true

# ---------------------------------------------------------------------
# format_item_tooltip — items v2 schema (damage_min/max + armor + evasion)
# ---------------------------------------------------------------------

func test_tooltip_renders_v2_weapon_damage_range() -> void:
	# v2 weapons declare damage_min/damage_max, not legacy `atk`. The
	# tooltip's base-parts block must read the v2 keys.
	var item := {
		"name": "Test Sword", "rarity": "common", "slot": "weapon",
		"damage_min": 4, "damage_max": 9,
	}
	var tip: String = AffixSystem.format_item_tooltip(item, {"affixes": []})
	assert_true(tip.contains("4-9 Dmg"), "v2 weapon shows damage range, got: %s" % tip)
	assert_false(tip.contains("ATK"), "tooltip should not surface legacy ATK label, got: %s" % tip)

func test_tooltip_renders_v2_armor_and_evasion() -> void:
	var item := {
		"name": "Test Plate", "rarity": "common", "slot": "armor",
		"armor": 12, "evasion": 5,
	}
	var tip: String = AffixSystem.format_item_tooltip(item, {"affixes": []})
	assert_true(tip.contains("+12 Armor"), "v2 body shows armor, got: %s" % tip)
	assert_true(tip.contains("+5% Evasion"), "v2 body shows evasion, got: %s" % tip)
	assert_false(tip.contains("DEF"), "tooltip should not surface legacy DEF label, got: %s" % tip)

func test_format_stat_line_drops_legacy_atk_def_cases() -> void:
	# atk/def were the v1 affix stat keys. Nothing in affixes.json uses
	# them now, but the formatter previously had cases for them — those
	# went away with the v2 cleanup. A future re-add of an "atk" or
	# "def" affix will fall through to the +%d <stat> default, which
	# this test asserts so we notice if it sneaks back.
	assert_eq(AffixSystem._format_stat_line("atk", 5), "+5 atk",
		"removed legacy atk case must fall through to default")
	assert_eq(AffixSystem._format_stat_line("def", 7), "+7 def",
		"removed legacy def case must fall through to default")
	# hp stays — `of_vitality` rolls stat=hp.
	assert_eq(AffixSystem._format_stat_line("hp", 30), "+30 HP",
		"hp stays on the formatter — of_vitality is alive")
