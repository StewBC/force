; Mutable world and session. Zeroed at boot. Immutable tables are rom_*.

bss_start:

; Map and mission bounds; win_* is the visible subset used by cursor and drawing.
map_w:          .res 1
map_h:          .res 1
play_x:         .res 1
play_y:         .res 1
play_w:         .res 1
play_h:         .res 1
win_x:          .res 1
win_y:          .res 1
win_w:          .res 1
win_h:          .res 1
room_count:     .res 1

; Structure-of-arrays unit pool, indexed by slot. unit_count=0 means the slot is free.
; Cover IDs below COVER_MAX name chips; IDs from COVER_MAX name scouts; NONE is unassigned.
unit_x:         .res UNIT_MAX
unit_y:         .res UNIT_MAX
unit_section:   .res UNIT_MAX
unit_count:     .res UNIT_MAX
unit_kind:      .res UNIT_MAX
unit_glyph:     .res UNIT_MAX
unit_region:    .res UNIT_MAX
unit_cover:     .res UNIT_MAX
unit_over_verb: .res UNIT_MAX
unit_over_x:    .res UNIT_MAX
unit_over_y:    .res UNIT_MAX
unit_tgt_x:     .res UNIT_MAX
unit_tgt_y:     .res UNIT_MAX
unit_step_sx:   .res UNIT_MAX
unit_step_sy:   .res UNIT_MAX
unit_step_ax:   .res UNIT_MAX
unit_step_ay:   .res UNIT_MAX
unit_step_err:  .res UNIT_MAX
unit_step_run:  .res UNIT_MAX
unit_move_wait: .res UNIT_MAX
unit_hp:        .res UNIT_MAX
unit_fire_wait: .res UNIT_MAX
unit_fx:        .res UNIT_MAX

; Sections 0-7 are player letters, 8-15 enemies. NONE is the no-leader sentinel.
; order_str snapshots strength for morale; flags defer cover work to the tick.
section_lead:        .res SECTION_MAX
section_last_x:      .res SECTION_MAX
section_last_y:      .res SECTION_MAX
section_strength:    .res SECTION_MAX
section_flags:       .res SECTION_MAX
section_order_verb:  .res SECTION_MAX
section_order_x:     .res SECTION_MAX
section_order_y:     .res SECTION_MAX
section_order_force: .res SECTION_MAX
section_order_str:   .res SECTION_MAX

room_approach:  .res ROOM_MAX
room_flags:     .res ROOM_MAX
room_heat:      .res ROOM_MAX
last_x:         .res ROOM_MAX
last_y:         .res ROOM_MAX

; Inferred room endpoints and the fixed-stride room-to-room first-hop table.
portal_from:    .res PORTAL_MAX
portal_to:      .res PORTAL_MAX
next_hop:       .res ROOM_MAX * ROOM_MAX

path_fail_who:  .res 1
shot_this_tick: .res 1
grenade_rem:    .res 2
grenade_wait:   .res 2
nade_fx_x:      .res 2
nade_fx_y:      .res 2
nade_fx_ttl:    .res 2

; Director execution state and one pending timed spawn job; clock is little-endian.
script_pc:          .res 1
script_waiting:     .res 1
script_wait_pred0:  .res 1
script_wait_pred1:  .res 1
script_wait_beat:   .res 1
spawn_room:         .res 1
spawn_job_rem:      .res 1
spawn_job_letter:   .res 1
spawn_job_room:     .res 1
spawn_job_batch:    .res 1
spawn_job_period:   .res 1
spawn_job_wait:     .res 1
script_fired:       .res 1
script_clock:       .res 2
script_outcome:     .res 1

; Window-relative cursor, command draft, and temporary camera/intel selection.
cursor_x:       .res 1
cursor_y:       .res 1
frame_lo:       .res 1
joy_present:    .res 1
stick_latched:  .res 1
cmd_verb:       .res 1
cmd_who:        .res 1
cmd_dot:        .res 1
cmd_unit:       .res 1
cmd_x:          .res 1
cmd_y:          .res 1
cmd_force:      .res 1
cmd_slot:       .res 1
cmd_digits:     .res 1
cmd_last_who:   .res 1
cmd_flash:      .res 1
cmd_nopath:     .res 1
cam_prev_ok:    .res 1
cam_prev_x:     .res 1
cam_prev_y:     .res 1
cam_prev_cx:    .res 1
cam_prev_cy:    .res 1
cam_ttl:        .res 1
cycle_kind:     .res 1
cycle_room:     .res 1

