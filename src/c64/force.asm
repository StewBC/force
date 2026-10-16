; FORCE game intermediate — entered by the separately packaged bootstrap.
; Build: cmake --build build --target force_c64
; Play from repo root:
; ../machines/build/c64m -P -a -p build/force.prg --disk 8=build/c64
;
; Every .proc is preceded by a comment that states its job and the
; registers or zero-page values it takes, returns, or preserves.

.include "equ.inc"
.include "generated/homes.inc"

.include "generated/segments.inc"
.segdef "BOOT", $080D

.segment "OCC"
    .res $320

.segment "ZEROPAGE"
.include "zp.asm"

.segment "BASIC"
    .word $080B
    .word 10
    .byte $9E
    .byte "2061"
    .byte 0
    .word 0

.segment "BOOT"
    sei
    lda #$36
    sta $01
    cld
    ldx #$FF
    txs
    jmp main

.segment "CHARSET"
.incbin "generated/charset.bin"

.segment "SPRITE"
; 8x8 yellow box in the top-left of sprite 0. Interior blinks.
    .byte $FF,$00,$00
    .byte $81,$00,$00
    .byte $81,$00,$00
    .byte $81,$00,$00
    .byte $81,$00,$00
    .byte $81,$00,$00
    .byte $81,$00,$00
    .byte $FF,$00,$00
    .res 64-24, 0

.segment "CODE"
main:
    ; Bootstrap has installed the game while displaying the title. Load the
    ; catalog, start music, wait for RETURN, and release bitmap/matrix RAM.
    jsr show_title
menu_top:
    jsr menu_open
    jsr menu_loop
    jsr menu_launch
loop:
    ; Logic and the command take run every third video frame. The border
    ; IRQ has been latching keys on the frames in between.
    lda #$36
    sta $01
    jsr input_poll
    jsr game_tick
    lda in_leave
    bne to_menu
    jsr wait_ui
    jsr draw_all
    jmp loop
to_menu:
    sei
    jsr menu_commit
    jmp menu_top

;-----------------------------------------------------------------------------
; Clear all mutable state before any initializer reads it; end is exclusive.
.proc clear_bss
    lda #<bss_start
    sta zPtr
    lda #>bss_start
    sta zPtr+1
    ldy #0
next:
    lda #0                                     ; Pointer comparisons overwrite A on every pass
    sta (zPtr),y
    inc zPtr
    bne same
    inc zPtr+1
same:
    lda zPtr+1
    cmp #>bss_end
    bcc next
    bne done
    lda zPtr
    cmp #<bss_end
    bcc next
done:
    rts
.endproc

; Spin until the line-210 edge that closes this game frame.
; An edge left set by the logic pass is stale: the beam has already
; moved on, so that one is dropped and the next UI line is the draw.
.proc wait_ui
    lda #$36
    sta $01
    sei
    lda #0
    sta ui_edge
    cli
spin:
    lda ui_edge
    beq spin
    sei
    lda #0
    sta ui_edge
    lda ui_count
    cmp #FRAME_RASTERS
    bcc early
    lda #0
    sta ui_count
    cli
    rts
early:
    cli
    jmp spin
.endproc

.include "irq.asm"
.include "map.asm"
.include "draw.asm"
.include "input.asm"
.include "game.asm"
.include "command.asm"
.include "world.asm"
.include "move.asm"
.include "combat.asm"
.include "music.asm"
.include "title.asm"
.include "menu.asm"
.include "generated/tileset.asm"
.include "load.asm"
.include "deck.asm"
.include "tactics.asm"

.segment "BSS"
.include "bss.asm"

; Routing patch addresses are a pipeline contract. Fail rather than let a
; changed BSS layout redirect generated writes into unrelated world state.
.assert portal_from .eq ROUTE_PORTALS_HOME, "routing portal home moved"
.assert door_n .eq ROUTE_DOORS_HOME, "routing doorway home moved"
.assert door_lo-door_n .eq 2, "doorway image requires its reserved header byte"
.assert cb_i-door_n .eq 514, "doorway image stride/extent changed"
.assert endof("DECK") .le GEO_IMAGE, "deck overlaps loader scratch"
.assert endof("DECK") .le MENU_INDEX, "deck overlaps menu index"

.segment "CODE"
code_end:
.assert code_end .le $A000, "game code overlaps transfer/map tiles"
.segment "SPARE"
spare_end:
.assert spare_end .le SPRITE_DATA, "loader overlaps cursor"
.segment "DECK"
deck_end:
.segment "BRIDGE_DRAW"
gap_end:
