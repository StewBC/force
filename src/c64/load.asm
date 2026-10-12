; Read a bounded FMAP v3 bundle, validate its directory, and install typed
; homes. Decoder input may be staged RAM or a quiescent banked record.
;
; map_load reads the PETSCII name at name_ptr / map_len. The boot name
; comes from the catalog. Failure restores banking and shows LOAD ERROR.

.segment "SPARE"

PLANE_BYTES = 3200
GEO_BYTES   = 870
ACT_BYTES   = 640
CHUNK_MAX   = DIRECTORY_MAX

; SETNAM keeps this pointer. The four bytes are the CBM name.
map_len:
    .byte 8
name_ptr:
    .word cat_load_name

end_lo:     .res 1, 0
end_hi:     .res 1, 0
nchunk:     .res 1, 0
found:      .res 1, 0
eidx:       .res 1, 0
hits:       .res 1, 0
paper_held: .res 1, 0
ck_off:     .res 14, 0
ck_len:     .res 14, 0
plen:       .res 2, 0
cnt_spawn:  .res 1, 0
cnt_op:     .res 1, 0
cnt_beat:   .res 1, 0
cnt_watch:  .res 1, 0
cnt_pred:   .res 1, 0
cnt_where:  .res 1, 0
cnt_tmpl:   .res 1, 0

;-----------------------------------------------------------------------------
; Reload a different map. A = name length, X/Y = name pointer.
; Not wired to a key. sei around the load; irq_init and vic_init stay put.
; Does not return if map_load fails.
.proc map_reload
    sei
    sta map_len
    stx name_ptr
    sty name_ptr+1
    lda #0
    sta $D020
    sta $D015
    lda #$0B
    sta $D011
    jsr map_load
    cli
    rts
.endproc

;-----------------------------------------------------------------------------
; Read the current name, place chunks and routing, and clear BSS. Selection
; activation belongs to the caller; no implicit mission-0 initialization.
; Carry clear on success. On failure, does not return.
.proc map_load
    lda #$36
    sta $01
    jsr map_begin
    lda #1
    ldx #8
    ldy #1
    jsr $FFBA
    lda map_len
    ldx name_ptr
    ldy name_ptr+1
    jsr $FFBD
    lda #<TRANSFER_HOME
    sta zDst
    lda #>TRANSFER_HOME
    sta zDst+1
    lda #<(TRANSFER_HOME+TRANSFER_HOME_CAP)
    sta zPtr
    lda #>(TRANSFER_HOME+TRANSFER_HOME_CAP)
    sta zPtr+1
    jsr read_file
    stx end_lo
    sty end_hi
    bcc loaded
    cmp #$04
    beq missing
    jmp fail2
missing:
    jmp fail1
loaded:
    lda end_hi
    cmp #$D0
    bcs bad_end
    cmp #$A0
    bcc bad_end
    bne end_rng
    lda end_lo
    cmp #$42
    bcs end_rng
bad_end:
    jmp fail3
end_rng:
    jsr validate_map_integrity
    lda $A019
    cmp #CHUNK_MAX+1
    bcc cnt_cap
    jmp fail5
cnt_cap:
    cmp #0
    bne cnt_nz
    jmp fail5
cnt_nz:
    sta nchunk
    asl
    sta zT0
    asl
    asl
    clc
    adc zT0
    clc
    adc #26
    sta zT0
    lda #0
    sta zT1
    sec
    lda end_lo
    sbc zT0
    lda end_hi
    sbc #$A0
    bcs idx_fit
    jmp fail3
idx_fit:
    lda #$00
    sta zSrc
    lda #$A0
    sta zSrc+1
    lda #<INDEX_HOME
    sta zDst
    lda #>INDEX_HOME
    sta zDst+1
    jsr memmove
    lda INDEX_HOME
    cmp #$46
    bne bad_magic
    lda INDEX_HOME+1
    cmp #$4D
    bne bad_magic
    lda INDEX_HOME+2
    cmp #$41
    bne bad_magic
    lda INDEX_HOME+3
    cmp #$50
    bne bad_magic
    lda INDEX_HOME+4
    cmp #3
    beq magic_ok
bad_magic:
    jmp fail4
magic_ok:
    jsr validate_map_header
    lda INDEX_HOME+8
    cmp #<LAYOUT_ID
    bne bad_magic
    lda INDEX_HOME+9
    cmp #>LAYOUT_ID
    bne bad_magic
    lda INDEX_HOME+24
    cmp #17
    bcc cont_ok
    jmp fail5
cont_ok:
    jsr validate_map_extents
    lda #0
    sta eidx
entry:
    lda eidx
    cmp nchunk
    bcc :+
    jmp entries_done
:
    jsr set_entry_ptr
    ldy #1
    lda (zPtr),y
    and #$FE
    beq flags_ok
    jmp fail5
flags_ok:
    jsr chunk_past
    bcc inside
    jmp fail5
inside:
    ldy #0
    lda (zPtr),y
    bne nonzero_chunk
    jmp fail5
nonzero_chunk:
    cmp #MAP_SCHEMA_COUNT+1
    bcc supported_chunk
    jmp fail5
supported_chunk:
    tax
    dex
    lda bit_tab,x
    and found
    bne dup
    txa
    pha
    cmp #6
    bne bank_id_done
    jsr allow_bank_validator
    jmp accepted
bank_id_done:
    cmp #5
    bne :+
    jsr allow_program
    jmp accepted
:
    cmp #4
    bne :+
    jsr allow_routes
    jmp accepted
:
    cmp #2
    bcc low_id
    cpx #3
    beq id_paper_d
    lda #<rom_tiles
    ldy #>rom_tiles
    bne have_d
id_paper_d:
    lda #<rom_paper
    ldy #>rom_paper
have_d:
    sta zT4
    sty zT5
    jsr allow_plane
    jmp accepted
low_id:
    cmp #0
    bne id_mis_a
    jsr allow_geo
    jmp accepted
id_mis_a:
    jsr allow_mis
accepted:
    pla
    tax
    lda bit_tab,x
    ora found
    sta found
    jsr store_slot
    jmp next_entry
bit_tab:
    .byte $01, $02, $04, $08, $10, $20, $40
dup:
    jmp fail5
next_entry:
    inc eidx
    jmp entry
entries_done:
    lda nchunk
    sec
    sbc #1
    jsr set_entry_ptr
    jsr chunk_past
    bcs end_bad
    lda zT0
    cmp end_lo
    bne end_bad
    lda zT1
    cmp end_hi
    beq end_match
end_bad:
    jmp fail3
end_match:
    lda found
    and #$70
    cmp #$70
    bne miss_req
    lda found
    and #$01
    beq miss_req
    lda found
    and #$04
    beq miss_req
    lda found
    and #$08
    beq miss_req
    lda INDEX_HOME+24
    bne mis_opt
    lda found
    and #$02
    beq miss_req
mis_opt:
    ldx #6
    jsr load_slot_src
    lda #<BANK_VALIDATION_HOME
    sta zDst
    lda #>BANK_VALIDATION_HOME
    sta zDst+1
    jsr memmove
    lda found
    and #$02
    beq no_mis
    ldx #1
    jsr load_slot_src
    lda #<COLLECTION_HOME
    sta zDst
    lda #>COLLECTION_HOME
    sta zDst+1
    jsr memmove
