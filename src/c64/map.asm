; zA0 = x, zA1 = y. Row bases are filled once in world_load.
; zPtr -> tile byte, zPtr2 -> paper byte, A = tile, Y = 0.
; Preserves X.

.proc map_ptr
    ldy zA1
    lda row_lo,y
    clc
    adc zA0
    sta zPtr
    lda row_hi,y
    adc #0
    sta zPtr+1
    lda zPtr
    clc
    adc paper_off
    sta zPtr2
    lda zPtr+1
    adc paper_off+1
    sta zPtr2+1
    ldy #0
    lda (zPtr),y
    rts
.endproc

; map_w / map_h already copied. One base per row, plus the paper delta.
.proc build_rows
    lda #<rom_paper
    sec
    sbc #<rom_tiles
    sta paper_off
    lda #>rom_paper
    sbc #>rom_tiles
    sta paper_off+1
    lda #<rom_tiles
    sta zPtr
    lda #>rom_tiles
    sta zPtr+1
    ldy #0
next:
    cpy map_h
    bcs done
    cpy #40
    bcs done
    lda zPtr
    sta row_lo,y
    lda zPtr+1
    sta row_hi,y
    clc
    lda zPtr
    adc map_w
    sta zPtr
    lda zPtr+1
    adc #0
    sta zPtr+1
    iny
    jmp next
done:
    rts
.endproc
