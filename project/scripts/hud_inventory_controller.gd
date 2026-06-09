class_name HUDInventoryController
extends RefCounted

# Live HUD inventory + auto-salvage + drag-drop equip surface. Extracted
# from dungeon.gd 2026-06-09 as the second sub-system in the dungeon.gd
# god-class split (audit Tier 3, follow-up to LootFactory). Owns the
# Base + per-floor segment list, the flat _hud_inv_cache mirror used at
# save time, and per-slot equip cooldowns.
#
# RefCounted helper held by Dungeon as a field. Constructor takes refs
# to the bot, items_db, and the HudChrome the dungeon already owns.
# Methods that touch run-scoped state (current_floor) take it as an
# explicit arg so the controller never reads back into the dungeon.
#
# Behavior is a strict copy of the dungeon.gd functions it replaces;
# any tuning/balance changes belong in a separate beat. Two load-bearing
# guards survive the move unchanged:
#   * Chest-loot-loss fix (commit f80376b) — flush_pending_drops folds
#     in-flight LootDrops into the active segment before serialization.
#   * Click-duplication guard — instance_at_segment_idx + the prev /
#     now instance_id snapshots in every equip path detect a true no-op
#     vs a successful equip-into-empty-slot.

const EQUIP_COOLDOWN_SECONDS := 30.0

# Auto-salvage skips the species starter pair so a fresh-save bot
# never sells out of its starter weapons before reaching the first
# chest. Same const value as the dungeon.gd predecessor.
const STARTER_IDS := ["rusty_dagger", "tattered_hide"]

var _bot: Node = null
var _items_db: Dictionary = {}
var _chrome: Object = null
# Owner used for player-facing log lines. Dungeon implements `_log` and
# routes it through GrindLog + the HUD log feed. Kept as a Callable so
# the controller doesn't depend on the dungeon's full API.
var _log_cb: Callable = Callable()
# Drop-folding pulls live LootDrops from the dungeon's authoritative
# loot_drops + dropped_items + interactables arrays. Kept as Callables
# so the controller doesn't hold direct references to the dungeon's
# arrays (avoids cycle hazards on RefCounted teardown).
var _pending_drops_provider: Callable = Callable()
var _on_drop_folded: Callable = Callable()

# Inventory presented to the player. Segmented so the HUD can render a
# Base section + one section per floor that produced loot. Each segment
# is {header: String, items: Array[Dictionary]}. Mutating the items
# array (equip / loot) updates the HUD next frame; segments are never
# collapsed during a run so the player can see "what came from where"
# at a glance.
var loot_segments: Array = []
var current_floor_segment_index: int = -1
# Mirror used at run end to compute the flat saved inventory. Equals
# the concatenation of every segment's items, in order.
var hud_inv_cache: Array = []
var hud_inventory_seeded: bool = false
# Per-slot equip cooldowns in seconds. Decremented every _process tick.
var slot_cooldowns: Dictionary = {}

# Inventory cap drives auto-salvage when the bag fills up. Run-cached so
# the per-pickup check doesn't re-read disk. run_salvaged_* track the
# stats reported in the run summary.
var inventory_cap: int = 50
var run_salvaged_count: int = 0
var run_salvaged_gold: int = 0
# Auto-salvage runs deferred (floor end + run end) so each individual
# pickup never pays for the segment-shrink HUD rebuild. The previous
# inline call ran on every pickup once cap was hit, which was the
# loot-pickup stutter the user reported.
var pending_salvage_check: bool = false


func _init(bot: Node, items_db: Dictionary, chrome: Object) -> void:
	_bot = bot
	_items_db = items_db
	_chrome = chrome


# Re-bind dependencies. The dungeon constructs the controller before
# `bot` exists in some paths (deferred _ready) so it can reseat after
# the bot/chrome are created.
func bind(bot: Node, items_db: Dictionary, chrome: Object) -> void:
	_bot = bot
	_items_db = items_db
	_chrome = chrome


func set_log_callback(cb: Callable) -> void:
	_log_cb = cb


func set_pending_drops_provider(provider: Callable, on_folded: Callable) -> void:
	_pending_drops_provider = provider
	_on_drop_folded = on_folded


