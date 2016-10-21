; The windows and the keys.
;
;   row 0       title
;   rows 1-12   code (left), registers and stack (right, from REG_COL)
;   row 13      dump title, rows 14-17 dump
;   row 18      output title, rows 19-21 output of the program
;   row 22      message, or the line that is being typed
;   row 23      keys

CODE_FIRST:     equ     1
CODE_LINES:     equ     12
CODE_WIDTH:     equ     56
CODE_TEXT:      equ     20
REG_COL:        equ     58

; Called when the program is loaded and the registers are set.
ui_start:
        call    out_clear
        ld      hl,0
        ld      (dis_bias),hl
        xor     a
        ld      (ui_view),a
        ld      (nsd_line_step),a
        ld      (nsd_goto_on),a
        ld      (src_file),a
        ld      (ui_pc_name),a
        ld      h,a
        ld      l,a
        ld      (pc_key),hl
        inc     l
        ld      (src_cur),hl
        ld      hl,0FFFFh
        ld      (src_top),hl
        ld      hl,(nsd_pc)
        ld      (ui_code_top),hl
        ld      hl,(nsd_sp)
        ld      (ui_dump),hl
        ld      hl,msg_start
        ld      a,(dbg_status)
        cp      2
        jr      nz,start_message
        ld      hl,msg_bad_debug
start_message:
        ld      (ui_msg),hl
        call    ui_update_pc
        ld      a,(dbg_present)
        ld      (ui_view),a
        jp      ui_loop

; The program stopped; DE is the text that says why.
stop_message:
        ld      sp,nsd_stack
        xor     a
        ld      (nsd_goto_on),a
        ld      (ui_msg),de
        call    check_screen
        call    ui_update_pc

ui_loop:
        call    ui_draw
        call    save_screen
ui_key:
        call    read_key
        ld      b,a
        ld      hl,key_table
key_scan:
        ld      a,(hl)
        or      a
        jr      z,ui_key
        inc     hl
        cp      b
        jr      z,key_found
        inc     hl
        inc     hl
        jr      key_scan
key_found:
        ld      e,(hl)
        inc     hl
        ld      d,(hl)
        ex      de,hl
        jp      (hl)

key_table:
        defb    's'
        defw    key_step
        defb    'n'
        defw    key_next
        defb    'g'
        defw    key_go
        defb    'b'
        defw    key_break
        defb    'a'
        defw    key_code_address
        defb    'c'
        defw    key_cursor
        defb    'v'
        defw    key_view
        defb    'l'
        defw    key_line
        defb    'd'
        defw    key_dump_address
        defb    'r'
        defw    key_register
        defb    'm'
        defw    key_memory
        defb    'q'
        defw    key_quit
        defb    'j'
        defw    key_down
        defb    08Ah                    ; Keypad 2
        defw    key_down
        defb    'k'
        defw    key_up
        defb    082h                    ; Keypad 8
        defw    key_up
        defb    'J'
        defw    key_page_down
        defb    083h                    ; Keypad 3
        defw    key_page_down
        defb    'K'
        defw    key_page_up
        defb    089h                    ; Keypad 9
        defw    key_page_up
        defb    0Ch                     ; Ctrl-L
        defw    key_redraw
        defb    0

; Wait for a key, with the program's keys read through the BDOS.
read_key:
        ld      e,0FFh
        ld      c,6
        call    BDOS
        or      a
        jr      z,read_key
        ret

; ---------- running ----------
key_step:
        xor     a
        jr      key_run
key_next:
        ld      a,1
key_run:
        push    af
        xor     a
        ld      (nsd_line_step),a
        ld      a,(ui_view)
        or      a
        jr      z,key_run_start
        ld      hl,(pc_key)
        ld      a,h
        or      l
        jr      z,key_run_start
        ld      (nsd_step_key),hl
        ld      a,1
        ld      (nsd_line_step),a
