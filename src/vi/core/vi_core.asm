; Minimal CP/M 2.2 modal editor for an ANSI/VT100 compatible terminal.
; Assemble with: z80asm -o vi.com vi.asm
; The platform defines text, TEXT_SIZE and yank_buffer, and sets yank_limit
; in platform_init.

BDOS:   equ     0005h
FCB:    equ     005Ch
DMA:    equ     0080h
SCREEN_LINES: equ 23
STATUS_MODE_COLUMN: equ 74      ; One-based; "NORMAL" ends at column 79
TAB_SPACES: equ 4
; Internal cursor-key codes that platform_map_key returns.
KEY_UP:         equ 0F0h
KEY_DOWN:       equ 0F1h
KEY_LEFT:       equ 0F2h
KEY_RIGHT:      equ 0F3h
KEY_HOME:       equ 0F4h
KEY_END:        equ 0F5h
KEY_PAGE_DOWN:  equ 0F6h
KEY_PAGE_UP:    equ 0F7h
MAX_COUNT_PREFIX: equ 1000      ; A count stops growing at four digits

vi_start:
        ld      sp,stack_top
        call    platform_init
        xor     a
        ld      (text_len),a
        ld      (text_len+1),a
        ld      (cursor),a
        ld      (cursor+1),a
        ld      (modified),a
        ld      (movement_only),a
        call    clear_fcb
        call    parse_command_tail
        ld      a,(filename_set)
        or      a
        jr      z,main_loop
        call    load_file
main_loop:
        call    finish_command
        call    clamp_normal_cursor
        call    window_balance
        ld      a,(movement_only)
        or      a
        jr      z,main_full_redraw
        xor     a
        ld      (movement_only),a
        ld      hl,(view_line)
        ld      (old_view_line),hl
        call    adjust_view
        ld      hl,(view_line)
        ld      de,(old_view_line)
        or      a
        sbc     hl,de
        jr      nz,main_full_redraw
        call    position_cursor
        jr      main_read_key
main_full_redraw:
        call    redraw
main_read_key:
        call    read_key
        ld      (last_key),a
        call    classify_movement
        xor     a
        ld      (search_failed),a
        ld      a,(last_key)
        cp      01Bh
        jp      z,normal_mode
        cp      03h
        jp      z,normal_mode
        ld      a,(mode)
        or      a
        jp      nz,insert_mode
        call    take_count_digit
        jp      c,main_loop
        call    take_repeat_count
        ld      a,(expect_dd)
        or      a
        jr      z,dispatch_normal
        xor     a
        ld      (expect_dd),a
        ld      a,(last_key)
        cp      'd'
        jr      z,delete_line_pending
        call    word_mode_key
        jr      nz,dispatch_normal
        call    delete_word
        jp      main_loop
delete_line_pending:
        ld      hl,(repeat_times)
        call    delete_line
        jp      main_loop
dispatch_normal:
        ld      a,(expect_yy)
        or      a
        jr      z,dispatch_replace
        xor     a
        ld      (expect_yy),a
        ld      a,(last_key)
        cp      'y'
        jr      nz,dispatch_replace
        ld      hl,(repeat_times)
        call    yank_line
        jp      main_loop
dispatch_replace:
        ld      a,(expect_r)
        or      a
        jr      z,dispatch_change
        xor     a
        ld      (expect_r),a
        ld      a,(last_key)
        call    replace_character
        jp      main_loop
dispatch_change:
        ld      a,(expect_cw)
        or      a
        jr      z,dispatch_z
        xor     a
        ld      (expect_cw),a
        ld      a,(last_key)
        call    word_mode_key
        jr      nz,dispatch_z
        call    change_word
        jp      main_loop
dispatch_z:
        ld      a,(expect_zz)
        or      a
        jr      z,dispatch_gg
        xor     a
        ld      (expect_zz),a
        ld      a,(last_key)
        cp      'Z'
        jr      nz,dispatch_gg
        call    do_write
        jr      c,dispatch_normal_key
        jp      quit
dispatch_gg:
        ld      a,(expect_gg)
        or      a
        jr      z,dispatch_normal_key
        xor     a
        ld      (expect_gg),a
        ld      a,(last_key)
        cp      'g'
        jr      nz,dispatch_normal_key
        call    move_file_start
        jp      main_loop
dispatch_normal_key:
        ld      a,(last_key)
        call    is_repeatable_key
        jr      nz,dispatch_once
        ld      hl,(repeat_times)
dispatch_repeat:
        push    hl
        ld      a,(last_key)
        call    normal_key
        pop     hl
        dec     hl
        ld      a,h
        or      l
        jr      nz,dispatch_repeat
        jp      main_loop
dispatch_once:
        ld      a,(last_key)
        call    normal_key
        ; A prefix such as d or y keeps the count for its second key.
        call    any_prefix_pending
        jp      z,main_loop
        ld      hl,(repeat_times)
        ld      (repeat_count),hl
        jp      main_loop
; Cursor keys (F0h-F7h from platform_map_key) move in Insert mode too.
insert_mode:
        ld      a,(last_key)
        cp      KEY_UP
        jr      c,insert_text_key
        cp      KEY_PAGE_UP+1
        jr      nc,insert_text_key
        call    normal_key
        jp      main_loop
insert_text_key:
        call    insert_key
        jp      main_loop

normal_mode:
        ld      a,(mode)
        or      a
        call    nz,step_back_in_line
        xor     a
        ld      (repeat_count),a
        ld      (repeat_count+1),a
        ld      (mode),a
        ld      (expect_dd),a
        ld      (expect_yy),a
        ld      (expect_cw),a
        ld      (expect_zz),a
        ld      (expect_r),a
        ld      (expect_gg),a
        jp      main_loop

; A Normal-mode command is finished when no Insert session, prefix or count
; is pending. Its change, if any, is then closed, so the next edit starts a
; new undo log.
; A command that changed the text is kept for '.', unless it was an ex
; command, '.' itself, or too long. The next command's keys start afresh.
finish_command:
        ld      a,(mode)
        or      a
        ret     nz
        call    any_prefix_pending
        ret     nz
        ld      hl,(repeat_count)
        ld      a,h
        or      l
        ret     nz
        ld      hl,cmd_len
        ld      b,(hl)
        ld      (hl),a
        ld      a,(change_open)
        or      a
        ret     z
        xor     a
        ld      (change_open),a
        ld      a,b
        or      a
        ret     z
        cp      CMD_KEYS_MAX+1
        ret     nc
        ld      a,(cmd_keys)
        cp      ':'
        ret     z
        cp      '.'
        ret     z
        ld      a,b
        ld      (dot_len),a
        ld      c,b
        ld      b,0
        ld      hl,cmd_keys
        ld      de,dot_keys
        ldir
        ret

; Digits typed in Normal mode build a repeat count. A leading 0 is the
; line-start motion, and the key after a prefix (r5) is not a count digit.
; Carry is set when the key was taken as a digit.
take_count_digit:
        call    any_prefix_pending
        ret     nz
        ld      a,(last_key)
        sub     '0'
        jr      c,count_not_digit
        cp      10
        jr      nc,count_not_digit
        ld      e,a
        ld      d,0
        ld      hl,(repeat_count)
        ld      a,h
        or      l
        jr      nz,count_append
        ld      a,e
        or      a
        jr      z,count_not_digit
count_append:
        push    hl
        ld      bc,MAX_COUNT_PREFIX
        or      a
        sbc     hl,bc
        pop     hl
        jr      nc,count_taken
        add     hl,hl
        ld      b,h
        ld      c,l
        add     hl,hl
        add     hl,hl
        add     hl,bc
        add     hl,de
        ld      (repeat_count),hl
count_taken:
        ld      a,1
        ld      (movement_only),a
        scf
        ret
count_not_digit:
        or      a
        ret

; repeat_times = the typed count, or 1 without one; the count is consumed.
; count_typed is not 0 when there was a count.
take_repeat_count:
        ld      hl,(repeat_count)
        ld      a,h
        or      l
        ld      (count_typed),a
        jr      nz,repeat_count_ready
        inc     hl
repeat_count_ready:
        ld      (repeat_times),hl
        ld      hl,0
        ld      (repeat_count),hl
        ret

; NZ when a two-key command is waiting for its second key. Carry is clear.
any_prefix_pending:
        ld      a,(expect_dd)
        ld      b,a
        ld      a,(expect_yy)
        or      b
        ld      b,a
        ld      a,(expect_cw)
        or      b
        ld      b,a
        ld      a,(expect_zz)
        or      b
        ld      b,a
        ld      a,(expect_r)
        or      b
        ld      b,a
        ld      a,(expect_gg)
        or      b
        ret

; Z when the Normal-mode key in A repeats with a count.
is_repeatable_key:
        ld      hl,repeatable_keys
        ld      b,repeatable_keys_end-repeatable_keys
repeatable_scan:
        cp      (hl)
        ret     z
        inc     hl
        djnz    repeatable_scan
        ret

repeatable_keys:
        defb    'h','j','k','l','w','b','e','W','B','E','x','J','p','P'
        defb    KEY_UP,KEY_DOWN,KEY_LEFT,KEY_RIGHT,KEY_PAGE_DOWN,KEY_PAGE_UP
repeatable_keys_end:

; ---------- console and screen ----------
; Return the next key: from the '.' replay if one is running, otherwise from
; the console, recording it for '.'.
read_key:
        ld      a,(replay_left)
        or      a
        jr      nz,read_replayed_key
        call    platform_show_cursor
read_key_poll:
        ld      c,6
        ld      e,0FFh
        call    BDOS
        or      a
        jr      z,read_key_poll
        call    platform_map_key
        or      a
        ret     z
        push    af
        ld      a,(cmd_len)
        cp      CMD_KEYS_MAX
        jr      nc,read_key_too_long
        ld      e,a
        ld      d,0
        inc     a
        ld      (cmd_len),a
        ld      hl,cmd_keys
        add     hl,de
        pop     af
        ld      (hl),a
        ret
read_key_too_long:
        ld      a,CMD_KEYS_MAX+1        ; Too long to keep for '.'.
        ld      (cmd_len),a
        pop     af
        ret
read_replayed_key:
        dec     a
        ld      (replay_left),a
        ld      hl,(replay_ptr)
        ld      a,(hl)
        inc     hl
        ld      (replay_ptr),hl
        ret

; '.' replays the keys of the last command that changed the text.
repeat_change:
        ld      a,(dot_len)
        or      a
        ret     z
        ld      (replay_left),a
        ld      hl,dot_keys
        ld      (replay_ptr),hl
        ret

; Erase the character before the cursor on the screen.
erase_echo:
        ld      a,08h
        call    putc
        ld      a,' '
        call    putc
        ld      a,08h
        jp      putc

putc:
        push    af
        push    bc
        push    de
        push    hl
        call    platform_output_char
        pop     hl
        pop     de
        pop     bc
        pop     af
        ret

puts:
        ld      a,(hl)
        cp      '$'
        ret     z
        call    putc
        inc     hl
        jr      puts

