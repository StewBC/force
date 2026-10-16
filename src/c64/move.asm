; Movement from src/sdl/game/world.c: orders, cover, portals, stepper.
; Procs may trash X, Y, and the world zero-page temps. The unit index
; for a think lives in think_i.

; Find the room containing zA0,zA1. A = room or NONE; X is scratch, Y is preserved.
.proc region_at
    ldx #0
next:
    cpx room_count
    bcs none
    lda zA0
    cmp rom_room_x0,x
    bcc adv
    lda rom_room_x0,x
    clc
    adc rom_room_w,x
    cmp zA0
    bcc adv
    beq adv
    lda zA1
    cmp rom_room_y0,x
    bcc adv
    lda rom_room_y0,x
    clc
    adc rom_room_h,x
    cmp zA1
    bcc adv
    beq adv
    txa
    rts
adv:
    inx
    jmp next
none:
    lda #NONE
    rts
.endproc

;-----------------------------------------------------------------------------
; Read next_hop[source=zA0,destination=zA1]; rows have a fixed ROOM_MAX stride.
.proc hop_get
    lda zA0
    asl
    asl
    asl
    asl
    clc
    adc zA1
    tax
    lda next_hop,x
    rts
.endproc

;-----------------------------------------------------------------------------
; Store A in next_hop[source=zA0,destination=zA1].
.segment "SPARE"

.segment "CODE"

;-----------------------------------------------------------------------------
; Return the opposite cardinal in A; unknown/NONE remains FACE_NONE.
.proc opposite_face
    cmp #FACE_N
    bne n1
    lda #FACE_S
    rts
n1:
    cmp #FACE_S
    bne n2
    lda #FACE_N
    rts
n2:
    cmp #FACE_E
    bne n3
    lda #FACE_W
    rts
n3:
    cmp #FACE_W
    bne n4
    lda #FACE_E
    rts
n4:
    lda #FACE_NONE
    rts
.endproc

;-----------------------------------------------------------------------------
; Set room zA0's approach mask from zA1 and schedule affected enemy cover jobs.
.proc script_approach
    ldx zA0
    cpx room_count
    bcs done
    lda zA1
    sta room_approach,x
    stx mv_dest
    ldx #LETTER_MAX
who:
    cpx #SECTION_MAX
    bcs done
    lda section_order_x,x
    sta zA0
    lda section_order_y,x
    sta zA1
    stx mv_who
    jsr region_at
    ldx mv_who
    cmp mv_dest
    bne adv
    lda section_order_verb,x
    cmp #VERB_DEFEND
    beq mark
    cmp #VERB_RETREAT
    beq mark
    cmp #VERB_ATTACK
    bne adv
    lda section_flags,x
    and #FLAG_CONTACT
    beq adv
mark:
    lda section_flags,x
    ora #FLAG_ASSIGN
    sta section_flags,x
adv:
    inx
    jmp who
done:
    rts
.endproc

;-----------------------------------------------------------------------------
; Resolve script WHERE index zT0 into zA2,zA3. C = usable destination.
.proc resolve_where
    ldy zT0
    cpy sc_where_count
    bcs no
    lda sc_where_kind,y
    cmp #WHERE_CELL
    beq cell
    cmp #WHERE_ROOM
    beq room
    cmp #WHERE_EXIT
    beq exitw
no:
    clc
    rts
cell:
    lda sc_where_a,y
    sta zA2
    lda sc_where_b,y
    sta zA3
    sec
    rts
room:
    lda sc_where_a,y
    sta zA0
    jmp room_canonical
exitw:
    lda sc_where_a,y
    jmp exit_face
.endproc

;-----------------------------------------------------------------------------
; Choose room zA0's first cover chip, centre, or an open approach-edge cell.
.proc room_canonical
    ldx zA0
    cpx room_count
    bcc rc_ok
    jmp no
rc_ok:
    lda rom_room_cover_count,x
    beq geom
    lda rom_room_cover_base,x
    tax
    lda rom_cover_x,x
    sta zA2
    lda rom_cover_y,x
    sta zA3
    sec
    rts
geom:
    lda rom_room_w,x
    lsr
    clc
    adc rom_room_x0,x
    sta zA2
    lda rom_room_h,x
    lsr
    clc
    adc rom_room_y0,x
    sta zA3
    stx mv_lead
    jsr cell_open
    bcc geom_blk
    jmp yes
geom_blk:
    ldx mv_lead
    lda rom_room_axis,x
    cmp #AXIS_NS
    bne scan_ew
    lda room_approach,x
    and #APPROACH_S
    beq ns_top
    lda rom_room_y0,x
    clc
    adc rom_room_h,x
    sec
    sbc #1
    jmp ns_y
ns_top:
    lda rom_room_y0,x
ns_y:
    sta zA3
    lda #0
    sta mv_n
ns_x:
    lda mv_n
    cmp #20
    bcs no
    cmp rom_room_w,x
    bcs no
    clc
    adc rom_room_x0,x
    sta zA2
    stx mv_lead
    jsr cell_open
    bcs yes
    ldx mv_lead
    inc mv_n
    jmp ns_x
scan_ew:
    lda room_approach,x
    and #APPROACH_E
    beq ew_left
    lda rom_room_x0,x
    clc
    adc rom_room_w,x
    sec
    sbc #1
    jmp ew_x
ew_left:
    lda rom_room_x0,x
ew_x:
    sta zA2
    lda #0
    sta mv_n
ew_y:
    lda mv_n
    cmp #20
    bcs no
    cmp rom_room_h,x
    bcs no
    clc
    adc rom_room_y0,x
    sta zA3
    stx mv_lead
    jsr cell_open
    bcs yes
    ldx mv_lead
    inc mv_n
    jmp ew_y
yes:
    sec
    rts
no:
    clc
    rts
.endproc

;-----------------------------------------------------------------------------
; Find an open cell on playfield face A, then return the adjacent outside cell.
.proc exit_face
    sta mv_front
    ldx #0
rn:
    cpx room_count
    bcc rn_ok
    jmp no
rn_ok:
    stx mv_lead
    jsr room_on_play
    bcs on_play
    jmp radv
on_play:
    ldx mv_lead
    lda mv_front
    cmp #FACE_W
    beq face_w
    jmp fe
face_w:
    lda rom_room_x0,x
    cmp play_x
    beq west_ok
    jmp radv
west_ok:
    lda play_x
    sta zA2
    lda rom_room_h,x
    lsr
    clc
    adc rom_room_y0,x
    sta zA3
    lda #1
    jmp seek
fe:
    cmp #FACE_E
    bne fn
    lda play_x
    clc
    adc play_w
    sta zT0
    lda rom_room_x0,x
    clc
    adc rom_room_w,x
    cmp zT0
    beq east_ok
    jmp radv
east_ok:
    lda zT0
    sec
    sbc #1
    sta zA2
    lda rom_room_h,x
    lsr
    clc
    adc rom_room_y0,x
    sta zA3
    lda #1
    jmp seek
fn:
    cmp #FACE_N
    beq face_n
    jmp fs
face_n:
    lda rom_room_y0,x
    cmp play_y
    beq north_ok
    jmp radv
north_ok:
    lda play_y
    sta zA3
    lda rom_room_w,x
    lsr
    clc
    adc rom_room_x0,x
    sta zA2
    lda #0
    jmp seek
fs:
    cmp #FACE_S
    beq face_s
    jmp radv
face_s:
    lda play_y
    clc
    adc play_h
    sta zT0
    lda rom_room_y0,x
    clc
    adc rom_room_h,x
    cmp zT0
    beq south_ok
    jmp radv
south_ok:
    lda zT0
    sec
    sbc #1
    sta zA3
    lda rom_room_w,x
    lsr
    clc
    adc rom_room_x0,x
    sta zA2
    lda #0
seek:
    sta mv_dodge
    lda zA2
    sta ra_x0
    lda zA3
    sta ra_y0
    jsr cell_open
    bcs hit
    lda #1
    sta mv_n
spread:
    lda mv_n
    cmp #20
    bcs radv
    lda mv_dodge
    beq spread_x
    lda ra_y0
    clc
    adc mv_n
    sta zA3
    lda ra_x0
    sta zA2
    jsr cell_open
    bcs hit
    lda ra_y0
    sec
    sbc mv_n
    sta zA3
    lda ra_x0
    sta zA2
    jsr cell_open
    bcs hit
    jmp spread_n
spread_x:
    lda ra_x0
    clc
    adc mv_n
    sta zA2
    lda ra_y0
    sta zA3
    jsr cell_open
    bcs hit
    lda ra_x0
    sec
    sbc mv_n
    sta zA2
    lda ra_y0
    sta zA3
    jsr cell_open
    bcs hit
spread_n:
    inc mv_n
    jmp spread
hit:
    jsr push_out
    sec
    rts
radv:
    ldx mv_lead
    inx
    jmp rn
no:
    clc
    rts
.endproc

;-----------------------------------------------------------------------------
; C = room X overlaps the mission rectangle; touching edges alone do not count.
.proc room_on_play
    lda rom_room_x0,x
    clc
    adc rom_room_w,x
    cmp play_x
    bcc no
    beq no
    lda play_x
    clc
    adc play_w
    cmp rom_room_x0,x
    bcc no
    beq no
    lda rom_room_y0,x
    clc
    adc rom_room_h,x
    cmp play_y
    bcc no
    beq no
    lda play_y
    clc
    adc play_h
    cmp rom_room_y0,x
    bcc no
    beq no
    sec
    rts
