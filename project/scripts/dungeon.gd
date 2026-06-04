extends Node2D

const C := preload("res://scripts/constants.gd")
const DungeonGen := preload("res://scripts/dungeon_generator.gd")
const Path := preload("res://scripts/pathfinding.gd")

signal floor_started(floor_num: int)
signal floor_cleared(floor_num: int)
signal run_ended(victory: bool, report: Dictionary)
# Emitted when the branch's boss dies. main.gd listens and unlocks the
# next-tier branches in the save state.
signal boss_killed(branch_id: String)

const ENEMIES_PATH := "res://data/enemies.json"
const ITEMS_PATH := "res://data/items.json"
const MONSTER_MODS_PATH := "res://data/monster_mods.json"
const ENEMY_TILE_DIR := "res://assets/tiles/enemies/"

var enemy_data: Dictionary = {}
var items_db: Dictionary = {}
# Pack-tier modifiers (PoE-style). Loaded once at run start; rolled
# per-spawn for non-boss/non-miniboss/non-champion enemies.
var monster_mods: Array = []
var pathing: Path
var grid: Array
var rooms: Array
var bot: Bot
var enemies: Array[Enemy] = []
var current_floor: int = 1
var rng := RandomNumberGenerator.new()
var loot_log: Array[String] = []
var kills: Dictionary = {}
var dropped_items: Array = []
var visited_rooms: Array[bool] = []
var stairs_cell: Vector2i = Vector2i.ZERO
var journal: Array = []
var loot_drops: Array[LootDrop] = []
var interactables: Array[Interactable] = []
var bot_interacting: bool = false
var interact_target: Interactable = null
var interact_timer: float = 0.0
var vault_spawn_overrides: Dictionary = {}
var vault_decor_sprites: Array[Node2D] = []
var run_plan: Array = []
# Branch the player picked in the Outpost. Empty = legacy random-roll.
# Set by main.gd before the dungeon is added to the tree.
var branch_id: String = ""
var current_biome: Dictionary = {}
var ambient_modulate: CanvasModulate = null
var color_grade: ColorGrade = null
var fog: FogSystem = null
var current_renderer: MapRenderer = null
var bot_light: PointLight2D = null
var world_env: WorldEnvironment = null
var fog_overlay: FogOverlay = null
var ambient_decor_nodes: Array = []
var portal_active: bool = false
var portal_kind: String = ""
var portal_biome_override: Dictionary = {}
var portal_loot_bias: int = 0
var bot_target_cell: Vector2i = Vector2i(-1, -1)
var bot_target_kind: String = ""
var dist_to_stairs: Array = []
var ticks_without_move: int = 0
# Per-floor accumulating counters, reset on _build_floor, emitted on floor_cleared.
var floor_start_tick: int = 0
var floor_kills: int = 0
var floor_loot_picked: int = 0
var floor_chests_opened: int = 0
var floor_altars_used: int = 0
var floor_fountains_used: int = 0
var floor_portals_entered: int = 0
var floor_stalls: int = 0
var floor_hard_recoveries: int = 0
var floor_starting_hp: int = 0
var floor_placed_vaults: Array = []
var _last_fog_cell: Vector2i = Vector2i(-99, -99)
var _fog_dirty: bool = true
var _cached_world_lights: Array = []
var _cached_world_lights_valid: bool = false
# Set to false while _build_floor is running across frames; gates _process
# so the bot doesn't try to tick on a half-built floor.
var _floor_ready: bool = false
# Generation counter — each call to _build_floor bumps it. Async phases
# bail if their captured generation no longer matches, so a new build
# (or scene teardown) can preempt a half-finished one.
var _build_generation: int = 0
# Run-wide counters for run-end summary.
var run_kills: int = 0
var run_loot_picked: int = 0
var run_portals_entered: int = 0
var run_stalls: int = 0
var run_vaults_stamped: Array = []
var run_biomes_visited: Array = []
# IDs of `unique: true` items already dropped this run. Each unique drops
# at most once per run; subsequent rolls excluding it. Reset on run start.
var run_dropped_uniques: Array[String] = []
# Death retreat: revives_remaining starts at save.max_revives at run start
# and decrements on each retreat. When it hits zero, the next death is a
# real run-end. Scales later via bot upgrades / gear affixes.
var revives_remaining: int = 0
var retreats_this_run: int = 0
# Active run modifiers (Crowded, Endless, etc). Set at run start from
# save.branch_modifiers[branch_id]; cached here so spawn-time code paths
# don't reload the save. Effects fold into enemy count, floor count,
# rarity, gold, and chest counts.
var active_modifiers: Array = []
# Per-run resolved floor counts. Default to constants but Endless extends
# them. _boss_floor always equals _floors_per_run (boss is final floor).
var _floors_per_run: int = 6
var _boss_floor: int = 6
# Inventory cap drives auto-salvage when the bag fills up. Run-cached so
# the per-pickup check doesn't re-read disk. _run_salvaged_* track the
# stats reported in the run summary.
var _inventory_cap: int = 50
var _run_salvaged_count: int = 0
var _run_salvaged_gold: int = 0
# Auto-salvage runs deferred (floor end + run end) so each individual
# pickup never pays for the segment-shrink HUD rebuild. The previous
# inline call ran on every pickup once cap was hit, which was the
# loot-pickup stutter the user reported.
var _pending_salvage_check: bool = false
const MAX_TICKS_WITHOUT_MOVE := 30
var chrome: HudChrome = null
var run_turn: int = 0

@onready var map_layer: Node2D = $MapLayer
@onready var actor_layer: Node2D = $ActorLayer
@onready var camera: Camera2D = $Camera

func _ready() -> void:
	# BOTTER_SEED=<int> seeds the world-rng stream (vault picks, loot rolls,
	# affix rolls, generator). Same seed = same floor sequence + same loot.
	# Combat rng (per-attack crit on Actor.attack) is the global stream
	# (randf/randi without an rng), seeded separately so it stays its own
	# axis of variance — duels can converge or diverge on combat skill.
	var seed_env: String = OS.get_environment("BOTTER_SEED")
	if seed_env != "" and seed_env.is_valid_int():
		var s: int = int(seed_env)
		rng.seed = s
		# Also seed the global rng for the few class-level callers
		# (altar.gd / portal.gd setup-time picks, dcss_layouts.gd carve
		# step direction). These are "world" decisions, not combat.
		seed(s)
		print("[seed] world_rng=%d" % s)
	else:
		rng.randomize()
	enemy_data = _load_json(ENEMIES_PATH)
	items_db = _load_items(ITEMS_PATH)
	monster_mods = _load_monster_mods()
	# Layer ordering: floor base + wall/edge overlays draw at z=0/1 inside
	# MapLayer. Pin ActorLayer to z=10 so every actor + interactable +
	# ambient decor sits above ALL map tiles. Without this, the
	# overlay_layer (z=1) renders ON TOP of stairs/altars/chests/enemies
	# in dense biomes like hive — user-reported bug 2026-06-03.
	# Enemies + interactables don't need per-instance z_index after this;
	# the layer's z_index sets the floor for all of them.
	if actor_layer != null:
		actor_layer.z_index = 10
	# FlickerDriver animates every PointLight2D with a "flicker" meta dict.
	# Single shared driver keeps cost predictable.
	add_child(FlickerDriver.new())
	_start_run()

func _start_run() -> void:
	current_floor = 1
	loot_log.clear()
	kills.clear()
	journal.clear()
	# Resolve modifiers up front so floor count + plan size reflect Endless
	# and any future floor-shaping mods.
	_resolve_active_modifiers()
	run_plan = BiomeData.roll_run_plan(rng, branch_id, _floors_per_run)
	if ambient_modulate == null:
		ambient_modulate = CanvasModulate.new()
		add_child(ambient_modulate)
	# Per-biome color grade (post-process). Toggleable from video options
	# (gfx.color_grade); env override BOTTER_NO_COLOR_GRADE / BOTTER_NO_GRADE.
	if color_grade == null and VideoSettings.is_effect_enabled("color_grade") \
			and not OS.has_environment("BOTTER_NO_GRADE"):
		color_grade = ColorGrade.new()
		add_child(color_grade)
	if world_env == null:
		world_env = WorldEnvironment.new()
		var env := Environment.new()
		env.background_mode = Environment.BG_CANVAS
		# BOTTER_NO_GLOW=1 disables bloom for perf A/B testing.
		var glow_on: bool = not OS.has_environment("BOTTER_NO_GLOW")
		env.glow_enabled = glow_on
		env.glow_intensity = 0.9
		env.glow_strength = 1.2
		env.glow_bloom = 0.2
		env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
		env.glow_hdr_threshold = 1.0
		world_env.environment = env
		add_child(world_env)
	# BOTTER_NO_FOG=1 skips creating the fog overlay (full-screen shader,
	# 24-light loop per pixel). Visibility raycast still runs — sprites use
	# their own modulate fade. For perf A/B testing.
	if fog_overlay == null and camera != null and not OS.has_environment("BOTTER_NO_FOG"):
		fog_overlay = FogOverlay.new()
		add_child(fog_overlay)
		var view_size: Vector2 = get_viewport().get_visible_rect().size
		fog_overlay.setup(camera, view_size)
	var save: Dictionary = SaveState.load_state()
	bot = Bot.new()
	actor_layer.add_child(bot)
	bot.level = int(save.get("level", 1))
	bot.xp = int(save.get("xp", 0))
	bot.gold = int(save.get("gold", 0))
	bot.clear_blessings()
	bot.apply_gear(items_db, save.get("equipped", {}), save)
	# Spell autocast bookkeeping — fresh per run.
	SpellSystem.init_run(bot, items_db)
	# Reset run-wide counters at run start
	run_kills = 0
	run_loot_picked = 0
	run_portals_entered = 0
	run_stalls = 0
	run_vaults_stamped = []
	run_biomes_visited = []
	run_dropped_uniques.clear()
	revives_remaining = int(save.get("max_revives", 3))
	retreats_this_run = 0
	# Cache loot filter rank for the run — LootDrop.should_skip reads it
	# in the AI hot path so we don't want a disk hit there.
	LootDrop.loot_filter_min_rank = LootDrop.RARITY_RANK.get(String(save.get("loot_filter", "common")), 0)
	_inventory_cap = int(save.get("inventory_cap", 50)) + int(BotUpgrades.total_for_stat(save, "inventory_cap"))
	_run_salvaged_count = 0
	_run_salvaged_gold = 0
	# Seed the live inventory with the player's stash. The HUD renders this
	# as a "Base" section; loot picked up this run appends as Floor-N
	# sections below it.
	_loot_segments.clear()
	_loot_segments.append({"header": "Base", "items": save.get("inventory", []).duplicate(true)})
	_current_floor_segment_index = -1
	_slot_cooldowns.clear()
	_hud_inventory_seeded = false
	_rebuild_inv_cache()
	# Push once so the HUD shows the base inventory before any loot drops.
	# (chrome may not exist yet on the first frame; the HUD's _ensure path
	# will pick this up on its next update_biome_hud tick.)
	if chrome != null:
		_push_inventory_to_hud()
	GrindLog.log_line("[run] start hp=%d/%d level=%d gold=%d seed=%d" % [bot.hp, bot.max_hp, bot.level, bot.gold, rng.seed])
	_build_floor()

func _build_floor() -> void:
	# Async wrapper — splits the build across multiple frames so the
	# 70-600ms generate+render+decor work doesn't manifest as a single-
	# frame stutter on stairs descent. Each phase yields one frame so
	# Godot can process the rendering for the previous phase. Sync
	# call sites just don't await the result.
	_async_build_floor()

func _async_build_floor() -> void:
	_floor_ready = false
	_build_generation += 1
	var my_gen: int = _build_generation
	var t_total: int = Time.get_ticks_usec()
	for e in enemies:
		if is_instance_valid(e):
			e.queue_free()
	enemies.clear()
	for d in loot_drops:
		if is_instance_valid(d):
			d.queue_free()
	loot_drops.clear()
	for inter in interactables:
		if is_instance_valid(inter):
			inter.queue_free()
	interactables.clear()
	for s in vault_decor_sprites:
		if is_instance_valid(s):
			s.queue_free()
	vault_decor_sprites.clear()
	for n in ambient_decor_nodes:
		if is_instance_valid(n):
			n.queue_free()
	ambient_decor_nodes.clear()
	bot_target_cell = Vector2i(-1, -1)
	bot_target_kind = ""
	_stall_snapshot_taken = false
	_reset_stuck_timer()
	_last_bot_cell = Vector2i(-99, -99)
	vault_spawn_overrides.clear()
	bot_interacting = false
	interact_target = null
	interact_timer = 0.0
	floor_start_tick = Engine.get_process_frames()
	_last_fog_cell = Vector2i(-99, -99)
	_fog_dirty = true
	_cached_world_lights_valid = false
	# Each floor opens a new loot segment lazily — first pickup creates it.
	_current_floor_segment_index = -1
	_last_equipped_hash = 0
	floor_kills = 0
	floor_loot_picked = 0
	floor_chests_opened = 0
	floor_altars_used = 0
	floor_fountains_used = 0
	floor_portals_entered = 0
	floor_stalls = 0
	floor_hard_recoveries = 0

	if DebugJump.active and DebugJump.biome_id != "":
		# Replace the run plan with a 10-floor stretch of the debug biome so
		# branch label, biome content, and run-plan all agree.
		run_plan = []
		for i in 10:
			run_plan.append(DebugJump.biome_id)
		current_floor = DebugJump.floor_num if DebugJump.floor_num > 0 else current_floor
		print("[debug-jump] _build_floor biome=%s floor=%d" % [DebugJump.biome_id, current_floor])
	# BOTTER_FORCE_BIOME=<id> — pin every floor of an auto-grind run to one
	# biome. Used to A/B test a specific biome's perf cost without waiting
	# for the random run plan to roll it.
	elif OS.has_environment("BOTTER_FORCE_BIOME"):
		var forced: String = OS.get_environment("BOTTER_FORCE_BIOME")
		run_plan = []
		for i in 10:
			run_plan.append(forced)
	current_biome = BiomeData.biome_for_floor(run_plan, current_floor)
	if DebugJump.active and DebugJump.biome_id != "":
		var override: Dictionary = BiomeData.get_biome(DebugJump.biome_id)
		if not override.is_empty():
			current_biome = override
			print("[debug-jump] override applied id=%s" % current_biome.get("id", "?"))
	if portal_active and not portal_biome_override.is_empty():
		current_biome = portal_biome_override
	if ambient_modulate:
		ambient_modulate.color = BiomeData.modulate_for(current_biome)
	if color_grade:
		color_grade.transition_to(current_biome.get("color_grade", {}), 0.4)
	var vault_themes: Array = current_biome.get("vault_themes", ["dungeon"])

	var seed_val: int = rng.randi()
	# Reseed the global stream from world rng each floor build, so combat
	# rng (randf in actor.gd) doesn't consume world entropy between floors.
	# Otherwise a duel where build-A crits more than build-B on floor N
	# would generate different floor N+1 layouts despite identical seed.
	seed(rng.randi())
	var gen := DungeonGen.new(seed_val)
	var layout_id: String = BiomeData.roll_layout(current_biome, rng)
	# Biome may override map size (e.g. portal vaults need bigger floors).
	var size_arr: Array = current_biome.get("map_size", [C.MAP_W, C.MAP_H])
	var map_w: int = int(size_arr[0]) if size_arr.size() >= 2 else C.MAP_W
	var map_h: int = int(size_arr[1]) if size_arr.size() >= 2 else C.MAP_H
	# Phase 1: dungeon generation (the heaviest single block, 30-450ms).
	# Yield before so the descend tween has a chance to render, and the
	# old floor's queue_free's commit on this frame.
	await get_tree().process_frame
	if my_gen != _build_generation: return
	var t_gen: int = Time.get_ticks_usec()
	var data: Dictionary
	if DebugJump.showcase:
		data = _build_showcase_floor_data()
	else:
		data = gen.generate_themed(map_w, map_h, vault_themes, current_floor, layout_id, String(current_biome.get("id", "")))
	t_gen = Time.get_ticks_usec() - t_gen
	grid = data.grid
	rooms = data.rooms
	stairs_cell = data.get("stairs_down", _find_stairs_cell())
	dist_to_stairs = data.get("dist_to_stairs", [])
	var vr: Dictionary = data.get("vault_results", {})
	_apply_vault_results(vr)
	floor_placed_vaults = []
	for vname in vr.get("placed_vaults", []):
		floor_placed_vaults.append(String(vname))
		if not run_vaults_stamped.has(String(vname)):
			run_vaults_stamped.append(String(vname))

	visited_rooms = []
	visited_rooms.resize(rooms.size())
	for i in rooms.size():
		visited_rooms[i] = false

	pathing = Path.new()
	pathing.build(grid)

	var renderer := MapRenderer.new()
	for child in map_layer.get_children():
		child.queue_free()
	map_layer.add_child(renderer)
	# Phase 2: TileMap atlas bake + tile placement (40-90ms).
	await get_tree().process_frame
	if my_gen != _build_generation or not is_instance_valid(renderer): return
	var t_render: int = Time.get_ticks_usec()
	renderer.render(grid, rooms, current_biome, rng, vr)
	t_render = Time.get_ticks_usec() - t_render
	current_renderer = renderer
	fog = FogSystem.new()
	fog.setup(grid[0].size(), grid.size(), grid)
	if fog_overlay:
		fog_overlay.set_darkness(1.0)
		fog_overlay.set_visibility_grid(fog)
		# Push the wall mask once per floor — shader ray-march samples it
		# every fragment to test LoS from the bot. Replaces the per-cell
		# Bresenham FoV that produced tile-aligned ticks + stripe artifacts.
		fog_overlay.set_wall_mask_from_grid(grid)

	bot.terrain_grid = grid
	bot.place_at(data.spawn)
	_mark_room_visited_at(bot.cell)
	_center_camera_on_bot()
	# Phase 3: ambient decor scatter (5-15ms).
	await get_tree().process_frame
	if my_gen != _build_generation: return
	var t_decor: int = Time.get_ticks_usec()
	if DebugJump.showcase:
		_spawn_showcase_stations()
	else:
		_scatter_ambient_decor()
	t_decor = Time.get_ticks_usec() - t_decor

	var biome_name: String = String(current_biome.get("display_name", "the Dungeon"))
	var branch_label: String = BiomeData.branch_depth_label(run_plan, current_floor)
	var floor_label: String = "%s (%s)" % [branch_label, biome_name]
	if portal_active:
		floor_label = "%s Portal" % Portal.PORTAL_KINDS.get(portal_kind, {}).get("name", "Portal")
	elif _is_final_boss_floor():
		floor_label = "%s — Boss" % floor_label
	elif _is_miniboss_floor(current_floor):
		floor_label = "%s — Elite" % floor_label
	journal.append({
		"floor": current_floor,
		"biome": floor_label,
		"events": [],
	})

	# Phase 4: enemy spawn (3-8ms). Skipped in showcase mode — enemies
	# there are spawned by _spawn_showcase_stations() in phase 3.
	await get_tree().process_frame
	if my_gen != _build_generation: return
	var t_spawn: int = Time.get_ticks_usec()
	if not DebugJump.showcase:
		_spawn_enemies()
	# Threat-tier auras: classify each spawned enemy by power-vs-bot.
	# Trivial / even / dangerous / lethal.
	if VideoSettings.is_effect_enabled("threat_outlines"):
		_apply_threat_auras()
	t_spawn = Time.get_ticks_usec() - t_spawn
	_update_biome_hud()
	floor_starting_hp = bot.hp
	# `stealth` flavor on worn gear grants the bot a one-shot "stealthy"
	# status at floor start — the next attack lands +25% damage. Per-
	# floor refresh keeps it as a strong-opener bonus rather than a
	# permanent buff.
	if is_instance_valid(bot) and "stealth" in bot.combat_defense_tags():
		bot.add_status("stealthy", 0.0)  # persistent until first hit
	t_total = Time.get_ticks_usec() - t_total
	_floor_ready = true
	# Wave/burst pacing — fresh on each floor build. Jitter the next
	# fire by ±25% so the rhythm doesn't feel metronomic.
	_wave_accum = 0.0
	_burst_accum = 0.0
	_wave_interval = 6.0 + rng.randf() * 4.0  # 6-10s
	_burst_interval = 30.0 + rng.randf() * 20.0  # 30-50s
	GrindLog.log_line("[build-floor] f=%d total_ms=%.1f gen_ms=%.1f render_ms=%.1f decor_ms=%.1f spawn_ms=%.1f enemies=%d" % [
		current_floor, t_total / 1000.0, t_gen / 1000.0, t_render / 1000.0,
		t_decor / 1000.0, t_spawn / 1000.0, enemies.size(),
	])
	var perf_label: String = "%s|%s|f%d" % [
		String(current_biome.get("id", "?")),
		",".join(floor_placed_vaults) if not floor_placed_vaults.is_empty() else "_",
		current_floor,
	]
	PerfMon.floor_begin(perf_label)
	floor_started.emit(current_floor)

	# Debug-jump screenshot mode: after a short settle delay, save the
	# viewport to disk and quit. Lets Claude self-verify biomes/vaults
	# without needing an interactive screenshot MCP.
	if DebugJump.active and DebugJump.screenshot:
		_schedule_debug_screenshot()

