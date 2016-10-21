; LESS: a pager for text files on the NorthStar Advantage (64K Graphics CP/M 2.2).
;
;     LESS [-x] [-n] [d:]file
;
; The file is read from the disk by record, never all at once, so it can be larger than
; the memory. The lines are found with an index of one line in 16 that is made as the file
; is read. Long lines are cut at the edge of the screen (the arrows move the text
; sideways). The video code is the one of VI (src/common/adv_screen.asm).
;
;   space, f, PgDn   a page forward           b, PgUp      a page back
;   Enter, j, Down   a line forward           k, Up        a line back
;   d, u             half a page down, up     g, Home      the start    G, End   the end
;   /text, ?text     search forward, back     n, N         the next, the previous
;   Left, Right      sideways by 8 columns    0            back to column 0
;   r                draw the screen again    h            help            q   quit
;
; With -x the file is shown in hexadecimal, 16 bytes a line, with the offset and the
; characters (the bytes of the last record are all shown). With -n each line has its number.

BDOS:           equ     0005h
TAIL:           equ     0080h
FCB1:           equ     005Ch
ROWS:           equ     23              ; rows of text; row 23 is the status line
INDEX_MAX:      equ     768             ; entries of the line index (one line in 16)
LINE_MAX:       equ     255
ROW_SIZE:       equ     LINE_MAX+80+1

; Everything that is written is above the image, in 2000h-3FFFh: video RAM replaces
; 4000h-7FFFh while a glyph is written, so code, data and stack stay below it.
screen_shadow:  equ     2000h
index:          equ     screen_shadow+80*24
cache:          equ     index+INDEX_MAX*3
line_buffer:    equ     cache+128
row_buffer:     equ     line_buffer+LINE_MAX+1
status_buffer:  equ     row_buffer+ROW_SIZE
pattern:        equ     status_buffer+84        ; the text that is searched, in lower case
variables:      equ     pattern+32
stack_low:      equ     variables+256
stack_top:      equ     stack_low+128

        org     0100h
start:  ld      (orig_sp),sp
        ld      sp,stack_top
        call    main
        ld      sp,(orig_sp)
        ret

        include "adv_screen.asm"

; ---------- variables (after the stack) ----------
orig_sp:        equ     variables
top:            equ     orig_sp+2               ; The first line shown, from 0
total:          equ     top+2                   ; The number of lines when the end is known
index_count:    equ     total+2                 ; Entries in the index
read_record:    equ     index_count+2           ; Where the next character is read from
read_offset:    equ     read_record+2
cache_tag:      equ     read_offset+1
total_records:  equ     cache_tag+2
line_record:    equ     total_records+2         ; The record of the line that is shown first
hscroll:        equ     line_record+2
end_known:      equ     hscroll+1
end_hit:        equ     end_known+1             ; The reader has met the end of the file
too_long:       equ     end_hit+1
message:        equ     too_long+1              ; A message for the status line, or 0
pattern_length: equ     message+2
search_backward: equ    pattern_length+1
scratch:        equ     search_backward+1
last_row_line:  equ     scratch+2
fcb:            equ     last_row_line+2         ; 36 bytes
args:           equ     fcb+36
work:           equ     args+2
find_line:      equ     work+130
find_count:     equ     find_line+2
find_last:      equ     find_count+2
hex_mode:       equ     find_last+2
hex_count:      equ     hex_mode+1
hex_line_no:    equ     hex_count+1
hex_bytes:      equ     hex_line_no+2
pct_num:        equ     hex_bytes+16
pct_den:        equ     pct_num+2
wanted:         equ     pct_den+2
numbuf:         equ     wanted+2
number_mode:    equ     numbuf+8                ; -n: a column of line numbers
text_width:     equ     number_mode+1           ; Columns of text: 80, or 74 with -n
next_number:    equ     text_width+1            ; The number of the next line to draw
row_shown:      equ     next_number+2           ; The row has a line (not ~)
gutter:         equ     row_shown+1             ; 6 characters
variables_end:  equ     gutter+6

main:   call    clear_variables
        call    read_arguments
        jp      c,usage
        call    open_file
        ret     c
        call    screen_start
        ret     c
        call    show_start
        jp      key_loop

usage:  ld      de,msg_usage
        jp      print

clear_variables:
        ld      hl,orig_sp+2
        ld      de,orig_sp+3
        ld      bc,variables_end-orig_sp-3
        ld      (hl),0
        ldir
        ld      hl,0FFFFh
        ld      (cache_tag),hl
        ret

print:  ld      c,9
        jp      BDOS

