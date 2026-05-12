extends Control

signal deploy_pressed

const ITEMS_PATH := "res://data/items.json"
const ITEM_TILE_DIR := "res://assets/tiles/items/"

const SLOTS := ["weapon", "armor", "helm", "boots", "shield"]
const RARITY_COLORS := {
	"common": Color(0.85, 0.85, 0.85),
	"uncommon": Color(0.4, 0.7, 1.0),
	"rare": Color(1.0, 0.9, 0.3),
	"epic": Color(1.0, 0.5, 0.2),
	"legendary": Color(1.0, 0.3, 0.3),
}

var items_db: Dictionary = {}
var state: Dictionary = {}

@onready var stats_label: RichTextLabel = $V/Stats
@onready var equipped_grid: GridContainer = $V/Equipped
@onready var inventory_grid: GridContainer = $V/Scroll/Inventory
@onready var deploy_btn: Button = $V/Deploy

func _ready() -> void:
	items_db = _load_items()
	state = SaveState.load_state()
	deploy_btn.pressed.connect(_on_deploy)
	_render()

func _render() -> void:
	_render_stats()
	_render_equipped()
	_render_inventory()

func _render_stats() -> void:
	var max_hp := 50 + (int(state.level) - 1) * 8
	var atk := 5 + (int(state.level) - 1)
	var defense := 1 + int(int(state.level) / 3.0)
	var pct_hp: float = 0.0
	var pct_atk: float = 0.0
	for slot in SLOTS:
		var inst: Variant = state.equipped.get(slot, null)
		if inst == null or typeof(inst) != TYPE_DICTIONARY:
			continue
		var base_id: String = String(inst.get("base_id", ""))
		if not items_db.has(base_id):
			continue
		var item: Dictionary = items_db[base_id]
		max_hp += int(item.get("hp", 0))
		atk += int(item.get("atk", 0))
		defense += int(item.get("def", 0))
		var sums: Dictionary = AffixSystem.sum_affix_stats(inst.get("affixes", []))
		max_hp += int(sums.get("hp", 0))
		atk += int(sums.get("atk", 0))
		defense += int(sums.get("def", 0))
		pct_hp += float(sums.get("hp_pct", 0))
		pct_atk += float(sums.get("atk_pct", 0))
	max_hp = int(round(max_hp * (1.0 + pct_hp / 100.0)))
	atk = int(round(atk * (1.0 + pct_atk / 100.0)))
	stats_label.text = "[b]Lvl %d[/b]  [color=#aaa]xp %d[/color]  [color=#ffd]gold %d[/color]\n[b]HP[/b] %d   [b]ATK[/b] %d   [b]DEF[/b] %d   [color=#888]highest floor: %d[/color]" % [
		state.level, state.xp, state.gold, max_hp, atk, defense, state.highest_floor
	]

func _render_equipped() -> void:
	for c in equipped_grid.get_children():
		c.queue_free()
	for slot in SLOTS:
		var inst: Variant = state.equipped.get(slot, null)
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(96, 110)
		btn.tooltip_text = "Slot: %s" % slot
		if inst == null or typeof(inst) != TYPE_DICTIONARY:
			btn.text = "[%s]\nempty" % slot
		else:
			var base_id: String = String(inst.get("base_id", ""))
			if items_db.has(base_id):
				var item: Dictionary = items_db[base_id]
				var disp_name: String = AffixSystem.format_item_name(String(item.name), inst.get("affixes", []))
				btn.text = "%s\n[%s]\n%s" % [slot, item.rarity, disp_name]
				btn.add_theme_color_override("font_color", RARITY_COLORS.get(item.rarity, Color.WHITE))
		btn.pressed.connect(_unequip.bind(slot))
		equipped_grid.add_child(btn)

func _render_inventory() -> void:
	for c in inventory_grid.get_children():
		c.queue_free()
	var inv: Array = state.inventory
	if inv.is_empty():
		var l := Label.new()
		l.text = "Inventory empty. Run a dungeon to find loot."
		inventory_grid.add_child(l)
		return
	for i in inv.size():
		var inst: Variant = inv[i]
		if typeof(inst) != TYPE_DICTIONARY:
			continue
		var base_id: String = String(inst.get("base_id", ""))
		if not items_db.has(base_id):
			continue
		var item: Dictionary = items_db[base_id]
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(180, 90)
		var disp_name: String = AffixSystem.format_item_name(String(item.name), inst.get("affixes", []))
		var stat_lines: Array = ["+%d ATK  +%d DEF  +%d HP" % [
			int(item.get("atk", 0)), int(item.get("def", 0)), int(item.get("hp", 0))
		]]
		var affix_lines: Array = AffixSystem.format_affix_lines(inst.get("affixes", []))
		stat_lines.append_array(affix_lines)
		btn.text = "[%s] %s\n%s" % [item.rarity, disp_name, "\n".join(stat_lines)]
		btn.add_theme_color_override("font_color", RARITY_COLORS.get(item.rarity, Color.WHITE))
		btn.pressed.connect(_equip.bind(i))
		inventory_grid.add_child(btn)

func _equip(inv_index: int) -> void:
	var inv: Array = state.inventory
	if inv_index < 0 or inv_index >= inv.size():
		return
	var inst: Dictionary = inv[inv_index]
	var base_id: String = String(inst.get("base_id", ""))
	if not items_db.has(base_id):
		return
	var slot: String = String(items_db[base_id].slot)
	var current: Variant = state.equipped.get(slot, null)
	inv.remove_at(inv_index)
	if current != null and typeof(current) == TYPE_DICTIONARY:
		inv.append(current)
	state.equipped[slot] = inst
	SaveState.save_state(state)
	_render()

func _unequip(slot: String) -> void:
	var current: Variant = state.equipped.get(slot, null)
	if current == null or typeof(current) != TYPE_DICTIONARY:
		return
	state.inventory.append(current)
	state.equipped[slot] = null
	SaveState.save_state(state)
	_render()

func _on_deploy() -> void:
	deploy_pressed.emit()

func _load_items() -> Dictionary:
	var f := FileAccess.open(ITEMS_PATH, FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	var by_id: Dictionary = {}
	for it in parsed.get("items", []):
		by_id[it.id] = it
	return by_id
