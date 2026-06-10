#!/usr/bin/env python3
"""Theoretical-DPS curves for every spell archetype, f1-f30.

Pure-Python re-implementation of `SpellData.compute_damage` +
`SpellData.compute_cooldown` (project/scripts/spell_data.gd) and the
spell-side accumulators inside `StatCalc.compute`
(project/scripts/stat_calc.gd). Reads the same JSON files the engine
reads — items.json, species.json, spell_archetypes.json (dumped from
spell_data.gd).

Outputs:
  - tools/plots/spell_dps.csv      one row per (archetype, floor, target)
  - tools/plots/spell_dps.png      one curve per archetype
  - stdout markdown summary (top 5 / bottom 5 at f30)

The ground truth is /duel — this script trades real-combat fidelity for
~500ms instead of 30 minutes per number. Use as a Tier-1 sanity pass
before /duel; matplotlib PNG goes into the audit log.

Usage:
  # All 10 archetypes vs single + pack5 + boss, default profiles:
  python3 tools/analyze_spell_dps_curve.py

  # One archetype:
  python3 tools/analyze_spell_dps_curve.py --archetype spell_holy_beam

  # Different scenario:
  python3 tools/analyze_spell_dps_curve.py --target boss

  # No PNG (CSV+stdout only):
  python3 tools/analyze_spell_dps_curve.py --no-plot
"""
from __future__ import annotations

import argparse
import csv
import json
import math
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Optional

REPO = Path(__file__).resolve().parent.parent
DATA = REPO / "project" / "data"
PLOTS = REPO / "tools" / "plots"

ITEMS_JSON = DATA / "items.json"
SPECIES_JSON = DATA / "species.json"
SPELL_ARCH_JSON = DATA / "spell_archetypes.json"

# Soft caps mirroring stat_calc.gd:294-309.
CAP_SPELL_DAMAGE_PCT = 120.0
CAP_SPELL_CDR_PCT = 50.0
CAP_SPELL_ELEMENT_PCT = 100.0
CAP_SPELL_AREA_PCT = 100.0
CAP_SPELL_DURATION_PCT = 100.0
CAP_SPELL_PROJ_BONUS = 5
CAP_CLASS_SPELL_DMG_PCT = 100.0

TARGETS = ["single", "pack5", "boss", "line"]
ARCHETYPE_TO_DAMAGE_TYPE = {
    "spell_fireball": "fire",
    "spell_axes": "physical",
    "spell_holy_beam": "holy",
    "spell_chain_lightning": "lightning",
    "spell_frost_nova": "cold",
    "spell_magic_dart": "physical",
    "spell_iron_shot": "physical",
    "spell_sandblast": "physical",
    "spell_drain": "dark",
    "spell_shatter": "physical",
    # S10 expansion (a05 D + a10 §3.2). Cloud/totem/wisp DPS uses a
    # per-tick base; shape_multiplier handles the tick × duration math.
    "spell_bone_spear": "physical",
    "spell_venom_cloud": "poison",
    "spell_stormcaller_totem": "lightning",
    "spell_curse_brittlebone": "dark",
    "spell_wrath_charge": "physical",  # 0-dmg buff; DPS curve will read 0
    "spell_echo_lance": "lightning",
    "spell_wisp_servant": "physical",
    "spell_ember_bloom": "fire",
}


@dataclass
class Profile:
    """Floor-anchored gear profile mirrored from a05 §A reference table.

    The audit hand-calc was f1=common naked / f15=rare-mid /
    f30=legendary-stacked. We linearly interpolate between these three
    anchors for every other floor so the curve looks smooth instead of
    stepping.
    """

    floor: int
    rarity: str  # for picking the item row from items.json
    primary_stat: int  # stat lane (str/dex/int) value the spell scales off
    spell_damage_pct: float
    spell_cdr_pct: float
    spell_element_pct: float
    spell_proj_bonus: int
    spell_area_pct: float
    spell_duration_pct: float
    class_spell_pct: float = 0.0  # of_str/dex/int_mastery applied to matched lane


