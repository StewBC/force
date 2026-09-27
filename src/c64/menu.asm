; Campaign menu. The picture has already been copied away. The catalog
; lives here, in CODE, so a map load and clear_bss cannot wipe it.
; Screen codes: ASCII+96 is the font at chars 128-223. While the menu is
; up, chars 0-95 hold that font inverted and the real tiles sit at $C000.

MAP_MAX   = 4
MISS_MAX  = 16
NAME_MAX  = 16
TITLE_MAX = 27
LINE_MAX  = 80

KEY_UP    = 1
KEY_DOWN  = 2
KEY_RET   = 3
KEY_STOP  = 4
KEY_DEL   = 5
KEY_PLUS  = 6
KEY_MINUS = 7
KEY_STAR  = 8
KEY_F8    = 9
KEY_LEFT  = 10
KEY_RIGHT = 11

.segment "CODE"

; LOAD the PRG named CAMPAIGN into camp_file and parse it.
; Carry set when at least one mission parsed. A missing file or a bad
; image returns carry clear. The picture's VIC bank is put back, because a
; real drive load borrows the bank-select lines. Trashes A, X, Y, and zero page.
.proc campaign_load
    lda #$36
    sta $01
    lda #0
    sta $D01A
    sta map_count
    sta miss_count
    sta parse_err
    lda #1
    ldx #8
    ldy #0
    jsr $FFBA
    lda #camp_name_len
    ldx #<camp_name
    ldy #>camp_name
    jsr $FFBD
    lda #0
    ldx #<camp_file
    ldy #>camp_file
    jsr $FFD5
    bcs load_fail
    stx camp_end
    sty camp_end+1
    jsr parse_image
    lda parse_err
    bne load_fail
    lda miss_count
    beq load_fail
    lda #0
    sta ui_extra
    sta ui_col
    sta ui_map
    sta ui_miss
    sta ui_f8
    sta ui_save
    sta ui_need_save
    jsr title_bank
    jsr io_unmask
    sec
    rts
load_fail:
    jsr title_bank
    jsr io_unmask
    clc
    rts
.endproc

; Write the tables back over CAMPAIGN. "@:" replaces the old program, which
; is the save both the fast disk trap and a 1541 accept. Carry set on success.
; Trashes A, X, Y, and zero page.
.proc campaign_save
    lda #$36
    sta $01
    lda #0
    sta $D01A
    jsr emit_all
    lda #1
    ldx #8
    ldy #0
    jsr $FFBA
    lda #save_name_len
    ldx #<save_name
    ldy #>save_name
    jsr $FFBD
    lda #zPtr
    ldx camp_end
    ldy camp_end+1
    jsr $FFD8
    bcs save_fail
    jsr io_unmask
    sec
    rts
save_fail:
    jsr io_unmask
    clc
    rts
.endproc

; Remember whether the catalog reached the disk. Trashes A, X, Y, and zero page.
.proc note_save
    jsr campaign_save
    lda #0
    bcs saved
    lda #1
saved:
    sta ui_save
    rts
.endproc

; Raster IRQs off around a KERNAL disk call so the music player cannot
; trample zero page. Restores the music IRQ only. Trashes A.
.proc io_unmask
    lda music_on
    beq nomus
    lda #$01
    sta $D01A
nomus:
    rts
.endproc

; VIC bank 3, which is where the title picture lives. Disk I/O leaves the
; bank-select bits in the serial-idle state. Trashes A.
.proc title_bank
    lda $DD00
    and #$FC
    sta $DD00
    rts
.endproc

; Walk the loaded image. A 0 ends it. Leading zeros are the unused load
; address if a drive stored the header as data. Sets parse_err. Trashes A, X, Y.
.proc parse_image
    ; zPtr2 is the cursor. parse_line reuses zPtr for the title it stores.
    lda #<camp_file
    sta zPtr2
    lda #>camp_file
    sta zPtr2+1
    ldy #0
skip0:
    jsr image_end
    bcs parsed
    lda (zPtr2),y
    bne line
    jsr bump_ptr
    jmp skip0
line:
    ldy #0
copyline:
    jsr image_end
    bcs last
    sty zT6
    ldy #0
    lda (zPtr2),y
    jsr bump_ptr
    ldy zT6
    cmp #0
    beq parsed
    cmp #13
    beq have
    cmp #10
    beq have
    cpy #LINE_MAX
    bcs copyline
    sta camp_line,y
    iny
    jmp copyline
have:
    jsr take_line
    jmp line
last:
    cpy #0
    beq parsed
    jsr take_line
parsed:
    rts
.endproc

; Carry set when zPtr has reached camp_end. Preserves Y. Trashes A.
.proc image_end
    lda zPtr2+1
    cmp camp_end+1
    bcc open
    bne closed
    lda zPtr2
    cmp camp_end
    bcs closed
open:
    clc
    rts
closed:
    sec
    rts
.endproc

; Advance zPtr by one. Preserves A and Y.
.proc bump_ptr
    inc zPtr2
    bne bump_ok
    inc zPtr2+1
bump_ok:
    rts
.endproc

; Y is the line length. Empty lines are ignored. Trashes A, X. Preserves nothing of Y.
.proc take_line
    sty camp_n
    cpy #0
    beq skip
    jsr parse_line
skip:
    ldy #0
    rts
.endproc

