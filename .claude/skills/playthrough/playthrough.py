#!/usr/bin/env python3
"""playthrough.py — Simulate a full game playthrough start-to-end.

A playthrough is a sequence of grinds where the save state evolves
between runs (loot picked up, gold spent on upgrades, gear swapped per
policy). Stops when tier 5 boss is killed or run cap hit.

Per-tier metrics: runs needed, total elapsed, final stats, gear ATK/DEF/HP,
gold flow. Lets us calibrate the difficulty curve from data instead of
guessing.

Usage:

    python3 playthrough.py [--equip POLICY] [--upgrade POLICY] [--advance POLICY]
                           [--max-runs 200] [--seed-base 6000]

Policies:
    --equip:   score_weighted (default) | pure_dps | rarity_first
    --upgrade: round_robin (default)    | combat_first | hp_first
    --advance: strict (default)         | cautious | greedy

Each playthrough writes:
    logs/playthrough/<ts>_<equip>_<upgrade>_<advance>.log     (per-run lines)
    logs/playthrough/index.jsonl                              (summary entry)
"""

from __future__ import annotations
import argparse
import json
import sys
import time
from collections import Counter
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent.parent.parent
sys.path.insert(0, str(REPO_ROOT / "tools"))
sys.path.insert(0, str(REPO_ROOT / ".claude" / "skills" / "duel"))
sys.path.insert(0, str(REPO_ROOT / ".claude" / "skills" / "equip"))
sys.path.insert(0, str(REPO_ROOT / ".claude" / "skills" / "playthrough"))

import balance
from parse_grind import parse, RunResult
import policies as P

LOGS_DIR = REPO_ROOT / "logs" / "playthrough"
INDEX = LOGS_DIR / "index.jsonl"
DEBUG_SAVE = balance.DEBUG_SAVE


def starter_state() -> dict:
    """Match save_state.gd::_default()."""
    return {
        "gold": 0, "level": 1, "xp": 0, "inventory": [],
        "equipped": {
            "weapon": {"base_id": "rusty_dagger", "instance_id": "starter_weapon", "affixes": []},
            "armor":  {"base_id": "tattered_hide", "instance_id": "starter_armor", "affixes": []},
            "helm":   None, "boots": None, "shield": None,
            "ring1":  None, "ring2":  None, "amulet":  None,
        },
        "runs_completed": 0, "highest_floor": 0,
        "unlocked_branches": ["dungeon"],
        "bosses_killed": {}, "max_revives": 3,
        "loot_filter": "common", "inventory_cap": 50,
        "last_branch": "", "branch_modifiers": {},
        "bot_upgrades": {}, "shards": 0, "last_seen_timestamp": 0,
    }


def write_save(state: dict) -> None:
    DEBUG_SAVE.parent.mkdir(parents=True, exist_ok=True)
    with DEBUG_SAVE.open("w") as f:
        json.dump(state, f, indent=2)


def read_save() -> dict:
    if not DEBUG_SAVE.exists():
        return starter_state()
    return json.load(DEBUG_SAVE.open())


def gear_summary(state: dict, items_db: dict) -> dict:
    """Roll up equipped gear into ATK / DEF / HP totals."""
    atk = def_ = hp = 0
    eq = state.get("equipped", {})
    for slot, inst in eq.items():
        if not isinstance(inst, dict):
            continue
        item = items_db.get(inst.get("base_id", ""), {})
        atk += int(item.get("atk", 0))
        def_ += int(item.get("def", 0))
        hp += int(item.get("hp", 0))
        for af in inst.get("affixes", []):
            if af["id"] == "strength": atk += int(af["value"])
            elif af["id"] == "stamina": hp += int(af["value"])
            elif af["id"] == "agility": def_ += int(af["value"])
    return {"atk": atk, "def": def_, "hp": hp}


def equipped_summary_str(state: dict) -> str:
    """Compact 'wpn:demon_blade arm:scale_mail ...' string for logging."""
    parts = []
    eq = state.get("equipped", {})
    for slot in ("weapon", "armor", "helm", "shield", "boots"):
        inst = eq.get(slot)
        if isinstance(inst, dict) and inst.get("base_id"):
            parts.append(f"{slot[:3]}:{inst['base_id']}")
    return " ".join(parts) if parts else "(none)"


