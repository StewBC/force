; Raster split: rows 0-19 multicolour, 20-23 hires on black, row 24 hires on dark grey.

.proc irq_init
    lda #$7F
    sta $DC0D
    sta $DD0D
    lda $DC0D
    lda $DD0D
    lda #<irq
    sta $0314
    lda #>irq
    sta $0315
    lda #$01
    sta $D01A
    lda #$1B
    sta $D011
    lda #50
    sta $D012
    lda $D011
    and #$7F
    sta $D011
    lda #$FF
    sta $D019
    lda #1
    sta $CC
    rts
.endproc

.proc vic_init
    lda #0
    sta $D020
    lda #MC_INK_RED
    sta $D021
    lda #MC_INK_GREY
    sta $D022
    lda #MC_INK_BLUE
    sta $D023
    lda #$D8
    sta $D016
    lda #$18
    sta $D018
    lda #$FE
    sta SPRITE_PTR
    lda #COL_CYAN
    sta $D027
    lda #0
    sta $D01C
    sta $D017
    sta $D01D
    sta $D010
    lda #$01
    sta $D015
    rts
.endproc

; ($0314) is entered from $FF48, which has already pushed A, X, and Y.
; The two badline splits return through $EA81 (pop those and RTI).
; The bottom split is in the border, so it chains $EA31 once per frame
; and that path RTIs after the clock and keyboard scan.
.proc irq
    lda #$36
    sta $01
    lda $D019
    sta $D019
    lda $D012
    cmp #210
    bcc at_top
    cmp #242
    bcc at_ui
    lda #COL_DARK_GREY
    sta $D021
    lda #50
    jsr arm
    jmp $EA31
at_top:
    lda #$D8
    sta $D016
    lda #MC_INK_RED
    sta $D021
    lda #MC_INK_GREY
    sta $D022
    lda #MC_INK_BLUE
    sta $D023
    lda #210
    jsr arm
    jmp $EA81
at_ui:
    lda #$C8
    sta $D016
    lda #COL_BLACK
    sta $D021
    lda #1
    sta ui_edge
    lda ui_count
    cmp #FRAME_RASTERS
    bcs ui_sat
    inc ui_count
ui_sat:
    lda #242
    jsr arm
    jmp $EA81
arm:
    sta $D012
    lda $D011
    and #$7F
    sta $D011
    rts
.endproc
