; Deck pour, in-room bridge via, and the wall-gap slide.
; RAM lives in this segment, not BSS. Mission packs must end before it.
; Dry ground keeps a component id in paper bits 4-7, baked by gen_c64.py
; for the banks beside the deck. Bit 7 on a water cell is a temporary flood
; mark and is cleared before the flood returns. Tile 81 on water stays
; id 0: via_stand still rejects blue paper.

.segment "DECK"

Q_CAP = 160

;-----------------------------------------------------------------------------
; Deck index of zA0,zA1. A = index and C set, or A = NONE and C clear.
; Preserves X. Trashes Y.
.proc deck_at
    ldy #0
at_loop:
    cpy deck_count
    bcs at_miss
    lda deck_x,y
    cmp zA0
    bne at_adv
    lda deck_y,y
    cmp zA1
    bne at_adv
    tya
    sec
    rts
at_adv:
    iny
    jmp at_loop
at_miss:
    lda #NONE
    clc
    rts
.endproc

;-----------------------------------------------------------------------------
; Mark the 8-connected run that contains deck index A. A = NONE marks nothing.
; The stack pop reloads X after DEC: DEC does not change A.
; Trashes A, X, Y, zA0-zA3, zT4.
.proc deck_mark
    sta dk_me
    ldx #DECK_MAX-1
    lda #0
mk_cl:
    sta dk_mark,x
    dex
    bpl mk_cl
mk_seed:
    lda dk_me
    cmp #NONE
    beq mk_done
    cmp deck_count
    bcs mk_done
    tax
    lda #1
    sta dk_mark,x
    stx dk_qlo
    lda #1
    sta dk_qt
mk_pop:
    lda dk_qt
    beq mk_done
    dec dk_qt
    ldx dk_qt
    lda dk_qlo,x
    sta dk_me
    ldy #0
mk_sc:
    cpy deck_count
    bcs mk_pop
    lda dk_mark,y
    bne mk_nx
    ldx dk_me
    lda deck_x,x
    sta zA0
    lda deck_y,x
    sta zA1
    lda deck_x,y
    sta zA2
    lda deck_y,y
    sta zA3
    jsr chebyshev
    cmp #1
    bne mk_nx
    lda #1
    sta dk_mark,y
    lda dk_qt
    cmp #DECK_MAX
    bcs mk_nx
    tax
    tya
    sta dk_qlo,x
    inc dk_qt
mk_nx:
    iny
    jmp mk_sc
mk_done:
    rts
.endproc

;-----------------------------------------------------------------------------
; Unfinished marked neighbour of zA0,zA1. Most progress, then north, then west.
; Standing on the cell is distance 0 and is not picked.
; A = index and C set, or NONE and C clear. Trashes X, Y, zA2, zA3, zT4.
.proc deck_pick
    lda #NONE
    sta dk_best
    ldy #0
pk_loop:
    cpy deck_count
    bcs pk_fin
    lda dk_mark,y
    beq pk_nx
    lda deck_prog,y
    cmp #NONE
    beq pk_nx
    sta dk_pd
    lda deck_x,y
    sta zA2
    lda deck_y,y
    sta zA3
    jsr chebyshev
    cmp #1
    bne pk_nx
    ldx dk_best
    cpx #NONE
    beq pk_take
    lda deck_prog,x
    cmp dk_pd
    beq pk_tie
    bcc pk_take
    jmp pk_nx
pk_tie:
    lda deck_y,y
    cmp deck_y,x
    beq pk_same
    bcs pk_nx
    jmp pk_take
pk_same:
    lda deck_x,y
    cmp deck_x,x
    bcs pk_nx
pk_take:
    sty dk_best
pk_nx:
    iny
    jmp pk_loop
pk_fin:
    lda dk_best
    cmp #NONE
    beq pk_no
    sec
    rts
pk_no:
    clc
    rts
.endproc

;-----------------------------------------------------------------------------
; C set when zA0,zA1 is on or beside a marked deck cell. Trashes X, Y, zA2, zA3, zT4.
.proc deck_touches
    ldy #0
tc_loop:
    cpy deck_count
    bcs tc_no
    lda dk_mark,y
    beq tc_nx
    lda deck_x,y
    sta zA2
    lda deck_y,y
    sta zA3
    jsr chebyshev
    cmp #2
    bcs tc_nx
    sec
    rts
tc_nx:
    iny
    jmp tc_loop
tc_no:
    clc
    rts
.endproc

;-----------------------------------------------------------------------------
; One point from think_i into deck index A. A finished cell takes nothing.
; Cost 0 finishes nothing. Reaching the cost writes tile 81; room-edge
; completions update the pending state for a generated routing patch.
; Trashes A, X, Y, zA0, zA1, zPtr, zPtr2. Preserves think_i.
.proc deck_pour
    cmp deck_count
    bcs pr_done
    tax
    lda deck_cost
    beq pr_done
    lda deck_prog,x
    cmp #NONE
    beq pr_done
    clc
    adc #1
    sta dk_pd
    ldy think_i
    lda deck_x,x
    sta unit_built_x,y
    lda deck_y,x
    sta unit_built_y,y
    lda dk_pd
    cmp deck_cost
    bcs pr_fin
    sta deck_prog,x
    rts
pr_fin:
    lda #NONE
    sta deck_prog,x
    lda deck_x,x
    sta zA0
    lda deck_y,x
    sta zA1
    jsr map_ptr
    lda #TILE_DECK_BUILT
    sta (zPtr),y
    lda $BF00,x
    ora route_pending
    sta route_pending
pr_done:
    rts
.endproc

;-----------------------------------------------------------------------------
; Pour one point for every living builder who stands beside an unfinished plank.
; Does not step. Activates one combined routing variant after all pours.
; Trashes think_i and the stepper scratch. Runs before think_all.
.proc build_pulse
    lda route_state
    sta route_pending
    ldx #0