redraw:
        call    adjust_view
        call    scroll_since_last_frame
        call    platform_begin_redraw
        call    screen_clear
        ld      hl,(view_line)
        inc     hl
        call    gutter_start
        ld      a,(text_origin)
        dec     a
        ld      hl,text_columns
        add     a,(hl)
        ld      (row_max),a
        ld      hl,(text_len)
        ld      de,text
        add     hl,de
        ld      (draw_end),hl
        ld      hl,text
        ld      de,(view_offset)
        add     hl,de
        ld      b,SCREEN_LINES
draw_loop:
        push    bc
        call    find_line
        call    row_needs_drawing
        jr      c,draw_row
        call    platform_skip_row
        jr      c,draw_row
        ld      a,(show_numbers)
        or      a
        call    nz,gutter_increment
        jr      draw_next
draw_row:
        call    build_row
        ld      hl,row_buf
        call    platform_draw_row
draw_next:
        ld      hl,(row_next)
        pop     bc
        djnz    draw_loop
        xor     a
        ld      (dirty_all),a
        ld      (dirty_after),a
        ld      hl,0FFFFh
        ld      (dirty_from),hl
        jp      draw_status

; The line at HL: row_src is its start, row_chars the bytes before its line
; feed (or before the end of the text) and row_next the start of the next line.
find_line:
        ld      (row_src),hl
        ld      (row_next),hl
        ld      hl,0
        ld      (row_chars),hl
        ld      de,(draw_end)
        ld      hl,(row_src)
        ex      de,hl
        or      a
        sbc     hl,de
        ld      b,h
        ld      c,l
        ex      de,hl
        ld      a,b
        or      c
        ret     z
        ld      a,0Ah
        push    hl
        cpir
        ld      (row_next),hl
        pop     de
        jr      nz,find_measure
        dec     hl
find_measure:
        or      a
        sbc     hl,de
        ld      (row_chars),hl
        ret

; Carry is set when the row of this line has to be drawn: when something it
; shows has changed since the last frame. A change makes the rows from its line
; to the bottom need drawing when it added or removed a line feed or was not the
; only change (note_dirty), and only its own row otherwise.
row_needs_drawing:
        ld      a,(dirty_all)
        or      a
        jr      nz,row_draw
        ld      hl,(row_src)
        ld      de,text
        or      a
        sbc     hl,de
        ld      de,(row_chars)
        add     hl,de
        ld      de,(dirty_from)
        or      a
        sbc     hl,de
        jr      c,row_keep
        ld      a,(dirty_after)
        or      a
        jr      nz,row_draw
        ld      hl,0FFFFh
        ld      (dirty_from),hl
row_draw:
        scf
        ret
row_keep:
        or      a
        ret

; Build in row_buf what the screen shows for the line found by find_line: the
; line number, then the text with each tab as spaces up to the next 8-column
; stop and each other control byte as a question mark, cut at text_columns.
; Returns B = the length of the row.
build_row:
        ld      de,row_buf
        ld      a,(show_numbers)
        or      a
        call    nz,gutter_row
        ld      (row_text),de
        ld      hl,(row_chars)
        ld      a,(text_columns)
        ld      b,a
        ld      a,h
        or      a
        jr      nz,row_limit
        ld      a,l
        cp      b
        jr      nc,row_limit
        ld      b,a
row_limit:
        ld      hl,(row_src)
        ld      de,(row_text)
        ld      c,0
        ld      a,b
        or      a
        jr      z,row_done
row_copy:
        ld      a,(hl)
        inc     hl
        cp      20h
        jr      c,row_special
        ld      (de),a
        inc     de
        inc     c
row_next_char:
        djnz    row_copy
row_done:
        ld      hl,row_buf
        ex      de,hl
        or      a
        sbc     hl,de
        ld      a,(row_max)
        cp      l
        jr      c,row_clip
        ld      a,l
row_clip:
        ld      b,a
        ret
row_special:
        cp      09h
        jr      z,row_tab
        ld      a,'?'
        ld      (de),a
        inc     de
        inc     c
        jr      row_next_char
row_tab:
        ld      a,' '
        ld      (de),a
        inc     de
        inc     c
        ld      a,c
        and     7
        jr      nz,row_tab
        ld      a,(text_columns)
        sub     c
        jr      c,row_done
        jr      z,row_done
        inc     a
        cp      b
        jr      nc,row_next_char
        ld      b,a
        jr      row_next_char

; Make gutter_digits the five digits of the line number HL.
gutter_start:
        ld      de,gutter_digits
        ld      bc,-10000
        call    gutter_digit
        ld      bc,-1000
        call    gutter_digit
        ld      bc,-100
        call    gutter_digit
        ld      bc,-10
        call    gutter_digit
        ld      a,'0'
        add     a,l
        ld      (de),a
        ret
gutter_digit:
        ld      a,'0'-1
gutter_digit_next:
        inc     a
        add     hl,bc
        jr      c,gutter_digit_next
        sbc     hl,bc
        ld      (de),a
        inc     de
        ret

; Write the gutter of one row at DE (the number right-aligned in five
; columns, a bar and a space) and go on to the next line number.
gutter_row:
        ld      hl,gutter_digits
        ld      b,4
gutter_blank:
        ld      a,(hl)
        cp      '0'
        jr      nz,gutter_copy
        ld      a,' '
        ld      (de),a
        inc     de
        inc     hl
        djnz    gutter_blank
gutter_copy:
        inc     b
gutter_copy_digit:
        ld      a,(hl)
        ld      (de),a
        inc     hl
        inc     de
        djnz    gutter_copy_digit
        ld      a,'|'
        ld      (de),a
        inc     de
        ld      a,' '
        ld      (de),a
        inc     de
gutter_increment:
        ld      hl,gutter_digits+4
        ld      b,5
gutter_next:
        inc     (hl)
        ld      a,(hl)
        cp      '9'+1
        ret     nz
        ld      (hl),'0'
        dec     hl
        djnz    gutter_next
        ret

; When the view moved by 1 to SCREEN_LINES-1 lines since the last frame,
; let the platform move what is already on the screen, so the frame redraws
; only the rows that came into view.
scroll_since_last_frame:
        ld      hl,(view_line)
        ld      de,(drawn_view_line)
        ld      (drawn_view_line),hl
        or      a
        sbc     hl,de
        ld      a,h
        or      l
        ret     z
        ld      a,h
        or      a
        jr      z,scroll_down_lines
        inc     a               ; H = FFh: the view moved up.
        jr      nz,scroll_jump
        ld      a,l
        cp      -(SCREEN_LINES-1)
        jr      c,scroll_jump
        jp      platform_scroll
scroll_down_lines:
        ld      a,l
        cp      SCREEN_LINES
        jr      nc,scroll_jump
        jp      platform_scroll
scroll_jump:
        jp      mark_all_dirty

; The next frame draws every row.
mark_all_dirty:
        ld      a,1
        ld      (dirty_all),a
        ret

; A change of BC bytes at offset HL; DE addresses the bytes added or removed.
; The next frame draws again the rows it touched (see row_needs_drawing).
note_change:
        push    hl
        push    bc
        ex      de,hl
        call    count_newlines
        ld      a,d
        or      e
        pop     bc
        pop     hl
; HL = the offset of a change, A not 0 when it added or removed a line feed.
note_dirty:
        ld      c,a
        ld      de,(dirty_from)
        ld      a,d
        and     e
        inc     a
        jr      z,dirty_first
        ld      a,1
        ld      (dirty_after),a
        or      a
        sbc     hl,de
        ret     nc
        add     hl,de
        ld      (dirty_from),hl
        ret
dirty_first:
        ld      (dirty_from),hl
        ld      a,c
        or      a
        ld      a,0
        jr      z,dirty_lf
        inc     a
dirty_lf:
        ld      (dirty_after),a
        ret

; Status row: file name and flags on the left, the mode at the right edge.
draw_status:
        call    screen_status_start
        ld      hl,filename_label
        call    puts
        ld      a,(filename_set)
        or      a
        jr      nz,status_have_filename
        ld      hl,no_name_label
        call    puts
        jr      status_modified
status_have_filename:
        ld      hl,filename
        call    print_filename
status_modified:
        ld      a,(modified)
        or      a
        jr      z,status_search
        ld      hl,modified_label
        call    puts
status_search:
        ld      a,(search_failed)
        or      a
        jr      z,status_mode
        ld      hl,not_found_label
        call    puts
status_mode:
        ld      a,STATUS_MODE_COLUMN
        call    platform_status_column
        ld      hl,normal_label
        ld      a,(mode)
        or      a
        jr      z,status_mode_print
        call    platform_bold_on
        ld      hl,insert_label
        call    puts
        call    platform_bold_off
        jr      status_cursor
status_mode_print:
        call    puts
status_cursor:
        ; Position the cursor while Advantage cursor drawing is inhibited,
        ; then re-enable it without moving it.
        call    position_cursor
        jp      platform_end_redraw

; Row from the view top and column from the line start, both one-based for
; the ANSI terminal. Uses the cursor_line values from adjust_view.
position_cursor:
        ld      hl,(cursor_line)
        ld      de,(view_line)
        or      a
        sbc     hl,de
        ld      a,l
        inc     a
        ld      (ansi_row),a
        call    visual_column
        ld      a,(text_columns)
        ld      e,a
        ld      d,0
        or      a
        sbc     hl,de
        ld      a,80
        jr      nc,cursor_col_ok
        add     hl,de
        ld      a,(text_origin)
        add     a,l
cursor_col_ok:
        ld      (ansi_col),a
        jp      platform_position_cursor

; HL = screen column of the cursor within its line, zero-based, with tabs
; expanded to 8-column stops as redraw draws them.
visual_column:
        ld      hl,(cursor)
        ld      de,(cursor_line_start)
        or      a
        sbc     hl,de
        ld      b,h
        ld      c,l
        ld      hl,text
        add     hl,de
        ex      de,hl
        ld      hl,0
visual_column_loop:
        ld      a,b
        or      c
        ret     z
        ld      a,(de)
        inc     de
        dec     bc
        cp      09h
        jr      z,visual_column_tab
        inc     hl
        jr      visual_column_loop
visual_column_tab:
        ld      a,l
        or      7
        ld      l,a
        inc     hl
        jr      visual_column_loop

; Set movement_only when this key only moves the cursor. Mutations and
; mode changes still take the full redraw path.
classify_movement:
        xor     a
        ld      (movement_only),a
        call    any_prefix_pending
        ret     nz
        ld      a,(mode)
        or      a
        jr      z,classify_normal_move
        ld      a,(last_key)
        cp      KEY_UP
        jr      c,classify_done
        cp      KEY_PAGE_UP+1
        jr      nc,classify_done
        jr      classify_set_move
classify_normal_move:
        ld      a,(last_key)
        cp      KEY_UP
        jr      c,classify_ascii_move
        cp      KEY_PAGE_UP+1
        jr      c,classify_set_move
        jr      classify_done
