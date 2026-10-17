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

For C64 changes, build and run the pipeline regressions from the repo root:

```bash
cmake --build build --target force_c64
python3 tools/test_catalog.py
python3 tools/test_c64_packages.py
python3 tools/test_c64_components.py
python3 tools/test_c64_routes.py
python3 tools/test_objectives.py
python3 tools/test_container.py
python3 tools/test_biome.py
python3 tools/test_tactics.py
```

The target writes `build/force.prg` and the container SEQ files under
`build/c64/`. Relaunch the game and containers together; the loader checks
the layout id. Use `cmake --build build --target disk` for a disk image.
Use the CMake packaging target; direct assembly produces an intermediate
game image rather than the launchable bootstrap.
See [`c64-port.md`](c64-port.md) for windowed control-port checks.

`tools/test_tactics.py` also drives the authored Cross the River director:
partial/full bridge gates, friendly road reinforcements and bazooka, road
clearance and explicit second-wave attack order, southwest defensive spawn
and room order, southwest arrival, early-arrival prevention,
restart and wipe. Combat outcomes and movement are controlled in this
fixture; it does not establish mission balance or a full live playthrough.

C64 Cross the River load fix: native `test_c64_tactics.py --port 16529
--standard pal --mission 1` passed automatic RUN, title/menu, mission
validation/activation, first draw, F3 restart and tactics. The record
validator accepts predicate 10 (`bridge built`); predicates above 10 are
rejected by the host validator. Source/build-only checks did not catch
the original native predicate limit mismatch.

Native tactics checks (2026-10-16), after building:

```bash
python3 tools/test_c64_tactics.py --port 6510 --standard pal
python3 tools/test_c64_tactics.py --port 6510 --standard ntsc --mission 2
python3 tools/test_c64_tactics.py --port 6510 --movement-only
python3 tools/test_c64_tactics.py --port 16529 --mission 1 --cross-director
```

These own a windowed emulator with `-a -p`, Inspector and a private disk
copy. Choose an unused port; they refuse an occupied one. The Cross director
mode checks actual road-wave movement, delayed southwest cue, southwest
spawn and DEFEND movement into the adjacent room, then controlled
casualties and arrival for victory. Its observer stays outside firing range
to isolate deployment from combat balance. They terminate only that emulator. Automatic RUN, title/menu, selected
mission, F3 restart, nest armor/arc/walls, rocket damage/ammo/reload, rifle
fallback and exact-cell spawn backpressure are asserted. Bridge completion
keeps `drawn` set and marks its plank dirty; the next `draw_all` changes that
screen cell from tile 80 to 81 without a full-field repaint. Movement mode
replays DEFEND A at (22,9), waits 128 logic ticks, then MOVE A to (14,8)
and checks all seven men leave room 1 through its door and settle in room 2.
JSON evidence and emulator logs are left in the printed temporary folder.

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
requires a working display; it is not headless. Smoke skips the title and
the menu and paints mission 0. Before that frame it loads Cross the
river, requires six deck cells at (32–34, 2–3) stamped as tile 80 on
water with `deck_cost` 40, spawns two men on section B, sets the cost to
2, and ticks twice. Both pour the north plank, then one steps onto the
south plank. Failure is stderr `FORCE: bridge build failed` and exit 1.
Next it finishes every plank and orders one man off the south plank.
Failure is stderr `FORCE: bridge leave failed` and exit 1.
Next it checks a closed bridge, a west column only, then a full finish.
The closed bridge must hold the soldier at (30,8). Completing only the
west column permits an approach step to (31,7); finishing the entire bridge
must enable crossing. The fixture completes its final plank through normal
construction so the next-hop cache is rebuilt, rather than only stamping
tiles. The bridge build, leave and crossing checks pass as of 2026-10-11.
The full SDL smoke gate passes as of 2026-10-11.
When the crossing check passes, smoke runs `force_menu_selftest` against its own
three-mission catalog and a farm/cross score-line case. Authored mission names, count and order are
not inputs to the menu assertions. Save tests use a unique private directory
under `/tmp`, cleaned after the run. Checks include shown set, reveal, a score past a gap,
commit, F8, left and right leaving the bar, the first RETURN launching, a PRG round-trip under `/tmp`,
`farm 7` / `cross -` / a legacy `cross_river` line, and a few paint cells.
Failure is stderr `FORCE: menu self-test failed` and exit 1. A passing
run still opens a window, paints the farm plus the command strip, and
exits 0. It also loads Take the Ridge, requires seven friendly stamps on
local rows 0–19 (a stamp at y ≥ 20 fails), then reloads mission 0 before that frame.
Failure is stderr `FORCE: ridge friendlies missing` and exit 1. The self-test
does not write `build/c64/campaign.prg`. An interactive launch shows the
title until a key, then the campaign menu.

