extends GutTest

# Tests for LootFactory — the loot rolling + item construction module
# extracted from dungeon.gd 2026-06-09. Same-seed determinism is the
# load-bearing invariant: /duel and /sweep paired comparisons depend
# on it, and the audit's recommended regression net for the extraction
# is "same RNG seed → same rolls + rarity distribution within
# tolerance." These tests pin both.

var _items_db: Dictionary = {}

func before_all() -> void:
	# Load items.json the same way dungeon.gd does so the test exercises
	# the real corpus (309 items at extraction time). Without it the
	# pick_loot_id pools are empty and the determinism check is vacuous.
	var f := FileAccess.open("res://data/items.json", FileAccess.READ)
	assert_not_null(f, "items.json opens")
	if f == null:
		return
	var raw: Variant = JSON.parse_string(f.get_as_text())
	assert_eq(typeof(raw), TYPE_DICTIONARY, "items.json parses as dict")
	for it in raw.get("items", []):
		_items_db[String(it.id)] = it

func test_clamp_rarity_to_tier_caps_at_tier_ceiling() -> void:
	# T1 caps at uncommon, T3 at epic, T5 unrestricted.
	assert_eq(LootFactory.clamp_rarity_to_tier("legendary", 1), "uncommon",
		"T1 clamps legendary down to uncommon")
	assert_eq(LootFactory.clamp_rarity_to_tier("epic", 3), "epic",
		"T3 lets epic through")
	assert_eq(LootFactory.clamp_rarity_to_tier("legendary", 3), "epic",
		"T3 clamps legendary down to epic")
	assert_eq(LootFactory.clamp_rarity_to_tier("legendary", 5), "legendary",
		"T5 lets legendary through")
	assert_eq(LootFactory.clamp_rarity_to_tier("common", 5), "common",
		"common always allowed")

func test_salvage_value_known_rarities() -> void:
	# Locked-in baseline; shop.gd's sell-price formula and dungeon.gd's
	# auto-salvage both depend on these exact numbers.
	assert_eq(LootFactory.salvage_value("common"), 2)
	assert_eq(LootFactory.salvage_value("uncommon"), 6)
	assert_eq(LootFactory.salvage_value("rare"), 18)
	assert_eq(LootFactory.salvage_value("epic"), 60)
	assert_eq(LootFactory.salvage_value("legendary"), 200)
	# Unknown rarity falls through to 1, not 0 — preserving prior
	# .get(rarity, 1) behavior in dungeon.gd.
	assert_eq(LootFactory.salvage_value("nonsense"), 1)

func test_hue_to_stat_lean_color_wheel() -> void:
	assert_eq(LootFactory.hue_to_stat_lean(0.0), "atk", "0° red → atk")
	assert_eq(LootFactory.hue_to_stat_lean(45.0), "hp", "45° orange → hp")
	assert_eq(LootFactory.hue_to_stat_lean(80.0), "atk_speed", "80° yellow → atk_speed")
	assert_eq(LootFactory.hue_to_stat_lean(120.0), "haste", "120° green → haste")
	assert_eq(LootFactory.hue_to_stat_lean(180.0), "def", "180° cyan → def")
	assert_eq(LootFactory.hue_to_stat_lean(220.0), "regen", "220° blue → regen")
	assert_eq(LootFactory.hue_to_stat_lean(280.0), "crit", "280° purple → crit")
	assert_eq(LootFactory.hue_to_stat_lean(320.0), "atk", "320° magenta → atk")
	# Negative wraps to positive (-30° → 330° is in the magenta band ≥300°
	# which maps back to atk).
	assert_eq(LootFactory.hue_to_stat_lean(-30.0), "atk",
		"-30° wraps to 330° → atk (magenta wraps to red family)")

func test_roll_rarity_seeded_determinism() -> void:
	# Same seed + same args → byte-identical sequence. Foundation of
	# /duel and /sweep paired comparisons.
	var rng_a := RandomNumberGenerator.new()
	var rng_b := RandomNumberGenerator.new()
	rng_a.seed = 42
	rng_b.seed = 42
	for i in 50:
		var a: String = LootFactory.roll_rarity(rng_a, 3, 5, false, 0.0, 0.0)
		var b: String = LootFactory.roll_rarity(rng_b, 3, 5, false, 0.0, 0.0)
		assert_eq(a, b, "roll %d matches" % i)

