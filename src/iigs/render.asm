; Bank-local software cell rasterizer. Existing C64 compositor writes characters,
; colours and mutable unit glyphs; this boundary converts only changed cells.
; Input/output simulation widths. Uses its own scratch and D-page zPtr only.
                        longa  off
                        longi  off
render_frame            anop
                        rep    #$30
                        longa  on
                        longi  on
                        lda    menu_mode
                        and    #255
                        cmp    render_seen_mode
                        beq    render_mode_ok
                        sta    render_seen_mode
                        ldx    #1023
                        sep    #$20
                        longa  off
                        lda    #255
render_invalidate       sta    cached_glyph,x
                        sta    cached_colour,x
                        dex
                        bpl    render_invalidate
                        rep    #$20
                        longa  on
render_mode_ok          stz    render_buffer_index
                        jsr    render_dynamic_check
                        lda    cursor_y
                        and    #255
                        asl    a
                        asl    a
                        asl    a
                        sta    render_cursor
                        asl    a
                        asl    a
                        clc
                        adc    render_cursor
                        sta    render_cursor
                        lda    cursor_x
                        and    #255
                        clc
                        adc    render_cursor
                        sta    render_cursor
                        lda    menu_mode
                        and    #255
                        beq    render_game_cursor
                        lda    #$FFFF
                        sta    render_cursor
render_game_cursor      lda    render_cursor
                        and    #$FFFE
                        sta    render_cursor_pair
                        lda    render_previous_cursor
                        and    #$FFFE
                        sta    render_previous_pair
                        lda    #0
                        sta    render_index
                        sta    render_y
                        sta    render_row_start
                        lda    #40
                        sta    render_row_end
                        lda    #$2000
                        sta    render_row_address
                        ldx    #0
; Scan two cached cells at once in native16 mode. Only changed pairs,
; composite glyphs and the two cursor pairs need the individual-cell path.
render_row_loop         anop
render_pair_loop        lda    SCREEN,x
                        cmp    cached_glyph,x
                        bne    render_pair_slow
                        lda    COLORRAM,x
                        cmp    cached_colour,x
                        bne    render_pair_slow
                        lda    SCREEN,x
                        and    #$E0E0
                        cmp    #$E000
                        bcs    render_pair_slow
                        and    #$00E0
                        cmp    #$00E0
                        beq    render_pair_slow
                        cpx    render_cursor_pair
                        beq    render_pair_slow
                        cpx    render_previous_pair
                        beq    render_pair_slow
                        inx
                        inx
                        jmp    render_pair_advance
render_pair_slow        txa
                        clc
                        adc    #2
                        sta    render_pair_end
                        sep    #$20
                        longa  off
render_cell_loop        lda    SCREEN,x
                        cmp    cached_glyph,x
                        bne    render_changed
                        lda    COLORRAM,x
                        cmp    cached_colour,x
                        bne    render_changed
                        lda    SCREEN,x
                        cmp    #224
                        bcc    render_cursor_check
                        phx
                        rep    #$20
                        longa  on
                        and    #255
                        sec
                        sbc    #224
                        asl    a
                        tax
                        sep    #$20
                        longa  off
                        lda    render_dynamic_flags,x
                        plx
                        cmp    #0
                        bne    render_changed
render_cursor_check     cpx    render_cursor
                        beq    render_changed
                        cpx    render_previous_cursor
                        beq    render_changed
render_scan_next        inx
                        cpx    render_pair_end
                        bcc    render_cell_loop
                        rep    #$20
                        longa  on
render_pair_advance     cpx    render_row_end
                        bcc    render_pair_loop
                        stx    render_index
                        lda    render_row_end
                        sta    render_row_start
                        clc
                        adc    #40
                        sta    render_row_end
                        lda    render_row_address
                        clc
                        adc    #1280
                        sta    render_row_address
                        inc    render_y
                        lda    render_y
                        cmp    #25
                        bcs    render_frame_complete
                        jmp    render_row_loop
render_frame_complete   jmp    render_rows_done
render_changed          rep    #$20
                        longa  on
                        stx    render_index
                        txa
                        sec
                        sbc    render_row_start
                        sta    render_x
                        asl    a
                        asl    a
                        clc
                        adc    render_row_address
                        sta    render_address
                        sep    #$20
                        longa  off
                        lda    #0
                        sta    render_is_cursor
                        cpx    render_cursor
                        bne    render_cursor_known
                        lda    #1
                        sta    render_is_cursor
render_cursor_known     lda    SCREEN,x
                        sta    render_glyph
                        sta    cached_glyph,x
                        lda    COLORRAM,x
                        sta    cached_colour,x
                        and    #7
                        sta    render_paper
                        asl    a
                        asl    a
                        asl    a
                        asl    a
                        ora    render_paper
                        sta    render_paper
                        lda    COLORRAM,x
                        and    #15
                        sta    render_ink
; Static terrain has its own compiled immediate-push routines. The composed
; cursor/unit glyph path remains below and shares exactly the same palette.
                        lda    menu_mode
                        bne    render_generic
                        lda    render_y
                        cmp    #20
                        bcs    render_generic
                        lda    render_glyph
                        cmp    #128
                        bcs    render_generic
                        lda    render_is_cursor
                        bne    render_generic
render_compiled         rep    #$20
                        longa  on
                        lda    render_glyph
                        and    #255
                        asl    a
                        tax
                        lda    tile_frames,x
                        tax
                        lda    render_address
                        tay
                        lda    render_paper
                        and    #255
                        sta    render_paper_word
                        xba
                        ora    render_paper_word
                        jsl    draw_tile
                        jmp    render_skip
render_generic          rep    #$20
                        longa  on
                        lda    menu_mode
                        and    #255
                        bne    render_lookup_hires
                        lda    render_y
                        cmp    #20
                        bcs    render_lookup_hires
                        lda    render_paper
                        and    #7
                        xba
                        asl    a
                        asl    a
                        sta    render_lookup_offset
                        bra    render_lookup_ready
render_lookup_hires     lda    render_ink
                        and    #15
                        xba
                        asl    a
                        asl    a
                        clc
                        adc    #8192
                        sta    render_lookup_offset
                        lda    menu_mode
                        and    #255
                        bne    render_lookup_ready
                        lda    render_y
                        cmp    #24
                        bcc    render_lookup_ready
                        lda    render_lookup_offset
                        clc
                        adc    #16384
                        sta    render_lookup_offset
render_lookup_ready     lda    render_glyph
                        and    #255
                        asl    a
                        asl    a
                        asl    a
                        tay
                        copy   build/iigs/cellpack.s
                        sep    #$20
                        longa  off
render_pixels_done      anop
; Cyan 8x8 cursor, same frame_lo blink phase as C64 sprite.
                        lda    menu_mode
                        bne    render_no_cursor
                        lda    render_is_cursor
                        beq    render_no_cursor
                        lda    frame_lo
                        and    #8
                        beq    render_cursor_outline
                        ldx    #31
                        lda    #$33
render_cursor_fill      sta    render_buffer,x
                        dex
                        bpl    render_cursor_fill
                        bra    render_no_cursor
render_cursor_outline   ldx    #3
                        lda    #$33
render_cursor_edges     sta    render_buffer,x
                        sta    render_buffer+28,x
                        dex
                        bpl    render_cursor_edges
                        ldx    #4
render_cursor_sides     lda    render_buffer,x
                        and    #$0F
                        ora    #$30
                        sta    render_buffer,x
                        lda    render_buffer+3,x
                        and    #$F0
                        ora    #3
                        sta    render_buffer+3,x
                        inx
                        inx
                        inx
                        inx
                        cpx    #28
                        bcc    render_cursor_sides
render_no_cursor        rep    #$20
                        longa  on
                        jsr    stack_cell
render_skip             rep    #$20
                        longa  on
                        stz    render_buffer_index
                        ldx    render_index
                        sep    #$20
                        longa  off
                        jmp    render_scan_next
                        longa  on
render_rows_done        lda    render_row_address
                        sta    render_address
                        lda    #40
                        sta    render_x
                        lda    render_cursor
                        sta    render_previous_cursor
                        sep    #$30
                        longa  off
                        longi  off
                        rts

; Internal native16 helper. Compare each live composite glyph once per frame.
; A stationary soldier whose pixels did not change needs no hardware repaint.
                        longa  on
                        longi  on
render_dynamic_check    anop
                        ldx    #0
                        ldy    #0
render_dynamic_loop     lda    #0
                        sta    render_dynamic_flags,y
                        lda    CHARSET+1792,x
                        cmp    cached_dynamic,x
                        bne    render_dynamic_changed
                        lda    CHARSET+1794,x
                        cmp    cached_dynamic+2,x
                        bne    render_dynamic_changed
                        lda    CHARSET+1796,x
                        cmp    cached_dynamic+4,x
                        bne    render_dynamic_changed
                        lda    CHARSET+1798,x
                        cmp    cached_dynamic+6,x
                        beq    render_dynamic_next
render_dynamic_changed  lda    #1
                        sta    render_dynamic_flags,y
                        lda    CHARSET+1792,x
                        sta    cached_dynamic,x
                        lda    CHARSET+1794,x
                        sta    cached_dynamic+2,x
                        lda    CHARSET+1796,x
                        sta    cached_dynamic+4,x
                        lda    CHARSET+1798,x
                        sta    cached_dynamic+6,x
render_dynamic_next     txa
                        clc
                        adc    #8
                        tax
                        iny
                        iny
                        cpx    #256
                        bcc    render_dynamic_loop
                        rts

; Fixed aligned 8x8 stack blitter. Wrapper owns the whole moved-stack interval.
; Preserves P, DBR, D and S; masks IRQs before relocating S to bank $01.
; No JSR/JSL/Toolbox/interruptible operations occur while S addresses pixels.
stack_cell              anop
                        php
                        sei
                        rep    #$30
                        longa  on
                        longi  on
                        phb
                        phd
                        tsc
                        sta    render_saved_stack
                        sep    #$20
                        longa  off
                        lda    >$E0C068
                        sta    render_saved_state
                        ora    #$30
                        sta    >$E0C068
                        rep    #$20
                        longa  on
                        lda    render_address
                        clc
                        adc    #1123
                        tcs
                        copy   build/iigs/stack.s
                        lda    render_saved_stack
                        tcs
                        sep    #$20
                        longa  off
                        lda    render_saved_state
                        sta    >$E0C068
                        rep    #$20
                        longa  on
                        pld
                        plb
                        plp
                        rts

mc_pairs                dc     h'22BBEEFF'
render_seen_mode        dc     i2'$FFFF'
render_cursor_pair      ds     2
render_previous_pair    ds     2
render_pair_end         ds     2
render_cursor           ds     2
render_row_start        ds     2
render_row_end          ds     2
render_row_address      ds     2
render_is_cursor        ds     1
render_dynamic_flags    ds     64
cached_dynamic          ds     256
render_index            ds     2
render_previous_cursor  dc     i2'$FFFF'
render_address          ds     2
render_x                ds     2
render_y                ds     2
render_glyph            ds     2
render_lookup_offset    ds     2
render_paper_word       ds     2
render_paper            ds     2
render_ink              ds     2
render_bg               ds     1
render_bits             ds     1
render_pixel            ds     1
render_buffer_index     ds     2
render_buffer           ds     32
render_saved_stack      ds     2
render_saved_state      ds     1
cached_glyph            ds     1024
cached_colour           ds     1024

