; Playfield is multicolour text. Soldiers are composited into chars 224-255.

; The picture stays where it was written. The first call paints the farm
; and the text. A window move shifts the screen and colour already up and
; paints only the new edge; a jump with no overlap paints the field.
; Later calls write a cell only when a man moved or changed, and a command
; cell only when its glyph or colour changed. Occupancy is rebuilt on a
; full paint and on a scroll. A steady pass clears the cell a man left
; and writes the cell he entered. The caller has waited until the
; beam left the map, so this paint is the whole steady draw.
.proc draw_all
    lda drawn
    beq full
    lda win_x
    cmp seen_win_x
    bne field
    lda win_y
    cmp seen_win_y
    bne field
    jsr refresh_units
    jsr refresh_deck
    jsr refresh_ui
    jsr refresh_nades
    lda #0
    sta ui_dirty
    jmp place_cursor
field:
    jsr scroll_field
    jsr remember_units
    jsr refresh_deck
    jsr refresh_ui
    jsr refresh_nades
    lda #0
    sta ui_dirty
    jmp place_cursor
full:
    jsr build_occ
    jsr draw_field
    jsr draw_ui
    jsr remember_units
    jsr refresh_deck
    lda #1
    sta drawn
    lda #0
    sta ui_dirty
    jsr refresh_nades
    jmp place_cursor
.endproc

;-----------------------------------------------------------------------------
; Convert character code A to its eight-byte charset address in zPtr.
.proc char_addr
    sta zT0
    lda #0
    sta zT1
    asl zT0
    rol zT1
    asl zT0
    rol zT1
    asl zT0
    rol zT1
    clc
    lda zT0
    adc #<CHARSET
    sta zPtr
    lda zT1
    adc #>CHARSET
    sta zPtr+1
    rts
.endproc

;-----------------------------------------------------------------------------
; Compute screen and colour pointers (zSrc/zDst) from scr_x,scr_y: row*40+column.
.proc cell_addr
    lda scr_x
    sta zT0
    lda scr_y
    jsr screen_offset
    clc
    lda zT0
    adc #<SCREEN
    sta zSrc
    lda zT1
    adc #>SCREEN
    sta zSrc+1
    clc
    lda zT0
    adc #<COLORRAM
    sta zDst
    lda zT1
    adc #>COLORRAM
    sta zDst+1
    rts
.endproc

;-----------------------------------------------------------------------------
; Clear the visible occupancy map, then stamp each on-screen unit's slot index.
.proc build_occ
    lda #$FF
    ldx #0
fill:
    sta OCC,x
    sta OCC+$100,x
    sta OCC+$200,x
    inx
    bne fill
    ldx #31
tail:
    sta OCC+$300,x
    dex
    bpl tail
    ldx #0
next:
    lda unit_count,x
    beq skip
    lda unit_x,x
    sec
    sbc win_x
    cmp win_w
    bcs skip
    sta zA2
    lda unit_y,x
    sec
    sbc win_y
    cmp win_h
    bcs skip
    sta scr_y
    lda zA2
    sta scr_x
    stx zT7
    jsr cell_addr
    ldx zT7
    lda zSrc
    sec
    sbc #<SCREEN
    sta zPtr
    lda zSrc+1
    sbc #>SCREEN
    clc
    adc #>OCC
    sta zPtr+1
    ldy #0
    txa
    sta (zPtr),y
skip:
    inx
    cpx #UNIT_MAX
    bne next
    rts
.endproc

; Paint scr_x,scr_y from terrain, optional occupant and grenade flash.
; Writes the screen code and colour; occupied cells also update their glyph.
.proc draw_cell
    lda scr_x
    clc
    adc win_x
    sta zA0
    lda scr_y
    clc
    adc win_y
    sta zA1
    jsr map_ptr
    sta zA2
    ldy #0
    lda (zPtr2),y
    sta zA3
    ldx zA2
    lda rom_tile_force,x
    cmp #$FF
    beq use_paper
    sta zA3
use_paper:
    lda zA2
    pha
    lda zA3
    pha
    jsr grenade_fx_at
    php
    pla
    sta zT5
    pla
    sta zA3
    pla
    sta zA2
    lda zT5
    pha
    plp
    bcc no_flash
    lda #COL_LIGHT_RED
    sta zA3
