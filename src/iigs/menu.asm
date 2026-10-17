; Campaign/frontier semantics follow C64: replay completed rows, reveal temporary
; rows with +, hide with -, retain the greatest survivor count after a win only.
; Storage is an independent IIgs file, validated against stable authored stems.
; Public API simulation ABI, GS/OS calls occur only with normal bank-0 stack.
 longa off
 longi off
menu_open anop
 lda #1
 sta menu_mode
 lda #0
 sta menu_reset_armed
 jsr campaign_commit
 jsr menu_paint
 rts

menu_tick anop
 lda >$E0C000
 bmi menu_key
 rts
menu_key and #$7F
 sta menu_ascii
 lda >$E0C025
 sta menu_modifiers
 lda >$E0C010
 lda menu_ascii
 cmp #97
 bcc menu_upper
 cmp #123
 bcs menu_upper
 and #$DF
; CTRL-J and Down both produce LF. Check the latched Control modifier before
; acknowledging Down, and ignore firmware repeats for this on/off switch.
menu_upper sta menu_ascii
 cmp #$0A
 bne menu_control_done
 lda menu_modifiers
 and #2
 beq menu_control_restore
 lda menu_modifiers
 and #8
 beq menu_toggle_joystick
 rts
menu_toggle_joystick lda joystick_enabled
 eor #1
 sta joystick_enabled
 lda #0
 sta paddle_last_button
 jmp menu_repaint
menu_control_restore lda menu_ascii
menu_control_done cmp #$11
 bne menu_not_quit
 jmp shutdown
menu_not_quit cmp #$0B
 bne menu_down
 lda ui_miss
 bne menu_up_exists
 rts
menu_up_exists anop
 dec ui_miss
 jmp menu_repaint
menu_down cmp #$0A
 bne menu_reveal
 lda ui_miss
 clc
 adc #1
 cmp #MISSION_COUNT
 bcc menu_down_exists
 rts
menu_down_exists anop
 tax
 jsr miss_shown
 bcs menu_down_visible
 rts
menu_down_visible inc ui_miss
 jmp menu_repaint
menu_reveal cmp #43
 bne menu_hide
 jsr frontier_of
 clc
 adc #1
 adc ui_extra
 cmp #MISSION_COUNT
 bcs menu_key_done
 inc ui_extra
 sta ui_miss
 jmp menu_repaint
menu_hide cmp #45
 bne menu_reset
 lda #0
 sta ui_extra
 jsr frontier_of
 cmp #MISSION_COUNT
 bcc menu_hide_front
 lda #MISSION_COUNT-1
menu_hide_front sta ui_miss
 jmp menu_repaint
menu_reset cmp #42
 bne menu_enter
 lda menu_reset_armed
 beq menu_arm_reset
 ldx #MISSION_COUNT-1
 lda #255
menu_reset_scores sta miss_score,x
 dex
 bpl menu_reset_scores
 lda #0
 sta ui_miss
 sta ui_extra
 sta menu_reset_armed
 lda #1
 sta campaign_dirty
 jsr campaign_save
 jmp menu_repaint
menu_arm_reset lda #1
 sta menu_reset_armed
 jmp menu_repaint
menu_enter cmp #82
 bne menu_launch_key
 lda campaign_dirty
 beq menu_key_done
 jsr campaign_save
 jmp menu_repaint
menu_launch_key cmp #13
 bne menu_key_done
 ldx ui_miss
 jsr miss_shown
 bcc menu_key_done
 lda ui_miss
 sta mission_id
 jmp mission_load
menu_repaint jsr menu_paint
menu_key_done rts

frontier_of anop
 ldx #0
frontier_loop lda miss_score,x
 cmp #255
 beq frontier_found
 inx
 cpx #MISSION_COUNT
 bcc frontier_loop
frontier_found txa
 rts