; ---------- the file ----------
read_arguments:
        ld      a,(TAIL)
        and     07Fh
        ld      c,a
        ld      b,0
        ld      hl,TAIL+1
        ld      de,work
        or      a
        jr      z,arguments_copied
        ldir
arguments_copied:
        xor     a
        ld      (de),a
        ld      hl,work
        ld      a,80
        ld      (text_width),a
        call    skip_blanks
option_word:
        ld      a,(hl)
        cp      '-'
        jr      nz,arguments_name
        inc     hl
option_letter:
        ld      a,(hl)
        cp      'X'
        jr      z,option_hex
        cp      'N'
        jr      z,option_number
        scf
        ret
option_hex:
        ld      (hex_mode),a
        jr      option_next
option_number:
        ld      (number_mode),a
option_next:
        inc     hl
        ld      a,(hl)
        cp      ' '+1
        jr      nc,option_letter
        call    skip_blanks
        jr      option_word
arguments_name:
        ld      a,(hex_mode)
        or      a
        jr      z,arguments_width
        xor     a
        ld      (number_mode),a
arguments_width:
        ld      a,(number_mode)
        or      a
        jr      z,arguments_file
        ld      a,74
        ld      (text_width),a
arguments_file:
        ld      a,(hl)
        or      a
        scf
        ret     z
        ld      de,fcb
        call    parse_fcb
        ld      a,(fcb+1)
        cp      ' '
        scf
        ret     z
        or      a
        ret

; Open the file and read its size.
open_file:
        ld      de,fcb
        ld      c,15
        call    BDOS
        inc     a
        jr      nz,file_open
        ld      de,msg_not_found
        call    print
        scf
        ret
file_open:
        ld      de,fcb
        ld      c,35
        call    BDOS
        ld      hl,(fcb+33)
        ld      (total_records),hl
        ld      hl,index
        ld      (hl),0
        inc     hl
        ld      (hl),0
        inc     hl
        ld      (hl),0
        ld      hl,1
        ld      (index_count),hl
        ld      a,(hex_mode)
        or      a
        ret     z
        ld      hl,(total_records)
        add     hl,hl
        add     hl,hl
        add     hl,hl
        ld      (total),hl
        ld      a,1
        ld      (end_known),a
        or      a
        ret

; The next character of the file in A; carry at the end of the file. The end is the
; end of the records or a Ctrl-Z.
read_char:
        ld      a,(end_hit)
        or      a
        jr      nz,read_end
        ld      a,(read_offset)
        cp      128
        jr      c,read_have_record
        ld      hl,(read_record)
        inc     hl
        ld      (read_record),hl
        xor     a
        ld      (read_offset),a
read_have_record:
        ld      hl,(read_record)
        ld      de,(cache_tag)
        or      a
        sbc     hl,de
        jr      z,read_cached
        ld      de,cache
        ld      c,26
        call    BDOS
        ld      hl,(read_record)
        ld      (fcb+33),hl
        xor     a
        ld      (fcb+35),a
        ld      de,fcb
        ld      c,33
        call    BDOS
        or      a
        jr      nz,read_failed
        ld      hl,(read_record)
        ld      (cache_tag),hl
read_cached:
        ld      a,(read_offset)
        ld      e,a
        ld      d,0
        ld      hl,cache
        add     hl,de
        ld      a,(hl)
        cp      01Ah
        jr      nz,read_not_end
        ld      b,a
        ld      a,(hex_mode)
        or      a
        ld      a,b
        jr      z,read_end
read_not_end:
        ld      hl,read_offset
        inc     (hl)
        or      a
        ret
read_failed:
        ld      hl,0FFFFh
        ld      (cache_tag),hl
read_end:
        ld      a,1
        ld      (end_hit),a
        scf
        ret

; The next line of the file goes to line_buffer, ended by a zero; carriage returns are
; dropped and a line is cut at LINE_MAX characters. Carry when there is no line.
read_line:
        ld      a,(hex_mode)
        or      a
        jp      nz,hex_line
        ld      hl,line_buffer
        ld      b,0
        ld      c,0
read_line_next:
        push    hl
        push    bc
        call    read_char
        pop     bc
        pop     hl
        jr      c,read_line_end
        ld      c,1
        cp      0Ah
        jr      z,read_line_done
        cp      0Dh
        jr      z,read_line_next
        ld      d,a
        ld      a,b
        cp      LINE_MAX
        jr      nc,read_line_next
        ld      a,d
        ld      (hl),a
        inc     hl
        inc     b
        jr      read_line_next
read_line_end:
        ld      a,b
        or      c
        jr      nz,read_line_done
        ld      (hl),0
        scf
        ret
