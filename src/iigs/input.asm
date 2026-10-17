; Keyboard ROM latch. Simulation ABI; A/X/Y and z* are scratch.
; Arrow keys move; letters/digits and punctuation feed the existing wizard.
; Control-R restarts, Control-N selects next mission, Control-Q exits.
input_poll          anop
                    jsr   input_sample
; C64 RETURN acknowledges a completed mission before entering the wizard.
; Apply after sampling so keyboard, joystick and debug injection agree.
                    lda   script_outcome
                    beq   input_poll_done
                    lda   in_kind
                    cmp   #CMD_RETURN
                    bne   input_poll_done
                    lda   #0
                    sta   in_kind
                    lda   #1
                    sta   in_leave
input_poll_done     rts

input_sample        anop
                    lda   #0
                    sta   in_dx
                    sta   in_dy
                    sta   in_kind
                    sta   in_value
                    sta   in_restart
                    sta   in_leave
                    lda   debug_input
                    ora   debug_input+1
                    ora   debug_input+2
                    ora   debug_input+3
                    beq   input_hardware
                    lda   debug_input
                    sta   in_kind
                    lda   debug_input+1
                    sta   in_value
                    lda   debug_input+2
                    sta   in_dx
                    lda   debug_input+3
                    sta   in_dy
                    lda   #0
                    sta   debug_input
                    sta   debug_input+1
                    sta   debug_input+2
                    sta   debug_input+3
                    rts
input_hardware      jsr   input_joystick
                    lda   >$E0C000
                    bmi   input_key
                    rts
input_key           and   #$7F
                    sta   input_ascii
                    lda   >$E0C025
                    and   #8
                    sta   input_repeat_flag
                    lda   >$E0C010
input_decode        lda   input_ascii
                    cmp   #$08
                    bne   input_right
                    lda   #$FF
                    sta   in_dx
                    rts
input_right         cmp   #$15
                    bne   input_up
                    lda   #1
                    sta   in_dx
                    rts
input_up            cmp   #$0B
                    bne   input_down
                    lda   #$FF
                    sta   in_dy
                    rts
input_down          cmp   #$0A
                    bne   input_restart
                    lda   #1
                    sta   in_dy
                    rts
input_restart       ldx   input_repeat_flag
                    beq   input_nonrepeat
                    rts
input_nonrepeat     cmp   #$12
                    bne   input_quit
                    lda   #1
                    sta   in_restart
                    rts
input_quit          cmp   #$11
                    bne   input_next
                    lda   #1
                    sta   in_leave
                    rts
input_next          cmp   #$0E
                    bne   input_letter
                    lda   #2
                    sta   debug_action
                    rts
input_letter        cmp   #97
                    bcc   input_upper
                    cmp   #123
                    bcs   input_upper
                    and   #$DF
input_upper         cmp   #65
                    bcc   input_digit
                    cmp   #91
                    bcs   input_digit
                    sec
                    sbc   #65
                    sta   in_value
                    lda   #CMD_LETTER
                    sta   in_kind
                    rts
input_digit         cmp   #48
                    bcc   input_punct
                    cmp   #58
                    bcs   input_punct
                    sec
                    sbc   #48
                    sta   in_value
                    lda   #CMD_DIGIT
                    sta   in_kind
                    rts
input_punct         ldx   #0
input_punct_loop    cmp   input_keys,x
                    beq   input_punct_found
                    inx
                    cpx   #7
                    bcc   input_punct_loop
                    rts
input_punct_found   lda   input_tokens,x
                    sta   in_kind
                    rts
input_keys          dc    i1'44,32,13,127,46,27,8'
input_tokens        dc    i1'CMD_COMMA,CMD_SPACE,CMD_RETURN,CMD_DEL,CMD_PERIOD,CMD_ESC,CMD_DEL'
input_ascii         ds    1
input_repeat_flag   ds    1

; Standard Apple game-port paddles. Bounded 8-bit timing reads both axes together;
; IRQs must stay masked from the timer strobe through the final sample: an IRQ
; lets the analog timers expire without advancing our counters (false up/left).
; Restore the caller interrupt state before decoding or reading the button.
; absent hardware remains high to saturation on both axes and is ignored.
; Keyboard directions override the corresponding axis. Button 0 feeds RETURN
; once per press, so a held trigger cannot repeatedly advance wizard slots.
; Never touch the game port unless explicitly enabled in the mission menu.
input_joystick      anop
                    lda   joystick_enabled
                    bne   joystick_read
                    rts
joystick_read       anop
                    php
                    sei
                    lda   #0
                    sta   paddle_x
                    sta   paddle_y
                    lda   >$E0C070
                    ldx   #0
paddle_sample       lda   >$E0C064
                    bpl   paddle_x_done
                    inc   paddle_x
paddle_x_done       lda   >$E0C065
                    bpl   paddle_y_done
                    inc   paddle_y
paddle_y_done       inx
                    cpx   #255
                    bcc   paddle_sample
                    plp
                    lda   paddle_x
                    and   paddle_y
                    cmp   #255
                    beq   paddle_absent
                    lda   paddle_x
                    cmp   #64
                    bcs   paddle_right
                    lda   #255
                    sta   in_dx
                    bne   paddle_vertical
paddle_right        cmp   #192
                    bcc   paddle_vertical
                    lda   #1
                    sta   in_dx
paddle_vertical     lda   paddle_y
                    cmp   #64
                    bcs   paddle_down
                    lda   #255
                    sta   in_dy
                    bne   paddle_button
paddle_down         cmp   #192
                    bcc   paddle_button
                    lda   #1
                    sta   in_dy
paddle_button       lda   >$E0C061
                    and   #$80
                    cmp   paddle_last_button
                    beq   paddle_done
                    sta   paddle_last_button
                    beq   paddle_done
                    lda   #CMD_RETURN
                    sta   in_kind
paddle_done         rts
paddle_absent       lda   #0
                    sta   paddle_last_button
                    rts
paddle_x            ds    1
paddle_y            ds    1
paddle_last_button  ds    1

; Session option: startup resets it; mission loading must retain the choice.
joystick_enabled    dc    i1'0'

