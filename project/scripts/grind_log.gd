class_name GrindLog
extends RefCounted

const LOG_PATH := "user://grind.log"

static var _file: FileAccess = null
static var _enabled: bool = false

static func enable() -> void:
	_enabled = true
	_file = FileAccess.open(LOG_PATH, FileAccess.WRITE)

static func disable() -> void:
	if _file:
		_file.close()
		_file = null
	_enabled = false

static func log_line(msg: String) -> void:
	print(msg)
	if not _enabled:
		return
	if _file == null:
		_file = FileAccess.open(LOG_PATH, FileAccess.WRITE)
	if _file:
		_file.store_line(msg)
		_file.flush()
