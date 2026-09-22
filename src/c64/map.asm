; zA0 = x, zA1 = y. Farm width is 80.
; zPtr -> tile byte, zPtr2 -> paper byte, A = tile, Y = 0.
; Trashes X and zT0-zT3.

.proc map_ptr
    lda zA1
    sta zT0
    lda #0
    sta zT1
    ldx #4
shift16:
    asl zT0
    rol zT1
    dex
    bne shift16
    lda zT0
    sta zT2
    lda zT1
    sta zT3
    asl zT0
    rol zT1
    asl zT0
    rol zT1
    clc
    lda zT0
    adc zT2
    sta zT0
    lda zT1
    adc zT3
    sta zT1
    clc
    lda zT0
    adc zA0
    sta zT0
    lda zT1
    adc #0
    sta zT1
    clc
    lda zT0
    adc #<rom_tiles
    sta zPtr
    lda zT1
    adc #>rom_tiles
    sta zPtr+1
    clc
    lda zT0
    adc #<rom_paper
    sta zPtr2
    lda zT1
    adc #>rom_paper
    sta zPtr2+1
    ldy #0
    lda (zPtr),y
    rts
.endproc
