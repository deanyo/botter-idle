#!/usr/bin/env bash
# One-shot HTML5 build + itch.io push via butler.
#
# Setup (one-time):
#   1. Install butler:
#        brew install butler
#      OR download from https://itch.io/docs/butler/installing.html
#   2. Log in:
#        butler login
#   3. Set ITCH_TARGET below to your <user>/<project>:<channel>.
#
# Usage:
#   bash tools/deploy_web.sh           # build + push
#   bash tools/deploy_web.sh --no-push # build only
set -euo pipefail

# CHANGE ME — your itch.io target. Format: <user>/<project>:<channel>
ITCH_TARGET="${ITCH_TARGET:-deanyo-gh/botter-idle:html5}"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_DIR="$REPO_ROOT/project"
DIST_DIR="$REPO_ROOT/dist/web"
ZIP_PATH="$REPO_ROOT/dist/botter_web.zip"
GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"

echo "==> Stamping build version"
# Bump a per-deploy counter and stamp it into a JSON file the game
# reads at boot — main.gd prints "[build] version=N ts=..." so the
# user can verify which build their browser actually loaded.
COUNTER_FILE="$REPO_ROOT/dist/.build_counter"
if [[ -f "$COUNTER_FILE" ]]; then
  COUNTER=$(($(cat "$COUNTER_FILE") + 1))
else
  COUNTER=1
fi
echo "$COUNTER" > "$COUNTER_FILE"
TS=$(date '+%Y-%m-%d %H:%M:%S')
cat > "$PROJECT_DIR/data/build_version.json" <<EOF
{"version": "v${COUNTER}", "ts": "${TS}"}
EOF
echo "    version=v${COUNTER} ts=${TS}"

echo "==> Building HTML5 export"
rm -f "$ZIP_PATH"
rm -f "$DIST_DIR"/index.*
"$GODOT" --headless --path "$PROJECT_DIR" --export-release "Web (itch.io)" 2>&1 | tail -3

if [[ ! -f "$DIST_DIR/index.html" ]]; then
  echo "ERROR: export did not produce $DIST_DIR/index.html" >&2
  exit 1
fi

echo "==> Zipping for archive"
( cd "$DIST_DIR" && zip -rq "$ZIP_PATH" ./* )
ls -lh "$ZIP_PATH"

if [[ "${1:-}" == "--no-push" ]]; then
  echo "==> --no-push; skipping butler upload"
  exit 0
fi

# Resolve butler — prefer one on PATH, else fall back to ~/bin/butler.
BUTLER="${BUTLER:-}"
if [[ -z "$BUTLER" ]]; then
  if command -v butler >/dev/null 2>&1; then
    BUTLER="butler"
  elif [[ -x "$HOME/bin/butler" ]]; then
    BUTLER="$HOME/bin/butler"
  else
    echo "ERROR: butler not found. Download from" >&2
    echo "       https://itchio.itch.io/butler" >&2
    echo "       and place it at ~/bin/butler (or set BUTLER=/path/to/butler)" >&2
    exit 1
  fi
fi

# butler push the directory directly (not the zip — itch unpacks zips
# server-side but butler can diff a directory more efficiently).
echo "==> Pushing $DIST_DIR -> $ITCH_TARGET"
"$BUTLER" push "$DIST_DIR" "$ITCH_TARGET"

echo "==> Build status"
"$BUTLER" status "$ITCH_TARGET"
