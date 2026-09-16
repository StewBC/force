# Architecture and ownership

The only linked product today is the **SDL host** under `src/sdl/`. It is a
C11 prototype: 40×25 cells, 8×8 pixels. The playfield is a tile composite
from BSS `force_world`. The command strip is a four-slot wizard. There is
no 8-bit target tree yet. Last-order exists; `M` walks; `D`/`A` take cover;
`K` concentrates; rifles smear; force nibble breaks to `H`
(`FLAG_BREAKING` 0x08). Script ROM + RAM live on `force_world`; the stepper
is file-static in `world.c` (no `script.c`). `FLAG_CONTACT` 0x10 latches
enemy assault cover on dest-room entry. `script_outcome` freezes the tick
(fx only). No mixer.

**Paths in this folder** are repo-root literal (`src/sdl/...`, `CMakeLists.txt`,
`tools/`, `assets/`).

## Product boundary

`force` opens an SDL3 window (native 320×200 → 1280×800, 4× nearest-neighbour),
paints the active mission’s map window, and moves a cell cursor with keyboard
or the first gamepad/joystick. The four-slot wizard parses `M` `D` `H` `A` `K`
and writes last-order on RETURN. See [`game.md`](game.md). Map compile:
[`assets.md`](assets.md).

It is not the campaign RTS in [`doc/`](../doc/). Gaps versus that intent:
[`known-gaps.md`](known-gaps.md).

## Tree

```text
CMakeLists.txt            project(force) 0.1.0; add_subdirectory(src/sdl)
src/sdl/CMakeLists.txt    executable `force`; SDL3; C11; Python gen
src/sdl/main.c            window loop, --smoke
src/sdl/core/             types, font, character screen, rasterize
src/sdl/sdl/              SDL window, present, input poll
src/sdl/game/game.*       tick + compose frame
src/sdl/game/command.*    four-slot wizard (no SDL)
src/sdl/game/world.{h,c}  one BSS force_world (board + 32 units + 16 sections + script RAM); load / spawn / recount / shoot / script_step
src/sdl/generated/        force_data.{h,c} — tileset, two dense planes, SoA lists, force_script; do not edit
tools/gen_sdl.py          assets → generated (maps + cue sheets)
assets/                   PNG, TMX, tiles.txt, missions.txt, properties.txt, scripts/*.txt
```

Root CMake is the gate. Do not configure `-S src/sdl` as a second project.

The binary lands at `build/src/sdl/force` (no `RUNTIME_OUTPUT_DIRECTORY`).

## Dependency direction

```text
main.c       -> game + sdl/host
game/game.c  -> core/screen + core/types + game/world.h + game/command.h
game/command.c -> game/command.h + core/screen + stdio.h
game/world.c -> game/world.h + string.h  (world.h pulls generated/force_data)
sdl/host     -> sdl/input + core/types + SDL3
sdl/input    -> core/types + SDL3
core/screen  -> core/font + core/types
core/font    -> (none)
generated    -> (none)
```

Do not add reverse dependencies. `core/` must not include SDL headers.
`game/` must not include SDL headers; it sees the world through `force_input`
and writes a 320×200 `uint32_t` buffer. Host uploads that buffer.
`world.c` has no SDL and does not include `game.h`.

`tools/gen_sdl.py` is not linked. CMake runs it to produce `generated/`.

## Screen model

Constants live in `src/sdl/core/types.h`.

| Symbol | Value | Role |
|--------|-------|------|
| `FORCE_COLS` | 40 | Character columns |
| `FORCE_ROWS` | 25 | Character rows (C64 / this host) |
| `FORCE_PLAY_ROWS` | 24 | Portable rows 0–23 (Atari / Apple II) |
| `FORCE_FIELD_ROWS` | 20 | Playfield rows 0–19 |
| `FORCE_CELL_PX` | 8 | Pixels per cell |
| `FORCE_SCALE` | 4 | Host window scale |
| `FORCE_FB_W/H` | 320×200 | Native framebuffer |
| `FORCE_WIN_W/H` | 1280×800 | Default window |

Rows **0–19** are the playfield (tile composite). Rows **20–23** are the
portable 4-line command/status strip. Row **24** is extra chrome on C64 and
this SDL host; Atari and Apple II will not have it.

Chrome cells are `{ch, fg, bg}` with `fg`/`bg` in `enum force_color` (16
VIC-II indices). RGB for the strip lives in `core/screen.c`. Playfield RGB
comes from the tileset PNG.

## Thread and state ownership

One thread. `main` owns `force_host *`, `force_game`, and the per-frame
`force_input`. There is no runtime worker, no audio callback, no control port.

| Owner | Owns | Must not |
|-------|------|----------|
| `main` | Host lifetime, loop, `--smoke` | Game rules |
| `force_host` | Window, renderer, streaming texture, first pad/joy | `force_game` fields |
| `force_world_bss` | The one board (tiles, colour, lists, window, `row_off`) plus unit SoA (32: hp, fire_wait, fx, stepper), section SoA (16: last-order + `section_order_str`), and script RAM (`script_*`, one spawn-job) | Sit inside `force_game` |
| `force_game` | Screen cells, composed pixels, mission name, `world*` at BSS, cursor, wizard draft | SDL types; the world arrays; the unit pool |
| `force_input` | One frame of dx/dy/quit/fullscreen/joy/latch/cmd token | Persist across frames (host resets it) |

## Where to change code

| Path | Owns |
|------|------|
| `src/sdl/core/types.h` | Screen geometry, palette indices, `force_cell` / `force_screen` / `force_input` |
| `src/sdl/core/font.*` | 8×8 ASCII glyphs (chrome) |
| `src/sdl/core/screen.*` | Cell writes + XRGB8888 rasterize (chrome) |
| `src/sdl/sdl/host.*` | SDL init, events, present, stick attach |
| `src/sdl/sdl/input.*` | Keyboard / pad / stick → cursor delta + command token |
| `src/sdl/game/game.*` | Tick, chrome, playfield composite from BSS |
| `src/sdl/game/world.*` | BSS `force_world`, load / spawn / recount / relead, tick (consume → shoot → deaths → script → pulse → contact-start → consume → step → despawn), `force_section_issue`, `force_cover_assign` / `force_cover_release`. `FLAG_BREAKING` 0x08 and `FLAG_CONTACT` 0x10 on `section_flags` (with NOPATH 0x01, COVER_ASSIGN 0x02, COVER_RELEASE 0x04). Script stepper is file-static; no `script.c`. No mixer. |
| `src/sdl/generated/` | Do not edit; `tools/gen_sdl.py` |
| `tools/gen_sdl.py` | SDL data compiler (maps + cue sheets) |
| `assets/` | Sheet, maps, range file, mission file, properties.txt, scripts/*.txt |
| `src/sdl/main.c` | Loop glue |

## Operational rules

- Preserve the 40×25 / 8×8 / integer-scale contract.
- Playfield pixels are composed in game code; host only uploads. Do not draw
  with SDL from `game/` or `core/`.
- Do not introduce a mouse path. The product has no mouse.
- `core/` stays host-agnostic.
- Authoring changes go through `tools/gen_sdl.py`, not hand-written C arrays.