no_mis:
    ldx #0
    jsr load_slot_src
    lda #<GEO_IMAGE
    sta zDst
    lda #>GEO_IMAGE
    sta zDst+1
    jsr memmove
    jsr prepare_routes
    jsr place_planes
    jsr finish_geometry
    jsr clear_bss
    jsr install_routes
    clc
    rts
miss_req:
    jmp fail5
.endproc

; A = status. Stored before the spin so a break on load_fail sees it.
fail1:
    lda #1
    bne fail_enter
fail2:
    lda #2
    bne fail_enter
fail3:
    lda #3
    bne fail_enter
fail4:
    lda #4
    bne fail_enter
fail5:
    lda #5
    bne fail_enter
fail6:
    lda #6
    bne fail_enter
fail7:
    lda #7
    bne fail_enter
fail_enter:
    pha
    lda bank_active
    beq :+
    jsr bank_leave
:
    pla
    sta LOAD_STATUS
    jsr show_load_error
    lda #$02
    sta $D020
load_fail:
    jsr load_error_key
    beq load_fail
error_wait_return:
    jsr load_error_key
    bne error_wait_return
    jmp error_menu_return

;-----------------------------------------------------------------------------
; X = mission index. Carry clear after a scatter, or set if X is past
; mission_count. A count or a body that is not packed_len does not return.
.proc mission_activate
    jmp ma_gate
ma_mset:
    stx zR0
    lda INDEX_HOME+6
    sta zA0
    cpx zA0
    bcc ma_go
    sec
    rts
ma_go:
    jsr bank_enter
    lda COLLECTION_HOME
    cmp INDEX_HOME+6
    bne ma_invalid
    lda COLLECTION_HOME+1
    cmp #1
    bne ma_invalid
    lda COLLECTION_HOME+2
    cmp #<LAYOUT_ID
    bne ma_invalid
    lda COLLECTION_HOME+3
    cmp #>LAYOUT_ID
    bne ma_invalid
    lda COLLECTION_HOME+4
    cmp ck_len+2
    bne ma_invalid
    lda COLLECTION_HOME+5
    cmp ck_len+3
    bne ma_invalid
    ; Directory ordinal -> ten-byte entry; count capped by map validation.
    lda zR0
    asl
    sta zT0
    asl
    asl
    clc
    adc zT0
    adc #6
    sta zPtr
    lda #>COLLECTION_HOME
    adc #0
    sta zPtr+1
    ldy #9
ma_entry:
    lda (zPtr),y
    sta mission_entry,y
    dey
    bpl ma_entry
    jsr prepare_mission
    jsr bank_leave
    lda #<PACK_HOME
    sta zPtr
    lda #>PACK_HOME
    sta zPtr+1
    jmp ma_fit
ma_invalid:
    jmp fail7
ma_fit:
    lda plen+1
    bne ma_has7
    lda plen
    cmp #7
    bcs ma_has7
    jmp fail7
ma_has7:
    ldy #6
    lda (zPtr),y
    cmp #SPAWN_MAX+1
    bcc :+
    jmp fail7
:
    sta cnt_spawn
    lda #0
    sta zT0
    sta zT1
    lda cnt_spawn
    sta zA0
    lda #3
    sta zA1
    jsr add_times
    clc
    lda zT0
    adc #7
    sta zA1
    clc
    lda zA1
    adc #13
    sta zT0
    lda #0
    adc #0
    sta zT1
    lda plen+1
    cmp zT1
    bcc :+
    bne ma_counts
    lda plen
    cmp zT0
    bcs ma_counts
:
    jmp fail7
ma_counts:
    ldy zA1
    ldx #0
ma_capl:
    lda (zPtr),y
    cmp cap_tab,x
    bcc ma_capok
    jmp fail7
ma_capok:
    sta cnt_op,x
    iny
    inx
    cpx #6
    bne ma_capl
    lda #20
    sta zT0
    lda #0
    sta zT1
    ldx #0
ma_sz:
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
    bne ma_sz
    lda zT0
    cmp plen
    bne :+
    lda zT1
    cmp plen+1
    beq ma_place
:
    jmp fail7
ma_place:
    lda #<rom_play_x
    sta zDst
    lda #>rom_play_x
    sta zDst+1
    lda #<ACT_BYTES
    sta zT0
    lda #>ACT_BYTES
    sta zT1
    jsr zero_len
    lda zPtr
    sta zSrc
    lda zPtr+1
    sta zSrc+1
    lda #<rom_play_x
    sta zDst
    lda #>rom_play_x
    sta zDst+1
    lda #7
    sta zT0
    lda #0
    sta zT1
    jsr memmove
    clc
    lda zPtr
    adc #7
    sta zPtr
    bcc ma_sp
    inc zPtr+1
ma_sp:
    lda #<spawn_tab
    sta zT4
    lda #>spawn_tab
    sta zT5
    lda #1
    sta zR0
    jsr apply_groups
    lda zPtr
    sta zSrc
    lda zPtr+1
    sta zSrc+1
    lda #<sc_op_count
    sta zDst
    lda #>sc_op_count
    sta zDst+1
    lda #13
    sta zT0
    lda #0
    sta zT1
    jsr memmove
    clc
    lda zPtr
    adc #13
    sta zPtr
    bcc ma_ops
    inc zPtr+1
ma_ops:
    lda #<rest_tab
    sta zT4
    lda #>rest_tab
    sta zT5
    lda #6
    sta zR0
    jsr apply_groups
    jsr mission_publish
    clc
    rts
.endproc

;-----------------------------------------------------------------------------
; Check the geometry image, then zero $B900 and scatter. Does not return
; if a count or the walked size is wrong. Trashes zero page.
.proc geo_expand
    ; Width 1..MAP_W and height 1..MAP_ROWS. Zero and the next value fail.
    lda GEO_IMAGE
    beq geo_bad
    cmp #MAP_W+1
    bcs geo_bad
    lda GEO_IMAGE+1
    beq geo_bad
    cmp #MAP_ROWS+1
    bcc geo_size
geo_bad:
    jmp fail7
geo_size:
    lda GEO_IMAGE+2
    cmp #ROOM_MAX+1
    bcc :+
    jmp fail7
:
    lda GEO_IMAGE+3
    cmp #COVER_MAX+1
    bcc :+
    jmp fail7
:
    lda GEO_IMAGE+4
    cmp #PORTAL_MAX+1
    bcc :+
    jmp fail7
:
    lda GEO_IMAGE+5
    cmp #SCOUT_MAX+1
    bcc :+
    jmp fail7
:
    lda #6
    sta zT0
    lda #0
    sta zT1
    lda GEO_IMAGE+2
    sta zA0
    lda #13
    sta zA1
    jsr add_times
    lda GEO_IMAGE+3
    sta zA0
    lda #4
    sta zA1
    jsr add_times
    lda GEO_IMAGE+4
    sta zA0
    lda #2
    sta zA1
    jsr add_times
    lda GEO_IMAGE+5
    sta zA0
    lda #3
    sta zA1
    jsr add_times
    jsr deck_geo_size
    lda zT0
    cmp ck_len
    bne :+
    lda zT1
    cmp ck_len+1
    beq geo_ok