func _schedule_debug_screenshot() -> void:
	# Wait for fog to settle + sprites to fade in, then capture and quit.
	var t := get_tree().create_timer(DebugJump.screenshot_delay)
	t.timeout.connect(_capture_debug_screenshot)

func _capture_debug_screenshot() -> void:
	# Window has been pre-sized to 1024x1024 in main.gd at scene start. Here
	# we just: reveal fog, fit camera, wait one frame, save_png, write the
	# manifest, quit. No runtime resolution mutations.
	if fog and grid.size() > 0:
		var w: int = grid[0].size()
		var h: int = grid.size()
		for y in h:
			for x in w:
				fog.visibility[y][x] = fog.VIS_VISIBLE
		fog._update_texture()
		if current_renderer:
			current_renderer.apply_visibility(fog)
			current_renderer.reveal_all()
		if fog_overlay:
			fog_overlay.set_darkness(0.0)
		if ambient_modulate:
			ambient_modulate.color = Color(1, 1, 1, 1)
		if bot_light:
			bot_light.shadow_enabled = false
			bot_light.texture_scale = 50.0
			bot_light.energy = 2.5
		for inter in interactables:
			if is_instance_valid(inter):
				inter.visible = true
		for d in loot_drops:
			if is_instance_valid(d):
				d.visible = true
		for s in vault_decor_sprites:
			if is_instance_valid(s):
				s.visible = true
		for n in ambient_decor_nodes:
			if is_instance_valid(n):
				n.visible = true
		if camera:
			camera.position = Vector2(w * C.TILE_SIZE * 0.5, h * C.TILE_SIZE * 0.5)
			var view_size: Vector2 = get_viewport().get_visible_rect().size
			var map_w_px: float = float(w * C.TILE_SIZE)
			var map_h_px: float = float(h * C.TILE_SIZE)
			var zoom_x: float = view_size.x / max(1.0, map_w_px)
			var zoom_y: float = view_size.y / max(1.0, map_h_px)
			var zoom: float = minf(zoom_x, zoom_y) * 0.92
			camera.zoom = Vector2(zoom, zoom)
	# One frame after the camera/fog/visibility are set, render and capture.
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var dir := DirAccess.open("user://")
	if dir != null and not dir.dir_exists("debug_screenshots"):
		dir.make_dir("debug_screenshots")
	var name: String = DebugJump.biome_id
	if DebugJump.vault_name != "":
		name += "_" + DebugJump.vault_name
	var ts: int = Time.get_ticks_msec()
	var path := "user://debug_screenshots/%s_%d.png" % [name, ts]
	img.save_png(path)
	# Sidecar JSON with EVERYTHING Claude can't reliably read off a downscaled
	# pixel-art screenshot. The PNG is just shape/silhouette; this is truth.
	var sidecar_path: String = "user://debug_screenshots/%s_%d.json" % [name, ts]
	var meta: Dictionary = _collect_render_manifest(img, path, ts)
	var jf := FileAccess.open(sidecar_path, FileAccess.WRITE)
	if jf:
		jf.store_string(JSON.stringify(meta, "  "))
		jf.close()
	var manifest_path := "user://debug_screenshots/_manifest.txt"
	var existing: Dictionary = {}
	if FileAccess.file_exists(manifest_path):
		var rf := FileAccess.open(manifest_path, FileAccess.READ)
		if rf:
			for line in rf.get_as_text().split("\n"):
				if "=" in line:
					var p: PackedStringArray = line.split("=", true, 1)
					existing[p[0].strip_edges()] = p[1].strip_edges()
	existing[name] = path
	existing["LAST"] = path
	existing["LAST_JSON"] = sidecar_path
	var wf := FileAccess.open(manifest_path, FileAccess.WRITE)
	if wf:
		var keys: Array = existing.keys()
		keys.sort()
		for k in keys:
			wf.store_line("%s=%s" % [k, existing[k]])
		wf.close()
	print("[debug-screenshot] saved %s + %s" % [path, sidecar_path])
	get_tree().quit()

func _serialize_marks(marks: Array) -> Array:
	# Convert renderer marks (Vector2i cells) to JSON-friendly [x,y] arrays.
	var out: Array = []
	for m in marks:
		var d: Dictionary = {}
		if m is Dictionary:
			for k in m.keys():
				var v = m[k]
				if v is Vector2i:
					d[String(k)] = [int(v.x), int(v.y)]
				else:
					d[String(k)] = v
		out.append(d)
	return out

func _collect_render_manifest(img: Image, png_path: String, ts: int) -> Dictionary:
	# Comprehensive render manifest. Everything that informs what a Claude
	# image-reviewer should "see" — biome config, layout, all loaded textures,
	# overlay set, every entity on the floor with its cell, walls vs floor
	# counts, stairs/spawn, room rects, ambient settings, etc.
	var w: int = grid[0].size() if grid.size() > 0 else 0
	var h: int = grid.size()
	var floor_count: int = 0
	var wall_count: int = 0
	var door_count: int = 0
	var stair_count: int = 0
	var lava_count: int = 0
	var water_count: int = 0
	var ice_count: int = 0
	for y in h:
		for x in w:
			var v: int = grid[y][x]
			if v == C.T_FLOOR: floor_count += 1
			elif v == C.T_WALL: wall_count += 1
			elif v == C.T_DOOR: door_count += 1
			elif v == C.T_STAIRS_DOWN: stair_count += 1
			elif v == C.T_LAVA: lava_count += 1
			elif v == C.T_WATER: water_count += 1
			elif v == C.T_ICE: ice_count += 1

	var floor_primary: Array = BiomeData.load_floor_primary(current_biome)
	var floor_accent: Array = BiomeData.load_floor_accent(current_biome)
	var wall_primary: Array = BiomeData.load_wall_primary(current_biome)
	var wall_accent: Array = BiomeData.load_wall_accent(current_biome)
	var wall_alts: Array = BiomeData.load_wall_alternates(current_biome)
	var edge_overlay: Dictionary = BiomeData.load_edge_overlay(current_biome)

	var floor_primary_paths: Array = []
	for tex in floor_primary:
		if tex and tex.resource_path:
			floor_primary_paths.append(String(tex.resource_path))
	var floor_accent_paths: Array = []
	for tex in floor_accent:
		if tex and tex.resource_path:
			floor_accent_paths.append(String(tex.resource_path))
	var wall_primary_paths: Array = []
	for tex in wall_primary:
		if tex and tex.resource_path:
			wall_primary_paths.append(String(tex.resource_path))
	var wall_accent_paths: Array = []
	for tex in wall_accent:
		if tex and tex.resource_path:
			wall_accent_paths.append(String(tex.resource_path))
	var wall_alt_summary: Array = []
	for entry in wall_alts:
		var paths: Array = []
		for tex in entry.get("textures", []):
			if tex and tex.resource_path:
				paths.append(String(tex.resource_path))
		wall_alt_summary.append({"weight": entry.get("weight", 0), "textures": paths})
	var overlay_summary: Dictionary = {}
	for k in edge_overlay.keys():
		var val = edge_overlay[k]
		if val is Texture2D:
			overlay_summary[String(k)] = String(val.resource_path) if val.resource_path else "(unloaded)"
		elif val is Array:
			var arr: Array = []
			for tex in val:
				if tex is Texture2D and tex.resource_path:
					arr.append(String(tex.resource_path))
			overlay_summary[String(k)] = arr
		else:
			overlay_summary[String(k)] = val

	# Every enemy with id + cell + hp
	var enemy_list: Array = []
	for e in enemies:
		if not is_instance_valid(e): continue
		enemy_list.append({
			"id": String(e.enemy_id) if "enemy_id" in e else "",
			"name": String(e.display_name) if "display_name" in e else "",
			"cell": [int(e.cell.x), int(e.cell.y)],
			"hp": int(e.hp) if "hp" in e else 0,
			"max_hp": int(e.max_hp) if "max_hp" in e else 0,
			"is_boss": bool(e.is_boss) if "is_boss" in e else false,
			"is_miniboss": bool(e.is_miniboss) if "is_miniboss" in e else false,
			"visual_scale": float(e.visual_scale) if "visual_scale" in e else 1.0,
			"visual_anchor": String(e.visual_anchor) if "visual_anchor" in e else "centre",
		})

	# Every interactable
	var inter_list: Array = []
	for i in interactables:
		if not is_instance_valid(i): continue
		var kind: String = "unknown"
		var extra: Dictionary = {}
		if i is Chest:
			kind = "chest"
			extra["bias"] = i.rarity_bias
			extra["drops"] = i.drop_count
		elif i is Fountain:
			kind = "fountain"
		elif i is Altar:
			kind = "altar"
			extra["god"] = i.god
		elif i is Portal:
			kind = "portal"
			extra["portal_kind"] = i.kind
		elif i is LootDrop:
			kind = "loot"
			if "item" in i:
				extra["item_id"] = i.item.get("id", "")
				extra["rarity"] = i.item.get("rarity", "")
		else:
			kind = String(i.get_class())
		inter_list.append({
			"kind": kind,
			"cell": [int(i.cell.x), int(i.cell.y)],
			"consumed": bool(i.consumed) if "consumed" in i else false,
		} if extra.is_empty() else {
			"kind": kind,
			"cell": [int(i.cell.x), int(i.cell.y)],
			"consumed": bool(i.consumed) if "consumed" in i else false,
			"extra": extra,
		})

	# Rooms (BSP rectangles)
	var room_list: Array = []
	for r in rooms:
		room_list.append({
			"x": int(r.position.x), "y": int(r.position.y),
			"w": int(r.size.x), "h": int(r.size.y),
		})

	return {
		"png": png_path,
		"timestamp_ms": ts,
		"requested": {
			"biome_id": DebugJump.biome_id,
			"vault_name": DebugJump.vault_name,
			"floor_num": DebugJump.floor_num,
		},
		"resolved": {
			"biome_id": String(current_biome.get("id", "?")),
			"display_name": String(current_biome.get("display_name", "")),
			"layout_id": current_biome.get("layout", ""),
			"layouts_pool": current_biome.get("layouts", []),
			"vault_themes": current_biome.get("vault_themes", []),
			"darkness": float(current_biome.get("darkness", 0.0)),
			"modulate": current_biome.get("modulate", []),
			"map_size": current_biome.get("map_size", []),
			"enemy_pool": current_biome.get("enemy_pool", []),
			"ambient_decor": current_biome.get("ambient_decor", []),
			"ambient_density": current_biome.get("ambient_density", 0.0),
		},
		"render_textures": {
			"floor_primary_count": floor_primary_paths.size(),
			"floor_primary_samples": floor_primary_paths,
			"floor_accent_count": floor_accent_paths.size(),
			"floor_accent_samples": floor_accent_paths,
			"wall_primary": wall_primary_paths,
			"wall_accent": wall_accent_paths,
			"wall_alternates": wall_alt_summary,
			"edge_overlay": overlay_summary,
		},
		"hud": {
			"name": chrome.lbl_name.text if (chrome and is_instance_valid(chrome.lbl_name)) else "",
			"place": chrome.lbl_place.text if (chrome and is_instance_valid(chrome.lbl_place)) else "",
			"hp": chrome.lbl_hp.text if (chrome and is_instance_valid(chrome.lbl_hp)) else "",
			"atk": chrome.lbl_atk.text if (chrome and is_instance_valid(chrome.lbl_atk)) else "",
			"def": chrome.lbl_def.text if (chrome and is_instance_valid(chrome.lbl_def)) else "",
			"crit": chrome.lbl_crit.text if (chrome and is_instance_valid(chrome.lbl_crit)) else "",
			"haste": chrome.lbl_haste.text if (chrome and is_instance_valid(chrome.lbl_haste)) else "",
			"regen": chrome.lbl_regen.text if (chrome and is_instance_valid(chrome.lbl_regen)) else "",
			"gold": chrome.lbl_gold.text if (chrome and is_instance_valid(chrome.lbl_gold)) else "",
		},
		"bot": {
			"cell": [int(bot.cell.x), int(bot.cell.y)] if is_instance_valid(bot) else [],
			"hp": int(bot.hp) if is_instance_valid(bot) else 0,
			"max_hp": int(bot.max_hp) if is_instance_valid(bot) else 0,
			"atk": int(bot.atk) if is_instance_valid(bot) else 0,
			"def": int(bot.defense) if is_instance_valid(bot) else 0,
			"level": int(bot.level) if is_instance_valid(bot) else 0,
			"xp": int(bot.xp) if is_instance_valid(bot) else 0,
			"gold": int(bot.gold) if is_instance_valid(bot) else 0,
		},
		"floor": {
			"number": current_floor,
			"width": w,
			"height": h,
			"floor_cells": floor_count,
			"wall_cells": wall_count,
			"door_cells": door_count,
			"stair_cells": stair_count,
			"terrain_cells": {
				"lava": lava_count,
				"water": water_count,
				"ice": ice_count,
			},
			"rooms": room_list,
			"spawn_cell": [int(bot.cell.x), int(bot.cell.y)] if is_instance_valid(bot) else [],
			"stairs_cell": [int(stairs_cell.x), int(stairs_cell.y)],
			"placed_vaults_this_run": run_vaults_stamped,
			"branch_label": BiomeData.branch_depth_label(run_plan, current_floor),
		},
		"entities": {
			"enemies": enemy_list,
			"interactables": inter_list,
			"vault_decor_sprite_count": vault_decor_sprites.size(),
			"ambient_decor_node_count": ambient_decor_nodes.size(),
			"sigils_stamped": _serialize_marks(current_renderer.sigil_marks if current_renderer and "sigil_marks" in current_renderer else []),
			"decor_marks": _serialize_marks(current_renderer.decor_marks if current_renderer and "decor_marks" in current_renderer else []),
		},
		"render": {
			"image_width": img.get_width(),
			"image_height": img.get_height(),
			"pixels_per_tile": C.TILE_SIZE,
			"camera_position": [camera.position.x, camera.position.y] if camera else [],
			"camera_zoom": [camera.zoom.x, camera.zoom.y] if camera else [],
		},
		"warning": "DCSS pixel-art at 32px tiles, downscaled to a 1024px square. Trust this JSON for facts (biome, HUD, stats, entity positions, tile palettes). The PNG is reliable for shape, layout structure, and broad color silhouettes only.",
	}

func _ensure_hud() -> void:
	if chrome != null:
		return
	chrome = HudChrome.new()
	add_child(chrome)
	# HUD inventory cells call back here to request an equip swap.
	chrome.equip_request_target = self
	# Drag-drop signals from the HUD — let the player rearrange gear /
	# spells mid-run by dragging from inventory onto a paperdoll slot.
	chrome.hud_drag_drop.connect(_on_hud_drag_drop)
	chrome.hud_unequip_requested.connect(_on_hud_unequip_requested)

# DragManager fired drag_ended; HUD bubbled the payload + dst_slot up.
# Routes both inventory→paperdoll and paperdoll→paperdoll through the
# same code paths the click-equip uses (try_equip_from_segment +
# bot.equip_from_inventory) so the segment math + 2H exclusion + cache
# rebuild stay consistent. Without this, the drag-drop path fragmented
# the segment list and double-appended items.
func _on_hud_drag_drop(payload: Dictionary, dst_slot: String) -> void:
	if not is_instance_valid(bot):
		return
	var src_role: String = String(payload.get("role", ""))
	if src_role == "inventory":
		_hud_drag_equip_from_inv(int(payload.get("inv_index", -1)), dst_slot)
	elif src_role == "paperdoll":
		_hud_drag_swap_slots(String(payload.get("slot_id", "")), dst_slot)
	if chrome:
		chrome.update_equipped(bot.equipped, items_db, bot.species_id)
	_push_inventory_to_hud()
	_last_equipped_hash = 0

# Mid-run unequip — HUD sent the slot, we move the item back to the
# active loot segment so it shows up in the bag. Updates bot.equipped
# directly + rebuilds the inv cache so the bag re-renders cleanly.
func _on_hud_unequip_requested(slot_id: String) -> void:
	if not is_instance_valid(bot):
		return
	var current: Variant = bot.equipped.get(slot_id, null)
	if current == null or typeof(current) != TYPE_DICTIONARY:
		return
	bot.equipped[slot_id] = null
	bot.recompute_stats()
	bot._refresh_gear_overlays()
	_append_to_active_segment(current)
	_rebuild_inv_cache()
	if chrome:
		chrome.update_equipped(bot.equipped, items_db, bot.species_id)
	_push_inventory_to_hud()
	_last_equipped_hash = 0

# Inventory → paperdoll (drag). Find the segment that owns the flat
# inv_index, hand the item to bot.equip_from_inventory (which handles
# slot routing + 2H exclusion + recompute_stats), and place displaced
# items back at the SOURCE segment so the inventory order stays
# stable. Mirrors try_equip_from_segment exactly.
func _hud_drag_equip_from_inv(flat_inv_index: int, dst_slot: String) -> void:
	if flat_inv_index < 0 or flat_inv_index >= _hud_inv_cache.size():
		return
	# Find source segment + local index from the flat index.
	var src_seg_idx: int = -1
	var src_local_idx: int = -1
	var offset: int = 0
	for i in _loot_segments.size():
		var items: Array = _loot_segments[i].get("items", [])
		if flat_inv_index < offset + items.size():
			src_seg_idx = i
			src_local_idx = flat_inv_index - offset
			break
		offset += items.size()
	if src_seg_idx < 0 or src_local_idx < 0:
		return
	var src_items: Array = _loot_segments[src_seg_idx].get("items", [])
	var inst: Variant = src_items[src_local_idx]
	if typeof(inst) != TYPE_DICTIONARY:
		return
	# Per-slot cooldown gate (mirrors try_equip_from_segment so click
	# and drag honour the same equip cadence).
	var cd: float = float(_slot_cooldowns.get(dst_slot, 0.0))
	if cd > 0.0:
		_log("Equip on cooldown: %s (%.0fs left)" % [dst_slot.capitalize(), cd], "combat")
		return
	# Force the bot's resolver to write into the EXPLICIT dst_slot the
	# user picked — without this, dragging a spell onto spell3 would
	# auto-route into spell1 if it was empty. Cache + restore the
	# instance's "slot" field briefly to short-circuit the resolver.
	var item: Dictionary = items_db.get(String(inst.get("base_id", "")), {})
	if item.is_empty():
		return
	var displaced_arr: Array = _equip_to_explicit_slot(inst, dst_slot)
	if displaced_arr.is_empty() and bot.equipped.get(dst_slot, null) != inst:
		# Block was hit upstream (species-blocked, etc) — no-op.
		return
	src_items.remove_at(src_local_idx)
	for d in displaced_arr:
		if typeof(d) == TYPE_DICTIONARY:
			src_items.append(d)
	_slot_cooldowns[dst_slot] = EQUIP_COOLDOWN_SECONDS
	_rebuild_inv_cache()

