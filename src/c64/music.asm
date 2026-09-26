; C64-only SID playback. The player is resident so short mission cues can use
; it later; the long title score and mutable playback state live at $0900 and
; are deliberately overwritten by map_load after music_stop.

.segment "CODE"

SID         = $D400
SID_VOLUME  = $D418
MUSIC_IRQ_LINE = 250
MUSIC_FADE_FRAMES = 45       ; 0.9 seconds PAL, 0.75 seconds NTSC

; Start the title score and install its private once-per-frame raster IRQ.
; Called with IRQs masked. Trashes A, X, and Y.
.proc music_start
    jsr music_silence
    lda #0
    sta music_pos
    sta music_pos+1
    sta music_pos+2
    sta music_wait
    sta music_wait+1
    sta music_wait+2
    sta music_fade
    sta music_div
    lda #15
    sta SID_VOLUME
    ; Voice-specific envelopes. The pulse voice also needs a non-zero width.
    lda #$24
    sta SID+5
    lda #$F8
    sta SID+6
    lda #0
    sta SID+9
    lda #8
    sta SID+10
    lda #$58
    sta SID+12
    lda #$58
    sta SID+13
    lda #$48
    sta SID+19
    lda #$88
    sta SID+20

    ; KERNAL PAL flag: zero is NTSC. Ten score ticks per second on either.
    lda #5
    ldx $02A6
    bne pal
    lda #6
pal:
    sta music_rate

    lda #$7F
    sta $DC0D
    sta $DD0D
    lda $DC0D
    lda $DD0D
    lda #<music_irq
    sta $0314
    lda #>music_irq
    sta $0315
    lda #MUSIC_IRQ_LINE
    sta $D012
    lda $D011
    and #$7F
    sta $D011
    lda #$01
    sta $D01A
    lda #$FF
    sta $D019
    cli
    rts
.endproc

; Begin a quick master-volume fade. The title remains visible while it runs.
; Trashes A.
.proc music_begin_fade
    lda #MUSIC_FADE_FRAMES
    sta music_fade
    rts
.endproc

; Return carry set once the IRQ has completed the fade.
.proc music_fade_done
    lda music_fade
    bne no
    lda SID_VOLUME
    and #$0F
    bne no
    sec
    rts
no:
    clc
    rts
.endproc

; Remove the private interrupt and leave every SID register quiet.
; Returns with IRQs masked for the gameplay IRQ installation. Trashes A/X.
.proc music_stop
    sei
    lda #0
    sta $D01A
    lda #$FF
    sta $D019
    jmp music_silence
.endproc

; Clear all SID registers. Trashes A and X.
.proc music_silence
    lda #0
    ldx #24
clear:
    sta SID,x
    dex
    bpl clear
    rts
.endproc

; KERNAL hardware IRQ entry has already saved A/X/Y. Acknowledge the raster,
; advance the score, apply any fade, then use the KERNAL register-pop RTI.
.proc music_irq
    lda $D019
    sta $D019
    jsr music_frame
    jmp $EA81
.endproc

; One video-frame update. Trashes A, X, Y and zPtr/zT0/zT1.
.proc music_frame
    lda music_fade
    beq score
    dec music_fade
    lda music_fade
    beq faded
    ; Volume is ceil(frames/3), producing 15..1 over 45 frames.
    clc
    adc #2
    ldx #0
vol:
    cmp #3
    bcc putvol
    sec
    sbc #3
    inx
    bne vol
putvol:
    txa
    sta SID_VOLUME
    jmp score
faded:
    lda #0
    sta SID_VOLUME
    ldx #2
gateoff:
    lda music_sid_off,x
    tay
    lda #0
    sta SID+4,y
    dex
    bpl gateoff
    rts
score:
    inc music_div
    lda music_div
    cmp music_rate
    bcc done
    lda #0
    sta music_div
    ldx #0
voice:
    lda music_wait,x
    beq event
    dec music_wait,x
    jmp next
event:
    jsr music_event
next:
    inx
    cpx #3
    bne voice
done:
    rts
.endproc

