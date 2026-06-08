extends Actor

# Test stub — an Actor with overridable combat_weapon_tags and
# damage_min/max fields. Used by tests/actor_combat_tests.gd.
# Skips the heavy _ready (rig + sprite + hp_bar nodes) — tests don't
# need visuals; assertions read hp / is_alive / signals directly.

var weapon_tags: Array = []
var damage_min: int = 1
var damage_max: int = 1

func _ready() -> void:
	# Intentionally don't call super._ready — tests don't need rig/fx.
	pass

func combat_weapon_tags() -> Array:
	return weapon_tags

# _update_hp_bar gets called by take_damage. The base class's version
# guards on hp_bar == null (see actor.gd _update_hp_bar) so this is
# safe to inherit.
