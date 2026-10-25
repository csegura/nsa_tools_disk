; TERM: a serial terminal for the NorthStar Advantage (64K Graphics CP/M 2.2). It connects the
; serial board to another computer (a Raspberry Pi that runs getty, for example): what the keys
; give goes to the line, and what comes from the line is shown on the bitmap screen.
;
;     TERM [-b 1200|2400|4800|9600|19200] [-d 5|6|7|8] [-p N|E|O] [-s 1|2] [-x] [-e] [-h]
;
; The line is 9600 baud, 8 data bits, no parity, one stop bit (the boot ROM sets two) unless -b, -d,
; -p and -s say other. The Backspace
; key gives 08h to the program (the BIOS changes the 7Fh of the key); it is sent as 7Fh, which
; is what Linux terminals have for erase, unless -h keeps 08h. -x uses the
; software flow control (XOFF when the buffer is three quarters full, XON at a quarter), -e shows
; what is typed (the other side does not echo it). The function keys do local commands (the
; table fkey_table below; its codes are those of the keys F1 to F15: DBh to E9h):
;
;   F1 baud rate   F2 send ESC   F3 send Ctrl-C   F4 clear screen   F5 echo   F6 flow
;   F10 leave the program
;
; The screen is 23 rows of 80 columns and a status line. It understands a part of the VT100/ANSI
; escape sequences that a shell sends (cursor moves, erase, inverse video); the other sequences are
; skipped, and the control characters are never given to the BIOS (some of them clear the video
; RAM). The cursor is drawn by the program as an inverse cell.
;
; What comes from the line is polled (there is no interrupt) into a buffer of 4 KB, and the line is
; polled again between the cells that are drawn: at 9600 baud a character arrives every 1 ms and the
; chip holds only one. The keyboard is read through the BDOS only when the keyboard port says that
; a key waits, because a BDOS call takes about 0.6 ms.

BDOS:           equ     0005h
TAIL:           equ     0080h
RING:           equ     8000h           ; The receive buffer, above the video window
RING_END:       equ     9000h
XOFF_AT:        equ     0C00h
XON_AT:         equ     0400h
XON:            equ     11h
XOFF:           equ     13h
TEXT_ROWS:      equ     23
STATUS_ROW:     equ     23
KEY_EVERY:      equ     16              ; keyboard polls: after this many characters

; The function keys (codes DBh to E9h) and what they do. The program takes the first row that
; has the code; a row that is not wanted can be changed: the table ends with 0.
ACT_QUIT:       equ     1
ACT_BAUD:       equ     2
ACT_ESC:        equ     3
ACT_CTRL_C:     equ     4
ACT_CLEAR:      equ     5
ACT_ECHO:       equ     6
ACT_FLOW:       equ     7

; Everything that is written is below 4000h, which video RAM replaces while a glyph is
; written, except the receive buffer, which is above it.
screen_shadow:  equ     2000h
variables:      equ     screen_shadow+80*24
stack_low:      equ     variables+512
stack_top:      equ     stack_low+256

        org     0100h
start:  ld      (orig_sp),sp
        ld      sp,stack_top
        ld      hl,variables
        ld      de,variables+1
        ld      bc,variables_end-variables-1
        ld      (hl),0
        ldir
        ld      a,3
        ld      (baud_index),a
        ld      a,'8'
        ld      (line_data),a
        ld      a,'N'
        ld      (line_parity),a
        ld      a,'1'
        ld      (line_stops),a
        ld      hl,RING
        ld      (ring_head),hl
        ld      (ring_tail),hl
        call    main
        ld      sp,(orig_sp)
        ret

        include "adv_screen.asm"

; ---------- the command line ----------
main:   call    args_init
main_word:
        call    next_word
        jr      c,main_run
        ld      a,(word)
        cp      '-'
        jr      nz,usage
        call    parse_options
        jr      nc,main_word
usage:  ld      de,msg_usage
        jp      print
main_run:
        call    sio_find
        ld      de,msg_no_board
        jp      c,print
        call    baud_apply
        call    screen_start
        ret     c
        call    clear_screen
        call    draw_status
        call    run
        jp      screen_stop

tool_option:
        cp      'X'
        jr      nz,option_echo
        ld      a,1
        ld      (flag_flow),a
        or      a
        ret
option_echo:
        cp      'E'
        jr      nz,option_baud
        ld      a,1
        ld      (flag_echo),a
        or      a
        ret
option_baud:
        cp      'H'
        jr      nz,option_rate
        ld      a,1
        ld      (flag_bs08),a
        or      a
        ret
option_rate:
        cp      'B'
        jr      nz,option_data
        ld      a,(word+2)
        or      a
        scf
        ret     nz                      ; -b has its rate in the next word
        call    next_word
        ret     c
        ld      hl,word
        call    parse_decimal
        ret     c
        ld      a,(hl)
        or      a
        scf
        ret     nz
        ld      hl,baud_rates
        ld      b,0
