; Disk images are verified before any destination scatter. XOR8 covers the
; complete transferred FMAP extent, including directory and compatibility.
; Input end_lo/hi. A/X/Y/zSrc/zT0/1 scratch. No KERNAL/mapping changes.
.segment "VALIDATE"
.proc validate_map_integrity
    lda #<TRANSFER_HOME
    sta zSrc
    lda #>TRANSFER_HOME
    sta zSrc+1
    lda #0
    sta zT0
    ldy #0
vm_loop:
    lda (zSrc),y
    eor zT0
    sta zT0
    inc zSrc
    bne vm_same
    inc zSrc+1
vm_same:
    lda zSrc
    cmp end_lo
    bne vm_loop
    lda zSrc+1
    cmp end_hi
    bne vm_loop
    lda zT0
    beq done
    jmp fail5
done:
    rts
.endproc

; Directory offsets must be nonoverlapping, sorted, beyond the directory.
; Input nchunk. zPtr/zA*/zT*/eidx scratch. Called before storing any slot.
.proc validate_map_extents
    lda nchunk
    asl
    sta zT0
    asl
    asl
    clc
    adc zT0
    adc #26
    sta zT4
    lda #0
    adc #0
    sta zT5
    lda #0
    sta eidx
vm_loop:
    lda eidx
    jsr set_entry_ptr
    ldy #1
    lda (zPtr),y
    beq flags_ok
    cmp #1
    bne bad
    dey
    lda (zPtr),y
    cmp #3
    beq flags_ok
    cmp #4
    bne bad
flags_ok:
    ldy #3
    lda (zPtr),y
    cmp zT5
    bcc bad
    bne inside
    dey
    lda (zPtr),y
    cmp zT4
    bcc bad
inside:
    jsr chunk_past
    bcs bad
    sec
    lda zT0
    sbc #<TRANSFER_HOME
    sta zT4
    lda zT1
    sbc #>TRANSFER_HOME
    sta zT5
    inc eidx
    lda eidx
    cmp nchunk
    bne vm_loop
    rts
bad:
    jmp fail5
.endproc
; Prove the complete mission directory exists before banked entry reads.
; zA2/3 source length and zA0/1 offset are preserved; zT0/A scratch.
.proc validate_collection_extent
    lda zA3
    bne done
    lda INDEX_HOME+6
    asl
    sta zT0
    asl
    asl
    clc
    adc zT0
    adc #6
    cmp zA2
    bcc done
    beq done
    jmp fail5
done:
    rts
.endproc
; Error recovery reads only keyboard row 0, with KERNAL/I/O visible.
; Mask the obsolete raster owner before title_row0 briefly opens IRQs.
.proc load_error_key
    lda #0
    sta $D01A
    jsr title_row0
    sei
    and #2
    rts
.endproc
validate_end:
.assert validate_end .le SCREEN, "disk validator exceeds cassette-buffer allocation"