classify_ascii_move:
        cp      'h'
        jr      z,classify_set_move
        cp      'j'
        jr      z,classify_set_move
        cp      'k'
        jr      z,classify_set_move
        cp      'l'
        jr      z,classify_set_move
        cp      '0'
        jr      z,classify_set_move
        cp      '$'
        jr      z,classify_set_move
        cp      'w'
        jr      z,classify_set_move
        cp      'b'
        jr      z,classify_set_move
        cp      'e'
        jr      z,classify_set_move
        cp      'W'
        jr      z,classify_set_move
        cp      'B'
        jr      z,classify_set_move
        cp      'E'
        jr      z,classify_set_move
        cp      'G'
        jr      z,classify_set_move
        cp      06h
        jr      z,classify_set_move
        cp      02h
        jr      z,classify_set_move
        jr      classify_done
classify_set_move:
        ld      a,1
        ld      (movement_only),a
classify_done:
        ret

screen_clear:
        jp      platform_clear_screen

screen_status_start:
        jp      platform_status_start

; Start an ex-command prompt at the left of the cleared status row.
status_prompt:
        call    screen_status_start
        ld      a,':'
        jp      putc

print_decimal:
        ; The row/column are 1..80; this emits one or two ASCII digits.
        cp      10
        jr      c,decimal_one
        ld      b,a
        ld      a,b
        ld      c,0
decimal_count:
        cp      10
        jr      c,decimal_emit
        sub     10
        inc     c
        jr      decimal_count
decimal_emit:
        add     a,'0'
        ld      d,a
        ld      a,c
        add     a,'0'
        call    putc
        ld      a,d
        jp      putc
decimal_one:
        add     a,'0'
        jp      putc

print_filename:
        ld      b,8
filename_print_loop:
        ld      a,(hl)
        cp      ' '
        jr      z,filename_skip
        call    putc
filename_skip:
        inc     hl
        djnz    filename_print_loop
        ld      a,(hl)
        cp      ' '
        jr      z,filename_print_done
        ld      a,'.'
        call    putc
        ld      b,3
filename_ext_loop:
        ld      a,(hl)
        cp      ' '
        jr      z,filename_ext_skip
        call    putc
filename_ext_skip:
        inc     hl
        djnz    filename_ext_loop
filename_print_done:
        ret

; ---------- normal and insert mode ----------
normal_key:
        cp      KEY_UP
        jp      z,move_up
        cp      KEY_DOWN
        jp      z,move_down
        cp      KEY_LEFT
        jp      z,move_left
        cp      KEY_RIGHT
        jp      z,move_right
        cp      KEY_HOME
        jp      z,move_line_start
        cp      KEY_END
        jp      z,move_line_end
        cp      KEY_PAGE_DOWN
        jp      z,move_page_down
        cp      KEY_PAGE_UP
        jp      z,move_page_up
        cp      'h'
        jp      z,move_left
        cp      'l'
        jp      z,move_right
        cp      'j'
        jp      z,move_down
        cp      'k'
        jp      z,move_up
        cp      '0'
        jp      z,move_line_start
        cp      '$'
        jp      z,move_line_end
        cp      'w'
        jp      z,small_word_forward
        cp      'W'
        jp      z,big_word_forward
        cp      'b'
        jp      z,small_word_backward
        cp      'B'
        jp      z,big_word_backward
        cp      'e'
        jp      z,small_word_end
        cp      'E'
        jp      z,big_word_end
        cp      'G'
        jp      z,move_file_end
        cp      'g'
        jp      z,move_gg_prefix
        cp      06h
        jp      z,move_page_down
        cp      02h
        jp      z,move_page_up
        cp      'i'
        jp      z,enter_insert
        cp      'a'
        jp      z,append_insert
        cp      'o'
        jp      z,open_below
        cp      'O'
        jp      z,open_above
        cp      'u'
        jp      z,undo_change
        cp      012h
        jp      z,redo_change
        cp      '.'
        jp      z,repeat_change
        cp      'x'
        jp      z,delete_char_in_line
        cp      'r'
        jp      z,replace_prefix
        cp      'J'
        jp      z,join_lines
        cp      'd'
        jp      z,delete_line_prefix
        cp      'y'
        jp      z,yank_line_prefix
        cp      'p'
        jp      z,paste_after_line
        cp      'P'
        jp      z,paste_before_line
        cp      'c'
        jp      z,change_word_prefix
        cp      'D'
        jp      z,delete_to_line_end
        cp      'C'
        jp      z,change_to_line_end
        cp      'n'
        jp      z,repeat_search
        cp      'Z'
        jp      z,quit_prefix
        cp      ':'
        jp      z,ex_command
        cp      '/'
        jp      z,search_command
        ret

enter_insert:
        ld      a,1
        ld      (mode),a
        ret
append_insert:
        call    move_right
        ld      a,1
        ld      (mode),a
        ret
open_below:
        call    end_of_line
        call    insert_newline
        ld      a,1
        ld      (mode),a
        ret
open_above:
        call    have_room
        ret     c
        call    move_line_start
        call    insert_newline
        ld      hl,(cursor)     ; Back onto the new empty line.
        dec     hl
        ld      (cursor),hl
        ld      a,1
        ld      (mode),a
        ret

insert_key:
        cp      09h
        jr      z,insert_tab
        cp      0Dh
        jr      z,insert_newline
        cp      08h
        jp      z,backspace
        cp      7Fh
        jp      z,backspace
        cp      20h
        ret     c
        jp      insert_byte

insert_newline:
        ld      a,0Ah
        jp      insert_byte

insert_tab:
        ld      b,TAB_SPACES
insert_tab_loop:
        push    bc
        ld      a,' '
        call    insert_byte
        pop     bc
        djnz    insert_tab_loop
        ret

insert_byte:
        ld      (work_byte),a
        call    have_room
        ret     c
        ld      hl,(cursor)
        ld      bc,1
        ld      de,work_byte
        call    text_insert
        ld      hl,(cursor)
        inc     hl
        ld      (cursor),hl
        ld      a,1
        ld      (modified),a
        ret

; Open a gap of BC bytes at offset HL: move text[HL..text_len) up and grow
; text_len. The caller has checked that the gap fits.
open_gap:
        ld      (gap_size),bc
        ex      de,hl
        ld      hl,(text_len)
        or      a
        sbc     hl,de
        ld      b,h
        ld      c,l
        ld      hl,(text_len)
        ld      de,text-1
        add     hl,de
        push    hl
        ld      de,(gap_size)
        add     hl,de
        ex      de,hl
        pop     hl
        call    copy_backward
open_gap_moved:
        ld      hl,(text_len)
        ld      de,(gap_size)
        add     hl,de
        ld      (text_len),hl
        ret

; Move BC bytes from HL to DE upwards in memory, as LDIR does, but at 16 cycles
; a byte instead of 21: a block of 16 LDI that repeats while BC is not 0. The
; first pass jumps into the block so that it moves the bytes that do not fill
; one, and the rest is whole blocks. Moving the text is most of the cost of an
; edit near the start of a large document.
copy_forward:
        ld      a,b
        or      c
        ret     z
        ld      a,c
        and     15
        jr      z,copy_forward_block
        neg
        add     a,16
        add     a,a
        push    hl
        ld      hl,copy_forward_block
        add     a,l
        ld      l,a
        jr      nc,copy_forward_go
        inc     h
copy_forward_go:
        ex      (sp),hl
        ret
copy_forward_block:
        ldi
        ldi
        ldi
        ldi
        ldi
        ldi
        ldi
        ldi
        ldi
        ldi
        ldi
        ldi
        ldi
        ldi
        ldi
        ldi
        jp      pe,copy_forward_block
        ret

; The same downwards, as LDDR: HL and DE address the last bytes.
copy_backward:
        ld      a,b
        or      c
        ret     z
        ld      a,c
        and     15
        jr      z,copy_backward_block
        neg
        add     a,16
        add     a,a
        push    hl
        ld      hl,copy_backward_block
        add     a,l
        ld      l,a
        jr      nc,copy_backward_go
        inc     h
copy_backward_go:
        ex      (sp),hl
        ret
copy_backward_block:
        ldd
        ldd
        ldd
        ldd
        ldd
        ldd
        ldd
        ldd
        ldd
        ldd
        ldd
        ldd
        ldd
        ldd
        ldd
        ldd
        jp      pe,copy_backward_block
        ret

; Remove BC bytes at offset HL: move the rest of the text down and shrink
; text_len.
close_gap:
        ld      (gap_size),bc
        ld      (gap_offset),hl
        add     hl,bc
        ex      de,hl
        ld      hl,(text_len)
        or      a
        sbc     hl,de
        ld      b,h
        ld      c,l
        ld      hl,text
        add     hl,de
        push    hl
        ld      hl,text
        ld      de,(gap_offset)
        add     hl,de
        ex      de,hl
        pop     hl
        call    copy_forward
close_gap_moved:
        ld      hl,(text_len)
        ld      de,(gap_size)
        or      a
        sbc     hl,de
        ld      (text_len),hl
        ret

delete_to_line_end:
        jp      delete_line_tail

change_to_line_end:
        call    delete_line_tail
        ld      a,1
        ld      (mode),a
        ret

delete_line_tail:
        ld      hl,(cursor)
        ld      (word_start),hl
tail_scan:
        ld      hl,(text_len)
        ld      de,(cursor)
        or      a
        sbc     hl,de
        jr      z,tail_found
        ld      hl,text
        add     hl,de
        ld      a,(hl)
        cp      0Ah
        jr      z,tail_found
        inc     de
        ld      (cursor),de
        jr      tail_scan
tail_found:
        ld      hl,(cursor)
        ld      (word_end),hl
        ld      hl,(word_start)
        ld      (cursor),hl
        ld      hl,(word_end)
        ld      de,(word_start)
        or      a
        sbc     hl,de
        ld      (delete_count),hl
        ld      a,h
        or      l
        ret     z
        ld      hl,(word_start)
        ld      bc,(delete_count)
        call    text_delete
        ld      hl,(word_start)
        ld      (cursor),hl
        ld      a,1
        ld      (modified),a
        ret

; ---------- text changes and undo ----------
; Every change to the text goes through text_insert or text_delete, which
; log it for u. A change is one Normal-mode command, with its Insert session.
; Log record: type ('I', 'D' or 'G'), offset, length, the bytes, then the
; record length (length + 5) so that the log can be read backwards. A change
; starts with a 'G' record, its mark, and the log keeps the changes one after
; another. u applies the inverse of the records of the last change that is
; still done, from the last record to the first, and turns each record into
; its inverse; Ctrl-R applies the records of the next undone change in order,
; which turns them back. undo_cur is the end of the changes that are done and
; undo_end the end of the log: the text between them is what u has undone. A
; new change drops it. When the log is full the oldest changes are dropped.

; Insert BC bytes from DE at offset HL. The caller has checked the room.
text_insert:
        ld      a,b
        or      c
        ret     z
        push    hl
        push    bc
        push    de
        call    note_change
        pop     de
        pop     bc
        pop     hl
        push    hl
        push    bc
        push    de
        ld      a,'I'
        call    undo_record
        pop     de
        pop     bc
        pop     hl
        push    bc
        push    de
        push    hl
        call    open_gap
        pop     hl
        ld      de,text
        add     hl,de
        ex      de,hl
        pop     hl
        pop     bc
        ldir
        ret