key_run_start:
        pop     af
        call    do_step
        jr      key_failed
key_go:
        call    do_go
key_failed:
        ld      (ui_msg),de
        jp      ui_loop

; Run to the cursor of the window that is shown.
key_cursor:
        call    cursor_address
        jp      c,bad_argument
        call    program_address
        jp      c,bad_range
        ld      (nsd_goto),hl
        ld      a,1
        ld      (nsd_goto_on),a
        call    do_go
        xor     a
        ld      (nsd_goto_on),a
        jp      key_failed

key_redraw:
        call    screen_invalidate
        jp      ui_loop

key_quit:
        ld      sp,nsd_stack
        ld      a,23
        ld      (adv_y),a
        xor     a
        ld      (adv_x),a
        call    adv_show_cursor
        call    remove_hooks
        jp      0

; ---------- breakpoints ----------
; A breakpoint at the cursor of the window that is shown.
key_break:
        call    cursor_address
        jp      c,bad_argument
        call    program_address
        jp      c,bad_range
key_break_at:
        push    hl
        call    bp_find
        pop     hl
        jr      nz,break_new
        call    bp_remove
        ld      hl,msg_cleared
        jr      break_report
break_new:
        push    hl
        ex      de,hl
        call    dbg_find_line
        ld      b,h
        ld      c,l
        pop     hl
        call    bp_add
        ld      hl,msg_set
        jr      nc,break_report
        ld      hl,msg_full
break_report:
        ld      (ui_msg),hl
        jp      ui_loop

; Carry when HL is not in the memory of the program, where a breakpoint can go.
program_address:
        ld      a,h
        or      a
        jr      z,address_outside
        cp      NSD_BASE/256
        ccf
        ret
address_outside:
        scf
        ret

bad_range:
        ld      hl,msg_range
        ld      (ui_msg),hl
        jp      ui_loop

; HL = the address that the cursor is at: the instruction of the code window, or the
; first instruction of the line of the source window. Carry when the line has no code.
cursor_address:
        ld      a,(ui_view)
        or      a
        jr      nz,cursor_line
        ld      hl,(ui_code_cur)
        or      a
        ret
cursor_line:
        call    source_key
        push    de
        call    dbg_find_address
        pop     de
        ret     c
        ld      a,c
        xor     e
        ld      c,a
        ld      a,b
        xor     d
        or      c
        ret     z
        scf
        ret

; DE = the key of the line of the cursor of the source window.
source_key:
        ld      hl,(src_cur)
        jp      line_key

; ---------- the code window ----------
key_down:
        ld      a,1
        jr      key_move
key_up:
        ld      a,0FFh
        jr      key_move
key_page_down:
        ld      a,CODE_LINES
        jr      key_move
key_page_up:
        ld      a,-CODE_LINES
; Move the cursor of the window that is shown by A lines (a signed number).
key_move:
        ld      b,a
        ld      a,(ui_view)
        or      a
        jr      nz,source_move
        ld      a,b
        or      a
        jp      p,code_down
        neg
        ld      b,a
code_up:
        push    bc
        call    cursor_previous
        pop     bc
        djnz    code_up
        jr      code_moved
code_down:
code_down_next:
        push    bc
        call    cursor_next
        pop     bc
        djnz    code_down_next
code_moved:
        call    code_show
        jp      ui_loop
source_move:
        ld      hl,(src_cur)
        ld      a,b
        ld      e,a
        add     a,a
        sbc     a,a
        ld      d,a
        add     hl,de
        ld      (src_cur),hl
        call    source_limits
        call    source_show
        jp      ui_loop

; The cursor goes to the next instruction.
cursor_next:
        ld      hl,(ui_code_cur)
        call    instr_length
        ld      e,a
        ld      d,0
        add     hl,de
        ld      (ui_code_cur),hl
        ret

