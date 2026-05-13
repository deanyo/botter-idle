class_name VaultLibrary
extends RefCounted

const VAULT_DIR := "res://data/vaults/"

static var _vaults: Array = []
static var _loaded: bool = false

static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var dir := DirAccess.open(VAULT_DIR)
	if dir == null:
		push_error("Vault dir not found: %s" % VAULT_DIR)
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if not dir.current_is_dir() and name.ends_with(".json"):
			var f := FileAccess.open(VAULT_DIR + name, FileAccess.READ)
			if f != null:
				var parsed: Variant = JSON.parse_string(f.get_as_text())
				if typeof(parsed) == TYPE_DICTIONARY:
					_annotate_vault(parsed)
					_vaults.append(parsed)
				else:
					push_error("Failed to parse vault: %s" % name)
		name = dir.get_next()
	dir.list_dir_end()

static func all_vaults() -> Array:
	_ensure_loaded()
	return _vaults

# Count "C" chest glyphs once per vault and cache. Vaults with 4+ chests get
# weight-divided to ~1/20 their original — they're "treasure room" novelties,
# not the everyday stamp. Without this, the 28×22 chest-grid `des_vaults_vault`
# stamps almost as often as a normal vault and floods the map.
static func _annotate_vault(vault: Dictionary) -> void:
	var grid_arr: Array = vault.get("grid", [])
	var chest_count: int = 0
	for row in grid_arr:
		var s: String = String(row)
		for i in s.length():
			if s.substr(i, 1) == "C":
				chest_count += 1
	vault["_chest_count"] = chest_count

static func _effective_weight(vault: Dictionary) -> float:
	var w: float = float(vault.get("weight", 1))
	var chest_count: int = int(vault.get("_chest_count", 0))
	if chest_count >= 4:
		# Steep penalty: 4 chests = 1/8, 8+ chests = 1/20.
		var divisor: float = 8.0 if chest_count < 8 else 20.0
		return maxf(0.05, w / divisor)
	return w

static func _theme_match(vault: Dictionary, theme: String) -> bool:
	var themes: Array = vault.get("themes", [])
	return themes.has(theme) or themes.has("any")

static func _theme_match_any(vault: Dictionary, themes: Array) -> bool:
	var v_themes: Array = vault.get("themes", [])
	if v_themes.has("any"):
		return true
	# DCSS-port vaults are bulk-tagged 'dungeon' plus their real branch tag
	# (e.g. 'lair'). To stop branch-specific vaults from leaking into
	# atmospherically-wrong biomes, require a NON-dungeon tag overlap whenever
	# the vault has branch tags. The bare 'dungeon' biome (and any biome whose
	# only request is 'dungeon') still matches via the dungeon tag itself.
	var has_branch_tag: bool = false
	for vt in v_themes:
		if String(vt) != "dungeon":
			has_branch_tag = true
			break
	for t in themes:
		if t == "dungeon":
			# Dungeon-tag matches only when the vault has no branch tag, OR
			# the requesting set is dungeon-only (caller is the generic biome).
			if not has_branch_tag or themes.size() == 1:
				if v_themes.has(t):
					return true
			continue
		if v_themes.has(t):
			return true
	return false

static func _depth_match(vault: Dictionary, floor_num: int) -> bool:
	var fr: Array = vault.get("floor_range", [1, 999])
	return floor_num >= int(fr[0]) and floor_num <= int(fr[1])

static func _exclude(vault: Dictionary, placed_names: Dictionary) -> bool:
	var tags: Array = vault.get("tags", [])
	var name: String = String(vault.get("name", ""))
	if placed_names.has(name) and not tags.has("allow_dup"):
		return true
	return false

# Encompass-vault candidates: full-floor designs that replace layout entirely.
static func encompass_candidates(theme: String, floor_num: int) -> Array:
	return encompass_candidates_multi([theme], floor_num)

static func encompass_candidates_multi(themes: Array, floor_num: int) -> Array:
	_ensure_loaded()
	# Debug-jump can force a specific vault — return only that one if it
	# exists, regardless of theme/depth filters.
	if DebugJump.active and DebugJump.vault_name != "":
		var forced: Dictionary = find_by_name(DebugJump.vault_name)
		if not forced.is_empty():
			return [forced]
	var out: Array = []
	for v in _vaults:
		if String(v.get("orient", "float")).to_lower() != "encompass":
			continue
		if not _theme_match_any(v, themes):
			continue
		if not _depth_match(v, floor_num):
			continue
		out.append(v)
	return out

static func find_by_name(name: String) -> Dictionary:
	_ensure_loaded()
	for v in _vaults:
		if String(v.get("name", "")) == name:
			return v
	return {}

# Orient-bound candidates (north/south/east/west/centre).
static func oriented_candidates(theme: String, floor_num: int, placed_names: Dictionary) -> Array:
	return oriented_candidates_multi([theme], floor_num, placed_names)

static func oriented_candidates_multi(themes: Array, floor_num: int, placed_names: Dictionary) -> Array:
	_ensure_loaded()
	var out: Array = []
	for v in _vaults:
		var o: String = String(v.get("orient", "float")).to_lower()
		if o == "encompass" or o == "float":
			continue
		if not _theme_match_any(v, themes):
			continue
		if not _depth_match(v, floor_num):
			continue
		if _exclude(v, placed_names):
			continue
		out.append(v)
	return out

# Float candidates (room-stamped).
static func float_candidates(theme: String, floor_num: int, placed_names: Dictionary) -> Array:
	return float_candidates_multi([theme], floor_num, placed_names)

static func float_candidates_multi(themes: Array, floor_num: int, placed_names: Dictionary) -> Array:
	_ensure_loaded()
	# Debug-jump force path also applies to float vaults (e.g. for verifying
	# decor_overlays compositions on a small mini-vault).
	if DebugJump.active and DebugJump.vault_name != "":
		var forced: Dictionary = find_by_name(DebugJump.vault_name)
		if not forced.is_empty() and String(forced.get("orient", "float")).to_lower() == "float":
			return [forced]
	var out: Array = []
	for v in _vaults:
		var o: String = String(v.get("orient", "float")).to_lower()
		if o != "float":
			continue
		if not _theme_match_any(v, themes):
			continue
		if not _depth_match(v, floor_num):
			continue
		if _exclude(v, placed_names):
			continue
		out.append(v)
	return out

# Backwards-compat: old call site treats every vault as float-style.
static func candidates_for(theme: String, floor_num: int) -> Array:
	return float_candidates(theme, floor_num, {})

static func pick_weighted(candidates: Array, rng: RandomNumberGenerator) -> Dictionary:
	if candidates.is_empty():
		return {}
	var total: float = 0.0
	for c in candidates:
		total += _effective_weight(c)
	if total <= 0.0:
		return {}
	var roll: float = rng.randf_range(0.0, total)
	var cum: float = 0.0
	for c in candidates:
		cum += _effective_weight(c)
		if roll <= cum:
			return c
	return candidates[-1]

# CHANCE table: pick if vault's per-floor probability rolls in. If no chance
# field exists, treat as 100% (eligible if other filters pass).
static func passes_chance(vault: Dictionary, floor_num: int, rng: RandomNumberGenerator) -> bool:
	var chance: float = float(vault.get("chance", 1.0))
	if chance >= 1.0:
		return true
	return rng.randf() < chance
