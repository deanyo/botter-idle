extends GutTest

# Combat tests for Actor.resolve_swing + take_damage. Locks the
# 2026-06-08 combat-correctness fixes:
#   - Avoidance gates (evasion / footwork / reflective) fire ONCE per
#     swing, not once per typed component.
#   - Thorns / crystal returns aggregate over a single swing (no
#     multi-emit `died` on hybrid hits).
#   - Single-hit take_damage callers (spells, projectiles, splash)
#     route through resolve_swing and pick up the same semantics.
#   - Spell hits with element=fire vs fire_res defender mitigate via
#     both the worn tag AND the resistances dict.
#
# Run via:
#   /Applications/Godot.app/Contents/MacOS/Godot --path project --headless \
#       -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit
#
# Surfaced through tools/check_before_commit.sh.

const _StubAttacker := preload("res://tests/_stub_attacker.gd")
const _StubDefender := preload("res://tests/_stub_defender.gd")
const _StubBotDefender := preload("res://tests/_stub_bot_defender.gd")

func before_all() -> void:
	# Deterministic RNG so evasion / footwork / reflective rolls are
	# reproducible across runs.
	seed(0xB077E5)

# ---------------------------------------------------------------------
# take_damage typed-mitigation
# ---------------------------------------------------------------------

func test_physical_armor_subtracts() -> void:
	# Physical damage keeps the legacy flat-armor subtract. The S2
	# additive cap (a10 §5.2) governs the worn-tag DR + element resist
	# layers; armor sits outside it so early-game defenses still feel
	# right (otherwise a 3-dmg rat vs 0-armor fresh-save bot mitigates
	# to 2 instead of 1 via floor — doubling time-to-die).
	var d: Actor = _make_defender(100, 5, [], {})
	var dealt: int = d.take_damage(20, null, "physical")
	assert_eq(dealt, 15, "physical armor subtracts (20-5)")
	assert_eq(d.hp, 85, "physical armor — hp drop")
	d.free()

func test_fire_resist_halves_typed_damage() -> void:
	# 50% fire resistance, no attacker (no fire_res tag double-cut).
	var d: Actor = _make_defender(100, 0, [], {"fire": 50.0})
	var dealt: int = d.take_damage(40, null, "fire")
	assert_eq(dealt, 20, "fire resist 50% halves typed damage")
	d.free()

func test_harm_amplifies_incoming() -> void:
	var d: Actor = _make_defender(100, 0, ["harm"], {})
	var dealt: int = d.take_damage(20, null, "physical")
	assert_eq(dealt, 25, "harm +25% on incoming")
	d.free()

# ---------------------------------------------------------------------
# Avoidance gates — once per swing, not once per typed component
# ---------------------------------------------------------------------

func test_evasion_full_dodge_single_hit() -> void:
	var d: Actor = _make_defender(100, 0, [], {})
	d.evasion = 100.0
	var dealt: int = d.take_damage(50, null, "physical")
	assert_eq(dealt, 0, "100% evasion → 0 damage (single hit)")
	assert_eq(d.hp, 100, "100% evasion — hp unchanged")
	d.free()

func test_hybrid_swing_single_evasion_roll() -> void:
	# Defender with 50% evasion taking 200 hybrid swings.
	# Pre-fix (3 independent rolls @ 50%) → ~87.5% land = ~175 hits/200.
	# Post-fix (1 roll @ 50%) → ~50% land = ~100 hits/200.
	# Threshold: post-fix never exceeds ~140; pre-fix never lower.
	var attacker: _StubAttacker = _StubAttacker.new()
	attacker.weapon_tags = []
	attacker.set("damage_min", 10)
	attacker.set("damage_max", 10)
	var typed := {"physical": 4, "fire": 3, "cold": 3}
	var hits: int = 0
	for _i in 200:
		var d: _StubDefender = _make_defender(1000, 0, [], {})
		d.evasion = 50.0
		var dealt: int = d.resolve_swing(typed, attacker)
		if dealt > 0:
			hits += 1
		d.free()
	assert_lt(hits, 141,
		"hybrid evasion expected ~100 hits, got %d / 200 (>=141 = pre-fix multi-roll)" % hits)
	attacker.free()

# ---------------------------------------------------------------------
# Returns aggregate over swing
# ---------------------------------------------------------------------

func test_thorns_aggregates_over_swing() -> void:
	# Hybrid 20+10+10 = 40 dealt, thorns 15%.
	# Aggregated: round(40 × 0.15) = 6.
	# Split (pre-fix): round(20×0.15)+round(10×0.15)+round(10×0.15) = 3+2+2 = 7.
	var attacker: _StubAttacker = _StubAttacker.new()
	attacker.hp = 1000
	attacker.max_hp = 1000
	attacker.weapon_tags = []
	var d: Actor = _make_defender(1000, 0, ["thorns"], {})
	var typed := {"physical": 20, "fire": 10, "cold": 10}
	var dealt: int = d.resolve_swing(typed, attacker)
	assert_eq(dealt, 40, "thorns swing — full damage dealt")
	assert_eq(attacker.hp, 1000 - 6, "thorns aggregates — attacker took 6")
	d.free()
	attacker.free()

