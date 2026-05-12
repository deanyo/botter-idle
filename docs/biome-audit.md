# Biome visual audit (2026-05-12)

Produced via debug-jump screenshot self-verification — `DEBUG_FLOOR.txt` marker → 2-second settled screenshot saved to `user://debug_screenshots/<biome>.png`. All 24 biomes captured and inspected.

Order in this document = reading order in the screenshots, **not** quality ranking. See ratings inline.

## Methodology

For each biome, I checked:
- **Floor primary**: does the dominant tile read as biome-appropriate?
- **Wall primary**: contrast against floor? Biome-evocative?
- **Tile uniformity**: are primaries square-symmetric (good) or directional/feature-edge (bad — produces "messy" / "random" look)?
- **Lighting / palette**: ambient modulate consistent with biome theme?
- **Decor density**: ambient objects (lamps, mushrooms, sigils) present and on-theme?

---

## SHIP-READY (looks great or near-final)

### dungeon ✓
- Floor: warm grey stone with brown rust hints — square symmetric ✓
- Walls: matching grey stone with brick variants ✓
- Identity: classic stone dungeon, exactly the baseline we want
- Notes: reference quality

### lair ✓
- Floor: green organic mottled — fits "wild caves" aesthetic
- Walls: tree alternates appearing, brown wall primary ✓
- Identity: instantly reads as natural cavern
- Notes: this and dungeon are our calibration biomes

### crypt ✓
- Floor: dark stone with crypt-blue tint
- Walls: cool stone, fits dim mood
- Identity: claustrophobic and cool — works
- Notes: ambient_decor flames give nice glow

### tomb ✓
- Floor: warm tan sandstone — square symmetric ✓
- Walls: matching sandy walls
- Identity: definitely Egyptian tomb feel
- Notes: gold-ish modulate selling it

### forge / pandemonium ✓
- Floor: red-orange stone, lava-tinted
- Walls: dark forge walls
- Identity: hellish heat, immediately readable
- Notes: user previously praised pandemonium specifically

### zot ✓
- Floor: blue starfield/runic with subtle sparkle
- Walls: dark cool
- Identity: cosmic finale vibe — perfect for floor 10
- Notes: user previously praised zot specifically

### snake ✓
- Floor: yellow scaled — square symmetric, distinctive
- Walls: yellow brick
- Identity: serpentine pit, on-theme
- Notes: reads instantly different from other yellow-ish biomes

### tempo (temple) ✓
- Floor: marble — clean and reverent
- Walls: light brick
- Identity: holy ground, mostly empty
- Notes: low enemy_pool intentional (DCSS Temple has no monsters)

### orc / mines ✓
- Floor: warm tan/orange orcish stone
- Walls: similar tone
- Identity: industrial mining vibe
- Notes: passes muster

### labyrinth ✓
- Floor: dark labyrinth stone
- Walls: matching brick
- Identity: tight maze atmosphere
- Notes: works as transition biome

### glacier ✓
- Floor: blue ice-tinted stone
- Walls: cool tones
- Identity: chilly, distinctive
- Notes: passes

### swamp ✓
- Floor: brown bog
- Walls: mossy with mangrove alternates
- Identity: works
- Notes: passes

### forest ✓
- Floor: green organic
- Walls: tree alternates
- Identity: works as Lair-adjacent natural biome
- Notes: very similar to lair — could be made more woodsy with tree-density bump

---

## SHIP-WITH-NOTES (functional, room to improve)

### vaults — busy floor pattern
- Floor: ornate green-diamond rune pattern with grey-blue accent squares
- This is faithful DCSS Vaults marble (rune-engraved) but the rune pattern repeated everywhere is overpowering
- **Action item**: pick 1-2 rune-floor variants for primary, demote rest to accent. Or use plain marble (tomb-like) with rune patches as accent only.
- Reads as Vaults but visually busy compared to dungeon's calmness

