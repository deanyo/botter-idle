class_name AffixSystem
extends RefCounted

const AFFIXES_PATH := "res://data/affixes.json"
const BASE_TYPE_AFFIXES_PATH := "res://data/base_type_affixes.json"

# base_type_affixes.json uses readable category aliases ("crit", "haste",
# "strength", …) instead of raw affix ids. Pre-2026-06-09 the loader
# required keys to match an affix id verbatim, so every weight fell
# through the unknown-id filter and silently became uniform applies_to
# fallback. We now expand each category to a small id-list at load time
# so a tower_shield's "stamina:40 regen:10" actually biases toward
# of_vitality / of_the_bear / of_regen / of_lifesteal.
const _CATEGORY_EXPANSION := {
	"crit":     {"of_crit": 1.0},
	"haste":    {"of_haste": 1.0},
	"strength": {"of_might": 0.6, "of_str_mastery": 0.4},
	"agility":  {"of_finesse": 0.6, "of_the_cat": 0.4},
	"stamina":  {"of_vitality": 0.5, "of_the_bear": 0.5},
	"regen":    {"of_regen": 0.6, "of_lifesteal": 0.4},
}

static var _affixes_by_id: Dictionary = {}
static var _rarity_count: Dictionary = {}
static var _rarity_idx: Dictionary = {}
# Per-base-type affix weight maps. base_type → {affix_id: weight}.
# Higher weight = more likely. Missing base_types fall back to the
# applies_to filter on the global pool.
static var _base_type_weights: Dictionary = {}
static var _loaded: bool = false

static func _ensure_loaded() -> void:
	if _loaded:
		return
	var f := FileAccess.open(AFFIXES_PATH, FileAccess.READ)
	if f == null:
		push_error("Failed to open affixes.json")
		_loaded = true
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Failed to parse affixes.json")
		_loaded = true
		return
	var data: Dictionary = parsed
	for af in data.get("affixes", []):
		_affixes_by_id[af.id] = af
	_rarity_count = data.get("rarity_affix_count", {})
	_rarity_idx = data.get("rarity_tier_index", {})
	# Optional file — base-type affix tuning. Absent = global pool only.
	var bt_f := FileAccess.open(BASE_TYPE_AFFIXES_PATH, FileAccess.READ)
	if bt_f != null:
		var bt_parsed: Variant = JSON.parse_string(bt_f.get_as_text())
		if typeof(bt_parsed) == TYPE_DICTIONARY:
			var raw_bt: Dictionary = bt_parsed.get("base_types", {})
			# Expand category aliases ("crit"/"haste"/…) to real affix-ids
			# so the weight pool roll_affixes_for builds carries actual
			# affix entries. Pre-fix the entire file was silently dead.
			for base_type in raw_bt.keys():
				var src: Dictionary = raw_bt[base_type]
				var dst: Dictionary = {}
				for key in src.keys():
					var w: float = float(src[key])
					if w <= 0.0:
						continue
					var sub: Variant = _CATEGORY_EXPANSION.get(key, null)
					if typeof(sub) == TYPE_DICTIONARY:
						for af_id in sub.keys():
							dst[af_id] = float(dst.get(af_id, 0.0)) + w * float(sub[af_id])
					elif _affixes_by_id.has(key):
						dst[key] = float(dst.get(key, 0.0)) + w
				_base_type_weights[base_type] = dst
	_loaded = true

