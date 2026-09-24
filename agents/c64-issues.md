# C64 source review — 2026-09-24

Scope: handwritten `src/c64`, excluding `generated`. These are concrete review
findings and follow-up checks, not a proposed replacement architecture. Routine
names below are stable anchors within the named files. SDL remains the behaviour
reference. Fix one item at a time and verify it in c64m before combining changes.

## Fixed in this pass

- `force.asm: clear_bss`: reload zero inside the loop. Pointer comparisons left
  A nonzero, so the original loop filled most BSS with address bytes.
- `world.asm: world_load`: reload NONE for every section leader. Previously only
  section 15 received NONE; sections 0–14 received zero from the preceding pass.
- Removed dead command-label data and cancelling DEY/INY work in `paint_holes`,
  an overwritten path-failure store, unnecessary nested X saves in `unit_spawn`,
  an unused east-edge calculation/branch, and redundant accumulator loads.
- Added purpose/contract and sequence comments. Generated files were untouched.

## 1. Movement helpers do not consistently preserve caller state — high priority

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

## 2. MOVE arrival can reserve the wrong cover ID — high priority

**Evidence:** `move.asm: occupy_chip` passes the chip ID in A to `cover_taken`,
then stores A into `unit_cover`. `cover_taken` returns carry but leaves A holding
the last scanned count/cover byte, not the input chip ID. Its saved input is
in `zT0`. A successful unclaimed-chip lookup can thus store zero or another ID.

**Next steps:** establish an explicit result contract, preserve the selected
ID, and test chip 0, a nonzero chip, a scout ID and an already-reserved chip.
Verify facing, damage protection and reassignment after arrival, not just the
destination cell.

## 3. Reused unit slots retain old pacing/effect state — high priority

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

## 4. First path failure destroys unrelated section flags

**Evidence:** `move.asm: fail_path` loads `section_flags`, masks it with
`FLAG_NOPATH`, then ORs and stores that masked value. On first failure the
stored value is just `FLAG_NOPATH`, losing ASSIGN, RELEASE, BREAKING and CONTACT.

**Next steps:** preserve the original flags when setting NOPATH. Exercise failure
with each other flag set, repeated failure, and a subsequent order that clears
NOPATH. Check both the section state and the one-tick player notification.

## 5. Seam cache indexes can exceed its allocation — high priority for other rooms

**Evidence:** `bss.asm` allocates `seam_open` as 40 bytes. `move.asm: seam_ensure`
and `seam_hit` index it with absolute `mv_p`. On a horizontal seam, `mv_p` is a
map X coordinate, while this map is 80 columns wide. An opening at x=40 or later
addresses the combat scratch immediately following the cache. The narrow farm
route does not establish safety for every room pair.

**Next steps:** reproduce with a horizontal seam east of x=39 and guard bytes
after the cache. Choose relative seam indexing or an allocation bounded by the
largest coordinate range. Audit the fixed 40-row map lookup limit and generator
capacity checks at the same time; do not silently accept unsupported maps.

## 6. Full UI repaint and its comparison caches can disagree

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

## 7. Input repeat wraps; opposite controls have fall-through surprises

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

## 8. Command confirmation can show a different force from the issued order

**Evidence:** `command.asm: show_ok` takes displayed force in A. The normal
`commit::do_issue` path calls `section_issue`, then loads the confirmed Y
coordinate into A immediately before jumping to `show_ok`. `zA4` still contains
the issued force, but is not loaded. The order can execute correctly while the
SHOW line displays its Y coordinate as force. SPLIT/JOIN formatting also goes
through the shortened coordinate formatter despite WHERE being a letter.

**Next steps:** make the confirmation contract explicit across all callers.
Compare typed/default force, HALT, FOCUS, SPLIT and JOIN with the draft and actual
world order. Keep this separate from implementing the currently stubbed verbs.

## 9. Existing incomplete port features remain open

`world.asm` still rejects peel/join/nudge and returns NONE for intel helpers.
Script watches, contact-on-arrival and intel pulse are absent from the tick.
These are already described in `c64-port.md`; they were not implemented during
this commenting/review pass. Implement each against SDL with a focused scenario,
then check farm loss, the overrun spawn-room change and all three waves.

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

## Verification for this pass

- Direct am65 assembly before and after; no segment overlap.
- Windowed PAL c64m startup breakpoints: all 1,947 BSS bytes zero after clearing;
  all 16 section leaders NONE before spawning; six current-map friendly units
  and the correct section-0 leader after mission load.
- Screen RAM contains all four wizard labels after the first paint; the next
  input/logic/raster/draw iteration returns to `input_poll`.
- These checks validate the small edits above, not the deferred findings or a
  complete playable mission. Review findings have not all been runtime-reproduced.
