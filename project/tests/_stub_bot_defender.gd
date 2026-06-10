extends Bot

# Minimal Bot defender stub for S9 block tests. Extends Bot so the
# `self is Bot` gate in actor.gd::resolve_swing fires. Skips the heavy
# Actor._ready (rig/sprite/hp_bar) so headless tests run in microseconds.
# Tests poke block_chance / block_amount / hp / max_hp directly.

var defense_tags_value: Array = []

func _ready() -> void:
	# Intentionally don't call super._ready — tests don't need rig/fx,
	# and Bot._ready triggers ItemsDb load + status-overlay layer setup
	# that's irrelevant to combat-gate testing.
	pass

func combat_defense_tags() -> Array:
	return defense_tags_value
