; World RAM lives in bss.asm. Tables are rom_* / sc_*.
; This is the playable sim. Trace logging is omitted. Fog never hides.

; Reset the mission, create player stamps, and rebuild map/routing lookup tables.
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
    ; Direct stores, not cover_put. clear_bss leaves 0, which is chip id 0,
    ; and F3 does not run clear_bss. A later cover_put must not see that 0.
    ldx #UNIT_MAX-1
    lda #NONE
wipe:
    sta unit_cover,x
    dex
    bpl wipe
    ldx #CLAIM_BYTES-1
    lda #0
clm:
    sta cover_claim,x
    dex
    bpl clm
    ldx #SECTION_MAX-1
zs:
    lda #NONE                                  ; Each section starts without a leader
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
    lda rom_play_y
    sta play_y
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
    lda rom_cam_x
    sta win_x
    lda rom_cam_y
    sta win_y
    jsr clamp_window
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
    ; Only friendly map stamps become initial units; enemy arrivals belong to the script.
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
    ; Reset director state and shared grenade resources, then rebuild map/routing tables.
    jsr section_recount
    lda #0
    sta script_waiting
    sta script_fired
    sta script_clock
    sta script_clock+1
    sta objective_ttl
    sta script_outcome
    sta spawn_job_rem
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
    jsr deck_arm
    jsr initial_routes
    jsr script_init
    lda #1
    sta planes_live
    rts
.endproc

; X is the caller's index and is restored. zA0,zA1 are the cell, zA2 the
; section, zA3 the kind, zA4 the count, zT7 the glyph. Returns the slot in
; A, or NONE when the pool is full or the count/section is not spawnable.
; A new occupant starts with a clear fire wait, effects, overrides and
; stepper state. Move wait is the slot's phase, matching force_unit_spawn.
; Y is the slot while the body runs.
.proc unit_spawn
    txa
    pha
    lda zA4
    beq reject
    lda zA2
    cmp #SECTION_MAX
    bcc args_ok
reject:
    lda #NONE
    jmp leave
args_ok:
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
    tya
    tax
    lda #NONE
    jsr cover_put
    lda #0
    sta unit_over_verb,y
    sta unit_over_x,y
    sta unit_over_y,y
    sta unit_step_sx,y
    sta unit_step_sy,y
    sta unit_step_ax,y
    sta unit_step_ay,y
    sta unit_step_err,y
    sta unit_step_run,y
    sta unit_fire_wait,y
    sta unit_fx,y
    ; Slot modulo MOVE_WAIT. A stored 0 is due now, and so is a stored 1,
    ; because think_all acts on the tick the countdown reaches 0. A nonzero
    ; phase is stored one higher so the first step is that many ticks out.
    ; A step reloads 7 and keeps the phase. Sprint reloads 4 and drifts.
    tya
phase:
    cmp #MOVE_WAIT
    bcc phased
    sec
    sbc #MOVE_WAIT
    jmp phase
phased:
    beq storew
    adc #1
storew:
    sta unit_move_wait,y
    lda zA0
    sta unit_tgt_x,y
    lda zA1
    sta unit_tgt_y,y
    lda #HP_INFANTRY
    sta unit_hp,y
    jsr region_at                              ; Preserves Y; caller X is already on the stack
    sta unit_region,y
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
    jsr deck_clear_slot
    tya
leave:
    tay
    pla
    tax
    tya
    rts
.endproc

;-----------------------------------------------------------------------------
; Rebuild section strengths from occupied units with nonzero HP.
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

;-----------------------------------------------------------------------------
; Pull win_x/win_y so the win_w by win_h view stays inside the play rect.
; Trashes A and zT0. Preserves X and Y.
.proc clamp_window
    lda play_w
    sec
    sbc win_w
    bcs xwide
    lda #0
xwide:
    clc
    adc play_x
    sta zT0
    lda win_x
    cmp play_x
    bcs xge
    lda play_x
xge:
    cmp zT0
    bcc xset
    beq xset
    lda zT0
xset:
    sta win_x
    lda play_h
    sec
    sbc win_h
    bcs ywide
    lda #0
ywide:
    clc
    adc play_y
    sta zT0
    lda win_y
    cmp play_y
    bcs yge
    lda play_y
yge:
    cmp zT0
    bcc yset
    beq yset
    lda zT0
