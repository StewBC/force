# Known gaps

What the **SDL binary does not do**. Source of product intent:
[`doc/README.md`](../doc/README.md). Do not treat this file as a schedule.

Two columns: **not in the prototype** (true of `src/sdl/` today) versus
**out of product scope** (the design already rejected it).

## Not in the prototype

| Gap | Reality in `src/sdl/` |
|-----|------------------------|
| Command wizard | Strip paints `VERB WHO WHERE FORCE` and `READY`. No parser, no 4-byte command object, no Tab-to-line. WASD still moves the cursor. |
| Section roster occupancy | Row 23 paints `A B C D E F G H` all light grey. No section table, so no white/yellow. |
| Verbs A D M H K J S R F Z B C E | Unbound. `Q`/`Esc` quit; `F11` fullscreen. |
| Sections A–H, stacks, force nibble | No unit records. The spawn list is stamps, not the unit pool. See [`../doc/FORCE_08_Units_Sections_and_Tick.md`](../doc/FORCE_08_Units_Sections_and_Tick.md). |
| Rooms / portals / next-hop | Room rects and property tables are copied into BSS. Nothing walks them. |
| Overview zoom | One view. `Z` is not bound. |
| Fog, contacts, last-seen | No intel lists. `C`/`E` are unbound. |
| Combat / ROE / concentrate | No fire, no morale, no K. |
| Cover roster / approach bits | No sim. Hold the Farm is paint + design notes. |
| Engineers, mines, specials | No cell jobs. |
| Campaign / clock / waves | One mission window (`farm_mission`). No clock. |
| Hardware sprites | None. Cursor is a pixel overlay. |
| 8-bit targets | SDL host only. No C64 or Apple II tree. The compiler verifies 2-wide pixels but does not emit a charset. |
| Tests | No `tests/` directory, no ctest. `--smoke` is the only automated path. |
| LZSS / section packing | Load is a straight copy into BSS. Maps are linked raw. |

## Out of product scope (do not add)

From the design docs. These are not implicit TODOs.

- Mouse, drag-select, waypoint queues.
- A\* or per-hedge search. Rooms and portals are the path.
- Per-soldier facing, peeking, or objects-to-click. (Facing glyphs exist for
  authoring / later charset; the sim does not use them.)
- Base building / barracks click production.
- A third zoom that draws every private or 3/4 walls.
- Enemy concentrate (`K`). Enemy uses default ROE only.
- Perfect analog of a historical front. Invented battles in a WWII frame.

## Closed shape (already in code)

Do not relitigate without a design doc:

- 40×25 cells, 8×8 pixels, 320×200 native, 4× integer nearest-neighbour.
- Rows 0–19 playfield, 20–23 portable strip, 24 host/C64 extra.
- VIC-II 16-colour indices for chrome; playfield RGB from the sheet.
- `core/` has no SDL. `game/` has no SDL.
- TMX still has five named layers (`color`, `tiles`, `rooms`, `properties`,
  `actors`). Compiled `force_map` is two dense planes plus lists.
- Tile 112 is empty / knockout. Tiled `0` on colour/tiles collapses to 112.
  On meta planes Tiled `0` is absence; tile 0 is a legal spawn.
- CMake runs `tools/gen_sdl.py`; do not hand-edit `generated/`.
- One BSS `force_world`. After `force_world_load`, game code does not index
  `force_map` board columns or mission geometry. `g->mission` is the name.
- Spawn list is stamps, not the unit pool.