func test_crystal_aggregates_over_swing() -> void:
	# 40 dealt × 5% = 2, one chunk not three.
	var attacker: _StubAttacker = _StubAttacker.new()
	attacker.hp = 1000
	attacker.max_hp = 1000
	attacker.weapon_tags = []
	var d: Actor = _make_defender(1000, 0, ["crystal"], {})
	var typed := {"physical": 20, "fire": 10, "cold": 10}
	d.resolve_swing(typed, attacker)
	assert_eq(attacker.hp, 1000 - 2, "crystal aggregates — attacker took 2")
	d.free()
	attacker.free()

func test_died_signal_fires_once_on_hybrid_kill() -> void:
	# Pre-fix: thorns/crystal returns fired per-component. If first
	# chunk killed the attacker, subsequent chunks could re-emit died.
	# Post-fix: aggregated single chunk; second source (crystal) sees
	# is_alive=false guard.
	var attacker: _StubAttacker = _StubAttacker.new()
	attacker.hp = 5
	attacker.max_hp = 5
	attacker.weapon_tags = []
	var counter := {"n": 0}
	attacker.died.connect(func(_a): counter.n += 1)
	var d: Actor = _make_defender(1000, 0, ["thorns", "crystal"], {})
	var typed := {"physical": 50, "fire": 30, "cold": 30}
	d.resolve_swing(typed, attacker)
	assert_eq(counter.n, 1, "hybrid thorn-kill emits died ONCE")
	assert_false(attacker.is_alive, "attacker is dead")
	d.free()
	attacker.free()

# ---------------------------------------------------------------------
# Spell-side element piping
# ---------------------------------------------------------------------

func test_spell_fire_vs_fire_res_tag_and_resistance_dict() -> void:
	# S2 cap rules (a10 §5.2): mitigation layers additively sum, then
	# clamp at +90%. Defender carries fire_res tag (+50% vs attacker's
	# fire) AND 50% fire resistance via dict (+50%). Sum = 1.0 → cap
	# 0.90 → 100 × 0.10 = 10 dealt. Pre-cap multiplied: tag halves to
	# 50 → dict halves to 25. The cap intentionally compresses the
	# overlap so a single defensive identity can't trivialize fire.
	var attacker: _StubAttacker = _StubAttacker.new()
	attacker.weapon_tags = ["fire"]
	var d: Actor = _make_defender(1000, 0, ["fire_res"], {"fire": 50.0})
	var dealt: int = d.take_damage(100, attacker, "fire")
	assert_eq(dealt, 10, "fire vs fire_res tag + resistance dict (capped 90%)")
	d.free()
	attacker.free()

func test_damage_type_for_element_mapping() -> void:
	assert_eq(SpellData.damage_type_for_element("thunderous"), "lightning",
		"thunderous → lightning")
	assert_eq(SpellData.damage_type_for_element("fire"), "fire", "fire → fire")
	assert_eq(SpellData.damage_type_for_element(""), "physical", "empty → physical")

func test_lightning_resistance_halves_thunderous() -> void:
	var d: Actor = _make_defender(1000, 0, [], {"lightning": 50.0})
	var dealt: int = d.take_damage(80, null, "lightning")
	assert_eq(dealt, 40, "lightning resistance halves spell damage")
	d.free()

# ---------------------------------------------------------------------
# S2 cap rules (a10 §5.2): defensive mitigation cap +90%
# ---------------------------------------------------------------------

func test_defensive_mitigation_caps_at_90_pct() -> void:
	# Stack 75% lightning resist + 50% acrobat (low HP) + 25%
	# willpower vs an arcane attacker. Pre-cap multiplicative sum:
	# 0.25 × 0.83 × 0.75 = 0.156 → 84.4% mitigation. Additive sum:
	# 0.75 + 0.17 + 0.25 = 1.17 → cap 0.90 → 10% lands. The cap
	# enforces "no defensive stack ever drops damage below 10%".
	var attacker: _StubAttacker = _StubAttacker.new()
	attacker.weapon_tags = ["arcane"]
	var d: _StubDefender = _make_defender(100, 0, ["acrobat", "willpower"], {"lightning": 75.0})
	# Acrobat triggers below 30% HP — drop hp first.
	d.hp = 20
	var dealt: int = d.take_damage(100, attacker, "lightning")
	assert_eq(dealt, 10, "stacked DR clamps at 90% mitigation (10 of 100)")
	d.free()
	attacker.free()

func test_harm_can_amplify_past_baseline() -> void:
	# harm contributes -0.25; mit_sum can go negative. Floor of -0.50
	# means a hot stack of harm (alone or compounding with future
	# mods) can amplify damage taken up to ×1.50 — but not past it.
	var d: Actor = _make_defender(100, 0, ["harm"], {})
	var dealt: int = d.take_damage(20, null, "physical")
	assert_eq(dealt, 25, "harm amplifies +25% (mit_sum -0.25)")
	d.free()

# ---------------------------------------------------------------------
# S8 (a08 §A1) — enemies.json declares resistances by thematic group.
# These tests guard the data shape (the file contains the entries we
# expect) and the math shape (negative values amplify, positive values
# mitigate, both honoring the additive +90% / -50% mit_sum cap).
# ---------------------------------------------------------------------

