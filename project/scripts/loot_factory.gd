class_name LootFactory
extends RefCounted

# Loot rolling + item construction + salvage. Extracted from dungeon.gd
# 2026-06-09 as the first sub-system in the dungeon.gd god-class split
# (audit Tier 3). Pure static utility — caller passes rng, items_db,
# and any derived per-floor state explicitly. No node graph, no
# singletons, no per-instance state.
#
# Behavior is a strict copy of the dungeon.gd functions it replaces;
# any tuning/balance changes belong in a separate beat.

const TIER_RARITY_CAP := {
	1: "uncommon",
	2: "rare",
	3: "epic",
	4: "legendary",
	5: "legendary",
}

const RARITY_RANK := {
	"common": 0, "uncommon": 1, "rare": 2, "epic": 3, "legendary": 4,
}

# Slot-drop weights — proportion of drops that should go to each slot
# class. Pre-2026-06-06 picked uniformly across all items of the
# requested rarity, which meant slots with bigger pools (weapons 139,
# spells 175) drowned out slots with smaller pools (gloves 15, cloak
# 19). Now we pick slot first via this table, then pick an item within
# that slot weighted by its drop_weights[tier-1].
const SLOT_DROP_WEIGHTS: Dictionary = {
	"weapon": 18,
	"armor":  10,
	"helm":   10,
	"shield": 10,
	"boots":  10,
	"gloves": 10,
	"cloak":  10,
	"ring":   10,
	"amulet":  8,
	"spell":   4,  # gated to magic+ kills via allow_spell arg
}

# Salvage values by rarity. Used by both auto-salvage in dungeon and
# the shop's sell-price formula (sell = 2× salvage × shop modifier).
const SALVAGE_VALUES := {
	"common": 2, "uncommon": 6, "rare": 18, "epic": 60, "legendary": 200,
}

static func salvage_value(rarity: String) -> int:
	return int(SALVAGE_VALUES.get(rarity, 1))

# Cap a rolled rarity by source-floor tier. T1: max uncommon, T2: rare,
# T3: epic, T4+: legendary. Stops a Floor-2 portal from showering the
# bot with T5-grade legendaries that the home branch hasn't earned.
static func clamp_rarity_to_tier(rarity: String, tier: int) -> String:
	var cap: String = String(TIER_RARITY_CAP.get(tier, "legendary"))
	if int(RARITY_RANK.get(rarity, 0)) <= int(RARITY_RANK.get(cap, 4)):
		return rarity
	return cap

# Roll a rarity for an enemy drop. Caller supplies bonuses pulled from
# its own state (blessing from bot, mod_bonus from active run modifiers)
# so this stays a pure function. Boss rolls take a special path so a
# T1 dungeon boss still has a meaningful chance at top-tier drops
# before the source-tier clamp pulls it back to uncommon.
static func roll_rarity(
	rng: RandomNumberGenerator,
	src_tier: int,
	current_floor: int,
	is_boss: bool,
	blessing_bonus: float,
	mod_bonus: float,
) -> String:
	# §2.C back-compat shim — old bool callers route through the new
	# enemy_class path. is_boss=true → "boss", is_boss=false → "trash"
	# (the legacy two-class split). Elite tier needs an explicit
	# class string from the caller.
	var enemy_class: String = "boss" if is_boss else "trash"
	return roll_rarity_for_class(rng, src_tier, current_floor, enemy_class, blessing_bonus, mod_bonus)

