class_name DebugJump
extends RefCounted

# Static singleton-style globals set by main.gd from user://DEBUG_FLOOR.txt.
# When active, dungeon.gd skips the run_plan and forces a specific biome
# (and optionally a specific vault) on a single floor. Lets Claude validate
# generation/rendering of any biome+vault combination in seconds.

static var active: bool = false
static var biome_id: String = ""
static var vault_name: String = ""
static var floor_num: int = 1
static var screenshot: bool = false
static var screenshot_delay: float = 2.0
