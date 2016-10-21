; Data that needs no initial value. It follows res_end, so it is not in the COM file.
NSD_BP_MAX:     equ     16                      ; User breakpoints
NSD_PLANT_MAX:  equ     NSD_BP_MAX+3            ; and the temporary ones of a step
NSD_LINE_MAX:   equ     60
NAME_MAX:       equ     29

nsd_work:       equ     res_end                 ; The command line, as text
nsd_prog_fcb:   equ     nsd_work+130
; The registers of the program while it is stopped.
nsd_af:         equ     nsd_prog_fcb+36
nsd_bc:         equ     nsd_af+2
nsd_de:         equ     nsd_bc+2
nsd_hl:         equ     nsd_de+2
nsd_ix:         equ     nsd_hl+2
nsd_iy:         equ     nsd_ix+2
nsd_sp:         equ     nsd_iy+2
nsd_pc:         equ     nsd_sp+2
nsd_af2:        equ     nsd_pc+2
nsd_bc2:        equ     nsd_af2+2
nsd_de2:        equ     nsd_bc2+2
nsd_hl2:        equ     nsd_de2+2
nsd_i:          equ     nsd_hl2+2
; Breakpoints of the user: the address and the key of the line, a word each.
nsd_bp_n:       equ     nsd_i+1
nsd_bp_tab:     equ     nsd_bp_n+1
; Breakpoints that are in the memory of the program now: address and original byte.
nsd_plant_n:    equ     nsd_bp_tab+NSD_BP_MAX*4
nsd_plant_tab:  equ     nsd_plant_n+1
; Where the instruction at nsd_pc can go next.
nsd_next_n:     equ     nsd_plant_tab+NSD_PLANT_MAX*3
nsd_next_tab:   equ     nsd_next_n+1
nsd_len:        equ     nsd_next_tab+6
nsd_over:       equ     nsd_len+1               ; Nonzero: a step does not enter calls
nsd_go_after:   equ     nsd_over+1              ; Nonzero: go on after the step
nsd_reason:     equ     nsd_go_after+1
nsd_line_step:  equ     nsd_reason+1            ; Nonzero: a step runs to another line
nsd_step_key:   equ     nsd_line_step+1         ; The line where the step started
nsd_dma:        equ     nsd_step_key+2          ; The DMA address of the program
nsd_goto_on:    equ     nsd_dma+2          ; Nonzero: go to the address nsd_goto
nsd_goto:       equ     nsd_goto_on+1
nsd_rst_save:   equ     nsd_goto+2              ; The 3 bytes at 0038h
nsd_line:       equ     nsd_rst_save+3          ; The line that is typed: room, length, text
ui_ptr:         equ     nsd_line+2+NSD_LINE_MAX+1
ui_col:         equ     ui_ptr+2
ui_attr:        equ     ui_col+1
ui_code_top:    equ     ui_attr+1
ui_code_cur:    equ     ui_code_top+2
ui_dump:        equ     ui_code_cur+2
ui_msg:         equ     ui_dump+2
ui_vdb:         equ     ui_msg+2                ; Cursor and display start at the last frame
code_addr:      equ     ui_vdb+3
prompt_text:    equ     code_addr+2
reg_text:       equ     prompt_text+2
reg_entry:      equ     reg_text+2
dis_ptr:        equ     reg_entry+2
dis_index:      equ     dis_ptr+2               ; 0, 1 for IX or 2 for IY
dis_plain:      equ     dis_index+1
dis_op:         equ     dis_plain+1
dis_disp:       equ     dis_op+1
dis_buf:        equ     dis_disp+1
dis_bias:       equ     dis_buf+32
ui_view:        equ     dis_bias+2              ; 0 code, 1 source
src_file:       equ     ui_view+1
src_top:        equ     src_file+1
src_cur:        equ     src_top+2
pc_key:         equ     src_cur+2
ui_pc_name:     equ     pc_key+2
src_buf:        equ     ui_pc_name+48
; The debug file.
dbg_user:       equ     src_buf+64              ; The user area of the program
dbg_status:     equ     dbg_user+1              ; 0 no file, 1 good, 2 not good
dbg_present:    equ     dbg_status+1
dbg_count:      equ     dbg_present+1
dbg_secs_addr:  equ     dbg_count+1
dbg_secs_line:  equ     dbg_secs_addr+2
dbg_secs_sym:   equ     dbg_secs_line+2
dbg_sector:     equ     dbg_secs_sym+2
dbg_tag_a:      equ     dbg_sector+2
dbg_tag_b:      equ     dbg_tag_a+2
dbg_skip:       equ     dbg_tag_b+2
dbg_best:       equ     dbg_skip+1
dbg_limit:      equ     dbg_best+1
dbg_text_offset: equ    dbg_limit+2
dbg_text_record_no: equ dbg_text_offset+1
sym_name:       equ     dbg_text_record_no+2
sym_low:        equ     sym_name+2
sym_high:       equ     sym_low+2
sym_mid:        equ     sym_high+2
sym_entry:      equ     sym_mid+2
sym_buf:        equ     sym_entry+2
sym_token:      equ     sym_buf+32
src_lines:      equ     sym_token+32
dbg_fcb:        equ     src_lines+2
dbg_hdr:        equ     dbg_fcb+36
dbg_buf_a:      equ     dbg_hdr+128
dbg_buf_b:      equ     dbg_buf_a+128
dbg_blob:       equ     dbg_buf_b+128
out_col:        equ     dbg_blob+NSD_BLOB_MAX*128
nsd_out:        equ     out_col+1               ; The last lines of output of the program
nsd_frame:      equ     nsd_out+OUT_LINES*80
screen_shadow:  equ     nsd_frame+80*24
nsd_stack_low:  equ     screen_shadow+80*24
nsd_stack:      equ     nsd_stack_low+128       ; The debugger stack grows down from here
nsd_bss_end:    equ     nsd_stack