bp_loop:
    cpx #UNIT_MAX
    bcs bp_done
    stx think_i
    lda unit_count,x
    beq bp_adv
    lda unit_hp,x
    beq bp_adv
    lda unit_kind,x
    cmp #KIND_EMPLACEMENT
    beq bp_adv
    jsr effective_verb
    cmp #VERB_BUILD
    bne bp_adv
    ldx think_i
    ldy unit_section,x
    lda section_order_x,y
    sta zA0
    lda section_order_y,y
    sta zA1
    jsr deck_at
    bcc bp_adv
    jsr deck_mark
    ldx think_i
    lda unit_x,x
    sta zA0
    lda unit_y,x
    sta zA1
    jsr deck_pick
    bcc bp_adv
    jsr deck_pour
bp_adv:
    ldx think_i
    inx
    jmp bp_loop
bp_done:
    lda route_pending
    cmp route_state
    beq bp_return
    jmp activate_routes
bp_return:
    rts
.endproc

;-----------------------------------------------------------------------------
; Nearest open cell in the 8-neighbourhood of dk_anchx,dk_anchy for think_i.
; Smaller Chebyshev, then north, then west. C set: dk_nx,dk_ny. C clear: none.
; Trashes A, X, Y, zA0-zA3, zT4, zT7.
.proc deck_approach
    lda #0
    sta dk_have
    ldx #0
ap_loop:
    cpx #8
    bcc ap_body
    jmp ap_fin
ap_body:
    txa
    pha
    lda dk_anchx
    clc
    adc adx,x
    sta dk_nx
    lda dk_anchy
    clc
    adc ady,x
    sta dk_ny
    lda dk_nx
    sta zA2
    lda dk_ny
    sta zA3
    jsr cell_open
    bcc ap_nxt
    ldx think_i
    lda unit_x,x
    sta zA0
    lda unit_y,x
    sta zA1
    lda dk_nx
    sta zA2
    lda dk_ny
    sta zA3
    jsr chebyshev
    sta dk_pd
    lda dk_have
    beq ap_take
    lda dk_pd
    cmp dk_best
    beq ap_tie
    bcs ap_nxt
    jmp ap_take
ap_tie:
    lda dk_ny
    cmp dk_cury
    beq ap_sx
    bcs ap_nxt
    jmp ap_take
ap_sx:
    lda dk_nx
    cmp dk_curx
    bcs ap_nxt
ap_take:
    lda #1
    sta dk_have
    lda dk_pd
    sta dk_best
    lda dk_nx
    sta dk_curx
    lda dk_ny
    sta dk_cury
ap_nxt:
    pla
    tax
    inx
    jmp ap_loop
ap_fin:
    lda dk_have
    beq ap_no
    lda dk_curx
    sta dk_nx
    lda dk_cury
    sta dk_ny
    sec
    rts
ap_no:
    clc
    rts
.endproc

;-----------------------------------------------------------------------------
; Builder brain for think_i. Pour stays in build_pulse. Step onto the plank
; just finished, or walk to the nearest open cell beside WHERE.
; Sets mv_who before any failed route. Trashes the stepper scratch.
.proc build_think
    ldx think_i
    lda unit_section,x
    sta mv_who
    tay
    lda section_order_x,y
    sta dk_anchx
    sta zA0
    lda section_order_y,y
    sta dk_anchy
    sta zA1
    jsr deck_at
    bcs bt_on
    jmp bt_done
bt_on:
    jsr deck_mark
    ldx think_i
    lda unit_x,x
    sta zA0
    lda unit_y,x
    sta zA1
    jsr deck_pick
    bcc bt_step
    jmp bt_done
bt_step:
    ldx think_i
    lda unit_built_x,x
    cmp #NONE
    beq bt_touch
    cmp unit_x,x
    bne bt_built
    lda unit_built_y,x
    cmp unit_y,x
    beq bt_done
bt_built:
    lda unit_built_x,x
    sta zA0
    lda unit_built_y,x
    sta zA1
    jsr stepper_aim
    jmp stepper_step
bt_touch:
    ldx think_i
    lda unit_x,x
    sta zA0
    lda unit_y,x
    sta zA1
    jsr deck_touches
    bcs bt_done
    jsr deck_approach
    bcc bt_done
    lda dk_nx
    sta mv_ox
    lda dk_ny
    sta mv_oy
    jsr pull_desired
    bcc bt_done
    ldx think_i
    lda unit_x,x
    cmp mv_dx
    bne bt_go
    lda unit_y,x
    cmp mv_dy
    beq bt_done
bt_go:
    lda mv_here
    cmp mv_dest
    beq bt_walk
    lda mv_p
    cmp #NONE
    beq bt_walk
    jsr portal_cross
    bcs bt_done
bt_walk:
    lda mv_dx
    sta zA0
    lda mv_dy
    sta zA1
    jsr stepper_aim
    jmp stepper_step
bt_done:
    rts
.endproc

;-----------------------------------------------------------------------------
; C set when zA2,zA3 is dry open ground. A finished plank on water is not.
; Preserves X. Trashes A, Y, zA0, zA1, zPtr, zPtr2.
.proc via_stand
    lda zA2
    cmp map_w
    bcs vs_no
    lda zA3
    cmp map_h
    bcs vs_no
    lda zA2
    sta zA0
    lda zA3
    sta zA1
    jsr map_ptr
    lda (zPtr2),y
    and #$0F
    cmp #PAPER_WATER
    beq vs_no
    lda (zPtr),y
    cmp #TILE_DECK_BUILT
    beq vs_yes
    cmp #TILE_DECK_OPEN
    beq vs_no
    tay
    lda rom_tile_class,y
    cmp #CLASS_WALLS
    beq vs_no
    cmp #CLASS_BARRIERS
    beq vs_no
vs_yes:
    sec
    rts
vs_no:
    clc
    rts
.endproc

;-----------------------------------------------------------------------------
; Paper byte of zA2,zA3 in A. zPtr2 points at it and Y is 0. Preserves X.
; Copies the cell into zA0,zA1. Out of bounds returns A = 0 and C clear.
.proc paper_ptr
    lda zA2
    cmp map_w
    bcs pp_no
    lda zA3
    cmp map_h
    bcs pp_no
    lda zA2
    sta zA0
    lda zA3
    sta zA1
    jsr map_ptr
    lda (zPtr2),y
    sec
    rts
pp_no:
    lda #0
    clc
    rts
.endproc

;-----------------------------------------------------------------------------
; Component id in A for zA2,zA3. Bits 4-7. Zero when the cell is unstamped,
; water, or out of bounds. Preserves X. Trashes Y, zA0, zA1, zPtr, zPtr2.
.proc comp_id
    jsr paper_ptr
    bcc ci_zero
    lsr
    lsr
    lsr
    lsr
    and #$0F
    rts
ci_zero:
    lda #0
    rts
.endproc

;-----------------------------------------------------------------------------
; Copy the mission cost, zero progress, and stamp tile 80. Bank component
; ids arrive in rom_paper with the map bundle and survive mission restarts.
; Clears every slot's built cell and via.
; Trashes A, X, Y, and the paper pointer.
.proc deck_arm
    lda #0
    sta route_pending
    ldy #UNIT_MAX-1
    lda #NONE
da_cl:
    sta unit_built_x,y
    sta unit_built_y,y
    sta unit_via_x,y
    sta unit_via_y,y
    dey
    bpl da_cl
    lda sc_deck_cost
    sta deck_cost
    ldy #0
da_stamp:
    cpy deck_count
    bcs da_done
    lda #0
    sta deck_prog,y
    sty dk_me
    lda deck_x,y
    sta zA0
    lda deck_y,y
    sta zA1
    jsr map_ptr
    lda #TILE_DECK_OPEN
    sta (zPtr),y
    ldy dk_me
    iny
    jmp da_stamp
da_done:
    rts
.endproc

;-----------------------------------------------------------------------------
; Clear overrides, the built cell, and the via latch for units in section zA0.
; Trashes A, Y. Preserves X and zA0.
.proc deck_clear_who
    ldy #0
cw_loop:
    lda unit_section,y
    cmp zA0
    bne cw_nx
    lda #0
    sta unit_over_verb,y
    lda #NONE
    sta unit_built_x,y
    sta unit_built_y,y
    sta unit_via_x,y
    sta unit_via_y,y
cw_nx:
    iny
    cpy #UNIT_MAX
    bne cw_loop
    rts
.endproc

;-----------------------------------------------------------------------------
; Clear slot Y's built cell and via latch. Preserves X and Y.
.proc deck_clear_slot
    lda #NONE
    sta unit_built_x,y
    sta unit_built_y,y
    sta unit_via_x,y
    sta unit_via_y,y
    rts
.endproc

;-----------------------------------------------------------------------------
; C set when WHERE (zT4,zT5) is a deck cell, or the verb is not BUILD.
; C clear: BUILD aimed at something else. Trashes A, Y, zA0, zA1.
.proc build_where_ok
    lda cmd_verb
    cmp #VERB_BUILD
    beq bw_deck
    sec
    rts
bw_deck:
    lda zT4
    sta zA0
    lda zT5
    sta zA1
    jmp deck_at
.endproc

;-----------------------------------------------------------------------------
; Add the deck tail at GEO_IMAGE+zT0 to the geometry length. Count above 16
; does not return. Stores deck_count. Trashes A, Y, zPtr, zA0.
.proc deck_geo_size
    clc
    lda #<GEO_IMAGE
    adc zT0
    sta zPtr
    lda #>GEO_IMAGE
    adc zT1
    sta zPtr+1
    ldy #0
    lda (zPtr),y
    cmp #DECK_MAX+1
    bcc gs_ok
    jmp fail7
gs_ok:
    sta deck_count
    asl
    clc
    adc #1
    adc zT0
    sta zT0
    lda zT1
    adc #0
    sta zT1
    rts
.endproc

;-----------------------------------------------------------------------------
; zPtr is the deck-count byte after the scout columns. Zero both axes, then
; copy count bytes of x and count bytes of y. A later shorter map drops stale
; cells. Trashes A, Y, zPtr, dk_pd.
.proc deck_geo_copy
    ldy #DECK_MAX-1
    lda #0
gc_cl:
    sta deck_x,y
    sta deck_y,y
    dey
    bpl gc_cl
    ldy #0
    lda (zPtr),y
    sta dk_pd
    inc zPtr
    bne gc_x
    inc zPtr+1
gc_x:
    ldy #0
gc_xl:
    cpy dk_pd
    bcs gc_y0
    lda (zPtr),y
    sta deck_x,y
    iny
    jmp gc_xl
gc_y0:
    clc
    lda zPtr
    adc dk_pd
    sta zPtr
    bcc gc_y
    inc zPtr+1
gc_y:
    ldy #0
gc_yl:
    cpy dk_pd
    bcs gc_done
    lda (zPtr),y
    sta deck_y,y
    iny
    jmp gc_yl
gc_done:
    rts
.endproc

;-----------------------------------------------------------------------------
; C set when a dry orthogonal neighbour of dk_px,dk_py shares the anchor's
; component and sits strictly closer to dk_anchx,dk_anchy than the plank does.
; Id 0 never matches. Trashes A, X, Y, zA0-zA3, zT1, zPtr, zPtr2.
.proc via_touches
    lda dk_anchx
    sta zA2
    lda dk_anchy
    sta zA3
    jsr comp_id
    sta dk_id
    beq vt_no
    lda dk_px
    sta zA0
    lda dk_py
    sta zA1
    lda dk_anchx
    sta zA2
    lda dk_anchy
    sta zA3
    jsr manhattan
    sta dk_pd
    ldx #0
vt_dir:
    cpx #4
    bcs vt_no
    lda dk_px
    clc
    adc pdx,x
    sta zA2
    lda dk_py
    clc
    adc pdy,x
    sta zA3
    stx dk_dir
    jsr via_stand
    bcc vt_nx
    jsr comp_id
    cmp dk_id
    bne vt_nx
    lda zA2
    sta zA0
    lda zA3
    sta zA1
    lda dk_anchx
    sta zA2
    lda dk_anchy
    sta zA3
    jsr manhattan
    cmp dk_pd
    bcc vt_yes
vt_nx:
    ldx dk_dir
    inx
    jmp vt_dir
