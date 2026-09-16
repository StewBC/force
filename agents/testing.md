# Build and verification

There is no ctest suite. The gate is: configure, build, `--smoke`.

## Gate

From the **force repo root**:

```bash
cmake -B build -S . -DCMAKE_BUILD_TYPE=Debug
cmake --build build -j
./build/src/sdl/force --smoke
```

Expect a window that opens, paints the farm map plus the command strip, and
exits 0. Init failure is stderr `FORCE: failed to open an SDL window` and
exit 1. A Python or TMX error fails the **build** (`gen_sdl: ...` on stderr).

Interactive: `./build/src/sdl/force` (no args). Close with Esc, Q, or the
window chrome.

Root `CMakeLists.txt` is `project(force)` (CMake **3.20**, C **11**, extensions
off). It `add_subdirectory(src/sdl)`. Do not configure `-S src/sdl`.

The first build (and any later dirty `assets/` or `tools/gen_sdl.py`) runs
Python before compiling `generated/force_data.c`.

## Dependencies

`find_package(SDL3 REQUIRED CONFIG)`.
`find_package(Python3 REQUIRED COMPONENTS Interpreter)` — stdlib only; no
Pillow. On Apple Silicon, `/opt/homebrew` is appended to `CMAKE_PREFIX_PATH`
when that directory exists.

Warnings: `-Wall -Wextra -Wpedantic` (non-MSVC). `SDL3::SDL3main` is linked
when the target exists.

`CMAKE_EXPORT_COMPILE_COMMANDS` is on at the root.

## Smoke contract

`src/sdl/main.c`: if `argc > 1` and `argv[1]` is exactly `--smoke`, the loop
body runs **once** (pump, tick, draw, present) then breaks. That still
requires a working display; it is not headless.

There are no unit tests for font bits, rasterize, clamp, input repeat, or
the Python compiler.

## What a change should re-check by hand

| Change | Check |
|--------|-------|
| Screen geometry / scale | Window is 1280×800 default; resize stays integer-scaled; min size 320×200 |
| Map / tileset | Farm: green field, yellow lane, grey walls and roofs, eight blue soldiers at the gate, **no** red enemy stamps in the west field, roofs covering; grass shows through wall gaps. Roster A white, B–H grey. Row 21 `READY`; outcome PLAYING |
| `tiles.txt` / `missions.txt` / `properties.txt` / `scripts/*.txt` / TMX / PNG | Touch the file, `cmake --build`; `gen_sdl` should rerun |
| Cursor | Unshifted WASD and arrows; clamp at playfield edges (not into rows 20–24). On a soldier, roster A turns yellow. SHIFT+WASD must **not** walk |
| Stick | Plug/unplug updates `JOY YES/NO` on row 24. A desk pad must not print `LINE` until it moves. After first dpad/stick move: `LINE`, WASD become letters, unshifted M talks. Unplug returns to `WASD` |
| Wizard | Keyboard: SHIFT+M, RETURN → row 21 `MOVE A AT … FORCE 10`, last-order on A. SHIFT+A parses ATTACK (no VERB flash). SHIFT+K parses KILL. DEL pops. Esc/Q still quit |
| Stepper | After SHIFT+M RETURN, men walk toward a rank around WHERE (4-connected, ~15 Hz) and stop. Glyphs turn with the step. Halt stops in place. Roofs are walkable. Walls/barriers block. Two-wide gap: opposite traffic keep-right. Long open front (split yard): each man takes the nearest seam cell, no NO PATH. Sidestep is right-hand then re-aim, not march along the hedge. Smoke: eight player stamps unmoved, no enemies, outcome playing |
| Combat | SHIFT+D: they lock to farm holes. No enemies this PR (quiet farm; you can still `D` around). Hurt tint on the target; men vanish at hp 0. Occupying houses last longer than dirt. SHIFT+M goes silent. SHIFT+H holds and shoots. `K` concentrates (three-of-four due on the named cell; smear when quiet). Force 3 `A`/`D` HALTs after the first death; force 10 does not. Enemy never concentrates |
| Cover | SHIFT+D or SHIFT+A: live pole plus neutrals. Soft neutrals face the axis-snapped walk (EW room, retreat east → face E). Hard neutrals always face the painted cardinal (farm houses: `cover_hard_w`). All-neutral EW room no longer defaults to south. Wrong exclusive pole stays empty. `M` still walks to a rank around WHERE. Halt does not reshuffle holes |
| Trace | `FORCE_TRACE=1 ./build/src/sdl/force 2> /tmp/force_move.log` — each think: slot, cell, region, dest, verb, cover, aim, then step/cross |
| F11 | Fullscreen toggle |
| Esc / Q | Clean shutdown (no leak reports required; `force_host_shutdown` must run) |
| 2-wide pixels | A tile whose even/odd PNG pixels differ must fail `gen_sdl` |

Interactive PR1 (`./build/src/sdl/force`, no args) is a silent farm: eight
player men, verb NONE, no waves. You can still `D` the houses. Worse than
Phase 6 as a firefight, on purpose.

1. Smoke: exit 0, player unmoved, no enemies, row 21 `READY`, outcome playing.
2. `D` still claims farm holes. No seeded `A` in the west field.