func _log(msg: String, tag: String = "combat") -> void:
	if _log_cb.is_valid():
		_log_cb.call(msg, tag)


# Run start: seed the live inventory with the player's stash. The HUD
# renders this as a "Base" section; loot picked up this run appends as
# Floor-N sections below it.
func init_run(save: Dictionary) -> void:
	inventory_cap = int(save.get("inventory_cap", 50)) + int(BotUpgrades.total_for_stat(save, "inventory_cap"))
	run_salvaged_count = 0
	run_salvaged_gold = 0
	loot_segments.clear()
	loot_segments.append({"header": "Base", "items": save.get("inventory", []).duplicate(true)})
	current_floor_segment_index = -1
	slot_cooldowns.clear()
	hud_inventory_seeded = false
	pending_salvage_check = false
	_rebuild_inv_cache()


func clear_current_floor_segment() -> void:
	current_floor_segment_index = -1


func ensure_current_floor_segment(current_floor: int) -> void:
	if current_floor_segment_index >= 0 and current_floor_segment_index < loot_segments.size():
		return
	loot_segments.append({"header": "Floor %d" % current_floor, "items": []})
	current_floor_segment_index = loot_segments.size() - 1


func _rebuild_inv_cache() -> void:
	# Flat mirror of every segment's items, in render order. Used at run
	# end to write SaveState.inventory.
	hud_inv_cache.clear()
	for seg in loot_segments:
		for inst in seg.get("items", []):
			hud_inv_cache.append(inst)


func push_inventory_to_hud() -> void:
	if _chrome != null and is_instance_valid(_chrome):
		_chrome.update_inventory_segments(loot_segments, _items_db, slot_cooldowns)


# Pulled from _update_biome_hud — first tick after _ensure_hud, push
# the seeded inventory exactly once so the bag renders the Base
# segment before any loot drops.
func first_tick_seed() -> void:
	if hud_inventory_seeded:
		return
	push_inventory_to_hud()
	hud_inventory_seeded = true


# Append `inst` to the active floor segment if one exists, else
# segment 0 (Base). Used by mid-run unequip + drag-drop displaced
# items. Keeps newly-displaced gear discoverable on the current
# floor instead of polluting the base inventory.
func append_to_active_segment(inst: Dictionary) -> void:
	if loot_segments.is_empty():
		return
	var idx: int = current_floor_segment_index if (current_floor_segment_index >= 0 and current_floor_segment_index < loot_segments.size()) else 0
	loot_segments[idx]["items"].append(inst)


# Player-initiated equip from the HUD inventory. Per-slot cooldown stops
# the player from juggling identical items every tick to game positioning.
# Returns true if the equip happened.
# Identity probe used by the HUD to verify a click hasn't drifted to
# a different item between rebuilds. Returns the instance_id at
# (seg_idx, item_idx), or "" if out-of-range. UI polish 2026-06-04.
func instance_at_segment_idx(seg_idx: int, item_idx: int) -> String:
	if seg_idx < 0 or seg_idx >= loot_segments.size():
		return ""
	var items: Array = loot_segments[seg_idx].get("items", [])
	if item_idx < 0 or item_idx >= items.size():
		return ""
	var inst: Variant = items[item_idx]
	if typeof(inst) != TYPE_DICTIONARY:
		return ""
	return String(inst.get("instance_id", ""))


# Mirrors bot.equip_from_inventory's slot resolver so try_equip_from_segment
# can pre-snapshot the destination slot's instance_id before delegating.
# Without this we couldn't tell "successfully equipped into empty slot"
# from "blocked, did nothing." 2026-06-05.
func _resolve_equip_slot_for(inst: Dictionary, item_slot: String) -> String:
	if not is_instance_valid(_bot):
		return item_slot
	if item_slot == "ring":
		var ring_ids: Array = SpeciesData.ring_slot_ids(_bot.species_id)
		for r in ring_ids:
			if _bot.equipped.get(r, null) == null:
				return r
		return "ring"
	if item_slot == "spell":
		var spell_ids: Array = ["spell1", "spell2", "spell3", "spell4", "spell5"]
		for s in spell_ids:
			if _bot.equipped.get(s, null) == null:
				return s
		return "spell1"
	return item_slot


