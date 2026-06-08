extends SceneTree

# Hand-rolled tests for Actor.resolve_swing + take_damage.
# Locks the 2026-06-08 combat-correctness fixes:
#   - Avoidance gates (evasion / footwork / reflective) fire ONCE per
#     swing, not once per typed component.
#   - Thorns / crystal returns aggregate over a single swing (no
#     multi-emit `died` signal on hybrid hits).
#   - Single-hit take_damage callers (spells, projectiles, splash)
#     route through resolve_swing and pick up the same semantics.
#   - Spell hits with element=fire vs fire_res defender mitigate.
#
# No GUT dependency. Runs via:
#   /Applications/Godot.app/Contents/MacOS/Godot \
#       --path project --headless --script tests/actor_combat_tests.gd
#
# Surfaced through tools/check_before_commit.sh.

const _StubAttacker := preload("res://tests/_stub_attacker.gd")
const _StubDefender := preload("res://tests/_stub_defender.gd")

var _failures: int = 0
var _checks: int = 0

func _initialize() -> void:
	# Deterministic RNG so evasion / footwork / reflective rolls are
	# reproducible across runs.
	seed(0xB07_7E5)

	_test_take_damage_physical_armor()
	_test_take_damage_fire_resist()
	_test_take_damage_harm_amplifies()
	_test_evasion_full_dodge()
	_test_hybrid_swing_single_evasion_roll()
	_test_thorns_aggregates_over_swing()
	_test_crystal_aggregates_over_swing()
	_test_died_signal_fires_once_on_hybrid_kill()
	_test_spell_fire_vs_fire_res()
	_test_spell_thunderous_routes_to_lightning_resistance()

	_done()

# ---------------------------------------------------------------------
# take_damage typed-mitigation
# ---------------------------------------------------------------------

func _test_take_damage_physical_armor() -> void:
	var d: Actor = _make_defender(100, 5, [], {})
	# Raw 20 - armor 5 = 15.
	var dealt: int = d.take_damage(20, null, "physical")
	_eq("physical armor subtracts", dealt, 15)
	_eq("physical armor — hp drop", d.hp, 85)
	d.queue_free()

func _test_take_damage_fire_resist() -> void:
	# Defender with 50% fire resistance and `fire_res` tag (which doubles
	# the cut to 75% when attacker carries `fire`). With no attacker, the
	# tag does nothing — only the resistance dict applies.
	var d: Actor = _make_defender(100, 0, [], {"fire": 50.0})
	var dealt: int = d.take_damage(40, null, "fire")
	_eq("fire resist 50% halves typed damage", dealt, 20)
	d.queue_free()

func _test_take_damage_harm_amplifies() -> void:
	# Harm is defender-worn — multiplies incoming damage by 1.25. Pure
	# physical, no armor.
	var d: Actor = _make_defender(100, 0, ["harm"], {})
	var dealt: int = d.take_damage(20, null, "physical")
	# 20 × 1.25 = 25.
	_eq("harm +25% on incoming", dealt, 25)
	d.queue_free()

# ---------------------------------------------------------------------
# Avoidance gates — once per swing, not once per typed component
# ---------------------------------------------------------------------

func _test_evasion_full_dodge() -> void:
	# Single-hit path. Defender with 100% evasion takes 0.
	var d: Actor = _make_defender(100, 0, [], {})
	d.evasion = 100.0
	var dealt: int = d.take_damage(50, null, "physical")
	_eq("100% evasion → 0 damage (single hit)", dealt, 0)
	_eq("100% evasion — hp unchanged", d.hp, 100)
	d.queue_free()

