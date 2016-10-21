; The source window and what goes with it: the line of the program counter, the view that
; is shown, the numbers and labels that the prompts take.

; Called at each stop: the code window and the source window go to the program
; counter, and the label there is made.
ui_update_pc:
        ld      hl,(nsd_pc)
        ld      (ui_code_cur),hl
        call    code_show
        ld      de,(nsd_pc)
        call    dbg_find_line
        ld      (pc_key),hl
        ld      a,h
        or      l
        jr      z,pc_name
        ex      de,hl
        call    dbg_key_file
        ld      b,a
        ld      (src_cur),hl
        ld      a,(src_file)
        cp      b
        ld      a,b
        ld      (src_file),a
        jr      z,pc_follow
        ld      hl,0FFFFh
        ld      (src_top),hl
pc_follow:
        ld      hl,(src_cur)
        ld      de,(src_top)
        or      a
        sbc     hl,de
        jr      c,pc_center
        ld      de,CODE_LINES
        or      a
        sbc     hl,de
        jr      c,pc_name
pc_center:
        ld      hl,(src_cur)
        ld      de,3
        or      a
        sbc     hl,de
        jr      c,pc_first
        ld      a,h
        or      l
        jr      nz,pc_top
pc_first:
        ld      hl,1
pc_top:
        ld      (src_top),hl
pc_name:
        ld      de,(nsd_pc)
        call    dbg_symbol_at
        jr      c,pc_no_name
        push    hl
        ld      hl,sym_buf
        ld      de,ui_pc_name
        call    emit_zstring
        pop     hl
        ld      a,h
        or      l
        jr      z,pc_name_end
        push    hl
        ld      a,'+'
        call    emit_char
        pop     hl
        call    emit_hex16
pc_name_end:
        xor     a
        ld      (de),a
        ret
pc_no_name:
        xor     a
        ld      (ui_pc_name),a
        ret

key_view:
        ld      a,(dbg_present)
        or      a
        jr      z,view_none
        ld      a,(ui_view)
        xor     1
        ld      (ui_view),a
        jp      ui_loop
view_none:
        ld      hl,msg_no_debug
        ld      (ui_msg),hl
        jp      ui_loop

key_line:
        ld      a,(dbg_present)
        or      a
        jr      z,view_none
        ld      hl,msg_ask_line
        call    ui_prompt
        jp      c,ui_loop
        call    parse_decimal
        jp      c,bad_argument
        ld      (src_cur),de
        ld      a,1
        ld      (ui_view),a
        call    source_limits
        call    source_show
        jp      ui_loop

; Keep the line of the cursor of the source window between 1 and the last line.
source_limits:
        ld      a,(src_file)
        call    dbg_file_lines
        ex      de,hl
        ld      hl,(src_cur)
        bit     7,h
        jr      nz,limits_first
        ld      a,h
        or      l
        jr      z,limits_first
        push    hl
        or      a
        sbc     hl,de
        pop     hl
        jr      z,limits_keep
        jr      c,limits_keep
        ex      de,hl
        jr      limits_keep
limits_first:
        ld      hl,1
limits_keep:
        ld      (src_cur),hl
        ret

; Move the first line of the window so that the cursor is in it.
source_show:
        ld      hl,(src_cur)
        ld      de,(src_top)
        or      a
        sbc     hl,de
        jr      c,show_above
        ld      de,CODE_LINES
        or      a
        sbc     hl,de
        ret     c
        ld      hl,(src_cur)
        ld      de,CODE_LINES-1
        or      a
        sbc     hl,de
        ld      (src_top),hl
        ret
show_above:
        ld      hl,(src_cur)
        ld      (src_top),hl
        ret

draw_view:
        ld      a,(ui_view)
        or      a
        jp      z,draw_code

draw_source:
        ld      a,(src_file)
        ld      de,(src_top)
        call    dbg_seek_line
        ld      a,(src_file)
        call    dbg_file_lines
        ld      (src_lines),hl
        ld      hl,(src_top)
        ld      b,CODE_FIRST
source_row:
        push    bc
        push    hl
        call    source_line
        pop     hl
        inc     hl
        pop     bc
        inc     b
        ld      a,b
        cp      CODE_FIRST+CODE_LINES
        jr      nz,source_row
        ret

; HL = a line number, B = the screen row.
source_line:
        ld      (code_addr),hl
        ld      c,0
        call    ui_goto
        ld      hl,(src_lines)
        ld      de,(code_addr)
        or      a
        sbc     hl,de
        ret     c
        ld      de,src_buf
        ld      b,CODE_WIDTH-7
        call    dbg_text_line
        ld      hl,(code_addr)
        ld      de,(src_cur)
        or      a
        sbc     hl,de
        ld      a,0
        jr      nz,source_attr
        ld      a,80h
source_attr:
        ld      (ui_attr),a
        ld      hl,(code_addr)
        call    line_key
        push    de
        call    bp_has_key
        ld      a,' '
        jr      nz,source_no_break
        ld      a,'*'
source_no_break:
        call    ui_putc
        pop     de
        ld      hl,(pc_key)
        or      a
        sbc     hl,de
        ld      a,' '
        jr      nz,source_no_pc
        ld      a,'>'
source_no_pc:
        call    ui_putc
        ld      hl,(code_addr)
        call    ui_dec4
        ld      a,' '
        call    ui_putc
        ld      hl,src_buf
        call    ui_puts
        ld      a,CODE_WIDTH
        call    ui_pad_to
        xor     a
        ld      (ui_attr),a
        ret

; DE = the key of the line HL of the file that the source window shows.
line_key:
        push    hl
        ld      a,(src_file)
        call    dbg_file_base
        ex      de,hl
        pop     hl
        add     hl,de
        dec     hl
        ex      de,hl
        ret

; Z when a breakpoint is on the line with the key DE.
bp_has_key:
        ld      a,(nsd_bp_n)
        ld      b,a
        ld      hl,nsd_bp_tab+2
has_next:
        ld      a,b
        or      a
        jr      z,has_none
        ld      a,(hl)
        cp      e
        jr      nz,has_skip
        inc     hl
        ld      a,(hl)
        dec     hl
        cp      d
        ret     z
has_skip:
        inc     hl
        inc     hl
        inc     hl
        inc     hl
        djnz    has_next
has_none:
        or      1
        ret

; HL as a decimal number in four columns, with blanks in front.
ui_dec4:
        ld      c,1
        ld      de,1000
        call    dec_digit
        ld      de,100
        call    dec_digit
        ld      de,10
        call    dec_digit
        ld      c,0
        ld      de,1
dec_digit:
        ld      a,'0'-1
dec_count:
        inc     a
        or      a
        sbc     hl,de
        jr      nc,dec_count
        add     hl,de
        cp      '0'
        jr      nz,dec_put
        bit     0,c
        jr      z,dec_put
        ld      a,' '
        jr      dec_out
dec_put:
        ld      c,0
dec_out:
        push    hl
        call    ui_putc
        pop     hl
        ret

; A decimal number at HL: DE has it and HL is after it; carry when there is no digit.
parse_decimal:
        ld      de,0
        ld      b,0
decimal_next:
        ld      a,(hl)
        sub     '0'
        cp      10
        jr      nc,decimal_end
        push    hl
        ld      h,d
        ld      l,e
        add     hl,hl
        add     hl,hl
        add     hl,de
        add     hl,hl
        ld      e,a
        ld      d,0
        add     hl,de
        ex      de,hl
        pop     hl
        inc     hl
        inc     b
        jr      decimal_next
decimal_end:
        ld      a,(hl)
        or      a
        jr      z,decimal_last
        cp      ' '
        jr      nz,decimal_bad
decimal_last:
        ld      a,b
        or      a
        jr      z,decimal_bad
        cp      5
        jr      nc,decimal_bad
        or      a
        ret
decimal_bad:
        scf
        ret

; HL = text: an address in hexadecimal or a label (@name makes a label of a name that is
; also a number). DE = the address, HL is after the text; carry when it is neither.
parse_address:
        ld      a,(hl)
        cp      '@'
        jr      nz,address_try_hex
        inc     hl
        jr      address_label
address_try_hex:
        push    hl
        call    parse_hex
        jr      c,address_not_hex
        ld      a,(hl)
        or      a
        jr      z,address_hex_done
        cp      ' '
        jr      z,address_hex_done
address_not_hex:
        pop     hl
address_label:
        ld      de,sym_token
        ld      b,NAME_MAX
address_name:
        ld      a,(hl)
        or      a
        jr      z,address_name_end
        cp      ' '
        jr      z,address_name_end
        inc     hl
        ld      c,a
        ld      a,b
        or      a
        jr      z,address_name
        ld      a,c
        ld      (de),a
        inc     de
        dec     b
        jr      address_name
address_name_end:
        xor     a
        ld      (de),a
        push    hl
        ld      hl,sym_token
        call    dbg_find_symbol
        jr      c,address_no_label
        ex      de,hl
        pop     hl
        or      a
        ret
address_no_label:
        pop     hl
        scf
        ret
address_hex_done:
        pop     af
        or      a
        ret