func test_enemy_resistances_data_present() -> void:
	# Guard against accidentally dropping the resistance dict during
	# future enemies.json edits. ~45 enemies are tagged in S8; if the
	# count drops below the audit floor, we've regressed.
	var enemies: Dictionary = ItemsDb.enemies()
	var with_res: int = 0
	for id in enemies.keys():
		var def: Dictionary = enemies[id]
		var r: Variant = def.get("resistances", null)
		if typeof(r) == TYPE_DICTIONARY and not (r as Dictionary).is_empty():
			with_res += 1
	assert_gte(with_res, 30, "≥30 enemies declare resistances (S8 broken-combo signal)")
	# Spot-check the canonical anchor entries — these are load-bearing
	# for the Forge / Glacier / Crypt themed-punishment loop.
	assert_eq(int(enemies["fire_dragon"]["resistances"].get("fire", 0)), 75,
		"fire_dragon: +75 fire (Forge flagship)")
	assert_eq(int(enemies["fire_dragon"]["resistances"].get("cold", 0)), -40,
		"fire_dragon: -40 cold (vulnerability lane)")
	assert_eq(int(enemies["ice_dragon"]["resistances"].get("cold", 0)), 75,
		"ice_dragon: +75 cold (Glacier flagship)")
	assert_eq(int(enemies["lich"]["resistances"].get("holy", 0)), -50,
		"lich: -50 holy (anti-undead lane)")
	assert_eq(int(enemies["jelly"]["resistances"].get("poison", 0)), 75,
		"jelly: +75 poison (slime profile)")
	assert_eq(int(enemies["troll"]["resistances"].get("fire", 0)), -50,
		"troll: -50 fire (DCSS regen-stops-on-fire pattern)")

func test_enemy_resistance_negative_amplifies_via_mit_cap() -> void:
	# Negative resistance value contributes negatively to mit_sum, which
	# is clamped to [-0.50, +0.90]. -40% fire alone → 40% damage uplift.
	# Confirms the -40 cold values on Forge fire-creatures actually
	# punish a cold-mage who walks into the wrong biome.
	var d: Actor = _make_defender(100, 0, [], {"cold": -40.0})
	var dealt: int = d.take_damage(50, null, "cold")
	assert_eq(dealt, 70, "cold-vulnerable defender takes +40% from cold")
	d.free()

func test_enemy_resistance_positive_caps_at_75_pct() -> void:
	# The audit caps single-element resist at +75 to keep player counter-
	# play viable (a08 §A3 — fully-stacked anti-fire still chips 25%).
	# Test confirms the math: 75% lone resist → 25% lands.
	var d: Actor = _make_defender(100, 0, [], {"fire": 75.0})
	var dealt: int = d.take_damage(80, null, "fire")
	assert_eq(dealt, 20, "fire 75% resist → 25% of 80 = 20")
	d.free()

# ---------------------------------------------------------------------
# S4 Tier-1 affix mechanics (a02 P-8/9/10/11/12/13/15/16/19/27/28
# rescoped per a10 §3.2). Defender-side hooks (sundering, bloodletting)
# are testable without Bot stubs; attacker-side ephemeral lanes go
# through stat_calc tests + the /grind validation in S4 §V10/V13.
# ---------------------------------------------------------------------

func test_s4_of_sundering_reduces_physical_armor() -> void:
	# Defender at armor=20 takes 50 raw physical: post-mit (mit_sum=0) →
	# 50 - 20 = 30. Apply a 7-amount sunder stack: armor reduced to 13,
	# 50 - 13 = 37. Confirms the sunder hook routes the per-stack value
	# into the physical-armor-subtract branch in _apply_typed_damage.
	var d: Actor = _make_defender(200, 20, [], {})
	var baseline: int = d.take_damage(50, null, "physical")
	assert_eq(baseline, 30, "baseline physical: 50 raw - 20 armor = 30 dealt")
	var d2: Actor = _make_defender(200, 20, [], {})
	d2.add_sunder_stack(7)
	var sundered: int = d2.take_damage(50, null, "physical")
	assert_eq(sundered, 37, "sundered 7: 50 raw - (20-7) armor = 37 dealt")
	d.free()
	d2.free()

func test_s4_of_sundering_caps_at_2_stacks() -> void:
	# Per a10 P-11 rescope, sunder stacks cap at 2. A third
	# add_sunder_stack call should NOT increase the amount past stack#2.
	var d: Actor = _make_defender(200, 100, [], {})
	d.add_sunder_stack(10)  # stack 1
	d.add_sunder_stack(10)  # stack 2 — cap reached
	d.add_sunder_stack(10)  # stack 3 — should be no-op
	assert_eq(d._sunder_stacks, 2, "sunder stacks cap at 2")
	assert_eq(d._sunder_amount, 20, "sunder amount = 2 stacks × 10 = 20")
	d.free()

func test_s4_of_sundering_expires_after_duration() -> void:
	# Sunder expiry is checked lazily on next read. Manually set the
	# expiry to the past; the next physical hit should ignore the
	# sunder (full armor applies).
	var d: Actor = _make_defender(200, 20, [], {})
	d.add_sunder_stack(15)
	# Force expiry: rewind the expires_at marker.
	d._sunder_expires_at = 0.0
	var dealt: int = d.take_damage(50, null, "physical")
	assert_eq(dealt, 30, "expired sunder: 50 raw - 20 armor = 30 (full armor)")
	# State auto-cleared after the read.
	assert_eq(d._sunder_amount, 0, "sunder amount reset on expiry")
	assert_eq(d._sunder_stacks, 0, "sunder stacks reset on expiry")
	d.free()

