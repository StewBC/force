; Playfield is multicolour text. Soldiers are composited into chars 224-255.

; The picture stays where it was written. The first call paints the farm
; and the text. Later calls write a cell only when a man moved or changed,
; and a command cell only when its glyph or colour changed.
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
    jsr refresh_ui
    jsr refresh_nades
    jmp place_cursor
field:
    jsr build_occ
    jsr draw_field
    jsr remember_units
    jsr refresh_ui
    jsr refresh_nades
    jmp place_cursor
full:
    jsr build_occ
    jsr draw_field
    jsr draw_ui
    jsr remember_units
    lda #1
    sta drawn
    jsr refresh_nades
    jmp place_cursor
.endproc

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

.proc cell_addr
    lda scr_y
    sta zT0
    lda #0
    sta zT1
    asl zT0
    rol zT1
    asl zT0
    rol zT1
    asl zT0
    rol zT1
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
    adc scr_x
    sta zT0
    lda zT1
    adc #0
    sta zT1
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

; scr_x, scr_y are the screen cell. One store, then return.
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
    lda zA2
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
    sta zA2
    jsr char_addr
    lda zPtr
    sta zSrc
    lda zPtr+1
    sta zSrc+1
    lda zT7
    clc
    adc #224
    jsr char_addr
    lda zPtr
    sta zDst
    lda zPtr+1
    sta zDst+1
    ldy #0
copy:
    lda (zSrc),y
    sta (zDst),y
    iny
    cpy #8
    bne copy
    lda zA4
    jsr char_addr
    lda zPtr
    sta zSrc
    lda zPtr+1
    sta zSrc+1
    ldy #0
mixrow:
    lda (zDst),y
    sta zT4
    lda (zSrc),y
    sta zT5
    jsr mix_byte
    sta (zDst),y
    iny
    cpy #8
    bne mixrow
    rts
.endproc

; zT4 terrain byte, zT5 glyph byte, zT6 hurt. A = mixed byte.
.proc mix_byte
    lda #0
    sta zR0
    lda #4
    sta zT3
pair:
    lda #0
    sta zA0
    sta zA1
    asl zT4
    rol zA0
    asl zT4
    rol zA0
    asl zT5
    rol zA1
    asl zT5
    rol zA1
    lda zA0
    and #3
    cmp #3
    bne keep_t
    lda zA1
    and #3
    cmp #3
    beq keep_p
    ldx zT6
    beq use_u
    cmp #2
    bne use_u
    lda #0
    jmp store
use_u:
    lda zA1
    and #3
    jmp store
keep_t:
    lda zA0
    and #3
    jmp store
keep_p:
    lda #3
store:
    asl zR0
    asl zR0
    ora zR0
    sta zR0
    dec zT3
    bne pair
    lda zR0
    rts
.endproc

.proc draw_ui
    jsr clear_ui
    jsr cmd_paint
    jsr paint_cursor_text
    jsr paint_roster
    jsr paint_host
    rts
.endproc

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

; zA0 x, zA1 y, zA2 colour, zPtr ASCII string.
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

; zPtr text, zA2 colour, scr_x/scr_y start. Glyphs, then spaces out to column 39.
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

.proc paint_host
    lda #<host_line
    sta zPtr
    lda #>host_line
    sta zPtr+1
    lda #1
    sta scr_x
    lda #24
    sta scr_y
    lda #COL_CYAN
    sta zA2
    jsr puts_at
    lda stick_latched
    beq wasd
    lda #<line_word
    sta zPtr
    lda #>line_word
    sta zPtr+1
    jmp tail
wasd:
    lda #<wasd_word
    sta zPtr
    lda #>wasd_word
    sta zPtr+1
tail:
    lda #22
    sta scr_x
    lda #24
    sta scr_y
    lda #COL_CYAN
    sta zA2
    jmp puts_at
.endproc

host_line: .byte "C64 FARM", 0
line_word: .byte "LINE", 0
wasd_word: .byte "WASD", 0

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

.proc place_cursor
    lda frame_lo
    and #$20
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

.proc remember_units
    ldx #0
next:
    lda unit_count,x
    sta seen_count,x
    lda unit_x,x
    sta seen_x,x
    lda unit_y,x
    sta seen_y,x
    lda unit_hp,x
    sta seen_hp,x
    lda unit_fx,x
    sta seen_fx,x
    lda unit_glyph,x
    sta seen_glyph,x
    inx
    cpx #UNIT_MAX
    bne next
    lda win_x
    sta seen_win_x
    lda win_y
    sta seen_win_y
    rts
.endproc

.proc refresh_units
    jsr build_occ
    ldx #0
next:
    lda unit_count,x
    cmp seen_count,x
    bne changed
    lda unit_x,x
    cmp seen_x,x
    bne changed
    lda unit_y,x
    cmp seen_y,x
    bne changed
    lda unit_hp,x
    cmp seen_hp,x
    bne changed
    lda unit_fx,x
    cmp seen_fx,x
    bne changed
    lda unit_glyph,x
    cmp seen_glyph,x
    bne changed
    jmp adv
changed:
    txa
    pha
    lda seen_count,x
    beq now
    lda seen_x,x
    sta zA0
    lda seen_y,x
    sta zA1
    jsr draw_map_cell
now:
    pla
    tax
    lda unit_count,x
    beq copy
    txa
    pha
    lda unit_x,x
    sta zA0
    lda unit_y,x
    sta zA1
    jsr draw_map_cell
    pla
    tax
copy:
    lda unit_count,x
    sta seen_count,x
    lda unit_x,x
    sta seen_x,x
    lda unit_y,x
    sta seen_y,x
    lda unit_hp,x
    sta seen_hp,x
    lda unit_fx,x
    sta seen_fx,x
    lda unit_glyph,x
    sta seen_glyph,x
adv:
    inx
    cpx #UNIT_MAX
    beq leave
    jmp next
leave:
    rts
.endproc

.proc refresh_ui
    jsr refresh_holes
    jsr refresh_status
    jsr refresh_cursor_text
    jsr refresh_roster
    jmp refresh_host
.endproc

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

.proc refresh_status
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

.proc refresh_host
    lda stick_latched
    cmp seen_stick
    beq same
    sta seen_stick
    jmp paint_host
same:
    rts
.endproc