; X mission index, C shown; preserve X.
miss_shown anop
 stx menu_saved_x
 jsr frontier_of
 clc
 adc ui_extra
 cmp menu_saved_x
 ldx menu_saved_x
 rts

menu_paint anop
 rep #$10
 longi on
 ldx #999
 lda #128
menu_clear sta SCREEN,x
 lda #1
 sta COLORRAM,x
 lda #128
 dex
 bpl menu_clear
 sep #$10
 longi off
 lda #2
 sta scr_y
 lda #4
 sta scr_x
 lda #<menu_heading
 sta zPtr
 lda #>menu_heading
 sta zPtr+1
 jsr menu_puts
 lda #5
 sta scr_y
 lda #0
 sta menu_row
menu_row_loop ldx menu_row
 jsr miss_shown
 bcc menu_rows_done
 lda #3
 sta scr_x
 jsr cell_addr
 ldy #0
 lda menu_row
 cmp ui_miss
 bne menu_row_unselected
 lda #158
 sta (zSrc),y
menu_row_unselected lda #5
 sta scr_x
 lda menu_row
 asl a
 tax
 lda mission_titles,x
 sta zPtr
 lda mission_titles+1,x
 sta zPtr+1
 jsr menu_puts
 ldx menu_row
 lda miss_score,x
 cmp #255
 beq menu_no_score
 sta menu_score
 lda #34
 sta scr_x
 jsr cell_addr
 lda menu_score
 ldx #0
menu_score_tens cmp #10
 bcc menu_score_units
 sec
 sbc #10
 inx
 bne menu_score_tens
menu_score_units clc
 adc #144
 ldy #1
 sta (zSrc),y
 txa
 clc
 adc #144
 dey
 sta (zSrc),y
menu_no_score inc scr_y
 inc menu_row
 lda menu_row
 cmp #MISSION_COUNT
 bcc menu_row_loop
menu_rows_done lda #16
 sta scr_y
 lda #3
 sta scr_x
 lda #<menu_help
 sta zPtr
 lda #>menu_help
 sta zPtr+1
 jsr menu_puts
 inc scr_y
 lda #3
 sta scr_x
 lda #<menu_help2
 sta zPtr
 lda #>menu_help2
 sta zPtr+1
 jsr menu_puts
 inc scr_y
 lda #3
 sta scr_x
 lda #<menu_help3
 sta zPtr
 lda #>menu_help3
 sta zPtr+1
 jsr menu_puts
 lda #20
 sta scr_y
 lda #3
 sta scr_x
 lda joystick_enabled
 beq menu_joystick_disabled
 lda #<menu_joystick_on
 sta zPtr
 lda #>menu_joystick_on
 sta zPtr+1
 bra menu_joystick_paint
menu_joystick_disabled lda #<menu_joystick_off
 sta zPtr
 lda #>menu_joystick_off
 sta zPtr+1
menu_joystick_paint jsr menu_puts
 lda menu_reset_armed
 beq menu_error_check
 lda #<menu_reset_message
 sta zPtr
 lda #>menu_reset_message
 sta zPtr+1
 jmp menu_message
menu_error_check lda campaign_error
 beq menu_paint_done
 lda #<menu_error_message
 sta zPtr
 lda #>menu_error_message
 sta zPtr+1
menu_message lda #22
 sta scr_y
 lda #3
 sta scr_x
 jsr menu_puts
menu_paint_done rts

menu_puts anop
 jsr cell_addr
 ldy #0
menu_puts_loop lda (zPtr),y
 beq menu_puts_done
 clc
 adc #96
 sta (zSrc),y
 iny
 cpy #37
 bcc menu_puts_loop
menu_puts_done rts

campaign_commit anop
 lda mission_id
 sta ui_miss
 lda script_outcome
 cmp #OUT_WIN
 bne campaign_commit_done
 lda score_snap
 beq campaign_advance
 ldx mission_id
 lda miss_score,x
 cmp #255
 beq campaign_record_score
 cmp snap_score
 bcs campaign_advance