read_line_done:
        ld      (hl),0
        or      a
        ret

; Skip a line of the file. Carry when there is no line: the end, with no character.
skip_line:
        ld      b,0
skip_next:
        push    bc
        call    read_char
        pop     bc
        jr      c,skip_end
        ld      b,1
        cp      0Ah
        jr      nz,skip_next
        or      a
        ret
skip_end:
        ld      a,b
        or      a
        ret     nz
        scf
        ret

; Put the reader at the start of the line with the index entry A.
seek_entry:
        ld      l,a
        ld      h,0
        ld      d,h
        ld      e,l
        add     hl,hl
        add     hl,de
        ld      de,index
        add     hl,de
        ld      e,(hl)
        inc     hl
        ld      d,(hl)
        inc     hl
        ld      a,(hl)
        ld      (read_record),de
        ld      (read_offset),a
        xor     a
        ld      (end_hit),a
        ret

; Make the index hold the line DE (one entry in 16), or find the end of the file. Carry
; when the line is not in the file.
ensure_line:
        ld      a,d
        rrca
        rrca
        rrca
        rrca
        ld      h,a
        ld      a,e
        rrca
        rrca
        rrca
        rrca
        and     0Fh
        ld      l,a
        ld      a,h
        and     0F0h
        or      l
        ld      l,a
        ld      a,h
        and     0Fh
        ld      h,a                     ; HL = the line / 16: the entry that holds it
ensure_next:
        ld      de,(index_count)
        ld      (scratch),hl
        or      a
        sbc     hl,de
        jr      c,ensure_have
        ld      a,(end_known)
        or      a
        scf
        ret     nz
        call    extend_index
        ld      hl,(scratch)
        jr      ensure_next
ensure_have:
        or      a
        ret

; Add the entry that follows the last one: read 16 lines from it. When the file ends
; first, its length in lines is known.
extend_index:
        ld      hl,(index_count)
        dec     hl
        ld      a,l
        call    seek_entry
        ld      b,16
extend_line:
        push    bc
        call    skip_line
        pop     bc
        jr      c,extend_end
        djnz    extend_line
        ld      hl,(index_count)
        ld      de,INDEX_MAX
        or      a
        sbc     hl,de
        jr      nc,extend_full
        ld      hl,(index_count)
        ld      d,h
        ld      e,l
        add     hl,hl
        add     hl,de
        ld      de,index
        add     hl,de
        ld      de,(read_record)
        ld      (hl),e
        inc     hl
        ld      (hl),d
        inc     hl
        ld      a,(read_offset)
        ld      (hl),a
        ld      hl,(index_count)
        inc     hl
        ld      (index_count),hl
        ret
extend_full:
        ld      a,1
        ld      (too_long),a
extend_end:
        ld      a,16
        sub     b
        ld      e,a
        ld      d,0
        ld      hl,(index_count)
        dec     hl
        add     hl,hl
        add     hl,hl
        add     hl,hl
        add     hl,hl
        add     hl,de
        ld      (total),hl
        ld      a,1
        ld      (end_known),a
        ret

; Put the reader at the start of line DE (from 0); carry when the file has no such line.
seek_line:
        ld      a,(hex_mode)
        or      a
        jp      nz,hex_seek
        push    de
        call    ensure_line
        pop     de
        ret     c
        ld      a,e
        and     15
        ld      c,a
        ld      a,d
        rrca
        rrca
        rrca
        rrca
        ld      h,a
        ld      a,e
        rrca
        rrca
        rrca
        rrca
        and     0Fh
        ld      l,a
        ld      a,h
        and     0F0h
        or      l
        call    seek_entry
        ld      a,c
        or      a
        ret     z
        ld      b,a
seek_skip:
        push    bc
        call    skip_line
        pop     bc
        ret     c
        djnz    seek_skip
        or      a
        ret

; ---------- hexadecimal ----------
; Line DE of the hex view is the 16 bytes at 16 * DE: the record DE / 8, the offset
; 16 * (DE mod 8) in it. Carry when that is past the end.
hex_seek:
        ld      hl,(total)
        or      a
        sbc     hl,de
        jr      z,hex_past
        jr      c,hex_past
        ld      a,e
        and     7
        add     a,a
        add     a,a
        add     a,a
        add     a,a
        ld      (read_offset),a
        ld      h,d
        ld      l,e
        srl     h
        rr      l
        srl     h
        rr      l
        srl     h
        rr      l
        ld      (read_record),hl
        ld      (hex_line_no),de
        xor     a
        ld      (end_hit),a
        ret
hex_past:
        scf
        ret

