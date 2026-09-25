# C64 source review — 2026-09-24

Scope: handwritten `src/c64`, excluding `generated`. These are concrete review
findings and follow-up checks, not a proposed replacement architecture. Routine
names below are stable anchors within the named files. SDL remains the behaviour
reference. Fix one item at a time and verify it in c64m before combining changes.

## Resolution — 2026-09-24

Items 1–5, 7 and 8 were real differences from the SDL game and are fixed.
Item 6 does not hold. Item 9 (contact, intel, peel/join) played correctly.
Item 10 stays open: space/speed ideas that still want a measurement first.

CODE ends at exclusive `$9FFA`. The room from there to occupancy at `$C000` is `$2006` bytes, of which `$A000`–`$BFFF` is the 8K under BASIC. SPARE is `$2800`–`$3181`.
Exit despawn is still `$2800`–`$2A2B`. The SPLIT/JOIN status lines, the seam
cache, the script watches, peel/join, and the intel pulse follow it. Occupancy is `$C000`–`$C31F`. BSS is end-anchored at `$CFFF` and runs `$C7D2`–`$CFFF`.

A headless PAL boot reached the frame loop with farm tiles on row 0, the four
wizard labels on row 20, section 0 led, and the script already spawning. That
does not replay the sidestep, doorway, or confirmation cases.

## Fixed in this pass

- `force.asm: clear_bss`: reload zero inside the loop. Pointer comparisons left
  A nonzero, so the original loop filled most BSS with address bytes.
- `world.asm: world_load`: reload NONE for every section leader. Previously only
  section 15 received NONE; sections 0–14 received zero from the preceding pass.
- Removed dead command-label data and cancelling DEY/INY work in `paint_holes`,
  an overwritten path-failure store, unnecessary nested X saves in `unit_spawn`,
  an unused east-edge calculation/branch, and redundant accumulator loads.
- Added purpose/contract and sequence comments. Generated files were untouched.

## 1. Movement helpers do not consistently preserve caller state — fixed

**Evidence:** `move.asm: side_step` reads `unit_x,x` / `unit_y,x` after a failed
`try_step`, without restoring X from `think_i`. `try_step` calls `is_portal`
and `region_at`, which use X as a scan index. Failure paths can therefore leave
X naming a portal or room rather than the moving unit. The mirrored sidestep
can be computed from another unit's position.

`keep_right` stores its dominant-axis choice in `rb_y0` through `lane_signs`,
then calls `same_edge`, which overwrites `rb_y0` with a portal room endpoint.
`lane_better` subsequently interprets that room ID as the axis choice.

**Next steps:** define the clobber contract of each helper in these two call
chains; preserve the unit index and lane-axis state explicitly. Check failed
first sidesteps, blocked portals and two adjacent portals for all four travel
directions, including moving slots whose index differs from the room ID.

`side_step` reloads `think_i` before the mirrored sidestep. `lane_signs` stores
the axis in `lane_axis`. `same_edge` still uses `rb_y0` as a room edge.

## 2. MOVE arrival can reserve the wrong cover ID — fixed

**Evidence:** `move.asm: occupy_chip` passes the chip ID in A to `cover_taken`,
then stores A into `unit_cover`. `cover_taken` returns carry but leaves A holding
the last scanned count/cover byte, not the input chip ID. Its saved input is
in `zT0`. A successful unclaimed-chip lookup can thus store zero or another ID.

**Next steps:** establish an explicit result contract, preserve the selected
ID, and test chip 0, a nonzero chip, a scout ID and an already-reserved chip.
Verify facing, damage protection and reassignment after arrival, not just the
destination cell.

`occupy_chip` stores `zT0`, the id `cover_taken` saved. A remains scratch.

## 3. Reused unit slots retain old pacing/effect state — fixed

**Evidence:** `world.asm: unit_spawn` initializes position, identity, count, HP,
cover and target, but not `unit_move_wait`, `unit_fire_wait`, `unit_fx`, or the
stepper fields. Boot/restart clears some of these in `world_load`; deaths and
exit despawning do not clear all of them. Later spawn waves reuse free slots.
SDL's `force_unit_spawn` initializes those fields for every new occupant.

**Next steps:** compare the complete spawn contract with SDL, then initialize
all per-lifetime fields in one place. Kill/despawn a unit with nonzero waits,
reuse its slot, and verify immediate movement/fire eligibility and clean effects.
Also decide whether the C64 spawn API should reject invalid section/count
arguments as SDL does, or explicitly require validated callers.

`unit_spawn` clears the override, stepper, fire-wait and effect fields, sets
move wait to the slot phase, and returns NONE for a zero count or a section
past `SECTION_MAX`, as `force_unit_spawn` does.

## 4. First path failure destroys unrelated section flags — fixed

**Evidence:** `move.asm: fail_path` loads `section_flags`, masks it with
`FLAG_NOPATH`, then ORs and stores that masked value. On first failure the
stored value is just `FLAG_NOPATH`, losing ASSIGN, RELEASE, BREAKING and CONTACT.

**Next steps:** preserve the original flags when setting NOPATH. Exercise failure
with each other flag set, repeated failure, and a subsequent order that clears
NOPATH. Check both the section state and the one-tick player notification.

`fail_path` ORs `FLAG_NOPATH` onto the flags already stored.

## 5. Seam cache indexes can exceed its allocation — fixed

**Evidence:** `bss.asm` allocates `seam_open` as 40 bytes. `move.asm: seam_ensure`
and `seam_hit` index it with absolute `mv_p`. On a horizontal seam, `mv_p` is a
map X coordinate, while this map is 80 columns wide. An opening at x=40 or later
addresses the combat scratch immediately following the cache. The narrow farm
route does not establish safety for every room pair.

**Next steps:** reproduce with a horizontal seam east of x=39 and guard bytes
after the cache. Choose relative seam indexing or an allocation bounded by the
largest coordinate range. Audit the fixed 40-row map lookup limit and generator
capacity checks at the same time; do not silently accept unsupported maps.

The per-man `seam_open` cache is gone. `bake_doors` stores each shared wall's
open cells once, and a span longer than 20 is walked live. `gen_c64.py` rejects
a map taller than 40 rows, a width other than 80, more than 16 rooms, a room
edge over 40, and portal, cover or scout counts past the tables. `build_rows`
still refuses to write past `row_lo`.

## 6. Full UI repaint and its comparison caches can disagree — no change

**Evidence:** `draw.asm: draw_ui` paints current UI state but does not synchronize
`seen_hole`, `seen_line`, cursor, roster or host caches. `session_init` invalidates
`drawn` without resetting those caches. If a post-restart state equals an old
cache value but differs from the full paint, the next refresh can skip a needed
write. `field` also calls `refresh_ui` after a window move without updating
`seen_win_x/y`, so a changed window can keep forcing full field paints.

**Next steps:** give full paints a single cache synchronization/invalidation
policy. Change wizard highlight and roster selection, restart, then return to
the pre-restart selection. Check every UI component and repeated frames after
a window change. Preserve the two-pass vacate/stamp ordering for units.

`remember_units` stores `seen_win_x/y` on both the full paint and the window
path, so a moved window does not stick there. `draw_ui` paints the live UI.
A stale cache either matches that paint, and the next refresh correctly skips,
or it differs and the next refresh rewrites. It does not leave a cell wrong.

## 7. Input repeat wraps; opposite controls have fall-through surprises — fixed

**Evidence:** `input.asm: same` increments the eight-bit `key_hold` indefinitely.
After wrap, the initial delay is re-entered, causing a pause during a long hold.
In the cursor-right/down paths, `inc zT6` / `inc zT7` followed by BNE falls into
the left/up decrement when an opposing input makes the sum zero. For example,
A plus unshifted cursor-right fails to cancel as the surrounding accumulation
code suggests.

**Next steps:** compare long-hold and conflicting-input behaviour with SDL;
separate initial delay from the bounded repeat phase. Test beyond 256 polls,
direction changes, Shift, WASD and joystick combinations before changing input
priority or latching behaviour.

