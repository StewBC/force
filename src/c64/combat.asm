; Rifles, deaths, and grenades from src/sdl/game/world.c.
; A rifle picks the closest other-bank man inside 9. ray_clear stays
; and is not called. Grenade splash still walks it. Trace logging is
; omitted. Procs may trash X, Y, and world zero page. The shooter index
; lives in cb_i. Do not touch zSrc or zDst: draw calls grenade_fx_at
; while those point at the cell being stored.

cb_bit:
    .byte $01, $02, $04, $08, $10, $20, $40, $80

; zA0,zA1 and zA2,zA3. A = max(|dx|,|dy|). Trashes zT4.
.proc chebyshev
    lda zA0
    sec
    sbc zA2
    bcs dxok
    lda zA2
    sec
    sbc zA0
dxok:
    sta zT4
    lda zA1
    sec
    sbc zA3
    bcs dyok
    lda zA3
    sec
    sbc zA1
dyok:
    cmp zT4
    bcs bigger
    lda zT4
bigger:
    rts
.endproc

.proc chebyshev_cb
    lda cb_x0
    sta zA0
    lda cb_y0
    sta zA1
    lda cb_x1
    sta zA2
    lda cb_y1
    sta zA3
    jmp chebyshev
.endproc

.proc chebyshev_units
    ldx cb_i
    lda unit_x,x
    sta zA0
    lda unit_y,x
    sta zA1
    ldx cb_j
    lda unit_x,x
    sta zA2
    lda unit_y,x
    sta zA3
    jmp chebyshev
.endproc

; cb_x,cb_y. cb_kind 0 blocks walls and roofs; 1 blocks walls only.
; Carry set if the cell blocks.
.proc blocks_cell
    lda cb_x
    cmp map_w
    bcs block
    lda cb_y
    cmp map_h
    bcs block
    lda cb_x
    sta zA0
    lda cb_y
    sta zA1
    jsr map_ptr
    tax
    lda rom_tile_class,x
    cmp #CLASS_WALLS
    beq block
    ldx cb_kind
    bne open
    cmp #CLASS_ROOFS
    beq block
open:
    clc
    rts
block:
    sec
    rts
.endproc

; cb_x0,y0 -> cb_x1,y1. cb_kind selects the occluder.
; Carry set if the ray is clear. Endpoints are not tested.
.proc ray_clear
    lda cb_x1
    sec
    sbc cb_x0
    beq dx0
    bcs dxpos
    eor #$FF
    clc
    adc #1
    sta cb_adx
    lda #$FF
    sta cb_sx
    jmp dyset
dx0:
    sta cb_adx
    lda #0
    sta cb_sx
    jmp dyset
dxpos:
    sta cb_adx
    lda #1
    sta cb_sx
dyset:
    lda cb_y1
    sec
    sbc cb_y0
    beq dy0
    bcs dypos
    eor #$FF
    clc
    adc #1
    sta cb_ady
    lda #$FF
    sta cb_sy
    jmp nset
dy0:
    sta cb_ady
    lda #0
    sta cb_sy
    jmp nset
dypos:
    sta cb_ady
    lda #1
    sta cb_sy
nset:
    lda cb_adx
    cmp cb_ady
    bcs nx
    lda cb_ady
nx:
    sta cb_n
    cmp #2
    bcs far
    sec
    rts
far:
    lda cb_kind
    bne blast_lim
    lda cb_n
    cmp #RANGE_MAX
    bcc major
    jmp blocked
blast_lim:
    lda cb_n
    cmp #GRENADE_BLAST+1
    bcc major
    jmp blocked
major:
    lda cb_adx
    cmp cb_ady
    bcc ymaj
    lda cb_adx
    lsr
    sta cb_err
    lda cb_x0
    sta cb_x
    lda cb_y0
    sta cb_y
    lda #1
    sta cb_step
xloop:
    lda cb_step
    cmp cb_n
    bcc xstep
    jmp clear
xstep:
    clc
    lda cb_x
    adc cb_sx
    sta cb_x
    clc
    lda cb_err
    adc cb_ady
    sta cb_err
    cmp cb_adx
    bcc xnob
    sec
    sbc cb_adx
    sta cb_err
    clc
    lda cb_y
    adc cb_sy
    sta cb_y
xnob:
    jsr blocks_cell
    bcs blocked
    inc cb_step
    jmp xloop