; Delete BC bytes at offset HL.
text_delete:
        ld      a,b
        or      c
        ret     z
        push    hl
        push    bc
        ld      de,text
        add     hl,de
        ex      de,hl
        pop     bc
        pop     hl
        push    hl
        push    bc
        push    de
        call    note_change
        pop     de
        pop     bc
        pop     hl
        push    hl
        push    bc
        ld      a,'D'
        call    undo_record
        pop     bc
        pop     hl
        jp      close_gap

; Log a record: A = type, HL = offset, BC = length (not 0), DE = the bytes.
; The first record of a change starts it with a mark. A change that does not
; fit even in an empty log makes the whole log unusable, since the changes
; before it no longer match the text, and u never undoes part of a change.
undo_record:
        ld      (undo_type),a
        ld      a,(undo_logging)
        or      a
        ret     z
        ld      a,(change_open)
        or      a
        jr      nz,undo_record_append
        ld      a,1
        ld      (change_open),a
        xor     a
        ld      (undo_overflow),a
        push    hl
        push    de
        push    bc
        call    undo_begin
        pop     bc
        pop     de
        pop     hl
undo_record_append:
        ld      a,(undo_overflow)
        or      a
        ret     nz
        push    hl
        push    de
        push    bc
        ld      hl,7
        add     hl,bc
        ld      b,h
        ld      c,l
        call    undo_make_room
        pop     bc
        jr      nc,undo_record_fits
        pop     de
        pop     hl
        call    undo_clear
        ld      a,1
        ld      (undo_overflow),a
        ld      (change_open),a
        ret
undo_record_fits:
        pop     de
        pop     hl
        push    bc
        push    de
        ex      de,hl
        ld      hl,(undo_end)
        ld      a,(undo_type)
        ld      (hl),a
        inc     hl
        ld      (hl),e
        inc     hl
        ld      (hl),d
        inc     hl
        ld      (hl),c
        inc     hl
        ld      (hl),b
        inc     hl
        ex      de,hl
        pop     hl
        ldir
        ex      de,hl
        pop     bc
        push    hl
        ld      hl,5
        add     hl,bc
        ex      de,hl
        pop     hl
        ld      (hl),e
        inc     hl
        ld      (hl),d
        inc     hl
        ld      (undo_end),hl
        ld      (undo_cur),hl
        ret

; Start a change: drop what was undone and write its mark.
undo_begin:
        ld      hl,(undo_cur)
        ld      (undo_end),hl
        ld      bc,7
        call    undo_make_room
        jr      nc,undo_begin_mark
        call    undo_clear
        ld      a,1
        ld      (change_open),a
undo_begin_mark:
        ld      hl,(undo_end)
        ld      (hl),'G'
        inc     hl
        xor     a
        ld      (hl),a
        inc     hl
        ld      (hl),a
        inc     hl
        ld      (hl),a
        inc     hl
        ld      (hl),a
        inc     hl
        ld      (hl),5
        inc     hl
        ld      (hl),a
        inc     hl
        ld      (undo_end),hl
        ld      (undo_cur),hl
        ret

; Make room for BC more bytes in the log by dropping its oldest changes.
; Carry is set when only one change is left and it is not enough.
undo_make_room:
        push    bc
undo_room_check:
        pop     bc
        push    bc
        ld      hl,(undo_end)
        add     hl,bc
        ld      de,undo_buffer+UNDO_SIZE+1
        or      a
        sbc     hl,de
        jr      c,undo_room_ok
        call    undo_drop_oldest
        jr      nc,undo_room_check
        pop     bc
        scf
        ret
undo_room_ok:
        pop     bc
        or      a
        ret

; Remove the first change of the log. Carry is set when it is the only one.
undo_drop_oldest:
        ld      hl,undo_buffer+7
undo_drop_scan:
        ld      de,(undo_end)
        push    hl
        or      a
        sbc     hl,de
        pop     hl
        jr      nc,undo_drop_only
        ld      a,(hl)
        cp      'G'
        jr      z,undo_drop_found
        push    hl
        inc     hl
        inc     hl
        inc     hl
        ld      e,(hl)
        inc     hl
        ld      d,(hl)
        pop     hl
        add     hl,de
        ld      de,7
        add     hl,de
        jr      undo_drop_scan
undo_drop_found:
        ld      de,undo_buffer
        or      a
        sbc     hl,de
        push    hl
        ld      hl,(undo_end)
        ld      de,undo_buffer
        or      a
        sbc     hl,de
        pop     de
        or      a
        sbc     hl,de
        ld      b,h
        ld      c,l
        ld      hl,undo_buffer
        add     hl,de
        push    de
        ld      de,undo_buffer
        ld      a,b
        or      c
        jr      z,undo_drop_moved
        ldir
undo_drop_moved:
        pop     de
        ld      hl,(undo_end)
        or      a
        sbc     hl,de
        ld      (undo_end),hl
        ld      (undo_cur),hl
        or      a
        ret
undo_drop_only:
        scf
        ret

; Empty the log. A change that goes on starts a new one with its next record.
undo_clear:
        ld      hl,undo_buffer
        ld      (undo_end),hl
        ld      (undo_cur),hl
        xor     a
        ld      (undo_overflow),a
        ld      (change_open),a
        jp      mark_all_dirty

; u: undo the last change that is still done.
undo_change:
        ld      hl,(undo_cur)
        ld      de,undo_buffer
        or      a
        sbc     hl,de
        jr      z,undo_unavailable
        xor     a
        ld      (undo_logging),a
        ld      hl,(undo_cur)
undo_back_loop:
        dec     hl
        ld      d,(hl)
        dec     hl
        ld      e,(hl)
        or      a
        sbc     hl,de
        ld      a,(hl)
        cp      'G'
        jr      z,undo_back_done
        push    hl
        call    undo_apply_record
        pop     hl
        jr      undo_back_loop
undo_back_done:
        ld      (undo_cur),hl
        jr      undo_finished

; Ctrl-R: do again the change that u undid last.
redo_change:
        ld      hl,(undo_cur)
        ld      de,(undo_end)
        or      a
        sbc     hl,de
        jr      z,undo_unavailable
        xor     a
        ld      (undo_logging),a
        ld      hl,(undo_cur)
        ld      de,7
        add     hl,de
redo_loop:
        ld      de,(undo_end)
        push    hl
        or      a
        sbc     hl,de
        pop     hl
        jr      z,redo_done
        ld      a,(hl)
        cp      'G'
        jr      z,redo_done
        push    hl
        call    undo_apply_record
        pop     hl
        inc     hl
        inc     hl
        inc     hl
        ld      e,(hl)
        inc     hl
        ld      d,(hl)
        inc     hl
        add     hl,de
        inc     hl
        inc     hl
        jr      redo_loop
redo_done:
        ld      (undo_cur),hl
undo_finished:
        ld      a,1
        ld      (undo_logging),a
        ld      (modified),a
        ld      (view_stale),a
        ld      (dirty_all),a
        ret
undo_unavailable:
        ld      a,7
        jp      putc

; Apply the inverse of the record at HL and turn the record into it.
undo_apply_record:
        ld      (undo_rec),hl
        ld      a,(hl)
        inc     hl
        ld      e,(hl)
        inc     hl
        ld      d,(hl)
        inc     hl
        ld      c,(hl)
        inc     hl
        ld      b,(hl)
        inc     hl
        ld      (cursor),de
        cp      'I'
        jr      nz,undo_reinsert
        ex      de,hl
        call    close_gap
        ld      a,'D'
        jr      undo_flip
undo_reinsert:
        ex      de,hl
        push    bc
        push    de
        push    hl
        call    open_gap
        pop     hl
        ld      de,text
        add     hl,de
        ex      de,hl
        pop     hl
        pop     bc
        ldir
        ld      a,'I'
undo_flip:
        ld      hl,(undo_rec)
        ld      (hl),a
        ret

have_room:
        ld      hl,(text_len)
        ld      de,TEXT_SIZE
        or      a
        sbc     hl,de
        jr      c,room_yes
        ld      a,7
        call    putc
        scf
        ret
room_yes:
        or      a
        ret

backspace:
        ld      hl,(cursor)
        ld      a,h
        or      l
        ret     z
        dec     hl
        ld      (cursor),hl
        call    note_edit_at
        jp      delete_char

; x never deletes the newline, so it does nothing on an empty line.
delete_char_in_line:
        ld      hl,(cursor)
        ld      de,text
        add     hl,de
        ld      a,(hl)
        cp      0Ah
        ret     z

delete_char:
        ld      hl,(cursor)
        ld      de,(text_len)
        or      a
        sbc     hl,de
        ret     nc
        ld      hl,(cursor)
        ld      bc,1
        call    text_delete
        ld      a,1
        ld      (modified),a
        ret

delete_line_prefix:
        ld      a,'d'
        ld      (expect_dd),a
        ret

yank_line_prefix:
        ld      a,1
        ld      (expect_yy),a
        ret

change_word_prefix:
        ld      a,1
        ld      (expect_cw),a
        ret

quit_prefix:
        ld      a,1
        ld      (expect_zz),a
        ret

replace_prefix:
        ld      a,1
        ld      (expect_r),a
        ret

replace_character:
        cp      20h
        ret     c
        cp      7Fh
        ret     nc
        ld      (work_byte),a
        ld      hl,(cursor)
        ld      de,(text_len)
        or      a
        sbc     hl,de
        ret     nc
        ld      hl,(cursor)
        ld      de,text
        add     hl,de
        ld      a,(hl)
        cp      0Ah
        ret     z
        ld      hl,(cursor)
        ld      bc,1
        call    text_delete
        ld      hl,(cursor)
        ld      bc,1
        ld      de,work_byte
        call    text_insert
        ld      a,1
        ld      (modified),a
        ret

join_lines:
        call    end_of_line
        ld      hl,(cursor)
        ld      de,(text_len)
        or      a
        sbc     hl,de
        ret     z
        ld      hl,(cursor)
        ld      de,text
        add     hl,de
        ld      a,(hl)
        cp      0Ah
        ret     nz
        call    delete_char
        ; An empty first line has nothing to separate from the next text.
        ld      hl,(cursor)
        ld      a,h
        or      l
        ret     z
        dec     hl
        ld      de,text
        add     hl,de
        ld      a,(hl)
        cp      0Ah
        ret     z
        ; Insert one joining space unless the next text already has spacing.
        ld      hl,(cursor)
        ld      de,(text_len)
        or      a
        sbc     hl,de
        ret     z
        ld      hl,(cursor)
        ld      de,text
        add     hl,de
        ld      a,(hl)
        cp      ' '
        ret     z
        cp      0Ah
        ret     z
        ld      a,' '
        call    insert_byte
        ret     c
        ld      hl,(cursor)
        dec     hl
        ld      (cursor),hl
        ret