vt_yes:
    sec
    rts
vt_no:
    clc
    rts
.endproc

;-----------------------------------------------------------------------------
; Finished marked planks whose dry side faces the anchor. dk_side 0 writes
; dk_near, 1 writes dk_far. Anchor is dk_anchx,dk_anchy. Trashes the toucher.
.proc via_sides
    ldy #0
sd_loop:
    cpy deck_count
    bcs sd_done
    lda #0
    ldx dk_side
    bne sd_far
    sta dk_near,y
    jmp sd_chk
sd_far:
    sta dk_far,y
sd_chk:
    lda dk_mark,y
    beq sd_nx
    lda deck_prog,y
    cmp #NONE
    bne sd_nx
    lda deck_x,y
    sta dk_px
    lda deck_y,y
    sta dk_py
    sty dk_me
    jsr via_touches
    ldy dk_me
    bcc sd_nx
    lda #1
    ldx dk_side
    bne sd_setf
    sta dk_near,y
    jmp sd_nx
sd_setf:
    sta dk_far,y
sd_nx:
    iny
    jmp sd_loop
sd_done:
    rts
.endproc

;-----------------------------------------------------------------------------
; C set when deck index Y is a better aim than dk_best toward the anchor.
; Smaller Chebyshev, then north, then west. Preserves Y. Trashes A, X, zA0-zA3, zT4.
.proc via_prefer
    lda deck_x,y
    sta zA0
    lda deck_y,y
    sta zA1
    lda dk_anchx
    sta zA2
    lda dk_anchy
    sta zA3
    jsr chebyshev
    sta dk_pd
    ldx dk_best
    lda deck_x,x
    sta zA0
    lda deck_y,x
    sta zA1
    lda dk_anchx
    sta zA2
    lda dk_anchy
    sta zA3
    jsr chebyshev
    cmp dk_pd
    beq vp_tie
    bcc vp_no
    sec
    rts
vp_tie:
    ldx dk_best
    lda deck_y,y
    cmp deck_y,x
    beq vp_x
    bcc vp_yes
    clc
    rts
vp_x:
    lda deck_x,y
    cmp deck_x,x
    bcc vp_yes
    clc
    rts
vp_yes:
    sec
    rts
vp_no:
    clc
    rts
.endproc

;-----------------------------------------------------------------------------
; Best finished plank in dk_mark and dk_use, toward dk_anchx,dk_anchy.
; A = index and C set, or NONE and C clear. Trashes X, Y, zA0-zA3, zT4.
.proc via_best
    lda #NONE
    sta dk_best
    ldy #0
vb_loop:
    cpy deck_count
    bcs vb_fin
    lda dk_mark,y
    beq vb_nx
    lda dk_use,y
    beq vb_nx
    lda deck_prog,y
    cmp #NONE
    bne vb_nx
    lda dk_best
    cmp #NONE
    beq vb_take
    jsr via_prefer
    bcc vb_nx
vb_take:
    sty dk_best
vb_nx:
    iny
    jmp vb_loop
vb_fin:
    lda dk_best
    cmp #NONE
    beq vb_no
    sec
    rts
vb_no:
    clc
    rts
.endproc

;-----------------------------------------------------------------------------
; Spread dk_reach through finished marked planks at Chebyshev 1.
; Seeds are the cells already set. Trashes A, X, Y, zA0-zA3, zT4, and the queue.
.proc via_spread
    lda #0
    sta dk_qt
    ldy #0
sp_seed:
    cpy deck_count
    bcs sp_go
    lda dk_reach,y
    beq sp_sn
    ldx dk_qt
    tya
    sta dk_qlo,x
    inc dk_qt
sp_sn:
    iny
    jmp sp_seed
sp_go:
    lda #0
    sta dk_qh
sp_pop:
    lda dk_qh
    cmp dk_qt
    bcs sp_done
    tax
    lda dk_qlo,x
    sta dk_me
    inc dk_qh
    ldy #0
sp_sc:
    cpy deck_count
    bcs sp_pop
    lda dk_reach,y
    bne sp_nx
    lda dk_mark,y
    beq sp_nx
    lda deck_prog,y
    cmp #NONE
    bne sp_nx
    ldx dk_me
    lda deck_x,x
    sta zA0
    lda deck_y,x
    sta zA1
    lda deck_x,y
    sta zA2
    lda deck_y,y
    sta zA3
    jsr chebyshev
    cmp #1
    bne sp_nx
    lda #1
    sta dk_reach,y
    lda dk_qt
    cmp #DECK_MAX
    bcs sp_nx
    tax
    tya
    sta dk_qlo,x
    inc dk_qt
sp_nx:
    iny
    jmp sp_sc
sp_done:
    rts
.endproc

;-----------------------------------------------------------------------------
; C set when zA2,zA3 is a deck cell or blue paper. A wall on the bank is not.
; Preserves X. Trashes A, Y, zA0, zA1, zPtr, zPtr2.
.proc via_river
    lda zA2
    cmp map_w
    bcs vr_no
    lda zA3
    cmp map_h
    bcs vr_no
    lda zA2
    sta zA0
    lda zA3
    sta zA1
    jsr deck_at
    bcs vr_yes
    lda zA2
    sta zA0
    lda zA3
    sta zA1
    jsr map_ptr
    lda (zPtr2),y
    and #$0F
    cmp #PAPER_WATER
    beq vr_yes
vr_no:
    clc
    rts
vr_yes:
    sec
    rts
.endproc

;-----------------------------------------------------------------------------
; First river or deck cell on the open line from think_i to dk_anchx,dk_anchy.
; Endpoints are not hits. n <= 1 misses. C set: dk_hx,dk_hy. Trashes A, X, Y.
.proc via_first_block
    ldx think_i
    lda unit_x,x
    sta dk_bx
    lda unit_y,x
    sta dk_by
    lda dk_anchx
    sec
    sbc dk_bx
    beq fb_zx
    bcc fb_nx
    sta dk_bax
    lda #1
    sta dk_bsx
    jmp fb_yy
fb_nx:
    lda dk_bx
    sec
    sbc dk_anchx
    sta dk_bax
    lda #SX_NEG
    sta dk_bsx
    jmp fb_yy
