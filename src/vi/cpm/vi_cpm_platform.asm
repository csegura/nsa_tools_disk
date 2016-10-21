; ANSI/VT100 console backend for the general CP/M build.

TEXT_SIZE:      equ     8192    ; The buffers follow the program image.
CPM_YANK_SIZE:  equ     8192
UNDO_SIZE:      equ     4096
CMD_KEYS_MAX:   equ     128             ; Keys of one command kept for '.'

platform_init:
        ld      hl,CPM_YANK_SIZE
        ld      (yank_limit),hl
        ret

platform_map_key:
        ret

platform_output_char:
        ld      e,a
        ld      c,2
        jp      BDOS

platform_begin_redraw:
        ld      hl,ansi_home
        jp      puts

; Draw the B characters at HL as one row of the screen, clear what follows
; them and start the next row.
platform_draw_row:
        ld      a,b
        or      a
        jr      z,ansi_row_end
ansi_row_loop:
        ld      a,(hl)
        call    putc
        inc     hl
        djnz    ansi_row_loop
ansi_row_end:
        call    platform_clear_eol
        jp      platform_newline

; Carry is set: the terminal is written in full, so no row is left as it is.
platform_skip_row:
        scf
        ret

platform_end_redraw:
        ret

platform_show_cursor:
        ret

; The ANSI build redraws every row, so a scroll needs no work here.
platform_scroll:
        ret

platform_bold_on:
        ld      hl,ansi_bold
        jp      puts

platform_bold_off:
        ld      hl,ansi_normal
        jp      puts

; Leave the terminal cursor on the bottom row for the CP/M prompt.
platform_exit:
        ld      a,1
        jp      platform_status_column

platform_newline:
        ld      a,13
        call    putc
        ld      a,10
        jp      putc

platform_position_cursor:
        ld      hl,ansi_position
        call    puts
        ld      a,(ansi_row)
        call    print_decimal
        ld      a,';'
        call    putc
        ld      a,(ansi_col)
        call    print_decimal
        ld      a,'H'
        jp      putc

platform_clear_screen:
        ret

platform_clear_eol:
        push    hl
        ld      hl,ansi_clear_eol
        call    puts
        pop     hl
        ret

platform_status_start:
        ld      hl,status_line
        jp      puts

; A = one-based column on the status row.
platform_status_column:
        push    af
        ld      hl,status_row_position
        call    puts
        pop     af
        call    print_decimal
        ld      a,'H'
        jp      putc

platform_search_prompt:
        ld      hl,search_prompt
        jp      puts

ansi_home:      defm 27,"[H",'$'
ansi_bold:      defm 27,"[1m",'$'
ansi_normal:    defm 27,"[0m",'$'
ansi_clear_eol: defm 27,"[K",'$'
ansi_position:  defm 27,"[",'$'
status_line:    defm 27,"[24;1H",27,"[K",'$'
status_row_position: defm 27,"[24;",'$'
search_prompt:  defm 27,"[24;1H",27,"[K",'/', '$'
