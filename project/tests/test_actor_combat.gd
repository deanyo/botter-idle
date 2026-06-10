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