Unshifted cursor right and down always skip the opposite decrement, so A plus
cursor-right cancels. The counter no longer wraps into the delay. The cadence
itself is now a four-poll wait and then every logic poll, because a logic poll
is three video frames and the old 14-then-every-4 count made a hold feel like
a tap.

## 8. Command confirmation can show a different force from the issued order — fixed

**Evidence:** `command.asm: show_ok` takes displayed force in A. The normal
`commit::do_issue` path calls `section_issue`, then loads the confirmed Y
coordinate into A immediately before jumping to `show_ok`. `zA4` still contains
the issued force, but is not loaded. The order can execute correctly while the
SHOW line displays its Y coordinate as force. SPLIT/JOIN formatting also goes
through the shortened coordinate formatter despite WHERE being a letter.

**Next steps:** make the confirmation contract explicit across all callers.
Compare typed/default force, HALT, FOCUS, SPLIT and JOIN with the draft and actual
world order. Keep this separate from implementing the currently stubbed verbs.

`do_issue` passes `zA4` to `show_ok`. SPLIT keeps its count on the stack across
`section_peel` and shows Y as 0. The status line prints SPLIT and JOIN as
letters, and FOCUS without a WHO character. A zero focus count omits the force
suffix. Peel and join now run, so those confirmations are reachable. An
individual `.` order is `unit_nudge`.

## 9. Contact, intel, and peel/join are coded

`contact_start` runs after the spawn. `intel_pulse` runs after exit despawn.
`section_peel` and `section_join` return carry on success, and the intel
cyclers walk heat and marks. Individual `.` orders still go through
`unit_nudge`. Script watches run.
Played: an attack holes up on entering its room, Shift+C / Shift+E cycle,
and `S A B` / `J B A` move men. Farm loss, the overrun spawn-room change,
and all three waves were already in.

## 10. Measure before broader speed/space changes

- `draw.asm: cell_addr` and `scr_and_occ` duplicate row*40 arithmetic. Row tables
  or a shared offset helper could save cycles/code, with RAM and call overhead
  tradeoffs. Measure changed-unit and grenade-heavy frames, not only idle frames.
- `command.asm: copy_ready` and `line_str` are identical. Label-pointer tables
  could also replace `paint_holes`' branch ladder. These are straightforward
  future space reductions once callers and flags are checked.
- `world.asm: cell_open` still saves/restores X around `map_ptr`, although the
  current row-table implementation preserves X. Removing the zT7 store requires
  auditing callers for accidental dependence on that side effect.
- `world_tick` recounts deaths/strength and scans multiple unit arrays even on
  quiet ticks; `refresh_ui` ignores `ui_dirty` and rebuilds/compares status each
  draw. Use existing `tools/c64_profile.py` measurements before adding dirty
  state or caches that increase invalidation complexity.
- Fixed code space ends at BSS $A000. This pass moves CODE's exclusive end from
  $9FB1 to $9F6A: **71 bytes saved, 150 bytes remain**. SPARE is unchanged at
  $2800–$2A2B. Treat code placement and capacity assertions as part of any larger
  implementation; the old handoff's address/free-space estimate was stale.

  After the fixes above, and after contact/intel/peel landed in SPARE, CODE
  ended at exclusive `$9F84` (124 bytes free) and SPARE ran through `$30B8`.
  The duplicate copy and the row multiply were not changed. Current ends are
  in the resolution block above.

## Verification for this pass

- Direct am65 assembly before and after; no segment overlap.
- Windowed PAL c64m startup breakpoints: all 1,947 BSS bytes zero after clearing;
  all 16 section leaders NONE before spawning; six current-map friendly units
  and the correct section-0 leader after mission load.
- Screen RAM contains all four wizard labels after the first paint; the next
  input/logic/raster/draw iteration returns to `input_poll`.
- These checks validate the small edits above, not the deferred findings or a
  complete playable mission. Review findings have not all been runtime-reproduced.