no:
    clc
    rts
.endproc

;-----------------------------------------------------------------------------
; Service the timed spawn job in bounded batches, recounting successful arrivals.
.proc spawn_pulse
    lda spawn_job_rem
    bne go
    rts
go:
    lda spawn_job_wait
    beq batch
    dec spawn_job_wait
    beq batch
    rts
batch:
    lda spawn_job_batch
    cmp spawn_job_rem
    bcc useb
    lda spawn_job_rem
useb:
    sta mv_n
    lda #0
    sta mv_stand
land:
    lda mv_n
    beq fin
    dec mv_n
    jsr pick_spawn
    bcc land
    lda spawn_job_letter
    sta zA2
    jsr spawn_identity
    lda #1
    sta zA4
    jsr unit_spawn
    cmp #NONE
    beq fin
    dec spawn_job_rem
    inc mv_stand
    jmp land
fin:
    lda mv_stand
    beq waitp
    jsr section_recount
    ldx spawn_job_letter
    cpx #SECTION_MAX
    bcs waitp
    lda section_order_verb,x
    cmp #VERB_DEFEND
    beq mark
    cmp #VERB_RETREAT
    beq mark
    cmp #VERB_ATTACK
    bne waitp
    lda section_flags,x
    and #FLAG_CONTACT
    beq waitp
mark:
    lda section_flags,x
    ora #FLAG_ASSIGN
    sta section_flags,x
waitp:
    lda spawn_job_period
    sta spawn_job_wait
    rts
.endproc

;-----------------------------------------------------------------------------
; Search at most 32 cells of the spawn room, in its axis-dependent scan order.
.proc pick_spawn
    lda spawn_job_room
    cmp #NONE
    beq room_source
    bmi point
room_source:
    lda spawn_job_room
    cmp #NONE
    bne have
    lda spawn_room
have:
    cmp room_count
    bcc room_ok
    jmp no
point:
    and #$0F
    tax
    lda sc_where_a,x
    sta zA2
    lda sc_where_b,x
    sta zA3
    lda #NONE
    sta think_i
    jsr cell_free
    bcs point_free
    rts
point_free:
    lda zA2
    sta zA0
    lda zA3
    sta zA1
    sec
    rts
room_ok:
    sta mv_who
    tax
    lda rom_room_x0,x
    sta ra_x0
    lda rom_room_y0,x
    sta ra_y0
    lda rom_room_w,x
    sta ra_x1
    lda rom_room_h,x
    sta ra_y1
    lda #0
    sta mv_pref
    lda rom_room_axis,x
    cmp #AXIS_NS
    beq ns
    lda #0
    sta rb_x0
px:
    lda rb_x0
    cmp ra_x1
    bcs no
    lda #0
    sta rb_y0
py:
    lda rb_y0
    cmp ra_y1
    bcs pxn
    jsr spawn_try
    bcs yes
    lda mv_pref
    cmp #33
    bcs no
    inc rb_y0
    jmp py
pxn:
    inc rb_x0
    jmp px
ns:
    lda #0
    sta rb_y0
ny:
    lda rb_y0
    cmp ra_y1
    bcs no
    lda #0
    sta rb_x0
nx:
    lda rb_x0
    cmp ra_x1
    bcs nyn
    jsr spawn_try
    bcs yes
    lda mv_pref
    cmp #33
    bcs no
    inc rb_x0
    jmp nx
nyn:
    inc rb_y0
    jmp ny
yes:
    sec
    rts
no:
    clc
    rts
.endproc

;-----------------------------------------------------------------------------
; Reject occupied/roof cells and MOVE spawns too close to their destination.
.proc spawn_try
    inc mv_pref
    lda mv_pref
    cmp #33
    bcs no
    lda ra_x0
    clc
    adc rb_x0
    sta zA0
    sta zA2
    lda ra_y0
    clc
    adc rb_y0
    sta zA1
    sta zA3
    lda #NONE
    sta think_i
    jsr cell_free
    bcc no
    ldx zA2
    stx mv_nx
    ldx zA3
    stx mv_ny
    lda mv_nx
    sta zA0
    lda mv_ny
    sta zA1
    jsr map_ptr
    tay
    lda rom_tile_class,y
    cmp #CLASS_ROOFS
    beq no
    ldx spawn_job_letter
    cpx #SECTION_MAX
    bcs ok
    lda section_order_verb,x
    cmp #VERB_MOVE
    bne ok
    jsr near_order
    bcs no
ok:
    lda mv_nx
    sta zA0
    lda mv_ny
    sta zA1
    sec
    rts
no:
    clc
    rts
.endproc

;-----------------------------------------------------------------------------
; C = proposed spawn mv_nx,mv_ny is within one cell of the job's order target.
.proc near_order
    ldx spawn_job_letter
    lda mv_nx
    sec
    sbc section_order_x,x
    bcs axp
    eor #$FF
    clc
    adc #1
axp:
    sta zT0
    lda mv_ny
    sec
    sbc section_order_y,x
    bcs ayp
    eor #$FF
    clc
    adc #1
ayp:
    cmp zT0
    bcs big
    lda zT0
big:
    cmp #2
    bcs far
    sec
    rts
far:
    clc
    rts
.endproc

;-----------------------------------------------------------------------------
; C = zA2,zA3 is walkable and unoccupied by anyone except think_i.
.proc cell_free
    jsr cell_open
    bcc no
    lda think_i
    sta zT7
    jsr cell_taken
    bcs no
    sec
    rts
no:
    clc
    rts
.endproc

;-----------------------------------------------------------------------------
; Consume pending section assign/release flags before movement uses cover targets.
.proc cover_jobs
    ldx #0
n:
    cpx #SECTION_MAX
    bcs done
    lda section_flags,x
    and #FLAG_ASSIGN
    beq rel
    lda section_flags,x
    and #($FF ^ FLAG_ASSIGN ^ FLAG_RELEASE)
    sta section_flags,x
    txa
    sta mv_who
    jsr cover_assign
    ldx mv_who
    jmp adv
rel:
    lda section_flags,x
    and #FLAG_RELEASE
    beq adv
    lda section_flags,x
    and #($FF ^ FLAG_RELEASE)
    sta section_flags,x
    txa
    sta mv_who
    jsr cover_release
    ldx mv_who
adv:
    inx
    jmp n
done:
    rts
.endproc

;-----------------------------------------------------------------------------
; Release mv_who's section cover assignments, preserving individual overrides.
.proc cover_release
    ldy #0
n:
    lda unit_section,y
    cmp mv_who
    bne adv
    lda unit_over_verb,y
    bne adv
    tya
    tax
    lda #NONE
    jsr cover_put
adv:
    iny
    cpy #UNIT_MAX
    bne n
    rts
.endproc

;-----------------------------------------------------------------------------
; Choose a destination-room front and assign available cover to each eligible man.
.proc cover_assign
    ldx mv_who
    cpx #SECTION_MAX
    bcs done
    lda section_order_x,x
    sta zA0
    lda section_order_y,x
    sta zA1
    jsr region_at
    cmp #NONE
    beq rel
    cmp room_count
    bcs rel
    sta mv_dest
    jsr cover_release
    jsr section_front
    sta mv_front
    ldx #0
man:
    cpx #UNIT_MAX
    bcs done
    stx think_i
    lda unit_count,x
    beq manx
    lda unit_section,x
    cmp mv_who
    bne manx
    lda unit_kind,x
    cmp #KIND_EMPLACEMENT
    beq manx
    lda unit_over_verb,x
    bne manx
    jsr pick_best
    ldx think_i
    jsr cover_put
manx:
    ldx think_i
    inx
    jmp man
rel:
    jmp cover_release
done:
    rts
.endproc

;-----------------------------------------------------------------------------
; Rank eligible chips/scouts by protection, then distance; return cover ID or NONE.
.proc pick_best
    lda #0
    sta mv_stand
    lda #NONE
    sta mv_dx
    ldx mv_dest
    lda rom_room_axis,x
    sta mv_pref
    lda rom_room_cover_base,x
    sta sm_here
    lda rom_room_cover_lo,x
    sta sm_lo
    lda rom_room_cover_none,x
    sta sm_hi
    lda rom_room_cover_hi,x
    sta sm_next
    lda mv_front
    jsr opposite_face
    sta mv_ny
    lda mv_front
    cmp #FACE_NONE
    beq neutrals
    lda mv_pref
    cmp #AXIS_NONE
    beq neutrals
    cmp #AXIS_EW
    bne try_ns
    lda mv_ny
    cmp #FACE_E
    beq west_bank
    cmp #FACE_W
    beq east_bank
    jmp neutrals
try_ns:
    cmp #AXIS_NS
    bne neutrals
    lda mv_ny
    cmp #FACE_N
    beq west_bank
    cmp #FACE_S
    beq east_bank
neutrals:
    ; Cover tables are grouped low pole, neutral, high pole; select the eligible contiguous slice.
    lda sm_here
    clc
    adc sm_lo
    sta sm_mode
    lda sm_hi
    sta mv_n
    jmp scan
west_bank:
    lda sm_here
    sta sm_mode
    lda sm_lo
    clc
    adc sm_hi
    sta mv_n
    jmp scan
east_bank:
    lda sm_here
    clc
    adc sm_lo
    sta sm_mode
    lda sm_hi
    clc
    adc sm_next
    sta mv_n
scan:
    lda #0
    sta mv_lead
