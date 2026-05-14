extends Control

signal play_pressed
signal video_options_pressed

@onready var play_btn: Button = $V/Buttons/Play
@onready var options_btn: Button = $V/Buttons/Options
@onready var quit_btn: Button = $V/Buttons/Quit

func _ready() -> void:
	play_btn.pressed.connect(func(): play_pressed.emit())
	options_btn.pressed.connect(func(): video_options_pressed.emit())
	quit_btn.pressed.connect(func(): get_tree().quit())
