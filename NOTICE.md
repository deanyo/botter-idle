# Notice

This file enumerates the third-party content bundled in Botter and the
licenses under which it is included. The game logic itself (GDScript
source, scenes, shaders, JSON data files outside of `project/data/vaults/`)
is covered by `LICENSE` (All Rights Reserved). For game credits see
`CREDITS.md`.

## Tile sprites — DCSS / RLTiles (CC0)

The tile sprites bundled under `project/assets/tiles/` and the
unbundled DCSS tile pack under `dcss/` (gitignored, CC0) originate
from the Dungeon Crawl Stone Soup tile set, itself a descendant of
the public-domain RLTiles roguelike tileset.

> Part of the graphic tiles used in this program are from the public
> domain roguelike tileset RLTiles. http://rltiles.sourceforge.net/

The DCSS team and individual contributors signed off on CC0 1.0
Universal for these tiles in 2010. CC0 does not require attribution,
but in keeping with the original DCSS README's request that users
credit the contributors and link back so others can find the
source, the following list reproduces the contributor roster from
`dcss/Dungeon Crawl Stone Soup Full/README.txt`:

- abrahamwl
- Adam Borowski (castamir)
- Baconkid
- Brannock
- Brendan Hickey
- CanOfWorms
- Charles Otto (caotto)
- cjo
- co
- coolio
- Corin Buchanan-Howland
- Curio (curio.solus)
- David Lawrence Ramsey (dolorous)
- David Ploog (dploog)
- Denzi
- dolphin
- donblas / chamons
- dshaligram
- Edgar A. Bering IV
- Eino Keskitalo (evktalo)
- Enne Walker (ennewalker)
- Eronarn
- floatRand
- Florian Diebold
- frogbotherer
- fusentrap
- gammafunk
- Grunt (sgrunt / hypergrunt / Steve Melenchuk)
- Ixtli
- Jesse Luehrs (doy)
- Jinhlk
- Johanna Ploog (j-p-e-g)
- Jude Brown (bookofjude)
- LoginError
- Marbit
- minmay
- Mitsuhiro Itakura
- Mu
- n78291 (Shayne?)
- Neil Moore (|amethyst)
- Nicholas Feinberg (PleasingFungus)
- Omndra
- ontoclasm
- Poor_Yurik
- Porkchop
- pubby
- Purge
- Raphael Langella
- Raumkraut
- Robert Vollmert
- roctavian
- rsaarelm
- shmuale (wheals)
- Stefan O'Rear
- theTower
- Totaku
- xnmojo
- XuaXua
- zebez

The full contributor list and original CC0 licence text are reproduced
verbatim in `dcss/Dungeon Crawl Stone Soup Full/LICENSE.txt` and
`dcss/Dungeon Crawl Stone Soup Full/README.txt`.

Tile pack sources:
- https://github.com/crawl/tiles/tree/master/releases
- https://opengameart.org/content/dungeon-crawl-32x32-tiles
- https://opengameart.org/content/dungeon-crawl-32x32-tiles-supplemental

## Vault layouts — DCSS .des contributors

The 1320 ported vaults under `project/data/vaults/vault_*.json` are
shape ports of DCSS `.des` map definitions. The opaque per-theme IDs
(`vault_<theme>_NNNN`) replace the original DCSS-derived filenames;
`project/data/vault_id_map.json` records the mapping for traceability,
and each vault file's `_original_dcss_id` field preserves the source
filename.

DCSS source is licensed GPLv2+. Map definitions in DCSS (the `.des`
files) describe layout shapes and creative authorship; per the port
workflow described in `CLAUDE.md`, the glyph DSL was reimplemented as
a JSON shape (port format, not port source code) and the literal
ASCII grids were rotated by a hash-stable angle to avoid 1:1
reproduction.

The following DCSS contributors authored vault content represented
in the ported set, identified by their handles in the original
filenames:

- alex1729
- amethyst
- argonaut
- beargit
- bh
- blackcustard
- bobbens
- cheibrodos
- david
- dpeg
- dshaligram
- due
- ebering
- eino
- elwin
- erik
- evilmike
- floodkiller
- gammafunk
- grunt
- guppyfry
- hangedman
- hellmonk
- ilsuiw
- infiniplex
- johnstein
- kennysheep
- lemuel
- lightli
- mainiacjoe
- minmay
- mu
- mumra
- nicolae
- nooodl
- nzn
- pdpol
- pf
- regret
- skrybe
- spicy
- spider
- st
- storm
- tekkud
- weyrava
- wheals
- ximxim
- yaktaur

Approximately 100 additional vault files originated from DCSS source
without an attributable handle in the filename; those layouts are
attributed collectively to the DCSS contributor community at large.
The full Crawl development team is credited at
https://crawl.develz.org/wordpress/.

## Dungeon-layout algorithms — original GDScript

The dungeon-generation algorithms in `project/scripts/dcss_layouts.gd`
(`basic_level`, `make_trail`, `delve`, `octa_room`, `chequerboard`,
river/lake/Worley layouts) are original GDScript implementations of
standard procedural dungeon-generation patterns. They are not ported
or transliterated from DCSS source code; the file was rewritten in a
clean-room session against a behavior-only description (see
`CLAUDE.md` "HOW TO PORT" rules and `HANDOVER.md` for the rewrite
history).

## Godot Engine (MIT)

Botter is built on the Godot Engine (4.6.2-stable),
https://godotengine.org/, used under the MIT License:

> Copyright (c) 2014-present Godot Engine contributors.
> Copyright (c) 2007-2014 Juan Linietsky, Ariel Manzur.
>
> Permission is hereby granted, free of charge, to any person obtaining
> a copy of this software and associated documentation files (the
> "Software"), to deal in the Software without restriction, including
> without limitation the rights to use, copy, modify, merge, publish,
> distribute, sublicense, and/or sell copies of the Software, and to
> permit persons to whom the Software is furnished to do so, subject to
> the following conditions:
>
> The above copyright notice and this permission notice shall be
> included in all copies or substantial portions of the Software.
>
> THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
> EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
> MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
> NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS
> BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
> ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
> CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
> SOFTWARE.

Godot's full third-party notice (engine dependencies — FreeType,
HarfBuzz, mbedTLS, miniupnpc, etc.) is bundled with the Godot
distribution and reproduced at
https://github.com/godotengine/godot/blob/master/COPYRIGHT.txt.

## Test framework — GUT (MIT)

The `project/addons/gut/` directory vendors the Godot Unit Test
framework (GUT) 9.6.0, https://github.com/bitwes/Gut, used under
the MIT License. See `project/addons/gut/LICENSE.md` for the full
license text.
