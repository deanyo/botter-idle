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