yset:
    sta win_y
    rts
.endproc

;-----------------------------------------------------------------------------
; Clamp zA0,zA1 to the mission rectangle; a zero width disables the clamp.
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
; Rebuilds that section's formation list when the order cell changes.
.proc section_issue
    ldx zA0
    cpx #SECTION_MAX
    bcc who_ok
    jmp done
who_ok:
    lda zA2
    cmp section_order_x,x
    bne newcell
    lda zA3
    cmp section_order_y,x
    bne newcell
    lda form_n,x
    bne samecell
newcell:
    lda #1
    bne mark
samecell:
    lda #0
mark:
    sta zT6
    jsr deck_clear_who
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
    beq rel
    cmp #VERB_BUILD
    bne putf
rel:
    lda zT0
    and #($FF ^ FLAG_ASSIGN)
    ora #FLAG_RELEASE
    jmp put
asg:
    ; Defer cover assignment to the world tick; issuing an order does not move a man.
    lda zT0
    and #($FF ^ FLAG_RELEASE)
    ora #FLAG_ASSIGN
put:
    ldx zA0
    sta section_flags,x
    lda zT6
    beq done
    ldx zA0
    jsr form_build
done:
    rts
putf:
    lda zT0
    jmp put
.endproc

;-----------------------------------------------------------------------------
; Decay effects, resolve combat/deaths, run the script, then spawn and move survivors.
; After the spawn, an enemy attack that has entered its room takes cover,
; and the intel pulse runs once the movers and exit despawn have finished.
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
    jsr contact_start
    jsr cover_jobs
    jsr build_pulse
    jsr think_all
    jsr despawn_exits
    jsr intel_pulse
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
    tya
    tax
    lda #NONE
    jsr cover_put
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

; The $4000 image has no room for these. build_line jumps here.
; zT6 is the WHO character already written into the line.

;-----------------------------------------------------------------------------
; Append " <who> <WHERE letter>". Tail of line_ch.
.proc letters_who_x
    lda #' '
    jsr line_ch
    lda zT6
    jsr line_ch
    lda #' '
    jsr line_ch
    lda cmd_x
    clc
    adc #'A'
    jmp line_ch
.endproc

;-----------------------------------------------------------------------------
; Append the SPLIT draft. Returns to build_line's caller. Letters are sections.
.proc split_line
    lda cmd_slot
    cmp #SLOT_WHO
    bne sp_w
    lda cmd_who
    cmp #NONE
    beq leave
sp_w:
    lda cmd_slot
    cmp #SLOT_WHO
    beq sp_one
    cmp #SLOT_WHERE_X
    bne sp_two_or
    lda cmd_x
    cmp #LETTER_MAX
    bcs sp_one
sp_two_or:
    lda cmd_slot
    cmp #SLOT_WHERE_X
    beq sp_two
    cmp #SLOT_FORCE
    bne sp_typed
    lda cmd_force
    cmp #NONE
    beq sp_two
sp_typed:
    lda cmd_slot
    cmp #SLOT_FORCE
    bne sp_show
    jsr letters_who_x
    lda #' '
    jsr line_ch
    lda cmd_force
    jmp line_dec
sp_show:
    lda cmd_x
    cmp #LETTER_MAX
    bcs sp_one
    lda cmd_force
    cmp #2
    bcc sp_swap
    jsr sp_x_who
    lda #' '
    jsr line_ch
    lda cmd_force
    jmp line_dec
sp_swap:
    jmp sp_x_who
sp_one:
    lda #' '
    jsr line_ch
    lda zT6
    jmp line_ch
sp_two:
    jmp letters_who_x
leave:
    rts
sp_x_who:
    lda #' '
    jsr line_ch
    lda cmd_x
    clc
    adc #'A'
    jsr line_ch
    lda #' '
    jsr line_ch
    lda zT6
    jmp line_ch
.endproc

;-----------------------------------------------------------------------------
; Append the JOIN draft. Two letters are WHO then WHERE; a missing WHERE
; prints WHO alone.
.proc join_line
    lda cmd_slot
    cmp #SLOT_WHO
    bne jn_rest
    lda cmd_who
    cmp #NONE
    bne jn_rest
    rts
jn_rest:
    lda cmd_slot
    cmp #SLOT_WHO
    beq jn_one
    lda cmd_x
    cmp #LETTER_MAX
    bcs jn_one
    jmp letters_who_x
