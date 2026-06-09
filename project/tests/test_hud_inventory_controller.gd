extends GutTest

# Tests for HUDInventoryController — the live-inventory + auto-salvage +
# drag-drop equip module extracted from dungeon.gd 2026-06-09 (Tier 3
# god-class split, second extraction). The load-bearing invariants:
#
#   * Segment shape: init_run seeds Base; complete_loot_pickup lazy-
#     creates the floor segment; flush_pending_drops folds in-flight
#     drops (chest-loot-loss fix, commit f80376b).
#   * Cache: hud_inv_cache always equals the flat concat of segment
#     items.
#   * Auto-salvage: walks segments oldest-first, stops the moment cap
#     is reached, skips favorites + STARTER_IDS + items above the
#     loot filter rank, accrues run_salvaged_count / _gold for the
#     run report.
#   * Click-duplication guard: instance_at_segment_idx returns the
#     instance_id at (seg, idx) and "" out-of-range — HUD chrome
#     uses this to refuse stale clicks.
#   * Cooldown tick: per-slot cooldowns decay every frame.

const _StubBot := preload("res://tests/_stub_bot.gd")
const HUDInvCtrl := preload("res://scripts/hud_inventory_controller.gd")

# Tiny synthetic items_db. Mirrors the shape items.json carries —
# id / slot / rarity. Salvage values come from LootFactory.SALVAGE_VALUES
# (common 2, uncommon 6, rare 18, epic 60, legendary 200).
const ITEMS_DB := {
	"rusty_dagger":   {"id": "rusty_dagger",   "slot": "weapon", "rarity": "common"},
	"tattered_hide":  {"id": "tattered_hide",  "slot": "armor",  "rarity": "common"},
	"common_axe":     {"id": "common_axe",     "slot": "weapon", "rarity": "common"},
	"common_helm":    {"id": "common_helm",    "slot": "helm",   "rarity": "common"},
	"uncommon_belt":  {"id": "uncommon_belt",  "slot": "ring",   "rarity": "uncommon"},
	"rare_ring":      {"id": "rare_ring",      "slot": "ring",   "rarity": "rare"},
	"epic_blade":     {"id": "epic_blade",     "slot": "weapon", "rarity": "epic"},
	"legendary_orb":  {"id": "legendary_orb",  "slot": "amulet", "rarity": "legendary"},
}

var _bot: Node = null
var _ctrl: RefCounted = null

func before_each() -> void:
	_bot = _StubBot.new()
	add_child_autofree(_bot)
	# Reset the static loot_filter_min_rank between tests so an earlier
	# test that bumps the filter doesn't leak.
	LootDrop.loot_filter_min_rank = 0
	_ctrl = HUDInvCtrl.new(_bot, ITEMS_DB, null)


func _make_inst(base_id: String, instance_id: String = "", favorite: bool = false) -> Dictionary:
	var inst := {"base_id": base_id}
	if instance_id != "":
		inst["instance_id"] = instance_id
	if favorite:
		inst["favorite"] = true
	return inst


func _items(seg: Dictionary) -> Array:
	return seg.get("items", [])


# ---------------------------------------------------------------------
# init_run — seeds Base segment + cap + zero salvage counts
# ---------------------------------------------------------------------

func test_init_run_seeds_base_segment_with_save_inventory() -> void:
	var save := {
		"inventory_cap": 50,
		"inventory": [_make_inst("rusty_dagger", "i1"), _make_inst("tattered_hide", "i2")],
		"bot_upgrades": {},
	}
	_ctrl.init_run(save)
	assert_eq(_ctrl.loot_segments.size(), 1, "exactly one Base segment after init_run")
	assert_eq(_ctrl.loot_segments[0].header, "Base", "first segment is Base")
	assert_eq(_items(_ctrl.loot_segments[0]).size(), 2, "Base segment carries the saved inventory")
	assert_eq(_ctrl.hud_inv_cache.size(), 2, "flat cache mirrors segments")
	assert_eq(_ctrl.current_floor_segment_index, -1, "no floor segment yet")
	assert_eq(_ctrl.inventory_cap, 50, "cap read from save")
	assert_eq(_ctrl.run_salvaged_count, 0, "salvage count zeroed at run start")
	assert_eq(_ctrl.run_salvaged_gold, 0, "salvage gold zeroed at run start")


