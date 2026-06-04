extends CanvasLayer

# Themed loading curtain — drops over the entire viewport during scene
# transitions so the player sees a deliberate "Loading…" frame instead
# of the macOS spinner cursor + scene-swap flicker. UI polish pass
# 2026-06-04.
#
# NOTE: no class_name — registered as autoload `LoadingCurtain` in
# project.godot. Reference globally as `LoadingCurtain.show(...)`.
#
# Visual stack:
#   - full-viewport pure-black ColorRect
#   - faint amber radial gradient pulse (custom _draw)
#   - centered arc spinner (custom _draw)
#   - centered "Loading…" label below the spinner
#
# Behavior:
#   - layer = 200 (above DragManager 100, above pause_menu 100)
#   - Fade-in 200ms, fade-out 300ms via tween on self_modulate.a
#   - During display: get_tree().paused = true so dungeon ticks freeze
#   - During display: Input.set_default_cursor_shape(CURSOR_ARROW) so
#     macOS spinner can't peek through

signal shown
signal hidden

const FADE_IN_SEC: float = 0.20
const FADE_OUT_SEC: float = 0.30

var _root: Control = null
var _bg: ColorRect = null
var _spinner: Node2D = null
var _label: Label = null
var _tween: Tween = null
var _spinner_t: float = 0.0
var _pulse_t: float = 0.0
var _was_paused: bool = false
var _active: bool = false

func _ready() -> void:
	layer = 200
	process_mode = Node.PROCESS_MODE_ALWAYS  # keep ticking while paused
	_root = Control.new()
	# CanvasLayer parents don't drive Control anchors — set size
	# explicitly each frame in _process. Anchors here would resolve
	# against an undefined parent rect and end up at (0,0) → invisible.
	_root.size = get_viewport().get_visible_rect().size
	# Start with mouse filter IGNORE so the invisible curtain doesn't
	# eat clicks meant for the screen below. Flipped to STOP only
	# while the curtain is actively displayed (show_curtain).
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.modulate = Color(1, 1, 1, 0)
	_root.visible = false
	add_child(_root)
	_bg = ColorRect.new()
	_bg.color = Color(0, 0, 0, 1.0)
	_bg.size = _root.size
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_bg)
	# Spinner — Node2D with custom _draw painting an arc + the radial
	# pulse halo behind it. Centered each frame.
	_spinner = Node2D.new()
	_spinner.draw.connect(_draw_spinner)
	_root.add_child(_spinner)
	# Label below the spinner.
	_label = Label.new()
	_label.text = "Loading…"
	_label.add_theme_font_size_override("font_size", 18)
	_label.add_theme_color_override("font_color", Color(0.92, 0.78, 0.45))
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.anchor_left = 0.5
	_label.anchor_right = 0.5
	_root.add_child(_label)

# Modifier-key tracker — the loading curtain is an autoload that
# always exists and ticks via PROCESS_MODE_ALWAYS, so it's the right
# place to capture modifier state for the rest of the UI. Mac
# Input.is_key_pressed reports modifier state inconsistently;
# InputEventKey carries .shift_pressed / .alt_pressed / .meta_pressed
# from the OS layer reliably. We snapshot those into UILayout's
# static flags so any tooltip / cell can call UILayout.shift_held()
# without subscribing to anything.
func _input(event: InputEvent) -> void:
	# Modifier-key tracker — see UILayout._set_modifier_state.
	# Three input event families carry modifier state:
	#   InputEventKey       — every keystroke + held repeats
	#   InputEventMouseButton — mousedown/up
	#   InputEventMouseMotion — every cursor motion (high-frequency,
	#                           used as the catch-all so the modifier
	#                           snapshot stays fresh during hover)
	if event is InputEventKey or event is InputEventMouseButton or event is InputEventMouseMotion:
		var shift: bool = event.shift_pressed if "shift_pressed" in event else false
		var alt: bool = event.alt_pressed if "alt_pressed" in event else false
		var meta: bool = event.meta_pressed if "meta_pressed" in event else false
		# Special case: a pure modifier keydown — the press IS the
		# modifier itself, not a key WITH the modifier — so shift_pressed
		# is false on that event. Detect by inspecting the keycode
		# directly. ek.pressed is true on keydown, false on keyup, and
		# `echo` distinguishes auto-repeat from a real edge.
		if event is InputEventKey:
			var ek: InputEventKey = event
			var kc_keycode: int = ek.keycode
			var kc_physical: int = ek.physical_keycode
			if kc_keycode == KEY_SHIFT or kc_physical == KEY_SHIFT:
				shift = ek.pressed
			if kc_keycode == KEY_ALT or kc_physical == KEY_ALT:
				alt = ek.pressed if not alt else alt
			if kc_keycode == KEY_META or kc_physical == KEY_META:
				meta = ek.pressed if not meta else meta
			# Debug: log modifier-only events so we can see what Godot
			# actually reports on Mac. Cheap log; printed once per
			# transition. Remove once verified.
			if kc_keycode in [KEY_SHIFT, KEY_ALT, KEY_META] or kc_physical in [KEY_SHIFT, KEY_ALT, KEY_META]:
				print("[mod] kc=%d phys=%d pressed=%s shift=%s alt=%s meta=%s echo=%s" % [
					kc_keycode, kc_physical, str(ek.pressed),
					str(shift), str(alt), str(meta), str(ek.echo),
				])
		# Treat Cmd (⌘) as alt-equivalent on Mac so power-user
		# tooltips fire on a key Mac users naturally reach for.
		UILayout._set_modifier_state(shift, alt or meta)