fb_zx:
    lda #0
    sta dk_bax
    sta dk_bsx
fb_yy:
    lda dk_anchy
    sec
    sbc dk_by
    beq fb_zy
    bcc fb_ny
    sta dk_bay
    lda #1
    sta dk_bsy
    jmp fb_maj
fb_ny:
    lda dk_by
    sec
    sbc dk_anchy
    sta dk_bay
    lda #SX_NEG
    sta dk_bsy
    jmp fb_maj
fb_zy:
    lda #0
    sta dk_bay
    sta dk_bsy
fb_maj:
    lda dk_bax
    cmp dk_bay
    bcc fb_ymaj
    sta dk_bn
    cmp #2
    bcs fb_xgo
    jmp fb_no
fb_xgo:
    lsr
    sta dk_berr
    dec dk_bn
fb_x:
    lda dk_bx
    clc
    adc dk_bsx
    sta dk_bx
    lda dk_berr
    clc
    adc dk_bay
    sta dk_berr
    cmp dk_bax
    bcc fb_xchk
    sec
    sbc dk_bax
    sta dk_berr
    lda dk_by
    clc
    adc dk_bsy
    sta dk_by
fb_xchk:
    lda dk_bx
    sta zA2
    lda dk_by
    sta zA3
    jsr via_river
    bcs fb_hit
    dec dk_bn
    bne fb_x
    jmp fb_no
fb_ymaj:
    lda dk_bay
    sta dk_bn
    cmp #2
    bcc fb_no
    lsr
    sta dk_berr
    dec dk_bn
fb_y:
    lda dk_by
    clc
    adc dk_bsy
    sta dk_by
    lda dk_berr
    clc
    adc dk_bax
    sta dk_berr
    cmp dk_bay
    bcc fb_ychk
    sec
    sbc dk_bay
    sta dk_berr
    lda dk_bx
    clc
    adc dk_bsx
    sta dk_bx
fb_ychk:
    lda dk_bx
    sta zA2
    lda dk_by
    sta zA3
    jsr via_river
    bcs fb_hit
    dec dk_bn
    bne fb_y
fb_no:
    clc
    rts
fb_hit:
    lda dk_bx
    sta dk_hx
    lda dk_by
    sta dk_hy
    sec
    rts
.endproc

;-----------------------------------------------------------------------------
; Enqueue zA2,zA3 on the linear water list and set paper bit 7.
; C clear when stored. C set when the list is full: the bit stays clear.
; Trashes A, X, Y, zA0, zA1, zPtr, zPtr2.
.proc water_put
    lda dk_qt
    cmp #Q_CAP
    bcs wp_full
    tax
    lda zA2
    sta dk_qlo,x
    lda zA3
    sta dk_qhi,x
    inc dk_qt
    jsr paper_ptr
    bcc wp_full
    ora #$80
    sta (zPtr2),y
    clc
    rts
wp_full:
    sec
    rts
.endproc

;-----------------------------------------------------------------------------
; Clear paper bit 7 on every cell in the water list. Trashes A, X, Y, zp.
.proc water_clear
    ldx #0
wc_loop:
    cpx dk_qt
    bcs wc_done
    lda dk_qlo,x
    sta zA2
    lda dk_qhi,x
    sta zA3
    txa
    pha
    jsr paper_ptr
    bcc wc_nx
    and #$7F
    sta (zPtr2),y
wc_nx:
    pla
    tax
    inx
    jmp wc_loop
wc_done:
    rts
.endproc

;-----------------------------------------------------------------------------
; Deck index the hit belongs to, in this room. A deck cell returns at once.
; Water walks 4-connected water until an in-room deck. Another room's plank
; is crossed, not returned. C set and A = index, or C clear and A = NONE.
; Clears every temporary bit 7 before returning. Trashes the queue and zp.
.proc via_from_hit
    lda dk_hx
    sta zA0
    lda dk_hy
    sta zA1
    jsr deck_at
    bcc fh_water
    sta dk_origin
    lda dk_hx
    sta zA0
    lda dk_hy
    sta zA1
    jsr region_at
    cmp mv_here
    beq fh_mine
    jmp fh_no
fh_mine:
    lda dk_origin
    sec
    rts
fh_water:
    lda dk_hx
    sta zA2
    lda dk_hy
    sta zA3
    jsr paper_ptr
    and #$0F
    cmp #PAPER_WATER
    beq fh_wet
    jmp fh_no
fh_wet:
    lda #0
    sta dk_qt
    sta dk_qh
    jsr water_put
    bcc fh_pop
    jmp fh_clear
fh_pop:
    lda dk_qh
    cmp dk_qt
    bcc fh_cell
    jmp fh_clear
fh_cell:
    tax
    lda dk_qlo,x
    sta dk_curx
    lda dk_qhi,x
    sta dk_cury
    inc dk_qh
    ldx #0
fh_dir:
    cpx #4
    bcs fh_pop
    lda dk_curx
    clc
    adc pdx,x
    sta zA2
    lda dk_cury
    clc
    adc pdy,x
    sta zA3
    stx dk_dir
    lda zA2
    cmp map_w
    bcs fh_nx
    lda zA3
    cmp map_h
    bcs fh_nx
    jsr paper_ptr
    and #$0F
    cmp #PAPER_WATER
    bne fh_nx
    lda (zPtr2),y
    and #$80
    bne fh_nx
    lda zA2
    sta zA0
    lda zA3
    sta zA1
    jsr deck_at
    bcc fh_put
    sta dk_origin
    lda zA2
    pha
    lda zA3
    pha
    jsr region_at
    cmp mv_here
    bne fh_walk
    pla
    pla
    jsr water_clear
    lda dk_origin
    sec
    rts
fh_walk:
    pla
    sta zA3
    pla
    sta zA2
fh_put:
    jsr water_put
fh_nx:
    ldx dk_dir
    inx
    jmp fh_dir
fh_clear:
    jsr water_clear
fh_no:
    lda #NONE
    clc
    rts
.endproc