:
    jmp fail7
geo_ok:
    lda #<rom_map_w
    sta zDst
    lda #>rom_map_w
    sta zDst+1
    lda #<GEO_BYTES
    sta zT0
    lda #>GEO_BYTES
    sta zT1
    jsr zero_len
    lda #<GEO_IMAGE
    sta zSrc
    lda #>GEO_IMAGE
    sta zSrc+1
    lda #<rom_map_w
    sta zDst
    lda #>rom_map_w
    sta zDst+1
    lda #6
    sta zT0
    lda #0
    sta zT1
    jsr memmove
    lda #<(GEO_IMAGE+6)
    sta zPtr
    lda #>(GEO_IMAGE+6)
    sta zPtr+1
    lda #<geo_tab
    sta zT4
    lda #>geo_tab
    sta zT5
    lda #4
    sta zR0
    jsr apply_groups
    jmp deck_geo_copy
.endproc

;-----------------------------------------------------------------------------
; Put tiles at rom_tiles and paper at rom_paper. A raw source that misses
; the dest is copied straight there. Two sources still inside the tile
; dest are staged together when their lengths sum to at most 4096.
.proc place_planes
    lda #0
    sta hits
    sta paper_held
    ldx #2
    jsr load_slot_src
    jsr tile_span
    jsr ranges_hit
    bcc pp_tile_no
    lda #1
    sta hits
pp_tile_no:
    ldx #3
    jsr load_slot_src
    jsr tile_span
    jsr ranges_hit
    bcc pp_paper_no
    lda hits
    ora #2
    sta hits
pp_paper_no:
    lda hits
    cmp #3
    bne pp_split
    jmp stage_both
pp_split:
    lda hits
    and #1
    beq pp_tile_dir
    ldx #2
    jsr load_slot_src
    jsr move_to_scratch
    jsr scratch_to_tiles
    jmp pp_paper
pp_tile_dir:
    lda hits
    and #2
    beq pp_tile_plain
    ldx #3
    jsr load_slot_src
    jsr move_to_scratch
    lda #1
    sta paper_held
pp_tile_plain:
    ; Source misses the tile dest, so decode or copy it in place.
    ldx #2
    jsr load_slot_src
    lda #<rom_tiles
    sta zDst
    lda #>rom_tiles
    sta zDst+1
    ldy #4
    jsr emit_staged
pp_paper:
    lda paper_held
    beq pp_paper_live
    jmp scratch_to_paper
pp_paper_live:
    ldx #3
    jsr load_slot_src
    jsr paper_span
    jsr ranges_hit
    bcc pp_paper_dir
    ldx #3
    jsr load_slot_src
    jsr move_to_scratch
    jmp scratch_to_paper
pp_paper_dir:
    ; Source misses the paper dest. zSrc stays on that live source.
    ldx #3
    jsr load_slot_src
    jmp paper_emit
.endproc

;-----------------------------------------------------------------------------
; A = entry index. zPtr points at that 10-byte record in the index copy.
; Trashes A, zT0, zT1.
.segment "BRIDGE_DRAW"
.proc set_entry_ptr
    sta zT0
    asl
    sta zT1
    asl
    asl
    clc
    adc zT1
    clc
    adc #26
    clc
    adc #<INDEX_HOME
    sta zPtr
    lda #>INDEX_HOME
    adc #0
    sta zPtr+1
    rts
.endproc
.segment "SPARE"

;-----------------------------------------------------------------------------
; Carry set when the entry at zPtr ends past the loaded image.
; zA0/zA1 = offset, zA2/zA3 = src_len, zT0/zT1 = absolute end when inside.
.proc chunk_past
    ldy #2
    lda (zPtr),y
    sta zA0
    iny
    lda (zPtr),y
    sta zA1
    ldy #4
    lda (zPtr),y
    sta zA2
    iny
    lda (zPtr),y
    sta zA3
    clc
    lda zA0
    adc zA2
    sta zT0
    lda zA1
    adc zA3
    sta zT1
    bcs cp_out
    clc
    lda zT0
    adc #$00
    sta zT0
    lda zT1
    adc #$A0
    sta zT1
    bcs cp_out
    lda end_hi
    cmp zT1
    bcc cp_out
    bne cp_in
    lda end_lo
    cmp zT0
    bcc cp_out
cp_in:
    clc
    rts
cp_out:
    sec
    rts
.endproc

;-----------------------------------------------------------------------------
; X = slot 0..3. Stores zA0/zA1 offset and zA2/zA3 length. Trashes X.
.proc store_slot
    txa
    asl
    tax
    lda zA0
    sta ck_off,x
    lda zA1
    sta ck_off+1,x
    lda zA2
    sta ck_len,x
    lda zA3
    sta ck_len+1,x
    rts
.endproc

;-----------------------------------------------------------------------------
; X = slot. zSrc = $A000 + offset, zT0/zT1 = src_len. Trashes A, X.
.proc load_slot_src
    txa
    asl
    tax
    lda ck_off,x
    sta zSrc
    lda ck_off+1,x
    clc
    adc #$A0
    sta zSrc+1
    lda ck_len,x
    sta zT0
    lda ck_len+1,x
    and #$7F
    sta zT1
    rts
.endproc

;-----------------------------------------------------------------------------
; Geometry allowlist: dest rom_map_w, dest_len 870, src_len <= 870.
; Does not return on a mismatch. Preserves zA0-zA3 and zPtr.
.segment "DECK"
.proc allow_geo
    ldy #6
    lda (zPtr),y
    cmp #<rom_map_w
    bne ag_no
    iny
    lda (zPtr),y
    cmp #>rom_map_w
    bne ag_no
    ldy #8
    lda (zPtr),y
    cmp #<GEO_BYTES
    bne ag_no
    iny
    lda (zPtr),y
    cmp #>GEO_BYTES
    bne ag_no
    lda zA3
    cmp #>GEO_BYTES
    bcc ag_yes
    bne ag_no
    lda zA2
    cmp #<(GEO_BYTES+1)
    bcs ag_no
ag_yes:
    rts
ag_no:
    jmp fail5
.endproc

;-----------------------------------------------------------------------------
; zT6 * zT7 -> zT2/zT3. Height is at most 40. Product 0 or above 3200
; does not return. $0C80 is legal. Preserves zA0-zA3, zPtr, zT4, zT5.
.proc mul_wh
    lda #0
    sta zT2
    sta zT3
    ldx zT7
    beq mw_fail
mw_add:
    clc
    lda zT2
    adc zT6
    sta zT2
    bcc mw_nc
    inc zT3
mw_nc:
    dex
    bne mw_add
    lda zT2
    ora zT3
    beq mw_fail
    lda zT3
    cmp #$0C
    bcc mw_ok
    bne mw_fail
    lda zT2
    cmp #$81
    bcs mw_fail
mw_ok:
    rts
