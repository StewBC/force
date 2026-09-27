# Assets and the SDL compiler

Authoring files under `assets/` are compiled into `src/sdl/generated/` by
`tools/gen_sdl.py`. CMake owns that edge: `cmake --build` regenerates when
inputs change. There is no runtime file load.

Do not edit `src/sdl/generated/`. It is gitignored aside from `.gitignore`.

## Inputs

| Path | Role |
|------|------|
| `assets/png/tiles.png` | 128×64 indexed PNG, 8×8 cells, 16×8 sheet. Palette index 0 is transparent. |
| `assets/png/force_title_c64.png` | 160×200 RGB splash, Colodore VIC colours, at most four per 4×8 cell. `tools/gen_title.py` |
| `assets/maps/tiles.tsx` | Tiled tileset (geometry + pointer at the PNG). |
| `assets/maps/*.tmx` | Maps. `normandy.tmx` and `bastogne.tmx` are 80×40 (2×2 playfields). Bastogne is a copy of Normandy. |
| `assets/tiles.txt` | Tile-id ranges → names → class numbers. |
| `assets/properties.txt` | Colour-chip presets on the `properties` layer. |
| `assets/missions.txt` | Mission name, map stem, window rect, optional script stem, optional `"title"`. File order is the C64 campaign order. |
| `assets/scripts/*.txt` | Cue sheets. `gen_sdl.py` compiles them; no parser in the game. |

Aseprite source (`assets/aseprite/`) is not an input.

## `tiles.txt`

`#` to end of line is a comment. Two kinds of statement:

```text
0-7 goodguys
16-18,19-28,29 walls
empty=0
```

- Range line: ids, then a name. A name may have several ranges.
- Class line: `name=number`. Every name used in a range must have a class.
  Values must be unique.

Current classes: `empty=0`, `walls=1`, `roofs=2`, `barriers=3`,
`goodguys=4`, `enemies=5`, `colors=6`. Unlisted tile ids are class `empty`.

Tile **112** is named `empty` (Tiled GID 113). That is the knockout /
background chip. The compiler emits `FORCE_TILE_EMPTY`.

## `properties.txt`

`#` to end of line is a comment. Two kinds of statement:

```text
117 cover_good_w
cover_good_w=cover grade=2 advancing=w
118 cover_soft_w
cover_soft_w=cover grade=2 soft=w
127 cover_hard_w
cover_hard_w=cover grade=3 hard=w
```

- Chip line: tile id **113–127**, then a preset name. Tile 112 is knockout
  and is not a chip.
- Preset line: `name=kind` then optional `key=value` fields.

Cover: exactly one of `advancing=` / `soft=` / `hard=` (n/e/s/w).
`advancing` is an exclusive pole (rear). `soft` is neutral — anyone, look
from motion snapped to that axis (E/W chips make an EW room). `hard` is
neutral — anyone, look always that cardinal. Bare `none` is gone.
Scout presets still exist (`facing=` n/e/s/w) but have **no chip ids**
(the 15-chip row spent them on neutrals). `portal` is a door through a
wall tile; open fronts are inferred. Cover `facing=` is rejected.

A room is E–W **or** N–S (from any pole/soft/hard dir). Mixed fail.
Compiler packs `[lo | neutrals | hi]`. Live lists ≤ 12. Paint cap 24.
Neutrals sit in both lists, one occupant.

Old `cover_good_none` (tile 118) is now `cover_soft_w`. Farm interiors
that should always look west: restamp `cover_hard_w` (tile 127).

## `missions.txt`

```text
hold_farm normandy 40,0,40,20 farm "Hold the Farm"
```

