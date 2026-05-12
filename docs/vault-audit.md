# Vault visual audit (2026-05-12)

Captured via `scripts/debug_screenshot.sh <biome> <vault>` at 1920x1920 with full-map reveal (fog disabled, ambient modulate cleared, bot torch boosted, camera zoomed to fit grid). Screenshot manifest at `user://debug_screenshots/_manifest.txt`.

## Audit status

### Verified working
- **stone_arena** — oval grand-reveal arena, statue ring around perimeter, double-door entry, central stairs. ✓ Best-looking encompass vault we have.
- **twin_chambers** — top spawn chamber, vertical corridor, bottom loot chamber. Structurally clean.
- **portal_labyrinth** — large ovaloid maze, loot scattered, statues lining path. ✓
- **portal_arena** — broad arena with sweeping curves and statue rim. Looks solid.

### Captured but not visually verified yet (Read tool caching artifacts)
All 17 encompass vaults captured at 1920x1920. Latest paths in `_manifest.txt`. No connectivity errors during capture means all pass orphan-rescue (the hard correctness check).

- portal_bailey, portal_bazaar, portal_crucible, portal_desolation, portal_gauntlet
- portal_ice_cave, portal_necropolis, portal_ossuary, portal_sewer, portal_trove
- portal_volcano, portal_wizlab, portal_ziggurat

### Known visual quirks to revisit
1. **Grey halo around vault** — bot's PointLight2D radial-light texture creates a soft fade-to-grey-then-black outside the lit area. Cosmetic only. Disabling more of the lighting stack in screenshot mode would clean it up — defer.
2. **HUD covers top-left** — at 1920x1920 the HUD panel is still drawn at its mobile coords (10,4), so it covers a corner. Acceptable for audit screenshots.

## Tooling shipped
- `scripts/debug_screenshot.sh` — single-shot capture: `./debug_screenshot.sh <biome> [vault] [floor]` returns a unique-timestamp PNG path
- `_manifest.txt` — biome→latest-path map
- 1920x1920 viewport boost in screenshot mode
- Camera zoom-to-fit-grid in screenshot mode
- Whole-map reveal (fog/ambient/light overrides) in screenshot mode

## Process insights

1. **Read tool caches by name aggressively.** Same filename Reads can return stale content. Solution shipped: each screenshot has unique millisecond-precision suffix (`vaults_twin_chambers_3204.png`).
2. **Window-size boost requires `content_scale_mode = DISABLED`** or Godot rescales content back down. Set this in screenshot mode only.
3. **Camera zoom must compute from viewport size at capture time**, not from constants. Viewport is 540x960 mobile in normal play, 1920x1920 in audit. Camera zoom calc reads `get_viewport().get_visible_rect().size`.

## Next pass
- View remaining 13 portal vault screenshots, classify into ship/fix/redesign
- Polish bot-light grey halo if it bothers user
- Consider per-vault test harness that auto-asserts vault metrics (cell count, room count, distance from spawn to stairs)
