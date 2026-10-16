; All record validation occurs before objective relocation or runtime scatter.
; Enter with ROM hidden, IRQ/NMI contract active. No KERNAL calls. z* scratch.
; Reject counts, body extent, rectangle/spawns, op references and table links.
.segment "BANK_VALIDATION"
.proc validate_record
    lda mission_entry+7
    bne header
    lda mission_entry+6
    cmp #20
    bcs header
    jmp fail7
header:
    lda PACK_HOME
    cmp #80
    bcc coord_x
    jmp fail7
coord_x:
    lda PACK_HOME+1
    cmp #40
    bcc coord_y
    jmp fail7
coord_y:
    lda PACK_HOME+4
    cmp #80
    bcc camera_x
    jmp fail7
camera_x:
    lda PACK_HOME+5
    cmp #40
    bcc camera_y
    jmp fail7
camera_y:
    lda PACK_HOME+2
    bne valid_branch_1
    jmp bad
valid_branch_1:
    clc
    adc PACK_HOME
    cmp #161
    bcc safe_0
    jmp fail7
safe_0:
    lda PACK_HOME+3
    bne valid_branch_2
    jmp bad
valid_branch_2:
    clc
    adc PACK_HOME+1
    bcs bad
    cmp #41
    bcc valid_branch_3
    jmp bad
valid_branch_3:
    lda PACK_HOME+6
    cmp #SPAWN_MAX+1
    bcc valid_branch_4
    jmp bad
valid_branch_4:
    sta cnt_spawn
    asl
    clc
    adc cnt_spawn
    adc #7
    sta zT4
    tay
    lda mission_entry+7
    bne counts
    tya
    clc
    adc #13
    cmp plen
    bcc counts
    beq counts
bad:
    jmp fail7
counts:
    ldx #0
count:
    lda PACK_HOME,y
    cmp cap_tab,x
    bcc valid_branch_5
    jmp bad
valid_branch_5:
    sta cnt_op,x
    iny
    inx
    cpx #6
    bne count
    ; Initialize body-size accumulator before walking variable columns.
    lda #20
    sta zT0
    lda #0
    sta zT1
    ldx #0
size:
    lda cnt_spawn,x
    sta zA0
    lda mul_tab,x
    sta zA1
    txa
    pha
    jsr add_times
    pla
    tax
    inx
    cpx #7
    bne size
    lda zT0
    cmp plen
    beq valid_branch_6
    jmp bad
valid_branch_6:
    lda zT1
    cmp plen+1
    beq valid_branch_7
    jmp bad
valid_branch_7:
    ldy zT4
    lda PACK_HOME+6,y
    cmp rom_room_count
    bcc valid_branch_8
    jmp bad
valid_branch_8:
    lda PACK_HOME+7,y
    cmp cnt_beat
    bcc scalars
    lda cnt_beat
    beq scalars
    beq valid_branch_9
    jmp bad
valid_branch_9:
scalars:
    lda zT4
    clc
    adc #13
    sta zSrc
    lda #>PACK_HOME
    sta zSrc+1
    ; Validate spawn coordinates (the three-column tight image).
    lda #<(PACK_HOME+7)
    sta zPtr
    lda #>(PACK_HOME+7)
    sta zPtr+1
    ldy #0
spawn_x:
    cpy cnt_spawn
    beq spawn_y_start
    lda (zPtr),y
    cmp #160
    bcc valid_branch_10
    jmp bad
valid_branch_10:
    iny
    bne spawn_x
spawn_y_start:
    tya
    clc
    adc zPtr
    sta zPtr
    ldy #0
spawn_y:
    cpy cnt_spawn
    beq spawn_tiles_start
    lda (zPtr),y
    cmp #40
    bcc valid_branch_11
    jmp bad
valid_branch_11:
    iny
    bne spawn_y
spawn_tiles_start:
    tya
    clc
    adc zPtr
    sta zPtr
    ldy #0
spawn_tiles:
    cpy cnt_spawn
    beq ops_start
    lda (zPtr),y
    cmp #128
    bcc stamp_ok
    jmp fail7
stamp_ok:
    iny
    bne spawn_tiles
ops_start:
    lda zSrc
    clc
    adc cnt_op
    sta zPtr2
    lda zSrc+1
    adc #0
    sta zPtr2+1
    lda zPtr2
    clc
    adc cnt_op
    sta zDst
    lda zPtr2+1
    adc #0
    sta zDst+1
    lda zDst
    clc
    adc cnt_op
    sta zPtr
    lda zDst+1
    adc #0
    sta zPtr+1
    ldx #0
op:
    cpx cnt_op
    bne valid_branch_12
    jmp beats
valid_branch_12:
    ldy #0
    lda (zSrc),y
    cmp #11
    bcc valid_branch_13
    jmp invalid
valid_branch_13:
    cmp #1
    bne order
    lda (zPtr2),y
    cmp cnt_tmpl
    bcc valid_branch_14
    jmp invalid
valid_branch_14:
    bcc advance
order:
    cmp #2
    bne room
    lda (zPtr2),y
    cmp #16
    bcc valid_branch_15
    jmp invalid
valid_branch_15:
    lda (zPtr),y
    cmp cnt_where
    bcc valid_branch_16
    jmp invalid
valid_branch_16:
    bcc advance
room:
    cmp #3
    beq room_check
    cmp #4
    bne goto
room_check:
    lda (zPtr2),y
    cmp rom_room_count
    bcc valid_branch_17
    jmp invalid
valid_branch_17:
    bcc advance
goto:
    cmp #5
    bne wait
    lda (zPtr2),y
    cmp cnt_beat
    bcc valid_branch_18
    jmp invalid
valid_branch_18:
    bcc advance
wait:
    cmp #6
    bne advance
    lda (zPtr2),y
    cmp cnt_pred
    bcc valid_branch_19
    jmp invalid
valid_branch_19:
    lda (zDst),y
    cmp #$FF
    beq wait_dest
    cmp cnt_pred
    bcc valid_branch_20
    jmp invalid
valid_branch_20:
wait_dest:
    lda (zPtr),y
    cmp cnt_beat
    bcc valid_branch_21
    jmp invalid
valid_branch_21:
advance:
    inc zSrc
    bne src_same
    inc zSrc+1
src_same:
    inc zPtr2
    bne a_same
    inc zPtr2+1
a_same:
    inc zDst
    bne b_same
    inc zDst+1
b_same:
    inc zPtr
    bne c_same
    inc zPtr+1
c_same:
    inx
    jmp op
invalid:
    jmp fail7
beats:
    ldy #0
beat:
    cpy cnt_beat
    beq tables
    lda (zPtr),y
    cmp cnt_op
    bcc beat_ok
    beq valid_branch_22
    jmp invalid
valid_branch_22:
beat_ok:
    iny
    bne beat
tables:
    ; Advance from beat table to watch columns.
    lda cnt_beat
    jsr advance_table
    lda cnt_watch
    sta zR0
    lda #0
    sta zT7
watch:
    ldy zT7
    cpy zR0
    bne watch_in
    jmp predicates
watch_in:
    lda (zPtr),y
    cmp cnt_pred
    bcc table_safe_1
    jmp fail7
table_safe_1:
    tya
    clc
    adc cnt_watch
    tay
    lda (zPtr),y
    cmp #$FF
    beq watch_ok
    cmp cnt_pred
    bcc table_safe_2
    jmp fail7
table_safe_2:
watch_ok:
    ldy zT7
    tya
    clc
    adc cnt_watch
    adc cnt_watch
    tay
    lda (zPtr),y
    cmp #10
    bcs invalid_watch
    cmp #3
    beq watch_room
    cmp #4
    beq watch_room
    cmp #5
    bne watch_advance
    iny_arg:
    sta zT6
    tya
    clc
    adc cnt_watch
    tay
    lda (zPtr),y
    cmp cnt_beat
    bcs invalid_watch
    bcc watch_advance
watch_room:
    tya
    clc
    adc cnt_watch
    tay
    lda (zPtr),y
    and #$0F
    cmp rom_room_count
    bcs invalid_watch
watch_advance:
    ldy zT7
    tya
    clc
    adc cnt_watch
    adc cnt_watch
    adc cnt_watch
    adc cnt_watch
    tay
    lda (zPtr),y
    and #$FE
    bne invalid_watch
    inc zT7
    jmp watch
invalid_watch:
    jmp fail7
predicates:
    lda cnt_watch
    ldx #5
    jsr advance_columns
    ldy #0
pred:
    cpy cnt_pred
    beq wheres
    lda (zPtr),y
    cmp #PRED_BRIDGE_BUILT+1
    bcc table_safe_3
    jmp fail7
table_safe_3:
    iny
    bne pred
wheres:
    lda cnt_pred
    ldx #4
    jsr advance_columns
    lda zPtr
    sta zPtr2
    lda zPtr+1
    sta zPtr2+1
    ldy #0
where:
    cpy cnt_where
    beq templates
    lda (zPtr),y
    cmp #4
    bcc table_safe_4
    jmp fail7
table_safe_4:
    cmp #0
    bne where_ok
    tya
    clc
    adc cnt_where
    tay
    lda (zPtr),y
    cmp rom_room_count
    bcc table_safe_5
    jmp fail7
table_safe_5:
    tya
    sec
    sbc cnt_where
    tay
where_ok:
    iny
    bne where
invalid_table:
    jmp fail7
templates:
    lda cnt_where
    ldx #3
    jsr advance_columns
    lda #0
    sta zT7
tmpl:
    ldy zT7
    cpy cnt_tmpl
    bne :+
    jmp done
:
    lda (zPtr),y
    bne :+
    jmp invalid_template
:
    cmp #UNIT_MAX+1
    bcc :+
    jmp invalid_template
:
    sta zT5
    tya
    clc
    adc cnt_tmpl
    tay
    lda (zPtr),y
    and #$30
    cmp #$10
    bne :+
    jmp invalid_template
:
    sta zT4
    cmp #$20
    beq identity_ok
    lda (zPtr),y
    and #$C0
    beq :+
    jmp invalid_template
:
identity_ok:
    tya
    clc
    adc cnt_tmpl
    tay
    lda (zPtr),y
    cmp #$FF
    beq room_source
    bpl room_source
    and #$7F
    cmp cnt_where
    bcc :+
    jmp invalid_template
:
    tay
    lda (zPtr2),y
    cmp #WHERE_CELL
    beq :+
    jmp invalid_template
:
    tya
    clc
    adc cnt_where
    tay
    lda (zPtr2),y
    cmp rom_map_w
    bcc :+
    jmp invalid_template
:
    tya
    clc
    adc cnt_where
    tay
    lda (zPtr2),y
    cmp rom_map_h
    bcc :+
    jmp invalid_template
:
    lda zT4
    cmp #$20
    bne pacing
    lda zT5
    cmp #1
    beq :+
    jmp invalid_template
:
    beq pacing
room_source:
    ldx zT4
    cpx #$20
    bne :+
    jmp invalid_template
:
    cmp #$FF
    beq pacing
    cmp rom_room_count
    bcc :+
    jmp invalid_template
:
pacing:
    lda zT7
    clc
    adc cnt_tmpl
    adc cnt_tmpl
    adc cnt_tmpl
    tay
    lda (zPtr),y
    bne :+
    jmp invalid_template
:
    tya
    clc
    adc cnt_tmpl
    tay
    lda (zPtr),y
    bne :+
    jmp invalid_template
:
    inc zT7
    jmp tmpl
invalid_template:
    jmp fail7
done:
    rts
; A=count, X=columns. Advance zPtr by A*X, preserving Y.
advance_columns:
    sta zT6
column:
    lda zT6
    jsr advance_table
    dex
    bne column
    rts
advance_table:
    clc
    adc zPtr
    sta zPtr
    lda zPtr+1
    adc #0
    sta zPtr+1
    rts

.endproc
