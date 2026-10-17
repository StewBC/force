; Original authored C64 title, expanded from 160 source pixels to 320 SHR pixels.
; Public routines use the simulation ABI and restore native register widths.
show_title anop
 lda #1
 sta title_mode
 rep #$20
 longa on
 lda #$FFFF
 sta render_seen_mode
 sep #$20
 longa off
 rep #$30
 longa on
 longi on
 ldx #0
title_copy lda >title_image,x
 sta >$E12000,x
 inx
 inx
 cpx #32000
 bcc title_copy
 ldx #30
title_palette_copy lda title_palette,x
 sta >$E19E00,x
 dex
 dex
 bpl title_palette_copy
 sep #$30
 longa off
 longi off
 rts

title_poll anop
 lda >$E0C000
 bmi title_key
 rts
title_key and #127
 sta title_ascii
 lda >$E0C010
 lda title_ascii
 cmp #$11
 bne title_continue
 jmp shutdown
title_continue cmp #13
 beq title_dismiss
 rts
title_dismiss lda #0
 sta title_mode
 jsr game_palette
 rep #$20
 longa on
 lda #$FFFF
 sta render_seen_mode
 sep #$20
 longa off
 rts

game_palette anop
 rep #$30
 longa on
 longi on
 ldx #30
game_palette_copy lda palette,x
 sta >$E19E00,x
 dex
 dex
 bpl game_palette_copy
 sep #$30
 longa off
 longi off
 rts

title_mode ds 1
title_ascii ds 1