static func roll_affixes_for(item: Dictionary, rng: RandomNumberGenerator) -> Array:
	_ensure_loaded()
	var rarity: String = String(item.get("rarity", "common"))
	var slot: String = String(item.get("slot", ""))
	var n: int = int(_rarity_count.get(rarity, 0))
	if n <= 0:
		return []
	var tier_idx: int = int(_rarity_idx.get(rarity, 0))
	# Priority chain for the affix pool:
	#   1. item.affix_pool override (per-item authored allowlist with
	#      weights, e.g. {"crit": 30, "haste": 10})
	#   2. base_type weights from data/base_type_affixes.json (e.g.
	#      a rapier favors crit; a tower_shield favors stamina)
	#   3. applies_to fallback — uniform pick over all affixes that
	#      can apply to the slot (legacy behavior)
	var weights: Dictionary = {}
	var item_pool: Variant = item.get("affix_pool", null)
	var weights_from_base_type: bool = false
	if typeof(item_pool) == TYPE_DICTIONARY and not item_pool.is_empty():
		weights = item_pool
	else:
		var base_type: String = String(item.get("base_type", ""))
		if base_type != "" and _base_type_weights.has(base_type):
			weights = _base_type_weights[base_type]
			weights_from_base_type = true
	# Build the pool: weighted entries from `weights`, or applies_to
	# fallback at uniform weight 1.
	var pool: Array = []
	if weights.is_empty():
		for id in _affixes_by_id.keys():
			var af: Dictionary = _affixes_by_id[id]
			var applies: Array = af.applies_to
			if applies.has(slot) or applies.has("any"):
				pool.append({"def": af, "weight": 1.0})
	else:
		for af_id in weights.keys():
			var w: float = float(weights[af_id])
			if w <= 0.0 or not _affixes_by_id.has(af_id):
				continue
			# Base-type pools come from category expansion and may include
			# affix-ids that don't apply to this item's slot (e.g.
			# of_str_mastery via "strength" → only helm/amulet/spell). The
			# explicit per-item affix_pool override is trusted as authored.
			if weights_from_base_type:
				var bt_applies: Array = _affixes_by_id[af_id].applies_to
				if not (bt_applies.has(slot) or bt_applies.has("any")):
					continue
			pool.append({"def": _affixes_by_id[af_id], "weight": w})
		# If the override pool somehow ended up empty (all weights 0
		# or unknown ids), fall back to applies_to so the item still
		# gets affixes — better than silently rolling nothing.
		if pool.is_empty():
			for id in _affixes_by_id.keys():
				var af: Dictionary = _affixes_by_id[id]
				var applies: Array = af.applies_to
				if applies.has(slot) or applies.has("any"):
					pool.append({"def": af, "weight": 1.0})
	# Archetype gating on spells: flag-kind affixes (forked /
	# rending / comet_trail / etc) are spell-defining. They should
	# be rare gear-changers, not common-rarity name decoration.
	# Pre-2026-06-07 a Common Magic Dart could roll "Forked +
	# Rending" prefixes that did nothing visible. Now common +
	# uncommon spells skip flag-kind affixes entirely; rolls land
	# on plain stat affixes (channeling/resonance/etc).
	if slot == "spell" and (rarity == "common" or rarity == "uncommon"):
		var filtered: Array = []
		for entry in pool:
			if String(entry.def.get("kind", "flat")) != "flag":
				filtered.append(entry)
		pool = filtered
	var rolled: Array = []
	var used_ids: Dictionary = {}
	_roll_from_weighted(pool, n, used_ids, rolled, tier_idx, rng)
	return rolled

# Weighted pick without replacement. Same shape as the prior
# uniform-pick loop, just biased by the per-affix weight.
static func _roll_from_weighted(pool: Array, want: int, used_ids: Dictionary, into: Array, tier_idx: int, rng: RandomNumberGenerator) -> void:
	if pool.is_empty():
		return
	var attempts: int = 0
	while want > 0 and attempts < 30:
		attempts += 1
		var total_w: float = 0.0
		for entry in pool:
			if not used_ids.has(entry.def.id):
				total_w += float(entry.weight)
		if total_w <= 0.0:
			break  # all options used or weighted out
		var roll: float = rng.randf() * total_w
		var acc: float = 0.0
		var picked: Dictionary = {}
		for entry in pool:
			if used_ids.has(entry.def.id):
				continue
			acc += float(entry.weight)
			if roll <= acc:
				picked = entry.def
				break
		if picked.is_empty():
			continue
		used_ids[picked.id] = true
		var tiers: Array = picked.tiers
		var tier_entry = tiers[mini(tier_idx, tiers.size() - 1)]
		# v2 schema: tier is [min, max]. v1 schema: tier is a single int.
		# Handle both — single int means "fixed value, no range roll."
		var rolled: Dictionary = {"id": picked.id}
		if tier_entry is Array and tier_entry.size() >= 2:
			var lo: int = int(tier_entry[0])
			var hi: int = int(tier_entry[1])
			if String(picked.get("kind", "flat")) == "range":
				# Range affixes carry both bounds — used by tooltip to
				# render "+X-Y" lines and by combat to roll per-hit.
				rolled["value_min"] = lo
				rolled["value_max"] = hi
				# Legacy single-value field gets the midpoint so
				# sum_affix_stats keeps working for callers that don't
				# read value_min/max yet.
				rolled["value"] = int(round((lo + hi) / 2.0))
			else:
				rolled["value"] = rng.randi_range(lo, hi)
		else:
			rolled["value"] = int(tier_entry)
		into.append(rolled)
		want -= 1

static func get_affix_def(id: String) -> Dictionary:
	_ensure_loaded()
	return _affixes_by_id.get(id, {})

# Return every affix def whose `family` field matches. Used by the
# spell showcase to enumerate archetype-family flag affixes for the
# checkbox panel. 2026-06-05.
static func affixes_by_family(family: String) -> Array:
	_ensure_loaded()
	var out: Array = []
	for id in _affixes_by_id.keys():
		var af: Dictionary = _affixes_by_id[id]
		if String(af.get("family", "")) == family:
			out.append(af)
	return out

static func tier_index_for_rarity(rarity: String) -> int:
	_ensure_loaded()
	return int(_rarity_idx.get(rarity, 0))

