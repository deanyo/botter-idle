extends Node2D

const C := preload("res://scripts/constants.gd")
const DungeonGen := preload("res://scripts/dungeon_generator.gd")
const Path := preload("res://scripts/pathfinding.gd")

signal floor_started(floor_num: int)
signal floor_cleared(floor_num: int)
signal run_ended(victory: bool, report: Dictionary)

const ENEMIES_PATH := "res://data/enemies.json"
const ITEMS_PATH := "res://data/items.json"
const ENEMY_TILE_DIR := "res://assets/tiles/enemies/"

var enemy_data: Dictionary = {}
var items_db: Dictionary = {}
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
var current_biome: Dictionary = {}
var ambient_modulate: CanvasModulate = null
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
const MAX_TICKS_WITHOUT_MOVE := 30
var chrome: HudChrome = null
var run_turn: int = 0

@onready var map_layer: Node2D = $MapLayer
@onready var actor_layer: Node2D = $ActorLayer
@onready var camera: Camera2D = $Camera

func _ready() -> void:
	rng.randomize()
	enemy_data = _load_json(ENEMIES_PATH)
	items_db = _load_items(ITEMS_PATH)
	# FlickerDriver animates every PointLight2D with a "flicker" meta dict.
	# Single shared driver keeps cost predictable.
	add_child(FlickerDriver.new())
	_start_run()

func _start_run() -> void:
	current_floor = 1
	loot_log.clear()
	kills.clear()
	journal.clear()
	run_plan = BiomeData.roll_run_plan(rng)
	if ambient_modulate == null:
		ambient_modulate = CanvasModulate.new()
		add_child(ambient_modulate)
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
	bot.apply_gear(items_db, save.get("equipped", {}))
	# Reset run-wide counters at run start
	run_kills = 0
	run_loot_picked = 0
	run_portals_entered = 0
	run_stalls = 0
	run_vaults_stamped = []
	run_biomes_visited = []
	GrindLog.log_line("[run] start hp=%d/%d level=%d gold=%d" % [bot.hp, bot.max_hp, bot.level, bot.gold])
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
	_stuck_ticks = 0
	_last_bot_cell = Vector2i(-99, -99)
	vault_spawn_overrides.clear()
	bot_interacting = false
	interact_target = null
	interact_timer = 0.0
	floor_start_tick = Engine.get_process_frames()
	_last_fog_cell = Vector2i(-99, -99)
	_fog_dirty = true
	_cached_world_lights_valid = false
	# HUD inventory snapshot is per-run; refresh once at floor build.
	_last_inventory_dirty = true
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
	var vault_themes: Array = current_biome.get("vault_themes", ["dungeon"])

	var seed_val: int = rng.randi()
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
	var data: Dictionary = gen.generate_themed(map_w, map_h, vault_themes, current_floor, layout_id, String(current_biome.get("id", "")))
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

	bot.terrain_grid = grid
	bot.place_at(data.spawn)
	_mark_room_visited_at(bot.cell)
	_center_camera_on_bot()
	# Phase 3: ambient decor scatter (5-15ms).
	await get_tree().process_frame
	if my_gen != _build_generation: return
	var t_decor: int = Time.get_ticks_usec()
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

	# Phase 4: enemy spawn (3-8ms).
	await get_tree().process_frame
	if my_gen != _build_generation: return
	var t_spawn: int = Time.get_ticks_usec()
	_spawn_enemies()
	t_spawn = Time.get_ticks_usec() - t_spawn
	_update_biome_hud()
	floor_starting_hp = bot.hp
	t_total = Time.get_ticks_usec() - t_total
	_floor_ready = true
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
			"xp": chrome.lbl_level.text if (chrome and is_instance_valid(chrome.lbl_level)) else "",
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

var _hud_full_refresh_accum: float = 0.0
var _last_inventory_dirty: bool = true
var _last_equipped_hash: int = 0
# Cached inventory snapshot. Save-state reads from disk + JSON parse —
# we should NOT call SaveState.load_state() every frame. dropped_items
# tracks pickups during this run, and the floor's _build_floor seeds
# the cache from disk once.
var _hud_inv_cache: Array = []
var _hud_inv_cache_size_at_last_render: int = -1