option_baud_next:
        ld      a,(hl)
        inc     hl
        cp      e
        jr      nz,option_baud_skip
        ld      a,(hl)
        cp      d
        jr      z,option_baud_found
option_baud_skip:
        inc     hl
        inc     b
        ld      a,b
        cp      5
        jr      c,option_baud_next
        scf
        ret
option_baud_found:
        ld      a,b
        ld      (baud_index),a
        xor     a
        ld      (word+2),a              ; the word now has the rate: the options end here
        ret

option_data:
        cp      'D'
        jr      nz,option_parity
        call    line_value
        ret     c
        cp      '5'
        ret     c
        cp      '9'
        ccf
        ret     c
        ld      (line_data),a
        ret
option_parity:
        cp      'P'
        jr      nz,option_stops
        call    line_value
        ret     c
        ld      hl,parity_letters
        ld      bc,3
        cpir
        scf
        ret     nz
        ld      (line_parity),a
        or      a
        ret
option_stops:
        cp      'S'
        scf
        ret     nz
        call    line_value
        ret     c
        cp      '1'
        jr      z,option_stops_set
        cp      '2'
        scf
        ret     nz
option_stops_set:
        ld      (line_stops),a
        or      a
        ret

parity_letters: defm    "NEO"

; The value of -d, -p and -s is a word of one character after the option; A has it, and the
; options end here (as for -b).
line_value:
        ld      a,(word+2)
        or      a
        scf
        ret     nz
        call    next_word
        ret     c
        ld      a,(word+1)
        or      a
        scf
        ret     nz
        ld      (word+2),a
        ld      a,(word)
        or      a
        ret

; The mode byte of the chip from the line variables: stop bits in bits 7-6 (01 one, 11 two),
; parity in bits 5-4 (00 none, 10 odd, 11 even), data bits in bits 3-2 (00 for 5 up to 11 for 8)
; and 10 (16 times the baud rate).
line_apply:
        ld      a,(line_data)
        sub     '5'
        add     a,a
        add     a,a
        or      02h
        ld      b,a
        ld      c,0
        ld      a,(line_parity)
        cp      'N'
        jr      z,line_apply_stops
        ld      c,10h
        cp      'O'
        jr      z,line_apply_stops
        ld      c,30h
line_apply_stops:
        ld      d,40h
        ld      a,(line_stops)
        cp      '1'
        jr      z,line_apply_mode
        ld      d,0C0h
line_apply_mode:
        ld      a,b
        or      c
        or      d
        ld      (sio_mode),a
        ret

baud_rates:     defw    1200,2400,4800,9600,19200
baud_codes:     defb    70h,78h,7Ch,7Eh,7Fh
baud_text:      defm    " 1200"," 2400"," 4800"," 9600","19200"

; Set the line to the rate of baud_index.
baud_apply:
        ld      a,(baud_index)
        ld      e,a
        ld      d,0
        ld      hl,baud_codes
        add     hl,de
        ld      a,(hl)
        ld      (baud_code),a
        call    line_apply
        jp      sio_setup

print:  ld      c,9
        jp      BDOS

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
        ld      a,(adv_scan)
        ld      (orig_scan),a
        call    adv_hide_cursor
        ld      hl,screen_shadow
        ld      (hl),0FFh
        ld      de,screen_shadow+1
        ld      bc,80*24-1
        ldir
        or      a
        ret

; The program leaves: the screen is blank and the cursor of the BIOS is at the top.
screen_stop:
        call    cursor_off
        ld      a,(orig_scan)
        call    set_scan
        ld      hl,screen_shadow
        ld      (hl),0FFh
        ld      de,screen_shadow+1
        ld      bc,80*24-1
        ldir
        ld      b,24
        ld      c,0
screen_stop_row:
        push    bc
        ld      a,c
        call    erase_row
        pop     bc
        inc     c
        djnz    screen_stop_row
        xor     a
        ld      (adv_x),a
        ld      (adv_y),a
        ld      (adv_style),a
        jp      adv_show_cursor

; The row A of the screen is drawn blank.
erase_row:
        ld      (adv_y),a
        xor     a
        ld      (adv_style),a
        ld      b,80
        ld      c,0
erase_row_cell:
        ld      a,c
        ld      (adv_x),a
        ld      a,' '
        push    bc
        call    adv_draw_cell
        call    pump
        pop     bc
        inc     c
        djnz    erase_row_cell
        ret

clear_screen:
        call    cursor_off
        ld      b,TEXT_ROWS
        ld      c,0
clear_row:
        push    bc
        ld      a,c
        call    erase_row
        pop     bc
        inc     c
        djnz    clear_row
        xor     a
        ld      (cur_x),a
        ld      (cur_y),a
        ld      (wrap_pending),a
        ret

; The status line, in inverse video, from status_template: the rate, and E and X for the
; echo and the flow control.
draw_status:
        ld      hl,status_buffer
        ld      de,status_buffer+1
        ld      bc,79
        ld      (hl),' '
        ldir
        ld      hl,status_template
        ld      de,status_buffer
        ld      bc,status_template_end-status_template
        ldir
        ld      a,(baud_index)
        ld      c,a
        add     a,a
        add     a,a
        add     a,c
        ld      e,a
        ld      d,0
        ld      hl,baud_text
        add     hl,de
        ld      de,status_buffer+6
        ld      bc,5
        ldir
        ld      a,(line_data)
        ld      (status_buffer+12),a
        ld      a,(line_parity)
        ld      (status_buffer+13),a
        ld      a,(line_stops)
        ld      (status_buffer+14),a
        ld      a,(flag_echo)
        or      a
        jr      z,status_flow
        ld      a,'E'
        ld      (status_buffer+15),a
        ld      a,(lost)
        or      a
        jr      z,status_flow
        ld      a,'L'
        ld      (status_buffer+17),a
status_flow:
        ld      a,(flag_flow)
        or      a
        jr      z,status_draw
        ld      a,'X'
        ld      (status_buffer+16),a
status_draw:
        ld      a,STATUS_ROW
        ld      (adv_y),a
        ld      a,80h
        ld      (adv_style),a
        ld      hl,status_buffer
        ld      b,80
        ld      c,0
status_cell:
        ld      a,c
        ld      (adv_x),a
        ld      a,(hl)
        inc     hl
        push    hl
        push    bc
        call    adv_draw_cell
        call    pump
        pop     bc
        pop     hl
        inc     c
        djnz    status_cell
        xor     a
        ld      (adv_style),a
        ret

status_template:
        defm    " TERM xxxxx 8N1   F1 Baud  F2 ESC  F3 ^C  F4 Clear  F5 Echo  F6 Flow  F10 Quit"
status_template_end:

; ---------- the cursor ----------
; The cursor is the cell at (cur_x, cur_y) in the other weight. The shadow screen has what is
; drawn, so cursor_off has to be called before anything reads the shadow or draws.
cursor_off:
        ld      a,(cursor_drawn)
        or      a
        ret     z
        xor     a
        ld      (cursor_drawn),a
        ld      a,(cursor_at_x)
        ld      (adv_x),a
        ld      a,(cursor_at_y)
        ld      (adv_y),a
        ld      a,(cursor_saved)
        jr      draw_saved
cursor_on:
        ld      a,(cursor_drawn)
        or      a
        ret     nz
        ld      a,(cur_x)
        ld      (adv_x),a
        ld      (cursor_at_x),a
        ld      a,(cur_y)
        ld      (adv_y),a
        ld      (cursor_at_y),a
        call    adv_shadow_address
        ld      a,(hl)
        ld      (cursor_saved),a
        xor     80h
        ld      b,a
        ld      a,1
        ld      (cursor_drawn),a
        ld      a,b
; Draw the shadow value A (the character, and bit 7 for the weight) at (adv_x, adv_y).
draw_saved:
        ld      b,a
        and     80h
        ld      (adv_style),a
        ld      a,b
        and     7Fh
        call    adv_draw_cell
        xor     a
        ld      (adv_style),a
        ret

; ---------- the line ----------
; Every byte that the line has is put into the buffer. All the registers are kept.
pump:
        push    af
        push    bc
        push    de
        push    hl
pump_next:
        call    sio_poll
        jr      c,pump_done
        ld      hl,(ring_head)
        ld      (hl),a
        inc     hl
        ld      a,h
        cp      RING_END/256
        jr      nz,pump_room
        ld      h,RING/256
pump_room:
        ld      de,(ring_tail)
        or      a
        sbc     hl,de
        add     hl,de
        jr      z,pump_full
        ld      (ring_head),hl
        jr      pump_next
pump_full:
        ld      hl,lost
        ld      a,(hl)
        inc     a
        jr      z,pump_next
        ld      (hl),a
        jr      pump_next
pump_done:
        pop     hl
        pop     de
        pop     bc
        pop     af
        ret

; The next byte of the buffer in A; carry when it is empty.
ring_get:
        ld      hl,(ring_tail)
        ld      de,(ring_head)
        or      a
        sbc     hl,de
        add     hl,de
        jr      nz,ring_have
        scf
        ret
ring_have:
        ld      a,(hl)
        inc     hl
        ld      b,a
        ld      a,h
        cp      RING_END/256
        jr      nz,ring_kept
        ld      h,RING/256
ring_kept:
        ld      (ring_tail),hl
        ld      a,b
        or      a
        ret

; The status line shows an L when bytes of the line were thrown away (the buffer was full).
lost_check:
        ld      a,(lost)
        ld      hl,lost_shown
        cp      (hl)
        ret     z
        ld      (hl),a
        jp      draw_status