static func format_item_name(base_name: String, affixes: Array, inst: Variant = null) -> String:
	# Simplified to "BaseName [+Stat, +Stat]" — every affix is just an affix,
	# no prefix/suffix grammar. Empty-affix items show just the base name.
	# Optional `inst` arg: when supplied and inst.meta_rarity is set,
	# prefix the name with "Ancient" / "Primal" so the meta-rarity is
	# visible everywhere format_item_name is called from (HUD inv,
	# Outpost, run report, tooltips).
	_ensure_loaded()
	var prefix: String = ""
	if typeof(inst) == TYPE_DICTIONARY:
		# Quality tier prefix — "Pristine Iron Dagger" / "Rusted Tower
		# Shield" / "Mouldering Fireball Tome". Always rendered if
		# present, regardless of meta-rarity. Skips "Standard" since
		# that's the no-op baseline. Item-overhaul follow-up 2026-06-04.
		var quality: String = String(inst.get("quality", ""))
		if quality != "" and quality != "Standard":
			prefix = quality + " "
		var meta: String = String(inst.get("meta_rarity", ""))
		if meta == "ancient":
			prefix = "Ancient " + prefix
		elif meta == "primal":
			prefix = "Primal " + prefix
	var name_with_prefix: String = prefix + base_name
	if affixes.is_empty():
		return name_with_prefix
	var tags: Array = []
	for af_inst in affixes:
		var def: Dictionary = _affixes_by_id.get(af_inst.id, {})
		if def.is_empty():
			continue
		tags.append("+" + String(def.name))
	if tags.is_empty():
		return name_with_prefix
	return "%s [%s]" % [name_with_prefix, ", ".join(tags)]

static func format_affix_lines(affixes: Array) -> Array:
	_ensure_loaded()
	var lines: Array = []
	for af_inst in affixes:
		var def: Dictionary = _affixes_by_id.get(af_inst.id, {})
		if def.is_empty():
			continue
		var stat: String = String(def.stat)
		var v: int = int(af_inst.value)
		if v == 0:
			continue
		lines.append(_format_stat_line(stat, v))
	return lines

