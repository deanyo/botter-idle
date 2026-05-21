"""Decision policies for playthrough simulation.

Each policy is a pure function: takes save state + items_db / upgrade defs,
returns the action to take. No side effects — the harness applies the
returned action via inject_save.
"""

from __future__ import annotations
import json
from pathlib import Path
from typing import Callable

REPO_ROOT = Path(__file__).resolve().parent.parent.parent.parent
ITEMS_PATH = REPO_ROOT / "project" / "data" / "items.json"
UPGRADES_PATH = REPO_ROOT / "project" / "data" / "bot_upgrades.json"
BIOMES_PATH = REPO_ROOT / "project" / "data" / "biomes.json"

SLOTS_DERIVED = ["weapon", "armor", "helm", "boots", "shield"]
RARITY_RANK = {"common": 0, "uncommon": 1, "rare": 2, "epic": 3, "legendary": 4}


# ============================================================================
# EQUIP POLICIES — given inventory, return a dict {slot: item_instance | None}
# ============================================================================

def equip_score_weighted(state: dict, items_db: dict) -> dict:
    """Score = ATK*3 + DEF*5 + HP*0.5 + sum(affix_value).

    Mirrors how bot.recompute_stats actually values gear (DEF is rarer
    so worth more per point). Best general-purpose policy.
    """
    return _equip_by_score(state, items_db, _score_weighted)


def equip_pure_dps(state: dict, items_db: dict) -> dict:
    """Maximize ATK on weapon, DEF on every other slot."""
    def score_for_slot(slot, item, instance):
        base_id = item["id"]
        affix_atk = sum(a["value"] for a in instance.get("affixes", []) if a["id"] == "strength")
        affix_def = sum(a["value"] for a in instance.get("affixes", []) if a["id"] == "agility")
        if slot == "weapon":
            return item.get("atk", 0) + affix_atk * 1.5
        else:
            return item.get("def", 0) + affix_def * 1.5
    return _equip_by_score(state, items_db, score_for_slot)


def equip_rarity_first(state: dict, items_db: dict) -> dict:
    """Highest rarity wins, tiebreak on ATK+DEF+HP. Models naive players."""
    def score_for_slot(slot, item, instance):
        rarity = item.get("rarity", "common")
        return RARITY_RANK.get(rarity, 0) * 1000 \
               + item.get("atk", 0) + item.get("def", 0) + item.get("hp", 0)
    return _equip_by_score(state, items_db, score_for_slot)


def _score_weighted(slot: str, item: dict, instance: dict) -> float:
    score = item.get("atk", 0) * 3 + item.get("def", 0) * 5 + item.get("hp", 0) * 0.5
    for affix in instance.get("affixes", []):
        score += affix.get("value", 0)
    return score


def _equip_by_score(state: dict, items_db: dict, score_fn: Callable) -> dict:
    """Walk inventory + currently equipped items, pick best per slot."""
    candidates = {slot: [] for slot in SLOTS_DERIVED}

    # Include currently equipped (so we don't downgrade if inventory has nothing
    # better)
    eq = state.get("equipped", {})
    for slot in SLOTS_DERIVED:
        cur = eq.get(slot)
        if isinstance(cur, dict) and cur.get("base_id"):
            candidates[slot].append(cur)

    # Plus inventory
    for inst in state.get("inventory", []):
        if not isinstance(inst, dict):
            continue
        bid = inst.get("base_id", "")
        item = items_db.get(bid)
        if not item:
            continue
        slot = item.get("slot", "")
        if slot in candidates:
            candidates[slot].append(inst)

    out = {}
    for slot, items in candidates.items():
        if not items:
            out[slot] = None
            continue
        best = max(items, key=lambda i: score_fn(slot, items_db.get(i.get("base_id", ""), {}), i))
        out[slot] = best
    return out


# ============================================================================
# UPGRADE POLICIES — given gold, return list of upgrade purchases
# ============================================================================

def upgrades_round_robin(state: dict, upgrades_db: dict) -> list[str]:
    """Buy cheapest affordable upgrade until none affordable. Cycles through."""
    return _buy_upgrades(state, upgrades_db,
                          score_fn=lambda u, ranks: -_cost(u, ranks))


def upgrades_combat_first(state: dict, upgrades_db: dict) -> list[str]:
    """Prioritize combat_training and toughening, then everything else."""
    priority = {"combat_training": 100, "toughening": 90, "conditioning": 80,
                "quick_reflexes": 50, "loot_sense": 30, "pouch": 20}
    return _buy_upgrades(state, upgrades_db,
                          score_fn=lambda u, ranks: priority.get(u["id"], 0))


def upgrades_hp_first(state: dict, upgrades_db: dict) -> list[str]:
    """Prioritize survival: conditioning + toughening first."""
    priority = {"conditioning": 100, "toughening": 90, "quick_reflexes": 60,
                "combat_training": 50, "pouch": 30, "loot_sense": 20}
    return _buy_upgrades(state, upgrades_db,
                          score_fn=lambda u, ranks: priority.get(u["id"], 0))


