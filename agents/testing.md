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
| Map / tileset | Farm: green field, yellow lane, grey walls and roofs, eight blue soldiers at the gate, no TMX enemy stamps; after the first logic tick eight red enemies may stand in the west field, roofs covering; grass shows through wall gaps. Roster A white, B–H grey. Row 21 `READY` while playing, `HELD THE FARM` / `FARM LOST` on outcome. Smoke stays PLAYING |
| `tiles.txt` / `missions.txt` / `properties.txt` / `scripts/*.txt` / TMX / PNG | Touch the file, `cmake --build`; `gen_sdl` should rerun |
| Cursor | Unshifted WASD and arrows; clamp at playfield edges (not into rows 20–24). On a soldier, roster A turns yellow. SHIFT+WASD must **not** walk |
| Stick | Plug/unplug updates `JOY YES/NO` on row 24. A desk pad must not print `LINE` until it moves. After first dpad/stick move: `LINE`, WASD become letters, unshifted M talks. Unplug returns to `WASD` |
| Wizard | Keyboard: SHIFT+M, RETURN → row 21 `MOVE A AT … FORCE 10`, last-order on A. SHIFT+A parses ATTACK (no VERB flash). SHIFT+K parses KILL. SHIFT+R parses RETREAT. SHIFT+S / SHIFT+J parse SPLIT / JOIN (no VERB flash). Unshifted `.` in WHO after a combat verb tags the cursor man. DEL pops (and clears a `.` snapshot). Esc/Q still quit |
| Stepper | After SHIFT+M RETURN, men walk toward a rank around WHERE (~15 Hz) and stop. A NE dest is NE-NE-NE, not E-N-E-N; both-wall corners stay blocked and zipper. Glyphs turn with the step (8-way) except `R`, which overwrites to `section_front` (threat, opposite of travel). Halt stops in place. Roofs are walkable. Walls/barriers block. Two-wide gap: opposite traffic keep-right. Long open front (split yard): each man takes the nearest seam cell, no NO PATH. Sidestep is right-hand then re-aim, not march along the hedge. Smoke: eight player stamps unmoved, eight enemies may first-step in room 4, outcome playing |
| Combat | SHIFT+D: they lock to farm holes. Wave 1 walks in from room 4 (`ATTACK` room 1 force 10); men drop. Wave 2 hunkers in room 2 after the stagger, `R` room 3 (west walk, **east** glyphs, hi pole, not x=6 lo chips), then `M` exit-west (despawn or die). Wave 3 `D` room 3: men running 4→3 take **moving** (+1 LSR), not prone+moving; room-2 fire should wound them before they hole up. Win needs a living player body in room 3. Hurt tint on the target; men vanish at hp 0. Occupying houses last longer than dirt. SHIFT+M sprints (faster than `A`/`D`), silent on the way, fights at dest; a dest cover chip is claimed. SHIFT+H holds and shoots. `.` WHO: `M .` / `D .` onto a wall chip places that man without a letter peel. `S B` on a man peels him; `J B A` joins. `S B` on dirt beeps. `D A` after a wall nudge recalls him. `K` concentrates (three-of-four due on the named cell; smear when quiet). Force 3 `A`/`D` HALTs after the first death; force 10 does not. Enemy never concentrates. Script `A` does not steal houses at spawn; contact-start may assign leftover holes |
| Cover | SHIFT+D or SHIFT+A: live pole plus neutrals. Soft neutrals face the axis-snapped walk (EW room, `D` travel east → face E). Verb `R` faces **opposite** of travel (retreat west → front east). In dest, a death on `D` keeps the occupied pole (farm wave 2 stays looking east until `R`). Hard neutrals always face the painted cardinal (farm houses: `cover_hard_w`). All-neutral EW room no longer defaults to south. Wrong exclusive pole stays empty. `M` still walks to a rank around WHERE. Halt does not reshuffle holes |
| Trace | `FORCE_TRACE=1 ./build/src/sdl/force 2> /tmp/force_move.log` — each think: slot, cell, region, dest, verb, cover, aim, then step/cross. Director lines too. `FORCE_SCRIPT=1` is director-only (no unit spam): `script t=N beat/wait/-> /watch/order/spawn/cover`. `wait NAME` arms a `->`; `-> NAME` is the fire. `cover … front E dest 2` is assign (R farm fallback should be front E, dest room 2). |
| F11 | Fullscreen toggle |
| F3 | Reloads the current mission: player stamps back, script at beat 0, cursor centred, wizard idle, outcome PLAYING. Stick latch and fullscreen stay. Works after win/lose. Smoke does not press F3. |
| Esc / Q | Clean shutdown (no leak reports required; `force_host_shutdown` must run) |
| 2-wide pixels | A tile whose even/odd PNG pixels differ must fail `gen_sdl` |

Interactive (`./build/src/sdl/force`, no args): 3-act Hold the Farm.
`D` the houses, wave 1 walks in, wave 2 hunkers then runs west, wave 3
dies in room 3. Win (`HELD THE FARM`) needs that letter gone and a
player body in room 3. Lose (`FARM LOST`) if the player bank hits 0.
Overrun: five player men in room 4 moves later spawns to room 2.

1. Smoke: exit 0, player unmoved, enemies may first-step, row 21 `READY`, outcome playing.
2. `D` still claims farm holes. They walk in; leftover holes may fill on contact-start.
3. Clear room 3 with a living man there → yellow `HELD THE FARM`. Wipe → light-red `FARM LOST`.
