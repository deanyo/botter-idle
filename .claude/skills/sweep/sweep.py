#!/usr/bin/env python3
"""sweep.py — Vary one parameter across grinds, find sweet spot or rank options.

Two flavors:

  Item sweep:
      sweep.py --slot weapon --values demon_blade,runed_warsword,thunder_cleaver \\
               --base "armor=crystal_plate,Stamina5 level=30 branch=forge" \\
               -N 10
      → equips each weapon in turn (with same other gear), N runs each

  Item-set sweep (sugar for "all legendary swords"):
      sweep.py --slot weapon --values @legendary --base "level=30 branch=forge" -N 10
      → resolves @legendary to the full list of legendary weapon ids

  Affix sweep:
      sweep.py --affix crit --tiers 1,2,3,4,5 \\
               --base "weapon=demon_blade armor=crystal_plate level=30 branch=forge" \\
               -N 10
      → tests crit at each tier, all else equal

Each variant runs against the same seed sequence so the comparison is
paired. Output: ranked table by win rate (then avg floor as tiebreaker).
Writes summary to logs/balance/index.jsonl.
"""

from __future__ import annotations
import argparse
import json
import shlex
import subprocess
import sys
from collections import Counter
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent.parent.parent
sys.path.insert(0, str(REPO_ROOT / "tools"))
sys.path.insert(0, str(REPO_ROOT / ".claude" / "skills" / "equip"))
sys.path.insert(0, str(REPO_ROOT / ".claude" / "skills" / "duel"))

import balance
from parse_grind import parse, RunResult
from duel import equip_from_spec, summarize, wilson_ci
from equip import parse_args as parse_equip_args


ITEMS_PATH = REPO_ROOT / "project" / "data" / "items.json"


def load_items():
    return {it["id"]: it for it in json.load(ITEMS_PATH.open())["items"]}


# ---- Set shortcuts: @legendary, @epic, @rare, @<slot>, @<rarity>_<slot> ----
def expand_set(token: str, slot: str, items: dict) -> list[str]:
    """Resolve @legendary, @epic, @<slot>, @legendary_weapon, etc."""
    if not token.startswith("@"):
        return [token]
    name = token[1:].lower()
    parts = name.split("_")
    rarities = {"common", "uncommon", "rare", "epic", "legendary"}
    slots = {"weapon", "armor", "helm", "shield", "boots", "ring", "amulet"}
    rarity_filter, slot_filter = None, None
    for p in parts:
        if p in rarities:
            rarity_filter = p
        elif p in slots:
            slot_filter = p
    if not slot_filter:
        slot_filter = "ring" if slot in ("ring1", "ring2") else slot
    out = []
    for it in items.values():
        if it.get("slot") != slot_filter:
            continue
        if rarity_filter and it.get("rarity") != rarity_filter:
            continue
        out.append(it["id"])
    return sorted(out)


def parse_values(values_arg: str, slot: str, items: dict) -> list[str]:
    out = []
    for v in [v.strip() for v in values_arg.split(",") if v.strip()]:
        out.extend(expand_set(v, slot, items))
    # De-dup preserving order.
    seen = set()
    uniq = []
    for v in out:
        if v not in seen:
            seen.add(v)
            uniq.append(v)
    return uniq


def run_variants(variants: list[tuple[str, str]], seeds: list[int], speed: int,
                 invincible: bool, partial_label: str = "") -> dict[str, list[RunResult]]:
    """variants: [(label, full_spec_str)]. Returns {label: [run_results]}.

    Persists per-variant partial results to logs/balance/index.jsonl as each
    variant completes — so if the sweep is killed mid-experiment, the
    partial data is durable.
    """
    all_runs = {}
    for variant_label, spec_str in variants:
        print(f"\n--- variant: {variant_label} ---", flush=True)
        runs = []
        for i, s in enumerate(seeds):
            equip_from_spec(spec_str)
            balance.clean_markers()
            spawn = balance.run_grind(seed=s, runs=1, speed=speed,
                                      label=f"sweep_{variant_label}_s{s}",
                                      invincible=invincible)
            g = parse(spawn.log_path)
            if not g.runs:
                print(f"  WARN: variant {variant_label} seed={s} produced no run",
                      file=sys.stderr, flush=True)
                continue
            if g.runs[0].seed == 0:
                g.runs[0].seed = s
            r = g.runs[0]
            outcome = "WIN " if r.victory else "LOSS"
            print(f"  [{i+1}/{len(seeds)}] seed={s} {outcome} f={r.end_floor} "
                  f"kills={r.kills} loot={r.loot} elapsed={r.elapsed_s:.1f}s",
                  flush=True)
            runs.extend(g.runs)
        all_runs[variant_label] = runs

        # Durability: persist partial result after each variant completes
        # so a mid-sweep kill doesn't lose the data we already paid for.
        from duel import summarize
        if runs:
            balance.append_index({
                "kind": "sweep_partial_variant",
                "label": f"{partial_label}_{variant_label}" if partial_label else variant_label,
                "params": {"variant": variant_label, "spec": spec_str,
                           "seeds": list(seeds), "speed": speed,
                           "invincible": invincible},
                "summary": summarize(variant_label, runs),
            })
    return all_runs


def print_ranked_table(summaries: list[dict]):
    # Sort: win rate desc, then avg_floor desc, then avg_kills desc.
    summaries = sorted(summaries, key=lambda d: (
        -d.get("win_rate", 0),
        -d.get("avg_floor", 0),
        -d.get("avg_kills", 0),
    ))
    print()
    print(f"{'rank':<5}{'variant':<30}{'wins':<7}{'win_rate':<22}{'floor':<8}{'kills':<8}{'elapsed':<10}")
    print("-" * 95)
    for i, s in enumerate(summaries):
        wr = s.get("win_rate", 0)
        ci = s.get("win_rate_ci95", [0, 0])
        wr_str = f"{wr:.0%} [{ci[0]:.0%},{ci[1]:.0%}]"
        print(f"{i+1:<5}{s.get('label','?')[:28]:<30}{s.get('wins',0):<7}{wr_str:<22}"
              f"{s.get('avg_floor',0):<8.2f}{s.get('avg_kills',0):<8.1f}"
              f"{s.get('avg_elapsed_s',0):<10.1f}")


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--slot", help="Item slot to vary (weapon/armor/helm/...).")
    parser.add_argument("--values",
                        help="Comma-separated item ids, OR @set tokens "
                             "(e.g. @legendary, @epic_weapon).")
    parser.add_argument("--affix", help="Affix id to vary (strength/crit/...).")
    parser.add_argument("--tiers", help="Comma-separated tier list (1..5).")
    parser.add_argument("--base", default="",
                        help="Base /equip spec — applied to every variant.")
    parser.add_argument("--apply-to-slot", default="weapon",
                        help="When --affix is used, which slot to attach the "
                             "affix to (default: weapon).")
    parser.add_argument("-N", "--runs", type=int, default=10, help="Runs per variant.")
    parser.add_argument("--seed-base", type=int, default=1, help="First seed.")
    parser.add_argument("--speed", type=int, default=16)
    parser.add_argument("--invincible", action="store_true",
                        help="Keep grind invincibility (default off).")
    args = parser.parse_args()

    if args.slot and args.affix:
        sys.exit("--slot and --affix are mutually exclusive (one sweep at a time).")
    if not args.slot and not args.affix:
        sys.exit("must pass either --slot/--values or --affix/--tiers.")

    items = load_items()
    seeds = list(range(args.seed_base, args.seed_base + args.runs))

    # Build variants list of (label, full_spec_str).
    variants: list[tuple[str, str]] = []
    if args.slot:
        if not args.values:
            sys.exit("--values is required with --slot.")
        ids = parse_values(args.values, args.slot, items)
        if not ids:
            sys.exit(f"--values resolved to no items.")
        for item_id in ids:
            spec = f"{args.slot}={item_id} {args.base}".strip()
            variants.append((item_id, spec))
        print(f"Sweep: slot={args.slot}, {len(ids)} variants × {args.runs} seeds")
    else:
        if not args.tiers:
            sys.exit("--tiers is required with --affix.")
        tiers = [int(t.strip()) for t in args.tiers.split(",") if t.strip()]
        # base spec must include the slot we're attaching the affix to.
        base_args = parse_equip_args(shlex.split(args.base)) if args.base else {}
        slot_spec = base_args.get("equipped", {}).get(args.apply_to_slot)
        if not slot_spec:
            sys.exit(f"--base must equip {args.apply_to_slot} when sweeping affix tiers "
                     f"(so we have something to attach the affix to).")
        for t in tiers:
            # Inject the affix into the apply_to_slot.
            label = f"{args.affix}{t}"
            modified_spec = json.loads(json.dumps(base_args))
            slot_dict = modified_spec["equipped"][args.apply_to_slot]
            slot_dict.setdefault("affixes", []).append([args.affix, t])
            variants.append((label, json.dumps(modified_spec)))
        print(f"Sweep: affix={args.affix}, tiers={tiers} × {args.runs} seeds")

    sweep_label = (f"slot={args.slot}" if args.slot else f"affix={args.affix}") \
                  + f"_N{args.runs}_seedbase{args.seed_base}"
    all_runs = run_variants(variants, seeds, args.speed, args.invincible,
                            partial_label=sweep_label)
    summaries = [summarize(label, runs) for label, runs in all_runs.items()]
    print_ranked_table(summaries)

    balance.append_index({
        "kind": "sweep",
        "label": (f"slot={args.slot}" if args.slot else f"affix={args.affix}") +
                 f" N={args.runs}",
        "params": {
            "slot": args.slot, "values": args.values,
            "affix": args.affix, "tiers": args.tiers,
            "base": args.base, "runs": args.runs,
            "seed_base": args.seed_base, "speed": args.speed,
            "invincible": args.invincible,
        },
        "ranked": summaries,
    })
    print(f"\nappended summary to {balance.INDEX_PATH}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