func test_s5_petrify_gates_on_physical_only() -> void:
	# Stoneflesh Plate (Gargoyle anchor, a10 5.13.B rescope) carries
	# `petrify` worn-tag — -25% PHYSICAL DR while stationary. The
	# implementation guards on damage_type=="physical" AND self is Bot,
	# so a non-Bot with the tag should NOT mitigate elemental hits.
	# Stub defender path proves the type-gate without needing a real
	# Bot — fire damage must not pick up the petrify reduction here.
	var d: Actor = _make_defender(100, 0, ["petrify"], {})
	var dealt_fire: int = d.take_damage(40, null, "fire")
	assert_eq(dealt_fire, 40, "petrify must not reduce non-physical hits")
	d.free()
	# Same defender hit physically also doesn't fire petrify (stub
	# isn't a Bot — `self is Bot` short-circuits in actor.gd). The
	# point of the test: petrify never bleeds through on stubs, so
	# the field can be tested via Bot-instance integration tests.
	var d2: Actor = _make_defender(100, 0, ["petrify"], {})
	var dealt_phys: int = d2.take_damage(40, null, "physical")
	assert_eq(dealt_phys, 40, "petrify gated on `self is Bot` — stub picks up no DR")
	d2.free()

func test_s5_anchors_present_in_items_db() -> void:
	# Sanity check: the 30 race-anchor uniques shipped with S5 must
	# resolve in ItemsDb. If sync_items.py wasn't run after editing
	# items.json the editor / drop tables won't see them either.
	ItemsDb.preload_all()
	var db: Dictionary = ItemsDb.items()
	var expected: Array = [
		"spriggan_leaf_boots", "spriggan_fae_cloak", "spriggan_wisp_lance",
		"minotaur_horn_helm", "minotaur_champion_blade",
		"naga_coiled_ring", "naga_frostfang_ring",
		"tengu_wind_cloak", "tengu_skystriker_helm",
		"troll_hide_armor", "troll_crusher",
		"octopode_coral_ring", "octopode_eight_amulet",
		"demonspawn_hellsigil_brand", "demonspawn_ashen_crown",
		"vampire_sangromancer_locket", "vampire_nightshade_cloak",
		"vampire_splintered_tooth",
		"mummy_tomb_wrappings", "mummy_relic_amulet",
		"orc_beoghs_banner", "orc_raider_axe",
		"elf_grimoire_gloves", "elf_spire_tome",
		"gargoyle_stoneflesh_plate", "gargoyle_granite_amulet",
		"halfling_luck_charm", "halfling_quiet_knife",
		"kobold_scavenger_coat", "kobold_throwing_hand",
	]
	for aid in expected:
		assert_true(db.has(aid), "ItemsDb missing race anchor: %s" % aid)
		var item: Dictionary = db[aid]
		assert_true(item.has("requires_innate_tag"),
			"%s must declare requires_innate_tag" % aid)
		assert_true(bool(item.get("unique", false)),
			"%s must be unique:true" % aid)

func test_s4_of_bloodletting_applies_bleeding_status() -> void:
	# add_bloodletting routes through _apply_dot_status with the
	# "bleeding" id and sets up the per-tick payload. Confirms the
	# bleeding status is registered, has the expected per-tick amount,
	# and IS NOT gated by poison_res / fire_res (bleed is physical).
	var d: Actor = _make_defender(200, 0, ["poison_res", "fire_res"], {})
	d.add_bloodletting(5)
	assert_true(d.has_status("bleeding"),
		"bleeding status registered (not gated by poison/fire resists)")
	var entry: Dictionary = d._statuses["bleeding"]
	var dot: Dictionary = entry.get("dot", {})
	assert_eq(int(dot.get("amount", 0)), 5, "bleed per-tick = 5")
	assert_almost_eq(float(dot.get("interval", 0)), 1.0, 0.001, "bleed interval = 1.0s")
	d.free()

# ---------------------------------------------------------------------
# S9 — crit_multiplier_pct + block_chance / block_amount
# ---------------------------------------------------------------------

func test_s9_block_full_negates_when_amount_covers_swing() -> void:
	# block_chance=100 forces the gate to fire every swing. block_amount=20
	# covers a 15-physical hit entirely → full block (return 0).
	var d: _StubBotDefender = _make_bot_defender(200, 0, [], {})
	d.block_chance = 100.0
	d.block_amount = 20
	var dealt: int = d.take_damage(15, null, "physical")
	assert_eq(dealt, 0, "block_amount=20 vs raw=15 → full block (returns 0)")
	assert_eq(d.hp, 200, "full block — hp unchanged")
	d.free()

