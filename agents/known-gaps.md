# Known gaps

What the **SDL binary does not do**. Source of product intent:
[`doc/README.md`](../doc/README.md). Do not treat this file as a schedule.

Two columns: **not in the prototype** (true of `src/sdl/` today) versus
**out of product scope** (the design already rejected it).

## Not in the prototype

| Gap | Reality in `src/sdl/` |
|-----|------------------------|
| Verbs A K J S R F Z B C E | Unbound. `M` `D` `H` parse. `A` in VERB flashes. `Q`/`Esc` quit; `F11` fullscreen. |
| Stacks overlay, peel/join | 32-slot unit pool and 16-row section table exist. Last-order force 0–10 is stored, not evaluated. No count overlay, no `S`/`J`. See [`../doc/FORCE_08_Units_Sections_and_Tick.md`](../doc/FORCE_08_Units_Sections_and_Tick.md). |
| Overview zoom | One view. `Z` is not bound. |
| Fog, contacts, last-seen | No intel lists. `C`/`E` are unbound. |
| Combat / ROE / concentrate | No fire, no morale, no K. |

| Engineers, mines, specials | No cell jobs. |
| Campaign / clock / waves | One mission window (`farm_mission`). No clock. |
| Hardware sprites | None. Cursor is a pixel overlay. |
| 8-bit targets | SDL host only. No C64 or Apple II tree. The compiler verifies 2-wide pixels but does not emit a charset. |
| Tests | No `tests/` directory, no ctest. `--smoke` is the only automated path. |
| LZSS / section packing | Load is a straight copy into BSS. Maps are linked raw. |

## Out of product scope (do not add)

From the design docs. These are not implicit TODOs.

- Tab as a command-mode / cursor-mode toggle. Cursor is always live.
- Verbs on `0–9`. WHERE and FORCE are digits; the mnemonic is letters.
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
- After load, game code does not index spawn stamps. Occupancy is the
  32-slot unit SoA on `force_world`. ROM `force_map` still has spawn stamps.
- Section table (16 rows) and roster occupancy (white / grey / yellow).
- Greedy 4-connected stepper; no A*; no occupancy bitmap. Dest on the section
  for `M`; dest for `D` is `unit_cover`. Next-hop is a portal index. Roofs
  pass; walls and barriers block.
- Cover claim is FCFS best-remaining in the room the stack occupies.
  Approach default SOUTH. Scout live = watches that axis. Assign on D-commit
  flag, consumed at `world_tick` before think.
- No Tab mode. Keyboard: SHIFT+letter talks; unshifted WASD/arrows move.
  Stick play latches on first move past deadzone, not on `joy_present`.
- Command draft lives on `force_game`. Last-order is written only on RETURN.
