# Game (SDL)

Cursor on the active mission window, four-slot command wizard. Source:
`src/sdl/game/game.*`, `src/sdl/game/command.*`, `src/sdl/game/world.{h,c}`.
Loop glue: `src/sdl/main.c`. Map data: [`assets.md`](assets.md). Input
mapping: [`input.md`](input.md).

This is not combat. `M` walks to WHERE. `D` claims cover in the room each
stack occupies and walks to the hole (`$FF` = prone). `H` holds. Occupancy
is the 32-slot unit pool on `force_world`. The A–H roster is occupancy
chrome (white / grey / yellow).

## State

```c
typedef struct force_game {
    force_screen screen;
    uint32_t pixels[FORCE_FB_W * FORCE_FB_H];
    const force_mission *mission;   /* name / identity only after load */
    force_world *world;             /* &force_world_bss */
    int cursor_x;
    int cursor_y;
    uint32_t frames;
    bool joy_present;
    bool stick_latched;
    uint8_t cmd_verb;
    uint8_t cmd_who;
    uint8_t cmd_x;
    uint8_t cmd_y;
    uint8_t cmd_force;
    uint8_t cmd_slot;
    uint8_t cmd_digits;
    uint8_t cmd_last_who;
    uint8_t cmd_flash;
} force_game;
```

Parser + draft live on `force_game` (UI). Last-order stays world columns.
`force_game_init`: `mission = &force_missions[0]` (`farm_mission`),
`world = &force_world_bss`, `force_world_load(world, mission)` before
`field_w` / `field_h`, cursor at the centre of that window, `frames = 0`,
`stick_latched = false`, then `force_command_init` (seeds `cmd_last_who`
from the first occupied player letter; farm → A). After load, draw/clamp/
field size read the world. `g->mission` is the chrome name only. Units and
sections live on that world, not inside `force_game`.

## Tick

1. Decrement `cmd_flash` if > 0 (before feed, so a feed that sets 8 is
   red this draw and the next seven).
2. Add `in->cursor_dx/dy`, clamped to the world window (`win_w` / `win_h`,
   capped at `FORCE_COLS` × `FORCE_FIELD_ROWS`).
3. Copy `joy_present` and `stick_latched`.
4. `force_command_feed` (may set `cmd_flash = 8`).
5. `frames += 1`.

Cursor moves before feed so RETURN in the same frame uses the new cell.
Parse `M` / `D` / `H`. One RETURN commits remaining defaults onto
`section_order_*` for WHO 0–7. `A` in VERB flashes.
If `(frames % FORCE_LOGIC_PERIOD) == 0` **before** increment: `force_world_tick`
(cover flags consumed, then think). `M` walks to WHERE; `D` walks to the
claimed hole; `H` does not step. Frame 0 of `--smoke` is a logic tick with
verb NONE, so stamps stay put. Disconnected dest → `NO PATH`.

## Draw

## Draw

`force_game_draw` fills `g->pixels` every frame. Playfield reads BSS
(`world->color`, `world->tiles`, `world->unit_*`) via `row_off[my] + mx`.

1. Clear `g->screen`, paint rows 20–24 (strip + host line),
   `force_screen_rasterize` into `g->pixels`.
2. Playfield rows 0–19: fill colour + stamp `tiles` for the world window,
   then walk the 32 unit slots (skip `count == 0`; skip outside the window;
   stamp `unit_glyph`, re-stamp `tiles` so roofs cover). Do not rebuild a
   dense actors plane.
3. Cursor: yellow 1-pixel border; every 30 frames the cell fills yellow.

| Rows | Contents |
|------|----------|
| 0–19 | Mission window (colour + tiles + units + cursor) |
| 20–23 | Portable command strip: live wizard, talky line, map-cell `CURSOR xx,yy`, A–H roster |
| 24 | Host extra: `SDL  <mission>  JOY YES/NO  WASD\|LINE` |

Row 20: `VERB WHO WHERE FORCE`; current hole yellow (idle marks VERB),
flash light-red, SHOW all white. `force_command_paint` writes all four
tokens; the poster `puts` are gone. Row 21: `READY` when idle, talky
`MOVE A AT 10,20 FORCE 10` while drafting / after commit. Row 22 CURSOR
is **map** cells (`win_x + cursor_x`). Row 23 paints A–H from
`section_strength[0..7]`: white if that letter has men, light grey if empty,
yellow = implied WHO (`force_command_implied_who`, walk 32, first slot
wins) or the letter just typed (`cmd_who < 8`). Farm: A white, B–H grey;
cursor on a soldier turns A yellow. Room and property tables are in the
world and are not drawn. `M`/`D` walk; `H` holds. Cover is claimed on `D`.

`FORCE_TILE_PX` must equal `FORCE_CELL_PX` (`#error` in `game.c`).

## `main`

```text
force_host_init
force_game_init
while force_host_pump:
    tick, draw, present(game.pixels)
    if argv[1] == "--smoke": break
force_host_shutdown
```

`--smoke` is a one-frame bring-up: open, draw once, exit 0. Unknown argv is
ignored. Init failure prints `FORCE: failed to open an SDL window` on stderr
and returns 1.

No other CLI. No INI. No tests/ tree.