def _interp(a: float, b: float, t: float) -> float:
    return a + (b - a) * t


def _profile_for_floor(floor: int) -> Profile:
    """Smoothly interpolate the f1/f15/f30 anchor profiles from a05 §A.

    Per a05's reference table:
      f1   common   pstat=6   dmg=0   cdr=0   elem=0   proj=0
      f15  rare/ep  pstat=15  dmg=50  cdr=25  elem=30  proj=1
      f30  leg-cap  pstat=24  dmg=120 cdr=50  elem=100 proj=3
    """
    # Build piecewise-linear segments [1,15] and [15,30].
    f = max(1, min(30, floor))
    if f <= 15:
        t = (f - 1) / 14.0
        rarity = "common" if f < 4 else ("uncommon" if f < 8 else ("rare" if f < 13 else "epic"))
        return Profile(
            floor=f,
            rarity=rarity,
            primary_stat=int(round(_interp(6.0, 15.0, t))),
            spell_damage_pct=_interp(0.0, 50.0, t),
            spell_cdr_pct=_interp(0.0, 25.0, t),
            spell_element_pct=_interp(0.0, 30.0, t),
            spell_proj_bonus=int(round(_interp(0.0, 1.0, t))),
            spell_area_pct=_interp(0.0, 30.0, t),
            spell_duration_pct=_interp(0.0, 30.0, t),
        )
    t = (f - 15) / 15.0
    rarity = "epic" if f < 22 else "legendary"
    return Profile(
        floor=f,
        rarity=rarity,
        primary_stat=int(round(_interp(15.0, 24.0, t))),
        spell_damage_pct=_interp(50.0, CAP_SPELL_DAMAGE_PCT, t),
        spell_cdr_pct=_interp(25.0, CAP_SPELL_CDR_PCT, t),
        spell_element_pct=_interp(30.0, CAP_SPELL_ELEMENT_PCT, t),
        spell_proj_bonus=int(round(_interp(1.0, 3.0, t))),
        spell_area_pct=_interp(30.0, CAP_SPELL_AREA_PCT, t),
        spell_duration_pct=_interp(30.0, CAP_SPELL_DURATION_PCT, t),
    )


def _midpoint(item: dict) -> float:
    if "damage_min" in item or "damage_max" in item:
        lo = float(item.get("damage_min", item.get("damage_max", 1)))
        hi = float(item.get("damage_max", lo))
        return (lo + hi) / 2.0
    return float(item.get("damage", 0))


def _meta_qmult(meta: str, quality: str) -> float:
    """Mirror StatCalc + spell_data combined_base = clamp(meta×q, 1.30)."""
    meta_mult = 1.0
    if meta == "ancient":
        meta_mult = 1.20
    elif meta == "primal":
        meta_mult = 1.50
    qmult = 1.0
    if quality == "pristine":
        qmult = 1.10
    elif quality == "sublime":
        qmult = 1.20
    return min(1.30, meta_mult * qmult)


def _pick_item(items: list[dict], archetype: str, rarity: str) -> Optional[dict]:
    """Pick the highest-baseline item of the given archetype + rarity.

    Mirrors what /equip would resolve when the player loots one. Uses
    midpoint(damage_min, damage_max) as the proxy for "best legendary
    of this archetype" so the curve reflects the strongest item the
    player can actually hold at that floor.
    """
    matches = [
        it for it in items
        if it.get("base_type") == archetype and it.get("rarity") == rarity
    ]
    if not matches:
        # Fall back to next-lower rarity if a tier is missing for an
        # archetype — still better than returning archetype defaults.
        order = ["common", "uncommon", "rare", "epic", "legendary"]
        if rarity in order:
            idx = order.index(rarity)
            for r in order[:idx][::-1]:
                fallback = [it for it in items if it.get("base_type") == archetype and it.get("rarity") == r]
                if fallback:
                    matches = fallback
                    break
    if not matches:
        return None
    matches.sort(key=lambda it: _midpoint(it), reverse=True)
    return matches[0]