cj:
    lda mv_lead
    cmp mv_n
    bcc cj_ok
    jmp scouts
cj_ok:
    clc
    adc sm_mode
    sta mv_p
    cmp rom_cover_count
    bcc cover_ok
    jmp scouts
cover_ok:
    ldx think_i
    lda unit_section,x
    tax
    lda section_order_verb,x
    cmp #VERB_KILL
    bne notkill
    ldx mv_p
    lda rom_cover_x,x
    ldy mv_who
    cmp section_order_x,y
    bne notkill
    lda rom_cover_y,x
    cmp section_order_y,y
    beq cadv
notkill:
    lda mv_p
    jsr cover_taken
    bcs cadv
    ldx mv_p
    lda rom_cover_grade,x
    cmp #3
    beq g4
    cmp #2
    beq g2
    cmp #1
    beq g0
    jmp cadv
g4:
    lda #4
    jmp haveg
g2:
    lda #2
    jmp haveg
g0:
    lda #0
haveg:
    sta mv_holes
    ldx think_i
    lda unit_x,x
    sta zA0
    lda unit_y,x
    sta zA1
    ldx mv_p
    lda rom_cover_x,x
    sta zA2
    lda rom_cover_y,x
    sta zA3
    jsr manhattan
    sta zT0
    lda mv_stand
    beq take
    lda mv_holes
    cmp mv_dy
    bcc cadv
    bne take
    lda zT0
    cmp mv_nx
    bcs cadv
take:
    lda #1
    sta mv_stand
    lda mv_p
    sta mv_dx
    lda mv_holes
    sta mv_dy
    lda zT0
    sta mv_nx
cadv:
    inc mv_lead
    jmp cj
scouts:
    ; Scout positions rank below grade-3 cover but above grade-2 cover, then by distance.
    ldx mv_dest
    lda rom_room_scout_base,x
    sta sm_mode
    lda rom_room_scout_count,x
    sta mv_n
    lda #0
    sta mv_lead
sj:
    lda mv_lead
    cmp mv_n
    bcc sj_ok
    jmp out
sj_ok:
    clc
    adc sm_mode
    sta mv_p
    cmp rom_scout_count
    bcc scout_ok
    jmp out
scout_ok:
    lda mv_front
    cmp #FACE_NONE
    beq sadv
    ldx mv_p
    lda rom_scout_facing,x
    cmp mv_front
    bne sadv
    lda mv_p
    clc
    adc #COVER_MAX
    sta mv_p
    jsr cover_taken
    bcs sadv
    ldx think_i
    lda unit_x,x
    sta zA0
    lda unit_y,x
    sta zA1
    lda mv_p
    sec
    sbc #COVER_MAX
    tax
    lda rom_scout_x,x
    sta zA2
    lda rom_scout_y,x
    sta zA3
    jsr manhattan
    sta zT0
    lda #3
    sta mv_holes
    lda mv_stand
    beq stake
    lda #3
    cmp mv_dy
    bcc sadv
    bne stake
    lda zT0
    cmp mv_nx
    bcc stake
    bne sadv
    lda mv_p
    cmp mv_dx
    bcs sadv
stake:
    lda #1
    sta mv_stand
    lda mv_p
    sta mv_dx
    lda #3
    sta mv_dy
    lda zT0
    sta mv_nx
sadv:
    inc mv_lead
    jmp sj
out:
    lda mv_stand
    beq none
    lda mv_dx
    rts
none:
    lda #NONE
    rts
.endproc

;-----------------------------------------------------------------------------
; C set when cover id A is reserved. The id is left in zT0.
; An id at or above COVER_MAX+SCOUT_MAX returns C clear and is not indexed.
; A, X, and Y are scratch.
.proc cover_taken
    sta zT0
    cmp #(COVER_MAX + SCOUT_MAX)
    bcs miss
    lsr
    lsr
    lsr
    tax
    lda zT0
    and #7
    tay
    lda cover_claim,x
    and cb_bit,y
    beq miss
    sec
    rts
miss:
    clc
    rts
.endproc

;-----------------------------------------------------------------------------
; Store A in unit_cover,x and move the claim bit off the old id onto the new one.
; X and Y are preserved. The same id returns and leaves the bit alone.
; An id at or above COVER_MAX+SCOUT_MAX clears the old bit and sets nothing.
; Trashes A and zPtr. Does not write zA0-zA4, zR0, or zT0-zT7, and does not
; read unit_count. Death and despawn zero the count, then store NONE.
.proc cover_put
    cmp unit_cover,x
    bne chg
    rts
chg:
    sta zPtr
    txa
    pha
    tya
    pha
    lda unit_cover,x
    cmp #(COVER_MAX + SCOUT_MAX)
    bcs store
    jsr cp_off
store:
    pla
    tay
    pla
    tax
    lda zPtr
    sta unit_cover,x
    cmp #(COVER_MAX + SCOUT_MAX)
    bcs done
    txa
    pha
    tya
    pha
    lda zPtr
    jsr cp_on
    pla
    tay
    pla
    tax
done:
    rts
; A is an id in 0..159. Trash A, X, and Y. Leave zPtr alone.
cp_off:
    jsr cp_ix
    lda cb_bit,y
    eor #$FF
    and cover_claim,x
    sta cover_claim,x
    rts
cp_on:
    jsr cp_ix
    lda cb_bit,y
    ora cover_claim,x
    sta cover_claim,x
    rts
cp_ix:
    pha
    lsr
    lsr
    lsr
    tax
    pla
    and #7
    tay
    rts
.endproc

;-----------------------------------------------------------------------------
; Return |x0-x1|+|y0-y1| for zA0,zA1 and zA2,zA3; zT1 is scratch.
.proc manhattan
    lda zA0
    sec
    sbc zA2
    bcs xp
    eor #$FF
    clc
    adc #1
xp:
    sta zT1
    lda zA1
    sec
    sbc zA3
    bcs yp
    eor #$FF
    clc
    adc #1
yp:
    clc
    adc zT1
    rts
.endproc

;-----------------------------------------------------------------------------
; Resolve mv_who's front from occupied cover, travel direction, or room approach.
.proc section_front
    ldx mv_who
    cpx #SECTION_MAX
    bcc who_ok
    jmp none
who_ok:
    lda section_order_x,x
    sta zA0
    lda section_order_y,x
    sta zA1
    jsr region_at
    cmp #NONE
    bne reg_ok
    jmp none
reg_ok:
    cmp room_count
    bcc reg_in
    jmp none
reg_in:
    sta mv_dest
    tax
    lda rom_room_axis,x
    sta mv_pref
    lda #0
    sta mv_holes
    ldx mv_who
    lda section_lead,x
    sta mv_lead
    cmp #UNIT_MAX
    bcc lead_lim
    jmp nolead
lead_lim:
    tax
    lda unit_count,x
    bne lead_live
    jmp nolead
lead_live:
    lda unit_over_verb,x
    beq havelead
    ldx #0
find:
    cpx #UNIT_MAX
    bcc find_ok
    jmp nolead
find_ok:
    lda unit_count,x
    beq fn
    lda unit_section,x
    cmp mv_who
    bne fn
    lda unit_over_verb,x
    bne fn
    stx mv_lead
    jmp havelead
fn:
    inx
    jmp find
havelead:
    ldx mv_lead
    lda unit_region,x
    sta mv_here
    cmp mv_dest
    beq in_dest
    cmp #NONE
    beq elsew
    cmp room_count
    bcs elsew
    jsr mid_delta
    jmp snapped
in_dest:
    jsr front_occupied
    cmp #FACE_NONE
    beq from_lead
    sta mv_front
    lda #1
    sta mv_holes
    jmp maybe_r
from_lead:
    ldx mv_who
    lda section_order_x,x
    ldx mv_lead
    sec
    sbc unit_x,x
    sta zA2
    ldx mv_who
    lda section_order_y,x
    ldx mv_lead
    sec
    sbc unit_y,x
    sta zA3
    jmp snapped
elsew:
    ldx mv_who
    lda section_order_x,x
    ldx mv_lead
    sec
    sbc unit_x,x
    sta zA2
    ldx mv_who
    lda section_order_y,x
    ldx mv_lead
    sec
    sbc unit_y,x
    sta zA3
snapped:
    ; Use the room axis to avoid diagonal fronts; room approach is the fallback.
    lda mv_pref
    jsr snap_axis
    sta mv_front
    jmp maybe_fb
nolead:
    lda #FACE_NONE
    sta mv_front
maybe_fb:
    lda mv_front
    cmp #FACE_NONE
    bne maybe_r
    ldx mv_dest
    lda room_approach,x
    sta zA0
    lda mv_pref
    jsr approach_front
    sta mv_front
maybe_r:
    ; Reverse travel-facing for retreat, unless occupied cover already fixed the front.
    ldx mv_who
    lda section_order_verb,x
    cmp #VERB_RETREAT
    bne outf
    lda mv_holes
    bne outf
    lda mv_front
    jsr opposite_face
    rts
outf:
    lda mv_front
    rts
none:
    lda #FACE_NONE
    rts
.endproc

;-----------------------------------------------------------------------------
; Put the signed centre-to-centre delta (mv_here to mv_dest) in zA2,zA3.
.proc mid_delta
    ldx mv_dest
    lda rom_room_w,x
    lsr
    clc
    adc rom_room_x0,x
    sta zT0
    lda rom_room_h,x
    lsr
    clc
    adc rom_room_y0,x
    sta zT1
    ldx mv_here
    lda rom_room_w,x
    lsr
    clc
    adc rom_room_x0,x
    sta zA2
    lda zT0
    sec
    sbc zA2
    sta zA2
    lda rom_room_h,x
    lsr
    clc
    adc rom_room_y0,x
    sta zA3
    lda zT1
    sec
    sbc zA3
    sta zA3
    rts
