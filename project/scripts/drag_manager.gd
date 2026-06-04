extends CanvasLayer

# NOTE: no class_name — this script is registered as an autoload
# named `DragManager` in project.godot, so referencing it by class_name
# would collide. Access globally as `DragManager` (the autoload).

# Manual mouse-tracking drag-and-drop. Bypasses Godot's _get_drag_data
# system because that path has subtle issues with our nested
# ScrollContainer + GridContainer + Control hierarchies (focus-eats-press,
# Button-children-eat-press, etc). This implementation tracks the mouse
# directly and handles drop detection by Control.has_point() on release.
#
# Usage from cells:
#   - On left-press: DragManager.begin_drag(payload, preview_texture, [tint])
#   - On hover during drag: DragManager.set_hover_target(self, accepts)
#   - DragManager fires `drop` signal when the drag releases over a
#     valid target.
#
# Autoload: registered as a singleton via project.godot autoload
# (added in this session). Reachable as `DragManager` globally.
#
# `payload` is freeform — outpost passes a Dictionary describing what's
# being dragged (source_kind, inv_index, slot_id, item_slot). The drop
# handler reads it and performs the swap.

signal drag_started(payload: Dictionary)
signal drag_ended(payload: Dictionary, dropped_on: Variant)

var _active: bool = false
var _payload: Dictionary = {}
# Receivers register themselves on hover so we know who's under the
# cursor without iterating the whole tree on release. Last register
# wins (the actual visible drop target). Cleared on drag end.
var _hover_target: Variant = null
var _hover_accepts: bool = false

# Preview node reparented under us during drag. Free + null on end.
var _preview: Node2D = null
var _preview_sprite: Sprite2D = null
const PREVIEW_SIZE := 48
const DRAG_THRESHOLD_PX := 6.0  # how far cursor moves before drag activates

# Pending-drag state: a press happened but cursor hasn't moved past the
# threshold yet. begin_drag is called eagerly from cell gui_input, but
# we hold off on the visual until the cursor moves enough.
var _pending: bool = false
var _pending_payload: Dictionary = {}
var _pending_texture: Texture2D = null
var _pending_tint: Color = Color(1, 1, 1, 1)
var _press_pos: Vector2 = Vector2.ZERO

func _ready() -> void:
	# Sit above all UI so the preview renders on top of everything.
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS

func _process(_delta: float) -> void:
	# Update preview position to follow cursor during a live drag.
	if _active and _preview != null and is_instance_valid(_preview):
		_preview.position = get_viewport().get_mouse_position()

func _input(event: InputEvent) -> void:
	# Promote pending → active once cursor crosses the threshold. This
	# delays the visual long enough that a click (no motion) doesn't
	# spawn a preview.
	if _pending and event is InputEventMouseMotion:
		var cur: Vector2 = get_viewport().get_mouse_position()
		if cur.distance_to(_press_pos) > DRAG_THRESHOLD_PX:
			_promote_pending()
	# Release ends a drag (or cancels a pending one).
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
			if _active:
				_finish_drag()
			elif _pending:
				_pending = false
				_pending_payload = {}
				_pending_texture = null

# Public — call from a cell's _gui_input on left-press. We stage a
# pending drag; it only "activates" (preview shown, drop targets
# accepting) once the cursor moves past the threshold. That way a
# straight click doesn't trigger drag UX.
func begin_drag(payload: Dictionary, preview_texture: Texture2D, tint: Color = Color(1, 1, 1, 1)) -> void:
	if _active or _pending:
		return
	_pending = true
	_pending_payload = payload.duplicate()
	_pending_texture = preview_texture
	_pending_tint = tint
	_press_pos = get_viewport().get_mouse_position()

# Cells call this on _gui_input mouse-motion when active. We track
# the latest one so the drop on release knows the target.
func set_hover_target(target: Variant, accepts: bool) -> void:
	if not _active:
		return
	_hover_target = target
	_hover_accepts = accepts

# Cells call this on mouse-exit so we don't drop on stale targets.
func clear_hover_target(target: Variant) -> void:
	if _hover_target == target:
		_hover_target = null
		_hover_accepts = false

func is_dragging() -> bool:
	return _active

func get_payload() -> Dictionary:
	return _payload

func _promote_pending() -> void:
	_active = true
	_payload = _pending_payload
	# Build the floating preview node: a Sprite2D with the dragged
	# item's tile, at half-opacity, sized to PREVIEW_SIZE px.
	_preview = Node2D.new()
	_preview_sprite = Sprite2D.new()
	if _pending_texture != null:
		_preview_sprite.texture = _pending_texture
	_preview_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_preview_sprite.modulate = Color(_pending_tint.r, _pending_tint.g, _pending_tint.b, 0.85)
	# Scale the sprite so its rendered size is PREVIEW_SIZE.
	if _preview_sprite.texture:
		var src_w: float = _preview_sprite.texture.get_width()
		var src_h: float = _preview_sprite.texture.get_height()
		var fit: float = float(PREVIEW_SIZE) / max(src_w, src_h)
		_preview_sprite.scale = Vector2(fit, fit)
	_preview.add_child(_preview_sprite)
	add_child(_preview)
	_preview.position = get_viewport().get_mouse_position()
	_pending = false
	_pending_payload = {}
	_pending_texture = null
	drag_started.emit(_payload)

func _finish_drag() -> void:
	var dropped: Variant = _hover_target if _hover_accepts else null
	var payload: Dictionary = _payload
	# Tear down preview before signal dispatch so handlers can't
	# observe a stale state.
	if _preview != null and is_instance_valid(_preview):
		_preview.queue_free()
	_preview = null
	_preview_sprite = null
	_active = false
	_payload = {}
	_hover_target = null
	_hover_accepts = false
	drag_ended.emit(payload, dropped)