func try_equip_from_segment(seg_idx: int, item_idx: int) -> bool:
	if seg_idx < 0 or seg_idx >= loot_segments.size():
		return false
	var seg: Dictionary = loot_segments[seg_idx]
	var items: Array = seg.get("items", [])
	if item_idx < 0 or item_idx >= items.size():
		return false
	var inst: Variant = items[item_idx]
	if typeof(inst) != TYPE_DICTIONARY:
		return false
	var base_id: String = String(inst.get("base_id", ""))
	if not _items_db.has(base_id):
		return false
	var slot: String = String(_items_db[base_id].get("slot", ""))
	if slot == "":
		return false
	# Per-slot cooldown gate.
	var cd: float = float(slot_cooldowns.get(slot, 0.0))
	if cd > 0.0:
		_log("Equip on cooldown: %s (%.0fs left)" % [slot.capitalize(), cd], "combat")
		return false
	if not is_instance_valid(_bot):
		return false
	# Species can't wear this slot. Block early with a player-visible
	# log so the click feels intentional rather than silently ignored.
	if not SpeciesData.can_wear(_bot.species_id, slot):
		var sp_def: Dictionary = SpeciesData.get_def(_bot.species_id)
		_log("%s cannot wear %s." % [String(sp_def.get("name", "Bot")), slot.capitalize()], "combat")
		return false
	# Snapshot the destination slot's instance_id so we can detect a
	# true no-op (species block, slot resolver missed, etc.). Without
	# this guard the caller would unconditionally remove the picked
	# item from inventory whether the equip succeeded or not.
	# 2026-06-05 corruption fix.
	#
	# bot.equip_from_inventory returns [] for BOTH:
	#   * blocked (species, missing data) — nothing equipped
	#   * succeeded into an empty slot — nothing displaced
	# We can't tell those apart from the return value alone, so check
	# whether the slot's instance_id changed.
	var resolved_slot: String = _resolve_equip_slot_for(inst, slot)
	var prev_id: String = ""
	var prev_inst: Variant = _bot.equipped.get(resolved_slot, null)
	if typeof(prev_inst) == TYPE_DICTIONARY:
		prev_id = String(prev_inst.get("instance_id", ""))
	# 2H ↔ shield exclusion can return up to TWO displaced items.
	var displaced_arr: Array = _bot.equip_from_inventory(inst)
	var now_inst: Variant = _bot.equipped.get(resolved_slot, null)
	var now_id: String = ""
	if typeof(now_inst) == TYPE_DICTIONARY:
		now_id = String(now_inst.get("instance_id", ""))
	# True no-op: nothing displaced AND the destination slot didn't
	# change instance_id. Don't touch inventory.
	if displaced_arr.is_empty() and now_id == prev_id:
		return false
	# Remove the picked item from its segment.
	items.remove_at(item_idx)
	# Stash all displaced items back at the same segment so the player
	# can find them. Newest at the end so equipped→unequipped order
	# is preserved.
	for d in displaced_arr:
		if typeof(d) == TYPE_DICTIONARY:
			items.append(d)
	slot_cooldowns[slot] = EQUIP_COOLDOWN_SECONDS
	_rebuild_inv_cache()
	push_inventory_to_hud()
	return true


# DragManager fired drag_ended; HUD bubbled the payload + dst_slot up.
# Routes both inventory→paperdoll and paperdoll→paperdoll through the
# same code paths the click-equip uses (try_equip_from_segment +
# bot.equip_from_inventory) so the segment math + 2H exclusion + cache
# rebuild stay consistent. Without this, the drag-drop path fragmented
# the segment list and double-appended items.
func handle_drag_drop(payload: Dictionary, dst_slot: String) -> void:
	if not is_instance_valid(_bot):
		return
	var src_role: String = String(payload.get("role", ""))
	if src_role == "inventory":
		# Resolve by instance_id (authoritative) — falls back to
		# flat_inv_index only when the payload doesn't carry an id.
		# Stale flat_inv_index from drag-start time was the
		# "drag a targe, equipped a tattered hide" cross-wire bug;
		# instance_id is set on the source instance dict and survives
		# any segment shrink/reorder. 2026-06-05 corruption fix.
		var iid: String = String(payload.get("instance_id", ""))
		if iid != "":
			_hud_drag_equip_by_instance_id(iid, dst_slot)
		else:
			_hud_drag_equip_from_inv(int(payload.get("inv_index", -1)), dst_slot)
	elif src_role == "paperdoll":
		_hud_drag_swap_slots(String(payload.get("slot_id", "")), dst_slot)
	push_inventory_to_hud()


