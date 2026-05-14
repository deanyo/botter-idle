extends Control

signal back_pressed

const VS := preload("res://scripts/video_settings.gd")

@onready var mode_opt: OptionButton = $V/Form/ModeRow/Mode
@onready var res_opt: OptionButton = $V/Form/ResRow/Resolution
@onready var vsync_opt: OptionButton = $V/Form/VsyncRow/Vsync
@onready var back_btn: Button = $V/Buttons/Back

var settings: Dictionary = {}
var ready_done: bool = false

func _ready() -> void:
	settings = VS.load_settings()
	_populate_modes()
	_populate_resolutions()
	_populate_vsync()
	mode_opt.item_selected.connect(_on_changed)
	res_opt.item_selected.connect(_on_changed)
	vsync_opt.item_selected.connect(_on_changed)
	back_btn.pressed.connect(func(): back_pressed.emit())
	ready_done = true

func _populate_modes() -> void:
	mode_opt.clear()
	var modes: Array = [VS.MODE_WINDOWED, VS.MODE_BORDERLESS, VS.MODE_FULLSCREEN]
	var labels: Array = ["Windowed", "Borderless", "Fullscreen"]
	for i in modes.size():
		mode_opt.add_item(labels[i])
		mode_opt.set_item_metadata(i, modes[i])
	var current: String = String(settings.get("mode", VS.MODE_WINDOWED))
	for i in modes.size():
		if modes[i] == current:
			mode_opt.select(i)
			break

func _populate_resolutions() -> void:
	res_opt.clear()
	for i in VS.PRESETS.size():
		var p: Dictionary = VS.PRESETS[i]
		res_opt.add_item(String(p.label))
		res_opt.set_item_metadata(i, String(p.value))
	var current: String = String(settings.get("resolution", "native"))
	for i in VS.PRESETS.size():
		if String(VS.PRESETS[i].value) == current:
			res_opt.select(i)
			break

func _populate_vsync() -> void:
	vsync_opt.clear()
	vsync_opt.add_item("On")
	vsync_opt.set_item_metadata(0, true)
	vsync_opt.add_item("Off")
	vsync_opt.set_item_metadata(1, false)
	vsync_opt.select(0 if bool(settings.get("vsync", true)) else 1)

func _on_changed(_idx: int = 0) -> void:
	if not ready_done:
		return
	settings["mode"] = String(mode_opt.get_item_metadata(mode_opt.selected))
	settings["resolution"] = String(res_opt.get_item_metadata(res_opt.selected))
	settings["vsync"] = bool(vsync_opt.get_item_metadata(vsync_opt.selected))
	VS.save_settings(settings)
	VS.apply(settings)