jn_one:
    lda #' '
    jsr line_ch
    lda zT6
    jmp line_ch
.endproc

;-----------------------------------------------------------------------------
; Run script watches before the beat. X is the watch index. pred_true
; trashes X, so it is stacked across each test. A win or lose returns
; immediately. ONCE watches stay latched in script_fired. At most eight
; watches: script_fired is one byte.
.proc script_watches
    ldx #0
next:
    cpx sc_watch_count
    bcc in_n
    rts
in_n:
    cpx #8
    bcc in_8
    rts
in_8:
    lda sc_watch_flags,x
    and #WATCH_ONCE
    beq test
    lda script_fired
    and cb_bit,x
    bne adv
test:
    txa
    pha
    lda sc_watch_pred0,x
    jsr pred_true
    bcc fail
    pla
    tax
    lda sc_watch_pred1,x
    cmp #NONE
    beq fire
    txa
    pha
    jsr pred_true
    bcc fail
    pla
    tax
fire:
    lda cb_bit,x
    ora script_fired
    sta script_fired
    lda sc_watch_op,x
    cmp #OP_LOSE
    beq do_lose
    cmp #OP_WIN
    beq do_win
    cmp #OP_SET_SPAWN
    beq do_set
    cmp #OP_APPROACH
    beq do_ap
    cmp #OP_GOTO
    bne adv
    lda #0
    sta script_waiting
    lda sc_watch_arg,x
    tay
    lda sc_beat_pc,y
    sta script_pc
    jmp adv
do_set:
    lda sc_watch_arg,x
    sta spawn_room
    jmp adv
do_ap:
    lda sc_watch_arg,x
    and #$0F
    sta zA0
    lda sc_watch_arg,x
    lsr
    lsr
    lsr
    lsr
    sta zA1
    txa
    pha
    jsr script_approach
    pla
    tax
    jmp adv
do_lose:
    lda #OUT_LOSE
    bne store
do_win:
    lda #OUT_WIN
store:
    sta script_outcome
done:
    rts
fail:
    pla
    tax
adv:
    inx
    jmp next
.endproc

;-----------------------------------------------------------------------------
; Give one friendly his own order. zA0 unit, zA1 verb, zA2,zA3 cell.
; C set on acceptance. MOVE, HALT and KILL store that cell. DEFEND, ATTACK
; and RETREAT take the chip there, or the best open chip in that room.
; zT4,zT5 keep the cell; zR0 keeps the verb. think_i is the unit.
.proc unit_nudge
    ldx zA0
    cpx #UNIT_MAX
    bcs no
    lda unit_count,x
    beq no
    lda unit_hp,x
    beq no
    lda unit_section,x
    cmp #LETTER_MAX
    bcs no
    stx think_i
    lda zA2
    sta zT4
    lda zA3
    sta zT5
    lda zA1
    sta zR0
    cmp #VERB_MOVE
    bne not_mv
    jmp as_move
not_mv:
    cmp #VERB_HALT
    bne not_hl
    jmp as_halt
not_hl:
    cmp #VERB_KILL
    bne not_kl
    jmp as_kill
not_kl:
    cmp #VERB_DEFEND
    beq as_cover
    cmp #VERB_ATTACK
    beq as_cover
    cmp #VERB_RETREAT
    bne no
as_cover:
    lda zT4
    sta zA0
    lda zT5
    sta zA1
    jsr chip_at
    cmp #NONE
    beq room_pick
    sta zT3
    jsr cover_taken
    bcc chip_free
    ldx think_i
    lda unit_cover,x
    cmp zT3
    beq chip_free
no:
    clc
    rts
chip_free:
    lda zT3
    jsr cover_cell
    bcs chip_xy
    ldx think_i
    lda zR0
    sta unit_over_verb,x
    lda zT3
    jsr cover_put
    lda zT4
    sta unit_over_x,x
    lda zT5
    sta unit_over_y,x
    sec
    rts
chip_xy:
    ldx think_i
    lda zR0
    sta unit_over_verb,x
    lda zT3
    jsr cover_put
    lda mv_ox
    sta unit_over_x,x
    lda mv_oy
    sta unit_over_y,x
    sec
    rts