;-----------------------------------------------------------------------------
; dk_use[i] = dk_far[i] AND dk_reach[i], or near when dk_side is 0.
; Trashes A, Y.
.proc via_and
    ldy #0
va_loop:
    cpy deck_count
    bcs va_done
    ldx dk_side
    bne va_far
    lda dk_near,y
    jmp va_both
va_far:
    lda dk_far,y
va_both:
    beq va_z
    lda dk_reach,y
    beq va_z
    lda #1
    sta dk_use,y
    jmp va_nx
va_z:
    lda #0
    sta dk_use,y
va_nx:
    iny
    jmp va_loop
va_done:
    rts
.endproc

;-----------------------------------------------------------------------------
; Aim mv_dx,mv_dy at the near finished plank, then the far one.
; Already latched to mv_ox,mv_oy leaves the straight aim. A closed bridge
; does too. Reaching the chosen far plank stores the order cell.
; Trashes A, X, Y, the queue, and zp. Does not touch zSrc or zDst.
.proc via_steer
    ldx think_i
    lda unit_via_x,x
    cmp mv_ox
    bne vs_go
    lda unit_via_y,x
    cmp mv_oy
    bne vs_go
    jmp vs_done
vs_go:
    lda unit_x,x
    sta zA0
    lda unit_y,x
    sta zA1
    jsr deck_at
    bcc vs_off
    sta dk_me
    tax
    lda deck_prog,x
    cmp #NONE
    bne vs_off
    lda deck_x,x
    sta zA0
    lda deck_y,x
    sta zA1
    jsr region_at
    cmp mv_here
    bne vs_off
    lda dk_me
    jsr deck_mark
    lda mv_ox
    sta dk_anchx
    lda mv_oy
    sta dk_anchy
    lda #1
    sta dk_side
    jsr via_sides
    ldy #DECK_MAX-1
    lda #0
vs_zr:
    sta dk_reach,y
    dey
    bpl vs_zr
    ldx dk_me
    lda #1
    sta dk_reach,x
    jsr via_spread
    lda #1
    sta dk_side
    jsr via_and
    jsr via_best
    bcs vs_pick
    jmp vs_done
vs_pick:
    cmp dk_me
    beq vs_latch
    jmp vs_aim
vs_latch:
    ldx think_i
    lda mv_ox
    sta unit_via_x,x
    lda mv_oy
    sta unit_via_y,x
    rts
vs_off:
    lda mv_ox
    sta dk_anchx
    lda mv_oy
    sta dk_anchy
    jsr via_first_block
    bcc vs_done
    jsr via_from_hit
    bcc vs_done
    jsr deck_mark
    ldx think_i
    lda unit_x,x
    sta dk_anchx
    lda unit_y,x
    sta dk_anchy
    lda #0
    sta dk_side
    jsr via_sides
    lda mv_ox
    sta dk_anchx
    lda mv_oy
    sta dk_anchy
    lda #1
    sta dk_side
    jsr via_sides
    ldy #0
vs_rf:
    cpy deck_count
    bcs vs_sp
    lda dk_far,y
    sta dk_reach,y
    iny
    jmp vs_rf
vs_sp:
    jsr via_spread
    lda #0
    sta dk_side
    jsr via_and
    ldx think_i
    lda unit_x,x
    sta dk_anchx
    lda unit_y,x
    sta dk_anchy
    jsr via_best
    bcc vs_done
vs_aim:
    tax
    lda deck_x,x
    sta mv_dx
    lda deck_y,x
    sta mv_dy
vs_done:
    rts
.endproc

;-----------------------------------------------------------------------------
; C set when the preferred cardinal from zA2,zA3 is open. Restores zA2,zA3.
; mv_pref 1 uses unit_step_sx. pla does not change carry. Trashes A, X, Y, zT7.
.proc pref_open
    lda zA2
    pha
    lda zA3
    pha
    ldx think_i
    lda mv_pref
    beq po_y
    lda zA2
    clc
    adc unit_step_sx,x
    sta zA2
    jmp po_ask
po_y:
    lda zA3
    clc
    adc unit_step_sy,x
    sta zA3
po_ask:
    jsr cell_open
    pla
    sta zA3
    pla
    sta zA2
    rts
.endproc

;-----------------------------------------------------------------------------
; C set when zA2,zA3 is in-room, not a portal, and not terrain.
; NONE on either room is allowed. Trashes A, X, Y, zp temps.
.proc slide_stand
    jsr cell_open
    bcc ss_no
    lda zA2
    sta zA0
    lda zA3
    sta zA1
    jsr is_portal
    bcs ss_no
    lda zA2
    sta zA0
    lda zA3
    sta zA1
    jsr region_at
    sta dk_px
    ldx think_i
    lda unit_region,x
    cmp #NONE
    beq ss_yes
    lda dk_px
    cmp #NONE
    beq ss_yes
    cmp unit_region,x
    bne ss_no
ss_yes:
    sec
    rts
ss_no:
    clc
    rts
.endproc

;-----------------------------------------------------------------------------
; Steps of dk_sdx,dk_sdy until the preferred cardinal is open.
; A = k, or 0 when the lane ends or the gap is past SLIDE_CAP.
; Trashes A, X, Y, and zp temps. Leaves the unit where it stands.
.proc slide_dist
    ldx think_i
    lda unit_x,x
    sta dk_curx
    lda unit_y,x
    sta dk_cury
    lda #1
    sta dk_k
sd_loop:
    lda dk_k
    cmp #SLIDE_CAP+1
    bcs sd_zero
    lda dk_curx
    clc
    adc dk_sdx
    sta dk_curx
    sta zA2
    lda dk_cury
    clc
    adc dk_sdy
    sta dk_cury
    sta zA3
    jsr slide_stand
    bcc sd_zero
    lda dk_curx
    sta zA2
    lda dk_cury
    sta zA3
    jsr pref_open
    bcs sd_found
    inc dk_k
    jmp sd_loop
sd_found:
    lda dk_k
    rts
sd_zero:
    lda #0
    rts
.endproc

