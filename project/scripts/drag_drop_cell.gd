class_name DragDropCell
extends Control

# Drag-and-drop wrapper for outpost item cells (inventory + paperdoll
# slots). Lets the player drag an inventory item onto a specific
# equipped slot — or drag between equipped slots — instead of relying
# on auto-routing first-empty logic. Combat pivot 2026-06-04.
#
# Each instance carries:
#   source_kind: "inventory" or "slot"
#   inv_index:   inventory array index when source_kind == "inventory"
#   slot_id:     equipped-dict key when source_kind == "slot"
#                (e.g. "weapon", "ring", "spell1")
#   item_slot:   the items.json slot field (e.g. "weapon", "ring",
#                "spell") — gates drop compatibility (a spell can only
#                drop on a spell* cell, etc.)
#
# Drop signal emits up via callback so outpost can perform the swap.

signal swap_requested(payload: Dictionary)

var source_kind: String = "inventory"
var inv_index: int = -1
var slot_id: String = ""
var item_slot: String = ""
var preview_path: String = ""
# Empty cells (paperdoll slot with nothing equipped) accept drops but
# can't be dragged.
var is_empty: bool = false
# Outpost holds a callback we call when a swap is requested. Easier
# than wiring signals up through every cell; the outpost rebuilds
# them on every render anyway.
var on_swap: Callable = Callable()

func _ready() -> void:
	# Disable focus so click-drag isn't intercepted by Godot's focus
	# transition. Drag-and-drop in Godot 4 needs the control to be
	# mouse-stopping but NOT focus-grabbing — focus changes consume
	# the press event before drag detection kicks in.
	focus_mode = Control.FOCUS_NONE
	mouse_filter = Control.MOUSE_FILTER_STOP

func _get_drag_data(_at_position: Vector2) -> Variant:
	# Empty cells can't initiate drags.
	if is_empty:
		return null
	# Ghost preview that follows the cursor.
	if preview_path != "" and ResourceLoader.exists(preview_path):
		var preview := TextureRect.new()
		preview.texture = load(preview_path)
		preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		preview.size = Vector2(48, 48)
		preview.modulate = Color(1, 1, 1, 0.85)
		set_drag_preview(preview)
	return {
		"source_kind": source_kind,
		"inv_index":   inv_index,
		"slot_id":     slot_id,
		"item_slot":   item_slot,
	}

func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if typeof(data) != TYPE_DICTIONARY:
		return false
	# Only paperdoll slot cells accept drops — inventory cells are pure
	# drag sources (dropping back onto inventory is the auto unequip
	# path we already had via right-click; not strictly needed here).
	if source_kind != "slot":
		return false
	# Item-slot must match cell-slot family. A spell item drops only on
	# a spell* slot; a ring drops on ring*; everything else is 1:1.
	var dragged_item_slot: String = String(data.get("item_slot", ""))
	if dragged_item_slot == "":
		return false
	if dragged_item_slot == "spell" and slot_id.begins_with("spell"):
		return true
	if dragged_item_slot == "ring" and (slot_id == "ring" or slot_id.begins_with("ring")):
		return true
	if dragged_item_slot == slot_id:
		return true
	# 2H↔shield mutual swap is allowed via either weapon or shield slot.
	if (dragged_item_slot == "weapon" and slot_id == "weapon") \
			or (dragged_item_slot == "shield" and slot_id == "shield"):
		return true
	return false

func _drop_data(_at_position: Vector2, data: Variant) -> void:
	if not on_swap.is_valid():
		return
	var payload: Dictionary = {
		"src": data,
		"dst_slot": slot_id,
	}
	on_swap.call(payload)
