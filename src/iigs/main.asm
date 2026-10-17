; FORCE IIgs native platform. GS/OS entry is native M=0,X=0.
; Simulation boundary: M=X=1, D=owned bank-0 page, DBR=PBR=CORE bank.
 case on
 ALIGN 256
CORE START
 copy build/iigs/contracts.s
 copy build/iigs/asset_contracts.s
 phb
 phd
 php
 rep #$30
 longa on
 longi on
 cld
 phk
 plb
 tdc
 sta old_dp
 lda 0
 sta saved_caller_dp
 lda 2
 sta saved_caller_dp+2
 sep #$20
 longa off
 lda >$E0C029
 sta old_shr
 lda >$E0C034
 sta old_border
 lda >$E0C035
 sta old_shadow
 rep #$20
 longa on
 ldx #$0201
 jsl $E10000
 pea 0
 ldx #$0202
 jsl $E10000
 pla
 sta user_id
; Locked, fixed, page-aligned, no bank crossing, bank 0.
 pea 0
 pea 0
 pea 0
 pea 256
 lda user_id
 pha
 pea $C015
 pea 0
 pea 0
 ldx #$0902
 jsl $E10000
 pla
 sta dp_handle
 sta 0
 pla
 sta dp_handle+2
 sta 2
 bcc allocated
 lda saved_caller_dp
 sta 0
 lda saved_caller_dp+2
 sta 2
 jmp shutdown
allocated anop
 lda [0]
 sta debug_dp
 lda saved_caller_dp
 sta 0
 lda saved_caller_dp+2
 sta 2
 lda debug_dp
 tcd
 ldx #254
 lda #0
clear_dp sta 0,x
 dex
 dex
 bpl clear_dp
 lda #CORE
 sta debug_base
 cmp #65536-(core_end-CORE)
 bcc core_bank_valid
 beq core_bank_valid
 jmp shutdown
core_bank_valid sep #$20
 longa off
 lda #^CORE
 sta debug_base+2
 lda >$E0C029
 sta old_shr
 lda >$E0C034
 sta old_border
 lda >$E0C035
 sta old_shadow
 and #$F7
 sta >$E0C035
 lda #$E1
 sta >$E0C029
 lda #0
 sta >$E0C034
 rep #$20
 longa on
 ldx #$7DFE
 lda #0
clear_screen sta >$E12000,x
 dex
 dex
 bpl clear_screen
 ldx #254
clear_scbs sta >$E19D00,x
 dex
 dex
 bpl clear_scbs
 ldx #30
palette_loop lda palette,x
 sta >$E19E00,x
 dex
 dex
 bpl palette_loop
 ldx #2046
font_loop lda initial_charset,x
 sta CHARSET,x
 dex
 dex
 bpl font_loop
 sep #$30
 longa off
 longi off
 rep #$10
 longi on
 ldx #1023
 lda #255
clear_cache sta cached_glyph,x
 sta cached_colour,x
 dex
 bpl clear_cache
 sep #$10
 longi off
 lda #0
 sta mission_id
 sta joystick_enabled
 jsr mission_load
 jsr campaign_load
 jsr menu_open
 jsr show_title
 lda #1
 sta debug_ready
main_loop anop
 jsr frame_wait
 lda debug_action
 beq no_action
 cmp #1
 bne action_next
 jsr mission_load
 jmp action_done
action_next cmp #2
 bne action_done
 inc mission_id
 lda mission_id
 cmp #MISSION_COUNT
 bcc action_load
 lda #0
 sta mission_id
action_load jsr mission_load
action_done lda #0
 sta debug_action
no_action lda title_mode
 beq no_title
 jsr title_poll
 jmp main_loop
no_title lda menu_mode
 beq active_game
 jsr menu_tick
 jsr render_frame
 jmp main_loop
active_game lda debug_pause
 bne render_only
 jsr input_poll
 lda in_leave
 beq continue_game
 jsr menu_open
 jmp main_loop
