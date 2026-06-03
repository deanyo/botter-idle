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
	"gloves": "gloves/",
	"cloak":  "cloak/",
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
# DCSS hand1/hand2/body/head/boots sprites are pre-aligned to a 32×32
# canvas where the grip/anchor sits at the canvas position the player
# base figure's hand/head/etc occupies. DCSS pack_doll_buf draws each
# part at ofs_x=ofs_y=0 (no per-tile offset). So all our paperdoll
# overlays should also render at (0,0) relative to the rig — they're
# already pre-aligned by the DCSS artists.
const SLOT_OFFSETS := {
	"weapon": Vector2(0, 0),
	"shield": Vector2(0, 0),
	"helm":   Vector2(0, 0),
	"armor":  Vector2(0, 0),
	"boots":  Vector2(0, 0),
	"gloves": Vector2(0, 0),
	"cloak":  Vector2(0, 0),
}
# Z-order within the rig. Cloak goes BENEATH armor (it's the back
# layer), gloves go ABOVE armor (forward of body) but below the
# weapon. Helm above gloves so it tops the figure.
const SLOT_Z := {
	"cloak":  0,
	"boots":  1,
	"armor":  2,
	"gloves": 3,
	"helm":   4,
	"shield": 5,
	"weapon": 6,
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
		# Mirror bot.gd's rarity tint AND glow halo so the inventory/
		# outpost/menu paperdolls match the in-game render — a gold
		# legendary weapon should look gold and pulse everywhere it
		# appears, not just on the live bot.
		_apply_rarity_modulate(sprite, equipped.get(slot_id, null), items_db)
		_apply_rarity_glow(sprite, equipped.get(slot_id, null), items_db, slot_id)
		_apply_hand_enchant(rig, equipped.get(slot_id, null), items_db, slot_id)
	return {"rig": rig, "base": base, "slots": slots}

const _ITEM_GLOW_SHADER := preload("res://assets/item_glow.gdshader")

static func _apply_rarity_modulate(sprite: Sprite2D, inst: Variant, items_db: Dictionary) -> void:
	if inst == null or typeof(inst) != TYPE_DICTIONARY:
		return
	var base_id: String = String(inst.get("base_id", ""))
	if base_id == "" or not items_db.has(base_id):
		return
	var item: Dictionary = items_db[base_id]
	var rarity: String = String(item.get("rarity", "common"))
	var flavor_tags: Array = UITheme.combined_flavor_tags(item, inst)
	var meta: String = String(inst.get("meta_rarity", "")) if typeof(inst) == TYPE_DICTIONARY else ""
	sprite.modulate = UITheme.item_modulate(rarity, flavor_tags, meta)

# Sprite-localised glow on the weapon slot only — mirrors bot.gd. Uses
# the alpha-edge shader so the glow follows the silhouette instead of
# drawing a fat radial blob behind it.
static func _apply_rarity_glow(sprite: Sprite2D, inst: Variant, items_db: Dictionary, slot_id: String) -> void:
	if slot_id != "weapon":
		return
	if inst == null or typeof(inst) != TYPE_DICTIONARY:
		return
	var base_id: String = String(inst.get("base_id", ""))
	if base_id == "" or not items_db.has(base_id):
		return
	var item: Dictionary = items_db[base_id]
	var rarity: String = String(item.get("rarity", "common"))
	var flavor_tags: Array = UITheme.combined_flavor_tags(item, inst)
	var glow_color: Color = UITheme.item_glow_color(rarity, flavor_tags)
	if glow_color.a <= 0.0:
		return
	var mat := ShaderMaterial.new()
	mat.shader = _ITEM_GLOW_SHADER
	mat.set_shader_parameter("glow_color", glow_color)
	var base_strength: float = VideoSettings.tunable("glow_strength", 1.2)
	mat.set_shader_parameter("glow_strength", base_strength)
	var has_flavor: bool = false
	for tag in UITheme.FLAVOR_COLORS.keys():
		if tag in flavor_tags:
			has_flavor = true
			break
	var slider_thickness: float = VideoSettings.tunable("glow_thickness", 0.12)
	var thickness: float = slider_thickness * (1.20 if rarity == "legendary" or has_flavor else 1.0)
	mat.set_shader_parameter("thickness", thickness)
	sprite.material = mat
	var pulse_amt: float = VideoSettings.tunable("glow_pulse_amount", 0.30)
	var pulse := sprite.create_tween().set_loops()
	pulse.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	pulse.tween_method(func(v): mat.set_shader_parameter("glow_strength", v), base_strength - pulse_amt * 0.5, base_strength + pulse_amt * 0.5, 1.4)
	pulse.tween_method(func(v): mat.set_shader_parameter("glow_strength", v), base_strength + pulse_amt * 0.5, base_strength - pulse_amt * 0.5, 1.4)

# Anatomical hand offset on a 32×32 DCSS player sprite. The rig is
# centered at (0,0). DCSS spriggan_female draws the WEAPON hand on
# viewer-left (negative X) in the default _facing_x=1.0 pose; shield
# is on viewer-right. So the enchant offset is -8 to land on the
# weapon hand. When the rig flips (`rig.scale.x = -1` for right-
# facing movement), the negative X auto-flips to +X and the glow
# tracks to the correctly-mirrored weapon hand. Don't bake the flip
# into the glow's own scale — double-flip puts it back on the shield.
const HAND_OFFSET_X := -8.0
const HAND_OFFSET_Y := 1.0

# Hand-side enchant ambience — soft radial glow over the wielding
# hand tinted by flavor color. Parented to the RIG (not the weapon
# sprite) so it doesn't rotate during the swing tween, sits at a
# fixed hand offset, and mirrors automatically when the rig flips
# facing. Mirrors bot.gd::_apply_hand_enchant_ambience so HUD /
# Outpost / FX Tuner paperdolls match the live bot. Weapon slot only.
static func _apply_hand_enchant(rig: Node2D, inst: Variant, items_db: Dictionary, slot_id: String) -> void:
	if slot_id != "weapon":
		return
	if inst == null or typeof(inst) != TYPE_DICTIONARY:
		return
	if rig == null:
		return
	var base_id: String = String(inst.get("base_id", ""))
	if base_id == "" or not items_db.has(base_id):
		return
	var flavor_tags: Array = UITheme.combined_flavor_tags(items_db[base_id], inst)
	var fc: Color = UITheme.flavor_color_for(flavor_tags)
	if fc.a <= 0.0:
		return
	var glow := Sprite2D.new()
	glow.texture = LootDrop._make_glow_texture()
	glow.centered = true
	# Behind the weapon sprite (z_index in renderer SLOT_Z["weapon"]=5),
	# above body/helm so it reads as "weapon hand specifically."
	glow.z_index = 4
	var hand_scale: float = VideoSettings.tunable("hand_enchant_scale", 0.95)
	glow.scale = Vector2(hand_scale, hand_scale)
	glow.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	glow.position = Vector2(HAND_OFFSET_X, HAND_OFFSET_Y)
	var base_alpha: float = VideoSettings.tunable("hand_enchant_alpha", 0.30)
	glow.modulate = Color(fc.r, fc.g, fc.b, base_alpha)
	rig.add_child(glow)
	var dim := Color(fc.r, fc.g, fc.b, base_alpha * 0.45)
	var bright := Color(fc.r, fc.g, fc.b, base_alpha)
	var pulse := glow.create_tween().set_loops()
	pulse.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	pulse.tween_property(glow, "modulate", dim, 1.6)
	pulse.tween_property(glow, "modulate", bright, 1.6)

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
