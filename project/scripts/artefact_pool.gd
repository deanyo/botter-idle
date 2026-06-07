class_name ArtefactPool
extends RefCounted

const DIR := "res://assets/tiles/items/artefacts/"

static var _weapons: Array = []
static var _armors: Array = []
static var _loaded: bool = false

static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	# Manifest first — works on both desktop and HTML5. DirAccess on
	# res:// returns null in web exports (virtualized FS), so we ship
	# a baked listing in data/tile_dir_manifest.json.
	var names: Array = _list_artefact_files()
	for n in names:
		var s: String = String(n)
		if s.begins_with("wpn_"):
			_weapons.append(s)
		elif s.begins_with("arm_"):
			_armors.append(s)

static func _list_artefact_files() -> Array:
	var f := FileAccess.open("res://data/tile_dir_manifest.json", FileAccess.READ)
	if f != null:
		var parsed: Variant = JSON.parse_string(f.get_as_text())
		if typeof(parsed) == TYPE_DICTIONARY and parsed.has(DIR):
			return parsed[DIR]
	var arr: Array = []
	var dir := DirAccess.open(DIR)
	if dir == null:
		return arr
	dir.list_dir_begin()
	var n := dir.get_next()
	while n != "":
		if not dir.current_is_dir() and n.ends_with(".png"):
			arr.append(n)
		n = dir.get_next()
	dir.list_dir_end()
	return arr

static func pick_for_slot(slot: String, rng: RandomNumberGenerator) -> String:
	_ensure_loaded()
	var pool: Array = _armors
	if slot == "weapon":
		pool = _weapons
	if pool.is_empty():
		return ""
	return String(pool[rng.randi_range(0, pool.size() - 1)])

static func texture_for(name: String) -> Texture2D:
	if name == "":
		return null
	return load(DIR + name)