; h and l stay inside the line; l may reach the newline so that a can
; append, and clamp_normal_cursor takes Normal mode back one character.
move_left:
        jp      step_back_in_line
move_right:
        ld      hl,(cursor)
        ld      de,(text_len)
        or      a
        sbc     hl,de
        ret     nc
        ld      hl,(cursor)
        ld      de,text
        add     hl,de
        ld      a,(hl)
        cp      0Ah
        ret     z
        ld      hl,(cursor)
        inc     hl
        ld      (cursor),hl
        ret

; Move one character left unless the cursor is at the start of its line.
step_back_in_line:
        ld      hl,(cursor)
        ld      a,h
        or      l
        ret     z
        dec     hl
        ld      de,text
        add     hl,de
        ld      a,(hl)
        cp      0Ah
        ret     z
        ld      hl,(cursor)
        dec     hl
        ld      (cursor),hl
        ret

; In Normal mode the cursor rests on a character, not on the newline or the
; end of the document, unless its line is empty.
clamp_normal_cursor:
        ld      a,(mode)
        or      a
        ret     nz
        ld      hl,(cursor)
        ld      de,(text_len)
        or      a
        sbc     hl,de
        jp      z,step_back_in_line
        ld      hl,(cursor)
        ld      de,text
        add     hl,de
        ld      a,(hl)
        cp      0Ah
        ret     nz
        jp      step_back_in_line

move_line_start:
        ld      bc,(cursor)
        ld      hl,text
        add     hl,bc
line_start_scan:
        ld      a,b
        or      c
        jr      z,line_start_found
        dec     hl
        dec     bc
        ld      a,(hl)
        cp      0Ah
        jr      nz,line_start_scan
        inc     hl
        inc     bc
line_start_found:
        ld      (cursor),bc
        ret

move_line_end:
        jp      end_of_line

; NG and Ngg go to line N; gg goes to line 1.
move_file_start:
        ld      hl,(repeat_times)
        dec     hl
        jp      goto_line

; G goes to the end; NG goes to line N, or to the end if there is no such line.
move_file_end:
        ld      a,(count_typed)
        or      a
        jp      z,window_end
        ld      hl,(repeat_times)
        dec     hl
        jp      goto_line

move_gg_prefix:
        ld      a,1
        ld      (expect_gg),a
        ret

move_page_down:
        ld      a,22
        ld      (page_remaining),a
page_down_loop:
        call    move_down
        ld      a,(page_remaining)
        dec     a
        ld      (page_remaining),a
        jr      nz,page_down_loop
        ret

move_page_up:
        ld      a,22
        ld      (page_remaining),a
page_up_loop:
        call    move_up
        ld      a,(page_remaining)
        dec     a
        ld      (page_remaining),a
        jr      nz,page_up_loop
        ret

; ---------- word motions ----------
; vi words: a run of letters, digits and '_', or a run of other non-blank
; characters. WORDs (W, B, E) are runs of non-blank characters. An empty
; line counts as a word for w and b.
small_word_forward:
        xor     a
        jr      word_forward_mode
big_word_forward:
        ld      a,1
word_forward_mode:
        ld      (big_words),a
        ld      hl,(cursor)
        call    next_word_start
        ld      (cursor),hl
        ret

small_word_backward:
        xor     a
        jr      word_backward_mode
big_word_backward:
        ld      a,1
word_backward_mode:
        ld      (big_words),a
        ld      hl,(cursor)
        ld      a,h
        or      l
        ret     z
        dec     hl
word_backward_blanks:
        call    char_class
        or      a
        jr      nz,word_backward_found
        ld      a,h
        or      l
        jr      z,word_backward_done
        dec     hl
        jr      word_backward_blanks
word_backward_found:
        cp      3
        jr      z,word_backward_done
        ld      b,a
word_backward_same:
        ld      a,h
        or      l
        jr      z,word_backward_done
        dec     hl
        call    char_class
        cp      b
        jr      z,word_backward_same
        inc     hl
word_backward_done:
        ld      (cursor),hl
        ret

; e and E: to the last character of this or the next word. Blanks and
; empty lines are skipped; without a next word the cursor stays.
small_word_end:
        xor     a
        jr      word_end_mode
big_word_end:
        ld      a,1
word_end_mode:
        ld      (big_words),a
        ld      hl,(cursor)
        call    at_text_end
        ret     z
        inc     hl
word_end_blanks:
        call    at_text_end
        ret     z
        call    char_class
        or      a
        jr      z,word_end_skip
        cp      3
        jr      nz,word_end_found
word_end_skip:
        inc     hl
        jr      word_end_blanks
word_end_found:
        call    current_word_end
        dec     hl
        ld      (cursor),hl
        ret

; HL = start of the next word after offset HL, or the text end.
next_word_start:
        call    at_text_end
        ret     z
        call    char_class
        or      a
        jr      z,next_word_blanks
        cp      3
        jr      z,next_word_step
        call    current_word_end
        jr      next_word_blanks
next_word_step:
        inc     hl
next_word_blanks:
        call    at_text_end
        ret     z
        call    char_class
        or      a
        ret     nz
        inc     hl
        jr      next_word_blanks

; HL = offset just after the run of characters of the class at HL.
current_word_end:
        call    char_class
        ld      b,a
current_word_next:
        inc     hl
        call    at_text_end
        ret     z
        call    char_class
        cp      b
        jr      z,current_word_next
        ret

; Z when offset HL is the text end. HL and BC are kept.
at_text_end:
        push    hl
        ld      de,(text_len)
        or      a
        sbc     hl,de
        pop     hl
        ret

; A = class of the byte at offset HL: 0 blank (space, tab or a newline that
; ends a line with text), 1 word character, 2 other non-blank, 3 an empty
; line. With big_words set, every non-blank is class 1. HL, DE, BC are kept.
char_class:
        push    hl
        push    de
        ld      d,h
        ld      e,l
        ld      hl,text
        add     hl,de
        ld      a,(hl)
        cp      0Ah
        jr      z,class_newline
        cp      ' '+1
        jr      c,class_blank
        ld      e,a
        ld      a,(big_words)
        or      a
        jr      nz,class_word
        ld      a,e
        cp      '_'
        jr      z,class_word
        cp      '0'
        jr      c,class_other
        cp      '9'+1
        jr      c,class_word
        or      20h
        cp      'a'
        jr      c,class_other
        cp      'z'+1
        jr      c,class_word
class_other:
        ld      a,2
        jr      class_done
class_word:
        ld      a,1
        jr      class_done
class_blank:
        xor     a
        jr      class_done
class_newline:
        ld      a,d
        or      e
        jr      z,class_empty
        dec     hl
        ld      a,(hl)
        cp      0Ah
        jr      z,class_empty
        xor     a
        jr      class_done
class_empty:
        ld      a,3
class_done:
        pop     de
        pop     hl
        ret

move_up:
        call    current_column
        ld      a,c
        ld      (wanted_col),a
        call    move_line_start
        ld      bc,(cursor)
        ld      a,b
        or      c
        ret     z               ; Already on the first line.
        dec     bc              ; The newline that ends the previous line.
        ld      (cursor),bc
        call    move_line_start
        ld      bc,(cursor)
        ld      hl,text
        add     hl,bc
        ld      a,(wanted_col)
        jp      advance_column

move_down:
        call    current_column
        ld      a,c
        ld      (wanted_col),a
        ld      bc,(cursor)
        ld      hl,text
        add     hl,bc
down_find_end:
        ld      a,(hl)
        cp      0Ah
        jr      z,down_found
        ld      hl,(text_len)
        or      a
        sbc     hl,bc
        jr      z,down_done
        ld      hl,text
        add     hl,bc
        inc     hl
        inc     bc
        jr      down_find_end
down_found:
        inc     hl
        inc     bc
        ld      a,(wanted_col)
        call    advance_column
down_done:
        ret

current_column:
        ld      de,(cursor)
        ld      hl,text
        add     hl,de
        ld      b,0
col_back:
        ld      a,d
        or      e
        jr      z,col_done
        dec     hl
        dec     de
        ld      a,(hl)
        cp      0Ah
        jr      z,col_done
        inc     b
        jr      col_back
col_done:
        ld      c,b
        ret

advance_column:
        ; HL and BC point at line start/offset; A is desired column.
        ld      (wanted_col),a
adv_loop:
        ld      a,(wanted_col)
        or      a
        jr      z,adv_done
        ld      hl,(text_len)
        or      a
        sbc     hl,bc
        jr      z,adv_done
        ld      hl,text
        add     hl,bc
        ld      a,(hl)
        cp      0Ah
        jr      z,adv_done
        inc     bc
        ld      a,(wanted_col)
        dec     a
        ld      (wanted_col),a
        jr      adv_loop
adv_done:
        ld      (cursor),bc
        ret

; dd deletes HL lines from the cursor's line and keeps them in the yank
; buffer, so p puts them back.
delete_line:
        call    line_range
        call    yank_range
        ld      hl,(line_end)
        ld      de,(line_start)
        or      a
        sbc     hl,de
        ld      (delete_count),hl
        ld      b,h
        ld      c,l
        ld      hl,(line_start)
        call    text_delete
        ; The last line has no newline of its own. Remove the one before it,
        ; so no empty line is left, and move to the previous line.
        ld      a,(delete_had_lf)
        or      a
        jr      nz,delete_line_cursor
        ld      de,(line_start)
        ld      a,d
        or      e
        jr      z,delete_line_cursor
        dec     de
        ld      (cursor),de
        push    de
        ex      de,hl
        call    note_edit_at
        pop     hl
        ld      bc,1
        call    text_delete
        call    move_line_start
        jr      delete_line_done
delete_line_cursor:
        ld      hl,(line_start)
        ld      (cursor),hl
delete_line_done:
        ld      a,1
        ld      (modified),a
        ret

; line_start..line_end spans HL lines from the cursor's line: line_end is
; after the last newline, or the document end when fewer lines remain.
; delete_had_lf is 1 when the span ends with a newline. The cursor stays.
line_range:
        ld      (range_lines),hl
        ld      hl,(cursor)
        ld      (saved_cursor),hl
        call    move_line_start
        ld      de,(cursor)
        ld      (line_start),de
        ld      hl,(saved_cursor)
        ld      (cursor),hl
range_scan:
        xor     a
        ld      (delete_had_lf),a
range_scan_line:
        ld      hl,(text_len)
        or      a
        sbc     hl,de
        jr      z,range_done
        ld      hl,text
        add     hl,de
        ld      a,(hl)
        inc     de
        cp      0Ah
        jr      nz,range_scan_line
        ld      a,1
        ld      (delete_had_lf),a
        ld      hl,(range_lines)
        dec     hl
        ld      (range_lines),hl
        ld      a,h
        or      l
        jr      z,range_done
        ; The empty "line" after a final newline is not taken by a count.
        ld      hl,(text_len)
        or      a
        sbc     hl,de
        jr      nz,range_scan
range_done:
        ld      (line_end),de
        ret