campaign_record_score lda snap_score
 sta miss_score,x
 lda #1
 sta campaign_dirty
campaign_advance lda #0
 sta score_snap
 lda mission_id
 clc
 adc #1
 cmp #MISSION_COUNT
 bcs campaign_commit_save
 sta ui_miss
 tax
 jsr miss_shown
 bcs campaign_commit_save
 jsr frontier_of
 cmp #MISSION_COUNT
 bcs campaign_commit_save
 sta ui_miss
campaign_commit_save lda campaign_dirty
 beq campaign_commit_done
 jsr campaign_save
campaign_commit_done rts

campaign_load anop
 php
 phb
 phd
 rep #$30
 longa on
 longi on
 lda #0
 sta campaign_error
 sta campaign_dirty
 ldx #MISSION_COUNT-1
 sep #$20
 longa off
 lda #255
campaign_init_scores sta miss_score,x
 dex
 bpl campaign_init_scores
 rep #$20
 longa on
 jsr campaign_paths_init
 bcc campaign_load_paths_ok
 sta campaign_error
 jmp campaign_load_done
campaign_load_paths_ok jsr campaign_recover
 bcc campaign_load_open
 sta campaign_error
 jmp campaign_load_done
campaign_load_open jsl $E100A8
 dc i2'$2010'
 dc a4'campaign_open'
 bcc campaign_read_open
 cmp #$46
 bne campaign_open_failed
 jmp campaign_load_done
campaign_open_failed anop
 sta campaign_error
 jmp campaign_load_done
campaign_read_open lda campaign_open+2
 sta campaign_io+2
 sta campaign_close+2
 jsl $E100A8
 dc i2'$2012'
 dc a4'campaign_io'
 sta campaign_error
 jsl $E100A8
 dc i2'$2014'
 dc a4'campaign_close'
 bcs campaign_load_close_error
 lda campaign_error
 bne campaign_load_done
 lda campaign_io+12
 cmp #CAMPAIGN_BYTES
 bne campaign_invalid
 ldx #CAMPAIGN_HEADER_BYTES-1
 sep #$20
 longa off
campaign_header_loop lda campaign_buffer,x
 cmp campaign_template,x
 bne campaign_invalid8
 dex
 bpl campaign_header_loop
 lda #0
 ldx #CAMPAIGN_BYTES-1
campaign_checksum_loop eor campaign_buffer,x
 dex
 bpl campaign_checksum_loop
 cmp #0
 bne campaign_invalid8
 ldx #MISSION_COUNT-1
campaign_validate_score lda campaign_buffer+CAMPAIGN_HEADER_BYTES,x
 cmp #255
 beq campaign_score_valid
 cmp #UNIT_MAX+1
 bcs campaign_invalid8
campaign_score_valid dex
 bpl campaign_validate_score
 ldx #MISSION_COUNT-1
campaign_import_score lda campaign_buffer+CAMPAIGN_HEADER_BYTES,x
 sta miss_score,x
 dex
 bpl campaign_import_score
 rep #$20
 longa on
 lda #0
 sta campaign_error
 bra campaign_load_done
campaign_load_close_error sta campaign_error
 bra campaign_load_done
campaign_invalid8 rep #$20
 longa on
campaign_invalid lda #$47
 sta campaign_error
campaign_load_done pld
 plb
 plp
 rts

; Write NEW completely, close, rename old to backup, then install NEW. Failure
; before commit leaves the prior file untouched; install failure rolls it back.
campaign_save anop
 php
 phb
 phd
 rep #$30
 longa on
 longi on
 stz campaign_error
 stz campaign_had_old
 jsr campaign_paths_init
 bcc campaign_save_paths_ok
 jmp campaign_save_error
campaign_save_paths_ok jsr campaign_recover
 bcc campaign_save_recovered
 jmp campaign_save_error
campaign_save_recovered ldx #CAMPAIGN_HEADER_BYTES-1
 sep #$20
 longa off
campaign_export_header lda campaign_template,x
 sta campaign_buffer,x
 dex
 bpl campaign_export_header
 ldx #MISSION_COUNT-1
campaign_export_scores lda miss_score,x
 sta campaign_buffer+CAMPAIGN_HEADER_BYTES,x
 dex
 bpl campaign_export_scores
 lda #0
 ldx #CAMPAIGN_BYTES-2
campaign_export_check eor campaign_buffer,x
 dex
 bpl campaign_export_check
 sta campaign_buffer+CAMPAIGN_BYTES-1
 rep #$20
 longa on
; Stale temporary files are safe to remove; backup is retained until success.
 jsl $E100A8
 dc i2'$2002'
 dc a4'campaign_destroy_new'
 jsl $E100A8
 dc i2'$2001'
 dc a4'campaign_create'
 bcc campaign_created
 jmp campaign_save_error
campaign_created jsl $E100A8
 dc i2'$2010'
 dc a4'campaign_open_new'
 bcc campaign_write_open
 jmp campaign_save_error
campaign_write_open lda campaign_open_new+2
 sta campaign_io+2
 sta campaign_close+2
 jsl $E100A8
 dc i2'$2013'
 dc a4'campaign_io'
 sta campaign_error
 jsl $E100A8
 dc i2'$2014'
 dc a4'campaign_close'
 bcc campaign_closed
 jmp campaign_save_error
campaign_closed lda campaign_error
 beq campaign_wrote
 jmp campaign_save_done
campaign_wrote lda campaign_io+12
 cmp #CAMPAIGN_BYTES
 beq campaign_write_complete
 lda #$27
 jmp campaign_save_error
campaign_write_complete jsl $E100A8
 dc i2'$2002'
 dc a4'campaign_destroy_backup'
 jsl $E100A8
 dc i2'$2004'
 dc a4'campaign_backup'
 bcc campaign_backed_up
 cmp #$46
 beq campaign_install
 jmp campaign_save_error
campaign_backed_up inc campaign_had_old
campaign_install jsl $E100A8
 dc i2'$2004'
 dc a4'campaign_install_new'
 bcc campaign_installed
 sta campaign_error
 lda campaign_had_old
 beq campaign_save_done
 jsl $E100A8
 dc i2'$2004'
 dc a4'campaign_restore'
 bra campaign_save_done
campaign_installed jsl $E100A8
 dc i2'$2002'
 dc a4'campaign_destroy_backup'
 stz campaign_error
 sep #$20
 longa off
 stz campaign_dirty
 rep #$20
 longa on
 bra campaign_save_done
campaign_save_error sta campaign_error
campaign_save_done pld
 plb
 plp
 rts


; Native16 helper. Resolve the launch directory once, then use absolute paths.
; A raw GS/OS assembly program has no ORCA/C startup to initialize prefix 8.
; We read prefix 0 and never change any GS/OS prefix owned by the caller.
campaign_paths_init anop
 lda campaign_paths_ready
 and #255
 beq campaign_paths_resolve
 clc
 rts
campaign_paths_resolve jsl $E100A8
 dc i2'$200A'
 dc a4'campaign_prefix_params'
 bcc campaign_prefix_ok
 rts
campaign_prefix_ok lda campaign_prefix+2
 beq campaign_prefix_bad
 cmp #243
 bcc campaign_prefix_fits
campaign_prefix_bad lda #$40
 sec
 rts
campaign_prefix_fits sta campaign_prefix_length
 clc
 adc #11
 sta campaign_path
 lda campaign_prefix_length
 clc
 adc #9
 sta campaign_new_path
 sta campaign_backup_path
 ldx #0
 sep #$20
 longa off
campaign_prefix_copy lda campaign_prefix+4,x
 sta campaign_path+2,x
 sta campaign_new_path+2,x
 sta campaign_backup_path+2,x
 inx
 cpx campaign_prefix_length
 bcc campaign_prefix_copy
 ldy campaign_prefix_length
 ldx #0
