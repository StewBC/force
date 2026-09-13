# Assets and the SDL compiler

Authoring files under `assets/` are compiled into `src/sdl/generated/` by
`tools/gen_sdl.py`. CMake owns that edge: `cmake --build` regenerates when
inputs change. There is no runtime file load.

Do not edit `src/sdl/generated/`. It is gitignored aside from `.gitignore`.

## Inputs

| Path | Role |
|------|------|
| `assets/png/tiles.png` | 128×64 indexed PNG, 8×8 cells, 16×8 sheet. Palette index 0 is transparent. |
| `assets/maps/tiles.tsx` | Tiled tileset (geometry + pointer at the PNG). |
| `assets/maps/*.tmx` | Maps. `farm.tmx` is 40×20. |
| `assets/tiles.txt` | Tile-id ranges → names → class numbers. |
| `assets/properties.txt` | Colour-chip presets on the `properties` layer. |
| `assets/missions.txt` | Mission name, map stem, window rect. |

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
113 cover_hard_none
cover_hard_none=cover grade=3 facing=none
```

- Chip line: tile id **113–127**, then a preset name. Tile 112 is knockout
  and is not a chip.
- Preset line: `name=kind` then optional `key=value` fields.

Kinds: `cover` (grade 1–3, facing n/e/s/w/none), `scout` (facing n/e/s/w),
`portal`, `objective`, `mine`. Unknown painted chips fail the compile. A
preset with no chip is allowed. The file is required; zero chip lines would
be a legal empty vocabulary.

## `missions.txt`

```text
farm_mission farm 0,0,40,20
```

`name  map  x,y,w,h`. `map` is the `.tmx` stem. The rect must sit inside that
map. Missions are windows into a (later, larger) map; compression-by-section
is not implemented.

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
   `missions.txt`.
2. Decodes the PNG (8-bit indexed / RGB / RGBA, non-interlaced).
3. **Verifies each tile is 2-wide horizontally** (pair `x,x+1` identical).
   Does not pack to C64 2-bit; this is an SDL emitter.
4. Extracts rooms, then properties, then actors. Caps are `#define`s.
   Width > 80, height > 50, or width × height > 4000 fails the compile.
5. Writes `force_data.h` / `force_data.c` (SoA, not five planes).

CMake: `find_package(Python3 REQUIRED COMPONENTS Interpreter)` in
`src/sdl/CMakeLists.txt`. `add_custom_command` depends on the script, the
text files (`tiles.txt`, `missions.txt`, `properties.txt`), the PNG, the
TSX, and `assets/maps/*.tmx` (`CONFIGURE_DEPENDS` glob).

## Generated API

`generated/force_data.h` (included as `"generated/force_data.h"`):

- `FORCE_MAP_W_MAX` 80, `FORCE_MAP_H_MAX` 50, `FORCE_MAP_CELLS_MAX` 4000
- `force_tileset[COUNT][8][8]` — `uint32_t` ARGB, `A=0` transparent
- `force_tile_class[COUNT]`
- `force_map`: dense `color` + `tiles`, then room rect SoA, cover / portal /
  scout / spawn / objective / mine tables. No `properties` / `actors` /
  `rooms` plane pointers. Global SoA pointers are `NULL` iff that count is 0.
- `force_map_farm` (one symbol per `.tmx` stem)
- `force_missions[]` / `force_mission_count`

`force_world_load` in `src/sdl/game/world.c` is the ROM reader: it copies
board columns from `force_map` into cap-sized BSS. After load, `game.c`
does not index `force_map`.

## SDL draw

Playfield (rows 0–19) in `src/sdl/game/game.c`, from BSS after load:

1. For each cell of the world window: fill 8×8 from the colour-layer
   tile’s pixel `[0][0]` (fully transparent empty chip → opaque black), then
   stamp `tiles`. Index is `world->row_off[my] + mx`.
2. Walk the spawn list. Stamp `spawn_tile`, then re-stamp `tiles` on that
   cell so roofs still cover. Skip spawns outside the window.
3. Cursor: yellow 1-pixel border; full yellow cell on blink.

Chrome (rows 20–24) still goes through `force_screen` + the VGA font.

## What not to do

- Do not `#include` SDL from `core/` or `game/`.
- Do not load PNG/TMX at runtime.
- Do not hand-edit `generated/force_data.*`.
- Do not invent a C64 emitter here. Same authoring files, later pass.