no_flash:
    lda scr_x
    sta zA0
    lda scr_y
    sta zA1
    jsr occ_at
    cmp #$FF
    beq empty
    tax
    jsr compose_unit
    ldx zT7
    txa
    clc
    adc #224
    sta zA2
    jmp plot
empty:
plot:
    lda zA0
    pha
    lda zA1
    pha
    jsr cell_addr
    pla
    sta zA1
    pla
    sta zA0
    ldy #0
    lda zA2
    sta (zSrc),y
    lda zA3
    ora #$08
    sta (zDst),y
    rts
.endproc

;-----------------------------------------------------------------------------
; A = row, zT4 = column. zT0,zT1 = row*40+column. Trashes A, zT2, zT3.
.proc cell_off
    pha
    lda zT4
    sta zT0
    pla
    jmp screen_offset
.endproc

; A=row (0..24), zT0=column. Returns zT0/zT1=row*40+column.
; Preserves X/Y and zT4. The tables serve scrolling and ordinary cell writes.
.proc screen_offset
    sty zT2
    tay
    lda row40_lo,y
    clc
    adc zT0
    sta zT0
    lda row40_hi,y
    adc #0
    sta zT1
    ldy zT2
    rts
row40_lo:
    .byte 0, 40, 80, 120, 160, 200, 240, 24, 64, 104, 144, 184, 224, 8, 48, 88, 128, 168, 208, 248, 32, 72, 112, 152, 192
row40_hi:
    .byte 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 3, 3, 3, 3, 3
.endproc

; zT0,zT1 is a screen offset. zPtr = screen, zSrc = colour. Trashes A.
.proc point_dest
    clc
    lda zT0
    adc #<SCREEN
    sta zPtr
    lda zT1
    adc #>SCREEN
    sta zPtr+1
    lda zPtr+1
    clc
    adc #$D4
    sta zSrc+1
    lda zPtr
    sta zSrc
    rts
.endproc

; zT0,zT1 is a screen offset. zPtr2 = screen, zDst = colour. Trashes A.
.proc point_src
    clc
    lda zT0
    adc #<SCREEN
    sta zPtr2
    lda zT1
    adc #>SCREEN
    sta zPtr2+1
    lda zPtr2+1
    clc
    adc #$D4
    sta zDst+1
    lda zPtr2
    sta zDst
    rts
.endproc

; Copy X bytes at the four pointers, low address toward high. Y is 0.
; zPtr dest screen, zPtr2 source screen, zSrc dest colour, zDst source colour.
.proc copy_fwd
    ldy #0
fwd:
    lda (zPtr2),y
    sta (zPtr),y
    lda (zDst),y
    and #$0F
    ora #$08
    sta (zSrc),y
    inc zPtr2
    bne fs
    inc zPtr2+1
fs:
    inc zPtr
    bne fd
    inc zPtr+1
fd:
    inc zDst
    bne fc
    inc zDst+1
fc:
    inc zSrc
    bne fn
    inc zSrc+1
fn:
    dex
    bne fwd
    rts
.endproc

; Copy X bytes starting at the high byte, walking back. Same pointers.
.proc copy_back
    ldy #0
back:
    lda (zPtr2),y
    sta (zPtr),y
    lda (zDst),y
    and #$0F
    ora #$08
    sta (zSrc),y
    lda zPtr2
    bne bs
    dec zPtr2+1
bs:
    dec zPtr2
    lda zPtr
    bne bd
    dec zPtr+1
bd:
    dec zPtr
    lda zDst
    bne bc
    dec zDst+1
bc:
    dec zDst
    lda zSrc
    bne bn
    dec zSrc+1
bn:
    dec zSrc
    dex
    bne back
    rts
.endproc

; scr_y is the destination row. Copies the columns that were already on screen.
; scroll_dx/scroll_dy are the signed window delta. Trashes A, X, zp.
.proc copy_row
    lda scr_y
    clc
    adc scroll_dy
    sta zT6
    lda scroll_dx
    bmi row_neg
    lda #0
    sta zT4
    lda scr_y
    jsr cell_off
    lda zT0
    pha
    lda zT1
    pha
    lda scroll_dx
    sta zT4
    lda zT6
    jsr cell_off
    jsr point_src
    pla
    sta zT1
    pla
    sta zT0
    jsr point_dest
    lda #COLS
    sec
    sbc scroll_dx
    tax
    jmp copy_fwd
row_neg:
    lda scroll_dx
    eor #$FF
    clc
    adc #1
    sta zT7
    lda #COLS
    sec
    sbc #1
    sta zT4
    lda scr_y
    jsr cell_off
    lda zT0
    pha
    lda zT1
    pha
    lda #COLS
    sec
    sbc #1
    sec
    sbc zT7
    sta zT4
    lda zT6
    jsr cell_off
    jsr point_src
    pla
    sta zT1
    pla
    sta zT0
    jsr point_dest
    lda #COLS
    sec
    sbc zT7
    tax
    jmp copy_back
.endproc

; Paint scr_y, every column. draw_cell rewrites scr_x and scr_y.
.proc paint_row
    ldx #0
prow:
    stx scr_x
    lda scr_y
    pha
    txa
    pha
    jsr draw_cell
    pla
    tax
    pla
    sta scr_y
    inx
    cpx #COLS
    bne prow
    rts
.endproc

; Paint columns X inclusive through A exclusive on scr_y.
.proc paint_cols
    sta zT7
    stx scr_x
pcol:
    lda scr_x
    cmp zT7
    bcs pdone
    pha
    lda zT7
    pha
    lda scr_y
    pha
    jsr draw_cell
    pla
    sta scr_y
    pla
    sta zT7
    pla
    sta scr_x
    inc scr_x
    jmp pcol
pdone:
    rts
.endproc

; Shift the field by scroll_dx/scroll_dy. The delta is win minus seen_win.
; A jump with no shared cells repaints the field instead.
.proc scroll_rows
    lda scroll_dy
    bmi rows_up
    ldy #0
rdn:
    cpy #FIELD_ROWS
    bcs rdone
    tya
    clc
    adc scroll_dy
    cmp #FIELD_ROWS
    bcs rdone
    sty scr_y
    jsr copy_row
    ldy scr_y
    iny
    jmp rdn
rows_up:
    ldy #FIELD_ROWS
    dey
rup:
    tya
    clc
    adc scroll_dy
    bcc rdone
    sty scr_y
    jsr copy_row
    ldy scr_y
    dey
    cpy #$FF
    bne rup
rdone:
    rts
.endproc

; Paint the rows and columns the shift did not cover.
; Rows the shift uncovered. Bottom when the window moved down, top when it moved up.
.proc paint_new_rows
    lda scroll_dy
    beq row_done
    bmi row_top
    lda #FIELD_ROWS
    sec
    sbc scroll_dy
    tay
row_bot:
    cpy #FIELD_ROWS
    bcs row_done
    sty scr_y
    jsr paint_row
    ldy scr_y
    iny
    jmp row_bot
row_top:
    ldy #0
row_top2:
    sty scr_y
    lda scroll_dy
    eor #$FF
    clc
    adc #1
    cmp scr_y
    beq row_done
    bcc row_done
    jsr paint_row
    ldy scr_y
    iny
    jmp row_top2
row_done:
    rts
.endproc

; Right-hand columns the shift uncovered, on rows the copy already handled.
.proc paint_right_cols
    lda scroll_dy
    bmi rc_up
    ldy #0
rc_dn:
    cpy #FIELD_ROWS
    bcs rc_done
    tya
    clc
    adc scroll_dy
    cmp #FIELD_ROWS
    bcs rc_done
    sty scr_y
    lda #COLS
    sec
    sbc scroll_dx
    tax
    lda #COLS
    jsr paint_cols
    ldy scr_y
    iny
    jmp rc_dn
rc_up:
    lda scroll_dy
    eor #$FF
    clc
    adc #1
    tay
rc_up2:
    cpy #FIELD_ROWS
    bcs rc_done
    sty scr_y
    lda #COLS
    sec
    sbc scroll_dx
    tax
    lda #COLS
    jsr paint_cols
    ldy scr_y
    iny
    jmp rc_up2
rc_done:
    rts
.endproc

; Left-hand columns the shift uncovered, on rows the copy already handled.
.proc paint_left_cols
    lda scroll_dy
    bmi lc_up
    ldy #0
lc_dn:
    cpy #FIELD_ROWS
    bcs lc_done
    tya
    clc
    adc scroll_dy
    cmp #FIELD_ROWS
    bcs lc_done
    sty scr_y
    ldx #0
    lda scroll_dx
    eor #$FF
    clc
    adc #1
    jsr paint_cols
    ldy scr_y
    iny
    jmp lc_dn
lc_up:
    lda scroll_dy
    eor #$FF
    clc
    adc #1
    tay
lc_up2:
    cpy #FIELD_ROWS
    bcs lc_done
    sty scr_y
    ldx #0
    lda scroll_dx
    eor #$FF
    clc
    adc #1
    jsr paint_cols
    ldy scr_y
    iny
    jmp lc_up2
lc_done:
    rts
.endproc

; Columns the shift uncovered. New rows were already painted in full.
.proc paint_new_cols
    lda scroll_dx
    beq nc_done
    bmi nc_left
    jmp paint_right_cols
nc_left:
    jmp paint_left_cols
nc_done:
    rts
.endproc

.proc paint_edges
    jsr paint_new_rows
    jmp paint_new_cols
.endproc

;-----------------------------------------------------------------------------
; Bring the screen from seen_win_* to win_*. Overlap is copied; the new edge
; is painted. No shared cells repaints the whole field. Then men who moved
; inside the overlap are refreshed. Trashes A, X, Y, zp, scr_x, scr_y.
.proc scroll_field
    lda win_x
    sec
    sbc seen_win_x
    sta scroll_dx
    lda win_y
    sec
    sbc seen_win_y
    sta scroll_dy
    lda scroll_dx
    bpl adx
    eor #$FF
    clc
    adc #1
adx:
    cmp #COLS
    bcs repaint
    lda scroll_dy
    bpl ady
    eor #$FF
    clc
    adc #1
ady:
    cmp #FIELD_ROWS
    bcs repaint
    jsr scroll_rows
    jsr build_occ
    jsr paint_edges
    jmp refresh_units
repaint:
    jsr build_occ
    jmp draw_field
.endproc

;-----------------------------------------------------------------------------
; Paint all 40x20 map cells, including terrain, occupants and grenade flashes.
.proc draw_field
    lda #0
    sta scr_y
row:
    lda #0
    sta scr_x
col:
    jsr draw_cell
    inc scr_x
    lda scr_x
    cmp #COLS
    bne col
    inc scr_y
    lda scr_y
    cmp #FIELD_ROWS
    bne row
    rts
.endproc

; zA0, zA1 are map coordinates. Off-window cells are left alone.
.proc draw_map_cell
    lda zA0
    sec
    sbc win_x
    cmp win_w
    bcs out
    sta scr_x
    lda zA1
    sec
    sbc win_y
    cmp win_h
    bcs out
    sta scr_y
    jmp draw_cell
out:
    rts
.endproc

; zA0 = screen x, zA1 = screen y. A = occ byte.
.proc occ_at
    lda zA1
    sta scr_y
    lda zA0
    sta scr_x
    jsr cell_addr
    lda zSrc
    sec
    sbc #<SCREEN
    sta zPtr
    lda zSrc+1
    sbc #>SCREEN
    clc
    adc #>OCC
    sta zPtr+1
    ldy #0
    lda (zPtr),y
    rts
.endproc

; X = unit. Leaves the unit index in zT7. Screen char is 224+X.
; Terrain wins where a pixel is not paper, except built deck is ground
; behind the soldier. Hurt swaps the unit's blue/red ink.
.proc compose_unit
    stx zT7
    lda unit_fx,x
    and #$0F
    sta zT6
    lda unit_glyph,x
    sta zA4
    lda unit_x,x
    sta zA0
    lda unit_y,x
    sta zA1
    jsr map_ptr
    pha
    jsr char_addr
    lda zPtr
    sta zSrc
    lda zPtr+1
    sta zSrc+1
    lda zA4
    jsr char_addr
    lda zPtr
    sta zPtr2
    lda zPtr+1
    sta zPtr2+1
    pla
    sta zA4
    lda zT7
    clc
    adc #224
    jsr char_addr
    lda zPtr
    sta zDst
    lda zPtr+1
    sta zDst+1
    ldy #0
mixrow:
    lda (zSrc),y
    sta zT4
    lda (zPtr2),y
    sta zT5
    jsr weapon_glyph
    jsr mix_ground
    sta (zDst),y
    iny
    cpy #8
    bne mixrow
    rts
.endproc

; zT4 terrain byte, zT5 glyph byte, zT6 hurt (zero is none). A = mixed byte.
; Does not touch Y, zT6, or zT7. Paper terrain copies the glyph.
.proc mix_byte
    lda zT4
    cmp #$FF
    bne cells
    lda zT6
    beq glyph
    jsr tint_glyph
glyph:
    lda zT5
    rts
cells:
    lda zT6
    beq plain
    jsr tint_glyph
plain:
    ; Build a two-bit mask for terrain paper (%11); only those pixels admit the soldier.
    lda zT4
    and #$AA
    sta zT0
    lda zT4
    and #$55
    asl
    and zT0
    sta zT1
    lsr
    ora zT1
    sta zT1
    eor #$FF
    and zT4
    sta zR0
    lda zT5
    and zT1
    ora zR0
    rts
.endproc

; Glyph in zT5, unit in zT7. Player blue (%10) becomes red (%00);
; enemy red (%00) becomes blue (%10). Other pixels stay.
.proc tint_glyph
    ldx zT7
    lda unit_section,x
    cmp #LETTER_MAX
    bcs enemy
    lda zT5
    and #$AA
    sta zT0
    lda zT5
    and #$55
    asl
    and zT0
    sta zT0
    lda zT5
    and #$55
    ora zT0
    sta zT5
    rts
enemy:
    ; Put each low bit beside its high bit. Pairs with neither bit set are
    ; red; set their high bit to turn only those pixels blue.
    lda zT5
    and #$55
    asl
    sta zT0
    lda zT5
    and #$AA
    ora zT0
    eor #$FF
    and #$AA
    ora zT5
    sta zT5
    rts
.endproc

;-----------------------------------------------------------------------------
; Paint the complete five-row command area after a full screen invalidation.
.proc draw_ui
    jsr clear_ui
    jsr cmd_paint
    jsr paint_cursor_text
    jsr paint_roster
    jsr paint_objective
    rts
.endproc

;-----------------------------------------------------------------------------
; Blank the text rows with the custom font's space and white ink.
.proc clear_ui
    lda #FIELD_ROWS
    sta scr_y
row:
    lda #0
    sta scr_x
col:
    jsr cell_addr
    ldy #0
    lda #128
    sta (zSrc),y
    lda #COL_WHITE
    sta (zDst),y
    inc scr_x
    lda scr_x
    cmp #COLS
    bne col
    inc scr_y
    lda scr_y
    cmp #SCREEN_ROWS
    bne row
    rts
.endproc

; scr_x/scr_y select the cell, zA2 is colour, zPtr is a NUL-terminated ASCII string.
.proc puts_at
    jsr cell_addr
next:
    ldy #0
    lda (zPtr),y
    beq done
    clc
    adc #96
    sta (zSrc),y
    lda zA2
    sta (zDst),y
    inc zPtr
    bne no
    inc zPtr+1
no:
    inc zSrc
    bne no2
    inc zSrc+1
no2:
    inc zDst
    bne next
    inc zDst+1
    jmp next
done:
    rts
.endproc

; zPtr text, zA2 colour, scr_x/scr_y start. Pad through column 38; 39 is the margin.
.proc write_span
    jsr cell_addr
    ldy #0
    lda #0
    sta zT2
next:
    lda scr_x
    sta zT0
    tya
    clc
    adc zT0
    cmp #39
    bcs done
    lda zT2
    bne spc
    lda (zPtr),y
    beq mark
    clc
    adc #96
    jmp put
mark:
    lda #1
    sta zT2
spc:
    lda #128
put:
    sta (zSrc),y
    lda zA2
    sta (zDst),y
    iny
    jmp next
done:
    rts
.endproc

;-----------------------------------------------------------------------------
; Build the cursor's map coordinates and replace the coordinate status row.
.proc paint_cursor_text
    jsr cursor_cell
    lda #0
    sta line_n
    sta line_buf
    lda #'C'
    jsr line_ch
    lda #'U'
    jsr line_ch
    lda #'R'
    jsr line_ch
    lda #'S'
    jsr line_ch
    lda #'O'
    jsr line_ch
    lda #'R'
    jsr line_ch
    lda #' '
    jsr line_ch
    lda zA0
    jsr line_dec
    lda #','
    jsr line_ch
    lda zA1
    jsr line_dec
    lda #<line_buf
    sta zPtr
    lda #>line_buf
    sta zPtr+1
    lda #1
    sta scr_x
    lda #22
    sta scr_y
    lda #COL_WHITE
    sta zA2
    jmp write_span
.endproc

;-----------------------------------------------------------------------------
; Show A-H, dim empty sections, and highlight the explicit or implied selection.
.proc paint_roster
    jsr implied_who
    sta zA4
    lda cmd_who
    cmp #LETTER_MAX
    bcs use_imp
    sta zA4