func test_s9_block_partial_reduces_each_typed_leg_by_amount() -> void:
	# block_chance=100, block_amount=5. Hybrid swing 20 phys + 10 fire.
	# Both legs > 5, so partial block: reduce each by 5 (≥1 floor),
	# then mitigation pipeline runs. With no armor / no resistances,
	# defender takes (20-5) + (10-5) = 15 + 5 = 20.
	var d: _StubBotDefender = _make_bot_defender(200, 0, [], {})
	d.block_chance = 100.0
	d.block_amount = 5
	var attacker: _StubAttacker = _StubAttacker.new()
	attacker.weapon_tags = []
	var dealt: int = d.resolve_swing({"physical": 20, "fire": 10}, attacker)
	assert_eq(dealt, 20, "partial block: (20-5) + (10-5) = 20 dealt")
	d.free()
	attacker.free()

func test_s9_block_chance_zero_skips_gate() -> void:
	# block_chance=0 must skip the block branch entirely; even with a
	# huge block_amount, no swing should be reduced.
	var d: _StubBotDefender = _make_bot_defender(200, 0, [], {})
	d.block_chance = 0.0
	d.block_amount = 50
	var dealt: int = d.take_damage(20, null, "physical")
	assert_eq(dealt, 20, "block_chance=0 — block_amount irrelevant")
	d.free()

func test_s9_executioner_routes_to_crit_multiplier_pct() -> void:
	# of_executioner writes crit_multiplier_pct via the standard
	# accumulator pipeline. Authored on a single ring, expected mid-tier
	# value flows into the bot field via StatCalc.compute.
	ItemsDb.preload_all()
	var items_db: Dictionary = ItemsDb.items()
	var fake_db: Dictionary = items_db.duplicate(true)
	fake_db["__test_ring"] = {
		"id": "__test_ring", "slot": "ring", "rarity": "epic",
		"flavor_tags": [], "implicit_affixes": [],
	}
	var inst := {
		"base_id": "__test_ring", "rarity": "epic",
		"affixes": [{"id": "of_executioner", "value": 15}],
	}
	var save := {
		"species": "human",
		"stat_alloc_str": 0, "stat_alloc_dex": 0, "stat_alloc_int": 0,
		"stat_points_unspent": 0, "bot_upgrades": {},
	}
	var d: Dictionary = StatCalc.compute({"ring": inst}, fake_db, save, "human", 1, 0, 0, [])
	assert_almost_eq(float(d.get("crit_multiplier_pct", 0)), 15.0, 0.001,
		"of_executioner value=15 routes to crit_multiplier_pct accumulator")

func test_s9_crit_multiplier_pct_caps_at_35() -> void:
	# Soft cap at +35% per a10 §6 rescope. Single oversized roll (raw=200)
	# must clamp regardless of DR composition.
	ItemsDb.preload_all()
	var items_db: Dictionary = ItemsDb.items()
	var fake_db: Dictionary = items_db.duplicate(true)
	fake_db["__test_ring"] = {
		"id": "__test_ring", "slot": "ring", "rarity": "legendary",
		"flavor_tags": [], "implicit_affixes": [],
	}
	var inst := {
		"base_id": "__test_ring", "rarity": "legendary",
		"affixes": [{"id": "of_executioner", "value": 200}],
	}
	var save := {
		"species": "human",
		"stat_alloc_str": 0, "stat_alloc_dex": 0, "stat_alloc_int": 0,
		"stat_points_unspent": 0, "bot_upgrades": {},
	}
	var d: Dictionary = StatCalc.compute({"ring": inst}, fake_db, save, "human", 1, 0, 0, [])
	assert_almost_eq(float(d.get("crit_multiplier_pct", 0)), 35.0, 0.001,
		"crit_multiplier_pct soft-caps at +35% — raw=200 should clamp")

func test_s9_shield_base_block_stats_flow_through() -> void:
	# Shield-slot base items carry block_chance + block_amount fields.
	# StatCalc reads them off items_db (not affix-rolled) and surfaces them
	# on the dict. tower_shield = 25/20 per S9.
	ItemsDb.preload_all()
	var items_db: Dictionary = ItemsDb.items()
	if not items_db.has("tower_shield"):
		pending("tower_shield not present in items_db")
		return
	var inst := {"base_id": "tower_shield", "rarity": "uncommon", "affixes": []}
	var save := {
		"species": "human",
		"stat_alloc_str": 0, "stat_alloc_dex": 0, "stat_alloc_int": 0,
		"stat_points_unspent": 0, "bot_upgrades": {},
	}
	var d: Dictionary = StatCalc.compute({"shield": inst}, items_db, save, "human", 1, 0, 0, [])
	# tower_shield base = block_chance=25 / block_amount=20 (uncommon
	# meta_mult ×1.0, qmult ×1.0 → combined_base=1.0).
	assert_almost_eq(float(d.get("block_chance", 0)), 25.0, 0.001,
		"tower_shield base block_chance=25 flows through")
	assert_eq(int(d.get("block_amount", 0)), 20,
		"tower_shield base block_amount=20 flows through")