mw_fail:
    jmp fail5
.endproc

; rom_map_w * rom_map_h -> zT2/zT3. Same failures as mul_wh.
.proc plane_product
    lda rom_map_w
    sta zT6
    lda rom_map_h
    sta zT7
    jmp mul_wh
.endproc

; Tight plane size from the schema-1 payload still sitting at $A000.
; Directory walk has not expanded geometry, so rom_map_w is not live.
; Product in zT2/zT3. Restores zPtr. Missing schema or a non-zero codec
; does not return. Preserves zA0-zA3.
.proc plane_span
    lda zPtr
    pha
    lda zPtr+1
    pha
    ldx #0
ps_next:
    cpx nchunk
    bcs ps_bad
    txa
    jsr set_entry_ptr
    ldy #0
    lda (zPtr),y
    cmp #1
    beq ps_hit
    inx
    bne ps_next
ps_hit:
    ldy #1
    lda (zPtr),y
    bne ps_bad
    ldy #2
    lda (zPtr),y
    sta zT0
    iny
    lda (zPtr),y
    clc
    adc #>TRANSFER_HOME
    sta zPtr+1
    lda zT0
    sta zPtr
    ldy #0
    lda (zPtr),y
    sta zT6
    iny
    lda (zPtr),y
    sta zT7
    jsr mul_wh
    pla
    sta zPtr+1
    pla
    sta zPtr
    rts
ps_bad:
    pla
    pla
    jmp fail5
.endproc

;-----------------------------------------------------------------------------
; Collection allowlist: banked home and separately generated capacity.
; This does not constrain expanded missions; prepare_mission checks the
; 597-byte workspace independently. Preserves zA0-zA3 and zPtr.
.segment "SPARE"
.proc allow_mis
    ldy #6
    lda (zPtr),y
    cmp #<COLLECTION_HOME
    bne am_no
    iny
    lda (zPtr),y
    cmp #>COLLECTION_HOME
    bne am_no
    ldy #8
    lda (zPtr),y
    cmp zA2
    bne am_no
    iny
    lda (zPtr),y
    cmp zA3
    bne am_no
    lda zA3
    cmp #>(COLLECTION_HOME_CAP + 1)
    bcc am_yes
    bne am_no
    lda zA2
    cmp #<(COLLECTION_HOME_CAP + 1)
    bcs am_no
am_yes:
    jsr validate_collection_extent
    rts
am_no:
    jmp fail5
.endproc

;-----------------------------------------------------------------------------
; Plane allowlist. zT4/zT5 is the dest. dest_len is 3200.
; Raw src_len is width*height from the schema-1 payload, not rom_map_w.
; LZSS src_len is <= 4096, and bit 7 of zA3 marks it.
; Preserves zA0-zA2. zA3 gains the flag bit.
.proc allow_plane
    ldy #6
    lda (zPtr),y
    cmp zT4
    bne ap_no
    iny
    lda (zPtr),y
    cmp zT5
    bne ap_no
    ldy #8
    lda (zPtr),y
    cmp #<PLANE_BYTES
    bne ap_no
    iny
    lda (zPtr),y
    cmp #>PLANE_BYTES
    bne ap_no
    ldy #1
    lda (zPtr),y
    lsr
    bcc ap_raw
    lda zA3
    ora #$80
    sta zA3
    and #$7F
    cmp #$10
    bcc ap_yes
    bne ap_no
    lda zA2
    beq ap_yes
    ; Length is past 4096. Bit 7 is set, so the raw compare below fails.
ap_raw:
    jsr plane_span
    lda zA2
    cmp zT2
    bne ap_no
    lda zA3
    cmp zT3
    bne ap_no
ap_yes:
    rts
ap_no:
    jmp fail5
.endproc

;-----------------------------------------------------------------------------
; Move zT0/zT1 bytes from zSrc to zDst, low to high. Length 0 returns.
; None of these copies overlap, so there is no backward walk.
; Trashes A, X, Y, zSrc, zDst, zT0, zT1.
.proc memmove
    lda zT0
    ora zT1
    beq mv_done
    jmp copy_bytes
mv_done:
    rts
.endproc

; Stage the source in zSrc (length zT0/zT1) at $C000.
.proc move_to_scratch
    lda #<SCRATCH_AT
    sta zDst
    lda #>SCRATCH_AT
    sta zDst+1
    jmp memmove
.endproc

;-----------------------------------------------------------------------------
; Carry set if [zSrc, +zT0/1) intersects [zDst, +zT2/3).
; A zero length does not. Preserves the four pointers. Trashes zA0-zA3.
.proc ranges_hit
    lda zT0
    ora zT1
    beq rh_no
    lda zT2
    ora zT3
    beq rh_no
    clc
    lda zSrc
    adc zT0
    sta zA0
    lda zSrc+1
    adc zT1
    sta zA1
    clc
    lda zDst
    adc zT2
    sta zA2
    lda zDst+1
    adc zT3
    sta zA3
    lda zSrc+1
    cmp zA3
    bcc rh_a
    bne rh_no
    lda zSrc
    cmp zA2
    bcs rh_no
rh_a:
    lda zDst+1
    cmp zA1
    bcc rh_yes
    bne rh_no
    lda zDst
    cmp zA0
    bcs rh_no
rh_yes:
    sec
    rts
rh_no:
    clc
    rts
.endproc

;-----------------------------------------------------------------------------
; Write 0 to zT0/zT1 bytes at zDst. Trashes A, Y, zDst, zT0, zT1.
.proc zero_len
    ldy #0
zl:
    lda zT0
    ora zT1
    beq zd
    lda #0
    sta (zDst),y
    inc zDst
    bne zs
    inc zDst+1
zs:
    lda zT0
    bne zt
    dec zT1
zt:
    dec zT0
    jmp zl
zd:
    rts
.endproc

;-----------------------------------------------------------------------------
; zT0/zT1 += zA0 * zA1. zA0 is kept. Overflow does not return (status 7).
.proc add_times
    ; zT0/zT1 += zA0 * zA1. zA0 is kept. zA1 is consumed. Overflow is status 7.
at_loop:
    lda zA1
    beq at_done
    clc
    lda zT0
    adc zA0
    sta zT0
    bcc at_nc
    inc zT1
    bne at_nc
    jmp fail7
at_nc:
    dec zA1
    jmp at_loop
at_done:
    rts
.endproc

;-----------------------------------------------------------------------------
; Next byte of the mission chunk into A. zPtr advances, zT2/zT3 is the
; bytes still unread including this one. Empty does not return.
;-----------------------------------------------------------------------------
; Walk a group table. zT4/zT5 points at it, zR0 is the count. Each record is
; count-address, stride, field count, dest. zPtr advances through columns.
; Trashes A, X, Y, zA0-zA3, zT0-zT3, zT6, zT7, zSrc, zDst, zPtr2.
.proc apply_groups
ag:
    lda zR0
    beq ag_done
    ldy #0
    lda (zT4),y
    sta zT6
    iny
    lda (zT4),y
    sta zT7
    iny
    lda (zT4),y
    sta zA1
    iny
    lda (zT4),y
    sta zA2
    iny
    lda (zT4),y
    sta zPtr2
    iny
    lda (zT4),y
    sta zPtr2+1
    ldy #0
    lda (zT6),y
    sta zA0
    jsr scatter
    clc
    lda zT4
    adc #6
    sta zT4
    bcc ag_nc
    inc zT5