; Copy line_start..line_end to the yank buffer. A copy without a final
; newline gets one, so a put always adds whole lines.
yank_range:
        ld      hl,(line_end)
        ld      de,(line_start)
        or      a
        sbc     hl,de
        push    hl
        ld      bc,(yank_limit)  ; Leave room for an added newline.
        or      a
        sbc     hl,bc
        pop     hl
        jr      c,yank_range_fits
        ld      hl,0
        ld      (yank_len),hl
        ld      a,7
        jp      putc
yank_range_fits:
        ld      (yank_len),hl
        ld      b,h
        ld      c,l
        ld      hl,text
        add     hl,de
        ld      de,yank_buffer
        ld      a,b
        or      c
        jr      z,yank_add_lf           ; An empty last line yanks one newline.
        ldir
        ld      a,(delete_had_lf)
        or      a
        ret     nz
yank_add_lf:
        ex      de,hl
        ld      (hl),0Ah
        ld      hl,(yank_len)
        inc     hl
        ld      (yank_len),hl
        ret

; yy copies HL lines from the cursor's line.
yank_line:
        call    line_range
        jp      yank_range

paste_before_line:
        xor     a
        ld      (paste_separator),a
        call    move_line_start
        jr      paste_at_cursor

paste_after_line:
        xor     a
        ld      (paste_separator),a
        call    move_line_end
        ld      hl,(cursor)
        ld      de,(text_len)
        or      a
        sbc     hl,de
        jr      nz,paste_check_lf
        ld      hl,(text_len)
        ld      a,h
        or      l
        jr      z,paste_at_cursor
        dec     hl
        ld      de,text
        add     hl,de
        ld      a,(hl)
        cp      0Ah
        jr      z,paste_at_cursor
        ld      a,1
        ld      (paste_separator),a
        jr      paste_at_cursor
paste_check_lf:
        ld      hl,(cursor)
        ld      de,text
        add     hl,de
        ld      a,(hl)
        cp      0Ah
        jr      nz,paste_at_cursor
        ld      hl,(cursor)
        inc     hl
        ld      (cursor),hl
        jr      paste_at_cursor
paste_at_cursor:
        ld      hl,(yank_len)
        ld      a,h
        or      l
        ret     z
        ; After a last line without a newline, the separator ends that line,
        ; so the yank's final newline is dropped and no empty line is added.
        ld      a,(paste_separator)
        or      a
        jr      z,paste_len_ready
        push    hl
        ld      de,yank_buffer-1
        add     hl,de
        ld      a,(hl)
        pop     hl
        cp      0Ah
        jr      nz,paste_len_ready
        dec     hl
paste_len_ready:
        ld      (paste_len),hl
        ld      de,(text_len)
        add     hl,de
        ld      a,(paste_separator)
        or      a
        jr      z,paste_size_store
        inc     hl
paste_size_store:
        ld      (paste_required),hl
        ld      de,TEXT_SIZE
        or      a
        sbc     hl,de
        jr      c,paste_size_ok
        jr      z,paste_size_ok
        ld      a,7
        jp      putc
paste_size_ok:
        ld      a,(paste_separator)
        or      a
        jr      z,paste_loop_start
        ld      a,0Ah
        call    insert_byte
        xor     a
        ld      (paste_separator),a
paste_loop_start:
        ld      hl,(cursor)
        ld      (paste_start),hl
        ld      bc,(paste_len)
        ld      a,b
        or      c
        jr      z,paste_done
        ld      de,yank_buffer
        call    text_insert
        ld      a,1
        ld      (modified),a
paste_done:
        ld      hl,(paste_start)
        ld      (cursor),hl
        ret

; dw/dW delete to the start of the next word, but not past the end of the
; line. cw/cW change to the end of the current word, without the blanks
; after it; on blanks they act like dw. A count takes that many words.
; Z after word_mode_key when the last key was w (vi words) or W (WORDs).
word_mode_key:
        ld      a,(last_key)
        cp      'w'
        jr      z,word_mode_small
        cp      'W'
        ret     nz
        ld      a,1
        ld      (big_words),a
        cp      a
        ret
word_mode_small:
        xor     a
        ld      (big_words),a
        ret

delete_word:
        ld      hl,(cursor)
        ld      bc,(repeat_times)
delete_word_next:
        push    bc
        call    next_word_start
        pop     bc
        dec     bc
        ld      a,b
        or      c
        jr      nz,delete_word_next
        jr      delete_to_word_target

change_word:
        ld      hl,(cursor)
        call    at_text_end
        jr      z,change_word_insert
        call    char_class
        or      a
        jr      nz,change_word_in_word
        call    delete_word
        jr      change_word_insert
change_word_in_word:
        ld      bc,(repeat_times)
change_word_next:
        push    bc
        call    current_word_end
        pop     bc
        dec     bc
        ld      a,b
        or      c
        jr      z,change_word_target
        ; The next count starts at the next word.
change_word_skip_blanks:
        call    at_text_end
        jr      z,change_word_target
        call    char_class
        or      a
        jr      nz,change_word_next
        inc     hl
        jr      change_word_skip_blanks
change_word_target:
        call    delete_to_word_target
change_word_insert:
        ld      a,1
        ld      (mode),a
        ret

; Delete from the cursor to offset HL, stopping at the first newline.
delete_to_word_target:
        ld      (word_end),hl
        ld      hl,(cursor)
        ld      (word_start),hl
delete_word_find_lf:
        ld      de,(word_end)
        push    hl
        or      a
        sbc     hl,de
        pop     hl
        jr      nc,delete_word_range_ready
        push    hl
        ld      de,text
        add     hl,de
        ld      a,(hl)
        pop     hl
        cp      0Ah
        jr      z,delete_word_stop_at_lf
        inc     hl
        jr      delete_word_find_lf
delete_word_stop_at_lf:
        ld      (word_end),hl
delete_word_range_ready:
        ld      hl,(word_end)
        ld      de,(word_start)
        or      a
        sbc     hl,de
        ret     z
        ret     c
        ld      b,h
        ld      c,l
        ld      hl,(word_start)
        call    text_delete
        ld      hl,(word_start)
        ld      (cursor),hl
        ld      a,1
        ld      (modified),a
        ret

end_of_line:
        ld      bc,(cursor)
        ld      hl,text
        add     hl,bc
eol_loop:
        ld      a,(hl)
        cp      0Ah
        jr      z,eol_found
        ld      hl,(text_len)
        or      a
        sbc     hl,bc
        jr      z,eol_found
        ld      hl,text
        add     hl,bc
        inc     hl
        inc     bc
        jr      eol_loop
eol_found:
        ld      (cursor),bc
        ret

; ---------- colon commands ----------
ex_command:
        call    status_prompt
        call    read_key
        call    putc
        cp      'w'
        jr      z,command_write
        cp      'q'
        jr      z,command_quit
        cp      's'
        jp      z,command_substitute
        cp      '/'
        jp      z,search_command
        ret
command_write:
        call    read_key
        call    putc
        cp      'q'
        jr      z,command_write_quit
        cp      0Dh
        jp      z,do_write
        cp      ' '
        jr      z,write_filename
        ret
write_filename:
        call    read_filename_line
        jp      do_write
command_write_quit:
        call    do_write
        ret     c
        jp      quit
command_quit:
        call    read_key
        call    putc
        cp      '!'
        jp      z,quit
        ld      a,(modified)
        or      a
        jr      nz,quit_warning
        jp      quit
quit_warning:
        ld      hl,unsaved_message
        jp      puts

; :set nu / :set number shows line numbers; :set nonu / :set nonumber hides
; them. The 's' and 'e' are already read; the rest of the line is in
; set_text. Other options are ignored.
command_set:
        ld      hl,set_text
        ld      (input_ptr),hl
        xor     a
        ld      (input_len),a
        ld      (input_delim),a
        call    read_input_text
        ld      a,(input_len)
        cp      4
        ret     c
        ld      hl,set_text
        ld      a,(hl)
        cp      't'
        ret     nz
        inc     hl
        ld      a,(hl)
        cp      ' '
        ret     nz
        inc     hl
        ld      b,1             ; Show unless the option starts with "no".
        ld      a,(hl)
        cp      'n'
        jr      nz,set_option_name
        inc     hl
        ld      a,(hl)
        dec     hl
        cp      'o'
        jr      nz,set_option_name
        ld      b,0
        inc     hl
        inc     hl
set_option_name:
        ld      a,(hl)
        cp      'n'
        ret     nz
        inc     hl
        ld      a,(hl)
        cp      'u'
        ret     nz
        ld      a,b
        jp      set_line_numbers

; A = 1 shows the line-number gutter, 0 hides it and gives the text all 80
; columns.
set_line_numbers:
        ld      (show_numbers),a
        or      a
        ld      a,80
        ld      b,1
        jr      z,set_numbers_ready
        ld      a,73
        ld      b,8
set_numbers_ready:
        ld      (text_columns),a
        ld      a,b
        ld      (text_origin),a
        jp      mark_all_dirty

; Literal forward search: /pattern<Enter>
search_command:
        xor     a
        ld      (search_failed),a
        call    platform_search_prompt
        ld      hl,search_pattern
        ld      (input_ptr),hl
        xor     a
        ld      (input_len),a
        ld      (input_delim),a
        call    read_input_text
        ld      a,(input_len)
        ld      (pattern_len),a
        or      a
        ret     z
        jp      search_next_match

repeat_search:
        ld      a,(pattern_len)
        or      a
        ret     z
search_next_match:
        call    window_mark
        ld      hl,(cursor)
        inc     hl
        ld      (search_start),hl
        jp      search_in_window

; :s/old/new<Enter> replaces the first forward literal match.
command_substitute:
        xor     a
        ld      (search_failed),a
        call    read_key
        call    putc
        cp      'e'
        jp      z,command_set
        cp      '/'
        ret     nz
        ld      hl,search_pattern
        ld      (input_ptr),hl
        xor     a
        ld      (input_len),a
        ld      a,'/'
        ld      (input_delim),a
        call    read_input_text
        ld      a,(input_term)
        or      a
        ret     z
        ld      a,(input_len)
        ld      (pattern_len),a
        or      a
        ret     z
        ld      hl,replacement
        ld      (input_ptr),hl
        xor     a
        ld      (input_len),a
        ld      a,'/'
        ld      (input_delim),a
        call    read_input_text
        ld      a,(input_len)
        ld      (replacement_len),a
        xor     a
        ld      (global_replace),a
        ; The replacement may end at Enter (:s/old/new) or at the
        ; delimiter (:s/old/new/ or :s/old/new/g).
        ld      a,(input_term)
        or      a
        jr      z,substitute_flags_done
        call    read_key
        cp      'g'
        jr      nz,substitute_flags_done
        ld      a,1
        ld      (global_replace),a
        call    read_key
substitute_flags_done:
        ; vi's :s starts on the current line, even if the cursor is near
        ; the end of that line after leaving Insert mode.
        ld      hl,(cursor)
