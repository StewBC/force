; World RAM lives in bss.asm. Tables are rom_* / sc_*.
; This is the playable sim. Trace logging is omitted. Fog never hides.

.proc world_load
    ldx #UNIT_MAX-1
    lda #0
zu:
    sta unit_count,x
    sta unit_hp,x
    sta unit_fx,x
    sta unit_move_wait,x
    sta unit_fire_wait,x
    sta unit_over_verb,x
    dex
    bpl zu
    ldx #SECTION_MAX-1
    lda #NONE
zs:
    sta section_lead,x
    lda #0
    sta section_strength,x
    sta section_flags,x
    sta section_order_verb,x
    sta section_order_force,x
    sta section_order_str,x
    dex
    bpl zs
    lda rom_map_w
    sta map_w
    lda rom_map_h
    sta map_h
    lda rom_play_x
    sta play_x
    sta win_x
    lda rom_play_y
    sta play_y
    sta win_y
    lda rom_play_w
    sta play_w
    cmp #COLS
    bcc ww
    lda #COLS
ww:
    sta win_w
    lda rom_play_h
    sta play_h
    cmp #FIELD_ROWS
    bcc wh
    lda #FIELD_ROWS
wh:
    sta win_h
    lda rom_room_count
    sta room_count
    ldx #ROOM_MAX-1
zr:
    lda #0
    sta room_flags,x
    sta room_heat,x
    sta last_x,x
    sta last_y,x
    lda #4
    cpx room_count
    bcs zapp
    sta room_approach,x
    lda rom_room_axis,x
    cmp #1
    bne znext
    lda #8
    sta room_approach,x
znext:
    dex
    bpl zr
    jmp spawns
zapp:
    lda #0
    sta room_approach,x
    dex
    bpl zr
spawns:
    ldx #0
sp:
    cpx rom_spawn_count
    bcs script
    ldy rom_spawn_tile,x
    lda rom_tile_class,y
    cmp #CLASS_GOODGUYS
    bne spn
    lda rom_spawn_x,x
    sta zA0
    lda rom_spawn_y,x
    sta zA1
    lda #0
    sta zA2
    lda #KIND_INFANTRY
    sta zA3
    lda #1
    sta zA4
    lda rom_spawn_tile,x
    sta zT7
    jsr unit_spawn
spn:
    inx
    bne sp
script:
    jsr section_recount
    lda #0
    sta script_waiting
    sta script_fired
    sta script_clock
    sta script_clock+1
    sta script_outcome
    sta spawn_job_rem
    sta path_fail_who
    lda #NONE
    sta path_fail_who
    lda sc_start_spawn_room
    sta spawn_room
    ldx sc_start_beat
    lda sc_beat_pc,x
    sta script_pc
    lda sc_player_grenades
    sta grenade_rem
    lda sc_enemy_grenades
    sta grenade_rem+1
    lda #0
    sta grenade_wait
    sta grenade_wait+1
    sta nade_fx_ttl
    sta nade_fx_ttl+1
    jsr build_rows
    jsr bake_hop
    rts
.endproc

; X is the caller's index. The section lead uses X internally, so put it back.
.proc unit_spawn
    txa
    pha
    ldy #0
find:
    lda unit_count,y
    beq got
    iny
    cpy #UNIT_MAX
    bne find
    lda #NONE
    jmp leave
got:
    lda zA0
    sta unit_x,y
    lda zA1
    sta unit_y,y
    lda zA2
    sta unit_section,y
    lda zA4
    sta unit_count,y
    lda zA3
    sta unit_kind,y
    lda zT7
    sta unit_glyph,y
    lda #NONE
    sta unit_cover,y
    lda #0
    sta unit_over_verb,y
    lda zA0
    sta unit_tgt_x,y
    lda zA1
    sta unit_tgt_y,y
    lda #HP_INFANTRY
    sta unit_hp,y
    txa
    pha
    jsr region_at
    sta unit_region,y
    pla
    tax
    ldx zA2
    lda section_lead,x
    cmp #NONE
    bne led
    tya
    sta section_lead,x
    lda zA0
    sta section_last_x,x
    lda zA1
    sta section_last_y,x
led:
    tya
leave:
    tay
    pla
    tax
    tya
    rts
.endproc

.proc section_recount
    ldx #SECTION_MAX-1
    lda #0
cl:
    sta section_strength,x
    dex
    bpl cl
    ldx #0
n:
    lda unit_hp,x
    beq s
    lda unit_count,x
    beq s
    ldy unit_section,x
    clc
    adc section_strength,y
    sta section_strength,y
