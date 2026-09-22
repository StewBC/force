; FORCE Hold the Farm — C64 vertical slice.
; Assemble: am65 -i src/c64/force.asm -o force.prg --prg
; Play:     c64m --prg force.prg -a --pal

.include "equ.inc"

.segdef "ZEROPAGE", $02, noemit
.segdef "BASIC", $0801, locked
.segdef "BOOT", $080D, locked
.segdef "CHARSET", $2000, locked
.segdef "SPRITE", $3F80, locked
.segdef "CODE", $4000
.segdef "BSS", $A000, noemit

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
    jsr clear_bss
    jsr irq_init
    jsr vic_init
    jsr world_load
    jsr session_init
    jsr draw_all
    cli
loop:
    lda #$36
    sta $01
    jsr wait_frame
    jsr input_poll
    jsr game_tick
    jsr draw_all
    jmp loop

.proc clear_bss
    lda #<bss_start
    sta zPtr
    lda #>bss_start
    sta zPtr+1
    ldy #0
    lda #0
next:
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

.proc wait_frame
wait:
    lda frame_flag
    beq wait
    lda #0
    sta frame_flag
    rts
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
