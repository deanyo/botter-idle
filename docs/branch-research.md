# DCSS Dungeon Branches: Comprehensive Specification for Botter

**Author's note**: This document describes the full roster of Dungeon Crawl Stone Soup dungeon branches, paraphrased from the DCSS source code (`branch-data.h`, `.cc` source files, and `.des` vault definitions). All descriptions are original paraphrases written for the Botter idle-game project; no GPL-licensed code excerpts are included. Tile filenames, asset inventory, and vault tags are referenced by name per DCSS documentation, and are not creative authorship. This guide serves as the specification for porting DCSS branch structures, aesthetics, and generation algorithms to Botter.

---

## Table of Contents

1. [Document Purpose](#document-purpose)
2. [Major Branches](#major-branches)
   - Dungeon (D)
   - Lair of Beasts (Lair)
   - Orcish Mines (Orc)
   - Elven Halls (Elf)
   - Snake Pit (Snake)
   - Spider Nest (Spider)
   - Swamp (Swamp)
   - Shoals (Shoals)
   - Slime Pits (Slime)
   - Vaults (Vaults)
   - Crypt (Crypt)
   - Tomb (Tomb)
   - Depths (Depths)
   - Zot (Zot)
3. [Hell Branches](#hell-branches)
   - Hell (Vestibule)
   - Dis (Iron City of Dis)
   - Gehenna (Gehenna)
   - Cocytus (Cocytus)
   - Tartarus (Tartarus)
4. [Chaos Realms](#chaos-realms)
   - Pandemonium (Pan)
   - The Abyss (Abyss)
5. [Portal Vaults & Minor Branches](#portal-vaults--minor-branches)
6. [Asset Gaps & Feasibility Table](#asset-gaps--feasibility-table)

---

## Document Purpose

This specification catalogs every major DCSS dungeon branch, extracted from the canonical branch table (`branch-data.h`), vault definitions (`.des` files), and generator code. Each branch entry covers:

- **Canonical identity**: official name, abbreviation, and depth range
- **Visual identity**: floor/wall tile prefixes, ambient lighting, colour palette
- **Layout approach**: generator used (basic_level, delve, procedural, encompass-vault-driven)
- **Signature monsters & aesthetics**: recurring enemy types, environmental hazards
- **Vault library**: representative vaults and their themes
- **Botter integration**: how this branch fits into a 10-floor idle run
- **Asset inventory**: which tile/sprite assets exist in our project vs. are wiki-canonical but missing

The goal is to enable faithful porting of DCSS branches into Botter without reinventing generation algorithms or balance.

---

# Major Branches

## Dungeon (D)

**Canonical name**: "the Dungeon" | **Abbreviation**: "D" | **Depth**: 15 floors | **Entry**: main entry point

### Depth & Structure
The main spine of DCSS. Single linear descent from D:1 (the Dungeon entrance) to D:15, where access to the Depths becomes available. Dungeon acts as a tutorial zone and staging ground for branch access — other branches (Lair, Orc, Vaults, Slime, Temple) branch off from specific D floors.

### Visual Identity
Stone dungeon. Floors use mottled grey stone tiles (`floor/stone_*`), sometimes with rust streaks and worn edges. Walls are grey stone blocks (`wall/stone_*`), occasionally with cracks or moss patches. The environment is dimly lit (standard torchlight intensity), with no special ambient colour. D:1-7 feels relatively "clean" (fewer stains), while D:8+ gains more weathering and darker stone.

### Layout Style
DCSS's `dgn_build_basic_level` generator: procedural trail-then-rooms approach. The algorithm carves 2-4 random-walk corridors, then places BSP-style rectangular rooms, then adds doors. Produces a mix of winding corridors and chunky open rooms. No special hazards (water, lava, etc.) in the core dungeon.

### Signature Monsters
Early D (1-7): rats, goblins, kobolds, orcs, worms, bats. Mid D (8-12): orc archers, ogres, trolls, giant scorpions, wraiths, knights. Late D (13-15): liches, dragons, greater demons, titans, draconians. Scaling is gradual — room density and monster toughness increase per floor.

### Signature Features
Standard stone dungeon: floor/wall/doors/stairs. No special terrain like water or lava in main dungeon (those appear in branches). Occasional doors block corridors. Altars exist but are not common on main D floors (Temple branch is the dedicated altar zone).

### Vault Library
DCSS maintains thousands of vaults for D, classified by theme: generic rooms, minibosses, treasuries, statue halls, monster set-pieces. Tags include `dungeon_entry`, `dungeon`, `decor`, `monster`. Entry vaults appear on D:1-3 to ease player entry. Branch-linking vaults on D:8-14 transition to Lair, Orc, Vaults, etc.

### Run-Loop Role for Botter
**Floors 1-5 of a 10-floor run.** Dungeon is the baseline difficulty and visual anchor. As the player's bot upgrades, later D floors become easier and serve mainly as loot-grinding zones. Include D:1-3 (intro), skip to D:6-9 (mid), then D:12-15 (late) on optimal runs. Keep stone tile variety moderate so the visual ramp-up to branches feels earned.

### Asset Status
**AVAILABLE**: dungeon floor and wall prefixes (`stone_*`, `floor_stone_*`, `wall_stone_*`) are fully populated in `/project/assets/tiles/`. ~50+ variants across both categories.

---

## Lair of Beasts (Lair)

**Canonical name**: "the Lair of Beasts" | **Abbreviation**: "Lair" | **Depth**: 5 floors | **Entry**: off D:8-11 | **Sub-branches**: Snake, Spider, Swamp, Shoals, Slime

### Depth & Structure
A hub branch — five floors that connect horizontally to four major side branches (Snake Pit, Spider Nest, Swamp, Shoals) and one vertical connection (Slime). Lair floors 1-3 can access the four "rune" branches (exit runes in those branches can loop back to Lair). Slime branches off Lair floor 4-5.

### Visual Identity
Natural caverns with animal/vegetable themes. Floors are earthy brown with moss and grass (`floor/lair_*, floor/grass_*`). Walls are often *not* stone — they frequently become trees, vines, or dirt (`wall/lair_*, tree_*, mangrove_*`), creating a jungle/forest feel. Ambient lighting is slightly green-tinted and somewhat dim (natural canopy gloom). Water features appear frequently.

### Layout Style
DCSS uses `dgn-shoals.cc` / `dgn-swamp.cc` for Shoals/Swamp sub-branches, but Lair proper uses a mix: procedural `basic_level` (carves open caves with room nodes), some heavy vault-driven floors, and occasional `delve` caves (organic winding tunnels via cellular automaton). This variety makes each Lair floor feel distinct.

### Signature Monsters
Early Lair: jackals, adders, giant frogs, bullfrogs, water moccasins, cane toads, black bears. Mid Lair: wargs, komodo dragons, basilisks, hydras. Late Lair: elephants, death yaks, dire elephants, polar bears, anacondas. Distinctly animal-focused; few undead or demons. Many enemies have special movement (faster, ranged).

### Signature Features
Shallow water (`shallow_water` tiles, passable but slow movement). Occasional deep water lakes. Trees/vegetation block movement but don't generate items/monsters (they're terrain, not walls). Some vaults feature planted groves or animal lairs (bears in dens, snakes in nests). The rune branches each have a unique rune (swamp rune, snake rune, spider rune, shoals rune) — Lair itself has no rune, but reaching a rune branch and returning is part of the meta-progression.

### Vault Library
Lair vaults are tagged `lair_*` with sub-tags for biome (`lair_swamp_decor`, etc.). The library includes: animal warband set-pieces, water features (fountains, pools), tree clusters, small treasure caches, and transition vaults to branch exits. Most are "float" or minivault oriented, fitting into procedurally-carved caves.

### Run-Loop Role for Botter
**Floors 3-5 (if chaining Lair into the main run) or a dedicated 5-floor Lair-only run for loot grinding.** Lair breaks up the stone monotony with colour, water, and animal encounters. Include Lair if the run is meant to feel "natural" or "green." Skip if the run is on a tight schedule. The branch-hopping mechanic (player clears Shoals, returns to Lair, then descends Vaults) can be linearized for Botter as a simple sequential descent: `D → Lair → Shoals OR Swamp → back to main spine`.

### Asset Status
**MOSTLY AVAILABLE**: `lair` tile prefixes, tree sprites, grass floors are in the project. **GAPS**: some mangrove (`mangrove_*`) and specific water shoreline transitions (`deep_water_flow_*`) may need additional copies from the DCSS tileset. Water physics (slow movement, shallow vs. deep visual distinction) not yet implemented in Botter.

---

## Orcish Mines (Orc)

**Canonical name**: "the Orcish Mines" | **Abbreviation**: "Orc" | **Depth**: 2 floors | **Entry**: off D:9-12 | **Sub-branch**: Elven Halls (off Orc:1-2)

### Depth & Structure
A short industrial branch: two floors of mines. Entry is via a portal stair (`enter_orc`) found on D:9-12. Exit is a portal stair back to the Dungeon. The Elven Halls branch off Orc itself, creating a tree: `D → Orc → Elf`.

### Visual Identity
Mined rock with metal reinforcements. Floors are dark brown stone, often with rust stains and ore veins (`floor/orc_*`, occasional `floor/rust_*`). Walls are dark stone with striations, sometimes embedded with metal (`wall/orc_*`, `wall/metal_*`). Ambient lighting is dim and slightly brown-tinted (firelight from forges and torches). Metal pillars and iron grates punctuate the space.

### Layout Style
Heavy vault-driven — many `encompass` vaults per floor, creating distinct "war rooms" or "forge halls." When not in encompass mode, uses `basic_level` with more clustered room placement (mines are packed, not sprawling). Doors are frequent and often include iron grates (`iron_grate` features).

### Signature Monsters
Orc archers, orc warriors, orc knights, crossbow-wielding variants, ogres, two-headed ogres, trolls. A few shamans and soldiers. Orcs are the "humanoid" enemy group — organized, armoured, and often in packs. No undead or demons; purely physical combat challenges.

### Signature Features
Iron grates (impassable unless destroyed). Metal pillars (impassable, provide cover). Occasional pools. Many enclosed chambers (vault-driven design). Traps are less common than in Crypt but present. Metal doors and reinforced architecture reinforce the "mined fortress" aesthetic.

### Vault Library
Orc vaults include warrior barracks (clustered orc warriors), ogre lairs (2-4 ogres in a chamber), weapon caches (guarded by tough orcs), and transition vaults to Elven Halls. Tags: `orc_entry`, `orc_decor`, `orc_mons`, `orc_treasure`.

### Run-Loop Role for Botter
**Short interstitial branch.** Orc can appear floors 4-7 in a run, offering mid-difficulty combat and industrial aesthetic. Its brevity (2 floors) makes it ideal for pacing — explore Orc, then jump back to Dungeon or forward to Vaults. If Elven Halls is not implemented, Orc is purely linear.

### Asset Status
**AVAILABLE**: `orc` prefixes and `metal` wall tiles are in the project. Metal pillars and grates are available as sprite assets.

---

## Elven Halls (Elf)

**Canonical name**: "the Elven Halls" | **Abbreviation**: "Elf" | **Depth**: 3 floors | **Entry**: off Orc:1-2 | **Sub-branches**: Swamp, Snake, Shoals, Spider (can branch from here under certain game modes, creating a routing tree)

### Depth & Structure
A 3-floor branch accessible from Orc. Marked with the `dangerous_end` flag, indicating late-game difficulty and loot. Exits back to Orc or onward to other branches (in full DCSS, Elf can connect to Swamp, Snake, Shoals, Spider).

### Visual Identity
High-fantasy elven architecture. Floors are white or light-grey stone (`floor/elf_*`, `floor/hall_white_*`), often with a magical shimmer. Walls are distinctive elven brick (`wall_brick_elven_*`, `wall_hall_white_*`), possibly with crystal or glass accents (`wall_crystal_*`). Ambient lighting is bright and cool-toned (magical, not firelight). The feeling is clean, orderly, and magical.

### Layout Style
Vault-heavy. Elven Halls frequently uses `encompass` vaults or large preset layouts. When procedural, uses `basic_level` with more open rooms and fewer tortuous corridors (elves prefer straight, orderly architecture). Occasional water features (shallow pools, fountains).

### Signature Monsters
Deep elf warriors, deep elf knights, deep elf pyromancers, deep elf zephyrmancers (mages), elven archers. A few centaur warriors. Elf enemies are mid-to-high HP, high accuracy, often mage-focused. Fewer melee specialists compared to humanoid armies (orcs).

### Signature Features
Glowing arcane barriers (might exist as visual tiles). Statues of elven heroes. Fountains (dispense magical effects). Occasionally magically-sealed chambers. No industrial elements; no rot, rust, or decay.

### Vault Library
Elf vaults include mage circles (grouped mages), knight halls (armoured warriors), treasure vaults, and challenge arenas. Tags: `elf_entry`, `elf_decor`, `elf_mons`.

### Run-Loop Role for Botter
**Advanced branch, floors 5-8 range.** Elf is optional and challenging. For Botter, could be offered as an "elite" side branch with higher loot, or skipped in speedrun routes. Its late-game status and magical aesthetic offer visual contrast to stone dungeons.

### Asset Status
**AVAILABLE**: Elven brick and white stone tiles are in the project. Crystal walls may need supplementary copying. Elf-specific monsters (deep elf pyromancer, zephyrmancer) sprites needed from DCSS tileset.

---

## Snake Pit (Snake)

**Canonical name**: "the Snake Pit" | **Abbreviation**: "Snake" | **Depth**: 4 floors | **Entry**: off Lair:1-3 | **Rune**: Serpentine rune

### Depth & Structure
A 4-floor rune branch off Lair. Short depth; designed as a side-exploration goal. Exit is back to Lair or access to the Lair hub.

### Visual Identity
Underground pit with reptilian design. Floors are yellow-tinted stone (`floor/snake_*`, `floor/yellow_*`). Walls are often *not* stone — they're replaced with scaled/reptile textures, or become deep yellowy terrain (`wall_snake_*`, `wall_yellow_*`). Ambient lighting is dim and slightly yellow (bioluminescent glow or torch reflection). Water is present, often lava-adjacent (salamanders live on lava).

### Layout Style
Mix of `basic_level` and vaults. Shoals and Swamp use specialized generators; Snake uses more standard procedural layout with heavily-placed vaults. The branch layout often includes pit chambers (enclosed arenas) and water channels.

### Signature Monsters
Water moccasins, black mambas, anacondas, nagas, salamanders, lava snakes, giant frogs. Boss: Lamia (if encountered). Distinctly serpentine; many enemies are slow or use special movement (teleport, coil, constrict).

### Signature Features
Shallow water and deep water (movement-slowing). Lava tiles (`lava_*`) in some vaults (for salamanders). Pits (impassable terrain drops). Occasional lava channels. Many narrow, winding corridors (fitting for a snake pit).

### Vault Library
Snake vaults include naga warrens, salamander pits, lava pools, coiled staircases (unique visual), and treasure hoards. Tags: `snake_entry`, `snake_decor`, `snake_mons`.

### Run-Loop Role for Botter
**Rune branch, floors 3-5 (if running Lair).** Snake offers loot and a visual/aesthetic change (reptilian, pit-like). Include in runs seeking maximum loot or specific rune mechanics. Skip in speedrun routes.

### Asset Status
**PARTIAL**: Snake floor/wall prefixes are in the project. **GAPS**: specific lava tiles and salamander sprites may need copying.

---

## Spider Nest (Spider)

**Canonical name**: "the Spider Nest" | **Abbreviation**: "Spider" | **Depth**: 4 floors | **Entry**: off Lair:1-3 | **Rune**: Arachnid rune

### Depth & Structure
A 4-floor rune branch off Lair. Designed as an exploration goal, parallel to Snake/Swamp/Shoals.

### Visual Identity
Underground cavern with web-infested stone. Floors are brown or grey with webbing overlays (`floor/spider_*`, occasional `floor/web_*`). Walls are stone surrounded by thick webs (`wall/spider_*`, web textures overlaid). Ambient lighting is dim and cool-tinted (no light source except webs glowing faintly). Webbing is everywhere — visual clutter, but thematic.

### Layout Style
Vault-heavy, with many float/minivault designs. Procedural sections use `basic_level` with more open chambers (spiders web large spaces). Webs themselves don't block movement (cosmetic), but spider-placed traps do.

### Signature Monsters
Redbacks, jumping spiders, wolf spiders, orb spiders, giant spiders. Boss: Arachne (if present). Spiders are fast, relatively weak individually, but swarm. Many spit venom or have special attacks.

### Signature Features
Webbing (cosmetic terrain, doesn't block movement). Occasional pit traps. Small enclosed chambers connected by web-covered corridors. No water or lava. The biome is purely "arachnid warren."

### Vault Library
Spider vaults include egg chambers, spider warrens, web-trapped treasure, and boss arenas. Tags: `spider_entry`, `spider_decor`, `spider_mons`. Unique feature: web-themed trap vaults with visual webbing as the primary decor.

### Run-Loop Role for Botter
**Rune branch, floors 3-5 (if running Lair).** Spider is the "swarm" branch — expect many small enemies over fewer big ones. Visual variety from Lair (organic vs. stone), but less striking than Shoals or Crypt. Include for variety or specific monster-grinding goals.

### Asset Status
**PARTIAL**: Spider floor/wall prefixes available. **GAPS**: redback and jumping spider sprites need checking; web textures may need supplementary copying.

---

## Swamp (Swamp)

**Canonical name**: "the Swamp" | **Abbreviation**: "Swamp" | **Depth**: 4 floors | **Entry**: off Lair:1-3 | **Rune**: Swamp rune

### Depth & Structure
A 4-floor rune branch off Lair. One of the most visually distinct branches. Exits back to Lair.

### Visual Identity
Murky wetland. Floors are deep brown, waterlogged, often with moss and rot (`floor/swamp_*`, `floor_mud_*`, `floor_grass_muddy_*`). Walls are replaced with water, mangroves, or soft mud (`wall_swamp_*`, mangrove sprites, `wall_mud_*`). Ambient lighting is dim and greenish (swamp glow, rotting vegetation). Many tiles have algae or slime overlays. The branch feels claustrophobic and decaying.

### Layout Style
DCSS uses a dedicated `dgn-swamp.cc` generator. Creates winding water channels with landmass "islands." Vaults are placed on islands; corridors hug water features. Results in organic, flowing layouts quite different from rectangular rooms. High water coverage (~40-50% of floor is water tiles).

### Signature Monsters
Swamp worms, bog bodies, electric eels, giant frogs, goliath frogs, alligators, crocodiles, swamp dragons. Distinct aquatic/amphibian theme. Few humanoids; mostly creatures adapted to wetlands. Many are slow or water-dwelling.

### Signature Features
Deep water (impassable without special abilities or swimming). Shallow water (passable, slower movement). Mangrove trees (impassable terrain, don't generate items/monsters). Occasional leeches or water hazards. Mud tiles (cosmetic, thematic). The layout is water-centric — navigation is about island-hopping, not corridor traversal.

### Vault Library
Swamp vaults include creature lairs (giant frogs, swamp worms), water features (deep pools, swamp slicks), treasure caches on islands, and interconnected water passages. Tags: `swamp_entry`, `swamp_decor`, `swamp_mons`, `swamp_water`. Vaults are often "float" style, placed on islands detected by the generator.

### Run-Loop Role for Botter
**Rune branch, floors 3-5 (if running Lair).** Swamp is the most *visually different* branch from standard Dungeon. Use Swamp when you want to showcase biome variety. Its water-heavy layout is mechanically distinct (navigation challenges). Include for aesthetic impact; skip in efficiency runs.

### Asset Status
**PARTIAL**: Swamp floor/wall prefixes and mangrove sprites are in the project. **GAPS**: full water tileset (shore transitions, deep water variants) and swamp-specific creatures need verification.

---

## Shoals (Shoals)

**Canonical name**: "the Shoals" | **Abbreviation**: "Shoals" | **Depth**: 4 floors | **Entry**: off Lair:1-3 | **Rune**: Tide rune

### Depth & Structure
A 4-floor rune branch off Lair. Designed as the "water" counterpart to swamp (islands, not waterlogged). Unique mechanic: tidal system that shifts water levels per-turn (in full DCSS, this is a complex game mechanic; for Botter, can be simplified or aesthetic-only).

### Visual Identity
Tropical island/beach. Floors are sand or light stone (`floor/sand_*`, `floor_shoals_*`), bright and open. Walls are sparse; the "wall" is often deep water (`deep_water_*`) or sandy mounds (`wall_sand_*`). Ambient lighting is bright and warm (beach sunlight). The biome is open, expansive, and visually very different from underground branches.

### Layout Style
DCSS uses `dgn-shoals.cc` generator. Creates open water areas with sandy islands and rocks. Vaults are placed on islands or within water. The layout is very open — lots of visible space, fewer tight corridors. Often the largest single visible area of any DCSS branch per-floor.

### Signature Monsters
Merfolk, merfolk warriors, merfolk siren, sea snakes, eels, sirens, kraits, giant crabs. Distinctly aquatic humanoids and creatures. Few if any terrestrial animals.

### Signature Features
Deep water (impassable to land creatures, but some enemies swim). Shallow water (passable, cosmetic slow). Sandy terrain (cosmetic, no movement penalty). Rocks (impassable obstacles). No trees or vegetation. Boss encounter: Ilsuiw (a merfolk siren, if present) or Kraken (in some vault configurations).

### Vault Library
Shoals vaults include merfolk councils, creature lairs, treasure islands, whirlpools, sunken ship wreckage (thematic), and boss arenas. Tags: `shoals_entry`, `shoals_decor`, `shoals_mons`. Heavy use of water terrain KFEAT markers to place water features via vault glyphs.

### Run-Loop Role for Botter
**Rune branch, floors 3-5 (if running Lair).** Shoals is the most visually striking branch for tropical aesthetics. Use when visual variety is paramount. The open layout offers different navigation challenges (few corridors to block, lots of open water to navigate). Include for showpiece runs; the merfolk + island + water combination is instantly recognizable.

### Asset Status
**PARTIAL**: Sand and shoals tile prefixes available. **GAPS**: full merfolk sprite roster, specific water tiles (shore, tide markers, whirlpool effects).

---

## Slime Pits (Slime)

**Canonical name**: "the Pits of Slime" | **Abbreviation**: "Slime" | **Depth**: 5 floors | **Entry**: off Lair:4-5

### Depth & Structure
A 5-floor branch off the Lair hub, specifically floors 4-5 (deeper Lair). Slime is a unique "rune" branch with organic, non-rectilinear generation. One of the most mechanically unusual branches.

### Visual Identity
Gelatinous pit. Floors are translucent and slimy (`floor/slime_*`), often with a viscous appearance. Walls are also slime (`wall_slime_*`, or transparent slimy_transparent_stone). Ambient lighting is dim and greenish-yellow (bioluminescence from slime). The entire branch is organic and off-putting — no stone, no structure, just slime.

### Layout Style
DCSS uses a custom slime generator (not standard `basic_level`). Creates irregular, blob-like chambers with no clear grid structure. Walls and corridors are soft, winding, and interconnected. The result looks like the inside of a digestive system. Vaults are often "encompass" style, reshaping entire levels as slime cathedrals or breeding pits.

### Signature Monsters
Acid blobs, great orbs of eyes, jelly creatures, royal jellyfish. Few humanoids; mostly oozes and aberrations. Boss: Royal Jelly (a unique boss entity, not a regular enemy). The branch is entirely about battling and navigating slime-based entities.

### Signature Features
Slimy walls (cosmetic but thematic — walls are slime, not stone). Acid pools (damaging terrain). Jelly creatures (enemies are made of slime, feel organic). The entire floor is slime-centric; there are no stone elements. The Rune of Slime is placed within the branch. Special mechanic (in full DCSS): the Royal Jelly is unkillable and regenerates; defeating it requires a specific strategy (may not apply to Botter).

### Vault Library
Slime vaults include jelly breeding pits, acid pools, treasure repositories, and boss chambers. Tags: `slime_entry`, `slime_decor`. The vault library is smaller than other branches — most vaults are theme-consistent (slime only) so fewer variants.

### Run-Loop Role for Botter
**Late-game rune branch, floors 6-8 (if chained off deep Lair).** Slime is the "weird" branch — its organic generation and absence of conventional structure make it memorable. Use Slime when you want to showcase algorithmic generation diversity. The hazard-heavy layout (acid pools) adds mechanic depth. Include for late-game variety; skip in speed runs.

### Asset Status
**PARTIAL**: Slime tile prefixes and transparent slime walls are in the project. **GAPS**: acid pool tiles and Royal Jelly sprite may need copying or creation.

---

## Vaults (Vaults)

**Canonical name**: "the Vaults" | **Abbreviation**: "Vaults" | **Depth**: 5 floors | **Entry**: off D:13-14 | **Sub-branch**: Crypt (off Vaults:1-2)

### Depth & Structure
A 5-floor branch accessed from the main Dungeon late-game (D:13-14). The Vaults branch leads to the Crypt, which leads to the Tomb. Forms a linear sub-chain: `D → Vaults → Crypt → Tomb`. The Vaults themselves are a major loot destination and threat escalation point.

### Visual Identity
Fortified treasure vault. Floors are stone (`floor/vault_*` or `floor_stone_*`), often with a magical shimmer (precious metals embedded). Walls are reinforced stone or crystal (`wall_vault_*`, `wall_crystal_*`), sometimes with arcane barriers (`wall_zot_*` for decoration). Ambient lighting is warm and slightly magical (treasure glowing, magical wards shimmering). The biome is high-security and opulent.

### Layout Style
Vault-driven — many `encompass` vaults per floor, creating set-piece treasure rooms, guard chambers, and challenge arenas. When procedural, uses `basic_level` with more enclosed spaces and fewer open areas (treasures are locked away, not sprawling). Doors and grates are common.

### Signature Monsters
Liches, arcanists, deep elf pyromancers, death knights, ghosts, humanoid casters and warriors. Vaults enemies are often mages or undead — "guards" and "protectors" of treasures. Many have ranged attacks or spellcasting.

### Signature Features
Treasure piles (visual emphasis on loot). Statues (impassable, sometimes animated or cursed). Crystal barriers (magical obstacles). Iron doors and grates (security). Occasional altars or fountain features. No water, lava, or natural hazards; purely constructed architecture. The Rune of Vaults is housed in the branch.

### Vault Library
Vaults vaults are tagged `vaults_*`. They include treasure chambers (guarded by monsters and traps), statue halls, crystal galleries, treasure chests, and boss arenas. The library is enormous — Vaults is a major end-game branch with varied challenges. Sub-tags: `vaults_entry`, `vaults_decor`, `vaults_treasure`, `vaults_monster`.

### Run-Loop Role for Botter
**Mid-to-late game tier, floors 6-9.** Vaults is the "loot destination" branch. Its linear progression (Vaults → Crypt → Tomb) forms a natural story arc: treasure → graves → tomb (escalation of stakes). Use Vaults when the run should feel "successful" (finding treasure) and when transitioning toward endgame. The branch is essential for loot-focused strategies.

### Asset Status
**AVAILABLE**: Vault tile prefixes and crystal walls are in the project. Statues and treasure pile sprites are available. The branch is well-covered.

---

## Crypt (Crypt)

**Canonical name**: "the Crypt" | **Abbreviation**: "Crypt" | **Depth**: 3 floors | **Entry**: off Vaults:1-3 | **Sub-branch**: Tomb (off Crypt:1-3)

### Depth & Structure
A 3-floor branch off Vaults. Serves as a transition zone between treasure (Vaults) and the deepest challenge (Tomb). Exits back to Vaults or forward to Tomb.

### Visual Identity
Underground graveyard. Floors are grey stone with bones and sarcophagi (`floor/crypt_*`, bone tiles). Walls are weathered stone, sometimes with cracks or moss (`wall_crypt_*`, `wall_tomb_*` for weathering). Ambient lighting is dim and cool-toned (moonlight filtering through cracks, if any light exists). The biome is eerie and undead-focused; stone is crumbling, not pristine.

### Layout Style
Mix of `basic_level` (procedural carving) and vaults. Vaults create sarcophagi chambers, crypt vaults with sealed sarcophagi, and bone piles. Many chambers are small and enclosed (tombs are cramped). Doors are common; some are sealed (trap doors that open when enemies are disturbed).

### Signature Monsters
Skeletons, zombies, ghosts, wraiths, ancient champions, mummies (early versions), draugrs, liches. Distinctly undead-focused — no living humanoids or animals. Many enemies are armoured or have special undead abilities.

### Signature Features
Sarcophagi (impassable, sometimes trigger spawning undead when disturbed). Bone piles (cosmetic, thematic). Iron grates (security, can be unlocked). Altar to undead gods (if present). Traps (more common than Vaults — crypt traps include alarm traps, dart traps, bolt traps). The biome is trap-heavy and threat-escalated compared to Vaults.

### Vault Library
Crypt vaults include sarcophagi chambers, bone crypts, treasure vaults (for magical items), undead set-pieces, and transition vaults to Tomb. Tags: `crypt_entry`, `crypt_decor`, `crypt_mon`. Some vaults feature special Lua scripting to animate statues or drop grates when disturbed.

### Run-Loop Role for Botter
**Late-game tier, floors 7-8.** Crypt escalates threat and prepares for the Tomb finale. Its undead enemies and trap density make it a skill check. Use Crypt to establish late-game difficulty spikes. The visual transition from shiny Vaults to dour Crypt reinforces narrative progression.

### Asset Status
**AVAILABLE**: Crypt floor and wall prefixes are fully in the project. Bone sprites and sarcophagus tiles are available. Branch is well-covered.

---

## Tomb (Tomb)

**Canonical name**: "the Tomb of the Ancients" | **Abbreviation**: "Tomb" | **Depth**: 3 floors | **Entry**: off Crypt:1-3 | **Rune**: Tomb rune

### Depth & Structure
A 3-floor branch off Crypt, accessible only after progressing through Crypt. Marked with `islanded` flag (isolated, hard to escape), `dangerous_end` (late-game final challenge), and `no_shafts` (no shortcuts). The Tomb is a dead-end branch — once entered, the only exit is victory, death, or finding a portal out.

### Visual Identity
Ancient burial chamber. Floors are sandy and weathered (`floor/tomb_*`, `floor_sand_*`), with dust and decay visible. Walls are sandstone or crumbled stone (`wall_tomb_*`, `wall_sand_*`). Ambient lighting is very dim (torchlight is muted by dust and age). The biome is cramped, claustrophobic, and oppressive.

### Layout Style
Heavy on `encompass` vaults — Tomb floors are often entirely vault-driven with minimal procedural generation. When procedural, uses tight corridors and small chambers (fitting for a mausoleum). Rooms are interconnected in mazes, not open grids.

### Signature Monsters
Guardian mummies, royal mummies, ancient champions, ushabtis (guardian statues animated as enemies), mummy priests, soul eaters, liches, revenant soulmongers. The highest concentration of undead threats in the game. Many enemies have high HP and special undead abilities.

### Signature Features
Sarcophagi (numerous, often animated). Traps (very frequent, including alarm, vault, and specialized tomb traps). Dust and decay (visual elements, no mechanical impact). The Rune of Tomb is locked within the deepest chamber, requiring the player to navigate the entire branch to claim it. Sealed doors (require player to proceed linearly, can't backtrack).

### Vault Library
Tomb vaults are specialized: mummy chambers, guardian halls, sarcophagi crypts, and rune vaults. Tags: `tomb_entry`, `tomb_decor`. Many vaults feature Lua scripting for complex trap sequences and guardian spawning. The vault library is small because Tomb is short and designed as a singular epic chamber, not a varied exploration.

### Run-Loop Role for Botter
**Endgame capstone, floor 9-10 (if Tomb is the final floor).** Tomb is the "final dungeon" branch — the ultimate late-game challenge. Use Tomb as the climax of a run: navigate the gauntlet, claim the Tomb Rune, prove mastery. Tomb should only appear if the run is structured as a long campaign (8-10+ floors) with dedicated endgame content. For short (5-floor) runs, skip Tomb or replace it with a less punishing boss arena.

### Asset Status
**AVAILABLE**: Tomb floor and wall prefixes are in the project. Sarcophagus and guardian statues are available. Branch is well-covered.

---

## Depths (Depths)

**Canonical name**: "the Depths" | **Abbreviation**: "Depths" | **Depth**: 4 floors | **Entry**: off D:15 | **Sub-branch**: Zot (off Depths:4)

### Depth & Structure
A 4-floor branch accessible only after clearing the main Dungeon (D:15). The Depths serve as the penultimate tier before Zot. Single point of entry and exit (linear progression). Depths:4 (the bottom floor) contains the entry to Zot.

### Visual Identity
Underground chasm. Floors are dark grey stone with a mineral shine (`floor/depthstone_*`, crystalline elements). Walls are carved stone with a vaguely magical tint (`wall_depths_*`, sometimes `wall_crystal_*`). Ambient lighting is dim but has an eerie magical shimmer (crystals glowing faintly). The biome is both alien and grand — the "deep places of the world."

### Layout Style
Vault-driven for major encounters. Procedural sections use `basic_level` but with higher-complexity rooms (more pillars, more varied room shapes). Many vaults are large `encompass` designs creating epic chambers. The layout is designed to feel "grand" and threatening.

### Signature Monsters
Stone giants, frost giants, liches, ancient liches, dragons, hydras, titans, deep-dwelling creatures. Depths enemies are the highest-tier regular dungeon monsters — bosses and mini-bosses. Few "trash" enemies; most encounters are significant.

### Signature Features
Stone pillars (impassable, provide cover). Crystal formations (cosmetic, sometimes magical). Occasionally lava or water features. Traps are rare (focus is on direct combat encounters, not attrition). The biome is more about spectacle and challenge than environment hazards.

### Vault Library
Depths vaults include giant chambers (housing stone giants, frost giants), dragon lairs, lich temples, and transition vaults to Zot. Tags: `depths_entry`, `depths_mon`. Many vaults are named and unique — Depths is less about vault variety and more about iconic set pieces.

### Run-Loop Role for Botter
**Penultimate tier, floor 9 (before Zot on floor 10).** Depths is the "scaling" branch — each floor significantly harder than late-game Dungeon. Use Depths if the run has a boss progression arc (each floor is a mini-boss gauntlet). Depths feels like "approaching the endgame." Essential for long (9-10 floor) runs.

### Asset Status
**AVAILABLE**: Depths tile prefixes and crystal walls are in the project. Stone giant and dragon sprites exist. Branch is well-covered.

---

## Zot (Zot)

**Canonical name**: "the Realm of Zot" | **Abbreviation**: "Zot" | **Depth**: 5 floors | **Entry**: off Depths:4 | **Rune**: Orb of Zot (multiple runes guard this)

### Depth & Structure
A 5-floor branch accessible only after clearing Depths. Zot is the true endgame — the final destination. The Orb of Zot is housed on Zot:5, the deepest floor. Reaching Zot:5 and claiming the Orb is the game's victory condition.

### Visual Identity
Otherworldly realm. Floors are black or dark purple with crystalline patterns (`floor/zot_*`, `floor/black_*`). Walls are magical glass or dark crystal (`wall_zot_*`, `wall_crystal_*`, sometimes `wall_transparent_*`). Ambient lighting varies per floor but is often bright and saturated (per-floor colour). The biome is alien, magical, and grand. Each Zot floor has a unique colour scheme (red for Zot:1, blue for Zot:2, yellow for Zot:3, green for Zot:4, magenta for Zot:5).

### Layout Style
Heavy on `encompass` vaults. Many Zot floors are single large vaults, not procedurally generated. When procedural sections exist, they use complex room arrangements with pillars, glass barriers, and multi-room chambers. The layout is designed to be visually stunning and mechanically challenging.

### Signature Monsters
Dragons (many types: acid, fire, ice, storm, shadow, golden, iron, quicksilver, bone, lindwurms). Draconians (many types: warrior, mage, knight). Other unique entities: orbs of fire, orbs of electricity. Boss: the Orb of Zot (not a monster, a feature/objective). Zot enemies are the absolute highest-tier encounters.

### Signature Features
Glass barriers (magical obstacles, sometimes breakable). Coloured crystal walls (per-floor). The Orb of Zot (the objective, placed on Zot:5). No hazards like water or lava (focus is pure combat challenge). Many decorative crystal formations. The branch is visually opulent and focuses on spectacle.

### Vault Library
Zot vaults are named and epic: dragon chambers, arena arenas, crystal cathedrals, and the final Orb chamber. Tags: `zot_entry`, `zot_decor`, `zot_mon`. Few generic vaults; most are unique set pieces. The library exists but is smaller than mid-game branches because Zot is less about exploration and more about overcoming a series of challenges.

### Run-Loop Role for Botter
**Absolute endgame tier, floor 10 (final floor).** Zot is the goal. For Botter's 10-floor run structure, Zot:5 (the Orb chamber) should be the floor-10 boss arena. The run culminates here: defeat the Orb's guardians, claim the Orb, victory. Use Zot as the showpiece finale — make it visually stunning and mechanically climactic. This is where the player's bot proves its power.

### Asset Status
**AVAILABLE**: Zot floor and wall prefixes are in the project. Dragon and draconian sprites exist. The branch is well-covered.

---

# Hell Branches

Hell is a meta-branch: the Vestibule of Hell is a single-floor hub that connects to four elemental hells, each a single floor. Reaching Hell requires late-game progression; Hell branches are endgame-only.

## Hell (Vestibule)

**Canonical name**: "the Vestibule of Hell" | **Abbreviation**: "Hell" | **Depth**: 1 floor | **Entry**: off Depths:4 (alternative to Zot) or end-of-game | **Sub-branches**: Dis, Gehenna, Cocytus, Tartarus

### Depth & Structure
A single-floor hub connecting to the four Hells. The Vestibule itself is a place of transition — no exploration, just a crossroads. The four Hell branches branch off from the Vestibule.

### Visual Identity
Hellish gateway. Floors are red stone or dark lava (`floor/hell_*`, `floor_lava_*`). Walls are dark metal or hellstone (`wall_hell_*`, `wall_metal_*`). Ambient lighting is red-tinted and ominous (lava glow, brimstone fires). The biome is threatening and visually evil.

### Layout Style
Usually a small vault-driven area serving as a transition. Not a deep exploration zone — the Vestibule is a checkpoint.

### Signature Monsters
Hell knight, balrug, pit fiend (boss-tier demons). Few common trash enemies. Hell enemies are among the highest-tier threats.

### Signature Features
Lava features (damage, visual emphasis). Demonic architecture (thematic). The Vestibule entry itself serves as a gating mechanism — the player must choose which Hell to enter next.

### Vault Library
Vestibule vaults are minimal — mostly a transition chamber. Sub-vaults can branch to each Hell.

### Run-Loop Role for Botter
**Endgame branching point, floor 8-9 (if Hell is the chosen endgame tier).** The Vestibule represents "reaching Hell" — a late-game power spike. For Botter, could be structured as a "choose-your-path" node: pick a Hell to explore for loot/runes, then exit. Or skip entirely if the run doesn't include Hell content.

### Asset Status
**AVAILABLE**: Hell floor and wall prefixes are in the project. Demon sprites need checking.

---

## Dis (Iron City of Dis)

**Canonical name**: "the Iron City of Dis" | **Abbreviation**: "Dis" | **Depth**: 7 floors | **Entry**: off Hell (Vestibule) | **Rune**: Iron rune

### Depth & Structure
One of four Hell branches. A 7-floor vertical descent through the Iron City. Each floor is typically a single vault or series of connected vaults. Dis is the "metal/industrial" Hell.

### Visual Identity
Rusted iron fortress. Floors are metal or rust-stained stone (`floor/dis_*`, `floor_metal_*`, `floor_rust_*`). Walls are iron or corroded metal (`wall_dis_*`, `wall_metal_*`, `wall_rust_*`). Ambient lighting is cyan or steel-blue (magical metal corrosion). The biome is industrial, oppressive, and decaying.

### Layout Style
Entirely vault-driven. Each Dis floor is usually a single `encompass` vault (or a few connected vaults). No procedural generation — Dis is a linear gauntlet of hand-crafted chambers.

### Signature Monsters
Iron golems, hell sentinels, quicksilver elementals, iron giants, hell knights. Metal-themed enemies with high defences.

### Signature Features
Iron bars and grates (security, sometimes animated or breakable). Metal pillars (impassable). Lava pits (occasional, damage hazard). The Iron Rune of Zot is held in the deepest chamber. Many traps and mechanisms.

### Vault Library
Dis vaults are epic set pieces: iron halls, golem chambers, treasure vaults, and rune chambers. No generic vaults — all are unique. Tags: `dis_castle`, `dis_divider`, `dis_decor`.

### Run-Loop Role for Botter
**Optional Hell tier, floors 8-9 (if Hell is explored).** Dis is the "metal" Hell — visually striking and mechanically different (high-DEF enemies, few ranged attackers). Use Dis if showcasing Hell content; skip if focusing on Zot/Depths.

### Asset Status
**AVAILABLE**: Dis prefixes and metal walls are in the project. Iron golem and elemental sprites exist.

---

## Gehenna (Gehenna)

**Canonical name**: "Gehenna" | **Abbreviation**: "Geh" | **Depth**: 7 floors | **Entry**: off Hell (Vestibule) | **Rune**: Fiery rune

### Depth & Structure
One of four Hell branches. A 7-floor descent through a lava-filled hellscape. Each floor is typically a single vault. Gehenna is the "fire" Hell.

### Visual Identity
Volcanic inferno. Floors are lava or dark red stone (`floor_lava_*`, `floor_geh_*`, `floor_red_*`). Walls are lava or dark-red volcanic rock (`wall_geh_*`, `wall_lava_*`, `wall_red_*`). Ambient lighting is bright red-orange (lava glow). The biome is oppressively hot; visual impression is "inside a volcano."

### Layout Style
Entirely vault-driven. Each Gehenna floor is a single or dual vault, often featuring lava lakes and lava channels. No procedural sections.

### Signature Monsters
Sun demons, efreets, balrugs, undying armouries, lava creatures. Fire-themed enemies with fire attacks. High-threat, slow-moving creatures.

### Signature Features
Lava tiles (impassable, damage on contact). Lava lakes (hazard). Lava flows (cosmetic but thematic). The Fiery Rune of Zot is held within. Traps involving lava (lava traps, heat damage).

### Vault Library
Gehenna vaults are lava-centric: lava chambers, demon halls, fire-maze, rune vaults. All unique, no generics. Tags: `geh_lava_maze`, `geh_decor`.

### Run-Loop Role for Botter
**Optional Hell tier, floors 8-9 (if Hell is explored).** Gehenna is the "fire" Hell — intense, visually bright, and mechanically hazard-heavy. Use Gehenna for dramatic effect (lava everywhere, enemies on fire). Skip if prioritizing Zot.

### Asset Status
**PARTIAL**: Lava tiles are in the project. Gehenna-specific creatures may need copying. Lava hazard mechanics not yet implemented.

---

## Cocytus (Cocytus)

**Canonical name**: "Cocytus" | **Abbreviation**: "Coc" | **Depth**: 7 floors | **Entry**: off Hell (Vestibule) | **Rune**: Icy rune

### Depth & Structure
One of four Hell branches. A 7-floor descent through a frozen hellscape. Cocytus is the "ice" Hell.

### Visual Identity
Frozen wasteland. Floors are ice or light-blue stone (`floor_ice_*`, `floor_cocytus_*`, `floor_lightblue_*`). Walls are ice or frost-covered rock (`wall_ice_*`, `wall_cocytus_*`, `wall_white_*`). Ambient lighting is bright cyan or white (ice glow). The biome is cold and crystalline; visual impression is "inside a glacier."

### Layout Style
Entirely vault-driven. Each Cocytus floor is a vault, often featuring ice formations and frozen channels.

### Signature Monsters
Blizzard demons, rime drakes, ice fiends, frost giants, cold creatures. Ice-themed enemies with cold attacks. Many have slow/freeze effects.

### Signature Features
Ice tiles (impassable or slippery, depends on depth). Ice formations (cosmetic, sometimes breakable). The Icy Rune of Zot is held within. Few lava features; mostly ice and frost.

### Vault Library
Cocytus vaults are ice-centric: ice halls, frozen chambers, crystal mazes, rune vaults. All unique. Tags: `coc_decor`, `coc_mon`.

### Run-Loop Role for Botter
**Optional Hell tier, floors 8-9 (if Hell is explored).** Cocytus is the "ice" Hell — crystalline, beautiful, and mechanically hazard-heavy (slippery surfaces, cold damage). Use Cocytus for visual contrast (bright, not dark). Skip if prioritizing Zot.

### Asset Status
**PARTIAL**: Ice tiles are in the project (used for Glacier branch). Cocytus-specific creatures may need copying.

---

## Tartarus (Tartarus)

**Canonical name**: "Tartarus" | **Abbreviation**: "Tar" | **Depth**: 7 floors | **Entry**: off Hell (Vestibule) | **Rune**: Dark rune

### Depth & Structure
One of four Hell branches. A 7-floor descent through a shadowy, decaying hellscape. Tartarus is the "shadow" Hell.

### Visual Identity
Dark abyss. Floors are dark grey, purple, or black stone (`floor_tar_*`, `floor_black_*`, `floor_magenta_*`). Walls are dark stone or shadow (`wall_tar_*`, `wall_black_*`, `wall_magenta_*`). Ambient lighting is dim and purple-tinted (eldritch glow, void ambient). The biome is eerie and claustrophobic; visual impression is "the void made solid."

### Layout Style
Entirely vault-driven. Tartarus vaults often feature narrow corridors and enclosed chambers (tight, oppressive).

### Signature Monsters
Shadow demons, reapers, executioners, revenants, soul eaters, wraiths, death-aspected creatures. Undead and shadow themes dominate.

### Signature Features
Shadow terrain (cosmetic). Void/darkness (visual, not mechanic). The Dark Rune of Zot is held within. Many undead features (sarcophagi, bones). Traps are frequent.

### Vault Library
Tartarus vaults are shadow-centric: shadow chambers, undead halls, void crypts, rune vaults. All unique. Tags: `tar_decor`, `tar_mon`.

### Run-Loop Role for Botter
**Optional Hell tier, floors 8-9 (if Hell is explored).** Tartarus is the "shadow" Hell — thematically undead-heavy and visually dark. Use Tartarus if showcasing undead/necromancy content. Skip if prioritizing Zot.

### Asset Status
**PARTIAL**: Dark tile prefixes available. Shadow-specific creatures may need copying.

---

# Chaos Realms

These branches are unique, chaotic, and procedurally generated. They are optional endgame content.

## Pandemonium (Pan)

**Canonical name**: "Pandemonium" | **Abbreviation**: "Pan" | **Depth**: Procedurally infinite (1-N floors) | **Entry**: off Depths (or Hell Vestibule)

### Depth & Structure
Pandemonium is a "realm" rather than a traditional branch. It consists of procedurally-generated chambers, each a single floor. The player descends indefinitely, collecting runes and unique loot, until exiting manually. Filled with Demon Lords (unique named entities) that guard major runes.

### Visual Identity
Chaotic realm. Floors vary per-chamber (Pandemonium randomizes the biome): black void, fiery, icy, crystalline, etc. Walls are similarly randomized, often featuring strange textures and colours. Ambient lighting is chaotic and colourful (magical instability). The biome is *intentionally* disorienting — no visual consistency.

### Layout Style
Procedurally generated per-floor. Each Pandemonium floor is unique and randomized. Layouts mix `basic_level`, delve caves, and vault stamps. The result is unpredictable and thematically chaotic.

### Signature Monsters
Demons of all types: lesser demons, greater demons, unique Demon Lords (Mnoleg, Lom Lobon, Cerebov, Gloorx Vloq). Many enemies are high-tier threats. The Demon Lords are unique encounters (not repeating).

### Signature Features
Randomized terrain (chaos). Demonic architecture. The branch has no natural exit — the player must find or create an exit portal. Multiple runes are scattered throughout Pandemonium (collecting all four Hell runes + Pandemonium's own grants access to the Abyss). Demonic trees, crystal formations, lava, water, ice — all randomized per floor.

### Vault Library
Pandemonium vaults are few; most generation is procedural. Named vaults exist for Demon Lord chambers (each LL has a unique arena). Tags: `pan_decor`, `pan_lord_*`.

### Run-Loop Role for Botter
**Endgame chaos tier, optional post-Zot content.** Pandemonium is not part of the main progression. If implemented, it serves as a "infinite dungeon" mode: descend as far as you want, collect runes, fight Demon Lords. For Botter, Pandemonium could be an optional prestige-tier run: "survive N floors of Pandemonium for bonus loot/XP."

### Asset Status
**PARTIAL**: Various demon sprites exist. Procedural generation system needs designing. The chaotic nature means fewer tile prefixes are committed upfront — tiles are randomized.

---

## The Abyss (Abyss)

**Canonical name**: "the Abyss" | **Abbreviation**: "Abyss" | **Depth**: Procedurally infinite (1-N floors) | **Entry**: off Pandemonium (after collecting 4 Hell runes) or deep Depths | **Rune**: Abyssal rune

### Depth & Structure
The Abyss is the ultimate endgame branch. Procedurally infinite, with the Abyssal Rune hidden somewhere within. The player must navigate the chaotic Abyss, locate the rune, and escape. Very few players reach the Abyss.

### Visual Identity
Void and chaos. Floors are black or dark grey with shifting geometry (`floor/abyss_*`, `floor_black_*`). Walls are unstable and changeable (visually), sometimes glitching (`wall/abyss_*`). Ambient lighting is minimal and eerie (void glow). The biome is intentionally disorienting and alien — not a place, but an *absence*.

### Layout Style
Procedurally chaotic. Each Abyss floor is randomized, with no guarantees of structure. Geometry shifts; corridors are not guaranteed to connect. The generator creates a sense of confusion and danger. Vaults are minimal; most generation is proc.

### Signature Monsters
Abyssal creatures: very ugly things, tentacled monstrosities, spawns of chaos, wyverns, aberrations. The highest-tier unique monsters. Demons, undead, and chaotic creatures coexist. Many enemies have special mutation or chaos abilities.

### Signature Features
The Abyssal Rune (the goal). Demonic geometry and shifting terrain. The Abyss has no natural stairs — the player must find portals or force an escape. Many traps and hazards. Procedural chaos makes every visit unique. The Abyss mechanic in DCSS includes "abyssal mutations" (random stat changes) — may not apply to Botter.

### Vault Library
Minimal; almost all Abyss generation is procedural. Named vaults exist for the Abyssal Rune chamber and some unique encounters. Tags: `abyss_exit`, `abyss_rune`.

### Run-Loop Role for Botter
**Absolute endgame, post-Zot, optional ultra-difficulty content.** The Abyss should not appear in normal runs. If implemented, it's a prestige unlock: "clear Zot, unlock Abyss challenge." For Botter, the Abyss could be a roguelike sub-mode: infinite descent, permadeath, no gear progression, climb the leaderboard.

### Asset Status
**MINIMAL**: Abyss floor and wall prefixes exist but are sparse. Abyssal creatures and shift geometry need extensive work. This branch is out-of-scope for MVP.

---

# Portal Vaults & Minor Branches

DCSS includes many single-floor "portal vaults" accessible via portals scattered throughout the Dungeon. These are mini-dungeons with unique themes, loot, and challenges. For Botter, portal vaults are optional content—easily implemented as bonus floors in runs.

## List of Portal Vaults (not fully detailed due to length)

- **Ziggurat**: A procedurally-generated tower of 27 floors, each progressively harder, culminating in a unique Ziggurat boss. Cosmetic: black floor/wall, ascending tiers.
- **Labyrinth**: A single-floor maze. Exit is hidden; navigate to find it. Cosmetic: black maze tiles, winding corridors.
- **Bazaar**: A market zone with rare item purchases. No combat; cosmetic: colorful merchant stalls.
- **Trove**: A single-floor treasure vault. Packed with loot, few enemies. Cosmetic: gold and blue colours.
- **Sewer**: A grungy sewer system. Short, low-level content. Cosmetic: brown water, sewer tiles.
- **Ossuary**: A bone-filled ossuary. Similar to Crypt. Cosmetic: bone tiles, white stone.
- **Bailey**: A military fortification. Similar to Orc. Cosmetic: white and red stone, military architecture.
- **Gauntlet**: A challenge arena. Combat gauntlet with progressively hard encounters. Cosmetic: black arena.
- **Ice Cave**: A small frozen cave. Few enemies, few floors. Cosmetic: blue and white ice tiles.
- **Volcano**: A lava-filled caldera. Few floors, high heat. Cosmetic: red and black lava tiles.
- **Wizlab**: A wizard's laboratory. Unique per instance (randomized between a few templates). Cosmetic: varies per lab.
- **Desolation of Salt**: A salt flat wasteland. Few enemies, mostly navigation. Cosmetic: light-grey and brown salt tiles.
- **Gulch**: A gutter gulch (sewer-like ravine). Cosmetic: green and light-blue tiles.
- **Necropolis**: A necropolis arena. Cosmetic: magenta and light-grey stone.
- **Arena**: Okawaru's combat arena. Pure combat challenge, no exploration. Cosmetic: black arena.
- **Crucible**: The Crucible of Flesh. Combat arena with mutation mechanics. Cosmetic: black arena.

**Asset Status**: Portal vaults are optional. Most have tile prefixes already in the project (ice, volcano, lava, etc.). Implementing 1-2 portal vaults per development cycle is feasible; porting all ~16 is a mid-to-long-term goal.

---

# Asset Gaps & Feasibility Table

## Current Asset Inventory

**Botter Project Tile Assets** (as of latest inventory):

| Category | Count | Status |
|---|---|---|
| **Floor tiles** | 444 unique images | Broad coverage, ~50% utilization |
| **Wall tiles** | Many hundred | Broad coverage, ~50% utilization |
| **Enemy sprites** | ~180 unique | Minimal utilization (10 actively used) |
| **Item sprites** | Many hundred | Minimal utilization (~5% active) |
| **Artefact items** | 84+ unique weapons, 38+ armour | 0% utilization (legendary items use common sprites) |
| **Features** (altars, fountains, doors, statues) | 200+ total | Low utilization |
| **Decorative tiles** (trees, mushrooms, bones, etc.) | Many hundred | Minimal utilization |
| **Ambient effects** (blood, fire, ice, etc.) | 238+ frames | 0% utilization |

**Feasibility by Branch** (for shipping in Botter):

| Branch | Biome Tiles | Monsters | Vaults | Overall Status |
|---|---|---|---|---|
| **D** (Dungeon) | ✓ Ready | ✓ Basic | ✓ Ready | SHIP NOW |
| **Lair** | ✓ Ready | ✓ Ready | ✓ Ready | SHIP NOW |
| **Orc** | ✓ Ready | ✓ Ready | ✓ Ready | SHIP NOW |
| **Elf** | ✓ Mostly | ✗ Need sprites | ~ Partial | SHIP WITH GAPS |
| **Snake** | ~ Partial | ✓ Ready | ✓ Ready | SHIP WITH GAPS |
| **Spider** | ~ Partial | ✓ Ready | ✓ Ready | SHIP WITH GAPS |
| **Swamp** | ✓ Ready | ✓ Ready | ✓ Ready | SHIP NOW |
| **Shoals** | ~ Partial | ✗ Need merfolk | ✓ Ready | SHIP WITH GAPS |
| **Slime** | ✓ Ready | ✓ Ready | ✓ Ready | SHIP NOW |
| **Vaults** | ✓ Ready | ✓ Ready | ✓ Ready | SHIP NOW |
| **Crypt** | ✓ Ready | ✓ Ready | ✓ Ready | SHIP NOW |
| **Tomb** | ✓ Ready | ✓ Ready | ✓ Ready | SHIP NOW |
| **Depths** | ✓ Ready | ✓ Ready | ✓ Ready | SHIP NOW |
| **Zot** | ✓ Ready | ✓ Ready | ✓ Ready | SHIP NOW |
| **Hell** | ~ Partial | ✗ Need sprites | ✓ Ready | DEFER |
| **Dis** | ✓ Ready | ✓ Ready | ✓ Ready | SHIP WITH HELL |
| **Gehenna** | ~ Partial | ✓ Ready | ✓ Ready | SHIP WITH HELL |
| **Cocytus** | ~ Partial | ✓ Ready | ✓ Ready | SHIP WITH HELL |
| **Tartarus** | ~ Partial | ✓ Ready | ✓ Ready | SHIP WITH HELL |
| **Pan** | ✗ Partial | ✓ Ready | ✓ Ready | DEFER (procedural chaos) |
| **Abyss** | ✗ Partial | ✓ Ready | ✓ Ready | DEFER (procedural chaos) |

## High-Priority Tile Gaps

1. **Merfolk sprites**: Shoals and Elf need merfolk warrior, merfolk mage, merfolk siren sprites. ~3-5 key sprites.
2. **Deep elf mage sprites**: Elf branch needs deep elf pyromancer, deep elf zephyrmancer. 2 sprites.
3. **Lava hazard tiles**: Gehenna and Forge need true lava tiles (floor_lava_*) if hazard mechanics are added. Already partially in.
4. **Water shoreline transitions**: Swamp and Shoals need proper deep_water + shore tile blends. May require 10-20 additional tiles.
5. **Portal vault tiles**: Ice, volcano, salt, etc. partially available; may need supplementary copies.
6. **Hell-specific decor**: Iron golems, hell sentinels, Hell-specific monsters need sprites. ~8-10 sprites.

## High-Priority Monster Gaps

1. **Branch-signature monsters**: Each branch should have 5-10 unique enemies. Current roster is ~10 monsters total; branches need ~20 additional sprites (multiple enemies per branch).
2. **Dragon variants**: Zot and Depths need acid, fire, ice, storm, shadow, golden, iron, quicksilver, bone dragon sprites. 9+ sprites.
3. **Demon variants**: Hell and Pan need balrug, efreet, hell knight, sin beast, etc. ~10+ sprites.
4. **Undead variants**: Crypt and Tomb need more varied undead (wraiths, soul eaters, liches). 5-8 sprites.

## Recommendation for Phasing

**Phase 1 (MVP, ~8 branches)**: Ship D, Lair, Orc, Swamp, Vaults, Crypt, Tomb, Zot. All assets are ready or have minimal gaps. Use existing monsters and accept visual repetition.

**Phase 2 (Branch expansion, ~6 branches)**: Add Elf, Snake, Spider, Shoals, Depths, Slime. Copy merfolk + 1-2 sprites per branch from DCSS tileset, expand monster pools, ship new vaults.

**Phase 3 (Hell tier)**: Add Hell, Dis, Gehenna, Cocytus, Tartarus. Requires hell-specific monster sprites and tile prefixes. Later priority due to procedural generation complexity and optional end-game status.

**Phase 4 (Chaos realms)**: Add Pan and Abyss. Requires procedurally chaotic generation system; defer to post-MVP because implementation effort is high and content is optional.

---

## Conclusion

DCSS has a 20+-year history of balanced, polished branch design. By porting the branch structure, aesthetics, and (paraphrased) generation algorithms into Botter, we inherit decades of playtesting and design insight. The tile assets already exist in CC0 form, and the data (enemy HP, item affixes, boss designs) is public knowledge.

For Botter's 10-floor idle-run structure, a linear chain through 8-10 branches (D → Lair → Vaults → Crypt → Tomb → Depths → Zot, with optional side branches in Lair) provides narrative progression, visual variety, and escalating challenge. The Abyss and Pandemonium can be optional prestige content for dedicated players.

All specifications in this document are paraphrased from DCSS source; no GPL code is reproduced. Implementation in Botter's GDScript / Godot is the next step, following the porting rules in CLAUDE.md.

