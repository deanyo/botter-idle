class_name SaveState
extends RefCounted

const SAVE_PATH := "user://botter_save.json"

static func load_state() -> Dictionary:
	if not FileAccess.file_exists(SAVE_PATH):
		return _default()
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return _default()
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return _default()
	var state: Dictionary = parsed
	for k in _default().keys():
		if not state.has(k):
			state[k] = _default()[k]
	_migrate(state)
	return state

static func _migrate(state: Dictionary) -> void:
	var inv: Array = state.inventory
	for i in inv.size():
		if typeof(inv[i]) == TYPE_STRING:
			inv[i] = {"base_id": inv[i], "instance_id": "legacy_%d" % i, "affixes": []}
	var eq: Dictionary = state.equipped
	for slot in eq.keys():
		var v: Variant = eq[slot]
		if typeof(v) == TYPE_STRING:
			if v == "":
				eq[slot] = null
			else:
				eq[slot] = {"base_id": v, "instance_id": "legacy_eq_%s" % slot, "affixes": []}

static func save_state(state: Dictionary) -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(state, "  "))

static func _default() -> Dictionary:
	return {
		"gold": 0,
		"level": 1,
		"xp": 0,
		"inventory": [],
		"equipped": {
			"weapon": null,
			"armor": null,
			"helm": null,
			"boots": null,
			"shield": null,
		},
		"runs_completed": 0,
		"highest_floor": 0,
	}
