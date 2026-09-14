# FORCE development plan

| Field | Value |
| --- | --- |
| Author | FORCE design session |
| Date | 2026-09-13 |
| Status | **Draft** (index: **active**) |
| Last worked on | 2026-09-13 |
| Intent | [`../doc/README.md`](../doc/README.md) |
| Binary as it is | [`../agents/README.md`](../agents/README.md) |

Program of work for the SDL prototype and, later, the 8-bit targets.
Phase **numbers and names are frozen**. Later design docs cite them
(`Phase 4 — Rooms, portals, stepper`). Do not rename in place; add a
follow-on phase if the work splits.

This is not product intent (`doc/`) and not the binary-as-it-is
(`agents/`). When a phase lands, fold durable invariants into
`agents/` in the same change set.

## How a phase is done

1. **Design conversation** — scope, data shape, 6502 constraints.
2. **One or more design passes** — a document in `design/` through
   write → review → revise until consensus.
3. **Implementation** — C / compiler / assets as that design specifies.
4. **Handoff** — update `agents/` (and `known-gaps.md`) when behaviour
   is in `src/`.

Phase 0’s conversation already happened. Its design is
[`phase-0-pipeline.md`](phase-0-pipeline.md). Phase 1’s conversation
already happened. Its design is
[`phase-1-ram-world.md`](phase-1-ram-world.md). Phase 2’s conversation
already happened. Its design is
[`phase-2-units-exist.md`](phase-2-units-exist.md). Phase 3's
conversation already happened. Its design is
[`phase-3-command-line.md`](phase-3-command-line.md). Phase 4's
conversation already happened. Its design is
[`phase-4-rooms-portals-stepper.md`](phase-4-rooms-portals-stepper.md). Phase 5's
conversation already happened. Its design is
[`phase-5-cover-and-d.md`](phase-5-cover-and-d.md).

## 6502 filter (every phase)

The linked product today is SDL C11. Write that C, and the data it
consumes, as if the CPU were a 6502:

- Fixed arrays, integer ids, no allocator, no generic “pools”.
- Split arrays (SoA) where the 6502 would use `,x` / `,y`.
- One dense terrain buffer. Meta is lists with hard caps.
- If a system wants to scan the map, it is wrong. Scan 32 units,
  16 rooms, 12 cover slots.
- No C64 emitter until **Phase 10**. Same authoring files, later pass.

## First product

**Hold the Farm is a game** at the end of **Phase 7 — Mission script**.
That is the first playable, not “engine complete.” Overview, extra
verbs, other boards, and the 8-bit target come after.

```mermaid
flowchart LR
  P0["0 Pipeline honesty"] --> P1["1 RAM world"]
  P1 --> P2["2 Units exist"]
  P2 --> P3["3 Command line"]
  P3 --> P4["4 Rooms portals stepper"]
  P4 --> P5["5 Cover and D"]
  P5 --> P6["6 Combat"]
  P6 --> P7["7 Mission script"]
  P7 --> P8["8 Intel and camera"]
  P8 --> P9["9 Verbs and boards"]
  P9 --> P10["10 8-bit target"]
```

---

## Phase 0 — Pipeline honesty

Paint stays in Tiled. The compiler extracts lists. A text file names
the chips. Terrain (and SDL colour) stay dense. Caps are real. No sim;
the farm still draws.

- **In:** extractors for properties / rooms / actors; generated SoA
  tables; cut dense meta planes; enough `game.c` change that actors
  still stamp from the spawn list.
- **Out:** LZSS, mission load into a RAM terrain buffer, unit records,
  stepper, C64 emitter.

Design: [`phase-0-pipeline.md`](phase-0-pipeline.md).

## Phase 1 — RAM world, 6502-shaped

Mission “load” copies (later: decompresses) terrain into one buffer
and points at the tables. Fixed arrays, integer ids, no malloc.
Game code is not allowed to index a properties plane. Skeleton every
later system sits on. Still no orders and no movers.

Design: [`phase-1-ram-world.md`](phase-1-ram-world.md).

## Phase 2 — Units exist

Actors become the unit pool. Section table A–H. Strip occupancy can
start meaning something. Draw occupancy from the list, not a TMX
plane. Still no orders.

Design: [`phase-2-units-exist.md`](phase-2-units-exist.md).

## Phase 3 — Command line becomes real

Four-slot wizard, 4-byte command object. Bind `M` first. Chrome stops
being a poster. `Q` / `Esc` stay quit.

Design: [`phase-3-command-line.md`](phase-3-command-line.md).

## Phase 4 — Rooms, portals, stepper

Region rects + portal list + next-hop (256 bytes) + Bresenham error
on the unit. `M a` walks. No A*. Authoring promise: if greedy traps,
it was two rooms.

Design: [`phase-4-rooms-portals-stepper.md`](phase-4-rooms-portals-stepper.md).

## Phase 5 — Cover and D

Cover / scout tables, approach bits, assignment on the triggers in
[`../doc/FORCE_07_Rooms_Cover_and_Farm.md`](../doc/FORCE_07_Rooms_Cover_and_Farm.md).
First “they look smart” moment. Shooting not required to see it.

Design: [`phase-5-cover-and-d.md`](phase-5-cover-and-d.md).

## Phase 6 — Combat

Shoot half of the tick, default ROE smear, `K`, force nibble, coarse
morale. Enemy uses the same cover fill, no `K`.

## Phase 7 — Mission script

Clock, waves, approach bits flipping, win/lose. **Hold the Farm is
playable.**

## Phase 8 — Intel and camera

Overview `Z`, fog, `C` / `E` lists, window into a larger map when a
board needs it. Farm can stay one screen.

## Phase 9 — More verbs and the other boards

Engineers as cell jobs, `S` / `J`, remaining command card, Town / Loop
recycled through
[`../doc/FORCE_04_Campaign_Twenty_Scenarios.md`](../doc/FORCE_04_Campaign_Twenty_Scenarios.md).

## Phase 10 — 8-bit target

Charset pack, colour-RAM window, LZSS of terrain, hardware sprites for
vehicles + cursor. Same tables, different emitter. If Phase 1 was
honest, this is a pass, not a rewrite.

---

## What this plan does not do

- Reopen closed shape in [`../agents/known-gaps.md`](../agents/known-gaps.md)
  (40×25, no mouse, `core/` has no SDL, …).
- Treat `doc/` as a description of `src/sdl/`.
- Invent a C64 tree under `src/` before Phase 10.
- Keep dual representations “for debug” after a phase has cut them.

## References

- Game intent: [`../doc/README.md`](../doc/README.md)
- Memory rule (one map, lists for the rest):
  [`../doc/FORCE_06_Tiles_Memory_and_Sprites.md`](../doc/FORCE_06_Tiles_Memory_and_Sprites.md)
- Cover as numbered holes:
  [`../doc/FORCE_07_Rooms_Cover_and_Farm.md`](../doc/FORCE_07_Rooms_Cover_and_Farm.md)
- Current compiler: [`../agents/assets.md`](../agents/assets.md),
  `tools/gen_sdl.py`
