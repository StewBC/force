; Four-slot wizard. VERB WHO WHERE FORCE. Shift+letter talks.

verb_tab:
    .byte VERB_ATTACK, VERB_BUILD, 0, VERB_DEFEND, 0, VERB_FOCUS, 0, VERB_HALT
    .byte 0, VERB_JOIN, VERB_KILL, 0, VERB_MOVE, 0, 0, 0
    .byte 0, VERB_RETREAT, VERB_SPLIT, 0, 0, 0, 0, 0, 0, 0

verb_name_lo:
    .byte <nm_none, <nm_move, <nm_def, <nm_halt, <nm_atk, <nm_ret, <nm_kill, <nm_spl, <nm_join, <nm_foc, <nm_bld
verb_name_hi:
    .byte >nm_none, >nm_move, >nm_def, >nm_halt, >nm_atk, >nm_ret, >nm_kill, >nm_spl, >nm_join, >nm_foc, >nm_bld

nm_none: .byte 0
nm_move: .byte "MOVE", 0
nm_def:  .byte "DEFEND", 0
nm_halt: .byte "HALT", 0
nm_atk:  .byte "ATTACK", 0
nm_ret:  .byte "RETREAT", 0
nm_kill: .byte "KILL", 0
nm_spl:  .byte "SPLIT", 0
nm_join: .byte "JOIN", 0
nm_foc:  .byte "FOCUS", 0
nm_bld:  .byte "BUILD", 0

hole_x: .byte 1, 8, 14, 22
hole_len: .byte 4, 3, 5, 5

;-----------------------------------------------------------------------------
; Reset the wizard and choose the first nonempty player section as its fallback.
.proc cmd_init
    jsr draft_reset
    lda #NONE
    sta cmd_last_who
    ldx #0
seek:
    lda section_strength,x
    beq nxt
    stx cmd_last_who
    rts
nxt:
    inx
    cpx #LETTER_MAX
    bne seek
    rts
.endproc

;-----------------------------------------------------------------------------
; Discard the draft; NONE distinguishes omitted fields from a typed zero.
.proc draft_reset
    lda #VERB_NONE
    sta cmd_verb
    lda #NONE
    sta cmd_who
    sta cmd_unit
    sta cmd_force
    lda #0
    sta cmd_dot
    sta cmd_x
    sta cmd_y
    sta cmd_slot
    sta cmd_digits
    sta cmd_flash
    sta cmd_nopath
    rts
.endproc

;-----------------------------------------------------------------------------
; Keep invalid-command feedback visible for eight logic ticks.
.proc flash
    lda #8
    sta cmd_flash
    rts
.endproc

;-----------------------------------------------------------------------------
; Map an A-Z index in A to a verb, returning zero for an unbound letter.
.proc verb_from_letter
    cmp #26
    bcc ok
    lda #0
    rts
ok:
    tax
    lda verb_tab,x
    rts
.endproc

;-----------------------------------------------------------------------------
; C = set when WHERE names a section (SPLIT/JOIN), rather than a cell.
.proc letter_where
    lda cmd_verb
    cmp #VERB_SPLIT
    beq yes
    cmp #VERB_JOIN
    beq yes
    clc
    rts
yes:
    sec
    rts
.endproc

;-----------------------------------------------------------------------------
; Find the first occupied unit slot at the cursor; return its index or NONE in A.
.proc implied_unit
    jsr cursor_cell
    ldx #0
next:
    lda unit_count,x
    beq skip
    lda unit_x,x
    cmp zA0
    bne skip
    lda unit_y,x
    cmp zA1
    bne skip
    txa
    rts
skip:
    inx
    cpx #UNIT_MAX
    bne next
    lda #NONE
    rts
.endproc

;-----------------------------------------------------------------------------
; Resolve the cursor to a player section, rejecting empty cells and enemies.
.proc implied_who
    jsr implied_unit
    cmp #NONE
    beq none
    tax
    lda unit_section,x
    cmp #LETTER_MAX
    bcs none
    rts
none:
    lda #NONE
    rts
.endproc

;-----------------------------------------------------------------------------
; Route one input token through the wizard's current slot.
; CMD_ESC (RUN/STOP or left-arrow) cancels the draft globally.
.proc cmd_feed
    lda in_kind
    bne go
    rts
