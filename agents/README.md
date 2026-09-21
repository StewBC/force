# FORCE agent handoff

Implementation brief for the product **as it is**. Source is authoritative.
If a note and the code disagree, fix the note (or the code) in the same
change.

An agent given **only this file** can find game intent, speculative
architecture, and the SDL prototype sources. Do not treat [`doc/`](../doc/)
as a description of the binary. Do not treat [`design/`](../design/) as
landed.

**Paths in this folder** are repo-root literal (`src/sdl/...`, `CMakeLists.txt`,
`tools/`, `assets/`).

## Read order

1. This file (layout, where to look, other indexes).
2. Game intent, when the task is about what the player does:
   [`../doc/README.md`](../doc/README.md).
3. The component handoff for the code you are changing (table below).
4. [`testing.md`](testing.md) before claiming a change is done.
5. The source named by that handoff.

Parked / not-in-the-binary work: [`known-gaps.md`](known-gaps.md). Read it
when the task looks like "add the RTS"; skip it for host/screen/input fixes.

Map / tileset / `tools/gen_sdl.py` work starts at [`assets.md`](assets.md).

## Other indexes

| Index | What it is |
|-------|------------|
| [`../doc/README.md`](../doc/README.md) | Game design (vision, command language, maps, campaign). Product intent, not source-of-truth for C. |
| [`../design/README.md`](../design/README.md) | Speculative / in-flight **code** designs. Status legend and index. |

Do not put speculative writeups in `agents/`. Lasting invariants belong here
once they land in `src/`. Campaign and command-language drafts belong in
`doc/`, not `design/`.

## Product

FORCE is a single-player 8-bit-style RTS. The **current binary** is an SDL3
C11 prototype: a 40×25 screen at 4× nearest-neighbour, the farm map composited
from Tiled data, a cell cursor, and a four-slot command wizard (`M` sprints;
`D`/`A` take cover; `H` holds; `K` concentrates; `S`/`J` peel/join;
`.` tags a man; rifles smear; grenades break wall stalemates). Version
**0.1.0**.

It is not yet a campaign. See [`known-gaps.md`](known-gaps.md).

## Where to look

| Task | Handoff | Source |
|------|---------|--------|
| Layers, ownership, screen geometry | [`architecture.md`](architecture.md) | `src/sdl/**`, root `CMakeLists.txt` |
| Cell buffer, font, VIC-II palette, chrome rasterize | [`screen.md`](screen.md) | `src/sdl/core/{types.h,font.*,screen.*}` |
| Window, present, fullscreen, stick hotplug | [`host.md`](host.md) | `src/sdl/sdl/host.*` |
| Keyboard / pad / stick → cursor delta + command token | [`input.md`](input.md) | `src/sdl/sdl/input.*` |
| Cursor, wizard, playfield composite, `--smoke` | [`game.md`](game.md) | `src/sdl/game/game.*`, `src/sdl/game/command.*`, `src/sdl/game/world.{h,c}`, `src/sdl/main.c` |
| Tileset, TMX planes, Python compiler, missions | [`assets.md`](assets.md) | `tools/gen_sdl.py`, `assets/`, `src/sdl/generated/` |
| What the binary does not do | [`known-gaps.md`](known-gaps.md) | (absence in `src/sdl/`) |
| Configure, build, smoke | [`testing.md`](testing.md) | `CMakeLists.txt`, `src/sdl/CMakeLists.txt` |

Keep docs current. Stale handoffs are worse than none.

## Tree

```text
src/sdl/main.c        host loop, --smoke
src/sdl/core/         types, font, character screen (chrome)
src/sdl/sdl/          SDL window + input
src/sdl/game/         tick + compose frame + command wizard; world.{h,c} is BSS board + unit pool
src/sdl/generated/    linked map/tileset C (build product)
tools/gen_sdl.py      assets → generated
assets/               PNG, TMX, tiles.txt, missions.txt
doc/                  game design
design/               code designs
agents/               this handoff
```

## Verification

From the **force repo root**:

```bash
cmake -B build -S . -DCMAKE_BUILD_TYPE=Debug
cmake --build build -j
./build/src/sdl/force --smoke
```

Details in [`testing.md`](testing.md). No ctest. Interactive run is
`./build/src/sdl/force`.