# Mid-run unequip — HUD sent the slot, we move the item back to the
# active loot segment so it shows up in the bag. Updates bot.equipped
# directly + rebuilds the inv cache so the bag re-renders cleanly.
func handle_unequip_request(slot_id: String) -> void:
	if not is_instance_valid(_bot):
		return
	var current: Variant = _bot.equipped.get(slot_id, null)
	if current == null or typeof(current) != TYPE_DICTIONARY:
		return
	_bot.equipped[slot_id] = null
	_bot.recompute_stats()
	_bot._refresh_gear_overlays()
	append_to_active_segment(current)
	_rebuild_inv_cache()
	push_inventory_to_hud()


# Inventory → paperdoll (drag). Find the segment that owns the flat
# inv_index, hand the item to bot.equip_from_inventory (which handles
# slot routing + 2H exclusion + recompute_stats), and place displaced
# items back at the SOURCE segment so the inventory order stays
# stable. Mirrors try_equip_from_segment exactly.
# Authoritative drag-equip resolver — finds the source item by its
# instance_id rather than by a stale flat_inv_index. Walks every
# segment's items array, equips the first match. instance_id is unique
# (minted at drop time, preserved across save/load), so this is the
# safest route. 2026-06-05.
func _hud_drag_equip_by_instance_id(instance_id: String, dst_slot: String) -> void:
	for seg_i in loot_segments.size():
		var items: Array = loot_segments[seg_i].get("items", [])
		for item_i in items.size():
			var inst: Variant = items[item_i]
			if typeof(inst) != TYPE_DICTIONARY:
				continue
			if String(inst.get("instance_id", "")) == instance_id:
				_hud_drag_equip_at(seg_i, item_i, dst_slot)
				return


# Shared body — used by both _hud_drag_equip_by_instance_id and
# _hud_drag_equip_from_inv. Equips items[seg_idx][item_idx] into
# dst_slot with all the same guards (cooldown, species block, 2H/shield
# exclusion, no-op detection). 2026-06-05.
func _hud_drag_equip_at(src_seg_idx: int, src_local_idx: int, dst_slot: String) -> void:
	if src_seg_idx < 0 or src_seg_idx >= loot_segments.size():
		return
	var src_items: Array = loot_segments[src_seg_idx].get("items", [])
	if src_local_idx < 0 or src_local_idx >= src_items.size():
		return
	var inst: Variant = src_items[src_local_idx]
	if typeof(inst) != TYPE_DICTIONARY:
		return
	var cd: float = float(slot_cooldowns.get(dst_slot, 0.0))
	if cd > 0.0:
		_log("Equip on cooldown: %s (%.0fs left)" % [dst_slot.capitalize(), cd], "combat")
		return
	var item: Dictionary = _items_db.get(String(inst.get("base_id", "")), {})
	if item.is_empty():
		return
	var prev_inst_id: String = ""
	var prev_inst: Variant = _bot.equipped.get(dst_slot, null)
	if typeof(prev_inst) == TYPE_DICTIONARY:
		prev_inst_id = String(prev_inst.get("instance_id", ""))
	var displaced_arr: Array = _equip_to_explicit_slot(inst, dst_slot)
	var now_inst: Variant = _bot.equipped.get(dst_slot, null)
	var now_inst_id: String = ""
	if typeof(now_inst) == TYPE_DICTIONARY:
		now_inst_id = String(now_inst.get("instance_id", ""))
	if displaced_arr.is_empty() and now_inst_id == prev_inst_id:
		return
	src_items.remove_at(src_local_idx)
	for d in displaced_arr:
		if typeof(d) == TYPE_DICTIONARY:
			src_items.append(d)
	slot_cooldowns[dst_slot] = EQUIP_COOLDOWN_SECONDS
	_rebuild_inv_cache()