;-----------------------------------------------------------------------------
; Try the one-cell dodge dk_sdx,dk_sdy with the sidestep rules. C from try_step.
.proc slide_one
    ldx think_i
    lda unit_x,x
    clc
    adc dk_sdx
    sta zA2
    lda unit_y,x
    clc
    adc dk_sdy
    sta zA3
    lda #1
    sta mv_dodge
    jmp try_step
.endproc

;-----------------------------------------------------------------------------
; 1 landed, 0 both gaps busy, $FF no gap inside the cap.
; Right is the SDL hand: east's right is +y, south's right is -x.
; Tie or only-right goes right. Trashes A, X, Y, and zp temps.
.proc try_around
    ldx think_i
    lda #0
    sta dk_rx
    sta dk_ry
    sta dk_lx
    sta dk_ly
    lda mv_pref
    beq ta_y
    lda unit_step_sx,x
    bne ta_xhas
    jmp ta_none
ta_xhas:
    cmp #1
    bne ta_xneg
    lda #1
    sta dk_ry
    lda #SX_NEG
    sta dk_ly
    jmp ta_dist
ta_xneg:
    lda #SX_NEG
    sta dk_ry
    lda #1
    sta dk_ly
    jmp ta_dist
ta_y:
    lda unit_step_sy,x
    bne ta_yhas
    jmp ta_none
ta_yhas:
    cmp #1
    bne ta_yneg
    lda #SX_NEG
    sta dk_rx
    lda #1
    sta dk_lx
    jmp ta_dist
ta_yneg:
    lda #1
    sta dk_rx
    lda #SX_NEG
    sta dk_lx
ta_dist:
    lda dk_rx
    sta dk_sdx
    lda dk_ry
    sta dk_sdy
    jsr slide_dist
    sta dk_rd
    lda dk_lx
    sta dk_sdx
    lda dk_ly
    sta dk_sdy
    jsr slide_dist
    sta dk_ld
    lda dk_rd
    ora dk_ld
    beq ta_none
    lda dk_rd
    beq ta_left
    lda dk_ld
    beq ta_right
    cmp dk_rd
    bcs ta_right
ta_left:
    lda dk_lx
    sta dk_sdx
    lda dk_ly
    sta dk_sdy
    lda #0
    sta dk_side
    jmp ta_step
ta_right:
    lda dk_rx
    sta dk_sdx
    lda dk_ry
    sta dk_sdy
    lda #1
    sta dk_side
ta_step:
    jsr slide_one
    bcs ta_land
    lda dk_side
    beq ta_other_r
    lda dk_ld
    beq ta_busy
    lda dk_lx
    sta dk_sdx
    lda dk_ly
    sta dk_sdy
    jmp ta_step2
ta_other_r:
    lda dk_rd
    beq ta_busy
    lda dk_rx
    sta dk_sdx
    lda dk_ry
    sta dk_sdy
ta_step2:
    jsr slide_one
    bcs ta_land
ta_busy:
    lda #0
    rts
ta_land:
    lda #1
    rts
ta_none:
    lda #$FF
    rts
.endproc

;-----------------------------------------------------------------------------
; Preferred cardinal is terrain: take the other axis only when that step
; opens it, else the nearer gap. C set means the old dodge must not run
; (landed, or both gaps are busy). C clear means not a wall, or no gap
; inside the cap. Trashes A, X, Y, and zp temps.
.proc slide_gate
    jsr pref_blocked
    bcc sg_open
    lda mv_pref
    beq sg_ox
    ldx think_i
    lda unit_step_sy,x
    beq sg_around
    clc
    adc unit_y,x
    sta zA3
    lda unit_x,x
    sta zA2
    jsr pref_open
    bcc sg_around
    lda #0
    sta mv_dodge
    jsr try_step
    bcc sg_around
    sec
    rts
sg_ox:
    ldx think_i
    lda unit_step_sx,x
    beq sg_around
    clc
    adc unit_x,x
    sta zA2
    lda unit_y,x
    sta zA3
    jsr pref_open
    bcc sg_around
    lda #0
    sta mv_dodge
    jsr try_step
    bcc sg_around
    sec
    rts
sg_around:
    jsr try_around
    cmp #$FF
    beq sg_open
    sec
    rts
sg_open:
    clc
    rts
.endproc

;-----------------------------------------------------------------------------
; C set when think_i's preferred neighbour is terrain or out of bounds.
; A zero sign on that axis is not a wall. Trashes A, X, Y, zT7, zPtr, zPtr2.
.proc pref_blocked
    ldx think_i
    lda mv_pref
    beq pb_y
    lda unit_step_sx,x
    beq pb_open
    clc
    adc unit_x,x
    sta zA2
    lda unit_y,x
    sta zA3
    jmp pb_ask
pb_y:
    lda unit_step_sy,x
    beq pb_open
    clc
    adc unit_y,x
    sta zA3
    lda unit_x,x
    sta zA2
pb_ask:
    jsr cell_open
    bcs pb_open
    sec
    rts
pb_open:
    clc
    rts
.endproc

; North, east, south, west. Approach is the 8-neighbourhood, north-west first.
pdx: .byte 0, 1, 0, $FF
pdy: .byte $FF, 0, 1, 0
adx: .byte $FF, 0, 1, $FF, 1, $FF, 0, 1
ady: .byte $FF, $FF, $FF, 0, 0, 1, 1, 1