# Equip an inventory instance into an EXPLICIT slot (no auto-routing).
# Returns displaced items the same way bot.equip_from_inventory does
# so callers can reinsert them. Used by the drag-drop path; the click
# path keeps using bot.equip_from_inventory which auto-routes.
func _equip_to_explicit_slot(inst: Dictionary, dst_slot: String) -> Array:
	if not is_instance_valid(bot):
		return []
	var item: Dictionary = items_db.get(String(inst.get("base_id", "")), {})
	if item.is_empty():
		return []
	# Species body-shape block.
	if not dst_slot.begins_with("spell") and not SpeciesData.can_wear(bot.species_id, dst_slot):
		return []
	var displaced: Array = []
	# 2H↔shield exclusion (gear slots only).
	if dst_slot == "weapon" and Bot.is_two_handed_base_type(String(item.get("base_type", ""))):
		var s: Variant = bot.equipped.get("shield", null)
		if s != null and typeof(s) == TYPE_DICTIONARY:
			displaced.append(s)
			bot.equipped["shield"] = null
	elif dst_slot == "shield":
		var w: Variant = bot.equipped.get("weapon", null)
		if w != null and typeof(w) == TYPE_DICTIONARY:
			var w_id: String = String(w.get("base_id", ""))
			if w_id != "" and items_db.has(w_id):
				if Bot.is_two_handed_base_type(String(items_db[w_id].get("base_type", ""))):
					displaced.append(w)
					bot.equipped["weapon"] = null
	# Direct displace into dst_slot.
	var prev: Variant = bot.equipped.get(dst_slot, null)
	if prev != null and typeof(prev) == TYPE_DICTIONARY:
		displaced.append(prev)
	bot.equipped[dst_slot] = inst.duplicate(true)
	var prev_max: int = bot.max_hp
	bot.recompute_stats()
	bot.hp = clampi(bot.hp + (bot.max_hp - prev_max), 0, bot.max_hp)
	bot._update_hp_bar()
	bot._refresh_gear_overlays()
	return displaced

func _hud_drag_swap_slots(src_slot: String, dst_slot: String) -> void:
	if src_slot == "" or src_slot == dst_slot:
		return
	var a: Variant = bot.equipped.get(src_slot, null)
	if a == null or typeof(a) != TYPE_DICTIONARY:
		return
	var b: Variant = bot.equipped.get(dst_slot, null)
	bot.equipped[dst_slot] = a
	bot.equipped[src_slot] = b if (b != null and typeof(b) == TYPE_DICTIONARY) else null
	bot.recompute_stats()
	bot._refresh_gear_overlays()

# Append `inst` to the active floor segment if one exists, else
# segment 0 (Base). Used by mid-run unequip + drag-drop displaced
# items. Keeps newly-displaced gear discoverable on the current
# floor instead of polluting the base inventory.
func _append_to_active_segment(inst: Dictionary) -> void:
	if _loot_segments.is_empty():
		return
	var idx: int = _current_floor_segment_index if (_current_floor_segment_index >= 0 and _current_floor_segment_index < _loot_segments.size()) else 0
	_loot_segments[idx]["items"].append(inst)

var _hud_full_refresh_accum: float = 0.0
var _last_equipped_hash: int = 0
# Inventory presented to the player. Segmented so the HUD can render a
# Base section + one section per floor that produced loot. Each segment is
# {header: String, items: Array[Dictionary]}. Mutating the items array
# (equip / loot) updates the HUD next frame; segments are never collapsed
# during a run so the player can see "what came from where" at a glance.
var _loot_segments: Array = []
var _current_floor_segment_index: int = -1
# Mirror used at run end to compute the flat saved inventory. Equals the
# concatenation of every segment's items, in order.
var _hud_inv_cache: Array = []
var _hud_inventory_seeded: bool = false
# Per-slot equip cooldowns in seconds. Decremented every _process tick.
var _slot_cooldowns: Dictionary = {}
const EQUIP_COOLDOWN_SECONDS := 30.0

func _update_biome_hud() -> void:
	_ensure_hud()
	var biome_id: String = String(current_biome.get("id", "?"))
	var branch: String = BiomeData.branch_depth_label(run_plan, current_floor)
	var place_str := "%s  (%s)" % [branch, biome_id]
	# Stats label updates internally diff each label — cheap when steady.
	chrome.update_stats(bot, place_str, run_turn)
	if is_instance_valid(bot):
		chrome.update_buffs(bot.active_statuses())
	_hud_full_refresh_accum += get_process_delta_time()
	var equipped_hash: int = (bot.equipped.hash() if is_instance_valid(bot) else 0)
	var eq_changed: bool = equipped_hash != _last_equipped_hash
	if eq_changed:
		chrome.update_equipped(bot.equipped if is_instance_valid(bot) else {}, items_db, bot.species_id if is_instance_valid(bot) else "")
		_last_equipped_hash = equipped_hash
	# Inventory updates are pushed via _push_inventory_to_hud() whenever
	# segments mutate (loot pickup, equip). First-tick push covers the case
	# where the chrome wasn't ready when the run started.
	if not _hud_inventory_seeded:
		_push_inventory_to_hud()
		_hud_inventory_seeded = true
	# Minimap — every 0.25s is plenty for visualizing bot motion.
	if _hud_full_refresh_accum >= 0.25:
		_hud_full_refresh_accum = 0.0
		var visible_cells: Dictionary = {}
		if fog != null and "visible" in fog:
			visible_cells = fog.visible
		if grid is Array and not grid.is_empty():
			var bot_cell: Vector2i = bot.cell if is_instance_valid(bot) else Vector2i(-1, -1)
			chrome.update_minimap(grid, bot_cell, stairs_cell, visible_cells)
	# Debug HUD (top-left): biome / vaults / cell counts / FPS.
	var dbg: Array = []
	dbg.append("biome: %s" % biome_id)
	dbg.append("floor: %d  layout: %s" % [current_floor, String(current_biome.get("layout", "?"))])
	if not run_vaults_stamped.is_empty():
		var recent_vaults: Array = run_vaults_stamped.slice(max(0, run_vaults_stamped.size() - 4))
		dbg.append("vaults: %s" % ", ".join(recent_vaults.map(func(s): return String(s))))
	if grid is Array and not grid.is_empty():
		dbg.append("grid: %dx%d" % [grid[0].size(), grid.size()])
	dbg.append("enemies: %d  inter: %d" % [enemies.size(), interactables.size()])
	dbg.append("fps: %d  draws: %d" % [
		Engine.get_frames_per_second(),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
	])
	for line in PerfMon.format_hud_lines():
		dbg.append(line)
	chrome.update_debug(dbg)

func _spawn_enemies() -> void:
	var pool: Array = []
	var is_boss_floor: bool = current_floor >= _boss_floor
	var biome_pool: Array = current_biome.get("enemy_pool", [])
	for id in enemy_data.keys():
		var def: Dictionary = enemy_data[id]
		if def.boss:
			continue
		if biome_pool.has(id) and def.min_floor <= current_floor:
			pool.append(id)
	if pool.is_empty():
		for id in enemy_data.keys():
			var def2: Dictionary = enemy_data[id]
			if not def2.boss and def2.min_floor <= current_floor:
				pool.append(id)
	if pool.is_empty():
		pool.append("rat")

	if is_boss_floor:
		# Branch boss = the strongest enemy in the branch's pool, scaled to
		# boss tier. Lets every branch have a thematic boss without
		# bespoke per-branch enemy data; bespoke bosses can replace this
		# later by setting a `boss_id` field on the biome. We ignore
		# min_floor for the boss pick because boss floors should always
		# have one regardless of "this enemy normally only spawns on D:8".
		var boss_pool: Array = []
		for id in biome_pool:
			if enemy_data.has(id) and not enemy_data[id].boss:
				boss_pool.append(id)
		var boss_id: String = _pick_branch_boss_id(boss_pool if not boss_pool.is_empty() else pool)
		_spawn_branch_boss(boss_id, _pick_boss_room())
	elif _is_miniboss_floor(current_floor):
		var elite_id: String = _pick_miniboss_id(pool)
		_spawn_miniboss(elite_id, _pick_boss_room())

	for cell in vault_spawn_overrides.keys():
		var spec: Variant = vault_spawn_overrides[cell]
		if typeof(spec) != TYPE_DICTIONARY:
			continue
		var enemy_pool: Array = spec.get("enemy_pool", [])
		if enemy_pool.is_empty():
			continue
		var enemy_id: String = String(enemy_pool[rng.randi_range(0, enemy_pool.size() - 1)])
		_spawn_specific(enemy_id, cell)

	# Pack-clustered spawn. Replaces the old "for N: spawn random" loop.
	# We aim for high mob counts (floor 1 ~50, floor 6 ~150) by spawning
	# a moderate number of pack centers, each surrounded by a cluster
	# of same-id packmates. Cluster spawning is cheaper than uniform
	# random because:
	#   * AI repath cap (3/frame) and 8-cell aggro range mean idle
	#     packs cost almost nothing per frame
	#   * Sticky-target combat naturally engages one pack at a time
	#   * Enemy soft-collision keeps cluster packing reasonable
	# Pack leaders re-roll for magic/rare at slightly elevated rates so
	# they're the visual centerpiece.
	_spawn_packs(pool)

	var chest_count: int = 1 + (1 if rng.randf() < 0.5 else 0)
	if _is_miniboss_floor(current_floor):
		chest_count = 2
	if is_boss_floor:
		chest_count = 3
	if portal_active:
		chest_count += 1 + portal_loot_bias
	# Treasure Hoard adds one chest per floor.
	chest_count += int(RunModifiers.sum_effect(active_modifiers, "extra_chests_per_floor", 0.0))
	# Hunted modifier: extra elite on the targeted floor.
	if RunModifiers.has_extra_miniboss_on(active_modifiers, current_floor):
		var elite_id2: String = _pick_miniboss_id(pool)
		_spawn_miniboss(elite_id2, _pick_boss_room())
	for i in chest_count:
		var chest_cell: Vector2i = _random_walkable_cell_far_from_bot()
		var bias: int = 0
		if rng.randf() < 0.2:
			bias = 1
		if rng.randf() < 0.05 or is_boss_floor:
			bias = 2
		if portal_active:
			bias = max(bias, portal_loot_bias)
		# Fortified modifier: chests carry more contents.
		var contents_mult: float = RunModifiers.sum_effect(active_modifiers, "chest_contents_mult", 1.0)
		var contents: int = int(round(float(rng.randi_range(1, 3)) * contents_mult))
		_spawn_chest(chest_cell, contents, bias)

	if rng.randf() < 0.35:
		var fountain_cell: Vector2i = _random_walkable_cell_far_from_bot()
		var kind_roll: float = rng.randf()
		var fountain_kind: String = "blue"
		if kind_roll < 0.15:
			fountain_kind = "sparkling"
		elif kind_roll < 0.30:
			fountain_kind = "blood"
		_spawn_fountain(fountain_cell, fountain_kind)

	if not is_boss_floor and rng.randf() < 0.25:
		var altar_cell: Vector2i = _random_walkable_cell_far_from_bot()
		_spawn_altar(altar_cell)

	# Portals: stepping on one swaps the floor to a themed mini-floor with
	# bumped loot. Skip on portal floors themselves and on the boss/floor 1.
	if not is_boss_floor and not portal_active and current_floor >= 2 and current_floor <= _floors_per_run - 1:
		if rng.randf() < 0.15:
			var portal_cell: Vector2i = _random_walkable_cell_far_from_bot()
			_spawn_portal(portal_cell)

func _is_miniboss_floor(f: int) -> bool:
	return f != _boss_floor and f in C.MINIBOSS_FLOORS

func _is_final_boss_floor() -> bool:
	return current_floor >= _boss_floor

func _log(msg: String, tag: String = "combat") -> void:
	if not journal.is_empty():
		journal.back().events.append(msg)
	if chrome != null:
		chrome.push_log(msg, tag)

func _pick_miniboss_id(pool: Array) -> String:
	if pool.is_empty():
		return "rat"
	var ranked: Array = pool.duplicate()
	ranked.sort_custom(func(a, b): return float(enemy_data[a].hp) > float(enemy_data[b].hp))
	return ranked[0]

# Branch boss = strongest enemy from the branch's pool. Same selection as
# miniboss but scaled differently (see _spawn_branch_boss).
func _pick_branch_boss_id(pool: Array) -> String:
	return _pick_miniboss_id(pool)

func _branch_tier_mult() -> float:
	# Reads from current_biome (set per floor in _build_floor). Defaults to
	# tier 1 if missing or out of range. Folds in the Bloodlust modifier
	# (enemy_stat_mult) so it applies uniformly to every enemy spawn site.
	var tier: int = clampi(int(current_biome.get("tier", 1)) - 1, 0, C.TIER_SCALE.size() - 1)
	var mod_mult: float = RunModifiers.sum_effect(active_modifiers, "enemy_stat_mult", 1.0)
	return float(C.TIER_SCALE[tier]) * mod_mult

func _apply_threat_auras() -> void:
	# Classify each living enemy 0..3 based on power-vs-bot. Cheap heuristic:
	#   ratio = enemy.atk / max(bot.atk - enemy.defense, 1)  (rounds-to-kill)
	#   * combined with hp ratio
	# Bosses + minibosses pin to tier 3 / 2 regardless.
	if not is_instance_valid(bot):
		return
	var bot_eff_atk: float = max(1.0, float(bot.atk))
	var bot_max_hp: float = max(1.0, float(bot.max_hp))
	for e in enemies:
		if not is_instance_valid(e) or not e.is_alive:
			continue
		var tier: int = 0
		if e.is_boss:
			tier = 3
		elif e.is_miniboss:
			tier = 2
		else:
			# Hits-to-kill from bot's perspective. With heavy DEF the bot
			# can struggle even on low-HP enemies — factor that in.
			var net_atk: float = max(1.0, bot_eff_atk - float(e.defense))
			var hits_to_kill: float = float(e.max_hp) / net_atk
			# Damage ratio: enemy hp from one bot hit vs bot's max hp
			# from one enemy hit.
			var enemy_threat: float = float(e.atk) / bot_max_hp
			# Combine: many hits to kill OR significant enemy damage = higher tier.
			if hits_to_kill > 6.0 or enemy_threat > 0.20:
				tier = 3
			elif hits_to_kill > 3.0 or enemy_threat > 0.10:
				tier = 2
			elif hits_to_kill > 1.5 or enemy_threat > 0.04:
				tier = 1
			else:
				tier = 0
		e.apply_threat_aura(tier)

func _spawn_branch_boss(id: String, at_cell: Vector2i) -> void:
	if not enemy_data.has(id):
		return
	var def: Dictionary = enemy_data[id]
	var e := Enemy.new()
	actor_layer.add_child(e)
	e.enemy_id = id + "_boss"
	e.display_name = "Greater " + str(def.name)  # placeholder; bespoke names later
	e.xp_reward = int(def.xp) * 8
	e.is_boss = true
	var floor_mult: float = pow(1.10, current_floor - 1)
	var tier_mult: float = _branch_tier_mult()
	# Boss stats: similar to miniboss but bumped — 3.0× HP, 1.7× ATK, 1.5× DEF.
	e.max_hp = int(round(float(def.hp) * floor_mult * tier_mult * 3.0))
	e.atk = int(round(float(def.atk) * floor_mult * tier_mult * 1.7))
	e.defense = int(round(float(def.def) * floor_mult * tier_mult * 1.5))
	e.hp = e.max_hp
	e.move_speed = float(def.speed) * 4.0
	var tex: Texture2D = load(ENEMY_TILE_DIR + def.tile)
	if tex:
		e.set_texture(tex)
		var base_scale: float = float(def.get("visual_scale", 1.0))
		var anchor: String = String(def.get("visual_anchor", "centre"))
		# Boss scale: 1.7× base, capped by Actor.apply_visual_scale.
		e.apply_visual_scale(base_scale * 1.7, anchor, 3)
		if e.rig:
			e.rig.modulate = Color(1.4, 0.8, 0.8)
			e.fx = SpriteFX.new(e.rig, e.sprite)
		var bl_spec: String = String(def.get("light_spec", ""))
		if bl_spec != "":
			LightSpec.attach(e, bl_spec)
	# Persistent red outline so the player reads "boss" at a glance,
	# regardless of bot-relative threat (a tank bot can shred a boss
	# but the visual identity should stay consistent).
	e.apply_persistent_outline()
	e.place_at(at_cell)
	e.repath_timer = rng.randf_range(0.0, Enemy.REPATH_INTERVAL)
	e.died.connect(_on_enemy_died)
	enemies.append(e)

func _spawn_miniboss(id: String, at_cell: Vector2i) -> void:
	if not enemy_data.has(id):
		return
	var def: Dictionary = enemy_data[id]
	var e := Enemy.new()
	actor_layer.add_child(e)
	e.enemy_id = id + "_elite"
	e.display_name = "Greater " + str(def.name)
	e.xp_reward = int(def.xp) * 4
	e.is_boss = false
	e.is_miniboss = true
	var floor_mult: float = pow(1.10, current_floor - 1)
	var tier_mult: float = _branch_tier_mult()
	e.max_hp = int(round(float(def.hp) * floor_mult * tier_mult * 1.8))
	e.atk = int(round(float(def.atk) * floor_mult * tier_mult * 1.4))
	e.defense = int(round(float(def.def) * floor_mult * tier_mult * 1.3))
	e.hp = e.max_hp
	e.move_speed = float(def.speed) * 4.0
	var tex: Texture2D = load(ENEMY_TILE_DIR + def.tile)
	if tex:
		e.set_texture(tex)
		# Miniboss visual = base creature scale x 1.4, capped at 2.5.
		var base_scale: float = float(def.get("visual_scale", 1.0))
		var anchor: String = String(def.get("visual_anchor", "centre"))
		e.apply_visual_scale(base_scale * 1.4, anchor, 2)
		if e.rig:
			e.rig.modulate = Color(1.2, 0.85, 0.85)
			e.fx = SpriteFX.new(e.rig, e.sprite)
		# Miniboss inherits creature's light_spec if defined.
		var ml_spec: String = String(def.get("light_spec", ""))
		if ml_spec != "":
			LightSpec.attach(e, ml_spec)
	# Orange outline for minibosses — telegraphs "elite" without
	# matching the boss red.
	e.apply_persistent_outline()
	e.place_at(at_cell)
	# Stagger initial repath so a freshly-spawned horde doesn't all repath
	# on the same frame. Spread across the full REPATH_INTERVAL.
	e.repath_timer = rng.randf_range(0.0, Enemy.REPATH_INTERVAL)
	e.died.connect(_on_enemy_died)
	enemies.append(e)

