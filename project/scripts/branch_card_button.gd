class_name BranchCardButton
extends Button

# Item-tooltip-styled deploy card. Holds the structured tooltip data
# computed by Outpost's per-picker cache and instantiates a styled
# BranchTooltip on hover via Godot's _make_custom_tooltip override.
# Falls back to the inherited tooltip_text if data is empty.

var tooltip_data: Dictionary = {}

func _make_custom_tooltip(_for_text: String) -> Object:
	if tooltip_data.is_empty():
		return null
	var tt := BranchTooltip.new()
	tt.render(tooltip_data)
	return tt
