extends Node

# Stub dungeon for WaveSpawner unit tests. Records spawn calls and
# exposes the fields the spawner reads (bot, rng, enemies, _floor_ready,
# current_floor, current_biome). Bot exposes is_alive so the spawner's
# is_alive gate fires correctly. _spawn_specific records the call but
# DOESN'T mutate `enemies` — tests append fake enemies to enemies
# manually so they can pin the alive-count gate independently of the
# spawn.
#
# _random_walkable_cell_far_from_bot returns a stub cell so the test
# doesn't need a real grid. _warp_in_last_spawn is exercised by
# wave_spawner directly; here it would be a no-op (no rig), but the
# tests don't call drain_one against a real spawn so the warp path is
# guarded inside the spawner itself.

class _StubBot:
	var is_alive: bool = true

class _StubEnemy:
	var is_alive: bool = true
	var rig: Node2D = null


var bot: _StubBot = _StubBot.new()
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var enemies: Array = []
var _floor_ready: bool = true
var current_floor: int = 1
var current_biome: Dictionary = {
	"id": "stub",
	"enemy_pool": ["rat", "kobold", "orc"],
}

# Records of side-effecting calls so tests can assert against them.
var spawn_calls: Array = []  # [{id, cell, tier}]
var random_cell_calls: int = 0


func _spawn_specific(id: String, cell: Vector2i, tier: int = -1) -> void:
	spawn_calls.append({"id": id, "cell": cell, "tier": tier})


func _random_walkable_cell_far_from_bot() -> Vector2i:
	random_cell_calls += 1
	return Vector2i(40, 40)


func add_alive_enemy() -> _StubEnemy:
	var e := _StubEnemy.new()
	enemies.append(e)
	return e