deck_count:     .res 1
deck_x:         .res DECK_MAX
deck_y:         .res DECK_MAX
deck_prog:      .res DECK_MAX
deck_cost:      .res 1
unit_built_x:   .res UNIT_MAX
unit_built_y:   .res UNIT_MAX
unit_via_x:     .res UNIT_MAX
unit_via_y:     .res UNIT_MAX
dk_mark:        .res DECK_MAX
dk_near:        .res DECK_MAX
dk_far:         .res DECK_MAX
dk_reach:       .res DECK_MAX
dk_use:         .res DECK_MAX
dk_qlo:         .res Q_CAP
dk_qhi:         .res Q_CAP
dk_qh:          .res 1
dk_qt:          .res 1
dk_id:          .res 1
dk_curx:        .res 1
dk_cury:        .res 1
dk_nx:          .res 1
dk_ny:          .res 1
dk_px:          .res 1
dk_py:          .res 1
dk_pd:          .res 1
dk_anchx:       .res 1
dk_anchy:       .res 1
dk_dir:         .res 1
dk_best:        .res 1
dk_me:          .res 1
dk_origin:      .res 1
dk_side:        .res 1
dk_have:        .res 1
dk_k:           .res 1
dk_hx:          .res 1
dk_hy:          .res 1
dk_bx:          .res 1
dk_by:          .res 1
dk_bsx:         .res 1
dk_bsy:         .res 1
dk_bax:         .res 1
dk_bay:         .res 1
dk_berr:        .res 1
dk_bn:          .res 1
dk_sdx:         .res 1
dk_sdy:         .res 1
dk_rx:          .res 1
dk_ry:          .res 1
dk_lx:          .res 1
dk_ly:          .res 1
dk_rd:          .res 1
dk_ld:          .res 1

; Initial routing comes from chunk 5; the reversible variant program in
; chunk 6 survives at $BF00. No room graph is calculated by the game.
route_ready: .byte 0
route_state: .byte 0

; Validate the raw 818-byte initial-routing chunk. Its source must lie
; below the expanded geometry so geo_expand cannot overwrite it.
.proc allow_routes
    ldy #1
    lda (zPtr),y
    bne bad
    ldy #6
    lda (zPtr),y
    bne bad
    iny
    lda (zPtr),y
    cmp #$1C
    bne bad
    iny
    lda (zPtr),y
    cmp #<818
    bne bad
    iny
    lda (zPtr),y
    cmp #>818
    bne bad
    lda zA2
    cmp #<818
    bne bad
    lda zA3
    cmp #>818
    bne bad
    lda end_hi
    cmp #$B9
    bcc good
    bne bad
    lda end_lo
    beq good
bad:
    jmp fail5
good:
    rts
.endproc

; Geometry scratch is dead now. Park routing there before planes expand.
.proc stage_routes
    lda found
    and #$10
    beq done
    ldx #4
    jsr load_slot_src
    lda #0
    sta zDst
    lda #$1C
    sta zDst+1
    jsr memmove
    lda #1
    sta route_ready
done:
    rts
.endproc

; Scatter the staged initial tables after clear_bss. The routing program
; at $BF00 stays separate from BSS and active mission data.
.proc install_routes
    lda route_ready
    beq done
    lda #0
    sta zSrc
    lda #$1C
    sta zSrc+1
    lda #<portal_from
    sta zDst
    lda #>portal_from
    sta zDst+1
    lda #<304
    sta zT0
    lda #>304
    sta zT1
    jsr memmove
    lda #$30
    sta zSrc
    lda #$1D
    sta zSrc+1
    lda #<door_n
    sta zDst
    lda #>door_n
    sta zDst+1
    lda #<514
    sta zT0
    lda #>514
    sta zT1
    jsr memmove
done:
    rts
.endproc

; Activate the initial routing state on restart, undoing any bridge patch.
.proc initial_routes
    jsr portal_bake
    lda #0
    jmp activate_routes
.endproc

; Expand geometry and stage both routing chunks before plane placement.
; FMAP v2 bounds the source below geometry RAM to preserve unread chunks.
.proc prepare_routes
    lda found
    and #$10
    beq done
    jsr geo_expand
    jsr stage_routes
    jmp stage_program
done:
    rts
.endproc

; Geometry has already been expanded by prepare_routes.
.proc finish_geometry
    lda route_ready
    bne done
    jmp geo_expand
done:
    rts
.endproc

route_pending: .byte 0


; Chunk 6 is a fixed 256-byte routing program at $BF00, below occupancy.
; The bundle must include the initial tables and end below geometry RAM.
.proc allow_program
    ldy #1
    lda (zPtr),y
    bne bad
    lda zA2
    bne bad
    lda zA3
    cmp #1
    bne bad
    ldy #6
    lda (zPtr),y
    bne bad
    iny
    lda (zPtr),y
    cmp #$BF
    bne bad
    iny
    lda (zPtr),y
    bne bad
    iny
    lda (zPtr),y
    cmp #1
    bne bad
    lda end_hi
    cmp #$B9
    bcc done
    bne bad
    lda end_lo
    beq done
bad:
    jmp fail5
done:
    rts
.endproc

; Stage the routing program before plane placement. It survives campaign
; scratch reuse, occupancy rebuilds, and active-mission initialization.
.proc stage_program
    lda found
    and #$20
    beq done
    ldx #5
    jsr load_slot_src
    lda #0
    sta zDst
    lda #$BF
    sta zDst+1
    jsr memmove
    lda #2
    sta route_ready
done:
    rts
.endproc

; A is the new compact bridge state. Undo the old state's shared patches
; to the initial values, then apply the new state's generated replacements.
.proc activate_routes
    sta dk_best
    lda #1
    sta dk_pd
    lda route_state
    jsr patch_variant
    lda #0
    sta dk_pd
    lda dk_best
    sta route_state
    jmp patch_variant
.endproc

; A selects a state's group list. dk_pd=1 restores old bytes; 0 applies new.
; Groups are page,count,(index,initial,value)*count. Trashes queue scratch
; and zp; called after all builders have poured, before soldier movement.
.segment "CODE"
.proc patch_variant
    tax
    lda $BF10,x
    sta zPtr
    lda #$BF
    sta zPtr+1
    ldy #0
    lda (zPtr),y
    sta dk_qt
    beq done
    iny
    sty dk_me
group:
    ldy dk_me
    lda (zPtr),y
    tax
    lda $BF00,x
    sta zDst+1
    lda #0
    sta zDst
    inx
    lda $BF00,x
    sta dk_dir
    inx
entry:
    lda $BF00,x
    tay
    inx
    lda $BF00,x
    sta zT0
    inx
    lda dk_pd
    bne restore
    lda $BF00,x
    jmp store
restore:
    lda zT0
store:
    sta (zDst),y
    inx
    dec dk_dir
    bne entry
    inc dk_me
    dec dk_qt
    bne group
done:
    rts
.endproc
