# Input

Keyboard, first SDL gamepad, or first raw joystick → one cell step per
accepted frame, plus one edge-triggered command token. Source:
`src/sdl/sdl/input.*`. Types: `force_input` in `src/sdl/core/types.h`.

Host reset/poll wiring: [`host.md`](host.md). Cursor and wizard consume:
[`game.md`](game.md).

## `force_input` (one frame)

| Field | Set by |
|-------|--------|
| `cursor_dx` / `cursor_dy` | −1, 0, or +1 after clamp and repeat gate |
| `quit` | Host event switch (window close) |
| `toggle_fullscreen` | Host event switch (`F11`) |
| `restart` | Host event switch (`F3`) |
| `joy_present` | Pad or raw joy pointer is non-NULL |
| `stick_latched` | Stick-play latch (not presence) |
| `cmd_kind` | `enum force_cmd_kind` — at most one token this frame |
| `cmd_value` | Letter 0–25 or digit 0–9; else 0 |

`force_input_reset` zeroes all of the above (`cmd_kind = FORCE_CMD_NONE`,
`stick_latched = false`). Host calls it at the start of every pump. Do not
accumulate in the struct across frames. Poll fills `stick_latched` from a
static; the reset-false is overwritten the same pump.

## Mapping

Two mappings. The switch is the latch, not `joy_present`.

| | Keyboard play (`stick_latched == false`) | Stick play (`true`) |
| --- | --- | --- |
| Cursor | unshifted WASD + arrows + stick/dpad/hat (a stick move also **sets** the latch) | stick/dpad/hat + **arrows only** |
| A–Z into the hole | SHIFT+letter, edge | unshifted **or** SHIFT+letter, edge |
| Unshifted WASD | cursor | letters |
| SHIFT+WASD | letter only — no cursor step | letter only — no cursor step |
| Digits / comma / space / period / RETURN / DEL / Esc | scancodes (SHIFT+1 is still 1) | same (period still talks; Esc cancels) |
| Arrows | always cursor | always cursor |

WASD is added to the keyboard vector only if `!stick_latched && !shift`.

## Stick latch

Not `joy_present`. A pad on the desk must not steal WASD.

- Cold start: keyboard play.
- First real stick/pad vector (`sdx`/`sdy` non-zero before OR with the
  keyboard vector, analog past **16000**, or dpad, or hat) latches.
- Unplug (both pointers NULL) **or pad/joy identity change** clears.
  Host unplug is `close_sticks` then `open_first_stick` in the same pump,
  so poll tracks `prev_pad` / `prev_joy` rather than waiting for a NULL
  frame. A replacement device waits for **its** move.
- Keyboard WASD never sets the latch. Do not latch on the summed `dx/dy`
  or on the cursor `fire` bit.
- Latch does not clear when the stick recentres.

Row 24 shows `WASD` / `LINE` from this bit (`LINE` = unshifted A is a
letter). `JOY YES` is presence only.

## Directions

Two vectors, then the existing hold gate:

- Keyboard: arrows always; WASD only if `!stick_latched && !shift`.
- Gamepad (if `pad != NULL`): dpad plus left stick past deadzone **16000**.
- Else raw joystick: hat 0 (if any) plus axes 0/1 with the same deadzone.

Opposite keys cancel to zero, then `clamp_dir` folds anything outside
[−1, 1]. Diagonal is allowed (both axes non-zero).

Gamepad wins over raw joystick: if a pad is open, the joy branch is not
read. Fire button is **not** mapped. There is no mouse path. Tab is not
bound.

## Command token

Edge-triggered. One token per press, at most one per frame. **Not** the
cursor hold gate. First edge in this order wins: **Esc**, RETURN / KP_ENTER, DEL /
BACKSPACE, comma, space, **period**, number-row 0–9 then keypad 0–9, A–Z. A letter is
emitted only if `stick_latched || shift`. Period talks unshifted (not a letter;
no pad glyph). Digits are named scancodes (`SDL_SCANCODE_0` plus `1`–`9`;
`SCANCODE_0+i` is not 0–9 because row `1`–`9` are 30–38 and `0` is 39).

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

Statics: `hold` / `last_dx` / `last_dy` / `stick_latched` / `prev_pad` /
`prev_joy` / `prev_letters` / `prev_digits` / `prev_misc`. They survive
host teardown and would be shared if a second host ever polled. One host
is the current product.

## What is not bound

No Tab-to-line. No F-key command macros (`F3` restarts the session, `F11`
toggles fullscreen; both are host events, not wizard tokens). `B` `C`
`X` `E` are letters this TU already emits; the wizard treats them as camera
/ cycle instants in IDLE and SHOW. `Z` is emitted and ignored. `A` is a
letter, not a mapped verb here. The wizard grammar lives in
`game/command.c`, not this TU.