; The next 16 bytes as a line: offset, bytes and characters. Carry at the end.
hex_line:
        ld      hl,hex_bytes
        ld      b,16
        ld      c,0
hex_get:
        push    hl
        push    bc
        call    read_char
        pop     bc
        pop     hl
        jr      c,hex_got
        ld      (hl),a
        inc     hl
        inc     c
        djnz    hex_get
hex_got:
        ld      a,c
        or      a
        jr      nz,hex_have
        scf
        ret
hex_have:
        ld      (hex_count),a
        ld      de,line_buffer
        ld      hl,(hex_line_no)
        ld      a,h
        rrca
        rrca
        rrca
        rrca
        and     0Fh
        call    hex_digit
        add     hl,hl
        add     hl,hl
        add     hl,hl
        add     hl,hl
        ld      a,h
        call    hex_byte
        ld      a,l
        call    hex_byte
        ld      a,' '
        ld      (de),a
        inc     de
        ld      (de),a
        inc     de
        ld      hl,hex_bytes
        ld      a,(hex_count)
        ld      b,a
        ld      c,16
hex_cells:
        ld      a,c
        cp      8
        jr      nz,hex_cell
        ld      a,' '
        ld      (de),a
        inc     de
hex_cell:
        ld      a,b
        or      a
        jr      z,hex_blank
        ld      a,(hl)
        inc     hl
        dec     b
        call    hex_byte
        jr      hex_gap
hex_blank:
        ld      a,' '
        ld      (de),a
        inc     de
        ld      (de),a
        inc     de
hex_gap:
        ld      a,' '
        ld      (de),a
        inc     de
        dec     c
        jr      nz,hex_cells
        ld      a,'|'
        ld      (de),a
        inc     de
        ld      hl,hex_bytes
        ld      a,(hex_count)
        ld      b,a
hex_chars:
        ld      a,(hl)
        inc     hl
        cp      ' '
        jr      c,hex_dot
        cp      7Fh
        jr      c,hex_char
hex_dot:
        ld      a,'.'
hex_char:
        ld      (de),a
        inc     de
        djnz    hex_chars
        ld      a,'|'
        ld      (de),a
        inc     de
        xor     a
        ld      (de),a
        ld      hl,(hex_line_no)
        inc     hl
        ld      (hex_line_no),hl
        or      a
        ret

hex_byte:
        push    af
        rrca
        rrca
        rrca
        rrca
        call    hex_digit
        pop     af
hex_digit:
        and     0Fh
        add     a,'0'
        cp      '9'+1
        jr      c,hex_store
        add     a,'A'-'0'-10
hex_store:
        ld      (de),a
        inc     de
        ret

; ---------- the screen ----------
screen_start:
        call    adv_find_vdb
        jr      nc,screen_found
        ld      de,msg_no_video
        call    print
        scf
        ret
screen_found:
        ld      a,1
        ld      (adv_inverse),a
        ld      (adv_cursor_shown),a
        call    adv_read_scan
        call    adv_hide_cursor
        jp      invalidate

; Every cell of the screen is unknown.
invalidate:
        ld      hl,screen_shadow
        ld      (hl),0FFh
        ld      de,screen_shadow+1
        ld      bc,80*24-1
        ldir
        ret

screen_stop:
        ld      a,23
        ld      (adv_y),a
        xor     a
        ld      (adv_x),a
        ld      (adv_style),a
        jp      adv_show_cursor

show_start:
        ld      hl,0
        ld      (top),hl
        jp      draw_screen

; Draw the rows of text and the status line.
draw_screen:
        ld      de,(top)
        call    seek_line
        jr      nc,draw_rows
        ld      a,1
        ld      (end_hit),a
draw_rows:
        ld      hl,(read_record)
        ld      (line_record),hl
        ld      hl,(top)
        inc     hl
        ld      (next_number),hl
        ld      b,0
draw_row_next:
        push    bc
        call    read_line
        jr      c,draw_empty
        ld      a,1
        ld      (row_shown),a
        call    expand_line
        jr      draw_row
draw_empty:
        xor     a
        ld      (row_shown),a
        call    blank_row
        pop     bc
        push    bc
        ld      a,b
        or      a
        jr      z,draw_row
        ld      a,'~'
        ld      (row_buffer),a
draw_row:
        pop     bc
        push    bc
        ld      a,b
        call    draw_text_row
        pop     bc
        inc     b
        ld      a,b
        cp      ROWS
        jr      nz,draw_row_next
        jp      draw_status

blank_row:
        ld      hl,row_buffer
        ld      de,row_buffer+1
        ld      bc,ROW_SIZE-1
        ld      (hl),' '
        ldir
        ret