; With -x: XOFF when the buffer is three quarters full, XON when it has a quarter.
flow_check:
        ld      a,(flag_flow)
        or      a
        ret     z
        ld      hl,(ring_head)
        ld      de,(ring_tail)
        or      a
        sbc     hl,de
        ld      a,h
        and     0Fh
        ld      h,a
        ld      de,XOFF_AT
        ld      a,(xoff_sent)
        or      a
        jr      nz,flow_resume
        or      a
        sbc     hl,de
        ret     c
        ld      a,1
        ld      (xoff_sent),a
        ld      a,XOFF
        jp      sio_tx
flow_resume:
        ld      de,XON_AT
        or      a
        sbc     hl,de
        ret     nc
        xor     a
        ld      (xoff_sent),a
        ld      a,XON
        jp      sio_tx

; ---------- the main loop ----------
run:    ld      a,KEY_EVERY
        ld      (key_tick),a
run_loop:
        call    pump
        call    flow_check
        call    lost_check
        call    ring_get
        jr      c,run_idle
        push    af
        call    cursor_off
        pop     af
        call    term_char
        ld      hl,key_tick
        dec     (hl)
        jr      nz,run_next
        ld      (hl),KEY_EVERY
        call    service_key
run_next:
        ld      a,(quit_flag)
        or      a
        jr      z,run_loop
        ret
run_idle:
        call    cursor_on
        call    service_key
        jr      run_next

; A key that waits (the keyboard port says so) is read through the BDOS and handled.
service_key:
        in      a,(0D0h)
        bit     6,a
        ret     z
        ld      e,0FFh
        ld      c,6
        call    BDOS
        or      a
        ret     z
        jp      key_handle

; The key A: a function key does its command, the cursor keys send a sequence, the
; others go to the line.
key_handle:
        ld      b,a
        cp      0DBh
        jr      c,key_other
        cp      0EAh
        jr      nc,key_other
        ld      hl,fkey_table
key_function:
        ld      a,(hl)
        or      a
        ret     z
        inc     hl
        cp      b
        jr      z,key_command
        inc     hl
        jr      key_function
key_command:
        ld      a,(hl)
        jp      do_action
key_other:
        ld      a,b
        cp      80h
        jr      nc,key_cursor
        cp      08h
        jr      nz,key_plain
        ld      a,(flag_bs08)
        or      a
        ld      a,7Fh
        jr      z,key_plain
        ld      a,08h
key_plain:
        ld      (key_byte),a
        call    sio_tx
        ld      a,(flag_echo)
        or      a
        ret     z
        call    cursor_off
        ld      a,(key_byte)
        cp      7Fh
        jr      nz,echo_char
        ld      a,08h                   ; the echo of Backspace moves the cursor back
echo_char:
        call    term_char
        ld      a,(key_byte)
        cp      0Dh
        ret     nz
        ld      a,0Ah
        jp      term_char
key_cursor:
        ld      hl,key_sequences
key_cursor_next:
        ld      a,(hl)
        or      a
        ret     z
        inc     hl
        cp      b
        jr      z,key_send
key_cursor_skip:
        ld      a,(hl)
        inc     hl
        or      a
        jr      nz,key_cursor_skip
        jr      key_cursor_next
key_send:
        ld      a,1Bh
        call    sio_tx
        ld      b,'['
        ld      a,(cursor_app)
        or      a
        jr      z,key_send_bracket
        ld      a,(hl)                  ; only the four arrows change: ESC O A to D
        cp      'A'
        jr      c,key_send_bracket
        cp      'E'
        jr      nc,key_send_bracket
        ld      b,'O'
key_send_bracket:
        ld      a,b
        call    sio_tx
key_send_next:
        ld      a,(hl)
        inc     hl
        or      a
        ret     z
        call    sio_tx
        jr      key_send_next

