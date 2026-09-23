# C64 pass profile

Baseline for one main-loop pass, measured 2026-09-23 on the rifle-rule
PRG (no sight ray), before the soldier redraw. Repeat it with
[`../tools/c64_profile.py`](../tools/c64_profile.py) after a change that
should move these numbers. The redraw's result is the section below.

## The pass

PAL. Cycles come from c64m `get-cpu`, so this is emulated time, not
wall-clock time. A video frame is `985248 / 50` = 19,705 cycles.

The pass starts at `input_poll` and ends at the instruction after
`jsr draw_all` (the `jmp` back to the top of the loop). It is a pass
that calls `world_tick`. `logic_acc` was 46, so `logic_acc + 15` did
not fit in 50 and this pass ticked. The other 35 of every 50 passes
only read the keyboard and draw.

Setup is F3, then `D A 64,9` (shift plus the letter): section A
defends map (64, 9). The script then stops on the first `input_poll`
where a living enemy has map x in 55–58. That is inside room 2, past
the west edge at x=53.

This run's men, all at 16 hp:

| Who | Cell |
|-----|------|
| Friendly 0 | (66, 3) |
| Friendlies 1–5 | (62, 9), (62, 11), (62, 6), (62, 12), (62, 14) |
| Enemy 11 | (55, 8) |

`drawn` was set and the window matched, so the draw took the steady
path. One enemy stepped. The six friendlies did not.

The bucket sum equalled the cycle bracket, 35,778. That is 1.82
video frames. Shares below are of this pass, rounded. They sum to
35,195. The other 583 cycles are the sprite cursor, the grenade-flash
check, the command-and-cursor tick, script, spawn, grenade cooldown,
and the few instructions between calls.

| Where the time went | Cycles | Share of this pass |
|---------------------|-------:|-------------------:|
| Drawing men | 10,080 | 28% |
| Walking | 5,353 | 15% |
| Keyboard | 4,639 | 13% |
| Targeting | 3,783 | 11% |
| Death scan | 2,775 | 8% |
| Command line | 2,740 | 8% |
| Grenade search | 2,269 | 6% |
| Shoot loop overhead | 1,923 | 5% |
| Cover | 902 | 3% |
| Hurt timers | 490 | 1% |
| Resolving the shot | 241 | 1% |

## What each row is

| Row | Routines on this pass |
|-----|------------------------|
| Drawing men | `refresh_units`, including `build_occ` |
| Walking | `think_all` |
| Keyboard | `input_poll` |
| Targeting | `smear_closest` and `find_on_cell` (2 calls, 1,558 and 2,225) |
| Death scan | `apply_deaths` (nobody died) |
| Command line | `refresh_ui` |
| Grenade search | `try_grenade` (2 calls: 51 and 2,218; no throw) |
| Shoot loop overhead | the `shoot_all` / `unit_shoot` loop, plus `weapons_free` (7 calls, about 70 each) |
| Cover | both `cover_jobs` calls |
| Hurt timers | `decay_fx` |
| Resolving the shot | `posture_damage`, `apply_hit_y`, `note_contact` (1 call, 241) |

`build_occ` fills `$C000`–`$C31F` with `$FF` before it looks at who
moved. Counted from the instructions, that fill is 5,444 cycles and
it sits inside "Drawing men". The compare then stored two cells.

A second run on this same PRG stopped on the same cell, enemy 11 at
(55, 8), and counted Drawing men at 10,080 again. The pass total
moved from 35,778 to 35,906. Keyboard, targeting, and the shoot-loop
row each shifted by about a hundred cycles. Drawing men is the stable
row, and it is the one the redraw has to shrink. Another man still
alive in that x band would move the targeting and grenade rows.

## After the soldier redraw

Same script, run again after the redraw. `logic_acc` was 46. Enemy
11 was at (55, 8) on 16 hp, and the six friendlies were on the same
houses. That pass did not step. Drawing men was 2,184 cycles, the
compare across the pool and nothing else. The pass was 27,738
cycles, 1.41 video frames.

| Where the time went | Cycles | Share of this pass |
|---------------------|-------:|-------------------:|
| Drawing men | 2,184 | 8% |
| Walking | 5,084 | 18% |
| Keyboard | 4,314 | 16% |
| Targeting | 4,107 | 15% |
| Death scan | 2,782 | 10% |
| Command line | 2,732 | 10% |
| Grenade search | 2,269 | 8% |
| Shoot loop overhead | 1,923 | 7% |
| Cover | 902 | 3% |
| Hurt timers | 490 | 2% |
| Resolving the shot | 241 | 1% |

Those rows sum to 27,028. The other 710 cycles are the sprite cursor,
the grenade-flash check, and the calls between the timed routines.

A separate logic pass stepped enemy 11 from (55, 8) to (56, 8) at
1 hp with the hurt tint set. `refresh_units` on that pass was
4,054 cycles: the same scan, the map character in the cell he
left, his index on the cell he entered, and one composite. Both
cells are tile `$70`. A quiet pass stays 2,184. The script stops
on the first logic tick in that x band, so a repeat can land on
either row depending on whether his move wait expires that tick.