func test_init_run_deep_copies_save_inventory() -> void:
	var inst := _make_inst("rusty_dagger", "i1")
	var save := {"inventory": [inst], "inventory_cap": 50, "bot_upgrades": {}}
	_ctrl.init_run(save)
	# Mutate the segment-side inst — save's array must NOT see the change.
	(_ctrl.loot_segments[0].items[0] as Dictionary)["instance_id"] = "MUTATED"
	assert_eq(String(inst.get("instance_id", "")), "i1", "init_run deep-copied the saved inventory")


# ---------------------------------------------------------------------
# complete_loot_pickup — lazy-creates floor segment, appends, rebuilds cache
# ---------------------------------------------------------------------

func test_complete_loot_pickup_lazy_creates_floor_segment() -> void:
	_ctrl.init_run({"inventory": [], "inventory_cap": 50, "bot_upgrades": {}})
	_ctrl.complete_loot_pickup(_make_inst("common_axe", "i1"), 3)
	assert_eq(_ctrl.loot_segments.size(), 2, "Base + Floor 3 segments")
	assert_eq(_ctrl.loot_segments[1].header, "Floor 3", "lazy floor segment named for the floor")
	assert_eq(_items(_ctrl.loot_segments[1]).size(), 1, "drop appended to floor segment")
	assert_eq(_ctrl.current_floor_segment_index, 1, "floor segment index updated")
	assert_eq(_ctrl.hud_inv_cache.size(), 1, "cache picks up the new drop")
	assert_true(_ctrl.pending_salvage_check, "pickup defers a salvage check")


func test_complete_loot_pickup_reuses_existing_floor_segment() -> void:
	_ctrl.init_run({"inventory": [], "inventory_cap": 50, "bot_upgrades": {}})
	_ctrl.complete_loot_pickup(_make_inst("common_axe", "a"), 3)
	_ctrl.complete_loot_pickup(_make_inst("common_helm", "b"), 3)
	assert_eq(_ctrl.loot_segments.size(), 2, "still Base + Floor 3, no extra segment")
	assert_eq(_items(_ctrl.loot_segments[1]).size(), 2, "second drop appended to same segment")


# ---------------------------------------------------------------------
# flush_pending_drops — chest-loot-loss fix (commit f80376b)
# ---------------------------------------------------------------------

# Minimal LootDrop stand-in for flush_pending_drops. The real LootDrop
# is a Node2D with assets; the controller only reads consumed +
# instance + is_instance_valid().
class FakeDrop:
	extends RefCounted
	var consumed: bool = false
	var instance: Dictionary = {}


func test_flush_pending_drops_folds_unconsumed_into_active_segment() -> void:
	_ctrl.init_run({"inventory": [], "inventory_cap": 50, "bot_upgrades": {}})
	# Set the active floor segment as if the bot had walked one drop already.
	_ctrl.complete_loot_pickup(_make_inst("common_axe", "first"), 2)
	var d1 := FakeDrop.new()
	d1.instance = _make_inst("common_helm", "pending1")
	var d2 := FakeDrop.new()
	d2.instance = _make_inst("rare_ring", "pending2")
	var d_already_consumed := FakeDrop.new()
	d_already_consumed.consumed = true
	d_already_consumed.instance = _make_inst("epic_blade", "skipped")
	var pending: Array = [d1, d2, d_already_consumed]
	_ctrl.set_pending_drops_provider(func(): return pending, Callable())
	_ctrl.flush_pending_drops(2)
	assert_eq(_items(_ctrl.loot_segments[1]).size(), 3,
		"first walk-pickup + 2 unconsumed flushes — consumed drop skipped")
	assert_true(d1.consumed, "flushed drop marked consumed")
	assert_true(d2.consumed, "flushed drop marked consumed")
	assert_eq(_ctrl.hud_inv_cache.size(), 3, "cache reflects 3 items")


func test_flush_pending_drops_creates_segment_when_no_walk_pickup_yet() -> void:
	# Reproduces the audit scenario directly: open a chest, escape to
	# main menu before walking onto the drops. Pre-fix, every drop
	# vanished. Post-fix, flush_pending_drops creates the floor
	# segment on demand.
	_ctrl.init_run({"inventory": [], "inventory_cap": 50, "bot_upgrades": {}})
	var d := FakeDrop.new()
	d.instance = _make_inst("common_axe", "esc_pre_pickup")
	_ctrl.set_pending_drops_provider(func(): return [d], Callable())
	_ctrl.flush_pending_drops(4)
	assert_eq(_ctrl.loot_segments.size(), 2, "Base + lazy Floor 4 segment")
	assert_eq(_ctrl.loot_segments[1].header, "Floor 4")
	assert_eq(_items(_ctrl.loot_segments[1]).size(), 1, "the chest drop was banked")


# ---------------------------------------------------------------------
# maybe_auto_salvage — oldest-first, skip favorites + STARTERS + above-filter
# ---------------------------------------------------------------------

func test_maybe_auto_salvage_does_nothing_under_cap() -> void:
	_ctrl.init_run({
		"inventory": [_make_inst("common_axe", "a"), _make_inst("common_helm", "b")],
		"inventory_cap": 50, "bot_upgrades": {},
	})
	_ctrl.maybe_auto_salvage()
	assert_eq(_ctrl.hud_inv_cache.size(), 2, "no salvage when under cap")
	assert_eq(_ctrl.run_salvaged_count, 0, "no run salvage stat changes")


func test_maybe_auto_salvage_walks_oldest_first_until_cap() -> void:
	# cap=2, three items in Base — salvage should drop the oldest one.
	# Auto-salvage's threshold is the loot filter rank; default
	# loot_filter_min_rank=0 lets only common items through, which
	# all three are.
	_ctrl.init_run({
		"inventory": [
			_make_inst("common_axe", "old"),
			_make_inst("common_helm", "mid"),
			_make_inst("common_axe", "new"),
		],
		"inventory_cap": 2, "bot_upgrades": {},
	})
	_ctrl.maybe_auto_salvage()
	assert_eq(_ctrl.hud_inv_cache.size(), 2, "one common salvaged to bring cache to cap")
	assert_eq(_ctrl.run_salvaged_count, 1, "run_salvaged_count tracked")
	assert_eq(_ctrl.run_salvaged_gold, 2, "common = 2 gold (LootFactory.salvage_value)")
	assert_eq(_bot.gold, 2, "bot.gold credited")
	# The oldest item went, mid + new survive.
	var ids: Array = []
	for inst in _items(_ctrl.loot_segments[0]):
		ids.append(String(inst.get("instance_id", "")))
	assert_does_not_have(ids, "old", "oldest was salvaged")
	assert_has(ids, "mid", "newer items preserved")
	assert_has(ids, "new", "newer items preserved")


func test_maybe_auto_salvage_skips_starter_ids() -> void:
	_ctrl.init_run({
		"inventory": [
			_make_inst("rusty_dagger", "starter_w"),
			_make_inst("tattered_hide", "starter_a"),
			_make_inst("common_axe", "regular"),
		],
		"inventory_cap": 2, "bot_upgrades": {},
	})
	_ctrl.maybe_auto_salvage()
	# The non-starter common is the only valid salvage target.
	var ids: Array = []
	for inst in _items(_ctrl.loot_segments[0]):
		ids.append(String(inst.get("instance_id", "")))
	assert_has(ids, "starter_w", "rusty_dagger never salvaged")
	assert_has(ids, "starter_a", "tattered_hide never salvaged")
	assert_does_not_have(ids, "regular", "non-starter common was salvaged")


func test_maybe_auto_salvage_skips_favorites() -> void:
	_ctrl.init_run({
		"inventory": [
			_make_inst("common_axe", "fav", true),
			_make_inst("common_helm", "regular"),
		],
		"inventory_cap": 1, "bot_upgrades": {},
	})
	_ctrl.maybe_auto_salvage()
	var ids: Array = []
	for inst in _items(_ctrl.loot_segments[0]):
		ids.append(String(inst.get("instance_id", "")))
	assert_has(ids, "fav", "favorite preserved despite cap pressure")
	assert_does_not_have(ids, "regular", "non-favorite salvaged")


func test_maybe_auto_salvage_skips_above_filter_rarity() -> void:
	# loot_filter_min_rank=2 (rare+) — items strictly above rare (epic,
	# legendary) are protected; rare and below are sold.
	LootDrop.loot_filter_min_rank = 2
	_ctrl.init_run({
		"inventory": [
			_make_inst("common_axe", "common"),
			_make_inst("rare_ring", "rare"),
			_make_inst("epic_blade", "epic"),
			_make_inst("legendary_orb", "leg"),
		],
		"inventory_cap": 2, "bot_upgrades": {},
	})
	_ctrl.maybe_auto_salvage()
	var ids: Array = []
	for inst in _items(_ctrl.loot_segments[0]):
		ids.append(String(inst.get("instance_id", "")))
	assert_does_not_have(ids, "common", "common ≤ filter rank — salvaged")
	assert_does_not_have(ids, "rare", "rare ≤ filter rank — salvaged")
	assert_has(ids, "epic", "epic strictly above filter — preserved")
	assert_has(ids, "leg", "legendary strictly above filter — preserved")


