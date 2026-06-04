class_name Quality
extends RefCounted

# Quality tier system — every drop rolls one of 20 named tiers between
# 0.80x (Rusted / Mouldering) and 1.20x (Masterwork / Sublime). Stacks
# on top of rarity + meta-rarity. Distribution centers around
# 1.00x Standard so most drops feel "normal"; the extremes create the
# screenshot-bait moments at the tail. Item-overhaul follow-up
# 2026-06-04.
#
# Quality affects:
#   - Baseline stats (damage_min/max, armor, evasion) at FULL strength
#   - Affix values at HALF strength (so a 1.20x Masterwork gives
#     affixes +10%, not +20% — keeps affixes feeling rolled, not
#     overruled by quality alone)
#
# Stored on the per-instance dict as inst.quality = "Pristine" etc.
# Tier name is the key into TIERS so we can also pull display color +
# multiplier on demand.

# Gear quality tiers (weapons + body + jewelry). Workmanlike names —
# the visual feel of "this thing is built to last" or "this thing has
# seen better days."
const GEAR_TIERS := [
	{ "name": "Rusted",       "mult": 0.80, "weight": 4 },
	{ "name": "Worn",         "mult": 0.83, "weight": 8 },
	{ "name": "Battered",     "mult": 0.85, "weight": 10 },
	{ "name": "Crude",        "mult": 0.88, "weight": 14 },
	{ "name": "Common",       "mult": 0.90, "weight": 30 },
	{ "name": "Plain",        "mult": 0.93, "weight": 50 },
	{ "name": "Sturdy",       "mult": 0.95, "weight": 80 },
	{ "name": "Honest",       "mult": 0.97, "weight": 100 },
	{ "name": "Standard",     "mult": 1.00, "weight": 150 },
	{ "name": "Tempered",     "mult": 1.02, "weight": 100 },
	{ "name": "Heirloom",     "mult": 1.05, "weight": 70 },
	{ "name": "Reinforced",   "mult": 1.08, "weight": 40 },
	{ "name": "Pristine",     "mult": 1.10, "weight": 22 },
	{ "name": "Forged",       "mult": 1.12, "weight": 14 },
	{ "name": "Refined",      "mult": 1.14, "weight": 9 },
	{ "name": "Exceptional",  "mult": 1.16, "weight": 5 },
	{ "name": "Superior",     "mult": 1.17, "weight": 3 },
	{ "name": "Exquisite",    "mult": 1.18, "weight": 2 },
	{ "name": "Mastercrafted","mult": 1.19, "weight": 1 },
	{ "name": "Masterwork",   "mult": 1.20, "weight": 1 },  # halved by floor below; top is genuinely rare
]

# Spell-tome quality tiers. Thematic for tomes/scrolls — bookish,
# magical, condition-of-the-paper. Same multiplier curve so a
# Masterwork sword and a Sublime tome feel mechanically equivalent.
const SPELL_TIERS := [
	{ "name": "Mouldering",  "mult": 0.80, "weight": 4 },
	{ "name": "Tattered",    "mult": 0.83, "weight": 8 },
	{ "name": "Faded",       "mult": 0.85, "weight": 10 },
	{ "name": "Dusty",       "mult": 0.88, "weight": 14 },
	{ "name": "Yellowed",    "mult": 0.90, "weight": 30 },
	{ "name": "Worn",        "mult": 0.93, "weight": 50 },
	{ "name": "Bound",       "mult": 0.95, "weight": 80 },
	{ "name": "Studied",     "mult": 0.97, "weight": 100 },
	{ "name": "Standard",    "mult": 1.00, "weight": 150 },
	{ "name": "Annotated",   "mult": 1.02, "weight": 100 },
	{ "name": "Embossed",    "mult": 1.05, "weight": 70 },
	{ "name": "Gilded",      "mult": 1.08, "weight": 40 },
	{ "name": "Pristine",    "mult": 1.10, "weight": 22 },
	{ "name": "Runed",       "mult": 1.12, "weight": 14 },
	{ "name": "Resonant",    "mult": 1.14, "weight": 9 },
	{ "name": "Glyphed",     "mult": 1.16, "weight": 5 },
	{ "name": "Sigilled",    "mult": 1.17, "weight": 3 },
	{ "name": "Eldritch",    "mult": 1.18, "weight": 2 },
	{ "name": "Archlight",   "mult": 1.19, "weight": 1 },
	{ "name": "Sublime",     "mult": 1.20, "weight": 1 },
]

