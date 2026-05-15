class_name BiomeData
extends RefCounted

const BIOMES_PATH := "res://data/biomes.json"
const FLOOR_DIR := "res://assets/tiles/floor/"
const WALL_DIR := "res://assets/tiles/wall/"
const OVERLAY_DIR := "res://assets/tiles/overlays/"
const SIGIL_DIR := "res://assets/tiles/sigils/"

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

static func roll_run_plan(rng: RandomNumberGenerator, branch_id: String = "") -> Array:
	# Branch-locked plan: every floor of the run is the chosen branch's
	# biome (boss floor uses the same biome with a stronger spawn). Empty
	# branch_id = legacy random-roll plan — kept for showcase / debug.
	_ensure_loaded()
	const C := preload("res://scripts/constants.gd")
	if branch_id != "" and _biomes.has(branch_id):
		var plan: Array = []
		for i in C.FLOORS_PER_RUN:
			plan.append(branch_id)
		return plan
	var ids: Array = _biomes.keys()
	if ids.is_empty():
		var fallback: Array = []
		for i in C.FLOORS_PER_RUN:
			fallback.append("dungeon")
		return fallback
	var rolled: Array = []
	for i in C.FLOORS_PER_RUN:
		rolled.append(String(ids[rng.randi() % ids.size()]))
	return rolled

# Returns the branch tier (1..5) for a biome id. Defaults to 1 if missing.
static func tier_for_biome(biome_id: String) -> int:
	_ensure_loaded()
	if not _biomes.has(biome_id):
		return 1
	return int(_biomes[biome_id].get("tier", 1))

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

# Optional secondary floor pool used by the dual-floor mix system. Cells
# fall into "primary zone" or "secondary zone" based on a noise sample;
# transitions look smooth without the per-cell-confetti problem.
static func load_floor_secondary(biome: Dictionary) -> Array:
	return _expand_prefixes(biome.get("floor_secondary", []), FLOOR_DIR)

# Liquid type used by river/lake builders. "water" or "lava" or "" (none).
static func liquid_type_for(biome: Dictionary) -> String:
	return String(biome.get("liquid_type", ""))

static func load_wall_primary(biome: Dictionary) -> Array:
	# Accepts a string ("spider") for backwards compat, or an array
	# (["spider", "@stone_brick_0"]) for editor-driven explicit lists.
	var raw: Variant = biome.get("wall_primary", "")
	var prefixes: Array
	if typeof(raw) == TYPE_ARRAY:
		prefixes = raw
	else:
		prefixes = [String(raw)] if String(raw) != "" else []
	if prefixes.is_empty():
		return []
	return _expand_prefixes(prefixes, WALL_DIR)

static func load_wall_accent(biome: Dictionary) -> Array:
	return _expand_prefixes(biome.get("wall_accent", []), WALL_DIR)

static func load_wall_alternates(biome: Dictionary) -> Array:
	# Each alternate group can supply either:
	#   "prefix": "tree"     (legacy: single prefix)
	#   "prefixes": [...]    (editor-driven: list of prefixes / @stems)
	var out: Array = []
	for entry in biome.get("wall_alternates", []):
		var weight: float = float(entry.get("weight", 1))
		var prefixes: Array
		if entry.has("prefixes"):
			prefixes = entry["prefixes"]
		elif entry.has("prefix"):
			prefixes = [String(entry["prefix"])]
		else:
			continue
		var textures: Array = _expand_prefixes(prefixes, WALL_DIR)
		if textures.is_empty():
			continue
		out.append({"textures": textures, "weight": weight})
	return out

static func _expand_prefixes(prefixes: Array, dir_path: String) -> Array:
	# Two entry forms:
	#   "spider"      → prefix expansion: pulls every `spider_<digit>.png`
	#   "@spider_0"   → literal: pulls exactly `spider_0.png`
	# The `@` form lets the biome editor pick individual variants without
	# changing the dir layout. Prefix form keeps backwards compat — all
	# existing biome JSON entries are bare prefixes.
	var arr: Array = []
	var files: Array = _list_dir(dir_path)
	for prefix in prefixes:
		var entry: String = String(prefix)
		if entry.begins_with("@"):
			var stem: String = entry.substr(1)
			var fname: String = stem + ".png"
			if files.has(fname):
				var tex: Texture2D = load(dir_path + fname)
				if tex:
					arr.append(tex)
			continue
		var p: String = entry + "_"
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

# Edge-overlay autotile loader. Returns a Dictionary keyed by direction:
#   {"north": Texture, "south": Texture, "east", "west",
#    "northeast", "northwest", "southeast", "southwest",
#    "full": Texture (fully-enclosed; optional),
#    "patches": Array (random spatter; optional)}
# An empty dict signals "biome has no overlay".
static func load_edge_overlay(biome: Dictionary) -> Dictionary:
	var spec: Dictionary = biome.get("edge_overlay", {})
	if spec.is_empty():
		return {}
	var prefix: String = String(spec.get("prefix", ""))
	if prefix == "":
		return {}
	var dirs := ["north", "south", "east", "west",
		"northeast", "northwest", "southeast", "southwest"]
	var out: Dictionary = {}
	for d in dirs:
		var path: String = OVERLAY_DIR + prefix + "_" + d + ".png"
		if ResourceLoader.exists(path):
			out[d] = load(path)
	# Optional fully-covered tile (used when ALL 4 cardinals are walls).
	var full_path: String = OVERLAY_DIR + prefix + "_full.png"
	if ResourceLoader.exists(full_path):
		out["full"] = load(full_path)
	# Optional patches (random spatter for cells with no wall neighbours).
	var patches: Array = []
	for i in range(0, 8):
		var p: String = OVERLAY_DIR + prefix + "_" + str(i) + ".png"
		if ResourceLoader.exists(p):
			patches.append(load(p))
		else:
			break
	if not patches.is_empty():
		out["patches"] = patches
	out["density"] = float(spec.get("density", 0.7))
	out["patch_density"] = float(spec.get("patch_density", 0.04))
	return out

# Per-biome sigil tile pool. Biome JSON declares `sigil_set: ["sigil_circle",
# "sigil_cross", ...]` (filenames in res://assets/tiles/sigils/, no ext) and
# `sigil_density: [min, max]` rooms per BSP room. Empty array disables sigils.
static func load_sigil_set(biome: Dictionary) -> Array:
	var names: Array = biome.get("sigil_set", [])
	if names.is_empty():
		return []
	var out: Array = []
	for n in names:
		var path: String = SIGIL_DIR + String(n) + ".png"
		if ResourceLoader.exists(path):
			out.append(load(path))
	return out

# Returns Vector2i(min_per_room, max_per_room). Default [0, 0] = disabled.
static func sigil_density(biome: Dictionary) -> Vector2i:
	var d: Array = biome.get("sigil_density", [0, 0])
	var lo: int = int(d[0]) if d.size() > 0 else 0
	var hi: int = int(d[1]) if d.size() > 1 else lo
	return Vector2i(lo, hi)

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