# Plain-English description of what each affix stat actually does, keyed
# by the affix's `stat` field. Surfaces under the stat line when Alt is
# held in the tooltip — players read flavor names like "of Bloodletting"
# without knowing they're seeing lifesteal. PLAYTEST 2026-06-10 #2.
const _STAT_DESCRIPTIONS := {
	# Base item stats (rendered at the top of the tooltip — these have
	# no rolled affix value so {N} placeholders aren't substituted; keep
	# the wording behavior-focused, not roll-focused).
	"damage": "Per swing/cast: rolls a value in [min, max].",
	"attack_speed": "Seconds between swings (lower = faster).",
	"spell_cooldown": "Seconds between casts (lower = faster).",
	# Core stats. {N} resolves to the rolled value when called from an
	# affix line; left literal for base-stat lines.
	"hp": "Adds {N} to your max health.",
	"hp_regen": "Restores {N} HP every second.",
	"str": "+{N} Strength. Each excess STR (over 5): +1.5% max HP, +melee damage scaling.",
	"dex": "+{N} Dexterity. Each excess DEX (over 5): +0.5% crit, +1% haste.",
	"int": "+{N} Intelligence. Each excess INT (over 5): +1% spell damage, +0.5% area, +0.5% duration.",
	"armor": "Subtracts {N} from each incoming physical hit (post-crit).",
	"evasion": "+{N}% chance to fully dodge an incoming attack.",
	"crit_chance": "+{N}% chance per swing to deal crit damage.",
	"crit_multiplier_pct": "Crit hits deal +{N}% of base damage on top.",
	"block_chance": "+{N}% chance per incoming hit to trigger a block.",
	"block_amount": "Blocks subtract {N} from the incoming hit.",
	"haste_pct": "Multiplies swing speed and spell cycling by 1 + {N}/100.",
	"lifesteal_pct": "Heals you for {N}% of damage dealt.",
	# Spell tuning stats.
	"spell_damage_pct": "Multiplies all spell damage by 1 + {N}/100.",
	"spell_cdr_pct": "Reduces spell cooldowns by {N}% (multiplicative).",
	"spell_proj_bonus": "Adds +{N} projectiles per cast.",
	"spell_proj_speed_pct": "Multiplies projectile speed by 1 + {N}/100.",
	"spell_area_pct": "Multiplies spell area/cone size by 1 + {N}/100.",
	"spell_duration_pct": "Multiplies lingering-effect duration by 1 + {N}/100.",
	# Element-coded spell-school masteries.
	"fire_dmg_pct": "Multiplies fire-element spell damage by 1 + {N}/100.",
	"cold_dmg_pct": "Multiplies cold-element spell damage by 1 + {N}/100.",
	"lightning_dmg_pct": "Multiplies lightning-element spell damage by 1 + {N}/100.",
	"holy_dmg_pct": "Multiplies holy-element spell damage by 1 + {N}/100.",
	"poison_dmg_pct": "Multiplies poison-element spell damage by 1 + {N}/100.",
	"dark_dmg_pct": "Multiplies dark-element spell damage by 1 + {N}/100.",
	# Stat-class spell masteries.
	"str_spell_dmg_pct": "Multiplies STR-scaling spell damage by 1 + {N}/100.",
	"dex_spell_dmg_pct": "Multiplies DEX-scaling spell damage by 1 + {N}/100.",
	"int_spell_dmg_pct": "Multiplies INT-scaling spell damage by 1 + {N}/100.",
	# +X-Y bonus damage on hit (range affixes — {LO}/{HI} pull from
	# value_min/value_max so each hit deals exactly that range).
	"fire_extra": "Adds {LO}-{HI} fire damage to each hit.",
	"cold_extra": "Adds {LO}-{HI} cold damage to each hit.",
	"thunderous_extra": "Adds {LO}-{HI} lightning damage to each hit.",
	"lightning_extra": "Adds {LO}-{HI} lightning damage to each hit.",
	"holy_extra": "Adds {LO}-{HI} holy damage to each hit.",
	"poison_extra": "Adds {LO}-{HI} poison damage to each hit.",
	"dark_extra": "Adds {LO}-{HI} dark damage to each hit.",
	"physical_extra": "Adds {LO}-{HI} physical damage to each hit.",
	# Resistances.
	"fire_res": "Subtracts {N}% from incoming fire damage.",
	"cold_res": "Subtracts {N}% from incoming cold damage.",
	"lightning_res": "Subtracts {N}% from incoming lightning damage.",
	"holy_res": "Subtracts {N}% from incoming holy damage.",
	"poison_res": "Subtracts {N}% from incoming poison damage.",
	"dark_res": "Subtracts {N}% from incoming dark damage.",
	# Misc utility.
	"loot_rarity_bonus": "+{N}% to upgrade-tier rolls on every drop.",
	"xp_gain_pct": "Multiplies XP gained by 1 + {N}/100.",
	"aggro_bonus": "Enemy aggro radius += {N} tiles.",
	"move_speed": "Walk speed × 1 + {N}/100.",
	"gold_drop_pct": "Gold dropped × 1 + {N}/100.",
	"spell_tome_drop_pct": "+{N}% chance per boss kill to drop a bonus spell tome.",
	# Named-effect affixes — opaque flavor names → mathematical mechanics.
	"tempest_dmg_pct": "+{N}% spell damage; spell cooldowns +({N}/3)% (penalty).",
	"synergy_pct": "+{N}% all damage IF you also carry a STR + DEX + INT affix simultaneously.",
	"sage_per_unspent_pct": "+({N} × min(unspent, 10) / 10)% spell damage. Caps at {N}% with 10 unspent.",
	"berserker_peak_pct": "Each kill (3s window) adds a stack (cap 5). Each stack: +({N}/5)% damage.",
	"hunter_pct": "+{N}% damage to targets above 80% HP.",
	"str_dmg_per5_peak_pct": "Per 5 excess STR (cap 10 ranks): +({N}/10)% damage. Peak +{N}% at +50 STR.",
	"echo_every_n": "Every {N}-th swing fires a free echo strike. Lower N = more often.",
	"sundering_per_stack": "Each hit stacks -{N} armor on the target (max 2 stacks).",
	"bloodletting_per_stack": "Each hit applies a 4-tick bleed dealing {N} physical/sec.",
	# Spell-archetype flag affixes — each modifies one specific spell.
	"spell_axes_bleed": "Spinning Axes: hits leave a bleed (4s, scales with weapon damage).",
	"spell_chain_extra_jumps": "Chain Lightning: +{N} additional bounce targets per cast.",
	"spell_dart_split": "Magic Dart: each cast splits into {N} shards.",
	"spell_fireball_ground": "Fireball: leaves a 3s ground-fire on impact (scales with spell damage).",
	"spell_frost_root": "Frost Nova: hit enemies are rooted for 1s.",
	"spell_holy_radiance": "Holy Beam: pulses damage in a 1.5-tile aura around the target.",
	"spell_iron_dust": "Earthbreaker: leaves an iron-dust cloud (slow + small DoT).",
	"spell_sandblast_blind": "Sandblast: hit enemies have +30% miss chance for 3s.",
	"spell_shatter_aftershock": "Shatter: triggers a delayed AoE 0.6s after impact.",
	"spell_drain_buff": "Cast: gain a 4s self-buff that converts {N}% of damage dealt into healing.",
	# S11 boss-anchor unique mechanics (a07 §6.1-6.12). Each maps 1:1 to one
	# implicit_affix on a single boss-anchor item.
	"bleed_on_miss": "On a missed melee swing: 100% chance to apply a 3s bleed (4 dmg/s).",
	"dancing_blade": "On melee hit: 25% chance to fire an extra weapon-damage strike at the same target.",
	"polymorph_first_kill": "First kill each floor splits into a friendly slime (50 ATK, 1 floor lifespan).",
	"wolf_kinship_pct": "+{N}% damage to wolf-family enemies (wolf, hound, hell hound, wolf spider).",
	"anchor_regen": "+{N} HP/sec regeneration while equipped.",
	"hp_per_kill_cap": "+1 max HP per kill on this floor (cap +{N}; resets each floor).",
	"tidesong_water_pct": "+{N}% damage to enemies standing on water tiles.",
	"venom_on_hit": "Each melee hit applies 1 stack of poison (3 ticks × 0.5s, max 5 stacks).",
	"phylactery_revive_pct": "Once per floor: revive at {N}% max HP on lethal damage.",
	"extra_chests_per_floor": "+{N} chest spawned each floor.",
	"fifth_cast_pct": "Every 5th spell cast deals +{N}% damage (counter resets each floor).",
	# §1.H attempt_attack-shape conditional affixes (a02 P-001..005, a10 caps).
	"low_hp_target_dmg_pct": "+{N}% damage to enemies below 30% HP. Cap 40.",
	"glass_cannon_dmg_pct": "+{N}% damage while above 80% HP. Cap 30. (Mutex with low_hp_target_dmg_pct.)",
	"low_hp_dr_pct": "Take {N}% less damage while below 40% HP. Cap 28.",
	"boss_dmg_pct": "+{N}% damage to bosses, elites, and uniques. Cap 40.",
	"pack_dmg_per_enemy_pct": "+{N}% damage per enemy within 3 tiles (cap 5 enemies).",
	"full_hp_armor_pct": "+{N}% armor while at full HP. Cap 75.",
	"weapon_bleed_per_sec": "Each landed hit applies a 4s bleed dealing {N} physical/sec.",
	"holy_dot_per_sec": "Each landed hit applies a 3s holy burn dealing {N} holy/sec.",
	"revenge_dmg_pct": "After taking damage: +{N}% damage for 3s. Cap 50.",
	"first_hit_pct": "Your first hit on each enemy deals +{N}% damage. Per-target gate, no stack.",
	"hp_per_kill_flat": "+{N} HP per kill. Counts toward the +max_hp/floor cap (of_serpent_growth).",
	"melee_armor_pen_pct": "Your melee attacks ignore {N}% of enemy armor. Cap 50.",
	"spell_resist_pen_pct": "Elemental hits ignore {N}% of enemy resistance. Cap 35.",
	"crit_mark_dmg_pct": "On crit: mark target for 4s. Marked enemies take +{N}% damage. Cap 40.",
	"recoup_pct": "After taking damage: heal {N}% of damage taken over 4s. Cap 28.",
	"move_spell_dmg_pct": "+{N}% spell damage while moving. Cap 40.",
	"thorns_flat": "Reflects {N} damage back at the attacker on every hit you take. Cap 25.",
	"block_thorns_flat": "On block: reflect {N} damage back at the attacker. Shield-only. Cap 50.",
	"first_hit_mark_pct": "First hit on each enemy applies a 3s mark: target takes +{N}% damage from all sources. Cap 25.",
	"doomstrike_dmg_pct": "Every 5th swing deals +{N}% damage. Cannot crit. Cap 100.",
	"riposte_dmg_pct": "When your swing is evaded or blocked: counter-strike for {N}% of weapon damage. Procs once per second.",
	"high_hp_cdr_pct": "+{N}% spell cooldown reduction while above 90% HP. Cap 20.",
	"kill_streak_cdr_pct": "Each kill (3s window) adds a stack (cap 4). Each stack: +{N}% spell CDR. Cap 7/stack.",
	"crit_chain_pct": "On crit: chain to the nearest enemy within 4 tiles for {N}% of the crit's damage. Cap 50.",
	"step_pulse_pct": "Every 8 cells walked: discharge a 2-tile AoE for {N}% of weapon damage. Cap 80.",
	"loot_quantity_pct": "+{N}% chance to spawn an extra loot drop on each kill that drops loot. Hard cap 50.",
	"damage_taken_pct": "Take {N}% less damage from all sources. Cap 40.",
	"dot_duration_pct": "+{N}% duration on damage-over-time effects you apply (bleed, burn, poison, smite). Cap 80.",
	"damage_vs_unique_pct": "+{N}% damage to rare-tier (named pack) enemies. Cap 40.",
	"low_hp_dmg_pct": "+{N}% damage while below 40% HP. Cap 30. (Mutex with glass_cannon_dmg_pct.)",
	# §2.J mana-axis affixes.
	"mana_max_flat": "+{N} mana_max (raises the spell-cast pool ceiling).",
	"mana_regen_pct": "+{N}% mana regen rate. Cap 100.",
	"mana_cost_pct": "{N}% mana cost on every spell cast (negative = discount). Cap -50.",
	"mana_floor_start_flat": "+{N} mana on every floor entry (extra ammo for the first pack).",
	"mana_on_hit_flat": "+{N} mana per landed melee hit (caster-melee bridge).",
}

