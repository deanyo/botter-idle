#!/usr/bin/env python3
"""Sync canonical CREDITS.md / NOTICE.md into the Godot project.

The repo-root .md files are authoritative; project/data/credits.txt
and project/data/notice.txt are shipped copies the in-game Credits
screen reads via res://data/.

Run from repo root:
    python3 tools/sync_credits.py            # writes if drift
    python3 tools/sync_credits.py --check    # exit 1 on drift, no write

Wired into tools/check_before_commit.sh so the in-game text can't
silently fall behind the canonical attribution.
"""
from __future__ import annotations
import argparse
import os
import sys

REPO_ROOT = os.path.dirname(os.path.abspath(os.path.dirname(__file__)))
PAIRS = [
    ('CREDITS.md', 'project/data/credits.txt'),
    ('NOTICE.md', 'project/data/notice.txt'),
]


def read(p: str) -> str:
    with open(os.path.join(REPO_ROOT, p)) as f:
        return f.read()


def write(p: str, body: str) -> None:
    with open(os.path.join(REPO_ROOT, p), 'w') as f:
        f.write(body)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument('--check', action='store_true',
                    help='exit non-zero on drift instead of writing')
    args = ap.parse_args()

    drift: list[str] = []
    for src, dst in PAIRS:
        s = read(src)
        try:
            d = read(dst)
        except FileNotFoundError:
            d = ''
        if s != d:
            drift.append(f'{src} != {dst}')
            if not args.check:
                write(dst, s)

    if drift:
        if args.check:
            for d in drift:
                print(f'DRIFT: {d}', file=sys.stderr)
            print('run: python3 tools/sync_credits.py', file=sys.stderr)
            return 1
        for d in drift:
            print(f'synced: {d}')
    else:
        print('credits + notice in sync')
    return 0


if __name__ == '__main__':
    sys.exit(main())