func _spawn_specific(id: String, at_cell: Vector2i, force_pack_tier: int = -1) -> void:
	if not enemy_data.has(id):
		return
	var def: Dictionary = enemy_data[id]
	var e := Enemy.new()
	actor_layer.add_child(e)
	var is_champion: bool = (not def.boss) and rng.randf() < 0.012
	# Pack tier roll. Skip for champions (already special) and bosses
	# (their own treatment). Magic/rare are PoE-style modifiers on top
	# of the base creature. Pack-system callers can force a specific
	# tier (leaders force magic/rare, packmates force normal) via
	# force_pack_tier; default -1 means "roll normally."
	var pack_tier: int = Enemy.PACK_NORMAL
	if force_pack_tier >= 0:
		pack_tier = force_pack_tier
	elif not bool(def.boss) and not is_champion:
		var src_tier: int = int(current_biome.get("tier", 1))
		pack_tier = _roll_pack_tier(src_tier)
	var picked_mods: Array = []
	if pack_tier == Enemy.PACK_MAGIC:
		picked_mods = _pick_pack_mods(1)
	elif pack_tier == Enemy.PACK_RARE:
		picked_mods = _pick_pack_mods(2)
	# Build the display name: rare gets its mod labels prefixed
	# (e.g. "Hasted Vicious Goblin"), magic gets a faint marker, normal
	# stays vanilla.
	var base_name: String = String(def.name)
	if is_champion:
		base_name = "Champion " + base_name
	if pack_tier == Enemy.PACK_RARE:
		var prefix: PackedStringArray = []
		for m in picked_mods:
			prefix.append(String(m.get("label", "")))
		e.display_name = " ".join(prefix) + " " + base_name
		e.display_name = e.display_name.strip_edges()
	elif pack_tier == Enemy.PACK_MAGIC and not picked_mods.is_empty():
		e.display_name = "%s %s" % [String(picked_mods[0].get("label", "")), base_name]
	else:
		e.display_name = base_name
	e.enemy_id = id
	# Pack-tier xp scaling — magic 1.5x, rare 3x. Same shape as champion.
	var pack_xp_mult: float = 1.0
	if pack_tier == Enemy.PACK_MAGIC: pack_xp_mult = 1.5
	elif pack_tier == Enemy.PACK_RARE: pack_xp_mult = 3.0
	e.xp_reward = int(round(float(def.xp) * (3.0 if is_champion else 1.0) * pack_xp_mult))
	e.is_boss = bool(def.boss)
	e.pack_tier = pack_tier
	var floor_mult: float = pow(1.10, current_floor - 1)
	# Branch tier multiplier — turns the same enemy IDs into Tier-5
	# nightmares without bespoke per-tier enemy data. See constants.gd
	# TIER_SCALE.
	var tier_mult: float = _branch_tier_mult()
	var champ_mult: float = 1.5 if is_champion else 1.0
	# Pack stat bumps — magic +20% HP/+10% ATK, rare +60% HP/+30% ATK.
	# Multiplicative on top of champion/floor/tier so the strongest
	# scenarios (T5 floor 6 rare champion) read as appropriately scary.
	var pack_hp_mult: float = 1.0
	var pack_atk_mult: float = 1.0
	if pack_tier == Enemy.PACK_MAGIC:
		pack_hp_mult = 1.20
		pack_atk_mult = 1.10
	elif pack_tier == Enemy.PACK_RARE:
		pack_hp_mult = 1.60
		pack_atk_mult = 1.30
	e.max_hp = int(round(float(def.hp) * floor_mult * tier_mult * champ_mult * pack_hp_mult))
	e.atk = int(round(float(def.atk) * floor_mult * tier_mult * champ_mult * pack_atk_mult))
	e.defense = int(round(float(def.def) * floor_mult * tier_mult * (1.2 if is_champion else 1.0)))
	e.hp = e.max_hp
	e.move_speed = float(def.speed) * 4.0
	var tex: Texture2D = load(ENEMY_TILE_DIR + def.tile)
	if tex:
		e.set_texture(tex)
		# Data-driven visual scale. Champion variants stack on top of base.
		# Per-spawn jitter (0.85..1.15) keeps a cluster of identical mob
		# IDs from looking like clones — only applied to rank-and-file
		# (non-boss / non-miniboss / non-champion) so important silhouettes
		# stay recognizable.
		var base_scale: float = float(def.get("visual_scale", 1.0))
		var anchor: String = String(def.get("visual_anchor", "centre"))
		var vz: int = int(def.get("visual_z", 1 if base_scale > 1.0 else 0))
		var champ_visual: float = 1.25 if is_champion else 1.0
		var jitter: float = 1.0
		if not bool(def.boss) and not is_champion:
			jitter = rng.randf_range(0.85, 1.15)
		e.apply_visual_scale(base_scale * champ_visual * jitter, anchor, vz)
		if is_champion and e.rig:
			e.rig.modulate = Color(1.0, 0.85, 1.3)
			e.fx = SpriteFX.new(e.rig, e.sprite)
			LightSpec.attach(e, "sigil")
		# Per-creature emitter: fire/ice creatures emit their own light.
		var enemy_light_spec: String = String(def.get("light_spec", ""))
		if enemy_light_spec != "":
			LightSpec.attach(e, enemy_light_spec)
	# Apply pack mods after stat init so they multiply / add to the
	# champion-scaled values.
	for mod in picked_mods:
		e.pack_mods.append(String(mod.get("id", "")))
		_apply_pack_mod(e, mod)
	# Pack visuals (tint + aura) — last so they sit on top of any
	# champion/light effects already applied.
	e.apply_pack_visuals()
	# Persistent outline for magic/rare. Threat-aura still sets `tier`
	# for thickness, but pack_color overrides the color so the outline
	# reads as "magic" or "rare" rather than threat-relative.
	e.apply_persistent_outline()
	if pack_tier != Enemy.PACK_NORMAL and GrindLog._enabled:
		var tier_label: String = "rare" if pack_tier == Enemy.PACK_RARE else "magic"
		GrindLog.log_line("[pack] tier=%s id=%s mods=%s" % [tier_label, id, str(e.pack_mods)])
	e.place_at(at_cell)
	# Stagger initial repath so a freshly-spawned horde doesn't all repath
	# on the same frame. Spread across the full REPATH_INTERVAL.
	e.repath_timer = rng.randf_range(0.0, Enemy.REPATH_INTERVAL)
	e.died.connect(_on_enemy_died)
	enemies.append(e)

func _on_enemy_died(actor: Actor) -> void:
	var e := actor as Enemy
	if e == null or not is_instance_valid(e):
		return
	floor_kills += 1
	# Combat effect: biome-themed kill flash. Forge → fire, Glacier → ice,
	# others → blood splat.
	var biome_id: String = String(current_biome.get("id", ""))
	var kill_pos: Vector2 = e.position + Vector2(C.TILE_SIZE * 0.5, C.TILE_SIZE * 0.5)
	if biome_id == "forge" or biome_id == "pandemonium":
		Effects.fire_flash(actor_layer, kill_pos)
	elif biome_id == "glacier":
		Effects.ice_shatter(actor_layer, kill_pos)
	else:
		Effects.blood_splat(actor_layer, kill_pos)
	bot.gain_xp(e.xp_reward)
	var gold_mult: float = RunModifiers.sum_effect(active_modifiers, "gold_mult", 1.0)
	var gold_drop: int = int(round(float(rng.randi_range(1, 5) + current_floor) * gold_mult))
	bot.gold += gold_drop
	kills[e.enemy_id] = kills.get(e.enemy_id, 0) + 1
	loot_log.append("%s slain (+%d gold, +%d xp)" % [e.display_name, gold_drop, e.xp_reward])
	if e.is_boss:
		_log("Slew %s. (+%d gold, +%d xp)" % [e.display_name, gold_drop, e.xp_reward])
		# Branch boss dead → notify main.gd so the player unlocks the next
		# tier's branches. Branch id comes from current biome (boss floors
		# always sit on the chosen branch's biome).
		boss_killed.emit(String(current_biome.get("id", "")))
	elif e.is_miniboss:
		_log("Vanquished %s! (+%d gold, +%d xp)" % [e.display_name, gold_drop, e.xp_reward])
	else:
		_log("Slew a %s." % e.display_name)
	_maybe_drop_item(e)
	enemies.erase(e)
	# Enemy may have been a light emitter (fire dragon, ice giant, etc) — its
	# light is gone, fog needs to repaint without it.
	invalidate_fog()
	# A boss-flagged enemy only ends the run if we're actually on the
	# final-boss floor. Vault-stamped bosses on earlier floors are just
	# strong elites — they shouldn't auto-win the run.
	if e.is_boss and current_floor >= _boss_floor:
		_end_run(true)
		return

func _maybe_drop_item(e: Enemy) -> void:
	# Drop chance scales by tier — pack-clustered spawns mean 100+
	# mobs per floor. Normal mobs at the old 15% drop rate would
	# flood the inventory. Magic/rare leaders carry the loot pressure
	# instead, so the typical floor stays at ~10-15 drops while
	# kills 10×.
	# `fortune` flavor: +20% drop chance per source on the bot's gear.
	var fortune_mult: float = 1.0
	if is_instance_valid(bot):
		for t in bot.combat_defense_tags():
			if t == "fortune":
				fortune_mult += 0.20
	var roll: float = rng.randf() / fortune_mult
	var threshold: float = 0.05
	if e.pack_tier == Enemy.PACK_MAGIC:
		threshold = 0.30
	elif e.pack_tier == Enemy.PACK_RARE:
		threshold = 1.0
	if e.is_miniboss:
		threshold = 1.0
	elif e.is_boss:
		threshold = 1.0
	if roll > threshold:
		return
	# Drop count: rare leaders + bosses drop multiple items.
	var drop_count: int = 1
	if e.pack_tier == Enemy.PACK_RARE:
		drop_count = 2
	if e.is_boss:
		drop_count = int(round(RunModifiers.sum_effect(active_modifiers, "boss_loot_mult", 1.0)))
		drop_count = maxi(drop_count, 1)
	for _i in drop_count:
		var rarity: String = _roll_rarity(e.is_boss or e.is_miniboss or e.pack_tier == Enemy.PACK_RARE)
		var picked: String = _pick_loot_id(rarity)
		if picked == "":
			continue
		var instance: Dictionary = _create_item_instance(picked)
		_spawn_loot_drop(instance, e.cell)

func _create_item_instance(base_id: String) -> Dictionary:
	var base: Dictionary = items_db.get(base_id, {})
	var affixes: Array = AffixSystem.roll_affixes_for(base, rng)
	var inst: Dictionary = {
		"base_id": base_id,
		"instance_id": _gen_instance_id(),
		"affixes": affixes,
	}
	# Meta-rarity roll (D3 Ancient / Primal pattern). Independent of
	# the rarity tier — any drop, even a common, can roll "ancient"
	# (1%) for +20% stats or "primal" (0.1%) for +50% stats. Visual
	# tint changes (gold for ancient, red for primal) plus a name
	# prefix. This is the "screenshot brag" lever the user asked for.
	var meta_roll: float = rng.randf()
	if meta_roll < 0.001:
		inst["meta_rarity"] = "primal"
	elif meta_roll < 0.011:  # 1% (after the 0.1% primal slice)
		inst["meta_rarity"] = "ancient"
	# Per-instance recolor roll (~30% of drops get a hue shift; tiny
	# fractions get shimmer/inverted/prismatic). Each hue carries a
	# small stat lean — red leans strength, blue leans regen, etc.
	# Even non-recolored items keep `tint` absent so the runtime
	# can short-circuit the shader for free.
	var tint_roll: float = rng.randf()
	if tint_roll < 0.005:
		# Prismatic — animated rainbow. ~0.5%.
		inst["tint"] = {
			"hue": rng.randf_range(0.0, 360.0),
			"sat": 1.0,
			"mode": "prismatic",
			"lean": _hue_to_stat_lean(rng.randf_range(0.0, 360.0)),
			"lean_pct": 15.0,
		}
	elif tint_roll < 0.015:
		# Inverted — palette flipped. ~1%.
		var h: float = rng.randf_range(0.0, 360.0)
		inst["tint"] = {
			"hue": h,
			"sat": rng.randf_range(0.6, 1.2),
			"mode": "inverted",
			"lean": _hue_to_stat_lean(h),
			"lean_pct": 12.0,
		}
	elif tint_roll < 0.045:
		# Shimmer — animated highlight sweep. ~3%.
		var h2: float = rng.randf_range(0.0, 360.0)
		inst["tint"] = {
			"hue": h2,
			"sat": rng.randf_range(0.9, 1.3),
			"mode": "shimmer",
			"lean": _hue_to_stat_lean(h2),
			"lean_pct": 10.0,
		}
	elif tint_roll < 0.30:
		# Plain hue shift. ~25%.
		var h3: float = rng.randf_range(0.0, 360.0)
		inst["tint"] = {
			"hue": h3,
			"sat": rng.randf_range(0.7, 1.2),
			"mode": "normal",
			"lean": _hue_to_stat_lean(h3),
			"lean_pct": 7.0,
		}
	# Per-instance "enchant" flavor roll. Static `flavor_tags` on the
	# base item still apply (vampires_tooth is always vampiric); this
	# layer adds an optional ADDITIONAL flavor on top, e.g. "Iron
	# Dagger" rolling fire 5% of the time. Distinct from rarity rolls
	# so it's a separate axis of surprise on drops.
	# items.json controls:
	#   enchant_chance: 0..1 (default 0.05 if pool present, else 0)
	#   enchant_pool:   array of flavor ids that can roll; falls back
	#                   to UITheme's full FLAVOR_COLORS list when omitted
	var enchant_chance: float = float(base.get("enchant_chance", 0.0))
	if enchant_chance > 0.0 and rng.randf() < enchant_chance:
		var pool: Array = base.get("enchant_pool", [])
		if pool.is_empty():
			pool = UITheme.FLAVOR_COLORS.keys()
		# Don't roll an enchant that duplicates a static tag — pointless
		# and visually noisy (double trails, double glow).
		var existing: Array = base.get("flavor_tags", [])
		var candidates: Array = []
		for p in pool:
			if not (p in existing):
				candidates.append(p)
		if not candidates.is_empty():
			inst["enchant"] = String(candidates[rng.randi_range(0, candidates.size() - 1)])
	if String(base.get("rarity", "")) == "legendary":
		var slot: String = String(base.get("slot", "armor"))
		var artefact: String = ArtefactPool.pick_for_slot(slot, rng)
		if artefact != "":
			inst["tile_override"] = "artefacts/" + artefact
	return inst

func _gen_instance_id() -> String:
	return "%d_%d" % [Time.get_unix_time_from_system(), rng.randi()]

# Map a hue (0–360°) to which stat the recolored item leans toward.
# Mirrors the color-wheel intuition: red→strength, green→haste, etc.
# Used by Bot.recompute_stats to apply a per-instance percentage
# bonus on top of the base item stats.
func _hue_to_stat_lean(hue: float) -> String:
	hue = fmod(hue, 360.0)
	if hue < 0.0:
		hue += 360.0
	if hue < 30.0:    return "atk"        # red
	if hue < 60.0:    return "hp"         # orange — stamina-leaning
	if hue < 100.0:   return "atk_speed"  # yellow → haste
	if hue < 160.0:   return "haste"      # green
	if hue < 200.0:   return "def"        # cyan → agility
	if hue < 260.0:   return "regen"      # blue
	if hue < 300.0:   return "crit"       # purple
	return "atk"                          # magenta — back to red family

func _spawn_loot_drop(instance: Dictionary, at_cell: Vector2i) -> void:
	var base_id: String = String(instance.get("base_id", ""))
	if not items_db.has(base_id):
		return
	var drop := LootDrop.new()
	drop.setup_instance(instance, items_db[base_id], at_cell)
	actor_layer.add_child(drop)
	loot_drops.append(drop)
	interactables.append(drop)

func _spawn_chest(at_cell: Vector2i, drops: int = 2, bias: int = 0) -> void:
	var chest := Chest.new()
	chest.setup(at_cell, drops, bias)
	actor_layer.add_child(chest)
	interactables.append(chest)
	chest.opened.connect(_on_chest_opened)

func _spawn_fountain(at_cell: Vector2i, kind: String) -> void:
	var fountain := Fountain.new()
	fountain.setup(at_cell, kind)
	actor_layer.add_child(fountain)
	interactables.append(fountain)
	fountain.drank.connect(_on_fountain_drank)

func _on_fountain_drank(_fountain: Fountain, heal: int, kind: String) -> void:
	floor_fountains_used += 1
	_log("Drank from a %s fountain (+%d HP)." % [kind, heal])

func _apply_vault_results(results: Dictionary) -> void:
	if results.is_empty():
		return
	var fountains: Array = results.get("fountains", [])
	for entry in fountains:
		if typeof(entry) == TYPE_DICTIONARY:
			_spawn_fountain(entry.cell, String(entry.get("kind", "blue")))
		else:
			_spawn_fountain(entry, "blue")
	var chest_marks: Array = results.get("chest_marks", [])
	for cell in chest_marks:
		_spawn_chest(cell, rng.randi_range(2, 3), 1)
	var loot_marks: Array = results.get("loot_marks", [])
	for entry in loot_marks:
		var cell: Vector2i = entry.cell if typeof(entry) == TYPE_DICTIONARY else entry
		var rarity: String = _roll_rarity(false)
		var picked: String = _pick_loot_id(rarity)
		if picked == "":
			continue
		var inst: Dictionary = _create_item_instance(picked)
		_spawn_loot_drop(inst, cell)
	var statues: Array = results.get("statues", [])
	for cell in statues:
		_place_statue(cell)
	var altar_marks: Array = results.get("altar_marks", [])
	for entry in altar_marks:
		if typeof(entry) == TYPE_DICTIONARY:
			_spawn_altar(entry.cell)
		else:
			_spawn_altar(entry)
	vault_spawn_overrides = results.get("spawn_overrides", {})
	var placed: Array = results.get("placed_vaults", [])
	if not placed.is_empty():
		_log("Notable: %s." % ", ".join(placed))

func _place_statue(cell: Vector2i) -> void:
	var tex: Texture2D = load("res://assets/tiles/features/statue_granite.png")
	if tex == null:
		return
	var s := Sprite2D.new()
	s.texture = tex
	s.centered = false
	s.position = Vector2(cell.x * C.TILE_SIZE, cell.y * C.TILE_SIZE)
	s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	map_layer.add_child(s)
	vault_decor_sprites.append(s)
	var occ := LightOccluder2D.new()
	occ.occluder = MapRenderer._occluder_poly()
	occ.position = Vector2(cell.x * C.TILE_SIZE, cell.y * C.TILE_SIZE)
	map_layer.add_child(occ)
	vault_decor_sprites.append(occ)
	if pathing and pathing.astar:
		pathing.astar.set_point_solid(cell, true)

func _spawn_altar(at_cell: Vector2i) -> void:
	var altar := Altar.new()
	altar.setup(at_cell)
	actor_layer.add_child(altar)
	interactables.append(altar)
	altar.blessed.connect(_on_altar_blessed)

func _on_altar_blessed(altar: Altar, blessing: Dictionary) -> void:
	floor_altars_used += 1
	var bname: String = String(blessing.get("name", "blessing"))
	var bdesc: String = String(blessing.get("desc", ""))
	_log("Received %s — %s" % [bname, bdesc], "loot")
	# Magic shimmer at altar position for divine-grant flair.
	if is_instance_valid(altar):
		var pos: Vector2 = altar.position + Vector2(C.TILE_SIZE * 0.5, C.TILE_SIZE * 0.5)
		Effects.magic_shimmer(actor_layer, pos)
	# ENCH: blessed overlay persists for the rest of the run (duration<=0).
	# clear_blessings() at run-start removes it implicitly via Bot reset.
	if is_instance_valid(bot) and bot.is_alive:
		bot.add_status("blessed", 0.0)

func _spawn_portal(at_cell: Vector2i) -> void:
	var portal := Portal.new()
	portal.setup(at_cell, Portal.random_kind(rng))
	actor_layer.add_child(portal)
	interactables.append(portal)
	portal.entered.connect(_on_portal_entered)

func _on_portal_entered(_portal: Portal, kind: String, biome_id: String, loot_bias: int) -> void:
	var override: Dictionary = BiomeData.get_biome(biome_id)
	if override.is_empty():
		return
	var def: Dictionary = Portal.PORTAL_KINDS.get(kind, {})
	var portal_name: String = String(def.get("name", "Portal"))
	_log("Stepped through a %s portal." % portal_name)
	GrindLog.log_line("[portal] entered=%s -> biome=%s bias=%d on_floor=%d" % [kind, biome_id, loot_bias, current_floor])
	floor_portals_entered += 1
	portal_active = true
	portal_kind = kind
	portal_biome_override = override
	portal_loot_bias = loot_bias
	# Rebuild the floor in-place using the portal biome. Floor counter does
	# not advance — descending the portal's stairs continues the run normally.
	_build_floor()

# Source-floor tier — the home branch's tier, NOT the portal biome's.
# A bazaar portal (vaults, T4) stamped on a Floor 2 dungeon (T1) returns
# T1 here, so loot rolls don't escape the home branch's progression.
# Used as the rarity ceiling and the drop_weights index.
func _source_tier() -> int:
	if branch_id != "" and BiomeData.tier_for_biome(branch_id) > 0:
		return clampi(BiomeData.tier_for_biome(branch_id), 1, 5)
	return clampi(int(current_biome.get("tier", 1)), 1, 5)