func invalidate_hud_inventory() -> void:
	_last_inventory_dirty = true

func _update_biome_hud() -> void:
	_ensure_hud()
	var biome_id: String = String(current_biome.get("id", "?"))
	var branch: String = BiomeData.branch_depth_label(run_plan, current_floor)
	var place_str := "%s  (%s)" % [branch, biome_id]
	# Stats label updates internally diff each label — cheap when steady.
	chrome.update_stats(bot, place_str, run_turn)
	_hud_full_refresh_accum += get_process_delta_time()
	var equipped_hash: int = (bot.equipped.hash() if is_instance_valid(bot) else 0)
	var eq_changed: bool = equipped_hash != _last_equipped_hash
	if eq_changed:
		chrome.update_equipped(bot.equipped if is_instance_valid(bot) else {}, items_db)
		_last_equipped_hash = equipped_hash
	if _last_inventory_dirty:
		# Lazy reload from disk only when something invalidated it. This
		# is the slow path — file open + JSON parse + migrate.
		_hud_inv_cache = SaveState.load_state().get("inventory", [])
		chrome.update_inventory(_hud_inv_cache, items_db)
		_last_inventory_dirty = false
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
	var is_boss_floor: bool = current_floor >= C.BOSS_FLOOR
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
		for id in enemy_data.keys():
			if enemy_data[id].boss:
				_spawn_specific(id, _pick_boss_room())
				break
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

	var count: int = 4 + current_floor * 2
	for i in count:
		var id: String = pool[rng.randi_range(0, pool.size() - 1)]
		var cell: Vector2i = _random_walkable_cell_far_from_bot()
		_spawn_specific(id, cell)

	var chest_count: int = 1 + (1 if rng.randf() < 0.5 else 0)
	if _is_miniboss_floor(current_floor):
		chest_count = 2
	if is_boss_floor:
		chest_count = 3
	if portal_active:
		chest_count += 1 + portal_loot_bias
	for i in chest_count:
		var chest_cell: Vector2i = _random_walkable_cell_far_from_bot()
		var bias: int = 0
		if rng.randf() < 0.2:
			bias = 1
		if rng.randf() < 0.05 or is_boss_floor:
			bias = 2
		if portal_active:
			bias = max(bias, portal_loot_bias)
		_spawn_chest(chest_cell, rng.randi_range(1, 3), bias)

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
	if not is_boss_floor and not portal_active and current_floor >= 2 and current_floor <= C.FLOORS_PER_RUN - 1:
		if rng.randf() < 0.15:
			var portal_cell: Vector2i = _random_walkable_cell_far_from_bot()
			_spawn_portal(portal_cell)

func _is_miniboss_floor(f: int) -> bool:
	return f != C.BOSS_FLOOR and f in C.MINIBOSS_FLOORS

func _is_final_boss_floor() -> bool:
	return current_floor >= C.BOSS_FLOOR

func _log(msg: String) -> void:
	if not journal.is_empty():
		journal.back().events.append(msg)
	if chrome != null:
		chrome.push_log(msg)

func _pick_miniboss_id(pool: Array) -> String:
	if pool.is_empty():
		return "rat"
	var ranked: Array = pool.duplicate()
	ranked.sort_custom(func(a, b): return float(enemy_data[a].hp) > float(enemy_data[b].hp))
	return ranked[0]

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
	e.max_hp = int(round(float(def.hp) * floor_mult * 1.8))
	e.atk = int(round(float(def.atk) * floor_mult * 1.4))
	e.defense = int(round(float(def.def) * floor_mult * 1.3))
	e.hp = e.max_hp
	e.move_speed = float(def.speed) * 4.0
	var tex: Texture2D = load(ENEMY_TILE_DIR + def.tile)
	if tex:
		e.set_texture(tex)
		# Miniboss visual = base creature scale x 1.4, capped at 2.5.
		var base_scale: float = float(def.get("visual_scale", 1.0))
		var anchor: String = String(def.get("visual_anchor", "centre"))
		e.apply_visual_scale(base_scale * 1.4, anchor, 2)
		if e.sprite:
			e.sprite.modulate = Color(1.2, 0.85, 0.85)
			e.fx = SpriteFX.new(e.sprite)
		# Miniboss inherits creature's light_spec if defined.
		var ml_spec: String = String(def.get("light_spec", ""))
		if ml_spec != "":
			LightSpec.attach(e, ml_spec)
	e.place_at(at_cell)
	# Stagger initial repath so a freshly-spawned horde doesn't all repath
	# on the same frame. Spread across the full REPATH_INTERVAL.
	e.repath_timer = rng.randf_range(0.0, Enemy.REPATH_INTERVAL)
	e.died.connect(_on_enemy_died)
	enemies.append(e)