s:
    inx
    cpx #UNIT_MAX
    bne n
    rts
.endproc

.proc world_clamp_play
    lda play_w
    beq done
    lda zA0
    cmp play_x
    bcs xhi
    lda play_x
    sta zA0
xhi:
    lda play_x
    clc
    adc play_w
    sec
    sbc #1
    cmp zA0
    bcs yok
    sta zA0
yok:
    lda zA1
    cmp play_y
    bcs yhi
    lda play_y
    sta zA1
yhi:
    lda play_y
    clc
    adc play_h
    sec
    sbc #1
    cmp zA1
    bcs done
    sta zA1
done:
    rts
.endproc

; zA0 who, zA1 verb, zA2 x, zA3 y, zA4 force. Leaves zT4/zT5 alone.
.proc section_issue
    ldx zA0
    cpx #SECTION_MAX
    bcs done
    ldy #0
walk:
    lda unit_section,y
    cmp zA0
    bne nxt
    lda #0
    sta unit_over_verb,y
nxt:
    iny
    cpy #UNIT_MAX
    bne walk
    ldx zA0
    lda zA1
    sta section_order_verb,x
    lda zA2
    sta section_order_x,x
    lda zA3
    sta section_order_y,x
    lda zA4
    sta section_order_force,x
    lda section_strength,x
    sta section_order_str,x
    lda section_flags,x
    and #($FF ^ FLAG_NOPATH ^ FLAG_BREAKING ^ FLAG_CONTACT)
    sta zT0
    lda zA1
    cmp #VERB_DEFEND
    beq asg
    cmp #VERB_ATTACK
    beq asg
    cmp #VERB_RETREAT
    beq asg
    cmp #VERB_MOVE
    bne putf
    lda zT0
    and #($FF ^ FLAG_ASSIGN)
    ora #FLAG_RELEASE
    jmp put
asg:
    lda zT0
    and #($FF ^ FLAG_RELEASE)
    ora #FLAG_ASSIGN
put:
    ldx zA0
    sta section_flags,x
done:
    rts
putf:
    lda zT0
    jmp put
.endproc

.proc section_peel
    clc
    rts
.endproc

.proc section_join
    clc
    rts
.endproc

.proc unit_nudge
    clc
    rts
.endproc

.proc intel_next_hot
    lda #NONE
    rts
.endproc

.proc intel_next_mark
    lda #NONE
    rts
.endproc

.proc intel_player_in_room
    lda #NONE
    rts
.endproc

.proc world_tick
    jsr decay_fx
    lda script_outcome
    beq go
    rts
go:
    inc script_clock
    bne nc
    inc script_clock+1
nc:
    lda #NONE
    sta path_fail_who
    lda #0
    sta shot_this_tick
    jsr cover_jobs
    jsr decay_grenade_wait
    jsr shoot_all
    jsr apply_deaths
    jsr script_step
    lda script_outcome
    beq cont
    rts
cont:
    jsr spawn_pulse
    jsr cover_jobs
    jsr think_all
    jsr despawn_exits
    rts
.endproc

.segment "SPARE"

; zA0,zA1. Carry set when the cell is outside the playfield.
; A wrapped 255 is outside: it is the step past a zero edge.
.proc off_play
    lda play_w
    beq no
    lda play_h
    beq no
    lda zA0
    cmp play_x
    bcc yes
    lda play_x
    clc
    adc play_w
    cmp zA0
    bcc yes
    beq yes
    lda zA1
    cmp play_y
    bcc yes
    lda play_y
    clc
    adc play_h
    cmp zA1
    bcc yes
    beq yes
no:
    clc
    rts
yes:
    sec
    rts
.endproc

; zA0,zA1 is one cell outside the playfield. A is the face he
; crossed. Carry clear when the cell is still on the playfield.
.proc face_of
    jsr off_play
    bcc no
    lda play_x
    bne wcmp
    lda zA0
    cmp #$FF
    beq west
wcmp:
    lda zA0
    cmp play_x
    bcc west
    lda play_x
    clc
    adc play_w
    cmp zA0
    bcc east
    beq east
    lda play_y
    bne ncmp
    lda zA1
    cmp #$FF
    beq north
ncmp:
    lda zA1
    cmp play_y
    bcc north
    lda #FACE_S
    sec
    rts
west:
    lda #FACE_W
    sec
    rts
east:
    lda #FACE_E
    sec
    rts
north:
    lda #FACE_N
    sec
    rts