func _process(delta: float) -> void:
	if not _active:
		return
	_spinner_t += delta * 4.0  # arc rotation speed
	_pulse_t += delta * 1.5    # halo pulse speed
	# Resize the root + bg to match the viewport every frame so the
	# curtain always covers the full window even after a resize.
	# CanvasLayer parents don't drive anchor layout for Controls.
	var view: Vector2 = get_viewport().get_visible_rect().size
	if is_instance_valid(_root):
		_root.size = view
	if is_instance_valid(_bg):
		_bg.size = view
	if is_instance_valid(_spinner):
		_spinner.position = view * 0.5
		_spinner.queue_redraw()
	if is_instance_valid(_label):
		_label.size = Vector2(280, 24)
		_label.position = view * 0.5 + Vector2(-140, 56)

func _draw_spinner() -> void:
	# Radial halo pulse — soft amber glow under the spinner. Sine wave
	# 0.40 → 0.70 alpha breathing.
	var halo_alpha: float = 0.55 + sin(_pulse_t) * 0.15
	var halo_color: Color = Color(0.92, 0.78, 0.45, halo_alpha * 0.35)
	for i in range(6, 0, -1):
		var r: float = 60.0 + float(i) * 8.0
		var a: float = halo_color.a * pow(1.0 - float(i) / 7.0, 1.6)
		_spinner.draw_circle(Vector2.ZERO, r, Color(halo_color.r, halo_color.g, halo_color.b, a))
	# Arc spinner — sweeps a 0.6 rad arc that rotates around the center.
	var arc_color: Color = Color(0.92, 0.78, 0.45, 0.95)
	var arc_dim: Color = Color(0.92, 0.78, 0.45, 0.30)
	# Background ring (full circle, dim).
	_spinner.draw_arc(Vector2.ZERO, 32.0, 0.0, TAU, 64, arc_dim, 3.0, true)
	# Foreground sweep.
	var start: float = _spinner_t
	var sweep: float = PI * 0.6
	_spinner.draw_arc(Vector2.ZERO, 32.0, start, start + sweep, 24, arc_color, 3.5, true)
	# Inner dot pulses.
	var dot_alpha: float = 0.6 + sin(_pulse_t * 2.0) * 0.3
	_spinner.draw_circle(Vector2.ZERO, 4.0, Color(1.0, 0.92, 0.55, dot_alpha))

# Public API ──────────────────────────────────────────────────────────

# Convenience: drop the curtain over a scene swap. Fades in fast,
# holds, fades out — total ~700ms so the player sees a real loading
# beat regardless of how fast the swap actually completes.
# Replaces the manual show → await → hide pattern (which deadlocked
# main._swap when the tree paused). Item-overhaul UI pass 2026-06-04.
const SWAP_HOLD_SEC: float = 0.30
func show_for_swap(label: String = "Loading…") -> void:
	show_curtain(label)
	# Hide after the hold via a one-shot timer. Timer is process_mode
	# ALWAYS so it ticks even if some caller paused the tree.
	var t := Timer.new()
	t.one_shot = true
	t.wait_time = FADE_IN_SEC + SWAP_HOLD_SEC
	t.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(t)
	t.timeout.connect(func():
		hide_curtain()
		t.queue_free()
	)
	t.start()

func show_curtain(label: String = "Loading…") -> void:
	if _active:
		# Already up — just update label.
		if is_instance_valid(_label):
			_label.text = label
		return
	_active = true
	if is_instance_valid(_label):
		_label.text = label
	if is_instance_valid(_root):
		_root.visible = true
		_root.mouse_filter = Control.MOUSE_FILTER_STOP  # eat clicks while up
	# Force arrow cursor so the macOS spinner doesn't peek through.
	# Note: we deliberately do NOT pause the tree here — pausing was
	# blocking await get_tree().process_frame which deadlocked the
	# scene swap (player click did nothing visible). The curtain is
	# only up for ~one frame each direction so dungeon ticks during
	# the brief overlap don't matter.
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	# Fade in.
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_root, "modulate:a", 1.0, FADE_IN_SEC)
	shown.emit()

func hide_curtain() -> void:
	if not _active:
		return
	_active = false
	# Fade out → hide root.
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_root, "modulate:a", 0.0, FADE_OUT_SEC)
	_tween.tween_callback(func():
		if is_instance_valid(_root):
			_root.visible = false
			_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hidden.emit()
	)

# Convenience wrapper — show curtain, await one frame, run callable,
# await one frame for the new scene to settle, hide curtain. Used by
# main._swap to keep transition bookkeeping in one place.
func wrap(callable: Callable, label: String = "Loading…") -> void:
	show_curtain(label)
	await get_tree().process_frame
	callable.call()
	await get_tree().process_frame
	hide_curtain()

func is_active() -> bool:
	return _active
