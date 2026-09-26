; LOAD "PROBE",8,1 into $A000 and halt at probe_ok or probe_fail.
; The program stays at $0801. $A000 is only the loaded payload.
;
; Data file (host name probe.prg, CBM name PROBE), 18 bytes:
;   00 A0  then the 16 payload bytes below. Exclusive end is $A010.
; Payload:
;   01 02 03 04 05 06 07 08 09 0A 0B 0C 0D 0E 0F 10
;
; probe_status, stored before probe_fail:
;   1  KERNAL A=$04 file not found
;   2  KERNAL A=$05 device or read error
;   3  exclusive end in X/Y is not $A010
;   4  payload at $A000 does not match
;   5  carry set with any other KERNAL A
;
; 10 SYS 2061. 2061 is $080D, the first CODE byte.

.segdef "BASIC", $0801, locked
.segdef "CODE", $080D, locked

.segment "BASIC"
    .word $080B
    .word 10
    .byte $9E
    .byte "2061"
    .byte 0
    .word 0

.segment "CODE"
    ; $A000 is BASIC ROM while $01=$37. $36 keeps KERNAL and shows that RAM.
    lda #$36
    sta $01
    lda #1
    ldx #8
    ldy #1
    jsr $FFBA
    lda #5
    ldx #<probe_name
    ldy #>probe_name
    jsr $FFBD
    lda #0
    jsr $FFD5
    bcc loaded
    cmp #$04
    beq not_found
    cmp #$05
    beq dev_err
    lda #5
    bne store
not_found:
    lda #1
    bne store
dev_err:
    lda #2
    bne store
loaded:
    cpx #$10
    bne bad_end
    cpy #$A0
    bne bad_end
    ldx #0
next:
    lda $A000,x
    cmp probe_expect,x
    bne bad_payload
    inx
    cpx #16
    bne next
    jmp probe_ok
bad_end:
    lda #3
    bne store
bad_payload:
    lda #4
store:
    sta probe_status
probe_fail:
    jmp probe_fail
probe_ok:
    jmp probe_ok

probe_name:
    .byte "PROBE"
probe_expect:
    .byte $01,$02,$03,$04,$05,$06,$07,$08
    .byte $09,$0A,$0B,$0C,$0D,$0E,$0F,$10
probe_status:
    .byte 0