# Roll a quality tier given the item's slot. Returns the tier dict
# {name, mult, weight}. Spell slot uses SPELL_TIERS for thematic
# naming; everything else uses GEAR_TIERS.
static func roll(slot: String, rng: RandomNumberGenerator) -> Dictionary:
	var table: Array = SPELL_TIERS if slot == "spell" else GEAR_TIERS
	var total_w: float = 0.0
	for t in table:
		total_w += float(t.weight)
	var r: float = rng.randf() * total_w
	var acc: float = 0.0
	for t in table:
		acc += float(t.weight)
		if r <= acc:
			return t
	return table[8]  # fallback to Standard

# Look up a tier by name across both tables. Returns the dict or
# {} if not found. Tooltip + name-prefix logic uses this to fetch
# the multiplier from the stored inst.quality string.
static func get_tier(name: String) -> Dictionary:
	for t in GEAR_TIERS:
		if String(t.name) == name:
			return t
	for t in SPELL_TIERS:
		if String(t.name) == name:
			return t
	return {}

# Effective multiplier for an instance's stored quality tier. Returns
# 1.0 for missing / unknown tiers (back-compat with existing items).
static func multiplier_for(inst: Variant) -> float:
	if typeof(inst) != TYPE_DICTIONARY:
		return 1.0
	var name: String = String(inst.get("quality", ""))
	if name == "":
		return 1.0
	var tier: Dictionary = get_tier(name)
	if tier.is_empty():
		return 1.0
	return float(tier.get("mult", 1.0))

# Affix multiplier — half strength of the baseline multiplier so
# affixes still feel rolled rather than dominated by quality. A 1.20x
# Masterwork → 1.10x affix bonus; 0.80x Rusted → 0.90x affix penalty.
static func affix_multiplier_for(inst: Variant) -> float:
	var m: float = multiplier_for(inst)
	return 1.0 + (m - 1.0) * 0.5

# Percentile rank of a tier within its table (0..100, 100 = top).
# Used by the Alt-extended tooltip to show "top 6%" / "bottom 4%"
# context — gives the player a sense of how lucky the roll was.
static func percentile_for(name: String, slot: String) -> int:
	var table: Array = SPELL_TIERS if slot == "spell" else GEAR_TIERS
	var idx: int = -1
	for i in table.size():
		if String(table[i].name) == name:
			idx = i
			break
	if idx < 0:
		return 50
	# Sum weights at-or-above this index → that's the chance of
	# rolling THIS tier or better. Convert to a top-X% reading.
	var total_w: float = 0.0
	var above_w: float = 0.0
	for i in table.size():
		var w: float = float(table[i].weight)
		total_w += w
		if i >= idx:
			above_w += w
	if total_w <= 0.0:
		return 50
	return int(round(100.0 * above_w / total_w))

# Visual tier color — drives title hue + tooltip glow accent.
# Below-Standard quality dims toward grey; above-Standard goes warmer
# from amber → gold → white-gold at the top tier.
static func color_for(name: String) -> Color:
	var tier: Dictionary = get_tier(name)
	if tier.is_empty():
		return Color(0.85, 0.85, 0.85)
	var m: float = float(tier.get("mult", 1.0))
	# Map mult ∈ [0.80, 1.20] linearly into a warm-cool gradient.
	if m < 1.0:
		var t: float = (1.0 - m) / 0.20  # 0..1 for 1.0..0.80
		# Cool grey shading for below-standard.
		return Color(0.85, 0.85, 0.85).lerp(Color(0.55, 0.55, 0.60), t)
	else:
		var t: float = (m - 1.0) / 0.20  # 0..1 for 1.0..1.20
		# Warm gold ascending for above-standard.
		return Color(0.85, 0.85, 0.85).lerp(Color(1.00, 0.92, 0.45), t)

# Eye-candy gating thresholds — shared across tooltip animations.
# The tooltip reads these to decide which animations to spawn.
const PULSE_THRESHOLD := 1.10   # Pristine + above
const SHIMMER_THRESHOLD := 1.16 # Exceptional + above
const PARTICLES_THRESHOLD := 1.19  # Mastercrafted + Masterwork

static func has_pulse(inst: Variant) -> bool:
	return multiplier_for(inst) >= PULSE_THRESHOLD

static func has_shimmer(inst: Variant) -> bool:
	return multiplier_for(inst) >= SHIMMER_THRESHOLD

static func has_particles(inst: Variant) -> bool:
	return multiplier_for(inst) >= PARTICLES_THRESHOLD
