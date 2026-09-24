.proc session_init
    lda win_w
    lsr
    sta cursor_x
    lda win_h
    lsr
    sta cursor_y
    lda #0
    sta frame_lo
    sta drawn
    sta cam_prev_ok
    sta cam_ttl
    sta cycle_kind
    sta cmd_nopath
    lda #NONE
    sta cycle_room
    jmp cmd_init
.endproc

.proc cursor_cell
    lda win_x
    clc
    adc cursor_x
    sta zA0
    lda win_y
    clc
    adc cursor_y
    sta zA1
    rts
.endproc

.proc game_tick
    lda in_restart
    beq live
    jsr world_load
    jsr session_init
    jmp logic
live:
    lda cmd_flash
    beq no_flash
    dec cmd_flash
    bne no_flash
    lda #0
    sta cmd_nopath
    lda #1
    sta ui_dirty
no_flash:
    jsr move_cursor
    jsr cmd_feed
logic:
    inc frame_lo
    jsr world_tick
    lda in_restart
    bne done
    lda script_outcome
    bne cam
    lda path_fail_who
    cmp #LETTER_MAX
    bcs cam
    lda #1
    sta cmd_nopath
    lda #8
    sta cmd_flash
cam:
    lda cam_ttl
    beq done
    dec cam_ttl
    bne done
    jsr camera_back
done:
    rts
.endproc

.proc move_cursor
    lda in_dx
    beq do_y
    bmi left
    inc cursor_x
    lda cursor_x
    cmp win_w
    bcc moved_x
    lda win_w
    sec
    sbc #1
    sta cursor_x
    jmp do_y
moved_x:
    lda #1
    sta ui_dirty
    jmp do_y
left:
    lda cursor_x
    beq do_y
    dec cursor_x
    lda #1
    sta ui_dirty
do_y:
    lda in_dy
    beq done
    bmi up
    inc cursor_y
    lda cursor_y
    cmp win_h
    bcc moved_y
    lda win_h
    sec
    sbc #1
    sta cursor_y
    rts
moved_y:
    lda #1
    sta ui_dirty
    rts
up:
    lda cursor_y
    beq done
    dec cursor_y
    lda #1
    sta ui_dirty
done:
    rts
.endproc

.proc camera_save
    lda #1
    sta cam_prev_ok
    lda win_x
    sta cam_prev_x
    lda win_y
    sta cam_prev_y
    lda cursor_x
    sta cam_prev_cx
    lda cursor_y
    sta cam_prev_cy
    rts
.endproc

.proc camera_focus
    jsr world_clamp_play
    jsr camera_save
    lda zA0
    sec
    sbc win_x
    bcs cx_ok
    lda #0
cx_ok:
    cmp win_w
    bcc cx_st
    lda win_w
    sec
    sbc #1
cx_st:
    sta cursor_x
    lda zA1
    sec
    sbc win_y
    bcs cy_ok
    lda #0
cy_ok:
    cmp win_h
    bcc cy_st
    lda win_h
    sec
    sbc #1
cy_st:
    sta cursor_y
    lda #0
    sta cam_ttl
    rts
.endproc

.proc camera_back
    lda cam_prev_ok
    bne have
    clc
    rts
have:
    lda win_x
    pha
    lda win_y
    pha
    lda cursor_x
    pha
    lda cursor_y
    pha
    lda cam_prev_x
    sta win_x
    lda cam_prev_y
    sta win_y
    lda cam_prev_cx
    sta cursor_x
    lda cam_prev_cy
    sta cursor_y
    pla
    sta cam_prev_cy
    pla
    sta cam_prev_cx
    pla
    sta cam_prev_y
    pla
    sta cam_prev_x
    lda #0
    sta cam_ttl
    sec
    rts
.endproc
