# Known gaps

What the **SDL binary does not do**. Source of product intent:
[`doc/README.md`](../doc/README.md). Do not treat this file as a schedule.

Two columns: **not in the prototype** (true of `src/sdl/` today) versus
**out of product scope** (the design already rejected it).

## Not in the prototype

| Gap | Reality in `src/sdl/` |
|-----|------------------------|
| Verbs J S F Z B C E | Unbound. `M` `D` `H` `A` `K` `R` parse. `Q`/`Esc` quit; `F11` fullscreen; `F3` restarts the current mission. |
| Stacks overlay, peel/join | 32-slot unit pool and 16-row section table exist. Last-order force 0–10 is evaluated on death (break to `H`). No count overlay, no `S`/`J`. See [`../doc/FORCE_08_Units_Sections_and_Tick.md`](../doc/FORCE_08_Units_Sections_and_Tick.md). |
| Overview zoom | One view. `Z` is not bound. |
| Fog, contacts, last-seen | No intel lists. `C`/`E` are unbound. |
| Engineers, mines, specials | No cell jobs. |
| Campaign / clock / waves | Hold the Farm (mission 1) is playable: 3-act director, win/lose chrome, overrun `spawn_room`. Not a gap for farm. Remaining: other 19 boards, clock-as-win skin, pageant (truck / radio). No campaign screen. |
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
- Greedy stepper, 8-connected when both signs are set; no A*; no occupancy
  bitmap. Diagonal lands if the dest cell is free and not both cardinals
  are wall/barrier (occupancy does not block the cut). Same `move_wait`.
  Blocked diagonal falls back to the 4-connected zipper (other axis, then
  sidestep). Sidesteps stay 4-connected and refuse portals / room pops.
  Cardinal far-run (major axis, cap 8 past 16) only when one sign is 0.
  `M` dest is a 3×3 rank around WHERE; `D` dest is `unit_cover`. Next-hop
  is the first neighbour room. Abutting rooms with open tiles are a front
  (closest cell on a long seam; keep-right if two cells). Painted portal
  chips are doors through walls. Roofs pass; walls and barriers block.
  Glyphs face last step (8-way) except `R`, which overwrites to
  `section_front` before draw; arrival still cover (cardinal).
- Cover claim is FCFS in the room of WHERE, **live advancing list only**
  (order direction snapped to the room axis, plus neutrals; ≤ 12). Wrong
  pole is not a candidate. `cover_facing` is pole 1–4, soft 5–8, or hard
  9–12. Soft look = section front (axis-snapped motion). Hard look = the
  painted cardinal. Scout live = scout facing equals this letter’s front.
  Approach default is on-axis (NS → SOUTH, EW → WEST). Assign on D/A/R-commit
  flag, consumed at `world_tick` before shoot. Wizard parses `R` (WHERE-explicit;
  front is opposite of travel). Scout chips have no tile ids.
- HP model B: `unit_hp` spawn 16, `count` occupancy 1. Tick is consume →
  shoot → deaths → script → pulse → contact-start → consume → step →
  despawn. `M` silent (pause `fire_wait`). `H` weapons free, no step.
  Closest smear; skip `hp == 0`. Grade only on the hole cell. Dest-remaining
  is moving (+1 LSR), not also prone. No load-time
  enemy `ATTACK` seed. Script `A` does not assign at issue; `FLAG_CONTACT`
  latches assign when an enemy letter with verb `A` first has a living man
  in the dest room. Enemy death reassigns on `D`/`R` or `FLAG_CONTACT`.
- `K` three-of-four due on the named cell (body+LOS / body+blocked smear
  this shooter / quiet all smear). Skip that cell as a cover hole.
  Force-break: nibble vs `section_order_str` vs live strength; verb →
  `HALT`, `FLAG_BREAKING`. Force 10 never. No morale byte. Enemy never `K`.
- No Tab mode. Keyboard: SHIFT+letter talks; unshifted WASD/arrows move.
  Stick play latches on first move past deadzone, not on `joy_present`.
- Command draft lives on `force_game`. Last-order is written only on RETURN.