func test_s9_block_caps_at_30_chance_and_20_amount() -> void:
	# Soft caps per a10 rescope. block_chance ≤ 30, block_amount ≤ 20.
	ItemsDb.preload_all()
	var items_db: Dictionary = ItemsDb.items()
	var fake_db: Dictionary = items_db.duplicate(true)
	fake_db["__test_shield"] = {
		"id": "__test_shield", "slot": "shield", "rarity": "legendary",
		"base_type": "tower_shield",
		"block_chance": 100,    # raw, pre-cap
		"block_amount": 100,    # raw, pre-cap
		"flavor_tags": [], "implicit_affixes": [],
	}
	var inst := {"base_id": "__test_shield", "rarity": "legendary", "affixes": []}
	var save := {
		"species": "human",
		"stat_alloc_str": 0, "stat_alloc_dex": 0, "stat_alloc_int": 0,
		"stat_points_unspent": 0, "bot_upgrades": {},
	}
	var d: Dictionary = StatCalc.compute({"shield": inst}, fake_db, save, "human", 1, 0, 0, [])
	assert_almost_eq(float(d.get("block_chance", 0)), 30.0, 0.001,
		"block_chance soft-caps at 30")
	assert_eq(int(d.get("block_amount", 0)), 20,
		"block_amount soft-caps at 20")

# ---------------------------------------------------------------------
# S10 — 8 new spell archetypes (a05 D + a10 §3.2 rescopes)
# ---------------------------------------------------------------------

func test_s10_archetypes_registered() -> void:
	# Sanity — every new archetype must be in SpellData.ARCHETYPES so
	# spell_system._dispatch_fire's match arms don't silently drop casts.
	for aid in [
		"spell_bone_spear", "spell_venom_cloud", "spell_stormcaller_totem",
		"spell_curse_brittlebone", "spell_wrath_charge", "spell_echo_lance",
		"spell_wisp_servant", "spell_ember_bloom",
	]:
		assert_true(SpellData.is_spell_archetype(aid),
			"S10 archetype %s must be registered" % aid)

func test_s10_cursed_amplifies_incoming_15pct() -> void:
	# Curse of Brittlebone (a05 prop-4 + a10 §3.2 rescope to +15%) —
	# defender taking damage while "cursed" eats +15% raw before
	# mitigation. Verifies the new amp path in _apply_typed_damage.
	# Use bot-typed defender so add_status is allowed (status overlay
	# is gated on VideoSettings.gfx.ench).
	var d: _StubBotDefender = _make_bot_defender(1000, 0, [], {})
	# Bypass the VideoSettings gate by writing the status entry directly.
	d._statuses["cursed"] = {"expires_at": 0.0, "sprite": null}
	var dealt: int = d.take_damage(100, null, "fire")
	# Pre-amp 100 fire damage; with no resists, mit_sum=0, post: 100×1.15 = 115.
	assert_eq(dealt, 115, "cursed amplifies +15% on incoming")
	d.free()

func test_s10_cursed_halves_armor_on_physical() -> void:
	# Cursed targets ALSO take -50% effective armor on physical hits.
	# Defender: 100 HP, 20 armor, cursed status.
	var d: _StubBotDefender = _make_bot_defender(1000, 20, [], {})
	d._statuses["cursed"] = {"expires_at": 0.0, "sprite": null}
	var dealt: int = d.take_damage(100, null, "physical")
	# 100 × 1.15 = 115 raw; mit_sum=0; post_mit=115; eff_armor 20→10
	# (cursed half); dmg = 115 - 10 = 105.
	assert_eq(dealt, 105, "cursed halves effective armor on physical")
	d.free()

func test_s10_wrath_status_registered() -> void:
	# Wrath Charge writes "wrath" status; status registry must know it.
	assert_true(StatusOverlay.has_status("wrath"),
		"wrath status must be registered for buff visibility")
	assert_true(StatusOverlay.has_status("cursed"),
		"cursed status must be registered for debuff visibility")

func test_s10_spell_tomes_present() -> void:
	# Every new archetype has at least 5 tomes spanning rarities.
	# Catches mis-injection regressions and keeps the loot pool honest.
	var items: Array = []
	if FileAccess.file_exists("res://data/items.json"):
		var f: FileAccess = FileAccess.open("res://data/items.json", FileAccess.READ)
		if f != null:
			var doc: Variant = JSON.parse_string(f.get_as_text())
			if doc is Dictionary and doc.has("items"):
				items = doc["items"]
	var counts: Dictionary = {}
	for it in items:
		var bt: String = String(it.get("base_type", ""))
		if bt in [
			"spell_bone_spear", "spell_venom_cloud", "spell_stormcaller_totem",
			"spell_curse_brittlebone", "spell_wrath_charge", "spell_echo_lance",
			"spell_wisp_servant", "spell_ember_bloom",
		]:
			counts[bt] = int(counts.get(bt, 0)) + 1
	assert_eq(counts.size(), 8, "all 8 new archetypes present in items.json")
	for arch in counts.keys():
		assert_gte(int(counts[arch]), 5,
			"%s should have ≥5 tomes (got %d)" % [arch, counts[arch]])

func test_s10_wrath_charge_archetype_zero_damage() -> void:
	# Wrath Charge declares damage=0 in archetype — it's a self-buff,
	# never deals direct damage. Lock so a future "let's add a thorn"
	# regression doesn't quietly break the rescope.
	var arch: Dictionary = SpellData.archetype_def("spell_wrath_charge")
	assert_eq(int(arch.get("damage", -1)), 0,
		"Wrath Charge archetype damage must stay 0 (self-buff only)")

