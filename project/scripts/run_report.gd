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

func _ready() -> void:
	deploy_btn.pressed.connect(func(): deploy_again.emit())
	garage_btn.pressed.connect(func(): back_to_garage.emit())

func show_report(victory: bool, report: Dictionary) -> void:
	title.text = "VICTORY" if victory else "YOU DIED"
	title.add_theme_color_override("font_color", Color(0.4, 0.95, 0.4) if victory else Color(0.95, 0.3, 0.3))

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

func _format_instance(inst: Dictionary, items_db: Dictionary, dimmed: bool) -> String:
	var base_id: String = String(inst.get("base_id", ""))
	if not items_db.has(base_id):
		return "(unknown)"
	var item: Dictionary = items_db[base_id]
	var disp: String = AffixSystem.format_item_name(String(item.name), inst.get("affixes", []), inst)
	var color: String = "666" if dimmed else RARITY_COLORS.get(str(item.rarity), "cccccc")
	return "[color=#%s]%s[/color]" % [color, disp]
