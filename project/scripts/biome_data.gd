class_name BiomeData
extends RefCounted

const BIOMES_PATH := "res://data/biomes.json"
const FLOOR_DIR := "res://assets/tiles/floor/"
const WALL_DIR := "res://assets/tiles/wall/"

static var _biomes: Dictionary = {}
static var _run_plans: Array = []
static var _loaded: bool = false
static var _file_index: Dictionary = {}

static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var f := FileAccess.open(BIOMES_PATH, FileAccess.READ)
	if f == null:
		push_error("biomes.json not found")
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("biomes.json malformed")
		return
	_biomes = parsed.get("biomes", {})
	_run_plans = parsed.get("run_plans", [])

static func roll_run_plan(rng: RandomNumberGenerator) -> Array:
	_ensure_loaded()
	# Fully-random plan: each of the 10 floor slots gets an independently rolled
	# biome id from the full roster. Bypasses the weighted run_plans table while
	# we shake out vault variety.
	var ids: Array = _biomes.keys()
	if ids.is_empty():
		return ["dungeon", "dungeon", "dungeon", "dungeon", "dungeon", "dungeon", "dungeon", "dungeon", "dungeon", "dungeon"]
	var plan: Array = []
	for i in 10:
		plan.append(String(ids[rng.randi() % ids.size()]))
	return plan

static func get_biome(biome_id: String) -> Dictionary:
	_ensure_loaded()
	if not _biomes.has(biome_id):
		return {}
	var b: Dictionary = _biomes[biome_id].duplicate()
	b["id"] = biome_id
	return b

static func biome_for_floor(plan: Array, floor_num: int) -> Dictionary:
	_ensure_loaded()
	var idx: int = clampi(floor_num - 1, 0, plan.size() - 1)
	var biome_id: String = String(plan[idx])
	var b: Dictionary = _biomes.get(biome_id, {}).duplicate()
	b["id"] = biome_id
	return b

# Returns DCSS-style branch depth (e.g. floor 7 of 'crypt, crypt, vaults' run is
# "Crypt:2"). Counts consecutive same-biome floors leading up to floor_num.
static func branch_depth_label(plan: Array, floor_num: int) -> String:
	if plan.is_empty():
		return "D:%d" % floor_num
	var idx: int = clampi(floor_num - 1, 0, plan.size() - 1)
	var biome_id: String = String(plan[idx])
	var depth: int = 1
	var i: int = idx - 1
	while i >= 0 and String(plan[i]) == biome_id:
		depth += 1
		i -= 1
	return "%s:%d" % [_branch_short_name(biome_id), depth]

static func _branch_short_name(biome_id: String) -> String:
	# DCSS's branch abbreviations: D, Lair, Vaults, Crypt, Tomb, Snake, etc.
	# We use the biome id capitalised; "dungeon" maps to "D" specifically.
	if biome_id == "dungeon" or biome_id == "dungeon_dark":
		return "D"
	return biome_id.capitalize()

static func load_floor_primary(biome: Dictionary) -> Array:
	return _expand_prefixes(biome.get("floor_primary", []), FLOOR_DIR)

static func load_floor_accent(biome: Dictionary) -> Array:
	return _expand_prefixes(biome.get("floor_accent", []), FLOOR_DIR)

static func load_wall_primary(biome: Dictionary) -> Array:
	var prefix: String = String(biome.get("wall_primary", ""))
	if prefix == "":
		return []
	return _expand_prefixes([prefix], WALL_DIR)

static func load_wall_accent(biome: Dictionary) -> Array:
	return _expand_prefixes(biome.get("wall_accent", []), WALL_DIR)

static func load_wall_alternates(biome: Dictionary) -> Array:
	var out: Array = []
	for entry in biome.get("wall_alternates", []):
		var prefix: String = String(entry.get("prefix", ""))
		var weight: float = float(entry.get("weight", 1))
		var textures: Array = _expand_prefixes([prefix], WALL_DIR)
		if textures.is_empty():
			continue
		out.append({"textures": textures, "weight": weight})
	return out

static func _expand_prefixes(prefixes: Array, dir_path: String) -> Array:
	# Match exactly `prefix_<digit>` so e.g. 'slime' doesn't accidentally pull
	# in 'slime_alt_*' files (which would belong to a separate accent prefix).
	var arr: Array = []
	var files: Array = _list_dir(dir_path)
	for prefix in prefixes:
		var p: String = String(prefix) + "_"
		for f in files:
			if not f.begins_with(p):
				continue
			var tail: String = f.substr(p.length(), 1)
			if tail.is_empty() or not tail.is_valid_int():
				continue
			var tex: Texture2D = load(dir_path + f)
			if tex:
				arr.append(tex)
	return arr

static func _list_dir(dir_path: String) -> Array:
	if _file_index.has(dir_path):
		return _file_index[dir_path]
	var arr: Array = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		_file_index[dir_path] = arr
		return arr
	dir.list_dir_begin()
	var n := dir.get_next()
	while n != "":
		if not dir.current_is_dir() and n.ends_with(".png"):
			arr.append(n)
		n = dir.get_next()
	dir.list_dir_end()
	_file_index[dir_path] = arr
	return arr

static func modulate_for(biome: Dictionary) -> Color:
	var m: Array = biome.get("modulate", [1, 1, 1, 1])
	return Color(float(m[0]), float(m[1]), float(m[2]), float(m[3]))

static func darkness_for(biome: Dictionary) -> float:
	return float(biome.get("darkness", 0.2))

static func pick_ambient_decor(biome: Dictionary, rng: RandomNumberGenerator) -> String:
	var pool: Array = biome.get("ambient_decor", [])
	if pool.is_empty():
		return ""
	var total: float = 0.0
	for entry in pool:
		total += float(entry.get("weight", 1))
	if total <= 0.0:
		return ""
	var roll: float = rng.randf_range(0.0, total)
	var cum: float = 0.0
	for entry in pool:
		cum += float(entry.get("weight", 1))
		if roll <= cum:
			return String(entry.get("id", ""))
	return String(pool[-1].get("id", ""))

static func ambient_density_for(biome: Dictionary) -> float:
	return float(biome.get("ambient_density", 0.012))

# Roll a layout id from the biome's weighted layouts table. Falls back to the
# legacy single 'layout' field, then to 'basic', so older biome entries still work.
static func roll_layout(biome: Dictionary, rng: RandomNumberGenerator) -> String:
	var pool: Array = biome.get("layouts", [])
	if pool.is_empty():
		return String(biome.get("layout", "basic"))
	var total: float = 0.0
	for entry in pool:
		total += float(entry.get("weight", 1))
	if total <= 0.0:
		return String(biome.get("layout", "basic"))
	var roll: float = rng.randf_range(0.0, total)
	var cum: float = 0.0
	for entry in pool:
		cum += float(entry.get("weight", 1))
		if roll <= cum:
			return String(entry.get("id", "basic"))
	return String(pool[-1].get("id", "basic"))