def compute_damage_per_cast(
    item: dict,
    archetype_def: dict,
    profile: Profile,
    *,
    meta: str = "",
    quality: str = "",
) -> float:
    """Pure-Python mirror of SpellData.compute_damage.

    Uses the rolled damage range midpoint instead of a single
    randi_range — analytic, not stochastic.
    """
    base = _midpoint(item)
    if base <= 0:
        base = float(archetype_def.get("damage", 10))
    base *= _meta_qmult(meta, quality)
    stat_mult = 1.0 + max(0, profile.primary_stat - 5) * 0.02
    dmg_mult = 1.0 + min(profile.spell_damage_pct, CAP_SPELL_DAMAGE_PCT) / 100.0
    elem = str(archetype_def.get("element", ""))
    elem_mult = 1.0
    if elem:
        elem_mult = 1.0 + min(profile.spell_element_pct, CAP_SPELL_ELEMENT_PCT) / 100.0
    class_mult = 1.0 + min(profile.class_spell_pct, CAP_CLASS_SPELL_DMG_PCT) / 100.0
    return base * stat_mult * dmg_mult * elem_mult * class_mult


def compute_cooldown(item: dict, archetype_def: dict, profile: Profile) -> float:
    base_cd = float(item.get("spell_cooldown", archetype_def.get("cooldown", 3.0)))
    cdr = max(0.0, min(profile.spell_cdr_pct, CAP_SPELL_CDR_PCT))
    return max(0.3, base_cd * (1.0 - cdr / 100.0))