func _hud_drag_equip_from_inv(flat_inv_index: int, dst_slot: String) -> void:
	if flat_inv_index < 0 or flat_inv_index >= hud_inv_cache.size():
		return
	# Find source segment + local index from the flat index.
	var src_seg_idx: int = -1
	var src_local_idx: int = -1
	var offset: int = 0
	for i in loot_segments.size():
		var items: Array = loot_segments[i].get("items", [])
		if flat_inv_index < offset + items.size():
			src_seg_idx = i
			src_local_idx = flat_inv_index - offset
			break
		offset += items.size()
	if src_seg_idx < 0 or src_local_idx < 0:
		return
	var src_items: Array = loot_segments[src_seg_idx].get("items", [])
	var inst: Variant = src_items[src_local_idx]
	if typeof(inst) != TYPE_DICTIONARY:
		return
	# Per-slot cooldown gate (mirrors try_equip_from_segment so click
	# and drag honour the same equip cadence).
	var cd: float = float(slot_cooldowns.get(dst_slot, 0.0))
	if cd > 0.0:
		_log("Equip on cooldown: %s (%.0fs left)" % [dst_slot.capitalize(), cd], "combat")
		return
	# Force the bot's resolver to write into the EXPLICIT dst_slot the
	# user picked — without this, dragging a spell onto spell3 would
	# auto-route into spell1 if it was empty. Cache + restore the
	# instance's "slot" field briefly to short-circuit the resolver.
	var item: Dictionary = _items_db.get(String(inst.get("base_id", "")), {})
	if item.is_empty():
		return
	# Snapshot whatever was in the slot BEFORE the equip attempt so we
	# can detect a true no-op (block hit upstream — species, cooldown,
	# etc.) by comparing the slot's instance_id afterwards. Comparing
	# `bot.equipped[dst_slot] != inst` was incorrect because
	# `_equip_to_explicit_slot` deep-duplicates the inst into the slot,
	# so the check ALWAYS fired on a successful equip into an empty
	# slot — leaving the inventory copy in place AND a duplicate on the
	# bot. Source of the duplication bug. UI polish 2026-06-04.
	var prev_inst_id: String = ""
	var prev_inst: Variant = _bot.equipped.get(dst_slot, null)
	if typeof(prev_inst) == TYPE_DICTIONARY:
		prev_inst_id = String(prev_inst.get("instance_id", ""))
	var displaced_arr: Array = _equip_to_explicit_slot(inst, dst_slot)
	var now_inst: Variant = _bot.equipped.get(dst_slot, null)
	var now_inst_id: String = ""
	if typeof(now_inst) == TYPE_DICTIONARY:
		now_inst_id = String(now_inst.get("instance_id", ""))
	# A successful equip always changes the instance_id in the slot.
	# If displaced is empty AND the slot looks unchanged, the equip
	# was rejected by an upstream block — leave the inventory alone.
	if displaced_arr.is_empty() and now_inst_id == prev_inst_id:
		return
	src_items.remove_at(src_local_idx)
	for d in displaced_arr:
		if typeof(d) == TYPE_DICTIONARY:
			src_items.append(d)
	slot_cooldowns[dst_slot] = EQUIP_COOLDOWN_SECONDS
	_rebuild_inv_cache()


# Equip an inventory instance into an EXPLICIT slot (no auto-routing).
# Returns displaced items the same way bot.equip_from_inventory does
# so callers can reinsert them. Used by the drag-drop path; the click
# path keeps using bot.equip_from_inventory which auto-routes.
func _equip_to_explicit_slot(inst: Dictionary, dst_slot: String) -> Array:
	if not is_instance_valid(_bot):
		return []
	var item: Dictionary = _items_db.get(String(inst.get("base_id", "")), {})
	if item.is_empty():
		return []
	# Slot-family hard guard. The hover-time check in
	# hud_chrome._paperdoll_accepts_drop should already reject
	# mismatched drops, but a stale payload / corrupted inventory cell
	# could route an amulet onto the weapon slot. Reject defensively
	# so we never equip an item into a slot it doesn't belong in.
	# 2026-06-05 corruption fix.
	var item_slot: String = String(item.get("slot", ""))
	if item_slot == "":
		return []
	var dst_family: String = dst_slot
	if dst_slot.begins_with("ring"):
		dst_family = "ring"
	elif dst_slot.begins_with("spell"):
		dst_family = "spell"
	if item_slot != dst_family:
		return []
	# Species body-shape block.
	if not dst_slot.begins_with("spell") and not SpeciesData.can_wear(_bot.species_id, dst_slot):
		return []
	var displaced: Array = []
	# 2H/dual ↔ shield exclusion (gear slots only). Routes through
	# is_two_handed(item) so dual-wield uniques (Gyre) trigger the
	# same shield-exclusion as 2H weapons. 2026-06-05.
	if dst_slot == "weapon" and Bot.is_two_handed(item):
		var s: Variant = _bot.equipped.get("shield", null)
		if s != null and typeof(s) == TYPE_DICTIONARY:
			displaced.append(s)
			_bot.equipped["shield"] = null
	elif dst_slot == "shield":
		var w: Variant = _bot.equipped.get("weapon", null)
		if w != null and typeof(w) == TYPE_DICTIONARY:
			var w_id: String = String(w.get("base_id", ""))
			if w_id != "" and _items_db.has(w_id):
				if Bot.is_two_handed(_items_db[w_id]):
					displaced.append(w)
					_bot.equipped["weapon"] = null
	# Direct displace into dst_slot.
	var prev: Variant = _bot.equipped.get(dst_slot, null)
	if prev != null and typeof(prev) == TYPE_DICTIONARY:
		displaced.append(prev)
	_bot.equipped[dst_slot] = inst.duplicate(true)
	var prev_max: int = _bot.max_hp
	_bot.recompute_stats()
	_bot.hp = clampi(_bot.hp + (_bot.max_hp - prev_max), 0, _bot.max_hp)
	_bot._update_hp_bar()
	_bot._refresh_gear_overlays()
	return displaced


func _hud_drag_swap_slots(src_slot: String, dst_slot: String) -> void:
	if src_slot == "" or src_slot == dst_slot:
		return
	var a: Variant = _bot.equipped.get(src_slot, null)
	if a == null or typeof(a) != TYPE_DICTIONARY:
		return
	var b: Variant = _bot.equipped.get(dst_slot, null)
	_bot.equipped[dst_slot] = a
	_bot.equipped[src_slot] = b if (b != null and typeof(b) == TYPE_DICTIONARY) else null
	_bot.recompute_stats()
	_bot._refresh_gear_overlays()


# Loot pickup completion — called from the dungeon when the bot
# finishes walking onto a LootDrop. Adds inst to the active floor
# segment (lazy-creating it on first pickup), rebuilds the cache,
# defers the auto-salvage check.
func complete_loot_pickup(inst: Dictionary, current_floor: int) -> void:
	ensure_current_floor_segment(current_floor)
	(loot_segments[current_floor_segment_index].items as Array).append(inst)
	_rebuild_inv_cache()
	# Auto-salvage is deferred to floor-end / run-end so the HUD never
	# pays the segment-shrink rebuild cost mid-combat. The cap is a
	# soft cap during a run; the next descent / death flushes overflow.
	# Inline call ran on every pickup once cap was hit, which was the
	# loot stutter we tracked down.
	pending_salvage_check = true
	push_inventory_to_hud()


