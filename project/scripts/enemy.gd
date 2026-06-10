class_name Enemy
extends Actor

var enemy_id: String = ""
var display_name: String = ""
var xp_reward: int = 0
var is_boss: bool = false
var is_miniboss: bool = false
var aggro_range: int = 8
var repath_timer: float = 0.0
const REPATH_INTERVAL := 0.8

# PoE-style pack tier (normal / magic / rare). Applied at spawn time
# alongside (and ON TOP of) the existing champion roll. Magic gets +20%
# HP / +10% ATK / 1 mod, rare gets +60% HP / +30% ATK / 2 mods. Rare
# also gets a named title (e.g. "Hasted Vicious Goblin"). The visual
# differentiator is set up in apply_pack_visuals().
const PACK_NORMAL := 0
const PACK_MAGIC := 1
const PACK_RARE := 2
var pack_tier: int = PACK_NORMAL
var pack_mods: Array[String] = []
# Defender-side flavor tags coming from pack mods (e.g. ["vampiric"])
# get folded into combat_defense_tags() so existing tag-driven combat
# mechanics work without any per-mod special-case wiring.
var _pack_defense_tags: Array[String] = []

# Per-element resistance dict, populated from enemies.json by
# dungeon.gd::_spawn_specific. Keys are damage_type strings
# ("fire" / "cold" / "lightning" / "holy" / "poison" / "dark" /
# "physical"). Values are signed int percent (+75 = 75% mitigation;
# -40 = 40% amplification — the "vulnerable" lane). actor.gd::
# _apply_typed_damage reads this via `if "resistances" in self`
# and routes the value into the additive +90% mitigation cap.
# Empty dict = no resistances (matches the actor.gd fall-through).
var resistances: Dictionary = {}

# Threat tier 0..3. Set by dungeon.gd::_apply_threat_auras after spawn,
# based on power-vs-bot. Drives the threat_outline.gdshader pulse color.
# 0 = trivial, 1 = even match, 2 = dangerous, 3 = lethal/boss.
var threat_tier: int = 0
const THREAT_OUTLINE_SHADER := preload("res://assets/threat_outline.gdshader")

func combat_label() -> String:
	return enemy_id if enemy_id != "" else "enemy"

# Pack mods that grant defender-worn flavor tags (vampiric pack mod →
# ["vampiric"]) feed back through the same combat pipe Bot uses for
# armor/shield tags, so we get those mechanics for free.
func combat_defense_tags() -> Array:
	return _pack_defense_tags

func apply_threat_aura(tier: int) -> void:
	# Apply the threat-outline shader as a sprite material. tier=0 is a
	# valid "no outline" state — the shader skips the outline math when
	# tier <= 0 (so we don't pay neighbor-sample cost on weak enemies).
	threat_tier = tier
	_ensure_outline_material()
	(sprite.material as ShaderMaterial).set_shader_parameter("tier", tier)

# Pack/boss outline color. Stable per-enemy regardless of bot-relative
# threat — magic/rare/boss/miniboss should *always* outline so the
# player can read the danger at a glance. Threat tier still drives
# pulse intensity / thickness via the shader's tier path.
const _PACK_OUTLINE_COLOR := {
	PACK_MAGIC: Color(0.45, 0.75, 1.00, 0.85),   # cool blue
	PACK_RARE:  Color(1.00, 0.85, 0.30, 0.95),   # gold yellow
}
const _BOSS_OUTLINE_COLOR := Color(1.00, 0.20, 0.20, 0.95)
const _MINIBOSS_OUTLINE_COLOR := Color(1.00, 0.55, 0.20, 0.90)

# Set the persistent outline color based on pack tier + boss flags.
# Picks the strongest signal: boss > miniboss > pack rare > pack magic.
# Called once at spawn after stats and pack tier are known.
func apply_persistent_outline() -> void:
	_ensure_outline_material()
	var col: Color = Color(0, 0, 0, 0)
	if is_boss:
		col = _BOSS_OUTLINE_COLOR
	elif is_miniboss:
		col = _MINIBOSS_OUTLINE_COLOR
	elif pack_tier == PACK_RARE:
		col = _PACK_OUTLINE_COLOR.get(PACK_RARE, col)
	elif pack_tier == PACK_MAGIC:
		col = _PACK_OUTLINE_COLOR.get(PACK_MAGIC, col)
	(sprite.material as ShaderMaterial).set_shader_parameter("pack_color", col)
	# Make the outline a touch thicker for outlined enemies — easier to
	# read at the dungeon zoom level.
	if col.a > 0.0:
		(sprite.material as ShaderMaterial).set_shader_parameter("thickness", 0.09)