go:
    ldx #1
    stx ui_dirty
    cmp #CMD_ESC
    bne not_esc
    jsr draft_reset
    lda #0
    sta cycle_kind
    lda #NONE
    sta cycle_room
    rts
not_esc:
    cmp #CMD_SPACE
    bne not_sp
    lda cycle_kind
    beq as_comma
    lda cmd_slot
    beq snap
    cmp #SLOT_SHOW
    bne as_comma
snap:
    jmp cycle_snap
as_comma:
    lda #CMD_COMMA
not_sp:
    sta zT7
    lda cmd_slot
    cmp #SLOT_WHO
    bne n_who
    jmp slot_who
n_who:
    cmp #SLOT_WHERE_X
    bne n_wx
    jmp slot_num
n_wx:
    cmp #SLOT_WHERE_Y
    bne n_wy
    jmp slot_num
n_wy:
    cmp #SLOT_FORCE
    bne n_wf
    jmp slot_num
n_wf:
    cmp #SLOT_SHOW
    bne n_show
    jmp slot_show
n_show:
    lda zT7
    cmp #CMD_LETTER
    beq is_letter
    jmp bad
is_letter:
    lda in_value
    jsr accept_instant
    bcc do_verb
    jmp fed
do_verb:
    lda in_value
    jmp accept_verb
bad:
    lda zT7
    cmp #CMD_RETURN
    bne n_ret
    jmp fed
n_ret:
    cmp #CMD_DEL
    bne n_del
    jmp fed
n_del:
    jmp flash
slot_show:
    lda zT7
    cmp #CMD_LETTER
    bne show_other
    lda in_value
    jsr accept_instant
    bcc show_verb
    jmp fed
show_verb:
    lda in_value
    jsr verb_from_letter
    beq show_acc
    jsr draft_reset
show_acc:
    lda in_value
    jmp accept_verb
show_other:
    cmp #CMD_DEL
    bne show_nop
    jmp draft_reset
show_nop:
    cmp #CMD_RETURN
    bne sn1
    jmp fed
sn1:
    cmp #CMD_DIGIT
    bne sn2
    jmp fed
sn2:
    cmp #CMD_COMMA
    bne sn3
    jmp fed
sn3:
    jmp flash
slot_who:
    lda zT7
    cmp #CMD_LETTER
    bne who_dot
    lda in_value
    jmp accept_who
who_dot:
    cmp #CMD_PERIOD
    bne who_ret
    jmp accept_period
who_ret:
    cmp #CMD_RETURN
    bne who_del
    jmp commit
who_del:
    cmp #CMD_DEL
    bne bad
    jmp pop_slot
slot_num:
    jsr letter_where
    bcc num_digit
    lda cmd_slot
    cmp #SLOT_WHERE_X
    bne num_digit
    lda zT7
    cmp #CMD_LETTER
    bne num_digit
    lda in_value
    cmp #LETTER_MAX
    bcc who_letter
    jmp flash
who_letter:
    sta cmd_x
    lda #0
    sta cmd_digits
    lda cmd_verb
    cmp #VERB_SPLIT
    beq split_force
    jmp fed
split_force:
    lda #SLOT_FORCE
    sta cmd_slot
    lda #NONE
    sta cmd_force
    rts
num_digit:
    lda zT7
    cmp #CMD_DIGIT
    bne num_sep
    jsr letter_where
    bcc dig_ok
    lda cmd_slot
    cmp #SLOT_WHERE_X
    bne dig_ok
    jmp flash
dig_ok:
    lda in_value
    jmp accept_digit
num_sep:
    cmp #CMD_COMMA
    bne num_ret
    jmp accept_sep
num_ret:
    cmp #CMD_RETURN
    bne num_del
    jmp commit
num_del:
    cmp #CMD_DEL
    beq do_pop
    jmp flash
do_pop:
    jmp pop_slot
fed:
    rts
.endproc

;-----------------------------------------------------------------------------
; Handle BACK and intel cycling without creating a draft. C = token consumed.
.proc accept_instant
    sta zA4
    cmp #6
    bne not_b
    jsr camera_back
    bcs ok_i
    jsr flash
ok_i:
    sec
    rts
not_b:
    cmp #2
    beq cyc
    cmp #23
    bne not_c