# §2.C (S12) — three-class rarity rolling. enemy_class:
#   "trash"  baseline drop curve (low rare-and-up tail).
#   "elite"  intermediate — magic/rare-leader-tier mobs. Bias halfway
#            between trash and boss so elite-density floors yield more
#            magic gear without dipping into boss-tier (legendary).
#   "boss"   high-tier curve unchanged from the legacy boss path
#            (50% legendary / 35% epic / 15% rare).
# Routes to roll_rarity_for_class so the §2.A roll_rarity rewrite (when
# it ships) only needs one entry point to consume tier_drop_band.
static func roll_rarity_for_class(
	rng: RandomNumberGenerator,
	src_tier: int,
	current_floor: int,
	enemy_class: String,
	blessing_bonus: float,
	mod_bonus: float,
) -> String:
	# §2.A (S12) — replaces the legacy hardcoded thresholds with a
	# data-driven weighted pick from drop_tuning.tier_drop_band[T*][band].
	# Each band is a 5-int weight array [common, uncommon, rare, epic,
	# legendary]. The blessing/mod/floor/tier bonuses translate into a
	# tail-weight bump for rare+ entries so the gate stays composable.
	var weights: Array = DropTuning.tier_drop_band(src_tier, current_floor).duplicate()
	# Compose external bonuses: each +0.05 on the legacy roll equals a
	# ~5% upward shift toward rare+. Replicate by multiplying the
	# rare/epic/legendary entries' weight by (1 + bonus×N).
	# Mirrors the pre-§2.A "subtract from r" shape: blessing_bonus + mod_
	# bonus stack additively. Cap composite at +0.5 so a stacked
	# rarity-blessing bot can't blow out the curve.
	var tail_bump: float = clampf(blessing_bonus + mod_bonus, 0.0, 0.5)
	if tail_bump > 0.0:
		var bump: float = 1.0 + tail_bump * 4.0
		weights[2] = float(weights[2]) * bump  # rare
		weights[3] = float(weights[3]) * bump  # epic
		weights[4] = float(weights[4]) * bump  # legendary
	# Class step — boss bumps every roll by boss_step rarity tiers,
	# elite by elite_step. Implemented post-pick so the band table
	# stays trash-baseline; the per-class step is the differentiator.
	var rarity: String = _weighted_rarity_pick(rng, weights)
	if enemy_class == "boss":
		rarity = _bump_rarity(rarity, DropTuning.boss_step())
	elif enemy_class == "elite":
		rarity = _bump_rarity(rarity, DropTuning.elite_step())
	elif enemy_class == "trash":
		# Trash ceiling — never roll above the configured cap.
		rarity = _cap_rarity(rarity, DropTuning.trash_ceiling())
	return clamp_rarity_to_tier(rarity, src_tier)

# §2.A helper: weighted pick over [common, uncommon, rare, epic,
# legendary]. Returns "common" if total weight is non-positive (shouldn't
# happen with the authored data; defensive fallback).
static func _weighted_rarity_pick(rng: RandomNumberGenerator, weights: Array) -> String:
	const NAMES := ["common", "uncommon", "rare", "epic", "legendary"]
	var total: float = 0.0
	for w in weights:
		total += float(w)
	if total <= 0.0:
		return "common"
	var r: float = rng.randf() * total
	var acc: float = 0.0
	for i in range(NAMES.size()):
		acc += float(weights[i])
		if r <= acc:
			return NAMES[i]
	return NAMES[NAMES.size() - 1]

# §2.A helper: bump a rarity up by N tiers (capped at "legendary").
static func _bump_rarity(rarity: String, step: int) -> String:
	if step <= 0:
		return rarity
	const ORDER := ["common", "uncommon", "rare", "epic", "legendary"]
	var idx: int = int(RARITY_RANK.get(rarity, 0))
	idx = mini(idx + step, ORDER.size() - 1)
	return ORDER[idx]

# §2.A helper: cap a rarity at the configured ceiling (e.g. trash_ceiling).
static func _cap_rarity(rarity: String, ceiling: String) -> String:
	var current_rank: int = int(RARITY_RANK.get(rarity, 0))
	var cap_rank: int = int(RARITY_RANK.get(ceiling, 4))
	if current_rank <= cap_rank:
		return rarity
	const ORDER := ["common", "uncommon", "rare", "epic", "legendary"]
	return ORDER[cap_rank]

# Chest-pickup variant. Same source-tier clamp as roll_rarity so
# entering a wizlab portal on Floor 2 of the dungeon doesn't dump
# T5-grade legendaries from bonus chests.
static func roll_rarity_with_bias(
	rng: RandomNumberGenerator,
	src_tier: int,
	current_floor: int,
	bias: int,
) -> String:
	var floor_bonus: float = float(current_floor - 1) * 0.05
	var bias_bonus: float = float(bias) * 0.10
	var r: float = rng.randf() - floor_bonus - bias_bonus
	var rarity: String
	if r < 0.02: rarity = "legendary"
	elif r < 0.10: rarity = "epic"
	elif r < 0.25: rarity = "rare"
	elif r < 0.55: rarity = "uncommon"
	else: rarity = "common"
	return clamp_rarity_to_tier(rarity, src_tier)

# Pick an item id of the given rarity. Two-stage roll:
#   1. Pick a slot from SLOT_DROP_WEIGHTS (gated by `allow_spell` —
#      common-mob kills can't roll spells).
#   2. Pick an item within that slot, weighted by drop_weights[src_tier-1].
# Items already dropped this run AND flagged unique are excluded.
# Mutates run_dropped_uniques when a unique is picked.
# Returns "" if no eligible item exists.
static func pick_loot_id(
	rng: RandomNumberGenerator,
	rarity: String,
	items_db: Dictionary,
	src_tier: int,
	run_dropped_uniques: Array,
	allow_spell: bool = true,
	active_biome: String = "",
) -> String:
	var idx: int = src_tier - 1
	var pools: Dictionary = {}  # slot → Array[Dict]
	for id in items_db.keys():
		var item: Dictionary = items_db[id]
		if String(item.get("rarity", "")) != rarity:
			continue
		if bool(item.get("unique", false)) and run_dropped_uniques.has(id):
			continue
		# S11 biome_pool filter (a07 §9.2). Items with a biome_pool list
		# only roll when the active biome matches. Items without the
		# field stay biome-agnostic (back-compat).
		if active_biome != "":
			var bp: Variant = item.get("biome_pool", null)
			if bp is Array and not (bp as Array).is_empty():
				if not (active_biome in (bp as Array)):
					continue
		# S11 boss_drop filter — these items only drop via the boss-anchor
		# code path in dungeon._maybe_drop_item; never via the normal
		# rarity table.
		if String(item.get("boss_drop", "")) != "":
			continue
		var slot: String = String(item.get("slot", ""))
		if slot == "":
			continue
		if slot == "spell" and not allow_spell:
			continue
		var dw: Array = item.get("drop_weights", [])
		var w: float
		if dw.size() == 5:
			w = float(dw[idx])
			if w <= 0.0:
				continue
		else:
			w = 1.0
		var p: Array = pools.get(slot, [])
		p.append({"id": id, "weight": w})
		pools[slot] = p
	if pools.is_empty():
		return ""
	# Pick a slot first, weighted by SLOT_DROP_WEIGHTS but skipping
	# slots with empty pools at this rarity.
	var slot_total: float = 0.0
	var slot_keys: Array = []
	var slot_weights: Array = []
	for slot in pools.keys():
		var w: float = float(SLOT_DROP_WEIGHTS.get(slot, 5))
		slot_keys.append(slot)
		slot_weights.append(w)
		slot_total += w
	if slot_total <= 0.0:
		return ""
	var slot_roll: float = rng.randf() * slot_total
	var picked_slot: String = ""
	var slot_acc: float = 0.0
	for i in slot_keys.size():
		slot_acc += float(slot_weights[i])
		if slot_roll <= slot_acc:
			picked_slot = String(slot_keys[i])
			break
	if picked_slot == "":
		return ""
	# Pick an item within the slot weighted by its drop_weights.
	var slot_pool: Array = pools[picked_slot]
	var item_total: float = 0.0
	for entry in slot_pool:
		item_total += float(entry.weight)
	if item_total <= 0.0:
		return ""
	var item_roll: float = rng.randf() * item_total
	var item_acc: float = 0.0
	for entry in slot_pool:
		item_acc += float(entry.weight)
		if item_roll <= item_acc:
			var picked_id: String = String(entry.id)
			var picked_item: Dictionary = items_db[picked_id]
			if bool(picked_item.get("unique", false)):
				run_dropped_uniques.append(picked_id)
			return picked_id
	# Floating-point fallback: if accumulator never crosses the roll
	# (rare rounding edge case), pick the last entry deterministically.
	var last_entry: Dictionary = slot_pool[slot_pool.size() - 1]
	var last_id: String = String(last_entry.id)
	var last_item: Dictionary = items_db[last_id]
	if bool(last_item.get("unique", false)):
		run_dropped_uniques.append(last_id)
	return last_id

# Slot-locked variant of pick_loot_id. Picks an item of the given rarity
# AND given slot, weighted by drop_weights[src_tier-1] within the slot.
# Used by S4 of_scribe (a02 P-28) to roll bonus spell tomes on boss kills
# without involving SLOT_DROP_WEIGHTS' weapon-heavy distribution.
static func pick_loot_id_for_slot(
	rng: RandomNumberGenerator,
	rarity: String,
	target_slot: String,
	items_db: Dictionary,
	src_tier: int,
	run_dropped_uniques: Array,
) -> String:
	var idx: int = src_tier - 1
	var slot_pool: Array = []
	for id in items_db.keys():
		var item: Dictionary = items_db[id]
		if String(item.get("slot", "")) != target_slot:
			continue
		if String(item.get("rarity", "")) != rarity:
			continue
		if bool(item.get("unique", false)) and run_dropped_uniques.has(id):
			continue
		# S11 boss_drop filter — boss-anchor items only drop via the
		# explicit boss-anchor code path, never via slot rolls.
		if String(item.get("boss_drop", "")) != "":
			continue
		var dw: Array = item.get("drop_weights", [])
		var w: float
		if dw.size() == 5:
			w = float(dw[idx])
			if w <= 0.0:
				continue
		else:
			w = 1.0
		slot_pool.append({"id": id, "weight": w})
	if slot_pool.is_empty():
		return ""
	var item_total: float = 0.0
	for entry in slot_pool:
		item_total += float(entry.weight)
	if item_total <= 0.0:
		return ""
	var item_roll: float = rng.randf() * item_total
	var item_acc: float = 0.0
	for entry in slot_pool:
		item_acc += float(entry.weight)
		if item_roll <= item_acc:
			var picked_id: String = String(entry.id)
			var picked_item: Dictionary = items_db[picked_id]
			if bool(picked_item.get("unique", false)):
				run_dropped_uniques.append(picked_id)
			return picked_id
	var last_entry: Dictionary = slot_pool[slot_pool.size() - 1]
	var last_id: String = String(last_entry.id)
	var last_item: Dictionary = items_db[last_id]
	if bool(last_item.get("unique", false)):
		run_dropped_uniques.append(last_id)
	return last_id

# Map a hue (0–360°) to which stat the recolored item leans toward.
# Mirrors the color-wheel intuition: red→strength, green→haste, etc.
# Used by Bot.recompute_stats to apply a per-instance percentage
# bonus on top of the base item stats.
static func hue_to_stat_lean(hue: float) -> String:
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

static func _gen_instance_id(rng: RandomNumberGenerator) -> String:
	return "%d_%d" % [Time.get_unix_time_from_system(), rng.randi()]

