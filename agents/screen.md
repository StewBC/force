# Character screen, font, palette

Cell buffer and software rasterizer for **chrome** (rows 20–24). The
playfield is a tile composite; see [`game.md`](game.md) and
[`assets.md`](assets.md). No SDL types in this layer.

Source: `src/sdl/core/types.h`, `src/sdl/core/font.*`, `src/sdl/core/screen.*`.

## Buffer

`force_screen` is `force_cell cells[FORCE_ROWS][FORCE_COLS]` — 25×40, row
major, `cells[y][x]`. Each cell is one character plus two colour indices.

Writes:

| Call | Behaviour |
|------|-----------|
| `force_screen_clear` | Fill the whole buffer |
| `force_screen_fill` | Axis-aligned rect, clipped to 40×25 |
| `force_screen_putc` | One cell; out of bounds is a no-op |
| `force_screen_puts` | ASCII C string; stops at `NUL` or column 40; negative `x` is skipped until the string walks on-screen |

`fg`/`bg` are clamped to `FORCE_COLOR_COUNT` (unknown → white).

There is no dirty rectangle. Game rasterizes the full 40×25 then overwrites
the playfield.

## Palette

`enum force_color` in `types.h` is VIC-II order (black … light grey). RGB is
the common tutorial / "pepto simplified" table in `screen.c`, stored as
`0x00RRGGBB` then OR'd with `0xFF000000` at blit time (XRGB8888, opaque).

Do not put RGB in `types.h`. Chrome uses these indices. Playfield RGB comes
from the tileset PNG.

## Font

`force_glyph(ch)` returns 8 bytes, one per row. **Bit 0 is the leftmost
pixel** (not MSB-first). Index 0 is ASCII 32.

Source of the bits: public-domain VGA 8×8 (Marcel Sondaar / IBM, via Daniel
Hepper font8x8), compiled into `font.c`. This is a host stand-in, not a C64
character ROM.

| Input | Result |
|-------|--------|
| `32..127` | That glyph |
| `< 32` or `> 127` | Space |

There are no PETSCII in this font. Map tiles are not this font; see
[`assets.md`](assets.md).

## Rasterize

`force_screen_rasterize(screen, pixels)` writes `FORCE_FB_W * FORCE_FB_H`
`uint32_t`s (320×200). Caller owns the buffer (`force_game.pixels`). For each
cell, each of 8 glyph rows, each of 8 columns: bit set → fg, else bg.

Game calls this after painting the strip, then overwrites rows 0–19 with
tiles. Host uploads the composed buffer: [`host.md`](host.md).

## Objective row

Gameplay row 24 (line 25) is reserved for scripted objective cues, with a
dark-grey background and a `>` prefix at column 0 and text starting at column 2. Yellow/white ink
alternates gently, then the row becomes blank. The old platform, joystick,
and WASD/LINE labels have been removed; input-mode behavior is unchanged.