ymaj:
    lda cb_ady
    lsr
    sta cb_err
    lda cb_x0
    sta cb_x
    lda cb_y0
    sta cb_y
    lda #1
    sta cb_step
yloop:
    lda cb_step
    cmp cb_n
    bcs clear
    clc
    lda cb_y
    adc cb_sy
    sta cb_y
    clc
    lda cb_err
    adc cb_adx
    sta cb_err
    cmp cb_ady
    bcc ynob
    sec
    sbc cb_ady
    sta cb_err
    clc
    lda cb_x
    adc cb_sx
    sta cb_x
ynob:
    jsr blocks_cell
    bcs blocked
    inc cb_step
    jmp yloop
clear:
    sec
    rts
blocked:
    clc
    rts
.endproc

; Parked. Rifles do not call this. in_blast still walks ray_clear.
.proc ray_units
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
    lda #0
    sta cb_kind
    jmp ray_clear
.endproc

; Carry set when the cell is inside the occluded blast disk.
.proc in_blast
    jsr chebyshev_cb
    cmp #GRENADE_BLAST+1
    bcs no
    lda #1
    sta cb_kind
    jmp ray_clear
no:
    clc
    rts
.endproc

; zA0,zA1 are the map cell. Carry set when that cell should flash.
.proc grenade_fx_at
    lda zA0
    cmp map_w
    bcs no
    lda zA1
    cmp map_h
    bcs no
    sta cb_y1
    lda zA0
    sta cb_x1
    jsr map_ptr
    tax
    lda rom_tile_class,x
    cmp #CLASS_WALLS
    beq no
    cmp #CLASS_ROOFS
    beq no
    ldx #0
banks:
    lda nade_fx_ttl,x
    beq nb
    lda nade_fx_x,x
    sta cb_x0
    lda nade_fx_y,x
    sta cb_y0
    txa
    pha
    jsr in_blast
    pla
    tax
    bcs yes
nb:
    inx
    cpx #2
    bne banks
no:
    clc
    rts
yes:
    sec
    rts
.endproc

.proc other_bank_of_i
    ldx cb_i
    lda unit_section,x
    cmp #LETTER_MAX
    bcs en
    lda #LETTER_MAX
    bne setb
en:
    lda #0
setb:
    sta cb_bank
    clc
    adc #LETTER_MAX
    sta cb_bank_hi
    rts
.endproc

; think_i is the man. Carry set when he has not reached his dest.
.proc dest_left
    jsr unit_dest
    bcc here
    ldx think_i
    lda unit_x,x
    cmp mv_ox
    bne away
    lda unit_y,x
    cmp mv_oy
    bne away
here:
    clc
    rts
away:
    sec
    rts
.endproc

; Carry set when this infantry may fire. cb_verb is the effective verb.
.proc weapons_free
    ldx cb_i
    stx think_i
    lda unit_section,x
    sta mv_who
    jsr effective_verb
    sta cb_verb
    cmp #VERB_MOVE
    bne hold
    jsr dest_left
    bcs no
    sec
    rts
hold:
    cmp #VERB_ATTACK
    beq yes
    cmp #VERB_DEFEND
    beq yes
    cmp #VERB_RETREAT
    beq yes
    cmp #VERB_HALT
    beq yes
    cmp #VERB_KILL
    beq yes
no:
    clc
    rts
yes:
    sec
    rts
.endproc

; cb_dx, cb_dy are signed. A = cardinal, or FACE_NONE.
.proc snap_cardinal
    lda cb_dx
    bpl dxp
    eor #$FF
    clc
    adc #1
dxp:
    sta cb_adx
    lda cb_dy
    bpl dyp
    eor #$FF
    clc
    adc #1
dyp:
    sta cb_ady
    cmp cb_adx
    bcs dyge
    lda cb_dx
    bmi west
    lda #FACE_E
    rts
west:
    lda #FACE_W
    rts
dyge:
    lda cb_ady
    beq axonly
    lda cb_dy
    bmi north
    lda #FACE_S
    rts
north:
    lda #FACE_N
    rts
axonly:
    lda cb_adx
    beq none
    lda cb_dx
    bmi west2
    lda #FACE_E
    rts
west2:
    lda #FACE_W
    rts
none:
    lda #FACE_NONE
    rts
.endproc