# Cap a rolled rarity by source-floor tier. T1: max uncommon, T2: rare,
# T3: epic, T4+: legendary. Stops a Floor-2 portal from showering the
# bot with T5-grade legendaries that the home branch hasn't earned.
const _TIER_RARITY_CAP := {
	1: "uncommon",
	2: "rare",
	3: "epic",
	4: "legendary",
	5: "legendary",
}
const _RARITY_RANK := {
	"common": 0, "uncommon": 1, "rare": 2, "epic": 3, "legendary": 4,
}
func _clamp_rarity_to_tier(rarity: String, tier: int = -1) -> String:
	var t: int = tier if tier > 0 else _source_tier()
	var cap: String = String(_TIER_RARITY_CAP.get(t, "legendary"))
	if int(_RARITY_RANK.get(rarity, 0)) <= int(_RARITY_RANK.get(cap, 4)):
		return rarity
	return cap

# Pick an item id of the given rarity, weighted by drop_weights[source_tier-1].
# Items with no drop_weights field still roll (legacy fallback, weight 1).
# Items already dropped this run AND flagged unique are excluded.
# Returns "" if no eligible item exists.
func _pick_loot_id(rarity: String) -> String:
	var tier: int = _source_tier()
	var idx: int = tier - 1
	var ids: Array[String] = []
	var weights: Array[float] = []
	var total: float = 0.0
	for id in items_db.keys():
		var item: Dictionary = items_db[id]
		if String(item.get("rarity", "")) != rarity:
			continue
		if bool(item.get("unique", false)) and run_dropped_uniques.has(id):
			continue
		var dw: Array = item.get("drop_weights", [])
		var w: float
		if dw.size() == 5:
			w = float(dw[idx])
			if w <= 0.0:
				continue
		else:
			# Legacy item without drop_weights — keep it eligible at all tiers
			# until manifests cover its slot. Equal weight 1.
			w = 1.0
		ids.append(id)
		weights.append(w)
		total += w
	if ids.is_empty():
		return ""
	var roll: float = rng.randf() * total
	var acc: float = 0.0
	for i in ids.size():
		acc += weights[i]
		if roll <= acc:
			var picked: String = ids[i]
			var item: Dictionary = items_db[picked]
			if bool(item.get("unique", false)):
				run_dropped_uniques.append(picked)
			return picked
	return ids[ids.size() - 1]

func _roll_rarity(is_boss: bool) -> String:
	# Tier ceiling: source branch tier (NOT portal-overridden biome tier),
	# applied last so every other bonus stacks first then gets clamped.
	# A T1 dungeon boss rolls legendary 50% of the time then drops to
	# uncommon — keeps boss kills meaningful without trivializing T5
	# uniques.
	var src_tier: int = _source_tier()
	if is_boss:
		var boss_roll: float = rng.randf()
		var rarity_b: String
		if boss_roll < 0.5: rarity_b = "legendary"
		elif boss_roll < 0.85: rarity_b = "epic"
		else: rarity_b = "rare"
		return _clamp_rarity_to_tier(rarity_b, src_tier)
	var floor_bonus: float = float(current_floor - 1) * 0.05
	var blessing_bonus: float = bot.loot_rarity_bonus / 100.0 if is_instance_valid(bot) else 0.0
	# Tier baseline: tier 1 = 0, tier 5 = +0.20. Higher-tier branches
	# always lean toward better loot even without modifiers. Uses the
	# source branch tier so a low-tier portal doesn't double-dip on the
	# portal biome's tier here.
	var tier_bonus: float = float(src_tier - 1) * 0.05
	# Modifier-driven rarity bias (Treasure Hoard, Glittering).
	var mod_bonus: float = RunModifiers.sum_effect(active_modifiers, "rarity_bonus", 0.0)
	var r: float = rng.randf() - floor_bonus - blessing_bonus - tier_bonus - mod_bonus
	var rarity: String
	if r < 0.02: rarity = "legendary"
	elif r < 0.10: rarity = "epic"
	elif r < 0.25: rarity = "rare"
	elif r < 0.55: rarity = "uncommon"
	else: rarity = "common"
	return _clamp_rarity_to_tier(rarity, src_tier)

var _turn_accum: float = 0.0

func _process(delta: float) -> void:
	if not _floor_ready or not is_instance_valid(bot) or not bot.is_alive:
		return
	PerfMon.begin(PerfMon.TAG_FRAME)
	PerfMon.begin(PerfMon.TAG_AI)
	_tick_bot(delta)
	_tick_enemies(delta)
	PerfMon.end(PerfMon.TAG_AI)
	_center_camera_on_bot()
	_turn_accum += delta
	if _turn_accum >= 0.25:
		_turn_accum -= 0.25
		run_turn += 1
	_tick_equip_cooldowns(delta)
	SpellSystem.process_tick(bot, self, delta, items_db)
	_tick_wave_spawns(delta)
	_tick_burst_events(delta)
	_update_biome_hud()
	PerfMon.end(PerfMon.TAG_FRAME)
	if PerfMon.tick_frame():
		var suffix: String = PerfMon.format_log_suffix()
		if suffix != "":
			GrindLog.log_line("[perf] " + suffix)

const AGGRO_ENGAGE_RANGE := 5

var _lava_tick_accum: float = 0.0

# Wave + burst spawn accumulators for the VS-style density layer.
# wave: small periodic mob trickle from off-bot-POV cells. burst:
# rare large pack of MAGIC-tier mobs from one direction, telegraphed
# briefly. Both gate on `_floor_ready` so they can't fire mid-build.
# Combat-pivot 2026-06-04.
var _wave_accum: float = 0.0
var _wave_interval: float = 8.0  # seconds; jittered between casts
var _burst_accum: float = 0.0
var _burst_interval: float = 35.0
const _WAVE_MIN_MOBS := 4
const _WAVE_MAX_MOBS := 8
const _BURST_MIN_MOBS := 12
const _BURST_MAX_MOBS := 18
const _DENSITY_HARD_CAP := 400  # never exceed this active mob count

# Bot AI tuning constants. AGGRO_DISTANCE caps how far the bot will actively
# pursue an enemy. Beyond this, the bot ignores them and keeps exploring;
# adjacency check at the top of the tick still catches drive-by attacks.
const AGGRO_DISTANCE := 8
const RETREAT_HP_PCT := 0.30

func _tick_bot(delta: float) -> void:
	_mark_room_visited_at(bot.cell)
	_refresh_fog()
	_check_stuck(delta)
	bot.tick_statuses(delta)
	# Continuous status drivers: read terrain under bot and refresh
	# matching ENCH overlays. The actual mechanical effect is unchanged
	# (lava damages, water slows); add_status just makes it visible.
	if bot.is_alive and bot.cell.y >= 0 and bot.cell.y < grid.size() \
			and bot.cell.x >= 0 and bot.cell.x < grid[0].size():
		var here: int = grid[bot.cell.y][bot.cell.x]
		if here == C.T_LAVA:
			bot.add_status("burning", 0.7)  # short renewal so it fades when stepping off
		elif here == C.T_WATER:
			bot.add_status("slowed", 0.5)
	# Wounded overlay: bot below 30% HP. State-based; add persistent
	# and remove when healed back above the threshold.
	var is_wounded: bool = bot.is_alive and bot.hp > 0 and float(bot.hp) / float(max(1, bot.max_hp)) < 0.3
	if is_wounded and not bot.has_status("wounded"):
		bot.add_status("wounded", 0.0)
	elif not is_wounded and bot.has_status("wounded"):
		bot.remove_status("wounded")
	# Regen overlay: visible while bot has any regen-per-sec from gear
	# or blessings. State-based, not timed — add persistent (0) and
	# remove when the condition flips. Avoids buff-bar timer flicker.
	if bot.is_alive and bot.hp_regen_per_sec > 0.1:
		if not bot.has_status("regen"):
			bot.add_status("regen", 0.0)
	elif bot.has_status("regen"):
		bot.remove_status("regen")
	# Lava damage: if bot is standing on a lava cell, deal 5% max_hp
	# every 0.5 seconds. Tick accumulator avoids per-frame damage spam.
	_lava_tick_accum += delta
	if _lava_tick_accum >= 0.5:
		_lava_tick_accum = 0.0
		if bot.cell.y >= 0 and bot.cell.y < grid.size() \
				and bot.cell.x >= 0 and bot.cell.x < grid[0].size() \
				and grid[bot.cell.y][bot.cell.x] == C.T_LAVA \
				and bot.is_alive:
			var dmg: int = max(1, int(round(bot.max_hp * 0.05)))
			bot.take_damage(dmg)
			# Visual feedback for the burn.
			Effects.fire_flash(actor_layer, bot.position + Vector2(C.TILE_SIZE * 0.5, C.TILE_SIZE * 0.5))
			# Death-by-lava — checked here because no enemy is mid-attack to
			# pick it up downstream. Same retreat-or-end fork as combat death.
			if not bot.is_alive:
				_log("Bot succumbs to lava on floor %d." % current_floor)
				if _try_death_retreat("lava on f%d" % current_floor):
					return
				_end_run(false)
				return
	# Standing on stairs and no enemies nearby? Descend immediately.
	# Showcase mode pins the floor — never descend, even if the patrol
	# happens to cross the stairs cell (it doesn't, by design, but guard
	# against accidental rebuilds).
	if bot.cell == stairs_cell and _nearest_enemy() == null and not DebugJump.showcase:
		_descend()
		return
	if fog_overlay:
		PerfMon.begin(PerfMon.TAG_LIGHTS)
		# Bot world position for shader ray-march LoS — sampled every frame
		# so the lit cone tracks bot motion smoothly between cell boundaries.
		# Centred on the bot sprite (bot.position is its top-left tile origin).
		var bot_world: Vector2 = Vector2(INF, INF)
		var bot_radius_px: float = 0.0
		if is_instance_valid(bot):
			bot_world = bot.position + Vector2(C.TILE_SIZE * 0.5, C.TILE_SIZE * 0.5)
			bot_radius_px = float(FogSystem.BOT_LOS_RADIUS) * float(C.TILE_SIZE)
		fog_overlay.update_lights(_gather_lights(), delta, bot_world, bot_radius_px)
		PerfMon.end(PerfMon.TAG_LIGHTS)
	if bot_light == null and is_instance_valid(bot):
		bot_light = PointLight2D.new()
		bot_light.texture = _make_radial_light(128)
		bot_light.texture_scale = 4.5
		bot_light.offset = Vector2(C.TILE_SIZE * 0.5, C.TILE_SIZE * 0.5)
		bot_light.energy = 0.55
		bot_light.color = Color(1.0, 0.95, 0.8)
		# Limit z range so the light doesn't shine on the bot's own sprite
		# layers (z=1 body, z=2 weapon, z=5 bot itself). Light only affects
		# the world tiles at z=0.
		bot_light.range_z_min = -100
		bot_light.range_z_max = 0
		bot_light.shadow_enabled = true
		bot_light.shadow_filter = Light2D.SHADOW_FILTER_PCF5
		bot_light.shadow_filter_smooth = 1.5
		bot.add_child(bot_light)
		var t := bot_light.create_tween().set_loops()
		t.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		t.tween_property(bot_light, "energy", 0.45, 0.7)
		t.tween_property(bot_light, "energy", 0.65, 0.7)

	if bot_interacting:
		_tick_interaction(delta)
		return

	# Showcase mode: bot patrols a fixed path, ignoring enemies and
	# interactables. The bot's light reveals each station as it passes.
	# When the current path segment finishes, advance to the next station.
	if DebugJump.showcase:
		_showcase_tick_patrol(delta)
		return

	for inter in interactables:
		if is_instance_valid(inter) and inter.can_interact() and not inter.should_skip(bot) and inter.cell == bot.cell:
			_begin_interaction(inter)
			return

	# Tick-level state probe is gated to stall-recovery only (see _check_stuck).

	# If ANY enemy is adjacent, attack it. Don't switch targets while in melee.
	var adjacent_enemy: Enemy = null
	for e in enemies:
		if not is_instance_valid(e) or not e.is_alive:
			continue
		if _chebyshev(bot.cell, e.cell) <= 1:
			adjacent_enemy = e
			break
	if adjacent_enemy != null:
		bot.path = PackedVector2Array()
		bot.attempt_attack(adjacent_enemy, delta)
		bot_target_cell = adjacent_enemy.cell
		bot_target_kind = "enemy"
		return

	var nearby_enemy: Enemy = _nearest_enemy()

	# Sticky target: keep walking the existing path until it's consumed. Only
	# re-pick a target when path is fully done OR target is invalid.
	var has_path: bool = bot.path.size() > 0 and bot.path_index < bot.path.size()
	if has_path:
		# Check target is still valid; if not, drop path and re-pick.
		var still_valid: bool = false
		match bot_target_kind:
			"enemy":
				for e in enemies:
					if is_instance_valid(e) and e.is_alive and _chebyshev(e.cell, bot_target_cell) <= 2:
						bot_target_cell = e.cell
						still_valid = true
						break
			"interactable":
				for inter in interactables:
					if is_instance_valid(inter) and inter.cell == bot_target_cell and inter.can_interact() and not inter.should_skip(bot):
						still_valid = true
						break
			"room", "stairs":
				still_valid = true
		if still_valid:
			# Mark rooms as we pass through them (early credit).
			if bot_target_kind == "room":
				_mark_room_visited_at(bot.cell)
			bot.step_movement(delta)
			return
		# Target invalid — drop path so we re-pick.
		bot.path = PackedVector2Array()
		bot_target_cell = Vector2i(-1, -1)
		bot_target_kind = ""

	# Path consumed. Did we reach our target?
	if bot_target_kind == "stairs" and bot.cell == stairs_cell:
		_descend()
		return
	if bot_target_kind == "room":
		_mark_room_visited_at(bot.cell)

	bot_target_cell = Vector2i(-1, -1)
	bot_target_kind = ""

	# Need a new target.
	bot_target_cell = Vector2i(-1, -1)
	bot_target_kind = ""

	# Low-HP retreat: head to nearest fountain if we have one and HP is low.
	# Lets the bot survive a bad streak instead of fighting to 1 HP.
	var hp_low: bool = is_instance_valid(bot) and bot.max_hp > 0 \
			and float(bot.hp) / float(bot.max_hp) < RETREAT_HP_PCT
	if hp_low:
		var fountain: Interactable = _nearest_fountain_unconsumed()
		if fountain != null:
			var p_f: PackedVector2Array = pathing.path(bot.cell, fountain.cell)
			if p_f.size() > 1:
				bot.set_path(p_f.slice(1))
				bot_target_cell = fountain.cell
				bot_target_kind = "interactable"
				bot.step_movement(delta)
				return

	# Current-room loot priority: if the bot is inside a BSP room, finish
	# what's in this room (chests, altars, loot) before chasing distant
	# enemies. Makes bot feel like it explores rooms rather than beelining.
	var current_room_idx: int = _room_containing(bot.cell)
	if current_room_idx >= 0:
		var inter_in_room: Interactable = _nearest_interactable_in_room(rooms[current_room_idx])
		if inter_in_room != null:
			var p_in_room: PackedVector2Array = pathing.path(bot.cell, inter_in_room.cell)
			if p_in_room.size() > 1:
				bot.set_path(p_in_room.slice(1))
				bot_target_cell = inter_in_room.cell
				bot_target_kind = "interactable"
				bot.step_movement(delta)
				return

	# Pursue nearby enemy only within aggro range. Distant ones get ignored
	# so we don't beeline 30 cells across the map.
	# Vision flavor tag adds to aggro distance so the bot engages from
	# further away when wearing such gear.
	var aggro_dist: int = AGGRO_DISTANCE + bot.aggro_bonus
	if nearby_enemy != null and _chebyshev(bot.cell, nearby_enemy.cell) <= aggro_dist:
		var p_enemy: PackedVector2Array = pathing.path(bot.cell, nearby_enemy.cell)
		if p_enemy.size() > 1:
			bot.set_path(p_enemy.slice(1))
			bot_target_cell = nearby_enemy.cell
			bot_target_kind = "enemy"
			bot.step_movement(delta)
			return

	var nearest_inter: Interactable = _nearest_interactable()
	if nearest_inter != null:
		var p_int: PackedVector2Array = pathing.path(bot.cell, nearest_inter.cell)
		if p_int.size() > 1:
			bot.set_path(p_int.slice(1))
			bot_target_cell = nearest_inter.cell
			bot_target_kind = "interactable"
			bot.step_movement(delta)
			return

	# Explore: head to nearest unvisited room before descending. The sticky-target
	# system keeps us locked to one room until we arrive — no oscillation.
	var room_target: Vector2i = _nearest_unvisited_room_center()
	if room_target.x >= 0:
		var p_room: PackedVector2Array = pathing.path(bot.cell, room_target)
		if p_room.size() > 1:
			bot.set_path(p_room.slice(1))
			bot_target_cell = room_target
			bot_target_kind = "room"
			bot.step_movement(delta)
			return

	# Nothing left to explore — head to stairs.
	if bot.cell == stairs_cell:
		_descend()
		return
	var p_stairs: PackedVector2Array = pathing.path(bot.cell, stairs_cell)
	if p_stairs.size() > 1:
		bot.set_path(p_stairs.slice(1))
		bot_target_cell = stairs_cell
		bot_target_kind = "stairs"
		bot.step_movement(delta)
		return

	# Hard fallback: pathing failed for every priority. Walk the BFS distance
	# gradient toward stairs. Floor was pre-validated as connected, so a
	# downhill neighbor exists from any reachable cell.
	if dist_to_stairs.size() > 0 and bot.cell.y >= 0 and bot.cell.y < dist_to_stairs.size() and bot.cell.x >= 0 and bot.cell.x < dist_to_stairs[0].size():
		var current_d: int = dist_to_stairs[bot.cell.y][bot.cell.x]
		var best_neighbor := Vector2i(-1, -1)
		var best_d: int = current_d
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = bot.cell + d
			if n.x < 0 or n.y < 0 or n.y >= dist_to_stairs.size() or n.x >= dist_to_stairs[0].size():
				continue
			var nd: int = dist_to_stairs[n.y][n.x]
			if nd < 0:
				continue
			if nd < best_d:
				best_d = nd
				best_neighbor = n
		if best_neighbor.x >= 0:
			bot.set_path(PackedVector2Array([Vector2(best_neighbor.x * C.TILE_SIZE, best_neighbor.y * C.TILE_SIZE)]))
			bot_target_cell = best_neighbor
			bot_target_kind = "stairs"

	bot.step_movement(delta)

var _last_bot_cell: Vector2i = Vector2i(-99, -99)
# Seconds (not frames) — frame-based threshold broke on 120Hz ProMotion
# displays where 360 frames is 3s instead of the intended 6s. We measure
# real wall time so the watchdog behaves the same on every refresh rate.
var _stuck_seconds: float = 0.0
const STALL_WARN_SECONDS: float = 6.0
const STALL_SOFT_RECOVERY_SECONDS: float = 10.0
const STALL_HARD_RECOVERY_SECONDS: float = 18.0
const STALL_TELEPORT_SECONDS: float = 30.0
var _stall_snapshot_taken: bool = false
var _stall_warned: bool = false
var _stall_soft_attempted: bool = false
var _stall_hard_attempted: bool = false

