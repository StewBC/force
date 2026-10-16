; Resident load-error keyboard recovery; record validation lives in record.asm.
.segment "VALIDATE"

; Read keyboard row 0 with KERNAL/I/O visible. Mask the obsolete raster
; owner before title_row0 briefly opens IRQs.
.proc load_error_key
    lda #0
    sta $D01A
    jsr title_row0
    sei
    and #2
    rts
.endproc
validate_end:
.assert validate_end .le SCREEN, "disk validator exceeds cassette-buffer allocation"
