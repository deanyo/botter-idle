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
	var dir := DirAccess.open(DIR)
	if dir == null:
		return
	dir.list_dir_begin()
	var n := dir.get_next()
	while n != "":
		if not dir.current_is_dir() and n.ends_with(".png"):
			if n.begins_with("wpn_"):
				_weapons.append(n)
			elif n.begins_with("arm_"):
				_armors.append(n)
		n = dir.get_next()
	dir.list_dir_end()

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