# Note: of_devastation / of_iron_aegis / of_steadfast write into already-
# documented stat keys (crit_multiplier_pct / block_chance / block_amount).
# Their descriptions live above; no new entries needed.

static func description_for_stat(stat: String) -> String:
	return String(_STAT_DESCRIPTIONS.get(stat, ""))

# Stats whose flavor name ("of the Tempest", "Bleeding Edge") is opaque
# without a description. The tooltip always renders these descriptions
# inline regardless of Alt — no need to discover the binding to read
# what your item does. Plain-stat affixes (str/dex/hp/etc) stay
# Alt-gated since "+5 Strength" already self-documents.
const _NAMED_EFFECT_STATS := {
	"tempest_dmg_pct": true,
	"synergy_pct": true,
	"sage_per_unspent_pct": true,
	"berserker_peak_pct": true,
	"hunter_pct": true,
	"str_dmg_per5_peak_pct": true,
	"echo_every_n": true,
	"sundering_per_stack": true,
	"bloodletting_per_stack": true,
	"spell_axes_bleed": true,
	"spell_chain_extra_jumps": true,
	"spell_dart_split": true,
	"spell_fireball_ground": true,
	"spell_frost_root": true,
	"spell_holy_radiance": true,
	"spell_iron_dust": true,
	"spell_sandblast_blind": true,
	"spell_shatter_aftershock": true,
	"spell_drain_buff": true,
	# S11 boss-anchor opaque-name flavors → always emit description.
	"bleed_on_miss": true,
	"dancing_blade": true,
	"polymorph_first_kill": true,
	"wolf_kinship_pct": true,
	"anchor_regen": true,
	"hp_per_kill_cap": true,
	"tidesong_water_pct": true,
	"venom_on_hit": true,
	"phylactery_revive_pct": true,
	"extra_chests_per_floor": true,
	"fifth_cast_pct": true,
	"low_hp_target_dmg_pct": true,
	"glass_cannon_dmg_pct": true,
	"low_hp_dr_pct": true,
	"boss_dmg_pct": true,
	"pack_dmg_per_enemy_pct": true,
	"full_hp_armor_pct": true,
	"weapon_bleed_per_sec": true,
	"holy_dot_per_sec": true,
	"revenge_dmg_pct": true,
	"first_hit_pct": true,
	"hp_per_kill_flat": true,
	"melee_armor_pen_pct": true,
	"spell_resist_pen_pct": true,
	"crit_mark_dmg_pct": true,
	"recoup_pct": true,
	"move_spell_dmg_pct": true,
	"thorns_flat": true,
	"block_thorns_flat": true,
	"first_hit_mark_pct": true,
	"doomstrike_dmg_pct": true,
	"riposte_dmg_pct": true,
	"high_hp_cdr_pct": true,
	"kill_streak_cdr_pct": true,
	"crit_chain_pct": true,
	"step_pulse_pct": true,
	"loot_quantity_pct": true,
	"damage_taken_pct": true,
	"dot_duration_pct": true,
	"damage_vs_unique_pct": true,
	"low_hp_dmg_pct": true,
}