cyc:
    lda #1
    jsr cycle_list
    sec
    rts
not_c:
    lda zA4
    cmp #4
    bne no
    lda #2
    jsr cycle_list
    sec
    rts
no:
    clc
    rts
.endproc

;-----------------------------------------------------------------------------
; Start a fresh verb draft; FOCUS skips WHO and goes directly to coordinates.
.proc accept_verb
    jsr verb_from_letter
    bne ok
    jmp flash
ok:
    sta cmd_verb
    lda #NONE
    sta cmd_who
    sta cmd_unit
    sta cmd_force
    lda #0
    sta cmd_dot
    sta cmd_digits
    sta cmd_y
    jsr letter_where
    bcc cell_x
    lda #NONE
    sta cmd_x
    jmp who_slot
cell_x:
    lda #0
    sta cmd_x
who_slot:
    lda cmd_verb
    cmp #VERB_FOCUS
    bne who
    lda #SLOT_WHERE_X
    sta cmd_slot
    rts
who:
    lda #SLOT_WHO
    sta cmd_slot
    rts
.endproc

;-----------------------------------------------------------------------------
; Accept player letter A-H and advance to WHERE unless the verb is HALT.
.proc accept_who
    cmp #LETTER_MAX
    bcc ok
    jmp flash
ok:
    sta cmd_who
    lda #0
    sta cmd_dot
    sta cmd_digits
    lda #NONE
    sta cmd_unit
    lda cmd_verb
    cmp #VERB_HALT
    beq stay
    lda #SLOT_WHERE_X
    sta cmd_slot
    jsr letter_where
    bcc zero_x
    lda #NONE
    sta cmd_x
    rts
zero_x:
    lda #0
    sta cmd_x
stay:
    rts
.endproc

;-----------------------------------------------------------------------------
; Bind the draft to the friendly unit under the cursor for an individual order.
.proc accept_period
    jsr letter_where
    bcs bad
    lda cmd_verb
    beq bad
    jsr implied_unit
    cmp #NONE
    beq bad
    sta cmd_unit
    tax
    lda unit_section,x
    cmp #LETTER_MAX
    bcs bad
    sta cmd_who
    lda #1
    sta cmd_dot
    lda #0
    sta cmd_digits
    sta cmd_x
    lda cmd_verb
    cmp #VERB_HALT
    beq stay
    lda #SLOT_WHERE_X
    sta cmd_slot
stay:
    rts
bad:
    jmp flash
.endproc

;-----------------------------------------------------------------------------
; Append a decimal digit to the current field, enforcing field-specific limits.
.proc accept_digit
    sta zA4
    lda cmd_digits
    cmp #2
    bcc room
    jmp flash
room:
    lda cmd_slot
    cmp #SLOT_WHERE_X
    bne not_x
    lda cmd_x
    jsr mul10_add
    sta cmd_x
    inc cmd_digits
    rts
not_x:
    cmp #SLOT_WHERE_Y
    bne not_y
    lda cmd_y
    jsr mul10_add
    sta cmd_y
    inc cmd_digits
    rts
not_y:
    cmp #SLOT_FORCE
    bne bad
    lda cmd_verb
    cmp #VERB_SPLIT
    bne force_ok
    lda zA4
    bne force_ok
    lda cmd_digits
    beq bad
force_ok:
    lda cmd_digits
    bne second
    lda zA4
    sta cmd_force
    lda #1
    sta cmd_digits
    rts
second:
    lda cmd_force
    jsr mul10_add
    cmp #11
    bcs bad
    sta cmd_force
    lda #2
    sta cmd_digits
    rts
bad:
    jmp flash
.endproc

;-----------------------------------------------------------------------------
; Return A*10+zA4 for decimal entry; callers restrict the field to two digits.
.proc mul10_add
    sta zT0
    asl
    asl
    clc
    adc zT0
    asl
    clc
    adc zA4
    rts
.endproc

;-----------------------------------------------------------------------------
; Advance X to Y or Y to FORCE only after a coordinate has been entered.
.proc accept_sep
    jsr letter_where
    bcs bad
    lda cmd_slot
    cmp #SLOT_WHERE_X
    bne not_x
    lda cmd_digits
    beq bad
    lda #SLOT_WHERE_Y
    sta cmd_slot
    lda #0
    sta cmd_digits
    sta cmd_y
    rts
not_x:
    cmp #SLOT_WHERE_Y
    bne bad
    lda cmd_digits
    beq bad
    lda #SLOT_FORCE
    sta cmd_slot
    lda #0
    sta cmd_digits
    lda #NONE
    sta cmd_force
    rts
bad:
    jmp flash
.endproc

;-----------------------------------------------------------------------------
; Delete a digit first; an empty field backs up to the previous wizard slot.
.proc pop_slot
    lda cmd_slot
    beq done
    cmp #SLOT_SHOW
    bne not_show
    jmp draft_reset
not_show:
    cmp #SLOT_WHO
    bne n_pwho
    jmp pop_who
n_pwho:
    lda cmd_digits
    beq pop_back
    lda cmd_slot
    cmp #SLOT_WHERE_X
    bne py
    lda cmd_x
    jsr div10
    sta cmd_x
    dec cmd_digits
    rts
py:
    cmp #SLOT_WHERE_Y
    bne pf
    lda cmd_y
    jsr div10
    sta cmd_y
    dec cmd_digits
    rts
pf:
    lda cmd_force
    jsr div10
    sta cmd_force
    dec cmd_digits
    bne done
    lda #NONE
    sta cmd_force
done:
    rts
pop_back:
    lda cmd_slot
    cmp #SLOT_FORCE
    bne not_f
    lda cmd_verb
    cmp #VERB_SPLIT
    bne to_y
    lda #SLOT_WHERE_X
    sta cmd_slot
    lda #NONE
    sta cmd_force
    lda #0
    sta cmd_digits
    rts
to_y:
    lda #SLOT_WHERE_Y
    sta cmd_slot
    lda #NONE
    sta cmd_force
    lda cmd_y
    jsr digits_of
    sta cmd_digits
    rts
not_f:
    cmp #SLOT_WHERE_Y
    bne not_yy
    lda #SLOT_WHERE_X
    sta cmd_slot
    lda cmd_x
    jsr digits_of
    sta cmd_digits
    rts
not_yy:
    jsr letter_where
    bcc not_let
    lda cmd_x
    cmp #NONE
    beq not_let
    lda #NONE
    sta cmd_x
    lda #0
    sta cmd_digits
    rts
not_let:
    lda cmd_verb
    cmp #VERB_FOCUS
    bne to_who
    jmp draft_reset
to_who:
    lda #SLOT_WHO
    sta cmd_slot
    lda #NONE
    sta cmd_who
    sta cmd_unit
    lda #0
    sta cmd_dot
    sta cmd_digits
    jsr letter_where
    bcc zx
    lda #NONE
    sta cmd_x
    rts
zx:
    lda #0
    sta cmd_x
    rts
pop_who:
    lda cmd_who
    cmp #NONE
    bne clear
    lda cmd_dot
    bne clear
    jmp draft_reset
clear:
    lda #NONE
    sta cmd_who
    sta cmd_unit
    lda #0
    sta cmd_dot
    rts
.endproc

;-----------------------------------------------------------------------------
; Return unsigned floor(A/10), used to remove the last typed decimal digit.
.proc div10
    ldx #0
loop:
    cmp #10
    bcc done
    sec
    sbc #10
    inx
    bne loop
done:
    txa
    rts
.endproc

;-----------------------------------------------------------------------------
; Return the editable digit count for a coordinate; zero is treated as empty.
.proc digits_of
    cmp #10
    bcc one
    lda #2
    rts
one:
    cmp #1
    bcc zero
    lda #1
    rts
zero:
    lda #0
    rts
.endproc

;-----------------------------------------------------------------------------
; Resolve omitted fields, clamp the target, and dispatch the completed order.
.proc commit
    lda cmd_verb
    cmp #VERB_SPLIT
    bne not_s
    jmp commit_split
not_s:
    cmp #VERB_JOIN
    bne not_j
    jmp commit_join
not_j:
    lda cmd_verb
    cmp #VERB_HALT
    bne not_hd
    lda cmd_dot
    beq not_hd
    jmp commit_dot
not_hd:
    jsr cursor_cell
    lda zA0
    sta zT4
    lda zA1
    sta zT5
    lda cmd_verb
    cmp #VERB_HALT
    beq halt_xy
    lda cmd_slot
    cmp #SLOT_WHO
    beq use_cur
    cmp #SLOT_WHERE_X
    bne past_x
    lda cmd_digits
    beq use_cur
    lda cmd_x
    sta zT4
    jmp have_xy
past_x:
    cmp #SLOT_WHERE_Y
    bne full_xy
    lda cmd_digits
    bne full_y
    lda cmd_x
    sta zT4
    jmp have_xy
full_y:
    lda cmd_x
    sta zT4
    lda cmd_y
    sta zT5
    jmp have_xy
full_xy:
    lda cmd_x
    sta zT4
    lda cmd_y
    sta zT5
    jmp have_xy
use_cur:
    jmp have_xy
halt_xy:
    lda #0
    sta zT4
    sta zT5
have_xy:
    lda #10
    sta zA4
    lda cmd_slot
    cmp #SLOT_FORCE
    bne force_def
    lda cmd_force
    cmp #NONE
    beq force_def
    sta zA4
force_def:
    lda zT4
    sta zA0
    lda zT5
    sta zA1
    jsr world_clamp_play
    lda zA0
    sta zT4
    lda zA1
    sta zT5
    lda cmd_dot
    beq not_dot
    jmp commit_dot
not_dot:
    lda cmd_verb
    cmp #VERB_FOCUS
    bne issue
    lda cmd_slot
    cmp #SLOT_FORCE
    bne foc0
    lda cmd_force
    cmp #NONE
    bne foc_set
foc0:
    lda #0
    sta zA4
foc_set:
    lda zT4
    sta zA0
    lda zT5
    sta zA1
    jsr camera_focus
    lda zA4
    sta zT0
    lda #0
    sta zT1
mul16:
    lda zT0
    beq mul_done
    clc
    lda cam_ttl
    adc #FOCUS_TICKS
    sta cam_ttl
    dec zT0
    jmp mul16
mul_done:
    lda #0
    sta cycle_kind
    lda #NONE
    sta cycle_room
    sta zA0
    lda zT4
    sta zA2
    lda zT5
    sta zA3
    lda zA4
    jmp show_ok
issue:
    lda cmd_who
    cmp #NONE
    bne have_who
    jsr implied_who
    cmp #NONE
    bne got
    lda cmd_last_who
got:
    sta cmd_who
have_who:
    lda cmd_who
    cmp #LETTER_MAX
    bcc who_ok
rej:
    jmp flash
who_ok:
    lda cmd_verb
    cmp #VERB_HALT
    bne do_issue
    ldx cmd_who
    lda section_lead,x
    cmp #NONE
    beq use_last
    tax
    lda unit_x,x
    sta zT4
    lda unit_y,x
    sta zT5
    jmp halt_force
use_last:
    ldx cmd_who
    lda section_last_x,x
    sta zT4
    lda section_last_y,x
    sta zT5
halt_force:
    lda #10
    sta zA4
do_issue:
    jsr build_where_ok
    bcc rej
    lda cmd_who
    sta zA0
    lda cmd_verb
    sta zA1
    lda zT4
    sta zA2
    lda zT5
    sta zA3
    jsr section_issue
    lda #0
    sta cmd_dot
    lda #NONE
    sta cmd_unit
    lda cmd_who
    sta cmd_last_who
    sta zA0
    lda zT4
    sta zA2
    lda zT5
    sta zA3
    lda zA4
    jmp show_ok
.endproc

;-----------------------------------------------------------------------------
; Keep the accepted order in the wizard's SHOW state. A supplies displayed force.
.proc show_ok
    sta cmd_force
    lda #0
    sta cmd_nopath
    sta cmd_digits
    lda zA0
    sta cmd_who
    lda zA2
    sta cmd_x
    lda zA3
    sta cmd_y
    lda #SLOT_SHOW
    sta cmd_slot
    rts
.endproc

;-----------------------------------------------------------------------------
; Resolve source, destination and first unit before asking section_peel to split.
.proc commit_split
    jsr implied_unit
    sta zT6
    lda cmd_x
    cmp #LETTER_MAX
    bcs peel_cursor
    sta zA1
    lda cmd_who
    cmp #LETTER_MAX
    bcs bad
    sta zA0
    lda zT6
    cmp #NONE
    beq use_lead
    tax
    lda unit_section,x
    cmp zA0
    bne bad
    lda zT6
    sta zA2
    jmp have_first
use_lead:
    ldx zA0
    lda section_lead,x
    sta zA2
    jmp have_first
peel_cursor:
    lda cmd_who
    cmp #LETTER_MAX
    bcc dst_ok
bad:
    jmp flash
dst_ok:
    sta zA1
    lda zT6
    cmp #NONE
    beq bad
    tax
    lda unit_section,x
    cmp #LETTER_MAX
    bcs bad
    sta zA0
    lda zT6
    sta zA2
have_first:
    lda #1
    sta zA3
    lda cmd_slot
    cmp #SLOT_FORCE
    bne do_peel
    lda cmd_force
    cmp #NONE
    beq do_peel
    sta zA3
do_peel:
    lda zA3
    pha
    lda zA0
    sta zT4
    lda zA1
    sta zT5
    jsr section_peel
    bcs peeled
    pla
    jmp flash
peeled:
    lda #0
    sta cmd_dot
    sta zA3
    lda #NONE
    sta cmd_unit
    lda zT5
    sta cmd_last_who
    sta zA0
    lda zT4
    cmp zA0
    bne named
    lda #NONE
    sta zA2
    pla
    jmp show_ok
named:
    lda zT4
    sta zA2
    pla
    jmp show_ok
.endproc

;-----------------------------------------------------------------------------
; Validate both player letters and merge through section_join; flash on failure.
.proc commit_join
    lda cmd_who
    cmp #LETTER_MAX
    bcs bad
    sta zA0
    lda cmd_x
    cmp #LETTER_MAX
    bcs bad
    sta zA1
    jsr section_join
    bcs ok
bad:
    jmp flash
ok:
    lda #0
    sta cmd_dot
    lda #NONE
    sta cmd_unit
    lda zA1
    sta cmd_last_who
    sta zA0
    lda cmd_who
    sta zA2
    lda #0
    sta zA3
    lda #10
    jmp show_ok
.endproc

;-----------------------------------------------------------------------------
; Validate the selected individual and dispatch its override through unit_nudge.
.proc commit_dot
    ldx cmd_unit
    cpx #UNIT_MAX
    bcs bad
    lda unit_count,x
    beq bad
    lda unit_hp,x
    beq bad
    lda unit_section,x
    cmp #LETTER_MAX
    bcs bad
    lda cmd_verb
    cmp #VERB_HALT
    bne nudge
    lda unit_x,x
    sta zT4
    lda unit_y,x
    sta zT5
nudge:
    stx zA0
    lda cmd_verb
    sta zA1
    lda zT4
    sta zA2
    lda zT5
    sta zA3
    jsr unit_nudge
    bcs ok
bad:
    jmp flash
ok:
    ldx cmd_unit
    lda unit_section,x
    sta cmd_last_who
    sta zA0
    lda zT4
    sta zA2
    lda zT5
    sta zA3
    lda #10
    jmp show_ok
.endproc

;-----------------------------------------------------------------------------
; Advance contact/mark selection; preserve the current list position when cycling.
.proc cycle_list
    sta zA1
    lda #NONE
    sta zA0
    lda cycle_kind
    cmp zA1
    bne fresh
    lda cycle_room
    sta zA0
fresh:
    lda zA1
    cmp #1
    bne marks
    jsr intel_next_hot
    jmp got
marks:
    jsr intel_next_mark
got:
    cmp #NONE
    bne ok
    jmp flash
ok:
    sta cycle_room
    lda zA1
    sta cycle_kind
    rts
.endproc

;-----------------------------------------------------------------------------
; Focus the selected intel room, preferring its last known contact coordinates.
.proc cycle_snap
    lda cycle_kind
    beq bad
    lda cycle_room
    cmp room_count
    bcs bad
    tax
    lda room_flags,x
    and #ROOM_MARK
    beq canon
    lda last_x,x
    sta zA0
    lda last_y,x
    sta zA1
    jmp foc
canon:
    lda rom_room_w,x
    lsr
    clc
    adc rom_room_x0,x
    sta zA0
    lda rom_room_h,x
    lsr
    clc
    adc rom_room_y0,x
    sta zA1
foc:
    jsr camera_focus
    lda cycle_room
    sta zA0
    jsr intel_player_in_room
    cmp #LETTER_MAX
    bcs clear
    sta cmd_last_who
clear:
    lda #0
    sta cycle_kind
    lda #NONE
    sta cycle_room
    rts
bad:
    jmp flash
.endproc

; A = colour. line_buf holds the row-21 text.
.proc fill_status
    lda #0
    sta line_n
    sta line_buf
    lda script_outcome
    cmp #OUT_WIN
    bne not_win
    lda #<win_msg
    sta zPtr
    lda #>win_msg
    sta zPtr+1
    jsr copy_ready
    lda #COL_YELLOW
    rts
not_win:
    cmp #OUT_LOSE
    bne not_lose
    lda #<lose_msg
    sta zPtr
    lda #>lose_msg
    sta zPtr+1
    jsr copy_ready
    lda #COL_LIGHT_RED
    rts
not_lose:
    lda cmd_nopath
    beq normal
    lda cmd_flash
    beq normal
    lda #<np_msg
    sta zPtr
    lda #>np_msg
    sta zPtr+1
    jsr copy_ready
    lda #COL_LIGHT_RED
    rts
normal:
    jsr build_line
    lda cmd_slot
    beq green
    cmp #SLOT_SHOW
    beq green
    lda #COL_WHITE
    rts
green:
    lda #COL_LIGHT_GREEN
    rts
.endproc

;-----------------------------------------------------------------------------
; Paint wizard labels and the status text during a complete UI refresh.
.proc cmd_paint
    jsr paint_holes
    jsr fill_status
    sta zA2
    lda #<line_buf
    sta zPtr
    lda #>line_buf
    sta zPtr+1
    lda #1
    sta scr_x
    lda #21
    sta scr_y
    jmp write_span
.endproc

win_msg: .byte "SUCCESS", 0
lose_msg: .byte "DEFEAT", 0
np_msg: .byte "NO PATH", 0
ready_msg: .byte "READY", 0

; A = which of VERB/WHO/WHERE/FORCE is lit, or NONE.
.proc which_hole
    lda cmd_nopath
    beq hole_slot
    lda cmd_flash
    beq hole_slot
    lda #2
    rts
hole_slot:
    lda cmd_slot
    cmp #SLOT_SHOW
    bne not_show
    lda cmd_flash
    bne verb_hole
    lda #NONE
    rts
not_show:
    cmp #SLOT_WHO
    bne not_who
    lda #1
    rts
not_who:
    cmp #SLOT_WHERE_X
    beq where_h
    cmp #SLOT_WHERE_Y
    bne not_where
where_h:
    lda #2
    rts
not_where:
    cmp #SLOT_FORCE
    bne verb_hole
    lda #3
    rts
verb_hole:
    lda #0
    rts
.endproc

;-----------------------------------------------------------------------------
; Paint VERB/WHO/WHERE/FORCE, highlighting the active slot or input error.
.proc paint_holes
    jsr which_hole
    sta zT6
    ldx #0
next:
    lda hole_x,x
    sta scr_x
    lda #20
    sta scr_y
    txa
    pha
    jsr cell_addr
    pla
    tax
    lda #COL_WHITE
    cpx zT6
    bne col
    lda #COL_YELLOW
    ldy cmd_flash
    beq col
    lda #COL_LIGHT_RED
col:
    sta zA2
    ; Select the label text; puts_at sets its own string index.
    cpx #0
    bne h1
    lda #<hn_verb
    sta zPtr
    lda #>hn_verb
    sta zPtr+1
    jmp do
h1:
    cpx #1
    bne h2
    lda #<hn_who
    sta zPtr
    lda #>hn_who
    sta zPtr+1
    jmp do
h2:
    cpx #2
    bne h3
    lda #<hn_where
    sta zPtr
    lda #>hn_where
    sta zPtr+1
    jmp do
h3:
    lda #<hn_force
    sta zPtr
    lda #>hn_force
    sta zPtr+1
do:
    lda zA2
    pha
    txa
    pha
    jsr puts_at
    pla
    tax
    pla
    inx
    cpx #4
    bne next
    rts
.endproc