room_pick:
    lda zT4
    sta zA0
    lda zT5
    sta zA1
    jsr region_at
    cmp #NONE
    beq plain
    cmp room_count
    bcs plain
    sta zT2
    ldx think_i
    lda unit_section,x
    sta mv_who
    jsr section_front
    sta mv_front
    lda zT2
    sta mv_dest
    jsr pick_best
    cmp #NONE
    beq plain
    sta zT3
    jsr cover_cell
    bcc plain
    ldx think_i
    lda zR0
    sta unit_over_verb,x
    lda zT3
    jsr cover_put
    lda mv_ox
    sta unit_over_x,x
    lda mv_oy
    sta unit_over_y,x
    sec
    rts
plain:
    ldx think_i
    lda zR0
    sta unit_over_verb,x
    lda #NONE
    jsr cover_put
    lda zT4
    sta unit_over_x,x
    lda zT5
    sta unit_over_y,x
    sec
    rts
as_halt:
    ldx think_i
    lda #VERB_HALT
    sta unit_over_verb,x
    lda unit_x,x
    sta unit_over_x,x
    lda unit_y,x
    sta unit_over_y,x
    sec
    rts
as_kill:
    ldx think_i
    lda #VERB_KILL
    sta unit_over_verb,x
    lda zT4
    sta unit_over_x,x
    lda zT5
    sta unit_over_y,x
    sec
    rts
as_move:
    ldx think_i
    lda #VERB_MOVE
    sta unit_over_verb,x
    lda zT4
    sta unit_over_x,x
    lda zT5
    sta unit_over_y,x
    lda #NONE
    jsr cover_put
    sec
    rts
.endproc

;-----------------------------------------------------------------------------
; Move up to zA3 infantry from player section zA0 into zA1.
; zA2 is the preferred first slot, or NONE. Carry set on success.
; Carry clear changes nothing. Preserves zT4 and zT5 (the wizard's
; src/dst copy). Trashes A, X, Y, zA0-zA3, zT0-zT3, zT6, zT7.
.proc section_peel
    lda zA0
    cmp #LETTER_MAX
    bcc p_src
    jmp no
p_src:
    lda zA1
    cmp #LETTER_MAX
    bcc p_dst
    jmp no
p_dst:
    cmp zA0
    bne p_diff
    jmp no
p_diff:
    lda zA3
    bne p_n
    jmp no
p_n:
    ldx zA0
    lda section_order_verb,x
    cmp #VERB_KILL
    bne p_ok
    jmp no
p_ok:
    lda zA0
    sta zT2
    lda zA1
    sta zT3
    lda zA3
    sta zT1
    lda #0
    sta zT0
    sta zT6
    ldx zT3
    lda section_lead,x
    cmp #NONE
    bne p_led
    inc zT6
p_led:
    lda zA2
    cmp #UNIT_MAX
    bcs scan
    tax
    lda unit_count,x
    beq scan
    lda unit_section,x
    cmp zT2
    bne scan
    lda unit_kind,x
    cmp #KIND_EMPLACEMENT
    beq scan
    txa
    ldx zT0
    sta peel_pick,x
    inc zT0
scan:
    ldy #0
sloop:
    lda zT0
    cmp zT1
    bcs xfer
    lda unit_count,y
    beq sadv
    lda unit_section,y
    cmp zT2
    bne sadv
    lda unit_kind,y
    cmp #KIND_EMPLACEMENT
    beq sadv
    ldx #0
dup:
    cpx zT0
    bcs take
    lda peel_pick,x
    sty zT7
    cmp zT7
    beq sadv
    inx
    jmp dup
take:
    ldx zT0
    tya
    sta peel_pick,x
    inc zT0
sadv:
    iny
    cpy #UNIT_MAX
    bne sloop
xfer:
    lda zT0
    bne move
no:
    clc
    rts
move:
    ldy #0
xmove:
    cpy zT0
    bcs reled
    ldx peel_pick,y
    lda zT3
    sta unit_section,x
    lda #NONE
    jsr cover_put
    lda #VERB_NONE
    sta unit_over_verb,x
    iny
    jmp xmove
reled:
    ldx zT2
    jsr section_relead
    jsr section_recount
    lda zT6
    bne was_empty
    ldx zT3
    jsr section_relead
    jmp recount2
was_empty:
    ldy peel_pick
    ldx zT3
    tya
    sta section_lead,x
    lda unit_x,y
    sta section_last_x,x
    lda unit_y,y
    sta section_last_y,x
recount2:
    jsr section_recount
    sec
    rts
.endproc

;-----------------------------------------------------------------------------
; Merge every occupied slot in player section zA0 into zA1.
; Carry set on success. Preserves zA0 and zA1. Trashes A, X, Y, zT2, zT3.
.proc section_join
    lda zA0
    cmp #LETTER_MAX
    bcc j_src
    jmp no
j_src:
    lda zA1
    cmp #LETTER_MAX
    bcc j_dst
    jmp no
j_dst:
    cmp zA0
    bne j_diff
    jmp no
j_diff:
    ldx zA0
    lda section_strength,x
    bne j_has
    jmp no
j_has:
    ldx zA1
    lda section_order_verb,x
    bne j_live
    lda section_strength,x
    bne j_live
    jmp no
j_live:
    lda zA0
    sta zT2
    ldx zT2
    lda section_lead,x
    sta zT3
    ldy #0
jmove:
    lda unit_count,y
    beq jadv
    lda unit_section,y
    cmp zT2
    bne jadv
    lda zA1
    sta unit_section,y
    lda #VERB_NONE
    sta unit_over_verb,y
jadv:
    iny
    cpy #UNIT_MAX
    bne jmove
    ldx zA1
    lda section_lead,x
    cmp #NONE
    bne jclear
    lda zT3
    cmp #UNIT_MAX
    bcs jclear
    tay
    lda unit_section,y
    cmp zA1
    bne jclear
    tya
    sta section_lead,x
    lda unit_x,y
    sta section_last_x,x
    lda unit_y,y
    sta section_last_y,x
jclear:
    ldx zT2
    lda #NONE
    sta section_lead,x
    jsr section_recount
    ldx zA1
    lda section_order_verb,x
    cmp #VERB_DEFEND
    beq jarm
    cmp #VERB_ATTACK
    beq jarm
    cmp #VERB_RETREAT
    beq jarm
    jmp jok
jarm:
    lda section_flags,x
    and #($FF ^ FLAG_RELEASE)
    ora #FLAG_ASSIGN
    sta section_flags,x
jok:
    sec
    rts
no:
    clc
    rts
.endproc

;-----------------------------------------------------------------------------
; Next room after zA0 whose heat is still counting, or NONE in A.
; A previous room of NONE, or past the table, starts at room 0.
; Preserves zA1. Trashes A, X, zT0-zT2.
.proc intel_next_hot
    lda #0
    sta zT0
    jmp intel_next
.endproc

;-----------------------------------------------------------------------------
; Next room after zA0 with ROOM_MARK set, or NONE in A.
; Preserves zA1. Trashes A, X, zT0-zT2.
.proc intel_next_mark
    lda #ROOM_MARK
    sta zT0
    jmp intel_next
.endproc

;-----------------------------------------------------------------------------
; Walk the rooms once, starting just after zA0. zT0 = 0 selects heat;
; any other value is a room_flags mask. A = the room, or NONE.
; Preserves zA1.
.proc intel_next
    lda room_count
    bne have_n
none:
    lda #NONE
    rts
have_n:
    cmp #(ROOM_MAX+1)
    bcc capped
    lda #ROOM_MAX
capped:
    sta zT1
    lda zA0
    cmp zT1
    bcs wrap
    clc
    adc #1
    cmp zT1
    bcc have_s
wrap:
    lda #0
have_s:
    sta zT2
    tax
hi:
    cpx zT1
    bcs lo
    jsr intel_consider
    bcs found
    inx
    jmp hi
lo:
    ldx #0
lob:
    cpx zT2
    bcs none
    jsr intel_consider
    bcs found
    inx
    jmp lob
found:
    txa
    rts
.endproc

;-----------------------------------------------------------------------------
; X = room. zT0 = 0 selects a room whose heat is above zero, otherwise
; a room_flags mask. Carry set on a match. Preserves X, Y, and zA1.
.proc intel_consider
    lda zT0
    beq heat
    and room_flags,x
    beq no
yes:
    sec
    rts
heat:
    lda room_heat,x
    bne yes
no:
    clc
    rts
.endproc

;-----------------------------------------------------------------------------
; zA0 is a room. A = the first player section with an occupied slot
; there, or NONE. Does not require the slot to be in the room table.
; Trashes Y.
.proc intel_player_in_room
    ldy #0
scan:
    lda unit_count,y
    beq adv
    lda unit_region,y
    cmp zA0
    bne adv
    lda unit_section,y
    cmp #LETTER_MAX
    bcc found
adv:
    iny
    cpy #UNIT_MAX
    bne scan
    lda #NONE
    rts
found:
    rts
.endproc

;-----------------------------------------------------------------------------
; An attacking enemy section takes cover once any of its men has entered
; the order cell's room. Sets FLAG_CONTACT and FLAG_ASSIGN. No arguments.
; Trashes A, X, Y, zA0, zA1, zT0, zT1.
.proc contact_start
    ldx #LETTER_MAX
who:
    cpx #SECTION_MAX
    bcs done
    lda section_order_verb,x
    cmp #VERB_ATTACK
    bne adv
    lda section_flags,x
    and #FLAG_CONTACT
    bne adv
    lda section_order_x,x
    sta zA0
    lda section_order_y,x
    sta zA1
    stx zT1
    jsr region_at
    cmp #NONE
    beq re
    sta zT0
    ldy #0
men:
    lda unit_count,y
    beq madv
    lda unit_section,y
    cmp zT1
    bne madv
    lda unit_region,y
    cmp zT0
    bne madv
    ldx zT1
    lda section_flags,x
    ora #(FLAG_CONTACT | FLAG_ASSIGN)
    sta section_flags,x
    jmp re
madv:
    iny
    cpy #UNIT_MAX
    bne men
re:
    ldx zT1
adv:
    inx
    jmp who
done:
    rts
.endproc

;-----------------------------------------------------------------------------
; Y = unit. A = his room. A stored id past the room table is looked up
; from his cell. Y is preserved. Trashes X, zA0, zA1.
.proc room_of_unit
    lda unit_region,y
    cmp #ROOM_MAX
    bcc keep
    lda unit_x,y
    sta zA0
    lda unit_y,y
    sta zA1
    jmp region_at
keep:
    rts
.endproc

;-----------------------------------------------------------------------------
; Refresh LIVE, SEEN, and MARK, and cool every room's heat by one.
; Fog is off, so an enemy always marks the room he is standing in.
; No arguments. Trashes A, X, Y, zA0, zA1.
.proc intel_pulse
    ldx #ROOM_MAX-1
    lda #0
clr:
    sta enemy_in,x
    dex
    bpl clr
    ldx #ROOM_MAX-1
drop:
    lda room_flags,x
    and #($FF ^ ROOM_LIVE)
    sta room_flags,x
    dex
    bpl drop
    ldy #0
fri:
    lda unit_count,y
    beq fadv
    lda unit_hp,y
    beq fadv
    lda unit_section,y
    cmp #LETTER_MAX
    bcs fadv
    jsr room_of_unit
    cmp room_count
    bcs fadv
    cmp #ROOM_MAX
    bcs fadv
    tax
    lda room_flags,x
    ora #(ROOM_LIVE | ROOM_SEEN)
    sta room_flags,x
fadv:
    iny
    cpy #UNIT_MAX
    bne fri
    ldy #0
en:
    lda unit_count,y
    beq eadv
    lda unit_hp,y
    beq eadv
    lda unit_section,y
    cmp #LETTER_MAX
    bcc eadv
    cmp #SECTION_MAX
    bcs eadv
    jsr room_of_unit
    cmp room_count
    bcs eadv
    cmp #ROOM_MAX
    bcs eadv
    tax
    lda #1
    sta enemy_in,x
    lda room_flags,x
    and #ROOM_MARK
    bne marked
    lda #HEAT_START
    sta room_heat,x
marked:
    lda room_flags,x
    ora #ROOM_MARK
    sta room_flags,x
    lda unit_x,y
    sta last_x,x
    lda unit_y,y
    sta last_y,x
eadv:
    iny
    cpy #UNIT_MAX
    bne en
    ldy #0
cool:
    cpy room_count
    bcs done
    cpy #ROOM_MAX
    bcs done
    lda room_flags,y
    and #ROOM_LIVE
    beq heat
    lda enemy_in,y
    bne heat
    lda room_flags,y
    and #($FF ^ ROOM_MARK)
    sta room_flags,y
heat:
    lda room_heat,y
    beq cadv
    sec
    sbc #1
    sta room_heat,y
cadv:
    iny
    jmp cool
done:
    rts
.endproc

.segment "CODE"

;-----------------------------------------------------------------------------
; C = terrain at zA2,zA3 is in bounds and walkable; occupancy is a separate test.
; Tile 81 is open even on blue paper. Tile 80 is closed on its own.
; Walls, barriers (bush tiles 64-65), and blue paper (colour tile 118).
; The paper test masks the low nibble: component ids live in bits 4-7.
; map_ptr returns the tile in A and Y = 0.
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
    cmp #TILE_DECK_BUILT
    beq yes
    cmp #TILE_DECK_OPEN
    beq no
    pha
    lda (zPtr2),y
    and #$0F
    cmp #PAPER_WATER
    beq popno
    pla
    tay
    lda rom_tile_class,y
    cmp #CLASS_WALLS
    beq no
    cmp #CLASS_BARRIERS
    beq no
yes:
    sec
    rts
popno:
    pla
no:
    clc
    rts
.endproc

;-----------------------------------------------------------------------------
; C = a living unit occupies zA2,zA3, ignoring the slot in zT7.
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

;-----------------------------------------------------------------------------
; Show the objective addressed by op Y for about four seconds. Preserves Y.
.proc script_objective
    lda sc_op_a,y
    sta objective_ptr
    lda sc_op_b,y
    sta objective_ptr+1
    lda $02A6
    beq ntsc
    lda #67
    bne store
ntsc:
    lda #80
store:
    sta objective_ttl
    rts
.endproc

; Place init ops once after initial_routes, before watches. Y is the op index.
; Spawns drain before the next op. Does not move script_pc.
.proc script_init
    ldy #0
loop:
    cpy sc_beat_pc
    bcc one
    rts
one:
    lda sc_op_code,y
    cmp #1
    bne not_sp
    jsr init_drain
    jmp adv
not_sp:
    cmp #2
    bne not_ord
    tya
    pha
    jsr script_order
    pla
    tay
    jmp adv
not_ord:
    cmp #OP_SET_SPAWN
    bne not_set
    lda sc_op_a,y
    sta spawn_room
    jmp adv
not_set:
    cmp #OP_OBJECTIVE
    bne not_objective
    jsr script_objective
    jmp adv
not_objective:
    cmp #OP_APPROACH
    bne adv
    lda sc_op_a,y
    sta zA0
    lda sc_op_b,y
    sta zA1
    tya
    pha
    jsr script_approach
    pla
    tay
adv:
    iny
    jmp loop
.endproc

;-----------------------------------------------------------------------------
; Y is the spawn op. Arm that template and pulse until the group is placed
; or a pulse lands nobody. Preserves Y.
.proc init_drain
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
drain:
    lda spawn_job_rem
    beq done
    pha
    tya
    pha
    jsr spawn_pulse
    pla
    tay
    pla
    cmp spawn_job_rem
    beq done
    jmp drain
done:
    rts
.endproc

;-----------------------------------------------------------------------------
; Y is an order op. Issues it. Clobbers Y and the resolve scratch.
; Does not move script_pc. A live spawn job for this letter still
; snapshots issued strength as living plus remaining.
.proc script_order
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
    bcc skip
    jsr section_issue
    lda zA1
    cmp #VERB_ATTACK
    bne snap
    ldx mv_who
    lda section_flags,x
    and #($FF ^ FLAG_ASSIGN)
    sta section_flags,x
snap:
    lda spawn_job_rem
    beq skip
    lda spawn_job_letter
    cmp mv_who
    bne skip
    ldx mv_who
    lda section_strength,x
    clc
    adc spawn_job_rem
    sta section_order_str,x
skip:
    rts
.endproc

;-----------------------------------------------------------------------------
; Watches run first, then immediate ops until a wait or an outcome.
; An armed wait resumes on a later tick. A watch can end the mission
; while a wait is still armed. Init already ran at load, before watches.
.proc script_step
    jsr script_watches
    lda script_outcome
    beq playing
    rts
playing:
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
    cmp #OP_OBJECTIVE
    bne not_objective
    jsr script_objective
    inc script_pc
    jmp run
not_objective:
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
    ; Arm and return immediately: even an already-true condition waits until the next tick.
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
    jsr script_order
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
; Trashes X and Y.
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