func _test_hybrid_swing_single_evasion_roll() -> void:
	# 100% evasion defender hit by a 3-element hybrid swing. Pre-fix the
	# typed loop called take_damage 3× and each call rolled evasion fresh.
	# At 100% all 3 dodge so this would always pass even broken — instead
	# use an evasion < 100% and statistical aggregate.
	#
	# Test: defender with 50% evasion taking N hybrid swings. Pre-fix
	# (3 independent rolls @ 50%) → P(all dodge) = 0.125, so ~87.5% of
	# swings deal damage. Post-fix (1 roll @ 50%) → exactly 50% of swings
	# dodge, exactly 50% deal damage. Use 200 swings; expected hit count
	# tightly bands around 100, and pre-fix would overshoot well past 150.
	var attacker: _StubAttacker = _StubAttacker.new()
	attacker.weapon_tags = []
	attacker.set("damage_min", 10)
	attacker.set("damage_max", 10)
	# Build a typed dict matching what attempt_attack would build for a
	# hybrid weapon. Each component is an independent damage type.
	var typed: Dictionary = {"physical": 4, "fire": 3, "cold": 3}
	var hits: int = 0
	for _i in 200:
		var d: _StubDefender = _make_defender(1000, 0, [], {})
		d.evasion = 50.0
		var dealt: int = d.resolve_swing(typed, attacker)
		if dealt > 0:
			hits += 1
		d.queue_free()
	# With single-roll avoidance, hits should be ~100 ± ~20. Pre-fix would
	# give ~175 because P(at least one component lands) = 1 - 0.5^3 = 87.5%.
	# Threshold: post-fix never exceeds 140; pre-fix never lower.
	if hits > 140:
		_failures += 1
		print("  FAIL  hybrid evasion — pre-fix multi-roll detected (got %d hits / 200, expected ~100)" % hits)
	else:
		print("  PASS  hybrid evasion — single roll per swing (got %d hits / 200, expected ~100)" % hits)
	_checks += 1
	attacker.queue_free()

# ---------------------------------------------------------------------
# Returns aggregate over swing
# ---------------------------------------------------------------------

func _test_thorns_aggregates_over_swing() -> void:
	# Defender with thorns. Hybrid swing dealing 20 phys + 10 fire + 10
	# cold = 40 dealt. Thorns returns 15% × 40 = 6 to attacker.
	# Pre-fix: 3 independent take_damage calls → 3 thorns returns of
	# 15% × each component = 3 + 1 + 1 = 5 (rounded). Tighter test:
	# attacker HP delta = 6 (post-fix) vs 5 (pre-fix) — small but real.
	#
	# Better test: thorns with damage that would produce different
	# rounding when aggregated vs split. 20+10+10 dealt:
	# - aggregated: round(40 × 0.15) = round(6.0) = 6
	# - split: round(20×0.15) + round(10×0.15) + round(10×0.15)
	#        = round(3.0) + round(1.5) + round(1.5)
	#        = 3 + 2 + 2 = 7  (banker's? Godot uses round-half-to-even
	#                         but 1.5 → 2 either way)
	# So aggregated returns 6, split returns 7. Test exact return value.
	var attacker: _StubAttacker = _StubAttacker.new()
	attacker.hp = 1000
	attacker.max_hp = 1000
	attacker.weapon_tags = []
	var d: Actor = _make_defender(1000, 0, ["thorns"], {})
	var typed: Dictionary = {"physical": 20, "fire": 10, "cold": 10}
	var dealt: int = d.resolve_swing(typed, attacker)
	# All 3 components land (defender has no resists, no armor) — dealt = 40.
	_eq("thorns swing — full damage dealt", dealt, 40)
	# Attacker took 1 thorns return chunk, not 3. Damage = max(1, round(40×0.15)) = 6.
	_eq("thorns aggregates — attacker took 6", attacker.hp, 1000 - 6)
	d.queue_free()
	attacker.queue_free()

func _test_crystal_aggregates_over_swing() -> void:
	# Same shape as thorns but at 5% return.
	# 40 dealt × 0.05 = 2.0 → 2 to attacker (one chunk, not three).
	var attacker: _StubAttacker = _StubAttacker.new()
	attacker.hp = 1000
	attacker.max_hp = 1000
	attacker.weapon_tags = []
	var d: Actor = _make_defender(1000, 0, ["crystal"], {})
	var typed: Dictionary = {"physical": 20, "fire": 10, "cold": 10}
	d.resolve_swing(typed, attacker)
	_eq("crystal aggregates — attacker took 2", attacker.hp, 1000 - 2)
	d.queue_free()
	attacker.queue_free()