func test_roll_rarity_distribution_matches_thresholds() -> void:
	# At T5/floor 1/no bonuses, baseline thresholds are r<0.02 legendary,
	# 0.02-0.10 epic, 0.10-0.25 rare, 0.25-0.55 uncommon, else common.
	# T5 ceiling lets all rarities through. Run N=2000 to bound the
	# binomial noise: legendary expected ~40 with stddev ~6, so we use
	# a generous tolerance band.
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var counts: Dictionary = {"common": 0, "uncommon": 0, "rare": 0, "epic": 0, "legendary": 0}
	var n: int = 2000
	for i in n:
		# T5, floor 1, no boss, no bonuses → baseline distribution.
		# floor_bonus is 0 (current_floor=1), tier_bonus is 0.20 (T5).
		# Effective r = randf() - 0.20, so we expect rarity to skew up
		# vs the bare table — every random in [0, 0.20) maps to legendary.
		var rarity: String = LootFactory.roll_rarity(rng, 5, 1, false, 0.0, 0.0)
		counts[rarity] = int(counts[rarity]) + 1
	# Expected proportions with floor=1, tier_bonus=0.20:
	#   legendary: r<0.02+0.20=0.22 → ~22%
	#   epic:      0.22..0.30        → ~8%
	#   rare:      0.30..0.45        → ~15%
	#   uncommon:  0.45..0.75        → ~30%
	#   common:    0.75..1.0         → ~25% (the remaining 0.25 floor)
	# Wide tolerance bands (±5%) so flake is kept low.
	var p_leg: float = float(counts.legendary) / n
	var p_epic: float = float(counts.epic) / n
	var p_rare: float = float(counts.rare) / n
	var p_unc: float = float(counts.uncommon) / n
	var p_com: float = float(counts.common) / n
	assert_almost_eq(p_leg, 0.22, 0.05, "legendary ~22%% (got %.3f)" % p_leg)
	assert_almost_eq(p_epic, 0.08, 0.04, "epic ~8%% (got %.3f)" % p_epic)
	assert_almost_eq(p_rare, 0.15, 0.05, "rare ~15%% (got %.3f)" % p_rare)
	assert_almost_eq(p_unc, 0.30, 0.05, "uncommon ~30%% (got %.3f)" % p_unc)
	assert_almost_eq(p_com, 0.25, 0.05, "common ~25%% (got %.3f)" % p_com)

func test_roll_rarity_t1_clamps_to_uncommon() -> void:
	# T1 source-tier should never let anything past uncommon, even with
	# blessing/mod stacking pushing the roll into the legendary band.
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	for i in 200:
		# Big bonuses → roll always hits the legendary path before clamp.
		var rarity: String = LootFactory.roll_rarity(rng, 1, 1, false, 0.5, 0.5)
		assert_true(LootFactory.RARITY_RANK[rarity] <= 1,
			"T1 caps at uncommon (got %s)" % rarity)

func test_roll_rarity_boss_path_skews_high() -> void:
	# Boss roll: 50% legendary, 35% epic, 15% rare (subject to tier clamp).
	# At T5 (no clamp) we expect predominantly legendary.
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var leg: int = 0
	var n: int = 400
	for i in n:
		if LootFactory.roll_rarity(rng, 5, 1, true, 0.0, 0.0) == "legendary":
			leg += 1
	# 50% expected; bind to ±10% for stability.
	var p: float = float(leg) / n
	assert_almost_eq(p, 0.5, 0.10, "boss legendary ~50%% (got %.3f)" % p)

func test_roll_rarity_with_bias_seeded_determinism() -> void:
	var rng_a := RandomNumberGenerator.new()
	var rng_b := RandomNumberGenerator.new()
	rng_a.seed = 808
	rng_b.seed = 808
	for i in 50:
		var a: String = LootFactory.roll_rarity_with_bias(rng_a, 4, 3, 1)
		var b: String = LootFactory.roll_rarity_with_bias(rng_b, 4, 3, 1)
		assert_eq(a, b, "biased roll %d matches" % i)

func test_pick_loot_id_seeded_determinism() -> void:
	# Critical: paired duel/sweep relies on this. Same seed + same
	# items_db + same rarity + same allow_spell + same dropped_uniques
	# state → same picked id.
	if _items_db.is_empty():
		gut.p("items_db empty — skip")
		return
	var rng_a := RandomNumberGenerator.new()
	var rng_b := RandomNumberGenerator.new()
	rng_a.seed = 555
	rng_b.seed = 555
	var dropped_a: Array = []
	var dropped_b: Array = []
	for i in 30:
		var a: String = LootFactory.pick_loot_id(rng_a, "common", _items_db, 1, dropped_a, false)
		var b: String = LootFactory.pick_loot_id(rng_b, "common", _items_db, 1, dropped_b, false)
		assert_eq(a, b, "pick %d matches" % i)

