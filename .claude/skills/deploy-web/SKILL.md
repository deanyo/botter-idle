---
name: deploy-web
description: Build the HTML5 export and push it to itch.io via butler. Use when the user wants to ship a new web build to deanyo-gh/botter-idle so friends can playtest, or when they ask to "deploy" / "push to itch" / "publish". Wraps tools/deploy_web.sh — handles the Godot export, zip archive, and butler push in one command. First push uploads ~12MB; subsequent pushes only diff (typically <1MB).
user_invocable: true
---

# Botter web deploy

One-shot pipeline: Godot HTML5 export → zip archive → butler push to itch.io.

## Usage

```bash
bash /Users/dyo/claude/botter/tools/deploy_web.sh
```

That's it. It will:

1. Clear `dist/web/` and re-export from `project/` using the "Web (itch.io)" preset.
2. Zip the export to `dist/botter_web.zip` (12MB) for archive / manual fallback.
3. Push `dist/web/` to `deanyo-gh/botter-idle:html5` via butler.
4. Print build status.

To build without pushing (e.g. to test the export locally first):

```bash
bash /Users/dyo/claude/botter/tools/deploy_web.sh --no-push
```

## Prerequisites

One-time setup. **Skip this if `~/bin/butler version` works.**

1. Download butler from https://itchio.itch.io/butler (macOS amd64 zip).
2. `mkdir -p ~/bin && unzip ~/Downloads/butler-darwin-amd64.zip -d ~/bin/`
3. `chmod +x ~/bin/butler`
4. `~/bin/butler login` — opens a browser to authenticate.

The deploy script auto-resolves butler from PATH first, then `~/bin/butler` as
fallback. Override with `BUTLER=/path/to/butler bash deploy_web.sh` if needed.

## After a push lands

On the itch project page (https://deanyo-gh.itch.io/botter-idle/edit) confirm
the `html5` upload is ticked **"This file will be played in the browser"**. Set
once; future pushes inherit the flag.

## Inspecting an uploaded build

```bash
~/bin/butler status deanyo-gh/botter-idle:html5
```

Lists current channel/upload/build IDs. Useful when verifying a push went
through, or before / after a manual rollback.

## What the script does NOT do

- Run grind/screenshot validation before pushing — caller's responsibility.
- Bump a version string — itch auto-increments build numbers, but if you
  want a human-readable version, edit `project.godot::config/version`.
- Notify friends — paste the itch URL into wherever they hang out.
