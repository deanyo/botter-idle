#!/usr/bin/env python3
"""parse_grind.py — Parse Botter grind logs into structured Python objects.

Used by /duel and /sweep skills to compare runs. Also runnable as a CLI for
ad-hoc inspection:

    python3 tools/parse_grind.py logs/grind/<latest>.log
    python3 tools/parse_grind.py --combat logs/grind/<latest>.log    # per-attack rollup

The grind log emits structured single-line tags:

    [seed] world_rng=N
    [run] start hp=N/M level=N gold=N seed=N
    [run] end #N victory=true|false floor=N level=N gold=N kills=N loot=N
                portals=N stalls=N biomes=N uniq_vaults=N elapsed=Ns
    [gen] f=N biome=X layout=Y cells=N largest=N regions=N bbox=NxN rooms=N
          vaults=[...]
    [floor] f=N biome=X ticks=N kills=N loot=N chests=N altars=N fountains=N
            portals=N stalls=N hp_lost=N
    [combat] atk=X def=Y wpn=Z raw=N crit=0|1 dealt=N def_hp=N boss=0|1 mb=0|1
    [portal] entered=X -> biome=Y bias=N on_floor=N
    [run] auto-grind COMPLETE total=N runs

Anything else is ignored (perf lines, render lines, etc).

Caveat — bot invincibility in grind mode:

    By default, auto-grind sets DebugJump.bot_invincible = true so /grind
    reaches floor 10 reliably for procgen audit. In that mode [combat]
    events where defender=bot will all show dealt=0. To get meaningful
    damage-taken signal (and meaningful win-rate signal for /duel), set
    BOTTER_NO_INVINCIBLE=1 — the balance skills (/duel, /sweep) do this
    automatically. Damage *dealt* by bot to enemies is always accurate.
"""

from __future__ import annotations
import argparse
import json
import re
import sys
from collections import Counter, defaultdict
from dataclasses import dataclass, field
from pathlib import Path


# ---------- Dataclasses ----------

@dataclass
class CombatEvent:
    attacker: str          # "bot" or enemy_id
    defender: str          # "bot" or enemy_id
    weapon: str            # weapon base_id (empty when attacker is enemy)
    raw: int               # damage rolled (post-crit, pre-defense)
    crit: bool
    dealt: int             # damage actually applied (raw - target_def, ≥0)
    defender_hp: int       # target HP remaining after the hit
    boss: bool
    miniboss: bool


@dataclass
class FloorResult:
    f: int
    biome: str
    layout: str = ""
    ticks: int = 0
    kills: int = 0
    loot: int = 0
    chests: int = 0
    altars: int = 0
    fountains: int = 0
    portals: int = 0
    stalls: int = 0
    hp_lost: int = 0
    cells: int = 0
    largest: int = 0
    regions: int = 0
    bbox: str = ""
    rooms: int = 0
    vaults: list[str] = field(default_factory=list)


@dataclass
class RunResult:
    n: int                  # 1-based run number within the grind
    seed: int = 0           # BOTTER_SEED at run start
    start_hp: int = 0
    start_max_hp: int = 0
    start_level: int = 0
    start_gold: int = 0
    victory: bool = False
    end_floor: int = 0
    end_level: int = 0
    end_gold: int = 0
    kills: int = 0
    loot: int = 0
    portals: int = 0
    stalls: int = 0
    biomes_visited: int = 0
    unique_vaults: int = 0
    elapsed_s: float = 0.0
    floors: list[FloorResult] = field(default_factory=list)
    combat: list[CombatEvent] = field(default_factory=list)


@dataclass
class GrindResult:
    runs: list[RunResult] = field(default_factory=list)
    completed: bool = False
    total_runs: int = 0
    log_path: str = ""

    # ---- Convenience accessors ----
    @property
    def victories(self) -> int:
        return sum(1 for r in self.runs if r.victory)

    @property
    def win_rate(self) -> float:
        return self.victories / len(self.runs) if self.runs else 0.0

    @property
    def avg_floor(self) -> float:
        return _mean(r.end_floor for r in self.runs)

    @property
    def avg_kills(self) -> float:
        return _mean(r.kills for r in self.runs)

    @property
    def avg_loot(self) -> float:
        return _mean(r.loot for r in self.runs)

    @property
    def avg_elapsed(self) -> float:
        return _mean(r.elapsed_s for r in self.runs)

    def damage_by_weapon(self) -> Counter:
        """Sum of dealt damage by attacker weapon id (bot-side only)."""
        c = Counter()
        for r in self.runs:
            for ev in r.combat:
                if ev.attacker == "bot":
                    c[ev.weapon or "(unarmed)"] += ev.dealt
        return c

    def damage_by_attacker(self) -> Counter:
        c = Counter()
        for r in self.runs:
            for ev in r.combat:
                c[ev.attacker] += ev.dealt
        return c

    def damage_to_defender(self) -> Counter:
        c = Counter()
        for r in self.runs:
            for ev in r.combat:
                c[ev.defender] += ev.dealt
        return c

    def boss_kill_events(self) -> list[CombatEvent]:
        """Final-blow events on a boss — the hit that drops def_hp ≤ 0."""
        out = []
        for r in self.runs:
            for ev in r.combat:
                if ev.boss and ev.defender_hp <= 0:
                    out.append(ev)
        return out


