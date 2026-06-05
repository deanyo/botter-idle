extends Control

signal deploy_again
signal back_to_garage

const RARITY_COLORS := {
	"common": "cccccc",
	"uncommon": "66b3ff",
	"rare": "ffe066",
	"epic": "ff8033",
	"legendary": "ff4d4d",
}

@onready var title: Label = $V/Title
@onready var summary: RichTextLabel = $V/Summary
@onready var journal_box: RichTextLabel = $V/Scroll/Journal
@onready var loot_box: RichTextLabel = $V/LootScroll/LootList
@onready var deploy_btn: Button = $V/Buttons/DeployBtn
@onready var garage_btn: Button = $V/Buttons/GarageBtn

# Inserted dynamically when the run unlocks new branches. Lives just
# under the title and reads "TIER N CLEARED — Branches unlocked: X, Y."
# Beat 10 — 2026-06-04.
var _unlock_banner: Label = null
# Inserted dynamically as a thin horizontal underline below the title
# in a victory/defeat color. UI polish 2026-06-04.
var _title_underline: ColorRect = null

func _ready() -> void:
	deploy_btn.pressed.connect(func(): deploy_again.emit())
	garage_btn.pressed.connect(func(): back_to_garage.emit())
	UITheme.style_button(deploy_btn)
	UITheme.style_button(garage_btn)

func show_report(victory: bool, report: Dictionary) -> void:
	# Death is no longer permadeath — the run-active flag survives, gear/
	# xp/gold are kept, and the player redeploys with a re-thought
	# loadout. Phrase the title accordingly so the player understands
	# "this is a tactical setback, not a wipe."
	title.text = "VICTORY" if victory else "DEFEAT"
	# Title polish 2026-06-04 — bigger, centered, with a colored underline
	# strip below so the win/loss state reads from across the room.
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 56)
	var title_color: Color = Color(0.4, 0.95, 0.4) if victory else Color(0.95, 0.3, 0.3)
	title.add_theme_color_override("font_color", title_color)
	# Drop the underline + unlock banner just under the title node. The
	# title's parent (V VBoxContainer) controls the visual stack so we
	# insert the new nodes at index title.get_index()+1.
	_install_title_chrome(title_color)
	_install_unlock_banner(report.get("newly_unlocked", []))
	# Mirror the framing on the action buttons. Victory → fresh run.
	# Defeat → redeploy (same character, same gear, same gold).
	if deploy_btn != null:
		deploy_btn.text = "Deploy" if victory else "Redeploy"
	if garage_btn != null:
		garage_btn.text = "Outpost"

	var retreats: int = int(report.get("retreats", 0))
	var retreat_line: String = ""
	if retreats > 0:
		retreat_line = "   [color=#cc6666][b]Retreats:[/b] %d[/color]" % retreats
	var salvaged: int = int(report.get("salvaged_count", 0))
	var salvage_line: String = ""
	if salvaged > 0:
		salvage_line = "\n[color=#aaa]Auto-salvaged %d items (+%d gold)[/color]" % [
			salvaged, int(report.get("salvaged_gold", 0)),
		]
	summary.text = "[b]Floor:[/b] %d   [b]Level:[/b] %d   [b]Gold:[/b] %d%s\n[b]HP:[/b] %d / %d   [b]XP:[/b] %d%s" % [
		report.floor, report.level, report.gold, retreat_line, report.hp, report.max_hp, report.xp, salvage_line,
	]

	journal_box.text = _render_journal(report.get("journal", []))
	loot_box.text = _render_loot(report.get("kept", []), report.get("dropped", []), report.get("items_db", {}), victory)

