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
#   - centered paperdoll rig (the player's bot, scaled up large)
#   - "Loading…" label
#   - thin progress bar that animates left → right over the load duration
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
var _paperdoll_holder: Node2D = null
var _paperdoll_rig: Node2D = null
var _label: Label = null
var _bar_bg: ColorRect = null
var _bar_fill: ColorRect = null
var _bar_max_w: int = 320
var _tween: Tween = null
var _bar_tween: Tween = null
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
	# Paperdoll holder — the player's bot rig is rebuilt on each show
	# so it reflects the current equipped state. 2026-06-06.
	_paperdoll_holder = Node2D.new()
	_root.add_child(_paperdoll_holder)
	# Label above the bar.
	_label = Label.new()
	_label.text = "Loading…"
	_label.add_theme_font_size_override("font_size", 20)
	_label.add_theme_color_override("font_color", Color(0.92, 0.78, 0.45))
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_label)
	# Progress bar — thin amber bar that fills left → right over the
	# load duration. Synced to a tween in show_curtain so it visually
	# tracks the FADE_IN_SEC + SWAP_HOLD_SEC window.
	_bar_bg = ColorRect.new()
	_bar_bg.color = Color(0.18, 0.15, 0.10, 1.0)
	_bar_bg.size = Vector2(_bar_max_w, 6)
	_bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_bar_bg)
	_bar_fill = ColorRect.new()
	_bar_fill.color = Color(0.92, 0.78, 0.45, 1.0)
	_bar_fill.size = Vector2(0, 6)
	_bar_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_bar_fill)

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
		# Treat Cmd (⌘) as alt-equivalent on Mac so power-user
		# tooltips fire on a key Mac users naturally reach for.
		UILayout._set_modifier_state(shift, alt or meta)

func _process(delta: float) -> void:
	if not _active:
		return
	_pulse_t += delta * 1.5
	# Resize the root + bg to match the viewport every frame so the
	# curtain always covers the full window even after a resize.
	# CanvasLayer parents don't drive anchor layout for Controls.
	var view: Vector2 = get_viewport().get_visible_rect().size
	if is_instance_valid(_root):
		_root.size = view
	if is_instance_valid(_bg):
		_bg.size = view
	# Paperdoll centered, scaled large.
	if is_instance_valid(_paperdoll_holder):
		_paperdoll_holder.position = Vector2(view.x * 0.5, view.y * 0.5 - 30)
	# Label above the bar.
	if is_instance_valid(_label):
		_label.size = Vector2(280, 28)
		_label.position = Vector2(view.x * 0.5 - 140, view.y * 0.5 + 110)
	# Progress bar centered below the label.
	if is_instance_valid(_bar_bg):
		_bar_bg.position = Vector2(view.x * 0.5 - _bar_max_w * 0.5, view.y * 0.5 + 144)
	if is_instance_valid(_bar_fill):
		_bar_fill.position = _bar_bg.position

# Build the paperdoll rig from the active save and stash it under
# _paperdoll_holder. Called on each show_curtain so the rig reflects
# the player's current loadout — they see the bot they'll deploy.
# Falls back silently if SaveState / PaperdollRenderer / ItemsDb
# aren't reachable from this autoload context.
const _PAPERDOLL_RIG_SCALE: float = 6.0
const _ITEMS_PATH: String = "res://data/items.json"
func _rebuild_paperdoll() -> void:
	if _paperdoll_holder == null or not is_instance_valid(_paperdoll_holder):
		return
	# Wipe previous rig so re-shows reflect equip changes.
	for c in _paperdoll_holder.get_children():
		c.queue_free()
	_paperdoll_rig = null
	if SaveState == null:
		return
	var save: Dictionary = SaveState.load_state()
	if save.is_empty():
		return
	# Items DB — small JSON load; happens once per show so it's cheap.
	var items_db: Dictionary = {}
	var f := FileAccess.open(_ITEMS_PATH, FileAccess.READ)
	if f != null:
		var parsed: Variant = JSON.parse_string(f.get_as_text())
		if typeof(parsed) == TYPE_DICTIONARY:
			for it in parsed.get("items", []):
				items_db[it.id] = it
	var equipped: Dictionary = save.get("equipped", {})
	var species: String = String(save.get("species", ""))
	# static_only=true skips infinite-loop tweens — the curtain is
	# already moving via the load bar; we don't need orbit/glow on the
	# rig too.
	var built: Dictionary = PaperdollRenderer.build_rig(items_db, equipped, species, true)
	var rig: Node2D = built.get("rig", null)
	if rig != null:
		rig.scale = Vector2(_PAPERDOLL_RIG_SCALE, _PAPERDOLL_RIG_SCALE)
		_paperdoll_holder.add_child(rig)
		_paperdoll_rig = rig