def _mean(xs):
    xs = list(xs)
    return sum(xs) / len(xs) if xs else 0.0


# ---------- Parsing ----------

# Match key=value pairs where value is one of: integer, float, bareword, quoted
# string, or a JSON-style list. Simple approach — split on space then split on
# the first '=' per token. The vaults=[...] and elapsed=12.3s wrinkles are
# handled inline.
_KV_RE = re.compile(r"(\w+)=([^=]*?)(?=\s+\w+=|\s*$)")


def _parse_kv(line_body: str) -> dict[str, str]:
    """Extract key=value pairs from a log line body. Lazy match on the value."""
    return {m.group(1): m.group(2).strip() for m in _KV_RE.finditer(line_body)}


def _to_int(s: str, default: int = 0) -> int:
    try:
        return int(s.strip())
    except (ValueError, TypeError):
        return default


def _to_float(s: str, default: float = 0.0) -> float:
    try:
        return float(s.strip().rstrip("s"))
    except (ValueError, TypeError):
        return default


def _to_bool(s: str) -> bool:
    return s.strip().lower() in ("true", "1", "yes")


_VAULTS_RE = re.compile(r'vaults=\[(.*?)\]')
_QUOTED_RE = re.compile(r'"([^"]*)"')


def _extract_vaults(line: str) -> list[str]:
    m = _VAULTS_RE.search(line)
    if not m:
        return []
    return _QUOTED_RE.findall(m.group(1))


def parse(log_path: str | Path) -> GrindResult:
    """Parse a Botter grind log into a GrindResult."""
    grind = GrindResult(log_path=str(log_path))
    current: RunResult | None = None
    floors_by_n: dict[tuple[int, int], FloorResult] = {}

    with open(log_path) as f:
        for line in f:
            line = line.rstrip()

            # [run] start hp=N/M level=N gold=N seed=N
            if line.startswith("[run] start "):
                current = RunResult(n=len(grind.runs) + 1)
                grind.runs.append(current)
                kv = _parse_kv(line[len("[run] start "):])
                hp = kv.get("hp", "0/0")
                if "/" in hp:
                    a, b = hp.split("/", 1)
                    current.start_hp = _to_int(a)
                    current.start_max_hp = _to_int(b)
                current.start_level = _to_int(kv.get("level", "0"))
                current.start_gold = _to_int(kv.get("gold", "0"))
                current.seed = _to_int(kv.get("seed", "0"))
                continue

            # [run] end #N victory=... floor=... ...
            if line.startswith("[run] end "):
                if current is None:
                    continue
                kv = _parse_kv(line[len("[run] end "):])
                current.victory = _to_bool(kv.get("victory", ""))
                current.end_floor = _to_int(kv.get("floor", "0"))
                current.end_level = _to_int(kv.get("level", "0"))
                current.end_gold = _to_int(kv.get("gold", "0"))
                current.kills = _to_int(kv.get("kills", "0"))
                current.loot = _to_int(kv.get("loot", "0"))
                current.portals = _to_int(kv.get("portals", "0"))
                current.stalls = _to_int(kv.get("stalls", "0"))
                current.biomes_visited = _to_int(kv.get("biomes", "0"))
                current.unique_vaults = _to_int(kv.get("uniq_vaults", "0"))
                current.elapsed_s = _to_float(kv.get("elapsed", "0"))
                continue

            # [run] auto-grind COMPLETE total=N runs
            if "auto-grind COMPLETE" in line:
                grind.completed = True
                m = re.search(r"total=(\d+)", line)
                if m:
                    grind.total_runs = int(m.group(1))
                continue

            # [gen] f=N biome=X layout=Y cells=... vaults=[...]
            if line.startswith("[gen] "):
                if current is None:
                    continue
                kv = _parse_kv(line[len("[gen] "):])
                f = _to_int(kv.get("f", "0"))
                key = (current.n, f)
                fr = floors_by_n.get(key) or FloorResult(f=f, biome=kv.get("biome", ""))
                fr.layout = kv.get("layout", "")
                fr.cells = _to_int(kv.get("cells", "0"))
                fr.largest = _to_int(kv.get("largest", "0"))
                fr.regions = _to_int(kv.get("regions", "0"))
                fr.bbox = kv.get("bbox", "")
                fr.rooms = _to_int(kv.get("rooms", "0"))
                fr.vaults = _extract_vaults(line)
                if key not in floors_by_n:
                    floors_by_n[key] = fr
                    current.floors.append(fr)
                continue

            # [floor] f=N biome=X ticks=... kills=... ...
            if line.startswith("[floor] "):
                if current is None:
                    continue
                kv = _parse_kv(line[len("[floor] "):])
                f = _to_int(kv.get("f", "0"))
                key = (current.n, f)
                fr = floors_by_n.get(key)
                if fr is None:
                    fr = FloorResult(f=f, biome=kv.get("biome", ""))
                    floors_by_n[key] = fr
                    current.floors.append(fr)
                fr.ticks = _to_int(kv.get("ticks", "0"))
                fr.kills = _to_int(kv.get("kills", "0"))
                fr.loot = _to_int(kv.get("loot", "0"))
                fr.chests = _to_int(kv.get("chests", "0"))
                fr.altars = _to_int(kv.get("altars", "0"))
                fr.fountains = _to_int(kv.get("fountains", "0"))
                fr.portals = _to_int(kv.get("portals", "0"))
                fr.stalls = _to_int(kv.get("stalls", "0"))
                fr.hp_lost = _to_int(kv.get("hp_lost", "0"))
                continue

            # [combat] atk=X def=Y wpn=Z raw=N crit=0|1 dealt=N def_hp=N boss=0|1 mb=0|1
            if line.startswith("[combat] "):
                if current is None:
                    continue
                kv = _parse_kv(line[len("[combat] "):])
                current.combat.append(CombatEvent(
                    attacker=kv.get("atk", ""),
                    defender=kv.get("def", ""),
                    weapon=kv.get("wpn", ""),
                    raw=_to_int(kv.get("raw", "0")),
                    crit=kv.get("crit", "0") == "1",
                    dealt=_to_int(kv.get("dealt", "0")),
                    defender_hp=_to_int(kv.get("def_hp", "0")),
                    boss=kv.get("boss", "0") == "1",
                    miniboss=kv.get("mb", "0") == "1",
                ))
                continue

            # Other tags (portal, stall, perf, render, gen-phases) — currently
            # unused. Add fields above if a future skill needs them.

    return grind


# ---------- CLI ----------

def _print_summary(g: GrindResult, show_combat: bool = False):
    print(f"log: {g.log_path}")
    print(f"runs: {len(g.runs)}  completed={g.completed}")
    if not g.runs:
        return
    print(f"win_rate: {g.win_rate:.0%}  avg_floor: {g.avg_floor:.1f}  "
          f"avg_kills: {g.avg_kills:.1f}  avg_loot: {g.avg_loot:.1f}  "
          f"avg_elapsed: {g.avg_elapsed:.1f}s")
    for r in g.runs:
        outcome = "WIN " if r.victory else "LOSS"
        print(f"  #{r.n} {outcome} f={r.end_floor} kills={r.kills:>3} loot={r.loot:>3} "
              f"gold={r.end_gold:>5} elapsed={r.elapsed_s:>5.1f}s seed={r.seed}")
    if show_combat:
        print()
        print("damage by bot weapon:")
        for wpn, total in g.damage_by_weapon().most_common():
            print(f"  {wpn:30s} {total:>8} damage")
        print()
        print("top 10 enemy attackers (damage to bot):")
        atks = Counter()
        for r in g.runs:
            for ev in r.combat:
                if ev.defender == "bot":
                    atks[ev.attacker] += ev.dealt
        for atk, dmg in atks.most_common(10):
            print(f"  {atk:30s} {dmg:>8} damage")


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("log", help="Path to grind log.")
    parser.add_argument("--combat", action="store_true",
                        help="Include damage-source breakdown.")
    parser.add_argument("--json", action="store_true",
                        help="Emit machine-readable JSON instead of human summary.")
    args = parser.parse_args()
    g = parse(args.log)
    if args.json:
        # Hand-built dict (dataclasses → dict deep with combat list trimmed by
        # default to keep the output usable; pass --combat to include).
        out = {
            "log_path": g.log_path,
            "completed": g.completed,
            "total_runs": g.total_runs,
            "win_rate": g.win_rate,
            "avg_floor": g.avg_floor,
            "avg_kills": g.avg_kills,
            "avg_loot": g.avg_loot,
            "avg_elapsed_s": g.avg_elapsed,
            "runs": [{
                "n": r.n, "seed": r.seed, "victory": r.victory,
                "end_floor": r.end_floor, "kills": r.kills, "loot": r.loot,
                "gold": r.end_gold, "elapsed_s": r.elapsed_s,
                "floors": [{"f": fr.f, "biome": fr.biome, "kills": fr.kills,
                            "loot": fr.loot, "hp_lost": fr.hp_lost} for fr in r.floors],
                **({"damage_by_weapon": dict(_run_damage_by_weapon(r))} if args.combat else {}),
            } for r in g.runs],
        }
        print(json.dumps(out, indent=2))
    else:
        _print_summary(g, show_combat=args.combat)


def _run_damage_by_weapon(r: RunResult) -> Counter:
    c = Counter()
    for ev in r.combat:
        if ev.attacker == "bot":
            c[ev.weapon or "(unarmed)"] += ev.dealt
    return c


if __name__ == "__main__":
    sys.exit(main() or 0)