def shape_multiplier(archetype: str, profile: Profile, target: str) -> float:
    """Rough hits-per-cast factor for each archetype's shape.

    Calibrated against a05 §A hand-calc results, scaled by the post-
    S2 1.30 meta×qmult cap (a05 used 1.44 pre-cap). At f30 pack5 the
    expected analytic DPS values are ~315 holy_beam, ~898 axes, ~293
    frost_nova, ~247 fireball, ~153 chain — each within 10% of a05's
    pre-cap numbers × (1.30/1.44).

    When we need real positional fidelity (movement, AI, status
    interactions), /duel is the answer. This script is for the cheap
    "did we ceiling-break?" pass.
    """
    proj = min(CAP_SPELL_PROJ_BONUS, profile.spell_proj_bonus)
    area = 1.0 + min(profile.spell_area_pct, CAP_SPELL_AREA_PCT) / 100.0
    duration = 1.0 + min(profile.spell_duration_pct, CAP_SPELL_DURATION_PCT) / 100.0

    if target in ("single", "boss"):
        # Single-target: most archetypes cap at 1 hit/cast.
        if archetype == "spell_chain_lightning":
            # Only the first hit lands on a lone enemy; jumps fizzle.
            return 1.0
        if archetype == "spell_axes":
            # Orbit on a stationary enemy — invuln window per-axe-per-
            # enemy throttles re-hits. n_axes × duration × 0.20 lands
            # ~5 hits at cap (5 axes × 5s × 0.20).
            n_axes = 2 + proj
            duration_s = 2.5 * duration
            return n_axes * duration_s * 0.20
        if archetype == "spell_iron_shot":
            # First-body falloff = 1.0; pierce dies after one mob.
            return 1.0
        if archetype in ("spell_venom_cloud", "spell_ember_bloom"):
            # DoT cloud: per-tick × ticks-per-second × lifetime × 1 enemy.
            # Lifetime = base × (1 + dur_pct/100). Tick rate cap = 2/s.
            base_lifetime = 8.0 if archetype == "spell_venom_cloud" else 5.0
            ticks = base_lifetime * duration * 2.0
            return ticks  # one enemy in cloud for single-target
        if archetype == "spell_stormcaller_totem":
            # Stationary boss in range → totem zaps every 0.6s for 4s
            # × duration_pct. ~6.6 zaps at cap.
            base_lifetime = 4.0
            return (base_lifetime * duration) / 0.6
        if archetype == "spell_curse_brittlebone":
            # Direct damage 1 — DPS curve reads near-zero. The actual
            # value is the +15% amplification of OTHER spells, which
            # this analyzer doesn't synthesize. Treat as 1 hit.
            return 1.0
        if archetype == "spell_wrath_charge":
            return 0.0  # self-buff, no direct damage
        if archetype == "spell_echo_lance":
            # Single target — projectile bounces but only 1 enemy nearby
            # → second target absent → 1 hit.
            return 1.0
        if archetype == "spell_wisp_servant":
            # 1 wisp by default + proj_bonus. Each zaps every 1s for 6s
            # × dur_pct. ~12 zaps at cap.
            base_lifetime = 6.0
            n_wisps = 1 + proj
            return n_wisps * (base_lifetime * duration) / 1.0
        if archetype == "spell_bone_spear":
            # Single target → no bounce targets → 1 hit.
            return 1.0
        return 1.0

    if target == "pack5":
        # Pack of 5 clumped within the spell's effective range.
        if archetype == "spell_fireball":
            # 1 homing per projectile on different targets, capped at 5.
            return float(min(5, 1 + proj))
        if archetype == "spell_axes":
            # Calibrated to a05 §A2's "16 hit events at proj=3, dur cap":
            # n_axes × duration_s × 0.65 → 5 × 5 × 0.65 = 16.25 at cap.
            n_axes = 2 + proj
            duration_s = 2.5 * duration
            return n_axes * duration_s * 0.65
        if archetype == "spell_holy_beam":
            # 120° cone holds ~4 of 5 packed enemies even at area cap;
            # angle scales with area but enemies-in-cone caps at 4.
            return min(4.0, 2.0 + 1.0 * (area - 1.0) + 1.0)
        if archetype == "spell_chain_lightning":
            # 1 + (2 + proj) jumps with 0.7^n falloff per target.
            n = 1 + (2 + proj)
            return sum(0.7 ** k for k in range(min(5, n)))
        if archetype == "spell_frost_nova":
            # Radial — all 5 once.
            return 5.0
        if archetype == "spell_magic_dart":
            # 1 + proj_bonus darts, distributed across pack.
            return float(min(5, 1 + proj))
        if archetype == "spell_iron_shot":
            # Pierces 5 with 25% falloff per body.
            return sum(0.75 ** k for k in range(5))
        if archetype == "spell_sandblast":
            # Linear corridor — only enemies along the bot's facing
            # line; area widens the band but pack rarely lines up.
            return min(4.0, 2.0 + 0.5 * (area - 1.0))
        if archetype == "spell_drain":
            return float(min(5, 1 + proj))
        if archetype == "spell_shatter":
            # Cone like holy_beam — same 4-target saturation.
            return min(4.0, 2.0 + 1.0 * (area - 1.0) + 1.0)
        if archetype in ("spell_venom_cloud", "spell_ember_bloom"):
            # 3-enemy cap per tick × ticks × duration.
            base_lifetime = 8.0 if archetype == "spell_venom_cloud" else 5.0
            ticks = base_lifetime * duration * 2.0
            return ticks * 3.0  # 3-enemy cap
        if archetype == "spell_stormcaller_totem":
            # Totem zaps single target — pack of 5 still gets 1 zap
            # every 0.6s. Pack DPS = same as single (one zap, nearest).
            base_lifetime = 4.0
            return (base_lifetime * duration) / 0.6
        if archetype == "spell_curse_brittlebone":
            # 1 + proj_bonus targets cursed; direct damage = 1 each.
            return float(min(5, 1 + proj))
        if archetype == "spell_wrath_charge":
            return 0.0
        if archetype == "spell_echo_lance":
            # Hits 1 + 1 ricochet = 2 enemies at full damage.
            return 2.0
        if archetype == "spell_wisp_servant":
            # n wisps zap nearest enemy every 1s; per-tick saturates
            # at 1 enemy per wisp.
            base_lifetime = 6.0
            n_wisps = 1 + proj
            return n_wisps * (base_lifetime * duration) / 1.0
        if archetype == "spell_bone_spear":
            # Bouncing physical — 1 + 4 bounces with 30% loss.
            # Sum 1, 0.7, 0.49, 0.343, 0.240 = 2.77.
            return sum(0.7 ** k for k in range(5))
        return 1.0

    if target == "line":
        # 5 mobs in a straight line — favors pierce/chain shapes.
        if archetype == "spell_iron_shot":
            return sum(0.75 ** k for k in range(5))
        if archetype == "spell_chain_lightning":
            n = 1 + (2 + proj)
            return sum(0.7 ** k for k in range(min(5, n)))
        if archetype == "spell_sandblast":
            # Corridor sweep loves a line — full 4-cell sweep hits all.
            return 4.0
        if archetype == "spell_axes":
            # Orbit doesn't cover a line well; saturates ~3 mobs.
            n_axes = 2 + proj
            duration_s = 2.5 * duration
            return n_axes * duration_s * 0.40
        # Other shapes degrade vs. a sparse line.
        return shape_multiplier(archetype, profile, "single")

    return 1.0