; cb_j. Carry set and A = grade when he stands on his assigned chip.
; Scouts are not chips.
.proc on_assigned_hole
    ldx cb_j
    lda unit_cover,x
    cmp #COVER_MAX
    bcs no
    jsr cover_cell
    bcc no
    ldx cb_j
    lda unit_x,x
    cmp mv_ox
    bne no
    lda unit_y,x
    cmp mv_oy
    bne no
    lda unit_cover,x
    tax
    lda rom_cover_grade,x
    sec
    rts
no:
    clc
    rts
.endproc

; cb_j is the target. cb_x0,cb_y0 is the shooter. A = damage.
; Posture first, then the distance band.
.proc posture_damage
    lda #DMG_OPEN
    sta cb_dmg
    jsr on_assigned_hole
    bcs onchip
    jmp offchip
onchip:
    cmp #3
    bne grade12
    lda #DMG_COVER3
    sta cb_dmg
    jmp band
grade12:
    cmp #1
    beq faced
    cmp #2
    beq faced
    jmp band
faced:
    sta cb_dist
    ldx cb_j
    lda cb_x0
    sec
    sbc unit_x,x
    sta cb_dx
    lda cb_y0
    sec
    sbc unit_y,x
    sta cb_dy
    jsr snap_cardinal
    pha
    ldx cb_j
    lda unit_section,x
    sta mv_who
    lda unit_cover,x
    jsr cover_look
    sta zT6
    pla
    cmp zT6
    bne toband
    cmp #FACE_NONE
    bne have_face
toband:
    jmp band
have_face:
    lda cb_dist
    cmp #2
    bne g1
    lda #DMG_COVER2
    sta cb_dmg
    jmp band
g1:
    lda #DMG_COVER1
    sta cb_dmg
    jmp band
offchip:
    ldx cb_j
    stx think_i
    lda unit_section,x
    sta mv_who
    jsr dest_left
    bcs away
    jmp band
away:
    jsr effective_verb
    cmp #VERB_MOVE
    bne notm
    lda #DMG_SPRINT
    sta cb_dmg
    jmp band
notm:
    cmp #VERB_ATTACK
    beq walk
    cmp #VERB_DEFEND
    beq walk
    cmp #VERB_RETREAT
    beq walk
    jmp band
walk:
    lda #DMG_WALK
    sta cb_dmg
band:
    lda cb_x0
    sta zA0
    lda cb_y0
    sta zA1
    ldx cb_j
    lda unit_x,x
    sta zA2
    lda unit_y,x
    sta zA3
    jsr chebyshev
    cmp #RIFLE_FAR
    bcs zero
    cmp #RIFLE_HALF
    bcc keep
    lda cb_dmg
    lsr
    rts
keep:
    lda cb_dmg
    rts
zero:
    lda #0
    rts
.endproc

; Y = target, A = damage. Zero damage does not tint.
.proc apply_hit_y
    cmp #0
    beq done
    sta zT6
    cmp unit_hp,y
    bcc less
    lda #0
    sta unit_hp,y
    beq tint
less:
    lda unit_hp,y
    sec
    sbc zT6
    sta unit_hp,y
tint:
    lda unit_fx,y
    and #$F0
    ora #FX_HURT
    sta unit_fx,y
done:
    rts
.endproc

; zA0,zA1. Sets that room's heat.
.proc note_contact
    jsr region_at
    cmp #ROOM_MAX
    bcs done
    tax
    lda #HEAT_START
    sta room_heat,x
done:
    rts
.endproc

.proc smear_closest
    lda #NONE
    sta cb_tgt
    lda #$FF
    sta cb_best_d
    jsr other_bank_of_i
    ldx cb_i
    lda unit_x,x
    sta cb_x0
    lda unit_y,x
    sta cb_y0
    lda #0
    sta cb_j
loop:
    lda cb_j
    cmp cb_i
    beq adv
    ldx cb_j
    lda unit_count,x
    beq adv
    lda unit_hp,x
    beq adv
    lda unit_section,x
    cmp cb_bank
    bcc adv
    cmp cb_bank_hi
    bcs adv
    lda unit_x,x
    sec
    sbc cb_x0
    bcs sdx
    lda cb_x0
    sec
    sbc unit_x,x
sdx:
    cmp #RIFLE_FAR
    bcs adv
    lda unit_y,x
    sec
    sbc cb_y0
    bcs sdy
    lda cb_y0
    sec
    sbc unit_y,x
