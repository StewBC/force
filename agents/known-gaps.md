# Known gaps

What the **SDL binary does not do**. Source of product intent:
[`doc/README.md`](../doc/README.md). Do not treat this file as a schedule.

Two columns: **not in the prototype** (true of `src/sdl/` today) versus
**out of product scope** (the design already rejected it).

## Not in the prototype

| Gap | Reality in `src/sdl/` |
|-----|------------------------|
| Verbs F Z B C E | `F` focuses (skip WHO; FORCE is optional duration). `B` previous camera. `C`/`X` cycle hot rooms; `E` last-seen marks; SPACE snaps. `Z` is unbound (room-blob overview not drawn). `M` `D` `H` `A` `K` `R` `S` `J` parse. `.` is WHO (this stack). Esc cancels the draft; window chrome quits. `F11` fullscreen; `F3` restarts the current mission. |
| Overview zoom | Unbound. A C64 overview is a 16-room paint on the same 40×20, not a scaled tilemap. |
| Fog of war | Off (`FORCE_FOG` 0). Room heat / last-seen still feed `C`/`E`. Draw never hides. |
| Stacks overlay, type-join | Peel/join letter form is in (`S B`, `J B A`). No count overlay. Type-join `J I A,C` is not bound. See [`../doc/FORCE_08_Units_Sections_and_Tick.md`](../doc/FORCE_08_Units_Sections_and_Tick.md). |
| Cheat sheet / doctrine | `?` / CTRL overlay and `D *` idle doctrine are unbound. |
| Engineers, mines, specials | No cell jobs. |
| Campaign / clock / waves | SDL still boots mission 0 (`hold_farm`) and has no campaign screen. The C64 menu, progress file, and save rules are the contract to port: [`game.md`](game.md) (Campaign menu) and [`c64-port.md`](c64-port.md). Hold the Farm is playable: 3-act director, `SUCCESS` / `DEFEAT`, overrun `spawn_room`. Remaining: other boards, clock-as-win skin, pageant (truck / radio). |
| Hardware sprites | None. Cursor is a pixel overlay. |
| 8-bit targets | The C64 Hold the Farm vertical slice is playable, including its C64-only title SID; parity work and broader product scope remain in progress. Handoff: [`c64-port.md`](c64-port.md). Apple II is still absent. |
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
- Camera `win_*` is the 40×20 view (edge pan, `F`, `B`) inside the mission rect `play_*`. A rect the size of the view does not scroll. Sim and next-hop use the full map. `exit-*` despawn uses the mission edge. Fog draw is off.
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
  despawn. `M` silent while walking (pause `fire_wait`); weapons free at dest; occupy-if-chip. `H` weapons free, no step.
  Closest man inside 9; skip `hp == 0`. Walls do not stop a rifle. The
  sight ray stays in the file and is not called. On an assigned hole,
  grade 3 takes 1 from any side; grades 2 and 1 take 2 and 3 from the
  watched side and 10 from any other. Off a hole, sprint takes 5, a walk
  takes 7, and a stop takes 10. Dist 5–9 halves that. Dist 10 and out
  is not a target. No load-time
  enemy `ATTACK` seed. Script `A` does not assign at issue; `FLAG_CONTACT`
  latches assign when an enemy letter with verb `A` first has a living man
  in the dest room. Enemy death reassigns on `D`/`R` or `FLAG_CONTACT`.
- `K` three-of-four due on the named cell (body inside 9 / out of range
  or empty smears). Skip that cell as a cover hole.
  Force-break: nibble vs `section_order_str` vs live strength; verb →
  `HALT`, `FLAG_BREAKING`. Force 10 never. No morale byte. Enemy never `K`.
- Grenades: side stock + wait from the script header (farm 20/50 vs 5/100).
  Automatic on a man standing on his assigned cover chip in Chebyshev 2–5;
  blast R=2, walls occlude splash,
  friendly-in-disk aborts that target. Damage 8. Colour-fill flash, no
  explosion tile. No `unit_weapon` column.
- No Tab mode. Keyboard: SHIFT+letter talks; unshifted WASD/arrows move.
  Stick play latches on first move past deadzone, not on `joy_present`.
- Command draft lives on `force_game`. Last-order is written only on RETURN.
  Esc cancels the draft from any slot. No quit key; window chrome closes.