func _spawn_specific(id: String, at_cell: Vector2i) -> void:
	if not enemy_data.has(id):
		return
	var def: Dictionary = enemy_data[id]
	var e := Enemy.new()
	actor_layer.add_child(e)
	var is_champion: bool = (not def.boss) and rng.randf() < 0.012
	e.enemy_id = id
	e.display_name = ("Champion " + str(def.name)) if is_champion else def.name
	e.xp_reward = int(def.xp) * (3 if is_champion else 1)
	e.is_boss = bool(def.boss)
	var floor_mult: float = pow(1.10, current_floor - 1)
	var champ_mult: float = 1.5 if is_champion else 1.0
	e.max_hp = int(round(float(def.hp) * floor_mult * champ_mult))
	e.atk = int(round(float(def.atk) * floor_mult * champ_mult))
	e.defense = int(round(float(def.def) * floor_mult * (1.2 if is_champion else 1.0)))
	e.hp = e.max_hp
	e.move_speed = float(def.speed) * 4.0
	var tex: Texture2D = load(ENEMY_TILE_DIR + def.tile)
	if tex:
		e.set_texture(tex)
		# Data-driven visual scale. Champion variants stack on top of base.
		var base_scale: float = float(def.get("visual_scale", 1.0))
		var anchor: String = String(def.get("visual_anchor", "centre"))
		var vz: int = int(def.get("visual_z", 1 if base_scale > 1.0 else 0))
		var champ_visual: float = 1.25 if is_champion else 1.0
		e.apply_visual_scale(base_scale * champ_visual, anchor, vz)
		if is_champion and e.sprite:
			e.sprite.modulate = Color(1.0, 0.85, 1.3)
			e.fx = SpriteFX.new(e.sprite)
			LightSpec.attach(e, "sigil")
		# Per-creature emitter: fire/ice creatures emit their own light.
		var enemy_light_spec: String = String(def.get("light_spec", ""))
		if enemy_light_spec != "":
			LightSpec.attach(e, enemy_light_spec)
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
	var gold_drop: int = rng.randi_range(1, 5) + current_floor
	bot.gold += gold_drop
	kills[e.enemy_id] = kills.get(e.enemy_id, 0) + 1
	loot_log.append("%s slain (+%d gold, +%d xp)" % [e.display_name, gold_drop, e.xp_reward])
	if e.is_boss:
		_log("Slew %s. (+%d gold, +%d xp)" % [e.display_name, gold_drop, e.xp_reward])
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
	if e.is_boss and current_floor >= C.BOSS_FLOOR:
		_end_run(true)
		return

func _maybe_drop_item(e: Enemy) -> void:
	var roll: float = rng.randf()
	var threshold: float = 0.15
	if e.is_miniboss:
		threshold = 1.0
	elif e.is_boss:
		threshold = 1.0
	if roll > threshold:
		return
	var rarity: String = _roll_rarity(e.is_boss or e.is_miniboss)
	var pool: Array = []
	for id in items_db.keys():
		if items_db[id].rarity == rarity:
			pool.append(id)
	if pool.is_empty():
		return
	var picked: String = pool[rng.randi_range(0, pool.size() - 1)]
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
	if String(base.get("rarity", "")) == "legendary":
		var slot: String = String(base.get("slot", "armor"))
		var artefact: String = ArtefactPool.pick_for_slot(slot, rng)
		if artefact != "":
			inst["tile_override"] = "artefacts/" + artefact
	return inst