sdy:
    cmp #RIFLE_FAR
    bcs adv
    jsr chebyshev_units
    sta zT6
    cmp #RIFLE_FAR
    bcs adv
    lda cb_tgt
    cmp #NONE
    beq take
    lda zT6
    cmp cb_best_d
    bcs adv
take:
    lda zT6
    sta cb_best_d
    lda cb_j
    sta cb_tgt
adv:
    inc cb_j
    lda cb_j
    cmp #UNIT_MAX
    beq sdone
    jmp loop
sdone:
    rts
.endproc

; cb_x1,cb_y1 is the cell. Carry set and cb_tgt set when a living
; other-bank man stands there inside 9.
.proc find_on_cell
    jsr other_bank_of_i
    lda #0
    sta cb_j
loop:
    lda cb_j
    cmp cb_i
    beq adv
    ldx cb_j
    lda unit_count,x
    beq adv
    lda unit_hp,x
    beq adv
    lda unit_section,x
    cmp cb_bank
    bcc adv
    cmp cb_bank_hi
    bcs adv
    lda unit_x,x
    cmp cb_x1
    bne adv
    lda unit_y,x
    cmp cb_y1
    bne adv
    jsr chebyshev_units
    cmp #RIFLE_FAR
    bcs miss
    lda cb_j
    sta cb_tgt
    sec
    rts
miss:
    lda #NONE
    sta cb_tgt
    clc
    rts
adv:
    inc cb_j
    lda cb_j
    cmp #UNIT_MAX
    bne loop
    lda #NONE
    sta cb_tgt
    clc
    rts
.endproc

; Carry set when a same-bank body, thrower included, stands in the disk.
; Origin is cb_x0,cb_y0. cb_bank is the other bank.
.proc grenade_friendly_in
    ldy #0
loop:
    lda unit_count,y
    beq adv
    lda unit_hp,y
    beq adv
    lda unit_section,y
    cmp cb_bank
    bcc check
    cmp cb_bank_hi
    bcc adv
check:
    lda unit_x,y
    sta cb_x1
    lda unit_y,y
    sta cb_y1
    tya
    pha
    jsr in_blast
    pla
    tay
    bcs yes
adv:
    iny
    cpy #UNIT_MAX
    bne loop
    clc
    rts
yes:
    sec
    rts
.endproc

.proc pick_grenade
    lda #NONE
    sta cb_tgt
    lda #$FF
    sta cb_best_d
    jsr other_bank_of_i
    lda #0
    sta cb_j
loop:
    ldx cb_i
    lda unit_x,x
    sta cb_x0
    lda unit_y,x
    sta cb_y0
    lda cb_j
    cmp cb_i
    bne gself
    jmp adv
gself:
    ldx cb_j
    lda unit_count,x
    bne glive
    jmp adv
glive:
    lda unit_hp,x
    bne ghp
    jmp adv
ghp:
    lda unit_section,x
    cmp cb_bank
    bcc gskip
    cmp cb_bank_hi
    bcc gbank
gskip:
    jmp adv
gbank:
    lda unit_x,x
    sec
    sbc cb_x0
    bcs gdx
    lda cb_x0
    sec
    sbc unit_x,x
gdx:
    cmp #GRENADE_RANGE+1
    bcs adv
    lda unit_y,x
    sec
    sbc cb_y0
    bcs gdy
    lda cb_y0
    sec
    sbc unit_y,x
gdy:
    cmp #GRENADE_RANGE+1
    bcs adv
    jsr chebyshev_units
    sta zT6
    cmp #GRENADE_MIN
    bcc adv
    cmp #GRENADE_RANGE+1
    bcs adv
    lda cb_tgt
    cmp #NONE
    beq gtry
    lda zT6
    cmp cb_best_d
    bcs adv
gtry:
    jsr on_assigned_hole
    bcc adv
    ldx cb_j
    lda unit_x,x
    sta cb_x0
    lda unit_y,x
    sta cb_y0
    jsr grenade_friendly_in
    bcs adv
    lda cb_tgt
    cmp #NONE
    beq take
    lda zT6
    cmp cb_best_d
    bcs adv
take:
    lda zT6
    sta cb_best_d
    lda cb_j
    sta cb_tgt
adv:
    inc cb_j
    lda cb_j
    cmp #UNIT_MAX
    beq gdone
    jmp loop