ag_nc:
    dec zR0
    jmp ag
ag_done:
    rts
.endproc

cap_tab:
    .byte OP_MAX+1, BEAT_MAX+1, WATCH_MAX+1, PRED_MAX+1, WHERE_MAX+1, TMPL_MAX+1
mul_tab:
    .byte 3, 4, 1, 5, 4, 3, 5
spawn_tab:
    .word cnt_spawn
    .byte 32, 3
    .word rom_spawn_x
rest_tab:
    .word cnt_op
    .byte 64, 4
    .word sc_op_code
    .word cnt_beat
    .byte 12, 1
    .word sc_beat_pc
    .word cnt_watch
    .byte 8, 5
    .word sc_watch_pred0
    .word cnt_pred
    .byte 32, 4
    .word sc_pred_kind
    .word cnt_where
    .byte 16, 3
    .word sc_where_kind
    .word cnt_tmpl
    .byte 8, 5
    .word sc_spawn_n
geo_tab:
    .word GEO_IMAGE+2
    .byte 16, 13
    .word rom_room_x0
    .word GEO_IMAGE+3
    .byte 128, 4
    .word rom_cover_x
    .word GEO_IMAGE+4
    .byte 24, 2
    .word rom_portal_x
    .word GEO_IMAGE+5
    .byte 32, 3
    .word rom_scout_x

;-----------------------------------------------------------------------------
; Copy zA0-byte columns from zPtr into zPtr2 slots of stride zA1.
; zA2 is the field count. Both cursors advance. Trashes A, zSrc, zDst, zT0, zT1.
.proc scatter
sc_loop:
    lda zA2
    beq sc_done
    lda zPtr
    sta zSrc
    lda zPtr+1
    sta zSrc+1
    lda zPtr2
    sta zDst
    lda zPtr2+1
    sta zDst+1
    lda zA0
    sta zT0
    lda #0
    sta zT1
    lda zA0
    pha
    lda zA1
    pha
    lda zA2
    pha
    jsr memmove
    pla
    sta zA2
    pla
    sta zA1
    pla
    sta zA0
    clc
    lda zPtr
    adc zA0
    sta zPtr
    bcc sc_s
    inc zPtr+1
sc_s:
    clc
    lda zPtr2
    adc zA1
    sta zPtr2
    bcc sc_d
    inc zPtr2+1
sc_d:
    dec zA2
    jmp sc_loop
sc_done:
    rts
.endproc

; zDst/zT2/zT3 = tile home. Preserves zSrc and zT0/zT1.
.proc tile_span
    lda #<rom_tiles
    sta zDst
    lda #>rom_tiles
    sta zDst+1
    jmp span_len
.endproc

; zDst/zT2/zT3 = paper home. Preserves zSrc and zT0/zT1.
.proc paper_span
    lda #<rom_paper
    sta zDst
    lda #>rom_paper
    sta zDst+1
    jmp span_len
.endproc

.proc span_len
    lda #<PLANE_BYTES
    sta zT2
    lda #>PLANE_BYTES
    sta zT3
    rts
.endproc

; Staged tile bytes at $C000 onto the tile home. LZSS when the length's
; high bit is set; otherwise a raw copy of the tight plane.
.proc scratch_to_tiles
    lda #<SCRATCH_AT
    sta zSrc
    lda #>SCRATCH_AT
    sta zSrc+1
    lda #<rom_tiles
    sta zDst
    lda #>rom_tiles
    sta zDst+1
    ldy #4
    jmp emit_staged
.endproc

; Staged paper bytes at $C000 onto the paper home.
.proc scratch_to_paper
    lda #<SCRATCH_AT
    sta zSrc
    lda #>SCRATCH_AT
    sta zSrc+1
    jmp paper_emit
.endproc

; zSrc already points at the paper bytes, staged or still in the image.
.proc paper_emit
    lda #<rom_paper
    sta zDst
    lda #>rom_paper
    sta zDst+1
    ldy #6
    jmp emit_staged
.endproc

; Y indexes ck_len for this plane. Bit 7 of the high byte selects LZSS.
; A raw length is stored without that bit, so the same bytes are the copy.
.proc emit_staged
    lda ck_len,y
    sta zT0
    lda ck_len+1,y
    bmi es_lz
    sta zT1
    jmp memmove
es_lz:
    and #$7F
    sta zT1
    jmp lzss_decode
.endproc

; Both sources still lie in the tile dest. Park tiles at $C000 and paper
; right after, then expand. A running end past $D000 is status 7.
.proc stage_both
    lda #<SCRATCH_AT
    sta zDst
    lda #>SCRATCH_AT
    sta zDst+1
    ldx #2
sb_loop:
    txa
    pha
    jsr load_slot_src
    clc
    lda zDst
    adc zT0
    sta zA0
    lda zDst+1
    adc zT1
    sta zA1
    cmp #$D0
    bcc sb_fit
    bne sb_bad
    lda zA0
    beq sb_fit
sb_bad:
    jmp fail7
sb_fit:
    jsr memmove
    lda zA0
    sta zDst
    lda zA1
    sta zDst+1
    pla
    tax
    inx
    cpx #3
    bne sb_next
    lda zDst
    pha
    lda zDst+1
    pha
sb_next:
    cpx #4
    bne sb_loop
    jsr scratch_to_tiles
    pla
    sta zSrc+1
    pla
    sta zSrc
    jmp paper_emit
.endproc

; Next source byte in A. A dry source is status 6. Preserves X.
.proc lz_take
    lda zT0
    ora zT1
    beq lz_bad
    ldy #0
    lda (zSrc),y
    inc zSrc
    bne :+
    inc zSrc+1
:
    pha
    lda zT0
    bne :+
    dec zT1
:
    dec zT0
    pla
    rts
.endproc

; Status 6. Sits here so the decoder's bad-offset branch stays in range.
lz_bad:
    jmp fail6

;-----------------------------------------------------------------------------
; zSrc/zSrc+1 source, zDst/zDst+1 dest, zT0/zT1 src_len.
; Output length is rom_map_w * rom_map_h. geo_expand wrote those before
; place_planes, and stage_routes has already overwritten GEO_IMAGE.
; Called only after step 9 has staged this source into $C000-$CFFF.
; Carry clear if exactly that many bytes were written. Short, long, or a
; bad offset does not return (status 6). X counts bytes left in this match.
; Flag bits are LSB first. A spent buffer refills; the sentinel shifts out
; after eight bits and is not itself a token.
; Trashes A, X, Y, zSrc, zDst, zPtr, zA1-zA3, zT2-zT5.
.proc lzss_decode
    jsr plane_product
    jmp lzss_sized
.endproc

; Generic bounded decoder: zT2/3 exact output length, zT0/1 input length.
.proc lzss_sized
    lda zDst
    sta zT4
    clc
    adc zT2
    sta zT2
    lda zDst+1
    sta zT5
    adc zT3
    sta zT3
    lda #0
    sta zA1
    tax
lz_loop:
    lda zDst
    cmp zT2
    bne lz_go
    lda zDst+1
    cmp zT3
    bne lz_go
    txa
    bne lz_bad
    lda zT0
    ora zT1
    bne lz_bad
    clc
    rts
lz_go:
    txa
    bne lz_copy
    lsr zA1
    bne lz_have
    jsr lz_take
    sec
    ror
    sta zA1
lz_have:
    bcs lz_lit
    jsr lz_take
    sta zA2
    jsr lz_take
    pha
    and #$0F
    clc
    adc #3
    tax
    pla
    lsr
    lsr
    lsr
    lsr
    sta zA3
    ora zA2
    beq lz_bad
    sec
    lda zDst
    sbc zA2
    sta zPtr
    lda zDst+1
    sbc zA3
    sta zPtr+1
    lda zPtr
    cmp zT4
    lda zPtr+1
    sbc zT5
    bcc lz_bad
lz_copy:
    ldy #0
    lda (zPtr),y
    sta (zDst),y
    inc zDst
    bne :+
    inc zDst+1
:
    inc zPtr
    bne :+
    inc zPtr+1
:
    dex
    jmp lz_loop
lz_lit:
    jsr lz_take
    ldy #0
    sta (zDst),y
    inc zDst
    bne :+
    inc zDst+1
:
    jmp lz_loop
.endproc

.include "bank.asm"
.include "mission.asm"

.segment "CODE"
.include "transfer.inc"

.include "validate.asm"

.segment "CODE"
.proc allow_bank_validator
    ldy #1
    lda (zPtr),y
    bne bad
    ldy #6
    lda (zPtr),y
    cmp #<BANK_VALIDATION_HOME
    bne bad
    iny
    lda (zPtr),y
    cmp #>BANK_VALIDATION_HOME
    bne bad
    lda zA2
    cmp #<(bank_validation_end-BANK_VALIDATION_HOME)
    bne bad
    lda zA3
    cmp #>(bank_validation_end-BANK_VALIDATION_HOME)
    bne bad
    ldy #8
    lda (zPtr),y
    cmp zA2
    bne bad
    iny
    lda (zPtr),y
    cmp zA3
    bne bad
    rts
bad:
    jmp fail5
.endproc

.segment "CODE"
; Display the persistent numeric loader category after restoring bank state.
.proc show_load_error
    lda #$36
    sta $01
    lda $DD00
    ora #3
    sta $DD00
    lda #$18
    sta $D018
    lda #$C8
    sta $D016
    lda #$1B
    sta $D011
    ldx #9
message:
    lda load_error_text,x
    sta SCREEN+840,x
    lda #2
    sta COLORRAM+840,x
    dex
    bpl message
    lda LOAD_STATUS
    clc
    adc #$90
    sta SCREEN+851
    lda #2
    sta COLORRAM+851
    rts
.endproc
load_error_text: .byte $AC,$AF,$A1,$A4,$80,$A5,$B2,$B2,$AF,$B2

.segment "CODE"
selected_mission: .byte $FF
active_mission: .byte $FF
.proc quiesce_mission
    lda #0
    sta objective_ptr
    sta objective_ptr+1
    sta objective_ttl
    lda #$FF
    sta active_mission
    rts
.endproc
.proc validate_map_header
    lda INDEX_HOME+5
    cmp #1
    bne bad
    lda INDEX_HOME+6
    beq bad
    cmp #17
    bcs bad
    lda INDEX_HOME+7
    ora INDEX_HOME+24
    bne bad
    lda end_lo
    cmp INDEX_HOME+12
    bne bad
    lda end_hi
    sec
    sbc #>TRANSFER_HOME
    cmp INDEX_HOME+13
    bne bad
    lda INDEX_HOME+11
    bne bad
    ldx #23
reserved:
    lda INDEX_HOME,x
    bne bad
    dex
    cpx #13
    bne reserved
    rts
bad:
    jmp fail5
.endproc

.segment "CODE"
.proc mission_publish
    lda selected_mission
    sta active_mission
    rts
.endproc

.segment "CODE"
; A replacement invalidates the old map before any transfer/destination write.
.proc map_begin
    lda #$FF
    sta resident
    lda #0
    sta LOAD_STATUS
    sta found
    sta route_ready
    sta route_state
    sta read_extra
    sta read_extra+1
    sta read_clip
    rts
.endproc

; Fresh launch sets record_ready after unpack. The MSET walk stays for map_load.
.proc ma_gate
    stx selected_mission
    lda record_ready
    beq mset
    lda #0
    sta record_ready
    lda #<PACK_HOME
    sta zPtr
    lda #>PACK_HOME
    sta zPtr+1
    jmp mission_activate::ma_fit
mset:
    jmp mission_activate::ma_mset
.endproc

; A = container id 0..15. Refuses, with carry set and no disk read, when
; planes_live is set. in_restart does not grant or refuse the read.
; On success the image is at $E600, resident is the id, and carry is clear.
; The caller unpacks. A short, long, or drive error does not return.
.proc container_load
    sta want_c
    lda planes_live
    beq start
    sec
    rts
start:
    lda #$36
    sta $01
    lda #$FF
    sta resident
    lda #'C'
    sta cat_load_name
    ldx want_c
    lda hex_digits,x
    sta cat_load_name+1
    lda #2
    sta map_len
    lda #0
    sta read_extra
    sta read_extra+1
    lda #1
    sta read_clip
    lda #<TRANSFER_HOME
    sta zDst
    lda #>TRANSFER_HOME
    sta zDst+1
    lda #<(TRANSFER_HOME+TRANSFER_HOME_CAP)
    sta zPtr
    lda #>(TRANSFER_HOME+TRANSFER_HOME_CAP)
    sta zPtr+1
    jsr open_named
    bcs disk_fail
    jsr measure_got
    bcs disk_fail
    jsr learn_extent
    bcs disk_fail
    lda #<COLLECTION_HOME
    sta zDst
    lda #>COLLECTION_HOME
    sta zDst+1
    jsr copy_got
    jsr need_tail
    bcc xor_now
    jsr read_tail
    bcs disk_fail
xor_now:
    jsr xor_container
    bcs disk_fail
    jsr glyph_install
    lda want_c
    sta resident
    clc
    rts
disk_fail:
    lda #$FF
    sta resident
    jmp fail1
.endproc

.proc open_named
    lda #1
    ldx #8
    ldy #1
    jsr $FFBA
    lda map_len
    ldx #<cat_load_name
    ldy #>cat_load_name
    jsr $FFBD
    jsr read_file
    bcs open_bad
    stx end_lo
    sty end_hi
    clc
    rts
open_bad:
    sec
    rts
.endproc

; ctr_got = end - TRANSFER_HOME. Carry set when the end is below the buffer.
; SBC sets C when there was no borrow, so the flag is inverted on the way out.
.proc measure_got
    sec
    lda end_lo
    sbc #<TRANSFER_HOME
    sta ctr_got
    lda end_hi
    sbc #>TRANSFER_HOME
    sta ctr_got+1
    bcc below
    clc
    rts
