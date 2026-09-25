# Tick cost — spread steps, cheapen the weapon scans

| Field | Value |
| --- | --- |
| Author | FORCE design session |
| Date | 2026-09-25 |
| Status | **landed** |
| Last worked on | 2026-09-25 |
| Repo path | [`tick-cost.md`](tick-cost.md) |
| Source | `src/c64/combat.asm`, `src/c64/move.asm`, `src/c64/world.asm`, `src/sdl/game/world.c` |
| Binary as it is | [`../agents/c64-port.md`](../agents/c64-port.md) |

A contact tick is about 65,000 executed cycles before anyone steps. A step of the whole company adds about 100,000 on the same tick. Spread the steps, then make the rifle and grenade scans visit the other side only. Shots, damage, and the tick a ready man may fire stay as they are.

---

## What was measured

PAL, one lost farm, 2026-09-25. Cycles are processor work from `input_poll` to `wait_ui`, badline stalls excluded. 870 ticks through the loss. 410 used one processing frame, 246 used both and still made the draw, 214 were still running when the next draw frame began.

| Tick | What | Cycles | `unit_think` | `smear_closest` |
| --- | --- | ---: | ---: | ---: |
| 450 | quiet | 30,179 | 2 | 3 calls, ~4,600 |
| 205 | fight, not a step beat | 64,932 | 6 | 11 calls, ~18,700 |
| 206 | same fight, on a step | 166,319 | 11 | 12 calls, ~20,800 |

Tick 206 also spent about 15,000 in `pick_grenade`, about 12,500 in `cell_open` (183 calls), about 12,300 in `pick_front`, and about 25,000 walking the shared door (`seam_hit` 220, `seam_pair` 120, `seam_here`, `seam_ensure`). The ticks beside 206 were 64,932 and 69,359. The same step-versus-neighbour gap shows at tick 150 (159,819 against about 60,000).

`MOVE_WAIT` is 7. `unit_spawn` stores 0 into `unit_move_wait`, so every man is due on tick 1 and then reloads together. The peaks at ticks 1, 8, 15, 22, and so on are that lockstep. `FIRE_WAIT` is 8. Leave it. A damaging shot reloads it. A miss searches again next tick, and that stays.

The flight-recorder launch flag in `tools/coop.sh` (`--history-memory=2048`) was for this measurement. It is temporary and should not be committed.

## Order of work

### 1. Phase the movement wait

In `unit_spawn` (`src/c64/world.asm`), set `unit_move_wait` from the slot modulo `MOVE_WAIT` (7). `think_all` thinks on the tick the countdown reaches 0, so a stored 1 is already due, the same as 0. Phase 0 stores 0. Phases 1–6 store 2–7. `move_reload` of 7 keeps the phase. Do not add a second gate on the frame number.

Do the same where SDL sets `unit_move_wait` at spawn (`src/sdl/game/world.c`), so the two fights stay in step with each other.

A section that steps on its first due tick then arrives over seven ticks instead of as one rank. A contested cell goes to whoever is due first. Sprint reloads 4 (`MOVE_SPRINT`), so a sprinter drifts against the walkers. That is accepted. A think that does not step does not reload, so verb none drains the phase to 0. The gate soldiers are back in step before the first order. An enemy wave is ordered before that first think, and the reload keeps its spread.

This removes the ~100,000 doorway pile from a single tick. It does not shrink the 65,000 contact floor.

### 2. Keep the deltas the scan already has

`smear_closest` (`src/c64/combat.asm`) already rejects a man whose absolute x or y delta is `RIFLE_FAR` (10) or more. The range is the larger of those two numbers. The routine then calls `chebyshev_units`, which loads the coordinates and subtracts them again. Keep the larger delta. Distance 10 still misses. Distances 5–9 still halve posture damage.

`pick_grenade` does the same with `GRENADE_RANGE` (5) and `GRENADE_MIN` (2). Keep that larger delta too. Both rejects stay: under 2 is too close, over 5 is too far.

### 3. Reject against the best so far

Once a closest man is stored, skip the next man when one absolute delta is already at least `cb_best_d`. An equal distance still loses, because the earlier slot is kept. The scan still visits anyone who might be strictly closer.

### 4. Walk the other side, not all 32 slots

`UNIT_MAX` is 32. On tick 206, twelve shooters each walked every slot. Build two packed lists at the start of `shoot_all`, players then enemies, in ascending slot order. Each shooter walks the other list only. Rebuild the lists each `shoot_all`. Spawn and death already show up through `unit_count`, and a fresh pack cannot drift from the slots.

`smear_closest` and `pick_grenade` both use the lists (`side_pl`, `side_en`, packed by `pack_sides`). Ties stay with the earlier slot because the list is in slot order. A man killed earlier in the same volley still has `unit_count` set, so the walk skips `unit_hp` 0. `grenade_friendly_in` and `find_on_cell` keep walking slots. The friendly check runs only for a man who is already on a chip and inside throw range.

Shoot timing does not change. `unit_shoot` still searches on the tick `unit_fire_wait` reaches 0, and a damaging shot still stores `FIRE_WAIT`.

## Leave alone

- No dx,dy lookup table. The range is one comparison of two numbers already in hand.
- No occupancy-map sweep out to distance 9. A 19 by 19 block is more visits than 32 men.
- No phasing of `FIRE_WAIT`, and no reload on a miss. That would delay a shot the man is allowed to take.

## Check

One farm, through contact. Step ticks should lose the doorway pile. Contact ticks should fall from the mid-60,000s toward the 40,000s. The closest man inside 9 is unchanged, distance 10 still misses, and a grenade still requires a man on his chip and a blast with no friendly in it.