gdone:
    rts
.endproc

.proc gbank_of_i
    ldx cb_i
    lda unit_section,x
    cmp #LETTER_MAX
    lda #0
    bcc pl
    lda #1
pl:
    sta cb_gbank
    rts
.endproc

; cb_i throws at cb_j. Splash is the other bank only.
.proc apply_grenade_blast
    ldx cb_j
    lda unit_x,x
    sta cb_x0
    lda unit_y,x
    sta cb_y0
    jsr gbank_of_i
    jsr other_bank_of_i
    ldy #0
hit:
    lda unit_count,y
    beq hadv
    lda unit_hp,y
    beq hadv
    lda unit_section,y
    cmp cb_bank
    bcc hadv
    cmp cb_bank_hi
    bcs hadv
    lda unit_x,y
    sta cb_x1
    lda unit_y,y
    sta cb_y1
    tya
    pha
    jsr in_blast
    pla
    tay
    bcc hadv
    lda #GRENADE_DMG
    jsr apply_hit_y
hadv:
    iny
    cpy #UNIT_MAX
    bne hit
    ldx cb_gbank
    lda grenade_rem,x
    beq cooled
    dec grenade_rem,x
cooled:
    cpx #0
    bne ecool
    lda sc_player_grenade_wait
    jmp setc
ecool:
    lda sc_enemy_grenade_wait
setc:
    ldx cb_gbank
    sta grenade_wait,x
    lda cb_x0
    sta nade_fx_x,x
    lda cb_y0
    sta nade_fx_y,x
    lda #GRENADE_FX_TTL
    sta nade_fx_ttl,x
    ldx cb_i
    lda #FIRE_WAIT
    sta unit_fire_wait,x
    lda unit_x,x
    sta zA0
    lda unit_y,x
    sta zA1
    jsr note_contact
    lda cb_x0
    sta zA0
    lda cb_y0
    sta zA1
    jmp note_contact
.endproc

; Carry set when this man threw.
.proc try_grenade
    jsr gbank_of_i
    ldx cb_gbank
    lda grenade_rem,x
    beq no
    lda grenade_wait,x
    bne no
    jsr pick_grenade
    lda cb_tgt
    cmp #NONE
    beq no
    sta cb_j
    jsr apply_grenade_blast
    sec
    rts
no:
    clc
    rts
.endproc

.proc unit_shoot
    ldx cb_i
    lda unit_kind,x
    cmp #KIND_INFANTRY
    beq inf
    rts
inf:
    lda unit_section,x
    sta cb_sec
    jsr weapons_free
    bcs free
    rts
free:
    ldx cb_i
    lda unit_fire_wait,x
    beq ready
    dec unit_fire_wait,x
    beq ready
    rts
ready:
    jsr try_grenade
    bcc rifle
    rts
rifle:
    lda cb_verb
    cmp #VERB_KILL
    bne smear
    ldx cb_i
    lda unit_over_verb,x
    cmp #VERB_KILL
    bne due
    lda unit_over_x,x
    sta cb_x1
    lda unit_over_y,x
    sta cb_y1
    jsr find_on_cell
    bcs have
    jsr smear_closest
    jmp have
due:
    ldx cb_sec
    cpx #SECTION_MAX
    bcs smear
    inc cb_due,x
    lda cb_due,x
    and #3
    beq smear
    lda section_order_x,x
    sta cb_x1
    lda section_order_y,x
    sta cb_y1
    jsr find_on_cell
    bcs have
smear:
    jsr smear_closest
have:
    lda cb_tgt
    cmp #NONE
    bne fire
    rts
fire:
    sta cb_j
    ldx cb_i
    lda unit_x,x
    sta cb_x0
    lda unit_y,x
    sta cb_y0
    jsr posture_damage
    beq nodmg
    ldy cb_j
    jsr apply_hit_y
    lda shot_this_tick
    cmp #$FF
    beq waited
    inc shot_this_tick
waited:
    ldx cb_i
    lda #FIRE_WAIT
    sta unit_fire_wait,x
    lda unit_x,x
    sta zA0
    lda unit_y,x
    sta zA1
    jsr note_contact
    ldx cb_j
    lda unit_x,x
    sta zA0
    lda unit_y,x
    sta zA1
    jmp note_contact
nodmg:
    rts
.endproc

.proc shoot_all
    ldx #0
    lda #0