static func is_named_effect_stat(stat: String) -> bool:
	return _NAMED_EFFECT_STATS.has(stat)

static func _format_stat_line(stat: String, v: int) -> String:
	# Items v2 (2026-06-04) replaced atk/def with damage_min/max + armor +
	# evasion. No live affix uses "atk" or "def" any more — those cases
	# were dead pattern-matches kept around from v1.
	match stat:
		"hp": return "+%d HP" % v
		"hp_regen": return "+%d HP/sec" % v
		"crit_chance": return "+%d%% Crit" % v
		"str": return "+%d Str" % v
		"dex": return "+%d Dex" % v
		"int": return "+%d Int" % v
		"spell_cdr_pct": return "-%d%% Spell Cooldown" % v
		"spell_proj_bonus": return "+%d Spell Projectile" % v if v == 1 else "+%d Spell Projectiles" % v
		"spell_proj_speed_pct": return "+%d%% Projectile Speed" % v
		"spell_area_pct": return "+%d%% Spell Area" % v
		"spell_duration_pct": return "+%d%% Spell Duration" % v
		"spell_damage_pct": return "+%d%% Spell Damage" % v
		"crit_multiplier_pct": return "+%d%% Crit Damage" % v
		"block_chance": return "+%d%% Block Chance" % v
		"block_amount": return "+%d Block Amount" % v
		"fire_dmg_pct": return "+%d%% Fire Damage" % v
		"cold_dmg_pct": return "+%d%% Cold Damage" % v
		"lightning_dmg_pct": return "+%d%% Lightning Damage" % v
		"holy_dmg_pct": return "+%d%% Holy Damage" % v
		"poison_dmg_pct": return "+%d%% Poison Damage" % v
		"dark_dmg_pct": return "+%d%% Dark Damage" % v
	return "+%d %s" % [v, stat]