; line_buffer to row_buffer: tabs to the next multiple of 8, other control characters
; and the characters above 7Eh as ?.
expand_line:
        call    blank_row
        ld      hl,line_buffer
        ld      de,row_buffer
        ld      c,0
expand_next:
        ld      a,(hl)
        or      a
        ret     z
        inc     hl
        cp      9
        jr      z,expand_tab
        cp      ' '
        jr      c,expand_control
        cp      7Fh
        jr      c,expand_store
expand_control:
        ld      a,'?'
expand_store:
        ld      b,a
        ld      a,c
        cp      LINE_MAX
        ret     nc
        ld      a,b
        ld      (de),a
        inc     de
        inc     c
        jr      expand_next
expand_tab:
        ld      a,c
        cp      LINE_MAX
        ret     nc
        inc     de
        inc     c
        ld      a,c
        and     7
        jr      nz,expand_tab
        jr      expand_next

; Draw row_buffer from the column hscroll as the screen row A; with -n the line number goes
; first, in the columns 0-5, and the text is cut at 74 columns.
draw_text_row:
        ld      (adv_y),a
        xor     a
        ld      (adv_style),a
        ld      a,(number_mode)
        or      a
        jr      z,plain_cells
        call    draw_gutter
        ld      a,(hscroll)
        ld      e,a
        ld      d,0
        ld      hl,row_buffer
        add     hl,de
        ld      b,74
        ld      c,6
        jr      draw_cells
; The same without the numbers (the help screen).
draw_plain_row:
        ld      (adv_y),a
        xor     a
        ld      (adv_style),a
plain_cells:
        ld      a,(hscroll)
        ld      e,a
        ld      d,0
        ld      hl,row_buffer
        add     hl,de
        jr      draw_cells_start

; The number of the line of the row, in five columns and a blank (blanks for a row after the
; end of the file), at the start of the row adv_y.
draw_gutter:
        ld      hl,gutter
        ld      de,gutter+1
        ld      bc,5
        ld      (hl),' '
        ldir
        ld      a,(row_shown)
        or      a
        jr      z,gutter_draw
        ld      hl,(next_number)
        push    hl
        ld      de,gutter
        call    emit_decimal5
        pop     hl
        inc     hl
        ld      (next_number),hl
gutter_draw:
        ld      hl,gutter
        ld      b,6
        ld      c,0
        jp      draw_cells

; The status line, from status_buffer, in inverse video.
draw_status:
        call    build_status
        ld      a,23
        ld      (adv_y),a
        ld      a,80h
        ld      (adv_style),a
        ld      hl,status_buffer
        call    draw_cells_start
        xor     a
        ld      (adv_style),a
        ret

; The 80 characters at HL on the row adv_y.
draw_cells_start:
        ld      b,80
        ld      c,0
draw_cells:
        ld      a,c
        ld      (adv_x),a
        ld      a,(hl)
        inc     hl
        push    hl
        push    bc
        call    adv_draw_cell
        pop     bc
        pop     hl
        inc     c
        djnz    draw_cells
        ret

build_status:
        ld      hl,status_buffer
        ld      de,status_buffer+1
        ld      bc,79
        ld      (hl),' '
        ldir
        ld      de,status_buffer
        ld      hl,(message)
        ld      a,h
        or      l
        jr      z,status_normal
        call    put_text
        ld      hl,0
        ld      (message),hl
        ret
status_normal:
        ld      a,' '
        call    put_char
        ld      hl,fcb+1
        ld      b,8
        call    put_name
        ld      a,(fcb+9)
        cp      ' '
        jr      z,status_name_done
        ld      a,'.'
        call    put_char
        ld      hl,fcb+9
        ld      b,3
        call    put_name
status_name_done:
        ld      hl,txt_lines
        call    put_text
        ld      hl,(top)
        inc     hl
        call    emit_number
        ld      a,'-'
        call    put_char
        ld      hl,(top)
        ld      bc,ROWS
        add     hl,bc
        ld      a,(end_known)
        or      a
        jr      z,status_last
        ld      bc,(total)
        push    hl
        or      a
        sbc     hl,bc
        pop     hl
        jr      c,status_last
        ld      h,b
        ld      l,c
status_last:
        call    emit_number
        ld      a,(end_known)
        or      a
        jr      z,status_place
        ld      hl,txt_of
        call    put_text
        ld      hl,(total)
        call    emit_number
status_place:
        ld      hl,txt_two_spaces
        call    put_text
        call    put_percent
        ld      hl,txt_help
        jp      put_text

; The place of the first line in the file as a percentage of its records, or END when
; the last line is on the screen.
put_percent:
        ld      a,(end_known)
        or      a
        jr      z,percent_number
        ld      hl,(top)
        ld      bc,ROWS
        add     hl,bc
        ld      bc,(total)
        or      a
        sbc     hl,bc
        jr      c,percent_number
        ld      hl,txt_end
        jp      put_text
percent_number:
        push    de
        ld      de,(total_records)
        ld      a,d
        or      e
        jr      z,percent_none
        ld      hl,(line_record)
        call    percent
        pop     de
        call    emit_number
        ld      a,'%'
        jp      put_char
percent_none:
        pop     de
        ret

; HL * 100 / DE (DE below 32768, HL not above DE).
percent:
        ld      (pct_num),hl
        ld      (pct_den),de
        ld      bc,0
        ld      hl,0
        ld      a,100
percent_next:
        push    af
        ld      de,(pct_num)
        add     hl,de
        ld      de,(pct_den)
percent_reduce:
        or      a
        sbc     hl,de
        jr      c,percent_back
        inc     bc
        jr      percent_reduce
percent_back:
        add     hl,de
        pop     af
        dec     a
        jr      nz,percent_next
        ld      h,b
        ld      l,c
        ret

put_char:
        ld      (de),a
        inc     de
        ret

put_text:
        ld      a,(hl)
        inc     hl
        or      a
        ret     z
        ld      (de),a
        inc     de
        jr      put_text

put_name:
        ld      a,(hl)
        inc     hl
        cp      ' '
        jr      z,put_name_skip
        ld      (de),a
        inc     de
put_name_skip:
        djnz    put_name
        ret

; ---------- the keys ----------
; A key from the console, waited for.
read_key:
        ld      e,0FFh
        ld      c,6
        call    BDOS
        or      a
        jr      z,read_key
        ret

key_loop:
        call    read_key
        ld      b,a
        ld      hl,key_table
key_scan:
        ld      a,(hl)
        or      a
        jr      z,key_loop
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

; The Advantage keypad sends codes 82h, 8Ah, 88h, 86h, 87h, 84h, 83h and 89h with Cursor
; Lock on (the arrows of the emulator send them too).
key_table:
        defb    ' '
        defw    key_page_down
        defb    'f'
        defw    key_page_down
        defb    06h
        defw    key_page_down
        defb    083h
        defw    key_page_down
        defb    'b'
        defw    key_page_up
        defb    02h
        defw    key_page_up
        defb    089h
        defw    key_page_up
        defb    0Dh
        defw    key_line_down
        defb    'j'
        defw    key_line_down
        defb    08Ah
        defw    key_line_down
        defb    'k'
        defw    key_line_up
        defb    'y'
        defw    key_line_up
        defb    082h
        defw    key_line_up
        defb    'd'
        defw    key_half_down
        defb    'u'
        defw    key_half_up
        defb    'g'
        defw    key_start
        defb    '<'
        defw    key_start
        defb    087h
        defw    key_start
        defb    'G'
        defw    key_end
        defb    '>'
        defw    key_end
        defb    084h
        defw    key_end
        defb    088h
        defw    key_left
        defb    086h
        defw    key_right
        defb    '0'
        defw    key_column_zero
        defb    '/'
        defw    key_search_forward
        defb    '?'
        defw    key_search_backward
        defb    'n'
        defw    key_search_next
        defb    'N'
        defw    key_search_previous
        defb    'r'
        defw    key_redraw
        defb    0Ch
        defw    key_redraw
        defb    'h'
        defw    key_help
        defb    'q'
        defw    key_quit
        defb    03h
        defw    key_quit
        defb    0

key_quit:
        call    screen_stop
        ld      sp,(orig_sp)
        ret

key_redraw:
        call    invalidate
        call    draw_screen
        jp      key_loop

key_page_down:
        ld      hl,(top)
        ld      bc,ROWS-1
        jr      move_down
key_half_down:
        ld      hl,(top)
        ld      bc,ROWS/2
        jr      move_down
key_line_down:
        ld      hl,(top)
        ld      bc,1
move_down:
        add     hl,bc
        jr      scroll_to
key_page_up:
        ld      bc,ROWS-1
        jr      move_up
key_half_up:
        ld      bc,ROWS/2
        jr      move_up
key_line_up:
        ld      bc,1
move_up:
        ld      hl,(top)
        or      a
        sbc     hl,bc
        jr      nc,scroll_to
        ld      hl,0
        jr      scroll_to
key_start:
        ld      hl,0
        jr      scroll_to
key_end:
        call    count_to_end
        ld      hl,0FFFFh

