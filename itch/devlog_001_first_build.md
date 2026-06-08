# First playable build

If you're reading this, you probably got the link from me directly —
welcome, and thanks for trying it.

Quick recap of what Botter is: an idle game where instead of *playing*
a roguelike, you configure an autonomous bot and watch it run dungeons.
Think MMO botter / autoplay-stream aesthetic — the bot is the point.

The dungeon generation, monsters, items, and vault library are ported
in spirit from Dungeon Crawl Stone Soup. DCSS has 20 years of design
and balance baked in; I'd rather lean on that than reinvent it. The
original work is the bot AI and the idle-loop progression.

## What's working

- Procgen pipeline ported from DCSS's `dgn-layouts.cc` — trail+rooms,
  delve caves, octa rooms, chequerboard, river/lake
- ~1300 vaults from DCSS's .des library, theme-tagged per branch
- Combat loop: bot pathfinds, swings, levels, picks up loot
- Gear: rarity tiers, affixes, legendary uniques, per-instance tints
- Branch progression: clear boss → unlock siblings → unlock next tier
- End-game stats capped at ~1500 HP / ~300 ATK / ~100 DEF on purpose
  — no idle-game number creep, ever

## What's rough

- **Web load time**: first dungeon entry is 15-25s while the browser
  uploads tile textures to the GPU. Once loaded, runs play locked at
  120fps. Steam + mobile builds will skip this entirely.
- **Balance**: t1-t3 mostly tuned, t4-t5 still rough
- **Spell visuals**: functional, ugly, placeholder
- **No sound** yet

## What I want feedback on

- Where did the bot get stuck or feel pointless to upgrade?
- Any item or spell so good you stopped considering alternatives?
- Anything crash, freeze, or render weirdly?
- Did the loop hold your attention, or get boring fast?

Play it at the link above. Thanks for poking.
