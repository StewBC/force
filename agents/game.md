# Game (SDL)

Cursor on a camera window into the active map, four-slot command wizard.
Source: `src/sdl/game/game.*`, `src/sdl/game/command.*`,
`src/sdl/game/world.{h,c}`. Loop glue: `src/sdl/main.c`. Map data:
[`assets.md`](assets.md). Input mapping: [`input.md`](input.md).
Intel design: [`../design/phase-8-intel-camera.md`](../design/phase-8-intel-camera.md)
(camera / `C`/`E` landed; scaled `Z` and fog hide stripped).

Instant rifles on the 32-slot pool. Two-pass logic tick: all due shooters
fire, then deaths / relead / recount / cover reassign, then step. HP is a
byte, spawn 16; `count` stays occupancy 1. Closest smear (other bank,
Chebyshev under 10, skip `hp == 0`). Walls do not stop a rifle. The sight
ray (`los_clear`) stays in `world.c` and is not called. Damage is a posture
number: on his assigned hole, grade 3 takes 1 from any side, grade 2 takes
2 and grade 1 takes 3 only from the side that hole watches, and any other
side takes 10. Off a hole, `M` still on the way takes 5, `A`/`D`/`R` still
on the way takes 7, and anyone stopped takes 10. Dist 1–4 keeps that
number. Dist 5–9 halves it, so a house takes 0. Dist 10–15 is not a
target, and neither is 16 or beyond. A shot that lands starts `fire_wait`
8. A miss or an empty look does not.
Grenades are not a verb. Mission script stock + cooldown per bank
(`player_grenades` / `player_grenade_wait`, enemy pair). A weapons-free
infantry man throws when the bank has remaining, the side wait is 0, the
nearest other-bank body is standing on his assigned cover chip at
Chebyshev 2–5, and the Chebyshev-2 blast disk is free of friendlies
(walls occlude splash; the landing cell always hits). Damage 8, no posture
reduction. Thrower resumes rifle `fire_wait`. Colour-plane fill lerps toward hurt red
for 4 logic ticks on walkable cells in the disk; walls and roofs skip.
`M` sprints (`move_wait` 4), silent while walking,
weapons-free at dest, occupy-if-chip. `H`
weapons-free, no step. `A` / `D` / `R` weapons-free and walk (hole or 3×3).
`K` holds and concentrates: first 3 of every 4 due rifles on the named
cell if a living other-bank body sits there inside 9; the 4th smears;
out of range or nobody there smears.
Force nibble vs `section_order_str` vs live strength breaks the letter
to `H` (`FLAG_BREAKING`). Force 10 never. `M` walks to a 3×3 rank around
WHERE. `D`, `A`, and `R` claim cover in the room of WHERE (not the room the
stacks occupy now) and walk there; no hole → march to WHERE and prone. Cover is
directional: `pick_best` walks one live advancing list (this letter’s rear
pole plus neutrals, ≤ 12), not every chip in the room. Wrong-face holes
are not leftover grade-2. `D`/`A` front is travel toward WHERE while the lead is still
outside the dest room. Once they occupy exclusive holes in dest,
death reassign keeps that pole (does not snap to the WHERE cell).
`R` inverts travel (walk backwards, keep looking at the threat). Glyphs face the last
step (goodguys 0–7 N-clockwise including diagonals) except `R`, which
overwrites to `section_front` before draw; on a hole, look is derived
(opposite of an exclusive pole; soft neutrals use section front
snapped to the room axis; hard neutrals always that cardinal).
Occupancy is the 32-slot unit pool on
`force_world`. The A–H roster is occupancy chrome (white / grey / yellow).
Farm has no enemy actor stamps. `farm.tmx` is 80×40. `farm_mission` is the
NE play rect `40,0,40,20` (quadrant 2, today’s farm). NW/SW/SE are grass
(room colours 5–7) and sit outside that rect. `play_*` is the mission
rect and does not move. The view is 40×20 (`win_w` / `win_h`, smaller
when the rect is smaller). Edge-pan, `F`, and `B` keep `win_x` / `win_y`
inside `play_*`. Farm’s rect is already the view, so the camera does
not scroll. A typed WHERE is clamped into `play_*`. `exit-*` and
despawn use the play-rect edge (farm west = x=40).
`farm_mission` binds `force_script_farm`
(Hold the Farm, 3-act director). Load skips enemy stamps when
`mission->script != NULL` and does not seed section-8 `ATTACK`. Wave 1
patrol: spawn 8 A in spawn_room, `ATTACK` room 1 force 10, approach 1 W.
Wave 2 contact: stagger 8 B, `D` room 2 force 5 after `job idle`,
`R room 3` force 4 (west walk, east glyphs, hi pole), `M` exit-west
force 10 (despawn at the window west seam or die). Wave 3 last stand: 8 C `D` room 3 force 10. Win: C gone and a living player body in
room 3. Lose: player bank strength 0 at any time. Overrun: five player
men in room 4 sets `spawn_room` to 2 once. Script `A` does not steal
houses; `FLAG_CONTACT` latches `FLAG_COVER_ASSIGN` when they enter the
dest room. Hold the Farm is playable.

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
    uint8_t cmd_dot;
    uint8_t cmd_unit;
    uint8_t cmd_x;
    uint8_t cmd_y;
    uint8_t cmd_force;
    uint8_t cmd_slot;
    uint8_t cmd_digits;
    uint8_t cmd_last_who;
    uint8_t cmd_flash;
    uint8_t cmd_nopath;
    uint8_t cam_prev_ok;
    uint8_t cam_prev_x, cam_prev_y, cam_prev_cx, cam_prev_cy;
    uint8_t cam_ttl;
    uint8_t cycle_kind;
    uint8_t cycle_room;
} force_game;
```

Parser + draft live on `force_game` (UI). Last-order stays world columns.
`force_game_init`: `mission = &force_missions[0]` (`farm_mission`),
`world = &force_world_bss`, `stick_latched = false`, then `session_reset`:
`force_world_load(world, mission)` before `field_w` / `field_h`, cursor at
the centre of that window, `frames = 0`, `force_command_init` (seeds
`cmd_last_who` from the first occupied player letter; farm → A). After load,
draw/clamp/field size read the world. `g->mission` is the chrome name only.
Units and sections live on that world, not inside `force_game`. `F3` runs
the same `session_reset` on the current `g->mission` (win/lose included).
Stick latch and fullscreen stay.

## Tick

0. Copy `joy_present` and `stick_latched`. If `in->restart`, `session_reset`
   and skip 1–4 this frame (no cursor step, no wizard token).
1. Decrement `cmd_flash` if > 0 (before feed, so a feed that sets 8 is
   red this draw and the next seven).
2. Add `in->cursor_dx/dy`. Past a screen edge pans `win_x` / `win_y`
   (clamped so the 40×20 view stays inside the mission rect `play_*`).
3. `force_command_feed` (may set `cmd_flash = 8`). Esc (`FORCE_CMD_ESC`)
   `draft_reset`s from any slot, including SHOW; idle is a no-op. IDLE/SHOW
   `B` restores prev camera; `C`/`X` cycle `room_heat`;
   `E` cycles `MARK`; SPACE snaps a cycle. `F` is a verb (skip WHO). `Z` is ignored.
4. If `(frames % FORCE_LOGIC_PERIOD) == 0` **before** increment:
   `force_world_tick` (consume → shoot rifles or grenades → deaths → script → if PLAYING:
   pulse → contact-start → consume → step → despawn → intel). Frozen outcome
   decrements `unit_fx` and returns. Pulse places the spawn-job batch
   (move_wait pattern; first pulse this tick). Contact-start latches
   `FLAG_CONTACT` | `FLAG_COVER_ASSIGN` on enemy `A` entering dest.
   Despawn: enemy bank + verb `MOVE` + WHERE on the **mission** edge +
   Chebyshev ≤ 1 frees the slot (relead/recount, no force-break).
   Player never auto-despawns. Intel pulse: `MARK`/`last_*` from living
   enemies, `room_heat--` (feeds `C`/`E`; draw does not hide).
   `cam_ttl` ticks down; 0 restores prev camera.
5. `frames += 1`.

Cursor moves before feed so RETURN in the same frame uses the new cell.
Parse `M` / `D` / `H` / `A` / `K` / `R` / `S` / `J` / `F`. Esc clears the draft.
`.` in WHO snapshots the
cursor unit (stay in letter; `force_unit_nudge`). `F` commits a camera snap
(optional FORCE duration), not a section order. One RETURN on a combat verb
commits remaining
defaults through `force_section_issue` onto `section_order_*` for WHO 0–7, including
`section_order_str`, and clears `FLAG_BREAKING` / `FLAG_CONTACT` and that letter’s
overrides. `A` and `R`
latch `FLAG_COVER_ASSIGN` like `D`. `K` does not touch cover flags (holes stay).
`M` sprints to a blob cell around WHERE, silent on the way, fights at dest;
`D`/`A`/`R` walk to
the claimed hole (else 3×3) and shoot; `H` / `K` do not step and do shoot.
Fronts: abutting rooms with walkable tiles are a crossing (closest cell on
a long seam; keep-right on a 2-wide gap). Painted portal chips remain for
doors through walls. Sidestep right, re-aim every think. Frame 0 of
`--smoke` is a logic tick: player verb NONE stays put; script may spawn
eight in room 4 and `ORDER A`; they may first-step; Chebyshev to the
farm lead is ≥ 16 so no shot; outcome stays PLAYING (wipe needs 8 dead
player men; win needs act 3). Disconnected dest →
`NO PATH`.

## Draw

`force_game_draw` fills `g->pixels` every frame. Playfield reads BSS
(`world->color`, `world->tiles`, `world->unit_*`) via `row_off[my] + mx`.

1. Clear `g->screen`, paint rows 20–24 (strip + host line),
   `force_screen_rasterize` into `g->pixels`.
2. Playfield rows 0–19: fill colour + stamp `tiles` for the camera window.
   If `force_grenade_fx_at`, lerp the fill 50% toward `0xFFCC3333` before
   the scenery stamp (walls/roofs skip). Then walk the 32 unit slots
   (skip `count == 0`; skip outside the window; stamp `unit_glyph`; if
   hurt nibble, lerp; re-stamp `tiles` so roofs cover). Do not rebuild a
   dense actors plane. Do not poke `world->color`. Draw does not hide
   rooms or enemies.
3. Cursor: yellow 1-pixel border; every 30 frames the cell fills yellow.

| Rows | Contents |
|------|----------|
| 0–19 | Camera window (colour + tiles + units + cursor) |
| 20–23 | Portable command strip: live wizard, talky line, map-cell `CURSOR xx,yy`, A–H roster |
| 24 | Host extra: `SDL  <mission>  JOY YES/NO  WASD\|LINE` |

Row 20: `VERB WHO WHERE FORCE`; current hole yellow (idle marks VERB),
flash light-red, SHOW all white. `force_command_paint` writes all four
tokens; the poster `puts` are gone. Row 21: `HELD THE FARM` (yellow) /
`FARM LOST` (light-red) when `script_outcome` is win/lose, else `CONTACT n`
/ `MARK n` while a cycle is armed, else `READY`
when idle, talky `MOVE A AT 10,20 FORCE 10` / `ATTACK A AT 10,20 FORCE 10` /
`KILL A AT 10,20 FORCE 10` / `FOCUS AT 10,20` while drafting / after commit. Smoke stays
PLAYING. Interactive names the outcome and freezes the board. Row 22 CURSOR is
**map** cells (`win_x + cursor_x`). Row 23 paints A–H from
`section_strength[0..7]`: white if that letter has men, light grey if
empty, yellow = implied WHO (`force_command_implied_who`, walk 32, first
slot wins) or the letter just typed (`cmd_who < 8`). Farm: A white, B–H
grey; cursor on a soldier turns A yellow. Room and property tables are in
the world and are not drawn. `M`/`D`/`A`/`R` walk; `H`/`K` hold. Cover is
claimed on `D`, `A`, and `R`.

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
