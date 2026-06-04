class_name UILayout
extends RefCounted

# Layout helpers for the responsive UI pass (2026-06-04). All screens
# rebuild their layout from scratch in response to viewport size
# changes, debounced so dragging the window doesn't thrash. Each
# screen reads `current_shape(view)` to pick a WIDE or TALL layout
# branch.
#
# Aspect threshold of 1.20 means anything wider than 1.20× tall is
# WIDE (covers 4:3 / 5:4 / all 16:9+ desktop). Below 1.20 → TALL
# (portrait phones, vertical desktop windows).
#
# Subscribers attach to get_viewport().size_changed via
# subscribe_resize(); the helper debounces by 250ms before calling
# the user-supplied callback. Caller is responsible for tearing
# down + rebuilding their UI on each callback fire.

enum Shape { WIDE, TALL }

# Cross-platform modifier-key state. On macOS the physical-key /
# unified-key polls (Input.is_key_pressed) don't reliably reflect
# modifier-only presses. We snapshot modifier state via the
# `_input` callback in `ModifierTracker` (autoload-shaped helper
# below) which receives every InputEventKey + InputEventMouseButton
# with full .shift_pressed / .alt_pressed / .meta_pressed fields
# populated by the OS layer.
#
# Helpers always return the latest known state. Callers don't need
# to know about the tracker — just call shift_held() / alt_held().
#
# On Mac, alt_held also returns true when Cmd (⌘ / KEY_META) is
# pressed because mac users naturally reach for Cmd as the "modifier
# for power-user features." Option key (⌥ → KEY_ALT) still works.

static var _shift_held_state: bool = false
static var _alt_held_state: bool = false

# Called from a tracker node's _input handler — see
# `ModifierTrackerHelper.gd` autoload pattern. We set the static
# flags so any code in any scene can poll without subscribing.
static func _set_modifier_state(shift: bool, alt: bool) -> void:
	_shift_held_state = shift
	_alt_held_state = alt

static func shift_held() -> bool:
	# Belt-and-braces: poll the Input singleton too so single-press
	# scenarios where _input hasn't fired yet still work.
	return _shift_held_state or Input.is_key_pressed(KEY_SHIFT) or Input.is_physical_key_pressed(KEY_SHIFT)

static func alt_held() -> bool:
	return (
		_alt_held_state
		or Input.is_key_pressed(KEY_ALT) or Input.is_physical_key_pressed(KEY_ALT)
		# Mac convenience: Cmd ⌘ also counts as "alt" for the
		# alt-extended tooltip. Option ⌥ users still work via KEY_ALT.
		or Input.is_key_pressed(KEY_META) or Input.is_physical_key_pressed(KEY_META)
	)

const ASPECT_THRESHOLD: float = 1.20
const RESIZE_DEBOUNCE_SEC: float = 0.25
# Centered panoramic content band on ultrawide displays — content
# panes clamp to this width and the edges show BG_DEEP. Per the
# user's call: wide monitors get a panoramic centered UI.
const ULTRAWIDE_THRESHOLD: int = 1920
const PANORAMIC_BAND_WIDTH: int = 1920

static func current_shape(view: Vector2) -> Shape:
	if view.y <= 0.0:
		return Shape.WIDE
	var aspect: float = view.x / view.y
	return Shape.WIDE if aspect >= ASPECT_THRESHOLD else Shape.TALL

# Safe-area gutter — distance from viewport edge to first content
# element. 16px on small viewports; scales up to 32px for ultrawide
# so the panoramic centered UI has breathing room.
static func safe_gutter(view: Vector2) -> int:
	if view.x >= float(ULTRAWIDE_THRESHOLD):
		return 32
	if view.x >= 1280.0:
		return 20
	return 16

# Returns the centered panoramic content rect when the viewport is
# wider than ULTRAWIDE_THRESHOLD. On normal-width viewports just
# returns (0, 0) → view. Screens use this to place the actual UI
# inside the band; the edges become BG_DEEP letterboxes.
static func panoramic_rect(view: Vector2) -> Rect2:
	if view.x <= float(PANORAMIC_BAND_WIDTH):
		return Rect2(Vector2.ZERO, view)
	var pad_x: float = (view.x - float(PANORAMIC_BAND_WIDTH)) * 0.5
	return Rect2(Vector2(pad_x, 0.0), Vector2(float(PANORAMIC_BAND_WIDTH), view.y))

# Subscribe `owner` to viewport size_changed with a debounced
# callback. Returns the Timer node created (caller doesn't need to
# manage it — auto-frees with the owner). The first invocation
# inside RESIZE_DEBOUNCE_SEC is dropped; subsequent ones reset the
# timer. When the user stops resizing for that long, callback fires.
#
# Pattern in screen scripts:
#     UILayout.subscribe_resize(self, _on_viewport_resized)
# Where _on_viewport_resized() rebuilds the layout from scratch.
static func subscribe_resize(owner: Node, callback: Callable) -> Timer:
	if not is_instance_valid(owner):
		return null
	var timer := Timer.new()
	timer.one_shot = true
	timer.wait_time = RESIZE_DEBOUNCE_SEC
	timer.process_mode = Node.PROCESS_MODE_ALWAYS  # tick during pause
	timer.timeout.connect(callback)
	owner.add_child(timer)
	# Connect viewport size_changed → restart the timer. Each resize
	# event resets the countdown so callback only fires once after the
	# user stops dragging.
	owner.get_viewport().size_changed.connect(func():
		if is_instance_valid(timer):
			timer.start()
	)
	return timer

# Standard sidebar width clamp — scales 25% of viewport width with
# 320 / 480 px floor / ceiling. Used by the HUD sidebar.
static func sidebar_width(view: Vector2) -> int:
	return clampi(int(view.x * 0.25), 320, 480)

# Outpost paperdoll pane width — slightly wider than the HUD sidebar
# since it hosts a larger paperdoll + the spell row.
static func paperdoll_pane_width(view: Vector2) -> int:
	return clampi(int(view.x * 0.32), 280, 520)
