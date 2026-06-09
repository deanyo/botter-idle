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
	# Defender with fire_res tag (50% cut when attacker carries `fire`)
	# AND 50% fire resistance via dict. Attacker has fire weapon tag.
	# Fire 100 → tag halves to 50 → dict halves to 25.
	var attacker: _StubAttacker = _StubAttacker.new()
	attacker.weapon_tags = ["fire"]
	var d: Actor = _make_defender(1000, 0, ["fire_res"], {"fire": 50.0})
	var dealt: int = d.take_damage(100, attacker, "fire")
	assert_eq(dealt, 25, "fire vs fire_res tag + resistance dict")
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
