; Bounded device-8 PRG reader. SETNAM is done by caller. Input zDst=start,
; zPtr=exclusive limit. Output X/Y=exclusive end, C clear success/set error.
; Reads/discards the PRG address: it never authorizes placement. No writes
; beyond limit, even for an oversized file. Static state; non-nesting.
.proc read_file
    lda zDst
    sta read_ptr
    lda zDst+1
    sta read_ptr+1
    lda zPtr
    sta read_limit
    lda zPtr+1
    sta read_limit+1
    lda #2
    sta read_skip
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
    pla
    ldx read_skip
    beq store
    dec read_skip
    jmp eof
store:
    pha
    lda read_ptr
    cmp read_limit
    bne fits
    lda read_ptr+1
    cmp read_limit+1
    beq pop_error
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
read_skip: .byte 0
read_status: .byte 0