func test_maybe_auto_salvage_if_pending_clears_flag() -> void:
	_ctrl.init_run({"inventory": [], "inventory_cap": 50, "bot_upgrades": {}})
	_ctrl.pending_salvage_check = true
	# Under cap — flag should still clear because pending was set.
	var ran: bool = _ctrl.maybe_auto_salvage_if_pending()
	assert_true(ran, "pending flag triggered the helper")
	assert_false(_ctrl.pending_salvage_check, "flag cleared after run")


# ---------------------------------------------------------------------
# instance_at_segment_idx — click-duplication guard
# ---------------------------------------------------------------------

func test_instance_at_segment_idx_returns_instance_id_for_valid_pair() -> void:
	_ctrl.init_run({
		"inventory": [_make_inst("common_axe", "wanted"), _make_inst("common_helm", "other")],
		"inventory_cap": 50, "bot_upgrades": {},
	})
	assert_eq(_ctrl.instance_at_segment_idx(0, 0), "wanted",
		"valid (seg, idx) returns the live instance_id")
	assert_eq(_ctrl.instance_at_segment_idx(0, 1), "other")


func test_instance_at_segment_idx_returns_empty_for_out_of_range() -> void:
	_ctrl.init_run({
		"inventory": [_make_inst("common_axe", "i1")],
		"inventory_cap": 50, "bot_upgrades": {},
	})
	assert_eq(_ctrl.instance_at_segment_idx(-1, 0), "", "negative seg → empty")
	assert_eq(_ctrl.instance_at_segment_idx(0, -1), "", "negative idx → empty")
	assert_eq(_ctrl.instance_at_segment_idx(99, 0), "", "out-of-range seg → empty")
	assert_eq(_ctrl.instance_at_segment_idx(0, 99), "", "out-of-range idx → empty")


func test_instance_at_segment_idx_after_segment_shift_returns_new_id() -> void:
	# Stale-click scenario: HUD records (seg=0, idx=1, instance_id="X")
	# at click-down. Between then and click-up, item 0 was equipped and
	# removed. Items shifted left — (0, 1) now points at a different
	# item. The click-up handler compares the live id and refuses the
	# equip when it doesn't match the click-down id.
	_ctrl.init_run({
		"inventory": [_make_inst("common_axe", "a"), _make_inst("common_helm", "b")],
		"inventory_cap": 50, "bot_upgrades": {},
	})
	(_ctrl.loot_segments[0].items as Array).remove_at(0)  # simulate click-equip of item 0
	# The HUD recorded (0, 1, "b") but (0, 1) is now out of range.
	assert_eq(_ctrl.instance_at_segment_idx(0, 1), "",
		"stale (0, 1) post-shift returns empty (HUD will refuse equip)")


# ---------------------------------------------------------------------
# tick_cooldowns
# ---------------------------------------------------------------------

func test_tick_cooldowns_decays_and_clears() -> void:
	_ctrl.slot_cooldowns = {"weapon": 10.0, "armor": 0.5}
	_ctrl.tick_cooldowns(1.0)
	assert_almost_eq(float(_ctrl.slot_cooldowns.get("weapon", 0.0)), 9.0, 0.001)
	assert_false(_ctrl.slot_cooldowns.has("armor"),
		"sub-zero cooldown evicted")


# ---------------------------------------------------------------------
# append_to_active_segment
# ---------------------------------------------------------------------

func test_append_to_active_segment_lands_in_floor_when_active() -> void:
	_ctrl.init_run({"inventory": [], "inventory_cap": 50, "bot_upgrades": {}})
	_ctrl.complete_loot_pickup(_make_inst("common_axe", "p"), 5)
	_ctrl.append_to_active_segment(_make_inst("common_helm", "displaced"))
	assert_eq(_items(_ctrl.loot_segments[1]).size(), 2,
		"displaced item lands in active floor segment")


func test_append_to_active_segment_falls_back_to_base() -> void:
	_ctrl.init_run({"inventory": [], "inventory_cap": 50, "bot_upgrades": {}})
	# No floor segment yet — fall back to Base.
	_ctrl.append_to_active_segment(_make_inst("common_axe", "displaced"))
	assert_eq(_items(_ctrl.loot_segments[0]).size(), 1,
		"displaced item lands in Base when no active floor segment")
