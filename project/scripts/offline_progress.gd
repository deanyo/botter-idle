class_name OfflineProgress
extends RefCounted

# Simulates floors-while-away: estimates how many floors the bot would
# have cleared on the last deployed branch during the time the game was
# closed, rolls loot proportional to expected drop rate, and returns a
# summary the launch path can show before the main menu loads.

# Capped at 1h so AFK-checking has a daily-rhythm feel — going beyond
# that should be a meta-feature (offline-tax upgrade) not a flat bonus.
const MAX_OFFLINE_SECONDS := 3600
# Below this, treat "offline_seconds" as just a relaunch — no loot.
const MIN_OFFLINE_SECONDS := 60
# Baseline at CR == cr_recommended. Scales linearly with CR overage.
const BASELINE_FLOOR_SECONDS := 90.0
const FLOOR_LOOT_AVG := 4.0  # average loot drops per floor

# Compute and apply offline progress to the state. Returns a summary
# dict the launch UI can render: {seconds, floors, loot_count, gold}.
# Mutates state.inventory + state.gold + state.last_seen_timestamp.
static func apply(state: Dictionary, items_db: Dictionary) -> Dictionary:
	var summary: Dictionary = {
		"seconds": 0, "floors": 0, "loot_count": 0, "gold": 0, "branch": "",
	}
	var last_seen: int = int(state.get("last_seen_timestamp", 0))
	if last_seen <= 0:
		return summary
	var now: int = int(Time.get_unix_time_from_system())
	var elapsed: int = mini(now - last_seen, MAX_OFFLINE_SECONDS)
	if elapsed < MIN_OFFLINE_SECONDS:
		return summary
	var branch_id: String = String(state.get("last_branch", ""))
	if branch_id == "":
		return summary
	var biome: Dictionary = BiomeData.get_biome(branch_id)
	if biome.is_empty():
		return summary
	# Floor clear time scales: at recommended CR → BASELINE; at 2× CR →
	# half. Below recommended, slower (capped at 4× baseline so it doesn't
	# trail to zero floors).
	var bot_cr: float = _compute_cr(state, items_db)
	var rec_cr: float = float(biome.get("cr_recommended", 1))
	var ratio: float = bot_cr / max(1.0, rec_cr)
	var clear_seconds: float = clampf(BASELINE_FLOOR_SECONDS / max(0.5, ratio), 22.0, 360.0)
	var floors: int = int(float(elapsed) / clear_seconds)
	if floors <= 0:
		return summary
	# Roll loot — same drop logic as live runs would produce, but in
	# bulk. Drop rate based on tier; we just use the base item table
	# filtered to the player's loot_filter.
	var rolled: Array = _roll_loot(state, items_db, floors, biome)
	var gold_earned: int = int(_estimate_gold(biome, floors))
	# Apply.
	for it in rolled:
		state.inventory.append(it)
	state["gold"] = int(state.get("gold", 0)) + gold_earned
	summary.seconds = elapsed
	summary.floors = floors
	summary.loot_count = rolled.size()
	summary.gold = gold_earned
	summary.branch = String(biome.get("display_name", branch_id))
	return summary

static func _compute_cr(state: Dictionary, items_db: Dictionary) -> float:
	# Mirrors the rough CR formula from gameplay-loop-plan.md: lvl×10 +
	# atk×1.2 + def×2 + hp×0.1. Computed against the player's CURRENT
	# stats (base + gear + upgrades) — same numbers the Outpost shows.
	var lv: int = int(state.get("level", 1))
	var max_hp: int = 50 + (lv - 1) * 8
	var atk: int = 5 + (lv - 1)
	var defense: int = 1 + int(lv / 3.0)
	# Upgrade contributions.
	max_hp += int(BotUpgrades.total_for_stat(state, "max_hp"))
	atk += int(BotUpgrades.total_for_stat(state, "atk"))
	defense += int(BotUpgrades.total_for_stat(state, "def"))
	# Gear contributions.
	var equipped: Dictionary = state.get("equipped", {})
	for slot in equipped.keys():
		var inst: Variant = equipped[slot]
		if typeof(inst) != TYPE_DICTIONARY:
			continue
		var base_id: String = String(inst.get("base_id", ""))
		if not items_db.has(base_id):
			continue
		var item: Dictionary = items_db[base_id]
		max_hp += int(item.get("hp", 0))
		atk += int(item.get("atk", 0))
		defense += int(item.get("def", 0))
		var sums: Dictionary = AffixSystem.sum_affix_stats(inst.get("affixes", []))
		max_hp += int(sums.get("hp", 0))
		atk += int(sums.get("atk", 0))
		defense += int(sums.get("def", 0))
	return float(lv) * 10.0 + float(atk) * 1.2 + float(defense) * 2.0 + float(max_hp) * 0.1

