class_name ItemCell
extends Control

# Shared item cell — used everywhere a single item is rendered as a
# square tile (inventory grid, paperdoll slots, shop stock, sell zone,
# salvage queue, etc). One widget = one rendering path = consistent
# visuals + drag-drop behavior across every UI surface. UI overhaul
# beat 2026-06-04.
#
# State:
#   inst:        Variant (Dictionary or null) — the item instance
#   item:        Dictionary — the items.json def for inst.base_id
#   role:        String — "inventory" | "paperdoll" | "shop" | "sell"
#   slot_id:     String — equipped-dict key for paperdoll cells
#   inv_index:   int — inventory array index for inventory cells
#   shop_index:  int — shop stock index for shop cells
#   accepts_drop: Func returning bool — gate for drop compatibility.
#                 Outpost installs this when wiring the cell.
#   on_left_click, on_right_click, on_drop_received: Callables that
#                 receive the cell as arg (or payload+cell for drop).
#   blocked: bool — species can't wear / can't afford / etc — dims
#                   the sprite + adds a 🚫 glyph.

const INV_CELL_SIZE := 64
const SMALL_CELL_SIZE := 56  # paperdoll uses smaller cells

var inst: Variant = null
var item: Dictionary = {}
var role: String = "inventory"
var slot_id: String = ""
var inv_index: int = -1
var shop_index: int = -1
var accepts_drop: Callable = Callable()
var on_left_click: Callable = Callable()
var on_right_click: Callable = Callable()
var on_drop_received: Callable = Callable()
# Tooltip owner — called as (cell: ItemCell, show: bool). HudChrome /
# Outpost set this to their tooltip manager. WoW-style tooltip,
# item-overhaul v2.
var tooltip_owner: Callable = Callable()
var blocked: bool = false

# Internal child references — built in _ready, refreshed by render().
var _bg: ColorRect = null
var _border: ReferenceRect = null
var _sprite: TextureRect = null
var _star: Label = null
var _block_label: Label = null
var _hover_glow: ColorRect = null  # appears when a compatible drag hovers

# Visual sizing — caller sets `cell.cell_size` before adding to scene.
var cell_size: int = INV_CELL_SIZE

func _ready() -> void:
	custom_minimum_size = Vector2(cell_size, cell_size)
	size = Vector2(cell_size, cell_size)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE
	_bg = ColorRect.new()
	_bg.size = Vector2(cell_size, cell_size)
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg.color = Color(0, 0, 0, 0.5)
	add_child(_bg)
	_sprite = TextureRect.new()
	_sprite.size = Vector2(cell_size - 6, cell_size - 6)
	_sprite.position = Vector2(3, 3)
	_sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_sprite)
	_border = ReferenceRect.new()
	_border.size = Vector2(cell_size, cell_size)
	_border.border_color = Color(0.4, 0.35, 0.2, 0.8)
	_border.border_width = 1.0
	_border.editor_only = false
	_border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_border)
	_hover_glow = ColorRect.new()
	_hover_glow.size = Vector2(cell_size, cell_size)
	_hover_glow.color = Color(0.4, 0.95, 0.4, 0.0)
	_hover_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hover_glow)
	_star = Label.new()
	_star.text = "★"
	_star.add_theme_font_size_override("font_size", 14)
	_star.add_theme_color_override("font_color", Color(1.0, 0.85, 0.30, 1.0))
	_star.position = Vector2(cell_size - 18, -4)
	_star.size = Vector2(18, 18)
	_star.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_star.modulate = Color(1, 1, 1, 0)
	add_child(_star)
	# Block (🚫) overlay for species-blocked / can't-afford cells.
	_block_label = Label.new()
	_block_label.text = "🚫"
	_block_label.position = Vector2.ZERO
	_block_label.size = Vector2(cell_size, cell_size)
	_block_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_block_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_block_label.add_theme_font_size_override("font_size", 22)
	_block_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4, 0.9))
	_block_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_block_label.modulate = Color(1, 1, 1, 0)
	add_child(_block_label)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)

