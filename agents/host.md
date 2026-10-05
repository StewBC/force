# SDL host

Window, framebuffer blit, fullscreen, and stick hotplug. Source:
`src/sdl/sdl/host.*`. Input poll is a separate TU: [`input.md`](input.md).

`force_host` is opaque. Game code never sees SDL types.

## Init / shutdown

`force_host_init` allocates the host, `SDL_Init(VIDEO | JOYSTICK | GAMEPAD)`,
then `SDL_CreateWindowAndRenderer("FORCE", 1280×800, RESIZABLE |
HIGH_PIXEL_DENSITY)`.

Presentation:

- VSync on (`SDL_SetRenderVSync(..., 1)`).
- Logical size 320×200, `SDL_LOGICAL_PRESENTATION_INTEGER_SCALE`.
- Streaming texture `SDL_PIXELFORMAT_XRGB8888`, `SDL_SCALEMODE_NEAREST`.
- Minimum window size is native 320×200.

Homebrew SDL3 on Apple Silicon is on the CMake prefix path
(`/opt/homebrew`) from the root `CMakeLists.txt`.

`force_host_shutdown` closes sticks, destroys texture/renderer/window,
`SDL_Quit`, frees the host. NULL host is a no-op.

## Frame pump

`force_host_pump` returns false when the window should close.

1. `force_input_reset` (every field, every frame).
2. Drain `SDL_PollEvent`.
3. Apply fullscreen toggle if requested.
4. If quit, return false (input poll is skipped).
5. `force_input_poll` with the current pad/joy pointers.
6. Return true.

Quit: `SDL_EVENT_QUIT` (window chrome). No quit key. Esc is a wizard
token (`FORCE_CMD_ESC`, cancels the draft). Fullscreen: non-repeat
`F11` flips `host->fullscreen` and `SDL_SetWindowFullscreen`. Restart:
non-repeat `F3` sets `in->restart`; the game reloads the current mission
and does not write the campaign file (see [`game.md`](game.md)).
Non-repeat `F8` sets `in->f8`. The menu uses that edge. Play ignores it.
Quit skips `force_input_poll`. Stick latch lives in poll, not on the host; hotplug still
`close_sticks` then `open_first_stick` in the same pump.

`force_host_sync_input` polls once into a discarded `force_input`. `main`
calls it after the title key so a held key is not a new menu edge. It does
not present.

Key repeat events are ignored in the event switch. Cursor repeat is handled
in `input.c` from keyboard *state*, not key-down events.

## Present

`force_host_present(host, pixels)` uploads a 320×200 XRGB8888 buffer the
game already composed (`force_game.pixels`). Host does not rasterize.

1. `SDL_UpdateTexture` (pitch = `FORCE_FB_W * 4`).
2. Clear black, `SDL_RenderTexture` full logical dest, `SDL_RenderPresent`.

No letterbox colour other than the clear. Integer scale keeps pixels square.

## Sticks

At most one device: a gamepad if one exists, else a raw joystick.

| Event | Action |
|-------|--------|
| Init | `open_first_stick` |
| `GAMEPAD_ADDED` | Open it if no pad; drop a raw joy if one was open |
| `GAMEPAD_REMOVED` | If it was ours: close, then reopen first remaining |
| `JOYSTICK_ADDED` | `open_first_stick` (no-op if a pad or joy is already open) |
| `JOYSTICK_REMOVED` | If it was ours: close, then reopen first remaining |

`joy_present` on `force_input` is `(pad != NULL || joy != NULL)` after poll,
not "a stick is currently held".
