class_name ItemsDb
extends RefCounted

# Per-session cache of project/data/items.json + enemies.json +
# monster_mods.json. items.json is ~330KB → ~30-60ms to JSON.parse on
# desktop and re-loaded by dungeon._ready every dungeon entry plus
# main._apply_offline_progress on launch. Caching it once per Godot
# session removes the redundant cost from every load screen. Perf
# pass 2026-06-04.
#
# Usage:
#   var items_db: Dictionary = ItemsDb.items()
#   var enemies: Dictionary = ItemsDb.enemies()
#   var mods: Array = ItemsDb.monster_mods()
#
# All three load lazily on first call. preload_all() warms the cache
# at startup (call from main._ready) so the first dungeon entry pays
# zero parse cost.

const ITEMS_PATH := "res://data/items.json"
const ENEMIES_PATH := "res://data/enemies.json"
const MONSTER_MODS_PATH := "res://data/monster_mods.json"

static var _items: Dictionary = {}
static var _enemies: Dictionary = {}
static var _monster_mods: Array = []
static var _items_loaded: bool = false
static var _enemies_loaded: bool = false
static var _mods_loaded: bool = false

static func items() -> Dictionary:
	if not _items_loaded:
		var raw: Dictionary = _read_json(ITEMS_PATH)
		var by_id: Dictionary = {}
		for it in raw.get("items", []):
			by_id[it.id] = it
		_items = by_id
		_items_loaded = true
	return _items

static func enemies() -> Dictionary:
	if not _enemies_loaded:
		_enemies = _read_json(ENEMIES_PATH)
		_enemies_loaded = true
	return _enemies

static func monster_mods() -> Array:
	if not _mods_loaded:
		var raw: Dictionary = _read_json(MONSTER_MODS_PATH)
		_monster_mods = raw.get("mods", [])
		_mods_loaded = true
	return _monster_mods

# Warm the cache at startup so the first dungeon load doesn't pay a
# 30-60ms parse hit. Safe to call multiple times — _<x>_loaded gates
# each.
static func preload_all() -> void:
	items()
	enemies()
	monster_mods()

static func _read_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("ItemsDb: failed to open %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("ItemsDb: failed to parse %s" % path)
		return {}
	return parsed