hn_verb: .byte "VERB", 0
hn_who: .byte "WHO", 0
hn_where: .byte "WHERE", 0
hn_force: .byte "FORCE", 0

;-----------------------------------------------------------------------------
; Format the partial or accepted draft for row 21; idle displays READY.
; SPLIT and JOIN print section letters. FOCUS omits WHO, and a zero
; focus count omits the force suffix. Other verbs print AT x,y F n.
; show_ok's A is the force those lines display.
.proc build_line
    lda #0
    sta line_n
    sta line_buf
    lda cmd_slot
    bne not_idle
    lda #<ready_msg
    sta zPtr
    lda #>ready_msg
    sta zPtr+1
    jmp copy_ready
not_idle:
    jsr who_char
    sta zT6
    ldx cmd_verb
    lda verb_name_lo,x
    sta zPtr
    lda verb_name_hi,x
    sta zPtr+1
    jsr line_str
    lda cmd_verb
    cmp #VERB_SPLIT
    bne not_spl
    jmp split_line
not_spl:
    cmp #VERB_JOIN
    bne not_jn
    jmp join_line
not_jn:
    cmp #VERB_HALT
    bne not_halt
    lda cmd_slot
    cmp #SLOT_SHOW
    bne not_halt
    lda #' '
    jsr line_ch
    lda zT6
    jmp line_ch
not_halt:
    lda cmd_slot
    cmp #SLOT_WHO
    bne past_who
    lda cmd_who
    cmp #NONE
    bne show_who
    lda cmd_dot
    bne show_who
    jmp done
show_who:
    lda #' '
    jsr line_ch
    lda zT6
    jmp line_ch
past_who:
    lda cmd_verb
    cmp #VERB_FOCUS
    beq at_txt
    lda #' '
    jsr line_ch
    lda zT6
    jsr line_ch
at_txt:
    lda cmd_slot
    cmp #SLOT_WHERE_X
    bne past_x
    lda cmd_digits
    bne type_x
    jmp done
type_x:
    lda #' '
    jsr line_ch
    lda #'A'
    jsr line_ch
    lda #'T'
    jsr line_ch
    lda #' '
    jsr line_ch
    lda cmd_x
    jmp line_dec
past_x:
    lda #' '
    jsr line_ch
    lda #'A'
    jsr line_ch
    lda #'T'
    jsr line_ch
    lda #' '
    jsr line_ch
    lda cmd_x
    jsr line_dec
    lda #','
    jsr line_ch
    lda cmd_slot
    cmp #SLOT_WHERE_Y
    bne past_y
    lda cmd_digits
    beq done
    lda cmd_y
    jmp line_dec
past_y:
    lda cmd_y
    jsr line_dec
    lda cmd_verb
    cmp #VERB_FOCUS
    bne force_suf
    lda cmd_force
    beq done
force_suf:
    lda #' '
    jsr line_ch
    lda #'F'
    jsr line_ch
    lda cmd_slot
    cmp #SLOT_FORCE
    bne past_f
    lda cmd_force
    cmp #NONE
    beq done
    lda #' '
    jsr line_ch
    lda cmd_force
    jmp line_dec
past_f:
    lda #' '
    jsr line_ch
    lda cmd_force
    cmp #NONE
    bne prf
    lda #10
prf:
    jmp line_dec
done:
    rts
.endproc

;-----------------------------------------------------------------------------
; Append a NUL-terminated message at zPtr to the status buffer.
.proc copy_ready
    ldy #0
c:
    lda (zPtr),y
    beq end
    jsr line_ch
    iny
    bne c
end:
    rts
.endproc

;-----------------------------------------------------------------------------
; Append a NUL-terminated string at zPtr; line_ch bounds the destination.
.proc line_str
    ldy #0
c:
    lda (zPtr),y
    beq end
    jsr line_ch
    iny
    bne c
end:
    rts
.endproc

;-----------------------------------------------------------------------------
; Return the draft's WHO character: individual dot, section letter, or unknown '?'.
.proc who_char
    lda cmd_dot
    beq letter
    lda #'.'
    rts
letter:
    lda cmd_who
    cmp #LETTER_MAX
    bcc ok
    lda #'?'
    rts
ok:
    clc
    adc #'A'
    rts
.endproc