zdue:
    sta cb_due,x
    inx
    cpx #SECTION_MAX
    bne zdue
    ldx #0
n:
    stx cb_i
    lda unit_count,x
    beq adv
    jsr unit_shoot
adv:
    ldx cb_i
    inx
    cpx #UNIT_MAX
    bne n
    rts
.endproc

; A = section. Marks a letter that lost a man.
.proc dead_mark
    cmp #SECTION_MAX
    bcs done
    cmp #8
    bcs hi
    tax
    lda cb_dead0
    ora cb_bit,x
    sta cb_dead0
    rts
hi:
    sec
    sbc #8
    tax
    lda cb_dead1
    ora cb_bit,x
    sta cb_dead1
done:
    rts
.endproc

; A = section. Carry set when that letter lost a man.
.proc dead_has
    cmp #8
    bcs hi
    tax
    lda cb_bit,x
    and cb_dead0
    beq no
yes:
    sec
    rts
hi:
    sec
    sbc #8
    tax
    lda cb_bit,x
    and cb_dead1
    bne yes
no:
    clc
    rts
.endproc

; X = section. Carry set when a death should re-issue cover.
.proc death_reassign
    cpx #SECTION_MAX
    bcc ok
    clc
    rts
ok:
    lda section_order_verb,x
    cpx #LETTER_MAX
    bcs enemy
    cmp #VERB_ATTACK
    beq yes
    cmp #VERB_DEFEND
    beq yes
    cmp #VERB_RETREAT
    beq yes
    cmp #VERB_HALT
    beq yes
    cmp #VERB_KILL
    beq yes
    clc
    rts
yes:
    sec
    rts
enemy:
    cmp #VERB_DEFEND
    beq yes
    cmp #VERB_RETREAT
    beq yes
    cmp #VERB_ATTACK
    beq en_c
    cmp #VERB_HALT
    bne eno
en_c:
    lda section_flags,x
    and #FLAG_CONTACT
    beq eno
    sec
    rts
eno:
    clc
    rts
.endproc

; Carry set when force/snap/now says the section halts.
.proc force_broken
    lda cb_force
    cmp #10
    bcs no
    lda cb_now
    cmp cb_snap
    bcs no
    lda cb_force
    cmp #4
    bcc yes
    cmp #7
    bcs high
    lda cb_snap
    lsr
    cmp cb_now
    bcc no
yes:
    sec
    rts
high:
    lda cb_now
    cmp #2
    bcs no
    sec
    rts
no:
    clc
    rts
.endproc

; X = section.
.proc section_relead
    stx cb_sec
    cpx #SECTION_MAX
    bcc ok
    rts
ok:
    lda section_lead,x
    cmp #UNIT_MAX
    bcs find
    tay
    lda unit_count,y
    beq find
    lda unit_section,y
    cmp cb_sec
    bne find
    lda unit_x,y
    ldx cb_sec
    sta section_last_x,x
    lda unit_y,y
    sta section_last_y,x
    rts
find:
    ldx cb_sec
    lda section_order_x,x
    sta zA0
    lda section_order_y,x
    sta zA1
    jsr region_at
    sta cb_dest
    lda #NONE
    sta cb_tgt
    ldy #0
loop:
    lda unit_count,y
    beq adv
    lda unit_section,y
    cmp cb_sec
    bne adv
    lda cb_dest
    cmp #NONE
    beq savefb
    cmp unit_region,y
    bne savefb
    ldx cb_sec
    tya
    sta section_lead,x
    lda unit_x,y
    sta section_last_x,x
    lda unit_y,y
    sta section_last_y,x
    rts
savefb:
    lda cb_tgt
    cmp #NONE
    bne adv
    sty cb_tgt
adv:
    iny
    cpy #UNIT_MAX
    bne loop
    lda cb_tgt
    cmp #NONE
    beq none
    tay
    ldx cb_sec
    tya
    sta section_lead,x
    lda unit_x,y
    sta section_last_x,x
    lda unit_y,y
    sta section_last_y,x
    rts
none:
    ldx cb_sec
    lda #NONE
    sta section_lead,x
    rts
.endproc

.proc apply_deaths
    lda #0
    sta cb_dead0
    sta cb_dead1
    ldy #0