# Canonical hover tooltip for an item. Used by every UI surface that shows
# items so the format never drifts between HUD / Outpost / menu.
#   Line 1: "Item Name [rarity]"
#   Line 2: base "+X ATK +Y DEF +Z HP" (zeros suppressed)
#   Line N: each affix on its own line
static func format_item_tooltip(item_def: Dictionary, inst: Variant) -> String:
	if item_def.is_empty():
		return ""
	var affixes: Array = []
	if typeof(inst) == TYPE_DICTIONARY:
		affixes = inst.get("affixes", [])
	var disp_name: String = format_item_name(String(item_def.get("name", "")), affixes, inst)
	var rarity: String = String(item_def.get("rarity", "")).capitalize()
	var lines: Array = []
	# Append 2H badge to the rarity slot when applicable so the tooltip
	# telegraphs the shield-exclusion. Dual-wield class deferred (S6).
	var rarity_chunk: String = rarity
	if Bot.is_two_handed(item_def):
		var badge: String = "2H"
		rarity_chunk = (rarity + " · " + badge) if rarity != "" else badge
	lines.append("%s [%s]" % [disp_name, rarity_chunk] if rarity_chunk != "" else disp_name)
	# Meta-rarity line — Ancient (1%) or Primal (0.1%) per drop. Stat
	# multiplier is +20% / +50% baked into bot.recompute_stats so the
	# numbers in the line below already reflect it; this line just
	# tells the player WHY their stats look beefier than usual.
	if typeof(inst) == TYPE_DICTIONARY:
		var meta: String = String(inst.get("meta_rarity", ""))
		if meta == "ancient":
			lines.append("[Ancient]  +20% base stats")
		elif meta == "primal":
			lines.append("[Primal]  +50% base stats — extremely rare")
		# Tint roll line — describes what visual treatment the item
		# rolled and the stat lean that came with it.
		var tint: Variant = inst.get("tint", null)
		if typeof(tint) == TYPE_DICTIONARY:
			var mode: String = String(tint.get("mode", "normal"))
			var lean: String = String(tint.get("lean", ""))
			var lean_pct: float = float(tint.get("lean_pct", 0.0))
			var mode_labels: Dictionary = {
				"normal": "Tinted",
				"shimmer": "✦ Shimmering",
				"inverted": "⌧ Inverted",
				"prismatic": "◇ Prismatic",
			}
			var mode_label: String = String(mode_labels.get(mode, "Tinted"))
			lines.append("[%s]  +%.0f%% %s" % [mode_label, lean_pct, lean])
	# Items v2 schema (2026-06-04): weapons carry damage_min/damage_max,
	# body slots carry armor + evasion. Pre-v2 atk/def/hp were the
	# baseline keys; those are gone everywhere in items.json now.
	var base_parts: Array = []
	var dmin: int = int(item_def.get("damage_min", 0))
	var dmax: int = int(item_def.get("damage_max", 0))
	var armor_v: int = int(item_def.get("armor", 0))
	var evasion_v: int = int(item_def.get("evasion", 0))
	if dmin > 0 or dmax > 0:
		base_parts.append("%d-%d Dmg" % [dmin, dmax])
	if armor_v > 0: base_parts.append("+%d Armor" % armor_v)
	if evasion_v > 0: base_parts.append("+%d%% Evasion" % evasion_v)
	# Item secondary stats — direct contributions distinct from
	# rolled affixes. Hidden when zero so most items stay clean.
	var crit_v: float = float(item_def.get("crit_chance", 0))
	var hst_v: float = float(item_def.get("atk_speed_pct", 0))
	var rgn_v: float = float(item_def.get("hp_regen", 0))
	if crit_v > 0: base_parts.append("+%d%% Crit" % int(round(crit_v)))
	if hst_v > 0: base_parts.append("+%d%% Haste" % int(round(hst_v)))
	if rgn_v > 0: base_parts.append("+%.1f HP/s" % rgn_v)
	if not base_parts.is_empty():
		lines.append("  ".join(base_parts))
	var affix_lines: Array = format_affix_lines(affixes)
	lines.append_array(affix_lines)
	# Per-instance enchant line. Drop chance is rolled in
	# dungeon._create_item_instance and stored on inst.enchant; we
	# render a short mechanic blurb so the player understands what
	# the rolled flavor does.
	if typeof(inst) == TYPE_DICTIONARY:
		var enchant: String = String(inst.get("enchant", ""))
		if enchant != "":
			var blurb: String = ENCHANT_BLURBS.get(enchant, "")
			if blurb != "":
				lines.append("✦ Enchant — %s: %s" % [enchant.capitalize(), blurb])
			else:
				lines.append("✦ Enchant — %s" % enchant.capitalize())
	return "\n".join(lines)

