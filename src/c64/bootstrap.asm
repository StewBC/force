; Launchable title-only PRG. Game chunks are transferred through $A000 and
; consumed one at a time. Manifest pins format, compatibility and placement.
.include "generated/layout.inc"
.segdef "ZP", $02, noemit
.segdef "BASIC", $0801
.segdef "BOOT", $080D
.segdef "MANIFEST", $1C00
.segdef "ASSETS", $2000
.segment "ZP"
.include "zp.asm"
.segment "BASIC"
    .word $080B,10
    .byte $9E,"2061",0
    .word 0
.segment "BOOT"
    sei
    cld
    ldx #$FF
    txs
    lda #$36
    sta $01
    lda #$7F
    sta $DC0D
    sta $DD0D
    lda $DC0D
    lda $DD0D
    lda #0
    sta $D01A
    sta $D015
    sta $D020
    lda #$0B
    sta $D011
    ; Writes under visible ROM reach RAM; no hidden-ROM interrupt window.
    lda #<boot_bitmap
    sta zSrc
    lda #>boot_bitmap
    sta zSrc+1
    lda #$00
    sta zDst
    lda #$E0
    sta zDst+1
    lda #$40
    sta zT0
    lda #$1F
    sta zT1
    jsr boot_copy
    lda #<boot_screen
    sta zSrc
    lda #>boot_screen
    sta zSrc+1
    lda #0
    sta zDst
    lda #$CC
    sta zDst+1
    jsr cells
    lda #0
    sta zDst
    lda #$D8
    sta zDst+1
    jsr cells
    lda $DD00
    and #$FC
    sta $DD00
    lda #$38
    sta $D018
    lda #$D8
    sta $D016
    lda #0
    sta $D021
    lda #$3B
    sta $D011
    ; Title is now visible. No game code was present in the initial PRG.
boot_title_visible:
    lda #<startup_entries
    sta entry_ptr
    lda #>startup_entries
    sta entry_ptr+1
    lda #0
    sta chunk_index
next_chunk:
    lda #1
    ldx #8
    ldy #0
    jsr $FFBA
    lda chunk_index
    clc
    cmp #10
    bcc :+
    adc #6
:
    clc
    adc #$30
    sta game_name+5
    lda #6
    ldx #<game_name
    ldy #>game_name
    jsr $FFBD
    lda #<TRANSFER_HOME
    sta zDst
    lda #>TRANSFER_HOME
    sta zDst+1
    lda #<(TRANSFER_HOME+TRANSFER_HOME_CAP)
    sta zPtr
    lda #>(TRANSFER_HOME+TRANSFER_HOME_CAP)
    sta zPtr+1
    jsr read_file
    bcc :+
    jmp boot_fail
:
    stx zA0
    sty zA1
    ; All 16 file header bytes must match the compiled placement contract.
    lda entry_ptr
    sta zPtr
    lda entry_ptr+1
    sta zPtr+1
    ldy #0
header:
    lda TRANSFER_HOME,y
    cmp (zPtr),y
    beq :+
    jmp boot_fail
:
    iny
    cpy #16
    bne header
    clc
    lda TRANSFER_HOME+12
    adc #16
    sta zT0
    lda TRANSFER_HOME+13
    adc #>TRANSFER_HOME
    sta zT1
    lda zT0
    cmp zA0
    beq :+
    jmp boot_fail
:
    lda zT1
    cmp zA1
    beq :+
    jmp boot_fail
:
    ldy #16
    lda (zPtr),y
    sta zDst
    iny
    lda (zPtr),y
    sta zDst+1
    lda zDst
    sta dest_home
    lda zDst+1
    sta dest_home+1
    lda #<(TRANSFER_HOME+16)
    sta zSrc
    lda #>(TRANSFER_HOME+16)
    sta zSrc+1
    lda TRANSFER_HOME+12
    sta zT0
    lda TRANSFER_HOME+13
    sta zT1
    lda TRANSFER_HOME+8
    beq raw
    lda TRANSFER_HOME+10
    sta zT2
    lda TRANSFER_HOME+11
    sta zT3
    jsr boot_decode
    jmp verify
raw:
    jsr boot_copy
verify:
    lda dest_home
    sta zSrc
    lda dest_home+1
    sta zSrc+1
    lda TRANSFER_HOME+10
    sta zT0
    lda TRANSFER_HOME+11
    sta zT1
    lda #0
    sta check_byte
sum:
    lda zT0
    ora zT1
    beq summed
    jsr lz_take
    eor check_byte
    sta check_byte
    jmp sum
summed:
    lda check_byte
    cmp TRANSFER_HOME+14
    beq :+
    jmp boot_fail
:
    clc
    lda entry_ptr
    adc #18
    sta entry_ptr
    bcc :+
    inc entry_ptr+1
:
    inc chunk_index
    lda chunk_index
    cmp #STARTUP_COUNT
    beq :+
    jmp next_chunk
:
boot_ready:
    jmp $4000
boot_fail:
    sei
    lda #$36
    sta $01
    lda #2
    sta $D020
    jmp boot_error
cells:
    lda #$E8
    sta zT0
    lda #3
    sta zT1
    jmp boot_copy
entry_ptr: .word 0
chunk_index: .byte 0
dest_home: .word 0
check_byte: .byte 0
game_name: .byte "GAME00"

; zSrc/zDst, zT0/1 length. Advances pointers; zero length accepted.
.proc boot_copy
    lda zT0
    ora zT1
    beq done
    ldy #0
next:
    lda (zSrc),y
    sta (zDst),y
    inc zSrc
    bne :+
    inc zSrc+1
:
    inc zDst
    bne :+
    inc zDst+1
:
    lda zT0
    bne :+
    dec zT1
:
    dec zT0
    lda zT0
    ora zT1
    bne next
done:
    rts
.endproc

.proc lz_take
    lda zT0
    ora zT1
    beq lz_bad
    ldy #0
    lda (zSrc),y
    inc zSrc
    bne :+
    inc zSrc+1
:
    pha
    lda zT0
    bne :+
    dec zT1
:
    dec zT0
    pla
    rts
.endproc

; Status 6. Sits here so the decoder's bad-offset branch stays in range.
lz_bad:
    jmp boot_fail


.proc boot_decode
    lda zDst
    sta zT4
    clc
    adc zT2
    sta zT2
    lda zDst+1
    sta zT5
    adc zT3
    sta zT3
    lda #0
    sta zA1
    tax
lz_loop:
    lda zDst
    cmp zT2
    bne lz_go
    lda zDst+1
    cmp zT3
    bne lz_go
    txa
    bne lz_bad
    lda zT0
    ora zT1
    bne lz_bad
    clc
    rts
lz_go:
    txa
    bne lz_copy
    lsr zA1
    bne lz_have
    jsr lz_take
    sec
    ror
    sta zA1
lz_have:
    bcs lz_lit
    jsr lz_take
    sta zA2
    jsr lz_take
    pha
    and #$0F
    clc
    adc #3
    tax
    pla
    lsr
    lsr
    lsr
    lsr
    sta zA3
    ora zA2
    beq lz_bad
    sec
    lda zDst
    sbc zA2
    sta zPtr
    lda zDst+1
    sbc zA3
    sta zPtr+1
    lda zPtr
    cmp zT4
    lda zPtr+1
    sbc zT5
    bcc lz_bad
lz_copy:
    ldy #0
    lda (zPtr),y
    sta (zDst),y
    inc zDst
    bne :+
    inc zDst+1
:
    inc zPtr
    bne :+
    inc zPtr+1
:
    dex
    jmp lz_loop
lz_lit:
    jsr lz_take
    ldy #0
    sta (zDst),y
    inc zDst
    bne :+
    inc zDst+1
:
    jmp lz_loop
.endproc
.include "transfer_boot.inc"
boot_end:
.assert boot_end .le DECK_ORG, "bootstrap overwritten by installed deck"
.segment "MANIFEST"
.include "generated/startup.inc"
; Resident startup error renderer follows the pinned manifest. No game code
; is needed to show an error, including a missing or oversized first file.
.proc boot_error
    lda $DD00
    ora #3
    sta $DD00
    lda #$14
    sta $D018
    lda #$C8
    sta $D016
    lda #$1B
    sta $D011
    ldx #0
    lda #32
clear:
    sta $0400,x
    sta $0500,x
    sta $0600,x
    sta $0700,x
    inx
    bne clear
    ldx #9
message:
    lda boot_error_text,x
    sta $0540,x
    lda #2
    sta $D940,x
    dex
    bpl message
    ldx #5
file:
    lda game_name,x
    and #$3F
    sta $0568,x
    lda #2
    sta $D968,x
    dex
    bpl file
halt:
    jmp halt
.endproc
boot_error_text: .byte 12,15,1,4,32,5,18,18,15,18
.assert endof("MANIFEST") .le CHARSET, "bootstrap manifest exceeds scratch"
.segment "ASSETS"
boot_bitmap:
.incbin "generated/title_bitmap.bin"
boot_screen:
.incbin "generated/title_colour.bin"
