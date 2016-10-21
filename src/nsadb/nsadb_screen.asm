; The screen. A frame is built in nsd_frame, 80 by 24 cells: a character, plus 80h
; for inverse video. ui_present draws the cells that differ from the shadow screen,
; so a key that changes little draws little.

        include "adv_screen.asm"

; Find the video block and clear the frame. Carry when the screen is not that of a
; Graphics CP/M system.
screen_init:
        call    adv_find_vdb
        ret     c
        ld      a,1
        ld      (adv_inverse),a
        ld      (adv_cursor_shown),a    ; The CP/M prompt left the cursor visible.
        call    adv_read_scan
        call    adv_hide_cursor
        call    screen_invalidate
        call    frame_clear
        or      a
        ret

; Every cell of the screen is unknown: the program may have written on it.
screen_invalidate:
        ld      hl,screen_shadow
        ld      (hl),0FFh
        ld      de,screen_shadow+1
        ld      bc,80*24-1
        ldir
        ret

frame_clear:
        ld      hl,nsd_frame
        ld      (hl),' '
        ld      de,nsd_frame+1
        ld      bc,80*24-1
        ldir
        ret

; Draw every cell of the frame that is not on the screen.
ui_present:
        ld      hl,nsd_frame
        ld      de,screen_shadow
        ld      bc,0                    ; B = row, C = column
present_next:
        ld      a,(de)
        cp      (hl)
        jr      z,present_same
        push    hl
        push    de
        push    bc
        ld      a,c
        ld      (adv_x),a
        ld      a,b
        ld      (adv_y),a
        ld      a,(hl)
        ld      b,a
        and     80h
        ld      (adv_style),a
        ld      a,b
        and     7Fh
        call    adv_draw_cell
        pop     bc
        pop     de
        pop     hl
present_same:
        inc     hl
        inc     de
        inc     c
        ld      a,c
        cp      80
        jr      nz,present_next
        ld      c,0
        inc     b
        ld      a,b
        cp      24
        jr      nz,present_next
        ret

; The text position in the frame: B = row, C = column.
ui_goto:
        ld      a,c
        ld      (ui_col),a
        ld      l,b
        ld      h,0
        add     hl,hl
        add     hl,hl
        add     hl,hl
        add     hl,hl
        ld      d,h
        ld      e,l
        add     hl,hl
        add     hl,hl
        add     hl,de
        ld      de,nsd_frame
        add     hl,de
        ld      e,c
        ld      d,0
        add     hl,de
        ld      (ui_ptr),hl
        ret

; Put the character A at the text position. Destroys A, B and HL.
ui_putc:
        ld      b,a
        ld      a,(ui_col)
        cp      80
        ret     nc
        inc     a
        ld      (ui_col),a
        ld      hl,(ui_ptr)
        ld      a,(ui_attr)
        or      b
        ld      (hl),a
        inc     hl
        ld      (ui_ptr),hl
        ret

; Put the text at HL, ended by a zero.
ui_puts:
        ld      a,(hl)
        or      a
        ret     z
        inc     hl
        push    hl
        call    ui_putc
        pop     hl
        jr      ui_puts

; Put blanks up to column A (not including it).
ui_pad_to:
        ld      c,a
ui_pad_next:
        ld      a,(ui_col)
        cp      c
        ret     nc
        push    bc
        ld      a,' '
        call    ui_putc
        pop     bc
        jr      ui_pad_next

ui_hex16:
        push    hl
        ld      a,h
        call    ui_hex8
        pop     hl
        ld      a,l
ui_hex8:
        push    af
        rrca
        rrca
        rrca
        rrca
        call    ui_nibble
        pop     af
ui_nibble:
        and     0Fh
        add     a,'0'
        cp      '9'+1
        jr      c,ui_digit
        add     a,'A'-'0'-10
ui_digit:
        jp      ui_putc

; A row in inverse video with the text at HL: titles and the key line. B = row.
ui_rule:
        push    hl
        ld      c,0
        call    ui_goto
        ld      a,80h
        ld      (ui_attr),a
        pop     hl
        call    ui_puts
        ld      a,80
        call    ui_pad_to
        xor     a
        ld      (ui_attr),a
        ret
