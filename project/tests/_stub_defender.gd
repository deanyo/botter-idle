extends Actor

# Test stub — an Actor that returns a configurable defense-tag list
# from combat_defense_tags() and exposes a resistances dict on self
# (Actor.take_damage reads `self.resistances` if the field exists).

var defense_tags_value: Array = []
var resistances: Dictionary = {}
# Production Bot declares `evasion` via StatCalc.compute → recompute_stats;
# Actor.resolve_swing reads `self.evasion` only when the property exists.
# Declare it here so `"evasion" in self` evaluates true on the stub.
var evasion: float = 0.0

func _ready() -> void:
	# Skip rig/sprite/hp_bar setup — headless tests don't render.
	pass

func combat_defense_tags() -> Array:
	return defense_tags_value
