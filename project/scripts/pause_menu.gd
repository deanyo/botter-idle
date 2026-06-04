# Universal Escape menu. One instance lives at main.gd, listens for
# `ui_cancel` (Esc), and renders a centered panel with context-aware
# options. Pauses the SceneTree while open.
#
# Mounted at the root, above the active screen, so it works in main
# menu, outpost, and dungeon. Skipped during auto-grind (would freeze
# the harness) and screenshot mode (would obscure the capture).
#
# Layout: full-screen dimmed underlay + centered 360x420 panel with
# vertical button stack. Built in code so it can adapt to the active
# screen (Abandon Run only shows in dungeon, Back to Main Menu hides
# when already there).

class_name PauseMenu
extends CanvasLayer

const VS := preload("res://scripts/video_settings.gd")
const VIDEO_OPTIONS_SCENE := preload("res://scenes/video_options.tscn")
const FX_TUNER_SCENE := preload("res://scenes/fx_tuner.tscn")

signal resume_requested
signal video_settings_requested
signal main_menu_requested
signal abandon_requested
signal quit_requested

const COL_AMBER := Color(0.92, 0.78, 0.45)
const COL_DIM := Color(0.7, 0.6, 0.4)
const COL_PANEL := Color(0.0, 0.0, 0.0, 1.0)  # pure-black, OLED — UI pass 2026-06-04
const COL_PANEL_BORDER := Color(0.45, 0.36, 0.18, 0.85)

var _underlay: ColorRect = null
var _panel_root: Control = null
var _video_overlay: Control = null
# True when the dungeon scene is the active one — show Abandon Run.
var in_dungeon: bool = false
# True when the main menu is the active one — hide Back to Main Menu.
var in_main_menu: bool = false

func _ready() -> void:
	# Sit above HUD chrome (layer 50). Always-process so Esc unpauses.
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build()

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		# If video options is open, treat Esc as "back to pause menu".
		if _video_overlay != null and is_instance_valid(_video_overlay):
			_close_video_overlay()
			get_viewport().set_input_as_handled()
			return
		if visible:
			_resume()
		else:
			_open()
		get_viewport().set_input_as_handled()

# Update which buttons are visible based on which screen is active.
# Called by main.gd after every _swap.
func set_context(screen_name: String) -> void:
	in_dungeon = screen_name == "dungeon"
	in_main_menu = screen_name == "main_menu"
	if visible:
		_rebuild_buttons()

func _open() -> void:
	visible = true
	get_tree().paused = true
	_rebuild_buttons()

func _resume() -> void:
	visible = false
	get_tree().paused = false
	resume_requested.emit()

func _build() -> void:
	# Dimmed underlay.
	_underlay = ColorRect.new()
	_underlay.color = Color(0, 0, 0, 0.55)
	_underlay.anchor_right = 1.0
	_underlay.anchor_bottom = 1.0
	_underlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_underlay)

	# Panel — 360x420 centered.
	_panel_root = Control.new()
	_panel_root.anchor_left = 0.5
	_panel_root.anchor_right = 0.5
	_panel_root.anchor_top = 0.5
	_panel_root.anchor_bottom = 0.5
	_panel_root.offset_left = -180
	_panel_root.offset_right = 180
	_panel_root.offset_top = -240
	_panel_root.offset_bottom = 240
	_panel_root.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_panel_root)

	var bg := ColorRect.new()
	bg.color = COL_PANEL
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel_root.add_child(bg)
	var border := ReferenceRect.new()
	border.anchor_right = 1.0
	border.anchor_bottom = 1.0
	border.border_color = COL_PANEL_BORDER
	border.border_width = 2.0
	border.editor_only = false
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel_root.add_child(border)

	var title := Label.new()
	title.text = "Paused"
	title.add_theme_color_override("font_color", COL_AMBER)
	title.add_theme_font_size_override("font_size", 28)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(0, 24)
	title.size = Vector2(360, 36)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel_root.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Esc to resume"
	subtitle.add_theme_color_override("font_color", COL_DIM)
	subtitle.add_theme_font_size_override("font_size", 13)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.position = Vector2(0, 60)
	subtitle.size = Vector2(360, 18)
	subtitle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel_root.add_child(subtitle)

# Buttons are rebuilt every open so context-dependent ones (Abandon,
# Back to Main Menu) reflect the current screen. Cheap — 5 buttons max.
var _button_holder: VBoxContainer = null

func _rebuild_buttons() -> void:
	if _button_holder != null and is_instance_valid(_button_holder):
		_button_holder.queue_free()
	_button_holder = VBoxContainer.new()
	_button_holder.position = Vector2(40, 100)
	_button_holder.size = Vector2(280, 350)
	_button_holder.add_theme_constant_override("separation", 10)
	_panel_root.add_child(_button_holder)

	_button_holder.add_child(_make_button("Resume", _resume))
	_button_holder.add_child(_make_button("Video Settings", _open_video_settings))
	_button_holder.add_child(_make_button("FX Tuner", _open_fx_tuner))
	if in_dungeon:
		_button_holder.add_child(_make_button("Abandon Run", _abandon, COL_DIM))
	if not in_main_menu:
		_button_holder.add_child(_make_button("Back to Main Menu", _to_main_menu))
	_button_holder.add_child(_make_button("Quit Game", _quit, COL_DIM))

func _make_button(text: String, on_pressed: Callable, fg: Color = COL_AMBER) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(280, 44)
	btn.add_theme_color_override("font_color", fg)
	btn.add_theme_color_override("font_hover_color", COL_AMBER)
	btn.add_theme_font_size_override("font_size", 18)
	btn.pressed.connect(on_pressed)
	return btn

func _open_video_settings() -> void:
	_open_overlay(VIDEO_OPTIONS_SCENE)

func _open_fx_tuner() -> void:
	_open_overlay(FX_TUNER_SCENE)

func _open_overlay(scene: PackedScene) -> void:
	_panel_root.visible = false
	var opts: Node = scene.instantiate()
	# Keep the underlay so the screen stays dimmed beneath the overlay.
	_video_overlay = opts as Control
	add_child(_video_overlay)
	if _video_overlay.has_signal("back_pressed"):
		_video_overlay.back_pressed.connect(_close_video_overlay)

func _close_video_overlay() -> void:
	if _video_overlay != null and is_instance_valid(_video_overlay):
		_video_overlay.queue_free()
	_video_overlay = null
	if _panel_root != null and is_instance_valid(_panel_root):
		_panel_root.visible = true

func _to_main_menu() -> void:
	# Unpause first — main_menu_requested will swap scenes; tree.paused
	# stays true through the swap and breaks the new scene's _ready.
	visible = false
	get_tree().paused = false
	main_menu_requested.emit()

func _abandon() -> void:
	visible = false
	get_tree().paused = false
	abandon_requested.emit()

func _quit() -> void:
	get_tree().paused = false
	quit_requested.emit()
