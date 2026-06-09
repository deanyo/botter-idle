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

# ---------------------------------------------------------------------
# S1 regressions (2026-06-09 audit) — locking the four critical fixes
# from SYNTHESIS §C2: of_venom collision rename, element-pct affix
# survival, base_type category expansion, of_multicast non-zero floor.
# ---------------------------------------------------------------------

func test_of_envenom_replaces_pct_venom_no_collision() -> void:
	# Pre-fix: two affixes shared id "of_venom" — range (poison_extra)
	# and pct (poison_dmg_pct). Loader silently dropped one. Post-fix
	# the pct version is renamed to of_envenom; both must coexist with
	# distinct ids and distinct stat keys.
	var range_def: Dictionary = AffixSystem.get_affix_def("of_venom")
	var pct_def: Dictionary = AffixSystem.get_affix_def("of_envenom")
	assert_false(range_def.is_empty(), "of_venom (range) survives the rename")
	assert_false(pct_def.is_empty(), "of_envenom (pct) is reachable post-rename")
	assert_eq(String(range_def.get("stat", "")), "poison_extra",
		"of_venom keeps poison_extra range stat")
	assert_eq(String(pct_def.get("stat", "")), "poison_dmg_pct",
		"of_envenom owns poison_dmg_pct")

func test_element_pct_affixes_can_roll_on_jewelry() -> void:
	# Pre-fix: of_pyromancer / of_cryomancer / of_storm / of_zealot /
	# of_envenom / of_shadow appeared in zero items' affix_pool — pure
	# dead code. Post-fix every ring/amulet/spell pool carries them.
	# Statistical: across 200 legendary ring rolls (5 affixes each =
	# 1000 picks), at least one element-pct id should land.
	var rng := RandomNumberGenerator.new()
	var saw: bool = false
	var element_ids := ["of_pyromancer", "of_cryomancer", "of_storm",
		"of_zealot", "of_envenom", "of_shadow"]
	for s in 200:
		rng.seed = s
		var item := {
			"slot": "ring", "rarity": "legendary", "base_type": "ring",
			"affix_pool": {
				"of_pyromancer": 8, "of_cryomancer": 8, "of_storm": 8,
				"of_zealot": 8, "of_envenom": 8, "of_shadow": 8,
				"of_might": 8, "of_finesse": 8,
			},
		}
		var roll: Array = AffixSystem.roll_affixes_for(item, rng)
		for af_inst in roll:
			if String(af_inst.id) in element_ids:
				saw = true
				break
		if saw:
			break
	assert_true(saw, "element-pct affix rolled on ring within 200 attempts")

func test_base_type_category_expansion_resolves_to_real_affix_ids() -> void:
	# Pre-fix base_type_affixes.json keys ("crit"/"haste"/"strength"/…)
	# matched zero affix ids — the entire file fell through to the
	# applies_to fallback. Post-fix categories expand to id-lists at
	# load time; a tower_shield's "stamina:40 regen:10" should now
	# bias toward of_vitality / of_the_bear / of_regen / of_lifesteal.
	var rng := RandomNumberGenerator.new()
	var bias_count: int = 0
	var biased_ids := {"of_vitality": true, "of_the_bear": true,
		"of_regen": true, "of_lifesteal": true}
	for s in 200:
		rng.seed = s
		# tower_shield is in base_type_affixes with stamina:40 regen:10
		var item := {"slot": "shield", "rarity": "legendary", "base_type": "tower_shield"}
		var roll: Array = AffixSystem.roll_affixes_for(item, rng)
		for af_inst in roll:
			if biased_ids.has(String(af_inst.id)):
				bias_count += 1
	assert_gt(bias_count, 0,
		"tower_shield base-type weights should bias toward stamina/regen affixes (got %d hits over 200 rolls)" % bias_count)

func test_format_affix_lines_drops_zero_value_rows() -> void:
	# PLAYTEST #9 / S3.1 — flat/pct affix rolls whose displayed integer
	# is 0 must NOT reach the tooltip. format_affix_lines is the legacy
	# text-tooltip path (outpost slot tooltip + a few fallback callers),
	# so it has to suppress the same zero-rows the visual ItemTooltip
	# already filters. Range affixes carry value_min/max so a 0-midpoint
	# range stays visible.
	var affixes := [
		{"id": "of_multicast", "value": 0},        # flat, zero -> dropped
		{"id": "of_might",     "value": 4},        # flat, non-zero -> kept
		{"id": "of_channeling","value": 0},        # pct, zero -> dropped
		{"id": "of_embers",    "value_min": 0, "value_max": 0, "value": 0}, # range zero -> dropped
		{"id": "of_sharpness", "value_min": 1, "value_max": 3, "value": 2}, # range non-zero -> kept
	]
	var lines: Array = AffixSystem.format_affix_lines(affixes)
	# The +0 sub-string must never appear in any rendered row.
	for line in lines:
		assert_false(String(line).contains("+0 "),
			"format_affix_lines emitted a +0 flat row: " + String(line))
		assert_false(String(line).contains("+0%"),
			"format_affix_lines emitted a +0pct row: " + String(line))
	# At least one of_might row should exist (sanity: filter didn't drop everything).
	var saw_might: bool = false
	for line in lines:
		if String(line).contains("Strength") or String(line).contains("Str"):
			saw_might = true
			break
	assert_true(saw_might, "non-zero of_might survived the zero-filter")