func _gen_instance_id() -> String:
	return "%d_%d" % [Time.get_unix_time_from_system(), rng.randi()]

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
		var pool: Array = []
		for id in items_db.keys():
			if items_db[id].rarity == rarity:
				pool.append(id)
		if pool.is_empty():
			continue
		var picked: String = pool[rng.randi_range(0, pool.size() - 1)]
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
	_log("Received %s — %s" % [bname, bdesc])
	# Magic shimmer at altar position for divine-grant flair.
	if is_instance_valid(altar):
		var pos: Vector2 = altar.position + Vector2(C.TILE_SIZE * 0.5, C.TILE_SIZE * 0.5)
		Effects.magic_shimmer(actor_layer, pos)

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

func _roll_rarity(is_boss: bool) -> String:
	if is_boss:
		var boss_roll: float = rng.randf()
		if boss_roll < 0.5: return "legendary"
		if boss_roll < 0.85: return "epic"
		return "rare"
	var floor_bonus: float = float(current_floor - 1) * 0.05
	var blessing_bonus: float = bot.loot_rarity_bonus / 100.0 if is_instance_valid(bot) else 0.0
	var r: float = rng.randf() - floor_bonus - blessing_bonus
	if r < 0.02: return "legendary"
	if r < 0.10: return "epic"
	if r < 0.25: return "rare"
	if r < 0.55: return "uncommon"
	return "common"

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
	_update_biome_hud()
	PerfMon.end(PerfMon.TAG_FRAME)
	if PerfMon.tick_frame():
		var suffix: String = PerfMon.format_log_suffix()
		if suffix != "":
			GrindLog.log_line("[perf] " + suffix)

const AGGRO_ENGAGE_RANGE := 5

var _lava_tick_accum: float = 0.0

# Bot AI tuning constants. AGGRO_DISTANCE caps how far the bot will actively
# pursue an enemy. Beyond this, the bot ignores them and keeps exploring;
# adjacency check at the top of the tick still catches drive-by attacks.
const AGGRO_DISTANCE := 8
const RETREAT_HP_PCT := 0.30

func _tick_bot(delta: float) -> void:
	_mark_room_visited_at(bot.cell)
	_refresh_fog()
	_check_stuck()
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
	# Standing on stairs and no enemies nearby? Descend immediately.
	if bot.cell == stairs_cell and _nearest_enemy() == null:
		_descend()
		return
	if fog_overlay:
		PerfMon.begin(PerfMon.TAG_LIGHTS)
		fog_overlay.update_lights(_gather_lights(), delta)
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
	if nearby_enemy != null and _chebyshev(bot.cell, nearby_enemy.cell) <= AGGRO_DISTANCE:
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
var _stuck_ticks: int = 0
const STUCK_THRESHOLD := 120
const STUCK_RECOVERY_THRESHOLD := 360
var _stall_snapshot_taken: bool = false

func _check_stuck() -> void:
	if bot.cell == _last_bot_cell:
		_stuck_ticks += 1
		if _stuck_ticks == STUCK_THRESHOLD:
			floor_stalls += 1
			GrindLog.log_line("[stall] f=%d ticks=%d bot=%s target=%s kind=%s stairs=%s enemies=%d interactables=%d unvisited_rooms=%d alive_adj=%d" % [
				current_floor, _stuck_ticks, str(bot.cell), str(bot_target_cell), bot_target_kind,
				str(stairs_cell), enemies.size(), interactables.size(),
				_count_unvisited_rooms(), _count_alive_adjacent_enemies(),
			])
		if _stuck_ticks == STUCK_RECOVERY_THRESHOLD:
			if not _stall_snapshot_taken:
				_dump_stall_snapshot()
				_stall_snapshot_taken = true
			floor_hard_recoveries += 1
			GrindLog.log_line("[stall] HARD-RECOVERY f=%d teleport from=%s to=%s" % [current_floor, str(bot.cell), str(stairs_cell)])
			if stairs_cell.x >= 0 and stairs_cell.y >= 0 and stairs_cell.y < grid.size() and stairs_cell.x < grid[0].size():
				bot.place_at(stairs_cell)
				_descend()
			_stuck_ticks = 0
	else:
		_stuck_ticks = 0
	_last_bot_cell = bot.cell

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
	var display_name: String = AffixSystem.format_item_name(String(item.name), inst.get("affixes", []))
	floor_loot_picked += 1
	dropped_items.append(inst)
	loot_log.append("Looted: [%s] %s" % [item.rarity, display_name])
	_log("Found: %s [%s]" % [display_name, item.rarity])
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