; The first line shown becomes HL, but not past the last line that fills the screen.
scroll_to:
        ld      (wanted),hl
        ld      de,ROWS-1
        add     hl,de
        jr      c,scroll_clamp
        ex      de,hl
        call    seek_line
        jr      c,scroll_clamp
        call    read_line
        jr      c,scroll_clamp
        ld      hl,(wanted)
        jr      scroll_set
scroll_clamp:
        call    count_to_end
        ld      hl,(total)
        ld      de,ROWS
        or      a
        sbc     hl,de
        jr      nc,scroll_last
        ld      hl,0
scroll_last:
        ld      de,(wanted)
        push    hl
        or      a
        sbc     hl,de
        pop     hl
        jr      c,scroll_set
        ex      de,hl
scroll_set:
        ld      (top),hl
        call    draw_screen
        jp      key_loop

; Read the whole file once, so that the index and the number of lines are complete.
count_to_end:
        ld      a,(end_known)
        or      a
        ret     nz
        ld      hl,msg_counting
        ld      (message),hl
        call    draw_status
count_next:
        ld      a,(end_known)
        or      a
        ret     nz
        call    extend_index
        jr      count_next

key_left:
        ld      a,(hscroll)
        sub     8
        jr      nc,hscroll_set
        xor     a
        jr      hscroll_set
key_right:
        ld      a,(text_width)
        neg
        ld      c,a
        ld      a,(hscroll)
        add     a,8
        cp      c
        jr      c,hscroll_set
        ld      a,c
        jr      hscroll_set
key_column_zero:
        xor     a
hscroll_set:
        ld      (hscroll),a
        call    draw_screen
        jp      key_loop

; ---------- search ----------
key_search_forward:
        xor     a
        jr      search_ask
key_search_backward:
        ld      a,1
search_ask:
        ld      (search_backward),a
        call    read_pattern
        jp      c,key_redraw_status
        ld      a,(search_backward)
        jr      search_run

key_search_next:
        ld      a,(search_backward)
        jr      search_run
key_search_previous:
        ld      a,(search_backward)
        xor     1
search_run:
        ld      b,a
        ld      a,(pattern_length)
        or      a
        jr      nz,search_have
        ld      hl,msg_no_pattern
        jr      search_message
search_have:
        ld      a,b
        or      a
        jr      nz,search_back
        call    find_forward
        jr      search_result
search_back:
        call    find_backward
search_result:
        jr      c,search_missing
        ld      hl,(find_line)
        jp      scroll_to
search_missing:
        ld      hl,msg_not_found_text
search_message:
        ld      (message),hl
key_redraw_status:
        call    draw_status
        jp      key_loop

; The first line after the first one on the screen that has the pattern; carry if none.
find_forward:
        ld      hl,msg_searching
        ld      (message),hl
        call    draw_status
        ld      hl,(top)
        inc     hl
        ld      (find_line),hl
        ex      de,hl
        call    seek_line
        ret     c
find_forward_next:
        call    read_line
        ret     c
        call    match_line
        jr      z,find_found
        ld      hl,(find_line)
        inc     hl
        ld      (find_line),hl
        jr      find_forward_next
find_found:
        or      a
        ret

; The last line before the first one on the screen that has the pattern.
find_backward:
        ld      hl,msg_searching
        ld      (message),hl
        call    draw_status
        ld      hl,0
        ld      (find_count),hl
        ld      (find_last),hl
        ld      de,0
        call    seek_line
        ret     c
find_backward_next:
        ld      hl,(find_count)
        ld      de,(top)
        or      a
        sbc     hl,de
        jr      nc,find_backward_end
        call    read_line
        jr      c,find_backward_end
        call    match_line
        jr      nz,find_backward_step
        ld      hl,(find_count)
        inc     hl
        ld      (find_last),hl
find_backward_step:
        ld      hl,(find_count)
        inc     hl
        ld      (find_count),hl
        jr      find_backward_next
find_backward_end:
        ld      hl,(find_last)
        ld      a,h
        or      l
        scf
        ret     z
        dec     hl
        ld      (find_line),hl
        or      a
        ret

; Z when line_buffer has the pattern, in any case.
match_line:
        ld      hl,line_buffer
match_start:
        push    hl
        ld      de,pattern
match_char:
        ld      a,(de)
        or      a
        jr      z,match_found
        ld      b,a
        ld      a,(hl)
        or      a
        jr      z,match_missing
        inc     hl
        call    lower_case
        cp      b
        jr      nz,match_next
        inc     de
        jr      match_char
match_next:
        pop     hl
        inc     hl
        ld      a,(hl)
        or      a
        jr      nz,match_start
        or      1
        ret
match_found:
        pop     hl
        xor     a
        ret