# Bank any in-flight LootDrops into the inventory cache. Chests, vault
# loot marks and enemy drops all spawn `LootDrop` Interactables that
# only enter `hud_inv_cache` when the bot finishes walking onto them
# (`complete_loot_pickup` after `interact_duration` seconds). If the
# scene tears down before the bot reaches a drop, the item is lost.
# Called from `flush_to_save` so menu-exit mid-pickup banks the items.
func flush_pending_drops(current_floor: int) -> void:
	if not _pending_drops_provider.is_valid():
		return
	var drops: Array = _pending_drops_provider.call()
	for drop in drops:
		if not is_instance_valid(drop):
			continue
		if drop.consumed:
			continue
		if drop.instance.is_empty():
			continue
		ensure_current_floor_segment(current_floor)
		(loot_segments[current_floor_segment_index].items as Array).append(drop.instance)
		drop.consumed = true
		if _on_drop_folded.is_valid():
			_on_drop_folded.call(drop)
	_rebuild_inv_cache()
	push_inventory_to_hud()


# Auto-salvage: when inventory exceeds cap, walk segments oldest-first
# and convert items to gold until back under. Only salvages items with
# rarity at-or-below loot_filter (so a player who set filter=epic doesn't
# lose epic+ items). Starter gear is excluded — never salvage rusty_dagger
# or tattered_hide. Per item: gold = LootFactory.salvage_value(rarity).
func maybe_auto_salvage() -> void:
	if hud_inv_cache.size() <= inventory_cap:
		return
	# Salvage threshold = the player's loot filter. Items above filter
	# rarity are protected; only filtered-or-below get sold.
	var threshold_rank: int = LootDrop.loot_filter_min_rank
	var gold_earned: int = 0
	var salvaged_count: int = 0
	# Walk segments oldest-first (Base segment first — that's the player's
	# stash, which is correct for "salvage what's been sitting there
	# longest"). Within a segment, walk items by index.
	for seg in loot_segments:
		var items_arr: Array = seg.get("items", [])
		var i: int = 0
		while i < items_arr.size() and hud_inv_cache.size() - salvaged_count > inventory_cap:
			var inst: Variant = items_arr[i]
			if typeof(inst) != TYPE_DICTIONARY:
				i += 1
				continue
			var base_id: String = String(inst.get("base_id", ""))
			if base_id in STARTER_IDS:
				i += 1
				continue
			if not _items_db.has(base_id):
				i += 1
				continue
			# Favorited items are locked from auto-salvage. The user
			# starred them deliberately — bulk salvage skips them
			# regardless of rarity or filter setting.
			if bool(inst.get("favorite", false)):
				i += 1
				continue
			var item: Dictionary = _items_db[base_id]
			var rarity: String = String(item.get("rarity", "common"))
			# Anything strictly above the filter is protected.
			if LootDrop.RARITY_RANK.get(rarity, 0) > threshold_rank:
				i += 1
				continue
			gold_earned += LootFactory.salvage_value(rarity)
			salvaged_count += 1
			items_arr.remove_at(i)
			# Don't advance i — the next item shifted into this slot.
		if hud_inv_cache.size() - salvaged_count <= inventory_cap:
			break
	if salvaged_count > 0:
		if is_instance_valid(_bot):
			_bot.gold += gold_earned
		run_salvaged_count += salvaged_count
		run_salvaged_gold += gold_earned
		_rebuild_inv_cache()
		push_inventory_to_hud()
		_log("Salvaged %d items (+%d gold)." % [salvaged_count, gold_earned], "loot")


# Run flush-helper for floor-end / run-end / menu-exit. Returns true if
# auto-salvage actually ran (caller can clear pending_salvage_check).
func maybe_auto_salvage_if_pending() -> bool:
	if pending_salvage_check or hud_inv_cache.size() > inventory_cap:
		pending_salvage_check = false
		maybe_auto_salvage()
		return true
	return false


func tick_cooldowns(delta: float) -> void:
	if slot_cooldowns.is_empty():
		return
	for slot in slot_cooldowns.keys():
		var cd: float = float(slot_cooldowns[slot]) - delta
		if cd <= 0.0:
			slot_cooldowns.erase(slot)
		else:
			slot_cooldowns[slot] = cd
	# Lightweight per-frame refresh — only updates the paperdoll countdown
	# labels, not the inventory grid (which would be wasteful every tick).
	if _chrome != null and is_instance_valid(_chrome):
		_chrome.update_cooldowns(slot_cooldowns)