func test_pick_loot_id_excludes_spells_when_disallowed() -> void:
	if _items_db.is_empty():
		gut.p("items_db empty — skip")
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	var dropped: Array = []
	# Run plenty of picks at T1 (commons have positive drop_weight there;
	# they fade to 0 at T5 in items.json). allow_spell=false. Verify
	# none of them are spell-slot items. Always-asserts so the test
	# can't pass vacuously when picks return "".
	var picks: int = 0
	for i in 200:
		var picked: String = LootFactory.pick_loot_id(rng, "common", _items_db, 1, dropped, false)
		if picked == "":
			continue
		picks += 1
		var item: Dictionary = _items_db[picked]
		assert_ne(String(item.get("slot", "")), "spell",
			"allow_spell=false → no spell drops (got %s)" % picked)
	assert_gt(picks, 50, "got enough picks to be meaningful (%d)" % picks)

func test_pick_loot_id_records_unique_in_dropped() -> void:
	if _items_db.is_empty():
		gut.p("items_db empty — skip")
		return
	# Find a unique legendary item to test against.
	var unique_id: String = ""
	for id in _items_db.keys():
		var item: Dictionary = _items_db[id]
		if bool(item.get("unique", false)) and String(item.get("rarity", "")) == "legendary":
			unique_id = id
			break
	if unique_id == "":
		gut.p("no unique legendary in items_db — skip")
		return
	# Spam picks until we hit the unique once. Then it must be in
	# run_dropped_uniques and never picked again.
	var rng := RandomNumberGenerator.new()
	rng.seed = 31337
	var dropped: Array = []
	var saw_unique: bool = false
	for i in 5000:
		var picked: String = LootFactory.pick_loot_id(rng, "legendary", _items_db, 5, dropped, false)
		if picked == unique_id:
			saw_unique = true
			assert_true(dropped.has(unique_id), "unique recorded after pick")
			break
	if not saw_unique:
		gut.p("did not roll the unique in 5000 attempts — non-deterministic skip")
		return
	# Subsequent picks should never return the recorded unique.
	for i in 1000:
		var picked: String = LootFactory.pick_loot_id(rng, "legendary", _items_db, 5, dropped, false)
		assert_ne(picked, unique_id,
			"unique excluded from subsequent rolls (got %s on pick %d)" % [picked, i])

func test_create_item_instance_seeded_determinism() -> void:
	if _items_db.is_empty():
		gut.p("items_db empty — skip")
		return
	# Pick a base id that exists in the db. Use a common gear item so the
	# affix/tint/quality/enchant pipeline is fully exercised.
	var base_id: String = ""
	for id in _items_db.keys():
		var item: Dictionary = _items_db[id]
		if String(item.get("rarity", "")) == "common" and String(item.get("slot", "")) == "weapon":
			base_id = id
			break
	if base_id == "":
		gut.p("no common weapon in items_db — skip")
		return
	var rng_a := RandomNumberGenerator.new()
	var rng_b := RandomNumberGenerator.new()
	rng_a.seed = 2025
	rng_b.seed = 2025
	var inst_a: Dictionary = LootFactory.create_item_instance(rng_a, base_id, _items_db)
	var inst_b: Dictionary = LootFactory.create_item_instance(rng_b, base_id, _items_db)
	# instance_id includes Time.get_unix_time_from_system() so it'll
	# match within the same wall-clock second; compare every other field.
	assert_eq(inst_a.get("base_id"), inst_b.get("base_id"), "base_id matches")
	assert_eq(JSON.stringify(inst_a.get("affixes", [])),
			   JSON.stringify(inst_b.get("affixes", [])),
			   "affixes byte-identical")
	assert_eq(inst_a.get("meta_rarity", "_none"),
			   inst_b.get("meta_rarity", "_none"),
			   "meta_rarity matches")
	assert_eq(inst_a.get("quality", "_none"),
			   inst_b.get("quality", "_none"),
			   "quality matches")
	assert_eq(JSON.stringify(inst_a.get("tint", {})),
			   JSON.stringify(inst_b.get("tint", {})),
			   "tint matches")
	assert_eq(inst_a.get("enchant", "_none"),
			   inst_b.get("enchant", "_none"),
			   "enchant matches")
	assert_eq(inst_a.get("enchant_combo", "_none"),
			   inst_b.get("enchant_combo", "_none"),
			   "enchant_combo matches")

func test_create_item_instance_required_keys() -> void:
	if _items_db.is_empty():
		gut.p("items_db empty — skip")
		return
	var base_id: String = _items_db.keys()[0]
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var inst: Dictionary = LootFactory.create_item_instance(rng, base_id, _items_db)
	assert_true(inst.has("base_id"), "has base_id")
	assert_true(inst.has("instance_id"), "has instance_id")
	assert_true(inst.has("affixes"), "has affixes")
	assert_eq(String(inst.base_id), base_id, "base_id round-trips")
