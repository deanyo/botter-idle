class_name DebugDump
extends RefCounted

# Floor-dump dev-tool surface. Extracted from dungeon.gd 2026-06-09 as
# the third sub-system in the dungeon.gd god-class split (audit Tier 3,
# follow-up to LootFactory + HUDInventoryController). Pure static utility:
# caller passes the dungeon node, methods read its fields directly. No
# per-instance state, no node graph.
#
# This is a developer dump triggered from the in-game debug HUD button
# (chrome.debug_dump_requested). Never runs in a player session — there's
# no shipping surface here. Behavior is a strict copy of the dungeon.gd
# functions it replaces; any tuning belongs in a separate beat.

const C := preload("res://scripts/constants.gd")

# Convert renderer marks (Vector2i cells) to JSON-friendly [x,y] arrays.
# Used by build_floor_report and by dungeon's screenshot manifest, which
# is why it lives here as a generic helper rather than inline.
static func serialize_marks(marks: Array) -> Array:
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

# Flood-fill the floor cells to count regions + find the bounding box
# of the largest one. Mirrors the bad-floor detector heuristics. Used
# by build_floor_report so the dump tells me at a glance whether
# generation collapsed into a single tiny square.
static func analyze_floor_regions(grid: Array, w: int, h: int) -> Dictionary:
	if w == 0 or h == 0:
		return {}
	var visited: Array = []
	visited.resize(h)
	for y in h:
		var row: Array = []
		row.resize(w)
		for x in w:
			row[x] = false
		visited[y] = row
	var regions: Array = []
	var minx: int = w
	var miny: int = h
	var maxx: int = -1
	var maxy: int = -1
	var total_floor: int = 0
	for y in h:
		for x in w:
			if grid[y][x] != C.T_FLOOR and grid[y][x] != C.T_STAIRS_DOWN and grid[y][x] != C.T_DOOR:
				continue
			total_floor += 1
			if visited[y][x]:
				continue
			# BFS.
			var size: int = 0
			var stack: Array = [Vector2i(x, y)]
			visited[y][x] = true
			while not stack.is_empty():
				var c: Vector2i = stack.pop_back()
				size += 1
				if c.x < minx: minx = c.x
				if c.y < miny: miny = c.y
				if c.x > maxx: maxx = c.x
				if c.y > maxy: maxy = c.y
				for d in [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]:
					var n: Vector2i = c + d
					if n.x < 0 or n.y < 0 or n.x >= w or n.y >= h:
						continue
					if visited[n.y][n.x]:
						continue
					var t: int = grid[n.y][n.x]
					if t == C.T_FLOOR or t == C.T_STAIRS_DOWN or t == C.T_DOOR:
						visited[n.y][n.x] = true
						stack.append(n)
			regions.append(size)
	regions.sort()
	regions.reverse()
	var largest: int = regions[0] if not regions.is_empty() else 0
	var orphans: int = total_floor - largest
	var bad: bool = false
	var reasons: Array = []
	if total_floor < 250:
		bad = true; reasons.append("floor_count<250")
	if largest < 400:
		bad = true; reasons.append("largest_region<400")
	if maxx >= 0 and (maxx - minx) * (maxy - miny) < 400:
		bad = true; reasons.append("bbox<400")
	if orphans > 60:
		bad = true; reasons.append("orphan_cells>60")
	return {
		"region_count": regions.size(),
		"region_sizes_top5": regions.slice(0, mini(5, regions.size())),
		"largest_region": largest,
		"orphan_cells": orphans,
		"bbox": [minx, miny, maxx, maxy] if maxx >= 0 else [],
		"is_bad_floor": bad,
		"bad_reasons": reasons,
	}

