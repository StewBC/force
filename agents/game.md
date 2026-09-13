# Game (SDL)

Cursor on the active mission window, static command-strip chrome. Source:
`src/sdl/game/game.*`, `src/sdl/game/world.{h,c}`. Loop glue: `src/sdl/main.c`.
Map data: [`assets.md`](assets.md).

This is not the RTS sim. No orders, no sections as objects. Spawns on the
map are painted stamps, not a unit pool.

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
} force_game;
```

`force_game_init`: `mission = &force_missions[0]` (`farm_mission`),
`world = &force_world_bss`, `force_world_load(world, mission)` before
`field_w` / `field_h`, cursor at the centre of that window, `frames = 0`.
After load, draw/clamp/field size read the world. `g->mission` is the
chrome name only.

## Tick

Adds `in->cursor_dx/dy`, clamped to the world window (`win_w` / `win_h`,
capped at `FORCE_COLS` × `FORCE_FIELD_ROWS`). Copies `joy_present`, then
`frames += 1`.

## Draw

`force_game_draw` fills `g->pixels` every frame. Playfield reads BSS
(`world->color`, `world->tiles`, `world->spawn_*`) via `row_off[my] + mx`.

1. Clear `g->screen`, paint rows 20–24 (strip + host line),
   `force_screen_rasterize` into `g->pixels`.
2. Playfield rows 0–19: fill colour + stamp `tiles` for the world window,
   then walk the spawn list (stamp tile, re-stamp `tiles` so roofs cover).
   Skip spawns outside the window. Spawn stamps are O(spawns). Do not
   rebuild a dense actors plane.
3. Cursor: yellow 1-pixel border; every 30 frames the cell fills yellow.

| Rows | Contents |
|------|----------|
| 0–19 | Mission window (colour + tiles + spawn stamps + cursor) |
| 20–23 | Portable command strip: slot legend, `READY`, `CURSOR xx,yy`, A–H roster |
| 24 | Host extra: `SDL  <mission>  JOY YES/NO` |

Slot legend on row 20 is the intended language (`VERB   WHO   WHERE   FORCE`)
but nothing parses it. Row 21 is always `READY`. Row 23 is `A B C D E F G H`
in light grey (every letter empty; no section table yet). Room and property
tables are in the world and are not drawn.

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
