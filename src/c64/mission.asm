; Mission collection entry ABI: offset/stored/expanded/body u16, codec,
; XOR integrity. Bank is entered by caller, IRQ readers quiescent.
; prepare_mission validates bounds before any workspace write. z* scratch.
.segment "CODE"
mission_entry: .res 10, 0
mission_checksum: .byte 0

.segment "SPARE"
.proc prepare_mission
    ; Source must follow the complete directory.
    lda INDEX_HOME+6
    asl
    sta zT0
    asl
    asl
    clc
    adc zT0
    adc #6
    sta zT0
    lda #0
    adc #0
    cmp mission_entry+1
    bcc offset_ok
    bne bad
    lda mission_entry
    cmp zT0
    bcc bad
offset_ok:
    clc
    lda mission_entry
    adc mission_entry+2
    sta zT0
    lda mission_entry+1
    adc mission_entry+3
    bcs bad
    cmp ck_len+3
    bcc source_ok
    bne bad
    lda zT0
    cmp ck_len+2
    bcc source_ok
    beq source_ok
bad:
    jmp fail7
source_ok:
    lda mission_entry+2
    ora mission_entry+3
    beq bad
    lda mission_entry+5
    cmp #>PACK_HOME_CAP
    bcc size_ok
    bne bad
    lda mission_entry+4
    cmp #<(PACK_HOME_CAP+1)
    bcs bad
size_ok:
    lda mission_entry+7
    cmp mission_entry+5
    bcc body_ok
    bne bad
    lda mission_entry+6
    cmp mission_entry+4
    bcc body_ok
    bne bad
body_ok:
    jsr quiesce_mission
    lda mission_entry+6
    sta plen
    lda mission_entry+7
    sta plen+1
    clc
    lda mission_entry
    adc #<COLLECTION_HOME
    sta zSrc
    lda mission_entry+1
    adc #>COLLECTION_HOME
    sta zSrc+1
    lda mission_entry+2
    sta zT0
    lda mission_entry+3
    sta zT1
    lda #<PACK_HOME
    sta zDst
    lda #>PACK_HOME
    sta zDst+1
    lda mission_entry+8
    cmp #1
    beq compressed
    cmp #0
    bne bad
    lda zT0
    cmp mission_entry+4
    bne bad
    lda zT1
    cmp mission_entry+5
    bne bad
    jsr memmove
    jmp integrity
compressed:
    lda mission_entry+4
    sta zT2
    lda mission_entry+5
    sta zT3
    jsr lzss_sized
integrity:
    lda #<PACK_HOME
    sta zSrc
    lda #>PACK_HOME
    sta zSrc+1
    lda mission_entry+4
    sta zT0
    lda mission_entry+5
    sta zT1
    lda #0
    sta mission_checksum
    ldy #0
check:
    lda zT0
    ora zT1
    beq checked
    lda (zSrc),y
    eor mission_checksum
    sta mission_checksum
    inc zSrc
    bne :+
    inc zSrc+1
:
    lda zT0
    bne :+
    dec zT1
:
    dec zT0
    jmp check
checked:
    lda mission_checksum
    cmp mission_entry+9
    beq done
    jmp fail7
done:
    jsr validate_record
    jmp relocate_objectives
.endproc

; Validate text before resolving relative offsets into the immutable workspace.
; Called after count/body checks, before any scatter. A/X/Y/z* scratch.
.segment "BANK_VALIDATION"
.proc relocate_objectives
    lda cnt_spawn
    asl
    clc
    adc cnt_spawn
    adc #20
    sta zT4
    lda cnt_op
    clc
    adc zT4
    sta zT5
    lda cnt_op
    clc
    adc zT5
    sta zT6
    ; Operand columns can cross a page; use full pointers.
    lda #<PACK_HOME
    clc
    adc zT5
    sta zPtr2
    lda #>PACK_HOME
    adc #0
    sta zPtr2+1
    lda #<PACK_HOME
    clc
    adc zT6
    sta zDst
    lda #>PACK_HOME
    adc #0
    sta zDst+1
    lda #<PACK_HOME
    clc
    adc zT4
    sta zSrc
    lda #>PACK_HOME
    adc #0
    sta zSrc+1
    ldx #0
next:
    cpx cnt_op
    bne :+
    jmp done
:
    ldy #0
    lda (zSrc),y
    cmp #10
    bne advance
    lda (zPtr2),y
    sta zA0
    lda (zDst),y
    sta zA1
    ; Text must be after scatter body and within expanded record.
    cmp plen+1
    bcc bad
    bne text_start
    lda zA0
    cmp plen
    bcc bad
text_start:
    lda zA1
    cmp mission_entry+5
    bcc text_inside
    bne bad
    lda zA0
    cmp mission_entry+4
    bcs bad
text_inside:
    clc
    lda zA0
    adc #<PACK_HOME
    sta zPtr
    lda zA1
    adc #>PACK_HOME
    sta zPtr+1
    ; Exact expanded end, never read beyond it.
    lda mission_entry+4
    sta zT0
    lda mission_entry+5
    clc
    adc #>PACK_HOME
    sta zT1
    ldy #0
text:
    tya
    clc
    adc zPtr
    sta zA2
    lda zPtr+1
    adc #0
    cmp zT1
    bcc read
    bne bad
    lda zA2
    cmp zT0
    bcs bad
read:
    lda (zPtr),y
    beq terminated
    cmp #32
    bcc bad
    cmp #127
    bcs bad
    iny
    cpy #39
    bcc text
bad:
    jmp fail7
terminated:
    cpy #0
    beq bad
    ldy #0
    lda zPtr
    sta (zPtr2),y
    lda zPtr+1
    sta (zDst),y
advance:
    inc zSrc
    bne :+
    inc zSrc+1
:
    inc zPtr2
    bne :+
    inc zPtr2+1
:
    inc zDst
    bne :+
    inc zDst+1
:
    inx
    jmp next
done:
    lda #<PACK_HOME
    sta zPtr
    lda #>PACK_HOME
    sta zPtr+1
    rts
.endproc

.include "record.asm"
bank_validation_end:
.assert bank_validation_end .le COLLECTION_HOME, "banked validator overlaps collection"