; The cursor goes to the instruction before it. Inside the window the lines are exact;
; at the top it takes the start, up to 12 bytes back, from which the instructions
; reach the cursor exactly.
cursor_previous:
        ld      de,(ui_code_cur)
        ld      hl,(ui_code_top)
        or      a
        sbc     hl,de
        jr      nc,previous_search
        add     hl,de
        call    find_before
        jr      nz,previous_search
        ld      (ui_code_cur),hl
        ret
previous_search:
        ld      b,12
previous_try:
        ld      de,(ui_code_cur)
        ld      h,d
        ld      l,e
        ld      a,l
        sub     b
        ld      l,a
        ld      a,h
        sbc     a,0
        ld      h,a
        push    bc
        call    find_before
        pop     bc
        jr      z,previous_set
        djnz    previous_try
        ld      hl,(ui_code_cur)
        dec     hl
previous_set:
        ld      (ui_code_cur),hl
        ret

; Walk the instructions from HL up to the address DE. Z with HL at the last
; instruction before DE when the walk reaches DE exactly.
find_before:
        push    hl
        call    instr_length
        ld      c,a
        ld      b,0
        add     hl,bc
        or      a
        sbc     hl,de
        jr      z,before_found
        jr      nc,before_missed
        add     hl,de
        pop     bc
        jr      find_before
before_found:
        pop     hl
        xor     a
        ret
before_missed:
        pop     hl
        or      1
        ret

; Move the first line of the window so that the cursor is in it.
code_show:
        ld      hl,(ui_code_cur)
        ld      de,(ui_code_top)
        or      a
        sbc     hl,de
        jr      nc,code_below
        ld      hl,(ui_code_cur)
        ld      (ui_code_top),hl
        ret
code_below:
        ld      b,CODE_LINES
        ld      hl,(ui_code_top)
code_scan:
        ld      de,(ui_code_cur)
        push    hl
        or      a
        sbc     hl,de
        pop     hl
        ret     z
        push    bc
        call    instr_length
        ld      e,a
        ld      d,0
        add     hl,de
        pop     bc
        djnz    code_scan
        ; The cursor is below the last line: start at the next line and look again.
        ld      hl,(ui_code_top)
        call    instr_length
        ld      e,a
        ld      d,0
        add     hl,de
        ld      (ui_code_top),hl
        jr      code_show

key_code_address:
        ld      hl,msg_ask_code
        call    ui_prompt
        jp      c,ui_loop_cancel
        call    parse_address
        jp      c,bad_argument
        ld      (ui_code_cur),de
        ld      (ui_code_top),de
        xor     a
        ld      (ui_view),a
        jp      ui_loop_cancel

key_dump_address:
        ld      hl,msg_ask_dump
        call    ui_prompt
        jp      c,ui_loop_cancel
        call    parse_address
        jp      c,bad_argument
        ld      (ui_dump),de
        jp      ui_loop_cancel

bad_argument:
        ld      hl,msg_bad
        ld      (ui_msg),hl
ui_loop_cancel:
        jp      ui_loop

; "name value": set a register of the program.
key_register:
        ld      hl,msg_ask_register
        call    ui_prompt
        jp      c,ui_loop
        ld      (reg_text),hl
        ld      de,register_table
register_search:
        ld      a,(de)
        cp      0FFh
        jp      z,bad_argument
        ld      (reg_entry),de
        inc     de
        inc     de
        ld      hl,(reg_text)
        ld      a,(de)
        cp      (hl)
        jr      nz,register_next
        inc     de
        inc     hl
        ld      a,(de)
        cp      (hl)
        jr      nz,register_next
        inc     de
        inc     hl
        ld      c,' '
        ld      a,(hl)
        cp      27h
        jr      nz,register_third
        ld      c,a
        inc     hl
register_third:
        ld      a,(de)
        cp      c
        jr      z,register_found
register_next:
        ld      hl,(reg_entry)
        ld      de,7
        add     hl,de
        ex      de,hl
        jr      register_search