static func _roll_loot(state: Dictionary, items_db: Dictionary, floors: int, biome: Dictionary) -> Array:
	var rolled: Array = []
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var tier: int = int(biome.get("tier", 1))
	# Filter floor — match player's loot filter so bot doesn't "pick up"
	# stuff they'd skip live.
	var filter_rank: int = LootDrop.RARITY_RANK.get(String(state.get("loot_filter", "common")), 0)
	# Build a slot pool from items_db. Filter by drop_weights[tier-1] > 0 so
	# offline loot respects the same tier gating as live runs. Items missing
	# drop_weights stay eligible at all tiers (legacy fallback).
	var idx: int = clampi(tier, 1, 5) - 1
	var pool: Array = []
	for id in items_db.keys():
		var item: Dictionary = items_db[id]
		if int(LootDrop.RARITY_RANK.get(String(item.get("rarity", "common")), 0)) < filter_rank:
			continue
		var dw: Array = item.get("drop_weights", [])
		if dw.size() == 5 and float(dw[idx]) <= 0.0:
			continue
		pool.append(id)
	if pool.is_empty():
		return rolled
	var expected: int = int(round(float(floors) * FLOOR_LOOT_AVG))
	for i in expected:
		var id: String = pool[rng.randi() % pool.size()]
		var item: Dictionary = items_db[id]
		var rarity: String = String(item.get("rarity", "common"))
		# Roll against rarity probabilities by tier — common tilts toward
		# higher rarity in higher-tier branches. Reuse the live RNG curve
		# in dungeon._roll_rarity.
		var rolled_rarity: String = _roll_rarity(rng, tier)
		# If the random item's rarity is above the rolled rarity, skip
		# (saves us from biasing common-only inventories).
		if LootDrop.RARITY_RANK.get(rarity, 0) > LootDrop.RARITY_RANK.get(rolled_rarity, 0):
			continue
		var inst: Dictionary = {
			"base_id": id,
			"instance_id": "offline_%d_%d" % [Time.get_unix_time_from_system(), i],
			"affixes": AffixSystem.roll_affixes_for(item, rng),
		}
		rolled.append(inst)
	return rolled

static func _roll_rarity(rng: RandomNumberGenerator, tier: int) -> String:
	# Cribbed from dungeon._roll_rarity but simpler — no floor scaling,
	# no blessing bonus. Higher tier branches push rarity up.
	var floor_bonus: float = float(tier - 1) * 0.05
	var r: float = rng.randf() - floor_bonus
	if r < 0.02: return "legendary"
	if r < 0.10: return "epic"
	if r < 0.25: return "rare"
	if r < 0.55: return "uncommon"
	return "common"

static func _estimate_gold(biome: Dictionary, floors: int) -> int:
	# Per-tier average gold per floor from the gameplay loop doc, mid of
	# range: T1 ~10, T2 ~35, T3 ~130, T4 ~375, T5 ~1150.
	var per_floor: Array = [10, 35, 130, 375, 1150]
	var tier: int = clampi(int(biome.get("tier", 1)) - 1, 0, per_floor.size() - 1)
	return int(per_floor[tier]) * floors