### slime — substitute floor
- Currently using `dungeon` floor (stone) since DCSS slime tiles are directional overlays (lessons learned)
- Walls are slime-themed — gives "slime walls on stone floor" look, which is *correct* DCSS behavior
- **Action item**: long-term, build directional autotile (#66) so slime drips render on floor cells adjacent to walls. For now, look is intentional and acceptable.

### dungeon_dark — no longer broken
- After my fix: brick_dark walls, modulate brightened from 0.65 → 0.78
- Walls now visible and contrasting
- Reads as a darker dungeon variant — works as a tonal shift biome
- Notes: still slightly samey vs dungeon; could differentiate with cooler modulate

### depths
- Floor: black_cobalt — dark purple-blue stone with star sparkles
- Walls: crystal_wall — translucent crystal walls
- Identity: late-game cosmic descent, distinctive enough
- Notes: works. Subtle enough that on top of crypt/zot it might look samey; tune by giving depths a unique secondary palette later.

### elf
- Floor: crystal_floor — teal/cyan glittering tiles ✓
- Walls: brick_dark — too dark, somewhat muddies the elven shimmer
- Identity: cool-toned magical halls
- **Action item**: try lighter wall variants or magical-blue walls for a more high-fantasy look. Acceptable for now.

### spider
- Floor: bog_green substitute (DCSS lacks dedicated spider floor — webs are procedural)
- Walls: brick_brown — woodsy
- Identity: green-brown organic warren
- Notes: works as substitute. True spider feel requires web overlay decor (task #65).

### shoals
- Floor: yellow tinted (similar to snake) with yellow walls
- Identity: a beach-y pit feel, but fairly close to snake's palette
- **Action item**: separate shoals more from snake. Use cooler blue water tones, lighten floor toward sand.

### hive
- Floor: yellow honeycomb-ish
- Walls: matching
- Identity: works — bees-only biome reads correctly
- Notes: maybe add buzz/pollen ambient decor later

### abyss
- Floor: red-brown organic
- Walls: dark organic
- Identity: cursed/corrupt land — works
- Notes: could be even more chaotic with morphing tiles, but visually it's distinctive

---

## INSIGHTS FROM THIS PASS — applying broadly

These insights extend the lessons we learned from slime and the floor-tile audit. Bake into future biome work:

1. **DCSS's tile-prefix conventions are not uniform.** Some biomes have proper square-symmetric primary tiles (dungeon, lair, crypt, tomb, snake, hive). Others ship with directional overlays meant for wall-edge placement (slime). Always inspect raw tiles before assuming numbered variants are equivalent.

2. **Walls carry biome identity more reliably than floors.** Pandemonium and Zot feel right because their walls are visually distinct (dark + sparkle). Dungeon_dark felt wrong before because its walls disappeared into the modulate. **Action: when adding a new biome, prioritize getting walls right over floors.**

3. **Modulate is a strong lever.** Going from 0.65 (dungeon_dark first try) to 0.78 made walls suddenly visible. Modulate values below ~0.7 for any channel risk crushing detail. Reserve heavy modulate (<0.7) only for biomes where atmosphere > readability is desired (crypt, dungeon_dark, depths).

4. **Tile rotation could quadruple variety for free** — only on **square-symmetric** primaries. None of our current primaries explicitly are tagged rotatable; task #56 deferred until tile audit pass identifies safe candidates.

5. **Two biomes can share floor tiles if walls differ enough.** Forest and lair both use green organic — they're nearly indistinguishable by floor alone. We differentiate via wall_alternates (lair has more tree, forest stays cleaner).

6. **Ambient decor density matters more than I expected.** Biomes with `ambient_decor` lanterns/flames/orbs (crypt, vaults, zot) feel populated. Biomes with no decor (mines, depths) feel sterile. **Action: every biome should have at least one ambient-light type at 0.014+ density.**

7. **Run plans should respect difficulty curve.** Putting a high-floor biome (e.g. zot) at floor 1 via debug-jump made the bot trivially destroy enemies (HP 2592 vs floor-1 enemies). For shipped runs, branch chains should preserve the early-stone → mid-branch → late-stone → final-boss arc.

## Quality bumps to ship next session

Highest-impact, lowest-effort:
1. **Vaults floor demotion** — split `vaults_*` numbered tiles into primary subset + accent subset. Prevents the "ornate carpet" issue.
2. **Shoals palette differentiation** — pull cooler blue tiles (sand/sea) so it doesn't clone snake's yellow.
3. **Elf wall lightening** — try `elven` wall variants (if available) or use `brick_gray` instead of `brick_dark` to brighten elf halls.

Medium-effort, medium-impact:
4. **Forest secondary differentiation** — bump tree-density modifier so forest reads more "deep forest" vs lair's "open glade."
5. **Spider web ambient decor** — generate a 32×32 web texture programmatically (Image ops), use as ambient sprinkle in spider biome (task #65).

Defer:
6. Directional autotile for slime (task #66) — proper way to handle slime drips on wall-adjacent floor cells.
7. Tile rotation pass (task #56) — quadruples variety for free on rotation-safe biomes.