func test_spell_items_canonical_primary_stat_per_archetype() -> void:
	# S3.6 / A01 F-SPELL-03 — every spell item of a given archetype must
	# declare the SAME primary_stat. Audit found ~50% of items in each
	# archetype overrode the default; the flatten pass aligned them.
	# Lock the contract.
	var arch_defaults := {
		"spell_fireball": "int", "spell_axes": "str",
		"spell_holy_beam": "str", "spell_chain_lightning": "dex",
		"spell_frost_nova": "int", "spell_magic_dart": "dex",
		"spell_iron_shot": "str", "spell_sandblast": "str",
		"spell_drain": "int", "spell_shatter": "str",
	}
	var f := FileAccess.open("res://data/items.json", FileAccess.READ)
	assert_not_null(f, "items.json readable")
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	assert_eq(typeof(parsed), TYPE_DICTIONARY, "items.json parses")
	var data: Dictionary = parsed
	var mismatches: Array = []
	for it in data.get("items", []):
		if String(it.get("slot", "")) != "spell":
			continue
		var bt: String = String(it.get("base_type", ""))
		if not arch_defaults.has(bt):
			continue
		if not it.has("primary_stat"):
			continue
		if String(it["primary_stat"]) != String(arch_defaults[bt]):
			mismatches.append("%s declares primary_stat=%s, archetype=%s" %
				[String(it.get("id", "?")), String(it["primary_stat"]), bt])
	assert_eq(mismatches.size(), 0,
		"spell items must match archetype primary_stat. Drift: %s" % str(mismatches.slice(0, 5)))

func test_of_multicast_floor_no_longer_rolls_zero() -> void:
	# Pre-fix common/uncommon of_multicast tiers were [0,0]/[0,0],
	# producing "+0 Spell Projectile" tooltip lines (PLAYTEST #9).
	# Post-fix all five tiers floor at [1,1] minimum. The affix def
	# itself is the contract — no roll math required.
	var def: Dictionary = AffixSystem.get_affix_def("of_multicast")
	assert_false(def.is_empty(), "of_multicast still exists post-fix")
	for tier in def.get("tiers", []):
		assert_true(typeof(tier) == TYPE_ARRAY and tier.size() == 2,
			"of_multicast tier malformed: %s" % str(tier))
		var lo: int = int(tier[0])
		var hi: int = int(tier[1])
		assert_gte(lo, 1, "of_multicast tier floor < 1: %s" % str(tier))
		assert_gte(hi, 1, "of_multicast tier ceiling < 1: %s" % str(tier))

func test_dual_wield_class_deferred() -> void:
	# S6 cuts (synthesis §5.1, a01 F-DUAL-01) — the only weapon_class:"dual"
	# base (gyre) was deleted; dual-wield is deferred until 10+ bases ship
	# at once. Lock against accidental re-introduction.
	var f := FileAccess.open("res://data/items.json", FileAccess.READ)
	assert_not_null(f, "items.json readable")
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	assert_eq(typeof(parsed), TYPE_DICTIONARY, "items.json parses")
	var data: Dictionary = parsed
	var dual_items: Array = []
	for it in data.get("items", []):
		if String(it.get("weapon_class", "")) == "dual":
			dual_items.append(String(it.get("id", "?")))
	assert_eq(dual_items.size(), 0,
		"weapon_class:\"dual\" items present (re-add only if 10+ bases ship): %s"
		% str(dual_items))

func test_t3_axe_outliers_flattened() -> void:
	# S6.1 (a01 F-WEP-02) — five t3 axe/halberd/dire-flail outliers
	# previously sat at DPS=85, ~30% above the t3 2H median (74). They
	# made every t3 1H non-axe redundant. Flattened to ~74 DPS to restore
	# tier-curve sanity. Lock against re-tuning.
	var f := FileAccess.open("res://data/items.json", FileAccess.READ)
	assert_not_null(f, "items.json readable")
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	var data: Dictionary = parsed
	var seen := {}
	var targets := ["steel_battle_axe", "steel_broad_axe", "dire_flail", "steel_halberd"]
	for it in data.get("items", []):
		var iid: String = String(it.get("id", ""))
		if iid in targets:
			var dmin: float = float(it.get("damage_min", 0))
			var dmax: float = float(it.get("damage_max", 0))
			var sp: float = float(it.get("speed", 1.0))
			var dps: float = (dmin + dmax) / 2.0 / sp
			seen[iid] = dps
	for tgt in targets:
		assert_true(seen.has(tgt), "missing t3 outlier %s" % tgt)
		assert_lt(float(seen.get(tgt, 999.0)), 80.0,
			"t3 outlier %s DPS %.1f exceeds flattened ceiling 80"
			% [tgt, float(seen.get(tgt, 999.0))])

func test_magic_dart_retagged_dex() -> void:
	# S6.7 (a03 §A.4, a01 F-SPELL-02) — spell_magic_dart re-tagged INT → DEX
	# to close the dagger-Halfling-spam archetype gap. t5 mid bumped to 22.
	var f := FileAccess.open("res://data/items.json", FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	var data: Dictionary = parsed
	var saw_t5 := false
	for it in data.get("items", []):
		if String(it.get("base_type", "")) != "spell_magic_dart":
			continue
		# Every magic_dart item that declares primary_stat must be DEX.
		if it.has("primary_stat"):
			assert_eq(String(it["primary_stat"]), "dex",
				"magic_dart item %s primary_stat = %s (expected dex)"
				% [String(it.get("id", "?")), String(it["primary_stat"])])
		if int(it.get("item_tier", 0)) == 5:
			saw_t5 = true
			var mid: float = (float(it.get("damage_min", 0)) + float(it.get("damage_max", 0))) / 2.0
			assert_gte(mid, 21.0,
				"t5 magic_dart %s mid damage %.1f below 21 (expect ≥22)"
				% [String(it.get("id", "?")), mid])
	assert_true(saw_t5, "expected at least one t5 spell_magic_dart item")