register_found:
        call    skip_blanks
        call    parse_hex
        jp      c,bad_argument
        ld      hl,(reg_entry)
        ld      bc,5
        add     hl,bc
        ld      a,(hl)
        inc     hl
        ld      h,(hl)
        ld      l,a
        ld      (hl),e
        inc     hl
        ld      (hl),d
        jp      ui_loop

; "address byte byte ...": write bytes of the program's memory.
key_memory:
        ld      hl,msg_ask_memory
        call    ui_prompt
        jp      c,ui_loop_cancel
        call    parse_address
        jp      c,bad_argument
        push    de
memory_next:
        call    skip_blanks
        ld      a,(hl)
        or      a
        jr      z,memory_done
        call    parse_hex
        jr      c,memory_bad
        ld      a,d
        or      a
        jr      nz,memory_bad
        ex      (sp),hl
        ld      a,h
        cp      NSD_BASE/256
        jr      nc,memory_refused
        ld      (hl),e
        inc     hl
        ex      (sp),hl
        jr      memory_next
memory_done:
        pop     hl
        jp      ui_loop_cancel
memory_bad:
        pop     hl
        jp      bad_argument
memory_refused:
        pop     hl
        ld      hl,msg_refused
        ld      (ui_msg),hl
        jp      ui_loop_cancel

; ---------- reading a line ----------
; Type a line on the message row; HL is the prompt. The line is at HL when it returns,
; in capitals and ended by a zero; carry when it was cancelled with Ctrl-C.
ui_prompt:
        ld      (prompt_text),hl
        xor     a
        ld      (nsd_line+1),a
prompt_show:
        ld      b,22
        ld      c,0
        call    ui_goto
        ld      hl,(prompt_text)
        call    ui_puts
        ld      hl,nsd_line+2
        ld      a,(nsd_line+1)
        ld      b,a
        or      a
        jr      z,prompt_typed
prompt_char:
        ld      a,(hl)
        inc     hl
        push    hl
        push    bc
        call    ui_putc
        pop     bc
        pop     hl
        djnz    prompt_char
prompt_typed:
        ld      a,80h
        ld      (ui_attr),a
        ld      a,' '
        call    ui_putc
        xor     a
        ld      (ui_attr),a
        ld      a,80
        call    ui_pad_to
        call    ui_present
        call    read_key
        cp      0Dh
        jr      z,prompt_done
        cp      03h
        jr      z,prompt_cancel
        cp      08h
        jr      z,prompt_back
        cp      7Fh
        jr      z,prompt_back
        cp      20h
        jr      c,prompt_show
        jr      nc,prompt_add
prompt_back:
        ld      a,(nsd_line+1)
        or      a
        jr      z,prompt_show
        dec     a
        ld      (nsd_line+1),a
        jr      prompt_show
prompt_add:
        cp      'a'
        jr      c,prompt_store
        cp      'z'+1
        jr      nc,prompt_store
        sub     20h
prompt_store:
        ld      c,a
        ld      a,(nsd_line+1)
        cp      NSD_LINE_MAX
        jr      nc,prompt_show
        ld      e,a
        ld      d,0
        ld      hl,nsd_line+2
        add     hl,de
        ld      (hl),c
        inc     a
        ld      (nsd_line+1),a
        jr      prompt_show
prompt_done:
        ld      a,(nsd_line+1)
        ld      e,a
        ld      d,0
        ld      hl,nsd_line+2
        add     hl,de
        ld      (hl),0
        ld      hl,msg_blank
        ld      (ui_msg),hl
        ld      hl,nsd_line+2
        or      a
        ret
prompt_cancel:
        ld      hl,msg_blank
        ld      (ui_msg),hl
        scf
        ret

; Read a hexadecimal number at HL. DE has it and HL is after it; carry when there is
; no digit.
parse_hex:
        ld      de,0
        ld      b,0
parse_digit:
        ld      a,(hl)
        sub     '0'
        jr      c,parse_end
        cp      10
        jr      c,parse_value
        sub     'A'-'0'
        jr      c,parse_end
        cp      6
        jr      nc,parse_end
        add     a,10
parse_value:
        ex      de,hl
        add     hl,hl
        add     hl,hl
        add     hl,hl
        add     hl,hl
        ex      de,hl
        or      e
        ld      e,a
        inc     hl
        inc     b
        jr      parse_digit
parse_end:
        ld      a,b
        or      a
        jr      z,parse_none
        cp      5
        ret     c
parse_none:
        scf
        ret

; ---------- the screen after the program ran ----------
; The program or the system may have written on the screen, which moves the cursor
; of the video block or the display start: then every cell is drawn again.
save_screen:
        ld      hl,(adv_vdb)
        ld      a,(hl)
        ld      (ui_vdb),a
        inc     hl
        ld      a,(hl)
        ld      (ui_vdb+1),a
        ld      de,3
        add     hl,de
        ld      a,(hl)
        ld      (ui_vdb+2),a
        ret

check_screen:
        ld      hl,(adv_vdb)
        ld      a,(ui_vdb)
        cp      (hl)
        jr      nz,screen_changed
        inc     hl
        ld      a,(ui_vdb+1)
        cp      (hl)
        jr      nz,screen_changed
        ld      de,3
        add     hl,de
        ld      a,(ui_vdb+2)
        cp      (hl)
        ret     z
screen_changed:
        call    adv_read_scan
        ld      a,1
        ld      (adv_cursor_shown),a
        call    adv_hide_cursor
        jp      screen_invalidate

; ---------- drawing the windows ----------
ui_draw:
        call    frame_clear
        call    draw_title
        call    draw_view
        call    draw_registers
        call    draw_stack
        call    draw_dump
        call    draw_output
        call    draw_message
        ld      b,23
        ld      hl,txt_keys
        call    ui_rule
        jp      ui_present

draw_title:
        ld      b,0
        ld      c,0
        call    ui_goto
        ld      a,80h
        ld      (ui_attr),a
        ld      hl,txt_title
        call    ui_puts
        ld      hl,nsd_prog_fcb+1
        ld      b,8
        call    put_name
        ld      a,'.'
        call    ui_putc
        ld      hl,nsd_prog_fcb+9
        ld      b,3
        call    put_name
        ld      a,' '
        call    ui_putc
        ld      hl,ui_pc_name
        call    ui_puts
        ld      a,80
        call    ui_pad_to
        xor     a
        ld      (ui_attr),a
        ret

; The B characters at HL, without the blanks.
put_name:
        ld      a,(hl)
        inc     hl
        cp      ' '
        jr      z,put_name_skip
        push    hl
        push    bc
        call    ui_putc
        pop     bc
        pop     hl
put_name_skip:
        djnz    put_name
        ret

draw_message:
        ld      b,22
        ld      c,0
        call    ui_goto
        ld      hl,(ui_msg)
        jp      ui_puts

draw_output:
        ld      b,18
        ld      hl,txt_output
        call    ui_rule
        ld      hl,nsd_out
        ld      b,19
        ld      c,OUT_LINES
output_line:
        push    bc
        push    hl
        ld      c,0
        call    ui_goto
        pop     hl
        ld      b,80
output_char:
        ld      a,(hl)
        inc     hl
        push    hl
        push    bc
        call    ui_putc
        pop     bc
        pop     hl
        djnz    output_char
        pop     bc
        inc     b
        dec     c
        jr      nz,output_line
        ret

; ---------- code ----------
; Each line: the breakpoint mark, the PC mark, the address, the bytes and the text.
draw_code:
        ld      hl,(ui_code_top)
        ld      b,CODE_FIRST
draw_code_line:
        push    bc
        push    hl
        call    code_line
        pop     hl
        call    instr_length
        ld      e,a
        ld      d,0
        add     hl,de
        pop     bc
        inc     b
        ld      a,b
        cp      CODE_FIRST+CODE_LINES
        jr      nz,draw_code_line
        ret

; HL = the address, B = the screen row.
code_line:
        ld      (code_addr),hl
        ld      c,0
        call    ui_goto
        ld      hl,(code_addr)
        ld      de,(ui_code_cur)
        or      a
        sbc     hl,de
        ld      a,0
        jr      nz,code_attr
        ld      a,80h
code_attr:
        ld      (ui_attr),a
        ld      hl,(code_addr)
        call    bp_find
        ld      a,' '
        jr      nz,code_no_break
        ld      a,'*'
code_no_break:
        call    ui_putc
        ld      hl,(code_addr)
        ld      de,(nsd_pc)
        or      a
        sbc     hl,de
        ld      a,' '
        jr      nz,code_no_pc
        ld      a,'>'
code_no_pc:
        call    ui_putc
        ld      hl,(code_addr)
        call    ui_hex16
        ld      hl,(code_addr)
        call    instr_length
        ld      b,a
        ld      hl,(code_addr)
code_bytes:
        ld      a,' '
        push    hl
        push    bc
        call    ui_putc
        pop     bc
        pop     hl
        ld      a,(hl)
        inc     hl
        push    hl
        push    bc
        call    ui_hex8
        pop     bc
        pop     hl
        djnz    code_bytes
        ld      a,CODE_TEXT
        call    ui_pad_to
        ld      hl,(code_addr)
        ld      de,dis_buf
        call    disassemble
        ld      hl,dis_buf
        call    ui_puts
        ld      a,CODE_WIDTH
        call    ui_pad_to
        xor     a
        ld      (ui_attr),a
        ret

; ---------- registers and stack ----------
; Each entry: row, column, a name of three characters, the variable of the register.
register_table:
        defb    1,REG_COL
        defm    "AF "
        defw    nsd_af
        defb    1,REG_COL+11
        defm    "BC "
        defw    nsd_bc
        defb    2,REG_COL
        defm    "DE "
        defw    nsd_de
        defb    2,REG_COL+11
        defm    "HL "
        defw    nsd_hl
        defb    3,REG_COL
        defm    "IX "
        defw    nsd_ix
        defb    3,REG_COL+11
        defm    "IY "
        defw    nsd_iy
        defb    4,REG_COL
        defm    "SP "
        defw    nsd_sp
        defb    4,REG_COL+11
        defm    "PC "
        defw    nsd_pc
        defb    5,REG_COL
        defm    "AF'"
        defw    nsd_af2
        defb    5,REG_COL+11
        defm    "BC'"
        defw    nsd_bc2
        defb    6,REG_COL
        defm    "DE'"
        defw    nsd_de2
        defb    6,REG_COL+11
        defm    "HL'"
        defw    nsd_hl2
        defb    0FFh

draw_registers:
        ld      hl,register_table
register_row:
        ld      a,(hl)
        cp      0FFh
        jr      z,draw_flags
        ld      b,a
        inc     hl
        ld      c,(hl)
        inc     hl
        push    hl
        call    ui_goto
        pop     hl
        ld      b,3
register_label:
        ld      a,(hl)
        inc     hl
        push    hl
        push    bc
        call    ui_putc
        pop     bc
        pop     hl
        djnz    register_label
        ld      a,' '
        push    hl
        call    ui_putc
        pop     hl
        ld      e,(hl)
        inc     hl
        ld      d,(hl)
        inc     hl
        push    hl
        ex      de,hl
        ld      e,(hl)
        inc     hl
        ld      d,(hl)
        ex      de,hl
        call    ui_hex16
        pop     hl
        jr      register_row

; The flags: the letter when set, a dot when clear.
draw_flags:
        ld      b,7
        ld      c,REG_COL
        call    ui_goto
        ld      a,(nsd_af)
        ld      c,a
        ld      hl,txt_flags
        ld      b,8