below:
    sec
    rts
.endproc

; Header is inside the first 6400. Extent <= 6650. Carry set on a bad image.
.proc learn_extent
    lda ctr_got+1
    bne sized
    lda ctr_got
    cmp #28
    bcc bad
sized:
    lda TRANSFER_HOME
    cmp #'F'
    bne bad
    lda TRANSFER_HOME+1
    cmp #'C'
    bne bad
    lda TRANSFER_HOME+2
    cmp #'T'
    bne bad
    lda TRANSFER_HOME+3
    cmp #'R'
    bne bad
    lda TRANSFER_HOME+4
    cmp #1
    bne bad
    lda TRANSFER_HOME+6
    cmp #<LAYOUT_ID
    bne bad
    lda TRANSFER_HOME+7
    cmp #>LAYOUT_ID
    bne bad
    lda TRANSFER_HOME+26
    sta ctr_extent
    lda TRANSFER_HOME+27
    sta ctr_extent+1
    lda ctr_extent+1
    cmp #$1A
    bcs bad
    cmp #$19
    bcc under
    lda ctr_extent
    cmp #$FB
    bcs bad
under:
    lda ctr_extent+1
    cmp #>TRANSFER_HOME_CAP
    bcc small
    bne wide
    lda ctr_extent
    beq small
    bne wide
small:
    lda ctr_got
    cmp ctr_extent
    bne bad
    lda ctr_got+1
    cmp ctr_extent+1
    bne bad
    clc
    rts
wide:
    lda ctr_got
    bne bad
    lda ctr_got+1
    cmp #>TRANSFER_HOME_CAP
    bne bad
    clc
    rts
bad:
    sec
    rts
.endproc

; Carry set when the payload continues past the 6400-byte transfer buffer.
.proc need_tail
    lda ctr_extent+1
    cmp #>TRANSFER_HOME_CAP
    bcc no
    bne yes
    lda ctr_extent
    beq no
yes:
    sec
    rts
no:
    clc
    rts
.endproc

; Pass 1. read_extra skips the 6400 bytes already committed. Clip the tail.
.proc read_tail
    sec
    lda ctr_extent
    sbc #<TRANSFER_HOME_CAP
    sta ctr_tail
    lda ctr_extent+1
    sbc #>TRANSFER_HOME_CAP
    sta ctr_tail+1
    lda #<TRANSFER_HOME_CAP
    sta read_extra
    lda #>TRANSFER_HOME_CAP
    sta read_extra+1
    lda #1
    sta read_clip
    lda #<TRANSFER_HOME
    sta zDst
    lda #>TRANSFER_HOME
    sta zDst+1
    clc
    lda #<TRANSFER_HOME
    adc ctr_tail
    sta zPtr
    lda #>TRANSFER_HOME
    adc ctr_tail+1
    sta zPtr+1
    jsr open_named
    bcs tail_bad
    jsr measure_got
    bcs tail_bad
    lda ctr_got
    cmp ctr_tail
    bne tail_bad
    lda ctr_got+1
    cmp ctr_tail+1
    bne tail_bad
    lda #<(COLLECTION_HOME+TRANSFER_HOME_CAP)
    sta zDst
    lda #>(COLLECTION_HOME+TRANSFER_HOME_CAP)
    sta zDst+1
    jmp copy_got
tail_bad:
    sec
    rts
.endproc

; Copy ctr_got bytes from TRANSFER_HOME to zDst. Bank is open only for the move.
.proc copy_got
    jsr bank_enter
    lda #<TRANSFER_HOME
    sta zSrc
    lda #>TRANSFER_HOME
    sta zSrc+1
    lda ctr_got
    sta zT0
    lda ctr_got+1
    sta zT1
    jsr memmove
    jsr bank_leave
    clc
    rts
.endproc

; CODE ends at the tile window. This cold walk lives in the deck gap
; under the menu index. SPARE has no spare byte. Callers stay in CODE.
.segment "DECK"

; XOR of every container byte is 0. The field itself is included. Banked read.
.proc xor_container
    jsr bank_enter
    lda #<COLLECTION_HOME
    sta zPtr
    lda #>COLLECTION_HOME
    sta zPtr+1
    lda ctr_extent
    sta zT2
    lda ctr_extent+1
    sta zT3
    lda #0
    sta zT4
    ldy #0
walk:
    lda zT2
    ora zT3
    beq done
    lda (zPtr),y
    eor zT4
    sta zT4
    inc zPtr
    bne step
    inc zPtr+1
step:
    lda zT2
    bne dec_lo
    dec zT3
dec_lo:
    dec zT2
    jmp walk
done:
    jsr bank_leave
    lda zT4
    bne bad
    clc
    rts
bad:
    sec
    rts
.endproc

; Biome glyphs, after the XOR and before unpack. The transfer buffer is free.
; A missing file leaves the linked charset. $2400 is not written. The
; remembered name is not BSS, so clear_bss cannot drop it.
.proc glyph_install
    jsr bank_enter
    lda COLLECTION_HOME+9
    sta glyph_len
    cmp #16
    bcc len_ok
    jmp fail1
len_ok:
    ldy #0
copy_name:
    cpy glyph_len
    bcs name_done
    lda COLLECTION_HOME+10,y
    sta glyph_name,y
    iny
    bne copy_name
name_done:
    jsr bank_leave
    lda #$36
    sta $01
    lda glyph_len
    bne have_name
    clc
    rts
have_name:
    cmp installed_len
    bne load_it
    ldy #0
cmp_name:
    cpy glyph_len
    bcs same
    lda glyph_name,y
    cmp installed_name,y
    bne load_it
    iny
    bne cmp_name
same:
    clc
    rts
load_it:
    ldy #0
up:
    cpy glyph_len
    bcs up_done
    lda glyph_name,y
    cmp #'a'
    bcc storeu
    cmp #'z'+1
    bcs storeu
    sec
    sbc #32
storeu:
    sta cat_load_name,y
    iny
    bne up
up_done:
    lda glyph_len
    sta map_len
    lda #0
    sta read_extra
    sta read_extra+1
    lda #1
    sta read_clip
    lda #<TRANSFER_HOME
    sta zDst
    lda #>TRANSFER_HOME
    sta zDst+1
    lda #<(TRANSFER_HOME+1024)
    sta zPtr
    lda #>(TRANSFER_HOME+1024)
    sta zPtr+1
    jsr open_named
    bcs missing
    jsr measure_got
    bcs missing
    lda ctr_got
    bne bad_len
    lda ctr_got+1
    cmp #4
    bne bad_len
    lda #<CHARSET
    sta zDst
    lda #>CHARSET
    sta zDst+1
    jsr copy_got
    ldy #0
remember:
    cpy glyph_len
    bcs remembered
    lda glyph_name,y
    sta installed_name,y
    iny
    bne remember
remembered:
    lda glyph_len
    sta installed_len
missing:
    clc
    rts
bad_len:
    jmp fail1
.endproc

glyph_len: .byte 0
glyph_name: .res 15
installed_len: .byte 0
installed_name: .res 15