substitute_line_start_scan:
        ld      a,h
        or      l
        jr      z,substitute_line_start_found
        dec     hl
        push    hl
        ld      de,text
        add     hl,de
        ld      a,(hl)
        pop     hl
        cp      0Ah
        jr      nz,substitute_line_start_scan
        inc     hl
substitute_line_start_found:
        ld      (search_start),hl
        call    find_match
        ld      a,(match_found)
        or      a
        jr      nz,substitute_found
        ld      a,1
        ld      (search_failed),a
        ret
substitute_found:
        call    replace_match
        ld      a,(global_replace)
        or      a
        ret     z
substitute_global_loop:
        ld      hl,(cursor)
        ld      a,(replacement_len)
        ld      e,a
        ld      d,0
        add     hl,de
        ld      (search_start),hl
        call    find_match
        ld      a,(match_found)
        or      a
        ret     z
        call    replace_match
        jr      substitute_global_loop

; Read printable input to input_ptr until CR or input_delim. Keep at most 32.
read_input_text:
input_read_loop:
        call    read_key
        cp      08h
        jr      z,input_backspace
        cp      7Fh
        jr      z,input_backspace
        call    putc
        cp      0Dh
        jr      nz,input_check_delim
        xor     a
        ld      (input_term),a
        ret
input_backspace:
        ld      a,(input_len)
        or      a
        jr      z,input_read_loop
        dec     a
        ld      (input_len),a
        call    erase_echo
        jr      input_read_loop
input_check_delim:
        ld      c,a
        ld      a,(input_delim)
        or      a
        jr      z,input_append
        ld      a,c
        ld      b,a
        ld      a,(input_delim)
        cp      b
        jr      nz,input_append
        ld      a,1
        ld      (input_term),a
        ret
input_append:
        ld      a,(input_len)
        cp      32
        jr      nc,input_read_loop
        ld      e,a
        ld      d,0
        ld      hl,(input_ptr)
        add     hl,de
        ld      a,c
        ld      (hl),a
        ld      a,(input_len)
        inc     a
        ld      (input_len),a
        jr      input_read_loop

find_match:
        xor     a
        ld      (match_found),a
        ld      a,(pattern_len)
        or      a
        ret     z
        ld      hl,(text_len)
        ld      a,(pattern_len)
        ld      e,a
        ld      d,0
        or      a
        sbc     hl,de
        ret     c
        ld      (search_last),hl
        ld      hl,(search_start)
        ld      (search_pos),hl
search_candidate:
        ld      hl,(search_pos)
        ld      de,(search_last)
        or      a
        sbc     hl,de
        jr      c,search_compare
        jr      z,search_compare
        ret
search_compare:
        ld      hl,text
        ld      de,(search_pos)
        add     hl,de
        ld      de,search_pattern
        ld      a,(pattern_len)
        ld      b,a
search_compare_byte:
        ld      a,(de)
        cp      (hl)
        jr      nz,search_next_candidate
        inc     hl
        inc     de
        djnz    search_compare_byte
        ld      hl,(search_pos)
        ld      (cursor),hl
        ld      a,1
        ld      (match_found),a
        ret
search_next_candidate:
        ld      hl,(search_pos)
        inc     hl
        ld      (search_pos),hl
        jr      search_candidate

replace_match:
        ; Calculate and validate the new document size first.
        ld      hl,(text_len)
        ld      a,(pattern_len)
        ld      e,a
        ld      d,0
        or      a
        sbc     hl,de
        ld      a,(replacement_len)
        ld      e,a
        ld      d,0
        add     hl,de
        ld      (new_length),hl
        ld      de,TEXT_SIZE
        or      a
        sbc     hl,de
        jr      c,replace_size_ok
        jr      z,replace_size_ok
        ld      a,7
        jp      putc
replace_size_ok:
        ld      hl,(search_pos)
        ld      a,(pattern_len)
        ld      c,a
        ld      b,0
        call    text_delete
        ld      hl,(search_pos)
        ld      a,(replacement_len)
        ld      c,a
        ld      b,0
        ld      de,replacement
        call    text_insert
        ld      hl,(search_pos)
        ld      (cursor),hl
        ld      a,1
        ld      (modified),a
        ret

; Find the cursor's line from the previous view top (view_offset is the
; start of line view_line), and scroll only when the cursor leaves the view.
; Edits never change text before view_offset, except a Backspace or dd that
; removes the newline just before it; those set view_stale.
adjust_view:
        ld      a,(view_stale)
        or      a
        jr      nz,view_from_start
        ld      hl,(view_offset)
        ld      a,h
        or      l
        jr      z,view_anchor_ok
        ld      de,text-1
        add     hl,de
        ld      a,(hl)
        cp      0Ah
        jr      z,view_anchor_ok
view_from_start:
        xor     a
        ld      (view_stale),a
        ld      hl,0
        ld      (view_offset),hl
        ld      hl,(head_lines)
        ld      (view_line),hl
view_anchor_ok:
        ld      hl,(cursor)
        ld      de,(view_offset)
        or      a
        sbc     hl,de
        jr      c,view_cursor_above
        ld      b,h
        ld      c,l
        ld      hl,text
        add     hl,de
        call    count_newlines
        ld      hl,(view_line)
        add     hl,de
        jr      view_cursor_line_ready
view_cursor_above:
        ld      hl,(view_offset)
        ld      de,(cursor)
        or      a
        sbc     hl,de
        ld      b,h
        ld      c,l
        ld      hl,text
        add     hl,de
        call    count_newlines
        ld      hl,(view_line)
        or      a
        sbc     hl,de
view_cursor_line_ready:
        ld      (cursor_line),hl
        ld      hl,(cursor)
        call    line_start_of
        ld      (cursor_line_start),hl
        ; Keep the view unless the cursor is above or below its 23 lines.
        ld      hl,(cursor_line)
        ld      de,(view_line)
        or      a
        sbc     hl,de
        jr      c,view_top_at_cursor
        ld      de,SCREEN_LINES
        sbc     hl,de
        ret     c
        ld      hl,(cursor_line)
        ld      de,SCREEN_LINES-1
        or      a
        sbc     hl,de
        ld      (view_line),hl
        jr      view_find_offset
view_top_at_cursor:
        ld      hl,(cursor_line)
        ld      (view_line),hl
view_find_offset:
        ; Walk back (cursor_line - view_line) lines, at most 22.
        ld      hl,(cursor_line)
        ld      de,(view_line)
        or      a
        sbc     hl,de
        ld      b,l
        ld      hl,(cursor_line_start)
view_back_line:
        ld      a,b
        or      a
        jr      z,view_offset_found
        dec     hl
        push    bc
        call    line_start_of
        pop     bc
        dec     b
        jr      view_back_line
view_offset_found:
        ld      (view_offset),hl
        ret

; DE = number of newlines in the BC bytes at HL.
count_newlines:
        ld      de,0
        ld      a,b
        or      c
        ret     z
        ld      a,0Ah
count_newlines_loop:
        cpir
        ret     nz
        inc     de
        jp      pe,count_newlines_loop
        ret

; HL = offset of the start of the line that contains offset HL.
line_start_of:
        ld      a,h
        or      l
        ret     z
        ld      b,h
        ld      c,l
        ld      de,text-1
        add     hl,de
        ld      a,0Ah
        cpdr
        jr      nz,line_start_text
        inc     hl
        inc     hl
        ld      de,text
        or      a
        sbc     hl,de
        ret
line_start_text:
        ld      hl,0
        ret

; Set view_stale when an edit at offset HL is before the view top.
note_edit_at:
        ld      de,(view_offset)
        or      a
        sbc     hl,de
        ret     nc
        ld      a,1
        ld      (view_stale),a
        ret

; Leave through a warm boot: the buffers may have overwritten the CCP.
quit:
        call    window_cleanup
        call    platform_exit
        jp      0

; Read NAME.EXT or X:NAME.EXT after :w. An empty name keeps the old name
; and drive, so ":w " then Enter acts like ":w".
read_filename_line:
        ld      hl,filename
        ld      de,old_filename
        ld      bc,11
        ldir
        ld      a,(FCB)
        ld      (old_drive),a
        ld      hl,filename
        ld      b,11
        ld      a,' '
filename_blank_loop:
        ld      (hl),a
        inc     hl
        djnz    filename_blank_loop
        ld      hl,filename
        ld      b,8
filename_read_loop:
        push    hl              ; read_key goes through BDOS, which changes HL and B.
        push    bc
        call    read_key
        pop     bc
        pop     hl
        cp      08h
        jr      z,filename_backspace
        cp      7Fh
        jr      z,filename_backspace
        call    putc
        cp      0Dh
        jr      z,filename_read_done
        cp      '.'
        jr      z,filename_read_ext
        cp      ':'
        jr      z,filename_read_drive
        cp      20h
        jr      c,filename_read_loop
        cp      7Fh
        jr      nc,filename_read_loop
        cp      'a'
        jr      c,filename_char_ready
        cp      'z'+1
        jr      nc,filename_char_ready
        sub     20h
filename_char_ready:
        push    af
        ld      a,b
        or      a
        jr      z,filename_ignore_char
        pop     af
        ld      (hl),a
        inc     hl
        djnz    filename_read_loop
        jr      filename_read_loop
filename_ignore_char:
        pop     af
        jr      filename_read_loop
; Backspace takes back a character of the name or of the extension.
filename_backspace:
        ld      de,filename
        or      a
        sbc     hl,de
        add     hl,de
        jr      z,filename_read_loop
        ld      de,filename+8
        or      a
        sbc     hl,de
        add     hl,de
        jr      z,filename_read_loop
        dec     hl
        inc     b
        ld      (hl),' '
        call    erase_echo
        jr      filename_read_loop
filename_read_ext:
        ld      hl,filename+8
        ld      b,3
        jr      filename_read_loop
; "X:" right after :w selects drive X; a ':' anywhere else is ignored.
filename_read_drive:
        ld      a,b
        cp      7
        jr      nz,filename_read_loop
        ld      a,(filename)
        sub     'A'
        jr      c,filename_read_loop
        cp      16
        jr      nc,filename_read_loop
        inc     a
        ld      (FCB),a
        ld      a,' '
        ld      (filename),a
        ld      hl,filename
        ld      b,8
        jp      filename_read_loop
filename_read_done:
        ld      a,(filename)
        cp      ' '
        jr      z,filename_keep_old
        ld      a,1
        ld      (filename_set),a
        jp      make_fcb_name
filename_keep_old:
        ld      hl,old_filename
        ld      de,filename
        ld      bc,11
        ldir
        ld      a,(old_drive)
        ld      (FCB),a
        ret

do_write:
        ld      a,(filename_set)
        or      a
        jr      nz,write_named
        ld      hl,need_name_message
        call    puts
        scf
        ret
write_named:
        ld      a,(head_count)
        ld      hl,tail_count
        or      (hl)
        ld      hl,src_open
        or      (hl)
        jp      nz,write_windowed
        call    create_file
        jr      c,write_error
        call    save_begin
        ld      hl,text
        ld      bc,(text_len)
        call    save_bytes
        ret     c
        call    save_finish
        ret     c
        xor     a
        ld      (modified),a
        ret

