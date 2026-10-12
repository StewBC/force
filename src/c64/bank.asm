; Bounded storage access beneath KERNAL. Call only with gameplay readers
; quiescent. Non-nesting. Preserves $00/$01 and caller I flag; I/O stays on.
; A/X/Y and zPtr scratch. CIA2 NMI sources are disabled at startup; RESTORE
; uses a RAM RTI trampoline while KERNAL is hidden. No KERNAL calls in bank.
.segment "CODE"
bank_port: .byte 0
bank_ddr: .byte 0
bank_flags: .byte 0
bank_active: .byte 0
.proc bank_enter
    php
    pla
    sta bank_flags
    sei
    lda $00
    sta bank_ddr
    ora #7
    sta $00
    lda $01
    sta bank_port
    and #$F8
    ora #5
    sta $01
    lda #1
    sta bank_active
    rts
.endproc
.proc bank_leave
    lda bank_port
    sta $01
    lda bank_ddr
    sta $00
    lda #0
    sta bank_active
    lda bank_flags
    pha
    plp
    rts
.endproc
; Install RAM vectors with ROM still visible (writes reach underlying RAM).
; IRQ is masked in bank_enter. NMI acknowledges CIA2 and preserves A.
.proc bank_vectors
    lda #$7F
    sta $DD0D
    lda $DD0D
    lda #<bank_nmi
    sta $FFFA
    lda #>bank_nmi
    sta $FFFB
    lda #<bank_reset
    sta $FFFC
    lda #>bank_reset
    sta $FFFD
    lda #<bank_nmi
    sta $FFFE
    lda #>bank_nmi
    sta $FFFF
    rts
.endproc
.proc bank_nmi
    pha
    lda $DD0D
    pla
    rti
.endproc
.proc bank_reset
    sei
    lda #$36
    sta $01
    jmp ($FFFC)
.endproc
