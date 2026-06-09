extends Node

# Minimal Bot stub for HUDInventoryController tests. Carries the
# fields the controller reads (equipped, gold, max_hp, hp, species_id)
# without dragging in Actor's _ready (rig/fx/hp_bar). Methods the
# controller calls during equip flows (equip_from_inventory,
# recompute_stats, _refresh_gear_overlays, _update_hp_bar) are
# overridable no-ops; tests that exercise drag-equip can substitute
# their own fakes by reaching into these arrays directly.

var equipped: Dictionary = {}
var gold: int = 0
var hp: int = 100
var max_hp: int = 100
var species_id: String = "human"
var displaced_to_return: Array = []

func _ready() -> void:
	pass

func equip_from_inventory(_inst: Dictionary) -> Array:
	return displaced_to_return

func recompute_stats() -> void:
	pass

func _refresh_gear_overlays() -> void:
	pass

func _update_hp_bar() -> void:
	pass
