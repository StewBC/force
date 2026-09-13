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
| Map / tileset | Farm: green field, yellow lane, grey walls and roofs, blue soldiers at the gate; grass shows through wall gaps |
| `tiles.txt` / `missions.txt` / `properties.txt` / TMX / PNG | Touch the file, `cmake --build`; `gen_sdl` should rerun |
| Cursor | WASD and arrows; clamp at playfield edges (not into rows 20–24) |
| Stick | Plug/unplug updates `JOY YES/NO` on row 24; dpad/left-stick move |
| F11 | Fullscreen toggle |
| Esc / Q | Clean shutdown (no leak reports required; `force_host_shutdown` must run) |
| 2-wide pixels | A tile whose even/odd PNG pixels differ must fail `gen_sdl` |