.endproc

;-----------------------------------------------------------------------------
; Find a non-overridden section member's exclusive cover facing in mv_dest.
.proc front_occupied
    ldy #0
fo:
    lda unit_count,y
    beq fn
    lda unit_section,y
    cmp mv_who
    bne fn
    lda unit_over_verb,y
    bne fn
    lda unit_region,y
    cmp mv_dest
    bne fn
    lda unit_cover,y
    cmp rom_cover_count
    bcs fn
    tax
    lda rom_cover_facing,x
    cmp #COVER_SOFT_N
    bcs fn
    cmp #FACE_NONE
    beq fn
    jsr opposite_face
    rts
fn:
    iny
    cpy #UNIT_MAX
    bne fo
    lda #FACE_NONE
    rts
.endproc

;-----------------------------------------------------------------------------
; Snap signed zA2,zA3 travel to room axis A, returning a cardinal or FACE_NONE.
.proc snap_axis
    cmp #AXIS_EW
    bne ns
    lda zA2
    beq none
    bmi west
    lda #FACE_E
    rts
west:
    lda #FACE_W
    rts
ns:
    cmp #AXIS_NS
    bne none
    lda zA3
    beq none
    bmi north
    lda #FACE_S
    rts
north:
    lda #FACE_N
    rts
none:
    lda #FACE_NONE
    rts
.endproc

;-----------------------------------------------------------------------------
; Choose a facing from approach mask zA0, preferring room axis A. Preserves X.
.proc approach_front
    sta zT0
    stx zT1
    lda zT0
    cmp #AXIS_EW
    bne ns
    lda zA0
    and #APPROACH_E
    beq ew_w
    lda #FACE_E
    ldx zT1
    rts
ew_w:
    lda zA0
    and #APPROACH_W
    beq enone
    lda #FACE_W
    ldx zT1
    rts
ns:
    cmp #AXIS_NS
    bne bits
    lda zA0
    and #APPROACH_S
    beq ns_n
    lda #FACE_S
    ldx zT1
    rts
ns_n:
    lda zA0
    and #APPROACH_N
    beq enone
    lda #FACE_N
    ldx zT1
    rts
bits:
    lda zA0
    and #APPROACH_N
    beq b1
    lda #FACE_N
    ldx zT1
    rts
b1:
    lda zA0
    and #APPROACH_E
    beq b2
    lda #FACE_E
    ldx zT1
    rts
b2:
    lda zA0
    and #APPROACH_S
    beq b3
    lda #FACE_S
    ldx zT1
    rts
b3:
    lda zA0
    and #APPROACH_W
    beq enone
    lda #FACE_W
    ldx zT1
    rts
enone:
    lda #FACE_NONE
    ldx zT1
    rts
.endproc

;-----------------------------------------------------------------------------
; Move eligible mobile units when their per-unit movement delay expires.
.proc think_all
    ldx #0
n:
    cpx #UNIT_MAX
    bcs done
    stx think_i
    lda unit_count,x
    beq adv
    lda unit_kind,x
    cmp #KIND_EMPLACEMENT
    beq adv
    lda unit_move_wait,x
    beq go
    dec unit_move_wait,x
    bne adv
go:
    jsr unit_think
adv:
    ldx think_i
    inx
    jmp n
done:
    rts
.endproc

;-----------------------------------------------------------------------------
; Return think_i's individual override, falling back to its section's order.
.proc effective_verb
    ldx think_i
    lda unit_over_verb,x
    beq secv
    rts
secv:
    ldy unit_section,x
    lda section_order_verb,y
    rts
.endproc

;-----------------------------------------------------------------------------
; Resolve a unit's destination, route through rooms, then arrive, cross, or take a step.
.proc unit_think
    ldx think_i
    lda unit_x,x
    sta zA0
    lda unit_y,x
    sta zA1
    jsr region_at
    ldx think_i
    sta unit_region,x
    jsr step_off
    bcc ut_on
    jmp done
ut_on:
    jsr effective_verb
    cmp #VERB_BUILD
    bne nbld
    jsr build_think
    rts
nbld:
    ldx think_i
    lda unit_section,x
    sta mv_who
    jsr unit_dest
    bcc done
    jsr pull_desired
    bcc done
    ldx think_i
    lda unit_x,x
    cmp mv_ox
    bne notyet
    lda unit_y,x
    cmp mv_oy
    bne notyet
    lda unit_region,x
    cmp mv_dest
    bne notyet
    jsr arrive
    rts
notyet:
    lda mv_here
    cmp mv_dest
    beq walk
cross:
    lda mv_p
    cmp #NONE
    beq walk
    jsr portal_cross
    bcc walk
    jsr maybe_retreat_face
    rts
walk:
    lda mv_dx
    sta zA0
    lda mv_dy
    sta zA1
    jsr stepper_aim
    jsr stepper_step
    jsr step_off
    bcs done
    jsr maybe_retreat_face
    jsr effective_verb
    cmp #VERB_MOVE
    bne done
    ldx think_i
    lda unit_x,x
    cmp mv_ox
    bne done
    lda unit_y,x
    cmp mv_oy
    bne done
    jsr occupy_chip
done:
    rts
.endproc

;-----------------------------------------------------------------------------
; Keep a retreating unit looking toward the section front after moving.
.proc maybe_retreat_face
    jsr effective_verb
    cmp #VERB_RETREAT
    bne no
    jsr section_front
    jsr face_slot
no:
    rts
.endproc

;-----------------------------------------------------------------------------
; On arrival, claim MOVE cover if possible and face according to the assigned position.
.proc arrive
    jsr effective_verb
    cmp #VERB_MOVE
    bne faceq
    jsr occupy_chip
faceq:
    jsr effective_verb
    sta mv_pref
    cmp #VERB_DEFEND
    beq doface
    cmp #VERB_ATTACK
    beq doface
    cmp #VERB_RETREAT
    beq doface
    cmp #VERB_MOVE
    bne no
    ldx think_i
    lda unit_cover,x
    cmp #NONE
    beq no
doface:
    ldx think_i
    lda unit_cover,x
    jsr cover_look
    jsr face_slot
no:
    rts
.endproc

;-----------------------------------------------------------------------------
; Resolve think_i's override, cover or formation target into mv_ox,mv_oy. C = target.
.proc unit_dest
    jsr effective_verb
    sta mv_pref
    ldx think_i
    lda unit_over_verb,x
    beq noover
    lda unit_over_x,x
    sta mv_ox
    lda unit_over_y,x
    sta mv_oy
    sec
    rts
noover:
    lda mv_pref
    cmp #VERB_MOVE
    bne coverv
    jmp move_dest
coverv:
    cmp #VERB_DEFEND
    beq cov
    cmp #VERB_ATTACK
    beq cov
    cmp #VERB_RETREAT
    beq cov
    clc
    rts
cov:
    ldx think_i
    lda unit_cover,x
    jsr cover_cell
    bcs yes
    jmp move_dest
yes:
    sec
    rts
.endproc

;-----------------------------------------------------------------------------
; Decode cover/scout ID A into mv_ox,mv_oy; C clear for an invalid/unassigned ID.
.proc cover_cell
    cmp #NONE
    beq no
    cmp #COVER_MAX
    bcs scout
    cmp rom_cover_count
    bcs no
    tax
    lda rom_cover_x,x
    sta mv_ox
    lda rom_cover_y,x
    sta mv_oy
    sec
    rts
scout:
    sec
    sbc #COVER_MAX
    cmp rom_scout_count
    bcs no
    tax
    lda rom_scout_x,x
    sta mv_ox
    lda rom_scout_y,x
    sta mv_oy
    sec
    rts
no:
    clc
    rts
.endproc

;-----------------------------------------------------------------------------
; Choose a section member's formation cell, or the inside lip of an exit order.
.proc move_dest
    ldx mv_who
    lda section_order_x,x
    sta zA0
    lda section_order_y,x
    sta zA1
    jsr off_play
    bcc blob
    jsr lip_of
    bcc blob
    lda zA2
    sta mv_ox
    lda zA3
    sta mv_oy
    sec
    rts
blob:
    ; Rank section members into the nine-cell formation around WHERE, skipping invalid cells.
    ldx mv_who
    lda section_order_x,x
    sta mv_ox
    lda section_order_y,x
    sta mv_oy
    sta zA1
    lda mv_ox
    sta zA0
    jsr region_at
    sta mv_dest
    lda #0
    sta mv_n
    ldx #0
rk:
    cpx think_i
    bcs rdone
    lda unit_count,x
    beq radv
    lda unit_section,x
    cmp mv_who
    bne radv
    lda unit_kind,x
    cmp #KIND_EMPLACEMENT
    beq radv
    inc mv_n
radv:
    inx
    jmp rk
rdone:
    ; Rank indexes the list section_issue stored. Past the end, keep the
    ; last cell; with none stored, the order cell written above remains.
    ldx mv_who
    lda form_n,x
    beq useord
    cmp mv_n
    bcc last
    beq last
    lda mv_n
    jsr form_slot
    jmp take
last:
    lda form_n,x
    sec
    sbc #1
    jsr form_slot
take:
    lda form_cell,x
    tay
    ldx mv_who
    lda form_build::form_dx,y
    clc
    adc section_order_x,x
    sta mv_ox
    lda form_build::form_dy,y
    clc
    adc section_order_y,x
    sta mv_oy
useord:
    sec
    rts
.endproc

;-----------------------------------------------------------------------------
; C = candidate zA2,zA3 is open, in the destination room, and not a painted portal.
.proc blob_ok
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
    lda zA2
    pha
    lda zA3
    pha
    jsr region_at
    sta zT0
    pla
    sta zA3
    pla
    sta zA2
    lda zT0
    cmp mv_dest
    bne no
    lda zA2
    sta zA0
    lda zA3
    sta zA1
    jsr is_portal
    bcs no
    jsr cell_open
    rts
no:
    clc
    rts
.endproc

;-----------------------------------------------------------------------------
; C = zA0,zA1 is a painted portal with two inferred room endpoints.
; The bitset is built by portal_bake. Trashes A, Y, zPtr, zT0, zT1.
.proc is_portal
    jsr portal_addr
    bcc no
    lda portal_mask,y
    ldy #0
    and (zPtr),y
    beq no
    sec
    rts
no:
    clc
    rts
.endproc

;-----------------------------------------------------------------------------
; Turn the final target into a local seam/door waypoint; report a failed room route.
.proc pull_desired
    lda mv_ox
    sta zA0
    lda mv_oy
    sta zA1
    jsr region_at
    sta mv_dest
    ldx think_i
    lda unit_region,x
    sta mv_here
    lda #NONE
    sta mv_p
    lda mv_here
    cmp #NONE
    beq bad
    cmp room_count
    bcs bad
    lda mv_dest
    cmp #NONE
    beq bad
    cmp room_count
    bcs bad
    cmp mv_here
    bne other
    lda mv_ox
    sta mv_dx
    lda mv_oy
    sta mv_dy
    sec
    rts
other:
    ; Route to the next room, preferring an open seam before falling back to painted doors.
    lda mv_here
    sta zA0
    lda mv_dest
    sta zA1
    jsr hop_get
    cmp #NONE
    beq bad
    cmp room_count
    bcs bad
    sta mv_lead
    jsr pick_front
    bcc door
    lda #NONE
    sta mv_p
    sec
    rts
door:
    jsr find_seed
    cmp #NONE
    beq bad
    jsr keep_right
    sta mv_p
    jsr on_portal
    cmp #NONE
    beq aimdoor
    jsr portal_exit
    bcs out
    jmp bad
aimdoor:
    ldx mv_p
    lda rom_portal_x,x
    sta mv_dx
    lda rom_portal_y,x
    sta mv_dy
out:
    sec
    rts
bad:
    jsr fail_path
    clc
    rts
.endproc

;-----------------------------------------------------------------------------
; Latch NOPATH on a section and notify the player bank on its first failure.
; Other section flags stay. The masked test must not be the stored value.
.proc fail_path
    ldx mv_who
    cpx #SECTION_MAX
    bcs done
    lda section_flags,x
    and #FLAG_NOPATH
    bne done
    lda section_flags,x
    ora #FLAG_NOPATH
    sta section_flags,x
    cpx #LETTER_MAX
    bcs done
    stx path_fail_who
done:
    rts
.endproc

;-----------------------------------------------------------------------------
; Describe a touching room edge in sm_* for the live crossing walker.
.proc seam_prep
    lda zA0
    cmp room_count
    bcc sp_a
    jmp no
sp_a:
    lda zA1
    cmp room_count
    bcc sp_b
    jmp no
sp_b:
    cmp zA0
    beq no
    ldx zA0
    jsr box_a
    ldx zA1
    jsr box_b
    lda ra_x1
    cmp rb_x0
    bne v2
    lda ra_x1
    sec
    sbc #1
    sta sm_here
    lda rb_x0
    sta sm_next
    jmp vert
v2:
    lda rb_x1
    cmp ra_x0
    bne h1
    lda ra_x0
    sta sm_here
    lda rb_x1
    sec
    sbc #1
    sta sm_next
vert:
    lda #0
    sta sm_mode
    jsr y_overlap
    rts
h1:
    lda ra_y1
    cmp rb_y0
    bne h2
    lda ra_y1
    sec
    sbc #1
    sta sm_here
    lda rb_y0
    sta sm_next
    jmp horiz
h2:
    lda rb_y1
    cmp ra_y0
    bne no
    lda ra_y0
    sta sm_here
    lda rb_y1
    sec
    sbc #1
    sta sm_next
horiz:
    lda #1
    sta sm_mode
    jsr x_overlap
    rts
no:
    clc
    rts
.endproc

;-----------------------------------------------------------------------------
; Load room X's half-open rectangle into ra_x0/y0/x1/y1.
.proc box_a
    lda rom_room_x0,x
    sta ra_x0
    clc
    adc rom_room_w,x
    sta ra_x1
    lda rom_room_y0,x
    sta ra_y0
    clc
    adc rom_room_h,x
    sta ra_y1
    rts
.endproc

;-----------------------------------------------------------------------------
; Load room X's half-open rectangle into rb_x0/y0/x1/y1.
.proc box_b
    lda rom_room_x0,x
    sta rb_x0
    clc
    adc rom_room_w,x
    sta rb_x1
    lda rom_room_y0,x
    sta rb_y0
    clc
    adc rom_room_h,x
    sta rb_y1
    rts
.endproc

;-----------------------------------------------------------------------------
; Set the half-open shared Y interval sm_lo..sm_hi; caller tests for an empty span.
.proc y_overlap
    lda ra_y0
    cmp rb_y0
    bcs ylo_a
    lda rb_y0
    jmp ylo
ylo_a:
    lda ra_y0
ylo:
    sta sm_lo
    lda ra_y1
    cmp rb_y1
    bcc yhi_a
    lda rb_y1
    jmp yhi
yhi_a:
    lda ra_y1
yhi:
    sta sm_hi
    sec
    rts
.endproc

;-----------------------------------------------------------------------------
; Set the half-open shared X interval sm_lo..sm_hi; caller tests for an empty span.
.proc x_overlap
    lda ra_x0
    cmp rb_x0
    bcs xlo_a
    lda rb_x0
    jmp xlo
xlo_a:
    lda ra_x0
xlo:
    sta sm_lo
    lda ra_x1
    cmp rb_x1
    bcc xhi_a
    lda rb_x1
    jmp xhi
xhi_a:
    lda ra_x1
xhi:
    sta sm_hi
    sec
    rts
.endproc

;-----------------------------------------------------------------------------
; C = both sides of seam position mv_p are open; occupancy is deliberately ignored.
.proc seam_pair
    lda sm_mode
    bne hor
    lda sm_here
    sta zA2
    lda mv_p
    sta zA3
    jsr cell_open
    bcc no
    lda sm_next
    sta zA2
    lda mv_p
    sta zA3
    jmp cell_open
hor:
    lda mv_p
    sta zA2
    lda sm_here
    sta zA3
    jsr cell_open
    bcc no
    lda mv_p
    sta zA2
    lda sm_next
    sta zA3
    jmp cell_open
no:
    clc
    rts
.endproc

.segment "SPARE"

portal_mask:
    .byte $01,$02,$04,$08,$10,$20,$40,$80

;-----------------------------------------------------------------------------
; Point zPtr at the portal bit for zA0,zA1 and return its bit index in Y.
; C clear when the cell is outside the map. Preserves X. Trashes A, zT0, zT1.
.proc portal_addr
    lda zA0
    cmp map_w
    bcs no
    lda zA1
    cmp map_h
    bcs no
    lda #0
    sta zT1
    lda zA1
    asl
    rol zT1
    sta zT0
    asl zT0
    rol zT1
    asl zT0
    rol zT1
    clc
    adc zT0
    sta zT0
    bcc row
    inc zT1
row:
    lda zA0
    lsr
    lsr
    lsr
    clc
    adc zT0
    sta zT0
    bcc ptr
    inc zT1
ptr:
    lda zA0
    and #7
    tay
    lda #<portal_bits
    clc
    adc zT0
    sta zPtr
    lda #>portal_bits
    adc zT1
    sta zPtr+1
    sec
    rts
no:
    clc
    rts
.endproc

;-----------------------------------------------------------------------------
; Clear portal_bits, then set each generated portal that has two room ends.
; Preserves nothing. Called during mission initialization.
.proc portal_bake
    lda #0
    tay
c0:
    sta portal_bits,y
    iny
    bne c0
    ldy #0
c1:
    sta portal_bits+$100,y
    iny
    cpy #$90
    bne c1
    ldx #0
p:
    cpx rom_portal_count
    bcs done
    lda portal_from,x
    cmp #NONE
    beq adv
    lda portal_to,x
    cmp #NONE
    beq adv
    lda rom_portal_x,x
    sta zA0
    lda rom_portal_y,x
    sta zA1
    jsr portal_addr
    bcc adv
    lda portal_mask,y
    ldy #0
    ora (zPtr),y
    sta (zPtr),y
adv:
    inx
    jmp p
done:
    rts
.endproc

;-----------------------------------------------------------------------------
; Find the stored wall between rooms zA0 and zA1.
; C set: X is the door, A is 0 when zA0 is the lower room id and 1 otherwise.
; C clear: no stored list. Preserves zA0 and zA1. Trashes zT0-zT2.
.proc door_find
    lda zA0
    cmp zA1
    bcc lo
    lda zA1
    sta zT0
    lda zA0
    sta zT1
    lda #1
    jmp scan
lo:
    sta zT0
    lda zA1
    sta zT1
    lda #0
scan:
    sta zT2
    ldx #0
s:
    cpx door_n
    bcs miss
    lda door_lo,x
    cmp zT0
    bne nxt
    lda door_hi,x
    cmp zT1
    beq hit
nxt:
    inx
    jmp s
hit:
    lda door_cnt,x
    beq nxt
    lda zT2
    sec
    rts
miss:
    clc
    rts
.endproc

;-----------------------------------------------------------------------------
; Load direction A's geometry for door X into sm_*. Preserves X and A.
.proc door_load
    cmp #0
    bne back
    lda door_mode_f,x
    sta sm_mode
    lda door_here_f,x
    sta sm_here
    lda door_next_f,x
    sta sm_next
    lda door_slo_f,x
    sta sm_lo
    lda door_shi_f,x
    sta sm_hi
    lda #0
    rts
back:
    lda door_mode_b,x
    sta sm_mode
    lda door_here_b,x
    sta sm_here
    lda door_next_b,x
    sta sm_next
    lda door_slo_b,x
    sta sm_lo
    lda door_shi_b,x
    sta sm_hi
    lda #1
    rts
.endproc

;-----------------------------------------------------------------------------
; Choose an open seam crossing from the stored list, or walk a wall that
; was not stored. mv_here and mv_lead are the two rooms. C clear on failure.
; Trashes the seam scratch and A, X, Y.
.proc pick_front
    lda mv_here
    sta zA0
    lda mv_lead
    sta zA1
    jsr door_find
    bcc live
    jsr door_load
    jmp pick_list
live:
    lda mv_here
    sta zA0
    lda mv_lead
    sta zA1
    jsr seam_prep
    bcc no
    jmp pick_live
no:
    clc
    rts
.endproc

;-----------------------------------------------------------------------------
; Standing on the loaded seam crosses straight. Otherwise one pass of the
; open list: nearest when there are three or more, keep-right for one or two.
; X is the door on entry. sm_* is already loaded. C set, destination in mv_dx/mv_dy.
.proc pick_list
    stx zT6
    ldx think_i
    lda sm_mode
    bne stand_h
    lda unit_x,x
    cmp sm_here
    bne choose
    lda unit_y,x
    cmp sm_lo
    bcc choose
    cmp sm_hi
    bcs choose
    lda sm_next
    sta mv_dx
    lda unit_y,x
    sta mv_dy
    sec
    rts
stand_h:
    lda unit_y,x
    cmp sm_here
    bne choose
    lda unit_x,x
    cmp sm_lo
    bcc choose
    cmp sm_hi
    bcs choose
    lda unit_x,x
    sta mv_dx
    lda sm_next
    sta mv_dy
    sec
    rts
choose:
    ldx zT6
    lda door_cnt,x
    sta mv_n
    lda door_at,x
    sta zT6
    lda #0
    sta mv_lead
    lda mv_n
    cmp #3
    bcs near
    lda #0
    sta mv_stand
    jsr lane_signs
    jmp lloop
near:
    lda #$FF
    sta mv_nx
nloop:
    lda mv_lead
    cmp mv_n
    bcs ndone
    ldy zT6
    lda door_pool,y
    sta mv_p
    inc zT6
    inc mv_lead
    jsr seam_here
    ldx think_i
    lda unit_x,x
    sta zA0
    lda unit_y,x
    sta zA1
    jsr manhattan
    cmp mv_nx
    bcs nloop
    sta mv_nx
    lda zA2
    sta mv_dx
    lda zA3
    sta mv_dy
    jmp nloop
ndone:
    sec
    rts
lloop:
    lda mv_lead
    cmp mv_n
    bcs ldone
    ldy zT6
    lda door_pool,y
    sta mv_p
    inc zT6
    inc mv_lead
    jsr seam_here
    lda mv_stand
    bne lcmp
    lda zA2
    sta mv_dx
    lda zA3
    sta mv_dy
    lda #1
    sta mv_stand
    jmp lloop
lcmp:
    jsr lane_better
    bcc lloop
    lda zA2
    sta mv_dx
    lda zA3
    sta mv_dy
    jmp lloop
ldone:
    sec
    rts
.endproc

;-----------------------------------------------------------------------------
; Today's wall walk, for a span that was not stored. sm_* is already prepared.
; Straight across, then nearest or keep-right. C clear when nothing is open.
.proc pick_live
    lda #0
    sta mv_n
    sta mv_stand
    lda sm_lo
    sta mv_p
c1:
    lda mv_p
    cmp sm_hi
    bcs c1d
    jsr seam_here
    lda zA2
    ldx think_i
    cmp unit_x,x
    bne c1n
    lda zA3
    cmp unit_y,x
    bne c1n
    lda #1
    sta mv_stand
    lda sm_mode
    bne st_h
    lda sm_next
    sta mv_nx
    lda mv_p
    sta mv_ny
    jmp c1n
st_h:
    lda mv_p
    sta mv_nx
    lda sm_next
    sta mv_ny
c1n:
    jsr seam_pair
    bcc c1a
    inc mv_n
c1a:
    inc mv_p
    jmp c1
c1d:
    lda mv_n
    bne have_n
    jmp no
have_n:
    lda mv_stand
    beq choose
    lda mv_nx
    sta mv_dx
    lda mv_ny
    sta mv_dy
    sec
    rts
choose:
    lda mv_n
    cmp #3
    bcs nearest
    jmp lane
nearest:
    lda #0
    sta mv_stand
    lda sm_lo
    sta mv_p
    lda #$FF
    sta mv_nx
nloop:
    lda mv_p
    cmp sm_hi
    bcs ndone
    jsr seam_pair
    bcc nadv
    jsr seam_here
    ldx think_i
    lda unit_x,x
    sta zA0
    lda unit_y,x
    sta zA1
    jsr manhattan
    cmp mv_nx
    bcs nadv
    sta mv_nx
    lda zA2
    sta mv_dx
    lda zA3
    sta mv_dy
nadv:
    inc mv_p
    jmp nloop
ndone:
    sec
    rts
lane:
    lda #0
    sta mv_stand
    jsr lane_signs
    lda sm_lo
    sta mv_p
lloop:
    lda mv_p
    cmp sm_hi
    bcs ldone
    jsr seam_pair
    bcc ladv
    jsr seam_here
    lda mv_stand
    bne lcmp
    lda zA2
    sta mv_dx
    lda zA3
    sta mv_dy
    lda #1
    sta mv_stand
    jmp ladv
lcmp:
    jsr lane_better
    bcc ladv
    lda zA2
    sta mv_dx
    lda zA3
    sta mv_dy
ladv:
    inc mv_p
    jmp lloop
ldone:
    sec
    rts
no:
    clc
    rts
.endproc

;-----------------------------------------------------------------------------
; Section*9+slot for the formation tables. A is the slot, X the section.
; Returns the index in X. Trashes A, zT0, zT1.
.proc form_slot
    sta zT0
    txa
    asl
    asl
    asl
    sta zT1
    txa
    clc
    adc zT1
    clc
    adc zT0
    tax
    rts
.endproc

;-----------------------------------------------------------------------------
; Build section X's valid formation cells from its order cell.
; Same tests as the old move_dest walk. Preserves zT4 and zT5.
; Trashes A, Y, mv_*, zA0-zA3, zT0, zT1, zPtr, zT7.
.proc form_build
    stx mv_who
    lda section_order_x,x
    sta mv_ox
    sta zA0
    lda section_order_y,x
    sta mv_oy
    sta zA1
    jsr region_at
    sta mv_dest
    lda #0
    sta mv_n
    sta mv_lead
kloop:
    lda mv_lead
    cmp #FORM_CELLS
    bcs kend
    tay
    lda form_dx,y
    clc
    adc mv_ox
    sta zA2
    lda form_dy,y
    clc
    adc mv_oy
    sta zA3
    jsr blob_ok
    bcc kadv
    ldx mv_who
    lda mv_n
    jsr form_slot
    lda mv_lead
    sta form_cell,x
    inc mv_n
kadv:
    inc mv_lead
    jmp kloop
kend:
    ldx mv_who
    lda mv_n
    sta form_n,x
    rts
form_dx:
    .byte 0, 0, 0, $FF, 1, $FF, 1, 1, $FF
form_dy:
    .byte 0, $FF, 1, 0, 0, $FF, 1, $FF, 1
.endproc

.segment "CODE"

;-----------------------------------------------------------------------------
; Convert seam position mv_p into the current-room cell zA2,zA3.
.proc seam_here
    lda sm_mode
    bne hor
    lda sm_here
    sta zA2
    lda mv_p
    sta zA3
    rts
hor:
    lda mv_p
    sta zA2
    lda sm_here
    sta zA3
    rts
.endproc

;-----------------------------------------------------------------------------
; Classify travel direction and dominant axis for the keep-right lane tie-break.
; lane_axis is 1 when X dominates. rb_* are room edges: same_edge overwrites
; them between this call and lane_better, so the axis cannot live there.
.proc lane_signs
    ldx think_i
    lda mv_ox
    sec
    sbc unit_x,x
    sta mv_holes
    lda mv_oy
    sec
    sbc unit_y,x
    sta mv_pref
    lda mv_holes
    bpl axp
    eor #$FF
    clc
    adc #1
axp:
    sta zT0
    lda mv_pref
    bpl ayp
    eor #$FF
    clc
    adc #1
ayp:
    cmp zT0
    beq horiz
    bcs vert
horiz:
    lda #1
    sta lane_axis
    rts
vert:
    lda #0
    sta lane_axis
    rts
.endproc

;-----------------------------------------------------------------------------
; C = candidate zA2,zA3 is farther right than mv_dx,mv_dy for this travel direction.
; lane_axis selects the axis; mv_holes and mv_pref are the signed deltas.
.proc lane_better
    lda lane_axis
    beq vert
    lda mv_holes
    bmi west
    lda zA3
    cmp mv_dy
    bcc no
    bne yes
    lda zA2
    cmp mv_dx
    bcc no
    beq no
    jmp yes
west:
    lda zA3
    cmp mv_dy
    bcs noeq
    jmp yes
noeq:
    bne no
    lda zA2
    cmp mv_dx
    bcs no
    jmp yes
vert:
    lda mv_pref
    bmi north
    lda zA2
    cmp mv_dx
    bcs nox
    jmp yes
nox:
    bne no
    lda zA3
    cmp mv_dy
    bcc no
    beq no
    jmp yes
north:
    lda zA2
    cmp mv_dx
    bcc no
    bne yes
    lda zA3
    cmp mv_dy
    bcs no
yes:
    sec
    rts
no:
    clc
    rts
.endproc

;-----------------------------------------------------------------------------
; Return the first painted portal between mv_here and mv_lead, or NONE.
.proc find_seed
    ldx #0
n:
    cpx rom_portal_count
    bcs no
    lda portal_from,x
    cmp #NONE
    beq adv
    lda portal_to,x
    cmp #NONE
    beq adv
    lda portal_from,x
    cmp mv_here
    bne s2
    lda portal_to,x
    cmp mv_lead
    beq yes
s2:
    lda portal_from,x
    cmp mv_lead
    bne adv
    lda portal_to,x
    cmp mv_here
    beq yes
adv:
    inx
    jmp n
yes:
    txa
    rts
no:
    lda #NONE
    rts
.endproc

;-----------------------------------------------------------------------------
; Starting with portal A, choose a right-hand portal connecting the same room pair.
.proc keep_right
    sta mv_p
    tax
    lda rom_portal_x,x
    sta mv_dx
    lda rom_portal_y,x
    sta mv_dy
    jsr lane_signs
    ldx #0
n:
    cpx rom_portal_count
    bcs out
    cpx mv_p
    beq adv
    stx mv_nx
    lda mv_p
    sta zA0
    lda mv_nx
    sta zA1
    jsr same_edge
    bcc adv
    ldx mv_nx
    lda rom_portal_x,x
    sta zA2
    lda rom_portal_y,x
    sta zA3
    jsr lane_better
    bcc adv
    lda zA2
    sta mv_dx
    lda zA3
    sta mv_dy
    lda mv_nx
    sta mv_p
adv:
    inx
    jmp n
out:
    lda mv_p
    rts
.endproc

;-----------------------------------------------------------------------------
; C = portal indices zA0,zA1 connect the same unordered pair of rooms.
.proc same_edge
    ldx zA0
    lda portal_from,x
    sta ra_x0
    lda portal_to,x
    sta ra_y0
    ldx zA1
    lda portal_from,x
    sta rb_x0
    lda portal_to,x
    sta rb_y0
    lda ra_x0
    cmp #NONE
    beq no
    lda ra_y0
    cmp #NONE
    beq no
    lda rb_x0
    cmp #NONE
    beq no
    lda rb_y0
    cmp #NONE
    beq no
    lda ra_x0
    cmp rb_x0
    bne cross
    lda ra_y0
    cmp rb_y0
    beq yes
cross:
    lda ra_x0
    cmp rb_y0
    bne no
    lda ra_y0
    cmp rb_x0
    bne no
yes:
    sec
    rts
no:
    clc
    rts
.endproc

;-----------------------------------------------------------------------------
; Return the portal beneath think_i if it belongs to the selected edge, else NONE.
.proc on_portal
    ldx think_i
    lda unit_x,x
    sta zA0
    lda unit_y,x
    sta zA1
    ldx #0
n:
    cpx rom_portal_count
    bcs no
    lda rom_portal_x,x
    cmp zA0
    bne adv
    lda rom_portal_y,x
    cmp zA1
    bne adv
    cpx mv_p
    beq yes
    stx mv_nx
    lda mv_p
    sta zA2
    lda mv_nx
    sta zA3
    lda zA0
    pha
    lda zA1
    pha
    lda zA2
    sta zA0
    lda zA3
    sta zA1
    jsr same_edge
    pla
    sta zA1
    pla
    sta zA0
    bcs yesx
adv:
    inx
    jmp n
yesx:
    lda mv_nx
    rts
yes:
    txa
    rts
no:
    lda #NONE
    rts
.endproc

;-----------------------------------------------------------------------------
; Find the cardinal neighbour across mv_p and return it in mv_dx,mv_dy.
.proc portal_exit
    ldx mv_p
    lda portal_from,x
    cmp mv_here
    bne t2
    lda portal_to,x
    jmp other
t2:
    lda portal_to,x
    cmp mv_here
    bne no
    lda portal_from,x
other:
    cmp #NONE
    beq no
    sta mv_ny
    ldy #0
d:
    cpy #4
    bcs no
    ldx mv_p
    lda rom_portal_x,x
    clc
    adc pdx,y
    sta zA0
    lda rom_portal_y,x
    clc
    adc pdy,y
    sta zA1
    jsr region_at
    cmp mv_ny
    beq hit
    iny
    jmp d
hit:
    lda zA0
    sta mv_dx
    lda zA1
    sta mv_dy
    sec
    rts
no:
    clc
    rts
pdx:
    .byte 0, 1, 0, $FF
pdy:
    .byte $FF, 0, 1, 0
.endproc

;-----------------------------------------------------------------------------
; If standing on a matching portal, try landing across it. C = crossed.
.proc portal_cross
    jsr on_portal
    cmp #NONE
    beq no
    sta mv_p
    jsr portal_exit
    bcc no
    lda mv_dx
    sta zA2
    lda mv_dy
    sta zA3
    lda #0
    sta mv_dodge
    jmp try_land
no:
    clc
    rts
.endproc

;-----------------------------------------------------------------------------
; Prepare signed deltas and Bresenham error toward zA0,zA1, with capped cardinal runs.
.proc stepper_aim
    ldx think_i
    lda zA0
    sta unit_tgt_x
    sta mv_dx
    lda zA1
    sta unit_tgt_y
    sta mv_dy
    lda mv_dx
    sec
    sbc unit_x,x
    beq zsx
    bcc negx
    sta unit_step_ax
    lda #1
    sta unit_step_sx
    jmp yaim
negx:
    lda unit_x,x
    sec
    sbc mv_dx
    sta unit_step_ax
    lda #SX_NEG
    sta unit_step_sx
    jmp yaim
zsx:
    lda #0
    sta unit_step_ax
    sta unit_step_sx
yaim:
    lda mv_dy
    sec
    sbc unit_y,x
    beq zsy
    bcc negy
    sta unit_step_ay
    lda #1
    sta unit_step_sy
    jmp err
negy:
    lda unit_y,x
    sec
    sbc mv_dy
    sta unit_step_ay
    lda #SX_NEG
    sta unit_step_sy
    jmp err
zsy:
    lda #0
    sta unit_step_ay
    sta unit_step_sy
err:
    lda unit_step_ax
    sec
    sbc unit_step_ay
    sta unit_step_err
    lda unit_step_sx
    beq farchk
    lda unit_step_sy
    bne norun
farchk:
    lda unit_step_ax
    cmp #STEP_FAR+1
    bcs far
    lda unit_step_ay
    cmp #STEP_FAR+1
    bcc norun
far:
    lda unit_step_ax
    cmp unit_step_ay
    bcs maj
    lda unit_step_ay
maj:
    cmp #STEP_CAP
    bcc store
    lda #STEP_CAP
store:
    sta unit_step_run
    rts
norun:
    lda #0
    sta unit_step_run
    rts
.endproc

;-----------------------------------------------------------------------------
; Try a diagonal, preferred axis, alternate axis, then sidestep; reload movement pacing.
.proc stepper_step
    ldx think_i
    lda unit_step_ax
    ora unit_step_ay
    bne go
    clc
    rts
go:
    lda unit_step_sx
    beq card
    lda unit_step_sy
    beq card
    clc
    adc unit_y,x
    sta mv_ny
    lda unit_step_sx
    clc
    adc unit_x,x
    sta mv_nx
    lda mv_nx
    sta zA2
    lda unit_y,x
    sta zA3
    jsr cell_open
    bcc s2
    jmp dtry
s2:
    lda unit_x,x
    sta zA2
    lda mv_ny
    sta zA3
    jsr cell_open
    bcc card
dtry:
    lda mv_nx
    sta zA2
    lda mv_ny
    sta zA3
    lda #0
    sta mv_dodge
    jsr try_step
    bcc card
    jmp paced
card:
    ; If the diagonal is unavailable, try the preferred cardinal direction before its alternate.
    jsr pref_axis
    sta mv_pref
    cmp #1
    bne try_y
    ldx think_i
    lda unit_step_sx
    beq try_y
    clc
    adc unit_x,x
    sta zA2
    lda unit_y,x
    sta zA3
    lda #0
    sta mv_dodge
    jsr try_step
    bcc try_y
    jmp step_ok
try_y:
    lda mv_pref
    bne second
    ldx think_i
    lda unit_step_sy
    beq second
    clc
    adc unit_y,x
    sta zA3
    lda unit_x,x
    sta zA2
    lda #0
    sta mv_dodge
    jsr try_step
    bcc second
    jmp step_ok
second:
    jsr slide_gate
    bcs fall
    lda mv_pref
    beq sec_x
    ldx think_i
    lda unit_step_sy
    beq side
    clc
    adc unit_y,x
    sta zA3
    lda unit_x,x
    sta zA2
    lda #0
    sta mv_dodge
    jsr try_step
    bcs fall
    jmp side
sec_x:
    ldx think_i
    lda unit_step_sx
    beq side
    clc
    adc unit_x,x
    sta zA2
    lda unit_y,x
    sta zA3
    lda #0
    sta mv_dodge
    jsr try_step
    bcs fall
side:
    ; Both forward choices failed; try a lateral dodge and end any straight-run preference.
    jsr side_step
fall:
    ldx think_i
    lda #0
    sta unit_step_run
paced:
    jsr move_reload
    ldx think_i
    sta unit_move_wait,x
    sec
    rts
step_ok:
    ldx think_i
    lda unit_step_run
    beq bres
    dec unit_step_run
    bne paced
    lda unit_tgt_x
    sta zA0
    lda unit_tgt_y
    sta zA1
    jsr stepper_aim
    jmp paced
bres:
    ; Update accumulated error after a cardinal step to balance X/Y progress.
    lda mv_pref
    beq addax
    lda unit_step_err
    sec
    sbc unit_step_ay
    sta unit_step_err
    jmp paced
addax:
    lda unit_step_err
    clc
    adc unit_step_ax
    sta unit_step_err
    jmp paced
.endproc

;-----------------------------------------------------------------------------
; Return 1 for X or 0 for Y, using the far-run major axis or signed Bresenham error.
.proc pref_axis
    ldx think_i
    lda unit_step_run
    beq errp
    lda unit_step_ax
    cmp unit_step_ay
    bcs yes
    lda #0
    rts
yes:
    lda #1
    rts
errp:
    lda unit_step_err
    bmi no
    lda #1
    rts
no:
    lda #0
    rts
.endproc

;-----------------------------------------------------------------------------
; Try the right-hand sidestep, then its mirror; dodges cannot cross room/portal boundaries.
; try_step leaves X as a portal or room index, so the mirror reloads think_i.
.proc side_step
    ldx think_i
    lda mv_pref
    beq sy
    lda unit_step_sx
    beq no
    cmp #1
    bne sdy_n
    lda #1
    jmp sdy
sdy_n:
    lda #SX_NEG
sdy:
    clc
    adc unit_y,x
    sta zA3
    lda unit_x,x
    sta zA2
    lda #1
    sta mv_dodge
    jsr try_step
    bcs yes
    ldx think_i
    lda unit_y,x
    sec
    sbc zA3
    clc
    adc unit_y,x
    sta zA3
    lda unit_x,x
    sta zA2
    jsr try_step
    rts
sy:
    lda unit_step_sy
    beq no
    cmp #1
    bne sdx_p
    lda #SX_NEG
    jmp sdx
sdx_p:
    lda #1
sdx:
    clc
    adc unit_x,x
    sta zA2
    lda unit_y,x
    sta zA3
    lda #1
    sta mv_dodge
    jsr try_step
    bcs yes
    ldx think_i
    lda unit_x,x
    sec
    sbc zA2
    clc
    adc unit_x,x
    sta zA2
    lda unit_y,x
    sta zA3
    jsr try_step
yes:
    rts
no:
    clc
    rts
.endproc

;-----------------------------------------------------------------------------
; Check room/portal restrictions for candidate zA2,zA3 before attempting the landing.
.proc try_step
    lda zA2
    cmp map_w
    bcs no
    lda zA3
    cmp map_h
    bcs no
    lda zA2
    sta mv_nx
    lda zA3
    sta mv_ny
    sta zA1
    lda mv_nx
    sta zA0
    jsr is_portal
    bcc notp
    lda mv_dodge
    bne no
    jmp try_land
notp:
    lda mv_nx
    sta zA0
    lda mv_ny
    sta zA1
    jsr region_at
    sta zT6
    ldx think_i
    lda unit_region,x
    cmp #NONE
    beq land
    lda zT6
    cmp #NONE
    beq land
    cmp unit_region,x
    beq land
    lda mv_dodge
    bne no
land:
    jmp try_land
no:
    clc
    rts
.endproc

;-----------------------------------------------------------------------------
; Reject blocked/occupied terrain, then update facing, position and room. C = landed.
.proc try_land
    lda zA2
    sta mv_nx
    lda zA3
    sta mv_ny
    jsr cell_free
    bcc no
    jsr face_step
    ldx think_i
    lda mv_nx
    sta unit_x,x
    lda mv_ny
    sta unit_y,x
    sta zA1
    lda mv_nx
    sta zA0
    jsr region_at
    ldx think_i
    sta unit_region,x
    sec
    rts
no:
    clc
    rts
.endproc

;-----------------------------------------------------------------------------
; Convert the proposed movement delta to an eight-way soldier glyph.
.proc face_step
    ldx think_i
    lda mv_nx
    sec
    sbc unit_x,x
    sta zT0
    lda mv_ny
    sec
    sbc unit_y,x
    sta zT1
    lda zT0
    ora zT1
    beq no
    lda zT0
    beq dyonly
    bmi dxn
    lda zT1
    beq oct2
    bmi oct1
    lda #3
    jmp apply_face
oct2:
    lda #2
    jmp apply_face
oct1:
    lda #1
    jmp apply_face
dxn:
    lda zT1
    beq oct6
    bmi oct7
    lda #5
    jmp apply_face
oct6:
    lda #6
    jmp apply_face
oct7:
    lda #7
    jmp apply_face
dyonly:
    lda zT1
    bmi oct0
    lda #4
    jmp apply_face
oct0:
    lda #0
    jmp apply_face
no:
    rts
.endproc

;-----------------------------------------------------------------------------
; Apply octant A (0..7), adding the appropriate player/enemy glyph bank.
.proc apply_face
    cmp #8
    bcs done
    sta zT0
    ldx think_i
    lda unit_section,x
    cmp #LETTER_MAX
    bcc pbase
    lda #8
    bne add
pbase:
    lda #0
add:
    clc
    adc zT0
    sta unit_glyph,x
done:
    rts
.endproc

;-----------------------------------------------------------------------------
; Translate cardinal A into an eight-way glyph, ignoring FACE_NONE.
.proc face_slot
    cmp #FACE_N
    bne e
    lda #0
    jmp apply_face
e:
    cmp #FACE_E
    bne s
    lda #2
    jmp apply_face
s:
    cmp #FACE_S
    bne w
    lda #4
    jmp apply_face
w:
    cmp #FACE_W
    bne no
    lda #6
    jmp apply_face
no:
    rts
.endproc

;-----------------------------------------------------------------------------
; Decode hard/exclusive cover facing, or derive soft cover facing from the section front.
.proc cover_look
    cmp #NONE
    beq none
    cmp #COVER_MAX
    bcs sc
    cmp rom_cover_count
    bcs none
    tax
    lda rom_cover_facing,x
    jmp tag
sc:
    sec
    sbc #COVER_MAX
    cmp rom_scout_count
    bcs none
    tax
    lda rom_scout_facing,x
tag:
    cmp #COVER_HARD_N
    bcc soft
    sec
    sbc #COVER_HARD_N
    clc
    adc #FACE_N
    rts
soft:
    cmp #COVER_SOFT_N
    bcs sf
    cmp #FACE_NONE
    beq sf
    jmp opposite_face
sf:
    jmp section_front
none:
    lda #FACE_NONE
    rts
.endproc

;-----------------------------------------------------------------------------
; Claim an unreserved cover/scout position under think_i after a MOVE arrival.
; cover_taken returns the chip id in zT0; A is scratch on the way out.
.proc occupy_chip
    ldx think_i
    lda unit_cover,x
    cmp #NONE
    bne done
    lda unit_x,x
    sta zA0
    lda unit_y,x
    sta zA1
    jsr chip_at
    cmp #NONE
    beq done
    jsr cover_taken
    bcs done
    lda zT0
    ldx think_i
    jsr cover_put
done:
    rts
.endproc

;-----------------------------------------------------------------------------
; Return the cover/scout ID at zA0,zA1, or NONE when the cell has no position.
.proc chip_at
    ldx #0
n:
    cpx rom_cover_count
    bcs sc
    lda rom_cover_x,x
    cmp zA0
    bne adv
    lda rom_cover_y,x
    cmp zA1
    beq yes
adv:
    inx
    jmp n
yes:
    txa
    rts
sc:
    ldx #0
sn:
    cpx rom_scout_count
    bcs no
    lda rom_scout_x,x
    cmp zA0
    bne sadv
    lda rom_scout_y,x
    cmp zA1
    beq syes
sadv:
    inx
    jmp sn
syes:
    txa
    clc
    adc #COVER_MAX
    rts
no:
    lda #NONE
    rts
.endproc

;-----------------------------------------------------------------------------
; Return the movement delay for think_i: sprint for MOVE, normal pace otherwise.
.proc move_reload
    jsr effective_verb
    cmp #VERB_MOVE
    beq fast
    lda #MOVE_WAIT
    rts
fast:
    lda #MOVE_SPRINT
    rts
.endproc
