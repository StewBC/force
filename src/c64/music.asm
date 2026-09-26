; Title-only SID player and lament. map_load overwrites this whole segment,
; so music_stop must run before show_title returns. Nothing here is used
; once the mission is loaded.
;
; The piece is slow A minor, one pass of about 43 seconds, then all three
; voices loop together. Triangle bass, a low triangle line, and low-passed
; noise for the sea. Three distant concussions swell in and die; they are
; not struck. Pulse is unused — a square wave cuts too hard against this.
; Score ticks are a tenth of a second on PAL and NTSC.

.segment "TITLE_MUSIC"

SID             = $D400
SID_VOLUME      = $D418
MUSIC_IRQ_LINE  = 250
MUSIC_FADE_FRAMES = 45
MUSIC_RES       = $00                 ; no resonance. Even 1 makes the 6581 noise sing a pitch.
MUSIC_LOWPASS   = $10

INS_BASS        = 0
INS_LINE        = 1
INS_SEA         = 2
INS_FAR         = 3

; Start the score and install the private once-per-frame raster IRQ.
; Called with IRQs masked. Trashes A, X, and Y.
.proc music_start
    jsr music_silence
    lda #0
    ldx #(music_state_end - music_pos - 1)
wipe:
    sta music_pos,x
    dex
    bpl wipe
    lda #1
    sta music_wait
    sta music_wait+1
    sta music_wait+2
    lda #MUSIC_LOWPASS
    sta music_mode
    lda #$12
    sta music_center
    lda $02A6
    beq ntsc_table
    lda #<music_freq_pal
    sta music_ft
    lda #>music_freq_pal
    sta music_ft+1
    lda #5
    bne store_rate
ntsc_table:
    lda #<music_freq_ntsc
    sta music_ft
    lda #>music_freq_ntsc
    sta music_ft+1
    lda #6
store_rate:
    sta music_rate
    lda #$40
    sta $D417
    lda #0
    sta $D415
    lda music_center
    sta $D416
    lda #$0E
    ora music_mode
    sta SID_VOLUME

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

; Begin the short master-volume fade. The picture stays up while it runs.
; Trashes A.
.proc music_begin_fade
    lda #MUSIC_FADE_FRAMES
    sta music_fade
    rts
.endproc

; Carry set once the IRQ has finished the fade and the volume is zero.
.proc music_fade_done
    lda music_fade
    bne not_yet
    lda SID_VOLUME
    and #$0F
    bne not_yet
    sec
    rts
not_yet:
    clc
    rts
.endproc

; Drop the private interrupt and silence the SID.
; Returns with IRQs masked. Trashes A and X.
.proc music_stop
    sei
    lda #0
    sta $D01A
    lda #$FF
    sta $D019
    jmp music_silence
.endproc

; Zero all 25 SID registers. Trashes A and X.
.proc music_silence
    lda #0
    ldx #24
clear_sid:
    sta SID,x
    dex
    bpl clear_sid
    rts
.endproc

; KERNAL entry already saved A/X/Y. Ack the raster, run one frame, then
; the KERNAL register-pop RTI. $EA81, not $EA31: the title reads the key
; matrix itself and must not share it with SCNKEY.
.proc music_irq
    lda $D019
    sta $D019
    jsr music_frame
    jmp $EA81
.endproc

; One video frame. Advances the score at 10 Hz, then glides and the filter.
; Trashes A, X, Y, zPtr, and zT0-zT3.
.proc music_frame
    lda music_fade
    beq voices
    dec music_fade
    lda music_fade
    beq faded
    clc
    adc #2
    ldx #0
vol_step:
    cmp #3
    bcc vol_put
    sec
    sbc #3
    inx
    bne vol_step
vol_put:
    txa
    ora music_mode
    sta SID_VOLUME
    jmp voices
faded:
    lda music_mode
    sta SID_VOLUME
    ldx #2
gate_off:
    lda music_sid,x
    tay
    lda #0
    sta SID+4,y
    dex
    bpl gate_off
    rts
voices:
    inc music_div
    lda music_div
    cmp music_rate
    bcc moved
    lda #0
    sta music_div
    ldx #0
each_voice:
    dec music_wait,x
    bne next_voice
    jsr music_event
next_voice:
    inx
    cpx #3
    bne each_voice
moved:
    jsr music_move
    rts
.endproc

; Read voice X until a note or a rest consumes time. $FF restarts that voice.
; Preserves X. Trashes A, Y, zPtr, and zT0.
.proc music_event
again:
    lda music_lo,x
    sta zPtr
    lda music_hi,x
    sta zPtr+1
    ldy music_pos,x