; Load BANK once per boot, after the bitmap is off. Destination $E000.
; KERNAL writes there hit the RAM under the ROM, so the bank stays closed.
.proc load_bank
    lda bank_ready
    beq do_load
    rts
do_load:
    lda #$36
    sta $01
    lda #1
    ldx #8
    ldy #1
    jsr $FFBA
    lda #bank_name_len
    ldx #<bank_name
    ldy #>bank_name
    jsr $FFBD
    lda #0
    sta read_extra
    sta read_extra+1
    sta read_clip
    lda #<BANK_VALIDATION_HOME
    sta zDst
    lda #>BANK_VALIDATION_HOME
    sta zDst+1
    lda #<COLLECTION_HOME
    sta zPtr
    lda #>COLLECTION_HOME
    sta zPtr+1
    jsr read_file
    bcs bad
    cpx #<bank_validation_end
    bne bad
    cpy #>bank_validation_end
    bne bad
    lda #1
    sta bank_ready
    rts
bad:
    jmp fail1
.endproc

; Decode the mission at blob_off/blob_len out of the resident container.
; Bank is open for the whole walk. Does not call clear_bss or read_file.
.proc unpack_resident
    jsr bank_enter
    lda #1
    jsr chunk_fields
    lda ch_codec
    bne unpack_bad
    lda ch_stored
    sta ck_len
    lda ch_stored+1
    sta ck_len+1
    lda #<GEO_IMAGE
    sta zDst
    lda #>GEO_IMAGE
    sta zDst+1
    jsr place_raw
    jsr geo_expand
    lda #2
    jsr chunk_fields
    lda #<GEO_IMAGE
    sta zDst
    lda #>GEO_IMAGE
    sta zDst+1
    jsr place_raw
    lda #1
    sta route_ready
    lda #3
    jsr chunk_fields
    lda #<$BF00
    sta zDst
    lda #>$BF00
    sta zDst+1
    jsr place_raw
    lda #4
    jsr chunk_fields
    lda #<TRANSFER_HOME
    sta zDst
    lda #>TRANSFER_HOME
    sta zDst+1
    jsr place_decoded
    lda #5
    jsr chunk_fields
    lda #<(TRANSFER_HOME+$0C80)
    sta zDst
    lda #>(TRANSFER_HOME+$0C80)
    sta zDst+1
    jsr place_decoded
    lda #0
    jsr chunk_fields
    lda #<PACK_HOME
    sta zDst
    lda #>PACK_HOME
    sta zDst+1
    jsr place_decoded
    jsr check_record
    jsr validate_record
    jsr relocate_objectives
    jsr bank_leave
    clc
    rts
unpack_bad:
    jmp fail7
.endproc

; A = directory slot 0..5. Fills ch_* and zSrc. Bank is already open.
.proc chunk_fields
    sta zT7
    lda #<COLLECTION_HOME
    clc
    adc blob_off
    sta zPtr
    lda #>COLLECTION_HOME
    adc blob_off+1
    sta zPtr+1
    clc
    lda zPtr
    adc #12
    sta zPtr
    bcc base
    inc zPtr+1
base:
    lda zT7
    beq slot0
    asl
    asl
    asl
    asl
    clc
    adc zPtr
    sta zPtr
    bcc slot0
    inc zPtr+1
slot0:
    ldy #1
    lda (zPtr),y
    sta ch_codec
    iny
    lda (zPtr),y
    sta ch_xor
    ldy #6
    lda (zPtr),y
    sta ch_stored
    iny
    lda (zPtr),y
    sta ch_stored+1
    ldy #12
    lda (zPtr),y
    sta ch_decoded
    iny
    lda (zPtr),y
    sta ch_decoded+1
    iny
    lda (zPtr),y
    sta ch_body
    iny
    lda (zPtr),y
    sta ch_body+1
    ldy #4
    lda (zPtr),y
    clc
    adc #<COLLECTION_HOME
    sta zSrc
    iny
    lda (zPtr),y
    adc #>COLLECTION_HOME
    sta zSrc+1
    clc
    lda zSrc
    adc blob_off
    sta zSrc
    lda zSrc+1
    adc blob_off+1
    sta zSrc+1
    lda ch_stored
    sta zT0
    lda ch_stored+1
    sta zT1
    rts
.endproc

; Copy the stored bytes. Codec 0 only. zDst is the home. zT0 is the length.
.proc place_raw
    lda ch_codec
    bne raw_bad
    lda ch_stored
    sta zT0
    lda ch_stored+1
    sta zT1
    jmp memmove
raw_bad:
    jmp fail7
.endproc

; Codec 0 copies decoded bytes. Codec 1 calls lzss_sized with that length.
.proc place_decoded
    lda ch_codec
    beq raw
    cmp #1
    bne dec_bad
    lda ch_stored
    sta zT0
    lda ch_stored+1
    sta zT1
    lda ch_decoded
    sta zT2
    lda ch_decoded+1
    sta zT3
    jmp lzss_sized
raw:
    lda ch_stored
    cmp ch_decoded
    bne dec_bad
    lda ch_stored+1
    cmp ch_decoded+1
    bne dec_bad
    lda ch_decoded
    sta zT0
    lda ch_decoded+1
    sta zT1
    jmp memmove
dec_bad:
    jmp fail7
.endproc

; Body length into plen and the ten-byte entry the validator already reads.
.proc check_record
    lda #<PACK_HOME
    sta zSrc
    lda #>PACK_HOME
    sta zSrc+1
    lda ch_decoded
    sta zT0
    lda ch_decoded+1
    sta zT1
    lda #0
    sta zT4
    ldy #0
walk:
    lda zT0
    ora zT1
    beq checked
    lda (zSrc),y
    eor zT4
    sta zT4
    inc zSrc
    bne step
    inc zSrc+1
step:
    lda zT0
    bne dec_lo
    dec zT1
dec_lo:
    dec zT0
    jmp walk
checked:
    lda zT4
    cmp ch_xor
    beq noted
    jmp fail7
noted:
    lda ch_decoded
    sta mission_entry+4
    lda ch_decoded+1
    sta mission_entry+5
    lda ch_body
    sta mission_entry+6
    sta plen
    lda ch_body+1
    sta mission_entry+7
    sta plen+1
    lda ch_codec
    sta mission_entry+8
    lda ch_xor
    sta mission_entry+9
    rts
.endproc

.segment "CODE"
want_c: .byte 0
blob_off: .word 0
blob_len: .word 0
record_ready: .byte 0
bank_ready: .byte 0
ctr_extent: .word 0
ctr_got: .word 0
ctr_tail: .word 0
ch_codec: .byte 0
ch_xor: .byte 0
ch_stored: .word 0
ch_decoded: .word 0
ch_body: .word 0
hex_digits: .byte "0123456789ABCDEF"
bank_name: .byte "BANK"
bank_name_len = * - bank_name


.segment "CODE"
; Discard failed loader call frames; persistent catalog/menu code is intact.
.proc error_menu_return
    jsr quiesce_mission
    lda #$FF
    sta resident
    ldx #$FF
    txs
    jmp menu_top
.endproc