flag_next:
        ld      a,c
        add     a,a
        ld      c,a
        ld      a,'.'
        jr      nc,flag_put
        ld      a,(hl)
flag_put:
        inc     hl
        push    hl
        push    bc
        call    ui_putc
        pop     bc
        pop     hl
        djnz    flag_next
        ret

; Four lines of two words from the stack pointer of the program.
draw_stack:
        ld      hl,(nsd_sp)
        ld      b,9
stack_line:
        push    bc
        push    hl
        ld      c,REG_COL
        call    ui_goto
        pop     hl
        push    hl
        call    ui_hex16
        ld      a,':'
        call    ui_putc
        pop     hl
        ld      b,2
stack_word:
        ld      a,' '
        push    hl
        push    bc
        call    ui_putc
        pop     bc
        pop     hl
        ld      e,(hl)
        inc     hl
        ld      d,(hl)
        inc     hl
        push    hl
        push    bc
        ex      de,hl
        call    ui_hex16
        pop     bc
        pop     hl
        djnz    stack_word
        pop     bc
        inc     b
        ld      a,b
        cp      13
        jr      nz,stack_line
        ret

; ---------- dump ----------
draw_dump:
        ld      b,13
        ld      hl,txt_dump
        call    ui_rule
        ld      hl,(ui_dump)
        ld      b,14
dump_line:
        push    bc
        push    hl
        ld      c,0
        call    ui_goto
        pop     hl
        push    hl
        call    ui_hex16
        ld      a,':'
        call    ui_putc
        pop     hl
        push    hl
        ld      b,16
dump_byte:
        ld      a,' '
        push    hl
        push    bc
        call    ui_putc
        pop     bc
        pop     hl
        ld      a,(hl)
        inc     hl
        push    hl
        push    bc
        call    ui_hex8
        pop     bc
        pop     hl
        djnz    dump_byte
        pop     hl
        ld      a,' '
        push    hl
        call    ui_putc
        pop     hl
        ld      b,16
dump_text:
        ld      a,(hl)
        inc     hl
        cp      20h
        jr      c,dump_dot
        cp      7Fh
        jr      c,dump_put
dump_dot:
        ld      a,'.'
dump_put:
        push    hl
        push    bc
        call    ui_putc
        pop     bc
        pop     hl
        djnz    dump_text
        pop     bc
        inc     b
        ld      a,b
        cp      18
        jr      nz,dump_line
        ret

txt_title:      defm " NSADB  ",0
txt_output:     defm " Output",0
txt_dump:       defm " Dump",0
txt_flags:      defm "SZ.H.PNC"
txt_keys:       defm " s Step n Next g Go c Cursor b Break v View a Code l Line d Dump r Reg q Quit",0
msg_start:      defm " Start of the program",0
msg_blank:      defb 0
msg_breakpoint: defm " Breakpoint",0
msg_stopped:    defm " Stopped",0
msg_set:        defm " Breakpoint set",0
msg_cleared:    defm " Breakpoint cleared",0
msg_full:       defm " Too many breakpoints",0
msg_halt:       defm " HALT cannot be stepped",0
msg_rom:        defm " Cannot plant a breakpoint: not RAM",0
msg_range:      defm " A breakpoint goes in the program: 0100h up to NSADB",0
msg_bad:        defm " Bad argument",0
msg_refused:    defm " The memory of NSADB is not changed",0
msg_ended:      defm " Program ended: press a key",0
msg_bad_debug:  defm " The debug file is not for this program: run tools/mkdbg.py again",0
msg_no_debug:   defm " There is no debug file (make debug, or tools/mkdbg.py)",0
msg_ask_line:   defm " Line: ",0
msg_ask_code:   defm " Code address or label: ",0
msg_ask_dump:   defm " Dump address or label: ",0
msg_ask_register: defm " Register and value: ",0
msg_ask_memory: defm " Address and bytes: ",0
