# Input

Keyboard, first SDL gamepad, or first raw joystick → one cell step per
accepted frame. Source: `src/sdl/sdl/input.*`. Types: `force_input` in
`src/sdl/core/types.h`.

Host reset/poll wiring: [`host.md`](host.md). Cursor consume: [`game.md`](game.md).

## `force_input` (one frame)

| Field | Set by |
|-------|--------|
| `cursor_dx` / `cursor_dy` | −1, 0, or +1 after clamp and repeat gate |
| `quit` | Host event switch (`Esc` / `Q` / window close) |
| `toggle_fullscreen` | Host event switch (`F11`) |
| `joy_present` | Pad or raw joy pointer is non-NULL |

`force_input_reset` zeroes all of the above. Host calls it at the start of
every pump. Do not accumulate in the struct across frames.

## Directions

OR of:

- Keyboard: arrows and WASD (`SDL_GetKeyboardState`). A/D and left/right
  both feed X; W/S and up/down both feed Y.
- Gamepad (if `pad != NULL`): dpad plus left stick past deadzone **16000**.
- Else raw joystick: hat 0 (if any) plus axes 0/1 with the same deadzone.

Opposite keys cancel to zero, then `clamp_dir` folds anything outside
[−1, 1]. Diagonal is allowed (both axes non-zero).

Gamepad wins over raw joystick: if a pad is open, the joy branch is not
read. Fire button is **not** mapped. There is no mouse path.

## Repeat

Static state in `force_input_poll` (not on the host, not on the game):

| Symbol | Value | Meaning |
|--------|-------|---------|
| `REPEAT_DELAY` | 14 | Frames held before auto-repeat starts |
| `REPEAT_RATE` | 4 | Frames between repeats after the delay |
| `STICK_DEAD` | 16000 | Analog deadzone |

First frame of a direction (or a change of direction) fires immediately.
Release (`dx==0 && dy==0`) clears `hold`. While held on the same vector,
`cursor_dx/dy` are zero except on the delay/rate cadence.

Because `hold` / `last_dx` / `last_dy` are `static` inside the poll
function, they survive host teardown and would be shared if a second host
ever polled. One host is the current product.

## What is not bound

No command-line keys (A/D/M/H/K/…), no Tab-to-line, no Z overview, no
contact cycle. Those letters currently move the cursor (WASD). The four-slot
wizard in [`doc/FORCE_02_Command_Language_and_UI.md`](../doc/FORCE_02_Command_Language_and_UI.md)
is not in this TU.
