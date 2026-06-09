class_name ShowcaseRunner
extends RefCounted

# Showcase-mode integration glue extracted from dungeon.gd 2026-06-09 as
# the sixth and final Tier 3 sub-system split (audit Tier 3, follow-up
# to LootFactory / HUDInventoryController / DebugDump / RunState /
# WaveSpawner). Held by Dungeon as the `show` field.
#
# Activated by writing "showcase" to user://DEBUG_FLOOR.txt — see the
# /showcase skill. main.gd flips DebugJump.showcase=true on boot;
# Dungeon's _async_build_floor / _tick_bot / _check_stuck / _tick_enemies
# integration branches reroute through the runner (build the curated
# floor, spawn the fixed station roster, freeze enemy AI, walk the bot
# along a fixed loop).
#
# The static layout / patrol path / station roster live in
# scripts/showcase.gd as data. This file owns the runtime tick
# bookkeeping (patrol position) and the integration callbacks into
# Dungeon's spawn helpers (which need the actor_layer node, the
# interactables/ambient_decor_nodes arrays, the items_db, etc).
#
# Behavior is a strict copy of dungeon.gd's prior code — any tweaks to
# the visual-audit content belong in scripts/showcase.gd.

# Bot patrol bookkeeping. patrol is the list of cells the bot visits in
# order; patrol_idx is the index of the cell it's currently moving
# toward. begin_floor / build_floor_data resets both.
var patrol: Array = []
var patrol_idx: int = 0

# Bound dungeon ref. The runner reaches back into the dungeon for the
# actor_layer / interactables / ambient_decor_nodes / items_db / rng /
# bot / pathing / bot_target_* state, and the spawn helpers
# (_spawn_loot_drop, _spawn_specific, _spawn_chest, _spawn_fountain,
# _spawn_portal). Held as a plain ref — the dungeon owns this
# RefCounted, so the parent's lifetime always exceeds the helper's.
var _dungeon: Node = null


func _init(dungeon: Node) -> void:
	_dungeon = dungeon


# Are we in showcase mode? Reads DebugJump.showcase so the integration
# branches in dungeon.gd can call `show.is_active()` instead of
# referencing DebugJump directly.
func is_active() -> bool:
	return DebugJump.showcase


# Build the curated 80×80 floor data dict. Resets patrol bookkeeping
# and seeds the bot's spawn cell from the first patrol cell. Stairs
# sit in the corner so the field is populated for downstream code,
# but showcase mode never descends (see dungeon.gd _tick_bot gate).
func build_floor_data() -> Dictionary:
	var grid_arr: Array = Showcase.build_grid()
	patrol = Showcase.patrol_path()
	patrol_idx = 0
	var spawn: Vector2i = patrol[0] if not patrol.is_empty() else Vector2i(2, 2)
	return {
		"grid": grid_arr,
		"rooms": [],
		"spawn": spawn,
		"stairs_down": Vector2i(Showcase.MAP_W - 2, Showcase.MAP_H - 2),
		"dist_to_stairs": [],
		"vault_results": {},
	}


