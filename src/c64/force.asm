; FORCE Hold the Farm — C64 vertical slice.
; Assemble: am65 -i src/c64/force.asm -o force.prg --prg
; Play:     c64m --prg force.prg -a --pal
;
; Every .proc is preceded by a comment that states its job and the
; registers or zero-page values it takes, returns, or preserves.

.include "equ.inc"

.segdef "ZEROPAGE", $02, noemit
.segdef "BASIC", $0801, locked
.segdef "BOOT", $080D, locked
.segdef "CHARSET", $2000, locked
.segdef "SPRITE", $3F80, locked
.segdef "CODE", $4000
; Variables grow down from the last RAM byte under the I/O registers.
; $A000–$BFFF is then free for code while $01=$36 keeps BASIC out.
.segdef "BSS", end=$CFFF, noemit
; 40*20 occupancy filled by build_occ. Locked so it stays put under BSS.
.segdef "OCC", $C000, noemit, locked
; Charset-to-sprite gap. CODE may continue through $BFFF and must stop
; before occupancy at $C000.
.segdef "SPARE", $2800

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
    ; Blank before any colour write. The first paint fills colour RAM,
    ; and an open display shows that sweep. F3 does not return here.
    lda #0
    sta $D020
    sta $D015
    lda #$0B
    sta $D011
    jsr clear_bss
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
loop:
    ; Logic and the command take run every third video frame. The border
    ; IRQ has been latching keys on the frames in between.
    lda #$36
    sta $01
    jsr input_poll
    jsr game_tick
    jsr wait_ui
    jsr draw_all
    jmp loop

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
.include "generated/farm.asm"

.segment "BSS"
.include "bss.asm"
