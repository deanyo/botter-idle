#!/usr/bin/env python3
"""balance.py — Shared helpers for /duel, /sweep, and ad-hoc balance experiments.

Provides:
  - run_grind(seed, runs, speed, log_path, env={}) — runs Godot headless,
    streams stdout into log_path, returns when [run] auto-grind COMPLETE
    appears or after a timeout.
  - append_index(entry) — write one line to logs/balance/index.jsonl
  - new_log_path(kind, label) — timestamped log path under logs/balance/
  - inject(spec, reset=True) — convenience wrapper around inject_save.py.
  - clear_save() — delete debug save.

Skills should never spawn Godot directly; always go through run_grind so
that:
  - markers are cleaned up on exit (per CLAUDE.md hard rule)
  - BOTTER_NO_INVINCIBLE is set by default for balance experiments
  - logs land in logs/balance/ not logs/grind/
"""

from __future__ import annotations
import json
import os
import shutil
import signal
import subprocess
import sys
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Optional

REPO_ROOT = Path(__file__).resolve().parent.parent
PROJECT = REPO_ROOT / "project"
GODOT = "/Applications/Godot.app/Contents/MacOS/Godot"
USER_DATA = Path.home() / "Library" / "Application Support" / "Godot" / "app_userdata" / "Botter"
GRIND_MARKER = USER_DATA / "AUTO_GRIND.txt"
PARKED_MARKER = USER_DATA / "AUTO_GRIND.txt.parked"
DEBUG_MARKER = USER_DATA / "DEBUG_FLOOR.txt"
DEBUG_SAVE = USER_DATA / "botter_save_debug.json"

LOGS_BALANCE = REPO_ROOT / "logs" / "balance"
INDEX_PATH = LOGS_BALANCE / "index.jsonl"


def _ts() -> str:
    return time.strftime("%Y%m%d-%H%M%S")


def new_log_path(kind: str, label: str) -> Path:
    LOGS_BALANCE.mkdir(parents=True, exist_ok=True)
    safe_label = "".join(c if c.isalnum() or c in "-_" else "_" for c in label)[:40]
    return LOGS_BALANCE / f"{_ts()}_{kind}_{safe_label}.log"


def append_index(entry: dict) -> None:
    """Append one JSON line to logs/balance/index.jsonl."""
    LOGS_BALANCE.mkdir(parents=True, exist_ok=True)
    entry = dict(entry)
    entry.setdefault("ts", time.time())
    with INDEX_PATH.open("a") as f:
        f.write(json.dumps(entry) + "\n")


def clear_save() -> None:
    if DEBUG_SAVE.exists():
        DEBUG_SAVE.unlink()


def clean_markers() -> None:
    for p in (GRIND_MARKER, PARKED_MARKER, DEBUG_MARKER, DEBUG_MARKER.with_suffix(".txt.parked")):
        if p.exists():
            p.unlink()


def inject(spec: dict, reset: bool = True) -> None:
    """Run inject_save.py with the given spec dict. Validates against items.json etc."""
    cmd = [sys.executable, str(REPO_ROOT / "tools" / "inject_save.py")]
    if reset:
        cmd.append("--reset")
    cmd.append("-")
    res = subprocess.run(cmd, input=json.dumps(spec).encode(),
                         stdout=subprocess.DEVNULL,
                         stderr=subprocess.PIPE)
    if res.returncode != 0:
        raise RuntimeError(f"inject_save failed: {res.stderr.decode()}")


@dataclass
class GrindSpawn:
    log_path: Path
    runs_requested: int
    completed: bool = False
    elapsed_s: float = 0.0


def run_grind(seed: int, runs: int = 1, speed: int = 16,
              label: str = "exp", env_extra: Optional[dict] = None,
              invincible: bool = False, timeout_s: Optional[float] = None) -> GrindSpawn:
    """Drive a headless grind, return the log path.

    Args:
      seed: BOTTER_SEED. 0 means "no seeding" (random world).
      runs: how many complete runs to play in this Godot session.
      speed: Engine.time_scale multiplier (16x default = ~30s/run).
      label: short tag baked into the log filename.
      env_extra: additional env vars (e.g. {"BOTTER_FORCE_BIOME": "forge"}).
      invincible: True keeps grind invincibility (default False for balance).
      timeout_s: hard ceiling on the Godot subprocess. Default = 60 * runs.

    The function blocks until either:
      - the log contains "[run] auto-grind COMPLETE", OR
      - timeout_s elapses, in which case Godot is SIGTERM'd.

    Markers are always cleaned up on exit.
    """
    log_path = new_log_path("grind", label)
    if timeout_s is None:
        timeout_s = max(60.0, runs * 60.0)

    USER_DATA.mkdir(parents=True, exist_ok=True)
    GRIND_MARKER.write_text(f"{speed},{runs}\n")

    env = os.environ.copy()
    if seed != 0:
        env["BOTTER_SEED"] = str(seed)
    if not invincible:
        env["BOTTER_NO_INVINCIBLE"] = "1"
    if env_extra:
        env.update(env_extra)

    t0 = time.time()
    completed = False
    log_file = log_path.open("w")
    try:
        proc = subprocess.Popen(
            [GODOT, "--path", str(PROJECT), "--headless"],
            stdout=log_file, stderr=subprocess.STDOUT, env=env,
        )
        # Poll until completion line appears or timeout.
        while True:
            if proc.poll() is not None:
                break
            elapsed = time.time() - t0
            if elapsed >= timeout_s:
                # Hard kill — runaway run.
                proc.send_signal(signal.SIGTERM)
                try:
                    proc.wait(timeout=3.0)
                except subprocess.TimeoutExpired:
                    proc.kill()
                break
            # Cheap tail of the log to see if completion line landed.
            # Use a generous tail because [combat] is verbose at 16x speed.
            try:
                tail = _tail(log_path, 65536)
                if "[run] auto-grind COMPLETE" in tail:
                    proc.send_signal(signal.SIGTERM)
                    try:
                        proc.wait(timeout=3.0)
                    except subprocess.TimeoutExpired:
                        proc.kill()
                    completed = True
                    break
            except OSError:
                pass
            time.sleep(0.5)
        # Final check: if Godot exited cleanly (poll returned), the
        # completion line may be in the log even though we never saw it
        # mid-loop (small grinds finish in one polling interval).
        if not completed:
            try:
                tail = _tail(log_path, 131072)
                if "[run] auto-grind COMPLETE" in tail:
                    completed = True
            except OSError:
                pass
    finally:
        log_file.close()
        clean_markers()

    return GrindSpawn(log_path=log_path, runs_requested=runs,
                      completed=completed, elapsed_s=time.time() - t0)


def _tail(path: Path, n_bytes: int = 4096) -> str:
    sz = path.stat().st_size
    with path.open("rb") as f:
        f.seek(max(0, sz - n_bytes))
        return f.read().decode("utf-8", errors="replace")