def apply_equip_policy(state: dict, items_db: dict, policy_fn) -> tuple[dict, str]:
    """Returns (updated_state, change_summary_str)."""
    new_eq = policy_fn(state, items_db)
    old_eq = state.get("equipped", {})
    changes = []
    for slot, new_inst in new_eq.items():
        old_inst = old_eq.get(slot)
        old_id = old_inst.get("base_id") if isinstance(old_inst, dict) else None
        new_id = new_inst.get("base_id") if isinstance(new_inst, dict) else None
        if old_id != new_id:
            changes.append(f"{slot}: {old_id or '-'} → {new_id or '-'}")
    state["equipped"] = state.get("equipped", {})
    for slot, inst in new_eq.items():
        state["equipped"][slot] = inst
    return state, "; ".join(changes) if changes else "(no change)"


def apply_upgrade_policy(state: dict, upgrades_db: dict, policy_fn) -> tuple[dict, dict]:
    result = policy_fn(state, upgrades_db)
    state["bot_upgrades"] = result["bot_upgrades"]
    state["gold"] = result["gold"]
    return state, result


def apply_advance_policy(history, state, biomes_db, policy_fn, current_branch) -> str:
    return policy_fn(history, state.get("unlocked_branches", []), current_branch, biomes_db)


def run_playthrough(equip_p: str, upgrade_p: str, advance_p: str,
                    max_runs: int, seed_base: int, log_path: Path) -> dict:
    items_db = P.load_items_db()
    upgrades_db = P.load_upgrades_db()
    biomes_db = P.load_biomes_db()
    equip_fn = P.EQUIP_POLICIES[equip_p]
    upgrade_fn = P.UPGRADE_POLICIES[upgrade_p]
    advance_fn = P.ADVANCE_POLICIES[advance_p]

    # Initialize
    state = starter_state()
    state["unlocked_branches"] = ["dungeon"]
    write_save(state)
    history: list[dict] = []
    per_tier: dict[int, dict] = {1: _new_tier_record(), 2: _new_tier_record(),
                                  3: _new_tier_record(), 4: _new_tier_record(),
                                  5: _new_tier_record()}
    current_branch = "dungeon"
    max_tier_reached = 1
    t0 = time.time()

    log_f = log_path.open("w", buffering=1)  # line-buffered

    def _log(msg: str):
        print(msg, flush=True)
        log_f.write(msg + "\n")

    _log(f"=== PLAYTHROUGH start ===")
    _log(f"policies: equip={equip_p} upgrade={upgrade_p} advance={advance_p}")
    _log(f"max_runs={max_runs} seed_base={seed_base}")

    for run_idx in range(max_runs):
        seed = seed_base + run_idx

        # Decide branch
        current_branch = apply_advance_policy(history, state, biomes_db,
                                               advance_fn, current_branch)
        biome = biomes_db.get(current_branch, {})
        cur_tier = int(biome.get("tier", 1))
        max_tier_reached = max(max_tier_reached, cur_tier)

        # Apply upgrade policy (will use latest gold)
        state, upg = apply_upgrade_policy(state, upgrades_db, upgrade_fn)
        # Apply equip policy (will use updated inventory)
        state, gear_changes = apply_equip_policy(state, items_db, equip_fn)
        # Set last_branch for the run
        state["last_branch"] = current_branch
        write_save(state)

        gear = gear_summary(state, items_db)
        _log(f"\n--- run {run_idx + 1} | tier {cur_tier} | branch={current_branch} | "
             f"seed={seed} ---")
        _log(f"  pre-run: lvl={state['level']} gold={state['gold']} "
             f"hp_gear={gear['hp']} atk_gear={gear['atk']} def_gear={gear['def']}")
        if upg.get("purchased"):
            _log(f"  upgrades: bought {upg['purchased']} for {upg['spent']}g")
        if gear_changes != "(no change)":
            _log(f"  gear: {gear_changes}")
        _log(f"  equipped: {equipped_summary_str(state)}")

        # Run the grind. BOTTER_FORCE_BIOME pins every floor of the run
        # to the chosen branch — without this the runtime falls back to
        # random per-floor biome rolls (because dungeon.branch_id is only
        # set via the Outpost UI flow, which auto-grind bypasses).
        balance.clean_markers()
        spawn = balance.run_grind(seed=seed, runs=1, speed=16,
                                   label=f"playthrough_t{cur_tier}_r{run_idx+1}",
                                   invincible=False,
                                   env_extra={"BOTTER_FORCE_BIOME": current_branch})
        if not spawn.completed:
            _log(f"  WARN: grind incomplete (timeout?) at run {run_idx+1}")

        # Re-read save (Godot has now mutated it with run results)
        state = read_save()
        g = parse(spawn.log_path)
        run_result = g.runs[0] if g.runs else None
        if run_result is None:
            _log(f"  ERROR: no [run] end parsed; aborting playthrough")
            break

        history.append({
            "branch": current_branch, "tier": cur_tier,
            "victory": run_result.victory,
            "floor": run_result.end_floor,
            "kills": run_result.kills,
            "loot": run_result.loot,
            "elapsed_s": run_result.elapsed_s,
            "level_after": state.get("level", 1),
            "gold_after": state.get("gold", 0),
        })
        rec = per_tier[cur_tier]
        rec["runs"] += 1
        rec["elapsed_s"] += run_result.elapsed_s
        if run_result.victory:
            rec["wins"] += 1
            rec["bosses_killed"] = state.get("bosses_killed", {}).get(current_branch, 0)
        rec["last_floor"] = run_result.end_floor

        outcome = "WIN " if run_result.victory else "LOSS"
        _log(f"  result: {outcome} f={run_result.end_floor} kills={run_result.kills} "
             f"loot={run_result.loot} elapsed={run_result.elapsed_s:.1f}s "
             f"→ post-run lvl={state.get('level',1)} gold={state.get('gold',0)} "
             f"inv={len(state.get('inventory', []))}")

        # Check tier 5 cleared = playthrough complete
        bosses = state.get("bosses_killed", {})
        tier5_branches = ["forge", "glacier", "slime", "labyrinth", "abyss",
                          "pandemonium", "zot"]
        if any(bosses.get(b, 0) > 0 for b in tier5_branches):
            _log(f"\n=== T5 boss killed — playthrough complete ===")
            break

    # Summary
    elapsed_total = time.time() - t0
    _log(f"\n{'=' * 80}")
    _log(f"PLAYTHROUGH SUMMARY (wall-clock {elapsed_total/60:.1f} min)")
    _log(f"{'=' * 80}")
    _log(f"runs={len(history)} max_tier_reached={max_tier_reached}")
    _log(f"final: lvl={state.get('level',1)} gold={state.get('gold',0)}")
    final_gear = gear_summary(state, items_db)
    _log(f"final gear: hp+{final_gear['hp']} atk+{final_gear['atk']} def+{final_gear['def']}")
    _log(f"\n{'tier':<6}{'runs':<6}{'wins':<6}{'win%':<7}{'sim_s':<10}{'last_floor':<12}{'bosses_killed'}")
    for t in (1, 2, 3, 4, 5):
        r = per_tier[t]
        if r["runs"] == 0:
            continue
        wp = r["wins"] / r["runs"] * 100 if r["runs"] else 0
        _log(f"{t:<6}{r['runs']:<6}{r['wins']:<6}{wp:<7.0f}"
             f"{r['elapsed_s']:<10.1f}{r['last_floor']:<12}{r.get('bosses_killed', 0)}")

    log_f.close()
    summary = {
        "ts": time.time(),
        "kind": "playthrough",
        "policies": {"equip": equip_p, "upgrade": upgrade_p, "advance": advance_p},
        "max_runs": max_runs, "seed_base": seed_base,
        "wall_clock_min": elapsed_total / 60,
        "total_runs": len(history),
        "max_tier_reached": max_tier_reached,
        "final_level": state.get("level", 1),
        "final_gold": state.get("gold", 0),
        "final_gear": final_gear,
        "per_tier": per_tier,
        "log_path": str(log_path),
    }
    INDEX.parent.mkdir(parents=True, exist_ok=True)
    with INDEX.open("a") as f:
        f.write(json.dumps(summary) + "\n")
    return summary


def _new_tier_record() -> dict:
    return {"runs": 0, "wins": 0, "elapsed_s": 0.0, "last_floor": 0, "bosses_killed": 0}


def main():
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--equip", default="score_weighted",
                   choices=list(P.EQUIP_POLICIES))
    p.add_argument("--upgrade", default="round_robin",
                   choices=list(P.UPGRADE_POLICIES))
    p.add_argument("--advance", default="strict",
                   choices=list(P.ADVANCE_POLICIES))
    p.add_argument("--max-runs", type=int, default=200)
    p.add_argument("--seed-base", type=int, default=6000)
    args = p.parse_args()

    LOGS_DIR.mkdir(parents=True, exist_ok=True)
    ts = time.strftime("%Y%m%d-%H%M%S")
    label = f"{ts}_{args.equip}_{args.upgrade}_{args.advance}"
    log_path = LOGS_DIR / f"{label}.log"
    summary = run_playthrough(args.equip, args.upgrade, args.advance,
                              args.max_runs, args.seed_base, log_path)
    print(f"\nlog: {log_path}")
    print(f"appended summary to {INDEX}")


if __name__ == "__main__":
    main()