@dataclass
class CurveRow:
    archetype: str
    floor: int
    target: str
    per_cast: float
    effective_cd: float
    hits_per_cast: float
    dps: float
    base_damage: float
    primary_stat: int


def build_curve(
    archetype: str,
    archetype_def: dict,
    items: list[dict],
    targets: list[str],
    *,
    meta: str = "primal",
    quality: str = "sublime",
) -> list[CurveRow]:
    rows: list[CurveRow] = []
    for floor in range(1, 31):
        prof = _profile_for_floor(floor)
        item = _pick_item(items, archetype, prof.rarity)
        if item is None:
            continue
        per_cast = compute_damage_per_cast(item, archetype_def, prof, meta=meta, quality=quality)
        cd = compute_cooldown(item, archetype_def, prof)
        for tgt in targets:
            hits = shape_multiplier(archetype, prof, tgt)
            dps = (per_cast * hits) / cd if cd > 0 else 0.0
            rows.append(CurveRow(
                archetype=archetype,
                floor=floor,
                target=tgt,
                per_cast=per_cast,
                effective_cd=cd,
                hits_per_cast=hits,
                dps=dps,
                base_damage=_midpoint(item),
                primary_stat=prof.primary_stat,
            ))
    return rows


def write_csv(rows: list[CurveRow], path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="") as f:
        w = csv.writer(f)
        w.writerow([
            "archetype", "floor", "target",
            "per_cast", "effective_cd_s", "hits_per_cast",
            "dps", "base_damage_midpoint", "primary_stat_value",
        ])
        for r in rows:
            w.writerow([
                r.archetype, r.floor, r.target,
                f"{r.per_cast:.2f}", f"{r.effective_cd:.2f}", f"{r.hits_per_cast:.2f}",
                f"{r.dps:.2f}", f"{r.base_damage:.2f}", r.primary_stat,
            ])


