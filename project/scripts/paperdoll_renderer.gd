class_name PaperdollRenderer
extends RefCounted

# Builds a layered Sprite2D rig of the bot wearing equipped gear. One
# implementation drives the in-game bot AND every UI paperdoll, so what you
# see in inventory matches what fights in the dungeon.
#
# Layer order (bottom → top): bot base → boots → body armor → cloak → helm →
# shield (left hand) → weapon (right hand). Each overlay sits at (0,0) of the
# parent and is centered to align with the 32×32 player base art.

const BASE_TEX_PATH := "res://assets/tiles/player/spriggan_female.png"
const FALLBACK_TEX_PATH := "res://assets/tiles/player/bot.png"

const PLAYER_DIR := "res://assets/tiles/player/"
const SLOT_DIRS := {
	"weapon": "weapons/",
	"armor":  "body/",
	"helm":   "helm/",
	"shield": "shield/",
	"boots":  "boots/",
}
# Anatomical offsets from rig origin. The weapon sits in the right
# hand, shield in the left. Other slots align to base center.
#
# 2026-06-02 paperdoll fix: DCSS source confirms paperdoll renders with
# zero per-item offset (tiledoll.cc::pack_doll_buf line 991: ofs_x = 0,
# ofs_y = 0). DCSS solves the "different sword sizes look right" problem
# by maintaining a SEPARATE pre-aligned sprite tree: dcss-source/.../
# rltiles/player/{hand1, hand2, body, head, boots} — each has the gear
# drawn with the grip/anchor at the canvas position the player figure's
# hand/head/etc will be. The inventory sprites (item/weapon/, etc) are
# DIFFERENT files, drawn standalone for the loot drop / inventory icon.
#
# Our prior bug: sync_items.py was copying the inventory-tree sprites
# into BOTH project/assets/tiles/items/ AND project/assets/tiles/player/
# weapons/. Those are the standalone art, not the hand-aligned art —
# hence the misplaced/silly look. Fix: sync_items.py now pulls
# paperdoll overlays from the player/hand1/ tree where available, and
# falls back to the inventory tile only for missing entries.
const SLOT_OFFSETS := {
	"weapon": Vector2(4, 2),
	"shield": Vector2(-5, 2),
	"helm":   Vector2(0, 0),
	"armor":  Vector2(0, 0),
	"boots":  Vector2(0, 0),
}
# Z-order within the rig.
const SLOT_Z := {
	"boots":  1,
	"armor":  2,
	"helm":   3,
	"shield": 4,
	"weapon": 5,
}

# Returns: { rig: Node2D, base_sprite: Sprite2D, slots: { slot_id: Sprite2D } }
# Caller adds `rig` as a child wherever they want the bot to render. `slots`
# lets the bot swing the weapon Sprite2D, etc.
static func build_rig(items_db: Dictionary, equipped: Dictionary) -> Dictionary:
	var rig := Node2D.new()
	var base := Sprite2D.new()
	base.centered = true
	base.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var base_path := BASE_TEX_PATH
	if not ResourceLoader.exists(base_path):
		base_path = FALLBACK_TEX_PATH
	if ResourceLoader.exists(base_path):
		base.texture = load(base_path)
	rig.add_child(base)
	var slots: Dictionary = {}
	# Build overlays in z-order. Empty slots are skipped — no transparent
	# placeholder draws on the bot.
	var ordered_slots: Array = SLOT_Z.keys()
	ordered_slots.sort_custom(func(a, b): return int(SLOT_Z[a]) < int(SLOT_Z[b]))
	for slot_id in ordered_slots:
		var path: String = _resolve_overlay(slot_id, equipped, items_db)
		if path == "":
			continue
		var sprite := Sprite2D.new()
		sprite.texture = load(path)
		sprite.centered = true
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		sprite.position = SLOT_OFFSETS.get(slot_id, Vector2.ZERO)
		sprite.z_index = int(SLOT_Z[slot_id])
		rig.add_child(sprite)
		slots[slot_id] = sprite
	return {"rig": rig, "base": base, "slots": slots}

# Resolve `slot_id` → overlay sprite path, or "" if no equipped item.
static func _resolve_overlay(slot_id: String, equipped: Dictionary, items_db: Dictionary) -> String:
	var inst: Variant = equipped.get(slot_id, null)
	if inst == null or typeof(inst) != TYPE_DICTIONARY:
		return ""
	var base_id: String = String(inst.get("base_id", ""))
	if base_id == "" or not items_db.has(base_id):
		return ""
	var item: Dictionary = items_db[base_id]
	# `tile` is the inventory-card icon. The overlay sprite stem matches the
	# tile stem (e.g. armor_chain.png inventory card ↔ body/armor_chain.png
	# overlay) — items that share an item-tile family also share an overlay.
	# Items can override with an explicit `overlay` field if needed later.
	var stem: String = String(item.get("overlay", ""))
	if stem == "":
		stem = String(item.get("tile", ""))
		if stem.ends_with(".png"):
			stem = stem.substr(0, stem.length() - 4)
	if stem == "":
		return ""
	var dir: String = String(SLOT_DIRS.get(slot_id, ""))
	if dir == "":
		return ""
	var path: String = PLAYER_DIR + dir + stem + ".png"
	if not ResourceLoader.exists(path):
		return ""
	return path