`name  map  x,y,w,h [script] [cam=x,y] ["title"]`. `map` is the `.tmx` stem. Optional
script is the stem of `assets/scripts/<stem>.txt`. The quoted title is the
C64 menu label, 1..27 characters, and it is the last field. Optional `cam=x,y` is the
map cell where the 40×20 window's top-left opens; omitted, it is the rect
origin, and a value that would hang the window outside the rect is clamped
back inside. Missing file, unknown stem, or a script that names a room
colour the map does not have fails the **build**. The rect must sit inside
that map. It is the allowed play area. The view scrolls inside it; a 40×20
rect does not scroll. On a 2×2 board a mission is one quadrant,
a row (`12` / `34`), a column (`13` / `24`), or the whole board.
Diagonals are not rectangles. Farm is 80×40. The catalog row is the east
strip `40,0,40,40`, so the window opens at its top and can scroll south.
`exit-*` / despawn use the mission edge (farm west = x=40). Compression-by-section is not implemented.

## `scripts/*.txt`

Line-oriented cue sheet (`#` comments, `IDENT_RE` names). Room aliases bind
to colour chips, then to that mission map’s room index. Letters `A`–`H` are
enemy bank 8–15. Header (before any `beat`): `spawn_room`, and optional
`player_grenades` / `player_grenade_wait` / `enemy_grenades` /
`enemy_grenade_wait` (`<0-255>`, omitted = 0). `order` verbs `A` `D` `M` `H` `R`;
`force <0-10>` required.
`K` is rejected. `job idle` is illegal on a watcher. Caps fail the compile
(64 ops, 8 watchers, 12 beats, 32 preds, 16 wheres, 8 spawn templates,
15-char names). Beat and watch names are in ROM for `FORCE_SCRIPT=1`
traces. Farm is the 3-act Hold the Farm cue sheet (patrol, contact
fallback `R` room 3, last stand, wipe, overrun; player 20 grenades wait 50,
enemy 5 wait 100).

## TMX planes

Layers are keyed by **name**, not XML order. Authoring still uses five named
layers. The compiler keeps `color` and `tiles` dense and extracts lists from
the three meta planes.

| Layer | Tiled `0` | Tile 112 | Compiled |
|-------|-----------|----------|----------|
| `color` | `FORCE_TILE_EMPTY` | knockout fill | dense `uint8_t` |
| `tiles` | `FORCE_TILE_EMPTY` | knockout scenery | dense `uint8_t` |
| `rooms` | absence | knockout | filled rects (colour 1–15) |
| `properties` | absence | knockout | cover / portal / scout / objective / mine SoA |
| `actors` | absence | knockout | spawn list `x,y,tile` |

Missing meta layers are absence, not a plane of zeros. Unknown layer names
fail the compile. Tiled flip bits fail the compile.

**Knockout vs tile 0.** Tiled GID 0 on a meta plane is absence (`None`).
Tile **0** (`goodguys`, Tiled GID = `firstgid`) is a legal spawn. Tile **112**
(`FORCE_TILE_EMPTY`, Tiled GID 113 when `firstgid=1`) is knockout: no room,
no property, no spawn. Do not treat stored 0 as empty on meta.

Room paint uses colour chips **113–127** (colour = tile − 112). One colour
is one filled axis-aligned rect. Shared edges are allowed; shared cells are
not. Doughnuts, L-shapes, and two blobs of the same colour fail. Rooms must
cover every property and spawn cell.

GIDs on dense planes are 0-based tile ids (`gid - firstgid`); Tiled `0`
becomes 112. Meta GIDs keep tile 0.

## Compiler

`tools/gen_sdl.py --root <repo> --out src/sdl/generated`

Stdlib only (no Pillow). It:

1. Reads the TSX, PNG, `tiles.txt`, `properties.txt`, every `*.tmx`,
   `missions.txt`, and bound `assets/scripts/*.txt`.
2. Decodes the PNG (8-bit indexed / RGB / RGBA, non-interlaced).
3. **Verifies each tile is 2-wide horizontally** (pair `x,x+1` identical).
   Does not pack to C64 2-bit; this is an SDL emitter.
4. Extracts rooms, then properties, then actors. Caps are `#define`s.
   Width > 80, height > 50, or width × height > 4000 fails the compile.