campaign_name_copy lda campaign_state_name,x
 sta campaign_path+2,y
 inx
 iny
 cpx #11
 bcc campaign_name_copy
 ldy campaign_prefix_length
 ldx #0
campaign_temp_copy lda campaign_temp_name,x
 sta campaign_new_path+2,y
 lda campaign_backup_name,x
 sta campaign_backup_path+2,y
 inx
 iny
 cpx #9
 bcc campaign_temp_copy
 lda #1
 sta campaign_paths_ready
 rep #$20
 longa on
 clc
 rts

; Native16 internal helper. Never destroy the only prior copy after an interrupted
; rename transaction: restore BAK when primary is absent before loading or saving.
campaign_recover anop
 jsl $E100A8
 dc i2'$2010'
 dc a4'campaign_open'
 bcs campaign_recover_missing
 lda campaign_open+2
 sta campaign_close+2
 jsl $E100A8
 dc i2'$2014'
 dc a4'campaign_close'
 rts
campaign_recover_missing cmp #$46
 beq campaign_recover_backup
 sec
 rts
campaign_recover_backup jsl $E100A8
 dc i2'$2004'
 dc a4'campaign_restore'
 bcc campaign_recover_done
 cmp #$46
 bne campaign_recover_failed
 clc
campaign_recover_done rts
campaign_recover_failed sec
 rts

menu_heading dc c'FORCE - APPLE IIGS',h'00'
menu_help dc c'ARROWS: SELECT  RETURN: PLAY',h'00'
menu_help2 dc c'+: REVEAL  -: HIDE  *: RESET',h'00'
menu_help3 dc c'CTRL-Q: MENU / QUIT  CTRL-R: RESTART',h'00'
menu_reset_message dc c'PRESS * AGAIN TO CLEAR ALL SCORES',h'00'
menu_error_message dc c'SCORE ERROR - R RETRIES PENDING SAVE',h'00'
menu_joystick_off dc c'JOYSTICK: OFF  CTRL-J: TOGGLE',h'00'
menu_joystick_on dc c'JOYSTICK: ON   CTRL-J: TOGGLE',h'00'
menu_modifiers ds 1
menu_mode ds 1
menu_ascii ds 1
menu_reset_armed ds 1
menu_saved_x ds 1
menu_row ds 1
menu_score ds 1
ui_miss ds 1
ui_extra ds 1
miss_score ds MISSION_COUNT
campaign_dirty ds 1
campaign_error ds 2
campaign_had_old ds 2
campaign_buffer ds CAMPAIGN_BYTES
campaign_open dc i2'3,0',a4'campaign_path',i2'1'
campaign_open_new dc i2'3,0',a4'campaign_new_path',i2'2'
campaign_io dc i2'4,0',a4'campaign_buffer',i4'CAMPAIGN_BYTES,0'
campaign_close dc i2'1,0'
campaign_create dc i2'4',a4'campaign_new_path',i2'$C3,6',i4'0'
campaign_destroy_new dc i2'1',a4'campaign_new_path'
campaign_destroy_backup dc i2'1',a4'campaign_backup_path'
campaign_backup dc i2'2',a4'campaign_path,campaign_backup_path'
campaign_restore dc i2'2',a4'campaign_backup_path,campaign_path'
campaign_install_new dc i2'2',a4'campaign_new_path,campaign_path'
campaign_prefix_params dc i2'2,0',a4'campaign_prefix'
campaign_prefix dc i2'260,0'
 ds 256
campaign_prefix_length ds 2
campaign_paths_ready ds 2
campaign_state_name dc c'FORCE.STATE'
campaign_temp_name dc c'FORCE.NEW'
campaign_backup_name dc c'FORCE.BAK'
campaign_path ds 258
campaign_new_path ds 258
campaign_backup_path ds 258