; Parse camp_line. A bad line sets parse_err. Trashes A, X, Y, and zero page.
.proc parse_line
    ldx #0
    lda camp_line
    cmp #'#'
    beq skip
    jsr read_tok
    bcc bad
    stx zR0
    jsr find_map
    bcs bad
    sta zA0
    ldx zR0
    jsr read_dec
    bcc bad
    sta zA1
    jsr skip_sp
    cpx camp_n
    bcs bad
    lda camp_line,x
    cmp #'-'
    bne score_num
    inx
    lda #$FF
    jmp have_score
score_num:
    jsr read_dec
    bcc bad
have_score:
    sta zA2
    jsr read_tok
    bcc bad
    ldy miss_count
    cpy #MISS_MAX
    bcs bad
    lda zA0
    sta miss_map,y
    lda zA1
    sta miss_ord,y
    lda zA2
    sta miss_score,y
    lda tok_n
    sta miss_idlen,y
    stx zR0
    jsr store_id
    ldx zR0
    jsr store_title
    bcs bad
    inc miss_count
skip:
    rts
bad:
    lda #1
    sta parse_err
    rts
.endproc

; X is the scan index. Carry set and A is the value, 0..99. Trashes Y.
.proc read_dec
    jsr skip_sp
    cpx camp_n
    bcs dec_bad
    lda camp_line,x
    cmp #'0'
    bcc dec_bad
    cmp #'9'+1
    bcs dec_bad
    lda #0
    sta zT0
dec_loop:
    cpx camp_n
    bcs dec_ok
    lda camp_line,x
    cmp #'0'
    bcc dec_ok
    cmp #'9'+1
    bcs dec_ok
    sec
    sbc #'0'
    sta zT2
    lda zT0
    cmp #10
    bcs dec_bad
    asl
    sta zT3
    asl
    asl
    clc
    adc zT3
    clc
    adc zT2
    sta zT0
    inx
    jmp dec_loop
dec_ok:
    lda zT0
    sec
    rts
dec_bad:
    clc
    rts
.endproc

; Copy the next token into tok_buf. Carry set when it is non-empty.
; X advances. Trashes A and Y.
.proc read_tok
    lda #0
    sta tok_n
    jsr skip_sp
    cpx camp_n
    bcs tok_empty
tok_more:
    cpx camp_n
    bcs tok_ok
    lda camp_line,x
    cmp #' '
    beq tok_ok
    ldy tok_n
    cpy #NAME_MAX
    bcs tok_empty
    sta tok_buf,y
    inc tok_n
    inx
    jmp tok_more
tok_ok:
    lda tok_n
    beq tok_empty
    sec
    rts
tok_empty:
    clc
    rts
.endproc

; Advance X over spaces. Trashes A.
.proc skip_sp
sp:
    cpx camp_n
    bcs sp_done
    lda camp_line,x
    cmp #' '
    bne sp_done
    inx
    jmp sp
sp_done:
    rts
.endproc

; tok_buf is a map name. A comes back as its index. Carry set on overflow.
; Trashes X and Y.
.proc find_map
    ldy #0
find:
    cpy map_count
    bcs add_map
    tya
    jsr cat_map
    lda map_nlen,y
    cmp tok_n
    bne find_next
    sty zT4
    ldy #0
cmpb:
    cpy tok_n
    bcs found
    lda (zPtr),y
    cmp tok_buf,y
    bne find_resume
    iny
    jmp cmpb
find_resume:
    ldy zT4
find_next:
    iny
    jmp find
found:
    lda zT4
    clc
    rts
add_map:
    ldy map_count
    cpy #MAP_MAX
    bcs add_bad
    tya
    jsr cat_map
    lda tok_n
    sta map_nlen,y
    sty zT4
    ldy #0
copy:
    cpy tok_n
    bcs copied
    lda tok_buf,y
    sta (zPtr),y
    iny
    jmp copy
copied:
    ldy zT4
    inc map_count
    tya
    clc
    rts
add_bad:
    sec
    rts
.endproc

; miss_count is the slot. tok_buf is the id. Trashes A and Y.
.proc store_id
    ldy miss_count
    tya
    tax
    jsr id_ptr
    ldy #0
idc:
    cpy tok_n
    bcs id_done
    lda tok_buf,y
    sta (zPtr),y
    iny
    jmp idc
id_done:
    rts
.endproc

; The remainder of the line, after spaces, is the title. Carry set on failure.
; Trashes A, X, and Y.
.proc store_title
    jsr skip_sp
    cpx camp_n
    bcs title_bad
    stx zT4
    ldy camp_n
trim:
    cpy zT4
    beq title_bad
    dey
    lda camp_line,y
    cmp #' '
    beq trim
    iny
    tya
    sec
    sbc zT4
    cmp #TITLE_MAX+1
    bcs title_bad
    ldy miss_count
    sta miss_tlen,y
    tya
    tax
    jsr title_ptr
    ldy #0
tcopy:
    cpy zT0
    bcs title_ok
    sty zT3
    ldy zT4
    lda camp_line,y
    inc zT4
    ldy zT3
    sta (zPtr),y
    iny
    jmp tcopy
title_ok:
    clc
    rts
title_bad:
    sec
    rts
.endproc

; A = map index. zPtr points at its 16-byte slot. zT0 is the length. Trashes X.
.proc cat_map
    tax
    lda map_nlen,x
    sta zT0
    txa
    jsr mul16
    clc
    adc #<map_names
    sta zPtr
    lda #>map_names
    adc #0
    sta zPtr+1
    rts
.endproc

; X = mission index. zPtr points at its id. zT0 is the length. Trashes A.
.proc id_ptr
    lda miss_idlen,x
    sta zT0
    txa
    jsr mul16
    clc
    adc #<miss_id
    sta zPtr
    lda #>miss_id
    adc #0
    sta zPtr+1
    rts