5. Writes `force_data.h` / `force_data.c` (SoA, not five planes).

CMake: `find_package(Python3 REQUIRED COMPONENTS Interpreter)` in
`src/sdl/CMakeLists.txt`. `add_custom_command` depends on the script, the
text files (`tiles.txt`, `missions.txt`, `properties.txt`), the PNG, the
TSX, `assets/maps/*.tmx`, and `assets/scripts/*.txt` (`CONFIGURE_DEPENDS`
globs).

## Generated API

`generated/force_data.h` (included as `"generated/force_data.h"`):

- `FORCE_MAP_W_MAX` 80, `FORCE_MAP_H_MAX` 50, `FORCE_MAP_CELLS_MAX` 4000
- `FORCE_SPAWN_MAX` 32 (ROM stamp cap), `FORCE_UNIT_MAX` 32 (RAM pool;
  `FORCE_UNIT_MAX == FORCE_SPAWN_MAX`), `FORCE_SECTION_MAX` 16,
  `FORCE_LETTER_MAX` 8 (player roster / command-line WHO)
- `force_tileset[COUNT][8][8]` — `uint32_t` ARGB, `A=0` transparent
- `force_tile_class[COUNT]`
- `force_map`: dense `color` + `tiles`, then room rect SoA (including
  `room_axis` and `room_cover_lo/none/hi`), cover / portal / scout /
  spawn / objective / mine tables. `cover_facing` is advancing rear.
  Caps: `FORCE_COVER_PER_ROOM` 24, `FORCE_COVER_LIVE_MAX` 12,
  `FORCE_COVER_MAX` 128. No `properties` / `actors` / `rooms` plane
  pointers. Global SoA pointers are `NULL` iff that count is 0.
- `force_map_farm` (one symbol per `.tmx` stem)
- `force_script`: op / pred / where / watcher / beat / spawn-template SoA,
  plus grenade stock/wait per bank. Caps: `FORCE_SCRIPT_OPS_MAX` 64,
  watchers 8, beats 12, preds 32, wheres 16, spawn templates 8.
  `force_script_farm` (one symbol per script stem).
- `force_missions[]` / `force_mission_count`. Each mission has
  `const force_script *script` (NULL if the 4th field was omitted).

`force_world_load` in `src/sdl/game/world.c` is the ROM reader: it copies
board columns from `force_map` into cap-sized BSS, then feeds each stamp
through `force_unit_spawn`. Class `goodguys` → section 0, `enemies` →
section 8 (`FORCE_LETTER_MAX`); kind infantry, count 1, glyph = tile,
`unit_hp` 16. When `mission->script != NULL`, enemy stamps are skipped
(farm has none on `actors` either). There is no load-time ATTACK seed.
Script RAM (`script_pc`, spawn-job, clock, outcome, fired mask) is inited
from `mission->script`. After load, `game.c` does not index `force_map`.

## SDL draw

Playfield (rows 0–19) in `src/sdl/game/game.c`, from BSS after load:

1. For each cell of the world window: fill 8×8 from the colour-layer
   tile’s pixel `[0][0]` (fully transparent empty chip → opaque black), then
   stamp `tiles`. Index is `world->row_off[my] + mx`.
2. Walk the 32 unit slots (`unit_count[i] != 0`). Stamp `unit_glyph`; if
   the hurt nibble is set, lerp opaque glyph pixels 50% toward
   `0xFFCC3333`; then re-stamp `tiles` on that cell so roofs still cover.
   Skip units outside the window.
3. Cursor: yellow 1-pixel border; full yellow cell on blink.

Chrome (rows 20–24) still goes through `force_screen` + the VGA font.

## What not to do

- Do not `#include` SDL from `core/` or `game/`.
- Do not load PNG/TMX at runtime.
- Do not hand-edit `generated/force_data.*`.
- Do not invent a C64 emitter here. Same authoring files, later pass.