def _cost(upgrade: dict, ranks: dict) -> int:
    """Cost of next rank for upgrade. Curve from data/bot_upgrades.json."""
    rank = ranks.get(upgrade["id"], 0)
    if rank >= upgrade.get("max_rank", 0):
        return 1 << 30  # effectively infinite
    base = upgrade.get("base_cost", 100)
    mult = upgrade.get("cost_multiplier", 2.5)
    return int(base * (mult ** rank))


def _buy_upgrades(state: dict, upgrades_db: dict, score_fn: Callable) -> dict:
    """Repeatedly buy the highest-scoring affordable upgrade until broke.

    Returns updated bot_upgrades dict + spent gold delta. Does NOT modify state.
    """
    gold = int(state.get("gold", 0))
    ranks = dict(state.get("bot_upgrades", {}))
    purchased: list[str] = []
    spent = 0

    safety_iter = 100  # avoid infinite loops on weird data
    while safety_iter > 0:
        safety_iter -= 1
        # Find affordable, not-maxed upgrades, take highest score.
        affordable = []
        for u in upgrades_db.values():
            cur_rank = ranks.get(u["id"], 0)
            if cur_rank >= u.get("max_rank", 0):
                continue
            cost = _cost(u, ranks)
            if cost > gold:
                continue
            affordable.append(u)
        if not affordable:
            break
        pick = max(affordable, key=lambda u: score_fn(u, ranks))
        cost = _cost(pick, ranks)
        gold -= cost
        spent += cost
        ranks[pick["id"]] = ranks.get(pick["id"], 0) + 1
        purchased.append(pick["id"])
    return {"bot_upgrades": ranks, "gold": gold, "purchased": purchased, "spent": spent}


# ============================================================================
# ADVANCEMENT POLICIES — given run history, decide next branch to run
# ============================================================================

def advance_strict(history: list[dict], unlocked: list[str], current: str,
                   biomes_db: dict) -> str:
    """Advance immediately to the highest-tier branch unlocked. Default."""
    return _highest_tier_unlocked(unlocked, biomes_db)


def advance_cautious(history: list[dict], unlocked: list[str], current: str,
                     biomes_db: dict) -> str:
    """Need 3 wins in a row at current branch before advancing.

    If win streak < 3, stay at current. Otherwise advance to highest unlocked.
    """
    recent = [h for h in history if h.get("branch") == current][-3:]
    if len(recent) < 3 or not all(h.get("victory") for h in recent):
        return current
    return _highest_tier_unlocked(unlocked, biomes_db)


def advance_greedy(history: list[dict], unlocked: list[str], current: str,
                   biomes_db: dict) -> str:
    """Try the highest unlocked. If win rate < 30% over last 5 attempts, retreat."""
    target = _highest_tier_unlocked(unlocked, biomes_db)
    if target == current:
        return current
    recent_at_target = [h for h in history if h.get("branch") == target][-5:]
    if recent_at_target:
        wins = sum(1 for h in recent_at_target if h.get("victory"))
        if wins / len(recent_at_target) < 0.3:
            # Step down one tier
            return _step_down_tier(target, unlocked, biomes_db)
    return target


def _highest_tier_unlocked(unlocked: list[str], biomes_db: dict) -> str:
    """Of unlocked branches, return the highest tier (random pick within tier)."""
    by_tier = {}
    for b in unlocked:
        biome = biomes_db.get(b, {})
        tier = int(biome.get("tier", 1))
        by_tier.setdefault(tier, []).append(b)
    if not by_tier:
        return "dungeon"
    max_tier = max(by_tier)
    # Stable pick: alphabetically first (deterministic across re-runs)
    return sorted(by_tier[max_tier])[0]


def _step_down_tier(branch: str, unlocked: list[str], biomes_db: dict) -> str:
    cur_tier = int(biomes_db.get(branch, {}).get("tier", 1))
    candidates = [b for b in unlocked if int(biomes_db.get(b, {}).get("tier", 1)) == cur_tier - 1]
    return sorted(candidates)[0] if candidates else branch


# ============================================================================
# Database loaders
# ============================================================================

def load_items_db() -> dict:
    return {it["id"]: it for it in json.load(ITEMS_PATH.open())["items"]}


def load_upgrades_db() -> dict:
    data = json.load(UPGRADES_PATH.open())
    # data shape: {"upgrades": [{...}]}
    items = data.get("upgrades", []) if isinstance(data, dict) else data
    return {u["id"]: u for u in items}


def load_biomes_db() -> dict:
    return json.load(BIOMES_PATH.open())["biomes"]


# Registry — picks by name string for the harness's --policy flag
EQUIP_POLICIES = {
    "score_weighted": equip_score_weighted,
    "pure_dps": equip_pure_dps,
    "rarity_first": equip_rarity_first,
}

UPGRADE_POLICIES = {
    "round_robin": upgrades_round_robin,
    "combat_first": upgrades_combat_first,
    "hp_first": upgrades_hp_first,
}

ADVANCE_POLICIES = {
    "strict": advance_strict,
    "cautious": advance_cautious,
    "greedy": advance_greedy,
}
