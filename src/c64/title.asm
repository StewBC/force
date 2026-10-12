; Bootstrap has already copied/displayed the title and installed the game.
.segment "CODE"
.proc copy_bytes
    ldy #0
    lda zT1
    beq tail
page:
    lda (zSrc),y
    sta (zDst),y
    iny
    bne page
    inc zSrc+1
    inc zDst+1
    dec zT1
    bne page
tail:
    ldx zT0
    beq done
one:
    lda (zSrc),y
    sta (zDst),y
    iny
    dex
    bne one
done:
    rts
.endproc
.proc title_row0
    sei
    lda #$FF
    sta $DC02
    lda #0
    sta $DC03
    lda #$FE
    sta $DC00
    lda $DC01
    cli
    rts
.endproc
.proc show_title
    jsr bank_vectors
    jsr music_start
    sei
    jsr campaign_load
    cli
    bcs wait_rel
    lda #2
    sta $D020
stuck:
    jmp stuck
wait_rel:
    jsr title_row0
    and #$02
    beq wait_rel
wait_ret:
    jsr title_row0
    and #$02
    bne wait_ret
    ; Release matrix/bitmap before any BSS clear or collection placement.
    sei
    lda #$0B
    sta $D011
    rts
.endproc