func _check_stuck(delta: float) -> void:
	# Showcase mode pins the floor on purpose; the bot patrols a fixed loop
	# and "cell unchanged" is the steady state — never trigger here.
	if DebugJump.showcase:
		return
	if not is_instance_valid(bot) or not bot.is_alive:
		_reset_stuck_timer()
		return
	# Cell changed → real progress, reset everything.
	if bot.cell != _last_bot_cell:
		_last_bot_cell = bot.cell
		_reset_stuck_timer()
		return
	# Cell unchanged but the bot is legitimately busy — don't accumulate.
	# These cover the bulk of "looks idle" frames in normal play:
	#   * bot_interacting: kneeling at a chest/altar/fountain/loot/portal
	#   * enemy in combat range (Chebyshev <= AGGRO_ENGAGE_RANGE): swinging
	#     in melee OR repositioning vs. a ranged/knockback boss who isn't
	#     adjacent every frame. Generous radius is intentional — the cost
	#     of failing to teleport an actually-stuck bot for an extra few
	#     seconds is much smaller than the cost of teleporting mid-boss.
	#   * pending path: actively traversing between cells (mid-tween)
	if bot_interacting or bot.path.size() > 0 or _has_combat_engaged_enemy():
		_reset_stuck_timer()
		return
	# Genuinely idle — accumulate.
	_stuck_seconds += delta
	if not _stall_warned and _stuck_seconds >= STALL_WARN_SECONDS:
		_stall_warned = true
		floor_stalls += 1
		GrindLog.log_line("[stall] f=%d secs=%.1f bot=%s target=%s kind=%s stairs=%s enemies=%d interactables=%d unvisited_rooms=%d" % [
			current_floor, _stuck_seconds, str(bot.cell), str(bot_target_cell), bot_target_kind,
			str(stairs_cell), enemies.size(), interactables.size(),
			_count_unvisited_rooms(),
		])
	# Soft recovery: ditch whatever the bot was trying to do and force a
	# fresh path to stairs. Often the bot's higher-level planner is wedged
	# on an unreachable interactable while the stairs are perfectly walkable.
	if not _stall_soft_attempted and _stuck_seconds >= STALL_SOFT_RECOVERY_SECONDS:
		_stall_soft_attempted = true
		GrindLog.log_line("[stall] SOFT-RECOVERY f=%d repath bot=%s -> stairs=%s" % [
			current_floor, str(bot.cell), str(stairs_cell),
		])
		_force_repath_to_stairs()
		return
	# Hard recovery: clear all path/target state, repath from scratch.
	if not _stall_hard_attempted and _stuck_seconds >= STALL_HARD_RECOVERY_SECONDS:
		_stall_hard_attempted = true
		if not _stall_snapshot_taken:
			_dump_stall_snapshot()
			_stall_snapshot_taken = true
		GrindLog.log_line("[stall] HARD-RECOVERY f=%d clear-state+repath bot=%s -> stairs=%s" % [
			current_floor, str(bot.cell), str(stairs_cell),
		])
		bot.path = PackedVector2Array()
		bot_target_cell = Vector2i(-1, -1)
		bot_target_kind = ""
		_force_repath_to_stairs()
		return
	# Last resort: 30 seconds of doing nothing in an empty room means
	# something is broken (orphaned cell, busted dist field, generator
	# regression). Snap to stairs and descend so the run survives. This
	# should be exceptionally rare — every trigger of this branch is a
	# generator/AI bug worth investigating.
	if _stuck_seconds >= STALL_TELEPORT_SECONDS:
		floor_hard_recoveries += 1
		GrindLog.log_line("[stall] TELEPORT f=%d last-resort from=%s to=%s" % [
			current_floor, str(bot.cell), str(stairs_cell),
		])
		if stairs_cell.x >= 0 and stairs_cell.y >= 0 \
				and stairs_cell.y < grid.size() and stairs_cell.x < grid[0].size():
			bot.place_at(stairs_cell)
			_descend()
		_reset_stuck_timer()

func _reset_stuck_timer() -> void:
	_stuck_seconds = 0.0
	_stall_warned = false
	_stall_soft_attempted = false
	_stall_hard_attempted = false

func _force_repath_to_stairs() -> void:
	if stairs_cell.x < 0 or stairs_cell.y < 0:
		return
	if stairs_cell.y >= grid.size() or stairs_cell.x >= grid[0].size():
		return
	var p: PackedVector2Array = pathing.path(bot.cell, stairs_cell)
	if p.size() > 1:
		bot.set_path(p.slice(1))
		bot_target_cell = stairs_cell
		bot_target_kind = "stairs"

func _dump_stall_snapshot() -> void:
	var path := "user://stall_snapshot_floor%d.txt" % current_floor
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return
	f.store_line("# stall snapshot floor %d biome %s layout %s" % [current_floor, String(current_biome.get("id", "?")), String(current_biome.get("layout", "?"))])
	f.store_line("# bot=%s stairs=%s enemies=%d interactables=%d" % [str(bot.cell), str(stairs_cell), enemies.size(), interactables.size()])
	f.store_line("# legend: . floor   # wall   > stairs   B bot   E enemy   I interactable")
	var w: int = grid[0].size()
	var h: int = grid.size()
	for y in h:
		var row: String = ""
		for x in w:
			var cell := Vector2i(x, y)
			if cell == bot.cell:
				row += "B"
				continue
			if cell == stairs_cell:
				row += ">"
				continue
			var enemy_here: bool = false
			for e in enemies:
				if is_instance_valid(e) and e.is_alive and e.cell == cell:
					enemy_here = true
					break
			if enemy_here:
				row += "E"
				continue
			var inter_here: bool = false
			for inter in interactables:
				if is_instance_valid(inter) and inter.cell == cell:
					inter_here = true
					break
			if inter_here:
				row += "I"
				continue
			match grid[y][x]:
				C.T_FLOOR: row += "."
				C.T_WALL:  row += "#"
				C.T_STAIRS_DOWN: row += ">"
				_: row += "?"
		f.store_line(row)
	f.close()
	GrindLog.log_line("[grind] stall snapshot written to %s" % path)

func _count_unvisited_rooms() -> int:
	var n: int = 0
	for v in visited_rooms:
		if not v:
			n += 1
	return n

func _count_alive_adjacent_enemies() -> int:
	var n: int = 0
	for e in enemies:
		if is_instance_valid(e) and e.is_alive and _chebyshev(bot.cell, e.cell) <= 1:
			n += 1
	return n

# True if any live enemy is within combat-engagement range. Used by the
# stall watchdog to keep the timer at zero during boss fights, ranged duels,
# and knockback recovery — anywhere "fighting" might temporarily look like
# "standing still."
func _has_combat_engaged_enemy() -> bool:
	for e in enemies:
		if is_instance_valid(e) and e.is_alive and _chebyshev(bot.cell, e.cell) <= AGGRO_ENGAGE_RANGE:
			return true
	return false

func _nearest_interactable() -> Interactable:
	var best: Interactable = null
	var best_d: int = 9999
	for i in interactables:
		if not is_instance_valid(i) or not i.can_interact():
			continue
		if i.should_skip(bot):
			continue
		var dist: int = _chebyshev(bot.cell, i.cell)
		if dist < best_d:
			best_d = dist
			best = i
	return best

# Returns the nearest interactable whose cell is inside `rect` (a BSP room).
# Used by the current-room loot priority so bot finishes the room it's in
# before chasing distant goals.
func _nearest_interactable_in_room(rect: Rect2i) -> Interactable:
	var best: Interactable = null
	var best_d: int = 9999
	for i in interactables:
		if not is_instance_valid(i) or not i.can_interact():
			continue
		if i.should_skip(bot):
			continue
		if not rect.has_point(i.cell):
			continue
		var dist: int = _chebyshev(bot.cell, i.cell)
		if dist < best_d:
			best_d = dist
			best = i
	return best

# Returns the BSP room index containing `cell`, or -1 if none. For caves
# layouts where _detect_open_regions builds rectangle approximations of the
# organic regions, this still works — a bot standing inside a detected
# region is "in that room" for priority purposes.
func _room_containing(cell: Vector2i) -> int:
	for i in rooms.size():
		var r: Rect2i = rooms[i]
		if r.has_point(cell):
			return i
	return -1

# Nearest unconsumed fountain — used by low-HP retreat behaviour.
func _nearest_fountain_unconsumed() -> Interactable:
	var best: Interactable = null
	var best_d: int = 9999
	for i in interactables:
		if not is_instance_valid(i) or not i.can_interact():
			continue
		if not (i is Fountain):
			continue
		var dist: int = _chebyshev(bot.cell, i.cell)
		if dist < best_d:
			best_d = dist
			best = i
	return best

# True if `cell` is occupied by a live enemy other than `ignore`. Used by
# the enemy AI to avoid stacking — they wait their turn instead of piling
# onto the bot's cell.
func cell_has_other_enemy(cell: Vector2i, ignore: Enemy) -> bool:
	for e in enemies:
		if e == ignore:
			continue
		if not is_instance_valid(e) or not e.is_alive:
			continue
		if e.cell == cell:
			return true
	return false

func _begin_interaction(inter: Interactable) -> void:
	bot_interacting = true
	interact_target = inter
	interact_timer = inter.interact_duration
	bot.path = PackedVector2Array()
	if bot.fx:
		bot.fx.kneel(inter.interact_duration)
	inter.on_interact_start(bot)

func _tick_interaction(delta: float) -> void:
	interact_timer -= delta
	if interact_timer > 0.0:
		return
	var inter: Interactable = interact_target
	bot_interacting = false
	interact_target = null
	if not is_instance_valid(inter) or inter.consumed:
		return
	if inter is LootDrop:
		_complete_loot_pickup(inter)
	else:
		inter.on_interact_complete(bot)
	invalidate_fog()

func _complete_loot_pickup(drop: LootDrop) -> void:
	var inst: Dictionary = drop.instance
	var item: Dictionary = drop.item
	var display_name: String = AffixSystem.format_item_name(String(item.name), inst.get("affixes", []), inst)
	floor_loot_picked += 1
	dropped_items.append(inst)
	# Append into this floor's segment (lazy-create on first pickup).
	_ensure_current_floor_segment()
	(_loot_segments[_current_floor_segment_index].items as Array).append(inst)
	_rebuild_inv_cache()
	# Auto-salvage is deferred to floor-end / run-end so the HUD never
	# pays the segment-shrink rebuild cost mid-combat. The cap is a
	# soft cap during a run; the next descent / death flushes overflow.
	# Inline call ran on every pickup once cap was hit, which was the
	# loot stutter we tracked down.
	_pending_salvage_check = true
	_push_inventory_to_hud()
	loot_log.append("Looted: [%s] %s" % [item.rarity, display_name])
	_log("Found: %s [%s]" % [display_name, item.rarity], "loot")
	loot_drops.erase(drop)
	interactables.erase(drop)
	drop.consumed = true
	invalidate_fog()
	# Magic shimmer for legendaries; gold sparkle for rares.
	var rarity: String = String(item.get("rarity", ""))
	var pickup_pos: Vector2 = drop.position + Vector2(C.TILE_SIZE * 0.5, C.TILE_SIZE * 0.5)
	if rarity == "legendary":
		Effects.magic_shimmer(actor_layer, pickup_pos)
	elif rarity == "rare":
		Effects.gold_burst(actor_layer, pickup_pos)
	if bot.fx:
		bot.fx.loot_pop()
	drop.play_pickup_then_free()

func _ensure_current_floor_segment() -> void:
	if _current_floor_segment_index >= 0 and _current_floor_segment_index < _loot_segments.size():
		return
	_loot_segments.append({"header": "Floor %d" % current_floor, "items": []})
	_current_floor_segment_index = _loot_segments.size() - 1

func _rebuild_inv_cache() -> void:
	# Flat mirror of every segment's items, in render order. Used at run
	# end to write SaveState.inventory.
	_hud_inv_cache.clear()
	for seg in _loot_segments:
		for inst in seg.get("items", []):
			_hud_inv_cache.append(inst)

func _push_inventory_to_hud() -> void:
	if chrome != null:
		chrome.update_inventory_segments(_loot_segments, items_db, _slot_cooldowns)

# Pull this branch's rolled modifiers from save, clear them so the next
# Outpost visit re-rolls fresh, and resolve floor count from any
# Endless-style modifiers. Called from _start_run before roll_run_plan
# so the plan is sized correctly.
func _resolve_active_modifiers() -> void:
	var save: Dictionary = SaveState.load_state()
	var all_mods: Dictionary = save.get("branch_modifiers", {})
	active_modifiers = (all_mods.get(branch_id, []) as Array).duplicate() if branch_id != "" else []
	if branch_id != "" and all_mods.has(branch_id):
		all_mods.erase(branch_id)
		save["branch_modifiers"] = all_mods
		SaveState.save_state(save)
	if not active_modifiers.is_empty():
		GrindLog.log_line("[run] modifiers=%s" % str(active_modifiers))
	var extra_floors: int = int(RunModifiers.sum_effect(active_modifiers, "extra_floors", 0.0))
	_floors_per_run = C.FLOORS_PER_RUN + extra_floors
	_boss_floor = _floors_per_run

# Auto-salvage: when inventory exceeds cap, walk segments oldest-first
# and convert items to gold until back under. Only salvages items with
# rarity at-or-below loot_filter (so a player who set filter=epic doesn't
# lose epic+ items). Starter gear is excluded — never salvage rusty_dagger
# or tattered_hide. Per item: gold = SALVAGE_VALUES[rarity].
const _SALVAGE_VALUES := {
	"common": 2, "uncommon": 6, "rare": 18, "epic": 60, "legendary": 200,
}
const _STARTER_IDS := ["rusty_dagger", "tattered_hide"]

func _maybe_auto_salvage() -> void:
	if _hud_inv_cache.size() <= _inventory_cap:
		return
	# Salvage threshold = the player's loot filter. Items above filter
	# rarity are protected; only filtered-or-below get sold.
	var threshold_rank: int = LootDrop.loot_filter_min_rank
	var gold_earned: int = 0
	var salvaged_count: int = 0
	# Walk segments oldest-first (Base segment first — that's the player's
	# stash, which is correct for "salvage what's been sitting there
	# longest"). Within a segment, walk items by index.
	for seg in _loot_segments:
		var items_arr: Array = seg.get("items", [])
		var i: int = 0
		while i < items_arr.size() and _hud_inv_cache.size() - salvaged_count > _inventory_cap:
			var inst: Variant = items_arr[i]
			if typeof(inst) != TYPE_DICTIONARY:
				i += 1
				continue
			var base_id: String = String(inst.get("base_id", ""))
			if base_id in _STARTER_IDS:
				i += 1
				continue
			if not items_db.has(base_id):
				i += 1
				continue
			# Favorited items are locked from auto-salvage. The user
			# starred them deliberately — bulk salvage skips them
			# regardless of rarity or filter setting.
			if bool(inst.get("favorite", false)):
				i += 1
				continue
			var item: Dictionary = items_db[base_id]
			var rarity: String = String(item.get("rarity", "common"))
			# Anything strictly above the filter is protected.
			if LootDrop.RARITY_RANK.get(rarity, 0) > threshold_rank:
				i += 1
				continue
			gold_earned += int(_SALVAGE_VALUES.get(rarity, 1))
			salvaged_count += 1
			items_arr.remove_at(i)
			# Don't advance i — the next item shifted into this slot.
		if _hud_inv_cache.size() - salvaged_count <= _inventory_cap:
			break
	if salvaged_count > 0:
		bot.gold += gold_earned
		_run_salvaged_count += salvaged_count
		_run_salvaged_gold += gold_earned
		_rebuild_inv_cache()
		_push_inventory_to_hud()
		_log("Salvaged %d items (+%d gold)." % [salvaged_count, gold_earned], "loot")

# Player-initiated equip from the HUD inventory. Per-slot cooldown stops
# the player from juggling identical items every tick to game positioning.
# Returns true if the equip happened.
func try_equip_from_segment(seg_idx: int, item_idx: int) -> bool:
	if seg_idx < 0 or seg_idx >= _loot_segments.size():
		return false
	var seg: Dictionary = _loot_segments[seg_idx]
	var items: Array = seg.get("items", [])
	if item_idx < 0 or item_idx >= items.size():
		return false
	var inst: Variant = items[item_idx]
	if typeof(inst) != TYPE_DICTIONARY:
		return false
	var base_id: String = String(inst.get("base_id", ""))
	if not items_db.has(base_id):
		return false
	var slot: String = String(items_db[base_id].get("slot", ""))
	if slot == "":
		return false
	# Per-slot cooldown gate.
	var cd: float = float(_slot_cooldowns.get(slot, 0.0))
	if cd > 0.0:
		_log("Equip on cooldown: %s (%.0fs left)" % [slot.capitalize(), cd], "combat")
		return false
	if not is_instance_valid(bot):
		return false
	# Species can't wear this slot. Block early with a player-visible
	# log so the click feels intentional rather than silently ignored.
	if not SpeciesData.can_wear(bot.species_id, slot):
		var sp_def: Dictionary = SpeciesData.get_def(bot.species_id)
		_log("%s cannot wear %s." % [String(sp_def.get("name", "Bot")), slot.capitalize()], "combat")
		return false
	# 2H ↔ shield exclusion can return up to TWO displaced items.
	var displaced_arr: Array = bot.equip_from_inventory(inst)
	# Remove the picked item from its segment.
	items.remove_at(item_idx)
	# Stash all displaced items back at the same segment so the player
	# can find them. Newest at the end so equipped→unequipped order
	# is preserved.
	for d in displaced_arr:
		if typeof(d) == TYPE_DICTIONARY:
			items.append(d)
	_slot_cooldowns[slot] = EQUIP_COOLDOWN_SECONDS
	_rebuild_inv_cache()
	_push_inventory_to_hud()
	# Equip changed → trigger paperdoll refresh next frame via the existing
	# equipped-hash compare in _update_biome_hud.
	_last_equipped_hash = 0
	return true

func _tick_equip_cooldowns(delta: float) -> void:
	if _slot_cooldowns.is_empty():
		return
	for slot in _slot_cooldowns.keys():
		var cd: float = float(_slot_cooldowns[slot]) - delta
		if cd <= 0.0:
			_slot_cooldowns.erase(slot)
		else:
			_slot_cooldowns[slot] = cd
	# Lightweight per-frame refresh — only updates the paperdoll countdown
	# labels, not the inventory grid (which would be wasteful every tick).
	if chrome != null:
		chrome.update_cooldowns(_slot_cooldowns)

func _on_chest_opened(chest: Chest, n: int, bias: int) -> void:
	floor_chests_opened += 1
	var chest_world: Vector2 = chest.position + Vector2(C.TILE_SIZE * 0.5, C.TILE_SIZE * 0.5)
	for i in n:
		var rarity: String = _roll_rarity_with_bias(bias)
		var picked: String = _pick_loot_id(rarity)
		if picked == "":
			continue
		var inst: Dictionary = _create_item_instance(picked)
		var spawn_cell: Vector2i = _adjacent_walkable_cell(chest.cell, i + 1)
		var drop := _spawn_loot_drop_get(inst, spawn_cell)
		if drop:
			drop.arc_from(chest_world, 0.45 + i * 0.05)
	interactables.erase(chest)
	_log("Opened a chest!", "loot")
	var fade := chest.create_tween()
	fade.tween_interval(2.0)
	fade.tween_property(chest, "modulate:a", 0.0, 0.5)
	fade.tween_callback(chest.queue_free)
	invalidate_fog()

func _spawn_loot_drop_get(instance: Dictionary, at_cell: Vector2i) -> LootDrop:
	var base_id: String = String(instance.get("base_id", ""))
	if not items_db.has(base_id):
		return null
	var drop := LootDrop.new()
	drop.setup_instance(instance, items_db[base_id], at_cell)
	actor_layer.add_child(drop)
	loot_drops.append(drop)
	interactables.append(drop)
	return drop

func _roll_rarity_with_bias(bias: int) -> String:
	# Chest-pickup variant. Same source-tier clamp as _roll_rarity so
	# entering a wizlab portal on Floor 2 of the dungeon doesn't dump
	# T5-grade legendaries from the bonus chests.
	var floor_bonus: float = float(current_floor - 1) * 0.05
	var bias_bonus: float = float(bias) * 0.10
	var r: float = rng.randf() - floor_bonus - bias_bonus
	var rarity: String
	if r < 0.02: rarity = "legendary"
	elif r < 0.10: rarity = "epic"
	elif r < 0.25: rarity = "rare"
	elif r < 0.55: rarity = "uncommon"
	else: rarity = "common"
	return _clamp_rarity_to_tier(rarity)

func _adjacent_walkable_cell(center: Vector2i, idx: int) -> Vector2i:
	var offsets: Array[Vector2i] = [
		Vector2i(0, 0), Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
		Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)
	]
	for i in offsets.size():
		var probe: Vector2i = offsets[(i + idx) % offsets.size()]
		var c: Vector2i = center + probe
		if c.y >= 0 and c.y < grid.size() and c.x >= 0 and c.x < grid[0].size():
			if grid[c.y][c.x] == C.T_FLOOR:
				return c
	return center

const MAX_REPATHS_PER_FRAME := 3