continue_game lda in_restart
 beq do_tick
 jsr mission_load
 jmp do_tick
do_tick jsr game_tick
 rep #$20
 longa on
 inc debug_ticks
 bne tick_ok
 inc debug_ticks+2
tick_ok sep #$20
 longa off
render_only jsr draw_all
 jsr render_frame
 jmp main_loop

; Native API called in simulation mode. Restarts from immutable mission images.
mission_load anop
 lda #0
 sta menu_mode
 sta title_mode
 jsr game_palette
 rep #$30
 longa on
 longi on
 lda mission_id
 and #255
 asl a
 asl a
 tax
 lda mission_ptrs,x
 sta copy_source+1
 sep #$20
 longa off
 lda mission_ptrs+2,x
 sta copy_source+3
 rep #$20
 longa on
 ldx #0
copy_source lda >$000000,x
 sta active_mission,x
 inx
 inx
 cpx #ACTIVE_BYTES
 bcc copy_source
 ldx #bss_end-bss_start-1
 sep #$20
 longa off
 lda #0
clear_world sta bss_start,x
 dex
 bpl clear_world
; Relocate objective strings from image-relative offsets to near pointers.
 ldx #0
objective_loop lda sc_op_code,x
 cmp #10
 bne objective_next
 rep #$20
 longa on
 lda sc_op_a,x
 and #255
 sta relocation
 lda sc_op_b,x
 and #255
 xba
 ora relocation
 clc
 adc #active_mission
 sta relocation
 sep #$20
 longa off
 lda relocation
 sta sc_op_a,x
 lda relocation+1
 sta sc_op_b,x
objective_next inx
 cpx #64
 bcc objective_loop
 sep #$10
 longi off
 lda asset_deck_count
 sta deck_count
 ldx #15
copy_deck lda asset_deck_x,x
 sta deck_x,x
 lda asset_deck_y,x
 sta deck_y,x
 dex
 bpl copy_deck
 jsr world_load
 jsr session_init
 lda #0
 sta debug_ticks
 sta debug_ticks+1
 sta debug_ticks+2
 sta debug_ticks+3
 lda mission_id
 sta debug_mission
 rts

; Route state is a compact bridge mask. Copy 304+514 bytes from resident banks.
initial_routes anop
 jsr portal_bake
 lda #0
activate_routes anop
 sta route_state
 rep #$30
 longa on
 longi on
 and #255
 sta route_number
 lda mission_id
 and #255
 asl a
 asl a
 tax
 lda route_ptrs,x
 sta route_source+1
 sep #$20
 longa off
 lda route_ptrs+2,x
 sta route_source+3
 rep #$20
 longa on
 lda #0
route_offset_loop ldx route_number
 beq route_offset_done
 clc
 adc #818
 dec route_number
 bra route_offset_loop
route_offset_done clc
 adc route_source+1
 sta route_source+1
 bcc route_bank_ok
 sep #$20
 longa off
 inc route_source+3
 rep #$20
 longa on
route_bank_ok ldx #0
route_source lda >$000000,x
 sta portal_from,x
 inx
 inx
 cpx #304
 bcc route_source
; Destination is not contiguous: doorway follows unrelated BSS.
 lda route_source+1
 clc
 adc #304
 sta door_source+1
 sep #$20
 longa off
 lda route_source+3
 adc #0
 sta door_source+3
 rep #$20
 longa on
 ldx #0
door_source lda >$000000,x
 sta door_n,x
 inx
 inx
 cpx #514
 bcc door_source
 sep #$30
 longa off
 longi off
 rts

; Same rule ordering as C64 game_tick; restart and score persistence platform-owned.
game_tick anop
 lda cmd_flash
 beq tick_no_flash
 dec cmd_flash
 bne tick_no_flash
 lda #0
 sta cmd_nopath
 lda #1
 sta ui_dirty
tick_no_flash jsr move_cursor
 jsr cmd_feed
 lda objective_ttl
 beq tick_no_objective
 dec objective_ttl