no:
    clc
    rts
.endproc

; The open cell in zA2,zA3 is on the playfield edge. Step it
; one cell off that face. mv_front is the exit face.
.proc push_out
    lda mv_front
    cmp #FACE_W
    bne pe
    lda zA2
    bne wdec
    lda #$FF
    sta zA2
    rts
wdec:
    sec
    sbc #1
    sta zA2
    rts
pe:
    cmp #FACE_E
    bne pn
    inc zA2
    rts
pn:
    cmp #FACE_N
    bne ps
    lda zA3
    bne ndec
    lda #$FF
    sta zA3
    rts
ndec:
    sec
    sbc #1
    sta zA3
    rts
ps:
    inc zA3
    rts
.endproc

; zA0,zA1 outside. zA2,zA3 becomes the playfield cell he steps from.
.proc lip_of
    jsr face_of
    bcc no
    cmp #FACE_W
    bne le
    lda play_x
    sta zA2
    lda zA1
    sta zA3
    sec
    rts
le:
    cmp #FACE_E
    bne ln
    lda play_x
    clc
    adc play_w
    sec
    sbc #1
    sta zA2
    lda zA1
    sta zA3
    sec
    rts
ln:
    cmp #FACE_N
    bne ls
    lda zA0
    sta zA2
    lda play_y
    sta zA3
    sec
    rts
ls:
    lda zA0
    sta zA2
    lda play_y
    clc
    adc play_h
    sec
    sbc #1
    sta zA3
    sec
    rts
no:
    clc
    rts
.endproc

; If this man's MOVE order is off the playfield and he is standing
; on that edge, step him one cell off. Carry set when he left.
; Already-off men stop here so the march does not continue.
.proc step_off
    ldx think_i
    lda unit_x,x
    sta zA0
    lda unit_y,x
    sta zA1
    jsr off_play
    bcc on
    jsr exit_move
    rts
on:
    jsr exit_move
    bcc no
    ldx think_i
    cmp #FACE_W
    bne se
    lda unit_x,x
    cmp play_x
    bne no
    lda play_x
    beq ww
    sec
    sbc #1
    sta unit_x,x
    sec
    rts
ww:
    lda #$FF
    sta unit_x,x
    sec
    rts
se:
    cmp #FACE_E
    bne sn
    lda play_x
    clc
    adc play_w
    sec
    sbc #1
    cmp unit_x,x
    bne no
    inc unit_x,x
    sec
    rts
sn:
    cmp #FACE_N
    bne ss
    lda unit_y,x
    cmp play_y
    bne no
    lda play_y
    beq nw
    sec
    sbc #1
    sta unit_y,x
    sec
    rts
nw:
    lda #$FF
    sta unit_y,x
    sec
    rts
ss:
    lda play_y
    clc
    adc play_h
    sec
    sbc #1
    cmp unit_y,x
    bne no
    inc unit_y,x
    sec
    rts
no:
    clc
    rts
.endproc

; Section of think_i. Carry set and A = face when his order is
; MOVE to a cell outside the playfield. Enemy sections only.
.proc exit_move
    ldx think_i
    lda unit_section,x
    cmp #LETTER_MAX
    bcc no
    cmp #SECTION_MAX
    bcs no
    tax
    lda section_order_verb,x
    cmp #VERB_MOVE
    bne no
    lda section_order_x,x
    sta zA0
    lda section_order_y,x
    sta zA1
    jmp face_of
no:
    clc
    rts
.endproc

; An enemy ordered to march off the playfield is removed only once
; his own cell is outside it. Standing on the edge does not count.
.proc despawn_exits
    lda #0
    sta zT7
    ldy #0
walk:
    lda unit_count,y
    beq adv
    ldx unit_section,y
    cpx #LETTER_MAX
    bcc adv
    cpx #SECTION_MAX
    bcs adv
    lda section_order_verb,x
    cmp #VERB_MOVE
    bne adv
    lda section_order_x,x
    sta zA0
    lda section_order_y,x
    sta zA1
    jsr off_play
    bcc adv
    lda unit_x,y
    sta zA0
    lda unit_y,y
    sta zA1
    jsr off_play
    bcc adv
    lda #0
    sta unit_count,y
    sta unit_over_verb,y
    sta unit_fx,y
    lda #NONE
    sta unit_cover,y
    ldx unit_section,y
    txa
    and #7
    tax
    lda cb_bit,x
    ora zT7
    sta zT7
adv:
    iny
    cpy #UNIT_MAX
    bne walk
    lda zT7
    beq done
    ldx #LETTER_MAX
bits:
    lda zT7
    beq recount
    lsr zT7
    bcc nxt
    txa
    pha
    jsr section_relead
    pla
    tax
nxt:
    inx
    cpx #SECTION_MAX
    bne bits
recount:
    jsr section_recount
done:
    rts
.endproc

.segment "CODE"

.proc cell_open
    lda zA2
    cmp map_w
    bcs no
    lda zA3
    cmp map_h
    bcs no
    lda zA2
    sta zA0
    lda zA3
    sta zA1
    stx zT7
    jsr map_ptr
    ldx zT7
    tay
    lda rom_tile_class,y
    cmp #CLASS_WALLS
    beq no
    cmp #CLASS_BARRIERS
    beq no
    sec
    rts
no:
    clc
    rts
.endproc

.proc cell_taken
    ldy #0
t:
    cpy zT7
    beq tn
    lda unit_count,y
    beq tn
    lda unit_hp,y
    beq tn
    lda unit_x,y
    cmp zA2
    bne tn
    lda unit_y,y
    cmp zA3
    bne tn
    sec
    rts
tn:
    iny
    cpy #UNIT_MAX
    bne t
    clc
    rts
.endproc

.proc script_step
    lda script_waiting
    bne waiting
run:
    ldy script_pc
    cpy sc_op_count
    bcc op
    rts
op:
    lda sc_op_code,y
    cmp #1
    bne not_spawn
    jmp op_spawn
not_spawn:
    cmp #6
    beq op_wait
    cmp #7
    beq op_win
    cmp #8
    beq op_lose
    cmp #5
    beq op_goto
    cmp #2
    bne not_ord
    jmp op_order
not_ord:
    cmp #OP_SET_SPAWN
    beq op_setsp
    cmp #OP_APPROACH
    beq op_approach
    inc script_pc
    jmp run
op_win:
    lda #OUT_WIN
    sta script_outcome
    rts
op_lose:
    lda #OUT_LOSE
    sta script_outcome
    rts
op_goto:
    lda sc_op_a,y
    sta script_pc
    jmp run
op_wait:
    lda sc_op_a,y
    sta script_wait_pred0
    lda sc_op_b,y
    sta script_wait_pred1
    lda sc_op_c,y
    sta script_wait_beat
    lda #1
    sta script_waiting
    inc script_pc
    rts
waiting:
    jsr pred_ok
    bcc still
    lda #0
    sta script_waiting
    ldy script_wait_beat
    lda sc_beat_pc,y
    sta script_pc
    jmp run
still:
    rts
op_setsp:
    lda sc_op_a,y
    sta spawn_room
    inc script_pc
    jmp run
op_approach:
    lda sc_op_a,y
    sta zA0
    lda sc_op_b,y
    sta zA1
    jsr script_approach
    inc script_pc
    jmp run
op_spawn:
    lda sc_op_a,y
    tax
    lda sc_spawn_n,x
    sta spawn_job_rem
    lda sc_spawn_letter,x
    sta spawn_job_letter
    lda sc_spawn_room,x
    sta spawn_job_room
    lda sc_spawn_batch,x
    sta spawn_job_batch
    lda sc_spawn_period,x
    sta spawn_job_period
    lda #0
    sta spawn_job_wait
    inc script_pc
    jmp run
op_order:
    lda sc_op_a,y
    sta zA0
    sta mv_who
    lda sc_op_b,y
    and #$0F
    sta zA1
    lda sc_op_b,y
    lsr
    lsr
    lsr
    lsr
    sta zA4
    lda sc_op_c,y
    sta zT0
    lda zA0
    pha
    lda zA1
    pha
    lda zA4
    pha
    jsr resolve_where
    pla
    sta zA4
    pla
    sta zA1
    pla
    sta zA0
    bcc ord_skip
    jsr section_issue
    lda zA1
    cmp #VERB_ATTACK
    bne ord_str
    ldx mv_who
    lda section_flags,x
    and #($FF ^ FLAG_ASSIGN)
    sta section_flags,x
ord_str:
    lda spawn_job_rem
    beq ord_skip
    lda spawn_job_letter
    cmp mv_who
    bne ord_skip
    ldx mv_who
    lda section_strength,x
    clc
    adc spawn_job_rem
    sta section_order_str,x
ord_skip:
    inc script_pc
    jmp run
.endproc

; Carry set when the armed wait pair is true.
; A second index of $FF means there is no second predicate.
; Who $FF is the player bank (sections 0-7). Any other who is one section.
.proc pred_ok
    lda script_wait_pred0
    jsr pred_true
    bcc bad
    lda script_wait_pred1
    cmp #NONE
    beq good
    jsr pred_true
    bcc bad
good:
    sec
    rts
bad:
    clc
    rts
.endproc

; A is the predicate index. Carry set when that one predicate is true.
.proc pred_true
    cmp sc_pred_count
    bcs bad
    tay
    lda sc_pred_who,y
    sta zA0
    lda sc_pred_a,y
    sta zA1
    lda sc_pred_b,y
    sta zA2
    lda sc_pred_kind,y
    cmp #PRED_NONE
    beq good
    cmp #PRED_STR_EQ
    beq str_eq
    cmp #PRED_STR_LE
    beq str_le
    cmp #PRED_STR_GE
    beq str_ge
    cmp #PRED_IN_GE
    beq in_ge
    cmp #PRED_REACHED
    beq reached
    cmp #PRED_JOB_IDLE
    beq job
    cmp #PRED_AT_CELL
    bne not_cell
    jmp at_cell
not_cell:
    cmp #PRED_CLOCK_GE
    bne not_clock
    jmp clock
not_clock:
    cmp #PRED_REL_GE
    bne bad
    jmp rel
bad:
    clc
    rts
good:
    sec
    rts
str_eq:
    jsr bank_strength
    cmp zA1
    beq good
    clc
    rts
str_le:
    jsr bank_strength
    cmp zA1
    bcc good
    beq good
    clc
    rts
str_ge:
    jsr bank_strength
    cmp zA1
    bcs good
    clc
    rts
in_ge:
    jsr count_in_room
    cmp zA2
    bcs good
    clc
    rts
reached:
    jsr count_in_room
    cmp #1
    bcs good
    clc
    rts
job:
    lda spawn_job_rem
    beq good
    clc
    rts
at_cell:
    ldy #0
ac_n:
    lda unit_count,y
    beq ac_adv
    lda unit_x,y
    cmp zA1
    bne ac_adv
    lda unit_y,y
    cmp zA2
    bne ac_adv
    lda unit_section,y
    ldx zA0
    cpx #NONE
    bne ac_one
    cmp #LETTER_MAX
    bcs ac_adv
    sec
    rts
ac_one:
    cmp zA0
    bne ac_adv
    sec
    rts
ac_adv:
    iny
    cpy #UNIT_MAX
    bne ac_n
    clc
    rts
clock:
    lda script_clock+1
    cmp zA2
    bcc clock_no
    bne clock_yes
    lda script_clock
    cmp zA1
    bcc clock_no
clock_yes:
    sec
    rts
clock_no:
    clc
    rts
rel:
    lda #0
    sta zT0
    sta zT1
    ldy #0
rel_n:
    lda unit_count,y
    beq rel_adv
    lda unit_region,y
    cmp zA1
    bne rel_adv
    lda unit_section,y
    cmp #LETTER_MAX
    bcs rel_en
    inc zT0
    jmp rel_adv
rel_en:
    inc zT1
rel_adv:
    iny
    cpy #UNIT_MAX
    bne rel_n
    lda zT0
    cmp zT1
    bcc rel_no
    sec
    rts
rel_no:
    clc
    rts
.endproc

; zA0 is who. A comes back as that section's strength, or the
; player-bank sum. The sum wraps at 8 bits, the same as SDL.
.proc bank_strength
    lda zA0
    cmp #NONE
    beq sum
    cmp #SECTION_MAX
    bcs zero
    tax
    lda section_strength,x
    rts
sum:
    lda #0
    ldx #0
add:
    clc
    adc section_strength,x
    inx
    cpx #LETTER_MAX
    bne add
    rts
zero:
    lda #0
    rts
.endproc

; zA0 is who, zA1 is the room. A is a head count, not a strength sum.
; unit_count nonzero is living. Player who counts sections 0-7.
.proc count_in_room
    lda #0
    sta zT0
    ldy #0
next:
    lda unit_count,y
    beq adv
    lda unit_region,y
    cmp zA1
    bne adv
    lda unit_section,y
    ldx zA0
    cpx #NONE
    beq ply
    cmp zA0
    bne adv
    inc zT0
    jmp adv
ply:
    cmp #LETTER_MAX
    bcs adv
    inc zT0
adv:
    iny
    cpy #UNIT_MAX
    bne next
    lda zT0
    rts
.endproc