; The sequences that the cursor keys of the keypad send: after ESC [ .
key_sequences:
        defb    82h
        defm    "A",0
        defb    8Ah
        defm    "B",0
        defb    86h
        defm    "C",0
        defb    88h
        defm    "D",0
        defb    87h
        defm    "H",0
        defb    84h
        defm    "F",0
        defb    89h
        defm    "5~",0
        defb    83h
        defm    "6~",0
        defb    0

; The local command A.
do_action:
        cp      ACT_QUIT
        jr      nz,action_baud
        ld      (quit_flag),a
        ret
action_baud:
        cp      ACT_BAUD
        jr      nz,action_esc
        ld      a,(baud_index)
        inc     a
        cp      5
        jr      c,baud_next
        xor     a
baud_next:
        ld      (baud_index),a
        call    baud_apply
        jp      draw_status
action_esc:
        cp      ACT_ESC
        jr      nz,action_ctrl_c
        ld      a,1Bh
        jp      sio_tx
action_ctrl_c:
        cp      ACT_CTRL_C
        jr      nz,action_clear
        ld      a,3
        jp      sio_tx
action_clear:
        cp      ACT_CLEAR
        jr      nz,action_echo
        jp      clear_screen
action_echo:
        cp      ACT_ECHO
        jr      nz,action_flow
        ld      a,(flag_echo)
        xor     1
        ld      (flag_echo),a
        jp      draw_status
action_flow:
        cp      ACT_FLOW
        ret     nz
        ld      a,(flag_flow)
        xor     1
        ld      (flag_flow),a
        jr      nz,action_flow_done
        ld      a,(xoff_sent)
        or      a
        jr      z,action_flow_done
        xor     a
        ld      (xoff_sent),a
        ld      a,XON
        call    sio_tx
action_flow_done:
        jp      draw_status

fkey_table:
        defb    0DBh,ACT_BAUD           ; F1
        defb    0DCh,ACT_ESC            ; F2
        defb    0DDh,ACT_CTRL_C         ; F3
        defb    0DEh,ACT_CLEAR          ; F4
        defb    0DFh,ACT_ECHO           ; F5
        defb    0E0h,ACT_FLOW           ; F6
        defb    0E4h,ACT_QUIT           ; F10
        defb    0

; ---------- what the line sends ----------
; The byte A from the line: a character is drawn, a control is done, ESC starts a sequence.
term_char:
        ld      b,a
        ld      a,(pstate)
        or      a
        jp      nz,term_state
        ld      a,b
        cp      20h
        jr      c,term_control
        cp      7Fh
        jr      c,put_char_near
        cp      0C0h
        ret     c                       ; the bytes after the first of a UTF-8 character
        ld      a,'?'                   ; one cell for the whole character
put_char_near:
        jp      put_char
term_control:
        cp      0Dh
        jr      z,do_cr
        cp      0Ah
        jr      z,do_lf
        cp      0Bh
        jr      z,do_lf
        cp      0Ch
        jr      z,do_lf
        cp      08h
        jr      z,do_bs
        cp      09h
        jr      z,do_tab
        cp      1Bh
        ret     nz
        ld      a,1
        ld      (pstate),a
        ret

do_cr:  xor     a
        ld      (cur_x),a
        ld      (wrap_pending),a
        ret
do_bs:  xor     a
        ld      (wrap_pending),a
        ld      a,(cur_x)
        or      a
        ret     z
        dec     a
        ld      (cur_x),a
        ret
do_tab: xor     a
        ld      (wrap_pending),a
        ld      a,(cur_x)
        or      7
        inc     a
        cp      80
        jr      c,tab_set
        ld      a,79
tab_set:
        ld      (cur_x),a
        ret
do_lf:  xor     a
        ld      (wrap_pending),a
        ld      a,(cur_y)
        inc     a
        cp      TEXT_ROWS
        jr      c,lf_set
        jp      scroll_up
lf_set: ld      (cur_y),a
        ret

; A printable character A at the cursor, which moves on (a line that is full waits for the next
; character before it goes to the next row).
put_char:
        ld      c,a
        ld      a,(wrap_pending)
        or      a
        jr      z,put_draw
        push    bc
        call    do_cr
        call    do_lf
        pop     bc
put_draw:
        ld      a,(cur_x)
        ld      (adv_x),a
        ld      a,(cur_y)
        ld      (adv_y),a
        ld      a,(attr)
        ld      (adv_style),a
        ld      a,c
        call    adv_draw_cell
        call    pump
        ld      a,(cur_x)
        cp      79
        jr      nc,put_last
        inc     a
        ld      (cur_x),a
        ret
put_last:
        ld      a,1
        ld      (wrap_pending),a
        ret

; The text moves up one row. The display start moves by 10 scanlines (port 90h, and the ROM data
; block that follows it), the shadow screen moves with the picture, and only the cells of the row
; that is new (blank) and of the status line, which moved up with the picture, are drawn again.
scroll_up:
        ld      a,(adv_scan)
        add     a,10
        call    set_scan
        ld      hl,screen_shadow+80
        ld      de,screen_shadow
        ld      b,23
        call    shadow_rows_up
        ld      hl,screen_shadow+80*23
        ld      (hl),0FFh
        ld      de,screen_shadow+80*23+1
        ld      bc,79
        ldir
        ld      a,TEXT_ROWS-1
        call    erase_row
        jp      draw_status

; The text moves down one row (the cursor was on the top row): as scroll_up, the other way; the
; row that comes in at the top and the status line are drawn.
scroll_down:
        ld      a,(adv_scan)
        sub     10
        call    set_scan
        ld      hl,screen_shadow+80*23-1
        ld      de,screen_shadow+80*24-1
        ld      b,23
        call    shadow_rows_down
        ld      hl,screen_shadow
        ld      (hl),0FFh
        ld      de,screen_shadow+1
        ld      bc,79
        ldir
        ld      hl,screen_shadow+80*23
        ld      (hl),0FFh
        ld      de,screen_shadow+80*23+1
        ld      bc,79
        ldir
        xor     a
        call    erase_row
        jp      draw_status

; B rows of the shadow screen are copied one row at a time (up or down in memory), and the
; board is polled after each row: it keeps one byte, about 1 ms at 9600 baud, and one LDIR of
; all the rows (10 ms) lost the bytes that came during a scroll.
shadow_rows_up:
        push    bc
        ld      bc,80
        ldir
        call    pump
        pop     bc
        djnz    shadow_rows_up
        ret
shadow_rows_down:
        push    bc
        ld      bc,80
        lddr
        call    pump
        pop     bc
        djnz    shadow_rows_down
        ret

; The display starts at the scanline A.
set_scan:
        ld      (adv_scan),a
        ld      hl,(adv_vdb)
        ld      de,ADV_VDB_SCAN
        add     hl,de
        ld      (hl),a
        out     (ADV_VIDEO_START),a
        ret

; ---------- escape sequences ----------
; pstate: 0 text, 1 after ESC, 2 in ESC [ (the numbers go to params), 3 in ESC ] (skipped
; until BEL or ESC \), 4 skip one more character.
term_state:
        ld      a,(pstate)
        cp      2
        jp      z,state_csi
        cp      3
        jp      z,state_osc
        cp      4
        jr      z,state_skip
        ld      a,b
        cp      '['
        jr      z,esc_csi
        cp      ']'
        jr      z,esc_osc
        cp      '('
        jr      z,esc_skip
        cp      ')'
        jr      z,esc_skip
        cp      'c'
        jr      z,esc_reset
        cp      '7'
        jr      z,esc_save
        cp      '8'
        jr      z,esc_restore
        cp      'D'
        jr      z,esc_index
        cp      'E'
        jr      z,esc_next_line
        cp      'M'
        jr      z,esc_reverse
state_end:
        xor     a
        ld      (pstate),a
        ret
state_skip:
        jr      state_end
esc_skip:
        ld      a,4
        ld      (pstate),a
        ret
esc_osc:
        ld      a,3
        ld      (pstate),a
        xor     a
        ld      (osc_count),a
        ret
esc_csi:
        ld      a,2
        ld      (pstate),a
        ld      hl,params
        ld      de,params+1
        ld      bc,params_end-params-1
        ld      (hl),0
        ldir
        xor     a
        ld      (nparam),a
        ld      (private_mark),a
        ret
esc_reset:
        xor     a
        ld      (pstate),a
        ld      (attr),a
        jp      clear_screen
esc_save:
        ld      a,(cur_x)
        ld      (saved_x),a
        ld      a,(cur_y)
        ld      (saved_y),a
        jr      state_end
esc_restore:
        ld      a,(saved_x)
        ld      (cur_x),a
        ld      a,(saved_y)
        ld      (cur_y),a
        xor     a
        ld      (wrap_pending),a
        jr      state_end
esc_index:
        xor     a
        ld      (pstate),a
        jp      do_lf
esc_next_line:
        xor     a
        ld      (pstate),a
        call    do_cr
        jp      do_lf
esc_reverse:
        xor     a
        ld      (pstate),a
        ld      (wrap_pending),a
        ld      a,(cur_y)
        or      a
        jp      z,scroll_down
        dec     a
        ld      (cur_y),a
        ret

; A string that ESC ] began ends at BEL, or at ESC and one more character. It also ends after
; 255 characters, so that a lost end does not hold the screen.
state_osc:
        ld      a,b
        cp      07h
        jp      z,state_end
        cp      1Bh
        jr      z,osc_escape
        ld      hl,osc_count
        inc     (hl)
        ret     nz
        jp      state_end
