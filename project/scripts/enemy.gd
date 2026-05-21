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

# Threat tier 0..3. Set by dungeon.gd::_apply_threat_auras after spawn,
# based on power-vs-bot. Drives the threat_outline.gdshader pulse color.
# 0 = trivial, 1 = even match, 2 = dangerous, 3 = lethal/boss.
var threat_tier: int = 0
const THREAT_OUTLINE_SHADER := preload("res://assets/threat_outline.gdshader")

func combat_label() -> String:
	return enemy_id if enemy_id != "" else "enemy"

func apply_threat_aura(tier: int) -> void:
	# Apply the threat-outline shader as a sprite material. tier=0 is a
	# valid "no outline" state — the shader skips the outline math when
	# tier <= 0 (so we don't pay neighbor-sample cost on weak enemies).
	threat_tier = tier
	if sprite == null:
		return
	if sprite.material == null or not (sprite.material is ShaderMaterial) \
			or (sprite.material as ShaderMaterial).shader != THREAT_OUTLINE_SHADER:
		var mat := ShaderMaterial.new()
		mat.shader = THREAT_OUTLINE_SHADER
		sprite.material = mat
	(sprite.material as ShaderMaterial).set_shader_parameter("tier", tier)