func test_s10_curse_brittlebone_zero_direct_damage() -> void:
	# Curse direct damage stays at 1 — just enough for kill log routing.
	# The actual power is the +15% amp + -50% armor on the cursed enemy.
	var arch: Dictionary = SpellData.archetype_def("spell_curse_brittlebone")
	assert_eq(int(arch.get("damage", -1)), 1,
		"Curse archetype damage must be 1 (kill-log register only)")

func test_s10_cloud_per_tick_base_within_rescope() -> void:
	# a10 §3.2 rescope: venom_cloud 1.5/tick, ember_bloom 2.0/tick.
	# Archetype baseline rounds to 2 each (compute_damage rolls items'
	# damage_min/max; archetype default is the floor when item omits).
	var venom: Dictionary = SpellData.archetype_def("spell_venom_cloud")
	var ember: Dictionary = SpellData.archetype_def("spell_ember_bloom")
	assert_lte(int(venom.get("damage", 99)), 2,
		"venom_cloud per-tick base ≤ 2 (a10 rescope)")
	assert_lte(int(ember.get("damage", 99)), 2,
		"ember_bloom per-tick base ≤ 2 (a10 rescope)")

# ---------------------------------------------------------------------
# S11 — Boss-anchor uniques + biome-targeted drops (a07 §6.1-6.12)
# ---------------------------------------------------------------------

func test_s11_all_12_boss_anchors_present_in_items_db() -> void:
	# Sanity: every boss-anchor unique is in ItemsDb, declares boss_drop +
	# biome_pool + implicit_affixes, and is unique:true (so run_dropped_uniques
	# de-dupes on drop). If any of these slip, the loot pipeline silently
	# breaks for the affected boss.
	ItemsDb.preload_all()
	var db: Dictionary = ItemsDb.items()
	var expected: Array = [
		"sigmunds_sickle", "blorks_pickaxe", "eustachio_dancing_sword",
		"kirkes_pendant", "grums_wolfclaw_gauntlets", "psyche_holy_censer",
		"lernaean_hydra_cloak", "ilsuiw_trident", "aizul_serpent_knife",
		"boris_phylactery", "frederick_vault_key_ring", "tiamat_five_heads",
	]
	for aid in expected:
		assert_true(db.has(aid), "ItemsDb missing boss anchor: %s" % aid)
		var item: Dictionary = db[aid]
		assert_true(bool(item.get("unique", false)),
			"%s must be unique:true" % aid)
		assert_ne(String(item.get("boss_drop", "")), "",
			"%s must declare boss_drop" % aid)
		var bp: Variant = item.get("biome_pool", null)
		assert_true(bp is Array and not (bp as Array).is_empty(),
			"%s must declare a non-empty biome_pool" % aid)
		var implicits: Variant = item.get("implicit_affixes", [])
		assert_true(implicits is Array and not (implicits as Array).is_empty(),
			"%s must declare implicit_affixes (the unique mechanic)" % aid)

func test_s11_boss_drop_fields_reference_real_enemies() -> void:
	# Linter mirrors this in CI, but lock it as a runtime regression too —
	# the dungeon's _pick_boss_anchor_id matches enemy.enemy_id against
	# items_db boss_drop verbatim. A typo never spawns the anchor.
	ItemsDb.preload_all()
	var db: Dictionary = ItemsDb.items()
	var enemies_path := "res://data/enemies.json"
	var f: FileAccess = FileAccess.open(enemies_path, FileAccess.READ)
	assert_not_null(f, "enemies.json readable")
	var enemies: Dictionary = JSON.parse_string(f.get_as_text())
	for id in db.keys():
		var bd: String = String(db[id].get("boss_drop", ""))
		if bd == "":
			continue
		assert_true(enemies.has(bd),
			"item %s boss_drop=%s must be a real enemy id" % [id, bd])

func test_s11_biome_pool_field_filters_out_anchors_from_normal_drops() -> void:
	# A boss-anchor item can never be picked by the normal rarity loot
	# table — the LootFactory.pick_loot_id boss_drop guard short-circuits
	# even when biome_pool would otherwise match. This protects against
	# random T1 runs accidentally rolling Sigmund's Sickle from a chest.
	ItemsDb.preload_all()
	var db: Dictionary = ItemsDb.items()
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var ran: Array = []
	for _i in 200:
		var picked: String = LootFactory.pick_loot_id(rng, "legendary", db, 1, [], false, "dungeon")
		if picked != "":
			ran.append(picked)
	for aid in ["sigmunds_sickle", "blorks_pickaxe", "eustachio_dancing_sword"]:
		assert_false(aid in ran,
			"boss-anchor %s must not appear in normal pick_loot_id rolls" % aid)