func _ensure_outline_material() -> void:
	if sprite == null:
		return
	# Web GL Compatibility compiles/links a fresh shader pipeline per
	# (texture × shader) combination, on the main thread, the first time
	# the pair is drawn. Wave spawns dropping 4 fresh enemy textures all
	# sharing the threat_outline shader was producing 6+ second hangs
	# (logged via PerfMon spike detector 2026-06-08). Skip the outline
	# shader entirely on web — bosses/champions still get a modulate
	# wash from apply_pack_visuals() so they remain readable.
	if OS.has_feature("web"):
		return
	if sprite.material == null or not (sprite.material is ShaderMaterial) \
			or (sprite.material as ShaderMaterial).shader != THREAT_OUTLINE_SHADER:
		var mat := ShaderMaterial.new()
		mat.shader = THREAT_OUTLINE_SHADER
		sprite.material = mat

# Tint colors per pack tier — applied on top of any champion modulate
# already set by dungeon.gd. Picked to read at zoom against typical
# DCSS palette. Magic = blue wash (subtle), rare = saturated yellow.
const _PACK_TINT := {
	PACK_MAGIC: Color(0.75, 0.85, 1.10),   # blue
	PACK_RARE:  Color(1.20, 1.05, 0.55),   # yellow / gold
}
const _PACK_AURA_COLOR := {
	PACK_MAGIC: Color(0.55, 0.75, 1.00, 0.55),
	PACK_RARE:  Color(1.00, 0.90, 0.35, 0.75),
}
const _PACK_AURA_SCALE := {
	PACK_MAGIC: 1.5,
	PACK_RARE:  2.2,
}

# Apply pack tier visuals. Called from dungeon.gd::_spawn_specific
# after the base creature is set up but before threat auras roll. The
# stat boosts associated with the tier are applied separately at the
# spawn site so they compose with floor/branch/champion multipliers.
func apply_pack_visuals() -> void:
	if pack_tier == PACK_NORMAL or rig == null:
		return
	# Multiplicative tint — preserves whatever modulate dungeon.gd
	# already wrote (champion's pinkish wash, miniboss's red).
	var tint: Color = _PACK_TINT.get(pack_tier, Color(1, 1, 1))
	var existing: Color = rig.modulate
	rig.modulate = Color(
		existing.r * tint.r,
		existing.g * tint.g,
		existing.b * tint.b,
		existing.a,
	)
	# Refresh the SpriteFX base modulate so attack_lunge "rests" at the
	# new pack-tinted color rather than snapping back to the original.
	if fx != null:
		fx.base_modulate = rig.modulate
	# Aura behind the rig — same radial glow asset Bot's halo uses.
	# Reused via the LootDrop static factory.
	var glow := Sprite2D.new()
	glow.texture = preload("res://scripts/loot_drop.gd")._make_glow_texture()
	glow.centered = true
	glow.position = Vector2(C.TILE_SIZE * 0.5, C.TILE_SIZE * 0.5) - rig.position
	glow.scale = Vector2.ONE * float(_PACK_AURA_SCALE.get(pack_tier, 1.5))
	glow.z_index = -2
	glow.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var c: Color = _PACK_AURA_COLOR.get(pack_tier, Color(1, 1, 1, 0.5))
	glow.modulate = c
	rig.add_child(glow)
	# Pulse — slower for magic, faster + brighter for rare. Tween owned
	# by glow so it dies cleanly with the enemy.
	var dim := Color(c.r, c.g, c.b, c.a * 0.45)
	var period: float = 1.6 if pack_tier == PACK_MAGIC else 1.0
	var pulse := glow.create_tween().set_loops()
	pulse.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	pulse.tween_property(glow, "modulate", dim, period)
	pulse.tween_property(glow, "modulate", c, period)

# Add a defender-worn flavor tag that combat_defense_tags() will return.
# Used by dungeon.gd to wire vampiric/etc pack mods through the existing
# Bot-side tag combat machinery (no new per-mod hooks needed).
func add_pack_defense_tag(tag: String) -> void:
	if tag == "" or tag in _pack_defense_tags:
		return
	_pack_defense_tags.append(tag)