# Build a comprehensive JSON-serializable floor report for triage.
# Wired to a "Dump floor" button on the in-game debug HUD so the player
# can paste a complete state snapshot into a bug report:
#   - every enemy with cell + hp
#   - every interactable with cell + kind + extras (chest bias,
#     altar god, portal kind, loot rarity)
#   - bot location + stats + equipped slot summary
#   - HUD strings as visible to the player
#   - active modifiers, loaded textures
#   - first 24 rows of the grid as ASCII so a human can paste it
static func build_floor_report(dungeon: Node) -> Dictionary:
	var grid: Array = dungeon.grid
	var rooms: Array = dungeon.rooms
	var enemies: Array = dungeon.enemies
	var interactables: Array = dungeon.interactables
	var current_biome: Dictionary = dungeon.current_biome
	var current_floor: int = dungeon.current_floor
	var run_plan: Array = dungeon.run_plan
	var active_modifiers: Array = dungeon.active_modifiers
	var vault_decor_sprites: Array = dungeon.vault_decor_sprites
	var ambient_decor_nodes: Array = dungeon.ambient_decor_nodes
	var run_vaults_stamped: Array = dungeon.run_vaults_stamped
	var floor_placed_vaults: Array = dungeon.floor_placed_vaults
	var stairs_cell: Vector2i = dungeon.stairs_cell
	var bot = dungeon.bot
	var chrome = dungeon.chrome
	var rng: RandomNumberGenerator = dungeon.rng
	var current_renderer = dungeon.current_renderer

	var w: int = grid[0].size() if grid.size() > 0 else 0
	var h: int = grid.size()
	# Cell counts.
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
	# Region/bbox analysis — the same metrics the generator's bad-floor
	# detector uses. Helps me spot "floor came out as one tiny square"
	# without needing the PNG.
	var region_data: Dictionary = analyze_floor_regions(grid, w, h)
	# Rooms.
	var room_list: Array = []
	for r in rooms:
		room_list.append({
			"x": int(r.position.x), "y": int(r.position.y),
			"w": int(r.size.x), "h": int(r.size.y),
		})
	# Enemies.
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
		})
	# Interactables.
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
			"extra": extra,
		})
	# Loaded biome textures (resource paths) — helps me check "did the
	# right floor pool load" without opening Godot.
	var floor_primary: Array = BiomeData.load_floor_primary(current_biome)
	var floor_primary_paths: Array = []
	for tex in floor_primary:
		if tex and tex.resource_path:
			floor_primary_paths.append(String(tex.resource_path))
	var wall_primary: Array = BiomeData.load_wall_primary(current_biome)
	var wall_primary_paths: Array = []
	for tex in wall_primary:
		if tex and tex.resource_path:
			wall_primary_paths.append(String(tex.resource_path))
	# Bot summary.
	var bot_summary: Dictionary = {}
	if is_instance_valid(bot):
		var equipped_summary: Dictionary = {}
		for slot in bot.equipped.keys():
			var inst: Variant = bot.equipped[slot]
			if typeof(inst) == TYPE_DICTIONARY:
				equipped_summary[String(slot)] = String(inst.get("base_id", ""))
		bot_summary = {
			"cell": [int(bot.cell.x), int(bot.cell.y)],
			"hp": int(bot.hp), "max_hp": int(bot.max_hp),
			"atk": int(bot.atk), "def": int(bot.defense),
			"level": int(bot.level), "xp": int(bot.xp), "gold": int(bot.gold),
			"species": String(bot.species_id) if "species_id" in bot else "",
			"equipped": equipped_summary,
		}
	# HUD strings as visible to the player right now. Place dropped from
	# HUD header 2026-06-06 (lives in StatPanel Misc section now).
	var hud_strings: Dictionary = {}
	if chrome != null and is_instance_valid(chrome):
		hud_strings = {
			"name": chrome.lbl_name.text if is_instance_valid(chrome.lbl_name) else "",
			"hp": chrome.lbl_hp.text if is_instance_valid(chrome.lbl_hp) else "",
		}
	# ASCII map — first chars of each tile across the whole floor so I
	# can eyeball it without re-rendering. `.` floor `#` wall `+` door
	# `>` stairs `~` water `=` lava `*` ice `B` bot `e` enemy `?` else.
	var ascii_rows: Array = []
	var bot_cell_xy: Vector2i = bot.cell if is_instance_valid(bot) else Vector2i(-1, -1)
	var enemy_cell_set: Dictionary = {}
	for e in enemies:
		if is_instance_valid(e):
			enemy_cell_set[e.cell] = true
	for y in h:
		var row: PackedStringArray = []
		for x in w:
			var c := Vector2i(x, y)
			if c == bot_cell_xy:
				row.append("B")
				continue
			if enemy_cell_set.has(c):
				row.append("e")
				continue
			match grid[y][x]:
				C.T_FLOOR: row.append(".")
				C.T_WALL: row.append("#")
				C.T_DOOR: row.append("+")
				C.T_STAIRS_DOWN: row.append(">")
				C.T_WATER: row.append("~")
				C.T_LAVA: row.append("=")
				C.T_ICE: row.append("*")
				_: row.append("?")
		ascii_rows.append("".join(row))
	# Final payload.
	return {
		"timestamp_unix": int(Time.get_unix_time_from_system()),
		"timestamp_msec": Time.get_ticks_msec(),
		"version": "floor_report_v1",
		"rng_seed": int(rng.seed),
		"run_plan": run_plan,
		"active_modifiers": active_modifiers,
		"resolved_biome": {
			"id": String(current_biome.get("id", "?")),
			"display_name": String(current_biome.get("display_name", "")),
			"tier": int(current_biome.get("tier", 0)),
			"layout": String(current_biome.get("layout", "")),
			"layouts_pool": current_biome.get("layouts", []),
			"vault_themes": current_biome.get("vault_themes", []),
			"map_size": current_biome.get("map_size", []),
			"modulate": current_biome.get("modulate", []),
			"darkness": float(current_biome.get("darkness", 0.0)),
			"liquid_type": String(current_biome.get("liquid_type", "")),
			"enemy_pool": current_biome.get("enemy_pool", []),
			"boss_id": String(current_biome.get("boss_id", "")),
		},
		"floor": {
			"number": current_floor,
			"branch_label": BiomeData.branch_depth_label(run_plan, current_floor),
			"width": w, "height": h,
			"floor_cells": floor_count,
			"wall_cells": wall_count,
			"door_cells": door_count,
			"stair_cells": stair_count,
			"terrain_cells": {"lava": lava_count, "water": water_count, "ice": ice_count},
			"region_count": region_data.get("region_count", 0),
			"largest_region": region_data.get("largest_region", 0),
			"bbox": region_data.get("bbox", []),
			"orphan_cells": region_data.get("orphan_cells", 0),
			"is_bad_floor": region_data.get("is_bad_floor", false),
			"bad_reasons": region_data.get("bad_reasons", []),
			"rooms": room_list,
			"spawn_cell": [int(bot.cell.x), int(bot.cell.y)] if is_instance_valid(bot) else [],
			"stairs_cell": [int(stairs_cell.x), int(stairs_cell.y)],
			"placed_vaults_this_floor": floor_placed_vaults,
			"placed_vaults_this_run": run_vaults_stamped,
		},
		"render_textures": {
			"floor_primary": floor_primary_paths,
			"wall_primary": wall_primary_paths,
		},
		"entities": {
			"enemies": enemy_list,
			"enemy_count": enemy_list.size(),
			"interactables": inter_list,
			"interactable_count": inter_list.size(),
			"vault_decor_sprite_count": vault_decor_sprites.size(),
			"ambient_decor_node_count": ambient_decor_nodes.size(),
			"sigils_stamped": serialize_marks(current_renderer.sigil_marks if current_renderer and "sigil_marks" in current_renderer else []),
			"decor_marks": serialize_marks(current_renderer.decor_marks if current_renderer and "decor_marks" in current_renderer else []),
		},
		"bot": bot_summary,
		"hud": hud_strings,
		"ascii_map": ascii_rows,
	}

# Wired to chrome.debug_dump_requested — builds the full floor report,
# saves to user://floor_dump_<unix>.json, copies the JSON to the
# clipboard, prints to console, and updates the HUD with a confirmation.
# 2026-06-05.
static func dump_and_save(dungeon: Node) -> void:
	var report: Dictionary = build_floor_report(dungeon)
	var ts: int = int(Time.get_unix_time_from_system())
	var path := "user://floor_dump_%d.json" % ts
	var text: String = JSON.stringify(report, "  ")
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(text)
		f.close()
	DisplayServer.clipboard_set(text)
	var fs_path: String = ProjectSettings.globalize_path(path)
	print("[floor-dump] saved=%s clipboard=%d chars" % [fs_path, text.length()])
	GrindLog.log_line("[floor-dump] saved=%s" % fs_path)
	var chrome = dungeon.chrome
	if chrome != null and is_instance_valid(chrome):
		chrome.flash_debug_dump_status("Copied %d chars · %s" % [text.length(), fs_path])