match_missing:
        pop     hl
        or      1
        ret

lower_case:
        cp      'A'
        ret     c
        cp      'Z'+1
        ret     nc
        add     a,20h
        ret

; Ask for the pattern on the status line: the text goes to `pattern` in lower case.
; Carry when it is cancelled with Ctrl-C or empty.
read_pattern:
        ld      hl,pattern
        ld      (hl),0
        xor     a
        ld      (scratch),a
pattern_show:
        ld      hl,status_buffer
        ld      de,status_buffer+1
        ld      bc,79
        ld      (hl),' '
        ldir
        ld      de,status_buffer
        ld      a,(search_backward)
        or      a
        ld      a,'/'
        jr      z,pattern_prompt
        ld      a,'?'
pattern_prompt:
        call    put_char
        ld      hl,pattern
        call    put_text
        ld      a,'_'
        call    put_char
        ld      a,23
        ld      (adv_y),a
        ld      a,80h
        ld      (adv_style),a
        ld      hl,status_buffer
        call    draw_cells_start
        xor     a
        ld      (adv_style),a
        call    read_key
        cp      0Dh
        jr      z,pattern_done
        cp      03h
        jr      z,pattern_cancel
        cp      08h
        jr      z,pattern_back
        cp      7Fh
        jr      z,pattern_back
        cp      ' '
        jr      c,pattern_show
        cp      7Fh
        jr      nc,pattern_show
        call    lower_case
        ld      c,a
        ld      a,(scratch)
        cp      30
        jr      nc,pattern_show
        ld      e,a
        ld      d,0
        ld      hl,pattern
        add     hl,de
        ld      (hl),c
        inc     hl
        ld      (hl),0
        inc     a
        ld      (scratch),a
        jp      pattern_show
pattern_back:
        ld      a,(scratch)
        or      a
        jr      z,pattern_show
        dec     a
        ld      (scratch),a
        ld      e,a
        ld      d,0
        ld      hl,pattern
        add     hl,de
        ld      (hl),0
        jp      pattern_show
pattern_done:
        ld      a,(scratch)
        ld      (pattern_length),a
        or      a
        ret     nz
        scf
        ret
pattern_cancel:
        scf
        ret

; ---------- help ----------
key_help:
        ld      hl,help_text
        ld      b,0
help_row:
        push    bc
        push    hl
        call    blank_row
        pop     hl
        ld      de,row_buffer
        call    put_text
        push    hl
        xor     a
        ld      (hscroll),a
        pop     hl
        pop     bc
        push    bc
        push    hl
        ld      a,b
        call    draw_plain_row
        pop     hl
        pop     bc
        inc     b
        ld      a,(hl)
        or      a
        jr      nz,help_row
help_blank:
        ld      a,b
        cp      ROWS
        jr      z,help_wait
        push    bc
        call    blank_row
        pop     bc
        push    bc
        ld      a,b
        call    draw_plain_row
        pop     bc
        inc     b
        jr      help_blank
help_wait:
        call    read_key
        jp      key_redraw

        include "cpm_fcb.asm"
        include "decimal.asm"

msg_usage:      defm "Usage: LESS [-x] [-n] [d:]file",13,10,'$'
msg_not_found:  defm "LESS: file not found",13,10,'$'
msg_no_video:   defm "LESS: needs the 64K Graphics CP/M video",13,10,'$'
msg_counting:   defm " Counting the lines of the file...",0
msg_searching:  defm " Searching...",0
msg_no_pattern: defm " No pattern: type / or ? and a text",0
msg_not_found_text: defm " Pattern not found",0
txt_lines:      defm "  lines ",0
txt_of:         defm " of ",0
txt_two_spaces: defm "  ",0
txt_end:        defm "END",0
txt_help:       defm "   h help  q quit",0

help_text:
        defm    " LESS: a pager for text files",0
        defm    " ",0
        defm    " space, f, PgDn   a page forward        b, PgUp     a page back",0
        defm    " Enter, j, Down   a line forward        k, y, Up    a line back",0
        defm    " d, u             half a page down, up",0
        defm    " g, Home          the start             G, End      the end",0
        defm    " /text, ?text     search forward, back  n, N        the next, the previous",0
        defm    " Left, Right      sideways by 8 columns 0           back to column 0",0
        defm    " -n at the start shows the numbers of the lines; -x shows the bytes",0
        defm    " r, Ctrl-L        draw the screen again q, Ctrl-C   quit",0
        defm    " ",0
        defm    " A line is cut at the edge of the screen: use Left and Right to see the rest.",0
        defm    " The search ignores the case of letters.",0
        defb    0
image_end:
