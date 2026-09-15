# Game (SDL)

Cursor on the active mission window, four-slot command wizard. Source:
`src/sdl/game/game.*`, `src/sdl/game/command.*`, `src/sdl/game/world.{h,c}`.
Loop glue: `src/sdl/main.c`. Map data: [`assets.md`](assets.md). Input
mapping: [`input.md`](input.md).

Instant rifles on the 32-slot pool. Two-pass logic tick: all due shooters
fire, then deaths / relead / recount / cover reassign, then step. HP is a
byte, spawn 16; `count` stays occupancy 1. Closest smear (other bank,
Chebyshev, LOS, skip `hp == 0`). Cover is stacked `LSR` on a 16-byte rifle
table; grade only when occupying the hole. `M` is silent transit. `H`
weapons-free, no step. `A` / `D` weapons-free and walk (hole or 3×3).
`K` holds and concentrates: first 3 of every 4 due rifles on the named
cell if a living other-bank body sits there with LOS; the 4th smears;
blocked LOS smears that shooter (cell is not quiet); no body → all smear.
Force nibble vs `section_order_str` vs live strength breaks the letter
to `H` (`FLAG_BREAKING`). Force 10 never. `M` walks to a 3×3 rank around
WHERE. `D` and `A` claim cover in the room of WHERE (not the room the
stacks occupy now) and walk there; no hole → march to WHERE and prone. Cover is
directional: `pick_best` walks one live advancing list (this letter’s rear
pole plus neutrals, ≤ 12), not every chip in the room. Wrong-face holes
are not leftover grade-2. Glyphs face the last cardinal step (goodguys
0–7 N-clockwise); on a hole, look is derived (opposite of an exclusive
pole; soft neutrals use section front snapped to the room axis; hard
neutrals always that cardinal). Occupancy is the 32-slot unit pool on
`force_world`. The A–H roster is occupancy chrome (white / grey / yellow).
Farm stamps enemy infantry in the west field; section 8 gets a standing
`A` at load (no `FLAG_COVER_ASSIGN`).

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
5. If `(frames % FORCE_LOGIC_PERIOD) == 0` **before** increment:
   `force_world_tick` (cover flags, shoot all, deaths, cover flags, step).
6. `frames += 1`.

Cursor moves before feed so RETURN in the same frame uses the new cell.
Parse `M` / `D` / `H` / `A` / `K`. One RETURN commits remaining defaults onto
`section_order_*` for WHO 0–7, including `section_order_str`, and clears
`FLAG_BREAKING`. `A` latches `FLAG_COVER_ASSIGN` like `D`. `K` does not
touch cover flags (holes stay). `M` walks to a blob cell around WHERE and
does not shoot; `D`/`A` walk to the claimed hole (else 3×3) and shoot;
`H` / `K` do not step and do shoot. Fronts: abutting rooms
with walkable tiles are a crossing (closest cell on a long seam; keep-right
on a 2-wide gap). Painted portal chips remain for doors through walls.
Sidestep right, re-aim every think. Frame 0 of `--smoke` is a logic tick:
player verb NONE stays put; seeded enemy `A` may first-step. Disconnected
dest → `NO PATH`.

## Draw

`force_game_draw` fills `g->pixels` every frame. Playfield reads BSS
(`world->color`, `world->tiles`, `world->unit_*`) via `row_off[my] + mx`.

1. Clear `g->screen`, paint rows 20–24 (strip + host line),
   `force_screen_rasterize` into `g->pixels`.
2. Playfield rows 0–19: fill colour + stamp `tiles` for the world window,
   then walk the 32 unit slots (skip `count == 0`; skip outside the window;
   stamp `unit_glyph`; if hurt nibble, lerp opaque glyph pixels 50% toward
   `0xFFCC3333`; re-stamp `tiles` so roofs cover). Do not rebuild a
   dense actors plane. Do not poke `world->color`.
3. Cursor: yellow 1-pixel border; every 30 frames the cell fills yellow.

| Rows | Contents |
|------|----------|
| 0–19 | Mission window (colour + tiles + units + cursor) |
| 20–23 | Portable command strip: live wizard, talky line, map-cell `CURSOR xx,yy`, A–H roster |
| 24 | Host extra: `SDL  <mission>  JOY YES/NO  WASD\|LINE` |

Row 20: `VERB WHO WHERE FORCE`; current hole yellow (idle marks VERB),
flash light-red, SHOW all white. `force_command_paint` writes all four
tokens; the poster `puts` are gone. Row 21: `READY` when idle, talky
`MOVE A AT 10,20 FORCE 10` / `ATTACK A AT 10,20 FORCE 10` /
`KILL A AT 10,20 FORCE 10` while drafting / after commit. Row 22 CURSOR is
**map** cells (`win_x + cursor_x`). Row 23 paints A–H from
`section_strength[0..7]`: white if that letter has men, light grey if
empty, yellow = implied WHO (`force_command_implied_who`, walk 32, first
slot wins) or the letter just typed (`cmd_who < 8`). Farm: A white, B–H
grey; cursor on a soldier turns A yellow. Room and property tables are in
the world and are not drawn. `M`/`D`/`A` walk; `H`/`K` hold. Cover is
claimed on `D` and `A`.

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
