#!/usr/bin/env python3
"""Walks project/assets/tiles/ and writes tools/biome_manifest.json.

Used by tools/biome_editor.html — a static HTML page can't read the
filesystem, so we pre-bake a list of every PNG available per asset
directory plus a parsed prefix → variants index.

Run from repo root:  python3 tools/build_biome_manifest.py
"""
from __future__ import annotations

import json
import re
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
ASSETS = REPO / "project" / "assets" / "tiles"
OUT = REPO / "tools" / "biome_manifest.json"

DIRS = [
    "floor",
    "wall",
    "overlays",
    "sigils",
    "decor_impassable",
    "features",
    "gateways",
    "terrain",
]

# Same as biome_data.gd's _expand_prefixes: only `prefix_<digit>` tails count.
PREFIX_VARIANT_RE = re.compile(r"^(?P<prefix>.+?)_(?P<idx>\d+)$")
# Directional overlay names like dirt_north, dirt_northeast, dirt_full.
DIR_NAMES = {
    "north", "south", "east", "west",
    "northeast", "northwest", "southeast", "southwest",
    "full",
}


def list_pngs(d: Path) -> list[str]:
    if not d.exists():
        return []
    return sorted(p.stem for p in d.iterdir() if p.suffix == ".png")


def index_prefixes(stems: list[str]) -> dict[str, list[str]]:
    """Group stems by `prefix` where filename matches `prefix_<int>`."""
    groups: dict[str, list[str]] = {}
    for s in stems:
        m = PREFIX_VARIANT_RE.match(s)
        if not m:
            continue
        groups.setdefault(m.group("prefix"), []).append(s)
    return {k: sorted(v) for k, v in sorted(groups.items())}


def index_directional(stems: list[str]) -> dict[str, dict[str, str]]:
    """Group overlay stems by prefix → {direction: stem}.

    `dirt_north` → groups['dirt']['north'] = 'dirt_north'
    """
    groups: dict[str, dict[str, str]] = {}
    for s in stems:
        # Try longest direction name match.
        for dname in DIR_NAMES:
            suffix = "_" + dname
            if s.endswith(suffix):
                prefix = s[: -len(suffix)]
                if prefix:
                    groups.setdefault(prefix, {})[dname] = s
                break
    return {k: v for k, v in sorted(groups.items())}


def main() -> None:
    out: dict = {"dirs": {}, "prefixes": {}, "directional": {}}
    for d in DIRS:
        path = ASSETS / d
        stems = list_pngs(path)
        out["dirs"][d] = stems
        out["prefixes"][d] = index_prefixes(stems)
    # Directional sets only meaningful for overlays/.
    out["directional"]["overlays"] = index_directional(list_pngs(ASSETS / "overlays"))

    OUT.write_text(json.dumps(out, indent=2) + "\n")
    total = sum(len(v) for v in out["dirs"].values())
    print(f"wrote {OUT.relative_to(REPO)} — {total} tiles across {len(DIRS)} dirs")


if __name__ == "__main__":
    main()