; One poll result, plus latches the border IRQ fills on every video frame.
; key_hit is rising edges. key_lvl is keys seen down since the last poll.
in_dx:          .res 1
in_dy:          .res 1
in_kind:        .res 1
in_value:       .res 1
in_restart:     .res 1
key_now:        .res 8
key_prev:       .res 8
key_hit:        .res 8
key_lvl:        .res 8
key_seen:       .res 8
joy_lat:        .res 1
scan_row:       .res 1
scan_edge:      .res 1
rise7:          .res 1
key_qual:       .res 1
key_hold:       .res 1
key_last_dx:    .res 1
key_last_dy:    .res 1
line_n:         .res 1
line_buf:       .res 40
blink:          .res 1
scr_x:          .res 1
scr_y:          .res 1

; Last picture written. The raster keeps it, so later draws compare these.
seen_count:     .res UNIT_MAX
seen_x:         .res UNIT_MAX
seen_y:         .res UNIT_MAX
seen_hp:        .res UNIT_MAX
seen_fx:        .res UNIT_MAX
seen_glyph:     .res UNIT_MAX
seen_win_x:     .res 1
seen_win_y:     .res 1
seen_hole:      .res 4
seen_line:      .res 40
seen_line_col:  .res 1
seen_cur_x:     .res 1
seen_cur_y:     .res 1
seen_cur_wx:    .res 1
seen_cur_wy:    .res 1
seen_roster:    .res LETTER_MAX
seen_stick:     .res 1
drawn:          .res 1
ui_dirty:       .res 1

; Stepper scratch. Cleared with the rest of BSS.
think_i:        .res 1
mv_ox:          .res 1
mv_oy:          .res 1
mv_dx:          .res 1
mv_dy:          .res 1
mv_p:           .res 1
mv_here:        .res 1
mv_dest:        .res 1
mv_who:         .res 1
mv_front:       .res 1
mv_lead:        .res 1
mv_holes:       .res 1
mv_dodge:       .res 1
mv_pref:        .res 1
lane_axis:      .res 1      ; 1 = horizontal keep-right axis. Not a room edge.
mv_nx:          .res 1
mv_ny:          .res 1
mv_stand:       .res 1
mv_n:           .res 1
sm_mode:        .res 1
sm_here:        .res 1
sm_next:        .res 1
sm_lo:          .res 1
sm_hi:          .res 1
ra_x0:          .res 1
ra_y0:          .res 1
ra_x1:          .res 1
ra_y1:          .res 1
rb_x0:          .res 1
rb_y0:          .res 1
rb_x1:          .res 1
rb_y1:          .res 1
hop_vis:        .res ROOM_MAX
hop_q:          .res ROOM_MAX
hop_qh:         .res 1
hop_qt:         .res 1

; map_ptr row bases. paper_off is rom_paper - rom_tiles.
row_lo:         .res MAP_ROWS
row_hi:         .res MAP_ROWS
paper_off:      .res 2

; Open cells on the doorway last asked about, indexed from the span start.
; Terrain does not change. A span longer than this is not stored.
seam_on:        .res 1
seam_a:         .res 1
seam_b:         .res 1
seam_open:      .res SEAM_SPAN

; Combat scratch, and the last grenade disk the steady draw painted.
cb_i:           .res 1
cb_j:           .res 1
cb_tgt:         .res 1
cb_sec:         .res 1
cb_verb:        .res 1
cb_bank:        .res 1
cb_bank_hi:     .res 1
cb_gbank:       .res 1
cb_dist:        .res 1
cb_best_d:      .res 1
cb_dmg:         .res 1      ; posture number for the shot in progress
cb_force:       .res 1
cb_snap:        .res 1
cb_now:         .res 1
cb_dest:        .res 1
cb_x0:          .res 1
cb_y0:          .res 1
cb_x1:          .res 1
cb_y1:          .res 1
cb_x:           .res 1
cb_y:           .res 1
cb_dx:          .res 1
cb_dy:          .res 1
cb_adx:         .res 1
cb_ady:         .res 1
cb_sx:          .res 1
cb_sy:          .res 1
cb_n:           .res 1
cb_err:         .res 1
cb_step:        .res 1
cb_kind:        .res 1
cb_dead0:       .res 1
cb_dead1:       .res 1
cb_due:         .res SECTION_MAX
disk_cx:        .res 1
disk_cy:        .res 1
seen_nade_x:    .res 2
seen_nade_y:    .res 2
seen_nade_ttl:  .res 2

; Men to stamp after vacated cells are cleared.
draw_n:         .res 1
draw_at:        .res 1
draw_i:         .res UNIT_MAX

; Scratch owned by section_peel (picked slots) and intel_pulse (enemy rooms).
; Live only inside those calls.
peel_pick:      .res UNIT_MAX
enemy_in:       .res ROOM_MAX

bss_end:
