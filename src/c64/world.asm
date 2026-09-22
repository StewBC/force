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
    rts
.endproc

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
    beq op_spawn
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
    lda #1
    sta script_waiting
    inc script_pc
waiting:
    jsr pred_ok
    bcc still
    lda #0
    sta script_waiting
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

.proc pred_ok
    clc
    rts
.endproc