scan:
    lda unit_count,y
    beq sadv
    lda unit_hp,y
    bne sadv
    lda unit_section,y
    jsr dead_mark
    lda #0
    sta unit_count,y
    lda #NONE
    sta unit_cover,y
    lda #0
    sta unit_over_verb,y
    sta unit_fx,y
sadv:
    iny
    cpy #UNIT_MAX
    bne scan
    ldy #0
re:
    tya
    jsr dead_has
    bcc radv
    sty cb_sec
    ldx cb_sec
    tya
    pha
    jsr section_relead
    ldx cb_sec
    jsr death_reassign
    pla
    tay
    bcc radv
    ldx cb_sec
    lda section_flags,x
    and #($FF ^ FLAG_RELEASE)
    ora #FLAG_ASSIGN
    sta section_flags,x
radv:
    iny
    cpy #SECTION_MAX
    bne re
    jsr section_recount
    ldy #0
br:
    tya
    jsr dead_has
    bcc badv
    sty cb_sec
    lda spawn_job_rem
    beq chk
    lda spawn_job_letter
    cmp cb_sec
    beq badv
chk:
    ldx cb_sec
    lda section_order_force,x
    sta cb_force
    lda section_order_str,x
    sta cb_snap
    lda section_strength,x
    sta cb_now
    jsr force_broken
    bcc badv
    ldx cb_sec
    lda #VERB_HALT
    sta section_order_verb,x
    lda section_flags,x
    ora #FLAG_BREAKING
    sta section_flags,x
badv:
    iny
    cpy #SECTION_MAX
    bne br
    rts
.endproc

.proc decay_fx
    ldx #0
uloop:
    lda unit_fx,x
    beq uadv
    pha
    and #$0F
    beq lo0
    sec
    sbc #1
lo0:
    sta zT0
    pla
    lsr
    lsr
    lsr
    lsr
    beq hi0
    sec
    sbc #1
hi0:
    asl
    asl
    asl
    asl
    ora zT0
    sta unit_fx,x
uadv:
    inx
    cpx #UNIT_MAX
    bne uloop
    ldx #0
nloop:
    lda nade_fx_ttl,x
    beq nadv
    dec nade_fx_ttl,x
nadv:
    inx
    cpx #2
    bne nloop
    rts
.endproc

.proc decay_grenade_wait
    ldx #0
loop:
    lda grenade_wait,x
    beq adv
    dec grenade_wait,x
adv:
    inx
    cpx #2
    bne loop
    rts
.endproc

; disk_cx, disk_cy. Chebyshev 2 is the whole 5x5.
.proc paint_disk
    lda #$FE
    sta cb_dy
dy:
    lda #$FE
    sta cb_dx
dx:
    lda disk_cx
    clc
    adc cb_dx
    sta zA0
    lda disk_cy
    clc
    adc cb_dy
    sta zA1
    jsr draw_map_cell
    inc cb_dx
    lda cb_dx
    cmp #3
    bne dx
    inc cb_dy
    lda cb_dy
    cmp #3
    bne dy
    rts
.endproc

; Repaint a bank's disk when its ttl or origin changes, including the
; clear on the tick the flash ends. Steady draws do not walk the field.
.proc refresh_nades
    ldx #0
bn:
    stx cb_gbank
    lda nade_fx_x,x
    cmp seen_nade_x,x
    bne changed
    lda nade_fx_y,x
    cmp seen_nade_y,x
    bne changed
    lda nade_fx_ttl,x
    cmp seen_nade_ttl,x
    beq store
changed:
    lda seen_nade_ttl,x
    beq newonly
    lda seen_nade_x,x
    sta disk_cx
    lda seen_nade_y,x
    sta disk_cy
    jsr paint_disk
    ldx cb_gbank
newonly:
    lda nade_fx_ttl,x
    beq store
    lda nade_fx_x,x
    cmp seen_nade_x,x
    bne paintn
    lda nade_fx_y,x
    cmp seen_nade_y,x
    bne paintn
    lda seen_nade_ttl,x
    bne store
paintn:
    lda nade_fx_x,x
    sta disk_cx
    lda nade_fx_y,x
    sta disk_cy
    jsr paint_disk
    ldx cb_gbank
store:
    lda nade_fx_x,x
    sta seen_nade_x,x
    lda nade_fx_y,x
    sta seen_nade_y,x
    lda nade_fx_ttl,x
    sta seen_nade_ttl,x
    inx
    cpx #2
    beq done
    jmp bn
done:
    rts
.endproc
