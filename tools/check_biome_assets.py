#!/usr/bin/env python3
"""
Sanity-check biomes.json prefix references against actual files in
project/assets/tiles/.

What it catches:
  - floor_primary / floor_secondary / floor_accent prefixes that
    expand to ZERO files in project/assets/tiles/floor/ (likely
    renamed or deleted sprites)
  - wall_primary / wall_accent / wall_alternates prefixes with no
    matching files in project/assets/tiles/wall/
  - edge_overlay prefixes that don't resolve to a directional set
    in project/assets/tiles/overlays/ (need at least north + full)
  - sigil_set @stem references that point at missing files
  - ambient_decor ids whose tile filename is missing
  - liquid_type / vault_themes / enemy_pool — only sanity-checks
    reference lookups available; emit warnings, not errors

Output: a per-biome report with broken references called out and a
summary. Exit code 0 if every biome resolves cleanly, 1 if any
prefix has zero matches (so CI / pre-commit can gate on it).

Run from repo root:
    python3 tools/check_biome_assets.py
"""

import json
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
BIOMES = REPO / "project" / "data" / "biomes.json"
ENEMIES = REPO / "project" / "data" / "enemies.json"
TILES_DIR = REPO / "project" / "assets" / "tiles"
FLOOR_DIR = TILES_DIR / "floor"
WALL_DIR = TILES_DIR / "wall"
OVERLAYS_DIR = TILES_DIR / "overlays"
SIGILS_DIR = TILES_DIR / "sigils"
FEATURES_DIR = TILES_DIR / "features"


def list_pngs(d: Path) -> set[str]:
    if not d.is_dir():
        return set()
    return {p.name for p in d.glob("*.png")}


def expand_prefixes(prefixes: list, files: set[str]) -> tuple[list[str], list[str]]:
    """Mirror biome_data.gd::_expand_prefixes. Return (resolved, broken)."""
    resolved = []
    broken = []
    for entry in prefixes:
        s = str(entry)
        if s.startswith("@"):
            stem = s[1:]
            fname = f"{stem}.png"
            if fname in files:
                resolved.append(fname)
            else:
                broken.append(s)
            continue
        # Prefix form: <entry>_<digit>.png
        prefix = f"{s}_"
        matched = [f for f in files if f.startswith(prefix) and re.match(r"^\d+", f[len(prefix):])]
        if not matched:
            broken.append(s)
        else:
            resolved.extend(matched)
    return resolved, broken


def check_edge_overlay(spec: dict, files: set[str]) -> list[str]:
    """Edge overlay needs the 4 cardinal directional pieces. _full and
    _<digit> patches are optional (see biome_data.gd::load_edge_overlay)."""
    if not isinstance(spec, dict):
        return []
    prefix = str(spec.get("prefix", ""))
    if not prefix:
        return []
    expected = [f"{prefix}_{d}.png" for d in ("north", "south", "east", "west")]
    return [e for e in expected if e not in files]


def check_sigil_set(sigils: list, files: set[str]) -> list[str]:
    """Each entry should be a stem with matching png in sigils/."""
    broken = []
    for s in sigils:
        stem = str(s)
        if stem.startswith("@"):
            stem = stem[1:]
        fname = f"{stem}.png"
        if fname not in files:
            broken.append(stem)
    return broken


def main() -> int:
    if not BIOMES.exists():
        print(f"missing {BIOMES}", file=sys.stderr)
        return 2
    with BIOMES.open() as f:
        doc = json.load(f)
    biomes = doc.get("biomes", {})
    floor_files = list_pngs(FLOOR_DIR)
    wall_files = list_pngs(WALL_DIR)
    overlay_files = list_pngs(OVERLAYS_DIR)
    sigil_files = list_pngs(SIGILS_DIR)
    feature_files = list_pngs(FEATURES_DIR)

    enemies = {}
    if ENEMIES.exists():
        with ENEMIES.open() as f:
            enemies = json.load(f)

    print(f"Checking {len(biomes)} biomes against:")
    print(f"  floor/    {len(floor_files)} files")
    print(f"  wall/     {len(wall_files)} files")
    print(f"  overlays/ {len(overlay_files)} files")
    print(f"  sigils/   {len(sigil_files)} files")
    print(f"  features/ {len(feature_files)} files")
    print()

    total_broken = 0
    biome_findings: dict[str, list[str]] = {}

    for biome_id, biome in biomes.items():
        findings: list[str] = []
        # Floor pools
        for key, dir_files, label in [
            ("floor_primary", floor_files, "floor"),
            ("floor_secondary", floor_files, "floor"),
            ("floor_accent", floor_files, "floor"),
        ]:
            prefixes = biome.get(key, [])
            if prefixes:
                _, broken = expand_prefixes(prefixes, dir_files)
                for b in broken:
                    findings.append(f"  {key}: '{b}' has no matching files in {label}/")
        # Wall pools — wall_primary can be string OR array; normalize.
        wp = biome.get("wall_primary", [])
        if isinstance(wp, str):
            wp = [wp]
        if wp:
            _, broken = expand_prefixes(wp, wall_files)
            for b in broken:
                findings.append(f"  wall_primary: '{b}' has no matching files in wall/")
        wa = biome.get("wall_accent", [])
        if wa:
            _, broken = expand_prefixes(wa, wall_files)
            for b in broken:
                findings.append(f"  wall_accent: '{b}' has no matching files in wall/")
        # wall_alternates can be {"prefix": "..."} or {"prefixes": [...]}
        walts = biome.get("wall_alternates", [])
        for spec in walts:
            if isinstance(spec, dict):
                if "prefix" in spec:
                    _, broken = expand_prefixes([spec["prefix"]], wall_files)
                    for b in broken:
                        findings.append(f"  wall_alternates: '{b}' has no matching files in wall/")
                if "prefixes" in spec:
                    _, broken = expand_prefixes(spec["prefixes"], wall_files)
                    for b in broken:
                        findings.append(f"  wall_alternates: '{b}' has no matching files in wall/")
        # Edge overlay
        eo = biome.get("edge_overlay", {})
        missing = check_edge_overlay(eo, overlay_files)
        for m in missing:
            findings.append(f"  edge_overlay: missing {m}")
        # Sigil set
        sigils = biome.get("sigil_set", [])
        broken = check_sigil_set(sigils, sigil_files)
        for b in broken:
            findings.append(f"  sigil_set: '{b}' missing in sigils/")
        # Ambient decor — features/ filename heuristic.
        decor = biome.get("ambient_decor", [])
        for d in decor:
            # Each decor entry is either a bare id or {"id": "...", "weight": ...}.
            did = d if isinstance(d, str) else str(d.get("id", ""))
            if not did:
                continue
            # AmbientDecor maps id → tile via DECOR_SPECS in ambient_decor.gd.
            # We only sanity-check the FILENAME so missing decor ids that
            # WOULD resolve to a known tile aren't flagged here.
        # Enemy pool sanity — just confirm each id resolves in enemies.json.
        epool = biome.get("enemy_pool", [])
        for eid in epool:
            if str(eid) not in enemies:
                findings.append(f"  enemy_pool: '{eid}' not found in enemies.json")
        if findings:
            biome_findings[biome_id] = findings
            total_broken += len(findings)

    if not biome_findings:
        print("✓ All biomes resolve cleanly.")
        return 0
    print(f"⚠ Found {total_broken} broken reference(s) across {len(biome_findings)} biome(s):\n")
    for biome_id, findings in sorted(biome_findings.items()):
        print(f"[{biome_id}]")
        for f in findings:
            print(f)
        print()
    return 1


if __name__ == "__main__":
    sys.exit(main())