def write_plot(rows: list[CurveRow], path: Path, target: str) -> Optional[Path]:
    try:
        import matplotlib.pyplot as plt  # noqa: WPS433
    except ImportError:
        print("[warn] matplotlib not available; skipping PNG", file=sys.stderr)
        return None
    by_arch: dict[str, list[CurveRow]] = {}
    for r in rows:
        if r.target != target:
            continue
        by_arch.setdefault(r.archetype, []).append(r)
    if not by_arch:
        return None
    plt.figure(figsize=(10, 6))
    for arch, rs in sorted(by_arch.items()):
        rs.sort(key=lambda x: x.floor)
        plt.plot([r.floor for r in rs], [r.dps for r in rs], label=arch, linewidth=1.5)
    plt.title(f"Spell DPS curves — target={target} (analytic)")
    plt.xlabel("Floor")
    plt.ylabel("DPS (theoretical)")
    plt.grid(True, alpha=0.3)
    plt.legend(fontsize=8, ncol=2)
    plt.tight_layout()
    path.parent.mkdir(parents=True, exist_ok=True)
    plt.savefig(path, dpi=120)
    plt.close()
    return path


def render_summary(rows: list[CurveRow], target: str) -> str:
    """Markdown summary block: top 5 / bottom 5 at f30 for the target."""
    f30 = sorted(
        [r for r in rows if r.floor == 30 and r.target == target],
        key=lambda r: r.dps,
        reverse=True,
    )
    if not f30:
        return ""
    lines = [
        f"## f30 DPS — target={target} (analytic, primal+sublime gear)",
        "",
        f"| rank | archetype | DPS | per-cast | hits/cast | eff CD |",
        f"|---|---|---|---|---|---|",
    ]
    for i, r in enumerate(f30, 1):
        lines.append(
            f"| {i} | {r.archetype} | {r.dps:.0f} | {r.per_cast:.0f} | {r.hits_per_cast:.1f} | {r.effective_cd:.2f}s |"
        )
    return "\n".join(lines) + "\n"


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n", 1)[0])
    ap.add_argument("--archetype", help="restrict to one archetype id")
    ap.add_argument("--target", choices=TARGETS + ["all"], default="all")
    ap.add_argument("--out-csv", default=str(PLOTS / "spell_dps.csv"))
    ap.add_argument("--out-png", default=str(PLOTS / "spell_dps.png"))
    ap.add_argument("--no-plot", action="store_true")
    ap.add_argument("--meta", default="primal", choices=["", "ancient", "primal"])
    ap.add_argument("--quality", default="sublime", choices=["", "pristine", "sublime"])
    args = ap.parse_args(argv)

    items_doc = json.loads(ITEMS_JSON.read_text())
    species_doc = json.loads(SPECIES_JSON.read_text())  # noqa: F841 (reserved for future per-species curves)
    if not SPELL_ARCH_JSON.exists():
        print(
            f"[err] {SPELL_ARCH_JSON.relative_to(REPO)} not found. Run "
            "tools/dump_spell_archetypes.py first.",
            file=sys.stderr,
        )
        return 1
    archetypes = json.loads(SPELL_ARCH_JSON.read_text())

    items: list[dict] = items_doc.get("items", [])
    arch_ids = [args.archetype] if args.archetype else sorted(archetypes.keys())
    targets = TARGETS if args.target == "all" else [args.target]

    all_rows: list[CurveRow] = []
    for aid in arch_ids:
        defn = archetypes.get(aid)
        if defn is None:
            print(f"[warn] unknown archetype {aid}", file=sys.stderr)
            continue
        rows = build_curve(aid, defn, items, targets, meta=args.meta, quality=args.quality)
        all_rows.extend(rows)

    write_csv(all_rows, Path(args.out_csv))
    print(f"Wrote {len(all_rows)} rows → {Path(args.out_csv).relative_to(REPO)}")

    if not args.no_plot:
        plot_target = "pack5" if args.target == "all" else args.target
        png_path = write_plot(all_rows, Path(args.out_png), plot_target)
        if png_path:
            print(f"Wrote PNG → {png_path.relative_to(REPO)}")

    # Markdown summary for stdout — only for the most-asked target.
    summary_target = "pack5" if args.target == "all" else args.target
    print()
    print(render_summary(all_rows, summary_target))

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