tick_no_objective inc frame_lo
 jsr world_tick
 lda script_outcome
 cmp #OUT_WIN
 bne tick_camera
 lda score_snap
 bne tick_camera
 lda #1
 sta score_snap
 lda #NONE
 sta zA0
 jsr bank_strength
 sta snap_score
tick_camera lda script_outcome
 bne tick_camera_expire
 lda path_fail_who
 cmp #LETTER_MAX
 bcs tick_camera_expire
 lda #1
 sta cmd_nopath
 lda #8
 sta cmd_flash
tick_camera_expire lda cam_ttl
 beq tick_done
 dec cam_ttl
 bne tick_done
 jsr camera_back
tick_done rts

; SHR cursor is composited by render_frame, never a VIC sprite.
place_cursor anop
 rts

; Pace at one logic tick per three 60-Hz system ticks, including render time.
; Native GetTick is outside simulation. Low-word modular comparisons are valid
; because deadlines are always only three ticks ahead. Overruns drop frames.
frame_wait anop
 php
 phb
 phd
 rep #$30
 longa on
 longi on
frame_wait_poll pea 0
 pea 0
 ldx #$2503
 jsl $E10000
 pla
 sta frame_now
 pla
 lda frame_paced
 and #255
 bne frame_wait_have_deadline
 lda frame_now
 clc
 adc #3
 sta frame_deadline
 lda #1
 sta frame_paced
frame_wait_have_deadline lda frame_now
 sec
 sbc frame_deadline
 bmi frame_wait_poll
 lda frame_now
 clc
 adc #3
 sta frame_deadline
 pld
 plb
 plp
 rts

shutdown anop
 rep #$30
 longa on
 longi on
 sep #$20
 longa off
 lda old_shr
 sta >$E0C029
 lda old_border
 sta >$E0C034
 lda old_shadow
 sta >$E0C035
 rep #$20
 longa on
 lda old_dp
 tcd
 lda user_id
 pha
 ldx #$0302
 jsl $E10000
 ldx #$0301
 jsl $E10000
; Restore P last: PLD/PLB modify N/Z. Scratch uses long addressing
; because restoring the caller DBR invalidates CORE-relative access.
 sep #$20
 longa off
 pla
 sta >exit_status
 rep #$20
 longa on
 pld
 plb
 sep #$20
 longa off
 lda >exit_status
 pha
 plp
 jsl $E100A8
 dc i2'$2029'
 dc a4'quit_parameters'
quit_parameters dc i2'0'

 longa off
 longi off
 copy src/iigs/input.asm
 copy src/iigs/menu.asm
 longa off
 longi off
 copy src/iigs/title.asm
 copy src/iigs/render.asm
 longa off
 longi off
 copy build/iigs/core.s
 copy build/iigs/assets.s
 copy build/iigs/pointers.s

palette dc i2'$000,$FFF,$800,$AFE,$C4C,$0C5,$00A,$EE7,$D85,$640,$F77,$333,$777,$AF6,$08F,$BBB'
exit_status ds 1
saved_caller_dp ds 4
old_dp ds 2
user_id ds 2
dp_handle ds 4
old_shr ds 1
old_border ds 1
old_shadow ds 1
relocation ds 2
route_number ds 2
frame_now ds 2
frame_deadline ds 2
frame_paced ds 2
mission_id ds 1
ntsc_flag dc i1'0'

; Debugger ABI v1, little endian; exported symbol map gives bank-relative offsets.
debug_signature dc c'FORCEIIGS'
debug_version dc i1'1'
debug_base ds 4
debug_dp ds 2
debug_ready ds 1
debug_pause ds 1
debug_ticks ds 4
debug_mission ds 1
debug_action ds 1
debug_input ds 4
debug_call ds 16

 ALIGN 256
SCREEN ds 1024
COLORRAM ds 1024
OCC ds 1024
CHARSET ds 2048
active_mission ds ACTIVE_BYTES
core_end anop
 END
