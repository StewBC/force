.segment "CODE"

; Boot splash. show_title is the only call. Comment that jsr out to
; boot straight into the mission. The picture bytes are the TITLE segment
; placed immediately after CODE (see force.asm). This copies them out and
; does not blank on the way out: main's existing blank is the post-key blank.
;
; VIC bank 3. Bitmap at $E000 (under the KERNAL). Screen matrix at $CC00.
; Colour nybbles at $D800. Background is black, the only shared colour.
; music_start installs a private raster IRQ once the picture is ready. A key
; is a matrix press after the picture is up; it starts a short audible fade.

BITMAP_AT   = $E000
SCREEN_AT   = $CC00
STAGE_AT    = $0400
COLOUR_AT   = $D800
BITMAP_LEN  = 8000
CELL_LEN    = 1000

; Copy zT1*256+zT0 bytes from zSrc to zDst, low to high.
; Trashes A, X, Y, and those four zero-page locations.
.proc copy_bytes
    ldy #0
    lda zT1
    beq tail
page:
    lda (zSrc),y
    sta (zDst),y
    iny
    bne page
    inc zSrc+1
    inc zDst+1
    dec zT1
    bne page
tail:
    ldx zT0
    beq done
one:
    lda (zSrc),y
    sta (zDst),y
    iny
    dex
    bne one
done:
    rts
.endproc

; Blank, show the title, wait until a key is pressed after the matrix is
; idle. Leaves the picture on screen until the fade completes, then removes
; the title IRQ and returns with IRQs masked. A, X, and Y are scratch.
.proc show_title
    lda #0
    sta $D020
    sta $D015
    lda #$0B
    sta $D011

    lda #<title_screen
    sta zSrc
    lda #>title_screen
    sta zSrc+1
    lda #<STAGE_AT
    sta zDst
    lda #>STAGE_AT
    sta zDst+1
    lda #<CELL_LEN
    sta zT0
    lda #>CELL_LEN
    sta zT1
    jsr copy_bytes

    lda #<title_colour
    sta zSrc
    lda #>title_colour
    sta zSrc+1
    lda #<COLOUR_AT
    sta zDst
    lda #>COLOUR_AT
    sta zDst+1
    lda #<CELL_LEN
    sta zT0
    lda #>CELL_LEN
    sta zT1
    jsr copy_bytes

    ; RAM under the KERNAL. $35 keeps I/O and the BASIC window as RAM.
    lda #$35
    sta $01
    lda #<title_bitmap
    sta zSrc
    lda #>title_bitmap
    sta zSrc+1
    lda #<BITMAP_AT
    sta zDst
    lda #>BITMAP_AT
    sta zDst+1
    lda #<BITMAP_LEN
    sta zT0
    lda #>BITMAP_LEN
    sta zT1
    jsr copy_bytes
    lda #$36
    sta $01

    lda #<STAGE_AT
    sta zSrc
    lda #>STAGE_AT
    sta zSrc+1
    lda #<SCREEN_AT
    sta zDst
    lda #>SCREEN_AT
    sta zDst+1
    lda #<CELL_LEN
    sta zT0
    lda #>CELL_LEN
    sta zT1
    jsr copy_bytes

    lda $DD00
    and #$FC
    sta $DD00
    ; Bank 3. Bits 7-4 of $D018 are the matrix in steps of $400:
    ; 3 * $400 = $CC00. Bit 3 places the bitmap at $E000.
    lda #$38
    sta $D018
    lda #$D8
    sta $D016
    lda #0
    sta $D021
    lda #$3B
    sta $D011

    jsr music_start

    lda #$FF
    sta $DC02
    lda #0
    sta $DC03
idle:
    lda #0
    sta $DC00
    lda $DC01
    cmp #$FF
    bne idle
down:
    lda #0
    sta $DC00
    lda $DC01
    cmp #$FF
    beq down
    lda #$FF
    sta $DC00
    jsr music_begin_fade
fade:
    jsr music_fade_done
    bcc fade
    jsr music_stop
    rts
.endproc