# Construct a fully-rolled item instance from a base id. Pure function
# of (rng, base_id, items_db). Rolls meta-rarity (Ancient/Primal),
# tint/recolor, enchant + enchant combo, artefact tile override (for
# legendaries), quality tier. Affixes via AffixSystem.
static func create_item_instance(
	rng: RandomNumberGenerator,
	base_id: String,
	items_db: Dictionary,
) -> Dictionary:
	var base: Dictionary = items_db.get(base_id, {})
	var affixes: Array = AffixSystem.roll_affixes_for(base, rng)
	var inst: Dictionary = {
		"base_id": base_id,
		"instance_id": _gen_instance_id(rng),
		"affixes": affixes,
	}
	# Meta-rarity roll (D3 Ancient / Primal pattern). Independent of
	# the rarity tier — any drop, even a common, can roll "ancient"
	# (1%) for +20% stats or "primal" (0.1%) for +50% stats. Visual
	# tint changes (gold for ancient, red for primal) plus a name
	# prefix.
	var meta_roll: float = rng.randf()
	var primal_t: float = DropTuning.primal_chance()
	var ancient_t: float = DropTuning.ancient_chance()
	if meta_roll < primal_t:
		inst["meta_rarity"] = "primal"
	elif meta_roll < ancient_t:
		inst["meta_rarity"] = "ancient"
	# Item-authored default_tint short-circuits the random recolor
	# roll. Items with `default_tint: {hue, sat, mode}` in items.json
	# always drop with that recolor — set via item_editor.html's Look
	# section.
	var def_tint: Variant = base.get("default_tint", null)
	if typeof(def_tint) == TYPE_DICTIONARY and String(def_tint.get("mode", "")) != "":
		var d: Dictionary = (def_tint as Dictionary).duplicate(true)
		# Stat lean falls out of hue same as rolled tints, so build
		# editor doesn't have to set it.
		if not d.has("lean"):
			d["lean"] = hue_to_stat_lean(float(d.get("hue", 0.0)))
		if not d.has("lean_pct"):
			d["lean_pct"] = 8.0
		inst["tint"] = d
	# Per-instance recolor roll (~30% of drops get a hue shift; tiny
	# fractions get shimmer/inverted/prismatic). Each hue carries a
	# small stat lean — red leans strength, blue leans regen, etc.
	# Even non-recolored items keep `tint` absent so the runtime
	# can short-circuit the shader for free.
	var tint_roll: float = rng.randf()
	# Tint thresholds layer in priority order (rarest first). Each one
	# pulls from DropTuning so the portal can scale them.
	var prismatic_t: float = DropTuning.tint_prismatic_chance()
	var inverted_t: float = prismatic_t + DropTuning.tint_inverted_chance()
	var shimmer_t: float = inverted_t + DropTuning.tint_shimmer_chance()
	var any_t: float = DropTuning.tint_any_chance()  # absolute, not cumulative
	# If the item already carries a default_tint (set just above), the
	# random roll is suppressed — the author wanted a specific look.
	if inst.has("tint"):
		tint_roll = 999.0
	if tint_roll < prismatic_t:
		inst["tint"] = {
			"hue": rng.randf_range(0.0, 360.0),
			"sat": 1.0,
			"mode": "prismatic",
			"lean": hue_to_stat_lean(rng.randf_range(0.0, 360.0)),
			"lean_pct": 15.0,
		}
	elif tint_roll < inverted_t:
		var h: float = rng.randf_range(0.0, 360.0)
		inst["tint"] = {
			"hue": h, "sat": rng.randf_range(0.6, 1.2), "mode": "inverted",
			"lean": hue_to_stat_lean(h), "lean_pct": 12.0,
		}
	elif tint_roll < shimmer_t:
		var h2: float = rng.randf_range(0.0, 360.0)
		inst["tint"] = {
			"hue": h2, "sat": rng.randf_range(0.9, 1.3), "mode": "shimmer",
			"lean": hue_to_stat_lean(h2), "lean_pct": 10.0,
		}
	elif tint_roll < any_t:
		var h3: float = rng.randf_range(0.0, 360.0)
		inst["tint"] = {
			"hue": h3, "sat": rng.randf_range(0.7, 1.2), "mode": "normal",
			"lean": hue_to_stat_lean(h3), "lean_pct": 7.0,
		}
	# Per-instance "enchant" flavor roll. Static `flavor_tags` on the
	# base item still apply (vampires_tooth is always vampiric); this
	# layer adds an optional ADDITIONAL flavor on top, e.g. "Iron
	# Dagger" rolling fire 5% of the time.
	var enchant_chance: float = float(base.get("enchant_chance", 0.0)) * DropTuning.enchant_chance_mult()
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
			var first_enchant: String = String(candidates[rng.randi_range(0, candidates.size() - 1)])
			inst["enchant"] = first_enchant
			# Enchant combo roll — secondary enchant pick that, if it
			# matches a registered combo with the first, replaces both
			# with the compound.
			var combo_chance: float = DropTuning.enchant_combo_chance()
			if combo_chance > 0.0 and rng.randf() < combo_chance:
				var combo_candidates: Array = []
				for p2 in candidates:
					if String(p2) != first_enchant:
						combo_candidates.append(p2)
				if not combo_candidates.is_empty():
					var second_enchant: String = String(combo_candidates[rng.randi_range(0, combo_candidates.size() - 1)])
					var combo: Dictionary = EnchantCombos.combo_for_pair(first_enchant, second_enchant)
					if not combo.is_empty():
						inst["enchant_combo"] = String(combo.id)
						inst.erase("enchant")
	if String(base.get("rarity", "")) == "legendary":
		var slot: String = String(base.get("slot", "armor"))
		var artefact: String = ArtefactPool.pick_for_slot(slot, rng)
		if artefact != "":
			inst["tile_override"] = "artefacts/" + artefact
	# Quality tier — every drop rolls one (Rusted/Worn/.../Masterwork
	# for gear, Mouldering/.../Sublime for spells). Multiplier scales
	# baseline stats at full strength + affixes at half strength so
	# affix rolls still feel like the rolled axis.
	var quality_slot: String = String(base.get("slot", ""))
	var quality_tier: Dictionary = Quality.roll(quality_slot, rng)
	if not quality_tier.is_empty():
		inst["quality"] = String(quality_tier.name)
	return inst
