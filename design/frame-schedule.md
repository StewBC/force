# Frame schedule — one world_tick on three video rasters

| Field | Value |
| --- | --- |
| Author | FORCE design session |
| Date | 2026-09-23 |
| Status | **landed** |
| Last worked on | 2026-09-24 |
| Repo path | [`frame-schedule.md`](frame-schedule.md) |
| Source | `src/c64/force.asm`, `src/c64/game.asm`, `src/c64/irq.asm`, `src/c64/equ.inc`, `src/c64/draw.asm`, `src/sdl/game/world.h` |
| Binary as it is | [`../agents/c64-port.md`](../agents/c64-port.md) |

One game frame is one `world_tick`, then the draw. The draw starts when the beam leaves the map. Three video frames is the period. Two would hold the fight that was measured. Three stays, because a scroll repaint costs more than that draw and the spare is kept.

---

## The loop

`main` in `src/c64/force.asm`:

```asm
loop:
    jsr input_poll
    jsr game_tick       ; world_tick, every pass
    jsr wait_ui
    jsr draw_all
    jmp loop
```

`game_tick` always calls `world_tick`. `wait_ui` then spins until line 210 has fired `FRAME_RASTERS` (3) times since the previous draw. Line 210 is the IRQ that switches rows 20–24 from the multicolour map to normal text. That is the bottom of the map.

The draw starts on that edge. The UI barely changes, so beginning while the beam is on those rows is acceptable. The map is the picture that tears if it is written while the beam is still on it, and a scroll would show that. The draw is supposed to finish before line 51 brings the beam back to the top of the map. The next `world_tick` starts as soon as `draw_all` returns, still in that third frame.

An edge that is already set when the logic returns is dropped. The beam has moved on, so painting then would write the map under the beam. The draw waits for the next line 210.

`ui_edge` is `$FB` and `ui_count` is `$FC`, both zero page. The line-210 arm sets the edge and increments the count, saturating at 3. Line 251 does not gate the frame. It restores the multicolour field in the bottom border, after the grey bar. The port does not read `$02A6`. NTSC and PAL both use three rasters.

`input_poll` runs once per logic frame, at the top of the loop. The sprite cursor is placed in `draw_all`. Key repeat (delay 14, rate 4) therefore counts logic frames.

SDL keeps the same count. `FORCE_LOGIC_PERIOD` is 3. `game.c` ticks when `frames % 3 == 0` before the increment, so frames 0 and 3 tick and frames 1 and 2 do not. The host stays on vsync. There is no millisecond timer. Tick constants (`MOVE_WAIT`, `FIRE_WAIT`, grenade ttl, and the rest) are unchanged.

## What was measured

PAL, c64m, 2026-09-24, room 2, enemy at map x 55, quiet men. `tools/c64_profile.py`.

| Piece | Cycles |
| --- | --- |
| Logic and the draw, excluding the spin | 28,506 |
| Draw inside that | 5,244 |
| Spin until line 210 | 25,403 |
| One pass, input to the next input | 53,909 |

`draw_all` was entered at raster 213 on four stops. The spin is the spare in the three-frame slot. A heavier fight spends it before the draw moves. Past it, the logic is still running at the UI line and the draw waits for the next one.

## Why it stays at three

This fight fits in two video frames. One frame does not hold the logic. Two do: the draw is about 5,200 cycles at the UI line, the logic is about 23,300, and the rest of those two frames is a few thousand cycles of spin.

It stays at three. A scroll has to repaint the field, which costs more than this dirty draw, and the extra frame is there for that and for whatever else shows up.