save_begin:
        ld      hl,0
        ld      (out_recs),hl
        ld      a,0Ah
        ld      (out_last),a
        jp      save_new_record

; Write BC bytes from HL with a CR before each LF. Carry is set on an error.
save_bytes:
        ld      (write_ptr),hl
        ld      (remaining),bc
save_loop:
        ld      hl,(remaining)
        ld      a,h
        or      l
        ret     z
        dec     hl
        ld      (remaining),hl
        ld      hl,(write_ptr)
        ld      a,(hl)
        inc     hl
        ld      (write_ptr),hl
        ld      (out_last),a
        cp      0Ah
        jr      nz,save_byte
        ld      a,0Dh
        call    save_put
        jr      c,write_error
        ld      a,0Ah
save_byte:
        call    save_put
        jr      c,write_error
        jr      save_loop

; End the last line, write the last record and close the file.
save_finish:
        call    save_final_newline
        jr      c,write_error
        ; The unused tail of the last record is already 1Ah, the CP/M text end.
        ld      a,(record_pos)
        or      a
        jr      z,save_close
        call    write_record
        or      a
        jr      nz,write_error
save_close:
        ld      c,16
        ld      de,FCB
        call    BDOS
        or      a
        ret
write_error:
        ld      hl,write_error_message
        call    puts
        scf
        ret

; End the last line with CR/LF as vi does. Carry is set on a write error.
save_final_newline:
        ld      a,(out_last)
        cp      0Ah
        ret     z
        ld      a,0Dh
        call    save_put
        ret     c
        ld      a,0Ah
        jp      save_put

; Store A in the record and write the record when it is full, so a CR/LF
; pair may cross a record boundary. Carry is set on a write error.
save_put:
        ld      e,a
        ld      a,(record_pos)
        ld      c,a
        ld      b,0
        ld      hl,record
        add     hl,bc
        ld      (hl),e
        inc     a
        ld      (record_pos),a
        cp      128
        jr      z,save_put_full
        or      a
        ret
save_put_full:
        call    write_record
        or      a
        scf
        ret     nz
        call    save_new_record
        or      a
        ret

save_new_record:
        ld      hl,record
        ld      b,128
save_fill_record:
        ld      (hl),01Ah
        inc     hl
        djnz    save_fill_record
        xor     a
        ld      (record_pos),a
        ret

write_record:
        push    hl
        push    de
        push    bc
        ld      hl,(out_recs)
        inc     hl
        ld      (out_recs),hl
        ld      de,record
        ld      c,26
        call    BDOS
        ld      de,FCB
        ld      c,21
        call    BDOS
        pop     bc
        pop     de
        pop     hl
        ret

; Start the file at its first record: after a load, the FCB extent and
; record fields still point at the end of the file that was read.
create_file:
        ld      hl,FCB+12
        ld      b,36-12
create_fcb_clear:
        ld      (hl),0
        inc     hl
        djnz    create_fcb_clear
        ld      de,FCB
        ld      c,19
        call    BDOS
        ld      de,FCB
        ld      c,22
        call    BDOS
        cp      0FFh
        jr      nz,create_ok
        scf
        ret
create_ok:
        or      a
        ret

; ---------- CP/M file loading ----------
load_file:
        ld      de,FCB
        ld      c,15
        call    BDOS
        cp      0FFh
        jr      nz,load_read
        ld      hl,file_missing_message
        jp      puts
load_read:
        ld      hl,0
        ld      (text_len),hl
        ld      (src_next_rec),hl
        ld      a,1
        ld      (view_stale),a
        ld      (src_open),a
        xor     a
        ld      (src_left),a
        ld      hl,FCB
        ld      de,src_fcb
        ld      bc,36
        ldir
        ld      hl,text
        ld      bc,TEXT_SIZE-WIN_SLACK
        call    src_fill
        ld      (text_len),bc
        xor     a
        ld      (modified),a
        ld      a,(src_open)
        or      a
        jr      z,load_whole
        ; The file is larger than the buffer: the window starts at the top.
        ld      hl,0
        ld      (cursor),hl
        ret
load_whole:
        ld      de,FCB
        ld      c,16
        call    BDOS
        ld      hl,(text_len)
        ld      (cursor),hl
        ret

; ---------- command tail and FCB ----------
clear_fcb:
        ld      hl,FCB
        ld      b,36
clear_fcb_loop:
        xor     a
        ld      (hl),a
        inc     hl
        djnz    clear_fcb_loop
        ld      hl,FCB+1
        ld      b,11
fcb_space_loop:
        ld      (hl),' '
        inc     hl
        djnz    fcb_space_loop
        ret

parse_command_tail:
        ld      hl,filename
        ld      b,11
        ld      a,' '
tail_blank:
        ld      (hl),a
        inc     hl
        djnz    tail_blank
        ld      a,(DMA)
        or      a
        ret     z
        ld      (tail_remaining),a
        ld      hl,DMA+1
        ld      de,filename
        ld      a,8
        ld      (field_remaining),a
        xor     a
        ld      (filename_count),a
tail_skip_leading_space:
        ld      a,(tail_remaining)
        or      a
        ret     z
        ld      a,(hl)
        cp      ' '
        jr      z,tail_skip_one_space
        cp      9
        jr      nz,tail_drive
tail_skip_one_space:
        inc     hl
        ld      a,(tail_remaining)
        dec     a
        ld      (tail_remaining),a
        jr      tail_skip_leading_space
; A leading "X:" selects the drive in the FCB (CP/M upper-cases the tail).
tail_drive:
        ld      a,(tail_remaining)
        cp      2
        jr      c,tail_copy
        inc     hl
        ld      a,(hl)
        dec     hl
        cp      ':'
        jr      nz,tail_copy
        ld      a,(hl)
        sub     'A'
        jr      c,tail_copy
        cp      16
        jr      nc,tail_copy
        inc     a
        ld      (FCB),a
        inc     hl
        inc     hl
        ld      a,(tail_remaining)
        sub     2
        ld      (tail_remaining),a
tail_copy:
        ld      a,(tail_remaining)
        or      a
        jr      z,tail_done
        ld      a,(hl)
        cp      ' '
        jr      z,tail_done
        cp      9
        jr      z,tail_done
        cp      '.'
        jr      z,tail_dot
        cp      'a'
        jr      c,tail_store
        cp      'z'+1
        jr      nc,tail_store
        sub     20h
tail_store:
        push    af
        ld      a,(field_remaining)
        or      a
        jr      z,tail_skip_store
        pop     af
        ld      (de),a
        inc     de
        ld      a,(field_remaining)
        dec     a
        ld      (field_remaining),a
        ld      a,(filename_count)
        inc     a
        ld      (filename_count),a
        jr      tail_advance
tail_skip_store:
        pop     af
tail_advance:
        inc     hl
        ld      a,(tail_remaining)
        dec     a
        ld      (tail_remaining),a
        jr      tail_copy
tail_dot:
        ld      de,filename+8
        ld      a,3
        ld      (field_remaining),a
        inc     hl
        ld      a,(tail_remaining)
        dec     a
        ld      (tail_remaining),a
        jr      tail_copy
tail_done:
        ld      a,(filename_count)
        or      a
        jr      z,tail_name_empty
        ld      a,1
        ld      (filename_set),a
        call    copy_filename_to_fcb
tail_name_empty:
        ret

make_fcb_name:
        jp      copy_filename_to_fcb
copy_filename_to_fcb:
        ld      hl,filename
        ld      de,FCB+1
        ld      b,11
fcb_name_copy:
        ld      a,(hl)
        ld      (de),a
        inc     hl
        inc     de
        djnz    fcb_name_copy
        ret

        include "vi_tmp.asm"
        include "vi_window.asm"

; ---------- data ----------
mode:           defb 0
modified:       defb 0
filename_set:   defb 0
expect_dd:      defb 0
delete_had_lf:  defb 0
repeat_count:   defw 0
repeat_times:   defw 0
gutter_digits:  defs 5,'0'
row_next:       defw 0
row_text:       defw 0
draw_end:       defw 0
row_max:        defb 0
row_src:        defw 0
row_chars:      defw 0
dirty_from:     defw 0FFFFh
dirty_after:    defb 0
dirty_all:      defb 1
count_typed:    defb 0
expect_yy:      defb 0
expect_cw:      defb 0
expect_zz:      defb 0
expect_r:       defb 0
last_key:       defb 0
tail_remaining: defb 0
field_remaining:defb 0
filename_count: defb 0
search_failed:  defb 0
global_replace: defb 0
big_words:      defb 0
undo_type:      defb 0
undo_logging:   defb 1
change_open:    defb 0
undo_overflow:  defb 0
undo_end:       defw undo_buffer
undo_cur:       defw undo_buffer
undo_rec:       defw 0
cmd_len:        defb 0
dot_len:        defb 0
replay_left:    defb 0
replay_ptr:     defw 0
paste_separator: defb 0
expect_gg:       defb 0
page_remaining: defb 0
show_numbers:   defb 1
text_columns:   defb 73             ; Visible text columns after the gutter
text_origin:    defb 8              ; One-based screen column of text column 0
input_len:      defb 0
input_delim:    defb 0
input_term:     defb 0
pattern_len:    defb 0
replacement_len:defb 0
match_found:    defb 0
input_ptr:      defw 0
search_start:   defw 0
search_pos:     defw 0
search_last:    defw 0
new_length:     defw 0
work_byte:      defb 0
wanted_col:     defb 0
ansi_row:       defb 1
ansi_col:       defb 1
movement_only:  defb 0
old_view_line:  defw 0
drawn_view_line: defw 0
cursor_line:    defw 0
cursor_line_start: defw 0
view_stale:     defb 0
yank_limit:     defw 0
text_len:       defw 0
cursor:         defw 0
view_line:      defw 0
view_offset:    defw 0
remaining:      defw 0
write_ptr:      defw 0
line_start:     defw 0
line_end:       defw 0
delete_count:   defw 0
saved_cursor:   defw 0
yank_len:       defw 0
gap_size:       defw 0
gap_offset:     defw 0
paste_start:    defw 0
paste_len:      defw 0
range_lines:    defw 0
paste_required: defw 0
word_start:     defw 0
word_end:       defw 0
record_pos:     defb 0
filename:       defs 11,' '
old_filename:   defs 11,' '
old_drive:      defb 0
search_pattern: defs 32,0
replacement:    defs 32,0
set_text:       defs 32,0
record:         defs 128,01Ah
normal_label:   defm "NORMAL",'$'
insert_label:   defm "INSERT",'$'
modified_label: defm " [modified]",'$'
filename_label: defm "FILE: ",'$'
no_name_label:  defm "[No Name]",'$'
unsaved_message:defm 13,10,"No write since last change (use :q! to discard)",'$'
need_name_message: defm 13,10,"No file name",'$'
file_missing_message: defm 13,10,"File not found; new buffer",'$'
write_error_message: defm 13,10,"Write error",'$'
not_found_label:defm " [not found]",'$'