There are no unit tests for font bits, rasterize, clamp, or input repeat.
The menu self-test runs only from `--smoke`. C64 pipeline regression tests
are listed below.

## What a change should re-check by hand

| Change | Check |
|--------|-------|
| Screen geometry / scale | Window is 1280×800 default; resize stays integer-scaled; min size 320×200 |
| Map / tileset | Farm: 40×20 map, the whole file, no scroll. Green field, yellow lane, grey walls and roofs, seven blue soldiers at the gate, no TMX enemy stamps; after the first logic tick six red enemies may stand in the west field, roofs covering; grass shows through wall gaps. The river and the ridge are other maps and are not on screen. Roster A white, B–H grey. Row 21 `READY` while playing, `SUCCESS` / `DEFEAT` on outcome. Smoke stays PLAYING |
| `tiles.txt` / `missions.txt` / `properties.txt` / `scripts/*.txt` / TMX / PNG | Touch the file, `cmake --build`; `gen_sdl` should rerun |
| Cursor | Unshifted WASD and arrows; at a playfield edge the camera pans only while the mission rect is larger than the 40×20 view (farm does not pan). The cursor does not enter rows 20–24. On a soldier, roster A turns yellow. SHIFT+WASD must **not** walk |
| Stick | After first dpad/stick move, WASD become letters and unshifted M talks. Unplug returns to WASD cursor movement. There is no input-mode label on row 24 |
| Wizard | Keyboard: SHIFT+M, RETURN → row 21 `MOVE A AT … FORCE 10`, last-order on A. SHIFT+A parses ATTACK (no VERB flash). SHIFT+K parses KILL. SHIFT+R parses RETREAT. SHIFT+S / SHIFT+J parse SPLIT / JOIN (no VERB flash). SHIFT+F parses FOCUS (skip WHO; RETURN uses cursor cell). SHIFT+B parses BUILD (WHERE must be a deck cell). SHIFT+G previous camera. SHIFT+C / SHIFT+E cycle CONTACT / MARK; SPACE snaps. SHIFT+Z is unbound. Unshifted `.` in WHO after a combat verb tags the cursor man. DEL pops (and clears a `.` snapshot). Esc cancels the whole draft from any slot (including SHOW) back to `READY`. Idle Esc is a no-op |
| Stepper | After SHIFT+M RETURN, men walk toward a rank around WHERE (one step every third video frame) and stop. A NE dest is NE-NE-NE, not E-N-E-N; both-wall corners stay blocked and zipper. Glyphs turn with the step (8-way) except `R`, which overwrites to `section_front` (threat, opposite of travel). Halt stops in place. Roofs are walkable. Walls, barriers, bush tiles 64–65, and blue ground (colour tile 118) block. Two-wide gap: opposite traffic keep-right. Long open front (split yard): each man takes the nearest seam cell, no NO PATH. Sidestep is right-hand then re-aim, not march along the hedge. Smoke: seven player stamps unmoved, six enemies may first-step in room 4, outcome playing |
| Combat | SHIFT+D: they lock to farm holes. Wave 1 walks in from room 4 (`ATTACK` room 1 force 10); men drop. Wave 2 hunkers in room 2 after the stagger, `R` room 3 (west walk, **east** glyphs, hi pole, not x=6 lo chips), then `M` exit-west (despawn at the mission west edge `x=0` or die). Wave 3 `D` room 3: men walking 4→3 take 7, not the hole number; room-2 fire wounds them before they hole up. Win needs a living player body in room 3. Hurt tint on the target; men vanish at hp 0. A house takes 1 from any side. A grade-2 hole takes 2 from the side it watches and 10 from any other side. Sprint takes 5, a walk takes 7, a man stopped off a hole takes 10. Those numbers are for 1–4 cells. At 5–9 they halve, so a house takes 0. At 10 and beyond he is not a target. Rifles hit through walls inside 9. From the x=22 houses, room 3 is out of rifle range and the west edge of room 2 is the half-damage band. A man on a chip at Chebyshev 2–5 draws a pineapple; the ground fill flashes red on the splash disk and stops at the wall; stock ticks down (farm player 8 wait 50, enemy 0 wait 200). Open-yard rifles do not spend grenades. SHIFT+M sprints (faster than `A`/`D`), silent on the way, fights at dest; a dest cover chip is claimed. SHIFT+H holds and shoots. `.` WHO: `M .` / `D .` onto a wall chip places that man without a letter peel. `S B` on a man peels him; `J B A` joins. `S B` on dirt beeps. `D A` after a wall nudge recalls him. `K` concentrates (three-of-four due on the named cell when a man is there inside 9; smear otherwise). Force 3 `A`/`D` HALTs after the first death; force 10 does not. Enemy never concentrates. Script `A` does not steal houses at spawn; contact-start may assign leftover holes |
| Cover | SHIFT+D or SHIFT+A: live pole plus neutrals. Soft neutrals face the axis-snapped walk (EW room, `D` travel east → face E). Verb `R` faces **opposite** of travel (retreat west → front east). In dest, a death on `D` keeps the occupied pole (farm wave 2 stays looking east until `R`). Hard neutrals always face the painted cardinal (farm houses: `cover_hard_w`). All-neutral EW room no longer defaults to south. Wrong exclusive pole stays empty. `M` still walks to a rank around WHERE. Halt does not reshuffle holes |
| Trace | `FORCE_TRACE=1 ./build/src/sdl/force 2> /tmp/force.log` — think lines (slot, cell, region, dest, verb, cover, aim, step/cross), director lines, and combat. `FORCE_SCRIPT=1` is director-only. `FORCE_COMBAT=1` is rifles + grenades (no stepper spam): due shot `t=N shoot u3A (22,8) R1 v4 -> u19a (12,8) R3 d9 g3 dmg1 hp15` (`d` Chebyshev, `g` occupied grade or 0, `dead` when hp hits 0). Due with nobody in range: `-> none otherN rngN`. A landed shot is the posture number or half of it: 1, 2, 3, 5, 7, or 10. A house at dist 5–9 logs `dmg0` and does not start the reload. Grenade: `t=N nade u3A (22,8) R1 -> u19a (12,8) R3 d2 hits1 dmg8 rem19 hp8 dead`. Tick rollup when anyone fired, missed, or threw: `combat fire N none N dmg0 N silent N nade N pN eN` (`silent` = infantry not weapons-free). `wait NAME` arms a `->`; `-> NAME` is the fire. `cover … front E dest 2` is assign (R farm fallback should be front E, dest room 2). |
| Camera / intel | Farm: the cursor stops on the playfield edge; the map is the whole view, so the river never appears. SHIFT+F RETURN snaps inside the map; SHIFT+G restores. A typed WHERE outside the map clamps onto it. During fire SHIFT+C → `CONTACT n`, SPACE centres that room. `Z` does not toggle a scaled map. Draw shows every room inside the view. |
| Objectives | Farm load/F3: line 25 shows `Hold the farm`, prefixed with `>`, alternating yellow/white for about four seconds, then blank. Enter beat `last`: `Move west` replaces any prior cue and restarts the timer. No platform/WASD labels. Reload or change mission clears prior state. SDL timer is 240 video frames; C64 is 67 PAL or 80 NTSC logic ticks. |
| F11 | Fullscreen toggle |
| F3 | Reloads the current mission: player stamps back, script at beat 0, cursor centred, wizard idle, outcome PLAYING. Stick latch and fullscreen stay. Works after win/lose. Does not write the campaign file and does not return to the menu. Smoke does not press F3. |
| SDL campaign | After the title: row 0 title, row 6 `Missions:` and `Survivors:`, rows 8–17 one title list, row 24 credit. A fresh file shows only the first mission. The selected row is inverse. Up and down move one step. Left and right do not move the bar. RETURN on a shown row starts it. `+` reveals the next for this sitting and does not write. F8 then F8 clears scores. Win: menu appears with the new count, row 22 says `SAVING` for about 20 frames, then the file has that count (living player strength, or the old count if it was higher). Loss does not write. RETURN on `SUCCESS` / `DEFEAT` returns to the menu. A refused write shows `SAVE FAILED` and leaves the file unchanged. |
| C64 title SID | Title begins an audible three-voice minor-key loop after it appears. RETURN dismisses it, and only after `CAMPAIGN` has loaded; the song keeps playing on the menu. Choosing a mission fades SID volume to zero across 45 frames (about 0.9 seconds on PAL, 0.75 on NTSC) before the battle raster handler is installed. PAL and NTSC retain approximately the same score tempo. |
| C64 campaign | Menu: row 0 title, row 6 `Missions:` and `Survivors:`, rows 8–17 one title list, row 24 credit. The selected row is inverse. Left, right, STOP, and DEL do not move the bar. RETURN on a shown row starts it. The title loads `INDEX` into `$1800` before the bitmap comes down. A bad index or a missing campaign leaves the title up with a red border. A fresh file shows only the first mission. `+` reveals the next for this sitting and does not write. F8 then F8 clears scores and writes. Win: menu appears with the new count, row 22 says `SAVING`, then the file has that count (living player strength, or the old count if it was higher). Loss does not write. Read-only device 8 shows `SAVE FAILED` and leaves the file unchanged. Drive Write must be on or the save is refused. |
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
4. The farm view does not pan. Wave 2 `M` exit-west despawns at the west edge (`x=0`).