# Refresh visuals from current `inst`/`item`/`blocked`/`slot_id` state.
# Caller mutates fields then calls render() — keeps the cell stateful
# without forcing a full rebuild on every frame.
func render() -> void:
	if not is_inside_tree():
		return
	var rarity: String = String(item.get("rarity", "common")) if not item.is_empty() else ""
	var has_item: bool = (inst != null and typeof(inst) == TYPE_DICTIONARY and not item.is_empty())
	# Sprite texture.
	if has_item:
		var tile_path: String = "res://assets/tiles/items/" + String(item.get("tile", ""))
		if ResourceLoader.exists(tile_path):
			_sprite.texture = load(tile_path)
		else:
			_sprite.texture = null
	else:
		# Empty paperdoll cell: show greyscale slot icon.
		var icon: String = UITheme.empty_slot_icon_path(slot_id) if role == "paperdoll" else ""
		if icon != "":
			_sprite.texture = load(icon)
		else:
			_sprite.texture = null
	# Modulate (rarity + flavor + meta tints).
	if has_item:
		var tags: Array = UITheme.combined_flavor_tags(item, inst)
		var meta: String = String(inst.get("meta_rarity", ""))
		_sprite.modulate = UITheme.item_modulate(rarity, tags, meta)
		var recolor: ShaderMaterial = UITheme.recolor_material_for(inst)
		_sprite.material = recolor
	else:
		_sprite.modulate = Color(1, 1, 1, 1)
		_sprite.material = null
	# Border color: rarity if equipped, spell-class color for spell
	# cells with content, otherwise neutral.
	if has_item and rarity != "":
		_border.border_color = UITheme.rarity_color(rarity)
	else:
		_border.border_color = Color(0.4, 0.35, 0.2, 0.8)
	if role == "paperdoll" and slot_id.begins_with("spell") and has_item:
		var pstat: String = UITheme.spell_primary_stat(item)
		_border.border_color = UITheme.spell_class_color(pstat)
	# Favorite star.
	var fav: bool = false
	if has_item:
		fav = bool(inst.get("favorite", false))
	_star.modulate = Color(1, 1, 1, 1.0 if fav else 0.0)
	# Blocked overlay.
	_block_label.modulate = Color(1, 1, 1, 0.95 if blocked else 0.0)
	if blocked:
		_sprite.modulate.a = 0.45
	# Tooltip.
	# Item-overhaul v2: native tooltip_text replaced by the custom
	# ItemTooltip widget — managed by HudChrome / Outpost. Empty
	# tooltip_text suppresses the engine's default popup so we don't
	# get two tooltips at once.
	tooltip_text = ""

func _slot_label(sid: String) -> String:
	if sid.begins_with("ring") and sid.length() > 4:
		return "Ring %s" % sid.substr(4).to_upper()
	if sid.begins_with("spell") and sid.length() > 5:
		var roman := ["", "I", "II", "III", "IV", "V"]
		var n: int = int(sid.substr(5))
		return "Spell %s" % (roman[n] if n < roman.size() else str(n))
	return sid.capitalize()

# Build the payload describing what's being dragged from this cell.
# DragManager.begin_drag eats this verbatim; outpost reads it on drop.
func _drag_payload() -> Dictionary:
	# instance_id is the stable identity — handlers resolve live array
	# positions from this rather than trusting cell-built indices that
	# may have drifted across mutations.
	return {
		"role": role,
		"slot_id": slot_id,
		"inv_index": inv_index,
		"shop_index": shop_index,
		"instance_id": String(inst.get("instance_id", "")) if (inst != null and typeof(inst) == TYPE_DICTIONARY) else "",
		"item_slot": String(item.get("slot", "")) if not item.is_empty() else "",
	}

func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb: InputEventMouseButton = event
	# On press, stage a drag (DragManager promotes it after threshold).
	# On release with no drag promotion, treat as click.
	var has_item: bool = (inst != null and typeof(inst) == TYPE_DICTIONARY)
	if mb.button_index == MOUSE_BUTTON_LEFT:
		if mb.pressed:
			# Pre-drag hook — let owners (e.g. HUD) resolve a stale
			# flat inv_index right before the drag stages. Avoids
			# storing indices that drift across inventory rebuilds.
			var resolver: Variant = get_meta("flat_index_resolver", null)
			if resolver != null and (resolver as Callable).is_valid():
				(resolver as Callable).call()
			if has_item and not blocked and DragManager:
				var preview_tex: Texture2D = _sprite.texture
				DragManager.begin_drag(_drag_payload(), preview_tex, _sprite.modulate)
		else:
			# Release. If DragManager activated a drag, this fires the
			# drop handler via DragManager's drag_ended signal — DON'T
			# treat as click. If it stayed pending (no motion), the
			# drag system cancelled it; treat as click.
			if DragManager and not DragManager.is_dragging():
				if on_left_click.is_valid():
					on_left_click.call(self)
	elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
		if on_right_click.is_valid():
			on_right_click.call(self)

func _on_mouse_entered() -> void:
	if DragManager and DragManager.is_dragging():
		var payload: Dictionary = DragManager.get_payload()
		var ok: bool = false
		if accepts_drop.is_valid():
			ok = bool(accepts_drop.call(payload))
		DragManager.set_hover_target(self, ok)
		# Highlight: green if compatible, red if not.
		_hover_glow.color = Color(0.4, 0.95, 0.4, 0.25) if ok else Color(0.95, 0.3, 0.3, 0.25)
	else:
		_hover_glow.color = Color(0.85, 0.85, 0.85, 0.10)
	# WoW-style tooltip — owner spawns it. Skip while dragging (the
	# preview is already cursor-following; a tooltip on top would clutter).
	var has_item: bool = (inst != null and typeof(inst) == TYPE_DICTIONARY and not item.is_empty())
	if has_item and tooltip_owner.is_valid() and not (DragManager and DragManager.is_dragging()):
		tooltip_owner.call(self, true)

func _on_mouse_exited() -> void:
	if DragManager:
		DragManager.clear_hover_target(self)
	_hover_glow.color = Color(0, 0, 0, 0)
	if tooltip_owner.is_valid():
		tooltip_owner.call(self, false)
