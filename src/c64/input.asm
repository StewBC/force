; Keyboard matrix and joystick port 2. One command edge per frame, cursor with repeat.

bitcol: .byte $01,$02,$04,$08,$10,$20,$40,$80

; A-Z as row*8+col.
letter_rc:
    .byte 1*8+2, 3*8+4, 2*8+4, 2*8+2, 1*8+6, 2*8+5, 3*8+2
    .byte 3*8+5, 4*8+1, 4*8+2, 4*8+5, 5*8+2, 4*8+4, 4*8+7
    .byte 4*8+6, 5*8+1, 7*8+6, 2*8+1, 1*8+5, 2*8+6, 3*8+6
    .byte 3*8+7, 1*8+1, 2*8+7, 3*8+1, 1*8+4

digit_rc:
    .byte 4*8+3, 7*8+0, 7*8+3, 1*8+0, 1*8+3
    .byte 2*8+0, 2*8+3, 3*8+0, 3*8+3, 4*8+0

; X is the caller's index (digit and letter walks). Do not keep the row in X.
.proc key_edge
    sta zT0
    txa
    pha
    tya
    pha
    lda zT0
    and #7
    tay
    lda zT0
    lsr
    lsr
    lsr
    tax
    lda key_now,x
    and bitcol,y
    beq up
    lda key_prev,x
    and bitcol,y
    bne up
    pla
    tay
    pla
    tax
    sec
    rts
up:
    pla
    tay
    pla
    tax
    clc
    rts
.endproc

.proc key_down
    sta zT0
    txa
    pha
    tya
    pha
    lda zT0
    and #7
    tay
    lda zT0
    lsr
    lsr
    lsr
    tax
    lda key_now,x
    and bitcol,y
    beq up
    pla
    tay
    pla
    tax
    sec
    rts
up:
    pla
    tay
    pla
    tax
    clc
    rts
.endproc

.proc input_poll
    lda #0
    sta in_dx
    sta in_dy
    sta in_kind
    sta in_value
    sta in_restart
    sei
    lda #$FF
    sta $DC02
    lda #0
    sta $DC03
    lda #$FE
    sta zT0
    ldy #0
scan:
    lda zT0
    sta $DC00
    lda $DC01
    eor #$FF
    sta key_now,y
    sec
    rol zT0
    iny
    cpy #8
    bne scan
    lda #0
    sta $DC02
    lda $DC00
    eor #$FF
    and #$1F
    sta zT4
    lda #$FF
    sta $DC02
    cli

    lda #1*8+7
    jsr key_down
    bcs shifted
    lda #6*8+4
    jsr key_down
    bcc no_shift
shifted:
    lda #1
    sta zT5
    bne have_shift
no_shift:
    lda #0
    sta zT5
have_shift:
    lda #0
    sta zT6
    sta zT7
    lda stick_latched
    bne no_wasd
    lda zT5
    bne no_wasd
    lda #1*8+2
    jsr key_down
    bcc na
    dec zT6
na:
    lda #2*8+2
    jsr key_down
    bcc nd
    inc zT6
nd:
    lda #1*8+1
    jsr key_down
    bcc nw
    dec zT7
nw:
    lda #1*8+5
    jsr key_down
    bcc no_wasd
    inc zT7
no_wasd:
    lda #0*8+2
    jsr key_down
    bcc no_lr
    lda zT5
    bne lr_left
    inc zT6
    bne no_lr
lr_left:
    dec zT6
no_lr:
    lda #0*8+7
    jsr key_down
    bcc no_ud
    lda zT5
    bne ud_up
    inc zT7
    bne joy
ud_up:
    dec zT7
joy:
no_ud:
    lda zT4
    and #4
    beq jnl
    dec zT6
    lda #1
    sta stick_latched
jnl:
    lda zT4
    and #8
    beq jnr
    inc zT6
    lda #1
    sta stick_latched
jnr:
    lda zT4
    and #1
    beq jnu
    dec zT7
    lda #1
    sta stick_latched
jnu:
    lda zT4
    and #2
    beq jnd
    inc zT7
    lda #1
    sta stick_latched
jnd:
    lda zT6
    beq dx0
    bmi dxm
    lda #1
    sta in_dx
    bne dy
dxm:
    lda #$FF
    sta in_dx
dx0:
dy:
    lda zT7
    beq dy0
    bmi dym
    lda #1
    sta in_dy
    bne rep
dym:
    lda #$FF
    sta in_dy
dy0:
rep:
    lda in_dx
    ora in_dy
    bne moving
    lda #0
    sta key_hold
    beq cmds
moving:
    lda key_hold
    bne held
    lda #1
    sta key_hold
    lda in_dx
    sta key_last_dx
    lda in_dy
    sta key_last_dy
    jmp cmds
held:
    lda in_dx
    cmp key_last_dx
    bne fresh
    lda in_dy
    cmp key_last_dy
    beq same
fresh:
    lda #1
    sta key_hold
    lda in_dx
    sta key_last_dx
    lda in_dy
    sta key_last_dy
    jmp cmds
same:
    inc key_hold
    lda key_hold
    cmp #14
    bcc stop_move
    sec
    sbc #14
    and #3
    beq cmds
stop_move:
    lda #0
    sta in_dx
    sta in_dy
cmds:
    lda #0*8+5
    jsr key_edge
    bcc no_f3
    lda #1
    sta in_restart
no_f3:
    lda #7*8+1
    jsr key_edge
    bcc no_esc
    lda #CMD_ESC
    sta in_kind
    jmp done_cmd
no_esc:
    lda #0*8+1
    jsr key_edge
    bcc no_ret
    lda #CMD_RETURN
    sta in_kind
    jmp done_cmd
no_ret:
    lda #0*8+0
    jsr key_edge
    bcc no_del
    lda #CMD_DEL
    sta in_kind
    jmp done_cmd
no_del:
    lda #5*8+7
    jsr key_edge
    bcc no_comma
    lda #CMD_COMMA
    sta in_kind
    jmp done_cmd
no_comma:
    lda #7*8+4
    jsr key_edge
    bcc no_space
    lda #CMD_SPACE
    sta in_kind
    jmp done_cmd
no_space:
    lda #5*8+4
    jsr key_edge
    bcc no_dot
    lda #CMD_PERIOD
    sta in_kind
    jmp done_cmd
no_dot:
    ldx #0
dig:
    lda digit_rc,x
    jsr key_edge
    bcc next_d
    lda #CMD_DIGIT
    sta in_kind
    stx in_value
    jmp done_cmd
next_d:
    inx
    cpx #10
    bne dig
    lda stick_latched
    ora zT5
    beq done_cmd
    ldx #0
let:
    lda letter_rc,x
    jsr key_edge
    bcc next_l
    lda #CMD_LETTER
    sta in_kind
    stx in_value
    jmp done_cmd
next_l:
    inx
    cpx #26
    bne let
done_cmd:
    ldx #0
copyk:
    lda key_now,x
    sta key_prev,x
    inx
    cpx #8
    bne copyk
    rts
.endproc