C64 bank-label compiler: `python3 tools/test_c64_components.py` checks terrain
rules, disconnected banks, a large complete flood, and component-id overflow.

C64 routing compiler: `python3 tools/test_c64_routes.py` checks
first-hop propagation, unreachable rooms, closed deck versus built water,
painted portals, deterministic BFS ties, reversible patches across all
synthetic bridge states and transitions, and patch-program budget rejection.

C64 bridge runtime checks: compare the full 818-byte active image with
pipeline variants. Normandy verification covers all 64 physical completion
combinations and all 16 routing-state transitions. Maximum activation is
5.9 ms; a pulse with two simultaneous boundary completions activates their
combined state once and takes 22.1 ms. Verify restart restores state zero
after campaign scratch reuse, and `$BF00` retains the patch program.
Compositor checks compare all eight charset bytes for a soldier over tile
81, hurt tint over tile 81, and the unchanged wall-over-soldier rule.

Session verification also compared all 3200 loaded paper bytes with generated
labels on Normandy and Bastogne, and compared every Normandy construction
combination's hops and crossing positions with a fresh host-side bake.
Bastogne's no-bridge program loads and survives mission resets; activation
of its sole state takes about 0.12 ms. Startup measurements are recorded
in [`c64-port.md`](c64-port.md); they exclude the first draw.

