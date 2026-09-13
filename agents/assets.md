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

## `missions.txt`

```text
farm_mission farm 0,0,40,20
```

`name  map  x,y,w,h`. `map` is the `.tmx` stem. The rect must sit inside that
map. Missions are windows into a (later, larger) map; compression-by-section
is not implemented.

## TMX planes

Layers are keyed by **name**, not XML order. Required vocabulary:

| Layer | Tiled `0` becomes | Drawn? |
|-------|-------------------|--------|
| `color` | `FORCE_TILE_EMPTY` | Fill under the tile |
| `tiles` | `FORCE_TILE_EMPTY` | Stamp last (covers actors) |
| `properties` | `0` (no stamp) | No |
| `actors` | `0` (no stamp) | Stamp under `tiles` if non-zero |
| `rooms` | `0` (no stamp) | No |

Missing `rooms` / `properties` / `actors` emit a zero plane. Unknown layer
names fail the compile. Tiled flip bits fail the compile.

Room paint uses the colour chips starting at colour **1** (tile 113). Colour
**0** / tile 112 stays empty.

GIDs are stored as 0-based tile ids (`gid - firstgid`).

## Compiler

`tools/gen_sdl.py --root <repo> --out src/sdl/generated`

Stdlib only (no Pillow). It:

1. Reads the TSX, PNG, `tiles.txt`, every `*.tmx`, `missions.txt`.
2. Decodes the PNG (8-bit indexed / RGB / RGBA, non-interlaced).
3. **Verifies each tile is 2-wide horizontally** (pair `x,x+1` identical).
   Does not pack to C64 2-bit; this is an SDL emitter.
4. Writes `force_data.h` / `force_data.c`.

CMake: `find_package(Python3 REQUIRED COMPONENTS Interpreter)` in
`src/sdl/CMakeLists.txt`. `add_custom_command` depends on the script, the
text files, the PNG, the TSX, and `assets/maps/*.tmx`
(`CONFIGURE_DEPENDS` glob).

## Generated API

`generated/force_data.h` (included as `"generated/force_data.h"`):

- `force_tileset[COUNT][8][8]` — `uint32_t` ARGB, `A=0` transparent
- `force_tile_class[COUNT]`
- `force_map` with five plane pointers (`uint8_t` tile ids)
- `force_map_farm` (one symbol per `.tmx` stem)
- `force_missions[]` / `force_mission_count`

## SDL draw

Playfield (rows 0–19), per cell, in `src/sdl/game/game.c`:

1. Fill 8×8 from the colour-layer tile’s pixel `[0][0]`. Fully transparent
   (empty chip) → opaque black.
2. Stamp `actors` if the cell is not 0.
3. Stamp `tiles` where alpha ≠ 0 (roofs hide actors; Tiled may still show
   actors on top for authoring).
4. Cursor: yellow 1-pixel border; full yellow cell on blink.

Chrome (rows 20–24) still goes through `force_screen` + the VGA font.

## What not to do

- Do not `#include` SDL from `core/` or `game/`.
- Do not load PNG/TMX at runtime.
- Do not hand-edit `generated/force_data.*`.
- Do not invent a C64 emitter here. Same authoring files, later pass.