osc_escape:
        ld      a,4
        ld      (pstate),a
        ret

; Inside ESC [: digits make the number, ; goes to the next, ? and > mark a private
; sequence, and a letter ends it.
state_csi:
        ld      a,b
        cp      1Bh
        jr      z,csi_restart
        cp      18h
        jp      z,state_end
        cp      1Ah
        jp      z,state_end
        cp      '0'
        jr      c,csi_not_digit
        cp      '9'+1
        jr      nc,csi_not_digit
        sub     '0'
        ld      c,a
        call    param_pointer
        ld      a,(hl)
        cp      26
        jr      nc,csi_digit_full
        add     a,a
        ld      b,a
        add     a,a
        add     a,a
        add     a,b
        add     a,c
        jr      nc,csi_digit_store
csi_digit_full:
        ld      a,255
csi_digit_store:
        ld      (hl),a
        ret
csi_not_digit:
        cp      ';'
        jr      nz,csi_not_semicolon
        ld      a,(nparam)
        cp      7
        ret     nc
        inc     a
        ld      (nparam),a
        ret
csi_not_semicolon:
        cp      '?'
        jr      z,csi_private
        cp      '>'
        jr      z,csi_private
        cp      40h
        jr      c,csi_ignore
        cp      7Fh
        jr      nc,csi_ignore
        ld      c,a
        xor     a
        ld      (pstate),a
        ld      a,(private_mark)
        or      a
        jr      nz,csi_private_final
        ld      a,c
        jp      csi_final
; ESC [ ? 1 h and ESC [ ? 1 l: the cursor keys send ESC O A (application mode) or ESC [ A.
csi_private_final:
        ld      a,(params)
        cp      1
        ret     nz
        ld      a,c
        cp      'h'
        jr      z,cursor_app_on
        cp      'l'
        ret     nz
        xor     a
        ld      (cursor_app),a
        ret
cursor_app_on:
        ld      a,1
        ld      (cursor_app),a
        ret
csi_private:
        ld      a,1
        ld      (private_mark),a
csi_ignore:
        ret

; An ESC inside the sequence starts a new one.
csi_restart:
        ld      a,1
        ld      (pstate),a
        ret

; HL = the number that is being read.
param_pointer:
        ld      a,(nparam)
        ld      e,a
        ld      d,0
        ld      hl,params
        add     hl,de
        ret

; The sequence ends with the letter A: do it. A number that was not given is 0 (and a count of
; 0 is 1).
csi_final:
        cp      'A'
        jr      z,csi_up
        cp      'B'
        jr      z,csi_down
        cp      'C'
        jr      z,csi_right
        cp      'D'
        jr      z,csi_left
        cp      'H'
        jp      z,csi_home
        cp      'f'
        jr      z,csi_home
        cp      'G'
        jr      z,csi_column
        cp      'J'
        jp      z,csi_erase_screen
        cp      'K'
        jp      z,csi_erase_line
        cp      'm'
        jp      z,csi_attribute
        ret

; The first number, or 1.
count_param:
        ld      a,(params)
        or      a
        ret     nz
        inc     a
        ret
csi_up: call    count_param
        ld      b,a
        ld      a,(cur_y)
        sub     b
        jr      nc,up_set
        xor     a
up_set: ld      (cur_y),a
        xor     a
        ld      (wrap_pending),a
        ret
csi_down:
        call    count_param
        ld      b,a
        ld      a,(cur_y)
        add     a,b
        cp      TEXT_ROWS
        jr      c,down_set
        ld      a,TEXT_ROWS-1
down_set:
        ld      (cur_y),a
        xor     a
        ld      (wrap_pending),a
        ret
csi_right:
        call    count_param
        ld      b,a
        ld      a,(cur_x)
        add     a,b
        cp      80
        jr      c,right_set
        ld      a,79
right_set:
        ld      (cur_x),a
        xor     a
        ld      (wrap_pending),a
        ret
csi_left:
        call    count_param
        ld      b,a
        ld      a,(cur_x)
        sub     b
        jr      nc,left_set
        xor     a
left_set:
        ld      (cur_x),a
        xor     a
        ld      (wrap_pending),a
        ret
csi_column:
        call    count_param
        dec     a
        cp      80
        jr      c,column_set
        ld      a,79
column_set:
        ld      (cur_x),a
        xor     a
        ld      (wrap_pending),a
        ret
csi_home:
        xor     a
        ld      (wrap_pending),a
        ld      a,(params)
        or      a
        jr      z,home_row
        dec     a
home_row:
        cp      TEXT_ROWS
        jr      c,home_row_set
        ld      a,TEXT_ROWS-1
home_row_set:
        ld      (cur_y),a
        ld      a,(params+1)
        or      a
        jr      z,home_column
        dec     a
home_column:
        cp      80
        jr      c,home_column_set
        ld      a,79
home_column_set:
        ld      (cur_x),a
        ret

; ESC [ K: 0 from the cursor to the end of the row, 1 from the start to the cursor, 2 the row.
csi_erase_line:
        ld      a,(cur_y)
        ld      (adv_y),a
        ld      a,(params)
        ld      b,0
        ld      c,79
        cp      1
        jr      z,erase_start
        cp      2
        jr      z,erase_span
        ld      a,(cur_x)
        ld      b,a
        jr      erase_span
erase_start:
        ld      a,(cur_x)
        ld      c,a
erase_span:
        jp      erase_cells

; Blank the cells b to c of the row adv_y.
erase_cells:
        ld      a,b
        ld      (adv_x),a
        xor     a
        ld      (adv_style),a
        push    bc
        ld      a,' '
        call    adv_draw_cell
        call    pump
        pop     bc
        ld      a,b
        cp      c
        ret     nc
        inc     b
        jr      erase_cells

; ESC [ J: 0 from the cursor to the end of the screen, 1 from the start to the cursor, 2 all.
csi_erase_screen:
        ld      a,(params)
        cp      2
        jp      z,clear_screen_keep
        cp      1
        jr      z,erase_above
        call    csi_erase_line
        ld      a,(cur_y)
        inc     a
erase_below:
        cp      TEXT_ROWS
        ret     nc
        push    af
        call    erase_row
        pop     af
        inc     a
        jr      erase_below
erase_above:
        xor     a
erase_above_row:
        ld      hl,cur_y
        cp      (hl)
        jr      nc,erase_above_line
        push    af
        call    erase_row
        pop     af
        inc     a
        jr      erase_above_row
erase_above_line:
        jp      csi_erase_line
; Erase all but leave the cursor where it is.
clear_screen_keep:
        ld      a,(cur_x)
        ld      b,a
        ld      a,(cur_y)
        ld      c,a
        push    bc
        call    clear_screen
        pop     bc
        ld      a,b
        ld      (cur_x),a
        ld      a,c
        ld      (cur_y),a
        ret

; ESC [ m: 0 normal, 1 and 7 inverse (the screen has no bold), 22 and 27 normal; the other
; numbers (colours) are skipped.
csi_attribute:
        ld      hl,params
        ld      a,(nparam)
        inc     a
        ld      b,a
attribute_next:
        ld      a,(hl)
        inc     hl
        cp      38
        jr      z,attribute_colour
        cp      48
        jr      z,attribute_colour
        or      a
        jr      z,attribute_normal
        cp      1
        jr      z,attribute_inverse
        cp      7
        jr      z,attribute_inverse
        cp      22
        jr      z,attribute_normal
        cp      27
        jr      z,attribute_normal
        djnz    attribute_next
        ret
; 38 and 48 have the colour after them: ;5;n or ;2;r;g;b. They are skipped as a whole.
attribute_colour:
        dec     b
        ret     z
        ld      a,(hl)
        inc     hl
        ld      c,a
        dec     b
        ret     z
        ld      a,c
        cp      5
        ld      c,1
        jr      z,attribute_skip
        ld      c,3
attribute_skip:
        ld      a,b
        sub     c
        ret     c
        ret     z
        ld      b,a
        ld      a,c
        ld      e,a
        ld      d,0
        add     hl,de
        jr      attribute_next
attribute_normal:
        xor     a
        ld      (attr),a
        djnz    attribute_next
        ret
attribute_inverse:
        ld      a,80h
        ld      (attr),a
        djnz    attribute_next
        ret

        include "cpm_fcb.asm"
        include "cpm_args.asm"
        include "adv_sio.asm"

msg_usage:      defm "Usage: TERM [-b 1200|2400|4800|9600|19200] [-d 5|6|7|8]",13,10
                defm "            [-p N|E|O] [-s 1|2] [-x] [-e] [-h]",13,10,'$'
msg_no_board:   defm "TERM: there is no serial board (TINFO shows the boards of the machine)",13,10,'$'
msg_no_video:   defm "TERM: this is not the Advantage console",13,10,'$'
args:           defw    0

image_end:
; The variables (zero when the program starts).
flag_flow:      equ     variables
flag_echo:      equ     flag_flow+1
flag_bs08:      equ     flag_echo+1
xoff_sent:      equ     flag_bs08+1
quit_flag:      equ     xoff_sent+1
cursor_drawn:   equ     quit_flag+1
cursor_saved:   equ     cursor_drawn+1
cursor_at_x:    equ     cursor_saved+1
cursor_at_y:    equ     cursor_at_x+1
wrap_pending:   equ     cursor_at_y+1
cur_x:          equ     wrap_pending+1
cur_y:          equ     cur_x+1
saved_x:        equ     cur_y+1
saved_y:        equ     saved_x+1
attr:           equ     saved_y+1
pstate:         equ     attr+1
nparam:         equ     pstate+1
private_mark:   equ     nparam+1
osc_count:      equ     private_mark+1
key_tick:       equ     osc_count+1
lost:           equ     key_tick+1
lost_shown:     equ     lost+1
key_byte:       equ     lost_shown+1
cursor_app:     equ     key_byte+1
orig_scan:      equ     cursor_app+1
baud_index:     equ     orig_scan+1
baud_code:      equ     baud_index+1
port_data:      equ     baud_code+1
port_control:   equ     port_data+1
port_baud:      equ     port_control+1
rx_seconds:     equ     port_baud+1
line_data:      equ     rx_seconds+1
line_parity:    equ     line_data+1
line_stops:     equ     line_parity+1
params:         equ     line_stops+1
params_end:     equ     params+8
ring_head:      equ     params_end
ring_tail:      equ     ring_head+2
variables_end:  equ     ring_tail+2
orig_sp:        equ     variables_end
args_pos:       equ     orig_sp+2
work:           equ     args_pos+2
word:           equ     work+130
status_buffer:  equ     word+64