func test_s11_phylactery_revives_at_pct_max_hp_once_per_floor() -> void:
	# of_phylactery (Boris): once-per-floor revive at 25% max_hp on lethal
	# damage. Gates on revive_used_this_floor mutex (S2 a11 §2.11). Set
	# the field directly to skip recompute_stats; the bot stub doesn't
	# carry an items_db.
	var d: _StubBotDefender = _make_bot_defender(200, 0, [], {})
	d.phylactery_revive_pct = 25.0
	d.revive_used_this_floor = false
	# Lethal hit — should NOT die.
	d.take_damage(500, null, "physical")
	assert_true(d.is_alive, "phylactery prevents the lethal hit")
	assert_eq(d.hp, 50, "revives to 25% of max_hp (200×0.25=50)")
	assert_true(d.revive_used_this_floor,
		"revive_used_this_floor flag set after revive consumes")
	# Second lethal hit on the same floor — should die (mutex held).
	d.take_damage(500, null, "physical")
	assert_false(d.is_alive,
		"second lethal hit kills (revive_used_this_floor mutex)")
	d.free()

func test_s11_phylactery_does_not_fire_when_field_zero() -> void:
	# Without phylactery_revive_pct, lethal damage kills as normal — proves
	# the gate is actually reading the field, not always-on.
	var d: _StubBotDefender = _make_bot_defender(100, 0, [], {})
	d.phylactery_revive_pct = 0.0
	d.revive_used_this_floor = false
	d.take_damage(500, null, "physical")
	assert_false(d.is_alive,
		"no revive when phylactery_revive_pct=0 → bot dies as normal")
	d.free()

func test_s11_anchor_regen_folds_into_hp_regen() -> void:
	# Psyche's Holy Censer (of_holy_anchor) writes anchor_regen which
	# bot.recompute_stats adds to hp_regen_per_sec. Feed StatCalc directly
	# with a stub equipped dict to confirm the dict carries the field.
	ItemsDb.preload_all()
	var db: Dictionary = ItemsDb.items()
	var psyche: Dictionary = db.get("psyche_holy_censer", {})
	assert_false(psyche.is_empty(), "psyche_holy_censer present in items_db")
	var equipped: Dictionary = {"helm": {"base_id": "psyche_holy_censer", "affixes": []}}
	var d: Dictionary = StatCalc.compute(equipped, db, {}, "human", 1, 0, 0, [])
	assert_almost_eq(float(d.get("anchor_regen", -1.0)), 3.0, 0.001,
		"psyche_holy_censer rolls of_holy_anchor with anchor_regen=3")

func test_s11_extra_chests_per_floor_reads_from_vault_key_ring() -> void:
	# Frederick's Vault-Key Ring (of_vault_key) bumps extra_chests_per_floor
	# by 1. Dungeon._populate_floor reads bot.extra_chests_per_floor and
	# adds it to chest_count.
	ItemsDb.preload_all()
	var db: Dictionary = ItemsDb.items()
	var ring: Dictionary = db.get("frederick_vault_key_ring", {})
	assert_false(ring.is_empty(), "frederick_vault_key_ring present in items_db")
	var equipped: Dictionary = {"ring": {"base_id": "frederick_vault_key_ring", "affixes": []}}
	var d: Dictionary = StatCalc.compute(equipped, db, {}, "human", 1, 0, 0, [])
	assert_eq(int(d.get("extra_chests_per_floor", -1)), 1,
		"vault-key ring grants +1 extra_chests_per_floor")

func test_s11_tiamat_grants_three_resists_and_fifth_cast_pct() -> void:
	# Tiamat's Five Heads bundles fire/cold/poison resists + fifth_cast_pct.
	# All four implicits should land on a wearer simultaneously.
	ItemsDb.preload_all()
	var db: Dictionary = ItemsDb.items()
	var helm: Dictionary = db.get("tiamat_five_heads", {})
	assert_false(helm.is_empty(), "tiamat_five_heads present in items_db")
	var equipped: Dictionary = {"helm": {"base_id": "tiamat_five_heads", "affixes": []}}
	var d: Dictionary = StatCalc.compute(equipped, db, {}, "human", 1, 0, 0, [])
	var res: Dictionary = d.get("resistances", {})
	assert_gte(float(res.get("fire", 0.0)), 1.0,
		"tiamat grants fire resist via implicit")
	assert_gte(float(res.get("cold", 0.0)), 1.0,
		"tiamat grants cold resist via implicit")
	assert_gte(float(res.get("poison", 0.0)), 1.0,
		"tiamat grants poison resist via implicit")
	assert_almost_eq(float(d.get("fifth_cast_pct", -1.0)), 15.0, 0.001,
		"tiamat sets fifth_cast_pct=15 (a10 §3.2 rescope)")

# ---------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------

func _make_defender(hp_max: int, armor: int, defense_tags: Array, resistances: Dictionary) -> _StubDefender:
	var d: _StubDefender = _StubDefender.new()
	d.max_hp = hp_max
	d.hp = hp_max
	d.defense = armor
	d.defense_tags_value = defense_tags.duplicate()
	d.resistances = resistances.duplicate()
	d.is_alive = true
	return d

func _make_bot_defender(hp_max: int, armor: int, defense_tags: Array, resistances: Dictionary) -> _StubBotDefender:
	# Real-Bot-typed defender so the `self is Bot` gate in resolve_swing
	# evaluates true. Used by S9 block tests where the gate is gated on
	# the actor type.
	var d: _StubBotDefender = _StubBotDefender.new()
	d.max_hp = hp_max
	d.hp = hp_max
	d.defense = armor
	d.defense_tags_value = defense_tags.duplicate()
	d.resistances = resistances.duplicate()
	d.is_alive = true
	return d