func _test_died_signal_fires_once_on_hybrid_kill() -> void:
	# Pre-fix bug: thorns/crystal returns fired per-component. If the
	# first thorn chunk killed the attacker, subsequent chunks would
	# call _play_death_then_emit again (is_alive=false guard wasn't
	# universal). Verify the signal fires exactly once for an attacker
	# killed by a hybrid swing's thorn return.
	var attacker: _StubAttacker = _StubAttacker.new()
	attacker.hp = 5  # tiny so any thorn chunk kills
	attacker.max_hp = 5
	attacker.weapon_tags = []
	# Connect a counter to died.
	var counter: Dictionary = {"n": 0}
	attacker.died.connect(func(_a): counter.n += 1)
	var d: Actor = _make_defender(1000, 0, ["thorns", "crystal"], {})
	var typed: Dictionary = {"physical": 50, "fire": 30, "cold": 30}
	d.resolve_swing(typed, attacker)
	# Aggregated returns: thorns = round(110 × 0.15) = 17, crystal = round(110 × 0.05) = 6.
	# First fires, kills attacker, second sees attacker.is_alive=false and skips.
	_eq("hybrid thorn-kill emits died ONCE", counter.n, 1)
	_eq("attacker is dead", attacker.is_alive, false)
	d.queue_free()
	attacker.queue_free()

# ---------------------------------------------------------------------
# Spell-side element piping
# ---------------------------------------------------------------------

func _test_spell_fire_vs_fire_res() -> void:
	# Defender with fire_res (50% reduction when attacker carries `fire`)
	# AND 50% fire resistance via the resistances dict. Attacker carries
	# `fire` weapon tag (a fire dragon, fireball-tomed bot, etc.).
	# Fire 100 → fire_res tag halves to 50, then resistances 50% halves
	# again to 25.
	var attacker: _StubAttacker = _StubAttacker.new()
	attacker.weapon_tags = ["fire"]
	var d: Actor = _make_defender(1000, 0, ["fire_res"], {"fire": 50.0})
	var dealt: int = d.take_damage(100, attacker, "fire")
	_eq("fire vs fire_res tag + resistance dict", dealt, 25)
	d.queue_free()
	attacker.queue_free()

func _test_spell_thunderous_routes_to_lightning_resistance() -> void:
	# Spell archetype element="thunderous" maps to damage_type="lightning"
	# via SpellData.damage_type_for_element. Defender with 50% lightning
	# resistance. Spell hit at 80 → 40.
	_eq("damage_type_for_element thunderous", SpellData.damage_type_for_element("thunderous"), "lightning")
	_eq("damage_type_for_element fire", SpellData.damage_type_for_element("fire"), "fire")
	_eq("damage_type_for_element ''", SpellData.damage_type_for_element(""), "physical")
	var d: Actor = _make_defender(1000, 0, [], {"lightning": 50.0})
	var dealt: int = d.take_damage(80, null, "lightning")
	_eq("lightning resistance halves spell damage", dealt, 40)
	d.queue_free()

# ---------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------

# Build a defender Actor with the given hp/armor + defender-worn tags +
# resistances dict. We use a small subclass so combat_defense_tags() can
# return the tags array we want without touching production Actor code.
func _make_defender(hp_max: int, armor: int, defense_tags: Array, resistances: Dictionary) -> _StubDefender:
	var d: _StubDefender = _StubDefender.new()
	d.max_hp = hp_max
	d.hp = hp_max
	d.defense = armor
	d.defense_tags_value = defense_tags.duplicate()
	# Resistances dict is read off `self.resistances`; declared as a
	# field on the stub.
	d.resistances = resistances.duplicate()
	# fx is null (no scene tree). _update_hp_bar handles null hp_bar.
	# Avoid is_alive auto-computation by setting explicitly.
	d.is_alive = true
	return d

func _eq(name: String, actual, expected) -> void:
	_checks += 1
	if actual == expected:
		print("  PASS  %s  (= %s)" % [name, str(actual)])
	else:
		_failures += 1
		print("  FAIL  %s  expected %s, got %s" % [name, str(expected), str(actual)])

func _done() -> void:
	print("")
	print("Actor combat tests: %d/%d passed" % [_checks - _failures, _checks])
	quit(1 if _failures > 0 else 0)