.endproc

; X = mission index. zPtr points at its title. zT0 is the length. Trashes A.
.proc title_ptr
    lda miss_tlen,x
    sta zT0
    txa
    sta zT1
    asl
    asl
    sta zT2
    lda zT1
    asl
    asl
    asl
    asl
    asl
    sec
    sbc zT2
    clc
    adc #<miss_title
    sta zPtr
    lda #>miss_title
    adc #0
    sta zPtr+1
    rts
.endproc

; A = index 0..15. A comes back as index*16. Trashes nothing else.
.proc mul16
    asl
    asl
    asl
    asl
    rts
.endproc

; Write every mission line into camp_file. camp_end is the exclusive end.
; The start pointer for SAVE is zPtr. Trashes A, X, and Y.
.proc emit_all
    lda #<camp_file
    sta zPtr2
    lda #>camp_file
    sta zPtr2+1
    ldx #0
emit_next:
    cpx miss_count
    bcs emit_done
    txa
    pha
    jsr emit_mission
    pla
    tax
    inx
    jmp emit_next
emit_done:
    lda zPtr2
    sta camp_end
    lda zPtr2+1
    sta camp_end+1
    lda #<camp_file
    sta zPtr
    lda #>camp_file
    sta zPtr+1
    rts
.endproc

; Append A to camp_file. Drops the byte when the buffer is full. Trashes Y.
.proc buf_putc
    pha
    lda zPtr2+1
    cmp #>camp_limit
    bcc room
    bne full
    lda zPtr2
    cmp #<camp_limit
    bcs full
room:
    pla
    ldy #0
    sta (zPtr2),y
    inc zPtr2
    bne put_ok
    inc zPtr2+1
put_ok:
    rts
full:
    pla
    rts
.endproc

; X = mission index. One CR-terminated line. Trashes A, X, and Y.
.proc emit_mission
    stx zR0
    lda miss_map,x
    jsr emit_map_name
    lda #' '
    jsr buf_putc
    ldx zR0
    lda miss_ord,x
    jsr emit_dec
    lda #' '
    jsr buf_putc
    ldx zR0
    lda miss_score,x
    cmp #$FF
    bne emit_num
    lda #'-'
    jsr buf_putc
    jmp emit_idsp
emit_num:
    jsr emit_dec
emit_idsp:
    lda #' '
    jsr buf_putc
    ldx zR0
    jsr emit_id
    lda #' '
    jsr buf_putc
    ldx zR0
    jsr emit_title
    lda #13
    jmp buf_putc
.endproc

; A = map index. Trashes A, X, and Y.
.proc emit_map_name
    jsr cat_map
    jmp emit_ptr
.endproc

; X = mission. Trashes A and Y.
.proc emit_id
    jsr id_ptr
    jmp emit_ptr
.endproc

; X = mission. Trashes A and Y.
.proc emit_title
    jsr title_ptr
    jmp emit_ptr
.endproc

; zPtr/zT0 is the span. buf_putc clears Y, so the index is stacked.
; Trashes A and Y.
.proc emit_ptr
    ldy #0
ep:
    cpy zT0
    bcs ep_done
    tya
    pha
    lda (zPtr),y
    jsr buf_putc
    pla
    tay
    iny
    jmp ep
ep_done:
    rts
.endproc

; A = 0..99. Prints decimal without a leading zero, except for zero itself.
; Trashes A, X, and Y.
.proc emit_dec
    ldx #0
tens:
    cmp #10
    bcc ones
    sec
    sbc #10
    inx
    jmp tens
ones:
    pha
    cpx #0
    beq one_only
    txa
    ora #$30
    jsr buf_putc
one_only:
    pla
    ora #$30
    jmp buf_putc
.endproc

; Install the text screen, invert the font, and draw. Starts the music
; when the mission silenced it. Trashes A, X, Y, and zero page.
.proc menu_open
    lda music_on
    bne vic
    sei
    jsr music_start
vic:
    sei
    jsr menu_vic
    jsr menu_invert
    jsr menu_sync
    jsr menu_draw
    lda ui_need_save
    beq open_on
    jsr menu_save_now
open_on:
    cli
    rts
.endproc

; Black text page, charset at $2000, screen at $0400. Trashes A.
.proc menu_vic
    lda #$0B
    sta $D011
    lda #0
    sta $D015
    sta $D020
    sta $D021
    lda $DD00
    ora #$03
    sta $DD00
    lda #$C8
    sta $D016
    lda #$18
    sta $D018
    rts
.endproc

; Stash tiles 0-95 at $C000 and put an inverted font in their place.
; A second call while the font is already swapped does nothing. Trashes A, X, Y.
.proc menu_invert
    lda font_swapped
    beq do_inv
    rts
do_inv:
    lda #$00
    sta zSrc
    lda #$20
    sta zSrc+1
    lda #$00
    sta zDst
    lda #$C0
    sta zDst+1
    lda #$00
    sta zT0
    lda #$03
    sta zT1
    jsr copy_bytes
    lda #$00
    sta zSrc
    lda #$24
    sta zSrc+1
    lda #$00
    sta zDst
    lda #$20
    sta zDst+1
    ldy #0
inv:
    lda (zSrc),y
    eor #$FF
    sta (zDst),y
    iny
    bne inv
    inc zSrc+1
    inc zDst+1
    lda zDst+1
    cmp #$23
    bne inv
    lda #1
    sta font_swapped
    rts
.endproc

