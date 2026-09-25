# Door crossings — one list per doorway, one formation per order

| Field | Value |
| --- | --- |
| Author | FORCE design session |
| Date | 2026-09-25 |
| Status | **active** |
| Last worked on | 2026-09-25 |
| Repo path | [`door-crossings.md`](door-crossings.md) |
| Source | `src/c64/move.asm`, `src/c64/world.asm`, `src/c64/equ.inc` |
| Follows | [`tick-cost.md`](tick-cost.md) |

Six men resolving a doorway on one tick cost about 90,000 cycles. The openings and the formation cells are facts about the map and the order. Compute each once. A man then reads a short list.

---

## What was measured

PAL, the farm after the step-phasing and weapon-scan work, 2026-09-25. Tick 363 took 136,043 cycles from `input_poll` to `wait_ui`. Tick 362, with the same ten calls to `unit_think`, took 44,297. The rifle search on 363 ran 4 times and cost about 2,300.

The extra cost on 363 was six men in `pick_front`:

| Work | Calls | Cycles |
| --- | ---: | ---: |
| `is_portal` | 61 | 17,040 |
| `move_dest` |  | 12,497 |
| `pick_front` | 6 | 11,319 |
| `seam_hit` | 240 | 10,467 |
| `region_at` | 97 | 8,737 |
| `cell_open` and `map_ptr` | 95 each | 12,593 |

`seam_hit` was already using the 40-byte `seam_open` cache. Each question was cheap. `pick_front` still walks every cell of the shared wall, and it walks that wall three times per man: count the openings, then nearest, then keep-right. Six men times a wall of about thirteen cells times three passes is the 240 hits.

`is_portal` scans all `rom_portal_count` entries (12 on this farm) per call. `blob_ok` calls it for every formation candidate, and `try_step` calls it for every landing.

## Rules that must survive

The visible crossing does not change. SDL stays the spec. These tables are a C64 cycle cut.

`pick_front` today, and after the change:

- The man is standing on the seam line, and the doorway has at least one open cell: he crosses straight, at his own coordinate, even when the cell he is standing on is shut. Some other cell on that wall being open is enough.
- No open cell: the pick fails, as it does now.
- Three or more open cells, and he is not on the seam line: the open cell with the smallest Manhattan distance to him. An equal distance keeps the one found earlier in the `sm_lo` .. `sm_hi` walk.
- One or two open cells, and he is not on the seam line: keep-right, `lane_signs` and `lane_better`, over the open cells in that same order.

`seam_pair` ignores occupancy. Men standing in the doorway do not change the list.

`move_dest` ranks living non-emplacement members of the section with a slot below `think_i`. That rank indexes the valid formation cells in `bdx`/`bdy` order. Invalid cells are skipped. If the rank runs off the end of the valid cells, the destination stays the raw order cell (`useord`). An exit order that `off_play` accepts still uses `lip_of`, not the formation list.

## 1. Portal bitset

Build it at the end of `infer_portals`, which `bake_hop` already calls from `world_load`. A cell is set when some portal index has that `rom_portal_x`/`rom_portal_y` and both `portal_from` and `portal_to` are not `NONE`. That is the current `is_portal` test.

The farm map is 80 by 40. One bit per cell is 400 bytes. `is_portal` becomes a bounds check and a bit test. `try_step` and `blob_ok` keep calling it.

Put the bits in BSS. The end-anchored BSS has about `$4F7` bytes of headroom above the occupancy table before this table. 400 bytes fits. The `$A000`–`$BFFF` code gap stays free.

## 2. Open cells of each shared wall

After `infer_portals`, and before `bake_hop` starts its room search, find every ordered room pair that `seam_prep` accepts. For each, run the existing `seam_pair` walk once and store:

- `sm_mode`, `sm_here`, `sm_next`, `sm_lo`, `sm_hi`
- the open `mv_p` values, in ascending order

`rooms_linked` treats "any open cell" as "the list is non-empty", then falls through to `painted_link` as it does now.

`pick_front` loads that record instead of calling `seam_prep` and `seam_ensure`. Standing on the seam is a range check against `sm_lo`/`sm_hi` and the fixed axis, not a walk. The nearest and keep-right passes iterate the open list once between them, in stored order, which is the old `sm_lo` order.

A span longer than the stored cap keeps today's walk for that one pair. `SEAM_SPAN` is 40. Farm walls should fit in a much smaller cap. Size the store for the pairs that actually touch. Ten rooms do not produce 90 walls.

This replaces the per-man `seam_ensure` rebuild and the triple wall scan. The 40-byte `seam_open` cache can go away once nothing calls it.

## 3. Formation cells, once per order

When `section_issue` stores `section_order_x` and `section_order_y`, build that section's valid formation list. Same `bdx`/`bdy` order, same `blob_ok` tests: inside the map, in the order cell's room, not a portal, `cell_open`. Store up to nine cells and a count. `SECTION_MAX` is 16, so the table is 16 counts plus 16 by 9 by 2 coordinate bytes.

`move_dest` still counts the rank itself. That loop is slots below `think_i`. The rank then indexes the stored list. A miss falls through to the raw order cell. The `lip_of` path stays as it is.

Rebuild the list only when that section's order cell changes. A death or a spawn changes ranks and does not change which cells are valid. `world_load` issues the starting orders after `bake_hop`, so the portal bitset already exists.

## Leave alone

- Do not change nearest, keep-right, or the straight-across rule to something simpler.
- Do not let occupancy filter the doorway list.
- Do not put the bitset or the doorway lists in the `$A000` code gap.
- The weapon scans and the movement phases from `tick-cost.md` stay as they landed.

## Check

One farm through a room crossing. A tick where several men are due at a door should fall toward the cost of tick 362, about 44,000 cycles, rather than 136,000. The man who was going to cross straight still crosses straight. A wide hole still takes the nearest open cell. A narrow hole still keeps right. A section still forms on the same cells, in the same slot-rank order.
