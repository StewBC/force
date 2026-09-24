; Raster split: rows 0-19 multicolour text, rows 20-23 normal text on
; black, row 24 normal text on dark grey.
; 210 switches to normal text. 242 sets the grey paper. 251, the first
; bottom-border line, restores multicolour.

; Install the raster handler with IRQs masked and the display held off.
; Arms line 251. A is scratch. X and Y are preserved.
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
    lda #$0B
    sta $D011
    lda #RASTER_MC
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

;-----------------------------------------------------------------------------
; Select the charset and the multicolour palette. The cursor sprite stays
; off until the border split opens the display. A is scratch. X and Y are preserved.
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
    sta $D015
    rts
.endproc

; ($0314) is entered from $FF48, which has already pushed A, X, and Y.
; The 210 and 242 splits return through $EA81 (pop those and RTI).
; The 251 split is in the bottom border, so it chains $EA31 once per frame
; and that path RTIs after the clock and keyboard scan.
; A line below 210 is the same multicolour job: the border interrupt was late.
.proc irq
    lda #$36
    sta $01
    lda $D019
    sta $D019
    lda $D012
    cmp #RASTER_UI
    bcc at_mc
    cmp #RASTER_GREY
    bcc at_ui
    cmp #RASTER_MC
    bcc at_grey
at_mc:
    lda #$D8
    sta $D016
    lda #MC_INK_RED
    sta $D021
    lda #MC_INK_GREY
    sta $D022
    lda #MC_INK_BLUE
    sta $D023
    lda screen_hold
    beq mc_arm
    lda $D012
    cmp #RASTER_MC
    bcs mc_open
    cmp #RASTER_MAP
    bcs mc_arm
mc_open:
    lda $D011
    ora #$10
    sta $D011
    lda #$01
    sta $D015
    lda #0
    sta screen_hold
mc_arm:
    lda #RASTER_UI
    jsr arm
    jsr input_scan
    jmp $EA31
at_grey:
    lda #COL_DARK_GREY
    sta $D021
    lda #RASTER_MC
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
    lda #RASTER_GREY
    jsr arm
    jmp $EA81
arm:
    sta $D012
    lda $D011
    and #$7F
    sta $D011
    rts
.endproc