; Read the next note/duration pair for voice X. $FF loops that voice.
; Trashes A, Y, zPtr/zT0/zT1; restores X.
.proc music_event
again:
    lda music_seq_lo,x
    sta zPtr
    lda music_seq_hi,x
    sta zPtr+1
    ldy music_pos,x
    lda (zPtr),y
    cmp #$FF
    bne note
    lda #0
    sta music_pos,x
    tay
    lda (zPtr),y
note:
    sta zT0
    iny
    lda (zPtr),y
    sta music_wait,x
    iny
    tya
    sta music_pos,x

    lda music_sid_off,x
    tay
    lda #0
    sta SID+4,y
    lda zT0
    beq rest
    stx zT1
    sec
    sbc #1
    asl
    tax
    lda music_freq,x
    sta SID,y
    lda music_freq+1,x
    sta SID+1,y
    ldx zT1
    lda music_control,x
    sta SID+4,y
rest:
    rts
.endproc

music_sid_off: .byte 0, 7, 14
; Three triangles: bass forward, melody deliberately soft, counter-line dark.
; A pulse melody was too rich in upper harmonics against the low pedal.
music_control: .byte $11, $11, $11
music_seq_lo:  .byte <music_bass, <music_melody, <music_counter
music_seq_hi:  .byte >music_bass, >music_melody, >music_counter

.segment "TITLE_MUSIC"

; Mutable title-only state. It is initialized before IRQs are enabled.
music_pos:  .res 3, 0
music_wait: .res 3, 0
music_rate: .res 1, 0
music_div:  .res 1, 0
music_fade: .res 1, 0

; Equal-tempered PAL SID frequencies, C1 through B4. NTSC pitch differs by
; about 2.3%, acceptable here; tempo itself is compensated above.
music_freq:
    .word $022D,$024E,$0271,$0296,$02BE,$02E8,$0314,$0343,$0375,$03AA,$03E2,$041D
    .word $045A,$049C,$04E2,$052D,$057B,$05CF,$0628,$0686,$06EA,$0754,$07C4,$083A
    .word $08B5,$0938,$09C4,$0A59,$0AF7,$0B9E,$0C50,$0D0D,$0DD4,$0EA8,$0F88,$1074
    .word $116A,$1271,$1388,$14B2,$15EE,$173D,$18A0,$1A1A,$1BA9,$1D50,$1F10,$20E8

; "Grey Horizon" — an original slow lament in D minor. Score ticks are a
; tenth of a second. Zero is a rest; notes 1..48 index C2..B5 above.
; The bass is an inexorable D/A pedal, the melody rises but repeatedly falls
; short of resolution, and the counter-voice moves like distant low horns.
music_bass:
    .byte 3,8, 0,2, 10,6, 0,4, 3,8, 0,2, 8,6, 0,4
    .byte 1,8, 0,2, 8,6, 0,4, 3,8, 0,2, 10,6, 0,4
    .byte 6,8, 0,2, 1,6, 0,4, 8,8, 0,2, 3,6, 0,4
    .byte 3,8, 0,2, 10,6, 0,4, 3,12, 1,4, 3,8, 0,4, $FF

music_melody:
    .byte 0,16, 27,6, 29,4, 30,8, 29,4, 27,6, 0,4
    .byte 25,6, 27,4, 29,8, 27,4, 25,6, 0,8
    .byte 30,6, 32,4, 34,8, 32,4, 30,6, 29,4, 27,8, 0,6
    .byte 25,6, 27,4, 29,8, 30,4, 29,6, 27,4, 25,10, 0,8
    .byte 27,6, 29,4, 30,8, 34,4, 32,6, 30,4, 29,8, 0,6
    .byte 27,8, 25,6, 23,4, 25,8, 27,6, 25,4, 22,12, 0,10, $FF

music_counter:
    .byte 0,8, 15,12, 0,4, 13,12, 0,4
    .byte 10,12, 0,4, 13,12, 0,4
    .byte 18,12, 0,4, 17,12, 0,4
    .byte 15,12, 0,4, 13,12, 0,4
    .byte 10,8, 12,4, 13,12, 0,4, 15,16, 0,8, $FF