## Staged C64 loading verification (2026-10-11)

See [C64 loading](c64-loading.md) for current formats, memory usage,
measurements and remaining verification limits. Build with
`cmake --build build --target force_c64` (or `disk` for D64). Launch the
bootstrap `build/force.prg` with device 8 mounted on `build/c64`.
Use `build/c64/game-image.sym` for runtime probes.

Host checks: `python3 tools/test_c64_packages.py`,
`tools/test_c64_components.py`, `tools/test_c64_routes.py`, and
`tools/test_objectives.py`. Runtime scripts are `test_c64_banked_runtime.py`,
`test_c64_loading_failures.py`, `test_c64_bank.py`, `test_c64_campaign_io.py`,
and `test_c64_play_flow.py` in tools/. Use their `--help` for ports/standards.
They attach to an existing windowed c64m and can reset/pause it. Campaign
checks require an isolated writable fixture mounted at launch; never point
save/reset tests at the user's campaign. Other fixtures are isolated copies.
The supplementary `test_c64_boot_disk.py` normal BASIC LOAD probe is still
unverified; its timeout must not be counted as a passing disk-boot check.

Generated evidence and screenshots live in `build/c64/banked-evidence/`;
`build/c64/memory-report.{json,md}` record fresh segment capacities and
intentional phase overlays. Clean/incremental package checks and deleted
chunk repair were tested. User script and campaign bytes remain intact.

## Local bridge movement verification (2026-10-11)

SDL smoke includes `ZU XFF / YFFFF` (X is a finished plank), with water
around the deck, traversed in both directions without stepping on tile 80
or using a bridge-specific diagonal exception. Existing build, leave, closed/partial
and complete bridge checks still pass with bridge steering removed.
A windowed C64 clone of the paused game reached (35,6) from (34,3), and
traversed the same partial deck in both directions. From X it stepped down,
left, then diagonally onto Z under the ordinary corner rule. The original
emulator stayed paused. With cost 1, the builder at (31,3) finished (32,2)
without moving, then finished (32,3) before stepping onto it: both touching
planks complete before movement. A separate offset-bank probe at (30,8) oscillated
between (31,7) and (31,8) both with and without the former bridge steering;
that room-routing issue remains unresolved and is not a passing crossing test.

## Apple IIgs native acceptance

Build with `cmake --build build --target force_iigs`; see [iigs.md](iigs.md) for
toolchain, private disk launch, matching symbols and demonstrated limits. Host
checks are `python3 tools/iigs/test_assets.py` and
`python3 tools/iigs/test_probe.py`. Native test entry points in `tools/iigs/` use
the GSSquared debugger and require explicit private-session socket/symbol paths.
They execute guest code; do not run campaign/reset/shutdown fixtures against
personal save data. `test_shutdown.py` terminates its guest application.

IIgs untouched-cursor regression: run `tools/iigs/test_input_idle.py` with the
private session's socket/symbols and a neutral controller. It runs Farm and Cross
through the actual main loop with IRQs enabled. The older direct-call idle check
masks IRQs and cannot detect interrupt-induced analog timer undercounts.