read_byte:
    lda (zPtr),y
    bmi command
    sta zT0
    iny
    lda (zPtr),y
    bne have_dur
    lda #1
have_dur:
    sta music_wait,x
    iny
    tya
    sta music_pos,x
    lda zT0
    beq do_rest
    jsr music_note
    rts
do_rest:
    jsr music_release
    rts
command:
    cmp #$FF
    bne not_loop
    lda #0
    sta music_pos,x
    jmp again
not_loop:
    iny
    cmp #$F0
    beq set_ins
    cmp #$F1
    beq set_center
    cmp #$F2
    beq set_slide
    tya
    sta music_pos,x
    jmp again
set_ins:
    lda (zPtr),y
    iny
    sta music_ins,x
    tya
    sta music_pos,x
    jmp again
set_center:
    lda (zPtr),y
    iny
    sta music_center
    tya
    sta music_pos,x
    jmp again
set_slide:
    lda (zPtr),y
    iny
    sta music_slide,x
    tya
    sta music_pos,x
    jmp again
.endproc

; Gate off, but leave the waveform and the filter route so a noise tail
; stays dull instead of opening into a hiss. Preserves X.
.proc music_release
    lda music_wave,x
    beq released
    and #$FE
    ldy music_sid,x
    sta SID+4,y
    lda #0
    sta music_wave,x
    sta music_glide,x
released:
    rts
.endproc

; Start the pitch in zT0 on voice X. A repeated pitch with the gate already
; open holds through the loop point instead of clicking. Preserves X.
.proc music_note
    jsr music_lookup
    lda music_slide,x
    beq attack_or_hold
    sta music_glide,x
    lda #0
    sta music_slide,x
    jsr music_wave_match
    bcs noted
    lda music_freq_lo,x
    ora music_freq_hi,x
    bne open_gate
    lda music_tgt_lo,x
    sta music_freq_lo,x
    lda music_tgt_hi,x
    sta music_freq_hi,x
    jmp open_gate
attack_or_hold:
    jsr music_holding_same
    bcs noted
    lda #0
    sta music_glide,x
    lda music_tgt_lo,x
    sta music_freq_lo,x
    lda music_tgt_hi,x
    sta music_freq_hi,x
open_gate:
    jsr music_gate_on
noted:
    rts
.endproc

; Pitch in zT0 (1 = C1) to music_tgt for voice X. Preserves X. Trashes A, Y, zPtr.
.proc music_lookup
    lda zT0
    sec
    sbc #1
    asl
    tay
    lda music_ft
    sta zPtr
    lda music_ft+1
    sta zPtr+1
    lda (zPtr),y
    sta music_tgt_lo,x
    iny
    lda (zPtr),y
    sta music_tgt_hi,x
    rts
.endproc

; Carry set when voice X is already gating this instrument's waveform.
; Preserves X and Y's caller's needs; trashes A and uses zT1 to hold Y.
.proc music_wave_match
    lda music_wave,x
    beq no_match
    sty zT1
    ldy music_ins,x
    cmp ins_wave,y
    bne restore_no
    ldy zT1
    sec
    rts
restore_no:
    ldy zT1
no_match:
    clc
    rts
.endproc

; Carry set when X is already holding this exact pitch on its waveform.
; Preserves X.
.proc music_holding_same
    jsr music_wave_match
    bcc not_same
    lda music_freq_lo,x
    cmp music_tgt_lo,x
    bne not_same
    lda music_freq_hi,x
    cmp music_tgt_hi,x
    bne not_same
    sec
    rts
not_same:
    clc
    rts
.endproc

; Open the gate for voice X at freq_cur, using music_ins. A noise instrument
; with a bump value pushes the filter open for a moment. Preserves X.
.proc music_gate_on
    stx zT0
    lda music_sid,x
    sta zT1
    ldy music_ins,x
    lda ins_bump,y
    beq no_bump
    sta music_bump
no_bump:
    lda ins_route,y
    ldx zT0
    sta music_route,x
    ldy music_ins,x
    lda ins_wave,y
    sta music_wave,x
    lda ins_ad,y
    sta zT2
    lda ins_sr,y
    sta zT3
    ldy zT1
    lda #$08
    sta SID+4,y
    ldx zT0
    lda music_freq_lo,x
    sta SID,y
    lda music_freq_hi,x
    sta SID+1,y
    lda zT2
    sta SID+5,y
    lda zT3
    sta SID+6,y
    lda music_wave,x
    sta SID+4,y
    jsr music_route_write
    ldx zT0
    rts
.endproc

; Resonance stays put; the low three bits follow whichever voices are noise.
.proc music_route_write
    lda music_route
    ora music_route+1
    ora music_route+2
    ora #MUSIC_RES
    sta $D417
    rts