func _tick_enemies(delta: float) -> void:
	# Showcase mode: enemies are frozen visual props — no AI, no aggro,
	# no path. Their light_spec / sprite / flicker still update, since
	# those are driven elsewhere (FlickerDriver per-frame, sprites are
	# CanvasItems that paint regardless).
	if DebugJump.showcase:
		return
	# Cap A* paths per frame so a horde repath doesn't burn 24*1ms in one
	# tick. Enemies that miss this frame's slot keep their old path
	# (still animates) and try again next frame — at 60Hz the player
	# never sees the difference.
	var repaths_this_frame: int = 0
	for e in enemies:
		if not is_instance_valid(e) or not e.is_alive:
			continue
		# Tick ENCH overlays per-enemy. Cheap (skips when no statuses).
		e.tick_statuses(delta)
		var dist: int = _chebyshev(e.cell, bot.cell)
		if dist > e.aggro_range:
			continue
		if dist <= 1:
			e.path = PackedVector2Array()
			e.attempt_attack(bot, delta)
			if not bot.is_alive:
				_log("Slain by %s on floor %d." % [e.display_name, current_floor])
				if _try_death_retreat("slain by %s on f%d" % [e.display_name, current_floor]):
					return
				_end_run(false)
				return
		else:
			e.repath_timer -= delta
			var needs_repath: bool = e.path.is_empty() or e.path_index >= e.path.size() or e.repath_timer <= 0.0
			if needs_repath and repaths_this_frame < MAX_REPATHS_PER_FRAME:
				e.repath_timer = Enemy.REPATH_INTERVAL
				var p: PackedVector2Array = pathing.path(e.cell, bot.cell)
				if p.size() > 1:
					e.set_path(p.slice(1))
				repaths_this_frame += 1
			# Soft collision: if our next path-cell already has another live
			# enemy on it, hold this tick so we don't visually stack.
			# Bot's cell is exempt — the goal of pursuit IS to share that cell.
			if e.path.size() > 0 and e.path_index < e.path.size():
				var next: Vector2 = e.path[e.path_index]
				var next_cell := Vector2i(int(next.x / C.TILE_SIZE), int(next.y / C.TILE_SIZE))
				if next_cell != bot.cell and cell_has_other_enemy(next_cell, e):
					continue
			e.step_movement(delta)

func _mark_room_visited_at(cell: Vector2i) -> void:
	for i in rooms.size():
		var r: Rect2i = rooms[i]
		if cell.x >= r.position.x and cell.x < r.position.x + r.size.x \
				and cell.y >= r.position.y and cell.y < r.position.y + r.size.y:
			visited_rooms[i] = true
			return

func _nearest_unvisited_room_center() -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_d: int = 999999
	for i in rooms.size():
		if visited_rooms[i]:
			continue
		var center: Vector2i = _room_center(rooms[i])
		var d: int = _chebyshev(bot.cell, center)
		if d < best_d:
			best_d = d
			best = center
	return best

func _room_center(r: Rect2i) -> Vector2i:
	return Vector2i(r.position.x + int(r.size.x / 2.0), r.position.y + int(r.size.y / 2.0))

func _descend() -> void:
	# Flush any deferred auto-salvage now that the floor is over —
	# the HUD rebuild happens during the load screen, not mid-combat.
	if _pending_salvage_check:
		_pending_salvage_check = false
		_maybe_auto_salvage()
	# Per-floor summary line — one structured row per cleared floor. Emitted
	# before floor_cleared so consumers see the data first.
	var ticks: int = Engine.get_process_frames() - floor_start_tick
	var biome_id: String = String(current_biome.get("id", "?"))
	var floor_label: String = "%s%s" % [biome_id, ".portal" if portal_active else ""]
	var hp_lost: int = max(0, floor_starting_hp - bot.hp)
	GrindLog.log_line("[floor] f=%d biome=%s ticks=%d kills=%d loot=%d chests=%d altars=%d fountains=%d portals=%d stalls=%d hp_lost=%d" % [
		current_floor, floor_label, ticks, floor_kills, floor_loot_picked,
		floor_chests_opened, floor_altars_used, floor_fountains_used,
		floor_portals_entered, floor_stalls, hp_lost,
	])
	var perf_floor: String = PerfMon.floor_end_summary()
	if perf_floor != "":
		GrindLog.log_line("[perf-floor] " + perf_floor)
	# Run-wide accumulators
	run_kills += floor_kills
	run_loot_picked += floor_loot_picked
	run_portals_entered += floor_portals_entered
	run_stalls += floor_stalls
	if not run_biomes_visited.has(biome_id):
		run_biomes_visited.append(biome_id)
	floor_cleared.emit(current_floor)
	if portal_active:
		# Portal stairs return to the run's main progression on the NEXT floor.
		_log("Returned from %s portal." % portal_kind)
		portal_active = false
		portal_kind = ""
		portal_biome_override = {}
		portal_loot_bias = 0
	_log("Descended to floor %d." % (current_floor + 1))
	if current_floor >= _floors_per_run:
		_end_run(true)
		return
	current_floor += 1
	_build_floor()

# Bot just hit HP=0. If the player has a revive left, retreat to floor 1
# of the current branch with full HP — keeps the run going so AFK play
# accrues loot even on a too-hard branch. When revives are exhausted, the
# next death is a real game-over and we _end_run(false). Returns true if
# the death was absorbed into a retreat (caller should NOT also _end_run).
func _try_death_retreat(reason: String) -> bool:
	if revives_remaining <= 0:
		return false
	revives_remaining -= 1
	retreats_this_run += 1
	_log("Bot retreats — %d revives left." % revives_remaining, "loot")
	GrindLog.log_line("[retreat] reason=\"%s\" revives_left=%d retreats_this_run=%d" % [
		reason, revives_remaining, retreats_this_run,
	])
	# Revive the bot at full HP. Actor.take_damage already started the
	# death-spin tween + queued an _on_death_tween_done callback that
	# would queue_free the bot. Kill the tween, reset the rig transform,
	# disconnect the queue_free, and flip is_alive back so AI resumes on
	# the new floor. Bot stays the same instance — level, xp, gear,
	# equipped, mid-run inventory all preserved.
	if bot.fx and bot.fx.transient and bot.fx.transient.is_valid():
		bot.fx.transient.kill()
	if bot.rig:
		bot.rig.rotation = 0.0
		bot.rig.scale = Vector2.ONE
		bot.rig.modulate = Color(1, 1, 1, 1)
	bot.is_alive = true
	bot.hp = bot.max_hp
	bot._update_hp_bar()
	# Reset to floor 1 of the same branch. Loot accumulated so far stays
	# in _loot_segments and _hud_inv_cache; new floor opens its own segment.
	current_floor = 1
	_build_floor()
	return true

func _end_run(victory: bool) -> void:
	# Final salvage pass before we serialize. Done unconditionally so
	# the saved inventory respects the cap even if the run ended on a
	# pickup that overflowed without a chance to flush.
	if _pending_salvage_check or _hud_inv_cache.size() > _inventory_cap:
		_pending_salvage_check = false
		_maybe_auto_salvage()
	# Loot is loot — banked on victory or death. The idle-game loop is "watch
	# the bot fill your stash"; a 50% death tax punishes idle play.
	var save: Dictionary = SaveState.load_state()
	save.gold = bot.gold
	save.level = bot.level
	save.xp = bot.xp
	# Persist whatever is currently in the live HUD inventory cache. That's
	# the source of truth — it includes base inventory + everything looted
	# this run, minus anything that got equipped mid-run (those moved to
	# bot.equipped, also persisted below).
	save.inventory = _hud_inv_cache.duplicate(true)
	save.equipped = bot.equipped.duplicate(true) if is_instance_valid(bot) else save.get("equipped", {})
	save.runs_completed = int(save.get("runs_completed", 0)) + 1
	save.highest_floor = maxi(int(save.get("highest_floor", 0)), current_floor)
	SaveState.save_state(save)
	# Surface spell fire count to the grind log so headless smoke runs
	# can verify the autocast layer is alive without an editor session.
	var by_arch: Dictionary = SpellSystem.get_fire_by_arch()
	var arch_summary: String = ""
	for k in by_arch.keys():
		arch_summary += " %s=%d" % [k, int(by_arch[k])]
	GrindLog.log_line("[spells] fire_count=%d%s" % [SpellSystem.get_fire_count(), arch_summary])
	var kept: Array = dropped_items.duplicate(true)

	var report: Dictionary = {
		"victory": victory,
		"floor": current_floor,
		"level": bot.level,
		"xp": bot.xp,
		"gold": bot.gold,
		"hp": bot.hp,
		"max_hp": bot.max_hp,
		"retreats": retreats_this_run,
		"salvaged_count": _run_salvaged_count,
		"salvaged_gold": _run_salvaged_gold,
		"kills": kills.duplicate(),
		"loot_log": loot_log.duplicate(),
		"dropped": dropped_items.duplicate(),
		"kept": kept,
		"journal": journal.duplicate(true),
		"items_db": items_db,
	}
	run_ended.emit(victory, report)

func _nearest_enemy() -> Enemy:
	var best: Enemy = null
	var best_d: int = 9999
	for e in enemies:
		if not is_instance_valid(e) or not e.is_alive:
			continue
		var d: int = _chebyshev(bot.cell, e.cell)
		if d < best_d:
			best_d = d
			best = e
	return best

func _chebyshev(a: Vector2i, b: Vector2i) -> int:
	return maxi(abs(a.x - b.x), abs(a.y - b.y))

func _random_walkable_cell_far_from_bot() -> Vector2i:
	# Try the strict ≥6 chebyshev pick first. If the rolling loop fails
	# (tight floors / caves layouts with bot in the middle), DO NOT fall
	# through to a deterministic top-left scan — that's the bug that
	# stacks every enemy + interactable on the north tile when the
	# strict path rejects too many candidates. Instead, collect all
	# valid floor cells and weight-pick by chebyshev so we still get
	# spread without a hard floor on distance.
	for _i in 200:
		var x: int
		var y: int
		if rooms.is_empty():
			x = rng.randi_range(1, grid[0].size() - 2)
			y = rng.randi_range(1, grid.size() - 2)
		else:
			var rm: Rect2i = rooms[rng.randi_range(0, rooms.size() - 1)]
			x = rng.randi_range(rm.position.x, rm.position.x + rm.size.x - 1)
			y = rng.randi_range(rm.position.y, rm.position.y + rm.size.y - 1)
		if y < 0 or y >= grid.size() or x < 0 or x >= grid[0].size():
			continue
		if grid[y][x] != C.T_FLOOR:
			continue
		var cell := Vector2i(x, y)
		if _chebyshev(cell, bot.cell) > 6:
			return cell
	# Fallback: collect every walkable cell, prefer the farthest from
	# the bot but pick randomly within the top decile so spawn waves
	# don't deterministically pile on a single cell.
	var candidates: Array[Vector2i] = []
	for y in grid.size():
		for x in grid[0].size():
			if grid[y][x] == C.T_FLOOR:
				var c := Vector2i(x, y)
				if c != bot.cell:
					candidates.append(c)
	if candidates.is_empty():
		return bot.cell
	# Sort by chebyshev DESC; sample from the farthest 25% so caller
	# still gets a "far from bot" cell but not the same one every call.
	candidates.sort_custom(func(a, b): return _chebyshev(a, bot.cell) > _chebyshev(b, bot.cell))
	var pool_size: int = maxi(1, int(candidates.size() / 4))
	return candidates[rng.randi_range(0, pool_size - 1)]

func _pick_boss_room() -> Vector2i:
	if not rooms.is_empty():
		var rm: Rect2i = rooms[rooms.size() - 1]
		return Vector2i(rm.position.x + int(rm.size.x / 2.0), rm.position.y + int(rm.size.y / 2.0))
	# fallback: farthest floor cell from bot
	return _random_walkable_cell_far_from_bot()

func _find_stairs_cell() -> Vector2i:
	for y in grid.size():
		for x in grid[0].size():
			if grid[y][x] == C.T_STAIRS_DOWN:
				return Vector2i(x, y)
	return bot.cell

func _center_camera_on_bot() -> void:
	if not (camera and is_instance_valid(bot)):
		return
	camera.position = bot.position + Vector2(C.TILE_SIZE * 0.5, C.TILE_SIZE * 0.5)
	# Screenshot mode: capture the whole 1024×1024 frame as dungeon content,
	# no chrome compensation needed.
	if DebugJump.active and DebugJump.screenshot:
		camera.offset = Vector2.ZERO
		return
	# Translucent chrome means the player can see the dungeon UNDER the right
	# sidebar and bottom bag — so the visible-dungeon "main viewport" is the
	# rectangle not covered by chrome. Shift the camera so the bot sits at the
	# centre of that rectangle, not the geometric viewport centre. In Godot
	# 2D, camera.offset shifts the rendered view: +x makes the bot appear
	# LEFT on screen (away from the right sidebar), +y makes the bot appear
	# UP on screen (away from the bottom bag). Offset is in world units, so
	# we divide by zoom to get the requested screen-pixel shift.
	var dx_screen: float = HudChrome.SIDEBAR_W * 0.5
	var dy_screen: float = HudChrome.BAG_H * 0.5
	var zx: float = camera.zoom.x if camera.zoom.x != 0.0 else 1.0
	var zy: float = camera.zoom.y if camera.zoom.y != 0.0 else 1.0
	camera.offset = Vector2(dx_screen / zx, dy_screen / zy)

func _scatter_ambient_decor() -> void:
	var density: float = BiomeData.ambient_density_for(current_biome)
	if density <= 0.0:
		return
	for y in grid.size():
		var row: Array = grid[y]
		for x in row.size():
			if row[x] != C.T_FLOOR:
				continue
			if rng.randf() > density:
				continue
			var decor_id: String = BiomeData.pick_ambient_decor(current_biome, rng)
			if decor_id == "":
				continue
			var decor := AmbientDecor.new()
			decor.setup(decor_id, Vector2i(x, y))
			actor_layer.add_child(decor)
			ambient_decor_nodes.append(decor)

func _world_light_sources() -> Array:
	# Returns [{cell, position, radius_px, intensity, color, flicker}] for
	# every world light source. Each source feeds both LoS computation and
	# the fog shader tint. Bot is appended separately by callers.
	# `flicker` carries {category, freq, amp, seed} so _gather_lights can
	# sample noise per-frame to modulate intensity (decor lights have no
	# PointLight2D so flicker animation lives in the source dict, not on a
	# scene-tree node).
	# Cached: invalidated by invalidate_fog() (interactable consume,
	# enemy death/spawn, floor build).
	if _cached_world_lights_valid:
		return _cached_world_lights
	var out: Array = []
	for inter in interactables:
		if not is_instance_valid(inter) or inter.consumed:
			continue
		var spec_id: String = ""
		if inter is Chest:
			spec_id = "chest_orange" if inter.rarity_bias >= 2 else "chest_gold"
		elif inter is Fountain:
			spec_id = "fountain_" + (inter as Fountain).kind
		elif inter is Altar:
			spec_id = "altar_" + (inter as Altar).god
		elif inter is LootDrop:
			var rarity: String = String((inter as LootDrop).item.get("rarity", "common"))
			if rarity != "common":
				spec_id = "loot_" + rarity
		if spec_id == "":
			continue
		var spec: Dictionary = LightSpec.SPECS.get(spec_id, {})
		if spec.is_empty():
			continue
		var radius_tiles: float = float(spec.get("range", 3.0))
		out.append({
			"cell": inter.cell,
			"position": inter.position + Vector2(C.TILE_SIZE * 0.5, C.TILE_SIZE * 0.5),
			"radius": int(ceil(radius_tiles)),
			"radius_px": C.TILE_SIZE * radius_tiles,
			"intensity": float(spec.get("energy", 0.7)),
			"color": spec.get("color", Color(1, 1, 1)),
			"flicker": _flicker_meta_for(spec),
		})
	for n in ambient_decor_nodes:
		if not is_instance_valid(n) or not (n is AmbientDecor):
			continue
		var decor := n as AmbientDecor
		if decor.light_spec_id == "":
			continue
		var spec2: Dictionary = LightSpec.SPECS.get(decor.light_spec_id, {})
		if spec2.is_empty():
			continue
		var radius_tiles2: float = float(spec2.get("range", 3.0))
		out.append({
			"cell": decor.cell,
			"position": decor.position + Vector2(C.TILE_SIZE * 0.5, C.TILE_SIZE * 0.5),
			"radius": int(ceil(radius_tiles2)),
			"radius_px": C.TILE_SIZE * radius_tiles2,
			"intensity": float(spec2.get("energy", 0.6)),
			"color": spec2.get("color", Color(1, 1, 1)),
			"flicker": _flicker_meta_for(spec2),
		})
	_cached_world_lights = out
	_cached_world_lights_valid = true
	return out

var _flicker_seed_counter: int = 0
var _flicker_noise: FastNoiseLite = null

func _flicker_meta_for(spec: Dictionary) -> Dictionary:
	# Per-source flicker descriptor — used by _gather_lights to modulate
	# intensity each frame. amp=0 means "steady, skip the noise sample."
	var amp: float = float(spec.get("amp", 0.0))
	if amp <= 0.0:
		return {}
	_flicker_seed_counter += 1
	return {
		"category": String(spec.get("category", "steady")),
		"freq": float(spec.get("freq", 1.0)),
		"amp": amp,
		"seed": _flicker_seed_counter,
	}

func _flicker_factor(meta: Dictionary, t: float) -> float:
	# Returns the multiplier to apply to base intensity. Mirrors
	# FlickerDriver._animate_light's math so PointLight2D-backed lights and
	# fog-shader-only lights pulse identically.
	if meta.is_empty():
		return 1.0
	if _flicker_noise == null:
		_flicker_noise = FastNoiseLite.new()
		_flicker_noise.noise_type = FastNoiseLite.TYPE_PERLIN
		_flicker_noise.frequency = 1.0
	var freq: float = float(meta.get("freq", 1.0))
	var amp: float = float(meta.get("amp", 0.0))
	var seed_id: int = int(meta.get("seed", 0))
	var n: float = _flicker_noise.get_noise_2d(t * freq, float(seed_id) * 17.3)
	var category: String = String(meta.get("category", ""))
	if category == "magic":
		var slow: float = sin(t * freq * 0.4 + float(seed_id) * 0.7) * 0.4
		n = (n + slow) * 0.5
	return maxf(0.0, 1.0 + n * amp)

func invalidate_fog() -> void:
	# Called when an interactable is consumed, an enemy dies/spawns, or any
	# other event that changes the visible-light set or visibility-blocker
	# layout. Bot motion is handled implicitly by the cell-change check.
	_fog_dirty = true
	_cached_world_lights_valid = false

func _refresh_fog() -> void:
	if fog == null or not is_instance_valid(bot):
		return
	# Gate on bot cell change OR explicit dirty flag. The fog state only
	# meaningfully changes when LoS sources move, so re-running raycast +
	# texture rebuild + per-actor visibility every frame is wasted work.
	# Per-tile modulate fade in MapRenderer continues to run every frame
	# regardless, so transitions stay smooth.
	if bot.cell == _last_fog_cell and not _fog_dirty:
		return
	PerfMon.begin(PerfMon.TAG_FOG)
	_last_fog_cell = bot.cell
	_fog_dirty = false
	var sources: Array = _world_light_sources()
	fog.recompute(bot.cell, sources)
	if current_renderer:
		current_renderer.apply_visibility(fog)
	_apply_visibility_to_actors()
	if fog_overlay:
		fog_overlay.set_visibility_grid(fog)
	PerfMon.end(PerfMon.TAG_FOG)

func _apply_visibility_to_actors() -> void:
	if fog == null:
		return
	for e in enemies:
		if not is_instance_valid(e):
			continue
		e.visible = fog.is_visible(e.cell)
	for d in loot_drops:
		if not is_instance_valid(d):
			continue
		d.visible = fog.is_visible(d.cell)
	for inter in interactables:
		if not is_instance_valid(inter):
			continue
		if inter is LootDrop:
			continue
		inter.visible = fog.is_visible(inter.cell)
	for s in vault_decor_sprites:
		if not is_instance_valid(s):
			continue
		var sc := Vector2i(int(s.position.x / C.TILE_SIZE), int(s.position.y / C.TILE_SIZE))
		s.visible = fog.is_visible(sc)
	for n in ambient_decor_nodes:
		if not is_instance_valid(n):
			continue
		var nc: Vector2i = (n as AmbientDecor).cell if n is AmbientDecor else Vector2i(int(n.position.x / C.TILE_SIZE), int(n.position.y / C.TILE_SIZE))
		n.visible = fog.is_visible(nc)

func _gather_lights() -> Array:
	# Lights consumed by the fog shader. Bot light is unconditional. World
	# lights only contribute if their source cell is currently visible — this
	# stops a torch in an unexplored room from bleeding warmth into the
	# corridor outside it.
	# Flicker meta on each source lets us modulate intensity per-frame
	# without a PointLight2D node — same animation as FlickerDriver does for
	# actor-tier lights, but driven CPU-side and pushed via the existing
	# light_intensities[] shader uniform.
	var out: Array = []
	var t: float = Time.get_ticks_msec() / 1000.0
	if is_instance_valid(bot):
		out.append({
			"position": bot.position + Vector2(C.TILE_SIZE * 0.5, C.TILE_SIZE * 0.5),
			"radius": C.TILE_SIZE * 7.5,
			"intensity": 1.1,
			"color": Color(1.0, 0.92, 0.78, 1.0),
		})
	for src in _world_light_sources():
		if fog and not fog.is_visible(src.cell):
			continue
		var base_intensity: float = float(src.intensity)
		var meta: Dictionary = src.get("flicker", {})
		var animated: float = base_intensity * _flicker_factor(meta, t)
		out.append({
			"position": src.position,
			"radius": src.radius_px,
			"intensity": animated,
			"color": src.color,
		})
	return out

func _make_radial_light(size_px: int) -> Texture2D:
	var img := Image.create(size_px, size_px, false, Image.FORMAT_RGBA8)
	var center := Vector2(size_px * 0.5, size_px * 0.5)
	var max_d: float = size_px * 0.5
	for y in size_px:
		for x in size_px:
			var d: float = Vector2(x, y).distance_to(center)
			var t: float = clampf(1.0 - d / max_d, 0.0, 1.0)
			var a: float = t * t
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)

# --- Showcase mode ---------------------------------------------------------
# Hand-curated visual audit floor. See scripts/showcase.gd. Activated by the
# /showcase skill writing "showcase" to user://DEBUG_FLOOR.txt.

var _showcase_patrol: Array = []
var _showcase_patrol_idx: int = 0

func _build_showcase_floor_data() -> Dictionary:
	var grid_arr: Array = Showcase.build_grid()
	# Bot spawns at the first patrol cell. Stairs cell is parked far away
	# (corner) — we never want the bot to descend in showcase mode, but the
	# field is required by downstream code.
	_showcase_patrol = Showcase.patrol_path()
	_showcase_patrol_idx = 0
	var spawn: Vector2i = _showcase_patrol[0] if not _showcase_patrol.is_empty() else Vector2i(2, 2)
	return {
		"grid": grid_arr,
		"rooms": [],
		"spawn": spawn,
		"stairs_down": Vector2i(Showcase.MAP_W - 2, Showcase.MAP_H - 2),
		"dist_to_stairs": [],
		"vault_results": {},
	}

func _spawn_showcase_stations() -> void:
	for s in Showcase.STATIONS:
		var cell: Vector2i = s.anchor
		var kind: String = s.kind
		match kind:
			"fire_decor":
				for d in ["flame_0", "flame_1", "flame_2"]:
					var c: Vector2i = cell + Vector2i(["flame_0","flame_1","flame_2"].find(d) - 1, 0)
					_showcase_spawn_decor(d, c)
			"magic_decor":
				_showcase_spawn_decor("lantern", cell + Vector2i(-1, 0))
				_showcase_spawn_decor("magic_lamp", cell)
				_showcase_spawn_decor("orb", cell + Vector2i(1, 0))
			"crystal_decor":
				_showcase_spawn_decor("orb_glow_0", cell + Vector2i(-1, 0))
				_showcase_spawn_decor("orb_glow_1", cell)
				_showcase_spawn_decor("crystal_orb", cell + Vector2i(1, 0))
			"mushroom_decor":
				_showcase_spawn_decor("mold_1", cell + Vector2i(-1, 0))
				_showcase_spawn_decor("mold_2", cell)
				_showcase_spawn_decor("zot_pillar", cell + Vector2i(1, 0))
			"campfire":
				# Actor-tier flicker — full PointLight2D + embers. Lets us
				# compare the decor-tier (fog-only) flicker side by side.
				_showcase_spawn_decor("campfire", cell)
			"lava_pool", "water_pool", "ice_patch":
				pass # Terrain stamped at grid-build time; no entity needed.
			"fountain_blue":
				_spawn_fountain(cell, "blue")
			"fountain_blood":
				_spawn_fountain(cell, "blood")
			"altar_trog", "altar_zin", "altar_vehumet", "altar_kikubaaqudgha", "altar_xom":
				var god_id: String = kind.substr(6)
				var altar := Altar.new()
				altar.setup(cell, god_id)
				actor_layer.add_child(altar)
				interactables.append(altar)
			"loot_common", "loot_uncommon", "loot_rare", "loot_epic", "loot_legendary":
				var rarity: String = kind.substr(5)
				_showcase_spawn_loot_at(cell, rarity)
			"chest_normal":
				_spawn_chest(cell, 2, 0)
			"chest_rich":
				_spawn_chest(cell, 3, 2)
			"portal":
				_spawn_portal(cell)
			"enemy_fire_dragon":
				_showcase_spawn_enemy("fire_dragon", cell)
			"enemy_ice_dragon":
				_showcase_spawn_enemy("ice_dragon", cell)
			"enemy_salamander":
				_showcase_spawn_enemy("salamander", cell)
			"enemy_blizzard_demon":
				_showcase_spawn_enemy("blizzard_demon", cell)
			"enemy_firefly":
				_showcase_spawn_enemy("firefly", cell)

func _showcase_spawn_decor(decor_id: String, cell: Vector2i) -> void:
	var decor := AmbientDecor.new()
	decor.setup(decor_id, cell)
	actor_layer.add_child(decor)
	ambient_decor_nodes.append(decor)

func _showcase_spawn_loot_at(cell: Vector2i, rarity: String) -> void:
	var pool: Array = []
	for id in items_db.keys():
		if items_db[id].rarity == rarity:
			pool.append(id)
	if pool.is_empty():
		return
	var picked: String = pool[0]
	var inst: Dictionary = _create_item_instance(picked)
	_spawn_loot_drop(inst, cell)

func _showcase_spawn_enemy(id: String, cell: Vector2i) -> void:
	# Same path as _spawn_specific so creature lights / scaling are honoured.
	# Frozen-in-place is enforced by _tick_enemies skipping all movement when
	# DebugJump.showcase is set.
	_spawn_specific(id, cell)

func _showcase_tick_patrol(delta: float) -> void:
	# Walk to the next patrol cell. When the bot reaches it, advance the
	# index and emit a path to the next one. Loops forever.
	# step_movement is the per-frame mover — Bot._process doesn't move on
	# its own; the dungeon's tick is what advances the bot along its path.
	if _showcase_patrol.is_empty():
		return
	var has_path: bool = bot.path.size() > 0 and bot.path_index < bot.path.size()
	if has_path:
		bot.step_movement(delta)
		return
	# Arrived (or no path yet) — pick next station.
	_showcase_patrol_idx = (_showcase_patrol_idx + 1) % _showcase_patrol.size()
	var target: Vector2i = _showcase_patrol[_showcase_patrol_idx]
	# If our spawn cell already matches the first station, skip ahead by
	# rolling once more — otherwise we'd ask pathing for an empty path and
	# get stuck.
	if target == bot.cell:
		_showcase_patrol_idx = (_showcase_patrol_idx + 1) % _showcase_patrol.size()
		target = _showcase_patrol[_showcase_patrol_idx]
	var p: PackedVector2Array = pathing.path(bot.cell, target)
	if p.size() > 1:
		bot.set_path(p.slice(1))
		bot_target_cell = target
		bot_target_kind = "showcase_patrol"
		bot.step_movement(delta)

func _load_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("Failed to open %s" % path)
		return {}
	var text: String = f.get_as_text()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Failed to parse %s" % path)
		return {}
	return parsed

func _load_items(path: String) -> Dictionary:
	var raw: Dictionary = _load_json(path)
	var by_id: Dictionary = {}
	for it in raw.get("items", []):
		by_id[it.id] = it
	return by_id

func _load_monster_mods() -> Array:
	var raw: Dictionary = _load_json(MONSTER_MODS_PATH)
	return raw.get("mods", [])

# PoE-style pack tier system. Roll a tier per non-boss/non-miniboss/
# non-champion spawn; magic = +20% HP / +10% ATK / 1 mod, rare =
# +60% HP / +30% ATK / 2 mods. Roll rate scales with branch tier so
# T1 stays mostly normal mobs while T5 packs visible color/aura
# variety. Champions skip the roll — they already have their own
# visual treatment, double-tagging would clash.
const _PACK_RARE_BASE_RATE := 0.012   # 1.2% at T1, scales up
const _PACK_MAGIC_BASE_RATE := 0.07   # 7% at T1, scales up

func _roll_pack_tier(branch_tier: int) -> int:
	# Branch tier scales each rate by ~1.5× per tier. T1: 1.2/7%,
	# T2: 1.8/10.5, T3: 2.7/15.7, T4: 4/24, T5: 6/35.
	var scale: float = pow(1.5, float(maxi(branch_tier - 1, 0)))
	var rare_rate: float = _PACK_RARE_BASE_RATE * scale
	var magic_rate: float = _PACK_MAGIC_BASE_RATE * scale
	var r: float = rng.randf()
	if r < rare_rate:
		return Enemy.PACK_RARE
	if r < rare_rate + magic_rate:
		return Enemy.PACK_MAGIC
	return Enemy.PACK_NORMAL

# Pack leaders re-roll at elevated rates so the pack-clustered system
# produces a visible amount of magic/rare leaders even at low tiers.
# A leader has a 30% (T1) → 80% (T5) chance of being modified. Within
# the modified pool, ~85% magic / ~15% rare.
func _roll_leader_pack_tier(branch_tier: int) -> int:
	var scale: float = pow(1.5, float(maxi(branch_tier - 1, 0)))
	var modified_chance: float = clampf(0.30 * scale, 0.0, 0.85)
	if rng.randf() >= modified_chance:
		return Enemy.PACK_NORMAL
	return Enemy.PACK_RARE if rng.randf() < 0.18 else Enemy.PACK_MAGIC

# Pick N distinct mods. Random sample without replacement so a rare
# can't get two copies of "Hasted." Returns array of mod dict refs.
func _pick_pack_mods(count: int) -> Array:
	if monster_mods.is_empty() or count <= 0:
		return []
	var pool: Array = monster_mods.duplicate()
	pool.shuffle()
	return pool.slice(0, mini(count, pool.size()))

# Apply a mod's stat / behavior payload to a freshly-spawned enemy.
# Operates BEFORE pack-tier hp/atk multipliers so the percentages
# compose cleanly. The mod's flavor_tags get pushed onto the enemy's
# defender-tag pipeline so existing combat hooks (vampiric leech etc)
# fire without per-mod special-casing.
func _apply_pack_mod(e: Enemy, mod: Dictionary) -> void:
	var atk_pct: float = float(mod.get("atk_pct", 0.0))
	var def_pct: float = float(mod.get("def_pct", 0.0))
	var hp_pct: float = float(mod.get("hp_pct", 0.0))
	if atk_pct != 0.0:
		e.atk = int(round(float(e.atk) * (1.0 + atk_pct / 100.0)))
	if def_pct != 0.0:
		e.defense = int(round(float(e.defense) * (1.0 + def_pct / 100.0)))
	if hp_pct != 0.0:
		e.max_hp = int(round(float(e.max_hp) * (1.0 + hp_pct / 100.0)))
		e.hp = e.max_hp
	var atk_speed_pct: float = float(mod.get("atk_speed_pct", 0.0))
	if atk_speed_pct != 0.0:
		# Same shape as bot's haste: shorten the attack interval.
		e.attack_interval = e.attack_interval / (1.0 + atk_speed_pct / 100.0)
	var move_speed_mult: float = float(mod.get("move_speed_mult", 1.0))
	if move_speed_mult != 1.0:
		e.move_speed *= move_speed_mult
	# hp_regen_per_sec: Actor doesn't tick its own regen (only Bot does),
	# so a regenerating monster mod would need an enemy regen tick path.
	# Stub for now — declared in monster_mods.json so the slot exists,
	# but functionally a no-op until an enemy regen ticker lands. TODO.
	for tag in mod.get("flavor_tags", []):
		e.add_pack_defense_tag(String(tag))

# Periodic wave spawn — every 6-10s, top up the floor's mob count
# back toward the floor's target density. Designed as a TOP-UP: only
# fires if the alive count has dropped meaningfully below the floor's
# initial density target. Prevents invincible-bot grinds from running
# forever (waves used to pile on top, so the floor never emptied).
# Combat pivot 2026-06-04.
func _tick_wave_spawns(delta: float) -> void:
	if not _floor_ready or not is_instance_valid(bot) or not bot.is_alive:
		return
	_wave_accum += delta
	if _wave_accum < _wave_interval:
		return
	_wave_accum = 0.0
	_wave_interval = 6.0 + rng.randf() * 4.0
	var alive: int = 0
	for e in enemies:
		if is_instance_valid(e) and e.is_alive:
			alive += 1
	# Don't refill above ~70% of the floor's target density — the
	# bot needs to be able to clear enough to reach the stairs. Without
	# this gate, an invincible/over-geared bot literally cannot finish
	# floors because waves spawn faster than they kill.
	var target: int = int(round(70.0 + float(current_floor) * 25.0))  # ~75% of target_total
	if alive >= target or alive >= _DENSITY_HARD_CAP:
		return
	var pool: Array = _build_enemy_pool()
	if pool.is_empty():
		return
	var n: int = rng.randi_range(_WAVE_MIN_MOBS, _WAVE_MAX_MOBS)
	n = mini(n, target - alive)
	for _i in n:
		var pick: String = String(pool[rng.randi_range(0, pool.size() - 1)])
		var cell: Vector2i = _random_walkable_cell_far_from_bot()
		_spawn_specific(pick, cell, Enemy.PACK_NORMAL)

# Burst event — every 30-50s, spawn a 12-18 mob MAGIC pack from one
# direction relative to the bot. No telegraph yet (Phase 4 polish);
# the cluster shape itself is the telegraph (mobs visibly stream in).
func _tick_burst_events(delta: float) -> void:
	if not _floor_ready or not is_instance_valid(bot) or not bot.is_alive:
		return
	_burst_accum += delta
	if _burst_accum < _burst_interval:
		return
	_burst_accum = 0.0
	_burst_interval = 30.0 + rng.randf() * 20.0
	var alive: int = 0
	for e in enemies:
		if is_instance_valid(e) and e.is_alive:
			alive += 1
	# Bursts skip if the floor's already populated — they're dramatic
	# events for a thinned floor, not an "even more mobs" multiplier.
	var burst_threshold: int = int(round(50.0 + float(current_floor) * 20.0))  # ~half of target
	if alive >= burst_threshold or alive >= _DENSITY_HARD_CAP:
		return
	var pool: Array = _build_enemy_pool()
	if pool.is_empty():
		return
	# Pick one cluster center far from the bot — packmates spawn within
	# _PACK_RADIUS so they read as a coherent burst.
	var pack_id: String = String(pool[rng.randi_range(0, pool.size() - 1)])
	var center: Vector2i = _random_walkable_cell_far_from_bot()
	var n: int = rng.randi_range(_BURST_MIN_MOBS, _BURST_MAX_MOBS)
	n = mini(n, _DENSITY_HARD_CAP - alive)
	# Leader rolls MAGIC tier so the burst has a visible elite.
	_spawn_specific(pack_id, center, Enemy.PACK_MAGIC)
	for i in range(n - 1):
		var member_cell: Vector2i = _walkable_cell_near(center, _PACK_RADIUS)
		_spawn_specific(pack_id, member_cell, Enemy.PACK_NORMAL)
	GrindLog.log_line("[burst] f=%d id=%s n=%d" % [current_floor, pack_id, n])

# Helper to rebuild the per-floor enemy pool — same logic as
# _spawn_enemies pool construction. Extracted so wave/burst can pull
# from the live biome roster without duplicating code.
func _build_enemy_pool() -> Array:
	var pool: Array = []
	if current_biome.is_empty():
		return pool
	var raw_pool: Variant = current_biome.get("enemy_pool", null)
	if raw_pool is Array:
		for entry in raw_pool:
			if entry is String:
				pool.append(entry)
			elif entry is Dictionary and entry.has("id"):
				pool.append(String(entry["id"]))
	return pool

# PoE-style pack-clustered spawn. Replaces uniform-random N-spawn so
# the floor reads as "groups of monsters" rather than thinly scattered
# individuals. Math: target_total = 90 + floor*30 (modifier-adjusted),
# split into packs of 6-12 same-id mobs. Each pack has 1 leader
# (rolls magic/rare at elevated rates) + 5-11 packmates (forced to
# normal so the leader stays the visual centerpiece).
const _PACK_SIZE_MIN := 6
const _PACK_SIZE_MAX := 12
const _PACK_RADIUS := 4

func _spawn_packs(pool: Array) -> void:
	if pool.is_empty():
		return
	var count_mult: float = RunModifiers.sum_effect(active_modifiers, "enemy_count_mult", 1.0)
	# Target total mobs for this floor. Combat-pivot 2026-06-04 — bumped
	# from 40+floor*20 (~60-160 mobs) to 90+floor*30 (~120-330 mobs) so
	# the autocast layer always has targets and the late-floor screen
	# reads VS-like. Capped at 350 to keep the actor-tick budget sane.
	var target_total: int = int(round((90.0 + float(current_floor) * 30.0) * count_mult))
	target_total = mini(target_total, 350)
	if target_total <= 0:
		return
	var src_tier: int = int(current_biome.get("tier", 1))
	var spawned: int = 0
	# Safety cap on pack iterations — if all packs come out small (rng
	# roll low end), don't loop forever trying to hit target_total.
	var max_iterations: int = 50
	while spawned < target_total and max_iterations > 0:
		max_iterations -= 1
		var pack_size: int = rng.randi_range(_PACK_SIZE_MIN, _PACK_SIZE_MAX)
		# Don't overshoot target by a full pack.
		var remaining: int = target_total - spawned
		if remaining < _PACK_SIZE_MIN:
			pack_size = remaining
		# Pack is uniform monster id — that's what makes a pack read
		# as a pack visually. Different packs roll different ids so
		# the floor still has variety.
		var pack_id: String = String(pool[rng.randi_range(0, pool.size() - 1)])
		var leader_cell: Vector2i = _random_walkable_cell_far_from_bot()
		var leader_tier: int = _roll_leader_pack_tier(src_tier)
		_spawn_specific(pack_id, leader_cell, leader_tier)
		spawned += 1
		# Spawn packmates clustered around the leader. Try cells within
		# radius first, fall back to random walkable if cluster is full.
		for j in range(pack_size - 1):
			if spawned >= target_total:
				break
			var member_cell: Vector2i = _walkable_cell_near(leader_cell, _PACK_RADIUS)
			if member_cell == leader_cell:
				member_cell = _random_walkable_cell_far_from_bot()
			_spawn_specific(pack_id, member_cell, Enemy.PACK_NORMAL)
			spawned += 1

# Find a walkable cell within `radius` of `center`. Returns center if
# no nearby cell is open (caller falls back to a global random pick).
func _walkable_cell_near(center: Vector2i, radius: int) -> Vector2i:
	# Try `tries` random offsets within the radius — bounded loop so a
	# tightly-packed cluster doesn't burn time.
	for _i in 16:
		var dx: int = rng.randi_range(-radius, radius)
		var dy: int = rng.randi_range(-radius, radius)
		if dx == 0 and dy == 0:
			continue
		var c: Vector2i = center + Vector2i(dx, dy)
		if c.y < 0 or c.y >= grid.size() or c.x < 0 or c.x >= grid[0].size():
			continue
		if grid[c.y][c.x] == C.T_FLOOR and c != bot.cell:
			return c
	return center