# One-line mechanic descriptions per enchant flavor — surfaced in the
# tooltip so the player understands what they rolled. Numbers track
# the actual mechanics in actor.gd::attempt_attack and elsewhere; if
# those are tuned, update here too.
const ENCHANT_BLURBS := {
	"vampiric":    "8% of damage dealt heals you.",
	"fire":        "On hit, burns target for 4% max HP × 3 ticks.",
	"cold":        "15% chance to freeze; +20% damage vs frozen.",
	"holy":        "+50% damage vs undead and demons.",
	"poison":      "On hit, poisons target for 3% max HP × 4 ticks.",
	"thunderous":  "On hit, splash 50% to one adjacent enemy.",
	"dark":        "Grim aura. (passive flavor)",
	"dragon_bane": "+50% damage vs dragons and wyrms.",
	"brutal":      "+25% damage vs targets ≤30% HP.",
	"precision":   "Anti-streak crit: +5%/swing toward +50% cap.",
	"rage":        "+5% atk per kill within 6s, cap +30%.",
	"thorns":      "Returns 15% of damage taken to attackers.",
	"reflective":  "10% chance to fully negate an incoming hit.",
	"harm":        "+25% damage dealt and taken.",
	"vitality":    "+1 HP regen per second.",
	"fortified":   "+20% defense (per source, cap +50%).",
	"willpower":   "-25% damage from elemental and arcane attackers.",
	"swiftness":   "+10% move speed (per source, cap +30%).",
	"regen":       "+0.5 HP regen per second.",
	"stealth":     "First attack each floor lands +25%.",
	"lordly":      "+15% XP gained.",
	"footwork":    "8% chance to fully evade an attack.",
	"warding":     "-20% damage from boss / miniboss attackers.",
	"elemental":   "+1% damage per character level (scales with you).",
	"wisdom":      "+15% XP gained.",
	"arcane":      "Every 4th swing: +50% magic burst.",
	"fire_res":    "-50% fire damage; immune to burn DoT.",
	"cold_res":    "-50% cold damage; immune to freeze.",
	"poison_res":  "Immune to poison DoT.",
	"vision":      "+1 aggro range (engage enemies further out).",
	"rampaging":   "On kill, refund attack cooldown.",
	"flying":      "Ignore water slow.",
	"fortune":     "+20% loot drop chance.",
	"faith":       "+50% fountain heal; +0.5 HP regen.",
	"acrobat":     "When below 30% HP, -17% damage taken.",
	"death":       "On kill, 25% chance to splash 5% atk to adjacent.",
	"earth":       "-15% damage from physical attackers.",
	"guardian":    "Flat -10% damage taken.",
	"demon":       "+25% damage vs undead and demons.",
	"crystal":     "Returns 5% of damage taken (passive thorns).",
	"dual":        "15% chance to attack twice.",
	"sound":       "10% chance to stun for 1s on hit.",
	"ponderous":   "+10% damage but -10% attack speed.",
	"slaying":     "Stat-flavor (already on base atk).",
	"psychic":     "Mind-shielded. (decorative for now)",
	"agility":     "Stat-flavor (already on base evasion).",
	"shadow":      "Umbral. (decorative for now)",
	# S5 race-anchor conditional flavors (a04 §5 + a10 rescopes).
	"feast":       "On kill, heal +2% max HP (capped at 50% MHP/s).",
	"first_blood": "+20% damage on the first swing of a new encounter.",
	"petrify":     "-25% physical damage taken while stationary.",
	# S11 boss-anchor display flavors (a07 §6.1-6.12). Decorative — these
	# tags color the inventory chrome but do not carry their own combat
	# mechanic; the unique's behavior lives in implicit_affixes.
	"bloody":      "Stained with old blood.",
	"bloodlust":   "Hungry for the next kill.",
	"tide":        "Heavy with sea-spray.",
}

static func sum_affix_stats(affixes: Array) -> Dictionary:
	_ensure_loaded()
	var sums: Dictionary = {}
	for af_inst in affixes:
		var def: Dictionary = _affixes_by_id.get(af_inst.id, {})
		if def.is_empty():
			continue
		var stat: String = String(def.stat)
		sums[stat] = sums.get(stat, 0) + int(af_inst.get("value", 0))
		# Range affixes (kind=range, e.g. of_embers, of_sharpness) also
		# carry value_min / value_max so combat can roll a fresh value
		# per hit. We accumulate the bounds under "<stat>_min" /
		# "<stat>_max" keys so callers can reach them without re-walking
		# the affix list.
		if af_inst.has("value_min") and af_inst.has("value_max"):
			sums[stat + "_min"] = sums.get(stat + "_min", 0) + int(af_inst["value_min"])
			sums[stat + "_max"] = sums.get(stat + "_max", 0) + int(af_inst["value_max"])
	return sums
