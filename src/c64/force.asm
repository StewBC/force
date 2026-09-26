; FORCE Hold the Farm — C64 vertical slice.
; Assemble: am65 -i src/c64/force.asm -o force.prg --prg
; Play from repo root:
; ../machines/build/c64m -P -a -p build/force.prg --disk 8=build/c64
;
; Every .proc is preceded by a comment that states its job and the
; registers or zero-page values it takes, returns, or preserves.

.include "equ.inc"
.include "generated/homes.inc"

.segdef "ZEROPAGE", $02, noemit
.segdef "BASIC", $0801, locked
.segdef "BOOT", $080D, locked
; Title-only SID player, score, and state. map_load later replaces this
; workspace with the packed mission, so music_stop must run before show_title returns.
.segdef "TITLE_MUSIC", $0900, reclaimable
.segdef "CHARSET", $2000, locked
.segdef "SPRITE", $3F80, locked
.segdef "CODE", $4000
; Flush with the last CODE byte. Moves with CODE; no zero gap in the PRG.
.segdef "TITLE", after="CODE", reclaimable
; Variables grow down from the last RAM byte under the I/O registers.
; The title segment is reclaimable and is placed flush after CODE, so once
; it crosses $C000 it may share these addresses. show_title copies it away
; before clear_bss. $01=$36 keeps code under the BASIC window executable.
.segdef "BSS", end=$CFFF, noemit, overlap_reclaimable
; 40*20 occupancy filled by build_occ. Locked so it stays put under BSS.
.segdef "OCC", $C000, noemit, locked, overlap_reclaimable
; Charset-to-sprite gap. CODE is followed immediately by TITLE.
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
    ; Splash. Comment out this jsr to boot straight into the mission.
    jsr show_title
    ; Blank before any colour write. The first paint fills colour RAM,
    ; and an open display shows that sweep. This is also the blank after
    ; the title key. F3 does not return here.
    lda #0
    sta $D020
    sta $D015
    lda #$0B
    sta $D011
    jsr irq_init
    jsr vic_init
    ; clear_bss and mission 0 run inside map_load. F3 does not come back here.
    jsr map_load
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
.include "music.asm"
.include "title.asm"
.include "generated/tileset.asm"
.include "load.asm"

; 8000 bitmap bytes, then 1000 screen bytes, then 1000 colour nybbles.
.segment "TITLE"
title_bitmap:
.incbin "generated/title_bitmap.bin"
title_screen:
.incbin "generated/title_colour.bin"
title_colour = title_screen + 1000

.segment "BSS"
.include "bss.asm"