use_imp:
    ldx #0
next:
    txa
    asl
    clc
    adc #1
    sta scr_x
    lda #23
    sta scr_y
    jsr cell_addr
    ldy #0
    txa
    clc
    adc #161
    sta (zSrc),y
    lda #COL_LIGHT_GREY
    ldy section_strength,x
    beq col
    lda #COL_WHITE
col:
    cpx zA4
    bne put
    lda #COL_YELLOW
put:
    ldy #0
    sta (zDst),y
    inx
    cpx #LETTER_MAX
    bne next
    rts
.endproc

;-----------------------------------------------------------------------------
; Paint the transient objective on row 24; blank it when its timer expires.
.proc paint_objective
    ldx #39
clear:
    lda #128
    sta SCREEN+960,x
    lda #COL_WHITE
    sta COLORRAM+960,x
    dex
    bpl clear
    lda objective_ttl
    beq done
    and #4
    beq yellow
    lda #COL_WHITE
    bne ink
yellow:
    lda #COL_YELLOW
ink:
    sta zA2
    sta COLORRAM+960
    lda #158 ; ASCII > + 96
    sta SCREEN+960
    lda objective_ptr
    sta zPtr
    lda objective_ptr+1
    sta zPtr+1
    lda #2
    sta scr_x
    lda #24
    sta scr_y
    jmp puts_at
done:
    rts
.endproc

;-----------------------------------------------------------------------------
; Append A to the bounded, NUL-terminated status buffer; X is scratch.
.proc line_ch
    ldx line_n
    cpx #39
    bcs full
    sta line_buf,x
    inx
    stx line_n
    lda #0
    sta line_buf,x
full:
    rts
.endproc

; A = 0-99 into the line as decimal, no leading zero except 0.
.proc line_dec
    sta zT0
    cmp #10
    bcc one
    ldx #0
tens:
    cmp #10
    bcc td
    sec
    sbc #10
    inx
    bne tens
td:
    pha
    txa
    clc
    adc #'0'
    jsr line_ch
    pla
one:
    clc
    adc #'0'
    jmp line_ch
.endproc

;-----------------------------------------------------------------------------
; Blink the sprite interior and convert character coordinates to VIC pixel positions.
; The interior holds for 8 logic ticks. frame_lo counts those ticks.
.proc place_cursor
    lda frame_lo
    and #$08
    beq open
    lda #$FF
    bne fill
open:
    lda #$81
fill:
    sta SPRITE_DATA+3
    sta SPRITE_DATA+6
    sta SPRITE_DATA+9
    sta SPRITE_DATA+12
    sta SPRITE_DATA+15
    sta SPRITE_DATA+18
    lda cursor_x
    sta zT0
    lda #0
    sta zT1
    asl zT0
    rol zT1
    asl zT0
    rol zT1
    asl zT0
    rol zT1
    clc
    lda zT0
    adc #24
    sta $D000
    lda zT1
    adc #0
    beq nox
    lda #1
    sta $D010
    bne ypos
nox:
    lda #0
    sta $D010
ypos:
    lda cursor_y
    asl
    asl
    asl
    clc
    adc #50
    sta $D001
    rts
.endproc

;-----------------------------------------------------------------------------
; Snapshot all units and the window after a complete field paint.
.proc remember_units
    ldx #0
next:
    lda unit_count,x
    sta seen_count,x
    lda unit_x,x
    sta seen_x,x
    lda unit_y,x
    sta seen_y,x
    lda unit_fx,x
    sta seen_fx,x
    lda unit_glyph,x
    sta seen_glyph,x
    lda unit_kind,x
    sta seen_kind,x
    inx
    cpx #UNIT_MAX
    bne next
    lda win_x
    sta seen_win_x
    lda win_y
    sta seen_win_y
    rts
.endproc

; zA0, zA1 are map coordinates. Carry clear when the cell is on screen.
; scr_x and scr_y are set in that case. Preserves X.
.proc on_screen
    lda zA0
    sec
    sbc win_x
    cmp win_w
    bcs off
    sta scr_x
    lda zA1
    sec
    sbc win_y
    cmp win_h
    bcs off
    sta scr_y
    clc
    rts
off:
    sec
    rts
.endproc

; scr_x, scr_y select the cell. zSrc is its screen byte, zPtr its occ byte.
; Preserves X and Y.
.proc scr_and_occ
    lda scr_x
    sta zT0
    lda scr_y
    jsr screen_offset
    clc
    lda zT0
    adc #<SCREEN
    sta zSrc
    lda zT1
    adc #>SCREEN
    sta zSrc+1
    clc
    lda zT0
    adc #<OCC
    sta zPtr
    lda zT1
    adc #>OCC
    sta zPtr+1
    rts
.endproc

; X = unit. The cell he was drawn on gets the map character and an empty
; occupancy byte. Off-screen men are left alone. Preserves X.
.proc restore_seen
    lda seen_x,x
    sta zA0
    lda seen_y,x
    sta zA1
    jsr on_screen
    bcs out
    jsr map_ptr
    pha
    jsr scr_and_occ
    ldy #0
    lda #$FF
    sta (zPtr),y
    pla
    sta (zSrc),y
out:
    rts
.endproc

; X = unit, still alive. Writes his index, composites charset 224+X, and
; stores that screen code. Colour RAM is already the cell's paper colour.
.proc stamp_unit
    lda unit_x,x
    sta zA0
    lda unit_y,x
    sta zA1
    jsr on_screen
    bcs out
    jsr compose_unit
    ldx zT7
    jsr scr_and_occ
    ldy #0
    txa
    sta (zPtr),y
    clc
    adc #224
    sta (zSrc),y
out:
    rts
.endproc

;-----------------------------------------------------------------------------
; Record unit X's current visual state after its old/new cells have been handled.
.proc note_seen
    lda unit_count,x
    sta seen_count,x
    lda unit_x,x
    sta seen_x,x
    lda unit_y,x
    sta seen_y,x
    lda unit_fx,x
    sta seen_fx,x
    lda unit_glyph,x
    sta seen_glyph,x
    lda unit_kind,x
    sta seen_kind,x
    rts
.endproc

; Clear vacated cells before stamping. A man can step onto a cell another
; man left this tick, including one who died, and men do not share a cell.
.proc refresh_units
    lda #0
    sta draw_n
    ldx #0
scan:
    lda unit_count,x
    cmp seen_count,x
    bne chg
    lda unit_x,x
    cmp seen_x,x
    bne chg
    lda unit_y,x
    cmp seen_y,x
    bne chg
    lda unit_fx,x
    cmp seen_fx,x
    bne chg
    lda unit_glyph,x
    cmp seen_glyph,x
    bne chg
    lda unit_kind,x
    cmp seen_kind,x
    bne chg
next:
    inx
    cpx #UNIT_MAX
    bne scan
    lda #0
    sta draw_at
place:
    ; All vacated cells are now clear, so new occupants can safely reuse them.
    lda draw_at
    cmp draw_n
    beq done
    tax
    lda draw_i,x
    tax
    lda unit_count,x
    beq noteonly
    jsr stamp_unit
noteonly:
    ldx draw_at
    lda draw_i,x
    tax
    jsr note_seen
    inc draw_at
    jmp place
done:
    rts
chg:
    ; Stationary visual changes need a glyph remix; movement/death must first restore terrain.
    lda seen_count,x
    beq queue
    lda unit_count,x
    beq leave
    lda unit_x,x
    cmp seen_x,x
    bne leave
    lda unit_y,x
    cmp seen_y,x
    bne leave
    lda unit_glyph,x
    cmp seen_glyph,x
    bne remix
    lda unit_kind,x
    cmp seen_kind,x
    bne remix
    lda unit_fx,x
    eor seen_fx,x
    and #$0F
    beq stay
remix:
    jsr compose_unit
    ldx zT7
stay:
    jsr note_seen
    jmp next
leave:
    jsr restore_seen
queue:
    ldy draw_n
    txa
    sta draw_i,y
    inc draw_n
    jmp next
.endproc

;-----------------------------------------------------------------------------
; Compare each UI component with its cached state before writing screen RAM.
.proc refresh_ui
    jsr refresh_holes
    jsr refresh_status
    jsr refresh_cursor_text
    jsr refresh_roster
    jmp paint_objective
.endproc

;-----------------------------------------------------------------------------
; Recolour only wizard labels whose active/error highlight changed.
.proc refresh_holes
    jsr which_hole
    sta zA4
    ldx #0
next:
    lda #COL_WHITE
    cpx zA4
    bne col
    lda #COL_YELLOW
    ldy cmd_flash
    beq col
    lda #COL_LIGHT_RED
col:
    cmp seen_hole,x
    beq adv
    sta seen_hole,x
    sta zA2
    txa
    pha
    lda hole_x,x
    sta scr_x
    lda #20
    sta scr_y
    jsr cell_addr
    pla
    tax
    lda hole_len,x
    sta zT1
    ldy #0
paint:
    lda zA2
    sta (zDst),y
    iny
    cpy zT1
    bne paint
adv:
    inx
    cpx #4
    bne next
    rts
.endproc

;-----------------------------------------------------------------------------
; Build the status line and repaint only if its text or colour changed.
.proc refresh_status
    jsr status_changed
    bcs update
    rts
update:
    jsr fill_status
    sta zA2
    ldx #0
cmpb:
    lda line_buf,x
    cmp seen_line,x
    bne dirty
    cmp #0
    beq col
    inx
    cpx #40
    bne cmpb
col:
    lda zA2
    cmp seen_line_col
    beq same
dirty:
    ; Replace the complete text span to erase leftovers from a longer previous message.
    lda #<line_buf
    sta zPtr
    lda #>line_buf
    sta zPtr+1
    lda #1
    sta scr_x
    lda #21
    sta scr_y
    jsr write_span
    ldx #0
copy:
    lda line_buf,x
    sta seen_line,x
    beq wipe
    inx
    cpx #40
    bne copy
    beq savec
wipe:
    inx
    cpx #40
    beq savec
    lda #0
    sta seen_line,x
    jmp wipe
savec:
    lda zA2
    sta seen_line_col
same:
    rts
.endproc

;-----------------------------------------------------------------------------
; Repaint coordinates when either the cursor or its window origin changes.
.proc refresh_cursor_text
    lda cursor_x
    cmp seen_cur_x
    bne go
    lda cursor_y
    cmp seen_cur_y
    bne go
    lda win_x
    cmp seen_cur_wx
    bne go
    lda win_y
    cmp seen_cur_wy
    bne go
    rts
go:
    lda cursor_x
    sta seen_cur_x
    lda cursor_y
    sta seen_cur_y
    lda win_x
    sta seen_cur_wx
    lda win_y
    sta seen_cur_wy
    jmp paint_cursor_text
.endproc

;-----------------------------------------------------------------------------
; Update only section letters whose strength/selection colour changed.
.proc refresh_roster
    jsr implied_who
    sta zA4
    lda cmd_who
    cmp #LETTER_MAX
    bcs marked
    sta zA4
marked:
    ldx #0
next:
    lda #COL_LIGHT_GREY
    ldy section_strength,x
    beq col
    lda #COL_WHITE
col:
    cpx zA4
    bne have
    lda #COL_YELLOW
have:
    cmp seen_roster,x
    beq adv
    sta seen_roster,x
    sta zA2
    txa
    pha
    asl
    clc
    adc #1
    sta scr_x
    lda #23
    sta scr_y
    jsr cell_addr
    pla
    tax
    ldy #0
    lda zA2
    sta (zDst),y
adv:
    inx
    cpx #LETTER_MAX
    bne next
    rts
.endproc

;-----------------------------------------------------------------------------
.segment "BRIDGE_DRAW"

; Built deck is ground: tint the soldier, then let his non-paper pixels
; cover the deck. Other terrain retains the existing foreground rule.
; zA4 is the terrain tile; all other inputs match mix_byte.
.proc mix_ground
    lda zA4
    cmp #TILE_DECK_BUILT
    beq deck
    jmp mix_byte
deck:
    lda zT6
    beq plain
    jsr tint_glyph
plain:
    ldx zT4
    lda zT5
    sta zT4
    stx zT5
    jmp mix_byte::plain
.endproc

.segment "CODE"

.segment "CODE"
; Refresh only completed planks, after units/occupancy or the full field paint.
; Off-screen changes need no paint: scrolling reads the current map.
.proc refresh_deck
    lda #0
    sta deck_draw_i
next:
    ldx deck_draw_i
    cpx deck_count
    bcs done
    lda deck_dirty,x
    beq advance
    lda #0
    sta deck_dirty,x
    lda deck_x,x
    sta zA0
    lda deck_y,x
    sta zA1
    jsr on_screen
    bcs advance
    jsr draw_cell
advance:
    inc deck_draw_i
    jmp next
done:
    rts
.endproc