.endproc

; Glide each voice toward its target, drift the bass, and breathe the filter.
; Trashes A, X, Y, zT0, and zT1.
.proc music_move
    inc music_drift_div
    lda music_drift_div
    and #7
    bne voices
    inc music_drift_i
    lda music_drift_i
    and #$0F
    sta music_drift_i
voices:
    ldx #2
step_voice:
    lda music_glide,x
    beq write_one
    jsr music_glide_step
write_one:
    jsr music_write_pitch
    dex
    bpl step_voice
    jsr music_filter
    rts
.endproc

; Move voice X one glide step and stop on the target. Preserves X.
.proc music_glide_step
    lda music_freq_hi,x
    cmp music_tgt_hi,x
    bcc glide_up
    bne glide_down
    lda music_freq_lo,x
    cmp music_tgt_lo,x
    bcc glide_up
    bne glide_down
    lda #0
    sta music_glide,x
    rts
glide_up:
    lda music_freq_lo,x
    clc
    adc music_glide,x
    sta zT0
    lda music_freq_hi,x
    adc #0
    sta zT1
    lda music_tgt_lo,x
    cmp zT0
    lda music_tgt_hi,x
    sbc zT1
    bcs store_step
    jmp clamp_target
glide_down:
    lda music_freq_lo,x
    sec
    sbc music_glide,x
    sta zT0
    lda music_freq_hi,x
    sbc #0
    sta zT1
    lda zT0
    cmp music_tgt_lo,x
    lda zT1
    sbc music_tgt_hi,x
    bcs store_step
clamp_target:
    lda music_tgt_lo,x
    sta music_freq_lo,x
    lda music_tgt_hi,x
    sta music_freq_hi,x
    lda #0
    sta music_glide,x
    rts
store_step:
    lda zT0
    sta music_freq_lo,x
    lda zT1
    sta music_freq_hi,x
    rts
.endproc

; Write voice X's pitch. The bass wanders a few cents when it is not gliding,
; so the drone never sits still. Preserves X.
.proc music_write_pitch
    lda music_freq_lo,x
    sta zT0
    lda music_freq_hi,x
    sta zT1
    cpx #0
    bne store_freq
    lda music_glide
    bne store_freq
    lda music_wave
    cmp #$11
    bne store_freq
    ldy music_drift_i
    lda drift_tab,y
    sta zT2
    lda #0
    sta zT3
    lda zT2
    bpl add_drift
    dec zT3
add_drift:
    lda zT0
    clc
    adc zT2
    sta zT0
    lda zT1
    adc zT3
    sta zT1
store_freq:
    ldy music_sid,x
    lda zT0
    sta SID,y
    lda zT1
    sta SID+1,y
    rts
.endproc

; Slow triangle on the noise cutoff, plus the concussion's short opening.
; Trashes A and Y.
.proc music_filter
    lda music_bump
    beq lfo_clock
    dec music_bump
lfo_clock:
    inc music_lfo_div
    lda music_lfo_div
    and #3
    bne shape
    inc music_lfo
    lda music_lfo
    and #$3F
    sta music_lfo
shape:
    lda music_lfo
    and #$3F
    cmp #$20
    bcc rise
    lda #$40
    sec
    sbc music_lfo
rise:
    lsr
    clc
    adc music_center
    sec
    sbc #8
    clc
    adc music_bump
    cmp #$08
    bcs above_floor
    lda #$08
above_floor:
    cmp #$20
    bcc store_cut
    lda #$20
store_cut:
    sta $D416
    lda #0
    sta $D415
    rts
.endproc

; Waveforms and envelopes. Bass is a heavy triangle. The line attacks slowly
; and sits lower in the mix. Sea is quiet filtered noise. Far is the same
; noise with a very slow attack and a short gate, so it never reaches a crack.
ins_ad:     .byte $47, $8A, $03, $C2
ins_sr:     .byte $C8, $A9, $44, $0A
ins_wave:   .byte $11, $11, $81, $81
ins_route:  .byte $00, $00, $04, $01
ins_bump:   .byte $00, $00, $00, $06

; ± a few SID units, about two and a half seconds per pass.
drift_tab:  .byte 0, 1, 3, 4, 5, 4, 3, 1, 0, $FF, $FD, $FC, $FB, $FC, $FD, $FF

music_sid:  .byte 0, 7, 14
music_lo:   .byte <music_bass, <music_line, <music_sea
music_hi:   .byte >music_bass, >music_line, >music_sea