; Put the stashed tiles back. Trashes A, X, and Y.
.proc menu_restore_font
    lda font_swapped
    bne do_res
    rts
do_res:
    lda #$00
    sta zSrc
    lda #$C0
    sta zSrc+1
    lda #$00
    sta zDst
    lda #$20
    sta zDst+1
    lda #$00
    sta zT0
    lda #$03
    sta zT1
    jsr copy_bytes
    lda #0
    sta font_swapped
    rts
.endproc

; Draw, then wait for a choice. Returns with a mission selected in menu_played.
; Trashes A, X, Y, and zero page.
.proc menu_loop
redraw:
    sei
    jsr menu_refresh
    cli
waitk:
    jsr menu_key
    bcc waitk
    sei
    jsr menu_handle
    cli
    bcs redraw
    rts
.endproc

; Fade and silence, clear the page, then restore the tiles. The inverse
; bar lives in chars 0-95, so those tiles must stay put until the menu
; is off the screen. Load the map when it is not resident, then enter
; the battle the way a cold start used to. Trashes A, X, Y.
.proc menu_launch
    sei
    ldx menu_played
    lda miss_map,x
    sta launch_map
    cmp resident
    beq no_note
    lda #<load_s
    sta zPtr
    lda #>load_s
    sta zPtr+1
    lda #0
    sta scr_x
    lda #22
    sta scr_y
    lda #COL_WHITE
    sta zA2
    lda #0
    sta zA3
    jsr menu_puts
no_note:
    cli
    lda music_on
    beq quiet
    jsr music_begin_fade
fade:
    jsr music_fade_done
    bcc fade
    jsr music_stop
    jmp stopped
quiet:
    sei
stopped:
    lda #$0B
    sta $D011
    jsr clear_screen
    jsr menu_restore_font
    lda launch_map
    cmp resident
    beq activate
    jsr set_load_name
    jsr map_load
    lda launch_map
    sta resident
activate:
    ldx menu_played
    lda miss_ord,x
    tax
    jsr mission_activate
    jsr irq_init
    jsr vic_init
    jsr world_load
    jsr session_init
    jsr draw_all
    lda #0
    sta ui_edge
    sta ui_count
    lda #1
    sta screen_hold
    lda #$FF
    sta $D019
    cli
    rts
.endproc

; Copy the resident map's CBM name into the loader. Trashes A, X, and Y.
.proc set_load_name
    lda launch_map
    jsr cat_map
    lda zT0
    sta map_len
    ldy #0
copyn:
    cpy #NAME_MAX
    bcs copy_done
    cpy zT0
    bcs pad
    lda (zPtr),y
    jmp storec
pad:
    lda #0
storec:
    sta cat_load_name,y
    iny
    jmp copyn
copy_done:
    rts
.endproc

; A win stores a higher survivor count and moves the bar to the next mission.
; A loss leaves the bar on the mission just played. Trashes A, X, and Y.
.proc menu_commit
    lda script_outcome
    cmp #OUT_WIN
    bne show_played
    lda score_snap
    beq advance
    ldx menu_played
    lda miss_score,x
    cmp #$FF
    beq store_score
    cmp snap_score
    bcs advance
store_score:
    lda snap_score
    sta miss_score,x
    lda #1
    sta ui_need_save
advance:
    ldx menu_played
    inx
    cpx miss_count
    bcs show_played
    stx menu_played
    jsr miss_shown
    bcs show_played
    jsr frontier_of
    cmp miss_count
    bcs show_played
    sta menu_played
show_played:
    ldx menu_played
    lda miss_map,x
    sta ui_map
    stx ui_miss
    lda #1
    sta ui_col
    lda #0
    sta ui_f8
    rts
.endproc

; Paint the fixed page and the two columns. Trashes A, X, Y, and zero page.
.proc menu_draw
    lda #$0B
    sta $D011
    jsr clear_screen
    lda #<title_s
    sta zPtr
    lda #>title_s
    sta zPtr+1
    lda #0
    jsr draw_center
    lda #<credit_s
    sta zPtr
    lda #>credit_s
    sta zPtr+1
    lda #24
    jsr draw_center
    jsr draw_headers
    jsr draw_maps
    jsr draw_missions
    jsr draw_status
    lda #$1B
    sta $D011
    rts
.endproc

; The menu is already on screen. Say so, then write the catalog.
; IRQs stay masked: the music player and the KERNAL share zero page.
; Trashes A, X, Y, and zero page.
.proc menu_save_now
    lda #0
    sta ui_need_save
    lda #<saving_s
    sta zPtr
    lda #>saving_s
    sta zPtr+1
    lda #COL_WHITE
    sta zA2
    lda #0
    sta scr_x
    sta zA3
    lda #22
    sta scr_y
    jsr menu_puts
    jsr note_save
    jmp draw_status
.endproc

; Repaint the lists in place. The display stays on, so a choice does not
; flash the page. Trashes A, X, Y, and zero page.
.proc menu_refresh
    jsr blank_lists
    jsr draw_headers
    jsr draw_maps
    jsr draw_missions
    jmp draw_status
.endproc

; Row 6 column titles. Colour follows the active column. Trashes A, X, Y.
.proc draw_headers
    lda #0
    sta scr_x
    lda #6
    sta scr_y
    lda #COL_DARK_GREY
    ldx ui_col
    bne map_dim
    lda #COL_WHITE
map_dim:
    sta zA2
    lda #0
    sta zA3
    lda #<hdr_map
    sta zPtr
    lda #>hdr_map
    sta zPtr+1
    jsr menu_puts
    lda #10
    sta scr_x
    lda #COL_DARK_GREY
    ldx ui_col
    beq mis_dim
    lda #COL_WHITE