func _render_journal(journal: Array) -> String:
	if journal.is_empty():
		return "[i]No journal entries.[/i]"
	var lines: Array[String] = []
	for entry in journal:
		var floor_num: int = int(entry.floor)
		var biome: String = String(entry.biome)
		lines.append("[b][color=#ffd479]Floor %d — %s[/color][/b]" % [floor_num, biome])
		var events: Array = entry.events
		if events.is_empty():
			lines.append("  [color=#888]· nothing of note ·[/color]")
		else:
			for ev in events:
				lines.append("  • %s" % str(ev))
		lines.append("")
	return "\n".join(lines)

func _render_loot(kept: Array, _dropped: Array, items_db: Dictionary, _victory: bool) -> String:
	# Loot is loot — banked regardless of victory/death since the death-loss
	# tax was removed (idle-game friendly). dropped == kept in the new flow.
	if kept.is_empty():
		return "[i]No loot found.[/i]"
	var lines: Array[String] = []
	lines.append("[b]Loot Recovered[/b]")
	for inst in kept:
		lines.append("  • " + _format_instance(inst, items_db, false))
	return "\n".join(lines)

func _install_title_chrome(title_color: Color) -> void:
	# Insert a thin colored underline strip below the title, centered to
	# the title's width. Idempotent — re-show_report just updates color.
	if _title_underline != null and is_instance_valid(_title_underline):
		_title_underline.color = Color(title_color.r, title_color.g, title_color.b, 0.85)
		return
	_title_underline = ColorRect.new()
	_title_underline.color = Color(title_color.r, title_color.g, title_color.b, 0.85)
	_title_underline.custom_minimum_size = Vector2(220, 3)
	_title_underline.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var parent: Node = title.get_parent()
	if parent != null:
		parent.add_child(_title_underline)
		parent.move_child(_title_underline, title.get_index() + 1)

func _install_unlock_banner(newly_unlocked: Array) -> void:
	# Show / hide / update the "branches unlocked" banner based on what
	# this run accomplished. Created lazily, reused on subsequent calls.
	if newly_unlocked == null or newly_unlocked.is_empty():
		if _unlock_banner != null and is_instance_valid(_unlock_banner):
			_unlock_banner.visible = false
		return
	# Pretty-print: capitalize each id, comma-separate.
	var pretty: Array[String] = []
	for b in newly_unlocked:
		pretty.append(String(b).capitalize())
	var line: String = "BRANCHES UNLOCKED: " + ", ".join(pretty)
	if _unlock_banner == null or not is_instance_valid(_unlock_banner):
		_unlock_banner = Label.new()
		_unlock_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_unlock_banner.add_theme_font_size_override("font_size", 18)
		_unlock_banner.add_theme_color_override("font_color", Color(1.0, 0.85, 0.30))
		_unlock_banner.add_theme_color_override("font_outline_color", Color(0, 0, 0))
		_unlock_banner.add_theme_constant_override("outline_size", 3)
		var parent: Node = title.get_parent()
		if parent != null:
			parent.add_child(_unlock_banner)
			# Place after the underline strip if we have one, else right
			# under the title.
			var idx: int = title.get_index() + 1
			if _title_underline != null and is_instance_valid(_title_underline):
				idx = _title_underline.get_index() + 1
			parent.move_child(_unlock_banner, idx)
	_unlock_banner.text = line
	_unlock_banner.visible = true
	# Subtle slow pulse so the eye lands on it.
	var t := _unlock_banner.create_tween().set_loops()
	t.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.tween_property(_unlock_banner, "modulate:a", 0.55, 1.4)
	t.tween_property(_unlock_banner, "modulate:a", 1.0, 1.4)

func _format_instance(inst: Dictionary, items_db: Dictionary, dimmed: bool) -> String:
	var base_id: String = String(inst.get("base_id", ""))
	if not items_db.has(base_id):
		return "(unknown)"
	var item: Dictionary = items_db[base_id]
	var disp: String = AffixSystem.format_item_name(String(item.name), inst.get("affixes", []), inst)
	var color: String = "666" if dimmed else RARITY_COLORS.get(str(item.rarity), "cccccc")
	return "[color=#%s]%s[/color]" % [color, disp]