; Equal temperament, C1 through B4. Index 1 is C1.
music_freq_pal:
    .word $022D,$024E,$0271,$0296,$02BE,$02E7,$0314,$0342,$0374,$03A9,$03E0,$041B
    .word $045A,$049C,$04E2,$052D,$057B,$05CF,$0627,$0685,$06E8,$0751,$07C1,$0837
    .word $08B4,$0938,$09C4,$0A59,$0AF7,$0B9D,$0C4E,$0D0A,$0DD0,$0EA2,$0F81,$106D
    .word $1167,$1270,$1389,$14B2,$15ED,$173B,$189C,$1A13,$1BA0,$1D45,$1F02,$20DA
music_freq_ntsc:
    .word $0218,$0238,$025A,$027E,$02A4,$02CC,$02F7,$0324,$0354,$0386,$03BC,$03F5
    .word $0431,$0471,$04B4,$04FC,$0548,$0598,$05ED,$0648,$06A7,$070C,$0778,$07E9
    .word $0862,$08E2,$0969,$09F8,$0A90,$0B30,$0BDB,$0C8F,$0D4E,$0E19,$0EF0,$0FD3
    .word $10C4,$11C3,$12D1,$13F0,$151F,$1661,$17B6,$191E,$1A9D,$1C32,$1DDF,$1FA6

music_pos:      .res 3, 0
music_wait:     .res 3, 0
music_ins:      .res 3, 0
music_wave:     .res 3, 0
music_route:    .res 3, 0
music_freq_lo:  .res 3, 0
music_freq_hi:  .res 3, 0
music_tgt_lo:   .res 3, 0
music_tgt_hi:   .res 3, 0
music_glide:    .res 3, 0
music_slide:    .res 3, 0
music_rate:     .res 1, 0
music_div:      .res 1, 0
music_fade:     .res 1, 0
music_mode:     .res 1, 0
music_center:   .res 1, 0
music_lfo:      .res 1, 0
music_lfo_div:  .res 1, 0
music_bump:     .res 1, 0
music_drift_i:  .res 1, 0
music_drift_div:.res 1, 0
music_ft:       .res 2, 0
music_state_end:

; Note numbers: A1=$0A Bb1=$0B C2=$0D D2=$0F Eb2=$10 G1=$08
; G2=$14 A2=$16 Bb2=$17 B2=$18 C3=$19 D3=$1B E3=$1D F3=$1E
; Each voice below totals 432 ticks.

; Hull. Long A, a lift to D under the line's ache, a half-step roll, then
; the Eb that leans on the line and falls back. The far instrument is the
; concussion: two ticks of gate, then a rest so the release can fade.
music_bass:
    .byte $F0, INS_BASS
    .byte $0A, 4
    .byte $F0, INS_FAR, $0A, 2
    .byte $F0, INS_BASS, $00, 10
    .byte $0A, 80
    .byte $0A, 54, $0F, 18, $0A, 24
    .byte $F0, INS_FAR, $0A, 2
    .byte $F0, INS_BASS, $00, 14
    .byte $F2, 1, $0B, 42
    .byte $F2, 1, $0A, 38
    .byte $0F, 28
    .byte $F0, INS_FAR, $0A, 2
    .byte $F0, INS_BASS, $00, 10
    .byte $0D, 10, $10, 24
    .byte $F2, 4, $0A, 22
    .byte $0A, 48
    .byte $FF

; The man. Low, mostly falling, never a major brightness. Rests are him
; looking and not singing. F3 is as high as he goes, and it sinks.
music_line:
    .byte $F0, INS_LINE
    .byte $00, 24
    .byte $1D, 12, $1B, 6, $19, 18, $18, 6, $16, 18
    .byte $00, 12
    .byte $19, 12, $1B, 12, $1D, 6, $1E, 18, $1D, 6, $1B, 12, $19, 18, $16, 12
    .byte $00, 12
    .byte $17, 12, $19, 12, $17, 18, $16, 12, $14, 12, $16, 18
    .byte $1D, 12, $1B, 12, $19, 12, $18, 12, $19, 12, $16, 24
    .byte $00, 12
    .byte $00, 24
    .byte $19, 6, $18, 6, $16, 12
    .byte $FF

; Water, and the war under it. Centers move the low-pass; the notes only
; choose how low the noise clock sits. Gaps are the lonely bars.
music_sea:
    .byte $F0, INS_SEA, $F1, $0A
    .byte $0A, 60, $00, 36
    .byte $00, 12, $F1, $10, $0F, 72, $00, 12
    .byte $F1, $14, $0B, 24, $00, 8, $08, 48, $00, 16
    .byte $F1, $0C, $0D, 40, $00, 8, $10, 20, $00, 28
    .byte $F1, $0A, $00, 20, $0A, 28
    .byte $FF
