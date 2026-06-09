extends Node

# Stub dungeon for ShowcaseRunner unit tests. Exposes the fields the
# runner reads (bot, rng, items_db, actor_layer, interactables,
# ambient_decor_nodes, pathing, bot_target_*) and records the spawn
# helper calls so the tests can assert against them. The runner only
# directly drives the patrol bookkeeping in tests; the spawn-station
# integration is exercised by the live /showcase skill smoke (visual
# fidelity isn't pinned by GUT).

class _StubBot:
	var cell: Vector2i = Vector2i(15, 14)
	var path: PackedVector2Array = PackedVector2Array()
	var path_index: int = 0
	var step_calls: int = 0
	var set_path_calls: Array = []  # list of PackedVector2Array

	func step_movement(_delta: float) -> void:
		step_calls += 1

	func set_path(p: PackedVector2Array) -> void:
		set_path_calls.append(p)
		path = p
		path_index = 0


class _StubPath:
	# Returns a 4-cell path covering from→to. Length>1 so the runner's
	# `if p.size() > 1` gate fires consistently.
	func path(from_cell: Vector2i, to_cell: Vector2i) -> PackedVector2Array:
		var out: PackedVector2Array = PackedVector2Array()
		out.append(Vector2(from_cell))
		out.append(Vector2(from_cell.x + 1, from_cell.y))
		out.append(Vector2(to_cell.x - 1, to_cell.y))
		out.append(Vector2(to_cell))
		return out


var bot: _StubBot = _StubBot.new()
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var items_db: Dictionary = {}
# actor_layer would be a Node2D in a real dungeon; the patrol tests
# don't exercise spawn_stations so this stays null. add_child_autofree
# in before_each catches any allocation a future test introduces.
var actor_layer: Node2D = null
var interactables: Array = []
var ambient_decor_nodes: Array = []
var pathing: _StubPath = _StubPath.new()
var bot_target_cell: Vector2i = Vector2i(-1, -1)
var bot_target_kind: String = ""

# Spawn-helper call recorders. The runner's spawn_stations() walks the
# Showcase.STATIONS roster and dispatches into these — this stub
# captures the calls so a test could assert against them, though the
# build/tick/is_active tests are the load-bearing surface.
var spawn_specific_calls: Array = []
var spawn_chest_calls: Array = []
var spawn_fountain_calls: Array = []
var spawn_portal_calls: Array = []
var spawn_loot_drop_calls: Array = []


func _spawn_specific(id: String, cell: Vector2i, tier: int = -1) -> void:
	spawn_specific_calls.append({"id": id, "cell": cell, "tier": tier})


func _spawn_chest(cell: Vector2i, drops: int = 2, bias: int = 0) -> void:
	spawn_chest_calls.append({"cell": cell, "drops": drops, "bias": bias})


func _spawn_fountain(cell: Vector2i, kind: String) -> void:
	spawn_fountain_calls.append({"cell": cell, "kind": kind})


func _spawn_portal(cell: Vector2i) -> void:
	spawn_portal_calls.append({"cell": cell})


func _spawn_loot_drop(inst: Dictionary, cell: Vector2i) -> void:
	spawn_loot_drop_calls.append({"inst": inst, "cell": cell})