# Public API ──────────────────────────────────────────────────────────

# Convenience: drop the curtain over a scene swap. Fades in fast,
# holds, fades out — total ~700ms so the player sees a real loading
# beat regardless of how fast the swap actually completes.
# Replaces the manual show → await → hide pattern (which deadlocked
# main._swap when the tree paused). Item-overhaul UI pass 2026-06-04.
const SWAP_HOLD_SEC: float = 0.30
# Maximum time to keep the curtain up while waiting on a "ready"
# signal (hold_until_signal). Safety net so a slow loader can't strand
# the curtain forever on a busted run. Perf pass 2026-06-04.
const SIGNAL_TIMEOUT_SEC: float = 5.0
func show_for_swap(label: String = "Loading…") -> void:
	# When a caller has already painted the curtain via show_curtain()
	# directly (e.g. main._on_deploy preloading the dungeon) the curtain
	# is already visible — just queue a hide timer and skip the
	# show_curtain call so we don't reset the alpha tween.
	var was_active: bool = _active
	show_curtain(label)
	# Hide after the hold via a one-shot timer. Timer is process_mode
	# ALWAYS so it ticks even if some caller paused the tree.
	var t := Timer.new()
	t.one_shot = true
	t.wait_time = (0.0 if was_active else FADE_IN_SEC) + SWAP_HOLD_SEC
	t.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(t)
	t.timeout.connect(func():
		hide_curtain()
		t.queue_free()
	)
	t.start()

# Show the curtain and keep it up until `signal_obj.<signal_name>`
# fires (or SIGNAL_TIMEOUT_SEC elapses, whichever first). Tighter UX
# than show_for_swap when the wait is determined by a real "ready"
# event — e.g. dungeon.floor_started fires once the floor is fully
# built, so the curtain hides exactly when there's something to see.
# Perf pass 2026-06-04.
func hold_until_signal(signal_obj: Object, signal_name: String, label: String = "Loading…") -> void:
	show_curtain(label)
	if signal_obj == null or not signal_obj.has_signal(signal_name):
		# Fallback to a fixed hold so the curtain still hides cleanly.
		var t0 := Timer.new()
		t0.one_shot = true
		t0.wait_time = FADE_IN_SEC + SWAP_HOLD_SEC
		t0.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(t0)
		t0.timeout.connect(func():
			hide_curtain()
			t0.queue_free()
		)
		t0.start()
		return
	# One-element array so the bool mutation actually persists across
	# the two lambdas. GDScript captures locals by value, so a plain
	# `var hidden_yet: bool = false` would let both the signal AND
	# the safety timer fire hide_curtain().
	var hidden_flag: Array = [false]
	var hide_once = func():
		if hidden_flag[0]:
			return
		hidden_flag[0] = true
		hide_curtain()
	# Connect ONESHOT so we don't keep an active reference past the
	# first fire.
	signal_obj.connect(signal_name, hide_once, CONNECT_ONE_SHOT)
	# Safety-net timer — caps the curtain duration even if the signal
	# never fires.
	var safety := Timer.new()
	safety.one_shot = true
	safety.wait_time = SIGNAL_TIMEOUT_SEC
	safety.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(safety)
	safety.timeout.connect(func():
		hide_once.call()
		safety.queue_free()
	)
	safety.start()

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
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	# Build the paperdoll rig from the player's current save.
	_rebuild_paperdoll()
	# Animate the load bar from 0 → full over the expected hold window.
	# Visual progress cue, even though we don't have a real percent value.
	if is_instance_valid(_bar_fill):
		_bar_fill.size = Vector2(0, 6)
		if _bar_tween != null and _bar_tween.is_valid():
			_bar_tween.kill()
		_bar_tween = create_tween()
		_bar_tween.tween_property(_bar_fill, "size:x",
			float(_bar_max_w), FADE_IN_SEC + SWAP_HOLD_SEC) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
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
