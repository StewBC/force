; Compact reinforcement/weapon extension. Template byte: facing:2, kind:2,
; section:4. Point origins tag an existing CELL WHERE with bit 7.
.segment "SPARE"
spawn_job_type: .byte 0
weapon_ammo: .res UNIT_MAX, 0
cb_weapon: .byte 0
seen_kind: .res UNIT_MAX, 0
status_valid: .byte 0
status_outcome: .byte 0
STATUS_KEY_BYTES = 12
status_key: .res STATUS_KEY_BYTES, 0

; X=template, Y preserved. Shared by init and beat spawns.
.proc arm_spawn
    lda sc_spawn_n,x
    sta spawn_job_rem
    lda sc_spawn_letter,x
    sta spawn_job_type
    and #$0F
    sta spawn_job_letter
    lda sc_spawn_room,x
    sta spawn_job_room
    lda sc_spawn_batch,x
    sta spawn_job_batch
    lda sc_spawn_period,x
    sta spawn_job_period
    lda #0
    sta spawn_job_wait
    rts
.endproc

; Return zA3=kind, zT7=facing glyph for the pending job. A/X scratch.
.proc spawn_identity
    lda spawn_job_type
    lsr
    lsr
    lsr
    lsr
    and #3
    sta zA3
    cmp #KIND_EMPLACEMENT
    bne east
    lda spawn_job_type
    rol
    rol
    rol
    and #3
    asl
    bpl face
east:
    lda #2
face:
    sta zT7
    lda spawn_job_letter
    cmp #LETTER_MAX
    bcc done
    lda zT7
    ora #8
    sta zT7
done:
    rts
.endproc

; Y=new slot, zA3=kind. Initialize HP/ammo on every reuse. Preserve X/Y.
.proc weapon_spawn
    lda #0
    sta weapon_ammo,y
    lda zA3
    cmp #KIND_BAZOOKA
    bne health
    lda #4
    sta weapon_ammo,y
health:
    lda zA3
    cmp #KIND_EMPLACEMENT
    beq nest
    lda #HP_INFANTRY
    bne store
nest:
    lda #48
store:
    sta unit_hp,y
    rts
.endproc

; cb_i=shooter. Carry clear for the reserved vehicle kind. Empty launchers
; fall back to the rifle; cb_weapon is the weapon used for this opportunity.
.proc weapon_prepare
    ldx cb_i
    lda unit_kind,x
    cmp #1
    beq no
    cmp #KIND_BAZOOKA
    bne ready
    lda weapon_ammo,x
    bne bazooka
    lda #KIND_INFANTRY
    beq ready
bazooka:
    lda #KIND_BAZOOKA
ready:
    sta cb_weapon
    sec
    rts
no:
    clc
    rts
.endproc

; cb_i/cb_j=shooter/target. Preserve the closest-distance accumulator.
; Rifles retain existing rules; launchers select nests with a wall-clear ray.
; Nests use a cardinal 90-degree arc and a wall-clear ray.
.proc special_target_ok
    lda cb_weapon
    beq yes
    cmp #KIND_BAZOOKA
    bne positions
    ldx cb_j
    lda unit_kind,x
    cmp #KIND_EMPLACEMENT
    bne no
positions:
    ldx cb_i
    lda unit_x,x
    sta cb_x0
    lda unit_y,x
    sta cb_y0
    ldx cb_j
    lda unit_x,x
    sta cb_x1
    lda unit_y,x
    sta cb_y1
    lda cb_weapon
    cmp #KIND_EMPLACEMENT
    bne ray
    jsr nest_arc
    bcc no
ray:
    lda #2
    sta cb_kind
    jmp ray_clear
yes:
    sec
    rts
no:
    clc
    rts
.endproc

; Endpoints cb_x0/y0 -> cb_x1/y1. C=inside the nest's forward 90-degree arc.
.proc nest_arc
    lda cb_x1
    sec
    sbc cb_x0
    sta cb_dx
    bpl xabs
    eor #$FF
    clc
    adc #1
xabs:
    sta cb_adx
    lda cb_y1
    sec
    sbc cb_y0
    sta cb_dy
    bpl yabs
    eor #$FF
    clc
    adc #1
yabs:
    sta cb_ady
    ldx cb_i
    lda unit_glyph,x
    and #6
    beq north
    cmp #2
    beq east
    cmp #4
    beq south
west:
    lda cb_dx
    bpl no
    bmi horizontal
east:
    lda cb_dx
    bmi no
horizontal:
    lda cb_adx
    cmp cb_ady
    rts
north:
    lda cb_dy
    bpl no
    bmi vertical
south:
    lda cb_dy
    bmi no
vertical:
    lda cb_ady
    cmp cb_adx
    rts
no:
    clc
    rts
.endproc

; A=posture damage, cb_j=target. Nests take 1 from a landed bullet;
; launcher hits deal 32 regardless of posture. Grenades retain their 8.
.proc weapon_damage
    ldx cb_weapon
    cpx #KIND_BAZOOKA
    beq rocket
    cmp #0
    beq done
    ldx cb_j
    pha
    lda unit_kind,x
    cmp #KIND_EMPLACEMENT
    bne ordinary
    pla
    lda #1
    rts
ordinary:
    pla
done:
    rts
rocket:
    lda #32
    rts
.endproc

; cb_i=shooter. Return reload in A; consume ammunition only on a rocket hit.
.proc weapon_reload
    lda cb_weapon
    cmp #KIND_EMPLACEMENT
    beq nest
    cmp #KIND_BAZOOKA
    bne rifle
    ldx cb_i
    dec weapon_ammo,x
    lda #20
    rts
nest:
    lda #3
    rts
rifle:
    lda #FIRE_WAIT
    rts
.endproc
weapon_range: .byte RIFLE_FAR, 0, RIFLE_FAR, RIFLE_FAR

; Compare every input used by fill_status, independently of the broad UI flag.
; C=set if formatting is necessary. X/A scratch. No cursor/roster dependencies.
.proc status_changed
    lda status_valid
    beq changed
    lda script_outcome
    cmp status_outcome
    bne changed
    ldx #cmd_nopath-cmd_verb
compare:
    lda cmd_verb,x
    cmp status_key,x
    bne changed
    dex
    bpl compare
    clc
    rts
changed:
    lda #1
    sta status_valid
    lda script_outcome
    sta status_outcome
    ldx #cmd_nopath-cmd_verb
copy:
    lda cmd_verb,x
    sta status_key,x
    dex
    bpl copy
    sec
    rts
.endproc
; Launchers prefer nests; if none is available their crew uses rifles.
.proc pick_weapon_target
    jsr smear_closest
    lda cb_tgt
    cmp #NONE
    bne done
    lda cb_weapon
    cmp #KIND_BAZOOKA
    bne done
    lda #0
    sta cb_weapon
    jmp smear_closest
done:
    rts
.endproc

; Add a grey tripod or launcher tube to the ordinary facing glyph row Y.
; Preserve Y and all compositor pointers. zT5 is the glyph byte.
.proc weapon_glyph
    ldx zT7
    lda unit_kind,x
    cmp #KIND_EMPLACEMENT
    bne launcher
    cpy #6
    beq grey
    rts
launcher:
    cmp #KIND_BAZOOKA
    bne done
    cpy #3
    bne done
grey:
    lda #$55
    sta zT5
done:
    rts
.endproc
.segment "CODE"
