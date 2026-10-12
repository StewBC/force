; Bounded device-8 PRG reader. SETNAM is done by caller. Input zDst=start,
; zPtr=exclusive limit. Output X/Y=exclusive end, C clear success/set error.
; read_extra is a 16-bit payload skip after the two-byte PRG address.
; read_clip nonzero: the byte that would land on the limit is not stored,
; and that end is success. Every caller sets both. They are not BSS.
; Static state; non-nesting. No KERNAL call of this proc from inside the bank.
.proc read_file
    lda zDst
    sta read_ptr
    lda zDst+1
    sta read_ptr+1
    lda zPtr
    sta read_limit
    lda zPtr+1
    sta read_limit+1
    clc
    lda #2
    adc read_extra
    sta read_skip
    lda #0
    adc read_extra+1
    sta read_skip+1
    ; OPEN rejects logical file 0. The skip above leaves that in A
    ; whenever read_extra is under 256, including the index load.
    ; CHKIN and CLOSE in this proc already use 2.
    lda #2
    ldx #8
    ldy #2
    jsr $FFBA
    jsr $FFC0
    bcs error
    ldx #2
    jsr $FFC6
    bcs error
next:
    jsr $FFCF
    pha
    jsr $FFB7
    sta read_status
    and #$BF
    bne pop_error
    lda read_skip
    ora read_skip+1
    beq store
    pla
    lda read_skip
    bne dec_lo
    dec read_skip+1
dec_lo:
    dec read_skip
    jmp eof
store:
    lda read_ptr
    cmp read_limit
    bne fits
    lda read_ptr+1
    cmp read_limit+1
    bne fits
    lda read_clip
    bne clip_ok
    jmp pop_error
clip_ok:
    pla
    lda #0
    beq close
fits:
    lda read_ptr
    sta zDst
    lda read_ptr+1
    sta zDst+1
    pla
    ldy #0
    sta (zDst),y
    inc read_ptr
    bne eof
    inc read_ptr+1
eof:
    lda read_status
    and #$40
    beq next
    lda read_skip
    ora read_skip+1
    bne error
    lda #0
    beq close
pop_error:
    pla
error:
    lda #1
close:
    sta read_status
    lda #2
    ldx #2
    jsr $FFC3
    jsr $FFCC
    ldx read_ptr
    ldy read_ptr+1
    lda read_status
    cmp #1
    rts
.endproc
read_ptr: .word 0
read_limit: .word 0
read_skip: .word 0
read_extra: .word 0
read_clip: .byte 0
read_status: .byte 0