func _on_chest_opened(chest: Chest, n: int, bias: int) -> void:
	floor_chests_opened += 1
	var chest_world: Vector2 = chest.position + Vector2(C.TILE_SIZE * 0.5, C.TILE_SIZE * 0.5)
	for i in n:
		var rarity: String = _roll_rarity_with_bias(bias)
		var pool: Array = []
		for id in items_db.keys():
			if items_db[id].rarity == rarity:
				pool.append(id)
		if pool.is_empty():
			continue
		var picked: String = pool[rng.randi_range(0, pool.size() - 1)]
		var inst: Dictionary = _create_item_instance(picked)
		var spawn_cell: Vector2i = _adjacent_walkable_cell(chest.cell, i + 1)
		var drop := _spawn_loot_drop_get(inst, spawn_cell)
		if drop:
			drop.arc_from(chest_world, 0.45 + i * 0.05)
	interactables.erase(chest)
	_log("Opened a chest!")
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
	var floor_bonus: float = float(current_floor - 1) * 0.05
	var bias_bonus: float = float(bias) * 0.10
	var r: float = rng.randf() - floor_bonus - bias_bonus
	if r < 0.02: return "legendary"
	if r < 0.10: return "epic"
	if r < 0.25: return "rare"
	if r < 0.55: return "uncommon"
	return "common"

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
	# Cap A* paths per frame so a horde repath doesn't burn 24*1ms in one
	# tick. Enemies that miss this frame's slot keep their old path
	# (still animates) and try again next frame — at 60Hz the player
	# never sees the difference.
	var repaths_this_frame: int = 0
	for e in enemies:
		if not is_instance_valid(e) or not e.is_alive:
			continue
		var dist: int = _chebyshev(e.cell, bot.cell)
		if dist > e.aggro_range:
			continue
		if dist <= 1:
			e.path = PackedVector2Array()
			e.attempt_attack(bot, delta)
			if not bot.is_alive:
				_log("Slain by %s on floor %d." % [e.display_name, current_floor])
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
	if current_floor >= C.FLOORS_PER_RUN:
		_end_run(true)
		return
	current_floor += 1
	_build_floor()

func _end_run(victory: bool) -> void:
	var save: Dictionary = SaveState.load_state()
	save.gold = bot.gold
	save.level = bot.level
	save.xp = bot.xp
	var inv: Array = save.get("inventory", [])
	var kept: Array = []
	if victory:
		kept = dropped_items.duplicate(true)
	else:
		for it in dropped_items:
			if rng.randf() < 0.5:
				kept.append(it.duplicate(true))
	for it in kept:
		inv.append(it)
	save.inventory = inv
	save.runs_completed = int(save.get("runs_completed", 0)) + 1
	save.highest_floor = maxi(int(save.get("highest_floor", 0)), current_floor)
	SaveState.save_state(save)

	var report: Dictionary = {
		"victory": victory,
		"floor": current_floor,
		"level": bot.level,
		"xp": bot.xp,
		"gold": bot.gold,
		"hp": bot.hp,
		"max_hp": bot.max_hp,
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
	# fallback: any walkable cell
	for y in grid.size():
		for x in grid[0].size():
			if grid[y][x] == C.T_FLOOR and Vector2i(x, y) != bot.cell:
				return Vector2i(x, y)
	return bot.cell

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
	# Returns [{cell, position, radius_px, intensity, color}] for every
	# world light source. Each source feeds both LoS computation and the
	# fog shader tint. Bot is appended separately by callers.
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
		})
	_cached_world_lights = out
	_cached_world_lights_valid = true
	return out

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
	var out: Array = []
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
		out.append({
			"position": src.position,
			"radius": src.radius_px,
			"intensity": src.intensity,
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