mis_dim:
    sta zA2
    lda #<mis_h
    sta zPtr
    lda #>mis_h
    sta zPtr+1
    jsr menu_puts
    lda #30
    sta scr_x
    lda #COL_DARK_GREY
    sta zA2
    lda #<sur_h
    sta zPtr
    lda #>sur_h
    sta zPtr+1
    jmp menu_puts
.endproc

; Row 22. The reset prompt wins over a failed save. Trashes A, X, and Y.
.proc draw_status
    jsr blank_row22
    lda ui_f8
    beq no_f8
    lda #<f8_s
    sta zPtr
    lda #>f8_s
    sta zPtr+1
    lda #COL_WHITE
    jmp status_at
no_f8:
    lda ui_save
    beq no_status
    lda #<save_s
    sta zPtr
    lda #>save_s
    sta zPtr+1
    lda #COL_LIGHT_RED
status_at:
    sta zA2
    lda #0
    sta scr_x
    sta zA3
    lda #22
    sta scr_y
    jmp menu_puts
no_status:
    rts
.endproc

; A = row. zPtr is a NUL-terminated string, drawn centered in white.
; Trashes A, X, and Y.
.proc draw_center
    sta scr_y
    ldy #0
clen:
    lda (zPtr),y
    beq clen_done
    iny
    jmp clen
clen_done:
    sty zT0
    lda #40
    sec
    sbc zT0
    lsr
    sta scr_x
    lda #COL_WHITE
    sta zA2
    lda #0
    sta zA3
    jmp menu_puts
.endproc

; Blank all 25 rows. Stops at colour $DBE8, short of the CIA. Trashes A, X, Y.
.proc clear_screen
    lda #<SCREEN
    sta zSrc
    lda #>SCREEN
    sta zSrc+1
    lda #<COLORRAM
    sta zDst
    lda #>COLORRAM
    sta zDst+1
    ldx #3
    ldy #0
full:
    lda #128
    sta (zSrc),y
    lda #COL_WHITE
    sta (zDst),y
    iny
    bne full
    inc zSrc+1
    inc zDst+1
    dex
    bne full
tail:
    cpy #232
    bcs tail_done
    lda #128
    sta (zSrc),y
    lda #COL_WHITE
    sta (zDst),y
    iny
    jmp tail
tail_done:
    rts
.endproc

; Rows 8-17, the whole list. 400 bytes from screen $0540. Trashes A, X, Y.
.proc blank_lists
    lda #$40
    sta zSrc
    lda #$05
    sta zSrc+1
    lda #$40
    sta zDst
    lda #$D9
    sta zDst+1
    ldx #1
    ldy #0
page:
    lda #128
    sta (zSrc),y
    lda #COL_WHITE
    sta (zDst),y
    iny
    bne page
    inc zSrc+1
    inc zDst+1
    dex
    bne page
rest:
    cpy #144
    bcs rest_done
    lda #128
    sta (zSrc),y
    lda #COL_WHITE
    sta (zDst),y
    iny
    jmp rest
rest_done:
    rts
.endproc

; Status row. 40 bytes at screen $0770. Trashes A and Y.
.proc blank_row22
    lda #$70
    sta zSrc
    lda #$07
    sta zSrc+1
    lda #$70
    sta zDst
    lda #$DB
    sta zDst+1
    ldy #0
wipe:
    lda #128
    sta (zSrc),y
    lda #COL_WHITE
    sta (zDst),y
    iny
    cpy #40
    bne wipe
    rts
.endproc

; Visible maps from row 8. The current map stays inverse in either
; column. Trashes A, X, and Y.
.proc draw_maps
    lda #8
    sta scr_y
    ldx #0
map_loop:
    cpx map_count
    bcs maps_done
    lda scr_y
    cmp #18
    bcs maps_done
    stx zT4
    jsr map_has_shown
    bcc map_next
    lda #0
    sta scr_x
    lda #0
    sta zA3
    lda #COL_WHITE
    sta zA2
    cpx ui_map
    bne map_plain
    lda #1
    sta zA3
map_plain:
    txa
    jsr cat_map
    jsr draw_cased
    inc scr_y
map_next:
    inx
    jmp map_loop
maps_done:
    rts
.endproc

; Missions of ui_map, windowed into rows 8-17. Trashes A, X, and Y.
.proc draw_missions
    jsr window_skip
    lda #0
    sta passed
    lda #8
    sta scr_y
    ldy #0
mloop:
    cpy miss_count
    bcs mdone
    lda scr_y
    cmp #18
    bcs mdone
    lda miss_map,y
    cmp ui_map
    bne mnext
    tya
    tax
    jsr miss_shown
    bcc mnext
    lda passed
    cmp win_skip
    bcc mskip
    jsr draw_one_mission
    inc scr_y
mskip:
    inc passed
mnext:
    iny
    jmp mloop
mdone:
    rts
.endproc

; How many shown rows of this map to skip so ui_miss stays on rows 8-17.
; Trashes A, X, and Y. Result in win_skip.
.proc window_skip
    lda #0
    sta win_skip
    sta zT6
    ldy #0
wloop:
    cpy miss_count
    bcs wdone
    lda miss_map,y
    cmp ui_map
    bne wnext
    tya
    tax
    jsr miss_shown
    bcc wnext
    cpy ui_miss
    bne not_cur
    lda zT6
    sta win_skip
not_cur:
    inc zT6
wnext:
    iny
    jmp wloop
wdone:
    lda win_skip
    cmp #10
    bcc wzero
    sec
    sbc #9
    sta win_skip
    rts
wzero:
    lda #0
    sta win_skip
    rts
.endproc

; Y = mission index. Preserves Y. Trashes A and X.
.proc draw_one_mission
    tya
    pha
    tax
    lda #10
    sta scr_x
    lda #0
    sta zA3
    lda miss_score,x
    cmp #$FF
    beq open_col
    lda #COL_LIGHT_GREEN
    jmp setc
open_col:
    lda #COL_WHITE
setc:
    sta zA2
    lda ui_col
    beq plain
    cpx ui_miss
    bne plain
    lda #1
    sta zA3
    lda #COL_WHITE
    sta zA2
plain:
    jsr title_ptr
    jsr draw_raw
pad:
    lda scr_x
    cmp #38
    bcs score
    lda #' '
    jsr menu_putc
    jmp pad
score:
    pla
    pha
    tax
    jsr draw_score
    pla
    tay
    rts
.endproc

; X = mission. Two columns ending at column 39. Trashes A and X.
.proc draw_score
    lda #38
    sta scr_x
    lda miss_score,x
    cmp #$FF
    bne have_n
    lda #' '
    jsr menu_putc
    lda #'-'
    jmp menu_putc
have_n:
    cmp #10
    bcs two
    lda #' '
    jsr menu_putc
    lda miss_score,x
    jmp one_digit
two:
    lda miss_score,x
    ldx #0
tens:
    cmp #10
    bcc tens_done
    sec
    sbc #10
    inx
    jmp tens
tens_done:
    pha
    txa
    jsr one_digit
    pla
one_digit:
    ora #$30
    jmp menu_putc
.endproc

; zPtr/zT0 is a map name. The first letter stays, the rest drops to lower case.
; Pads with spaces through column 8. Trashes A, X, and Y.
.proc draw_cased
    ldy #0
cch:
    lda scr_x
    cmp #9
    bcs cdone
    cpy zT0
    bcs cpad
    lda (zPtr),y
    cpy #0
    beq cout
    cmp #'A'
    bcc cout
    cmp #'Z'+1
    bcs cout
    clc
    adc #32
cout:
    jsr menu_putc
    iny
    jmp cch
cpad:
    lda #' '
    jsr menu_putc
    jmp cch
cdone:
    rts
.endproc

; zPtr/zT0 is literal text. Stops at column 37 so the score still fits.
; Trashes A and Y.
.proc draw_raw
    ldy #0
rch:
    lda scr_x
    cmp #37
    bcs rdone
    cpy zT0
    bcs rdone
    lda (zPtr),y
    jsr menu_putc
    iny
    jmp rch
rdone:
    rts
.endproc

; zPtr is NUL-terminated. zA2 colour, zA3 inverse. Trashes A and Y.
.proc menu_puts
    ldy #0
pnext:
    lda (zPtr),y
    beq pdone
    jsr menu_putc
    inc zPtr
    bne pnext
    inc zPtr+1
    jmp pnext
pdone:
    rts
.endproc

; scr_x/scr_y select the cell. A is ASCII. zA2 is colour. zA3 nonzero inverts.
; Trashes X and Y. Advances scr_x.
.proc menu_putc
    sta zA4
    txa
    pha
    tya
    pha
    lda zPtr
    pha
    lda zPtr+1
    pha
    lda zT0
    pha
    jsr cell_addr
    pla
    sta zT0
    pla
    sta zPtr+1
    pla
    sta zPtr
    pla
    tay
    pla
    tax
    lda zA3
    beq norm_a
    lda zA4
    sec
    sbc #32
    jmp storeg
norm_a:
    lda zA4
    clc
    adc #96
storeg:
    sta zA4
    tya
    pha
    ldy #0
    lda zA4
    sta (zSrc),y
    lda zA2
    sta (zDst),y
    pla
    tay
    inc scr_x
    rts
.endproc

; Sample the matrix and return one new key in A. Carry set when there is one.
; Trashes X and Y. Does not use zero page, so the music IRQ may interrupt it.
.proc menu_key
    sei
    jsr menu_sample
    ldx #0
edge:
    lda menu_now,x
    eor #$FF
    and menu_prev,x
    sta menu_edge,x
    lda menu_now,x
    sta menu_prev,x
    inx
    cpx #8
    bne edge
    lda menu_joy
    eor #$FF
    and menu_joy_prev
    sta menu_joy_edge
    lda menu_joy
    sta menu_joy_prev
    lda menu_edge+0
    and #$02
    beq no_ret
    lda #KEY_RET
    jmp hit
no_ret:
    lda menu_edge+0
    and #$08
    beq no_f8
    jsr shift_down
    bcc no_f8
    lda #KEY_F8
    jmp hit
no_f8:
    lda menu_edge+5
    and #$01
    beq no_plus
    lda #KEY_PLUS
    jmp hit
no_plus:
    lda menu_edge+5
    and #$08
    beq no_minus
    lda #KEY_MINUS
    jmp hit
no_minus:
    lda menu_edge+6
    and #$02
    beq no_star
    lda #KEY_STAR
    jmp hit
no_star:
    lda menu_edge+7
    and #$80
    beq no_stop
    lda #KEY_STOP
    jmp hit
no_stop:
    lda menu_edge+0
    and #$01
    beq no_del
    lda #KEY_DEL
    jmp hit
no_del:
    lda menu_edge+0
    and #$80
    beq no_cur
    jsr shift_down
    lda #KEY_DOWN
    bcc cur_dn
    lda #KEY_UP
cur_dn:
    jmp hit
no_cur:
    lda menu_edge+0
    and #$04
    beq no_lr
    jsr shift_down
    lda #KEY_RIGHT
    bcc lr_plain
    lda #KEY_LEFT
lr_plain:
    jmp hit
no_lr:
    lda menu_joy_edge
    and #$10
    beq no_fire
    lda #KEY_RET
    jmp hit
no_fire:
    lda menu_joy_edge
    and #$01
    beq no_jup
    lda #KEY_UP
    jmp hit
no_jup:
    lda menu_joy_edge
    and #$02
    beq no_jdown
    lda #KEY_DOWN
    jmp hit
no_jdown:
    lda menu_joy_edge
    and #$04
    beq no_jleft
    lda #KEY_LEFT
    jmp hit
no_jleft:
    lda menu_joy_edge
    and #$08
    beq none
    lda #KEY_RIGHT
hit:
    sec
    cli
    rts
none:
    clc
    cli
    rts
.endproc

; Carry set when either Shift key is down in menu_now. Trashes A.
.proc shift_down
    lda menu_now+1
    and #$80
    beq sh_yes
    lda menu_now+6
    and #$10
    beq sh_yes
    clc
    rts
sh_yes:
    sec
    rts
.endproc

; Read eight keyboard rows and joystick port 2. Trashes A and X.
.proc menu_sample
    ldx #0
srow:
    lda #$FF
    sta $DC02
    lda #0
    sta $DC03
    lda rowmask,x
    sta $DC00
    lda $DC01
    sta menu_now,x
    inx
    cpx #8
    bne srow
    lda #$FF
    sta $DC00
    lda $DC00
    sta menu_joy
    rts
rowmask:
    .byte $FE,$FD,$FB,$F7,$EF,$DF,$BF,$7F
.endproc

; Copy the current matrix into the edge memory so a held RETURN does not
; also activate the menu. Trashes A and X.
.proc menu_sync
    jsr menu_sample
    ldx #7
sy:
    lda menu_now,x
    sta menu_prev,x
    dex
    bpl sy
    lda menu_joy
    sta menu_joy_prev
    rts
.endproc

; A = key code from menu_key. Carry set to redraw, clear to launch.
; Trashes A, X, Y, and zero page.
.proc menu_handle
    ldx ui_f8
    beq normal
    cmp #KEY_F8
    beq do_f8
    lda #0
    sta ui_f8
    sec
    rts
normal:
    cmp #KEY_F8
    bne no_arm
    lda #1
    sta ui_f8
    sec
    rts
do_f8:
    jsr reset_scores
    jsr menu_refresh
    jsr menu_save_now
    sec
    rts
no_arm:
    cmp #KEY_UP
    bne no_up
    lda #$FF
    jmp move_sel
no_up:
    cmp #KEY_DOWN
    bne no_down
    lda #1
    jmp move_sel
no_down:
    cmp #KEY_RET
    bne no_ret
    jmp do_return
no_ret:
    cmp #KEY_STOP
    beq back_col
    cmp #KEY_DEL
    beq back_col
    cmp #KEY_LEFT
    beq back_col
    cmp #KEY_PLUS
    bne no_plus
    jsr reveal_next
    sec
    rts
no_plus:
    cmp #KEY_MINUS
    beq snap_back
    cmp #KEY_STAR
    beq snap_back
    cmp #KEY_RIGHT
    bne ignored
    jmp enter_missions
ignored:
    sec
    rts
back_col:
    lda #0
    sta ui_col
    sec
    rts
snap_back:
    lda #0
    sta ui_extra
    jsr clamp_cursor
    sec
    rts
.endproc

; A = +1 or $FF. Moves inside the active column. Carry set. Trashes A, X, Y.
.proc move_sel
    ldx ui_col
    bne move_m
    jsr move_map
    sec
    rts
move_m:
    jsr move_miss
    sec
    rts
.endproc

; A = step. Trashes A, X, and Y.
.proc move_map
    sta zA4
    lda ui_map
walk:
    clc
    adc zA4
    cmp map_count
    bcs mdone
    sta zT4
    pha
    ldx zT4
    jsr map_has_shown
    pla
    bcc walk
    sta ui_map
    jsr focus_mission
mdone:
    rts
.endproc

; A = step. Trashes A, X, and Y.
.proc move_miss
    sta zA4
    lda ui_miss
    sta zT7
walkm:
    lda zT7
    clc
    adc zA4
    cmp miss_count
    bcs mdone
    sta zT7
    tax
    lda miss_map,x
    cmp ui_map
    bne walkm
    jsr miss_shown
    bcc walkm
    stx ui_miss
mdone:
    rts
.endproc

; Return on a map enters its mission list. Return on a mission leaves to play.
; Carry clear means launch. Trashes A, X, and Y.
.proc do_return
    lda ui_col
    bne launch
    jmp enter_missions
launch:
    lda ui_miss
    sta menu_played
    clc
    rts
.endproc

; Move onto the mission column and land on its open row. Already there is
; a no-op, so a right press does not launch. Carry set. Trashes A, X, and Y.
.proc enter_missions
    lda ui_col
    bne stay
    ldx ui_map
    jsr map_has_shown
    bcc stay
    lda #1
    sta ui_col
    jsr focus_mission
stay:
    sec
    rts
.endproc

; Reveal one more mission for this sitting and put the bar on it.
; Trashes A, X, and Y.
.proc reveal_next
    jsr frontier_of
    clc
    adc #1
    bcs rev_done
    adc ui_extra
    bcs rev_done
    cmp miss_count
    bcs rev_done
    inc ui_extra
    jsr frontier_of
    clc
    adc ui_extra
    sta ui_miss
    tax
    lda miss_map,x
    sta ui_map
    lda #1
    sta ui_col
rev_done:
    rts
.endproc

; Drop the session reveal. If the bar sat on a hidden row, move to the open one.
; Trashes A, X, and Y.
.proc clamp_cursor
    ldx ui_miss
    jsr miss_shown
    bcs clamp_ok
    jsr frontier_of
    cmp miss_count
    bcc use_front
    lda miss_count
    beq clamp_ok
    sec
    sbc #1
use_front:
    sta ui_miss
    tax
    lda miss_map,x
    sta ui_map
clamp_ok:
    rts
.endproc

; Bar prefers the open mission when it is on ui_map, else the first shown one.
; Trashes A, X, and Y.
.proc focus_mission
    jsr frontier_of
    cmp miss_count
    bcs first_of
    tax
    lda miss_map,x
    cmp ui_map
    bne first_of
    stx ui_miss
    rts
first_of:
    ldx #0
scan:
    cpx miss_count
    bcs focus_done
    lda miss_map,x
    cmp ui_map
    bne scan_next
    jsr miss_shown
    bcc scan_next
    stx ui_miss
    rts
scan_next:
    inx
    jmp scan
focus_done:
    rts
.endproc

; Clear every score and the session reveal. The bar returns to the first map.
; Trashes A and X.
.proc reset_scores
    ldx #0
    lda #$FF
wipe:
    cpx miss_count
    bcs wiped
    sta miss_score,x
    inx
    jmp wipe
wiped:
    lda #0
    sta ui_extra
    sta ui_col
    sta ui_map
    sta ui_miss
    sta ui_f8
    rts
.endproc

; A comes back as the first mission with no score, or miss_count. Trashes X and Y.
.proc frontier_of
    ldx #0
fr:
    cpx miss_count
    bcs fr_done
    lda miss_score,x
    cmp #$FF
    beq fr_done
    inx
    jmp fr
fr_done:
    txa
    rts
.endproc

; X = mission index. Carry set when that row is on the page. Preserves X.
; Trashes A and Y.
.proc miss_shown
    stx zT0
    txa
    pha
    jsr frontier_of
    clc
    adc #1
    bcs sh_no
    adc ui_extra
    bcs sh_no
    cmp zT0
    beq sh_no
    bcc sh_no
    pla
    tax
    sec
    rts
sh_no:
    pla
    tax
    clc
    rts
.endproc

; X = map index on entry, also passed in zT4 by some callers. Carry set when
; any shown mission belongs to it. Trashes A and Y. Preserves X.
.proc map_has_shown
    stx zT4
    txa
    pha
    ldy #0
hs:
    cpy miss_count
    bcs hs_no
    lda miss_map,y
    cmp zT4
    bne hs_next
    tya
    tax
    jsr miss_shown
    bcs hs_yes
hs_next:
    iny
    jmp hs
hs_yes:
    pla
    tax
    sec
    rts
hs_no:
    pla
    tax
    clc
    rts
.endproc

camp_name:
    .byte "CAMPAIGN"
camp_name_len = * - camp_name
save_name:
    .byte "@:CAMPAIGN"
save_name_len = * - save_name

title_s:
    .byte "FORCE - WWII RTS", 0
hdr_map:
    .byte "Map:", 0
mis_h:
    .byte "Missions:", 0
sur_h:
    .byte "Survivors:", 0
credit_s:
    .byte "Stefan Wessels, 2026", 0
f8_s:
    .byte "F8 AGAIN TO RESET", 0
save_s:
    .byte "SAVE FAILED", 0
saving_s:
    .byte "SAVING", 0
load_s:
    .byte "LOADING", 0

map_count:  .byte 0
map_nlen:   .res MAP_MAX, 0
map_names:  .res MAP_MAX * NAME_MAX, 0
miss_count: .byte 0
miss_map:   .res MISS_MAX, 0
miss_ord:   .res MISS_MAX, 0
miss_score: .res MISS_MAX, 0
miss_idlen: .res MISS_MAX, 0
miss_id:    .res MISS_MAX * NAME_MAX, 0
miss_tlen:  .res MISS_MAX, 0
miss_title: .res MISS_MAX * (TITLE_MAX + 1), 0

ui_extra:   .byte 0
ui_col:     .byte 0
ui_map:     .byte 0
ui_miss:    .byte 0
ui_f8:      .byte 0
ui_save:    .byte 0
ui_need_save: .byte 0
menu_played:.byte 0
launch_map: .byte 0
resident:   .byte $FF
cat_load_name: .res 16, 0
font_swapped:.byte 0
parse_err:  .byte 0
camp_n:     .byte 0
tok_n:      .byte 0
win_skip:   .byte 0
passed:     .byte 0
camp_line:  .res LINE_MAX, 0
camp_end:   .word 0
; Scratch for the campaign program image. $1C00 is the map loader's
; geometry image, and only while a bundle is being placed. The catalog
; load finishes before that, and a save runs after the image is dead.
camp_file   = $1C00
camp_limit  = $2000
tok_buf:    .res NAME_MAX, 0
menu_now:   .res 8, 0
menu_prev:  .res 8, $FF
menu_edge:  .res 8, 0
menu_joy:   .byte $FF
menu_joy_prev: .byte $FF
menu_joy_edge: .byte 0
