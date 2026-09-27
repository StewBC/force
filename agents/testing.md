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

Interactive: `./build/src/sdl/force` (no args). Close with the
window chrome.

Root `CMakeLists.txt` is `project(force)` (CMake **3.20**, C **11**, extensions
off). It `add_subdirectory(src/sdl)` and `src/c64`. Do not configure `-S src/sdl`.

The C64 target `force_c64` writes `build/force.prg`. It is not the smoke gate
and is not yet a playable Hold the Farm. Assemble by hand with
`../machines/build/am65 -i src/c64/force.asm -o build/force.prg --prg`
from `src/c64` after `python3 tools/gen_title.py` and `python3 tools/gen_c64.py`.

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
requires a working display; it is not headless. Smoke does not show the
title splash. An interactive launch shows it until a key.

There are no unit tests for font bits, rasterize, clamp, input repeat, or
the Python compiler.

## What a change should re-check by hand

| Change | Check |
|--------|-------|
| Screen geometry / scale | Window is 1280×800 default; resize stays integer-scaled; min size 320×200 |
| Map / tileset | Farm: 80×40 map, mission rect NE `40,0,40,20` (today’s farm, no scroll). Green field, yellow lane, grey walls and roofs, six blue soldiers at the gate, no TMX enemy stamps; after the first logic tick eight red enemies may stand in the west field, roofs covering; grass shows through wall gaps. Other three quadrants are grass and are not on screen. Roster A white, B–H grey. Row 21 `READY` while playing, `SUCCESS` / `DEFEAT` on outcome. Smoke stays PLAYING |
| `tiles.txt` / `missions.txt` / `properties.txt` / `scripts/*.txt` / TMX / PNG | Touch the file, `cmake --build`; `gen_sdl` should rerun |
| Cursor | Unshifted WASD and arrows; at a playfield edge the camera pans only while the mission rect is larger than the 40×20 view (farm does not pan). The cursor does not enter rows 20–24. On a soldier, roster A turns yellow. SHIFT+WASD must **not** walk |
| Stick | Plug/unplug updates `JOY YES/NO` on row 24. A desk pad must not print `LINE` until it moves. After first dpad/stick move: `LINE`, WASD become letters, unshifted M talks. Unplug returns to `WASD` |
| Wizard | Keyboard: SHIFT+M, RETURN → row 21 `MOVE A AT … FORCE 10`, last-order on A. SHIFT+A parses ATTACK (no VERB flash). SHIFT+K parses KILL. SHIFT+R parses RETREAT. SHIFT+S / SHIFT+J parse SPLIT / JOIN (no VERB flash). SHIFT+F parses FOCUS (skip WHO; RETURN uses cursor cell). SHIFT+B previous camera. SHIFT+C / SHIFT+E cycle CONTACT / MARK; SPACE snaps. SHIFT+Z is unbound. Unshifted `.` in WHO after a combat verb tags the cursor man. DEL pops (and clears a `.` snapshot). Esc cancels the whole draft from any slot (including SHOW) back to `READY`. Idle Esc is a no-op |
| Stepper | After SHIFT+M RETURN, men walk toward a rank around WHERE (one step every third video frame) and stop. A NE dest is NE-NE-NE, not E-N-E-N; both-wall corners stay blocked and zipper. Glyphs turn with the step (8-way) except `R`, which overwrites to `section_front` (threat, opposite of travel). Halt stops in place. Roofs are walkable. Walls/barriers block. Two-wide gap: opposite traffic keep-right. Long open front (split yard): each man takes the nearest seam cell, no NO PATH. Sidestep is right-hand then re-aim, not march along the hedge. Smoke: six player stamps unmoved, eight enemies may first-step in room 4, outcome playing |
| Combat | SHIFT+D: they lock to farm holes. Wave 1 walks in from room 4 (`ATTACK` room 1 force 10); men drop. Wave 2 hunkers in room 2 after the stagger, `R` room 3 (west walk, **east** glyphs, hi pole, not x=6 lo chips), then `M` exit-west (despawn at the mission west edge `x=40` or die). Wave 3 `D` room 3: men walking 4→3 take 7, not the hole number; room-2 fire wounds them before they hole up. Win needs a living player body in room 3. Hurt tint on the target; men vanish at hp 0. A house takes 1 from any side. A grade-2 hole takes 2 from the side it watches and 10 from any other side. Sprint takes 5, a walk takes 7, a man stopped off a hole takes 10. Those numbers are for 1–4 cells. At 5–9 they halve, so a house takes 0. At 10 and beyond he is not a target. Rifles hit through walls inside 9. From the x=62 houses, room 3 is out of rifle range and the west edge of room 2 is the half-damage band. A man on a chip at Chebyshev 2–5 draws a pineapple; the ground fill flashes red on the splash disk and stops at the wall; stock ticks down (farm player 20 wait 50, enemy 5 wait 100). Open-yard rifles do not spend grenades. SHIFT+M sprints (faster than `A`/`D`), silent on the way, fights at dest; a dest cover chip is claimed. SHIFT+H holds and shoots. `.` WHO: `M .` / `D .` onto a wall chip places that man without a letter peel. `S B` on a man peels him; `J B A` joins. `S B` on dirt beeps. `D A` after a wall nudge recalls him. `K` concentrates (three-of-four due on the named cell when a man is there inside 9; smear otherwise). Force 3 `A`/`D` HALTs after the first death; force 10 does not. Enemy never concentrates. Script `A` does not steal houses at spawn; contact-start may assign leftover holes |
| Cover | SHIFT+D or SHIFT+A: live pole plus neutrals. Soft neutrals face the axis-snapped walk (EW room, `D` travel east → face E). Verb `R` faces **opposite** of travel (retreat west → front east). In dest, a death on `D` keeps the occupied pole (farm wave 2 stays looking east until `R`). Hard neutrals always face the painted cardinal (farm houses: `cover_hard_w`). All-neutral EW room no longer defaults to south. Wrong exclusive pole stays empty. `M` still walks to a rank around WHERE. Halt does not reshuffle holes |
| Trace | `FORCE_TRACE=1 ./build/src/sdl/force 2> /tmp/force.log` — think lines (slot, cell, region, dest, verb, cover, aim, step/cross), director lines, and combat. `FORCE_SCRIPT=1` is director-only. `FORCE_COMBAT=1` is rifles + grenades (no stepper spam): due shot `t=N shoot u3A (22,8) R1 v4 -> u19a (12,8) R3 d9 g3 dmg1 hp15` (`d` Chebyshev, `g` occupied grade or 0, `dead` when hp hits 0). Due with nobody in range: `-> none otherN rngN`. A landed shot is the posture number or half of it: 1, 2, 3, 5, 7, or 10. A house at dist 5–9 logs `dmg0` and does not start the reload. Grenade: `t=N nade u3A (22,8) R1 -> u19a (12,8) R3 d2 hits1 dmg8 rem19 hp8 dead`. Tick rollup when anyone fired, missed, or threw: `combat fire N none N dmg0 N silent N nade N pN eN` (`silent` = infantry not weapons-free). `wait NAME` arms a `->`; `-> NAME` is the fire. `cover … front E dest 2` is assign (R farm fallback should be front E, dest room 2). |
| Camera / intel | Farm: the cursor stops on the playfield edge; NW grass never appears. SHIFT+F RETURN snaps inside the mission rect; SHIFT+B restores. A typed WHERE outside the rect clamps onto it. During fire SHIFT+C → `CONTACT n`, SPACE centres that room. `Z` does not toggle a scaled map. Draw shows every room inside the view. |
| F11 | Fullscreen toggle |
| F3 | Reloads the current mission: player stamps back, script at beat 0, cursor centred, wizard idle, outcome PLAYING. Stick latch and fullscreen stay. Works after win/lose. Smoke does not press F3. |
| C64 title SID | Title begins an audible three-voice minor-key loop after it appears. RETURN dismisses it, and only after `CAMPAIGN` has loaded; the song keeps playing on the menu. Choosing a mission fades SID volume to zero across 45 frames (about 0.9 seconds on PAL, 0.75 on NTSC) before the battle raster handler is installed. PAL and NTSC retain approximately the same score tempo. |
| Window close | Clean shutdown (no leak reports required; `force_host_shutdown` must run). No quit key |
| 2-wide pixels | A tile whose even/odd PNG pixels differ must fail `gen_sdl` |

Interactive (`./build/src/sdl/force`, no args): 3-act Hold the Farm.
`D` the houses, wave 1 walks in, wave 2 hunkers then runs west, wave 3
dies in room 3. Win (`SUCCESS`) needs that letter gone and a
player body in room 3. Lose (`DEFEAT`) if the player bank hits 0.
Overrun: five player men in room 4 moves later spawns to room 2.

1. Smoke: exit 0, player unmoved, enemies may first-step, row 21 `READY`, outcome playing.
2. `D` still claims farm holes. They walk in; leftover holes may fill on contact-start.
3. Clear room 3 with a living man there → yellow `SUCCESS`. Wipe → light-red `DEFEAT`.
4. Pan west into NW grass. Wave 2 `M` exit-west despawns at the farm seam (`x=40`).