# Instantiate every Showcase.STATIONS entry. Decor goes via AmbientDecor;
# loot/chest/fountain/portal/altar/enemy go through the dungeon's regular
# spawn helpers so creature lights / altar gods / chest contents all
# match production behavior. Lava/water/ice are stamped at grid-build
# time inside Showcase.build_grid; nothing to spawn here for them.
func spawn_stations() -> void:
	for s in Showcase.STATIONS:
		var cell: Vector2i = s.anchor
		var kind: String = s.kind
		match kind:
			"fire_decor":
				for d in ["flame_0", "flame_1", "flame_2"]:
					var c: Vector2i = cell + Vector2i(["flame_0","flame_1","flame_2"].find(d) - 1, 0)
					_spawn_decor(d, c)
			"magic_decor":
				_spawn_decor("lantern", cell + Vector2i(-1, 0))
				_spawn_decor("magic_lamp", cell)
				_spawn_decor("orb", cell + Vector2i(1, 0))
			"crystal_decor":
				_spawn_decor("orb_glow_0", cell + Vector2i(-1, 0))
				_spawn_decor("orb_glow_1", cell)
				_spawn_decor("crystal_orb", cell + Vector2i(1, 0))
			"mushroom_decor":
				_spawn_decor("mold_1", cell + Vector2i(-1, 0))
				_spawn_decor("mold_2", cell)
				_spawn_decor("zot_pillar", cell + Vector2i(1, 0))
			"campfire":
				# Actor-tier flicker — full PointLight2D + embers. Lets us
				# compare the decor-tier (fog-only) flicker side by side.
				_spawn_decor("campfire", cell)
			"lava_pool", "water_pool", "ice_patch":
				pass # Terrain stamped at grid-build time; no entity needed.
			"fountain_blue":
				_dungeon._spawn_fountain(cell, "blue")
			"fountain_blood":
				_dungeon._spawn_fountain(cell, "blood")
			"altar_trog", "altar_zin", "altar_vehumet", "altar_kikubaaqudgha", "altar_xom":
				var god_id: String = kind.substr(6)
				var altar := Altar.new()
				altar.setup(cell, god_id)
				_dungeon.actor_layer.add_child(altar)
				_dungeon.interactables.append(altar)
			"loot_common", "loot_uncommon", "loot_rare", "loot_epic", "loot_legendary":
				var rarity: String = kind.substr(5)
				_spawn_loot_at(cell, rarity)
			"chest_normal":
				_dungeon._spawn_chest(cell, 2, 0)
			"chest_rich":
				_dungeon._spawn_chest(cell, 3, 2)
			"portal":
				_dungeon._spawn_portal(cell)
			"enemy_fire_dragon":
				_dungeon._spawn_specific("fire_dragon", cell)
			"enemy_ice_dragon":
				_dungeon._spawn_specific("ice_dragon", cell)
			"enemy_salamander":
				_dungeon._spawn_specific("salamander", cell)
			"enemy_blizzard_demon":
				_dungeon._spawn_specific("blizzard_demon", cell)
			"enemy_firefly":
				_dungeon._spawn_specific("firefly", cell)


# Walk to the next patrol cell. When the bot reaches it, advance the
# index and emit a path to the next one. Loops forever.
# step_movement is the per-frame mover — Bot._process doesn't move on
# its own; the dungeon's tick is what advances the bot along its path.
func tick_patrol(delta: float) -> void:
	if patrol.is_empty():
		return
	var bot = _dungeon.bot
	var has_path: bool = bot.path.size() > 0 and bot.path_index < bot.path.size()
	if has_path:
		bot.step_movement(delta)
		return
	# Arrived (or no path yet) — pick next station.
	patrol_idx = (patrol_idx + 1) % patrol.size()
	var target: Vector2i = patrol[patrol_idx]
	# If our spawn cell already matches the first station, skip ahead by
	# rolling once more — otherwise we'd ask pathing for an empty path and
	# get stuck.
	if target == bot.cell:
		patrol_idx = (patrol_idx + 1) % patrol.size()
		target = patrol[patrol_idx]
	var p: PackedVector2Array = _dungeon.pathing.path(bot.cell, target)
	if p.size() > 1:
		bot.set_path(p.slice(1))
		_dungeon.bot_target_cell = target
		_dungeon.bot_target_kind = "showcase_patrol"
		bot.step_movement(delta)


func _spawn_decor(decor_id: String, cell: Vector2i) -> void:
	var decor := AmbientDecor.new()
	decor.setup(decor_id, cell)
	_dungeon.actor_layer.add_child(decor)
	_dungeon.ambient_decor_nodes.append(decor)


func _spawn_loot_at(cell: Vector2i, rarity: String) -> void:
	var items_db: Dictionary = _dungeon.items_db
	var pool: Array = []
	for id in items_db.keys():
		if items_db[id].rarity == rarity:
			pool.append(id)
	if pool.is_empty():
		return
	var picked: String = pool[0]
	var inst: Dictionary = LootFactory.create_item_instance(_dungeon.rng, picked, items_db)
	_dungeon._spawn_loot_drop(inst, cell)
